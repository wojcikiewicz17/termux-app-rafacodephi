/**
 * rafaelia_glue.c
 * RAFAELIA — integração completa em C puro
 * Compilável diretamente no Termux ARM32 sem NDK:
 *
 *   clang -O2 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp \
 *         -std=c11 -ffast-math \
 *         rafaelia_glue.c -o rafaelia_glue -lm -ldl
 *
 * Roda todos os módulos em sequência:
 *   GPU probe → hw profile → 8 vCPU init → 42 ciclos →
 *   commit gate → paridade 1008 → senoides → CRC chain → stats
 *
 * ZERO malloc em qualquer ponto.
 */

#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <math.h>
#include <time.h>

#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

/* ── Arquitetura ────────────────────────────────────────────────────────── */
#if defined(__aarch64__)
  #define ABI "arm64-v8a"
#elif defined(__arm__)
  #define ABI "armeabi-v7a"
#else
  #define ABI "generic"
#endif

/* ── Arena global: 6MB ──────────────────────────────────────────────────── */
#define ARENA_CAP (6u*1024u*1024u)
static uint8_t __attribute__((aligned(64))) g_arena[ARENA_CAP];
static uint32_t g_bump = 0;

static void *A(uint32_t n, uint32_t al) {
    uint32_t m=al-1, s=(g_bump+m)&~m, e=s+n;
    if(e>ARENA_CAP) return 0;
    g_bump=e; return g_arena+s;
}
static void arena_reset(void){ g_bump=0; }

/* ── CRC32C ─────────────────────────────────────────────────────────────── */
static uint32_t CT[256];
static void crc_init(void){
    for(uint32_t i=0;i<256;i++){
        uint32_t v=i;
        for(int j=0;j<8;j++) v=(v&1)?(v>>1)^0x82F63B78u:(v>>1);
        CT[i]=v;
    }
}
static uint32_t crc(const void*b,uint32_t n){
    const uint8_t*p=(const uint8_t*)b; uint32_t c=~0u;
    while(n--) c=(c>>8)^CT[(c^*p++)&0xFF]; return ~c;
}

/* ── Output direto ──────────────────────────────────────────────────────── */
static const char HX[]="0123456789ABCDEF";
static void ws(const char*s){ write(1,s,strlen(s)); }
static void wn(void){ write(1,"\n",1); }
static void wu32(uint32_t v){
    char b[12]; int i=11; b[i]=0;
    if(!v){b[--i]='0';} else while(v){b[--i]=(char)('0'+v%10);v/=10;}
    ws(b+i);
}
static void whex(uint32_t v){
    char b[11]; b[0]='0'; b[1]='x';
    for(int i=0;i<8;i++) b[2+i]=HX[(v>>(28-i*4))&0xF];
    b[10]=0; ws(b);
}
static void wlabel(const char*l, uint32_t v){
    ws(l); whex(v); wn();
}

/* ── Q16.16 math ────────────────────────────────────────────────────────── */
static uint32_t qmul(uint32_t a, uint32_t b){
    return (uint32_t)(((uint64_t)a*b)>>16);
}
static uint32_t qema(uint32_t old, uint32_t in){
    /* 0.75*old + 0.25*in */
    return (uint32_t)(((uint64_t)old*49152u+(uint64_t)in*16384u)>>16);
}

/* sin(x) Taylor Q16.16: x - x^3/6 + x^5/120 */
#define Q2PI  411774u
#define QPI   205887u
#define INV6  10923u
#define INV120 546u
static uint32_t qsin(uint32_t x){
    while(x>=Q2PI) x-=Q2PI;
    int neg=0;
    if(x>=QPI){ x-=QPI; neg=1; }
    uint64_t x2=(uint64_t)x*x>>16;
    uint64_t x3=(uint64_t)x2*x>>16;
    uint64_t x5=(uint64_t)x3*x2>>16;
    uint64_t t1=(uint64_t)x3*INV6>>16;
    uint64_t t2=(uint64_t)x5*INV120>>16;
    int64_t r=(int64_t)x-(int64_t)t1+(int64_t)t2;
    if(r<0) r=0;
    if(r>65535) r=65535;
    return neg ? (uint32_t)(65535u-(uint32_t)r) : (uint32_t)r;
}

/* ── Constantes ─────────────────────────────────────────────────────────── */
#define SPIRAL  56755u
#define PHI_C   105965u
#define PERIOD  42u
#define N_VCPU  8u
#define TDIM    7u          /* dimensões do toro */
#define N_LAY   4u
#define N_STACKS 1000u
#define N_EXTRA  8u         /* 4+2+2 */
#define N_TOTAL  1008u

