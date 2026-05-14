@ ===========================================================================
@ RAFAELIA B4 — ORQUESTRAÇÃO FINAL: SENOIDE + SOBREPOSIÇÃO + VETOR-CAMADAS
@ ARM32 · zero deps · usa NEON para senoides aproximadas + pesos sobrepostos
@ Compilar: as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b4.S -o b4.o && ld b4.o -o rafaelia_b4
@
@ MODELO:
@   Cada "instrução complexa" é decomposta em 7 senoides sobrepostas.
@   Cada senoide representa uma camada de peso no espaço Q16.16.
@   A sobreposição produz um vetor de saída que é a "resposta" do sistema.
@   Aproximação de sin(x) via série de Taylor Q16.16:
@     sin(x) ≈ x - x^3/6 + x^5/120  (para x em Q16.16 rad)
@ ===========================================================================

.equ SYS_EXIT,   1
.equ SYS_WRITE,  4
.equ STDOUT,     1

@ Constantes Q16.16
.equ Q16_ONE,    0x00010000     @ 1.0
.equ Q16_HALF,   0x00008000     @ 0.5
.equ Q16_PI,     0x0003243F     @ pi
.equ Q16_2PI,    0x0006487F     @ 2*pi
.equ Q16_INV6,   0x00002AAB     @ 1/6
.equ Q16_INV120, 0x00000222     @ 1/120
.equ SPIRAL_Q16, 56755
.equ PHI_Q16,    105965
.equ PERIOD_42,  42
.equ N_LAYERS,   7              @ 7 camadas de peso

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_b4_boot:
    .ascii "B4: SENOIDE+CAMADAS\n"
    .equ msg_b4_boot_len, . - msg_b4_boot

msg_layer:
    .ascii "LAYER="
    .equ msg_layer_len, . - msg_layer

msg_overlap:
    .ascii "OVERLAP="
    .equ msg_overlap_len, . - msg_overlap

msg_final:
    .ascii "RAFAELIA:COMPLETE\n"
    .equ msg_final_len, . - msg_final

hex_t4: .ascii "0123456789ABCDEF"

@ Frequências das 7 camadas (Q16.16 rad/ciclo)
@ Baseadas em harmônicos da frequência fundamental pi/21
.align 4
layer_freqs:
    .long  9834    @ pi/21     layer 0 (fundamental)
    .long  19668   @ 2*pi/21   layer 1
    .long  29502   @ 3*pi/21   layer 2
    .long  39336   @ 4*pi/21   layer 3
    .long  49170   @ 5*pi/21   layer 4
    .long  59004   @ 6*pi/21   layer 5
    .long  68838   @ 7*pi/21 = pi/3  layer 6

@ Pesos iniciais das 7 camadas (Q16.16, decaimento exponencial)
.align 4
layer_weights:
    .long  65536   @ 1.000  layer 0
    .long  47952   @ 0.732  layer 1 (≈ 1/sqrt(2))
    .long  35112   @ 0.536  layer 2
    .long  25706   @ 0.392  layer 3
    .long  18818   @ 0.287  layer 4
    .long  13783   @ 0.210  layer 5
    .long  10096   @ 0.154  layer 6

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

@ fases das 7 camadas (Q16.16 acumuladas)
.align 5
g_phases:      .space N_LAYERS * 4

@ pesos adaptativos (modificados pelo sistema)
g_adapt_w:     .space N_LAYERS * 4

@ saída da sobreposição (7 elementos x Q16.16)
.align 5
g_overlap_out: .space N_LAYERS * 4

@ vetor de estado final (resultado da orquestração)
.align 5
g_final_vec:   .space N_LAYERS * 4

@ buffer de trabalho NEON
.align 6
g_neon_b4:     .space 256

g_hex_b4:      .space 16
g_iter_count:  .space 4

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    ldr     r0, =msg_b4_boot
    mov     r1, #msg_b4_boot_len
    bl      ws4

    @ inicializa fases e pesos adaptativos
    bl      b4_init

    @ loop principal: 42 iterações x 7 camadas
    mov     r4, #PERIOD_42

.B4main:
    cmp     r4, #0
    beq     .B4done

    @ computa senoide de cada camada e acumula sobreposição
    bl      compute_layers

    @ adapta pesos baseado na coerência
    bl      adapt_weights

    @ multiplica vetores de camada com NEON
    bl      neon_layer_mul

    subs    r4, r4, #1
    b       .B4main

