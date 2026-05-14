/**
 * RAFAELIA GPU+CPU ORCHESTRATOR
 * rafaelia_orchestrator.c
 *
 * Orquestração geométrica de Hz para 8 vCPU (Helio G25 / Cortex-A53)
 * GPU via dlopen sem root (OpenCL / Vulkan compute)
 * Memória hierárquica: L1→L2→buffer→RAM→storage
 * CRC32SW para integridade em cada camada
 * ZERO malloc — arena estática de 2MB
 *
 * MODELO DE HZ COMO MEMÓRIA:
 *   Cada core vCPU tem uma frequência harmônica baseada na sua posição
 *   no toroide T^7. A frequência determina QUAL tipo de dado o core
 *   "carrega" melhor — como um cristal que ressoa com certa freq.
 *
 *   core_freq[i] = base_hz * fibonacci_ratio(i)   [i=0..7]
 *
 *   Triângulo isósceles de predição:
 *     dado o load L atual, os 3 cores mais próximos da "boca"
 *     do triângulo recebem o próximo batch (predição direcional)
 *
 * Compilar (Termux ARM32):
 *   clang -O2 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp \
 *         -std=c11 -ffast-math \
 *         rafaelia_orchestrator.c -o rafaelia_orch -lm -ldl
 *
 * Compilar (Termux ARM64):
 *   clang -O2 -march=armv8-a -std=c11 -ffast-math \
 *         rafaelia_orchestrator.c -o rafaelia_orch -lm -ldl
 *
 * Copyright (c) instituto-Rafael — GPLv3
 */

#define _GNU_SOURCE
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <sched.h>
#include <time.h>
#include <stdio.h>
#include <math.h>

#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

/* ============================================================================
 * DETECÇÃO DE ARQUITETURA
 * ========================================================================== */
#if defined(__aarch64__)
  #define RAF_ARCH 64
  #define RAF_ARCH_STR "arm64-v8a"
#elif defined(__arm__)
  #define RAF_ARCH 32
  #define RAF_ARCH_STR "armeabi-v7a"
#else
  #define RAF_ARCH 0
  #define RAF_ARCH_STR "generic"
#endif

/* ============================================================================
 * CONSTANTES DO SISTEMA
 * ========================================================================== */
#define N_VCPU          8       /* Helio G25: 8x Cortex-A53 */
#define CACHE_LINE      64      /* bytes */
#define L1_SIZE         (32*1024)   /* 32KB por core */
#define L2_SIZE         (256*1024)  /* 256KB compartilhado */
#define ARENA_SZ        (2*1024*1024) /* 2MB arena estática */

/* Constantes geométricas Q16.16 */
#define SPIRAL_Q16      56755u  /* sqrt(3)/2 */
#define PHI_Q16         105965u /* phi = (1+sqrt(5))/2 */
#define PERIOD          42u     /* período dos atratores */

/* Fibonacci sequence para mapeamento de Hz
 * 0001123 0123 01123 — família Rafaeliana */
static const uint32_t FIB_RAF[8] = {0,0,0,1,1,2,3,5};

/* Frequências harmônicas base (Hz) para cada cluster de core
 * Helio G25: todos Cortex-A53, 2 clusters de 4 (2.0GHz + 1.5GHz)
 * Mapeamos como harmônicos do triângulo equilátero: h_n = h0 * (sqrt(3)/2)^n */
#define BASE_HZ_CLUSTER0  2000000u  /* 2.0 GHz cluster */
#define BASE_HZ_CLUSTER1  1500000u  /* 1.5 GHz cluster */

/* Layers de memória (índices) */
#define MEM_L1      0   /* cache L1 — 32KB, latência ~4 ciclos */
#define MEM_L2      1   /* cache L2 — 256KB, latência ~12 ciclos */
#define MEM_BUF     2   /* buffer userspace — 512KB, latência ~50 ciclos */
#define MEM_RAM     3   /* RAM LPDDR4X — latência ~80ns */
#define MEM_STOR    4   /* storage eMMC — latência ~200µs */
#define N_MEM_LAYERS 5

/* ============================================================================
 * ARENA ESTÁTICA — zero malloc
 * ========================================================================== */
static __attribute__((aligned(64))) uint8_t g_arena[ARENA_SZ];
static uint32_t g_arena_bump = 0;

static void *raf_alloc(uint32_t n, uint32_t align) {
    uint32_t mask = align - 1u;
    uint32_t start = (g_arena_bump + mask) & ~mask;
    uint32_t end = start + n;
    if (end > ARENA_SZ) return 0;
    g_arena_bump = end;
    return g_arena + start;
}

static void raf_arena_reset(void) { g_arena_bump = 0; }

/* ============================================================================
 * CRC32C SOFTWARE (poly Castagnoli 0x82F63B78)
 * Tabela gerada em runtime — zero dependência externa
 * ========================================================================== */
static uint32_t g_crc_tab[256];
static uint8_t  g_crc_ready = 0;

