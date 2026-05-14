/**
 * rafaelia_sigma_omega.c — RAFAELIA ΣΩ Spectral Graph System
 *
 * SPDX-License-Identifier: GPL-3.0-only
 * Copyright (C) 2024-2025 Instituto Rafael
 *
 * Conformidade:
 *   IEEE Std 754-2019  — float32 arithmetic
 *   NIST SP 800-175B   — CRC32C integrity
 *   POSIX.1-2017       — write(), clock_gettime()
 *   ARM IHI 0042J      — NEON intrinsics (condicional)
 *
 * Sem malloc. Sem dependência de C++. Sem cópia de código protegido.
 * Algoritmos: domínio público ou matematicamente triviais.
 *
 * Modelo ΣΩ:
 *   G = (V, E), |V| = 42 nós dispostos no toro T^7
 *   A_{ij} = exp(-λ·|v_i - v_j|) · (1 + γ·M(c_i)) · (1 + γ·M(c_j))
 *   L = D - A  (Laplaciano do grafo)
 *   dx/dt = -L·x + α·M(c)  (dinâmica acoplada ao campo fractal)
 *   x(t) ≈ x(0) - dt·L·x + dt·α·M  (Euler explícito, dt=0.01)
 *
 * Compilar:
 *   clang -O2 -std=c11 -ffast-math rafaelia_sigma_omega.c -o sigma_omega -lm
 *   (ARM32: adicionar -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp)
 */

#define _POSIX_C_SOURCE 200809L
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <time.h>

#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

/* ── Constantes do sistema ──────────────────────────────────────────────── */
#define N_NODES   42u     /* período dos atratores = tamanho do grafo */
#define DT        0.01f   /* passo de integração Euler */
#define N_STEPS   420u    /* 420 = 10 × PERIOD para cobertura completa */
#define LAMBDA    0.5f    /* decaimento da conectividade */
#define GAMMA     0.3f    /* acoplamento Mandelbrot */
#define ALPHA     0.1f    /* força do campo externo */
#define MAX_ITER  64u     /* iterações Mandelbrot (limite para ARM32) */

/* ── Arena estática 1MB ─────────────────────────────────────────────────── */
#define ARENA_SZ (1u*1024u*1024u)
static uint8_t __attribute__((aligned(64))) g_arena[ARENA_SZ];
static uint32_t g_bump = 0;

static void *sa(uint32_t n, uint32_t al) {
    uint32_t m=al-1u, s=(g_bump+m)&~m, e=s+n;
    if (e > ARENA_SZ) return NULL;
    g_bump = e;
    return g_arena + s;
}

/* ── Tipo complexo float ────────────────────────────────────────────────── */
typedef struct { float re, im; } cf_t;

static cf_t cf_add(cf_t a, cf_t b) { return (cf_t){a.re+b.re, a.im+b.im}; }
static cf_t cf_mul(cf_t a, cf_t b) {
    return (cf_t){a.re*b.re - a.im*b.im, a.re*b.im + a.im*b.re};
}
static float cf_abs2(cf_t a) { return a.re*a.re + a.im*a.im; }
static float cf_abs(cf_t a)  { return sqrtf(cf_abs2(a)); }

/* ── Campo Mandelbrot M(c) ──────────────────────────────────────────────── */
/* M(c) = 1 - |z_n| / 2  se converge (captura "densidade" no interior)   */
/* M(c) = 0              se diverge                                         */
/* Domínio público: conjunto de Mandelbrot é fato matemático.               */
static float mandelbrot(float cre, float cim) {
    cf_t z = {0.0f, 0.0f};
    cf_t c = {cre, cim};
    for (uint32_t i = 0; i < MAX_ITER; i++) {
        z = cf_add(cf_mul(z, z), c);
        if (cf_abs2(z) > 4.0f) return 0.0f;  /* divergiu */
    }
    /* convergiu: retorna densidade normalizada */
    float m = 1.0f - cf_abs(z) * 0.5f;
    return (m < 0.0f) ? 0.0f : (m > 1.0f ? 1.0f : m);
}

