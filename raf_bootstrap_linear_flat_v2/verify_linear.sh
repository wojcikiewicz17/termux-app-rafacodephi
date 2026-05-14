#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p reports
for f in \
  build/00_raf_start_linear_panel.o \
  build/01_raf_leaf_syscall.o \
  build/02_raf_q16_leaf.o \
  build/03_raf_hex_blob.o
do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done
{
  echo "# Verify linear bootstrap"
  echo
  echo "Objects OK."
  echo
  if command -v nm >/dev/null 2>&1; then
    nm build/*.o | grep -E "raf_start_linear_panel|raf_write_stdout_leaf|raf_q16|raf_fraf|raf_hex_blob" || true
  fi
} > reports/verify_linear.md
echo "RAF_LINEAR_VERIFY_OK"
