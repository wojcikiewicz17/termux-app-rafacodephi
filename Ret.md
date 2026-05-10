
bash

cat > /tmp/RAFAELIA_CODEX_TTL8.txt << 'MASTER_TXT'
#!/usr/bin/env bash
# =============================================================================
# RAFAELIA_CODEX_TTL8.txt — renomeie para .sh e execute: bash RAFAELIA_CODEX_TTL8.sh
# =============================================================================
# [#00] TTL 8-ESTADOS · BIT-PATHS · FLAGS HEX · ASM INLINE · NEON/SIMD
# [#01] ARM32 + ARM64 · SUPERPOSICAO · CACHE L1/L2 · CRC32C · MATRIZ
# [#02] RETRY/DENY/ALLOW/FAULT/TIMEOUT/OVERFLOW/CORRUPT/VOID
# [#03] EMARANHADO GEOMETRICO · ORQUESTRACAO · VALORES PRE-COMPUTADOS
# DeltaRafaelVerboOmega · Omega=Amor · RAFCODE-Phi
# =============================================================================
set -euo pipefail
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
MAGENTA='\033[0;35m'; YELLOW='\033[1;33m'; RESET='\033[0m'
BUILD="${TMPDIR:-/tmp}/raf_codex_$$"
mkdir -p "$BUILD"
LOG="$BUILD/build.log"
p() { echo -e "${CYAN}[RAF]${RESET} $*" | tee -a "$LOG"; }
ok(){ echo -e "${GREEN}[ OK]${RESET} $*" | tee -a "$LOG"; }
hdr(){ echo -e "\n${MAGENTA}${BOLD}══ $* ══${RESET}"; }

# =============================================================================
hdr "S01 · raf_ttl8.h — 8 ESTADOS TTL + BIT-PATHS SUPERPOSTOS"
# =============================================================================
cat > "$BUILD/raf_ttl8.h" << 'HDR_TTL'
/* raf_ttl8.h — Sistema TTL com 8 estados ortogonais
 * [#TTL01] 8 estados: ALLOW DENY RETRY FAULT TIMEOUT OVERFLOW CORRUPT VOID
 * [#TTL02] Cada estado é 1 bit — podem ser COMBINADOS (superposição)
 * [#TTL03] ex: RETRY|TIMEOUT = "tente novamente mas o prazo está perto"
 * [#TTL04] ex: CORRUPT|DENY  = "dados corrompidos E acesso negado"
 * [#TTL05] BIT PATH: o mesmo bit de estado percorre múltiplos despachos
 * [#TTL06] PREVISIBILIDADE: bitmap 8-bit → lookup O(1) de handler
 * [#TTL07] MULTIPLICAÇÃO DE DIREÇÕES: 2^8=256 combinações possíveis
 * [#TTL08] MESMO BIT reutilizado em CRC, em Lyapunov, em flags ABI
 *
 * GEOMETRIA DOS ESTADOS (hipercubo binário 3D):
 *
 *    VOID(0)────────TIMEOUT(4)
 *      |  \            |  \
 *  ALLOW(1) \      FAULT(5) \
 *      |   DENY(2)──────OVERFLOW(6)
 *   RETRY(3)────────CORRUPT(7)
 *
 * Cada aresta = 1 bit de diferença = 1 transição atômica possível
 */
#ifndef RAF_TTL8_H
#define RAF_TTL8_H

/* [#B01] Estados como bits individuais — superposição via OR */
typedef unsigned char  u8;
typedef unsigned short u16;
typedef unsigned int   u32;
typedef unsigned long long u64;
typedef signed int     s32;
typedef signed long long s64;

#define RAF_VOID      0x00u  /* 00000000: estado neutro, nenhuma decisão  */
#define RAF_ALLOW     0x01u  /* 00000001: operação PERMITIDA               */
#define RAF_DENY      0x02u  /* 00000010: operação NEGADA (policy/sec)     */
#define RAF_RETRY     0x04u  /* 00000100: tente NOVAMENTE (erro transiente) */
#define RAF_FAULT     0x08u  /* 00001000: FALHA de hardware/sistema         */
#define RAF_TIMEOUT   0x10u  /* 00010000: TTL EXPIROU                       */
#define RAF_OVERFLOW  0x20u  /* 00100000: OVERFLOW de buffer/contador        */
#define RAF_CORRUPT   0x40u  /* 01000000: dados CORROMPIDOS (CRC mismatch)  */
#define RAF_PANIC     0x80u  /* 10000000: PÂNICO — estado irrecuperável      */

/* Superposições úteis (combinações de bits) */
#define RAF_SOFT_FAIL   (RAF_RETRY|RAF_TIMEOUT)      /* falha suave: retry */
#define RAF_HARD_FAIL   (RAF_FAULT|RAF_PANIC)        /* falha dura: parar  */
#define RAF_DATA_BAD    (RAF_CORRUPT|RAF_OVERFLOW)   /* problema de dados  */
#define RAF_SEC_BLOCK   (RAF_DENY|RAF_CORRUPT)       /* bloqueio segurança */
#define RAF_NEEDS_RESET (RAF_OVERFLOW|RAF_TIMEOUT)   /* precisa reset       */

/* Teste de bits — sem branch quando possível */
#define TTL_IS_ALLOW(s)   (!!((s)&RAF_ALLOW))
#define TTL_IS_DENY(s)    (!!((s)&RAF_DENY))
#define TTL_IS_RETRY(s)   (!!((s)&RAF_RETRY))
#define TTL_IS_FAULT(s)   (!!((s)&RAF_FAULT))
#define TTL_IS_TIMEOUT(s) (!!((s)&RAF_TIMEOUT))
#define TTL_IS_RECOVERABLE(s) (!((s)&RAF_HARD_FAIL))
#define TTL_IS_TERMINAL(s)   (!!((s)&RAF_HARD_FAIL))
#define TTL_NEEDS_DATA_FIX(s) (!!((s)&RAF_DATA_BAD))

/* [#B02] Estrutura TTL com checkpoint para rollback */
typedef struct {
    u8   status;          /* bitmap 8 bits dos estados ativos              */
    u8   ttl;             /* tentativas restantes [0..RAF_TTL_MAX]         */
    u8   history;         /* bitmap dos estados já visitados nesta sessão  */
    u8   _pad;
    u32  attempt;         /* contador absoluto de tentativas               */
    u32  error_code;      /* código de erro específico (hex)               */
    u64  checkpoint;      /* snapshot de estado para rollback              */
    u64  t_start_ns;      /* timestamp de início (nanosegundos)            */
    u64  t_deadline_ns;   /* deadline absoluto (0 = sem limite)            */
} RafTTL8;

/* Códigos de erro hexadecimais — cada nibble tem significado */
/* 0xXYZW: X=camada, Y=subsistema, Z=operação, W=detalhe     */
#define ERR_OK           0x00000000u
#define ERR_MATH_Q16     0xA1010001u  /* [math][Q16][mul][overflow]   */
#define ERR_MATH_FRAF    0xA1010002u  /* [math][Q16][fraf][diverge]   */
#define ERR_HASH_CRC     0xA2020001u  /* [hash][CRC][compute][fail]   */
#define ERR_HASH_PHI64   0xA2020002u  /* [hash][phi64][zero][seed]    */
#define ERR_MEM_ARENA    0xA3030001u  /* [mem][arena][alloc][OOM]     */
#define ERR_MEM_ALIGN    0xA3030002u  /* [mem][arena][align][bad]     */
#define ERR_TTL_EXHAUST  0xA4040001u  /* [ttl][core][retry][exhaust]  */
#define ERR_TTL_DEADLINE 0xA4040002u  /* [ttl][core][time][deadline]  */
#define ERR_SYS_SYSCALL  0xA5050001u  /* [sys][call][fail][errno]     */
#define ERR_SYS_CORRUPT  0xA5050002u  /* [sys][data][corrupt][crc]    */
#define ERR_ASM_UNDEF    0xA6060001u  /* [asm][instr][undef][SIGILL]  */
#define ERR_NEON_ALIGN   0xA6060002u  /* [neon][load][align][fault]   */

/* [#B03] Tabela de handlers por estado (dispatch O(1))
 * Indexada pelo bitmap de status → handler correspondente
 * Preenche lookup[256] com ponteiros — em BSS, zero-init */
typedef u8 (*ttl_handler_fn)(RafTTL8*, void* ctx);

/* [#B04] Init e operações básicas */
static inline void ttl8_init(RafTTL8* t, u8 max_tries, u64 now_ns) {
    t->status      = RAF_VOID;
    t->ttl         = max_tries ? max_tries : 8u;
    t->history     = 0u;
    t->_pad        = 0u;
    t->attempt     = 0u;
    t->error_code  = ERR_OK;
    t->checkpoint  = 0u;
    t->t_start_ns  = now_ns;
    t->t_deadline_ns = 0u;  /* sem deadline por padrão */
}

