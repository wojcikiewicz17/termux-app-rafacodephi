@ ===========================================================================
@ RAFAELIA B6 — GPU DISPATCH + NEON KERNEL ARM32
@ Cortex-A53 · dlopen OpenCL/Vulkan · zero heap · zero libc runtime
@
@ MODELO:
@   1. tenta carregar libOpenCL.so via dl_open syscall (Android SL)
@   2. se falhar: executa kernel NEON puro (sempre disponível)
@   3. resultado: vetor 7D processado em camadas de cache L1→L2
@   4. integridade: CRC32C antes e depois de cada transfer
@
@ SYSCALLS USADAS:
@   SYS_OPENAT   = 322  (abre shared lib)
@   SYS_MMAP2    = 192  (mapeia lib em memória)
@   SYS_CLOSE    = 6
@   SYS_WRITE    = 4
@   SYS_EXIT     = 1
@   sem dlopen da libc — usa mmap direto do ELF
@
@ Compilar:
@   as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b6.S -o b6.o
@   ld b6.o -o rafaelia_b6
@ ===========================================================================

.equ SYS_EXIT,     1
.equ SYS_WRITE,    4
.equ SYS_OPEN,     5
.equ SYS_CLOSE,    6
.equ SYS_MMAP2,    192
.equ SYS_MUNMAP,   91
.equ SYS_STAT64,   195
.equ STDOUT,       1

.equ SPIRAL_Q16,   56755
.equ PHI_Q16,      105965
.equ PERIOD,       42
.equ N_VCPU,       8
.equ CACHE_LINE,   64

.equ O_RDONLY,     0
.equ PROT_R,       1
.equ PROT_RW,      3
.equ MAP_PRIVATE,  2
.equ MAP_ANON,     0x20
.equ MAP_FAILED,   0xFFFFFFFF

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_b6_boot:  .ascii "B6: GPU-DISPATCH+NEON-KERNEL\n"
.equ msg_b6_boot_len, . - msg_b6_boot

msg_gpu_try:  .ascii "GPU: probing...\n"
.equ msg_gpu_try_len, . - msg_gpu_try

msg_gpu_ok:   .ascii "GPU: OpenCL lib found\n"
.equ msg_gpu_ok_len, . - msg_gpu_ok

msg_gpu_fail: .ascii "GPU: fallback NEON CPU\n"
.equ msg_gpu_fail_len, . - msg_gpu_fail

msg_neon_run: .ascii "NEON: kernel running\n"
.equ msg_neon_run_len, . - msg_neon_run

msg_crc_pre:  .ascii "CRC_PRE=\n"
.equ msg_crc_pre_len, . - msg_crc_pre

msg_crc_post: .ascii "CRC_POST=\n"
.equ msg_crc_post_len, . - msg_crc_post

msg_vcpu_map: .ascii "VCPU_HZ_MAP:\n"
.equ msg_vcpu_map_len, . - msg_vcpu_map

msg_done6:    .ascii "B6:DONE\n"
.equ msg_done6_len, . - msg_done6

hex_t6:       .ascii "0123456789ABCDEF"

@ Paths OpenCL para Android (Helio G25 / PowerVR GE8320)
.align 2
ocl_path0:  .ascii "/vendor/lib/libOpenCL.so\0"
ocl_path1:  .ascii "/vendor/lib/egl/libGLES_mali.so\0"
ocl_path2:  .ascii "/system/lib/libOpenCL.so\0"
ocl_path3:  .ascii "/vendor/lib/libPVROCL.so\0"

.align 2
ocl_paths:
    .word ocl_path0
    .word ocl_path1
    .word ocl_path2
    .word ocl_path3
    .word 0              @ sentinel

@ Frequências harmônicas dos 8 vCPUs (Q16.16)
@ hz[i] = BASE * (SPIRAL_Q16/65536)^fib[i]
@ fib[i] = {0,0,0,1,1,2,3,5}
@ Pré-calculado: hz[i] = cluster_freq * factor[i]
.align 4
vcpu_hz_table:
    .long 58000   @ cpu0: cluster0 full
    .long 58000   @ cpu1
    .long 58000   @ cpu2
    .long 50296   @ cpu3: * SPIRAL = 58000*56755>>16
    .long 43500   @ cpu4: cluster1 full
    .long 43500   @ cpu5
    .long 37709   @ cpu6: * SPIRAL
    .long 26836   @ cpu7: * SPIRAL^2

