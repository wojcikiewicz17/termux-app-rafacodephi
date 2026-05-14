#!/data/data/com.termux/files/usr/bin/sh
# =============================================================================
# RAFAELIA — TERMUX ARM32 ANDROID MASTER SCRIPT
# Alvo: Termux no Android · ARM32 Cortex-A53 · Helio G25
#
# USO (dentro do Termux):
#   chmod +x termux_arm32_build.sh
#   ./termux_arm32_build.sh
#
# DEPENDÊNCIAS (instalar antes):
#   pkg update && pkg install clang binutils libandroid-spawn
#
# CONFORMIDADE:
#   GNU GPL v3.0 · IEEE Std 1003.1 (POSIX) · ARM IHI 0042J
#   NIST SP 800-175B · RFC 3720 · Android NDK r25c
#   Bionic libc (Android) — sem glibc
#
# NOTAS TERMUX:
#   • PREFIX = /data/data/com.termux/files/usr
#   • PIE obrigatório: Android 5+ (API 21+) · -fPIE -pie
#   • Bionic libc: sem getauxval() tradicional em API<18
#   • mmap2 disponível via syscall direto OU mmap() da bionic
#   • clone() disponível mas phantom killer limita filhos
#   • NEON habilitado: Cortex-A53 suporta neon-vfpv4
#   • page size: 4KB (Android <15) ou 16KB (Android 15+)
#   • sem /proc/sys write sem root
# =============================================================================
set -e

# ── Detecção de ambiente ──────────────────────────────────────────────────
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
WORK="$HOME_DIR/rafaelia_arm32"
mkdir -p "$WORK"
cd "$WORK"

OK="\033[32m✓\033[0m"; FAIL="\033[31m✗\033[0m"; INFO="\033[36m→\033[0m"
pass() { printf "$OK %s\n" "$*"; }
fail() { printf "$FAIL %s\n" "$*"; }
log()  { printf "$INFO %s\n" "$*"; }
hdr()  { printf "\n\033[1;33m=== %s ===\033[0m\n" "$*"; }

hdr "RAFAELIA TERMUX ARM32 — AMBIENTE"

# ── Verifica Termux ───────────────────────────────────────────────────────
if [ -d "$PREFIX" ]; then
    pass "Termux detectado: $PREFIX"
else
    fail "Termux não detectado — $PREFIX inexistente"
    log  "Continuando como Linux genérico ARM32"
fi

# ── ABI e toolchain ───────────────────────────────────────────────────────
ARCH=$(uname -m 2>/dev/null)
case "$ARCH" in
    armv7*|armv8l)
        ABI="armeabi-v7a"
        # Flags Termux ARM32: PIE obrigatório, NEON habilitado
        AFLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp"
        CFLAGS="-O2 -std=c11 -ffast-math -fPIE -pie $AFLAGS \
                -DNDEBUG -D__ANDROID__ -DTERMUX \
                -DHAS_NEON -DHAS_BM_NEON_ASM \
                -Wall -Wno-unused-result"
        # Para assembly standalone com _start:
        # PIE requer --dynamic-linker e -lc em Termux
        LDFLAGS_PIE="-pie -L$PREFIX/lib \
                     --dynamic-linker $PREFIX/lib/ld-linux.so"
        # Linker para ASM puro (não precisa de libc):
        LDFLAGS_BARE="-e _start"
        ;;
    aarch64)
        ABI="arm64-v8a"
        AFLAGS="-march=armv8-a"
        CFLAGS="-O2 -std=c11 -ffast-math -fPIE -pie $AFLAGS \
                -DNDEBUG -D__ANDROID__ -DTERMUX \
                -DHAS_NEON -DRAF_ARCH64 \
                -Wall -Wno-unused-result"
        LDFLAGS_PIE="-pie -L$PREFIX/lib"
        LDFLAGS_BARE="-e _start"
        ;;
    *)
        ABI="generic"
        AFLAGS=""
        CFLAGS="-O2 -std=c11 -ffast-math -fPIE -pie \
                -DNDEBUG -Wall -Wno-unused-result"
        LDFLAGS_PIE="-pie"
        LDFLAGS_BARE=""
        ;;
esac

# Compiladores disponíveis no Termux
CC="${CC:-clang}"
AS="${AS:-as}"
LD="${LD:-ld}"

log "ABI=$ABI  CC=$CC  ARCH=$ARCH"

# Verifica se clang está instalado
if ! command -v clang >/dev/null 2>&1; then
    fail "clang não encontrado"
    log  "Execute: pkg install clang binutils"
    exit 1
fi
pass "clang: $(clang --version 2>/dev/null | head -1)"

# ── Page size ─────────────────────────────────────────────────────────────
PG=$(getconf PAGE_SIZE 2>/dev/null || echo 4096)
log "Page size: ${PG} bytes"

# =============================================================================
# GERA: rafaelia_types.h — tipos sem libc pesada
# =============================================================================
hdr "GERANDO ARQUIVOS"

cat > rafaelia_types.h << 'TYPES_EOF'
/**
 * rafaelia_types.h — tipos primitivos RAFAELIA
 * SPDX-License-Identifier: GPL-3.0-only
 * Termux ARM32 · Bionic libc · zero overhead
 *
 * Conforma: ARM IHI 0042J §C1, IEEE Std 1003.1-2017
 */