/* ── vCPU ───────────────────────────────────────────────────────────────── */
typedef struct {
    uint32_t s[TDIM];   /* estado 7D Q16.16 */
    uint32_t hz;        /* frequência harmônica Q16.16 */
    uint32_t C, H;      /* coerência, entropia */
    uint32_t phase;     /* 0..41 */
    uint32_t layer;     /* 0=L1 1=L2 2=BUF 3=RAM */
    uint32_t load;      /* load Q16.16 */
    uint32_t crc_s;     /* CRC do estado */
} vcpu_t;

static vcpu_t g_vcpu[N_VCPU];

static const uint32_t HZ_TABLE[N_VCPU] =
    {58000,58000,58000,50296, 43500,43500,37709,26836};
static const uint32_t FIB8[N_VCPU] = {0,0,0,1,1,2,3,5};

static void vcpu_init(void){
    for(uint32_t i=0;i<N_VCPU;i++){
        vcpu_t *v=&g_vcpu[i];
        v->hz    = HZ_TABLE[i];
        v->C     = 0x8000u;
        v->H     = 0x8000u;
        v->phase = (i*PERIOD)/N_VCPU;
        v->load  = 0;
        /* layer por hz */
        v->layer = (v->hz>50000) ? 0 : (v->hz>38000) ? 1 :
                   (v->hz>25000) ? 2 : 3;
        /* seed estado com SPIRAL^fib mod 65536 */
        uint32_t seed = (SPIRAL * (i+1)) & 0xFFFFu;
        for(uint32_t d=0;d<TDIM;d++){
            seed = qmul(seed, SPIRAL) + d*1009u;
            v->s[d] = seed & 0xFFFFu;
        }
        v->crc_s = crc(v, offsetof(vcpu_t, crc_s));
    }
}

/* ── Triângulo isósceles de predição ────────────────────────────────────── */
static uint32_t predict_jet(void){
    /* ápice = core de maior hz */
    uint32_t apex=0;
    for(uint32_t i=1;i<N_VCPU;i++)
        if(g_vcpu[i].hz > g_vcpu[apex].hz) apex=i;
    /* jet = core de menor load ≠ apex */
    uint32_t jet=0; uint32_t ml=~0u;
    for(uint32_t i=0;i<N_VCPU;i++){
        if(i==apex) continue;
        if(g_vcpu[i].load < ml){ ml=g_vcpu[i].load; jet=i; }
    }
    return jet;
}

/* ── Camadas de memória ─────────────────────────────────────────────────── */
typedef struct {
    uint8_t  *buf;
    uint32_t  sz;
    uint32_t  crc_v;
    uint32_t  hits;
    uint32_t  misses;
} memlayer_t;

static memlayer_t g_mem[N_LAY];
static const uint32_t MEM_SZ[N_LAY] = {
    8*1024, 32*1024, 64*1024, 128*1024
};

static void mem_init(void){
    for(int i=0;i<(int)N_LAY;i++){
        g_mem[i].buf = (uint8_t*)A(MEM_SZ[i],64);
        g_mem[i].sz  = MEM_SZ[i];
        if(g_mem[i].buf) memset(g_mem[i].buf,0,MEM_SZ[i]);
        g_mem[i].crc_v = g_mem[i].buf ?
            crc(g_mem[i].buf, MEM_SZ[i]) : 0;
    }
}

static int mem_verify(int lay){
    if(!g_mem[lay].buf) return 1;
    return crc(g_mem[lay].buf, g_mem[lay].sz) == g_mem[lay].crc_v;
}

static void mem_write_block(int lay, uint32_t off, uint8_t *src, uint32_t n){
    if(!g_mem[lay].buf || off+n > g_mem[lay].sz) return;
    memcpy(g_mem[lay].buf+off, src, n);
    g_mem[lay].crc_v = crc(g_mem[lay].buf, g_mem[lay].sz);
}

/* ── BitStacks 1008 ─────────────────────────────────────────────────────── */
/* 1000 stacks de 64 bits (42 bits usados) + 2 paridade + 4+2 extras */
static uint64_t *g_stacks;   /* 1000 x uint64 */
static uint64_t  g_par0;     /* XOR paridade */
static uint64_t  g_par1;     /* CRC paridade (32 bits armazenado em 64) */
static uint64_t  g_extras[N_EXTRA]; /* triângulo isósceles + atratores */

