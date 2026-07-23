# Bash 訊號測試必須等待明確 ready marker

日期：2026-07-23

## 坑

以固定 `sleep 0.2` 等待子程序安裝 trap 會產生競態；在 WSL 或較慢磁碟上，訊號可能
在子程序進入測試延遲點前送達，造成退出碼或 rollback 偶發失敗。

## 解法

fake CLI 在指定操作開始延遲時建立 `delay.<operation>.<count>.ready`。測試必須輪詢
該 marker，確認父腳本已完成初始化並進入可中斷操作後，才送出 INT、TERM 或 HUP。
輪詢需有期限，且子程序提前結束時立即失敗，避免測試永久等待。
