@ ===========================================================================
@ RAFAELIA B2 — 7 DIREÇÕES + NEON PIPELINE + PREFETCH
@ ARM32 · Cortex-A53 · zero deps
@ Compilar: as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b2.S -o b2.o && ld b2.o -o rafaelia_b2
@ ===========================================================================

.equ SYS_EXIT,   1
.equ SYS_WRITE,  4
.equ STDOUT,     1

@ ---------------------------------------------------------------------------
@ 7 DIREÇÕES (enum)
@ ---------------------------------------------------------------------------
.equ DIR_NONE,     0
.equ DIR_UP,       1
.equ DIR_DOWN,     2
.equ DIR_FORWARD,  3
.equ DIR_RECURSE,  4
.equ DIR_COMPRESS, 5
.equ DIR_EXPAND,   6

@ Pesos Q16.16 uniformes (0x10000 / 7)
.equ W_NONE,      0x249B
.equ W_UP,        0x249B
.equ W_DOWN,      0x249B
.equ W_FORWARD,   0x249B
.equ W_RECURSE,   0x249B
.equ W_COMPRESS,  0x249B
.equ W_EXPAND,    0x249C

.equ SPIRAL_Q16,  56755
.equ PI_SIN_279,  3146       @ |pi*sin(279°)| * 65536

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_b2_boot:
    .ascii "B2: 7-DIRECTION ENGINE\n"
    .equ msg_b2_boot_len, . - msg_b2_boot

msg_pipeline_ok:
    .ascii "PIPELINE: OK\n"
    .equ msg_pipeline_ok_len, . - msg_pipeline_ok

msg_score:
    .ascii "SCORE="
    .equ msg_score_len, . - msg_score

hex_tab2: .ascii "0123456789ABCDEF"

@ Jump table: 7 ponteiros de função
.align 2
dir_jump_table:
    .word dir_none
    .word dir_up
    .word dir_down
    .word dir_forward
    .word dir_recurse
    .word dir_compress
    .word dir_expand

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

g_weights:   .space 7 * 4
g_score:     .space 4

.align 6
g_work_buf:  .space 256

@ histórico: 7 snapshots x 7 dims x 4 bytes
.align 5
g_history:   .space 7 * 7 * 4
g_hist_idx:  .space 4

g_hex_b2:    .space 16

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    bl      weights_init

    ldr     r0, =msg_b2_boot
    mov     r1, #msg_b2_boot_len
    bl      ws2

    @ 42 ciclos x 7 direções
    mov     r4, #42

.Bouter:
    cmp     r4, #0
    beq     .Bdone

    mov     r5, #0