static void stacks_init(void){
    g_stacks = (uint64_t*)A(N_STACKS*8u, 64);
    if(!g_stacks) return;
    /* fill Fibonacci mod 42 */
    uint32_t f0=0, f1=1;
    for(uint32_t i=0;i<N_STACKS;i++){
        uint32_t bits = f1 % PERIOD;
        g_stacks[i] = bits ? (1ULL<<bits)-1ULL : 0ULL;
        uint32_t fn = f0+f1; f0=f1; f1=fn;
    }
    /* paridade XOR */
    g_par0=0;
    for(uint32_t i=0;i<N_STACKS;i++) g_par0 ^= g_stacks[i];
    /* paridade CRC */
    g_par1 = crc(g_stacks, N_STACKS*8u);
}

static int stacks_verify(void){
    if(!g_stacks) return 1;
    uint64_t xr=0;
    for(uint32_t i=0;i<N_STACKS;i++) xr ^= g_stacks[i];
    if(xr != g_par0) return 0;
    return (uint64_t)crc(g_stacks, N_STACKS*8u) == g_par1;
}

/* conta bits totais */
static uint32_t stacks_popcount(void){
    uint32_t tot=0;
    for(uint32_t i=0;i<N_STACKS;i++){
        uint64_t v=g_stacks[i];
        while(v){ v&=v-1; tot++; }
    }
    return tot;
}

/* ── Commit Gate ────────────────────────────────────────────────────────── */
#define CG_LOAD    0x1u
#define CG_PROC    0x2u
#define CG_VERIFY  0x4u
#define CG_COMMIT  0x8u
#define CG_ALL     0xFu

static uint32_t g_cg_bitmap[N_VCPU];
static vcpu_t   g_snapshot[N_VCPU];
static uint32_t g_commits=0, g_rollbacks=0;

static void cg_run_one(uint32_t core){
    vcpu_t *v = &g_vcpu[core];

    /* LOAD */
    memcpy(&g_snapshot[core], v, sizeof(vcpu_t));
    g_cg_bitmap[core] |= CG_LOAD;

    /* PROCESS: EMA 7D */
    for(uint32_t d=0;d<TDIM;d++){
        uint32_t next_d = (d+1)%TDIM;
        v->s[d] = (uint32_t)(((uint64_t)v->s[d]*49152u +
                               (uint64_t)v->s[next_d]*16384u) >> 16);
    }
    v->C = qema(v->C, qmul(v->hz, SPIRAL)&0xFFFFu);
    v->H = qema(v->H, 65535u - (qmul(v->hz,SPIRAL)&0xFFFFu));
    v->phase = (v->phase+1u < PERIOD) ? v->phase+1u : 0u;
    g_cg_bitmap[core] |= CG_PROC;

    /* VERIFY */
    uint32_t sc = crc(v, offsetof(vcpu_t,crc_s));
    if(!sc || v->s[0] >= Q2PI){ /* sanidade */
        /* rollback */
        memcpy(v, &g_snapshot[core], sizeof(vcpu_t));
        g_cg_bitmap[core] = 0;
        g_rollbacks++;
        return;
    }
    g_cg_bitmap[core] |= CG_VERIFY;

    /* COMMIT */
    if((g_cg_bitmap[core]&CG_ALL)==CG_ALL){
        v->crc_s = sc;
        g_cg_bitmap[core] = 0;
        g_commits++;
    }
}

/* ── Senoides 7 camadas ─────────────────────────────────────────────────── */
static uint32_t g_sin_phases[TDIM];
static uint32_t g_sin_weights[TDIM];
static uint32_t g_phi_trace[PERIOD];
static uint32_t g_crc_chain=0;

static const uint32_t FREQS[TDIM]={9804,19608,29412,39216,49020,58824,68628};
static const uint32_t WINIT[TDIM]={65536,56755,49157,42573,36877,31940,27671};

static void sin_init(void){
    memcpy(g_sin_weights, WINIT, sizeof(WINIT));
    memset(g_sin_phases, 0, sizeof(g_sin_phases));
}

