@ ===========================================================================
@ RAFAELIA B1 — ARM32 AArch32 GNU Assembly
@ Cortex-A53 / Helio G25 / NEON / zero dependência externa
@ Compilar: as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b1.S -o b1.o
@           ld -o rafaelia_b1 b1.o
@ ===========================================================================

@ ---------------------------------------------------------------------------
@ SYSCALLS Linux ARM32
@ ---------------------------------------------------------------------------
.equ SYS_EXIT,       1
.equ SYS_WRITE,      4
.equ SYS_MMAP2,      192
.equ SYS_MUNMAP,     91
.equ SYS_CLONE,      120
.equ SYS_SCHED_YIELD, 158
.equ SYS_NANOSLEEP,  162
.equ SYS_PRCTL,      172
.equ STDOUT,         1
.equ STDERR,         2

@ ---------------------------------------------------------------------------
@ CONSTANTES GEOMÉTRICAS Q16.16
@ sqrt(3)/2 = 0.86602540378 → 56755
@ phi       = 1.61803398875 → 105965
@ pi        = 3.14159265359 → 205887
@ ---------------------------------------------------------------------------
.equ SPIRAL_Q16,    56755
.equ PHI_Q16,       105965
.equ PI_Q16,        205887
.equ ALPHA_Q16,     16384      @ 0.25
.equ INV_ALPHA_Q16, 49152      @ 0.75
.equ PERIOD_42,     42
.equ TORUS_DIM,     7
.equ CACHE_LINE,    64
.equ ARENA_SIZE,    0x800000   @ 8 MB

@ ---------------------------------------------------------------------------
@ MMAP flags
@ ---------------------------------------------------------------------------
.equ PROT_RW,       3
.equ MAP_ANON_PRIV, 0x22
.equ MAP_FAILED,    0xFFFFFFFF

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_start:      .ascii "RAFAELIA B1: BOOT\n"
.equ msg_start_len,    . - msg_start

msg_arena_ok:   .ascii "ARENA: OK\n"
.equ msg_arena_ok_len, . - msg_arena_ok

msg_crc_ok:     .ascii "CRC32SW: OK\n"
.equ msg_crc_ok_len,   . - msg_crc_ok

msg_torus_ok:   .ascii "TORUS7D: OK\n"
.equ msg_torus_ok_len, . - msg_torus_ok

msg_neon_ok:    .ascii "NEON: OK\n"
.equ msg_neon_ok_len,  . - msg_neon_ok

msg_done:       .ascii "RAFAELIA B1: DONE\n"
.equ msg_done_len,     . - msg_done

msg_phi:        .ascii "PHI="
.equ msg_phi_len,      . - msg_phi

hex_chars:      .ascii "0123456789ABCDEF"

@ Tabela dos 42 atratores no toro T^7
@ cada atrator: 7 x int32 = 28 bytes
.align 5
attractor_table:
.set _A, 0
.rept 42
    .long 0x0000 + _A * 0x0A3C
    .long 0x2000 + _A * 0x0D17
    .long 0x4000 + _A * 0x05FB
    .long 0x6000 + _A * 0x08E4
    .long 0x8000 + _A * 0x03C2
    .long 0xA000 + _A * 0x0B91
    .long 0xC000 + _A * 0x07A5
    .set _A, _A + 1
.endr

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

.align 5
g_state:        .space TORUS_DIM * 4
g_coherence:    .space 4
g_entropy:      .space 4
g_phase:        .space 4
g_step_count:   .space 4

g_arena_ptr:    .space 4
g_arena_bump:   .space 4
g_arena_cap:    .space 4

g_hex_buf:      .space 16
g_crc_result:   .space 4

.align 6
g_neon_scratch: .space 128

@ Tabela CRC32C gerada em runtime (256 x 4 bytes)
.align 6
g_crc_table:    .space 256 * 4

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    mov     r11, sp

    ldr     r0, =msg_start
    mov     r1, #msg_start_len
    bl      sys_write_stdout

    bl      arena_init
    cmp     r0, #0
    bne     .Lfatal_oom

    ldr     r0, =msg_arena_ok
    mov     r1, #msg_arena_ok_len
    bl      sys_write_stdout

    bl      crc32c_gentable

    ldr     r0, =msg_crc_ok
    mov     r1, #msg_crc_ok_len
    bl      sys_write_stdout

    bl      torus_init

    ldr     r0, =msg_torus_ok
    mov     r1, #msg_torus_ok_len
    bl      sys_write_stdout

    bl      neon_selftest

    ldr     r0, =msg_neon_ok
    mov     r1, #msg_neon_ok_len
    bl      sys_write_stdout

    bl      rafaelia_run_42

    ldr     r0, =msg_phi
    mov     r1, #msg_phi_len
    bl      sys_write_stdout

    ldr     r4, =g_coherence
    ldr     r0, [r4]
    bl      print_hex_word

    ldr     r0, =msg_done
    mov     r1, #msg_done_len
    bl      sys_write_stdout

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