.Bdir_loop:
    cmp     r5, #7
    beq     .Bdir_done

    ldr     r6, =dir_jump_table
    ldr     r7, [r6, r5, lsl #2]
    blx     r7

    add     r5, r5, #1
    b       .Bdir_loop

.Bdir_done:
    subs    r4, r4, #1
    b       .Bouter

.Bdone:
    ldr     r0, =msg_score
    mov     r1, #msg_score_len
    bl      ws2

    ldr     r0, =g_score
    ldr     r0, [r0]
    bl      print_hex32_b2

    ldr     r0, =msg_pipeline_ok
    mov     r1, #msg_pipeline_ok_len
    bl      ws2

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

@ ===========================================================================
@ weights_init
@ ===========================================================================
.type weights_init, %function
weights_init:
    push    {r4, lr}
    ldr     r4, =g_weights
    ldr     r0, =W_NONE;     str r0, [r4, #0]
    ldr     r0, =W_UP;       str r0, [r4, #4]
    ldr     r0, =W_DOWN;     str r0, [r4, #8]
    ldr     r0, =W_FORWARD;  str r0, [r4, #12]
    ldr     r0, =W_RECURSE;  str r0, [r4, #16]
    ldr     r0, =W_COMPRESS; str r0, [r4, #20]
    ldr     r0, =W_EXPAND;   str r0, [r4, #24]
    mov     r0, #0
    ldr     r1, =g_score;    str r0, [r1]
    ldr     r1, =g_hist_idx; str r0, [r1]
    pop     {r4, pc}

@ ===========================================================================
@ DIR_NONE — identidade
@ ===========================================================================
.type dir_none, %function
dir_none:
    push    {lr}
    ldr     r0, =g_score
    ldr     r1, [r0]
    ldr     r2, =W_NONE
    add     r1, r1, r2
    str     r1, [r0]
    pop     {pc}

@ ===========================================================================
@ DIR_UP — aumenta coerência via NEON vadd
@ ===========================================================================
.type dir_up, %function
dir_up:
    push    {r4, lr}
    vpush   {q0-q3}

    ldr     r4, =g_work_buf
    pld     [r4, #64]

    vld1.32 {q0, q1}, [r4]!
    vld1.32 {q2, q3}, [r4]

    vmov.i32 q8, #0x10000
    vadd.s32 q0, q0, q8

    vmov.i32 q9, #0xFFFF
    vmin.s32 q0, q0, q9

    sub     r4, r4, #32
    vst1.32 {q0, q1}, [r4]!

    ldr     r0, =g_score
    ldr     r1, [r0]
    ldr     r2, =W_UP
    add     r1, r1, r2
    str     r1, [r0]

    vpop    {q0-q3}
    pop     {r4, pc}

@ ===========================================================================
@ DIR_DOWN — ruído LCG via NEON
@ ===========================================================================
.type dir_down, %function
dir_down:
    push    {r4, lr}
    vpush   {q0-q1}

    ldr     r4, =g_work_buf
    pld     [r4]
    vld1.32 {q0}, [r4]

    vmov.i32 q1, #1664525
    vmul.s32 q0, q0, q1
    vmov.i32 q1, #1013904223
    vadd.s32 q0, q0, q1
    vmov.i32 q1, #0xFFFF
    vand     q0, q0, q1

    vst1.32 {q0}, [r4]

    ldr     r0, =g_score
    ldr     r1, [r0]
    ldr     r2, =W_DOWN
    lsr     r2, r2, #1
    add     r1, r1, r2
    str     r1, [r0]

    vpop    {q0-q1}
    pop     {r4, pc}

@ ===========================================================================
@ DIR_FORWARD — F_{n+1} = F_n * SPIRAL - PI_SIN_279 via NEON
@ ===========================================================================
.type dir_forward, %function
dir_forward:
    push    {r4, lr}
    vpush   {q0-q2}

    ldr     r4, =g_work_buf
    add     r4, r4, #240
    vld1.32 {q0}, [r4]

    vmov.i32 q1, #56755
    vmull.s32 q2, d0, d2
    vshrn.s64 d4, q2, #16
    vmull.s32 q2, d1, d3
    vshrn.s64 d5, q2, #16

    vmov.i32 q1, #PI_SIN_279
    vsub.s32 q2, q2, q1

    vst1.32 {q2}, [r4]

    ldr     r0, =g_score
    ldr     r1, [r0]
    ldr     r2, =W_FORWARD
    add     r1, r1, r2
    str     r1, [r0]

    vpop    {q0-q2}
    pop     {r4, pc}

@ ===========================================================================
@ DIR_RECURSE — snapshot no histórico
@ ===========================================================================
.type dir_recurse, %function
dir_recurse:
    push    {r4, r5, r6, lr}

    ldr     r4, =g_hist_idx
    ldr     r5, [r4]
    ldr     r6, =g_history
    mov     r0, #28
    mul     r0, r5, r0
    add     r6, r6, r0

    ldr     r0, =g_work_buf
    ldmia   r0, {r1, r2, r3}
    stmia   r6!, {r1, r2, r3}
    add     r0, r0, #12
    ldmia   r0, {r1, r2, r3}
    stmia   r6!, {r1, r2, r3}
    add     r0, r0, #12
    ldr     r1, [r0]
    str     r1, [r6]

    add     r5, r5, #1
    cmp     r5, #7
    moveq   r5, #0
    str     r5, [r4]

    ldr     r0, =g_score
    ldr     r1, [r0]
    ldr     r2, =W_RECURSE
    add     r1, r1, r2
    str     r1, [r0]

    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ DIR_COMPRESS — NEON vhadd (média de pares)
@ ===========================================================================
.type dir_compress, %function
dir_compress:
    push    {r4, lr}
    vpush   {q0-q3}

    ldr     r4, =g_work_buf
    pld     [r4, #128]

    vld1.32 {q0, q1}, [r4]!
    vld1.32 {q2, q3}, [r4]

    vhadd.s32 q0, q0, q1
    vhadd.s32 q2, q2, q3

    sub     r4, r4, #32
    vst1.32 {q0, q2}, [r4]

    ldr     r0, =g_score
    ldr     r1, [r0]
    ldr     r2, =W_COMPRESS
    add     r1, r1, r2
    str     r1, [r0]

    vpop    {q0-q3}
    pop     {r4, pc}

@ ===========================================================================
@ DIR_EXPAND — lerp entre work_buf e histórico via NEON vhadd
@ ===========================================================================
.type dir_expand, %function
dir_expand:
    push    {r4, r5, lr}
    vpush   {q0-q3}

    ldr     r4, =g_work_buf
    ldr     r5, =g_history

    vld1.32 {q0, q1}, [r4]
    vld1.32 {q2, q3}, [r5]

    vhadd.s32 q0, q0, q2
    vhadd.s32 q1, q1, q3

    vst1.32 {q0, q1}, [r4]

    ldr     r0, =g_score
    ldr     r1, [r0]
    ldr     r2, =W_EXPAND
    add     r1, r1, r2
    str     r1, [r0]

    vpop    {q0-q3}
    pop     {r4, r5, pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type ws2, %function
ws2:
    push    {lr}
    mov     r2, r1
    mov     r1, r0
    mov     r0, #STDOUT
    mov     r7, #SYS_WRITE
    swi     #0
    pop     {pc}

.type print_hex32_b2, %function
print_hex32_b2:
    push    {r4, r5, lr}
    mov     r4, r0
    ldr     r5, =g_hex_b2
    ldr     r2, =hex_tab2
    mov     r1, #28
.Ph2:
    lsr     r0, r4, r1
    and     r0, r0, #0xF
    ldrb    r0, [r2, r0]
    strb    r0, [r5], #1
    subs    r1, r1, #4
    bge     .Ph2
    mov     r0, #'\n'
    strb    r0, [r5]
    ldr     r0, =g_hex_b2
    mov     r1, #9
    bl      ws2
    pop     {r4, r5, pc}
