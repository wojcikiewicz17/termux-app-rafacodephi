@ ===========================================================================
@ RAFAELIA B8 — NEON SENOIDAL + PESOS ADAPTATIVOS + CRC ENCADEADA
@ ARM32 · Cortex-A53 · zero deps · sin/cos Taylor Q16.16
@
@ MODELO:
@   7 camadas senoidais com frequências harmônicas de π/21
@   Cada camada tem peso adaptativo (EMA 0.25)
@   Sobreposição: soma ponderada → coerência phi = (1-H)*C
@   CRC32C encadeada entre ciclos: crc_n = CRC(state || crc_{n-1})
@   Resultado: vetor phi[0..41] como trace de convergência
@
@ Compilar:
@   as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b8.S -o b8.o
@   ld b8.o -o rafaelia_b8
@ ===========================================================================

.equ SYS_EXIT,  1
.equ SYS_WRITE, 4
.equ STDOUT,    1

@ Constantes Q16.16
.equ Q16_ONE,     65536    @ 1.0
.equ Q16_HALF,    32768    @ 0.5
.equ Q16_PI,      205887   @ pi
.equ Q16_2PI,     411774   @ 2*pi
.equ Q16_INV6,    10923    @ 1/6  (10922.67)
.equ Q16_INV120,  546      @ 1/120 (546.13)
.equ Q16_INV5040, 13       @ 1/5040 (sem erro crítico)
.equ SPIRAL_Q16,  56755    @ sqrt(3)/2
.equ PHI_Q16,     105965   @ phi
.equ PERIOD,      42
.equ N_LAYERS,    7

@ Frequências harmônicas: freq[i] = (i+1)*pi/21 em Q16.16
@ pi/21 = 9804, 2pi/21=19608, 3pi/21=29412 ...
.equ F0, 9804
.equ F1, 19608
.equ F2, 29412
.equ F3, 39216
.equ F4, 49020
.equ F5, 58824
.equ F6, 68628

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_b8:     .ascii "B8: NEON-SIN+PESOS+CRC-CHAIN\n"
.equ msg_b8_len, . - msg_b8

msg_conv:   .ascii "CONV="
.equ msg_conv_len, . - msg_conv

msg_phi:    .ascii "PHI="
.equ msg_phi_len, . - msg_phi

msg_chain:  .ascii "CRC_CHAIN="
.equ msg_chain_len, . - msg_chain

msg_done8:  .ascii "B8:DONE\n"
.equ msg_done8_len, . - msg_done8

hex_t8:     .ascii "0123456789ABCDEF"

@ Frequências das 7 camadas
.align 4
g_freqs:
    .long F0, F1, F2, F3, F4, F5, F6

@ Pesos iniciais: decaimento exponencial (SPIRAL^i)
@ w[0]=65536, w[1]=56755, w[2]=49157, w[3]=42573
@ w[4]=36877, w[5]=31940, w[6]=27671
.align 4
g_weights_init:
    .long 65536, 56755, 49157, 42573, 36877, 31940, 27671

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

@ Fases das 7 camadas (Q16.16, acumulam a cada ciclo)
.align 4
g_phases:      .space N_LAYERS * 4

@ Pesos adaptativos (Q16.16)
.align 4
g_weights:     .space N_LAYERS * 4

@ Saída de cada camada (Q16.16, sin(fase)*peso)
.align 4
g_layer_out:   .space N_LAYERS * 4

@ Histórico phi[0..41] (trace de convergência)
.align 4
g_phi_trace:   .space PERIOD * 4

@ CRC32C encadeada
g_crc_chain:   .space 4

@ CRC table
.align 6
g_crc8_tab:    .space 256 * 4

@ Coerência e entropia globais
g_C:           .space 4
g_H:           .space 4

@ Scratch
g_hex8:        .space 16

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    bl      crc8_build
    bl      b8_init

    ldr     r0, =msg_b8
    mov     r1, #msg_b8_len
    bl      ws8

    @ 42 ciclos
    mov     r4, #PERIOD