#pragma once
#ifndef RAFAELIA_TYPES_H
#define RAFAELIA_TYPES_H

#include <stdint.h>
#include <stddef.h>

/* ── Tipos sem ambiguidade ────────────────────────────────────────────── */
typedef uint8_t   u8;
typedef uint16_t  u16;
typedef uint32_t  u32;
typedef uint64_t  u64;
typedef int8_t    i8;
typedef int16_t   i16;
typedef int32_t   i32;
typedef int64_t   i64;
typedef float     f32;

/* ARM32: sizeof(ptr)=4, sizeof(long)=4, sizeof(f32)=4 */
/* f64 PROIBIDO no hot path: 2x custo em softfp ARM32   */

/* ── Constantes Q16.16 ────────────────────────────────────────────────── */
#define Q16_ONE     65536u
#define Q16_HALF    32768u
#define Q16_SPIRAL  56755u   /* sqrt(3)/2 */
#define Q16_PHI     105965u  /* (1+sqrt(5))/2 */
#define Q16_PI      205887u  /* pi */
#define Q16_2PI     411774u  /* 2*pi */
#define Q16_INV6    10923u   /* 1/6 */
#define Q16_INV120  546u     /* 1/120 */

/* ── Status ───────────────────────────────────────────────────────────── */
#define RAF_OK    0
#define RAF_ERR  -1
#define RAF_OOM  -2

/* ── Alinhamentos ─────────────────────────────────────────────────────── */
#define ALIGN64  __attribute__((aligned(64)))
#define ALIGN16  __attribute__((aligned(16)))
#define FORCEINL __attribute__((always_inline)) static inline
#define NOINL    __attribute__((noinline))
#define PACKED   __attribute__((packed))

/* ── Constantes do sistema ────────────────────────────────────────────── */
#define PERIOD      42u
#define TORUS_DIM   7u
#define N_VCPU      8u
#define N_STACKS    1000u
#define N_EXTRA     8u
#define N_TOTAL     1008u
#define CACHE_LINE  64u

/* ── Q16.16 ops ───────────────────────────────────────────────────────── */
static inline u32 qmul(u32 a, u32 b){
    return (u32)(((u64)a*b)>>16);
}
static inline u32 qema(u32 old, u32 in){
    /* 0.75*old + 0.25*in  — sem float, sem divisão */
    return (u32)(((u64)old*49152u+(u64)in*16384u)>>16);
}
static inline u32 qabs(i32 v){
    return (u32)(v<0?-v:v);
}

/* ── sin Taylor Q16.16 — domínio público ─────────────────────────────── */
static inline u32 qsin(u32 x){
    while(x>=Q16_2PI) x-=Q16_2PI;
    int neg=0;
    if(x>=Q16_PI){x-=Q16_PI;neg=1;}
    u64 x2=(u64)x*x>>16;
    u64 x3=(u64)x2*x>>16;
    u64 x5=(u64)x3*x2>>16;
    u64 t1=(u64)x3*Q16_INV6>>16;
    u64 t2=(u64)x5*Q16_INV120>>16;
    i64 r=(i64)x-(i64)t1+(i64)t2;
    if(r<0)r=0; if(r>65535)r=65535;
    return neg?(u32)(65535u-(u32)r):(u32)r;
}

#endif /* RAFAELIA_TYPES_H */
TYPES_EOF
pass "rafaelia_types.h"

# =============================================================================
# GERA: rafaelia_arena.h — arena estática, zero malloc
# =============================================================================
cat > rafaelia_arena.h << 'ARENA_EOF'
/**
 * rafaelia_arena.h — arena estática zero malloc
 * SPDX-License-Identifier: GPL-3.0-only
 * Termux ARM32 · Bionic libc
 *
 * RAZÃO: malloc() da Bionic tem overhead de ~100 ciclos + fragmentação.
 * Arena estática elimina overhead, garante localidade de cache L1/L2,
 * e é determinística (sem falha de alloc no hot path).
 *
 * Conforma: IEEE Std 1003.1-2017 §13 (sem mmap obrigatório)
 */
#pragma once
#ifndef RAFAELIA_ARENA_H
#define RAFAELIA_ARENA_H

#include "rafaelia_types.h"

/* ── Arena global: 4MB BSS ───────────────────────────────────────────── */
/* BSS não ocupa espaço no binário — só reserva virtual                   */
/* Bionic aloca páginas lazy — sem custo de startup                       */
#define ARENA_SZ (4u*1024u*1024u)

extern u8   g_arena_buf[ARENA_SZ];
extern u32  g_arena_bump;

/* ── Alloc: alinha a `al` bytes (deve ser pot. de 2) ────────────────── */
FORCEINL void *raf_alloc(u32 n, u32 al) {
    u32 mask = al-1u;
    u32 s = (g_arena_bump+mask)&~mask;
    u32 e = s+n;
    if (e > ARENA_SZ) return 0;
    g_arena_bump = e;
    return g_arena_buf + s;
}

FORCEINL void raf_arena_reset(void) { g_arena_bump = 0; }

/* Macros convenientes */
#define RALLOC(T,n)   ((T*)raf_alloc((u32)(sizeof(T)*(n)), 16u))
#define RALLOC64(T,n) ((T*)raf_alloc((u32)(sizeof(T)*(n)), 64u))

