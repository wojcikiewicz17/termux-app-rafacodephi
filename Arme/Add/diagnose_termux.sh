#!/data/data/com.termux/files/usr/bin/sh
# diagnose_termux.sh — diagnóstico low-level para Termux ARM32 Android
OK="\033[32m✓\033[0m"; WARN="\033[33m⚠\033[0m"; FAIL="\033[31m✗\033[0m"
ok()  { printf "$OK %s\n" "$*"; }
warn(){ printf "$WARN %s\n" "$*"; }
fail(){ printf "$FAIL %s\n" "$*"; }
info(){ printf "  → %s\n" "$*"; }
hdr() { printf "\n\033[1;33m=== %s ===\033[0m\n" "$*"; }

hdr "TERMUX ENVIRONMENT"
info "PREFIX: ${PREFIX:-não definido}"
info "HOME: $HOME"
info "ARCH: $(uname -m)"
info "Android API: $(getprop ro.build.version.sdk 2>/dev/null || echo N/A)"
info "Device: $(getprop ro.product.model 2>/dev/null || echo N/A)"
info "Android: $(getprop ro.build.version.release 2>/dev/null || echo N/A)"

hdr "CPU"
ONLINE=$(cat /sys/devices/system/cpu/online 2>/dev/null || echo N/A)
FEATS=$(grep -m1 "Features" /proc/cpuinfo 2>/dev/null | sed 's/.*:\s*//')
MODEL=$(grep -m1 "Hardware\|model name\|Processor" /proc/cpuinfo 2>/dev/null | head -1 | sed 's/.*:\s*//')
info "Online CPUs: $ONLINE"
info "Model: $MODEL"
info "Features: $FEATS"
echo "$FEATS" | grep -qw "neon"   && ok "NEON"    || warn "NEON não detectado"
echo "$FEATS" | grep -qw "crc32"  && ok "CRC32"   || warn "CRC32 HW N/A (usaremos SW)"
echo "$FEATS" | grep -qw "vfpv4"  && ok "VFPv4"   || warn "VFPv4 não detectado"

hdr "FREQUÊNCIAS"
for cpu in 0 1 4 5; do
    F=/sys/devices/system/cpu/cpu${cpu}/cpufreq/cpuinfo_max_freq
    [ -f "$F" ] && info "cpu${cpu}: $(cat $F)kHz" || info "cpu${cpu}: N/A"
done

hdr "MEMÓRIA"
AVAIL=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
TOTAL=$(grep MemTotal    /proc/meminfo 2>/dev/null | awk '{print $2}')
info "RAM Total: ${TOTAL}kB"
info "RAM Avail: ${AVAIL}kB"
[ "${AVAIL:-0}" -gt 256000 ] && ok "RAM OK (>256MB)" || warn "RAM baixa (<256MB)"

hdr "PAGE SIZE"
PG=$(getconf PAGE_SIZE 2>/dev/null || echo 4096)
info "Page: ${PG} bytes"
[ "$PG" = "4096" ]  && ok "4KB (padrão Android)"
[ "$PG" = "16384" ] && ok "16KB (Android 15+ ready)"

hdr "CACHE"
for idx in 0 1 2; do
    B=/sys/devices/system/cpu/cpu0/cache/index${idx}
    [ -d "$B" ] || continue
    SZ=$(cat "$B/size" 2>/dev/null)
    TY=$(cat "$B/type" 2>/dev/null)
    LV=$(cat "$B/level" 2>/dev/null)
    LN=$(cat "$B/coherency_line_size" 2>/dev/null)
    ok "L${LV} ${TY}: sz=${SZ} line=${LN}B"
done

hdr "GPU / OpenCL"
FOUND=0
for p in /vendor/lib/libOpenCL.so /vendor/lib/libPVROCL.so \
          /system/lib/libOpenCL.so /vendor/lib/egl/libGLES_mali.so; do
    [ -f "$p" ] && { ok "GPU lib: $p"; FOUND=1; break; }
done
[ $FOUND -eq 0 ] && warn "OpenCL não encontrado — NEON fallback"
GPU=$(getprop ro.hardware.egl 2>/dev/null || echo N/A)
info "EGL hardware: $GPU"

hdr "OOM / PHANTOM"
OOM=$(cat /proc/$$/oom_score_adj 2>/dev/null || echo N/A)
info "OOM score: $OOM"
[ "${OOM:-0}" -lt 500 ] && ok "OOM OK" || warn "OOM alto ($OOM)"

hdr "TERMUX TOOLCHAIN"
for t in clang as ld ar; do
    command -v "$t" >/dev/null 2>&1 \
        && ok "$t: $(which $t)" \
        || fail "$t: NÃO INSTALADO — pkg install binutils clang"
done

hdr "NEON SELFTEST"
cat > /tmp/neon_t.c << 'NT'
#ifdef __ARM_NEON
#include <arm_neon.h>
#include <stdio.h>
int main(void){
    uint32x4_t a=vdupq_n_u32(56755);
    uint32_t r[4]; vst1q_u32(r,a);
    printf("NEON:OK:%u\n",r[0]); return r[0]!=56755;
}
NT
clang -O1 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp \
      -fPIE -pie /tmp/neon_t.c -o /tmp/neon_t 2>/dev/null \
    && /tmp/neon_t && ok "NEON selftest passou" \
    || warn "NEON selftest falhou (normal em emulador)"
rm -f /tmp/neon_t.c /tmp/neon_t

hdr "PERMISSÕES"
[ -w /proc/sys ] && warn "/proc/sys writable (root?)" || ok "/proc/sys protegido (sem root OK)"
[ -d /vendor/lib ] && ok "/vendor/lib acessível" || warn "/vendor/lib inacessível"

printf "\n\033[1;32m=== DIAGNÓSTICO TERMUX CONCLUÍDO ===\033[0m\n\n"