static uint32_t sin_step(uint32_t cycle){
    uint32_t overlap=0;
    for(uint32_t i=0;i<TDIM;i++){
        g_sin_phases[i] += FREQS[i];
        if(g_sin_phases[i] >= Q2PI) g_sin_phases[i] -= Q2PI;
        uint32_t sv = qsin(g_sin_phases[i]);
        uint32_t out = qmul(sv, g_sin_weights[i]);
        overlap += out;
        /* adapt peso */
        g_sin_weights[i] = (g_sin_weights[i]*3u + sv) >> 2;
    }
    /* normaliza /7 */
    uint32_t c_in = qmul(overlap, 9362u); /* 1/7 ≈ 9362/65536 */
    uint32_t h_in = 65535u - c_in;
    /* EMA global */
    static uint32_t C=0x8000, H=0x8000;
    C = qema(C, c_in); H = qema(H, h_in);
    uint32_t phi = qmul(65535u-H, C);
    g_phi_trace[cycle] = phi;
    /* CRC encadeada */
    uint32_t tmp[2] = {phi, g_crc_chain};
    g_crc_chain = crc(tmp, 8);
    return phi;
}

/* ── GPU probe ──────────────────────────────────────────────────────────── */
static const char *OCL[]={
    "/vendor/lib/libOpenCL.so",
    "/vendor/lib/egl/libGLES_mali.so",
    "/system/lib/libOpenCL.so",
    "/vendor/lib/libPVROCL.so", 0
};
static int gpu_available=0;
static void *gpu_lib=0;

static void gpu_probe(void){
    for(int i=0;OCL[i];i++){
        void *l=dlopen(OCL[i],RTLD_LAZY|RTLD_LOCAL);
        if(!l) continue;
        if(dlsym(l,"clGetPlatformIDs")){ gpu_lib=l; gpu_available=1; return; }
        dlclose(l);
    }
}

/* ── HW profile ─────────────────────────────────────────────────────────── */
typedef struct {
    uint32_t n_cpu;
    uint32_t freq0, freq1;
    uint32_t page_sz;
    uint8_t  neon;
    uint8_t  crc32_hw;
} hw_t;

static hw_t g_hw;

static uint32_t rd_u32(const char *p){
    char b[32]; int fd=open(p,O_RDONLY|O_CLOEXEC);
    if(fd<0) return 0;
    ssize_t n=read(fd,b,31); close(fd);
    if(n<=0) return 0; b[n]=0;
    uint32_t v=0;
    for(int i=0;b[i]>='0'&&b[i]<='9';i++) v=v*10+(b[i]-'0');
    return v;
}

static void hw_probe(void){
    g_hw.n_cpu  = rd_u32("/sys/devices/system/cpu/present");
    if(!g_hw.n_cpu) g_hw.n_cpu=N_VCPU;
    g_hw.freq0  = rd_u32("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq");
    g_hw.freq1  = rd_u32("/sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq");
    if(!g_hw.freq0) g_hw.freq0=2000000;
    if(!g_hw.freq1) g_hw.freq1=1500000;
    long pg=sysconf(_SC_PAGESIZE);
    g_hw.page_sz = pg>0 ? (uint32_t)pg : 4096;
#ifdef __ARM_NEON
    g_hw.neon=1;
#endif
#ifdef __ARM_FEATURE_CRC32
    g_hw.crc32_hw=1;
#endif
}

/* ── Throughput ─────────────────────────────────────────────────────────── */
static uint64_t now_us(void){
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC,&ts);
    return (uint64_t)ts.tv_sec*1000000u + (uint64_t)ts.tv_nsec/1000u;
}

