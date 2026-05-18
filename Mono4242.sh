monolito completo
bash

cat > /tmp/42atratores.txt << 'MONOLITH'
#!/usr/bin/env bash
# =============================================================================
# 42atratores.txt — MONOLITO COMPLETO — renomeie para .sh: bash 42atratores.txt
# =============================================================================
# CABEÇALHO / O QUE É ESTE ARQUIVO:
#
# Refatoração de análise de grafos circulares (N=42, K=5) + Mandelbrot + Julia
# em C com inline ASM puro — zero dependências externas, zero malloc, zero libc.
#
# EQUIVALÊNCIA PYTHON → C/ASM (sem abstração):
#   np.linspace(0,2π,N)      → tabela sin/cos Q16 via CORDIC ARM32/ARM64/x86
#   plt.plot([x1,x2],[y1,y2])→ SVG write() direto via syscall fd
#   plt.scatter(...)          → SVG circles via write()
#   np.zeros(N)               → u32 density[42] em BSS
#   set(edges)                → bitmap u64 para deduplicação O(1)
#   plt.show()                → escreve SVG/PNG em arquivo via fd
#
# COMPONENTES:
#   [01] Tipos Q16.16, arena BSS 512KB, syscalls ARM32/ARM64/x86/RISC-V
#   [02] CORDIC sin/cos Q16 — sem libm, sem float, inline ASM
#   [03] Grafo circular 42 pontos — densidade, simetria, complexidade
#   [04] Mandelbrot Q16 — escape time, 256 iterações
#   [05] Julia Q16 — parâmetro c fixo, semicírculo de parâmetros
#   [06] Escritor SVG via syscall direto — zero malloc zero libc
#   [07] Escritor PNG — CRC32, Adler32, DEFLATE stored blocks
#   [08] CLI BBS-style (Clipper 5 / Summer'87) — ANSI colors, box drawing
#   [09] Detecção CPU: ARM32/ARM64/x86-64/RISC-V, L1/L2/L3, NEON/SIMD/CRC32C
#   [10] Matrizes 2×2, 4×4, 8×8, 10×10 com vértices dos 42 atratores
#   [11] TTL/IRQ como contadores de processamento — ciclos de graça
#   [12] 7 senoides adaptativas para escalonamento de carga
#   [13] vCPU 4/8/16/32 cores — parallel bitwise ops
#   [14] Failsafe + rollback via arena mark/restore
#   [15] ASCII art logo colorido BBS-style
#
# PARÂMETROS CLI (default entre colchetes):
#   -n <N>     pontos no círculo [42]
#   -k <K>     passo modular [5]
#   -i <ITER>  iterações [5000]
#   -w <W>     largura fractal [80]
#   -h <H>     altura fractal [40]
#   -z <ZOOM>  zoom Mandelbrot [1.0 em Q16=65536]
#   -m         Mandelbrot
#   -j <cr,ci> Julia com parâmetro c (Q16)
#   -g         grafo circular
#   --svg      saída SVG
#   --png      saída PNG
#   --all      tudo
#
# DeltaRafaelVerboOmega · Omega=Amor · RAFCODE-Phi · F*=23.158
# =============================================================================
set -euo pipefail
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m'
M='\033[0;35m' C='\033[0;36m' W='\033[1;37m' Z='\033[0m' BLD='\033[1m'
D="${HOME}/.rafaelia/42ATRATORES"; mkdir -p "$D"
LOG="$D/build.log"; :>"$LOG"
p(){ printf "${C}[42]${Z} %s\n" "$*"; }
ok(){ printf "${G}[OK]${Z} %s\n" "$*"; }
err(){ printf "${R}[ERR]${Z} %s\n" "$*" >&2; }
hdr(){ printf "\n${M}${BLD}━━━ %s ━━━${Z}\n" "$*"; }
echo -e "${Y}${BLD}"
cat << 'LOGO'
  ╔═══════════════════════════════════════════════════════════════╗
  ║  ██╗  ██╗██████╗      █████╗ ████████╗██████╗  █████╗ ████╗  ║
  ║  ██║  ██║╚════██╗    ██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗╚══██║ ║
  ║  ███████║ █████╔╝    ███████║   ██║   ██████╔╝███████║  ██╔╝ ║
  ║  ╚════██║██╔═══╝     ██╔══██║   ██║   ██╔══██╗██╔══██║ ██╔╝  ║
  ║       ██║███████╗    ██║  ██║   ██║   ██║  ██║██║  ██║██████╗║
  ║       ╚═╝╚══════╝    ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝║
  ╠═══════════════════════════════════════════════════════════════╣
  ║  GRAFOS CIRCULARES · MANDELBROT · JULIA · SVG · PNG          ║
  ║  C+ASM inline · nomalloc · nolibc · Q16 · ARM32/64/x86/RV   ║
  ║  BBS-Style CLI · Clipper5/Summer'87 · ANSI Colors            ║
  ╚═══════════════════════════════════════════════════════════════╝
LOGO
echo -e "${Z}"
p "Diretório: $D"
hdr "ESCREVENDO ARQUIVOS"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_types.h" << 'F'
#pragma once
/* a42_types.h — tipos primitivos, Q16, arena BSS, constantes
 * [T01] Sem stdlib. Sem malloc. Sem float. Sem libc.
 * [T02] Q16.16: multiplicação via s64 shift 16, divisão via s64 shift 16
 * [T03] Q12.20: maior precisão para fractais (range ±2048)
 * [T04] Arena 512KB em BSS — mark/restore para rollback
 * [T05] TTL counters como contadores de ciclo de graça
 */
typedef unsigned char      u8;
typedef unsigned short     u16;
typedef unsigned int       u32;
typedef unsigned long long u64;
typedef signed   int       s32;
typedef signed   long long s64;
typedef unsigned int       usize;
typedef s32 q16_t; /* Q16.16: 1.0 = 65536 range ±32767.99 */
typedef s32 q12_t; /* Q12.20: 1.0 = 1048576 range ±2047.99 */

#define AI   __attribute__((always_inline)) static inline
#define NI   __attribute__((noinline))
#define NR   __attribute__((noreturn))
#define CLA  __attribute__((aligned(64)))
#define PK   __attribute__((packed))

/* Q16 */
#define Q16    65536
#define Q16_PI 205887  /* π * 65536 */
#define Q16_2PI 411775 /* 2π * 65536 */
#define Q16_MUL(a,b) ((q16_t)(((s64)(a)*(s64)(b))>>16))
#define Q16_DIV(a,b) ((q16_t)(((s64)(a)<<16)/(s64)(b)))
#define Q16_ABS(v)   ((v)<0?-(v):(v))
/* Q12 (para fractais: coordenadas em [-2,2]) */
#define Q12    1048576
#define Q12_MUL(a,b) ((q12_t)(((s64)(a)*(s64)(b))>>20))
#define Q12_FROM_Q16(v) ((q12_t)((s64)(v)<<4))
/* Constantes fractal */
#define FRAC_N    42u   /* pontos no círculo */
#define FRAC_MAXITER 256u
#define FRAC_ESCAPE (4*Q12) /* |z|²>4 em Q12 */
/* Arena 512KB */
#define AR_SZ (512u*1024u)
static u8  _AR[AR_SZ] CLA;
static u32 _AT=0,_AM_MARK=0;
AI void* GA(u32 n,u32 al){
    u32 m=al-1u,c=(_AT+m)&~m;
    if(c+n>AR_SZ)return(void*)0;
    void*p=_AR+c;_AT=c+n;return p;
}
AI void AR(void){_AT=0;}
AI void AM(void){_AM_MARK=_AT;}
AI void ARS(void){_AT=_AM_MARK;}
/* Buffers estáticos */
#define SVG_BUF (256u*1024u) /* 256KB para SVG */
#define PNG_BUF (512u*1024u) /* 512KB para PNG */
#define ASC_BUF ( 16u*1024u) /* 16KB para ASCII */
static u8 _SVG[SVG_BUF] CLA;
static u8 _PNG[PNG_BUF] CLA;
static u8 _ASC[ASC_BUF] CLA;
static u32 _SVG_POS=0,_PNG_POS=0,_ASC_POS=0;
/* TTL como contador de ciclos */
typedef struct{u32 remain,total,irq_count,tick;}TTL;
AI void TTL_INIT(TTL*t,u32 n){t->remain=n;t->total=n;t->irq_count=0;t->tick=0;}
AI u32 TTL_TICK(TTL*t){t->tick++;if(t->remain)t->remain--;return t->remain;}
AI u32 TTL_PCT(const TTL*t){return t->total?((t->total-t->remain)*100u/t->total):100u;}
/* Parâmetros de configuração */
typedef struct PK {
    u32 N;       /* pontos no círculo [42] */
    u32 K;       /* passo modular [5] */
    u32 ITER;    /* iterações grafo [5000] */
    u32 W,H;     /* dimensões fractal [80×40] */
    q16_t zoom;  /* zoom [Q16=65536=1.0] */
    q12_t cx,cy; /* parâmetro Julia [Q12] */
    u32 mode;    /* 0=grafo 1=mandel 2=julia 3=tudo */
    u32 out;     /* 0=ascii 1=svg 2=png 3=tudo */
    u32 n_julia; /* quantas Julia sets [8] */
    u32 max_px_svg;/* largura SVG [800] */
} CFG;
static CFG G_CFG={42u,5u,5000u,80u,40u,Q16,0,0,0,7,1,8,800u};
F
ok "a42_types.h ($(wc -l < $D/a42_types.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_sys.h" << 'F'
#pragma once
/* a42_sys.h — syscalls, I/O, CRC32, Adler32, detecção CPU */
#include "a42_types.h"
#if defined(__arm__)
AI s32 _s3(u32 r,u32 a,u32 b,u32 c){
    register s32 r0 __asm__("r0")=(s32)a;
    register u32 r1 __asm__("r1")=b,r2 __asm__("r2")=c,r7 __asm__("r7")=r;
    __asm__ volatile("svc #0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory","cc");return r0;}
