# Git Bash 只轉換參數、不轉換 stdin：造成 Copilot smoke test 在 Windows 長期假性通過

日期：2026-07-31

一句話摘要：Git Bash 會把 POSIX 路徑「參數」改寫成 Windows 路徑再交給原生執行檔，
但**不會**改寫經由 stdin 傳入的內容；`decomposition-gate` 的 smoke test 把 `cwd`
放在 JSON 裡經 stdin 傳給 hook，於是 Windows Python 收到無法解析的 `/tmp/...`，
造成**普遍性 deny**，而只比對 `deny` 的寬鬆斷言讓 7 個案例假性通過。

## 坑

`copilot/plugins/decomposition-gate/tests/smoke_test.sh` 在 Windows（Git Bash ＋
原生 Windows Python 3.12）上出現 16 案中 6 案 FAIL，全部是
`Invalid Copilot project root`。

根因鏈：

1. 測試以 `mktemp -d` 取得 Git Bash 的 POSIX 臨時路徑（`/tmp/tmp.XXXX`）。
2. 該路徑被寫進 JSON 的 `cwd` 欄位，**經 stdin** 交給 hook。
3. Git Bash 的路徑轉換（MSYS path mangling）只作用於傳給原生執行檔的**參數**，
   不會碰 stdin 的位元組。
4. 原生 Windows Python 收到字面的 `/tmp/tmp.XXXX`，視為當前磁碟根目錄下的
   `\tmp\tmp.XXXX`（不存在）。
5. `hook_protocol.project_root()` 的 `Path(cwd).resolve(strict=True)` 拋
   `FileNotFoundError` → 對**每一個**格式合法的事件都輸出 deny。

### 更嚴重的問題：假性通過

16 案中有 7 個「應被 deny」的斷言只比對輸出含 `"permissionDecision": "deny"`。
步驟 5 的普遍性 deny 正好滿足這個條件，所以**即使 gate 邏輯完全失效，這些斷言
照樣是綠的**。測試同時給出「6 個失敗」與「7 個假性成功」——後者比前者危險，
因為它會讓人誤以為關卡有效。

此測試從未進入根層 `tests/run_all.sh`，所以這個狀態長期無人察覺；vault 先前記載的
「smoke 16/16 通過」在此環境無法重現。

## 診斷時踩到的二次陷阱

第一次驗證假設時用的是：

```bash
d=$(mktemp -d); echo "$d"; python -c "...resolve(strict=True)..." "$d"
```

它**成功印出** Windows 路徑，看似否證了假設。但那是因為路徑是作為**參數**傳入，
Git Bash 在 Python 看到之前就轉換好了——徵兆是 CWD 在 `D:` 磁碟卻印出
`C:\Users\...\Temp\...`。

正確的驗證方式是讓路徑走 stdin，重現實際情境：

```bash
d=$(mktemp -d); echo "$d" | python -c "import pathlib,sys;p=sys.stdin.read().strip();print(repr(p));print(pathlib.Path(p).resolve(strict=True))"
# → FileNotFoundError: [WinError 2] ... '\\tmp\\tmp.XXXX'
```

**教訓：驗證「資料經某條通道傳輸後是否仍正確」時，診斷指令必須走同一條通道。**
換通道等於換掉受測條件。

## 解法

1. **`cwd` 先轉為原生路徑再放進 JSON**，並把反斜線轉義為 JSON 合法形式
   （漏掉轉義會讓 JSON 無效 → hook 回 `Invalid Copilot hook input` → 又是一種
   假性通過）：

   ```bash
   to_json_path() {
     local path="$1"
     if command -v cygpath >/dev/null 2>&1; then
       path="$(cygpath -w "$path")"
       path="${path//\\/\\\\}"
     fi
     printf '%s' "$path"
   }
   ```

   `filePath` 不需轉換——`decomposition_gate.py` 以 `path.replace("\\", "/")`
   正規化後才與 `PLAN` 比對，只有 `cwd` 需要真實可解析的原生路徑。

