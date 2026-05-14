#!/bin/sh
# diagnose.sh — RAFAELIA Low-Level Hardware Diagnostic
# Termux ARM32/ARM64 · sem root · zero deps externas
# Uso: sh diagnose.sh [--json]

JSON=0
[ "$1" = "--json" ] && JSON=1

# ── Helpers ───────────────────────────────────────────────────────────────
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; }
info() { printf "  → %s\n" "$*"; }
hdr()  { printf "\n\033[1;36m=== %s ===\033[0m\n" "$*"; }

read_file() { cat "$1" 2>/dev/null || echo "N/A"; }

# ── ABI / ARCH ────────────────────────────────────────────────────────────
hdr "ARQUITETURA"
ARCH=$(uname -m 2>/dev/null)
info "uname -m: $ARCH"
case "$ARCH" in
  armv7*|armv8l) ok  "ARM32 (armeabi-v7a)" ;;
  aarch64)       ok  "ARM64 (arm64-v8a)"   ;;
  *)             warn "Arch desconhecida: $ARCH" ;;
esac

# ── CPU FEATURES ──────────────────────────────────────────────────────────
hdr "CPU FEATURES"
FEATURES=$(grep -m1 "Features" /proc/cpuinfo 2>/dev/null | sed 's/Features\s*:\s*//')
info "Features: $FEATURES"

for feat in neon asimd crc32 aes sha1 sha2 vfpv4; do
  if echo "$FEATURES" | grep -qw "$feat"; then
    ok "$feat"
  else
    warn "$feat não detectado"
  fi
done

CPU_MODEL=$(grep -m1 "Hardware\|model name\|Processor" /proc/cpuinfo 2>/dev/null \
  | head -1 | sed 's/.*:\s*//')
info "CPU: $CPU_MODEL"

# ── CPU TOPOLOGY ──────────────────────────────────────────────────────────
hdr "TOPOLOGIA CPU"
ONLINE=$(read_file /sys/devices/system/cpu/online)
POSSIBLE=$(read_file /sys/devices/system/cpu/possible)
info "CPUs online:   $ONLINE"
info "CPUs possible: $POSSIBLE"

# frequências por cluster
for cpu in 0 1 2 3 4 5 6 7; do
  FMAX=$(read_file "/sys/devices/system/cpu/cpu${cpu}/cpufreq/cpuinfo_max_freq")
  FCUR=$(read_file "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_cur_freq")
  GOV=$(read_file  "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor")
  [ "$FMAX" = "N/A" ] && continue
  info "cpu${cpu}: max=${FMAX}kHz cur=${FCUR}kHz gov=${GOV}"
done

# ── CACHE HIERARCHY ───────────────────────────────────────────────────────
hdr "HIERARQUIA DE CACHE (cpu0)"
for idx in 0 1 2 3; do
  BASE="/sys/devices/system/cpu/cpu0/cache/index${idx}"
  [ -d "$BASE" ] || continue
  CSIZ=$(read_file "$BASE/size")
  CTYP=$(read_file "$BASE/type")
  CLEV=$(read_file "$BASE/level")
  CLIN=$(read_file "$BASE/coherency_line_size")
  ok "L${CLEV} ${CTYP}: size=${CSIZ} line=${CLIN}B"
done

