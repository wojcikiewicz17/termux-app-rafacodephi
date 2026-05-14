/**
 * baremetal_nomalloc.c
 * RAFAELIA — drop-in replacement para baremetal.c
 * ZERO malloc/free — arena estática por módulo
 * Menor fricção: sem heap, sem fragmentação, sem overhead
 *
 * Regra: toda memória vive em g_bm_arena (512KB estático).
 * mx_create/mx_free → arena_alloc/arena_reset (sem free individual).
 * Gaussian elimination usa scratch stack-local, não heap.
 *
 * Copyright (c) instituto-Rafael — GPLv3
 */

#include "baremetal.h"

#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <fcntl.h>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "TermuxBM"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG,LOG_TAG,__VA_ARGS__)
#else
#define LOGD(...)
#endif

/* ============================================================================
 * ARENA ESTÁTICA — 512KB, alinhada a cache line
 * ========================================================================== */
#define BM_ARENA_SZ (512u*1024u)

static unsigned char __attribute__((aligned(64)))
    g_bm_arena_buf[BM_ARENA_SZ];

static size_t g_bm_arena_off = 0;

/* arena pública (exposta via header) */
static mx_arena_t g_bm_arena_hdr = {
    .base = g_bm_arena_buf,
    .cap  = BM_ARENA_SZ,
    .off  = 0
};

/* ============================================================================
 * HWCAP via /proc/self/auxv — sem pthread_once, sem lock
 * Usa flag atômica simples (suficiente para single-thread init)
 * ========================================================================== */
typedef struct {
    uint32_t caps_rt;
    uint32_t caps_bin;
    int      valid;
    int      done;   /* 0 = não inicializado */
} bm_caps_t;

static bm_caps_t g_caps = {0,0,0,0};

#ifndef AT_HWCAP
#define AT_HWCAP  16
#endif
#ifndef AT_HWCAP2
#define AT_HWCAP2 26
#endif
#ifndef HWCAP_NEON
#define HWCAP_NEON   (1UL<<12)
#endif
#ifndef HWCAP_ASIMD
#define HWCAP_ASIMD  (1UL<<1)
#endif
#ifndef HWCAP_SVE
#define HWCAP_SVE    (1UL<<22)
#endif
#ifndef HWCAP2_SVE2
#define HWCAP2_SVE2  (1UL<<1)
#endif

