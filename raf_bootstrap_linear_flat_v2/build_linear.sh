#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p build reports
: > reports/build_linear.log
CC_BIN="${CC:-cc}"
ASFLAGS="-x assembler-with-cpp -I. -Wall -Wextra -ffunction-sections -fdata-sections"
build_obj() {
  local src="$1"
  local obj="build/${src%.S}.o"
  echo "[build] $src -> $obj" | tee -a reports/build_linear.log
  if "$CC_BIN" $ASFLAGS -c "$src" -o "$obj.tmp" >> reports/build_linear.log 2>&1; then
    mv "$obj.tmp" "$obj"
    cp "$obj" "$obj.ok"
  else
    echo "[fail] $src" | tee -a reports/build_linear.log
    rm -f "$obj.tmp"
    [ -f "$obj.ok" ] && cp "$obj.ok" "$obj"
    exit 1
  fi
}
build_obj 00_raf_start_linear_panel.S
build_obj 01_raf_leaf_syscall.S
build_obj 02_raf_q16_leaf.S
build_obj 03_raf_hex_blob.S
echo "RAF_LINEAR_OBJECTS_OK" | tee -a reports/build_linear.log
