#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT_DIR/reports"
REPORT_FILE="$REPORT_DIR/debug_bootstrap_test.md"
mkdir -p "$REPORT_DIR"

run_cmd() {
  local cmd="$1"
  local status="PASS"
  local output
  if ! output=$(bash -lc "$cmd" 2>&1); then
    status="FAIL"
  fi
  {
    echo "### Command"
    echo "\`\`\`bash"
    echo "$cmd"
    echo "\`\`\`"
    echo "- Status: **$status**"
    echo "- Output:"
    echo "\`\`\`text"
    echo "$output"
    echo "\`\`\`"
    echo
  } >> "$REPORT_FILE"

  [[ "$status" == "PASS" ]]
}

{
  echo "# Debug Bootstrap Local Build Report"
  echo
  echo "- Date (UTC): $(date -u +%F' '%T)"
  echo "- Repo: termux-app-rafacodephi"
  echo "- Mode: RAF_BOOTSTRAP_SOURCE=local"
  echo
  echo "## Execution"
  echo
} > "$REPORT_FILE"

run_cmd "bash scripts/setup_android_toolchain.sh" || true
run_cmd "bash scripts/verify_bootstrap_contract.sh --prepare-dev" || true
run_cmd "RAF_BOOTSTRAP_SOURCE=local ./gradlew :app:ensureBootstrapArchives --no-daemon" || true
run_cmd "RAF_BOOTSTRAP_SOURCE=local ./gradlew assembleDebug --no-daemon" || true

APK_PATH=$(find "$ROOT_DIR/app/build/outputs/apk" -type f -name '*debug*.apk' | head -n 1)
{
  echo "## APK Result"
  if [[ -n "$APK_PATH" ]]; then
    echo "- APK generated: **Yes**"
    echo "- APK path: \`$APK_PATH\`"
  else
    echo "- APK generated: **No**"
    echo "- APK path: \`N/A\`"
  fi
} >> "$REPORT_FILE"

echo "Report written to $REPORT_FILE"