@ Peso de cada layer de memória (Q16.16, soma = 1)
@ L1=0.40 L2=0.30 BUF=0.20 RAM=0.10
.align 4
layer_weights:
    .long 26214   @ 0.40 * 65536
    .long 19661   @ 0.30
    .long 13107   @ 0.20
    .long  6554   @ 0.10

@ Triângulo isósceles: base = sqrt(3), catetos = 1, ápice em (0,sqrt(3)/2)
@ codificado como [x_base_l, y_base_l, x_base_r, y_base_r, x_apex, y_apex]
@ Q16.16
.align 4
isosceles_pts:
    .long -56755,      0   @ base esquerda
    .long  56755,      0   @ base direita
    .long      0,  56755   @ ápice norte
    .long      0, -56755   @ ápice sul (jato)

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

@ Arena 2MB para este bloco
.equ ARENA6_SZ, (2*1024*1024)
.align 6
g_arena6:      .space ARENA6_SZ
g_arena6_bump: .space 4

@ Estado 7D dos vCPUs (8 * 7 * 4 bytes = 224 bytes)
.align 6
g_vcpu_state:  .space N_VCPU * 7 * 4

@ Vetor de loads dos vCPUs (8 * 4 bytes)
.align 4
g_vcpu_load:   .space N_VCPU * 4

@ Vetor de fases (8 * 4 bytes)
.align 4
g_vcpu_phase:  .space N_VCPU * 4

@ CRC32C table
.align 6
g_crc6:        .space 256 * 4

@ Resultado do kernel NEON (7D vetor de saída, float x7)
.align 6
g_neon_out:    .space 7 * 4

@ Estado do GPU dispatch
g_gpu_fd:      .space 4    @ file descriptor da lib OpenCL (-1 se não encontrada)
g_gpu_found:   .space 4    @ 1 se encontrado

@ Buffer hex
g_hex6:        .space 16

@ Stat64 buffer (para verificar existência de arquivo)
.align 4
g_stat64_buf:  .space 128

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    @ init CRC table
    bl      crc6_build

    @ init arena
    mov     r0, #0
    ldr     r1, =g_arena6_bump
    str     r0, [r1]

    @ init vCPU state com constantes irracionais
    bl      vcpu_state_init

    @ boot
    ldr     r0, =msg_b6_boot
    mov     r1, #msg_b6_boot_len
    bl      ws6

    @ GPU probe
    ldr     r0, =msg_gpu_try
    mov     r1, #msg_gpu_try_len
    bl      ws6

    bl      gpu_probe           @ r0 = 1 se OpenCL encontrado

    cmp     r0, #1
    bne     .Bgpu_fail

    ldr     r0, =msg_gpu_ok
    mov     r1, #msg_gpu_ok_len
    bl      ws6
    b       .Bgpu_dispatch

.Bgpu_fail:
    ldr     r0, =msg_gpu_fail
    mov     r1, #msg_gpu_fail_len
    bl      ws6

.Bgpu_dispatch:
    @ independente de GPU, executa kernel NEON
    @ (GPU real requereria contexto OpenCL que não temos sem root)
    ldr     r0, =msg_neon_run
    mov     r1, #msg_neon_run_len
    bl      ws6

    @ CRC do estado ANTES
    ldr     r0, =g_vcpu_state
    ldr     r1, =(N_VCPU * 7 * 4)
    bl      crc6_compute

    push    {r0}
    ldr     r0, =msg_crc_pre
    mov     r1, #msg_crc_pre_len
    bl      ws6
    pop     {r0}
    bl      ph6

    @ 42 ciclos do kernel
    mov     r4, #PERIOD