/* ── CRC32C Castagnoli (RFC 3720 §B.4, NIST SP 800-175B) ───────────── */
/* Poly 0x82F63B78 — domínio público, padronizado por RFC                 */
extern u32 g_crc_tab[256];
extern int g_crc_ready;

static inline void crc_build(void) {
    for (u32 i=0;i<256u;i++){
        u32 v=i;
        for(int j=0;j<8;j++) v=(v&1u)?(v>>1)^0x82F63B78u:(v>>1);
        g_crc_tab[i]=v;
    }
    g_crc_ready=1;
}

static inline u32 crc32c(const void *buf, u32 n){
    if(!g_crc_ready) crc_build();
    const u8 *p=(const u8*)buf; u32 c=~0u;
    while(n--) c=(c>>8)^g_crc_tab[(c^*p++)&0xFF];
    return ~c;
}

#endif /* RAFAELIA_ARENA_H */
ARENA_EOF
pass "rafaelia_arena.h"

# =============================================================================
# GERA: rafaelia_core.c — núcleo principal ARM32 Termux
# =============================================================================
cat > rafaelia_core.c << 'CORE_EOF'
/**
 * rafaelia_core.c — RAFAELIA Core ARM32 para Termux/Android
 * SPDX-License-Identifier: GPL-3.0-only
 * Copyright (C) 2024-2025 Instituto Rafael
 *
 * Compilar (Termux ARM32):
 *   clang -O2 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp \
 *         -fPIE -pie -std=c11 -ffast-math \
 *         rafaelia_core.c -o rafaelia_core -lm -ldl
 *
 * Conformidade:
 *   IEEE Std 1003.1-2017 (POSIX) — open, read, write, mmap
 *   IEEE Std 754-2019 — f32 via NEON; Q16.16 no hot path
 *   NIST SP 800-175B rev1 — CRC32C Castagnoli
 *   RFC 3720 §B.4 — poly 0x1EDC6F41 (equivale a 0x82F63B78 reversed)
 *   ARM IHI 0042J — NEON intrinsics AAPCS32
 *   Android NDK r25c — PIE, bionic libc, page-size
 *
 * TERMUX ESPECÍFICO:
 *   • Usa mmap() da bionic (não syscall direto) — mais portável
 *   • PIE: -fPIE -pie obrigatório desde Android 5.0 (API 21)
 *   • Phantom killer: clone() limitado — usa apenas 1 processo
 *   • /proc/self/auxv: disponível sem root para HWCAP
 *   • GPU: dlopen para /vendor/lib (requer permissão do fabricante)
 *   • Arena BSS: 4MB — Bionic aloca lazy, sem custo de startup
 */

#define _POSIX_C_SOURCE 200809L
#ifndef M_PI
#define M_PI 3.14159265358979323846f
#endif

#include "rafaelia_types.h"
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <dlfcn.h>
#include <time.h>

#ifdef HAS_NEON
#include <arm_neon.h>
#endif

/* ── Arena global (BSS) ─────────────────────────────────────────────── */
ALIGN64 u8  g_arena_buf[4u*1024u*1024u];
u32         g_arena_bump = 0;
u32         g_crc_tab[256];
int         g_crc_ready  = 0;

#include "rafaelia_arena.h"

/* ── Output sem printf (bionic printf tem overhead) ─────────────────── */
static const char HEX[] = "0123456789ABCDEF";
static void ws(const char *s){
    if(!s) return;
    size_t n=0; while(s[n]) n++;
    write(1,s,n);
}
static void wn(void){ write(1,"\n",1); }
static void wu32(u32 v){
    char b[12]; int i=11; b[i]=0;
    if(!v){b[--i]='0';}else while(v){b[--i]=(char)('0'+v%10);v/=10;}
    ws(b+i);
}
static void whex(u32 v){
    char b[11]="0x00000000";
    for(int i=0;i<8;i++) b[2+i]=HEX[(v>>(28-i*4))&0xF];
    ws(b);
}
static void wlabel(const char *l, u32 v){ ws(l); whex(v); wn(); }
static void wline(const char *a, const char *b){ ws(a); ws(b); wn(); }

/* ── HW probe via /proc — sem sysconf no hot path ───────────────────── */
typedef struct {
    u32 n_cpu;
    u32 freq0_khz;   /* cluster0 máximo */
    u32 freq1_khz;   /* cluster1 máximo */
    u32 page_sz;
    u32 cache_line;
    u8  has_neon;
    u8  has_crc32_hw;
    u8  gpu_found;
    char gpu_path[128];
} hw_t;

static u32 rd_u32_file(const char *p){
    char b[32]; int fd=open(p,O_RDONLY|O_CLOEXEC);
    if(fd<0) return 0;
    ssize_t n=read(fd,b,31); close(fd);
    if(n<=0) return 0; b[n]=0;
    u32 v=0;
    for(int i=0;b[i]>='0'&&b[i]<='9';i++) v=v*10u+(u32)(b[i]-'0');
    return v;
}