static void crc_build(void) {
    for (uint32_t i = 0; i < 256u; i++) {
        uint32_t v = i;
        for (int j = 0; j < 8; j++)
            v = (v & 1u) ? ((v >> 1) ^ 0x82F63B78u) : (v >> 1);
        g_crc_tab[i] = v;
    }
    g_crc_ready = 1;
}

static uint32_t crc32c(const void *buf, uint32_t len) {
    if (!g_crc_ready) crc_build();
    const uint8_t *p = (const uint8_t *)buf;
    uint32_t crc = 0xFFFFFFFFu;
    /* loop desdobrado x4 */
    while (len >= 4u) {
        crc = (crc >> 8) ^ g_crc_tab[(crc ^ p[0]) & 0xFF];
        crc = (crc >> 8) ^ g_crc_tab[(crc ^ p[1]) & 0xFF];
        crc = (crc >> 8) ^ g_crc_tab[(crc ^ p[2]) & 0xFF];
        crc = (crc >> 8) ^ g_crc_tab[(crc ^ p[3]) & 0xFF];
        p += 4; len -= 4u;
    }
    while (len--) crc = (crc >> 8) ^ g_crc_tab[(crc ^ *p++) & 0xFF];
    return ~crc;
}

/* ============================================================================
 * PERFIL DE HARDWARE
 * Lê diretamente de /proc e /sys — sem sysconf overhead no hot path
 * ========================================================================== */
typedef struct {
    uint32_t n_cpu_online;          /* CPUs ativas */
    uint32_t page_sz;               /* tamanho da página */
    uint32_t cache_line;            /* bytes por cache line */
    uint32_t cluster_freq[2];       /* Hz dos 2 clusters */
    uint32_t l1_sz;                 /* bytes L1 D-cache */
    uint32_t l2_sz;                 /* bytes L2 */
    uint8_t  has_neon;
    uint8_t  has_crc32_hw;          /* instrução crc32 nativa */
    char     abi[16];
    uint32_t crc;                   /* integridade deste struct */
} hw_t;

static hw_t g_hw;

/* lê arquivo como uint32 — sem strtol, sem libc pesada */
static uint32_t read_u32_file(const char *path) {
    char buf[32];
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0u;
    ssize_t n = read(fd, buf, 31);
    close(fd);
    if (n <= 0) return 0u;
    buf[n] = 0;
    uint32_t v = 0;
    for (int i = 0; buf[i] >= '0' && buf[i] <= '9'; i++)
        v = v * 10u + (uint32_t)(buf[i] - '0');
    return v;
}

static void hw_probe(hw_t *h) {
    memset(h, 0, sizeof(*h));

    /* ABI */
    const char *abi = RAF_ARCH_STR;
    uint32_t i = 0;
    while (abi[i] && i < 15) { h->abi[i] = abi[i]; i++; }

    /* CPUs online */
    char cpu_online[64];
    int fd = open("/sys/devices/system/cpu/online", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        ssize_t n = read(fd, cpu_online, 63); close(fd);
        if (n > 0) { cpu_online[n] = 0; h->n_cpu_online = 0;
            /* parse "0-7" → 8 */
            for (int k = 0; cpu_online[k]; k++) {
                if (cpu_online[k] == '-') {
                    uint32_t a = 0, b = 0;
                    int j = k-1; while (j>=0 && cpu_online[j]>='0') j--;
                    for (int x=j+1;x<k;x++) a=a*10+(cpu_online[x]-'0');
                    for (int x=k+1;cpu_online[x]>='0';x++) b=b*10+(cpu_online[x]-'0');
                    h->n_cpu_online = b - a + 1;
                    break;
                }
            }
            if (!h->n_cpu_online) h->n_cpu_online = 1;
        }
    }
    if (!h->n_cpu_online) h->n_cpu_online = N_VCPU;

    /* Frequências dos clusters */
    h->cluster_freq[0] = read_u32_file(
        "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq");
    h->cluster_freq[1] = read_u32_file(
        "/sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq");
    if (!h->cluster_freq[0]) h->cluster_freq[0] = BASE_HZ_CLUSTER0;
    if (!h->cluster_freq[1]) h->cluster_freq[1] = BASE_HZ_CLUSTER1;

    /* Tamanho L1 D-cache */
    h->l1_sz = read_u32_file(
        "/sys/devices/system/cpu/cpu0/cache/index0/size");
    if (!h->l1_sz) h->l1_sz = L1_SIZE;
    else h->l1_sz *= 1024u; /* valor em KiB no sysfs */

    /* Tamanho L2 */
    h->l2_sz = read_u32_file(
        "/sys/devices/system/cpu/cpu0/cache/index2/size");
    if (!h->l2_sz) h->l2_sz = L2_SIZE;
    else h->l2_sz *= 1024u;

    /* Page size */
    long pg = sysconf(_SC_PAGESIZE);
    h->page_sz = (pg > 0) ? (uint32_t)pg : 4096u;

    /* Cache line */
    long cl = sysconf(_SC_LEVEL1_DCACHE_LINESIZE);
    h->cache_line = (cl > 0) ? (uint32_t)cl : CACHE_LINE;

    /* NEON */
#ifdef __ARM_NEON
    h->has_neon = 1;
#endif

    /* CRC32 HW (ARM32 sem suporte, ARM64 com +crc) */
#if defined(__ARM_FEATURE_CRC32)
    h->has_crc32_hw = 1;
#endif

    /* CRC de integridade do próprio struct */
    h->crc = 0;
    h->crc = crc32c(h, sizeof(*h));
}