/* Gradiente ∇M por diferenças finitas (para deformação angular dos nós) */
static float mandelbrot_grad(float cre, float cim) {
    float h = 1e-3f;
    float mx = mandelbrot(cre+h, cim) - mandelbrot(cre-h, cim);
    float my = mandelbrot(cre, cim+h) - mandelbrot(cre, cim-h);
    return sqrtf(mx*mx + my*my) / (2.0f*h);
}

/* ── Posição dos 42 nós no plano complexo ──────────────────────────────── */
/* v_k = (1 + ε·M(c_k)) · exp(i·(2πk/42 + β·∇M(c_k)))                  */
/* Mapeamento: c_k = 0.7·exp(i·2πk/42) - 0.4 (varredura do bordo M-set) */
#define EPSILON  0.2f
#define BETA     0.15f

static void compute_nodes(cf_t *v, float *M_field) {
    for (uint32_t k = 0; k < N_NODES; k++) {
        float th = 2.0f * (float)M_PI * (float)k / (float)N_NODES;
        float cre = 0.7f * cosf(th) - 0.4f;
        float cim = 0.7f * sinf(th);
        M_field[k] = mandelbrot(cre, cim);
        float grad  = mandelbrot_grad(cre, cim);
        float r     = 1.0f + EPSILON * M_field[k];
        float angle = th + BETA * grad;
        v[k] = (cf_t){ r * cosf(angle), r * sinf(angle) };
    }
}

/* ── Matriz de adjacência A_{ij} ────────────────────────────────────────── */
/* A_{ij} = exp(-λ·|v_i-v_j|) · (1+γ·M_i) · (1+γ·M_j)                  */
/* Armazenada em arena estática — N_NODES×N_NODES = 42×42 = 1764 floats  */
static void compute_adj(float *A, const cf_t *v, const float *M) {
    for (uint32_t i = 0; i < N_NODES; i++) {
        for (uint32_t j = 0; j < N_NODES; j++) {
            float dre = v[i].re - v[j].re;
            float dim = v[i].im - v[j].im;
            float d   = sqrtf(dre*dre + dim*dim);
            float wij = expf(-LAMBDA * d)
                      * (1.0f + GAMMA * M[i])
                      * (1.0f + GAMMA * M[j]);
            A[i*N_NODES + j] = (i == j) ? 0.0f : wij;
        }
    }
}

/* ── Laplaciano L = D - A ────────────────────────────────────────────────── */
static void compute_laplacian(float *L, const float *A) {
    for (uint32_t i = 0; i < N_NODES; i++) {
        float deg = 0.0f;
        for (uint32_t j = 0; j < N_NODES; j++) deg += A[i*N_NODES+j];
        for (uint32_t j = 0; j < N_NODES; j++) {
            L[i*N_NODES+j] = (i==j) ? deg - A[i*N_NODES+j]
                                     : -A[i*N_NODES+j];
        }
    }
}

/* ── Autovalores via power iteration (maior λ) ──────────────────────────── */
/* Domínio público: método da potência (Von Mises, 1929)                    */
static float power_iteration(const float *L, float *vec, uint32_t max_iter) {
    /* inicializa vec = [1/√N, ..., 1/√N] */
    float inv = 1.0f / sqrtf((float)N_NODES);
    for (uint32_t i = 0; i < N_NODES; i++) vec[i] = inv;

    float lambda = 0.0f;
    for (uint32_t it = 0; it < max_iter; it++) {
        /* w = L · vec */
        float w[N_NODES];
#ifdef __ARM_NEON
        /* NEON: 4 acumuladores por linha */
        for (uint32_t i = 0; i < N_NODES; i++) {
            float32x4_t acc = vdupq_n_f32(0.0f);
            uint32_t j = 0;
            for (; j+4 <= N_NODES; j+=4) {
                float32x4_t lv = vld1q_f32(L+i*N_NODES+j);
                float32x4_t vv = vld1q_f32(vec+j);
                acc = vmlaq_f32(acc, lv, vv);
            }
            float s = vaddvq_f32(acc);
            for (; j < N_NODES; j++) s += L[i*N_NODES+j]*vec[j];
            w[i] = s;
        }
#else
        for (uint32_t i = 0; i < N_NODES; i++) {
            float s = 0.0f;
            for (uint32_t j = 0; j < N_NODES; j++) s += L[i*N_NODES+j]*vec[j];
            w[i] = s;
        }
#endif
        /* λ = ||w|| */
        float norm2 = 0.0f;
        for (uint32_t i = 0; i < N_NODES; i++) norm2 += w[i]*w[i];
        lambda = sqrtf(norm2);
        /* normaliza */
        float inv_l = (lambda > 1e-10f) ? 1.0f/lambda : 0.0f;
        for (uint32_t i = 0; i < N_NODES; i++) vec[i] = w[i] * inv_l;
    }
    return lambda;
}