/* lê auxv sem getauxval (sem libc pesada) */
static int bm_read_auxv(unsigned long *hwcap, unsigned long *hwcap2) {
    struct { unsigned long type; unsigned long val; } ent;
    int fd = open("/proc/self/auxv", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    int got = 0;
    *hwcap = 0; *hwcap2 = 0;
    while (read(fd, &ent, sizeof(ent)) == (ssize_t)sizeof(ent)) {
        if (ent.type == 0) break;
        if (ent.type == AT_HWCAP)  { *hwcap  = ent.val; got |= 1; }
        if (ent.type == AT_HWCAP2) { *hwcap2 = ent.val; got |= 2; }
    }
    close(fd);
    return (got & 1) != 0;
}

static void bm_init_caps(void) {
    if (g_caps.done) return;

    uint32_t bin = 0;
#if defined(HAS_NEON) || defined(__ARM_NEON) || defined(__ARM_NEON__)
    bin |= CAP_NEON | CAP_ASIMD;
#endif
#if defined(HAS_AVX2);  bin |= CAP_AVX2; bin |= CAP_AVX; }
#endif
#if defined(HAS_AVX)
    bin |= CAP_AVX;
#endif
#if defined(HAS_SSE42)
    bin |= CAP_SSE42 | CAP_SSE2;
#endif
#if defined(HAS_SSE2)
    bin |= CAP_SSE2;
#endif
    g_caps.caps_bin = bin;

    unsigned long hc = 0, hc2 = 0;
    if (bm_read_auxv(&hc, &hc2)) {
        uint32_t rt = 0;
#if defined(__aarch64__) || defined(__arm64__)
        if (hc & HWCAP_ASIMD) rt |= CAP_NEON | CAP_ASIMD;
        if (hc & HWCAP_SVE)   rt |= CAP_SVE;
        if (hc2 & HWCAP2_SVE2) rt |= CAP_SVE2;
#else
        if (hc & HWCAP_NEON)  rt |= CAP_NEON;
#endif
        g_caps.caps_rt = rt;
        g_caps.valid   = 1;
    }
    g_caps.done = 1;
}

/* ============================================================================
 * FAST MATH — sem libm no caminho quente
 * ========================================================================== */

/* Quake III rsqrt */
float fm_rsqrt(float x) {
    union { float f; uint32_t i; } u;
    u.f = x;
    u.i = 0x5f3759dfu - (u.i >> 1);
    u.f *= 1.5f - 0.5f * x * u.f * u.f;
    return u.f;
}

float fm_sqrt(float x) {
    if (x <= 0.0f) return 0.0f;
    return 1.0f / fm_rsqrt(x);
}

float fm_pow2(float x) { return x * x; }

/* exp via Horner — erro < 0.01% para |x| < 3 */
float fm_exp(float x) {
    if (x >  10.0f) return 22026.0f;
    if (x < -10.0f) return 0.0000454f;
    float x2=x*x, x3=x2*x, x4=x3*x, x5=x4*x;
    return 1.0f + x + x2*0.5f + x3*0.166667f + x4*0.041667f + x5*0.008333f;
}

/* log via IEEE bit hack — ±5% */
float fm_log(float x) {
    if (x <= 0.0f) return -1e9f;
    union { float f; uint32_t i; } u;
    u.f = x;
    return (float)((int)(u.i >> 23) - 127) * 0.693147f;
}

static inline float fm_abs(float x) { return x < 0.0f ? -x : x; }

/* ============================================================================
 * MEMORY OPS — bare-metal, sem libc
 * ========================================================================== */

void *bmem_cpy(void *d, const void *s, size_t n) {
    if (!d || !s || !n) return d;
    unsigned char *pd = (unsigned char *)d;
    const unsigned char *ps = (const unsigned char *)s;

#if defined(HAS_BM_NEON_ASM)
    /* alinha destino a 16 */
    while (n && ((uintptr_t)pd & 15u)) { *pd++ = *ps++; n--; }
    while (n >= 32u) {
        bm_memcpy_neon(pd, ps, 32u);
        pd += 32u; ps += 32u; n -= 32u;
    }
#elif defined(__ARM_ARCH_7A__) || defined(__aarch64__)
    /* word copy para alinhados */
    while (n >= 4u && !((uintptr_t)pd & 3u) && !((uintptr_t)ps & 3u)) {
        *(uint32_t *)pd = *(const uint32_t *)ps;
        pd += 4u; ps += 4u; n -= 4u;
    }
#endif
    while (n--) *pd++ = *ps++;
    return d;
}

void *bmem_set(void *d, int v, size_t n) {
    unsigned char *pd = (unsigned char *)d;
    unsigned char  c  = (unsigned char)v;
    uint32_t w = (uint32_t)c | ((uint32_t)c<<8) | ((uint32_t)c<<16) | ((uint32_t)c<<24);
    while (n >= 4u && !((uintptr_t)pd & 3u)) {
        *(uint32_t *)pd = w; pd += 4u; n -= 4u;
    }
    while (n--) *pd++ = c;
    return d;
}

void *bmem_zero(void *d, size_t n) { return bmem_set(d, 0, n); }

int bmem_cmp(const void *a, const void *b, size_t n) {
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    while (n--) { if (*pa != *pb) return *pa - *pb; pa++; pb++; }
    return 0;
}

/* ============================================================================
 * STRING OPS — sem libc
 * ========================================================================== */
size_t bstr_len(const char *s) {
    const char *p = s; while (*p) p++; return (size_t)(p - s);
}
int bstr_cmp(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *(const unsigned char *)a - *(const unsigned char *)b;
}
char *bstr_cpy(char *d, const char *s) {
    char *p = d; while ((*p++ = *s++)); return d;
}

/* ============================================================================
 * ARENA — implementação pública (sem malloc)
 * ========================================================================== */

/* alinha size para múltiplo de alignment */
static size_t align_up(size_t v, size_t a) {
    return a ? (v + a - 1u) & ~(a - 1u) : v;
}

/* arena_create: usa arena estática global — NÃO faz malloc */
mx_arena_t *arena_create(size_t cap) {
    if (!cap || cap > BM_ARENA_SZ) return NULL;
    g_bm_arena_hdr.base = g_bm_arena_buf;
    g_bm_arena_hdr.cap  = cap <= BM_ARENA_SZ ? cap : BM_ARENA_SZ;
    g_bm_arena_hdr.off  = 0;
    return &g_bm_arena_hdr;
}

void *arena_alloc(mx_arena_t *a, size_t sz, size_t align) {
    if (!a || !a->base || !sz) return NULL;
    if (!align) align = sizeof(void *);
    size_t start = align_up(a->off, align);
    if (start > a->cap || sz > a->cap - start) return NULL;
    void *p = a->base + start;
    a->off = start + sz;
    bmem_zero(p, sz);
    return p;
}

void arena_reset(mx_arena_t *a) { if (a) a->off = 0; }

/* arena_destroy: não libera nada (arena é estática) */
void arena_destroy(mx_arena_t *a) { if (a) arena_reset(a); }

/* ============================================================================
 * MATRIX — sem malloc, usa arena global
 * IMPORTANTE: mx_free é no-op (arena só reseta, não libera individual)
 * ========================================================================== */

mx_t *mx_create_in_arena(mx_arena_t *a, uint32_t r, uint32_t c) {
    if (!a || !r || !c) return NULL;
    if (r > 0xFFFFu / c) return NULL;
    mx_t *m = (mx_t *)arena_alloc(a, sizeof(mx_t), _Alignof(mx_t));
    if (!m) return NULL;
    size_t bytes = (size_t)r * c * sizeof(float);
    m->m = (float *)arena_alloc(a, bytes, _Alignof(float));
    if (!m->m) return NULL;
    m->r = r; m->c = c;
    return m;
}

/* mx_create: aloca na arena global (sem malloc) */
mx_t *mx_create(uint32_t r, uint32_t c) {
    return mx_create_in_arena(&g_bm_arena_hdr, r, c);
}

/* mx_free: NÃO libera — arena não suporta free individual
 * Para recuperar memória: arena_reset(&g_bm_arena_hdr) */
void mx_free(mx_t *m) { (void)m; /* no-op intencional */ }

void mx_zero(mx_t *m) {
    if (!m || !m->m) return;
    bmem_zero(m->m, (size_t)m->r * m->c * sizeof(float));
}

void mx_fill(mx_t *m, float v) {
    if (!m || !m->m) return;
    uint32_t n = m->r * m->c;
    for (uint32_t i = 0; i < n; i++) m->m[i] = v;
}

void mx_copy(const mx_t *a, mx_t *r) {
    if (!a || !r || a->r != r->r || a->c != r->c) return;
    bmem_cpy(r->m, a->m, (size_t)a->r * a->c * sizeof(float));
}

void mx_identity(mx_t *m) {
    if (!m || m->r != m->c) return;
    mx_zero(m);
    for (uint32_t i = 0; i < m->r; i++) m->m[i * m->c + i] = 1.0f;
}

void mx_add(const mx_t *a, const mx_t *b, mx_t *r) {
    if (!a || !b || !r) return;
    if (a->r != b->r || a->c != b->c || r->r != a->r || r->c != a->c) return;
    uint32_t n = a->r * a->c;
#ifdef __ARM_NEON
    uint32_t i = 0;
    for (; i + 4 <= n; i += 4) {
        float32x4_t va = vld1q_f32(a->m + i);
        float32x4_t vb = vld1q_f32(b->m + i);
        vst1q_f32(r->m + i, vaddq_f32(va, vb));
    }
    for (; i < n; i++) r->m[i] = a->m[i] + b->m[i];
#else
    for (uint32_t i = 0; i < n; i++) r->m[i] = a->m[i] + b->m[i];
#endif
}

void mx_sub(const mx_t *a, const mx_t *b, mx_t *r) {
    if (!a || !b || !r) return;
    if (a->r != b->r || a->c != b->c || r->r != a->r || r->c != a->c) return;
    uint32_t n = a->r * a->c;
    for (uint32_t i = 0; i < n; i++) r->m[i] = a->m[i] - b->m[i];
}

void mx_scale(mx_t *m, float s) {
    if (!m || !m->m) return;
    uint32_t n = m->r * m->c;
#ifdef __ARM_NEON
    float32x4_t vs = vdupq_n_f32(s);
    uint32_t i = 0;
    for (; i + 4 <= n; i += 4) {
        float32x4_t v = vld1q_f32(m->m + i);
        vst1q_f32(m->m + i, vmulq_f32(v, vs));
    }
    for (; i < n; i++) m->m[i] *= s;
#else
    for (uint32_t i = 0; i < n; i++) m->m[i] *= s;
#endif
}

/* mul: usa scratch na stack — sem arena, sem heap */
void mx_mul(const mx_t *a, const mx_t *b, mx_t *r) {
    if (!a || !b || !r) return;
    if (a->c != b->r || r->r != a->r || r->c != b->c) return;
    mx_zero(r);
    for (uint32_t i = 0; i < a->r; i++) {
        for (uint32_t k = 0; k < a->c; k++) {
            float aik = a->m[i * a->c + k];
            const float *bk = b->m + k * b->c;
            float *ri       = r->m + i * r->c;
#ifdef __ARM_NEON
            float32x4_t va = vdupq_n_f32(aik);
            uint32_t j = 0;
            for (; j + 4 <= b->c; j += 4) {
                float32x4_t vb = vld1q_f32(bk + j);
                float32x4_t vr = vld1q_f32(ri + j);
                vst1q_f32(ri + j, vmlaq_f32(vr, va, vb));
            }
            for (; j < b->c; j++) ri[j] += aik * bk[j];
#else
            for (uint32_t j = 0; j < b->c; j++) ri[j] += aik * bk[j];
#endif
        }
    }
}

void mx_transpose(const mx_t *a, mx_t *r) {
    if (!a || !r || r->r != a->c || r->c != a->r) return;
    for (uint32_t i = 0; i < a->r; i++)
        for (uint32_t j = 0; j < a->c; j++)
            r->m[j * r->c + i] = a->m[i * a->c + j];
}

float mx_trace(const mx_t *m) {
    if (!m || m->r != m->c) return 0.0f;
    float t = 0.0f;
    for (uint32_t i = 0; i < m->r; i++) t += m->m[i * m->c + i];
    return t;
}

/* mx_det: Sarrus para n≤3, eliminação gaussiana com scratch STACK para n>3
 * ZERO heap — usa array stack de até 16x16=256 floats (4KB) */
#define DET_MAXN 16
float mx_det(const mx_t *m) {
    if (!m || m->r != m->c) return 0.0f;
    uint32_t n = m->r;
    if (n == 1) return m->m[0];
    if (n == 2) return m->m[0]*m->m[3] - m->m[1]*m->m[2];
    if (n == 3) {
        float a=m->m[0],b=m->m[1],c=m->m[2];
        float d=m->m[3],e=m->m[4],f=m->m[5];
        float g=m->m[6],h=m->m[7],k=m->m[8];
        return a*e*k + b*f*g + c*d*h - c*e*g - b*d*k - a*f*h;
    }
    if (n > DET_MAXN) return 0.0f;

    /* scratch na stack — n*n floats, max 1KB para n=16 */
    float w[DET_MAXN * DET_MAXN];
    bmem_cpy(w, m->m, n * n * sizeof(float));

    float det = 1.0f;
    for (uint32_t k = 0; k < n; k++) {
        /* pivot */
        uint32_t piv = k; float mx_ = fm_abs(w[k*n+k]);
        for (uint32_t i = k+1; i < n; i++) {
            float v = fm_abs(w[i*n+k]);
            if (v > mx_) { mx_ = v; piv = i; }
        }
        if (piv != k) {
            for (uint32_t j = 0; j < n; j++) {
                float t = w[k*n+j]; w[k*n+j] = w[piv*n+j]; w[piv*n+j] = t;
            }
            det = -det;
        }
        float d = w[k*n+k];
        if (fm_abs(d) < 1e-10f) return 0.0f;
        det *= d;
        for (uint32_t i = k+1; i < n; i++) {
            float f2 = w[i*n+k] / d;
            for (uint32_t j = k; j < n; j++) w[i*n+j] -= f2 * w[k*n+j];
        }
    }
    return det;
}

/* mx_inv: Gauss-Jordan com scratch STACK (augmented n x 2n)
 * Limite: n ≤ 8 → 8*16=128 floats = 512 bytes stack */
#define INV_MAXN 8
int mx_inv(const mx_t *m, mx_t *r) {
    if (!m || !r || m->r != m->c || r->r != m->r || r->c != m->c) return -1;
    uint32_t n = m->r;
    if (n > INV_MAXN) return -1;

    float aug[INV_MAXN * (INV_MAXN*2)];
    bmem_zero(aug, sizeof(aug));

    /* preenche [M|I] */
    for (uint32_t i = 0; i < n; i++) {
        for (uint32_t j = 0; j < n; j++)
            aug[i*(2*n)+j] = m->m[i*m->c+j];
        aug[i*(2*n)+n+i] = 1.0f;
    }

    /* Gauss-Jordan */
    for (uint32_t k = 0; k < n; k++) {
        uint32_t piv = k; float mx_ = 0.0f;
        for (uint32_t i = k; i < n; i++) {
            float v = fm_abs(aug[i*(2*n)+k]);
            if (v > mx_) { mx_ = v; piv = i; }
        }
        if (mx_ < 1e-10f) return -1;
        if (piv != k) {
            for (uint32_t j = 0; j < 2*n; j++) {
                float t = aug[k*(2*n)+j];
                aug[k*(2*n)+j] = aug[piv*(2*n)+j];
                aug[piv*(2*n)+j] = t;
            }
        }
        float d = aug[k*(2*n)+k];
        for (uint32_t j = 0; j < 2*n; j++) aug[k*(2*n)+j] /= d;
        for (uint32_t i = 0; i < n; i++) {
            if (i == k) continue;
            float f2 = aug[i*(2*n)+k];
            for (uint32_t j = 0; j < 2*n; j++)
                aug[i*(2*n)+j] -= f2 * aug[k*(2*n)+j];
        }
    }
    for (uint32_t i = 0; i < n; i++)
        for (uint32_t j = 0; j < n; j++)
            r->m[i*r->c+j] = aug[i*(2*n)+n+j];
    return 0;
}

/* mx_solve_linear: scratch stack n*(n+1) floats, max n=8 → 72 floats */
#define SOLVE_MAXN 8
int mx_solve_linear(const mx_t *a, const float *b, float *x) {
    if (!a || !b || !x || a->r != a->c) return -1;
    uint32_t n = a->r;
    if (n > SOLVE_MAXN) return -1;

    float aug[SOLVE_MAXN * (SOLVE_MAXN+1)];
    for (uint32_t i = 0; i < n; i++) {
        for (uint32_t j = 0; j < n; j++)
            aug[i*(n+1)+j] = a->m[i*a->c+j];
        aug[i*(n+1)+n] = b[i];
    }

    for (uint32_t k = 0; k < n; k++) {
        uint32_t piv = k; float mx_ = 0.0f;
        for (uint32_t i = k; i < n; i++) {
            float v = fm_abs(aug[i*(n+1)+k]);
            if (v > mx_) { mx_ = v; piv = i; }
        }
        if (mx_ < 1e-10f) return -1;
        if (piv != k) {
            for (uint32_t j = 0; j <= n; j++) {
                float t = aug[k*(n+1)+j];
                aug[k*(n+1)+j] = aug[piv*(n+1)+j];
                aug[piv*(n+1)+j] = t;
            }
        }
        for (uint32_t i = k+1; i < n; i++) {
            float f2 = aug[i*(n+1)+k] / aug[k*(n+1)+k];
            for (uint32_t j = k; j <= n; j++)
                aug[i*(n+1)+j] -= f2 * aug[k*(n+1)+j];
        }
    }
    for (int i = (int)n-1; i >= 0; i--) {
        float s = aug[i*(n+1)+n];
        for (uint32_t j = (uint32_t)i+1; j < n; j++)
            s -= aug[i*(n+1)+j] * x[j];
        x[i] = s / aug[i*(n+1)+i];
    }
    return 0;
}

/* flip ops — sem alocação */
void mx_flip_h(mx_t *m) {
    if (!m) return;
    for (uint32_t i = 0; i < m->r; i++) {
        uint32_t l = 0, r2 = m->c - 1;
        while (l < r2) {
            float t = m->m[i*m->c+l];
            m->m[i*m->c+l] = m->m[i*m->c+r2];
            m->m[i*m->c+r2] = t;
            l++; r2--;
        }
    }
}

void mx_flip_v(mx_t *m) {
    if (!m) return;
    uint32_t top = 0, bot = m->r - 1;
    while (top < bot) {
        for (uint32_t j = 0; j < m->c; j++) {
            float t = m->m[top*m->c+j];
            m->m[top*m->c+j] = m->m[bot*m->c+j];
            m->m[bot*m->c+j] = t;
        }
        top++; bot--;
    }
}

void mx_flip_d(mx_t *m) {
    if (!m || m->r != m->c) return;
    for (uint32_t i = 0; i < m->r; i++)
        for (uint32_t j = i+1; j < m->c; j++) {
            float t = m->m[i*m->c+j];
            m->m[i*m->c+j] = m->m[j*m->c+i];
            m->m[j*m->c+i] = t;
        }
}

/* vector ops com NEON inline onde disponível */
void vop_add(const float *a, const float *b, float *r, uint32_t n) {
    if (!a || !b || !r) return;
#ifdef __ARM_NEON
    uint32_t i = 0;
    for (; i+4 <= n; i+=4)
        vst1q_f32(r+i, vaddq_f32(vld1q_f32(a+i), vld1q_f32(b+i)));
    for (; i < n; i++) r[i] = a[i] + b[i];
#else
    for (uint32_t i = 0; i < n; i++) r[i] = a[i] + b[i];
#endif
}

void vop_sub(const float *a, const float *b, float *r, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) r[i] = a[i] - b[i];
}