.Lfatal_oom:
    mov     r7, #SYS_EXIT
    mov     r0, #42
    swi     #0

@ ===========================================================================
@ arena_init
@ ===========================================================================
.type arena_init, %function
arena_init:
    push    {r4, r5, lr}
    mov     r0, #0
    ldr     r1, =ARENA_SIZE
    mov     r2, #PROT_RW
    mov     r3, #MAP_ANON_PRIV
    mov     r4, #-1
    mov     r5, #0
    mov     r7, #SYS_MMAP2
    swi     #0
    ldr     r1, =MAP_FAILED
    cmp     r0, r1
    beq     .Larena_fail
    ldr     r1, =g_arena_ptr
    str     r0, [r1]
    ldr     r1, =g_arena_bump
    mov     r2, #0
    str     r2, [r1]
    ldr     r1, =g_arena_cap
    ldr     r2, =ARENA_SIZE
    str     r2, [r1]
    mov     r0, #0
    pop     {r4, r5, pc}
.Larena_fail:
    mov     r0, #1
    pop     {r4, r5, pc}

@ ===========================================================================
@ arena_alloc — r0=bytes → r0=ptr ou 0
@ ===========================================================================
.type arena_alloc, %function
arena_alloc:
    push    {r4, r5, r6, lr}
    mov     r6, r0
    add     r0, r6, #15
    bic     r0, r0, #15
    ldr     r4, =g_arena_ptr
    ldr     r4, [r4]
    ldr     r5, =g_arena_bump
    ldr     r3, [r5]
    add     r1, r3, r0
    ldr     r2, =g_arena_cap
    ldr     r2, [r2]
    cmp     r1, r2
    bgt     .Loom
    str     r1, [r5]
    add     r0, r4, r3
    pop     {r4, r5, r6, pc}
.Loom:
    mov     r0, #0
    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ crc32c_gentable — poly 0x82F63B78
@ ===========================================================================
.type crc32c_gentable, %function
crc32c_gentable:
    push    {r4, r5, r6, r7, lr}
    ldr     r4, =g_crc_table
    mov     r5, #0
    ldr     r6, =0x82F63B78
.Lcrc_gen_loop:
    cmp     r5, #256
    beq     .Lcrc_gen_done
    mov     r0, r5
    mov     r7, #8
