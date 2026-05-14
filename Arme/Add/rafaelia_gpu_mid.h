/**
 * rafaelia_gpu_mid.h — GPU Middleware via dlopen
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * Conformidade:
 *   Khronos OpenCL 3.0 Specification (opencl-3.0.pdf)
 *   Vulkan 1.3 Specification §7 (compute pipelines)
 *   LGPL dlopen exception: usar dlopen para libs LGPL é permitido
 *   sem violar a GPL da aplicação (FSF opinion 2003).
 *
 * NÃO faz linkagem estática a nenhuma lib proprietária.
 * NÃO inclui headers proprietários em tempo de compilação.
 * Todas as assinaturas de função derivam das especificações públicas Khronos.
 */
#pragma once
#ifndef RAFAELIA_GPU_MID_H
#define RAFAELIA_GPU_MID_H

#include <stdint.h>
#include <stddef.h>

/* ── API pública do middleware ──────────────────────────────────────────── */
typedef enum {
    GPU_NONE   = 0,  /* sem GPU — usa CPU NEON */
    GPU_OPENCL = 1,  /* Khronos OpenCL 3.0 */
    GPU_VULKAN = 2,  /* Vulkan 1.3 compute */
} gpu_api_t;

typedef struct {
    gpu_api_t  api;
    void      *lib;          /* handle dlopen */
    char       path[128];    /* path da lib carregada */
    int        available;    /* 1 se pronto */
    uint32_t   max_work_grp; /* CL_DEVICE_MAX_WORK_GROUP_SIZE */
    uint32_t   version;      /* OpenCL version × 100 (300=3.0) */
} gpu_ctx_t;

/* Inicializa: tenta OpenCL, depois Vulkan, fallback CPU */
int  gpu_init(gpu_ctx_t *ctx);

/* Executa kernel EMA Q16.16 no device disponível */
/* src/dst: arrays de uint32_t (Q16.16), n elementos */
int  gpu_ema_step(gpu_ctx_t *ctx,
                  uint32_t *dst, const uint32_t *src,
                  uint32_t n, uint32_t alpha_q16);

/* Libera handles */
void gpu_free(gpu_ctx_t *ctx);

/* Retorna string descritiva do backend */
const char *gpu_api_name(gpu_api_t api);

#endif /* RAFAELIA_GPU_MID_H */