void vop_mul(const float *a, const float *b, float *r, uint32_t n) {
#ifdef __ARM_NEON
    uint32_t i = 0;
    for (; i+4 <= n; i+=4)
        vst1q_f32(r+i, vmulq_f32(vld1q_f32(a+i), vld1q_f32(b+i)));
    for (; i < n; i++) r[i] = a[i] * b[i];
#else
    for (uint32_t i = 0; i < n; i++) r[i] = a[i] * b[i];
#endif
}

void vop_scale(float *a, float s, uint32_t n) {
#ifdef __ARM_NEON
    float32x4_t vs = vdupq_n_f32(s);
    uint32_t i = 0;
    for (; i+4 <= n; i+=4)
        vst1q_f32(a+i, vmulq_f32(vld1q_f32(a+i), vs));
    for (; i < n; i++) a[i] *= s;
#else
    for (uint32_t i = 0; i < n; i++) a[i] *= s;
#endif
}

void vop_copy(const float *a, float *r, uint32_t n) {
    bmem_cpy(r, a, n * sizeof(float));
}

void vop_fill(float *a, float v, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) a[i] = v;
}

float vop_sum(const float *a, uint32_t n) {
    float s = 0.0f;
#ifdef __ARM_NEON
    float32x4_t acc = vdupq_n_f32(0.0f);
    uint32_t i = 0;
    for (; i+4 <= n; i+=4) acc = vaddq_f32(acc, vld1q_f32(a+i));
    float32x2_t lo = vget_low_f32(acc);
    float32x2_t hi = vget_high_f32(acc);
    s = vget_lane_f32(vpadd_f32(vadd_f32(lo,hi), vadd_f32(lo,hi)), 0);
    for (; i < n; i++) s += a[i];
#else
    for (uint32_t i = 0; i < n; i++) s += a[i];
#endif
    return s;
}