.Lcrc_bit_loop:
    tst     r0, #1
    lsr     r0, r0, #1
    eorne   r0, r0, r6
    subs    r7, r7, #1
    bne     .Lcrc_bit_loop
    str     r0, [r4, r5, lsl #2]
    add     r5, r5, #1
    b       .Lcrc_gen_loop
.Lcrc_gen_done:
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ crc32c_sw — r0=ptr r1=len → r0=crc
@ ===========================================================================
.type crc32c_sw, %function
crc32c_sw:
    push    {r4, r5, r6, r7, r8, lr}
    mov     r4, r0
    mov     r5, r1
    mvn     r6, #0
    ldr     r7, =g_crc_table
.Lcrc_data_loop:
    cmp     r5, #0
    beq     .Lcrc_final
    ldrb    r0, [r4], #1
    eor     r8, r6, r0
    and     r8, r8, #0xFF
    ldr     r0, [r7, r8, lsl #2]
    lsr     r6, r6, #8
    eor     r6, r6, r0
    subs    r5, r5, #1
    b       .Lcrc_data_loop
.Lcrc_final:
    mvn     r0, r6
    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ torus_init — estado 7D com constantes irracionais
@ ===========================================================================
.type torus_init, %function
torus_init:
    push    {r4, r5, r6, lr}
    ldr     r4, =g_state
    ldr     r5, =SPIRAL_Q16
    ldr     r6, =PHI_Q16
    and     r0, r5, #0xFFFF
    str     r0, [r4, #0]
    and     r0, r6, #0xFFFF
    str     r0, [r4, #4]
    mul     r0, r5, r6
    lsr     r0, r0, #16
    and     r0, r0, #0xFFFF
    str     r0, [r4, #8]
    ldr     r0, =PI_Q16
    and     r0, r0, #0xFFFF
    str     r0, [r4, #12]
    ldr     r1, =PI_Q16
    mul     r0, r1, r5
    lsr     r0, r0, #16
    and     r0, r0, #0xFFFF
    str     r0, [r4, #16]
    ldr     r1, =PI_Q16
    mul     r0, r6, r1
    lsr     r0, r0, #16
    and     r0, r0, #0xFFFF
    str     r0, [r4, #20]
    ldr     r1, =PI_Q16
    add     r0, r5, r6
    add     r0, r0, r1
    and     r0, r0, #0xFFFF
    str     r0, [r4, #24]
    ldr     r4, =g_coherence
    mov     r0, #0x8000
    str     r0, [r4]
    ldr     r4, =g_entropy
    str     r0, [r4]
    ldr     r4, =g_phase
    mov     r0, #0
    str     r0, [r4]
    ldr     r4, =g_step_count
    str     r0, [r4]
    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ torus_step — EMA update + fase
@ r0=C_in r1=H_in
@ ===========================================================================
.type torus_step, %function
torus_step:
    push    {r4, r5, r6, r7, lr}
    mov     r4, r0
    mov     r5, r1
    ldr     r6, =g_coherence
    ldr     r0, [r6]
    ldr     r7, =INV_ALPHA_Q16
    umull   r2, r3, r0, r7
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16
    ldr     r7, =ALPHA_Q16
    umull   r1, r3, r4, r7
    lsr     r1, r1, #16
    orr     r1, r1, r3, lsl #16
    add     r0, r2, r1
    uxth    r0, r0
    str     r0, [r6]
    ldr     r6, =g_entropy
    ldr     r0, [r6]
    ldr     r7, =INV_ALPHA_Q16
    umull   r2, r3, r0, r7
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16
    ldr     r7, =ALPHA_Q16
    umull   r1, r3, r5, r7
    lsr     r1, r1, #16
    orr     r1, r1, r3, lsl #16
    add     r0, r2, r1
    uxth    r0, r0
    str     r0, [r6]
    ldr     r6, =g_phase
    ldr     r0, [r6]
    add     r0, r0, #1
    cmp     r0, #PERIOD_42
    moveq   r0, #0
    str     r0, [r6]
    ldr     r6, =g_step_count
    ldr     r0, [r6]
    add     r0, r0, #1
    str     r0, [r6]
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ neon_mat4x4_mul — Q16.16 NEON 4x4
@ r0=A r1=B r2=C
@ ===========================================================================
.type neon_mat4x4_mul, %function
neon_mat4x4_mul:
    push    {r4, r5, r6, lr}
    vpush   {q4-q7}
    mov     r4, r0
    mov     r5, r1
    mov     r6, r2
    vld1.32 {q8},  [r5]!
    vld1.32 {q9},  [r5]!
    vld1.32 {q10}, [r5]!
    vld1.32 {q11}, [r5]!
    mov     r0, #4
.Lmat_row:
    cmp     r0, #0
    beq     .Lmat_done
    vld1.32 {q0}, [r4]!
    vdup.32 q1, d0[0]
    vmull.s32 q12, d2, d16
    vmull.s32 q13, d2, d17
    vdup.32 q1, d0[1]
    vmlal.s32 q12, d2, d18
    vmlal.s32 q13, d2, d19
    vdup.32 q1, d1[0]
    vmlal.s32 q12, d2, d20
    vmlal.s32 q13, d2, d21
    vdup.32 q1, d1[1]
    vmlal.s32 q12, d2, d22
    vmlal.s32 q13, d2, d23
    vshrn.s64 d4, q12, #16
    vshrn.s64 d5, q13, #16
    vst1.32 {q2}, [r6]!
    subs    r0, r0, #1
    b       .Lmat_row
.Lmat_done:
    vpop    {q4-q7}
    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ neon_selftest
@ ===========================================================================
.type neon_selftest, %function
neon_selftest:
    push    {r4, r5, r6, lr}
    mov     r0, #64
    bl      arena_alloc
    cmp     r0, #0
    beq     .Lneon_fail
    mov     r4, r0
    mov     r0, #64
    bl      arena_alloc
    cmp     r0, #0
    beq     .Lneon_fail
    mov     r5, r0
    mov     r0, #64
    bl      arena_alloc
    cmp     r0, #0
    beq     .Lneon_fail
    mov     r6, r0
    ldr     r1, =0x00010000
    str     r1, [r4, #0]
    str     r1, [r4, #20]
    str     r1, [r4, #40]
    str     r1, [r4, #60]
    mov     r0, r5
    mov     r1, r4
    mov     r2, #64
.Lcopy_loop:
    ldr     r3, [r1], #4
    str     r3, [r0], #4
    subs    r2, r2, #4
    bne     .Lcopy_loop
    mov     r0, r4
    mov     r1, r5
    mov     r2, r6
    bl      neon_mat4x4_mul
    ldr     r0, [r6, #0]
    ldr     r1, =0x00010000
    cmp     r0, r1
    bne     .Lneon_fail
    mov     r0, r6
    mov     r1, #64
    bl      crc32c_sw
    ldr     r1, =g_crc_result
    str     r0, [r1]
    pop     {r4, r5, r6, pc}
.Lneon_fail:
    mov     r7, #SYS_EXIT
    mov     r0, #99
    swi     #0

@ ===========================================================================
@ torus_collapse — distância Manhattan, 42 atratores
@ retorna r0=índice melhor atrator
@ ===========================================================================
.type torus_collapse, %function
torus_collapse:
    push    {r4, r5, r6, r7, r8, r9, r10, lr}
    ldr     r4, =g_state
    ldr     r5, =attractor_table
    ldr     r6, =0x7FFFFFFF
    mov     r7, #0
    mov     r8, #0
.Lcollapse_loop:
    cmp     r8, #42
    beq     .Lcollapse_done
    mov     r9, r8
    mov     r10, #28
    mul     r10, r9, r10
    add     r10, r5, r10
    mov     r9, #0
    mov     r3, #7
.Lcollapse_dim:
    ldr     r0, [r4], #4
    ldr     r1, [r10], #4
    subs    r2, r0, r1
    rsblt   r2, r2, #0
    add     r9, r9, r2
    subs    r3, r3, #1
    bne     .Lcollapse_dim
    sub     r4, r4, #28
    cmp     r9, r6
    movlt   r6, r9
    movlt   r7, r8
    add     r8, r8, #1
    b       .Lcollapse_loop
.Lcollapse_done:
    mov     r0, r7
    pop     {r4, r5, r6, r7, r8, r9, r10, pc}

@ ===========================================================================
@ rafaelia_run_42 — 42 ciclos principais
@ ===========================================================================
.type rafaelia_run_42, %function
rafaelia_run_42:
    push    {r4, r5, r6, lr}
    mov     r4, #PERIOD_42
.Rmain_cycle:
    cmp     r4, #0
    beq     .Rmain_done
    ldr     r5, =g_step_count
    ldr     r0, [r5]
    ldr     r1, =SPIRAL_Q16
    mul     r0, r0, r1
    lsr     r0, r0, #16
    and     r0, r0, #0xFFFF
    mvn     r1, r0
    and     r1, r1, #0xFFFF
    bl      torus_step
    ldr     r5, =g_phase
    ldr     r5, [r5]
    tst     r5, #7
    bne     .Rskip_collapse
    bl      torus_collapse
    ldr     r5, =attractor_table
    mov     r6, #28
    mul     r0, r0, r6
    add     r5, r5, r0
    ldr     r6, =g_state
    ldmia   r5, {r0, r1, r2, r3}
    stmia   r6, {r0, r1, r2, r3}
.Rskip_collapse:
    subs    r4, r4, #1
    b       .Rmain_cycle
.Rmain_done:
    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type sys_write_stdout, %function
sys_write_stdout:
    push    {lr}
    mov     r2, r1
    mov     r1, r0
    mov     r0, #STDOUT
    mov     r7, #SYS_WRITE
    swi     #0
    pop     {pc}

.type print_hex_word, %function
print_hex_word:
    push    {r4, r5, lr}
    mov     r4, r0
    ldr     r5, =g_hex_buf
    ldr     r2, =hex_chars
    mov     r1, #28
.Phex_loop:
    lsr     r0, r4, r1
    and     r0, r0, #0xF
    ldrb    r0, [r2, r0]
    strb    r0, [r5], #1
    subs    r1, r1, #4
    bge     .Phex_loop
    mov     r0, #'\n'
    strb    r0, [r5]
    ldr     r0, =g_hex_buf
    mov     r1, #9
    bl      sys_write_stdout
    pop     {r4, r5, pc}
