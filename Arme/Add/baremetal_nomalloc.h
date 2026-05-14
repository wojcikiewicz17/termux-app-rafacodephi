/**
 * baremetal_nomalloc.h
 * RAFAELIA — header atualizado: zero malloc, arena estática
 * Drop-in replacement para baremetal.h
 */
#pragma once
#ifndef BAREMETAL_NOMALLOC_H
#define BAREMETAL_NOMALLOC_H

#include <stdint.h>
#include <stddef.h>

/* ── Detecção de arco ─────────────────────────────────────────────────── */
#if defined(__aarch64__)||defined(__arm64__)
  #define ARCH_NAME "arm64-v8a"
  #define RAF_ARCH64 1
#elif defined(__arm__)||defined(__ARM_ARCH)
  #define ARCH_NAME "armeabi-v7a"
  #define RAF_ARCH32 1
#elif defined(__x86_64__)
  #define ARCH_NAME "x86_64"
#elif defined(__i386__)
  #define ARCH_NAME "x86"
#else
  #define ARCH_NAME "generic"
#endif

/* NEON disponível? */
#if defined(__ARM_NEON)||defined(__ARM_NEON__)
  #define HAS_NEON 1
  #include <arm_neon.h>
#endif

/* ── HWCAP bits ───────────────────────────────────────────────────────── */
#define CAP_NEON   (1u<<0)
#define CAP_ASIMD  (1u<<1)
#define CAP_SVE    (1u<<2)
#define CAP_SVE2   (1u<<3)
#define CAP_SSE2   (1u<<8)
#define CAP_SSE42  (1u<<9)
#define CAP_AVX    (1u<<10)
#define CAP_AVX2   (1u<<11)

/* ── Arena estática ───────────────────────────────────────────────────── */
typedef struct {
    unsigned char *base;
    size_t         cap;
    size_t         off;
} mx_arena_t;

mx_arena_t *arena_create(size_t cap);
void       *arena_alloc(mx_arena_t *a, size_t sz, size_t align);
void        arena_reset(mx_arena_t *a);
void        arena_destroy(mx_arena_t *a);  /* no-op, arena é estática */

/* ── Matrix ───────────────────────────────────────────────────────────── */
typedef struct { float *m; uint32_t r, c; } mx_t;

mx_t  *mx_create(uint32_t r, uint32_t c);
mx_t  *mx_create_in_arena(mx_arena_t *a, uint32_t r, uint32_t c);
void   mx_free(mx_t *m);          /* no-op: arena não libera individual */
void   mx_zero(mx_t *m);
void   mx_fill(mx_t *m, float v);
void   mx_copy(const mx_t *a, mx_t *r);
void   mx_identity(mx_t *m);
void   mx_add(const mx_t *a, const mx_t *b, mx_t *r);
void   mx_sub(const mx_t *a, const mx_t *b, mx_t *r);
void   mx_scale(mx_t *m, float s);
void   mx_mul(const mx_t *a, const mx_t *b, mx_t *r);
void   mx_transpose(const mx_t *a, mx_t *r);
float  mx_trace(const mx_t *m);
float  mx_det(const mx_t *m);
int    mx_inv(const mx_t *m, mx_t *r);
int    mx_solve_linear(const mx_t *a, const float *b, float *x);
void   mx_flip_h(mx_t *m);
void   mx_flip_v(mx_t *m);
void   mx_flip_d(mx_t *m);

/* ── Vector ops ───────────────────────────────────────────────────────── */
void  vop_add(const float*a,const float*b,float*r,uint32_t n);
void  vop_sub(const float*a,const float*b,float*r,uint32_t n);
void  vop_mul(const float*a,const float*b,float*r,uint32_t n);
void  vop_scale(float*a,float s,uint32_t n);
void  vop_copy(const float*a,float*r,uint32_t n);
void  vop_fill(float*a,float v,uint32_t n);
float vop_sum(const float*a,uint32_t n);
float vop_min(const float*a,uint32_t n);
float vop_max(const float*a,uint32_t n);
float vop_dot(const float*a,const float*b,uint32_t n);
float vop_norm(const float*a,uint32_t n);

/* ── Fast math (sem libm no hot path) ────────────────────────────────── */
float fm_rsqrt(float x);
float fm_sqrt(float x);
float fm_pow2(float x);
float fm_exp(float x);
float fm_log(float x);

/* ── Mem/string bare-metal ────────────────────────────────────────────── */
void  *bmem_cpy(void*d,const void*s,size_t n);
void  *bmem_set(void*d,int v,size_t n);
void  *bmem_zero(void*d,size_t n);
int    bmem_cmp(const void*a,const void*b,size_t n);
size_t bstr_len(const char*s);
int    bstr_cmp(const char*a,const char*b);
char  *bstr_cpy(char*d,const char*s);

/* ── Arch / HW profile ────────────────────────────────────────────────── */
const char *get_arch_name(void);
uint32_t    get_arch_caps(void);
uint32_t    get_arch_runtime_caps(void);
uint32_t    get_arch_binary_caps(void);
int         get_arch_runtime_caps_valid(void);

#define HW_ACCESS_HAS_ABI               (1u<<0)
#define HW_ACCESS_HAS_HWCAP             (1u<<1)
#define HW_ACCESS_HAS_HWCAP2            (1u<<2)
#define HW_ACCESS_HAS_CPUS_ONLINE       (1u<<3)
#define HW_ACCESS_HAS_CPU_CLUSTER_FREQ  (1u<<4)
#define HW_ACCESS_HAS_PAGE_SIZE         (1u<<5)
#define HW_ACCESS_HAS_CACHE_LINE        (1u<<6)
#define HW_ACCESS_NO_PHYS_REG_ACCESS    (1u<<16)
#define HW_ACCESS_NO_GPIO_PIN_ACCESS    (1u<<17)
#define HW_ACCESS_NO_KERNEL_MMIO_ACCESS (1u<<18)

typedef struct {
    char     abi[32];
    uint64_t hwcap;
    uint64_t hwcap2;
    uint32_t cpus_online;
    char     cpu_clusters[256];
    uint32_t page_size;
    uint32_t cache_line;
    uint32_t access_flags;
} hw_profile_t;

void get_hw_profile(hw_profile_t *p);

#endif /* BAREMETAL_NOMALLOC_H */