2. **「應被 deny」的斷言一律比對專屬原因片段**，不可只比對 `deny`。hook 輸出是
   ASCII 轉義 JSON（`ensure_ascii=True`，中文變 `\uXXXX`），故要挑各原因中的
   **ASCII 片段**：

   | 關卡 | 可辨識片段 |
   | --- | --- |
   | 拆解閘門 | `Plan gate:` |
   | 逃生口保護 | `.gate_disabled` |
   | 線路邊界 | `Invalid Copilot hook input` |
   | cwd 解析失敗 | `Invalid Copilot project root` |

   同樣的加固已套用到 `sensitive-data-guard` 的 smoke test
   （`Secret blocked`／`Personal data blocked`／`Invalid Copilot hook input`）。

3. **納入 CI**：新增 `tests/copilot_decomposition_gate_test.sh` 薄包裝，讓
   `tests/run_all.sh` 涵蓋它。缺陷長期未被發現的根本原因就是它不在 CI 裡。

修正後：`decomposition-gate` 16/16 真正通過（先前失敗的 6 案全部轉綠）；
`sensitive-data-guard` 加固後 27 項斷言全通過，且未暴露出被掩蓋的其他失敗。

## 加固斷言時另外踩到的兩個坑

2026-08-03 把同樣的加固套到 Claude／Codex 測試時，又遇到兩件事，性質與上面完全一致
（斷言看似成立，實際沒走到受測路徑）：

**一、攔截原因不一定在 JSON 裡。** Claude 的 `harness` 版 `plan_gate.py` 以
exit code 2 ＋ stderr 回饋攔截原因，**不輸出 JSON**；`integrated-harness` 版才輸出
`permissionDecisionReason`。只比對 JSON 欄位會讓 harness 那組斷言全部因為
「reason 是 None」而失敗——或反過來，若寫成「有 reason 才比對」就退化成不比對。
正確做法是兩個來源一起比對：

```python
detail = (result.reason or "") + result.stderr
assert reason_contains in detail, (reason_contains, result)
```

**二、製造「核准失效」情境時，變動後的計畫必須仍然合法。** 原本以
`plan.read_text() + "changed\n"` 模擬「計畫被改動後核准應失效」，但那行純文字落在
`## 允許修改範圍` 區段內，`parse_scopes` 先以「允許修改範圍必須使用 Markdown 清單」
攔截——**SHA-256 比對路徑從未被執行**，而只驗 `deny` 的斷言照樣是綠的。改成附加
合法的清單項目（一行 `docs/` 的反引號清單項）後，才真正驗到「拆解文件與核准版本
不一致」。

這兩項的共同教訓：**deny 只證明有東西被擋，不證明是你想測的那道關卡擋的。**
把 helper 的 reason 參數設為**必填**（而非可選），可讓漏填成為錯誤而非靜默退化。

## 適用範圍

Copilot 的 hook 都以 stdin 接收 JSON，故任何把路徑放進 hook 事件的測試都適用。

Claude 與 Codex 的測試已於 2026-08-03 完成稽核，兩個查核點結論不同：

- **POSIX 臨時路徑經 stdin：不適用。** 這些測試以 Python
  `tempfile.TemporaryDirectory()` 取得路徑，並在同一進程內以
  `subprocess.run([...], input=json.dumps(event))` 呼叫 hook，全程不經 Git Bash 的
  原生執行檔參數通道，故不構成本文的根因鏈。
- **「應被 deny」斷言只比對 `deny`：確認成立，已修復。** `claude_guardrail_test.sh`
  的 `assert_denied()` 與 `codex_guardrail_test.sh` 的 `denied()` 都只驗決策不驗原因；
  已分別為 10 處與 16 處呼叫補上原因專屬片段，`reason_contains` 改為必填參數，
  全套回歸 18/18 通過。

值得記下的是：當初把這兩點綁成一項稽核是對的。若只查路徑問題，會因為「不適用」
就收工，漏掉真正存在的斷言問題——而後者才是讓缺陷長期隱形的那一半。

## 關聯

- [[2026-07-23-vscode-copilot-hook-wiring]]（hook 佈線與 fail-open 鐵律）
- [[2026-07-31-copilot-sensitive-data-guard]]（本批次的設計決策）
- [[2026-08-03-copilot-batch-followups]]（待辦 2 即本文的 Claude／Codex 稽核，已關閉）