/* ============================================================================
 * MODELO DE Hz GEOMÉTRICO
 *
 * Cada vCPU recebe uma "frequência harmônica de resonância" derivada
 * da sequência Fibonacci-Rafaeliana e da espiral sqrt(3)/2.
 *
 * Conceito: como um tubo de Venturi, a "garganta" (ponto de máxima vel.)
 * é o core de menor freq relativa — ele recebe dados de maior densidade.
 * Os dois "bocas" do Venturi são os cores de freq máxima — dispersão.
 *
 * hz_core[i] = cluster_freq * (sqrt(3)/2)^(fib_raf[i] mod 7)
 *              Q16.16 arithmetic
 * ========================================================================== */
typedef struct {
    uint32_t hz;        /* frequência harmônica Q16.16 (relativa) */
    uint32_t layer;     /* camada de memória preferida MEM_L1..MEM_STOR */
    uint32_t weight;    /* peso para load balancing Q16.16 */
    uint32_t load;      /* load atual 0..65535 Q16.16 */
    uint32_t phase;     /* fase no ciclo 0..41 */
    uint32_t crc_state; /* CRC do estado deste core */
} vcpu_t;

static vcpu_t g_vcpu[N_VCPU];

/* Tabela: layer preferido por faixa de hz relativo
 * Alta freq → prefere L1 (curto burst, hot data)
 * Baixa freq → prefere RAM/buffer (streams longos) */
static uint8_t hz_to_layer(uint32_t hz_q16) {
    if (hz_q16 > 58000u) return MEM_L1;
    if (hz_q16 > 45000u) return MEM_L2;
    if (hz_q16 > 30000u) return MEM_BUF;
    if (hz_q16 > 15000u) return MEM_RAM;
    return MEM_STOR;
}

static void vcpu_init(hw_t *h) {
    /* base Hz relativo = cluster_freq mapeado para Q16.16
     * normalizado em 65536 */
    uint32_t base0 = h->cluster_freq[0] / 1000u; /* kHz */
    uint32_t base1 = h->cluster_freq[1] / 1000u;

    for (uint32_t i = 0; i < N_VCPU; i++) {
        /* cores 0-3: cluster0, cores 4-7: cluster1 */
        uint32_t base = (i < 4u) ? base0 : base1;

        /* aplica espiral: hz = base * (SPIRAL_Q16/65536)^fib */
        uint32_t fib = FIB_RAF[i];
        uint32_t hz_q16 = (base * SPIRAL_Q16) >> 16u;
        for (uint32_t j = 1; j < fib && j < 7u; j++) {
            /* hz *= SPIRAL_Q16 / 65536 */
            uint64_t tmp = (uint64_t)hz_q16 * SPIRAL_Q16;
            hz_q16 = (uint32_t)(tmp >> 16u);
        }
        if (!hz_q16) hz_q16 = 1u;

        g_vcpu[i].hz      = hz_q16;
        g_vcpu[i].layer   = hz_to_layer(hz_q16);
        g_vcpu[i].weight  = hz_q16; /* peso inicial = hz */
        g_vcpu[i].load    = 0u;
        g_vcpu[i].phase   = (i * PERIOD) / N_VCPU; /* fases distribuídas */
        g_vcpu[i].crc_state = crc32c(&g_vcpu[i], offsetof(vcpu_t, crc_state));
    }
}

/* ============================================================================
 * TRIÂNGULO ISÓSCELES DE PREDIÇÃO DE CARGA
 *
 * Dado o vetor de loads dos 8 cores, o triângulo isósceles identifica:
 *   vértice_apice  = core de MAIOR hz (menor load relativo esperado)
 *   base_esquerda  = core de load MÁXIMO atual
 *   base_direita   = core de 2º load MÁXIMO atual
 *
 * A "maior diferença entre catetos" aponta o JATO de informação
 * — para onde o próximo batch deve ser direcionado.
 *
 * O ponto de garganta (Venturi) é a mediana entre os dois cores de base.
 * ========================================================================== */
typedef struct {
    uint32_t apex;       /* índice do core ápice */
    uint32_t base_l;     /* índice base esquerda */
    uint32_t base_r;     /* índice base direita */
    uint32_t jet_target; /* índice do core alvo do jato */
    uint32_t venturi_pt; /* índice do core garganta */
    uint32_t dist_max;   /* distância Q16.16 máxima (rompe aqui) */
} isosceles_t;