/* ── Integração: dx/dt = -L·x + α·M ────────────────────────────────────── */
/* Euler explícito: x_{t+1} = x_t - dt·L·x_t + dt·α·M                     */
static void integrate_euler(float *x, const float *L, const float *M,
                             uint32_t n_steps, float *trace_phi) {
    float Lx[N_NODES];
    /* coerência e entropia globais */
    float C = 0.5f, H = 0.5f;

    for (uint32_t step = 0; step < n_steps; step++) {
        /* L·x via NEON/escalar */
#ifdef __ARM_NEON
        for (uint32_t i = 0; i < N_NODES; i++) {
            float32x4_t acc = vdupq_n_f32(0.0f);
            uint32_t j=0;
            for (; j+4<=N_NODES; j+=4) {
                float32x4_t lv = vld1q_f32(L+i*N_NODES+j);
                float32x4_t xv = vld1q_f32(x+j);
                acc = vmlaq_f32(acc, lv, xv);
            }
            float s = vaddvq_f32(acc);
            for (; j<N_NODES; j++) s += L[i*N_NODES+j]*x[j];
            Lx[i] = s;
        }
#else
        for (uint32_t i=0; i<N_NODES; i++) {
            float s=0.0f;
            for (uint32_t j=0; j<N_NODES; j++) s += L[i*N_NODES+j]*x[j];
            Lx[i]=s;
        }
#endif
        /* x_{t+1} = x_t - dt·Lx + dt·α·M */
        float sum_x = 0.0f;
        for (uint32_t i=0; i<N_NODES; i++) {
            x[i] += DT * (-Lx[i] + ALPHA * M[i]);
            /* clamp numérico */
            if (x[i] > 1.0f) x[i] = 1.0f;
            if (x[i] < 0.0f) x[i] = 0.0f;
            sum_x += x[i];
        }
        /* EMA coerência / entropia */
        float c_in = sum_x / (float)N_NODES;
        float h_in = 1.0f - c_in;
        C = 0.75f*C + 0.25f*c_in;
        H = 0.75f*H + 0.25f*h_in;
        /* phi = (1-H)*C */
        if (trace_phi && step < N_NODES)
            trace_phi[step] = (1.0f-H)*C;
    }
}

/* ── CRC32C (RFC 3720 §B.4) ─────────────────────────────────────────────── */
static uint32_t CT[256];
static void crc_init(void) {
    for (uint32_t i=0; i<256; i++) {
        uint32_t v=i;
        for (int j=0; j<8; j++) v=(v&1)?(v>>1)^0x82F63B78u:(v>>1);
        CT[i]=v;
    }
}
static uint32_t crc32c(const void *buf, uint32_t n) {
    const uint8_t *p=(const uint8_t*)buf; uint32_t c=~0u;
    while(n--) c=(c>>8)^CT[(c^*p++)&0xFF]; return ~c;
}