/* ── MAIN ───────────────────────────────────────────────────────────────── */
int main(void){
    crc_init();
    hw_probe();
    gpu_probe();
    vcpu_init();
    mem_init();
    stacks_init();
    sin_init();
    memset(g_cg_bitmap,0,sizeof(g_cg_bitmap));

    ws("=== RAFAELIA GLUE — ALL MODULES ===\n");
    ws("ABI:  "); ws(ABI); wn();
    ws("vCPU: "); wu32(g_hw.n_cpu); wn();
    ws("NEON: "); ws(g_hw.neon?"YES":"NO"); wn();
    ws("GPU:  "); ws(gpu_available?"OpenCL":"CPU-NEON"); wn();
    ws("ARENA_CAP: "); wu32(ARENA_CAP/1024); ws("KB\n");
    wn();

    uint64_t t0 = now_us();

    /* ── 42 ciclos principais ─────────────────────────────────────────── */
    for(uint32_t cy=0; cy<PERIOD; cy++){

        /* 1. predição triângulo isósceles */
        uint32_t jet = predict_jet();

        /* 2. commit gate no core jet_target */
        cg_run_one(jet);

        /* 3. NEON EMA na camada preferida do core */
        uint32_t lay = g_vcpu[jet].layer;
        if(g_mem[lay].buf && g_mem[lay].sz >= 64){
            /* escreve senoide no buffer */
            uint32_t sv = qsin(g_vcpu[jet].phase * 9804u);
            uint8_t  bv = (uint8_t)(sv >> 8);
#ifdef __ARM_NEON
            uint8x16_t v = vdupq_n_u8(bv);
            vst1q_u8(g_mem[lay].buf, v);
#else
            memset(g_mem[lay].buf, bv, 16);
#endif
            g_mem[lay].crc_v = crc(g_mem[lay].buf, g_mem[lay].sz);
            g_mem[lay].hits++;
        }

        /* 4. verifica integridade de todas as camadas */
        for(int l=0;l<(int)N_LAY;l++){
            if(!mem_verify(l)){
                /* rollback: zera camada */
                if(g_mem[l].buf) memset(g_mem[l].buf,0,g_mem[l].sz);
                g_mem[l].crc_v = crc(g_mem[l].buf, g_mem[l].sz);
                g_mem[l].misses++;
            }
        }

        /* 5. senoide 7 camadas */
        sin_step(cy);

        /* 6. EMA do load do jet */
        g_vcpu[jet].load = qema(g_vcpu[jet].load, SPIRAL & 0xFFFFu);

        /* 7. verifica paridade BitStacks a cada 7 ciclos */
        if((cy % 7u)==0 && !stacks_verify()){
            /* corrupção simulada — recalcula paridade */
            g_par0=0;
            for(uint32_t i=0;i<N_STACKS;i++) g_par0^=g_stacks[i];
            g_par1=crc(g_stacks,N_STACKS*8u);
        }
    }

    uint64_t elapsed = now_us() - t0;

    /* ── Relatório final ────────────────────────────────────────────────── */
    ws("\n=== RESULTADO 42 CICLOS ===\n");
    wlabel("ELAPSED_US=  ", (uint32_t)elapsed);
    wlabel("COMMITS=     ", g_commits);
    wlabel("ROLLBACKS=   ", g_rollbacks);
    wlabel("PHI_FINAL=   ", g_phi_trace[PERIOD-1]);
    wlabel("PHI_INIT=    ", g_phi_trace[0]);
    wlabel("CRC_CHAIN=   ", g_crc_chain);
    wlabel("STACKS_BITS= ", stacks_popcount());
    wlabel("ARENA_USED=  ", g_bump);

    ws("\n--- vCPU ---\n");
    static const char *LNAMES[]={"L1","L2","BF","RM"};
    for(uint32_t i=0;i<N_VCPU;i++){
        vcpu_t *v=&g_vcpu[i];
        ws("CPU"); wu32(i);
        ws(" hz="); whex(v->hz);
        ws(" C=");  whex(v->C);
        ws(" H=");  whex(v->H);
        ws(" lay=");ws(LNAMES[v->layer]);
        ws(" ph="); wu32(v->phase);
        wn();
    }

    ws("\n--- MEM LAYERS ---\n");
    for(int l=0;l<(int)N_LAY;l++){
        ws(LNAMES[l]);
        ws(" sz=");   wu32(g_mem[l].sz/1024); ws("KB");
        ws(" hit=");  wu32(g_mem[l].hits);
        ws(" miss="); wu32(g_mem[l].misses);
        ws(" crc=");  whex(g_mem[l].crc_v);
        wn();
    }

    ws("\n--- SENOIDES 7 CAMADAS ---\n");
    ws("phi[0]=");  whex(g_phi_trace[0]);  wn();
    ws("phi[21]="); whex(g_phi_trace[21]); wn();
    ws("phi[41]="); whex(g_phi_trace[41]); wn();

    /* convergência: phi cresceu? */
    if(g_phi_trace[41] >= g_phi_trace[0])
        ws("CONVERGENCIA: OK (phi cresceu)\n");
    else
        ws("CONVERGENCIA: OSCILANDO\n");

    ws("\n--- BITSTACKS 1008 ---\n");
    ws("INTEGRIDADE: "); ws(stacks_verify()?"OK":"FALHA"); wn();
    ws("PONTOS: "); wu32(N_TOTAL); wn();
    ws("BITS_SET: "); wu32(stacks_popcount()); wn();

    ws("\n--- GPU ---\n");
    ws("API: "); ws(gpu_available?"OpenCL":"CPU-NEON"); wn();

    if(gpu_lib) dlclose(gpu_lib);

    ws("\nARENA_FINAL: "); wu32(g_bump/1024); ws("KB / ");
    wu32(ARENA_CAP/1024); ws("KB\n");
    ws("=== DONE ===\n");
    return 0;
}
