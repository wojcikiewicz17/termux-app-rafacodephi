/**
 * Bare-metal low-level operations for Termux
 * RAFAELIA Framework - Header File
 * No external dependencies, architecture-optimized
 * 
 * This header defines the RAFAELIA computational framework interface:
 * - Matrix operations with deterministic mathematics
 * - Vector operations optimized with SIMD
 * - Flip operations for matrix solving (horizontal, vertical, diagonal)
 * - Fast math functions without legacy dependencies
 * - Bare-metal memory and string operations
 * 
 * Design Principles (RAFAELIA):
 * - Φ_ethica: Minimize entropy, maximize coherence
 * - Determinism: Predictable, reproducible results
 * - Self-contained: No external library dependencies
 * - Hardware-optimized: NEON/AVX/SSE support
 * - Modular: Clean separation of concerns
 * 
 * Copyright (c) 2024-present instituto-Rafael
 * License: GPLv3
 * Attribution: RAFAELIA Framework - RAFCODE-Φ
 */

#ifndef TERMUX_BAREMETAL_H
#define TERMUX_BAREMETAL_H

#include <stdint.h>
#include <stddef.h>

/* Architecture detection */
#if defined(__aarch64__) || defined(__arm64__)
    #define ARCH_ARM64 1
    #define ARCH_NAME "arm64-v8a"
#elif defined(__arm__) || defined(__ARM_ARCH_7A__)
    #define ARCH_ARM32 1
    #define ARCH_NAME "armeabi-v7a"
#elif defined(__x86_64__) || defined(__amd64__)
    #define ARCH_X86_64 1
    #define ARCH_NAME "x86_64"
#elif defined(__i386__) || defined(__i686__)
    #define ARCH_X86 1
    #define ARCH_NAME "x86"
#else
    #define ARCH_GENERIC 1
    #define ARCH_NAME "generic"
#endif

/* SIMD capability detection */
#if defined(__ARM_NEON) || defined(__ARM_NEON__)
    #define HAS_NEON 1
#endif


#if defined(__AVX2__)
    #define HAS_AVX2 1
#elif defined(__AVX__)
    #define HAS_AVX 1
#elif defined(__SSE4_2__)
    #define HAS_SSE42 1
#elif defined(__SSE2__)
    #define HAS_SSE2 1
#endif

/* Matrix structure - unnamed variables as requested */
typedef struct {
    float* m;       /* Matrix data */
    uint32_t r;     /* Rows */
    uint32_t c;     /* Columns */
} mx_t;

/* Vector operations */
void vop_add(const float* a, const float* b, float* r, uint32_t n);
void vop_sub(const float* a, const float* b, float* r, uint32_t n);
void vop_mul(const float* a, const float* b, float* r, uint32_t n);
void vop_scale(float* a, float s, uint32_t n);
void vop_copy(const float* a, float* r, uint32_t n);
void vop_fill(float* a, float v, uint32_t n);
float vop_sum(const float* a, uint32_t n);
float vop_min(const float* a, uint32_t n);
float vop_max(const float* a, uint32_t n);
float vop_dot(const float* a, const float* b, uint32_t n);
float vop_norm(const float* a, uint32_t n);

/* ASM kernels (runtime-dispatched when available) */
#if defined(HAS_BM_NEON_ASM)
extern float bm_dot_neon(const float* a, const float* b, uint32_t n);
extern void bm_vadd_neon(const float* a, const float* b, float* r, uint32_t n);
extern void* bm_memcpy_neon(void* d, const void* s, size_t n);
#endif



typedef struct {
    unsigned char* base;
    size_t cap;
    size_t off;
} mx_arena_t;

mx_arena_t* arena_create(size_t capacity_bytes);
void* arena_alloc(mx_arena_t* arena, size_t size_bytes, size_t alignment);
void arena_reset(mx_arena_t* arena);
void arena_destroy(mx_arena_t* arena);
mx_t* mx_create_in_arena(mx_arena_t* arena, uint32_t r, uint32_t c);

