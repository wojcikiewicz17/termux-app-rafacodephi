#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p build reports
CC_BIN="${CC:-cc}"
set +e
"$CC_BIN" -nostdlib -Wl,--gc-sections \
  build/00_raf_start_linear_panel.o \
  -o build/raf_linear_panel \
  > reports/link_linear.log 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "RAF_LINEAR_LINK_FAIL"
  cat reports/link_linear.log
  exit "$rc"
fi
echo "RAF_LINEAR_LINK_OK"