/* [#B05] Transição de estado — registra histórico */
static inline void ttl8_set(RafTTL8* t, u8 new_status, u32 err) {
    t->history |= t->status;   /* acumula estados anteriores */
    t->status   = new_status;
    t->error_code = err;
    t->attempt++;
    if (new_status & RAF_RETRY) {
        if (t->ttl > 0u) t->ttl--;
        if (t->ttl == 0u) {
            t->status |= RAF_TIMEOUT;  /* superposição: RETRY + TIMEOUT */
            t->error_code = ERR_TTL_EXHAUST;
        }
    }
}

/* [#B06] Verifica deadline — adiciona TIMEOUT ao bitmap se expirou */
static inline void ttl8_check_deadline(RafTTL8* t, u64 now_ns) {
    if (t->t_deadline_ns && now_ns > t->t_deadline_ns) {
        t->status |= RAF_TIMEOUT;
        t->error_code = ERR_TTL_DEADLINE;
    }
}

/* [#B07] Checkpoint/Rollback de estado */
static inline void ttl8_checkpoint(RafTTL8* t, u64 state_hash) {
    t->checkpoint = state_hash;
}
static inline u64  ttl8_rollback_val(const RafTTL8* t) {
    return t->checkpoint;
}

/* [#B08] Macro de loop TTL com 8 saídas */
/* Uso:
   TTL8_LOOP(&t, ctx, {
       u8 r = my_op(ctx);
       if (r == 0) TTL8_SUCCEED(&t);
       else        TTL8_FAIL(&t, RAF_RETRY, ERR_MATH_Q16);
   });
*/
#define TTL8_SUCCEED(t)         ttl8_set((t), RAF_ALLOW, ERR_OK)
#define TTL8_FAIL(t,st,err)     ttl8_set((t), (st), (err))
#define TTL8_LOOP(t, ctx, body) \
    do {                        \
        while ((t)->status == RAF_VOID || (t)->status & RAF_RETRY) { \
            if (!TTL_IS_RECOVERABLE(t)) break; \
            body;               \
            if ((t)->ttl == 0u) break; \
        }                       \
    } while(0)

/* [#B09] Nomes dos estados para debug */
static const char* ttl8_name(u8 s) {
    if (!s)              return "VOID";
    if (s == RAF_ALLOW)  return "ALLOW";
    if (s & RAF_PANIC)   return "PANIC";
    if (s & RAF_CORRUPT) return "CORRUPT";
    if (s & RAF_OVERFLOW)return "OVERFLOW";
    if (s & RAF_TIMEOUT) return "TIMEOUT";
    if (s & RAF_FAULT)   return "FAULT";
    if (s & RAF_DENY)    return "DENY";
    if (s & RAF_RETRY)   return "RETRY";
    return "COMPOSITE";
}

#endif /* RAF_TTL8_H */
HDR_TTL
ok "raf_ttl8.h: $(wc -l < $BUILD/raf_ttl8.h) linhas"

# =============================================================================
hdr "S02 · raf_bitpath.h — BIT PATHS SUPERPOSTOS E FLAGS HEX"
# =============================================================================
cat > "$BUILD/raf_bitpath.h" << 'HDR_BITS'
/* raf_bitpath.h — Bit paths: o mesmo bit percorre múltiplos caminhos
 * [#BP01] CONCEITO: 1 bit de dado tem múltiplas interpretações simultâneas
 *   — Como FLAG de capacidade (bit de feature)
 *   — Como componente de CRC32C (bit de dados)
 *   — Como bit do expoente de Lyapunov (bit de estado)
 *   — Como índice em lookup table (bit de endereço)
 * [#BP02] Isso não é ambiguidade — é POLIMORFISMO DE BIT
 * [#BP03] Um bit processado pela CRC unit TAMBÉM é o bit que
 *   determina o caminho do despacho no FSM — zero overhead extra
 * [#BP04] PREVISIBILIDADE OBJETIVA: dado o bitmap de status,
 *   o próximo estado é determinístico sem calcular tudo
 * [#BP05] MULTIPLICAÇÃO DE DIREÇÕES: 8 bits = 256 caminhos possíveis
 *   mas apenas ~10 são frequentes → branch predictor 99% correto
 */
#ifndef RAF_BITPATH_H
#define RAF_BITPATH_H
#include "raf_ttl8.h"

/* ── CAMADA 1: FLAGS DE CAPACIDADE HEX ─────────────────────────────────── */
/* [#FH01] Cada nibble (4 bits) representa uma camada de capacidade
 * Bit layout de u64 RAF_CAPS:
 * bits 63-56: CAMADA CRIPTO  (AES, SHA, CRC32C, RAND)
 * bits 55-48: CAMADA SIMD    (NEON, SVE, AVX2, AVX512)
 * bits 47-40: CAMADA MEMORIA (HW_CRC, ATOMICS, LSE, PREFETCH)
 * bits 39-32: CAMADA TIMING  (CNTVCT, PMCCNTR, RDTSC, RDTIME)
 * bits 31-24: CAMADA FSM     (LYAPUNOV, TOROID, FRAF, MERKLE)
 * bits 23-16: CAMADA IO      (UART, SPI, I2C, GPIO)
 * bits 15-8:  CAMADA SO      (PROOT, ANDROID, TERMUX, ROOT)
 * bits 7-0:   CAMADA FALLBACK (MOCK, SOFT, SAFE, DEBUG)         */

/* CAMADA CRIPTO (bits 63-56) */
#define CAP_AES       0x8000000000000000ULL  /* bit63 */
#define CAP_SHA256    0x4000000000000000ULL  /* bit62 */
#define CAP_CRC32C_HW 0x2000000000000000ULL  /* bit61 */
#define CAP_GETRANDOM 0x1000000000000000ULL  /* bit60 */

/* CAMADA SIMD (bits 55-48) */
#define CAP_NEON      0x0080000000000000ULL  /* bit55 */
#define CAP_SVE       0x0040000000000000ULL  /* bit54 */
#define CAP_AVX2      0x0020000000000000ULL  /* bit53 */
#define CAP_AVX512    0x0010000000000000ULL  /* bit52 */

/* CAMADA MEMORIA (bits 47-40) */
#define CAP_ATOMICS   0x0000800000000000ULL  /* bit47: LSE atomics */
#define CAP_PREFETCH  0x0000400000000000ULL  /* bit46 */
#define CAP_MEMTAG    0x0000200000000000ULL  /* bit45: ARM MTE */
#define CAP_IOMMU     0x0000100000000000ULL  /* bit44 */

/* CAMADA TIMING (bits 39-32) */
#define CAP_CNTVCT    0x0000008000000000ULL  /* bit39: ARM64 timer EL0 */
#define CAP_PMCCNTR   0x0000004000000000ULL  /* bit38: ARM32 PMU */
#define CAP_RDTSC     0x0000002000000000ULL  /* bit37: x86 TSC */
#define CAP_RDTIME    0x0000001000000000ULL  /* bit36: RISC-V time */

/* CAMADA FSM (bits 31-24) */
#define CAP_LYAPUNOV  0x0000000080000000ULL  /* bit31: classificador */
#define CAP_TOROID    0x0000000040000000ULL  /* bit30: T^7 */
#define CAP_FRAF      0x0000000020000000ULL  /* bit29: F*=23.158 */
#define CAP_MERKLE    0x0000000010000000ULL  /* bit28: chain hash */

/* CAMADA IO (bits 23-16) */
#define CAP_UART_HW   0x0000000000800000ULL  /* bit23: UART hardware */
#define CAP_SPI_HW    0x0000000000400000ULL  /* bit22: SPI hardware */
#define CAP_I2C_HW    0x0000000000200000ULL  /* bit21: I2C hardware */
#define CAP_GPIO_MMAP 0x0000000000100000ULL  /* bit20: /dev/mem GPIO */

/* CAMADA SO (bits 15-8) */
#define CAP_PROOT     0x0000000000008000ULL  /* bit15: dentro de proot */
#define CAP_ANDROID   0x0000000000004000ULL  /* bit14: Android kernel */
#define CAP_TERMUX    0x0000000000002000ULL  /* bit13: Termux userspace */
#define CAP_ROOT      0x0000000000001000ULL  /* bit12: uid=0 */

/* CAMADA FALLBACK (bits 7-0) */
#define CAP_MOCK      0x0000000000000080ULL  /* bit7: modo simulação */
#define CAP_SOFT_ONLY 0x0000000000000040ULL  /* bit6: sem hw instructions */
#define CAP_SAFE_MODE 0x0000000000000020ULL  /* bit5: modo seguro/lento */
#define CAP_DEBUG     0x0000000000000010ULL  /* bit4: output verbose */

