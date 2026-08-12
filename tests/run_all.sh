#!/usr/bin/env bash
set -uo pipefail
# 回歸測試統一入口：預設執行 smoke profile；完整模式切換測試以 full profile 執行。
# 使用 AGK_TEST_PROFILE=full bash tests/run_all.sh 可手動執行完整回歸。
# 任一測試失敗仍會跑完其餘測試，最後以非零狀態碼結束並列出失敗清單。
# 每個測試套用 timeout 保護（預設 40 分鐘，逾時視為失敗），把「掛住」與
# 「單純慢」明確區分；codex_mode_switch_test.sh 因大量 Python 直譯器啟動，
# 在 Windows（Git Bash）上耗時甚久，屬正常慢而非掛住。
#
# 預設值選定依據（2026-07-31 於 Windows／Git Bash 實測，18 支測試全通過）：
# codex_mode_switch_test.sh 1167 秒、claude_mode_switch_test.sh 116 秒、
# codex_global_install_test.sh 64 秒，其餘皆在 20 秒內。最慢者與次慢者相差一個
# 數量級，且原本的 1200 秒上限只剩 33 秒餘裕，機器稍慢即會誤判為失敗，
# 故提高為 2400 秒（約 2 倍餘裕）。若日後仍逾時，應調查該測試為何變慢，
# 而非再次調高上限。
# smoke profile 刻意略過 claude_mode_switch_test.sh 與 codex_mode_switch_test.sh；
# 兩者仍由 full profile、CI 排程或手動 workflow 執行。
# 可用環境變數 AGK_TEST_PROFILE（smoke／full）選擇模式，並以 AGK_TEST_TIMEOUT（秒）調整上限。
cd "$(dirname "$0")"

test_profile=${AGK_TEST_PROFILE:-smoke}
case "$test_profile" in
  smoke|full)
    ;;
  *)
    printf 'FAIL: 不支援的 AGK_TEST_PROFILE：%s（應為 smoke 或 full）\n' "$test_profile" >&2
    exit 2
    ;;
esac

timeout_seconds=${AGK_TEST_TIMEOUT:-2400}
run_one() {
  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "$timeout_seconds" bash "$1"
  else
    bash "$1"
  fi
}

failures=()
for test_script in ./*_test.sh; do
  name=$(basename "$test_script")
  printf '=== %s ===\n' "$name"

  if [[ "$test_profile" == smoke ]] && [[ "$name" == claude_mode_switch_test.sh || "$name" == codex_mode_switch_test.sh ]]; then
    printf -- '--- SKIP %s (smoke profile；使用 AGK_TEST_PROFILE=full 執行)\n\n' "$name"
    continue
  fi

  start=$SECONDS
  if run_one "$test_script"; then
    printf -- '--- PASS %s (%ss)\n\n' "$name" "$((SECONDS - start))"
  else
    printf -- '--- FAIL %s (%ss)\n\n' "$name" "$((SECONDS - start))"
    failures+=("$name")
  fi
done

if (( ${#failures[@]} )); then
  printf 'FAIL: %d 個測試失敗：%s\n' "${#failures[@]}" "${failures[*]}" >&2
  exit 1
fi
printf 'PASS: 全部回歸測試通過（profile: %s）\n' "$test_profile"
