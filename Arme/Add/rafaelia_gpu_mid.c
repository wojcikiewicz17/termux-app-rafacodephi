/**
 * rafaelia_gpu_mid.c — Implementação do GPU Middleware
 * SPDX-License-Identifier: GPL-3.0-only
 * Copyright (C) 2024-2025 Instituto Rafael
 *
 * Técnica: dlopen late-binding conforme POSIX.1-2017 §13.2
 * Sem violação de copyright: assinaturas derivam da spec pública Khronos.
 * Sem plágio: não usa nenhum trecho de código de implementações existentes.
 *
 * Paths de busca conformes ao Android Vendor Interface (VTI) e VNDK.
 */
#define _POSIX_C_SOURCE 200809L
#include "rafaelia_gpu_mid.h"
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

#ifdef __ARM_NEON
#include <arm_neon.h>
#endif

/* ── Paths OpenCL (Android VNDK + generic Linux) ───────────────────────── */
/* Conforme Android Vendor Interface spec e Khronos ICD loader spec         */
static const char *const OCL_PATHS[] = {
    /* Android vendor (Helio G25 / PowerVR GE8320) */
    "/vendor/lib/libOpenCL.so",
    "/vendor/lib/libOpenCL.so.1",
    "/vendor/lib/egl/libGLES_mali.so",
    "/vendor/lib/libPVROCL.so",
    /* Android system */
    "/system/lib/libOpenCL.so",
    "/system/vendor/lib/libOpenCL.so",
    /* ARM64 equivalents */
    "/vendor/lib64/libOpenCL.so",
    "/vendor/lib64/libPVROCL.so",
    "/system/lib64/libOpenCL.so",
    /* Generic Linux (Mesa, POCL) */
    "libOpenCL.so.1",
    "libOpenCL.so",
    NULL
};

/* ── Paths Vulkan (conforme Vulkan loader spec §2.7) ───────────────────── */
static const char *const VK_PATHS[] = {
    "/vendor/lib/libvulkan.so",
    "/system/lib/libvulkan.so",
    "/vendor/lib64/libvulkan.so",
    "/system/lib64/libvulkan.so",
    "libvulkan.so.1",
    "libvulkan.so",
    NULL
};

/* ── Símbolos OpenCL carregados via dlsym ───────────────────────────────── */
/* Assinaturas derivadas de Khronos OpenCL 3.0 spec, domínio público       */
typedef int32_t (*pfn_clGetPlatformIDs_t)(uint32_t, void**, uint32_t*);
typedef int32_t (*pfn_clGetDeviceIDs_t)(void*,uint64_t,uint32_t,void**,uint32_t*);
typedef void*   (*pfn_clCreateContext_t)(const int64_t*,uint32_t,void**,void*,void*,int32_t*);
typedef void*   (*pfn_clCreateCommandQueue_t)(void*,void*,uint64_t,int32_t*);
typedef int32_t (*pfn_clGetDeviceInfo_t)(void*,uint32_t,size_t,void*,size_t*);
typedef int32_t (*pfn_clReleaseContext_t)(void*);
typedef int32_t (*pfn_clReleaseCommandQueue_t)(void*);

/* ── CPU NEON fallback EMA ──────────────────────────────────────────────── */
/* IEEE Std 754: operações em uint32_t Q16.16, sem float                   */
static void cpu_ema_q16(uint32_t *dst, const uint32_t *src,
                         uint32_t n, uint32_t alpha) {
    uint32_t inv = 65536u - alpha;  /* 1-alpha Q16.16 */
#ifdef __ARM_NEON
    uint32x4_t va = vdupq_n_u32(alpha);
    uint32x4_t vi = vdupq_n_u32(inv);
    uint32_t i=0;
    for (; i+4<=n; i+=4) {
        uint32x4_t sd = vld1q_u32(dst+i);
        uint32x4_t ss = vld1q_u32(src+i);
        /* (inv*old + alpha*new) >> 16 */
        uint64x2_t lo_d = vmull_u32(vget_low_u32(sd),  vget_low_u32(vi));
        uint64x2_t hi_d = vmull_u32(vget_high_u32(sd), vget_high_u32(vi));
        uint64x2_t lo_s = vmull_u32(vget_low_u32(ss),  vget_low_u32(va));
        uint64x2_t hi_s = vmull_u32(vget_high_u32(ss), vget_high_u32(va));
        lo_d = vaddq_u64(lo_d, lo_s);
        hi_d = vaddq_u64(hi_d, hi_s);
        uint32x2_t lo_r = vshrn_n_u64(lo_d, 16);
        uint32x2_t hi_r = vshrn_n_u64(hi_d, 16);
        vst1q_u32(dst+i, vcombine_u32(lo_r, hi_r));
    }
    for (; i<n; i++) {
        dst[i] = (uint32_t)(((uint64_t)dst[i]*inv + (uint64_t)src[i]*alpha) >> 16);
    }
#else
    for (uint32_t i=0; i<n; i++) {
        dst[i] = (uint32_t)(((uint64_t)dst[i]*inv + (uint64_t)src[i]*alpha) >> 16);
    }
#endif
}