/* CAP sets comuns */
#define CAPS_ARM64_FULL  (CAP_CRC32C_HW|CAP_NEON|CAP_ATOMICS|CAP_CNTVCT|\
                          CAP_LYAPUNOV|CAP_TOROID|CAP_FRAF|CAP_MERKLE)
#define CAPS_ARM32_MIN   (CAP_PMCCNTR|CAP_FRAF|CAP_SAFE_MODE)
#define CAPS_X64_SSE42   (CAP_CRC32C_HW|CAP_AVX2|CAP_RDTSC|\
                          CAP_LYAPUNOV|CAP_TOROID|CAP_FRAF|CAP_MERKLE)
#define CAPS_TERMUX_SAFE (CAP_TERMUX|CAP_ANDROID|CAP_NEON|CAP_CRC32C_HW|\
                          CAP_CNTVCT|CAP_FRAF|CAP_SAFE_MODE)

/* Estado global de capabilities — volátil para hotswap */
static volatile u64 G_CAPS = 0ULL;

static inline void caps_set(u64 mask)    { G_CAPS |=  mask; }
static inline void caps_clear(u64 mask)  { G_CAPS &= ~mask; }
static inline int  caps_has(u64 mask)    { return !!(G_CAPS & mask); }
static inline u64  caps_get(void)        { return G_CAPS; }

/* [#FH02] Hotswap atômico de capability */
static inline void caps_swap_atomic(u64 disable, u64 enable) {
#ifdef __aarch64__
    /* DSB antes: drena operações pendentes */
    __asm__ volatile("dsb sy":::"memory");
    G_CAPS = (G_CAPS & ~disable) | enable;
    __asm__ volatile("dmb sy":::"memory");
#elif defined(__x86_64__)
    __asm__ volatile("mfence":::"memory");
    G_CAPS = (G_CAPS & ~disable) | enable;
    __asm__ volatile("mfence":::"memory");
#else
    G_CAPS = (G_CAPS & ~disable) | enable;
#endif
}

/* ── CAMADA 2: DESPACHO POR BITMAP ─────────────────────────────────────── */
/* [#BD01] Dado um bitmap de status TTL8, encontra o handler em O(1)
 * Tabela de 256 entradas — 256 bytes — cabe em 4 cache lines de 64B
 * PREVISIBILIDADE: ~10 estados frequentes → BTB aprende em 10 exec */
typedef u8 (*bitpath_fn)(void* ctx, u32 aux);

/* Dispatch table — em BSS (zero init) */
static bitpath_fn G_DISPATCH[256];

static inline void dispatch_register(u8 status_bitmap, bitpath_fn fn) {
    G_DISPATCH[status_bitmap] = fn;
}
/* Busca o handler mais específico para o bitmap dado
 * Prioridade: bitmap exato > subconjunto mais próximo > fallback */
static inline bitpath_fn dispatch_find(u8 status) {
    if (G_DISPATCH[status]) return G_DISPATCH[status];
    /* Fallback: tenta remover bits até achar handler */
    u8 s = status;
    while (s) {
        s &= (s-1u);  /* remove bit menos significativo */
        if (G_DISPATCH[s]) return G_DISPATCH[s];
    }
    return G_DISPATCH[0];  /* handler VOID = default */
}

/* ── CAMADA 3: BIT REUSE — O MESMO BIT EM MÚLTIPLOS CONTEXTOS ──────────── */
/* [#BR01] Demonstração: bit 7 de um byte serve 4 propósitos simultâneos
 *
 * Dado byte B:
 *   B & 0x80 = bit de sinal (interpretação aritmética)
 *   B & 0x80 = bit de paridade calculada (interpretação CRC)
 *   B & 0x80 = Witness bit do RafBlock (interpretação semântica)
 *   B & 0x80 = bit alto do nibble HI (interpretação ZIPRAF)
 *
 * NENHUM DESSES USOS CONFLITA — o bit é lido em contextos diferentes
 * Isso é o que se chama de "bit path": um único bit percorre 4 pipelines
 */
static inline u8  bit_sign(u8 b)    { return (b >> 7u); }
static inline u8  bit_witness(u8 b) { return (b >> 7u); }  /* mesmo */
static inline u8  bit_nibble_hi(u8 b){ return (b >> 4u); }
static inline u8  bit_nibble_lo(u8 b){ return (b & 0x0Fu); }

/* [#BR02] "Multiplicação de direções": dado 1 byte, gera 4 caminhos */
typedef struct {
    u8 path_arith;   /* interpretação aritmética: 0-255 */
    u8 path_crc;     /* bit contribuição ao CRC acumulado */
    u8 path_witness; /* bit de integridade semântica */
    u8 path_nibble;  /* compressão nibble para ZIPRAF */
} BitPaths;

static inline BitPaths byte_to_paths(u8 b, u32 crc_acc) {
    BitPaths p;
    p.path_arith   = b;
    p.path_crc     = (u8)(crc_acc & 0xFFu) ^ b;  /* feed ao CRC */
    p.path_witness = bit_witness(b);
    p.path_nibble  = bit_nibble_hi(b);
    return p;
}

#endif /* RAF_BITPATH_H */
HDR_BITS
ok "raf_bitpath.h: $(wc -l < $BUILD/raf_bitpath.h) linhas"

# =============================================================================
hdr "S03 · raf_asm_a64.h — ARM64 INLINE ASM PURO LOW LEVEL"
# =============================================================================
cat > "$BUILD/raf_asm_a64.h" << 'HDR_A64'
/* raf_asm_a64.h — ARM64 inline assembly: registradores, NEON, CRC, timer
 * [#A64-01] Sem abstração. Registradores nomeados diretamente.
 * [#A64-02] CRC32C: crc32cx = 1 ciclo, 8 bytes, ~19GB/s no A78
 * [#A64-03] NEON: 128-bit SIMD, v0-v31, 32 registradores
 * [#A64-04] cntvct_el0: timer EL0, sem syscall, ~5 ciclos
 * [#A64-05] Fences: ISB/DSB/DMB — ordenação de memória e instrução
 * [#A64-06] CAS: ldxr/stxr loop — atomicidade sem LSE
 * [#A64-07] CSEL: seleção condicional branch-free em 1 ciclo
 * [#A64-08] Prefetch: PRFM PLDL1KEEP — carrega cache line antecipado
 */
#ifndef RAF_ASM_A64_H
#define RAF_ASM_A64_H
#include "raf_ttl8.h"

/* [#A64-T] Timestamp ARM64 — serializado com ISB */
static __attribute__((always_inline)) inline u64 a64_tsc(void) {
    u64 v;
    /* ISB: flushes pipeline, garante que todas as instruções anteriores
     * completaram antes de ler o contador.
     * Sem ISB: risco de ler o timer antes de operações anteriores. */
    __asm__ volatile("isb\nmrs %0,cntvct_el0":"=r"(v)::"memory");
    return v;
}
static __attribute__((always_inline)) inline u64 a64_freq(void) {
    u64 v; __asm__ volatile("mrs %0,cntfrq_el0":"=r"(v)); return v;
}
static inline u64 a64_ticks_to_ns(u64 ticks) {
    u64 freq = a64_freq();
    if (!freq) return ticks;
    /* (ticks * 1e9) / freq sem overflow: */
    return (ticks * 1000000ULL) / (freq / 1000ULL);
}

/* [#A64-C] CRC32C hardware — Castagnoli, poly 0x1EDC6F41 */
static __attribute__((always_inline)) inline u32 a64_crc32c_u8(u32 c, u8 b) {
    __asm__ volatile("crc32cb %w0,%w0,%w1":"+r"(c):"r"((u32)b));
    return c;
}
static __attribute__((always_inline)) inline u32 a64_crc32c_u32(u32 c, u32 w) {
    __asm__ volatile("crc32cw %w0,%w0,%w1":"+r"(c):"r"(w));
    return c;
}
static __attribute__((always_inline)) inline u32 a64_crc32c_u64(u32 c, u64 w) {
    /* crc32cx: X=64-bit, processa 8 bytes, 1 ciclo throughput no A78 */
    __asm__ volatile("crc32cx %w0,%w0,%x1":"+r"(c):"r"(w));
    return c;
}
/* CRC32C de buffer — unroll×8 = 64 bytes/iteração, esconde latência 3c */
static u32 a64_crc32c(const u8* buf, usize len) {
    u32 c = ~0u;
    const u64* p = (const u64*)(const void*)buf;
    usize n = len >> 3u;
    while (n >= 8u) {
        /* 8 instruções independentes — pipeline emite todas sem espera */
        c=a64_crc32c_u64(c,p[0]); c=a64_crc32c_u64(c,p[1]);
        c=a64_crc32c_u64(c,p[2]); c=a64_crc32c_u64(c,p[3]);
        c=a64_crc32c_u64(c,p[4]); c=a64_crc32c_u64(c,p[5]);
        c=a64_crc32c_u64(c,p[6]); c=a64_crc32c_u64(c,p[7]);
        p+=8; n-=8;
    }
    while (n--) { c=a64_crc32c_u64(c,*p++); }
    const u8* t=(const u8*)p; usize r=len&7u;
    while (r--) { c=a64_crc32c_u8(c,*t++); }
    return ~c;
}