.Bcycle:
    cmp     r4, #0
    beq     .Bcycle_done

    @ step: atualiza fases, calcula sin, multiplica pesos
    mov     r0, #PERIOD
    sub     r0, r0, r4          @ cycle_index = PERIOD - r4
    bl      b8_step

    @ phi = (1-H)*C
    ldr     r5, =g_C
    ldr     r6, =g_H
    ldr     r5, [r5]
    ldr     r6, [r6]
    rsb     r6, r6, #65535      @ 1-H
    umull   r2, r3, r5, r6
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16 @ phi Q16.16

    @ armazena no trace
    ldr     r7, =g_phi_trace
    mov     r8, #PERIOD
    sub     r8, r8, r4
    str     r2, [r7, r8, lsl #2]

    @ CRC encadeada: crc_n = CRC(phi || crc_{n-1})
    ldr     r7, =g_crc_chain
    ldr     r3, [r7]
    @ xor phi com crc anterior como input
    eor     r2, r2, r3
    @ crc de 4 bytes
    ldr     r7, =g_crc_chain
    str     r2, [r7]            @ usa EOR como hash leve
    @ CRC real
    sub     sp, sp, #8
    str     r2, [sp, #0]
    str     r3, [sp, #4]
    mov     r0, sp
    mov     r1, #8
    bl      crc8_compute
    ldr     r1, =g_crc_chain
    str     r0, [r1]
    add     sp, sp, #8

    subs    r4, r4, #1
    b       .Bcycle

.Bcycle_done:
    @ imprime phi do último ciclo
    ldr     r0, =msg_phi
    mov     r1, #msg_phi_len
    bl      ws8
    ldr     r0, =g_phi_trace
    ldr     r0, [r0, #(PERIOD-1)*4]
    bl      ph8

    @ imprime convergência: phi[41] - phi[0] (deve ser > 0 se convergiu)
    ldr     r0, =msg_conv
    mov     r1, #msg_conv_len
    bl      ws8
    ldr     r4, =g_phi_trace
    ldr     r0, [r4, #(PERIOD-1)*4]
    ldr     r1, [r4, #0]
    subs    r0, r0, r1
    rsblt   r0, r0, #0          @ abs
    bl      ph8

    @ imprime CRC chain final
    ldr     r0, =msg_chain
    mov     r1, #msg_chain_len
    bl      ws8
    ldr     r0, =g_crc_chain
    ldr     r0, [r0]
    bl      ph8

    ldr     r0, =msg_done8
    mov     r1, #msg_done8_len
    bl      ws8

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

@ ===========================================================================
@ b8_init — copia pesos e zera fases
@ ===========================================================================
.type b8_init, %function
b8_init:
    push    {r4, lr}
    ldr     r4, =g_weights_init
    ldr     r0, =g_weights
    ldmia   r4, {r1, r2, r3, r4, r5, r6, r7}
    ldr     r8, =g_weights
    stmia   r8, {r1, r2, r3, r4, r5, r6, r7}
    ldr     r4, =g_phases
    mov     r0, #0
    mov     r1, #N_LAYERS
.Bpz:
    str     r0, [r4], #4
    subs    r1, r1, #1
    bne     .Bpz
    @ C=H=0x8000
    ldr     r4, =g_C
    mov     r0, #0x8000
    str     r0, [r4]
    ldr     r4, =g_H
    str     r0, [r4]
    @ crc_chain=0
    ldr     r4, =g_crc_chain
    mov     r0, #0
    str     r0, [r4]
    pop     {r4, pc}

@ ===========================================================================
@ sin_q16 — sin(x) Taylor: x - x^3/6 + x^5/120 - x^7/5040
@ r0 = x Q16.16 → r0 = sin(x) Q16.16
@ range: [0, 2*pi)
@ ===========================================================================
.type sin_q16, %function
sin_q16:
    push    {r4, r5, r6, r7, r8, lr}

    mov     r4, r0          @ x

    @ reduce mod 2pi
    ldr     r1, =Q16_2PI
.Sred:
    cmp     r4, r1
    subge   r4, r4, r1
    bge     .Sred

    @ quadrant check: se x > pi → sin(x) = -sin(x-pi)
    ldr     r1, =Q16_PI
    mov     r8, #0          @ sign = +1
    cmp     r4, r1
    subge   r4, r4, r1
    movge   r8, #1          @ sign = -1

    @ x^2 Q16.16
    umull   r5, r6, r4, r4
    lsr     r5, r5, #16
    orr     r5, r5, r6, lsl #16     @ r5 = x^2

    @ x^3 = x^2 * x
    umull   r2, r3, r5, r4
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16     @ r2 = x^3

    @ x^3/6
    ldr     r1, =Q16_INV6
    umull   r6, r7, r2, r1
    lsr     r6, r6, #16
    orr     r6, r6, r7, lsl #16     @ r6 = x^3/6

    @ x^5 = x^3 * x^2
    umull   r2, r3, r2, r5
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16     @ r2 = x^5

    @ x^5/120
    ldr     r1, =Q16_INV120
    umull   r7, r3, r2, r1
    lsr     r7, r7, #16
    orr     r7, r7, r3, lsl #16     @ r7 = x^5/120

    @ x^7 = x^5 * x^2
    umull   r2, r3, r2, r5
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16     @ r2 = x^7

    @ x^7/5040
    ldr     r1, =Q16_INV5040
    umull   r2, r3, r2, r1
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16     @ r2 = x^7/5040

    @ sin(x) = x - x^3/6 + x^5/120 - x^7/5040
    sub     r0, r4, r6
    add     r0, r0, r7
    sub     r0, r0, r2

    @ aplica sinal
    cmp     r8, #1
    rsbge   r0, r0, #0      @ negate

    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ b8_step — 1 ciclo: atualiza fases, sin, pesos, C/H
@ r0 = cycle_index (0..41)
@ ===========================================================================
.type b8_step, %function
b8_step:
    push    {r4, r5, r6, r7, r8, r9, r10, lr}
    vpush   {q0-q3}

    mov     r9, r0              @ cycle_index

    ldr     r4, =g_phases
    ldr     r5, =g_freqs
    ldr     r6, =g_weights
    ldr     r7, =g_layer_out

    @ soma ponderada acumulada (Q16.16)
    mov     r10, #0             @ overlap

    @ processa 4 camadas com NEON
    @ carrega fases[0..3]
    vld1.32 {q0}, [r4]          @ q0 = phases[0..3]
    @ carrega freqs[0..3]
    vld1.32 {q1}, [r5]          @ q1 = freqs[0..3]

    @ fase_nova = (fase + freq) mod 2*pi
    vadd.s32 q0, q0, q1

    @ clamp mod Q16_2PI: usa loop escalar (NEON não tem mod)
    vmov    r0, r1, d0          @ r0=lane0 r1=lane1
    vmov    r2, r3, d1          @ r2=lane2 r3=lane3

    ldr     r8, =Q16_2PI
    cmp     r0, r8; subge r0, r0, r8
    cmp     r1, r8; subge r1, r1, r8
    cmp     r2, r8; subge r2, r2, r8
    cmp     r3, r8; subge r3, r3, r8

    vmov    d0, r0, r1
    vmov    d1, r2, r3

    @ armazena fases atualizadas
    vst1.32 {q0}, [r4]

    @ calcula sin para cada uma das 4 fases
    mov     r0, r0; bl sin_q16; str r0, [r7, #0]
    mov     r0, r1; bl sin_q16; str r0, [r7, #4]
    mov     r0, r2; bl sin_q16; str r0, [r7, #8]
    mov     r0, r3; bl sin_q16; str r0, [r7, #12]

    @ multiplica por pesos[0..3] e acumula
    ldr     r0, [r7, #0]; ldr r1, [r6, #0]
    umull   r2, r3, r0, r1; lsr r2, r2, #16; add r10, r10, r2

    ldr     r0, [r7, #4]; ldr r1, [r6, #4]
    umull   r2, r3, r0, r1; lsr r2, r2, #16; add r10, r10, r2

    ldr     r0, [r7, #8]; ldr r1, [r6, #8]
    umull   r2, r3, r0, r1; lsr r2, r2, #16; add r10, r10, r2

    ldr     r0, [r7, #12]; ldr r1, [r6, #12]
    umull   r2, r3, r0, r1; lsr r2, r2, #16; add r10, r10, r2

    @ camadas 4..6 (escalar)
    add     r4, r4, #16         @ fases[4..6]
    add     r5, r5, #16         @ freqs[4..6]
    add     r6, r6, #16
    add     r7, r7, #16

    mov     r8, #3              @ 3 camadas restantes
    mov     r9, #0              @ offset

.Bscalar3:
    cmp     r8, #0
    beq     .Bscalar3_done

    ldr     r0, [r4, r9]        @ fase
    ldr     r1, [r5, r9]        @ freq
    add     r0, r0, r1
    ldr     r1, =Q16_2PI
    cmp     r0, r1
    subge   r0, r0, r1
    str     r0, [r4, r9]

    bl      sin_q16
    str     r0, [r7, r9]

    ldr     r1, [r6, r9]        @ peso
    umull   r2, r3, r0, r1
    lsr     r2, r2, #16
    add     r10, r10, r2

    add     r9, r9, #4
    subs    r8, r8, #1
    b       .Bscalar3

.Bscalar3_done:
    @ normaliza overlap por N_LAYERS
    ldr     r1, =9362           @ 1/7 * 65536 ≈ 9362
    umull   r2, r3, r10, r1
    lsr     r2, r2, #16
    and     r2, r2, #0xFFFF     @ C_in = sobreposição normalizada

    @ H_in = complemento
    rsb     r3, r2, #65535      @ H_in = 1 - C_in

    @ EMA C e H
    ldr     r4, =g_C
    ldr     r0, [r4]
    add     r1, r0, r0, lsl #1  @ 3*C
    add     r1, r1, r2
    lsr     r1, r1, #2          @ (3C + Cin)/4
    str     r1, [r4]

    ldr     r4, =g_H
    ldr     r0, [r4]
    add     r1, r0, r0, lsl #1
    add     r1, r1, r3
    lsr     r1, r1, #2
    str     r1, [r4]

    @ adapta pesos: w[i] = (3*w[i] + |sin_out[i]|)/4
    ldr     r4, =g_weights
    sub     r6, r6, #16         @ volta ao início
    sub     r7, r7, #16
    mov     r8, #N_LAYERS
    mov     r9, #0

.Badapt:
    cmp     r8, #0
    beq     .Badapt_done
    ldr     r0, [r6, r9]        @ w_old
    ldr     r1, [r7, r9]        @ sin_out (pode ser negativo)
    @ abs(sin_out)
    cmp     r1, #0
    rsblt   r1, r1, #0
    add     r2, r0, r0, lsl #1  @ 3*w
    add     r2, r2, r1
    lsr     r2, r2, #2          @ novo peso
    str     r2, [r4, r9]
    add     r9, r9, #4
    subs    r8, r8, #1
    b       .Badapt

.Badapt_done:
    vpop    {q0-q3}
    pop     {r4, r5, r6, r7, r8, r9, r10, pc}

@ ===========================================================================
@ CRC8
@ ===========================================================================
.type crc8_build, %function
crc8_build:
    push    {r4,r5,r6,r7,lr}
    ldr     r4,=g_crc8_tab; mov r5,#0
.Bc8b: cmp r5,#256; beq .Bc8bd
    mov r0,r5; mov r6,#8
.Bc8bb: tst r0,#1; lsr r0,r0,#1; ldrne r7,=0x82F63B78; eorne r0,r0,r7
    subs r6,r6,#1; bne .Bc8bb
    str r0,[r4,r5,lsl #2]; add r5,r5,#1; b .Bc8b
.Bc8bd: pop {r4,r5,r6,r7,pc}

.type crc8_compute, %function
crc8_compute:
    push    {r4,r5,r6,r7,r8,lr}
    mov r4,r0; mov r5,r1; mvn r6,#0; ldr r7,=g_crc8_tab
.Bc8c: cmp r5,#0; beq .Bc8cd
    ldrb r0,[r4],#1; eor r8,r6,r0; and r8,r8,#0xFF
    ldr r0,[r7,r8,lsl #2]; lsr r6,r6,#8; eor r6,r6,r0
    subs r5,r5,#1; b .Bc8c
.Bc8cd: mvn r0,r6
    pop {r4,r5,r6,r7,r8,pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type ws8, %function
ws8:
    push {lr}
    mov r2,r1; mov r1,r0; mov r0,#STDOUT; mov r7,#SYS_WRITE; swi #0
    pop {pc}

.type ph8, %function
ph8:
    push    {r4,r5,lr}
    mov r4,r0; ldr r5,=g_hex8; ldr r2,=hex_t8; mov r1,#28
.Bph8: lsr r0,r4,r1; and r0,r0,#0xF; ldrb r0,[r2,r0]; strb r0,[r5],#1
    subs r1,r1,#4; bge .Bph8
    mov r0,#'\n'; strb r0,[r5]; ldr r0,=g_hex8; mov r1,#9; bl ws8
    pop {r4,r5,pc}