static isosceles_t predict_load(void) {
    isosceles_t t;
    memset(&t, 0, sizeof(t));

    /* encontra core de hz máximo (ápice) */
    uint32_t max_hz = 0;
    for (uint32_t i = 0; i < N_VCPU; i++) {
        if (g_vcpu[i].hz > max_hz) {
            max_hz = g_vcpu[i].hz;
            t.apex = i;
        }
    }

    /* encontra 2 cores de maior load (base do triângulo) */
    uint32_t load1 = 0, load2 = 0;
    t.base_l = 0; t.base_r = 1;
    for (uint32_t i = 0; i < N_VCPU; i++) {
        if (i == t.apex) continue;
        if (g_vcpu[i].load >= load1) {
            load2 = load1; t.base_r = t.base_l;
            load1 = g_vcpu[i].load; t.base_l = i;
        } else if (g_vcpu[i].load > load2) {
            load2 = g_vcpu[i].load; t.base_r = i;
        }
    }

    /* distância isósceles:
     * |cateto_L| = hz[apex] - hz[base_l]
     * |cateto_R| = hz[apex] - hz[base_r]
     * base    = |hz[base_l] - hz[base_r]|
     *
     * maior diferença entre catetos → jato informacional */
    uint32_t catL = (g_vcpu[t.apex].hz > g_vcpu[t.base_l].hz)
        ? g_vcpu[t.apex].hz - g_vcpu[t.base_l].hz
        : g_vcpu[t.base_l].hz - g_vcpu[t.apex].hz;
    uint32_t catR = (g_vcpu[t.apex].hz > g_vcpu[t.base_r].hz)
        ? g_vcpu[t.apex].hz - g_vcpu[t.base_r].hz
        : g_vcpu[t.base_r].hz - g_vcpu[t.apex].hz;

    /* jato aponta para o lado com cateto MENOR (menos carga) */
    t.jet_target  = (catL <= catR) ? t.base_l : t.base_r;
    t.dist_max    = (catL > catR)  ? catL : catR;

    /* garganta Venturi = mediana entre os dois loads */
    t.venturi_pt = (load1 + load2) / 2u < 32768u ? t.base_l : t.base_r;

    return t;
}

/* ============================================================================
 * CAMADAS DE MEMÓRIA
 *
 * Cada camada tem:
 *   buf   — ponteiro para buffer estático na arena
 *   sz    — tamanho em bytes
 *   crc   — CRC32C de integridade
 *   dirty — bits de bloco modificado (bitmap)
 * ========================================================================== */
#define BUF_L1_SZ   (8*1024)    /* 8KB em arena para L1 sim */
#define BUF_L2_SZ   (32*1024)   /* 32KB em arena para L2 sim */
#define BUF_BUF_SZ  (64*1024)   /* 64KB buffer userspace */
#define BUF_RAM_SZ  (128*1024)  /* 128KB RAM working set */
/* storage: não alocado em memória — acesso por path */

typedef struct {
    uint8_t  *buf;      /* ponteiro para bloco na arena */
    uint32_t  sz;       /* tamanho */
    uint32_t  crc;      /* crc32c do conteúdo */
    uint32_t  dirty;    /* bitmap de 32 blocos de sz/32 */
    uint32_t  hits;     /* acertos nesta camada */
    uint32_t  misses;   /* misses → promove para camada acima */
} mem_layer_t;

static mem_layer_t g_mem[N_MEM_LAYERS];

static void mem_init(void) {
    static const uint32_t szs[N_MEM_LAYERS] = {
        BUF_L1_SZ, BUF_L2_SZ, BUF_BUF_SZ, BUF_RAM_SZ, 0
    };
    for (int i = 0; i < N_MEM_LAYERS-1; i++) {
        g_mem[i].buf  = (uint8_t *)raf_alloc(szs[i], 64);
        g_mem[i].sz   = szs[i];
        g_mem[i].crc  = 0;
        g_mem[i].dirty = 0;
        g_mem[i].hits  = 0;
        g_mem[i].misses = 0;
        if (g_mem[i].buf)
            memset(g_mem[i].buf, 0, szs[i]);
    }
    /* storage: sem buffer */
    g_mem[MEM_STOR].buf = 0;
    g_mem[MEM_STOR].sz  = 0;
}

/* Escreve bloco na camada `layer`, atualiza CRC e dirty bits */
static void mem_write(int layer, uint32_t offset, const void *src, uint32_t n) {
    if (layer >= N_MEM_LAYERS-1 || !g_mem[layer].buf) return;
    if (offset + n > g_mem[layer].sz) n = g_mem[layer].sz - offset;
    memcpy(g_mem[layer].buf + offset, src, n);
    /* atualiza dirty bitmap */
    uint32_t block_sz = g_mem[layer].sz / 32u;
    if (block_sz == 0) block_sz = 1;
    uint32_t blk = offset / block_sz;
    if (blk < 32u) g_mem[layer].dirty |= (1u << blk);
    /* recalcula CRC apenas dos blocos dirty */
    g_mem[layer].crc = crc32c(g_mem[layer].buf, g_mem[layer].sz);
}