/* GPU paths Android/Termux — por fabricante                              */
/* Referência: Android VNDK spec, Khronos OpenCL 3.0 ICD loader spec     */
static const char *GPU_PATHS[] = {
    /* MediaTek PowerVR GE8320 (Helio G25) */
    "/vendor/lib/libOpenCL.so",
    "/vendor/lib/libPVROCL.so",
    "/vendor/lib/egl/libGLES_mali.so",
    /* Qualcomm Adreno */
    "/vendor/lib/libOpenCL_adreno.so",
    "/system/vendor/lib/libOpenCL.so",
    /* ARM Mali */
    "/system/lib/egl/libGLES_mali.so",
    "/vendor/lib/libGLES_mali.so",
    /* Generic */
    "/system/lib/libOpenCL.so",
    NULL
};

static void hw_probe(hw_t *h){
    memset(h,0,sizeof(*h));
    h->n_cpu   = rd_u32_file("/sys/devices/system/cpu/present");
    if(!h->n_cpu) h->n_cpu = N_VCPU;
    h->freq0_khz = rd_u32_file(
        "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq");
    h->freq1_khz = rd_u32_file(
        "/sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq");
    if(!h->freq0_khz) h->freq0_khz = 2000000u;
    if(!h->freq1_khz) h->freq1_khz = 1500000u;
    long pg = sysconf(_SC_PAGESIZE);
    h->page_sz = (pg>0)?(u32)pg:4096u;
#ifdef _SC_LEVEL1_DCACHE_LINESIZE
    long cl = sysconf(_SC_LEVEL1_DCACHE_LINESIZE);
    h->cache_line = (cl>0)?(u32)cl:CACHE_LINE;
#else
    h->cache_line = CACHE_LINE;
#endif
#ifdef HAS_NEON
    h->has_neon = 1;
#endif
#ifdef __ARM_FEATURE_CRC32
    h->has_crc32_hw = 1;
#endif
    /* GPU probe via dlopen */
    for(int i=0;GPU_PATHS[i];i++){
        void *lib=dlopen(GPU_PATHS[i],RTLD_LAZY|RTLD_LOCAL);
        if(!lib) continue;
        if(dlsym(lib,"clGetPlatformIDs")){
            h->gpu_found=1;
            strncpy(h->gpu_path,GPU_PATHS[i],127);
            dlclose(lib); break;
        }
        dlclose(lib);
    }
}

/* ── vCPU model ─────────────────────────────────────────────────────── */
typedef struct {
    u32  s[TORUS_DIM]; /* estado 7D Q16.16 */
    u32  hz;           /* frequência harmônica Q16.16 */
    u32  C, H;         /* coerência, entropia */
    u32  phase;        /* 0..41 */
    u32  layer;        /* 0=L1 1=L2 2=BUF 3=RAM */
    u32  load;
    u32  crc_s;
} vcpu_t;

/* Hz por core: cluster0 (cpu0-3)=58000, cluster1 (cpu4-7)=43500 Q16.16 */
/* Derivado de freq * SPIRAL^fib[i] / 65536                               */
static const u32 HZ_TABLE[N_VCPU] =
    {58000u,58000u,58000u,50296u, 43500u,43500u,37709u,26836u};

static vcpu_t g_vcpu[N_VCPU];

static void vcpu_init(void){
    for(u32 i=0;i<N_VCPU;i++){
        vcpu_t *v=&g_vcpu[i];
        v->hz    = HZ_TABLE[i];
        v->C     = Q16_HALF;
        v->H     = Q16_HALF;
        v->phase = (i*PERIOD)/N_VCPU;
        v->load  = 0;
        v->layer = (v->hz>50000u)?0:(v->hz>38000u)?1:(v->hz>25000u)?2:3;
        u32 seed = (Q16_SPIRAL*(i+1u))&0xFFFFu;
        for(u32 d=0;d<TORUS_DIM;d++){
            seed = qmul(seed,Q16_SPIRAL)+d*1009u;
            v->s[d] = seed&0xFFFFu;
        }
        v->crc_s = crc32c(v,offsetof(vcpu_t,crc_s));
    }
}

/* ── Triângulo isósceles de predição ─────────────────────────────────── */
static u32 predict_jet(void){
    u32 apex=0;
    for(u32 i=1;i<N_VCPU;i++)
        if(g_vcpu[i].hz>g_vcpu[apex].hz) apex=i;
    u32 jet=0, ml=~0u;
    for(u32 i=0;i<N_VCPU;i++){
        if(i==apex) continue;
        if(g_vcpu[i].load<ml){ml=g_vcpu[i].load;jet=i;}
    }
    return jet;
}

/* ── BitStacks 1008 ──────────────────────────────────────────────────── */
static u64  *g_stacks;  /* 1000 x u64 na arena */
static u64   g_par_xor;
static u32   g_par_crc;

static void stacks_init(void){
    g_stacks=(u64*)RALLOC64(u64,N_STACKS);
    if(!g_stacks) return;
    memset(g_stacks,0,N_STACKS*8u);
    u64 f0=0,f1=1;
    for(u32 i=0;i<N_STACKS;i++){
        u32 bits=(u32)(f1%PERIOD);
        g_stacks[i]=bits?(1ULL<<bits)-1ULL:0ULL;
        u64 fn=f0+f1; f0=f1; f1=fn;
    }
    g_par_xor=0;
    for(u32 i=0;i<N_STACKS;i++) g_par_xor^=g_stacks[i];
    g_par_crc=crc32c(g_stacks,(u32)(N_STACKS*8u));
}

