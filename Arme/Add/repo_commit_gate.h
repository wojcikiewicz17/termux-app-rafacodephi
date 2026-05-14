#ifndef RAFAELIA_COMMIT_GATE_LL_H
#define RAFAELIA_COMMIT_GATE_LL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t s;
    uint32_t e;
    uint32_t c;
    uint32_t h;
    uint32_t g;
} rfg_t;

void rfg_i(rfg_t* x, uint64_t z);
uint32_t rfg_u(rfg_t* x, uint32_t ci, uint32_t hi, uint32_t st, uint32_t hx);

#ifdef __cplusplus
}
#endif

#endif
