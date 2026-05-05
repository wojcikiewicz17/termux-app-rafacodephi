#!/usr/bin/env bash
set -euo pipefail
ARCH="${1:-arm64}"
API="${2:-24}"
case "$ARCH" in
  arm32) TARGET="armv7a-linux-androideabi${API}" ;;
  arm64) TARGET="aarch64-linux-android${API}" ;;
  x86) TARGET="i686-linux-android${API}" ;;
  x86_64) TARGET="x86_64-linux-android${API}" ;;
  riscv64) TARGET="riscv64-linux-android35" ;;
  armv7a-neon) TARGET="armv7a-linux-androideabi${API}" ;;
  *) echo "unsupported-arch:$ARCH"; exit 2 ;;
esac
TMP_C=$(mktemp)
echo 'int x;' > "$TMP_C"
if clang --target="$TARGET" -c "$TMP_C" -o /tmp/raf_target_test.o >/dev/null 2>&1; then
  echo "supported:$TARGET"
  exit 0
fi
echo "unsupported-target:$TARGET"
exit 1