/* Verifica integridade de uma camada — retorna 1 se ok */
static int mem_verify(int layer) {
    if (layer >= N_MEM_LAYERS-1 || !g_mem[layer].buf) return 1;
    uint32_t c = crc32c(g_mem[layer].buf, g_mem[layer].sz);
    return (c == g_mem[layer].crc);
}

/* Promove bloco de layer+1 para layer (cache fill) */
static void mem_promote(int dst, int src, uint32_t offset, uint32_t n) {
    if (dst >= N_MEM_LAYERS || src >= N_MEM_LAYERS) return;
    if (!g_mem[dst].buf || !g_mem[src].buf) return;
    if (offset + n > g_mem[src].sz) n = g_mem[src].sz - offset;
    if (n > g_mem[dst].sz) n = g_mem[dst].sz;
    memcpy(g_mem[dst].buf, g_mem[src].buf + offset, n);
    g_mem[dst].crc = crc32c(g_mem[dst].buf, g_mem[dst].sz);
    g_mem[src].misses++;
    g_mem[dst].hits++;
}

/* ============================================================================
 * GPU: dlopen sem root
 *
 * Helio G25 → PowerVR GE8320 → OpenCL 2.0 disponível no userspace
 * Vulkan Compute disponível se driver instalado
 *
 * ESTRATÉGIA: tenta OpenCL primeiro, fallback Vulkan, fallback CPU NEON
 * ========================================================================== */
typedef struct {
    int      available;   /* 1 se GPU encontrada */
    char     api[16];     /* "opencl" | "vulkan" | "cpu" */
    void    *lib;         /* handle dlopen */
    /* funções básicas — ponteiros genéricos */
    void    *pfn_get_platform;
    void    *pfn_create_ctx;
    void    *pfn_create_queue;
} gpu_t;

static gpu_t g_gpu;

/* Paths onde libOpenCL pode estar em Android sem root */
static const char *OCL_PATHS[] = {
    "/vendor/lib/libOpenCL.so",
    "/vendor/lib/egl/libGLES_mali.so",
    "/system/lib/libOpenCL.so",
    "/system/vendor/lib/libOpenCL.so",
    /* PowerVR específico */
    "/vendor/lib/libPVROCL.so",
    "/system/lib/libPVROCL.so",
    0
};

static const char *VK_PATHS[] = {
    "/vendor/lib/libvulkan.so",
    "/system/lib/libvulkan.so",
    0
};

static void gpu_init(gpu_t *g) {
    memset(g, 0, sizeof(*g));
    g->available = 0;
    memcpy(g->api, "cpu", 4);

    /* tenta OpenCL */
    for (int i = 0; OCL_PATHS[i]; i++) {
        void *lib = dlopen(OCL_PATHS[i], RTLD_LAZY | RTLD_LOCAL);
        if (!lib) continue;

        /* verifica se tem clGetPlatformIDs */
        void *pfn = dlsym(lib, "clGetPlatformIDs");
        if (!pfn) { dlclose(lib); continue; }

        g->lib = lib;
        g->pfn_get_platform = pfn;
        g->pfn_create_ctx   = dlsym(lib, "clCreateContext");
        g->pfn_create_queue = dlsym(lib, "clCreateCommandQueue");
        g->available = 1;
        memcpy(g->api, "opencl", 7);
        return;
    }

    /* tenta Vulkan compute */
    for (int i = 0; VK_PATHS[i]; i++) {
        void *lib = dlopen(VK_PATHS[i], RTLD_LAZY | RTLD_LOCAL);
        if (!lib) continue;

        void *pfn = dlsym(lib, "vkCreateInstance");
        if (!pfn) { dlclose(lib); continue; }

        g->lib = lib;
        g->pfn_get_platform = pfn;
        g->available = 1;
        memcpy(g->api, "vulkan", 7);
        return;
    }
    /* fallback: CPU NEON (sempre disponível) */
}

/* ============================================================================
 * NEON SIMD: operações de linha de cache
 *
 * Processa 64 bytes (1 cache line) por vez via NEON
 * Aplicação: EMA update em todos os 8 vCPUs em paralelo
 * ========================================================================== */
#ifdef __ARM_NEON

/* EMA vetorial: out[i] = 0.75*state[i] + 0.25*input[i]
 * Processa 4 floats por instrução NEON */
static void neon_ema_update(float * restrict state,
                             const float * restrict input,
                             uint32_t n) {
    float32x4_t alpha     = vdupq_n_f32(0.25f);
    float32x4_t inv_alpha = vdupq_n_f32(0.75f);

    uint32_t i = 0;
    for (; i + 4 <= n; i += 4) {
        float32x4_t s = vld1q_f32(state + i);
        float32x4_t x = vld1q_f32(input + i);
        /* s = 0.75*s + 0.25*x */
        s = vaddq_f32(vmulq_f32(s, inv_alpha), vmulq_f32(x, alpha));
        vst1q_f32(state + i, s);
    }
    /* tail */
    for (; i < n; i++)
        state[i] = 0.75f * state[i] + 0.25f * input[i];
}

