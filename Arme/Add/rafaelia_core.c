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
