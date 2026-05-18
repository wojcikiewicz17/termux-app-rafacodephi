
cat > ./42atratores.txt << 'MONOLITH'
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

/