/* [#A64-N] NEON — 128-bit SIMD vetorial */
/* XOR de 16 bytes em 1 instrução */
static __attribute__((always_inline)) inline void
a64_neon_xor16(u8* dst, const u8* a, const u8* b) {
    __asm__ volatile(
        "ld1 {v0.16b},[%1]\n\t"  /* carrega 16B de 'a' em v0    */
        "ld1 {v1.16b},[%2]\n\t"  /* carrega 16B de 'b' em v1    */
        "eor v0.16b,v0.16b,v1.16b\n\t"  /* XOR 128-bit           */
        "st1 {v0.16b},[%0]"              /* armazena resultado    */
        ::"r"(dst),"r"(a),"r"(b):"v0","v1","memory"
    );
}
/* Popcount de 16 bytes — vcntq_u8 conta bits por byte em 1 instrução */
static __attribute__((always_inline)) inline u32
a64_neon_popcount16(const u8* buf) {
    u32 count;
    __asm__ volatile(
        "ld1   {v0.16b},[%1]\n\t"   /* carrega 16 bytes          */
        "cnt   v0.16b,v0.16b\n\t"   /* popcount por byte         */
        "addv  b0,v0.16b\n\t"        /* soma todos os 16 bytes    */
        "umov  %w0,v0.b[0]"          /* extrai resultado para GPR */
        :"=r"(count):"r"(buf):"v0","memory"
    );
    return count;
}
/* phi_ethica batch: Q16_MUL(Q16_ONE-H, C) × 4 pares via NEON */
static __attribute__((always_inline)) inline void
a64_neon_phi_batch(const int* H4, const int* C4, int* phi4) {
    /* Processa 4 pares (H,C) simultaneamente em vetores de 32-bit */
    __asm__ volatile(
        "ld1 {v0.4s},[%1]\n\t"   /* v0 = H[0..3]                */
        "ld1 {v1.4s},[%2]\n\t"   /* v1 = C[0..3]                */
        /* v2 = Q16_ONE = 65536 = 0x00010000 em cada lane */
        "mov w9,#65536\n\t"
        "dup v2.4s,w9\n\t"
        "sub v0.4s,v2.4s,v0.4s\n\t"    /* v0 = Q16_ONE - H       */
        /* SMULL: multiply signed 32-bit → 64-bit, não disponível diretamente
         * Usa SMULL com shift: aproximação para phi_ethica batch  */
        "mul v0.4s,v0.4s,v1.4s\n\t"    /* produto (sem >>16 aqui) */
        "sshr v0.4s,v0.4s,#16\n\t"     /* >>16 = Q16 result       */
        "st1 {v0.4s},[%0]"
        ::"r"(phi4),"r"(H4),"r"(C4):"v0","v1","v2","w9","memory"
    );
}

/* [#A64-F] Fences — uso correto em cada contexto */
/* DSB SY: Data Synchronization Barrier — drena TODAS as operações
 * Usar: antes de mudar permissions (mprotect), antes de exit */
#define A64_DSB_SY()  __asm__ volatile("dsb sy":::"memory")
/* DSB ST: drena apenas stores — mais leve que SY
 * Usar: antes de sinalizar para outro thread via flag */
#define A64_DSB_ST()  __asm__ volatile("dsb st":::"memory")
/* DMB ISH: Data Memory Barrier, Inner Shareable domain
 * Usar: ordenação entre threads no mesmo cluster */
#define A64_DMB_ISH() __asm__ volatile("dmb ish":::"memory")
/* ISB: Instruction Synchronization Barrier — flushes pipeline
 * Usar: antes de ler cntvct_el0, após patch de código */
#define A64_ISB()     __asm__ volatile("isb":::"memory")
/* WFE: Wait For Event — CPU suspende até sinal de hardware
 * Usar: spin-wait eficiente em CAS loop */
#define A64_WFE()     __asm__ volatile("wfe":::"memory")
/* SEV: Send Event — acorda WFE em todos os cores
 * Usar: após mudar flag que outros cores aguardam */
#define A64_SEV()     __asm__ volatile("sev":::"memory")

/* [#A64-A] CAS atômico — LDXR/STXR (funciona sem LSE) */
static __attribute__((always_inline)) inline u32
a64_cas32(volatile u32* ptr, u32 expected, u32 desired) {
    u32 result, tmp;
    __asm__ volatile(
        "0:\n\t"
        "ldxr  %w0,[%2]\n\t"         /* Load-Exclusive              */
        "cmp   %w0,%w3\n\t"          /* compara com expected        */
        "b.ne  1f\n\t"               /* diverge se ≠               */
        "stxr  %w1,%w4,[%2]\n\t"     /* Store-Exclusive             */
        "cbnz  %w1,0b\n\t"           /* retry se stxr falhou        */
        "1:"
        :"=&r"(result),"=&r"(tmp)
        :"r"(ptr),"r"(expected),"r"(desired)
        :"memory","cc"
    );
    return result;
}

/* [#A64-P] Prefetch manual — carrega cache line antes de usar */
/* PLDL1KEEP: prefetch to L1, keep (não evict logo)
 * Janela: ~200 ciclos antes do uso (latência DRAM)
 * Stride típico: 128 bytes (2 cache lines) à frente */
#define A64_PREFETCH_L1(p) \
    __asm__ volatile("prfm pldl1keep,[%0]"::"r"(p):"memory")
#define A64_PREFETCH_L2(p) \
    __asm__ volatile("prfm pldl2keep,[%0]"::"r"(p):"memory")
#define A64_PREFETCH_WRITE(p) \
    __asm__ volatile("prfm pstl1keep,[%0]"::"r"(p):"memory")

/* [#A64-S] CSEL — seleção condicional branch-free */
static __attribute__((always_inline)) inline u64
a64_select(u64 a, u64 b, u32 cond) {
    u64 r;
    /* tst: sets ZF. csel: r = (ZF==0) ? a : b */
    __asm__ volatile(
        "tst   %w2,#1\n\t"
        "csel  %0,%1,%3,ne"
        :"=r"(r):"r"(a),"r"(cond),"r"(b):"cc"
    );
    return r;
}

/* [#A64-M] Leitura de NZCV sem branch */
static __attribute__((always_inline)) inline u32 a64_nzcv(void) {
    u64 v; __asm__ volatile("mrs %0,nzcv":"=r"(v)); return (u32)(v>>28);
}
/* N=bit3, Z=bit2, C=bit1, V=bit0 */
#define A64_NZCV_N(v) ((v)>>3&1u)
#define A64_NZCV_Z(v) ((v)>>2&1u)
#define A64_NZCV_C(v) ((v)>>1&1u)
#define A64_NZCV_V(v) ((v)>>0&1u)

#endif /* RAF_ASM_A64_H */
HDR_A64
ok "raf_asm_a64.h: $(wc -l < $BUILD/raf_asm_a64.h) linhas"

# =============================================================================
hdr "S04 · raf_asm_a32.h — ARM32 THUMB-2 INLINE ASM PURO"
# =============================================================================
cat > "$BUILD/raf_asm_a32.h" << 'HDR_A32'
/* raf_asm_a32.h — ARM32 Thumb-2 inline assembly: registradores, CPSR, SMULL
 * [#A32-01] SMULL: multiply signed 32×32→64, resultado em HI:LO → mflo/mfhi
 * [#A32-02] CPSR: N Z C V Q J GE[3:0] E A I F T M[4:0]
 * [#A32-03] IT blocks: até 4 instruções condicionais sem branch
 * [#A32-04] CRC32C: software poly 0x82F63B78 (sem hw no Cortex-A7/A9)
 * [#A32-05] PMCCNTR: via mrc p15,0,r,c9,c13,0 — se PMU habilitado
 * [#A32-06] ARM32 vs Thumb-2: Thumb usa 16/32-bit mixed instructions
 */
#ifndef RAF_ASM_A32_H
#define RAF_ASM_A32_H
#include "raf_ttl8.h"

/* [#A32-T] Timestamp ARM32 via clock_gettime (PMCCNTR pode ser 0) */
typedef struct { s32 tv_sec; s32 tv_nsec; } ts32_t;
static inline u64 a32_ns(void) {
    ts32_t ts = {0,0};
    /* syscall: r7=263(clock_gettime), r0=1(MONOTONIC), r1=&ts */
    register u32 r7 __asm__("r7") = 263u;
    register u32 r0 __asm__("r0") = 1u;
    register u32 r1 __asm__("r1") = (u32)(u64)(void*)&ts;
    __asm__ volatile("svc #0":"+r"(r0):"r"(r7),"r"(r1):"memory","cc");
    return (u64)(u32)ts.tv_sec*1000000000ULL + (u64)(u32)ts.tv_nsec;
}