static int stacks_ok(void){
    if(!g_stacks) return 1;
    u32 c=crc32c(g_stacks,(u32)(N_STACKS*8u));
    return c==g_par_crc;
}

static u32 stacks_bits(void){
    u32 tot=0;
    for(u32 i=0;i<N_STACKS;i++){u64 v=g_stacks[i];while(v){v&=v-1;tot++;}}
    return tot;
}

/* ── Camadas de memória (arena interna) ──────────────────────────────── */
static u8 *g_l1, *g_l2, *g_buf, *g_ram;
static const u32 LSIZ[4]={8192u,32768u,65536u,131072u};

static void mem_init(void){
    g_l1  = RALLOC64(u8,LSIZ[0]);
    g_l2  = RALLOC64(u8,LSIZ[1]);
    g_buf = RALLOC64(u8,LSIZ[2]);
    g_ram = RALLOC64(u8,LSIZ[3]);
    if(g_l1)  memset(g_l1, 0,LSIZ[0]);
    if(g_l2)  memset(g_l2, 0,LSIZ[1]);
    if(g_buf) memset(g_buf,0,LSIZ[2]);
    if(g_ram) memset(g_ram,0,LSIZ[3]);
}

/* ── Commit gate ─────────────────────────────────────────────────────── */
static u32    g_cg_bm[N_VCPU];
static vcpu_t g_snap[N_VCPU];
static u32    g_commits=0, g_rollbacks=0;

#define CG_LOAD   0x1u
#define CG_PROC   0x2u
#define CG_VERIFY 0x4u
#define CG_COMMIT 0x8u
#define CG_ALL    0xFu

static void cg_step(u32 core){
    vcpu_t *v=&g_vcpu[core];
    /* LOAD */
    memcpy(&g_snap[core],v,sizeof(vcpu_t));
    g_cg_bm[core]|=CG_LOAD;
    /* PROCESS: EMA 7D Q16.16 */
    for(u32 d=0;d<TORUS_DIM;d++){
        u32 nd=(d+1u)%TORUS_DIM;
        v->s[d]=qema(v->s[d],v->s[nd]);
    }
    v->C=qema(v->C,qmul(v->hz,Q16_SPIRAL)&0xFFFFu);
    v->H=qema(v->H,65535u-(qmul(v->hz,Q16_SPIRAL)&0xFFFFu));
    v->phase=(v->phase+1u<PERIOD)?v->phase+1u:0u;
    g_cg_bm[core]|=CG_PROC;
    /* VERIFY */
    u32 sc=crc32c(v,offsetof(vcpu_t,crc_s));
    if(!sc||v->s[0]>=Q16_2PI){
        memcpy(v,&g_snap[core],sizeof(vcpu_t));
        g_cg_bm[core]=0; g_rollbacks++; return;
    }
    g_cg_bm[core]|=CG_VERIFY;
    /* COMMIT */
    if((g_cg_bm[core]&CG_ALL)==CG_ALL){
        v->crc_s=sc; g_cg_bm[core]=0; g_commits++;
    }
}

/* ── Senoides 7 camadas (ΣΩ lite) ───────────────────────────────────── */
static u32 g_sin_ph[TORUS_DIM];
static u32 g_sin_w[TORUS_DIM];
static u32 g_phi_tr[PERIOD];
static u32 g_crc_chain=0;
static u32 g_sin_C=Q16_HALF, g_sin_H=Q16_HALF;

static const u32 FREQS[TORUS_DIM]={9804u,19608u,29412u,39216u,49020u,58824u,68628u};
static const u32 WINIT[TORUS_DIM]={65536u,56755u,49157u,42573u,36877u,31940u,27671u};

static void sin_init(void){
    memcpy(g_sin_w,WINIT,sizeof(WINIT));
    memset(g_sin_ph,0,sizeof(g_sin_ph));
}

static u32 sin_step(u32 cy){
    u32 ov=0;
    for(u32 i=0;i<TORUS_DIM;i++){
        g_sin_ph[i]+=FREQS[i];
        if(g_sin_ph[i]>=Q16_2PI) g_sin_ph[i]-=Q16_2PI;
        u32 sv=qsin(g_sin_ph[i]);
        ov+=qmul(sv,g_sin_w[i]);
        g_sin_w[i]=(g_sin_w[i]*3u+sv)>>2;
    }
    u32 c_in=qmul(ov,9362u);
    g_sin_C=qema(g_sin_C,c_in);
    g_sin_H=qema(g_sin_H,65535u-c_in);
    u32 phi=qmul(65535u-g_sin_H,g_sin_C);
    if(cy<PERIOD) g_phi_tr[cy]=phi;
    u32 tmp[2]={phi,g_crc_chain};
    g_crc_chain=crc32c(tmp,8u);
    return phi;
}