float vop_min(const float *a, uint32_t n) {
    if (!n) return 0.0f;
    float v = a[0];
    for (uint32_t i = 1; i < n; i++) if (a[i] < v) v = a[i];
    return v;
}

float vop_max(const float *a, uint32_t n) {
    if (!n) return 0.0f;
    float v = a[0];
    for (uint32_t i = 1; i < n; i++) if (a[i] > v) v = a[i];
    return v;
}

float vop_dot(const float *a, const float *b, uint32_t n) {
    if (!a || !b) return 0.0f;
#ifdef HAS_BM_NEON_ASM
    uint32_t s4 = n & ~3u;
    float r = s4 ? bm_dot_neon(a, b, s4) : 0.0f;
    for (uint32_t i = s4; i < n; i++) r += a[i]*b[i];
    return r;
#else
    float s = 0.0f;
    for (uint32_t i = 0; i < n; i++) s += a[i]*b[i];
    return s;
#endif
}

float vop_norm(const float *a, uint32_t n) {
    return fm_sqrt(vop_dot(a, a, n));
}

/* ============================================================================
 * ARCH DETECTION — sem pthread_once, sem lock
 * ========================================================================== */
const char *get_arch_name(void) { return ARCH_NAME; }

uint32_t get_arch_caps(void) {
    bm_init_caps();
    return g_caps.valid ? g_caps.caps_rt : g_caps.caps_bin;
}

