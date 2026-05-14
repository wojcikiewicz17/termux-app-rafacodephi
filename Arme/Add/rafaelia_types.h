/**
 * rafaelia_types.h — tipos primitivos RAFAELIA
 * SPDX-License-Identifier: GPL-3.0-only
 * Termux ARM32 · Bionic libc · zero overhead
 *
 * Conforma: ARM IHI 0042J §C1, IEEE Std 1003.1-2017
 */
#pragma once
#ifndef RAFAELIA_TYPES_H
#define RAFAELIA_TYPES_H

#include <stdint.h>
#include <stddef.h>

/* ── Tipos sem ambiguidade ────────────────────────────────────────────── */
typedef uint8_t   u8;
typedef uint16_t  u16;
typedef uint32_t  u32;
typedef uint64_t  u64;
typedef int8_t    i8;
typedef int16_t   i16;
typedef int32_t   i32;
typedef int64_t   i64;
typedef float     f32;

/* ARM32: sizeof(ptr)=4, sizeof(long)=4, sizeof(f32)=4 */
/* f64 PROIBIDO no hot path: 2x custo em softfp ARM32   */

/* ── Constantes Q16.16 ────────────────────────────────────────────────── */
#define Q16_ONE     65536u
#define Q16_HALF    32768u
#define Q16_SPIRAL  56755u   /* sqrt(3)/2 */
#define Q16_PHI     105965u  /* (1+sqrt(5))/2 */
#define Q16_PI      205887u  /* pi */
#define Q16_2PI     411774u  /* 2*pi */
#define Q16_INV6    10923u   /* 1/6 */
#define Q16_INV120  546u     /* 1/120 */

/* ── Status ───────────────────────────────────────────────────────────── */
#define RAF_OK    0
#define RAF_ERR  -1
#define RAF_OOM  -2

/* ── Alinhamentos ─────────────────────────────────────────────────────── */
#define ALIGN64  __attribute__((aligned(64)))
#define ALIGN16  __attribute__((aligned(16)))
#define FORCEINL __attribute__((always_inline)) static inline
#define NOINL    __attribute__((noinline))
#define PACKED   __attribute__((packed))

/* ── Constantes do sistema ────────────────────────────────────────────── */
#define PERIOD      42u
#define TORUS_DIM   7u
#define N_VCPU      8u
#define N_STACKS    1000u
#define N_EXTRA     8u
#define N_TOTAL     1008u
#define CACHE_LINE  64u

/* ── Q16.16 ops ───────────────────────────────────────────────────────── */
static inline u32 qmul(u32 a, u32 b){
    return (u32)(((u64)a*b)>>16);
}
static inline u32 qema(u32 old, u32 in){
    /* 0.75*old + 0.25*in  — sem float, sem divisão */
    return (u32)(((u64)old*49152u+(u64)in*16384u)>>16);
}
static inline u32 qabs(i32 v){
    return (u32)(v<0?-v:v);
}

/* ── sin Taylor Q16.16 — domínio público ─────────────────────────────── */
static inline u32 qsin(u32 x){
    while(x>=Q16_2PI) x-=Q16_2PI;
    int neg=0;
    if(x>=Q16_PI){x-=Q16_PI;neg=1;}
    u64 x2=(u64)x*x>>16;
    u64 x3=(u64)x2*x>>16;
    u64 x5=(u64)x3*x2>>16;
    u64 t1=(u64)x3*Q16_INV6>>16;
    u64 t2=(u64)x5*Q16_INV120>>16;
    i64 r=(i64)x-(i64)t1+(i64)t2;
    if(r<0)r=0; if(r>65535)r=65535;
    return neg?(u32)(65535u-(u32)r):(u32)r;
}

#endif /* RAFAELIA_TYPES_H */