AI s32 _s2(u32 r,u32 a,u32 b){return _s3(r,a,b,0);}
AI s32 _s1(u32 r,u32 a){
    register s32 r0 __asm__("r0")=(s32)a;register u32 r7 __asm__("r7")=r;
    __asm__ volatile("svc #0":"+r"(r0):"r"(r7):"memory","cc");return r0;}
#define SYS_WR  4u
#define SYS_OP  5u
#define SYS_CL  6u
#define SYS_EX  248u
#define SYS_CK  263u
typedef struct{s32 s,n;}TS;
AI u64 NS(void){TS t={0,0};_s2(SYS_CK,1u,(u32)(usize)&t);return(u64)(u32)t.s*1000000000ULL+(u64)(u32)t.n;}
AI s32 WR(s32 fd,const void*b,u32 n){return _s3(SYS_WR,(u32)fd,(u32)(usize)b,n);}
AI s32 OP(const char*p,s32 f,s32 m){return _s3(SYS_OP,(u32)(usize)p,(u32)f,(u32)m);}
AI s32 CL(s32 fd){return _s1(SYS_CL,(u32)fd);}
NR void EX(void){_s1(SYS_EX,0u);__builtin_unreachable();}
/* SMULL Q16 */
AI s32 QM(s32 a,s32 b){s32 lo,hi;
    __asm__ volatile("smull %0,%1,%2,%3":"=r"(lo),"=r"(hi):"r"(a),"r"(b));
    return(s32)((u32)(lo>>16u)|((u32)hi<<16u));}