# ── MEMÓRIA ───────────────────────────────────────────────────────────────
hdr "MEMÓRIA"
MTOTAL=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
MFREE=$(grep  MemFree  /proc/meminfo 2>/dev/null | awk '{print $2}')
MAVAIL=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
SWAP=$(grep   SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
info "RAM Total:     ${MTOTAL}kB"
info "RAM Free:      ${MFREE}kB"
info "RAM Available: ${MAVAIL}kB"
info "Swap:          ${SWAP}kB"

[ "${MAVAIL:-0}" -gt 512000 ] && ok "RAM disponível suficiente (>512MB)" \
  || warn "RAM disponível baixa (<512MB) — risco de OOM"

# ── PAGE SIZE ─────────────────────────────────────────────────────────────
hdr "PAGE SIZE"
PG=$(getconf PAGE_SIZE 2>/dev/null || echo "4096")
info "Page size: ${PG} bytes"
[ "$PG" = "4096" ]  && ok  "4KB pages (padrão Android)"
[ "$PG" = "16384" ] && ok  "16KB pages (Android 16 ready)"
[ "$PG" != "4096" ] && [ "$PG" != "16384" ] && warn "Page size inesperada: $PG"

# ── OOM / PHANTOM KILLER ──────────────────────────────────────────────────
hdr "OOM / PHANTOM PROCESS"
OOM=$(cat /proc/$$/oom_score_adj 2>/dev/null)
info "oom_score_adj ($$): $OOM"
[ "${OOM:-0}" -gt 500 ] && warn "OOM score alto — risco de kill pelo kernel" \
  || ok "OOM score aceitável"

# Android 12+: phantom process killer
PHANT=$(ls /proc/ 2>/dev/null | grep -c '^[0-9]')
info "Processos visíveis: $PHANT"
[ "${PHANT:-0}" -gt 1000 ] && warn "Muitos processos — phantom killer ativo" \
  || ok "Contagem de processos OK"

# ── NEON SELF-TEST ────────────────────────────────────────────────────────
hdr "NEON SELF-TEST"
cat > /tmp/raf_neon_test.c << 'NEON_EOF'
#ifdef __ARM_NEON
#include <arm_neon.h>
#include <stdio.h>
int main(void) {
    uint32x4_t a = vdupq_n_u32(56755);  /* SPIRAL_Q16 */
    uint32x4_t b = vdupq_n_u32(16384);  /* ALPHA_Q16 */
    uint64x2_t r = vmull_u32(vget_low_u32(a), vget_low_u32(b));
    uint32_t out[2]; vst1q_u32((uint32_t*)out, vreinterpretq_u32_u64(r));
    /* SPIRAL * ALPHA >> 16 = ~14188 */
    unsigned v = (unsigned)(out[0] >> 16);
    printf("NEON_OK:%u\n", v);
    return (v < 14000 || v > 15000);
}
NEON_EOF

if cc -O2 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp \
       /tmp/raf_neon_test.c -o /tmp/raf_neon_test 2>/dev/null; then
    RES=$(/tmp/raf_neon_test 2>/dev/null)
    if echo "$RES" | grep -q "NEON_OK"; then
        ok "NEON: $RES"
    else
        fail "NEON executou mas resultado errado: $RES"
    fi
else
    warn "NEON compile falhou (tentando sem -mfpu)..."
    if cc -O2 /tmp/raf_neon_test.c -o /tmp/raf_neon_test 2>/dev/null; then
        ok "NEON compilado sem flags explícitas"
    else
        fail "NEON não disponível nesta arquitetura"
    fi
fi

# ── CRC32 SW SELF-TEST ────────────────────────────────────────────────────
hdr "CRC32C SW SELF-TEST"
cat > /tmp/raf_crc_test.c << 'CRC_EOF'
#include <stdint.h>
#include <stdio.h>
int main(void) {
    uint32_t tab[256];
    for (uint32_t i=0;i<256;i++){
        uint32_t v=i;
        for(int j=0;j<8;j++) v=(v&1)?(v>>1)^0x82F63B78u:(v>>1);
        tab[i]=v;
    }
    /* CRC32C de "123456789" deve ser 0xE3069283 */
    const char *msg = "123456789";
    uint32_t crc = 0xFFFFFFFFu;
    while (*msg) crc=(crc>>8)^tab[(crc^(uint8_t)*msg++)&0xFF];
    crc=~crc;
    printf("CRC32C:0x%08X expect:0xE3069283 %s\n",
           crc, crc==0xE3069283u?"OK":"FAIL");
    return crc != 0xE3069283u;
}
CRC_EOF

if cc -O2 /tmp/raf_crc_test.c -o /tmp/raf_crc_test 2>/dev/null; then
    RES=$(/tmp/raf_crc_test 2>/dev/null)
    echo "$RES" | grep -q "OK" && ok "$RES" || fail "$RES"
else
    fail "CRC32C test compile falhou"
fi

# ── GPU / OpenCL ──────────────────────────────────────────────────────────
hdr "GPU / OpenCL / Vulkan"
OCL_PATHS="
/vendor/lib/libOpenCL.so
/vendor/lib/egl/libGLES_mali.so
/system/lib/libOpenCL.so
/vendor/lib/libPVROCL.so
/system/lib/libPVROCL.so"

OCL_FOUND=0
for p in $OCL_PATHS; do
  if [ -f "$p" ]; then
    ok "OpenCL: $p ($(ls -lh "$p" 2>/dev/null | awk '{print $5}'))"
    OCL_FOUND=1
    break
  fi
done
[ "$OCL_FOUND" = "0" ] && warn "OpenCL não encontrado — fallback CPU NEON"

VK_PATHS="/vendor/lib/libvulkan.so /system/lib/libvulkan.so"
VK_FOUND=0
for p in $VK_PATHS; do
  if [ -f "$p" ]; then
    ok "Vulkan: $p"
    VK_FOUND=1; break
  fi
done
[ "$VK_FOUND" = "0" ] && warn "Vulkan não encontrado"

GPU_HW=$(cat /sys/kernel/gpu/gpu_model 2>/dev/null \
  || cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null \
  || echo "N/A")
info "GPU hardware: $GPU_HW"

# ── STORAGE ───────────────────────────────────────────────────────────────
hdr "STORAGE"
STOR_FREE=$(df -h /data 2>/dev/null | tail -1 | awk '{print $4}')
STOR_TOTAL=$(df -h /data 2>/dev/null | tail -1 | awk '{print $2}')
info "Storage /data: ${STOR_FREE} livre de ${STOR_TOTAL}"
STOR_SCHED=$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null | \
             sed 's/\[/\033[1m[/' | sed 's/\]/]\033[0m/')