.B4done:
    @ imprime resultado de cada camada
    ldr     r4, =g_final_vec
    mov     r5, #0

.Bprint_layer:
    cmp     r5, #N_LAYERS
    beq     .Bprint_done

    push    {r4, r5}
    ldr     r0, =msg_layer
    mov     r1, #msg_layer_len
    bl      ws4
    pop     {r4, r5}

    ldr     r0, [r4, r5, lsl #2]
    bl      print_hex32_b4

    add     r5, r5, #1
    b       .Bprint_layer

.Bprint_done:
    @ imprime sobreposição final
    ldr     r0, =msg_overlap
    mov     r1, #msg_overlap_len
    bl      ws4

    ldr     r4, =g_overlap_out
    mov     r0, #0
    mov     r5, #0

    @ XOR acumulado como "hash" da sobreposição
.Bxor_loop:
    cmp     r5, #N_LAYERS
    beq     .Bxor_done
    ldr     r1, [r4, r5, lsl #2]
    eor     r0, r0, r1
    add     r5, r5, #1
    b       .Bxor_loop

.Bxor_done:
    bl      print_hex32_b4

    ldr     r0, =msg_final
    mov     r1, #msg_final_len
    bl      ws4

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

@ ===========================================================================
@ b4_init — copia pesos iniciais, zera fases
@ ===========================================================================
.type b4_init, %function
b4_init:
    push    {r4, r5, lr}
    ldr     r4, =layer_weights
    ldr     r5, =g_adapt_w
    ldmia   r4, {r0, r1, r2, r3}
    stmia   r5!, {r0, r1, r2, r3}
    add     r4, r4, #16
    ldmia   r4, {r0, r1, r2}
    stmia   r5, {r0, r1, r2}
    ldr     r4, =g_phases
    mov     r0, #0
    mov     r1, #0
    mov     r2, #0
    mov     r3, #0
    stmia   r4!, {r0, r1, r2, r3}
    stmia   r4, {r0, r1, r2}
    mov     r0, #0
    ldr     r1, =g_iter_count
    str     r0, [r1]
    pop     {r4, r5, pc}

@ ===========================================================================
@ sin_q16 — aproximação sin(x) para x em Q16.16
@ Série: sin(x) ≈ x - x^3/6 + x^5/120
@ r0 = x (Q16.16) → r0 = sin(x) (Q16.16)
@ ===========================================================================
.type sin_q16, %function
sin_q16:
    push    {r4, r5, r6, lr}

    mov     r4, r0          @ x

    @ reduz para [-pi, pi] via mod 2pi
    ldr     r1, =Q16_2PI
    @ divisão inteira simples (sem FP)
    mov     r2, r4
    mov     r3, #0
.Smod:
    cmp     r2, r1
    subge   r2, r2, r1
    bge     .Smod
    mov     r4, r2

    @ x^2 (Q16.16 * Q16.16 → Q32.32 → shift 16 → Q16.16)
    umull   r5, r6, r4, r4      @ x^2
    lsr     r5, r5, #16
    orr     r5, r5, r6, lsl #16 @ r5 = x^2 Q16.16

    @ x^3 = x * x^2
    umull   r2, r3, r4, r5
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16 @ r2 = x^3 Q16.16

    @ x^3/6
    ldr     r3, =Q16_INV6
    umull   r6, r1, r2, r3
    lsr     r6, r6, #16
    orr     r6, r6, r1, lsl #16 @ r6 = x^3/6 Q16.16

    @ x^5 = x^3 * x^2
    umull   r1, r3, r2, r5
    lsr     r1, r1, #16
    orr     r1, r1, r3, lsl #16 @ r1 = x^5 Q16.16

    @ x^5/120
    ldr     r3, =Q16_INV120
    umull   r2, r3, r1, r3
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16 @ r2 = x^5/120 Q16.16

    @ sin(x) = x - x^3/6 + x^5/120
    sub     r0, r4, r6
    add     r0, r0, r2

    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ compute_layers — calcula senoide de cada camada, acumula em g_overlap_out
@ ===========================================================================
.type compute_layers, %function
compute_layers:
    push    {r4, r5, r6, r7, r8, r9, lr}

    ldr     r4, =g_phases
    ldr     r5, =layer_freqs
    ldr     r6, =g_adapt_w
    ldr     r7, =g_overlap_out
    mov     r8, #0              @ layer index

.Blayer_loop:
    cmp     r8, #N_LAYERS
    beq     .Blayer_done

    @ fase += freq[i]
    ldr     r0, [r4, r8, lsl #2]    @ fase atual
    ldr     r1, [r5, r8, lsl #2]    @ freq[i]
    add     r0, r0, r1
    @ wrap mod Q16_2PI
    ldr     r1, =Q16_2PI
.Bwrap:
    cmp     r0, r1
    subge   r0, r0, r1
    bge     .Bwrap
    str     r0, [r4, r8, lsl #2]    @ salva nova fase

    @ sin(fase)
    bl      sin_q16                  @ r0 = sin Q16.16

    @ * peso[i]
    ldr     r1, [r6, r8, lsl #2]
    umull   r2, r3, r0, r1
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16

    str     r2, [r7, r8, lsl #2]    @ overlap_out[i] = sin * peso

    add     r8, r8, #1
    b       .Blayer_loop

.Blayer_done:
    pop     {r4, r5, r6, r7, r8, r9, pc}

@ ===========================================================================
@ adapt_weights — atualiza pesos: w[i] = 0.75*w[i] + 0.25*|sin_out[i]|
@ ===========================================================================
.type adapt_weights, %function
adapt_weights:
    push    {r4, r5, r6, r7, lr}

    ldr     r4, =g_adapt_w
    ldr     r5, =g_overlap_out
    mov     r6, #0

.Badapt:
    cmp     r6, #N_LAYERS
    beq     .Badapt_done

    ldr     r0, [r4, r6, lsl #2]    @ w_old
    ldr     r1, [r5, r6, lsl #2]    @ sin_out

    @ w = 0.75*w_old + 0.25*sin_out
    ldr     r7, =49152              @ 0.75 Q16.16
    umull   r2, r3, r0, r7
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16

    ldr     r7, =16384              @ 0.25 Q16.16
    umull   r3, r7, r1, r7
    lsr     r3, r3, #16
    orr     r3, r3, r7, lsl #16

    add     r0, r2, r3
    str     r0, [r4, r6, lsl #2]

    add     r6, r6, #1
    b       .Badapt

.Badapt_done:
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ neon_layer_mul — multiplica pesos x overlap via NEON e grava g_final_vec
@ ===========================================================================
.type neon_layer_mul, %function
neon_layer_mul:
    push    {r4, r5, lr}
    vpush   {q0-q3}

    ldr     r4, =g_adapt_w
    ldr     r5, =g_overlap_out

    @ carrega 4 pesos + 4 overlap
    vld1.32 {q0}, [r4]!         @ weights[0..3]
    vld1.32 {q1}, [r5]!         @ overlap[0..3]

    @ produto elemento a elemento Q16.16
    vmull.s32 q2, d0, d2
    vshrn.s64 d4, q2, #16
    vmull.s32 q2, d1, d3
    vshrn.s64 d5, q2, #16

    ldr     r4, =g_final_vec
    vst1.32 {q2}, [r4]!

    @ carrega os 3 restantes (sem NEON para evitar overrun)
    ldr     r4, =g_adapt_w
    add     r4, r4, #16
    ldr     r5, =g_overlap_out
    add     r5, r5, #16
    ldr     r0, =g_final_vec
    add     r0, r0, #16

    mov     r6, #3
.Bscalar:
    cmp     r6, #0
    beq     .Bscalar_done
    ldr     r1, [r4], #4
    ldr     r2, [r5], #4
    umull   r3, r7, r1, r2
    lsr     r3, r3, #16
    orr     r3, r3, r7, lsl #16
    str     r3, [r0], #4
    subs    r6, r6, #1
    b       .Bscalar

.Bscalar_done:
    vpop    {q0-q3}
    pop     {r4, r5, pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type ws4, %function
ws4:
    push    {lr}
    mov     r2, r1
    mov     r1, r0
    mov     r0, #STDOUT
    mov     r7, #SYS_WRITE
    swi     #0
    pop     {pc}

.type print_hex32_b4, %function
print_hex32_b4:
    push    {r4, r5, lr}
    mov     r4, r0
    ldr     r5, =g_hex_b4
    ldr     r2, =hex_t4
    mov     r1, #28
.Ph4:
    lsr     r0, r4, r1
    and     r0, r0, #0xF
    ldrb    r0, [r2, r0]
    strb    r0, [r5], #1
    subs    r1, r1, #4
    bge     .Ph4
    mov     r0, #'\n'
    strb    r0, [r5]
    ldr     r0, =g_hex_b4
    mov     r1, #9
    bl      ws4
    pop     {r4, r5, pc}