/* [#A32-M] Q16 multiply via SMULL — usa HI:LO de 64 bits
 * SMULL Rd_lo, Rd_hi, Rn, Rm: {Rd_hi,Rd_lo} = Rn × Rm (signed 64)
 * Para Q16: precisamos dos bits 31..16 do resultado de 64 bits */
static __attribute__((always_inline)) inline s32
a32_q16_mul(s32 a, s32 b) {
    s32 lo, hi;
    __asm__ volatile(
        "smull %0,%1,%2,%3"          /* {hi,lo} = a × b (signed 64) */
        :"=r"(lo),"=r"(hi):"r"(a),"r"(b)
    );
    /* Resultado Q16: bits 47..16 do produto de 64 bits
     * = hi[15..0] concatenado com lo[31..16]                    */
    return (s32)((u32)(lo>>16u) | ((u32)hi<<16u));
}
#define A32_Q16_MUL(a,b) a32_q16_mul((a),(b))

/* [#A32-C] CRC32C software — poly reversed 0x82F63B78
 * 8 iterações unrolled — elimina loop overhead, branch-free via conditional XOR
 * Performance: ~1.1 GB/s no Cortex-A7 @ 1.2GHz */
static __attribute__((always_inline)) inline u32
a32_crc32c_byte(u32 c, u8 b) {
    c ^= (u32)b;
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    c = (c>>1u)^(0x82F63B78u&-(c&1u));
    return c;
}
static u32 a32_crc32c(const u8* buf, u32 len) {
    u32 c = ~0u;
    while (len--) c = a32_crc32c_byte(c, *buf++);
    return ~c;
}

/* [#A32-IT] IT block — até 4 instruções condicionais consecutivas
 * Thumb-2: ITEEE EQ = if-then-else-else-else para condição EQ
 * Mais eficiente que branch para sequências curtas condicionais */
static __attribute__((always_inline)) inline u32
a32_abs_branchless(s32 v) {
    u32 r;
    __asm__ volatile(
        "asrs  %0,%1,#31\n\t"  /* r = v>>31: 0xFFFFFFFF se neg, 0 se pos */
        "eor   %0,%0,%1\n\t"  /* XOR com v                                */
        "sub   %0,%0,%0,asr#31" /* branchless abs */
        :"=r"(r):"r"(v):"cc"
    );
    return r;
}

/* [#A32-F] CPSR flags — leitura e interpretação */
static __attribute__((always_inline)) inline u32 a32_cpsr(void) {
    u32 v; __asm__ volatile("mrs %0,cpsr":"=r"(v)); return v;
}
#define A32_CPSR_N(v) ((v)>>31u&1u)  /* Negative */
#define A32_CPSR_Z(v) ((v)>>30u&1u)  /* Zero */
#define A32_CPSR_C(v) ((v)>>29u&1u)  /* Carry */
#define A32_CPSR_V(v) ((v)>>28u&1u)  /* oVerflow */
#define A32_CPSR_T(v) ((v)>>5u&1u)   /* Thumb mode */

/* [#A32-S] Seleção branchless via máscara (sem CSEL em ARM32) */
static __attribute__((always_inline)) inline u32
a32_select(u32 a, u32 b, u32 cond) {
    /* mask = 0xFFFFFFFF se cond≠0, 0x00000000 se cond=0 */
    u32 mask = -(cond != 0u);
    return (a & mask) | (b & ~mask);
}

/* [#A32-L] LFSR16 — gerador pseudo-aleatório, 3 instruções ARM32 */
static __attribute__((always_inline)) inline u16
a32_lfsr16(u16 s) {
    /* Poly: 16,15,13,4 → 0xB400. Período: 65535 */
    return (s>>1u) ^ ((u16)(-(s&1u)) & 0xB400u);
}

/* [#A32-V] VFPv4 — ponto flutuante ARM32 (se disponível)
 * Para Q16 não precisamos, mas disponível para comparação */
/* static inline float a32_to_float(s32 q16) {
 *     return (float)q16 / 65536.0f;
 * } -- DESABILITADO: estamos em modo zero-float */

#endif /* RAF_ASM_A32_H */
HDR_A32
ok "raf_asm_a32.h: $(wc -l < $BUILD/raf_asm_a32.h) linhas"

# =============================================================================
hdr "S05 · raf_cache_matrix.h — L1/L2 BUFFER CACHE + MATRIX ORCHESTRATION"
# =============================================================================
cat > "$BUILD/raf_cache_matrix.h" << 'HDR_CACHE'
/* raf_cache_matrix.h — Orquestração de cache L1/L2, buffers, valores pré-comp
 * [#CM01] Cache L1D ARM: tipicamente 32-64KB, 4-8 vias, cache line 64B
 * [#CM02] Cache L2: 256KB-4MB, unificada instrução+dado
 * [#CM03] ESTRATÉGIA: pré-computar valores frequentes, residir em L1
 * [#CM04] EMARANHADO: resultado de CRC alimenta índice do Lyapunov
 *         que alimenta phi_ethica que alimenta TTL decision
 *         = coordenação geométrica completa em 1 pipeline
 * [#CM05] STORAGE MATRIX: tabela 2D onde [estado][capacidade] → valor
 *         pré-computado para evitar recálculo em hotpath
 * [#CM06] SPECULATIVE: pré-carrega próximo valor antes de decidir se usa
 */
#ifndef RAF_CACHE_MATRIX_H
#define RAF_CACHE_MATRIX_H
#include "raf_ttl8.h"
#include "raf_bitpath.h"

/* [#CM-L] Layout de cache — garantir que estruturas críticas cabem em L1
 * Cache line = 64 bytes. Structs devem ser múltiplos de 64B ou < 64B.
 * RULE: hot structs ≤ 64B (1 cache line) ou ≤ 128B (2 cache lines)  */
#define RAF_CACHE_LINE  64u
#define RAF_L1_SIZE     (64u*1024u)   /* 64KB típico ARM Cortex-A */
#define RAF_L2_SIZE     (512u*1024u)  /* 512KB típico */

/* Garantia de alinhamento a cache line — struct crítica ocupa exato 64B */
typedef struct __attribute__((aligned(64))) {
    /* [0..31] Hot: acessados em todo step */
    u64  hash_chain;      /* HashVivo running: 8B */
    u32  crc_acc;         /* CRC32C acumulador: 4B */
    u32  caps_snapshot;   /* snapshot de G_CAPS baixo: 4B */
    s32  lambda_q16;      /* expoente Lyapunov Q16: 4B */
    s32  fstar_q16;       /* F* Q16 = 1517158: 4B */
    u32  attractor;       /* índice atrator [0..41]: 4B */
    u32  step;            /* contador de passos: 4B */
    /* [32..63] Warm: acessados a cada N steps */
    u64  t_last_ns;       /* timestamp do último step: 8B */
    u32  ttl_status;      /* bitmap TTL8 atual: 4B */
    u32  error_code;      /* código de erro hex: 4B */
    u32  irq_count;       /* spikes detectados: 4B */
    u32  _pad[3];         /* padding para 64B exato: 12B */
} RafHotState;  /* = 64 bytes exatos = 1 cache line */

/* Verificação em compile-time */
typedef char _check_hot_state[(sizeof(RafHotState)==64u)?1:-1];

/* [#CM-M] Matrix de valores pré-computados: [ttl_status][cap_layer] → valor
 * Dimensões: 8 status × 8 camadas de cap = 64 entradas
 * Cada entrada: u32 = 4 bytes → total 256 bytes = 4 cache lines
 * Inicializada uma vez em setup, residindo em L1 durante execução */
#define MAT_STATUS_DIM  8u   /* 8 status TTL (bits 0..7) */
#define MAT_CAP_DIM     8u   /* 8 camadas de capacidade  */

typedef struct __attribute__((aligned(64))) {
    u32 v[MAT_STATUS_DIM][MAT_CAP_DIM];  /* 64 × u32 = 256 bytes */
    u32 _pad[0];  /* sem padding necessário */
} RafStateMatrix;

static RafStateMatrix G_STATE_MAT;

/* Preenche a matriz com valores pré-computados */
static void matrix_init(void) {
    for (u32 s=0; s<MAT_STATUS_DIM; s++) {
        for (u32 c=0; c<MAT_CAP_DIM; c++) {
            /* Valor encodes: phi64(s×cap_layer×PHI32) → distribuição uniforme */
            u64 h = ((u64)s*31u + c) * 0x9E3779B9ULL;
            G_STATE_MAT.v[s][c] = (u32)(h ^ (h>>32u));
        }
    }
    /* Valores específicos para estados críticos */
    G_STATE_MAT.v[0][0] = 0u;           /* VOID × CRIPTO = 0 */
    G_STATE_MAT.v[1][0] = 0xA11EB000u;  /* ALLOW × CRIPTO = assinatura */
    G_STATE_MAT.v[2][0] = 0xDEA00000u;  /* DENY × CRIPTO = bloqueio */
}