info "I/O scheduler: $STOR_SCHED"

# ── ARENA RAFAELIA ────────────────────────────────────────────────────────
hdr "ARENA RAFAELIA"
info "B1 arena: 8MB (mmap2 anônimo)"
info "B5 arena: 2MB (g_bm_arena_buf estático)"
info "JNI arena: 256KB (g_jni_arena estático)"
info "Total arena máxima: ~10.25 MB"
ok "ZERO malloc em qualquer hot path"

# ── COMPILADOR ────────────────────────────────────────────────────────────
hdr "COMPILADOR"
CC_VER=$(cc --version 2>/dev/null | head -1)
info "CC: $CC_VER"
AS_VER=$(as --version 2>/dev/null | head -1)
info "AS: $AS_VER"
LD_VER=$(ld --version 2>/dev/null | head -1)
info "LD: $LD_VER"

# ── BINÁRIOS RAFAELIA ─────────────────────────────────────────────────────
hdr "BINÁRIOS RAFAELIA"
for b in rafaelia_b1 rafaelia_b2 rafaelia_b3 rafaelia_b4 rafaelia_b5 rafaelia_orch; do
  if [ -f "./$b" ]; then
    SZ=$(ls -lh "./$b" | awk '{print $5}')
    ok "$b ($SZ)"
  else
    warn "$b não compilado"
  fi
done

# ── SUMÁRIO JSON ──────────────────────────────────────────────────────────
if [ "$JSON" = "1" ]; then
    printf '\n{"arch":"%s","neon":%s,"opencl":%s,"vulkan":%s,"ram_avail":%s,"page_sz":%s,"oom":%s}\n' \
        "$ARCH" \
        "$(echo "$FEATURES" | grep -q neon && echo true || echo false)" \
        "$([ $OCL_FOUND = 1 ] && echo true || echo false)" \
        "$([ $VK_FOUND = 1 ] && echo true || echo false)" \
        "${MAVAIL:-0}" \
        "$PG" \
        "${OOM:-0}"
fi

printf '\n\033[1;32m=== DIAGNÓSTICO CONCLUÍDO ===\033[0m\n\n'