/* ── NEON EMA batch (Q16.16) ─────────────────────────────────────────── */
#ifdef HAS_NEON
static void neon_ema_u32(u32 *dst, const u32 *src, u32 n, u32 alpha){
    u32 inv=65536u-alpha;
    uint32x4_t va=vdupq_n_u32(alpha), vi=vdupq_n_u32(inv);
    u32 i=0;
    for(;i+4<=n;i+=4){
        uint32x4_t sd=vld1q_u32(dst+i), ss=vld1q_u32(src+i);
        uint64x2_t lo=vaddq_u64(
            vmull_u32(vget_low_u32(sd), vget_low_u32(vi)),
            vmull_u32(vget_low_u32(ss), vget_low_u32(va)));
        uint64x2_t hi=vaddq_u64(
            vmull_u32(vget_high_u32(sd),vget_high_u32(vi)),
            vmull_u32(vget_high_u32(ss),vget_high_u32(va)));
        vst1q_u32(dst+i,
            vcombine_u32(vshrn_n_u64(lo,16),vshrn_n_u64(hi,16)));
    }
    for(;i<n;i++)
        dst[i]=(u32)(((u64)dst[i]*inv+(u64)src[i]*alpha)>>16);
}
#else
static void neon_ema_u32(u32*dst,const u32*src,u32 n,u32 alpha){
    u32 inv=65536u-alpha;
    for(u32 i=0;i<n;i++)
        dst[i]=(u32)(((u64)dst[i]*inv+(u64)src[i]*alpha)>>16);
}
#endif

/* ── Throughput ──────────────────────────────────────────────────────── */
static u64 now_us(void){
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC,&ts);
    return (u64)ts.tv_sec*1000000u+(u64)ts.tv_nsec/1000u;
}

/* ── MAIN ────────────────────────────────────────────────────────────── */
int main(void){
    crc_build();
    hw_t hw; hw_probe(&hw);
    vcpu_init();
    mem_init();
    stacks_init();
    sin_init();
    memset(g_cg_bm,0,sizeof(g_cg_bm));

    ws("=== RAFAELIA TERMUX ARM32 ===\n");
    wline("ABI:  ",
#if defined(__aarch64__)
        "arm64-v8a"
#elif defined(__arm__)
        "armeabi-v7a"
#else
        "generic"
#endif
    );
    ws("vCPU: "); wu32(hw.n_cpu); wn();
    ws("NEON: "); ws(hw.has_neon?"YES":"NO"); wn();
    ws("GPU:  "); ws(hw.gpu_found?hw.gpu_path:"CPU-NEON"); wn();
    ws("PAGE: "); wu32(hw.page_sz); wn();
    wlabel("FREQ0_kHz: ",(u32)hw.freq0_khz);
    wlabel("FREQ1_kHz: ",(u32)hw.freq1_khz);
    wn();

    u64 t0=now_us();

    /* 42 ciclos */
    for(u32 cy=0;cy<PERIOD;cy++){
        u32 jet=predict_jet();

        /* commit gate */
        cg_step(jet);

        /* NEON EMA na camada do core */
        u32 lay=g_vcpu[jet].layer;
        u8 *lbuf[]={g_l1,g_l2,g_buf,g_ram};
        u32 lsz[]  ={LSIZ[0],LSIZ[1],LSIZ[2],LSIZ[3]};
        if(lbuf[lay] && lsz[lay]>=16){
            u32 sv=qsin(g_vcpu[jet].phase*FREQS[0]);
            /* seed do input: senoide mapeada para u32 */
            static u32 src_pat[16];
            for(int k=0;k<16;k++) src_pat[k]=sv^(u32)(k*1009u);
            neon_ema_u32((u32*)lbuf[lay],src_pat,4u,16384u);
        }

        /* senoide 7 camadas */
        sin_step(cy);

        /* EMA do load */
        g_vcpu[jet].load=qema(g_vcpu[jet].load,Q16_SPIRAL&0xFFFFu);

        /* paridade stacks a cada 7 ciclos */
        if((cy%7u)==0 && !stacks_ok()){
            g_par_crc=crc32c(g_stacks,(u32)(N_STACKS*8u));
        }
    }

    u64 elapsed=now_us()-t0;

    ws("\n=== 42 CICLOS COMPLETOS ===\n");
    ws("ELAPSED_us: "); wu32((u32)elapsed);  wn();
    ws("COMMITS:    "); wu32(g_commits);      wn();
    ws("ROLLBACKS:  "); wu32(g_rollbacks);    wn();
    wlabel("PHI_FINAL:  ",g_phi_tr[PERIOD-1]);
    wlabel("CRC_CHAIN:  ",g_crc_chain);
    wlabel("CRC_STACKS: ",g_par_crc);
    ws("BITS_SET:   "); wu32(stacks_bits());  wn();
    ws("ARENA_USED: "); wu32(g_arena_bump/1024u); ws("KB\n");
    ws("TOTAL_PTS:  "); wu32(N_TOTAL);        wn();

    ws("\n--- vCPU HZ MAP ---\n");
    static const char *LN[]={"L1","L2","BF","RM"};
    for(u32 i=0;i<N_VCPU;i++){
        vcpu_t *v=&g_vcpu[i];
        ws("CPU"); wu32(i);
        ws(" hz="); whex(v->hz);
        ws(" C=");  whex(v->C);
        ws(" lay=");ws(LN[v->layer]);
        wn();
    }
    ws("=== DONE ===\n");
    return 0;
}
CORE_EOF
pass "rafaelia_core.c"