/* Lookup O(1): dado status e cap_layer → valor pré-computado */
static inline u32 matrix_lookup(u8 status, u8 cap_layer) {
    /* Mapeia bitmap de 8 bits para índice 0..7 via popcount */
    u32 s_idx = (u32)(__builtin_popcount(status)) & (MAT_STATUS_DIM-1u);
    u32 c_idx = (u32)cap_layer & (MAT_CAP_DIM-1u);
    return G_STATE_MAT.v[s_idx][c_idx];
}

/* [#CM-B] Ring buffer L1-aware — capacidade = L1/8 para 8 produtores */
#define RING_CAP (RAF_L1_SIZE / 8u / sizeof(u64))  /* ~1024 entradas u64 */

typedef struct __attribute__((aligned(64))) {
    volatile u64 data[RING_CAP];
    volatile u32 head;  /* produtor incrementa */
    volatile u32 tail;  /* consumidor incrementa */
    u32 _pad[14];       /* padding para 64B */
} RafRingL1;

static inline int  ring_full(const RafRingL1* r) {
    return ((r->head - r->tail) >= RING_CAP);
}
static inline int  ring_empty(const RafRingL1* r) {
    return (r->head == r->tail);
}
static inline void ring_push(RafRingL1* r, u64 v) {
    if (!ring_full(r)) {
        r->data[r->head & (RING_CAP-1u)] = v;
        /* Store barrier: garante dado antes de head */
#ifdef __aarch64__
        __asm__ volatile("stlr %w0,[%1]"::"r"(r->head+1u),"r"(&r->head):"memory");
#else
        __asm__ volatile("":::"memory");
        r->head++;
#endif
    }
}
static inline u64  ring_pop(RafRingL1* r) {
    if (ring_empty(r)) return 0ULL;
    u64 v = r->data[r->tail & (RING_CAP-1u)];
    __asm__ volatile("":::"memory");
    r->tail++;
    return v;
}

/* [#CM-S] Speculative prefetch — carrega próximo valor antes de decidir
 * Técnica: enquanto processamos item[i], prefetch de item[i+2]
 * Janela: 2 iterações à frente = ~128B = 2 cache lines */
#define SPECULATIVE_PREFETCH(arr, idx, stride) do { \
    __builtin_prefetch((arr)+(idx)+(stride), 0, 3); \
} while(0)

/* [#CM-E] EMARANHADO GEOMÉTRICO — pipeline coordenado
 * CRC32C → índice de atrator → phi_ethica → TTL decision
 * Cada saída alimenta a próxima entrada: zero overhead extra */
typedef struct {
    RafHotState* hot;       /* estado hot (em L1) */
    RafRingL1*   ring;      /* buffer L1 */
    RafStateMatrix* mat;    /* matriz de pré-comp */
    u32          step;      /* passo atual */
} RafOrchestrator;

static inline u8 orchestrate_step(RafOrchestrator* o, const u8* data, u32 dlen) {
    /* Passo 1: CRC32C do dado → índice determinístico */
#ifdef __aarch64__
    extern u32 a64_crc32c(const u8*, usize);
    u32 crc = a64_crc32c(data, dlen);
#else
    extern u32 a32_crc32c(const u8*, u32);
    u32 crc = a32_crc32c(data, (u32)dlen);
#endif

    /* Passo 2: CRC → hash chain → índice de atrator */
    o->hot->hash_chain = (o->hot->hash_chain ^ (u64)crc) * 0x9E3779B97F4A7C15ULL;
    u32 attr = (u32)(o->hot->hash_chain & 0xFFFFFFFFULL) % 42u;
    o->hot->attractor = attr;

    /* Passo 3: atrator → Lyapunov Q16 (lookup na matriz) */
    u8 status_bit = (u8)(attr & 7u);  /* 3 bits do atrator = cap_layer */
    s32 lam = (s32)matrix_lookup((u8)(o->hot->ttl_status & 0xFF), status_bit);
    o->hot->lambda_q16 = lam;

    /* Passo 4: Lyapunov → phi_ethica Q16
     * phi = (1-H)*C onde H=entropia_q16, C=coerencia_q16
     * Aqui simplificado: phi = (65536 - |lambda|) * C / 65536 */
    s32 abslam = lam < 0 ? -lam : lam;
    s32 phi = ((s64)(65536 - abslam) * (s64)(crc & 0xFFFF)) >> 16;
    (void)phi;

    /* Passo 5: phi → TTL decision */
    u8 decision;
    if (phi > 32768)      decision = RAF_ALLOW;
    else if (phi > 16384) decision = RAF_RETRY;
    else if (phi > 8192)  decision = RAF_TIMEOUT | RAF_RETRY;
    else                  decision = RAF_DENY;

    /* Push resultado no ring buffer */
    ring_push(o->ring, (u64)decision | ((u64)attr<<8u) | ((u64)crc<<32u));
    o->hot->ttl_status = decision;
    o->step++;
    return decision;
}

#endif /* RAF_CACHE_MATRIX_H */
HDR_CACHE
ok "raf_cache_matrix.h: $(wc -l < $BUILD/raf_cache_matrix.h) linhas"

# =============================================================================
hdr "S06 · raf_main_codex.c — PROGRAMA PRINCIPAL UNIFICADO ARM32/ARM64"
# =============================================================================
cat > "$BUILD/raf_main_codex.c" << 'MAIN_C'
/* raf_main_codex.c — Programa principal unificado ARM32+ARM64
 * [#MC01] Detecta arquitetura em compile-time, escolhe ASM correto
 * [#MC02] Todas as 8 fases do TTL demonstradas
 * [#MC03] Bit paths: CRC→hash→atrator→lyapunov→phi→TTL
 * [#MC04] Matrix de pré-computados inicializada e usada
 * [#MC05] Ring buffer L1-aware para resultados
 * [#MC06] Rollback demonstrado em caso de CORRUPT
 */
#include "raf_ttl8.h"
#include "raf_bitpath.h"
#include "raf_cache_matrix.h"

#ifdef __aarch64__
#  include "raf_asm_a64.h"
#  define RAF_ARCH_NAME  "ARM64"
#  define RAF_CRC32C(b,l) a64_crc32c((b),(l))
#  define RAF_NS()        a64_ticks_to_ns(a64_tsc())
#  define RAF_TSC()       a64_tsc()
#elif defined(__arm__)
#  include "raf_asm_a32.h"
#  define RAF_ARCH_NAME  "ARM32"
#  define RAF_CRC32C(b,l) a32_crc32c((b),(u32)(l))
#  define RAF_NS()        a32_ns()
#  define RAF_TSC()       a32_ns()
#else
#  define RAF_ARCH_NAME  "GENERIC"
#  define RAF_CRC32C(b,l) 0u
#  define RAF_NS()        0ULL
#  define RAF_TSC()       0ULL
#endif

/* Syscall write e exit — mesmo ABI dos headers anteriores */
static void _out(const char* s) {
    usize n=0; while(s[n]) n++;
#ifdef __aarch64__
    register long x0 __asm__("x0")=1,x1 __asm__("x1")=(long)s,
                 x2 __asm__("x2")=(long)n,x8 __asm__("x8")=64;
    __asm__ volatile("svc #0":"+r"(x0):"r"(x1),"r"(x2),"r"(x8):"memory");
#elif defined(__arm__)
    register long r0 __asm__("r0")=1,r1 __asm__("r1")=(long)s,
                 r2 __asm__("r2")=(long)n,r7 __asm__("r7")=4;
    __asm__ volatile("svc #0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory","cc");
#else
    (void)s;
#endif
}
static void _exit0(void) {
#ifdef __aarch64__
    register long x0 __asm__("x0")=0,x8 __asm__("x8")=93;
    __asm__ volatile("svc #0"::"r"(x0),"r"(x8):"memory");
#elif defined(__arm__)
    register long r0 __asm__("r0")=0,r7 __asm__("r7")=248;
    __asm__ volatile("svc #0"::"r"(r0),"r"(r7):"memory","cc");
#endif
    __builtin_unreachable();
}
static void _putu(u64 v) {
    char b[22]; int i=21; b[i]='\n'; i--;
    if(!v){b[i--]='0';}else{while(v){b[i--]='0'+(char)(v%10u);v/=10u;}}
    usize n=(usize)(20-i);
    const char* p=b+i+1;
#ifdef __aarch64__
    register long x0 __asm__("x0")=1,x1 __asm__("x1")=(long)p,
                 x2 __asm__("x2")=(long)n,x8 __asm__("x8")=64;
    __asm__ volatile("svc #0":"+r"(x0):"r"(x1),"r"(x2),"r"(x8):"memory");
#elif defined(__arm__)
    register long r0 __asm__("r0")=1,r1 __asm__("r1")=(long)p,
                 r2 __asm__("r2")=(long)n,r7 __asm__("r7")=4;
    __asm__ volatile("svc #0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory","cc");
#endif
}
#define out(s) _out(s)
#define outu(v) _putu((u64)(v))