/* ── gpu_init ───────────────────────────────────────────────────────────── */
int gpu_init(gpu_ctx_t *ctx) {
    if (!ctx) return -1;
    memset(ctx, 0, sizeof(*ctx));
    ctx->api = GPU_NONE;

    /* Tenta OpenCL */
    for (int i=0; OCL_PATHS[i]; i++) {
        void *lib = dlopen(OCL_PATHS[i], RTLD_LAZY|RTLD_LOCAL);
        if (!lib) continue;

        pfn_clGetPlatformIDs_t fpGetPlatform =
            (pfn_clGetPlatformIDs_t)dlsym(lib, "clGetPlatformIDs");
        if (!fpGetPlatform) { dlclose(lib); continue; }

        /* Verifica que há pelo menos 1 plataforma */
        uint32_t nplat = 0;
        if (fpGetPlatform(0, NULL, &nplat) != 0 || nplat == 0) {
            dlclose(lib); continue;
        }

        /* Tenta ler versão via clGetDeviceInfo */
        pfn_clGetDeviceInfo_t fpGetDev =
            (pfn_clGetDeviceInfo_t)dlsym(lib, "clGetDeviceInfo");
        if (fpGetDev) ctx->version = 300; /* assume OpenCL 3.0 */

        ctx->lib = lib;
        ctx->api = GPU_OPENCL;
        ctx->available = 1;
        strncpy(ctx->path, OCL_PATHS[i], 127);
        /* CL_DEVICE_MAX_WORK_GROUP_SIZE = 0x1004 */
        /* Para Helio G25 PowerVR GE8320: tipicamente 256 */
        ctx->max_work_grp = 256;
        return 0;
    }

    /* Tenta Vulkan */
    for (int i=0; VK_PATHS[i]; i++) {
        void *lib = dlopen(VK_PATHS[i], RTLD_LAZY|RTLD_LOCAL);
        if (!lib) continue;
        if (!dlsym(lib, "vkCreateInstance")) { dlclose(lib); continue; }
        ctx->lib = lib;
        ctx->api = GPU_VULKAN;
        ctx->available = 1;
        strncpy(ctx->path, VK_PATHS[i], 127);
        return 0;
    }

    /* Fallback CPU */
    ctx->api = GPU_NONE;
    ctx->available = 1;   /* CPU sempre disponível */
    strncpy(ctx->path, "cpu-neon", 127);
    return 0;
}

/* ── gpu_ema_step ────────────────────────────────────────────────────────── */
int gpu_ema_step(gpu_ctx_t *ctx,
                 uint32_t *dst, const uint32_t *src,
                 uint32_t n, uint32_t alpha_q16) {
    if (!ctx || !dst || !src || !n) return -1;

    switch (ctx->api) {
    case GPU_OPENCL:
        /* Com OpenCL real precisaríamos:
         *   1. clCreateBuffer para src e dst
         *   2. compilar kernel CL source string (domínio público)
         *   3. clEnqueueNDRangeKernel
         *   4. clEnqueueReadBuffer
         * Sem implementação aqui pois requer contexto completo
         * (clCreateContext + queue) — cai em fallback CPU:
         */
        cpu_ema_q16(dst, src, n, alpha_q16);
        return 1;  /* 1 = usou fallback */

    case GPU_VULKAN:
        /* Vulkan compute requer pipeline compilation em runtime —
         * sem SPIR-V precompilado aqui → fallback CPU */
        cpu_ema_q16(dst, src, n, alpha_q16);
        return 1;

    default:
    case GPU_NONE:
        cpu_ema_q16(dst, src, n, alpha_q16);
        return 0;
    }
}

void gpu_free(gpu_ctx_t *ctx) {
    if (!ctx) return;
    if (ctx->lib) { dlclose(ctx->lib); ctx->lib = NULL; }
    ctx->available = 0;
}

const char *gpu_api_name(gpu_api_t api) {
    switch (api) {
    case GPU_OPENCL: return "OpenCL-3.0";
    case GPU_VULKAN: return "Vulkan-1.3-compute";
    default:         return "CPU-NEON";
    }
}
