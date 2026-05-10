#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CC_BIN="${CC:-cc}"
OUT="${TMPDIR:-/tmp}/raf_cross_arch_selftest.$$"
trap 'rm -f "$OUT"' EXIT

"$CC_BIN" -std=c11 -Wall -Wextra -Werror -DRAF_CROSS_ARCH_SELFTEST \
  tools/rafaelia_cross_arch/raf_cross_arch_modules.c -o "$OUT"
"$OUT"

# Optional syntax-only probes when cross compilers are available.  They are not
# required for APK builds and are deliberately skipped instead of failing when a
# host lacks exotic toolchains.
probe() {
  local compiler="$1"; shift
  if command -v "$compiler" >/dev/null 2>&1; then
    "$compiler" "$@" -fsyntax-only tools/rafaelia_cross_arch/raf_cross_arch_modules.c
    echo "probe:$compiler:ok"
  else
    echo "probe:$compiler:skip"
  fi
}

probe riscv64-linux-gnu-gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-const-variable -DRAF_FREESTANDING -march=rv32imc -mabi=ilp32
probe mips-linux-gnu-gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-const-variable -DRAF_FREESTANDING -mips32r2
probe loongarch64-linux-gnu-gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-const-variable -DRAF_FREESTANDING
probe s390x-linux-gnu-gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-const-variable -DRAF_FREESTANDING
probe powerpc-linux-gnu-gcc -std=c11 -Wall -Wextra -Werror -Wno-unused-function -Wno-unused-const-variable -DRAF_FREESTANDING
