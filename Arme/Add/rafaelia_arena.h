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