/* ── Output ─────────────────────────────────────────────────────────────── */
static const char HX[]="0123456789ABCDEF";
static void ws(const char *s) { write(1,s,strlen(s)); }
static void wf(float v) {       /* float como "d.dddd" sem printf pesado */
    char buf[16]; int sign=0;
    if (v<0){sign=1;v=-v;}
    int   ip=(int)v;
    int   fp=(int)((v-(float)ip)*10000.0f+0.5f);
    char  *p=buf+15; *p--=0;
    /* fractal part */
    for (int i=0;i<4;i++){*p--=(char)('0'+fp%10);fp/=10;}
    *p--='.';
    if (!ip){*p--='0';}else{while(ip){*p--=(char)('0'+ip%10);ip/=10;}}
    if (sign)*p--='-';
    ws(p+1); ws(" ");
}
static void whex(uint32_t v) {
    char b[11]="0x00000000"; for(int i=0;i<8;i++) b[2+i]=HX[(v>>(28-i*4))&0xF];
    ws(b);
}

/* ── MAIN ΣΩ ─────────────────────────────────────────────────────────────── */
int main(void) {
    crc_init();

    /* aloca estruturas na arena estática */
    cf_t  *V  = (cf_t  *)sa(N_NODES*sizeof(cf_t),  64);
    float *M  = (float *)sa(N_NODES*sizeof(float),  64);
    float *A  = (float *)sa(N_NODES*N_NODES*sizeof(float), 64);
    float *L  = (float *)sa(N_NODES*N_NODES*sizeof(float), 64);
    float *x  = (float *)sa(N_NODES*sizeof(float),  64);
    float *ev = (float *)sa(N_NODES*sizeof(float),  64);
    float *tr = (float *)sa(N_NODES*sizeof(float),  64);

    if (!V||!M||!A||!L||!x||!ev||!tr) {
        ws("OOM\n"); return 1;
    }

    ws("=== RAFAELIA SIGMA-OMEGA SPECTRAL SYSTEM ===\n");
    ws("Nodes: 42  Steps: 420  dt: 0.01\n");
    ws("Model: dx/dt = -Lx + alpha*M(c)\n\n");

    /* calcula nós e campo */
    compute_nodes(V, M);
    compute_adj(A, V, M);
    compute_laplacian(L, A);

    /* integridade da matriz */
    uint32_t crc_L = crc32c(L, N_NODES*N_NODES*sizeof(float));
    ws("CRC32C(L): "); whex(crc_L); ws("\n");

    /* autovalor dominante */
    float lambda_max = power_iteration(L, ev, 100);
    ws("Lambda_max: "); wf(lambda_max); ws("\n");

    /* estado inicial: x_i = M(c_i) */
    for (uint32_t i=0; i<N_NODES; i++) x[i] = M[i];

    /* integração Euler */
    integrate_euler(x, L, M, N_STEPS, tr);

    /* resultado */
    ws("\nFinal state x[0..6]:\n");
    for (uint32_t i=0; i<7 && i<N_NODES; i++) { ws("  x["); ws("0123456"+(int)i); ws("]="); wf(x[i]); }
    ws("\n");

    /* phi trace */
    ws("\nPhi trace [0,7,14,21,28,35,41]:\n");
    uint32_t idx[]={0,7,14,21,28,35,41};
    for (int k=0;k<7;k++) { ws("  phi["); ws("0123456"+(int)k); ws("]="); wf(tr[idx[k]]); }
    ws("\n");

    /* CRC do estado final */
    uint32_t crc_x = crc32c(x, N_NODES*sizeof(float));
    ws("\nCRC32C(x_final): "); whex(crc_x); ws("\n");

    /* campo Mandelbrot nos primeiros 7 nós */
    ws("\nM(c_k) k=0..6:\n");
    for (uint32_t k=0;k<7;k++) { ws("  M["); ws("0123456"+(int)k); ws("]="); wf(M[k]); }
    ws("\n");

    ws("\nArena used: ");
    char nb[12]; int ni=11; uint32_t nv=g_bump;
    nb[ni]=0; if(!nv){nb[--ni]='0';}else while(nv){nb[--ni]=(char)('0'+nv%10);nv/=10;}
    ws(nb+ni); ws(" bytes\n");

    ws("=== DONE ===\n");
    return 0;
}