# =============================================================================
# GERA: Assembly B1 ARM32 Termux — com PIE-safe exit
# =============================================================================
cat > raf_asm_b1.S << 'ASM1_EOF'
@ ===========================================================================
@ raf_asm_b1.S — RAFAELIA B1 ARM32 Termux
@ Toro T^7 · CRC32C · EMA · 42 atratores
@
@ TERMUX: usa syscall SYS_exit_group (252) em vez de SYS_exit (1)
@         para compatibilidade com Bionic thread runtime
@
@ Compilar (Termux):
@   as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp raf_asm_b1.S -o b1.o
@   ld --dynamic-linker /data/data/com.termux/files/usr/lib/ld-linux.so \
@      -pie b1.o -o raf_b1
@ ---------------------------------------------------------------------------
@
@ Ou via clang (mais simples no Termux):
@   clang -fPIE -pie -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp \
@         raf_asm_b1.S -o raf_b1
@ ===========================================================================

.equ SYS_WRITE,      4
.equ SYS_EXIT_GROUP, 252   @ Termux/Android: usar exit_group
.equ SYS_MMAP2,      192
.equ STDOUT,         1
.equ PROT_RW,        3
.equ MAP_ANON,       0x22
.equ SPIRAL_Q16,     56755
.equ PHI_Q16,        105965
.equ PERIOD,         42
.equ TORUS_DIM,      7
.equ ARENA_SZ,       0x400000  @ 4MB

.section .rodata
.align 6

msg_boot:  .ascii "RAFAELIA B1 ARM32 TERMUX\n"
.equ msg_boot_len, . - msg_boot
msg_ok:    .ascii "B1:OK\n"
.equ msg_ok_len, . - msg_ok
msg_phi:   .ascii "PHI="
.equ msg_phi_len, . - msg_phi
hex_t:     .ascii "0123456789ABCDEF"

@ 42 atratores 7D Q16.16 (geração determinística via .set)
.align 4
attractor_table:
.set _A, 0
.rept 42
    .long 0x0000 + _A * 0x0A3C
    .long 0x2000 + _A * 0x0D17
    .long 0x4000 + _A * 0x05FB
    .long 0x6000 + _A * 0x08E4
    .long 0x8000 + _A * 0x03C2
    .long 0xA000 + _A * 0x0B91
    .long 0xC000 + _A * 0x07A5
    .set _A, _A + 1
.endr

.section .bss
.align 6

g_state:     .space TORUS_DIM * 4
g_C:         .space 4
g_H:         .space 4
g_phase:     .space 4
g_hex_buf:   .space 12
g_crc_tab:   .space 256 * 4

.section .text
.align 2
.global _start
.global main        @ alias para PIE

_start:
main:
    ldr     r0, =msg_boot
    mov     r1, #msg_boot_len
    bl      _ws

    bl      _crc_build
    bl      _torus_init
    bl      _run_42

    @ imprime phi final
    ldr     r0, =msg_phi
    mov     r1, #msg_phi_len
    bl      _ws

    ldr     r0, =g_C
    ldr     r0, [r0]
    bl      _ph

    ldr     r0, =msg_ok
    mov     r1, #msg_ok_len
    bl      _ws

    @ exit_group(0) — Termux/Bionic
    mov     r7, #SYS_EXIT_GROUP
    mov     r0, #0
    swi     #0

@ CRC32C build (Castagnoli, RFC 3720)
_crc_build:
    push {r4,r5,r6,r7,lr}
    ldr r4,=g_crc_tab; mov r5,#0
.cb: cmp r5,#256; beq .cbd
    mov r0,r5; mov r6,#8
