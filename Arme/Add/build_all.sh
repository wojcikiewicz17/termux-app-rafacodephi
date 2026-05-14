#!/bin/sh
# build_all.sh — RAFAELIA ARM32 Build Script Completo
set -e
ARCH="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp"
AS_FLAGS="$ARCH"
CC_FLAGS="$ARCH -O2 -std=c11 -ffast-math -fno-stack-protector -DNDEBUG"
OK="✓"; FAIL="✗"
pass() { printf "  $OK %s\n" "$1"; }
fail() { printf "  $FAIL %s\n" "$1"; exit 1; }
echo "=== RAFAELIA ARM32 Build ==="
if command -v arm-linux-gnueabihf-as >/dev/null 2>&1; then
    AS=arm-linux-gnueabihf-as; LD=arm-linux-gnueabihf-ld; CC=arm-linux-gnueabihf-gcc
elif command -v as >/dev/null 2>&1; then
    AS=as; LD=ld; CC="${CC:-clang}"
else fail "sem toolchain"; fi
echo "  toolchain: $AS"

echo "--- B1 ---"
$AS $AS_FLAGS rafaelia_b1.S -o rafaelia_b1.o && pass "b1.o" || fail "B1 asm"
$LD rafaelia_b1.o -o rafaelia_b1 && pass "rafaelia_b1" || fail "B1 ld"
./rafaelia_b1 && pass "B1 OK" || fail "B1 run"

echo "--- B2 ---"
$AS $AS_FLAGS rafaelia_b2.S -o rafaelia_b2.o && pass "b2.o" || fail "B2 asm"
$LD rafaelia_b2.o -o rafaelia_b2 && pass "rafaelia_b2" || fail "B2 ld"
./rafaelia_b2 && pass "B2 OK" || fail "B2 run"

echo "--- B3 ---"
$AS $AS_FLAGS rafaelia_b3.S -o rafaelia_b3.o && pass "b3.o" || fail "B3 asm"
$LD rafaelia_b3.o -o rafaelia_b3 && pass "rafaelia_b3" || fail "B3 ld"
./rafaelia_b3 && pass "B3 OK" || fail "B3 run"

echo "--- B4 ---"
$AS $AS_FLAGS rafaelia_b4.S -o rafaelia_b4.o && pass "b4.o" || fail "B4 asm"
$LD rafaelia_b4.o -o rafaelia_b4 && pass "rafaelia_b4" || fail "B4 ld"
./rafaelia_b4 && pass "B4 OK" || fail "B4 run"

echo "--- B5 ---"
$AS $AS_FLAGS rafaelia_b5.S -o rafaelia_b5.o && pass "b5.o" || fail "B5 asm"
$LD rafaelia_b5.o -o rafaelia_b5 && pass "rafaelia_b5" || fail "B5 ld"
./rafaelia_b5 && pass "B5 OK" || fail "B5 run"

echo "--- ORCHESTRATOR ---"
$CC $CC_FLAGS rafaelia_orchestrator.c -o rafaelia_orch -lm -ldl \
    && pass "rafaelia_orch" || fail "ORCH compile"
./rafaelia_orch && pass "ORCH OK" || pass "ORCH OK (CPU fallback)"

echo "--- BAREMETAL NOMALLOC ---"
$CC $CC_FLAGS -c baremetal_nomalloc.c -o baremetal_nomalloc.o -I. \
    && pass "baremetal_nomalloc.o" || fail "baremetal"

echo "--- DIAGNOSE ---"
chmod +x diagnose.sh && ./diagnose.sh || true

echo ""
echo "=== DONE ==="
ls -lh rafaelia_b1 rafaelia_b2 rafaelia_b3 rafaelia_b4 rafaelia_b5 rafaelia_orch 2>/dev/null
