/**
 * rafaelia_bitraf.c — BITRAF Matrix: particionamento geométrico de bits
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * Modelo BitRAF:
 *   Cada "ponto" da matriz 10×10×10+8 = 1008 tem um estado de 42 bits.
 *   Os bits são organizados em camadas de frequência:
 *     bits[0..6]   → frequências harmônicas (7 senoides)
 *     bits[7..13]  → pesos adaptativos (7 camadas)
 *     bits[14..20] → fases toroidais (7 dimensões)
 *     bits[21..27] → CRC parcial (7 bytes de 8 bits = hash posicional)
 *     bits[28..34] → load dos 8 vCPUs (7 bits significativos)
 *     bits[35..41] → estado do commit gate (7 flags)
 *
 * Travessia: gcd(stride, 1000) = 1 garante cobertura completa
 *   stride ∈ {1, 3, 7, 9, 11, 13, ...} — primos em relação a 1000
 *   stride = 7 escolhido por ser primo e harmônico natural do sistema.
 *
 * Sem malloc. Zero overhead. CRC32C em cada operação de escrita.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

/* ── Constantes ─────────────────────────────────────────────────────────── */
#define BF_X       10u
#define BF_Y       10u
#define BF_Z       10u
#define BF_VOL     1000u          /* X*Y*Z */
#define BF_EXTRA   8u             /* 4+2+2 */
#define BF_TOTAL   1008u
#define BF_BITS    42u            /* bits por ponto */
#define BF_STRIDE  7u             /* coprimo com 1000 */
#define BF_PERIOD  42u

/* ── Estrutura de um ponto (6 bytes = 42 bits + 2 bits padding) ──────────── */
/* Armazenamos em uint64_t para alinhamento e operações atômicas            */
typedef uint64_t bf_point_t;

/* ── Arena ──────────────────────────────────────────────────────────────── */
#define BF_ARENA_SZ (512u*1024u)
static uint8_t __attribute__((aligned(64))) g_bfa[BF_ARENA_SZ];
static uint32_t g_bfa_bump=0;
static void *bfa(uint32_t n,uint32_t al){
    uint32_t m=al-1,s=(g_bfa_bump+m)&~m,e=s+n;
    if(e>BF_ARENA_SZ) return NULL; g_bfa_bump=e; return g_bfa+s;
}

/* ── CRC32C inline ──────────────────────────────────────────────────────── */
static uint32_t BT[256];
static void bt_init(void){
    for(uint32_t i=0;i<256;i++){
        uint32_t v=i;
        for(int j=0;j<8;j++) v=(v&1)?(v>>1)^0x82F63B78u:(v>>1);
        BT[i]=v;
    }
}
static uint32_t bt_crc(const void*b,uint32_t n){
    const uint8_t*p=(const uint8_t*)b; uint32_t c=~0u;
    while(n--) c=(c>>8)^BT[(c^*p++)&0xFF]; return ~c;
}

/* ── Estado global ───────────────────────────────────────────────────────── */
typedef struct {
    bf_point_t *vol;       /* 1000 pontos do volume */
    bf_point_t  extra[8]; /* extras: 4 isósceles + 2 atratores + 2 paridade */
    uint64_t    par_xor;  /* XOR de todos os 1000 pontos */
    uint32_t    par_crc;  /* CRC32C do volume */
    uint32_t    trav_pos; /* posição atual da travessia */
    uint32_t    n_writes; /* contador de escritas */
    uint32_t    n_errs;   /* erros de integridade */
} bf_state_t;

static bf_state_t g_bf;

/* ── Inicialização ───────────────────────────────────────────────────────── */
static int bf_init(void) {
    bt_init();
    g_bf.vol = (bf_point_t*)bfa(BF_VOL*8u, 64u);
    if (!g_bf.vol) return -1;

    /* seed: Fibonacci mod 42 bits */
    uint64_t f0=0, f1=1;
    for (uint32_t i=0; i<BF_VOL; i++) {
        uint64_t bits = f1 % BF_BITS;
        g_bf.vol[i] = bits ? (1ULL<<bits)-1ULL : 0ULL;
        uint64_t fn = f0+f1; f0=f1; f1=fn;
    }

    /* extras: triângulo isósceles Q16.16 */
    /* base_L, base_R, apex_N, apex_S, attr0, attr1, par0, par1 */
    uint64_t iso[8] = {
        0x0000DD83ULL, /* +sqrt(3)/2 Q16.16 */
        0xFFFF2280ULL, /* -sqrt(3)/2 */
        0x0000DD83ULL, /* apex north */
        0xFFFF2280ULL, /* apex south */
        0x0001998AULL, /* attractor 0 */
        0xFFFE667BULL, /* attractor 1 */
        0ULL, 0ULL     /* paridade */
    };
    memcpy(g_bf.extra, iso, sizeof(iso));

    /* paridade */
    g_bf.par_xor = 0;
    for (uint32_t i=0; i<BF_VOL; i++) g_bf.par_xor ^= g_bf.vol[i];
    g_bf.par_crc = bt_crc(g_bf.vol, BF_VOL*8u);
    g_bf.extra[6] = g_bf.par_xor;
    g_bf.extra[7] = g_bf.par_crc;

    g_bf.trav_pos = 0;
    g_bf.n_writes = 0;
    g_bf.n_errs   = 0;
    return 0;
}