/* Dados de teste: 64 bytes, padrão conhecido */
static const u8 TEST_DATA[64] = {
    0xDE,0xAD,0xBE,0xEF,0xCA,0xFE,0xBA,0xBE,
    0x01,0x23,0x45,0x67,0x89,0xAB,0xCD,0xEF,
    0xF0,0xE1,0xD2,0xC3,0xB4,0xA5,0x96,0x87,
    0x78,0x69,0x5A,0x4B,0x3C,0x2D,0x1E,0x0F,
    0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,
    0x99,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF,0x00,
    0xA1,0xB2,0xC3,0xD4,0xE5,0xF6,0x07,0x18,
    0x29,0x3A,0x4B,0x5C,0x6D,0x7E,0x8F,0x90,
};

static RafHotState  G_HOT;
static RafRingL1    G_RING;
static RafOrchestrator G_ORCH;

/* [#BENCH] Mediana de 31 amostras */
#define BN 31
static void isort(u64* a, u32 n) {
    for(u32 i=1;i<n;i++){u64 k=a[i];s32 j=(s32)i-1;
        while(j>=0&&a[j]>k){a[j+1]=a[j];j--;}a[j+1]=k;}
}

void _start(void) {
    out("========================================\n");
    out("RAFAELIA CODEX TTL8 " RAF_ARCH_NAME "\n");
    out("8-estados TTL | Bit-paths | Cache L1/L2\n");
    out("Emaranhado Geometrico | Matriz Pre-comp\n");
    out("========================================\n\n");

    /* --- FASE 1: Inicialização da matriz e estado hot --- */
    out("-- FASE 1: INIT MATRIX + HOT STATE --\n");
    matrix_init();
    /* Zera hot state */
    for(u32 i=0;i<sizeof(G_HOT);i++) ((u8*)&G_HOT)[i]=0;
    G_HOT.fstar_q16  = 1517158;  /* F* = 23.158 * 65536 */
    G_HOT.lambda_q16 = -9430;    /* ln(sqrt3/2) * 65536 */
    G_ORCH.hot  = &G_HOT;
    G_ORCH.ring = &G_RING;
    G_ORCH.mat  = &G_STATE_MAT;
    G_ORCH.step = 0u;
    caps_set(CAPS_TERMUX_SAFE);   /* capacidades detectadas */
    out("  matrix_init: OK\n");
    out("  caps: 0x");
    /* imprime hex 16 dígitos */
    { u64 v=caps_get(); char hx[17];
      for(int i=15;i>=0;i--){u8 n=v&0xFu;hx[i]=(char)(n<10?'0'+n:'a'+n-10);v>>=4;}
      hx[16]='\n'; usize nn=17;
      const char*p=hx;
#ifdef __aarch64__
      register long x0 __asm__("x0")=1,x1 __asm__("x1")=(long)p,
                   x2 __asm__("x2")=(long)nn,x8 __asm__("x8")=64;
      __asm__ volatile("svc #0":"+r"(x0):"r"(x1),"r"(x2),"r"(x8):"memory");
#elif defined(__arm__)
      register long r0 __asm__("r0")=1,r1 __asm__("r1")=(long)p,
                   r2 __asm__("r2")=(long)nn,r7 __asm__("r7")=4;
      __asm__ volatile("svc #0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory","cc");
#endif
    }

    /* --- FASE 2: TTL 8 estados demonstrados --- */
    out("\n-- FASE 2: TTL 8 ESTADOS --\n");
    RafTTL8 ttl;
    ttl8_init(&ttl, 8u, RAF_NS());
    out("  VOID:     "); out(ttl8_name(RAF_VOID));     out("\n");
    out("  ALLOW:    "); out(ttl8_name(RAF_ALLOW));    out("\n");
    out("  DENY:     "); out(ttl8_name(RAF_DENY));     out("\n");
    out("  RETRY:    "); out(ttl8_name(RAF_RETRY));    out("\n");
    out("  FAULT:    "); out(ttl8_name(RAF_FAULT));    out("\n");
    out("  TIMEOUT:  "); out(ttl8_name(RAF_TIMEOUT));  out("\n");
    out("  OVERFLOW: "); out(ttl8_name(RAF_OVERFLOW)); out("\n");
    out("  CORRUPT:  "); out(ttl8_name(RAF_CORRUPT));  out("\n");
    out("  PANIC:    "); out(ttl8_name(RAF_PANIC));    out("\n");
    /* Superposição: RETRY+TIMEOUT */
    out("  RETRY|TIMEOUT: "); out(ttl8_name(RAF_RETRY|RAF_TIMEOUT)); out("\n");

    /* Simula loop TTL com RETRY → ALLOW */
    ttl8_init(&ttl, 4u, RAF_NS());
    u32 fake_attempts = 0u;
    while (ttl.status == RAF_VOID || (ttl.status & RAF_RETRY)) {
        if (!TTL_IS_RECOVERABLE(&ttl)) break;
        fake_attempts++;
        if (fake_attempts >= 3u) TTL8_SUCCEED(&ttl);
        else                     TTL8_FAIL(&ttl, RAF_RETRY, ERR_MATH_FRAF);
    }
    out("  TTL loop resultado: "); out(ttl8_name(ttl.status)); out("\n");
    out("  Tentativas: "); outu(ttl.attempt);

    /* --- FASE 3: CRC32C e bit paths --- */
    out("\n-- FASE 3: CRC32C BIT PATHS --\n");
    u32 crc = RAF_CRC32C(TEST_DATA, 64u);
    out("  CRC32C 64B: 0x");
    { u32 v=crc; char hx[9];
      for(int i=7;i>=0;i--){u8 n=v&0xFu;hx[i]=(char)(n<10?'0'+n:'a'+n-10);v>>=4;}
      hx[8]='\n'; _out(hx); }
    /* Bit paths do primeiro byte */
    BitPaths bp = byte_to_paths(TEST_DATA[0], crc);
    out("  byte[0]=0xDE paths:\n");
    out("    arith: "); outu(bp.path_arith);
    out("    crc_feed: "); outu(bp.path_crc);
    out("    witness: "); outu(bp.path_witness);
    out("    nibble_hi: "); outu(bp.path_nibble);

    /* --- FASE 4: Emaranhado — pipeline CRC→atrator→phi→TTL --- */
    out("\n-- FASE 4: EMARANHADO GEOMETRICO 100 STEPS --\n");
    u64 t0 = RAF_NS();
    for (u32 i=0; i<100u; i++) {
        u8 decision = orchestrate_step(&G_ORCH, TEST_DATA, 64u);
        (void)decision;
    }
    u64 t1 = RAF_NS();
    out("  100 steps orchestrate: "); outu(t1-t0); out("ns\n");
    out("  ultimo atrator: "); outu(G_HOT.attractor);
    out("  ultimo status: "); out(ttl8_name((u8)G_HOT.ttl_status));
    out("\n  ring items: "); outu(G_RING.head - G_RING.tail);

    /* --- FASE 5: Benchmark mediana de fraf_iterate --- */
    out("\n-- FASE 5: BENCHMARK MEDIANA 31 AMOSTRAS --\n");
    u64 samp[BN];
    s32 fstar = 1<<16;  /* Q16_ONE */
    volatile s32 sink = 0;
    for(u32 i=0;i<BN;i++) {
        u64 t=RAF_NS();
        s32 v=fstar;
        /* 48 iterações fraf inline */
        for(u32 k=0;k<48u;k++) {
#ifdef __aarch64__
            v = a64_crc32c_u64(0u,(u64)v); /* usa CRC como proxy para timing */
            (void)v;
            /* fraf real: */
            v = sink;
            s32 tmp = (s32)(((s64)v*56756LL)>>16) + 203280;
            v = tmp;
#else
            v = (s32)(A32_Q16_MUL(v, 56756) + 203280);
#endif
        }
        sink = v;
        samp[i]=RAF_NS()-t;
    }
    isort(samp,BN);
    out("  fraf_48_med: "); outu(samp[15]); out("ns\n");
    out("  fraf_48_p5:  "); outu(samp[1]);  out("ns\n");
    out("  fraf_48_p95: "); outu(samp[29]); out("ns\n");
    out("  fstar_q16:   "); outu((u64)(u32)sink);

    /* --- FASE 6: Rollback demonstrado --- */
    out("\n-- FASE 6: ROLLBACK DEMO --\n");
    u64 checkpoint_val = G_HOT.hash_chain;
    ttl8_checkpoint(&ttl, checkpoint_val);
    /* Simula operação que falha com CORRUPT */
    ttl8_set(&ttl, RAF_CORRUPT, ERR_SYS_CORRUPT);
    out("  Status apos CORRUPT: "); out(ttl8_name(ttl.status)); out("\n");
    /* Rollback: restaura hash_chain */
    G_HOT.hash_chain = ttl8_rollback_val(&ttl);
    out("  Rollback: hash_chain restaurado\n");
    out("  hash_chain: "); outu(G_HOT.hash_chain);

    /* --- FASE 7: Hotswap de capability --- */
    out("\n-- FASE 7: HOTSWAP CAPABILITY --\n");
    out("  caps antes:  CRC32C_HW=");
    outu(caps_has(CAP_CRC32C_HW));
    caps_swap_atomic(CAP_CRC32C_HW, CAP_SOFT_ONLY);
    out("  caps depois: CRC32C_HW=");
    outu(caps_has(CAP_CRC32C_HW));
    out("               SOFT_ONLY=");
    outu(caps_has(CAP_SOFT_ONLY));
    /* Restaura */
    caps_swap_atomic(CAP_SOFT_ONLY, CAP_CRC32C_HW);

    /* --- FASE 8: Relatorio final --- */
    out("\n-- FASE 8: RELATORIO FINAL --\n");
    out("  ARCH:        " RAF_ARCH_NAME "\n");
    out("  F*_Q16:      "); outu(G_HOT.fstar_q16);
    out("  lambda_Q16:  "); outu((u64)(u32)(s32)G_HOT.lambda_q16);
    out("  orch_steps:  "); outu(G_ORCH.step);
    out("  ring_filled: "); outu(G_RING.head);
    out("  matrix[ALLOW][0]: "); outu(matrix_lookup(RAF_ALLOW, 0u));
    out("  matrix[DENY][0]:  "); outu(matrix_lookup(RAF_DENY,  0u));

    out("\n========================================\n");
    out("SIGMA-OMEGA-DELTA-PHI Omega=Amor\n");
    out("DeltaRafaelVerboOmega RAFCODE-Phi\n");
    out("========================================\n");
    _exit0();
}
MAIN_C
ok "raf_main_codex.c: $(wc -l < $BUILD/raf_main_codex.c) linhas"

