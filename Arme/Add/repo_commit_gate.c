#include "rafaelia_commit_gate_ll.h"

#define RF_A 0x9E3779B185EBCA87ULL
#define RF_B 0x100000001B3ULL
#define RF_C 0x82F63B78U
#define RF_Q16 (1U << 16)
#define RF_ALPHA_Q16 16384U

static uint32_t rf_crc32c_u32(uint32_t v) {
    uint32_t r = ~0u;
    for (uint32_t i = 0; i < 4; ++i) {
        uint32_t b = (v >> (i << 3)) & 0xffu;
        r ^= b;
        for (uint32_t j = 0; j < 8; ++j) {
            uint32_t m = (uint32_t)(-(int32_t)(r & 1u));
            r = (r >> 1) ^ (RF_C & m);
        }
    }
    return ~r;
}

static uint32_t rf_mix32(uint32_t x) {
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

void rfg_i(rfg_t* x, uint64_t z) {
    x->s = z ^ RF_A;
    x->e = RF_Q16;
    x->c = 0;
    x->h = 0;
    x->g = 0;
}

uint32_t rfg_u(rfg_t* x, uint32_t ci, uint32_t hi, uint32_t st, uint32_t hx) {
    uint32_t c = x->c + (uint32_t)((((uint64_t)(ci - x->c)) * RF_ALPHA_Q16) >> 16);
    uint32_t h = x->h + (uint32_t)((((uint64_t)(hi - x->h)) * RF_ALPHA_Q16) >> 16);

    uint32_t p = (uint32_t)((((uint64_t)(RF_Q16 - h)) * c) >> 16);
    uint32_t k = rf_mix32((uint32_t)x->s ^ st ^ hx ^ p);
    uint32_t r = rf_crc32c_u32(k ^ hx ^ x->g);

    uint32_t z = (uint32_t)(-(int32_t)(h <= 58982u));
    uint32_t t = (uint32_t)(-(int32_t)(p != 0u));
    uint32_t v = (uint32_t)(-(int32_t)((r ^ hx) != 0u));
    uint32_t ok = (z & t & v) >> 31;

    x->s = (x->s ^ (uint64_t)k) * RF_B;
    x->c = c;
    x->h = h;
    x->e = p;
    x->g = r;
    return ok;
}