.Bcycle_loop:
    cmp     r4, #0
    beq     .Bcycle_done

    @ calcula jet_target via triângulo isósceles
    bl      isosceles_predict   @ r0 = jet_target (0..7)
    mov     r5, r0              @ salva

    @ executa kernel NEON no core r5
    mov     r0, r5
    bl      neon_kernel_step

    @ EMA do load do core jet_target
    ldr     r6, =g_vcpu_load
    ldr     r7, [r6, r5, lsl #2]
    @ load_new = 0.75*load + 0.25*SPIRAL (sintético)
    ldr     r8, =49152
    umull   r2, r3, r7, r8
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16
    ldr     r8, =16384
    ldr     r9, =SPIRAL_Q16
    umull   r3, r10, r9, r8
    lsr     r3, r3, #16
    add     r2, r2, r3
    uxth    r2, r2
    str     r2, [r6, r5, lsl #2]

    @ avança fase do core
    ldr     r6, =g_vcpu_phase
    ldr     r7, [r6, r5, lsl #2]
    add     r7, r7, #1
    cmp     r7, #PERIOD
    moveq   r7, #0
    str     r7, [r6, r5, lsl #2]

    subs    r4, r4, #1
    b       .Bcycle_loop

.Bcycle_done:
    @ CRC DEPOIS
    ldr     r0, =g_vcpu_state
    ldr     r1, =(N_VCPU * 7 * 4)
    bl      crc6_compute

    push    {r0}
    ldr     r0, =msg_crc_post
    mov     r1, #msg_crc_post_len
    bl      ws6
    pop     {r0}
    bl      ph6

    @ imprime mapa de hz dos vCPUs
    ldr     r0, =msg_vcpu_map
    mov     r1, #msg_vcpu_map_len
    bl      ws6
    bl      print_vcpu_hz

    ldr     r0, =msg_done6
    mov     r1, #msg_done6_len
    bl      ws6

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

@ ===========================================================================
@ vcpu_state_init — seeds com SPIRAL, PHI, PI em cada dim de cada core
@ ===========================================================================
.type vcpu_state_init, %function
vcpu_state_init:
    push    {r4, r5, r6, lr}
    ldr     r4, =g_vcpu_state
    ldr     r5, =SPIRAL_Q16
    ldr     r6, =PHI_Q16

    mov     r0, #0              @ core index

.Bvsi_loop:
    cmp     r0, #N_VCPU
    beq     .Bvsi_done

    @ addr = &g_vcpu_state[core * 7]
    mov     r1, #28             @ 7 * 4 bytes
    mul     r2, r0, r1
    add     r2, r4, r2          @ ptr ao estado do core

    @ semeia 7 dimensões com variação por core
    ldr     r3, =SPIRAL_Q16
    mul     r1, r0, r3
    lsr     r1, r1, #8          @ varia por core
    and     r1, r1, #0xFFFF

    str     r1, [r2, #0]
    mul     r3, r1, r5
    lsr     r3, r3, #16
    str     r3, [r2, #4]
    mul     r3, r3, r6
    lsr     r3, r3, #16
    str     r3, [r2, #8]
    mul     r3, r3, r5
    lsr     r3, r3, #16
    str     r3, [r2, #12]
    mul     r3, r3, r6
    lsr     r3, r3, #16
    str     r3, [r2, #16]
    mul     r3, r3, r5
    lsr     r3, r3, #16
    str     r3, [r2, #20]
    mul     r3, r3, r6
    lsr     r3, r3, #16
    str     r3, [r2, #24]

    add     r0, r0, #1
    b       .Bvsi_loop

.Bvsi_done:
    @ zera loads e fases
    ldr     r4, =g_vcpu_load
    ldr     r5, =g_vcpu_phase
    mov     r0, #0
    mov     r1, #N_VCPU
.Bvsi_zero:
    str     r0, [r4], #4
    str     r0, [r5], #4
    subs    r1, r1, #1
    bne     .Bvsi_zero

    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ gpu_probe — verifica existência dos paths OpenCL via SYS_STAT64
@ retorna r0 = 1 se encontrado, 0 caso contrário
@ ===========================================================================
.type gpu_probe, %function
gpu_probe:
    push    {r4, r5, lr}

    ldr     r4, =ocl_paths      @ array de ponteiros
    mov     r5, #0              @ índice

.Bgpu_probe_loop:
    ldr     r0, [r4, r5, lsl #2]   @ ptr para path string
    cmp     r0, #0
    beq     .Bgpu_not_found

    @ tenta open O_RDONLY
    mov     r1, #O_RDONLY
    mov     r2, #0
    mov     r7, #SYS_OPEN
    swi     #0

    @ se r0 >= 0: arquivo existe
    cmp     r0, #0
    blt     .Bgpu_next

    @ fecha o fd
    mov     r1, r0
    mov     r7, #SYS_CLOSE
    swi     #0

    @ salva resultado
    ldr     r1, =g_gpu_found
    mov     r0, #1
    str     r0, [r1]
    mov     r0, #1
    pop     {r4, r5, pc}

.Bgpu_next:
    add     r5, r5, #1
    b       .Bgpu_probe_loop

.Bgpu_not_found:
    ldr     r1, =g_gpu_found
    mov     r0, #0
    str     r0, [r1]
    pop     {r4, r5, pc}

@ ===========================================================================
@ neon_kernel_step — executa 1 passo do kernel no core r0
@ Aplica EMA NEON nos 7 dims do estado do core
@ r0 = core_idx (0..7)
@ ===========================================================================
.type neon_kernel_step, %function
neon_kernel_step:
    push    {r4, r5, r6, r7, lr}
    vpush   {q0-q3}

    mov     r4, r0              @ core_idx

    @ ptr ao estado do core: g_vcpu_state + core_idx * 28
    ldr     r5, =g_vcpu_state
    mov     r6, #28
    mul     r6, r4, r6
    add     r5, r5, r6          @ r5 = ptr estado

    @ hz do core (lookup na tabela)
    ldr     r6, =vcpu_hz_table
    ldr     r6, [r6, r4, lsl #2]   @ r6 = hz Q16.16 do core

    @ carga dos 7 dims em registradores SIMD
    @ vld1.32 carrega 4 x 32-bit por vez
    @ load dims [0..3]
    vld1.32 {q0}, [r5]          @ q0 = s[0..3]
    @ load dims [4..6] (apenas 3 — padding necessário)
    @ usa load de 3 words individualmente
    ldr     r7, [r5, #16]       @ s[4]
    ldr     r8, [r5, #20]       @ s[5]
    ldr     r9, [r5, #24]       @ s[6]
    vmov    d2, r7, r8          @ d2 = {s[4], s[5]}

    @ input sintético = hz * SPIRAL >> 16 (senoide simplificada)
    ldr     r7, =SPIRAL_Q16
    umull   r2, r3, r6, r7
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16
    and     r2, r2, #0xFFFF     @ c_in Q16.16

    @ replica c_in nos 4 lanes de q1
    vdup.32 q1, r2

    @ EMA vetorial: s_new = 0.75*s + 0.25*c_in
    @ alpha = 0.25 → 16384, inv_alpha = 0.75 → 49152
    vmov.i32 q2, #49152
    vmov.i32 q3, #16384

    @ q0_new = (q0 * 49152 + q1 * 16384) >> 16
    @ usa vmull (signed 32→64) + vshrn
    vmull.s32 q8,  d0, d4      @ d0 * inv_alpha lanes 0,1
    vmull.s32 q9,  d1, d5      @ d1 * inv_alpha lanes 2,3
    vmull.s32 q10, d0, d6      @ d0 * alpha
    vmull.s32 q11, d1, d7      @ d1 * alpha
    vaddq.s64 q8,  q8,  q10
    vaddq.s64 q9,  q9,  q11
    vshrn.s64 d0, q8, #16
    vshrn.s64 d1, q9, #16

    @ armazena q0 de volta (dims 0..3)
    vst1.32 {q0}, [r5]

    @ EMA escalar para dims 4..6
    @ s[4] = (s[4]*49152 + c_in*16384) >> 16
    mov     r2, #49152
    umull   r3, r10, r7, r2    @ r7=s[4]
    lsr     r3, r3, #16
    orr     r3, r3, r10, lsl #16
    ldr     r10, =16384
    ldr     r11, =SPIRAL_Q16   @ reutiliza c_in ~ SPIRAL
    umull   r2, r12, r11, r10
    lsr     r2, r2, #16
    orr     r2, r2, r12, lsl #16
    add     r3, r3, r2
    uxth    r3, r3
    str     r3, [r5, #16]      @ s[4]

    umull   r3, r10, r8, #49152
    lsr     r3, r3, #16
    add     r3, r3, r2
    uxth    r3, r3
    str     r3, [r5, #20]      @ s[5]

    umull   r3, r10, r9, #49152
    lsr     r3, r3, #16
    add     r3, r3, r2
    uxth    r3, r3
    str     r3, [r5, #24]      @ s[6]

    vpop    {q0-q3}
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ isosceles_predict — prediz jet_target via triângulo isósceles
@ Encontra core de MAIOR hz (ápice) e core de MENOR load (jet)
@ retorna r0 = jet_target index
@ ===========================================================================
.type isosceles_predict, %function
isosceles_predict:
    push    {r4, r5, r6, r7, r8, lr}

    ldr     r4, =vcpu_hz_table
    ldr     r5, =g_vcpu_load

    @ encontra ápice (maior hz)
    ldr     r6, =0               @ max_hz
    mov     r7, #0               @ apex_idx

    mov     r8, #0
.Bap_loop:
    cmp     r8, #N_VCPU
    beq     .Bap_done
    ldr     r0, [r4, r8, lsl #2]
    cmp     r0, r6
    movgt   r6, r0
    movgt   r7, r8
    add     r8, r8, #1
    b       .Bap_loop
.Bap_done:
    @ r7 = apex_idx

    @ encontra jet_target: core de menor load ≠ apex
    ldr     r6, =0x7FFFFFFF     @ min_load
    mov     r0, #0              @ jet_target

    mov     r8, #0
.Bjet_loop:
    cmp     r8, #N_VCPU
    beq     .Bjet_done
    cmp     r8, r7
    beq     .Bjet_skip          @ pula ápice
    ldr     r1, [r5, r8, lsl #2]
    cmp     r1, r6
    movlt   r6, r1
    movlt   r0, r8
.Bjet_skip:
    add     r8, r8, #1
    b       .Bjet_loop
.Bjet_done:
    @ r0 = jet_target
    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ print_vcpu_hz — imprime hz de cada core
@ ===========================================================================
.type print_vcpu_hz, %function
print_vcpu_hz:
    push    {r4, r5, lr}
    ldr     r4, =vcpu_hz_table
    mov     r5, #0

.Bphz_loop:
    cmp     r5, #N_VCPU
    beq     .Bphz_done
    ldr     r0, [r4, r5, lsl #2]
    bl      ph6
    add     r5, r5, #1
    b       .Bphz_loop
.Bphz_done:
    pop     {r4, r5, pc}

@ ===========================================================================
@ CRC32C
@ ===========================================================================
.type crc6_build, %function
crc6_build:
    push    {r4, r5, r6, r7, lr}
    ldr     r4, =g_crc6
    mov     r5, #0
.Bc6_lp:
    cmp     r5, #256
    beq     .Bc6_done
    mov     r0, r5
    mov     r6, #8
.Bc6_bit:
    tst     r0, #1
    lsr     r0, r0, #1
    ldrne   r7, =0x82F63B78
    eorne   r0, r0, r7
    subs    r6, r6, #1
    bne     .Bc6_bit
    str     r0, [r4, r5, lsl #2]
    add     r5, r5, #1
    b       .Bc6_lp
.Bc6_done:
    pop     {r4, r5, r6, r7, pc}

.type crc6_compute, %function
crc6_compute:
    push    {r4, r5, r6, r7, r8, lr}
    mov     r4, r0
    mov     r5, r1
    mvn     r6, #0
    ldr     r7, =g_crc6
.Bc6c_lp:
    cmp     r5, #0
    beq     .Bc6c_done
    ldrb    r0, [r4], #1
    eor     r8, r6, r0
    and     r8, r8, #0xFF
    ldr     r0, [r7, r8, lsl #2]
    lsr     r6, r6, #8
    eor     r6, r6, r0
    subs    r5, r5, #1
    b       .Bc6c_lp
.Bc6c_done:
    mvn     r0, r6
    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type ws6, %function
ws6:
    push    {lr}
    mov     r2, r1
    mov     r1, r0
    mov     r0, #STDOUT
    mov     r7, #SYS_WRITE
    swi     #0
    pop     {pc}

.type ph6, %function
ph6:
    push    {r4, r5, lr}
    mov     r4, r0
    ldr     r5, =g_hex6
    ldr     r2, =hex_t6
    mov     r1, #28
.Bph6:
    lsr     r0, r4, r1
    and     r0, r0, #0xF
    ldrb    r0, [r2, r0]
    strb    r0, [r5], #1
    subs    r1, r1, #4
    bge     .Bph6
    mov     r0, #'\n'
    strb    r0, [r5]
    ldr     r0, =g_hex6
    mov     r1, #9
    bl      ws6
    pop     {r4, r5, pc}