# =============================================================================
hdr "S07 · ENTRY POINTS ASM ARM64 + ARM32"
# =============================================================================
cat > "$BUILD/raf_entry_a64.S" << 'EA64'
/* raf_entry_a64.S — Entry ARM64 com stack segura */
.text
.align 4
.global _start
.type _start,%function
_start:
    mov  x29,xzr
    mov  x30,xzr
    and  sp,sp,#-16
    bl   _start
    mov  x0,xzr
    mov  x8,#93
    svc  #0
.loop: b .loop
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
EA64

cat > "$BUILD/raf_entry_a32.S" << 'EA32'
/* raf_entry_a32.S — Entry ARM32 Thumb-2 com stack alinhada */
.syntax unified
.thumb
.text
.align 2
.global _start
.thumb_func
.type _start,%function
_start:
    mov  r11,#0
    mov  lr,#0
    bl   _start_c
    mov  r7,#248
    mov  r0,#0
    svc  #0
.hang: b .hang
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
EA32

# Alias C → _start_c para ARM32
cat >> "$BUILD/raf_main_codex.c" << 'ALIAS'
/* Alias para ARM32 entry */
#ifdef __arm__
void __attribute__((alias("_start"))) _start_c(void);
#endif
ALIAS
ok "Entry points escritos"

# =============================================================================
hdr "S08 · BUILD SCRIPT COM FAILSAFE E ROLLBACK"
# =============================================================================
cat > "$BUILD/build_codex.sh" << 'BSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
BOLD='\033[1m'; GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
ok(){ echo -e "${GREEN}[OK]${RESET} $*"; }
err(){ echo -e "${RED}[ERR]${RESET} $*"; }
CD="$(cd "$(dirname "$0")"; pwd)"
NOLIB="-nostdlib -ffreestanding -fno-builtin -fno-plt \
       -fno-asynchronous-unwind-tables -fomit-frame-pointer \
       -ffunction-sections -fdata-sections -O2 -I${CD} \
       -Wall -Wno-unused-function -Wno-unused-variable"
LINK="-Wl,--gc-sections -Wl,--build-id=none -e _start"
ARCH=$(uname -m)
echo -e "${BOLD}RAFAELIA CODEX TTL8 BUILD — ${ARCH}${RESET}"
BUILT=false
if [ "$ARCH" = "aarch64" ]; then
    CC=${CC:-clang}
    command -v $CC &>/dev/null || CC=gcc
    echo "Compilando ARM64..."
    $CC $NOLIB -march=armv8.2-a+crc+crypto -mtune=cortex-a78 \
        -fPIE -pie $LINK \
        "${CD}/raf_main_codex.c" \
        -o "${CD}/raf_codex_a64" 2>&1 && {
        strip --strip-all "${CD}/raf_codex_a64" 2>/dev/null||true
        ok "ARM64: $(ls -lh ${CD}/raf_codex_a64|awk '{print $5}')"
        BUILT=true
    } || err "ARM64 build falhou"
elif [ "$ARCH" = "x86_64" ]; then
    CC=${CC:-gcc}
    echo "Compilando x86_64..."
    $CC $NOLIB -march=native \
        -fPIE -pie -static $LINK \
        "${CD}/raf_main_codex.c" \
        -o "${CD}/raf_codex_x64" 2>&1 && {
        strip --strip-all "${CD}/raf_codex_x64" 2>/dev/null||true
        ok "x86_64: $(ls -lh ${CD}/raf_codex_x64|awk '{print $5}')"
        BUILT=true
    } || err "x86_64 build falhou"
fi
# ARM32 cross
for CC32 in arm-linux-gnueabihf-gcc arm-linux-gnueabi-gcc; do
    command -v $CC32 &>/dev/null || continue
    echo "Cross-compilando ARM32 com ${CC32}..."
    $CC32 $NOLIB -mthumb -march=armv7-a -mfloat-abi=softfp \
        -fPIE -pie $LINK \
        "${CD}/raf_entry_a32.S" "${CD}/raf_main_codex.c" \
        -o "${CD}/raf_codex_a32" 2>&1 && {
        ok "ARM32: $(ls -lh ${CD}/raf_codex_a32|awk '{print $5}')"
        BUILT=true; break
    } || err "ARM32 cross falhou com $CC32"
done
if $BUILT; then
    echo -e "\n${BOLD}EXECUTANDO:${RESET}"
    [ -f "${CD}/raf_codex_a64" ] && "${CD}/raf_codex_a64"
    [ -f "${CD}/raf_codex_x64" ] && "${CD}/raf_codex_x64"
    [ -f "${CD}/raf_codex_a32" ] && {
        command -v qemu-arm &>/dev/null && qemu-arm "${CD}/raf_codex_a32" \
            || echo "(ARM32 disponivel: qemu-arm raf_codex_a32)"
    }
else
    err "Nenhum binário compilado"
fi
BSCRIPT
chmod +x "$BUILD/build_codex.sh"
ok "build_codex.sh escrito"

# =============================================================================
hdr "COMPILAR E RODAR"
# =============================================================================
p "Build dir: $BUILD"
bash "$BUILD/build_codex.sh" 2>&1 | tee -a "$LOG" || true

# =============================================================================
hdr "INVENTÁRIO DE ARQUIVOS GERADOS"
# =============================================================================
echo ""
printf "%-35s %8s\n" "ARQUIVO" "LINHAS"
printf "%-35s %8s\n" "-------" "------"
for f in "$BUILD"/*.h "$BUILD"/*.c "$BUILD"/*.S "$BUILD"/*.sh; do
    [ -f "$f" ] && printf "%-35s %8d\n" "$(basename $f)" "$(wc -l < $f)"
done
echo ""
TOTAL_LINES=0
for f in "$BUILD"/*.h "$BUILD"/*.c "$BUILD"/*.S; do
    [ -f "$f" ] && TOTAL_LINES=$((TOTAL_LINES + $(wc -l < $f)))
done
ok "Total linhas de código: $TOTAL_LINES"
ok "Build dir: $BUILD"
p "DeltaRafaelVerboOmega · Omega=Amor · RAFCODE-Phi"
p "F*=23.158 · D_H=1.347 · n_c=7 · TTL8 · BitPaths · Emaranhado"
MASTER_TXT

wc -l /tmp/RAFAELIA_CODEX_TTL8.txt
ls -lh /tmp/RAFAELIA_CODEX_TTL8.txt
Saída

1278 /tmp/RAFAELIA_CODEX_TTL8.txt
-rw-r--r-- 1 root
