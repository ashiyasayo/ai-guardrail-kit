# WSL /mnt/d 上 core.fileMode=false 會吃掉新腳本的可執行位元

日期：2026-07-23

## 坑

本專案位於 WSL 的 `/mnt/d`（Windows 掛載），git 設定為 `core.fileMode=false`。
在此情況下，新增的腳本無論磁碟上是否已 `chmod +x`，git 都會以 **100644**（非可執行）
記錄進索引；`chmod +x` 之後 git 也偵測不到 mode 變化。

Layer 1 新增 `scripts/sync-claude-hook-copies` 時即中招：`scripts/sync-codex-hook-copies`
是 100755，但新腳本被 commit 成 100644，兩者 mode 不一致（以 `git ls-files -s` 才看得出）。

## 解法

用 git 索引層級指令強制標記可執行位元，再修補 commit：

```
git update-index --chmod=+x scripts/sync-claude-hook-copies
git commit --amend --no-edit        # commit 尚未 push 時才安全
```

驗證 mode 是否正確：

```
git ls-files -s scripts/sync-claude-hook-copies   # 期望開頭為 100755
```

註記：
- `--commit --amend` 僅適用於「尚未 push」的 commit；已 push 者改用新 commit 修正。
- 測試若以 `bash <script>` 呼叫（而非直接 `./<script>`），即使少了可執行位元也能通過，
  因此測試綠燈不代表 mode 正確 —— mode 需另以 `git ls-files -s` 檢查。
