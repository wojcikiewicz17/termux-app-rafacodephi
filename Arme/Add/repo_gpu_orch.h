#ifndef RAFAELIA_GPU_ORCHESTRATOR_H
#define RAFAELIA_GPU_ORCHESTRATOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RGO_OK 0
#define RGO_ERR_ARGS -1
#define RGO_ERR_DLOPEN -2
#define RGO_ERR_DLSYM -3
#define RGO_ERR_GPU_RUNTIME -4
#define RGO_ERR_QUEUE_FULL -5
#define RGO_ERR_QUEUE_EMPTY -6

#define MAX_CORES 16u
#define WSQ_SIZE 64u

#define RGO_CAP_OPENCL (1u << 8)
#define RGO_CAP_VULKAN (1u << 9)

typedef enum {
    GPU_UNKNOWN = 0,
    GPU_PRESENT,
    GPU_NO_DRIVER,
    GPU_FAIL_RUNTIME
} rgpu_state_t;

typedef struct {
    uint32_t id;
    uint32_t task_hz_q16;
    uint32_t intensity;
    uint64_t deadline_ns;
    uint64_t submit_time_ns;
    uint32_t priority;
    uint8_t gpu_candidate;
} rtask_t;

int rgpu_probe_opencl(void);
int rgpu_probe_vulkan(void);
rgpu_state_t rgpu_get_state(void);
uint32_t rgpu_get_core_count(void);
void rcpu_map_toroidal(uint32_t* zones, uint32_t n);
uint32_t rcrc32_sw(const uint8_t* data, uint32_t len);
uint32_t rscheduler_pick_core(uint32_t task_hz_q16, uint32_t intensity);
void rscheduler_set_load(uint32_t core_idx, uint32_t load_q16);
void rscheduler_reset(void);
uint32_t rgpu_runtime_caps(void);

void remk_set_thermal(uint32_t thermal_0_100);
uint32_t remk_get_thermal(void);
int remk_enqueue_task(const rtask_t* task);
int remk_dequeue_task(rtask_t* task);
int remk_run_once(uint32_t* selected_core, uint32_t* used_gpu);

#ifdef __cplusplus
}
#endif

#endif