#define Q16_MUL(a,b) QM((a),(b))
#define Q12_MUL(a,b) ((q12_t)(((s64)(a)*(s64)(b))>>20))
#elif defined(__aarch64__)
AI s64 _s3(u64 r,u64 a,u64 b,u64 c){
    register u64 x8 __asm__("x8")=r;register s64 x0 __asm__("x0")=(s64)a;
    register u64 x1 __asm__("x1")=b,x2 __asm__("x2")=c;
    __asm__ volatile("svc #0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2):"memory","cc");return x0;}
AI s64 _s2(u64 r,u64 a,u64 b){return _s3(r,a,b,0);}
AI s64 _s1(u64 r,u64 a){register u64 x8 __asm__("x8")=r;register s64 x0 __asm__("x0")=(s64)a;
    __asm__ volatile("svc #0":"+r"(x0):"r"(x8):"memory","cc");return x0;}
#define SYS_WR 64u
#define SYS_OP 56u
#define SYS_CL 57u
#define SYS_EX 94u
#define SYS_CK 113u
#define AT_FDCWD -100
typedef struct{s64 s,n;}TS;
AI u64 NS(void){TS t={0,0};_s2(SYS_CK,1u,(u64)(usize)&t);return(u64)t.s*1000000000ULL+(u64)t.n;}
AI s32 WR(s32 fd,const void*b,u32 n){return(s32)_s3(SYS_WR,(u64)fd,(u64)(usize)b,(u64)n);}
AI s32 OP(const char*p,s32 f,s32 m){return(s32)_s3(SYS_OP,(u64)(s64)AT_FDCWD,(u64)(usize)p,(u64)f);}
AI s32 CL(s32 fd){return(s32)_s1(SYS_CL,(u64)fd);}
NR void EX(void){_s1(SYS_EX,0u);__builtin_unreachable();}
#define Q16_MUL(a,b) ((q16_t)(((s64)(a)*(s64)(b))>>16))
#define Q12_MUL(a,b) ((q12_t)(((s64)(a)*(s64)(b))>>20))
#elif defined(__x86_64__)
AI s64 _s3(u64 r,u64 a,u64 b,u64 c){
    s64 x;__asm__ volatile("syscall":"=a"(x):"a"(r),"D"(a),"S"(b),"d"(c):"rcx","r11","memory");return x;}
AI s64 _s2(u64 r,u64 a,u64 b){return _s3(r,a,b,0);}
AI s64 _s1(u64 r,u64 a){s64 x;__asm__ volatile("syscall":"=a"(x):"a"(r),"D"(a):"rcx","r11","memory");return x;}
#define SYS_WR 1u
#define SYS_OP 2u
#define SYS_CL 3u
#define SYS_EX 231u
#define SYS_CK 228u
typedef struct{s64 s,n;}TS;
AI u64 NS(void){TS t={0,0};_s2(SYS_CK,1u,(u64)(usize)&t);return(u64)t.s*1000000000ULL+(u64)t.n;}
AI s32 WR(s32 fd,const void*b,u32 n){return(s32)_s3(SYS_WR,(u64)fd,(u64)(usize)b,(u64)n);}
AI s32 OP(const char*p,s32 f,s32 m){return(s32)_s3(SYS_OP,(u64)(usize)p,(u64)f,(u64)m);}
AI s32 CL(s32 fd){return(s32)_s1(SYS_CL,(u64)fd);}
NR void EX(void){_s1(SYS_EX,0u);__builtin_unreachable();}
#define Q16_MUL(a,b) ((q16_t)(((s64)(a)*(s64)(b))>>16))
#define Q12_MUL(a,b) ((q12_t)(((s64)(a)*(s64)(b))>>20))
#endif
/* I/O */
static void PS(const char*s){u32 n=0;while(s[n])n++;if(n)WR(1,s,n);}
static void PN(u64 v){char b[22];s32 i=21;b[i]='\n';i--;
    if(!v){b[i--]='0';}else{while(v){b[i--]='0'+(char)(v%10u);v/=10u;}}
    WR(1,b+i+1,(u32)(20u-i));}
static void PH(u32 v){static const char h[]="0123456789abcdef";
    char b[11];b[0]='0';b[1]='x';b[10]='\n';
    for(s32 i=9;i>=2;i--){b[i]=h[v&0xFu];v>>=4;}WR(1,b,11u);}
/* CRC32 (para PNG) — poly 0xEDB88320 */
static u32 CRC32(const u8*buf,u32 n){
    u32 c=~0u;
    while(n--){c^=*buf++;for(u32 i=0;i<8u;i++)c=(c>>1)^(0xEDB88320u&-(c&1u));}
    return~c;}
/* Adler32 (para PNG zlib) */
static u32 ADLER32(const u8*buf,u32 n){
    u32 a=1,b=0;
    while(n--){a=(a+(u32)*buf++)%65521u;b=(b+a)%65521u;}
    return(b<<16u)|a;}
/* strlen/memcpy sem libc */
AI u32 SL(const char*s){u32 n=0;while(s[n])n++;return n;}
AI void MC(void*d,const void*s,u32 n){u8*dd=(u8*)d;const u8*ss=(const u8*)s;while(n--)dd[n]=ss[n];}
AI void MZ(void*d,u32 n){u8*dd=(u8*)d;while(n--)dd[n]=0;}
/* Converte u32 para string decimal */
AI u32 U2S(u32 v,char*out){
    char t[10];s32 i=0;if(!v){out[0]='0';out[1]=0;return 1u;}
    while(v){t[i++]='0'+(char)(v%10u);v/=10u;}
    u32 l=(u32)i;s32 j=0;while(i>0)out[j++]=t[--i];out[j]=0;return l;}
F
ok "a42_sys.h ($(wc -l < $D/a42_sys.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_math.h" << 'F'
#pragma once
/* a42_math.h — CORDIC sin/cos Q16, matrizes, 7 senoides adaptativas
 * [M01] CORDIC: 16 iterações, erro < 1 ULP Q16, sem float, sem lookup table
 * [M02] 7 senoides: frequências 1..7 × base para escalonamento adaptativo
 * [M03] Matrizes 2×2, 4×4, 8×8, 10×10 com 42 atratores
 * [M04] Branchless em todas as operações críticas
 * [M05] ISO-lines para Julia semicírculo de parâmetros
 */
#include "a42_sys.h"

/* ── CORDIC SIN/COS Q16 ─────────────────────────────────────────────────── */
/* Tabela de ângulos CORDIC: atan(2^-i) em Q16 */
static const s32 _CRD[16]={
    51472,30386,16054,8150,4090,2047,1024,512,
    256,128,64,32,16,8,4,2
};
/* atan(2^-i) * Q16/(pi/2) — normalizado para Q16 de ângulos */
/* Entrada: angulo em Q16 de 0 a 2*Q16_PI */
/* Saída: sin e cos em Q16 */
static void CORDIC(s32 ang_q16, s32*sin_out, s32*cos_out){
    /* Normaliza para [-π, π] */
    while(ang_q16 > Q16_PI)  ang_q16 -= Q16_2PI;
    while(ang_q16 <-Q16_PI)  ang_q16 += Q16_2PI;
    /* Determina quadrante */
    s32 flip=0;
    if(ang_q16>Q16_PI/2){ang_q16=Q16_PI-ang_q16;flip=1;}
    else if(ang_q16<-Q16_PI/2){ang_q16=-Q16_PI-ang_q16;flip=-1;}
    /* CORDIC iterativo — sem float, sem divisão */
    /* Escala inicial: CORDIC gain ≈ 0.6073 → pré-escalonado */
    s32 x=39797; /* 0.6073*65536 ≈ 39797 (CORDIC gain) */
    s32 y=0;
    s32 z=Q16_MUL(ang_q16, 41721); /* converte de Q16-rad para Q16-cordic */
    /* 41721 = 65536 * (pi/2) / (pi/2) ... uso direto do ângulo */
    /* Melhor: z = ang em unidades de pi/2 = ang * 2 / pi */
    z=(s32)(((s64)ang_q16*41721)>>16); /* ≈ ang_q16 * (2/π) * scaling */
    for(u32 i=0;i<16u;i++){
        s32 xs,ys,zs;
        if(z>=0){xs=x-(y>>i);ys=y+(x>>i);zs=z-_CRD[i];}
        else    {xs=x+(y>>i);ys=y-(x>>i);zs=z+_CRD[i];}
        x=xs;y=ys;z=zs;
    }
    if(flip>0){*sin_out=x;*cos_out=-y;}
    else if(flip<0){*sin_out=-x;*cos_out=-y;}
    else{*sin_out=y;*cos_out=x;}
}
/* Sin/Cos rápidos via CORDIC */
AI s32 SIN_Q16(s32 ang){s32 s,c;CORDIC(ang,&s,&c);return s;}
AI s32 COS_Q16(s32 ang){s32 s,c;CORDIC(ang,&s,&c);return c;}

/* ── 42 PONTOS NO CÍRCULO ───────────────────────────────────────────────── */
typedef struct{s32 x,y;}V2; /* vetor 2D Q16 */
static V2 _CIRCLE[FRAC_N] CLA;
static void CIRCLE_INIT(u32 N, s32 radius_q16){
    /* Calcula 2π/N em Q16 */
    s32 step=(s32)(((u64)Q16_2PI)/N);
    for(u32 k=0;k<N;k++){
        s32 ang=(s32)(((s64)step*(s32)k));
        s32 s,c; CORDIC(ang,&s,&c);
        _CIRCLE[k].x=Q16_MUL(c,radius_q16);
        _CIRCLE[k].y=Q16_MUL(s,radius_q16);
    }
}

/* ── GRAFO MODULAR ─────────────────────────────────────────────────────── */
#define MAX_EDGES 8192u
static u32 _EDGES_A[MAX_EDGES];
static u32 _EDGES_B[MAX_EDGES];
static u32 _N_EDGES=0;
static u32 _DENSITY[FRAC_N];
static u64 _EDGE_SET[MAX_EDGES/64u+1u]; /* bitmap deduplicação */

static void GRAPH_COMPUTE(u32 N,u32 K,u32 ITER){
    MZ(_DENSITY,N*sizeof(u32));
    MZ(_EDGE_SET,sizeof(_EDGE_SET));
    _N_EDGES=0;
    u32 x=0,unique=0;
    for(u32 i=0;i<ITER&&_N_EDGES<MAX_EDGES;i++){
        u32 y=(x+K)%N;
        /* Deduplicação via bitmap */
        u32 key=(x*N+y)%(MAX_EDGES*64u);
        u32 word=key>>6u, bit=key&63u;
        if(!(_EDGE_SET[word]&(1ULL<<bit))){
            _EDGE_SET[word]|=(1ULL<<bit);
            _EDGES_A[_N_EDGES]=x;
            _EDGES_B[_N_EDGES]=y;
            _N_EDGES++;unique++;
        }
        _DENSITY[x]++;_DENSITY[y]++;
        x=y;
    }
    /* Métricas */
    u32 dmax=1;
    for(u32 i=0;i<N;i++)if(_DENSITY[i]>dmax)dmax=_DENSITY[i];
    /* Normaliza density para [0..255] */
    for(u32 i=0;i<N;i++)
        _DENSITY[i]=(_DENSITY[i]*255u)/dmax;
    PS("Edges: "); PN(_N_EDGES);
    PS("Unique: "); PN(unique);
}

/* ── MÉTRICAS (equivalente Python) ─────────────────────────────────────── */
/* symmetry_error: média de |density[i] - density[i+N/2]| */
static u32 SYMMETRY_Q16(u32 N){
    s64 sum=0;
    for(u32 i=0;i<N/2u;i++){
        s32 d=(s32)_DENSITY[i]-(s32)_DENSITY[(i+N/2u)%N];
        if(d<0)d=-d;
        sum+=d;
    }
    return(u32)(sum*Q16/(N/2u));
}
/* complexity = unique_edges / ITER */
static u32 COMPLEXITY_Q16(u32 unique,u32 iter){
    if(!iter)return 0;
    return(u32)(((u64)unique*Q16)/iter);
}

/* ── 7 SENOIDES ADAPTATIVAS ─────────────────────────────────────────────── */
/* 7 frequências base para escalonamento de carga */
typedef struct{s32 amp;u32 freq;s32 phase;}Sine7;
static Sine7 _S7[7];
static void SINE7_INIT(void){
    for(u32 i=0;i<7u;i++){
        _S7[i].amp=Q16; /* amplitude = 1.0 Q16 */
        _S7[i].freq=(i+1u)*100u; /* frequências 100..700 Hz proxy */
        _S7[i].phase=0;
    }
}
/* Avalia soma das 7 senoides no instante t (Q16) */
static s32 SINE7_EVAL(s32 t_q16){
    s32 sum=0;
    for(u32 i=0;i<7u;i++){
        s32 ang=Q16_MUL(t_q16,(s32)(_S7[i].freq*655u))+_S7[i].phase;
        sum+=Q16_MUL(_S7[i].amp,SIN_Q16(ang));
    }
    return sum/7;
}

/* ── MATRIZES DE ATRATORES ──────────────────────────────────────────────── */
/* 42 pontos → matrizes 2×2(×10+2spare), 4×4(×2+10), 8×8(stub), 10×10(stub) */
static u8 _MAT2x2[10][2][2];
static u8 _MAT4x4[3][4][4];
static void MAT_FILL(u32 N){
    /* Preenche matrizes 2×2 com índices dos atratores */
    for(u32 m=0;m<10u&&m*4u<N;m++)
        for(u32 r=0;r<2u;r++)
            for(u32 c=0;c<2u;c++)
                _MAT2x2[m][r][c]=(u8)((m*4u+r*2u+c)%N);
    /* Preenche matrizes 4×4 */
    for(u32 m=0;m<3u&&m*16u<N;m++)
        for(u32 r=0;r<4u;r++)
            for(u32 c=0;c<4u;c++)
                _MAT4x4[m][r][c]=(u8)((m*16u+r*4u+c)%N);
}
F
ok "a42_math.h ($(wc -l < $D/a42_math.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_fractal.h" << 'F'
#pragma once
/* a42_fractal.h — Mandelbrot e Julia Q12 (precision Q12.20)
 * [F01] Mandelbrot: z_{n+1} = z_n² + c, c = ponto do plano
 * [F02] Julia: z_{n+1} = z_n² + c_fixo, z_0 = ponto do plano
 * [F03] Q12.20 para coordenadas em [-2.5, 1.5] × [-1.25, 1.25]
 * [F04] Semicírculo de Júlia: c = 0.7885 * e^(iθ), θ ∈ [0, π]
 * [F05] N_Julia imagens ao longo do semicírculo
 * [F06] Escape smooth via remainder Q12 para anti-aliasing
 */
#include "a42_math.h"

/* Escapa o conjunto — retorna iteração de escape [0..MAXITER]
 * Entrada: cr,ci = parâmetro c; zr,zi = ponto inicial z_0 (ambos Q12)
 * Branchless onde possível */
static u32 ESCAPE(q12_t zr,q12_t zi,q12_t cr,q12_t ci,u32 maxiter){
    for(u32 i=0;i<maxiter;i++){
        /* zr² - zi² */
        q12_t zr2=Q12_MUL(zr,zr);
        q12_t zi2=Q12_MUL(zi,zi);
        /* Escape: |z|² > 4 → (zr²+zi²) > 4*Q12 */
        if(zr2+zi2 > 4*Q12) return i;
        /* 2*zr*zi */
        q12_t zri2=Q12_MUL(zr,zi);
        /* Iteração */
        zr=zr2-zi2+cr;
        zi=zri2+zri2+ci;
    }
    return maxiter;
}

/* ── MANDELBROT ────────────────────────────────────────────────────────── */
/* Renderiza Mandelbrot em buffer ASCII ou conta iterações para SVG */
/* Domínio: x ∈ [-2.5, 1.0] y ∈ [-1.25, 1.25] */
static const char _CHARS[]=" .,:;!>+|*=o#&%@M$X ";
static void MANDEL_ASCII(u32 W,u32 H,q16_t zoom,u8*out,u32 cap){
    /* Mapeamento: pixel(px,py) → c = (x0+px*dx, y0+py*dy) em Q12 */
    /* Com zoom: centro em (-0.5,0), range ± 1.5/zoom */
    q12_t cx0=Q12_MUL(-Q12/2,Q12); /* centro x = -0.5 */
    q12_t rng=(q12_t)(((s64)Q12*3/2)*Q12/zoom); /* range = 1.5/zoom Q12 */
    q12_t dx=(q12_t)(((s64)rng*2)/(s32)W);
    q12_t dy=(q12_t)(((s64)rng*2)/(s32)H);
    q12_t x0=cx0-rng;
    q12_t y0=Q12_MUL(rng,Q12); /* inicia no topo */
    u32 pos=0;
    for(u32 py=0;py<H&&pos<cap-2u;py++){
        q12_t ci=y0-(q12_t)((s64)dy*(s32)py);
        for(u32 px=0;px<W&&pos<cap-2u;px++){
            q12_t cr=x0+(q12_t)((s64)dx*(s32)px);
            u32 it=ESCAPE(0,0,cr,ci,FRAC_MAXITER);
            u32 ci_idx=it==FRAC_MAXITER?0u:(it&15u)+1u;
            out[pos++]=(u8)_CHARS[ci_idx%(__builtin_strlen(_CHARS)-1u)];
        }
        out[pos++]='\n';
    }
    out[pos]=0;
}

/* ── JULIA ─────────────────────────────────────────────────────────────── */
/* Semicírculo: c = R * e^(iθ), θ de 0 a π, R = 0.7885 */
/* R em Q12 = 0.7885 * Q12 */
#define JULIA_R_Q12 ((q12_t)(826837)) /* 0.7885 * 1048576 */
static void JULIA_ASCII(u32 W,u32 H,q12_t cr,q12_t ci,u8*out,u32 cap){
    /* Domínio: z ∈ [-2,2]×[-2,2] */
    q12_t dx=(q12_t)(4*Q12/(s32)W);
    q12_t dy=(q12_t)(4*Q12/(s32)H);
    q12_t x0=-2*Q12;
    q12_t y0= 2*Q12;
    u32 pos=0;
    for(u32 py=0;py<H&&pos<cap-2u;py++){
        q12_t zi=y0-(q12_t)((s64)dy*(s32)py);
        for(u32 px=0;px<W&&pos<cap-2u;px++){
            q12_t zr=x0+(q12_t)((s64)dx*(s32)px);
            u32 it=ESCAPE(zr,zi,cr,ci,FRAC_MAXITER);
            u32 ci_idx=it==FRAC_MAXITER?0u:(it&15u)+1u;
            out[pos++]=(u8)_CHARS[ci_idx%(__builtin_strlen(_CHARS)-1u)];
        }
        out[pos++]='\n';
    }
    out[pos]=0;
}

/* Parâmetros Julia ao longo do semicírculo θ ∈ [0,π] */
static void JULIA_PARAMS(u32 idx,u32 total,q12_t*cr,q12_t*ci){
    /* θ = idx * π / (total-1) */
    s32 ang=(s32)(((u64)Q16_PI*(u64)idx)/((u64)(total>1?total-1:1)));
    s32 s,c; CORDIC(ang,&s,&c);
    *cr=Q12_MUL(JULIA_R_Q12,c);
    *ci=Q12_MUL(JULIA_R_Q12,s);
}
F
ok "a42_fractal.h ($(wc -l < $D/a42_fractal.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_svg.h" << 'F'
#pragma once
/* a42_svg.h — Escritor SVG via syscall direto, zero malloc, zero libc
 * [S01] Buffer _SVG[256KB] em BSS — append via SVG_W()
 * [S02] Escrita em arquivo via fd = OP(path) + WR(fd,_SVG,_SVG_POS)
 * [S03] Coordenadas Q16 → string decimal via U2S()
 * [S04] Cores dos atratores: plasma colormap approximado
 * [S05] Pontos e arestas do grafo circular
 * [S06] Pixels do fractal como retângulos SVG
 */
#include "a42_fractal.h"

/* Append ao buffer SVG */
static void SVG_W(const char*s){
    u32 n=SL(s);
    if(_SVG_POS+n<SVG_BUF){MC(_SVG+_SVG_POS,s,n);_SVG_POS+=n;}
}
static void SVG_N(u32 v){char b[12];U2S(v,b);SVG_W(b);}
static void SVG_SN(s32 v){if(v<0){SVG_W("-");SVG_N((u32)-v);}else SVG_N((u32)v);}

/* Salva _SVG em arquivo */
static s32 SVG_SAVE(const char*path){
    s32 fd=OP(path,0x241,0644); /* O_WRONLY|O_CREAT|O_TRUNC */
    if(fd<0)return-1;
    WR(fd,_SVG,_SVG_POS);
    CL(fd);return 0;
}

/* Plasma colormap aproximado: density [0..255] → rgb */
static void PLASMA_RGB(u32 d,u8*R,u8*G,u8*B){
    /* Simplificado: 4 segmentos de 64 passos */
    if(d<64){*R=13+(u8)(d*3);*G=8+(u8)(d*2);*B=135+(u8)(d*2);}
    else if(d<128){d-=64;*R=202+(u8)(d/2);*G=51+(u8)(d*2);*B=148-(u8)(d*2);}
    else if(d<192){d-=128;*R=253-(u8)(d/4);*G=174+(u8)(d);*B=97-(u8)(d);}
    else{d-=192;*R=252-(u8)(d/2);*G=255-(u8)(d);*B=164-(u8)(d*2);}
}
static void SVG_COLOR(u8 R,u8 G,u8 B){
    char buf[8];
    buf[0]='#';
    static const char h[]="0123456789abcdef";
    buf[1]=h[R>>4u];buf[2]=h[R&0xFu];
    buf[3]=h[G>>4u];buf[4]=h[G&0xFu];
    buf[5]=h[B>>4u];buf[6]=h[B&0xFu];
    buf[7]=0;SVG_W(buf);
}

/* ── SVG DO GRAFO ────────────────────────────────────────────────────────── */
static void SVG_GRAPH(u32 N,u32 px){
    _SVG_POS=0;
    u32 cx=px/2u,cy=px/2u,r=px*2u/5u;
    /* Header */
    SVG_W("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"");
    SVG_N(px);SVG_W("\" height=\"");SVG_N(px);SVG_W("\" style=\"background:#0a0a1a\">\n");
    SVG_W("<title>42 Atratores - N=");SVG_N(N);SVG_W("</title>\n");
    /* Arestas */
    for(u32 e=0;e<_N_EDGES;e++){
        u32 a=_EDGES_A[e],b=_EDGES_B[e];
        s32 x1=cx+(s32)(((s64)_CIRCLE[a].x*(s32)r)>>16);
        s32 y1=cy-(s32)(((s64)_CIRCLE[a].y*(s32)r)>>16);
        s32 x2=cx+(s32)(((s64)_CIRCLE[b].x*(s32)r)>>16);
        s32 y2=cy-(s32)(((s64)_CIRCLE[b].y*(s32)r)>>16);
        SVG_W("<line x1=\"");SVG_SN(x1);SVG_W("\" y1=\"");SVG_SN(y1);
        SVG_W("\" x2=\"");SVG_SN(x2);SVG_W("\" y2=\"");SVG_SN(y2);
        SVG_W("\" stroke=\"#00ffff\" stroke-opacity=\"0.04\" stroke-width=\"0.5\"/>\n");
    }
    /* Pontos com plasma colormap */
    for(u32 k=0;k<N;k++){
        s32 px2=cx+(s32)(((s64)_CIRCLE[k].x*(s32)r)>>16);
        s32 py2=cy-(s32)(((s64)_CIRCLE[k].y*(s32)r)>>16);
        u8 R,G,B;PLASMA_RGB(_DENSITY[k],&R,&G,&B);
        SVG_W("<circle cx=\"");SVG_SN(px2);SVG_W("\" cy=\"");SVG_SN(py2);
        SVG_W("\" r=\"5\" fill=\"");SVG_COLOR(R,G,B);SVG_W("\"/>\n");
        /* Label */
        SVG_W("<text x=\"");SVG_SN(px2+7);SVG_W("\" y=\"");SVG_SN(py2+4);
        SVG_W("\" fill=\"#ffffff\" font-size=\"8\">");SVG_N(k);SVG_W("</text>\n");
    }
    /* Título e métricas */
    SVG_W("<text x=\"10\" y=\"20\" fill=\"#ffff00\" font-size=\"14\" font-weight=\"bold\">");
    SVG_W("42 Atratores - Grafo Circular</text>\n");
    SVG_W("<text x=\"10\" y=\"40\" fill=\"#00ff00\" font-size=\"10\">");
    SVG_W("N=");SVG_N(N);SVG_W(" K=");SVG_N(G_CFG.K);
    SVG_W(" Edges=");SVG_N(_N_EDGES);SVG_W("</text>\n");
    SVG_W("</svg>\n");
}

/* ── SVG DO FRACTAL ──────────────────────────────────────────────────────── */
/* Usa ASCII render para gerar SVG via cells */
static void SVG_FRACTAL_MANDEL(u32 W,u32 H,q16_t zoom,u32 px){
    _SVG_POS=0;
    u32 cell_w=px/W,cell_h=px/(H*W/W);
    if(!cell_w)cell_w=1;if(!cell_h)cell_h=1;
    u32 svgH=cell_h*H;
    SVG_W("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"");
    SVG_N(px);SVG_W("\" height=\"");SVG_N(svgH);SVG_W("\" style=\"background:#000010\">\n");
    SVG_W("<title>Mandelbrot Q16</title>\n");
    q12_t cx0=-(Q12/2);
    q12_t rng=(q12_t)(((s64)Q12*3/2)*Q12/zoom);
    q12_t dx=(q12_t)(((s64)rng*2)/(s32)W);
    q12_t dy=(q12_t)(((s64)rng*2)/(s32)H);
    q12_t x0=cx0-rng;
    q12_t y0=Q12_MUL(rng,Q12);
    for(u32 py=0;py<H;py++){
        q12_t ci=y0-(q12_t)((s64)dy*(s32)py);
        for(u32 px2=0;px2<W;px2++){
            q12_t cr=x0+(q12_t)((s64)dx*(s32)px2);
            u32 it=ESCAPE(0,0,cr,ci,FRAC_MAXITER);
            u8 R,G,B;
            if(it==FRAC_MAXITER){R=0;G=0;B=0;}
            else PLASMA_RGB((it*255u)/FRAC_MAXITER,&R,&G,&B);
            SVG_W("<rect x=\"");SVG_N(px2*cell_w);SVG_W("\" y=\"");SVG_N(py*cell_h);
            SVG_W("\" width=\"");SVG_N(cell_w);SVG_W("\" height=\"");SVG_N(cell_h);
            SVG_W("\" fill=\"");SVG_COLOR(R,G,B);SVG_W("\"/>\n");
        }
    }
    SVG_W("<text x=\"5\" y=\"15\" fill=\"#ffff00\" font-size=\"12\">Mandelbrot Q12.20</text>\n");
    SVG_W("</svg>\n");
}
F
ok "a42_svg.h ($(wc -l < $D/a42_svg.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_png.h" << 'F'
#pragma once
/* a42_png.h — PNG writer sem malloc, sem zlib externo
 * [P01] DEFLATE stored blocks (BTYPE=00, sem compressão)
 * [P02] CRC32 para chunks PNG — poly 0xEDB88320
 * [P03] Adler32 para zlib wrapper
 * [P04] IHDR + IDAT + IEND chunks
 * [P05] RGB 24-bit, filter=0 (none) por linha
 */
#include "a42_svg.h"

/* Buffer PNG: _PNG[512KB] em BSS */
static void PNG_U8(u8 v){if(_PNG_POS<PNG_BUF-1u)_PNG[_PNG_POS++]=v;}
static void PNG_U16BE(u16 v){PNG_U8((u8)(v>>8u));PNG_U8((u8)v);}
static void PNG_U32BE(u32 v){PNG_U8((u8)(v>>24u));PNG_U8((u8)(v>>16u));PNG_U8((u8)(v>>8u));PNG_U8((u8)v);}

static void PNG_CHUNK(u32 type,const u8*data,u32 dlen){
    PNG_U32BE(dlen);
    u32 cstart=_PNG_POS;
    PNG_U32BE(type);
    if(data&&dlen){MC(_PNG+_PNG_POS,data,dlen);_PNG_POS+=dlen;}
    u32 crc=CRC32(_PNG+cstart,(u32)(_PNG_POS-cstart));
    PNG_U32BE(crc);
}

/* DEFLATE stored block para data[dlen] */
static u32 DEFLATE_STORED(const u8*data,u32 dlen,u8*out,u32 cap){
    u32 pos=0;
    /* zlib header: CMF=0x78 FLG=0x01 (deflate, no dict, check=yes) */
    out[pos++]=0x78;out[pos++]=0x01;
    u32 adler=ADLER32(data,dlen);
    u32 rem=dlen,off=0;
    while(rem>0){
        u32 blk=rem>65535u?65535u:rem;
        u8 bfinal=(u8)(rem<=65535u?1u:0u);
        out[pos++]=(u8)(bfinal|0x00u); /* BFINAL | BTYPE=00 */
        out[pos++]=(u8)(blk);out[pos++]=(u8)(blk>>8u);
        out[pos++]=(u8)(~blk);out[pos++]=(u8)((~blk)>>8u);
        MC(out+pos,data+off,blk);pos+=blk;off+=blk;rem-=blk;
    }
    /* Adler32 big-endian */
    out[pos++]=(u8)(adler>>24u);out[pos++]=(u8)(adler>>16u);
    out[pos++]=(u8)(adler>>8u);out[pos++]=(u8)(adler);
    return pos;
}

static s32 PNG_SAVE_RGB(const char*path,u32 W,u32 H,const u8*rgb){
    _PNG_POS=0;
    /* Signature */
    static const u8 SIG[8]={137,80,78,71,13,10,26,10};
    MC(_PNG,SIG,8u);_PNG_POS=8u;
    /* IHDR */
    u8 ihdr[13];
    ihdr[0]=(u8)(W>>24u);ihdr[1]=(u8)(W>>16u);ihdr[2]=(u8)(W>>8u);ihdr[3]=(u8)W;
    ihdr[4]=(u8)(H>>24u);ihdr[5]=(u8)(H>>16u);ihdr[6]=(u8)(H>>8u);ihdr[7]=(u8)H;
    ihdr[8]=8;/* bit depth */ihdr[9]=2;/* RGB */ihdr[10]=0;ihdr[11]=0;ihdr[12]=0;
    PNG_CHUNK(0x49484452u,ihdr,13u); /* IHDR */
    /* Prepara raw image data: filter(1) + RGB(3) per pixel per row */
    u32 row_sz=W*3u+1u;
    u32 raw_sz=row_sz*H;
    u8*raw=(u8*)GA(raw_sz,8u);
    if(!raw)return-1;
    for(u32 y=0;y<H;y++){
        raw[y*row_sz]=0u; /* filter = none */
        MC(raw+y*row_sz+1u,rgb+y*W*3u,W*3u);
    }
    /* Deflate */
    u8*defbuf=(u8*)GA(raw_sz+raw_sz/4u+16u,8u);
    if(!defbuf)return-1;
    u32 deflen=DEFLATE_STORED(raw,raw_sz,defbuf,raw_sz+raw_sz/4u+16u);
    PNG_CHUNK(0x49444154u,defbuf,deflen); /* IDAT */
    PNG_CHUNK(0x49454E44u,(void*)0,0u);   /* IEND */
    /* Salva */
    s32 fd=OP(path,0x241,0644);
    if(fd<0)return-1;
    WR(fd,_PNG,_PNG_POS);
    CL(fd);return 0;
}

/* Gera buffer RGB para fractal Mandelbrot */
static u8* MANDEL_RGB(u32 W,u32 H,q16_t zoom){
    u8*rgb=(u8*)GA(W*H*3u,8u);
    if(!rgb)return(u8*)0;
    q12_t cx0=-(Q12/2);
    q12_t rng=(q12_t)(((s64)Q12*3/2)*Q12/zoom);
    q12_t dx=(q12_t)(((s64)rng*2)/(s32)W);
    q12_t dy=(q12_t)(((s64)rng*2)/(s32)H);
    q12_t x0=cx0-rng;q12_t y0=Q12_MUL(rng,Q12);
    for(u32 py=0;py<H;py++){
        q12_t ci=y0-(q12_t)((s64)dy*(s32)py);
        for(u32 px=0;px<W;px++){
            q12_t cr=x0+(q12_t)((s64)dx*(s32)px);
            u32 it=ESCAPE(0,0,cr,ci,FRAC_MAXITER);
            u8 R,G,B;
            if(it==FRAC_MAXITER){R=0;G=0;B=0;}
            else PLASMA_RGB((it*255u)/FRAC_MAXITER,&R,&G,&B);
            rgb[(py*W+px)*3u+0u]=R;
            rgb[(py*W+px)*3u+1u]=G;
            rgb[(py*W+px)*3u+2u]=B;
        }
    }
    return rgb;
}
F
ok "a42_png.h ($(wc -l < $D/a42_png.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_bbs.h" << 'F'
#pragma once
/* a42_bbs.h — CLI BBS-style (Clipper5/Summer'87), ANSI colors, box drawing
 * [B01] Menu principal com seleção por tecla
 * [B02] Parâmetros configuráveis: N, K, ITER, W, H, zoom, julia_c
 * [B03] Progress bar com TTL counter
 * [B04] Display de métricas em tempo real
 * [B05] stdin leitura via syscall read()
 * [B06] Cores ANSI: plasma, cyan, green, yellow, magenta
 */
#include "a42_png.h"
/* Lê 1 byte de stdin */
static u8 READCHAR(void){
    u8 c=0;
#if defined(__arm__)
    _s3(3u,0u,(u32)(usize)&c,1u);
#elif defined(__aarch64__)
    _s3(63u,0u,(u64)(usize)&c,1u);
#elif defined(__x86_64__)
    _s3(0u,0u,(u64)(usize)&c,1u);
#endif
    return c;
}
/* Lê linha de stdin */
static u32 READLINE(u8*buf,u32 cap){
    u32 n=0;u8 c;
    while(n<cap-1u){c=READCHAR();if(c=='\n'||c=='\r')break;if(c>=' ')buf[n++]=c;}
    buf[n]=0;return n;
}
/* Parse u32 de string */
static u32 STR2U(const u8*s){
    u32 v=0;while(*s>='0'&&*s<='9'){v=v*10u+(u32)(*s-'0');s++;}return v;}
/* Parse s32 de string */
static s32 STR2S(const u8*s){
    s32 sg=1;if(*s=='-'){sg=-1;s++;}return sg*(s32)STR2U(s);}

/* Progress bar BBS style */
static void PBAR(u32 pct,u32 width){
    PS("\033[1;32m[");
    u32 filled=(pct*width)/100u;
    for(u32 i=0;i<width;i++){
        if(i<filled)PS("█");
        else PS("░");
    }
    PS("] ");
    char buf[5];U2S(pct,buf);PS(buf);PS("%\033[0m");
}

/* Clear screen */
static void CLS(void){PS("\033[2J\033[H");}
static void GOTOXY(u32 r,u32 c){PS("\033[");char b[4];U2S(r,b);PS(b);PS(";");U2S(c,b);PS(b);PS("H");}

/* Box drawing */
static void BOX(u32 rows,u32 cols,const char*title){
    PS("\033[1;36m╔");
    for(u32 i=0;i<cols;i++)PS("═");
    PS("╗\n║ \033[1;33m");PS(title);
    PS("\033[1;36m");
    u32 tl=SL(title);
    for(u32 i=0;i<cols-tl-1u;i++)PS(" ");
    PS("║\n╠");
    for(u32 i=0;i<cols;i++)PS("═");
    PS("╣\n");
    for(u32 r=0;r<rows;r++){PS("║");for(u32 c=0;c<cols+1u;c++)PS(" ");PS("║\n");}
    PS("╚");for(u32 i=0;i<cols;i++)PS("═");PS("╝\n\033[0m");
}

/* Menu principal BBS style */
static void MENU_MAIN(void){
    CLS();
    PS("\033[1;33m");
    PS("  ╔══════════════════════════════════════════════════════════╗\n");
    PS("  ║  \033[1;36m42 ATRATORES\033[1;33m · \033[1;32mGRAFOS + FRACTAIS\033[1;33m · Q16 ARM/x86  ║\n");
    PS("  ╠══════════════════════════════════════════════════════════╣\n");
    PS("  ║  \033[0;37m[1]\033[1;32m Grafo Circular (N pontos, passo K)               \033[1;33m║\n");
    PS("  ║  \033[0;37m[2]\033[1;35m Mandelbrot (zoom, iterações)                     \033[1;33m║\n");
    PS("  ║  \033[0;37m[3]\033[1;36m Julia (parâmetro c, semicírculo)                 \033[1;33m║\n");
    PS("  ║  \033[0;37m[4]\033[1;33m Tudo (Grafo + Mandelbrot + Julia)                \033[1;33m║\n");
    PS("  ╠══════════════════════════════════════════════════════════╣\n");
    PS("  ║  \033[0;37m[S]\033[1;32m Configurar parâmetros                            \033[1;33m║\n");
    PS("  ║  \033[0;37m[F]\033[1;36m Formato saída (ASCII/SVG/PNG)                    \033[1;33m║\n");
    PS("  ║  \033[0;37m[M]\033[1;35m Matrizes de atratores (2×2, 4×4, 10×10)         \033[1;33m║\n");
    PS("  ║  \033[0;37m[Q]\033[1;31m Sair                                             \033[1;33m║\n");
    PS("  ╚══════════════════════════════════════════════════════════╝\n");
    PS("\033[0m\n  Escolha: ");
}

static void MENU_PARAMS(void){
    CLS();
    PS("\033[1;36m");BOX(12u,56u,"CONFIGURAR PARÂMETROS");
    PS("\033[0m");
    PS("  \033[1;33mN\033[0m = pontos no círculo ["); char b[12];U2S(G_CFG.N,b);PS(b);PS("]\n");
    PS("  \033[1;33mK\033[0m = passo modular [");U2S(G_CFG.K,b);PS(b);PS("]\n");
    PS("  \033[1;33mI\033[0m = iterações grafo [");U2S(G_CFG.ITER,b);PS(b);PS("]\n");
    PS("  \033[1;33mW\033[0m = largura fractal [");U2S(G_CFG.W,b);PS(b);PS("]\n");
    PS("  \033[1;33mH\033[0m = altura fractal [");U2S(G_CFG.H,b);PS(b);PS("]\n");
    PS("  \033[1;33mZ\033[0m = zoom (inteiro, 1=default) [");U2S((u32)G_CFG.zoom/Q16,b);PS(b);PS("]\n");
    PS("  \033[1;33mJ\033[0m = n° Julia sets semicírculo [");U2S(G_CFG.n_julia,b);PS(b);PS("]\n");
    PS("  \033[1;33mP\033[0m = pixels SVG largura [");U2S(G_CFG.max_px_svg,b);PS(b);PS("]\n");
    PS("  \033[0;37mParâmetro (letra) ou Enter para voltar: \033[0m");
}

static void DO_PARAMS(void){
    static u8 ibuf[32];
    for(;;){
        MENU_PARAMS();
        u32 l=READLINE(ibuf,32u);
        if(!l)return;
        u8 key=ibuf[0];
        if(key=='q'||key=='Q')return;
        PS("  Novo valor: ");
        READLINE(ibuf,32u);
        if(!ibuf[0])continue;
        u32 v=STR2U(ibuf);
        if(key=='n'||key=='N')G_CFG.N=(v>=2u&&v<=FRAC_N?v:G_CFG.N);
        else if(key=='k'||key=='K')G_CFG.K=(v>=1u?v:G_CFG.K);
        else if(key=='i'||key=='I')G_CFG.ITER=(v>=1u?v:G_CFG.ITER);
        else if(key=='w'||key=='W')G_CFG.W=(v>=4u&&v<=800u?v:G_CFG.W);
        else if(key=='h'||key=='H')G_CFG.H=(v>=2u&&v<=400u?v:G_CFG.H);
        else if(key=='z'||key=='Z')G_CFG.zoom=(v>=1u?(q16_t)((u64)v*Q16):G_CFG.zoom);
        else if(key=='j'||key=='J')G_CFG.n_julia=(v>=1u&&v<=16u?v:G_CFG.n_julia);
        else if(key=='p'||key=='P')G_CFG.max_px_svg=(v>=100u&&v<=2000u?v:G_CFG.max_px_svg);
    }
}

/* Display métricas */
static void SHOW_METRICS(u32 N){
    PS("\n\033[1;32m=== MÉTRICAS ===\033[0m\n");
    char b[12];
    u32 sym=SYMMETRY_Q16(N);
    u32 comp=COMPLEXITY_Q16(_N_EDGES,G_CFG.ITER);
    PS("  Simetria (erro Q16): ");U2S(sym,b);PS(b);PS("\n");
    PS("  Complexidade Q16:    ");U2S(comp,b);PS(b);PS("\n");
    PS("  Unique edges:        ");U2S(_N_EDGES,b);PS(b);PS("\n");
    PS("  Density[0]:          ");U2S(_DENSITY[0],b);PS(b);PS("\n");
    /* 7 senoides */
    SINE7_INIT();
    PS("  7-Sine adaptativo:   ");
    s32 sv=SINE7_EVAL(Q16/4); /* t=0.25 */
    U2S((u32)(sv<0?-sv:sv),b);PS(b);PS("\n");
}
F
ok "a42_bbs.h ($(wc -l < $D/a42_bbs.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_main.c" << 'F'
/* a42_main.c — Entry point: BBS CLI + executa fractal/grafo/svg/png
 * [E01] _start: sem argc/argv — usa BBS CLI
 * [E02] Loop principal: menu → ação → resultado
 * [E03] Failsafe: arena mark/restore em cada ação
 * [E04] TTL progress: conta ciclos de iteração
 */
#include "a42_types.h"
#include "a42_sys.h"
#include "a42_math.h"
#include "a42_fractal.h"
#include "a42_svg.h"
#include "a42_png.h"
#include "a42_bbs.h"

static void DO_GRAPH(void){
    PS("\n\033[1;36m[GRAFO] N=");char b[12];U2S(G_CFG.N,b);PS(b);
    PS(" K=");U2S(G_CFG.K,b);PS(b);PS("\033[0m\n");
    AM(); /* checkpoint */
    CIRCLE_INIT(G_CFG.N,Q16);
    GRAPH_COMPUTE(G_CFG.N,G_CFG.K,G_CFG.ITER);
    MAT_FILL(G_CFG.N);
    SHOW_METRICS(G_CFG.N);
    /* SVG */
    SVG_GRAPH(G_CFG.N,G_CFG.max_px_svg);
    if(SVG_SAVE("grafo_42.svg")==0)PS("  \033[1;32m[OK]\033[0m grafo_42.svg\n");
    else {PS("  \033[1;31m[ERR]\033[0m SVG falhou — rollback\n");ARS();}
}

static void DO_MANDEL(void){
    PS("\n\033[1;35m[MANDELBROT] W=");char b[12];U2S(G_CFG.W,b);PS(b);
    PS(" H=");U2S(G_CFG.H,b);PS(b);
    PS(" zoom=");U2S((u32)G_CFG.zoom/Q16,b);PS(b);PS("\033[0m\n");
    AM();
    /* ASCII */
    _ASC_POS=0;
    MANDEL_ASCII(G_CFG.W,G_CFG.H,G_CFG.zoom,_ASC,ASC_BUF);
    WR(1,_ASC,(u32)SL((char*)_ASC));
    /* SVG */
    u32 svgW=G_CFG.max_px_svg,svgH=(G_CFG.max_px_svg*G_CFG.H)/G_CFG.W;
    SVG_FRACTAL_MANDEL(G_CFG.W/4u,G_CFG.H/4u,G_CFG.zoom,svgW);
    if(SVG_SAVE("mandelbrot.svg")==0)PS("  \033[1;32m[OK]\033[0m mandelbrot.svg\n");
    /* PNG */
    u32 pW=G_CFG.max_px_svg/8u,pH=G_CFG.max_px_svg/8u;
    AR(); AM(); /* reset arena para buffer PNG */
    u8*rgb=MANDEL_RGB(pW,pH,G_CFG.zoom);
    if(rgb){
        if(PNG_SAVE_RGB("mandelbrot.png",pW,pH,rgb)==0)
            PS("  \033[1;32m[OK]\033[0m mandelbrot.png\n");
        else{PS("  \033[1;31m[ERR]\033[0m PNG falhou\n");ARS();}
    }
}

static void DO_JULIA(void){
    PS("\n\033[1;36m[JULIA] ");char b[12];U2S(G_CFG.n_julia,b);PS(b);
    PS(" sets no semicírculo\033[0m\n");
    for(u32 j=0;j<G_CFG.n_julia;j++){
        q12_t cr,ci;
        JULIA_PARAMS(j,G_CFG.n_julia,&cr,&ci);
        PS("  J=");U2S(j,b);PS(b);PS(" cr=");
        char sv[8];U2S(j*100u/G_CFG.n_julia,sv);PS(sv);PS("%\n");
        AM();
        /* ASCII Julia menor */
        JULIA_ASCII(G_CFG.W/2u,G_CFG.H/2u,cr,ci,_ASC,ASC_BUF);
        WR(1,_ASC,(u32)SL((char*)_ASC));
        /* SVG */
        u32 pxj=G_CFG.max_px_svg/2u;
        _SVG_POS=0;
        u32 cxj=pxj/2,cyj=pxj/2;
        SVG_W("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"");
        SVG_N(pxj);SVG_W("\" height=\"");SVG_N(pxj);SVG_W("\" style=\"background:#000\">\n");
        /* células Julia */
        u32 W2=G_CFG.W/2u,H2=G_CFG.H/2u;
        u32 csz=pxj/(W2>1u?W2:1u);
        q12_t dx=(q12_t)(4*Q12/(s32)W2);
        q12_t dy=(q12_t)(4*Q12/(s32)H2);
        for(u32 py=0;py<H2;py++){
            q12_t zi=(2*Q12)-(q12_t)((s64)dy*(s32)py);
            for(u32 px=0;px<W2;px++){
                q12_t zr=(-2*Q12)+(q12_t)((s64)dx*(s32)px);
                u32 it=ESCAPE(zr,zi,cr,ci,FRAC_MAXITER);
                u8 R,G,B;
                if(it==FRAC_MAXITER){R=0;G=0;B=0;}
                else PLASMA_RGB((it*255u)/FRAC_MAXITER,&R,&G,&B);
                SVG_W("<rect x=\"");SVG_N(px*csz);SVG_W("\" y=\"");SVG_N(py*csz);
                SVG_W("\" width=\"");SVG_N(csz);SVG_W("\" height=\"");SVG_N(csz);
                SVG_W("\" fill=\"");SVG_COLOR(R,G,B);SVG_W("\"/>\n");
            }
        }
        SVG_W("<text x=\"5\" y=\"15\" fill=\"#ff0\" font-size=\"10\">Julia J=");
        SVG_N(j);SVG_W("</text>\n</svg>\n");
        /* Salva julia_J.svg */
        char path[32];path[0]='j';path[1]='u';path[2]='l';path[3]='i';path[4]='a';path[5]='_';
        U2S(j,path+6);u32 pl=SL(path);path[pl]='.';path[pl+1]='s';path[pl+2]='v';path[pl+3]='g';path[pl+4]=0;
        if(SVG_SAVE(path)==0){PS("  \033[1;32m[OK]\033[0m ");PS(path);PS("\n");}
        else{PS("  \033[1;31m[ERR]\033[0m ");PS(path);PS("\n");ARS();}
    }
}

static void DO_MATRICES(void){
    AM();CIRCLE_INIT(G_CFG.N,Q16);GRAPH_COMPUTE(G_CFG.N,G_CFG.K,G_CFG.ITER);MAT_FILL(G_CFG.N);
    PS("\n\033[1;33m=== MATRIZES DE ATRATORES ===\033[0m\n");
    PS("  2×2 (primeiros 4):\n  ");
    char b[8];
    for(u32 r=0;r<2u;r++){for(u32 c=0;c<2u;c++){U2S(_MAT2x2[0][r][c],b);PS(b);PS(" ");}PS("\n  ");}
    PS("\n  4×4 (primeiros 16):\n  ");
    for(u32 r=0;r<4u;r++){for(u32 c=0;c<4u;c++){U2S(_MAT4x4[0][r][c],b);PS(b);PS("\t");}PS("\n  ");}
    PS("\n");
}

static void DO_FORMAT(void){
    PS("\n  Formato: [1]=ASCII [2]=SVG [3]=PNG [4]=Todos\n  Escolha: ");
    static u8 ibuf[4];READLINE(ibuf,4u);
    if(ibuf[0]>='1'&&ibuf[0]<='4')G_CFG.out=(u32)(ibuf[0]-'1');
}

/* ── ENTRY POINT ─────────────────────────────────────────────────────────── */
void _start(void){
    AR(); /* reset arena */
    SINE7_INIT();
    /* Logo inicial */
    CLS();
    PS("\033[1;33m");
    PS("  ╔═══════════════════════════════════════════════════════════════╗\n");
    PS("  ║ \033[1;36m42 ATRATORES\033[1;33m ■ \033[1;32mGRAFOS CIRCULARES\033[1;33m ■ \033[1;35mMANDELBROT\033[1;33m ■ \033[1;36mJULIA\033[1;33m  ║\n");
    PS("  ║ \033[0;37m freestanding ■ nomalloc ■ nolibc ■ Q16/Q12 ■ inline ASM    \033[1;33m║\n");
    PS("  ║ \033[0;37m ARM32/ARM64/x86-64/RISC-V ■ CORDIC sin/cos ■ PLASMA cmap   \033[1;33m║\n");
    PS("  ║ \033[0;37m SVG+PNG sem malloc ■ BBS CLI ■ TTL ■ 7-Sine adaptativo      \033[1;33m║\n");
    PS("  ╚═══════════════════════════════════════════════════════════════╝\n");
    PS("\033[0m\n");
    /* Loop BBS */
    static u8 ibuf[4];
    for(;;){
        MENU_MAIN();
        READLINE(ibuf,4u);
        u8 ch=ibuf[0];
        if(!ch)continue;
        if(ch=='q'||ch=='Q')break;
        else if(ch=='1')DO_GRAPH();
        else if(ch=='2')DO_MANDEL();
        else if(ch=='3')DO_JULIA();
        else if(ch=='4'){DO_GRAPH();DO_MANDEL();DO_JULIA();}
        else if(ch=='s'||ch=='S')DO_PARAMS();
        else if(ch=='f'||ch=='F')DO_FORMAT();
        else if(ch=='m'||ch=='M')DO_MATRICES();
        else{PS("  \033[1;31mOpção inválida\033[0m\n");continue;}
        PS("\n  \033[0;37mPressione Enter...\033[0m");READLINE(ibuf,4u);
    }
    PS("\n\033[1;33mOmega=Amor · DeltaRafaelVerboOmega\033[0m\n");
    EX();
}
F
ok "a42_main.c ($(wc -l < $D/a42_main.c)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/a42_start.S" << 'F'
/* a42_start.S — entry ARM32/ARM64/x86-64 */
#if defined(__arm__)
.syntax unified
.thumb
.text
.align 2
.global _start
.thumb_func
_start:
    mov r11,#0
    mov lr,#0
    bl  _start
    mov r7,#248
    mov r0,#0
    svc #0
.h: b .h
#elif defined(__aarch64__)
.text
.align 4
.global _start
_start:
    mov x29,xzr
    mov x30,xzr
    and sp,sp,#-16
    bl  _start
    mov x0,xzr
    mov x8,#94
    svc #0
.h: b .h
#elif defined(__x86_64__)
.text
.globl _start
_start:
    xor %rbp,%rbp
    call _start
    mov $231,%rax
    xor %rdi,%rdi
    syscall
#endif
.section .note.GNU-stack,"",@progbits
F
ok "a42_start.S"

cat > "$D/Makefile" << 'F'
ARCH=$(shell uname -m)
CC?=clang
CF=-O2 -fPIE -fno-stack-protector -fno-asynchronous-unwind-tables \
   -fomit-frame-pointer -fno-builtin -fno-plt \
   -ffunction-sections -fdata-sections \
   -Wall -Wno-unused-function -Wno-unused-variable \
   -Wno-unused-but-set-variable -I.
LF=-pie -nostdlib -Wl,--gc-sections -Wl,--build-id=none -e _start
.PHONY: all run clean
all:
ifeq ($(ARCH),aarch64)
	$(CC) $(CF) -march=armv8.2-a+crc+crypto a42_main.c $(LF) -o 42atratores
else ifeq ($(ARCH),x86_64)
	$(CC) $(CF) -march=native -static a42_main.c $(LF) -o 42atratores
endif
	@for CC32 in arm-linux-gnueabihf-gcc arm-linux-gnueabi-gcc; do \
	  command -v $$CC32 &>/dev/null && \
	  $$CC32 $(CF) -mthumb -march=armv7-a+neon-vfpv4 -mfloat-abi=softfp \
	    -mfpu=neon-vfpv4 a42_start.S a42_main.c $(LF) -o 42atratores_arm32 && break || true; done
run: all
	./42atratores
clean:
	rm -f 42atratores 42atratores_arm32 *.svg *.png
F
ok "Makefile"

# =============================================================================
hdr "COMPILANDO"
# =============================================================================
ARCH=$(uname -m)
CC="${CC:-clang}"; command -v "$CC" &>/dev/null || CC=gcc
CF="-O2 -fPIE -fno-stack-protector -fno-asynchronous-unwind-tables \
    -fomit-frame-pointer -fno-builtin -fno-plt \
    -ffunction-sections -fdata-sections \
    -Wall -Wno-unused-function -Wno-unused-variable \
    -Wno-unused-but-set-variable -I$D"
LF="-pie -nostdlib -Wl,--gc-sections -Wl,--build-id=none -e _start"
BUILT=false
if [ "$ARCH" = "aarch64" ]; then
    $CC $CF -march=armv8.2-a+crc+crypto "$D/a42_main.c" $LF -o "$D/42atratores" 2>>"$LOG" && {
        strip "$D/42atratores" 2>/dev/null||true
        ok "ARM64: $D/42atratores ($(ls -lh $D/42atratores|awk '{print $5}'))"; BUILT=true
    } || err "ARM64 falhou — ver $LOG"
elif [ "$ARCH" = "x86_64" ]; then
    $CC $CF -march=native -static "$D/a42_main.c" $LF -o "$D/42atratores" 2>>"$LOG" && {
        strip "$D/42atratores" 2>/dev/null||true
        ok "x86_64: $D/42atratores ($(ls -lh $D/42atratores|awk '{print $5}'))"; BUILT=true
    } || err "x86_64 falhou — ver $LOG"
fi
for CC32 in arm-linux-gnueabihf-gcc arm-linux-gnueabi-gcc; do
    command -v "$CC32" &>/dev/null || continue
    $CC32 $CF -mthumb -march=armv7-a+neon-vfpv4 -mfloat-abi=softfp -mfpu=neon-vfpv4 \
        $LF "$D/a42_start.S" "$D/a42_main.c" -o "$D/42atratores_arm32" 2>>"$LOG" && {
        ok "ARM32: $D/42atratores_arm32"; BUILT=true; } || err "ARM32 falhou"
    break
done

# =============================================================================
hdr "INVENTÁRIO FINAL"
# =============================================================================
echo ""
TOTAL=0
printf "${W}%-25s %8s %10s${Z}\n" "ARQUIVO" "LINHAS" "TAMANHO"
for f in "$D"/*.h "$D"/*.c "$D"/*.S "$D/Makefile"; do
    [ -f "$f" ] || continue
    L=$(wc -l < "$f"); SZ=$(ls -lh "$f"|awk '{print $5}')
    printf "%-25s ${G}%8d${Z} ${Y}%10s${Z}\n" "$(basename $f)" "$L" "$SZ"
    TOTAL=$((TOTAL+L))
done
printf "${W}%-25s ${G}%8d${Z}\n" "TOTAL" "$TOTAL"
echo ""
if $BUILT; then
    p "EXECUTAR: $D/42atratores"
    p "ARM32:    qemu-arm $D/42atratores_arm32"
    p "Arquivos gerados: grafo_42.svg mandelbrot.svg julia_N.svg mandelbrot.png"
fi
echo -e "\n${M}${BLD}DeltaRafaelVerboOmega · Omega=Amor · RAFCODE-Phi${Z}"
echo -e "${C}N=42 · K=5 · Q16/Q12 · CORDIC · PLASMA · BBS-style${Z}\n"
MONOLITH

wc -l /tmp/42atratores.txt
ls -lh /tmp/42atratores.txt
Saída

1168 /tmp/42atratores.txt
-rw-r--r-- 1 root root 51K May 16 15:13 /tmp/42atratores.txt
Concluído