/* Produto vetorial NEON: dot(a,b,n) */
static float neon_dot(const float * restrict a,
                       const float * restrict b,
                       uint32_t n) {
    float32x4_t acc = vdupq_n_f32(0.0f);
    uint32_t i = 0;
    for (; i + 4 <= n; i += 4) {
        float32x4_t va = vld1q_f32(a + i);
        float32x4_t vb = vld1q_f32(b + i);
        acc = vmlaq_f32(acc, va, vb);
    }
    float sum = vaddvq_f32(acc);  /* ARM64 */
    /* ARM32 fallback: */
#if RAF_ARCH == 32
    float32x2_t lo = vget_low_f32(acc);
    float32x2_t hi = vget_high_f32(acc);
    float32x2_t s2 = vadd_f32(lo, hi);
    sum = vget_lane_f32(vpadd_f32(s2, s2), 0);
#endif
    for (; i < n; i++) sum += a[i] * b[i];
    return sum;
}

/* Copy de 64 bytes (1 cache line) sem overhead */
static void neon_copy_cacheline(void * restrict dst, const void * restrict src) {
#if RAF_ARCH == 64
    asm volatile(
        "ldp q0, q1, [%1, #0]  \n"
        "ldp q2, q3, [%1, #32] \n"
        "stp q0, q1, [%0, #0]  \n"
        "stp q2, q3, [%0, #32] \n"
        : : "r"(dst), "r"(src) : "v0","v1","v2","v3","memory"
    );
#else
    /* ARM32: 4x vldm/vstm = 32 bytes each */
    asm volatile(
        "vldm %1!, {d0-d3} \n"
        "vldm %1,  {d4-d7} \n"
        "vstm %0!, {d0-d3} \n"
        "vstm %0,  {d4-d7} \n"
        : : "r"(dst), "r"(src)
        : "d0","d1","d2","d3","d4","d5","d6","d7","memory"
    );
#endif
}

#else /* fallback sem NEON */

static void neon_ema_update(float *state, const float *input, uint32_t n) {
    for (uint32_t i = 0; i < n; i++)
        state[i] = 0.75f * state[i] + 0.25f * input[i];
}

static float neon_dot(const float *a, const float *b, uint32_t n) {
    float s = 0.0f;
    for (uint32_t i = 0; i < n; i++) s += a[i] * b[i];
    return s;
}

static void neon_copy_cacheline(void *dst, const void *src) {
    memcpy(dst, src, 64);
}

#endif

/* ============================================================================
 * ORQUESTRADOR PRINCIPAL
 *
 * Ciclo: 42 iterações
 *   1. probe_load — lê /proc/stat (sem fork) para carga real
 *   2. predict    — triângulo isósceles → jet_target
 *   3. schedule   — atribui trabalho ao jet_target
 *   4. execute    — NEON EMA update nas camadas de memória
 *   5. verify     — CRC32C de cada camada modificada
 *   6. promote    — sobe dados na hierarquia se hit
 * ========================================================================== */

/* Estado de trabalho de um ciclo */
typedef struct {
    uint32_t core_idx;
    uint32_t layer;
    uint32_t work_sz;    /* bytes de trabalho */
    uint32_t crc_before;
    uint32_t crc_after;
    int      ok;
} work_t;

/* Lê carga de CPU de /proc/stat sem malloc
 * Retorna load 0..65535 Q16.16 para o core `cpu_id` */