/* Matrix operations - deterministic mathematics */
mx_t* mx_create(uint32_t r, uint32_t c);
void mx_free(mx_t* m);
void mx_mul(const mx_t* a, const mx_t* b, mx_t* r);
void mx_transpose(const mx_t* a, mx_t* r);
void mx_zero(mx_t* m);
void mx_copy(const mx_t* a, mx_t* r);
void mx_fill(mx_t* m, float v);
float mx_det(const mx_t* m);
int mx_inv(const mx_t* m, mx_t* r);

/* Flip operations for matrix solving - RAFAELIA deterministic method */
void mx_flip_h(mx_t* m);  /* Horizontal flip */
void mx_flip_v(mx_t* m);  /* Vertical flip */
void mx_flip_d(mx_t* m);  /* Diagonal flip (transpose) */

/* Advanced matrix operations - RAFAELIA extended methods */
void mx_add(const mx_t* a, const mx_t* b, mx_t* r);  /* Element-wise addition */
void mx_sub(const mx_t* a, const mx_t* b, mx_t* r);  /* Element-wise subtraction */
void mx_scale(mx_t* m, float s);  /* Scalar multiplication */
float mx_trace(const mx_t* m);  /* Trace (sum of diagonal) */
void mx_identity(mx_t* m);  /* Set to identity matrix */
int mx_solve_linear(const mx_t* a, const float* b, float* x);  /* Solve Ax=b */

/* Fast math - no legacy functions */
float fm_sqrt(float x);
float fm_rsqrt(float x);  /* Reciprocal sqrt */
float fm_pow2(float x);
float fm_exp(float x);
float fm_log(float x);

/* Memory operations - bare-metal */
void* bmem_cpy(void* d, const void* s, size_t n);
void* bmem_set(void* d, int v, size_t n);
void* bmem_zero(void* d, size_t n);
int bmem_cmp(const void* a, const void* b, size_t n);

/* String operations - no libc */
size_t bstr_len(const char* s);
int bstr_cmp(const char* a, const char* b);
char* bstr_cpy(char* d, const char* s);

/* Architecture info */
const char* get_arch_name(void);
uint32_t get_arch_caps(void);
uint32_t get_arch_runtime_caps(void);
uint32_t get_arch_binary_caps(void);
int get_arch_runtime_caps_valid(void);

typedef struct {
    char abi[24];
    uint64_t hwcap;
    uint64_t hwcap2;
    uint32_t cpus_online;
    uint32_t page_size;
    uint32_t cache_line;
    uint32_t access_flags;
    char cpu_clusters[128];
} hw_profile_t;

void get_hw_profile(hw_profile_t* p);

/* Capability flags */
#define CAP_NEON     (1 << 0)
#define CAP_AVX      (1 << 1)
#define CAP_AVX2     (1 << 2)
#define CAP_SSE2     (1 << 3)
#define CAP_SSE42    (1 << 4)
#define CAP_ASIMD    (1 << 5)
#define CAP_SVE      (1 << 6)
#define CAP_SVE2     (1 << 7)
#define CAP_SSE      (1 << 8)

/* User-space accessibility flags */
#define HW_ACCESS_HAS_ABI               (1u << 0)
#define HW_ACCESS_HAS_HWCAP             (1u << 1)
#define HW_ACCESS_HAS_HWCAP2            (1u << 2)
#define HW_ACCESS_HAS_CPUS_ONLINE       (1u << 3)
#define HW_ACCESS_HAS_CPU_CLUSTER_FREQ  (1u << 4)
#define HW_ACCESS_HAS_PAGE_SIZE         (1u << 5)
#define HW_ACCESS_HAS_CACHE_LINE        (1u << 6)
#define HW_ACCESS_NO_PHYS_REG_ACCESS    (1u << 28)
#define HW_ACCESS_NO_GPIO_PIN_ACCESS    (1u << 29)
#define HW_ACCESS_NO_KERNEL_MMIO_ACCESS (1u << 30)

#endif /* TERMUX_BAREMETAL_H */