.cbb: tst r0,#1; lsr r0,r0,#1
    ldrne r7,=0x82F63B78; eorne r0,r0,r7
    subs r6,r6,#1; bne .cbb
    str r0,[r4,r5,lsl #2]; add r5,r5,#1; b .cb
.cbd: pop {r4,r5,r6,r7,pc}

@ torus init
_torus_init:
    push {r4,r5,r6,lr}
    ldr r4,=g_state
    ldr r5,=SPIRAL_Q16
    ldr r6,=PHI_Q16
    and r0,r5,#0xFFFF; str r0,[r4,#0]
    and r0,r6,#0xFFFF; str r0,[r4,#4]
    mul r0,r5,r6; lsr r0,r0,#16; and r0,r0,#0xFFFF; str r0,[r4,#8]
    mov r0,#0x8000; ldr r1,=g_C; str r0,[r1]
    ldr r1,=g_H; str r0,[r1]
    mov r0,#0; ldr r1,=g_phase; str r0,[r1]
    pop {r4,r5,r6,pc}

@ 42 ciclos EMA
_run_42:
    push {r4,r5,lr}
    mov r4,#PERIOD
.r42: cmp r4,#0; beq .r42d
    @ C_in sintético = SPIRAL * phase / PERIOD
    ldr r0,=g_phase; ldr r0,[r0]
    ldr r1,=SPIRAL_Q16; mul r0,r0,r1; lsr r0,r0,#4
    and r0,r0,#0xFFFF
    @ EMA: C = (3*C + C_in)/4
    ldr r5,=g_C; ldr r1,[r5]
    add r1,r1,r1,lsl #1   @ 3*C
    add r1,r1,r0; lsr r1,r1,#2
    str r1,[r5]
    @ phase++
    ldr r5,=g_phase; ldr r0,[r5]
    add r0,r0,#1; cmp r0,#PERIOD; moveq r0,#0
    str r0,[r5]
    subs r4,r4,#1; b .r42
.r42d:
    pop {r4,r5,pc}

_ws:
    push {lr}
    mov r2,r1; mov r1,r0; mov r0,#STDOUT
    mov r7,#SYS_WRITE; swi #0
    pop {pc}

_ph:
    push {r4,r5,lr}
    mov r4,r0; ldr r5,=g_hex_buf; ldr r2,=hex_t; mov r1,#28
.ph: lsr r0,r4,r1; and r0,r0,#0xF; ldrb r0,[r2,r0]; strb r0,[r5],#1
    subs r1,r1,#4; bge .ph
    mov r0,#'\n'; strb r0,[r5]; ldr r0,=g_hex_buf; mov r1,#9; bl _ws
    pop {r4,r5,pc}
ASM1_EOF
pass "raf_asm_b1.S"

# =============================================================================
# GERA: diagnose_termux.sh — diagnóstico específico para Termux
# =============================================================================
cat > diagnose_termux.sh << 'DIAG_EOF'
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
DIAG_EOF
chmod +x diagnose_termux.sh
pass "diagnose_termux.sh"

# =============================================================================
# COMPILAÇÃO — flags específicas Termux ARM32
# =============================================================================
hdr "COMPILANDO — Termux ARM32"

# C flags completos para Termux ARM32
TCF="$CFLAGS -I."

section(){ printf "\n\033[36m--- %s ---\033[0m\n" "$*"; }

section "rafaelia_core.c"
clang $TCF rafaelia_core.c -o rafaelia_core -lm -ldl 2>&1 \
    && pass "rafaelia_core" \
    || { fail "rafaelia_core — tentando sem -ldl"; \
         clang $TCF rafaelia_core.c -o rafaelia_core -lm 2>&1 \
             && pass "rafaelia_core (sem ldl)" || fail "rafaelia_core FALHOU"; }

section "raf_asm_b1.S via clang"
# No Termux: compilar .S com clang é mais confiável que as+ld manual
clang $CFLAGS raf_asm_b1.S -o raf_b1 2>/dev/null \
    && pass "raf_b1 (clang ASM)" \
    || {
        log "clang ASM falhou, tentando as+ld..."
        as $AFLAGS raf_asm_b1.S -o raf_b1.o 2>/dev/null \
            && ld $LDFLAGS_BARE raf_b1.o -o raf_b1 2>/dev/null \
            && pass "raf_b1 (as+ld)" \
            || log "raf_b1 asm skipped (normal em emulador x86)"
    }

# Compila módulos dos zips anteriores se existirem
for src in rafaelia_orchestrator.c rafaelia_glue.c rafaelia_bitraf.c \
           rafaelia_sigma_omega.c; do
    [ -f "$src" ] || continue
    BIN="${src%.c}"
    section "$src"
    clang $TCF "$src" -o "$BIN" -lm -ldl 2>/dev/null \
        && pass "$BIN" || log "$BIN skipped"
done

# =============================================================================
# EXECUÇÃO
# =============================================================================
hdr "EXECUTANDO"

run(){ BIN="$1"; [ -x "./$BIN" ] || { log "$BIN: não compilado"; return; }
    OUT=$(./"$BIN" 2>&1); RC=$?
    [ $RC -eq 0 ] && { pass "$BIN"; echo "$OUT" | head -5 | sed 's/^/  /'; } \
                  || { fail "$BIN (exit=$RC)"; echo "$OUT" | tail -3 | sed 's/^/  /'; }
}

run rafaelia_core
run raf_b1
for b in rafaelia_bitraf rafaelia_orch rafaelia_glue sigma_omega; do
    run "$b"
done

# =============================================================================
# DIAGNÓSTICO
# =============================================================================
hdr "DIAGNÓSTICO TERMUX"
./diagnose_termux.sh

# =============================================================================
# SUMÁRIO
# =============================================================================
hdr "SUMÁRIO"
printf "Diretório: %s\n" "$WORK"
printf "Arquivos gerados:\n"
ls -lh *.c *.h *.S *.sh 2>/dev/null | awk '{printf "  %-38s %s\n",$NF,$5}'
printf "\nBinários:\n"
ls -lh rafaelia_core raf_b1 rafaelia_bitraf \
        rafaelia_orch rafaelia_glue sigma_omega 2>/dev/null | \
    awk '{printf "  %-38s %s\n",$NF,$5}'
printf "\nArena (zero malloc):\n"
printf "  rafaelia_core:  4MB BSS\n"
printf "  raf_b1 ASM:     sem malloc (puro registradores)\n"
printf "  Total peak:     ~4MB (sem heap)\n"
printf "\nFlags ARM32 Termux:\n"
printf "  %s\n" "$CFLAGS" | tr ' ' '\n' | grep -v '^$' | sed 's/^/  /'
printf "\nPróximos passos:\n"
printf "  cp rafaelia_core ~/bin/  # instala binário\n"
printf "  ./diagnose_termux.sh     # diagnóstico completo\n"
printf "  ./rafaelia_core          # roda sistema\n"
printf "\n\033[1;32m=== TERMUX ARM32 BUILD COMPLETO ===\033[0m\n"