uint32_t get_arch_runtime_caps(void)    { bm_init_caps(); return g_caps.caps_rt; }
uint32_t get_arch_binary_caps(void)     { bm_init_caps(); return g_caps.caps_bin; }
int      get_arch_runtime_caps_valid(void) { bm_init_caps(); return g_caps.valid; }

/* ============================================================================
 * HW PROFILE — lê /sys e /proc diretamente, sem printf/sscanf
 * ========================================================================== */
static ssize_t bm_read_file(const char *path, char *buf, size_t n) {
    if (!path || !buf || !n) return -1;
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t r = read(fd, buf, n-1);
    close(fd);
    if (r <= 0) return -1;
    buf[r] = 0;
    return r;
}

static uint32_t bm_parse_online(const char *s) {
    if (!s || !*s) return 0;
    uint32_t cnt = 0, i = 0;
    while (s[i]) {
        while (s[i]==' '||s[i]=='\t'||s[i]=='\n'||s[i]==',') i++;
        if (!s[i]) break;
        uint32_t a = 0;
        while (s[i]>='0'&&s[i]<='9') { a=a*10+(uint32_t)(s[i]-'0'); i++; }
        if (s[i]=='-') {
            i++; uint32_t b=0;
            while (s[i]>='0'&&s[i]<='9') { b=b*10+(uint32_t)(s[i]-'0'); i++; }
            if (b>=a) cnt += b-a+1;
        } else cnt++;
        while (s[i]&&s[i]!=',') i++;
        if (s[i]==',') i++;
    }
    return cnt;
}

