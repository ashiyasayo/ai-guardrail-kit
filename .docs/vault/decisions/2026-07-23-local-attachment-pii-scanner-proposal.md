# 本機附件個資掃描與去識別化工具評估提案

日期：2026-07-23
狀態：評估提案，尚未進入實作，也尚未正式決定採用

## 背景

目前 Claude 與 Codex 的個資 hook 都只掃描 `UserPromptSubmit` 事件中的 `prompt`
純文字，以及寫入工具即將寫入的文字內容。現有 hook 沒有文件附件、圖片附件、MIME
type、Base64 或附件路徑等正式輸入欄位，因此無法只靠 plugin hook 保證在原生介面把
附件送給模型前完成掃描。

附件內若含身分證字號、手機、Email、地址、信用卡、學號或護照號碼，目前不會被可靠
攔截；圖片也沒有 OCR、證件、人臉、簽名或車牌辨識。

## 評估結論

附件掃描引擎本身可以實作，但若要求「未掃描附件絕對不能送給模型」，必須控制附件
選取到送出之間的上傳入口，例如專用 CLI、wrapper、受控上傳 UI 或 API gateway。
單靠目前 Claude／Codex 的 `UserPromptSubmit` hook 不足以形成強制防線。

建議先建立共用的本機掃描引擎與 `scan-and-redact` CLI；第一版屬使用者主動執行的
送模前處理工具，不宣稱能攔截原生拖放或附件按鈕。

## 建議架構

```text
使用者選擇附件
       ↓
檔案類型、大小與路徑安全驗證
       ↓
安全解析／本機 OCR
       ↓
轉成帶來源位置的標準文字區塊
       ↓
套用共用 PII 規則
       ↓
無命中：產生通過報告
有命中：產生去識別化副本
無法可靠掃描：fail closed
```

建議模組：

```text
shared/attachment_guard/
├── scanner.py
├── models.py
├── file_validation.py
├── pii_detector.py
├── redaction.py
├── report.py
├── cache.py
└── extractors/
    ├── base.py
    ├── plain_text.py
    ├── pdf.py
    ├── office.py
    └── image_ocr.py

scripts/guardrail
```

引擎應保留頁碼、段落、儲存格、投影片與 bounding box 等來源位置，不能只輸出一大段
文字，否則無法對 PDF 與圖片做可靠的實體遮罩。

## CLI 草案

```bash
guardrail scan input.pdf
guardrail scan-and-redact input.pdf
guardrail scan-and-redact input.pdf \
    --output sanitized/input.redacted.pdf \
    --report sanitized/input.report.json \
    --ocr auto \
    --fail-on-unsupported
```

輸出不得覆蓋原檔。掃描報告以 SHA-256 綁定輸出檔，文件被修改後原掃描結果立即失效；
報告只保存類型、位置、數量、遮罩後預覽或 keyed hash，不保存完整原始個資。

建議退出碼：

| Exit code | 意義 |
| --- | --- |
| `0` | 掃描完成，未發現個資 |
| `10` | 發現個資，已成功產生去識別化副本 |
| `20` | 發現個資，但無法安全去識別化 |
| `21` | 格式不支援 |
| `22` | 加密或損毀文件 |
| `23` | 超過大小、頁數或資源限制 |
| `30` | OCR／解析器失敗 |
| `40` | 輸入或路徑不安全 |

## 安全要求

- 預設使用本機解析與 OCR，原始附件不得先傳給外部 OCR 或模型。
- 以 magic bytes 驗證格式，不只相信副檔名。
- 防止符號連結逃逸、路徑穿越、Zip Bomb、超大頁面與資源耗盡。
- 加密、損毀、不支援或無法完整解析的文件一律 fail closed。
- 先寫暫存檔，再以原子方式完成輸出；失敗時清除不完整副本與 OCR 暫存資料。
- 去識別化後重新解析並再次掃描；仍命中時不得標記為安全。
- PDF 不可只疊加黑色方塊，必須移除或不可逆改寫底層文字／影像內容。
- 不記錄完整個資，稽核資料不得形成第二份敏感資料來源。

## 建議實作階段

1. 可靠 MVP：TXT、Markdown、CSV、JSON、文字型 PDF。
2. Office：DOCX、XLSX、PPTX，並掃描 properties、註解、隱藏工作表、speaker notes、
   嵌入物件與圖片。
3. 圖片與掃描 PDF：PNG、JPEG、TIFF、掃描型 PDF，以及 Office 內嵌圖片的本機 OCR。
4. 視覺型個資：證件、人臉、簽名、車牌、QR Code／條碼；此階段需要視覺模型或專用
   偵測器，不能只沿用文字 regex。

## PII 規則共用方向

目前 Claude 與 Codex 保留各自的平行 PII 實作。新增附件掃描器時不應再建立第三份規則，
建議抽出平台無關核心：

```text
shared/pii/
├── patterns.py
├── validators.py
└── masks.py
```

由 Claude hook adapter、Codex hook adapter 與 attachment scanner 共用。平台間的 hook I/O
協定仍可維持不同，但規則、驗證器與遮罩函式只保留一份審核來源。

## 尚待決定

- 第一版是否只支援掃描，或同時提供原格式去識別化。
- PDF 去識別化採內容移除、頁面重建或影像化輸出的安全與可用性取捨。
- OCR 引擎與繁體中文模型的選擇、授權、安裝大小及跨平台支援。
- 是否接受使用者主動執行 CLI，或需要受控 wrapper／上傳 UI 形成強制流程。
- 支援格式、檔案大小、頁數、OCR 時間及併發限制。
- 誤判申訴、人工覆核及例外放行的政策與稽核方式。