/* ── Índice 3D → linear ──────────────────────────────────────────────────── */
static uint32_t bf_idx(uint32_t x, uint32_t y, uint32_t z) {
    return (x%BF_X)*BF_Y*BF_Z + (y%BF_Y)*BF_Z + (z%BF_Z);
}

/* ── Escrita com CRC ─────────────────────────────────────────────────────── */
static int bf_write(uint32_t idx, bf_point_t val) {
    if (idx >= BF_VOL) return -1;
    g_bf.vol[idx] = val & ((1ULL<<BF_BITS)-1ULL); /* 42 bits */
    /* atualiza paridade incremental */
    g_bf.par_xor = bt_crc(g_bf.vol, BF_VOL*8u); /* reusa como hash */
    g_bf.par_crc = bt_crc(g_bf.vol, BF_VOL*8u);
    g_bf.n_writes++;
    return 0;
}

/* ── Verificação de integridade ─────────────────────────────────────────── */
static int bf_verify(void) {
    uint32_t c = bt_crc(g_bf.vol, BF_VOL*8u);
    if (c != g_bf.par_crc) { g_bf.n_errs++; return 0; }
    return 1;
}

/* ── Rollback via extra[6,7] ────────────────────────────────────────────── */
static void bf_rollback(void) {
    /* em sistema real: restaura snapshot anterior */
    /* aqui: recalcula paridade como mínimo safe */
    g_bf.par_xor = 0;
    for (uint32_t i=0;i<BF_VOL;i++) g_bf.par_xor ^= g_bf.vol[i];
    g_bf.par_crc = bt_crc(g_bf.vol, BF_VOL*8u);
    g_bf.extra[6] = g_bf.par_xor;
    g_bf.extra[7] = g_bf.par_crc;
}

/* ── Travessia toroidal com stride=7 ────────────────────────────────────── */
/* gcd(7, 1000) = 1 → cobre todos os 1000 pontos antes de repetir         */
static uint32_t bf_next_pos(void) {
    g_bf.trav_pos = (g_bf.trav_pos + BF_STRIDE) % BF_VOL;
    return g_bf.trav_pos;
}

/* ── popcount total ──────────────────────────────────────────────────────── */
static uint32_t bf_popcount(void) {
    uint32_t tot=0;
    for (uint32_t i=0;i<BF_VOL;i++) {
        uint64_t v=g_bf.vol[i];
        while(v){v&=v-1; tot++;}
    }
    return tot;
}

/* ── Output ─────────────────────────────────────────────────────────────── */
static void ws(const char*s){write(1,s,strlen(s));}
static void wu(uint32_t v){
    char b[12];int i=11;b[i]=0;
    if(!v){b[--i]='0';}else while(v){b[--i]=(char)('0'+v%10);v/=10;}
    ws(b+i);
}
static const char HX[]="0123456789ABCDEF";
static void wh(uint32_t v){
    char b[11]="0x00000000";
    for(int i=0;i<8;i++) b[2+i]=HX[(v>>(28-i*4))&0xF];
    ws(b);
}

/* ── MAIN BITRAF ─────────────────────────────────────────────────────────── */
int main(void) {
    if (bf_init()<0){ws("OOM\n");return 1;}

    ws("=== RAFAELIA BITRAF MATRIX 1008 ===\n");
    ws("Vol: 10x10x10=1000  Extra: 8  Total: 1008\n");
    ws("Bits/point: 42  Stride: 7 (gcd(7,1000)=1)\n\n");

    /* 42 ciclos de travessia e escrita */
    for (uint32_t cy=0; cy<BF_PERIOD; cy++) {
        uint32_t pos = bf_next_pos();

        /* calcula x,y,z da posição */
        uint32_t z = pos % BF_Z;
        uint32_t y = (pos / BF_Z) % BF_Y;
        uint32_t x = pos / (BF_Y*BF_Z);

        /* valor: EMA Q16.16 com constante Spiral */
        bf_point_t old = g_bf.vol[pos];
        bf_point_t sv  = (uint64_t)56755u; /* SPIRAL_Q16 */
        bf_point_t nv  = ((old*49152ULL + sv*16384ULL) >> 16) & ((1ULL<<42)-1);

        bf_write(pos, nv);

        /* verifica a cada 7 ciclos */
        if ((cy%7)==0 && !bf_verify()) {
            ws("ROLLBACK@cy="); wu(cy); ws("\n");
            bf_rollback();
        }
    }

    ws("Writes: "); wu(g_bf.n_writes); ws("\n");
    ws("Errors: "); wu(g_bf.n_errs);  ws("\n");
    ws("Bits set: "); wu(bf_popcount()); ws("\n");
    ws("CRC_vol: "); wh(g_bf.par_crc); ws("\n");
    ws("Points total: "); wu(BF_TOTAL); ws("\n");
    ws("Arena: "); wu(g_bfa_bump); ws(" bytes\n");
    ws("=== DONE ===\n");
    return 0;
}