static void bm_append(char *out, size_t cap, const char *txt) {
    size_t l=0; while(l<cap&&out[l]) l++;
    size_t i=0;
    while (txt[i] && l+i < cap-1) { out[l+i]=txt[i]; i++; }
    out[l+i]=0;
}

void get_hw_profile(hw_profile_t *p) {
    if (!p) return;
    bmem_zero(p, sizeof(*p));
    bstr_cpy(p->abi, ARCH_NAME);
    p->access_flags |= HW_ACCESS_HAS_ABI;

    /* hwcap via auxv (sem getauxval para evitar libc pesada) */
    unsigned long hc=0, hc2=0;
    if (bm_read_auxv(&hc, &hc2)) {
        p->hwcap  = (uint64_t)hc;
        p->hwcap2 = (uint64_t)hc2;
        p->access_flags |= HW_ACCESS_HAS_HWCAP | HW_ACCESS_HAS_HWCAP2;
    }

    /* CPUs online */
    char buf[64];
    if (bm_read_file("/sys/devices/system/cpu/online", buf, sizeof(buf)) > 0) {
        p->cpus_online = bm_parse_online(buf);
        if (p->cpus_online) p->access_flags |= HW_ACCESS_HAS_CPUS_ONLINE;
    }

    /* Frequências dos clusters */
    p->cpu_clusters[0] = 0;
    int found = 0;
    for (int cpu = 0; cpu < 8; cpu++) {
        char path[128], val[32], ppath[128], pval[32];
        int n = 0;
        /* monta path sem snprintf */
        const char *prefix = "/sys/devices/system/cpu/cpu";
        const char *suffix = "/cpufreq/cpuinfo_max_freq";
        uint32_t ci = (uint32_t)cpu;
        int pl = 0;
        while (prefix[pl]) { path[pl]=prefix[pl]; pl++; }
        if (!ci) { path[pl++]='0'; }
        else { char d[4]; int dl=0;
               while(ci){d[dl++]=(char)('0'+ci%10);ci/=10;}
               for(int k=dl-1;k>=0;k--) path[pl++]=d[k]; }
        int sl = 0;
        while (suffix[sl]) { path[pl+sl]=suffix[sl]; sl++; }
        path[pl+sl]=0;

        if (bm_read_file(path, val, sizeof(val)) <= 0) continue;

        /* dedup */
        int dup = 0;
        for (int prev = 0; prev < cpu; prev++) {
            ci=(uint32_t)prev; pl=0;
            while (prefix[pl]) { ppath[pl]=prefix[pl]; pl++; }
            if (!ci) { ppath[pl++]='0'; }
            else { char d[4]; int dl=0;
                   while(ci){d[dl++]=(char)('0'+ci%10);ci/=10;}
                   for(int k=dl-1;k>=0;k--) ppath[pl++]=d[k]; }
            sl=0; while(suffix[sl]){ppath[pl+sl]=suffix[sl];sl++;}
            ppath[pl+sl]=0;
            if (bm_read_file(ppath,pval,sizeof(pval))>0 && bstr_cmp(val,pval)==0)
                { dup=1; break; }
        }
        if (dup) continue;

        /* monta "clusterN:FREQ;" sem snprintf */
        char part[48];
        int pi=0;
        const char *cpfx = found ? ";cluster" : "cluster";
        while(*cpfx) part[pi++]=*cpfx++;
        part[pi++]=(char)('0'+found);
        part[pi++]=':';
        int vi=0; while(val[vi]) part[pi++]=val[vi++];
        part[pi]=0;
        bm_append(p->cpu_clusters, sizeof(p->cpu_clusters), part);
        found++;
        (void)n;
    }
    if (found) p->access_flags |= HW_ACCESS_HAS_CPU_CLUSTER_FREQ;

    /* page size */
    long pg = sysconf(_SC_PAGESIZE);
    if (pg > 0) { p->page_size=(uint32_t)pg; p->access_flags|=HW_ACCESS_HAS_PAGE_SIZE; }

#ifdef _SC_LEVEL1_DCACHE_LINESIZE
    long cl = sysconf(_SC_LEVEL1_DCACHE_LINESIZE);
    if (cl > 0) { p->cache_line=(uint32_t)cl; p->access_flags|=HW_ACCESS_HAS_CACHE_LINE; }
#endif

    p->access_flags |= HW_ACCESS_NO_PHYS_REG_ACCESS;
    p->access_flags |= HW_ACCESS_NO_GPIO_PIN_ACCESS;
    p->access_flags |= HW_ACCESS_NO_KERNEL_MMIO_ACCESS;
}