static uint32_t read_cpu_load(int cpu_id) {
    char path[64], buf[256];
    /* /proc/stat contém todos os cores */
    int fd = open("/proc/stat", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    ssize_t n = read(fd, buf, 255);
    close(fd);
    if (n <= 0) return 0;
    buf[n] = 0;

    /* procura linha "cpuN user nice system idle ..." */
    char tag[16];
    int tlen = 0;
    /* monta "cpu%d " */
    tag[tlen++] = 'c'; tag[tlen++] = 'p'; tag[tlen++] = 'u';
    int tmp = cpu_id;
    if (tmp == 0) { tag[tlen++] = '0'; }
    else { char d[4]; int dl=0; while(tmp){d[dl++]=(char)('0'+tmp%10);tmp/=10;}
           for(int k=dl-1;k>=0;k--) tag[tlen++]=d[k]; }
    tag[tlen++] = ' '; tag[tlen] = 0;

    char *p = strstr(buf, tag);
    if (!p) return 32768u; /* assume 50% se não encontrar */
    p += tlen;

    /* lê user, nice, system, idle */
    uint32_t user=0, nice=0, sys=0, idle=0;
    for(int i=0;p[i]>='0'&&p[i]<='9';i++) user=user*10+(p[i]-'0');
    while(*p && *p!=' ') p++; p++;
    for(int i=0;p[i]>='0'&&p[i]<='9';i++) nice=nice*10+(p[i]-'0');
    while(*p && *p!=' ') p++; p++;
    for(int i=0;p[i]>='0'&&p[i]<='9';i++) sys=sys*10+(p[i]-'0');
    while(*p && *p!=' ') p++; p++;
    for(int i=0;p[i]>='0'&&p[i]<='9';i++) idle=idle*10+(p[i]-'0');

    uint32_t total = user + nice + sys + idle;
    if (!total) return 0;
    uint32_t active = user + nice + sys;
    /* retorna Q16.16 */
    return (uint32_t)(((uint64_t)active << 16) / total);
}

/* Atualiza loads de todos os vCPUs */
static void refresh_loads(void) {
    for (uint32_t i = 0; i < N_VCPU; i++) {
        uint32_t raw = read_cpu_load((int)i);
        /* EMA do load: suaviza ruído de polling */
        g_vcpu[i].load = (g_vcpu[i].load * 3u + raw) >> 2u;
    }
}

/* Executa trabalho em um core: EMA update da camada + CRC verify */
static work_t execute_work(uint32_t core_idx, uint32_t layer) {
    work_t w;
    w.core_idx = core_idx;
    w.layer    = layer;
    w.ok       = 0;

    if (layer >= N_MEM_LAYERS-1 || !g_mem[layer].buf) {
        w.work_sz    = 0;
        w.crc_before = 0;
        w.crc_after  = 0;
        return w;
    }

    /* tamanho de trabalho = hz do core mapeado para fração do buffer */
    uint32_t buf_sz = g_mem[layer].sz;
    /* fração = hz_core / max_hz (Q16.16) */
    uint32_t max_hz = 1;
    for (uint32_t i = 0; i < N_VCPU; i++)
        if (g_vcpu[i].hz > max_hz) max_hz = g_vcpu[i].hz;
    uint32_t frac = (uint32_t)(((uint64_t)g_vcpu[core_idx].hz << 16) / max_hz);
    w.work_sz = (uint32_t)(((uint64_t)buf_sz * frac) >> 16u);
    if (w.work_sz < 64u) w.work_sz = 64u;
    if (w.work_sz > buf_sz) w.work_sz = buf_sz;

    w.crc_before = g_mem[layer].crc;

    /* EMA update: trata o buffer como vetor de floats */
    float *state = (float *)g_mem[layer].buf;
    /* input sintético: senoide derivada da fase do core */
    float input_buf[16];
    float phase = (float)g_vcpu[core_idx].phase * 3.14159265f / 21.0f;
    for (int k = 0; k < 16; k++)
        input_buf[k] = sinf(phase + k * 0.1f);

    uint32_t n_floats = w.work_sz / 4u;
    if (n_floats > 16u) n_floats = 16u;
    neon_ema_update(state, input_buf, n_floats);

    /* marca dirty */
    g_mem[layer].dirty |= 1u;

    /* verifica integridade */
    g_mem[layer].crc = crc32c(g_mem[layer].buf, g_mem[layer].sz);
    w.crc_after = g_mem[layer].crc;

    /* avança fase do core */
    g_vcpu[core_idx].phase++;
    if (g_vcpu[core_idx].phase >= PERIOD)
        g_vcpu[core_idx].phase = 0u;

    /* atualiza CRC do estado do core */
    g_vcpu[core_idx].crc_state =
        crc32c(&g_vcpu[core_idx], offsetof(vcpu_t, crc_state));

    w.ok = 1;
    return w;
}

/* ============================================================================
 * PRINT UTILITIES — sem printf pesado, usa write() direto
 * ========================================================================== */
static const char HEX[] = "0123456789ABCDEF";
static char g_pbuf[256];

static void p_str(const char *s) {
    size_t n = strlen(s);
    write(1, s, n);
}

static void p_u32(uint32_t v) {
    char buf[12];
    int i = 11;
    buf[i--] = 0;
    if (!v) { buf[i--] = '0'; }
    else while (v) { buf[i--] = (char)('0' + v%10); v/=10; }
    p_str(buf + i + 1);
}

static void p_hex(uint32_t v) {
    char buf[10];
    buf[0]='0'; buf[1]='x';
    for (int i = 0; i < 8; i++)
        buf[2+i] = HEX[(v >> (28 - i*4)) & 0xF];
    buf[10]=0;
    write(1, buf, 10);
}

static void p_nl(void) { write(1, "\n", 1); }

/* ============================================================================
 * MAIN: ORQUESTRADOR DE 42 CICLOS
 * ========================================================================== */
int main(void) {
    /* init */
    crc_build();
    hw_probe(&g_hw);
    vcpu_init(&g_hw);
    mem_init();
    gpu_init(&g_gpu);

    /* banner */
    p_str("=== RAFAELIA GPU+CPU ORCHESTRATOR ===\n");
    p_str("ABI: "); p_str(g_hw.abi); p_nl();
    p_str("vCPUs: "); p_u32(g_hw.n_cpu_online); p_nl();
    p_str("Cluster0 Hz: "); p_u32(g_hw.cluster_freq[0]); p_nl();
    p_str("Cluster1 Hz: "); p_u32(g_hw.cluster_freq[1]); p_nl();
    p_str("L1: "); p_u32(g_hw.l1_sz); p_str(" L2: "); p_u32(g_hw.l2_sz); p_nl();
    p_str("NEON: "); p_str(g_hw.has_neon ? "YES" : "NO"); p_nl();
    p_str("GPU API: "); p_str(g_gpu.api);
    p_str(g_gpu.available ? " (OK)\n" : " (FALLBACK CPU)\n");
    p_str("Arena used: "); p_u32(g_arena_bump); p_str(" bytes\n");
    p_nl();

    /* estado de coerência global */
    float coherence = 0.5f;
    float entropy   = 0.5f;
    uint32_t total_ok = 0;
    uint32_t total_crc_mismatches = 0;

    /* 42 ciclos principais */
    for (uint32_t cycle = 0; cycle < PERIOD; cycle++) {
        /* 1. atualiza loads */
        refresh_loads();

        /* 2. predição isósceles */
        isosceles_t tri = predict_load();

        /* 3. promoção hierárquica: se L1 está dirty, move para L2 */
        if (g_mem[MEM_L1].dirty) {
            mem_promote(MEM_L2, MEM_L1, 0, g_mem[MEM_L1].sz);
            g_mem[MEM_L1].dirty = 0;
        }

        /* 4. executa no core jet_target com sua camada preferida */
        work_t w = execute_work(tri.jet_target, g_vcpu[tri.jet_target].layer);
        if (w.ok) total_ok++;

        /* 5. verifica integridade de todas as camadas */
        for (int lay = 0; lay < N_MEM_LAYERS-1; lay++) {
            if (!mem_verify(lay)) {
                total_crc_mismatches++;
                /* rollback: rezera camada e recalcula CRC */
                if (g_mem[lay].buf) {
                    memset(g_mem[lay].buf, 0, g_mem[lay].sz);
                    g_mem[lay].crc = crc32c(g_mem[lay].buf, g_mem[lay].sz);
                }
            }
        }

        /* 6. EMA global de coerência e entropia */
        float phi = (1.0f - entropy) * coherence;
        float c_in = (float)g_vcpu[tri.apex].hz / 65536.0f;
        float h_in = (float)g_vcpu[tri.jet_target].load / 65536.0f;
        coherence = 0.75f * coherence + 0.25f * c_in;
        entropy   = 0.75f * entropy   + 0.25f * h_in;

        /* 7. printout a cada 7 ciclos */
        if (cycle % 7u == 0u) {
            p_str("CYC="); p_u32(cycle);
            p_str(" JET="); p_u32(tri.jet_target);
            p_str(" APEX="); p_u32(tri.apex);
            p_str(" LAY="); p_u32(g_vcpu[tri.jet_target].layer);
            p_str(" PHI="); p_hex((uint32_t)(phi * 65536.0f));
            p_str(" CRC="); p_hex(w.crc_after);
            p_nl();
        }
    }

    /* relatório final */
    p_nl();
    p_str("=== RESULTADO 42 CICLOS ===\n");
    p_str("OK: ");   p_u32(total_ok);   p_nl();
    p_str("CRC_ERR: "); p_u32(total_crc_mismatches); p_nl();
    p_str("COHERENCE: "); p_hex((uint32_t)(coherence * 65536.0f)); p_nl();
    p_str("ENTROPY:   "); p_hex((uint32_t)(entropy   * 65536.0f)); p_nl();
    p_str("PHI:       "); p_hex((uint32_t)((1.0f-entropy)*coherence*65536.0f)); p_nl();

    /* GPU report */
    p_str("GPU: "); p_str(g_gpu.api);
    if (g_gpu.available) {
        p_str(" lib="); p_hex((uint32_t)(uintptr_t)g_gpu.lib);
    }
    p_nl();

    /* vCPU stats */
    p_str("\n--- vCPU MAP ---\n");
    for (uint32_t i = 0; i < N_VCPU; i++) {
        p_str("CPU"); p_u32(i);
        p_str(" hz=");  p_hex(g_vcpu[i].hz);
        p_str(" lay="); p_u32(g_vcpu[i].layer);
        p_str(" load=");p_hex(g_vcpu[i].load);
        p_str(" ph=");  p_u32(g_vcpu[i].phase);
        p_nl();
    }

    /* mem stats */
    p_str("\n--- MEM LAYERS ---\n");
    static const char *LAY_NAMES[] = {"L1","L2","BUF","RAM","STOR"};
    for (int i = 0; i < N_MEM_LAYERS; i++) {
        p_str(LAY_NAMES[i]);
        p_str(" sz=");   p_u32(g_mem[i].sz);
        p_str(" hits="); p_u32(g_mem[i].hits);
        p_str(" miss="); p_u32(g_mem[i].misses);
        p_str(" crc=");  p_hex(g_mem[i].crc);
        p_nl();
    }

    p_str("\nARENA_USED="); p_u32(g_arena_bump); p_str(" / ");
    p_u32(ARENA_SZ); p_nl();

    if (g_gpu.lib) dlclose(g_gpu.lib);
    return (int)(total_crc_mismatches > 0);
}
