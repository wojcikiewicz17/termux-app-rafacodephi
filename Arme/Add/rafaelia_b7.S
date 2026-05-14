@ ===========================================================================
@ RAFAELIA B7 — Hz-AS-MEMORY + 4-CYCLE COMMIT GATE + TOROIDAL ROUTING
@ ARM32 · Cortex-A53 · zero deps · semáforo via atomic ops
@
@ CONCEITO:
@   Cada core vCPU tem uma "frequência de ressonância" que determina
@   em qual camada de memória ele "pensa melhor".
@   Alta hz → L1 (curto burst, hot data, 4 ciclos latência)
@   Média hz → L2 (256KB, 12 ciclos)
@   Baixa hz → RAM (80ns)
@
@   Roteamento toroidal: o vetor de estado 7D determina para qual core
@   o próximo pacote de dados deve ser enviado (traversal toroidal).
@   gcd(step, N_VCPU) = 1 garante cobertura total.
@
@   Commit gate: 4 fases atômicas por posição
@     LOAD → PROCESS → VERIFY → COMMIT
@   Fail-safe: se VERIFY falha, rollback para snapshot anterior.
@
@ Compilar:
@   as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b7.S -o b7.o
@   ld b7.o -o rafaelia_b7
@ ===========================================================================

.equ SYS_EXIT,  1
.equ SYS_WRITE, 4
.equ SYS_MMAP2, 192
.equ STDOUT,    1
.equ PROT_RW,   3
.equ MAP_ANON,  0x22

@ Constantes geométricas Q16.16
.equ SPIRAL_Q16,  56755
.equ PHI_Q16,     105965
.equ SQRT3_2_Q16, 56755    @ = SPIRAL_Q16
.equ PERIOD,      42
.equ N_VCPU,      8
.equ TORUS_DIM,   7

@ Commit gate fases
.equ CG_LOAD,    0x1
.equ CG_PROCESS, 0x2
.equ CG_VERIFY,  0x4
.equ CG_COMMIT,  0x8
.equ CG_ALL,     0xF

@ Layers de memória
.equ L_L1,   0
.equ L_L2,   1
.equ L_BUF,  2
.equ L_RAM,  3
.equ N_LAY,  4

@ Hz threshold Q16.16 por layer
.equ THR_L1,  50000   @ hz > 50000 → L1
.equ THR_L2,  38000   @ hz > 38000 → L2
.equ THR_BUF, 25000   @ hz > 25000 → BUF
                       @ else → RAM

@ Stride toroidal (gcd(3, 8) = 1 → cobre todos os cores)
.equ TORUS_STRIDE, 3

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_b7:     .ascii "B7: Hz-MEM+GATE+TORUS\n"
.equ msg_b7_len, . - msg_b7

msg_cg_run: .ascii "COMMIT_GATE:42cycles\n"
.equ msg_cg_run_len, . - msg_cg_run

msg_route:  .ascii "TORUS_ROUTE:\n"
.equ msg_route_len, . - msg_route

msg_rb:     .ascii "ROLLBACK:detected\n"
.equ msg_rb_len, . - msg_rb

msg_stats:  .ascii "STATS:"
.equ msg_stats_len, . - msg_stats

msg_done7:  .ascii "B7:DONE\n"
.equ msg_done7_len, . - msg_done7

hex_t7:     .ascii "0123456789ABCDEF"

@ vCPU hz Q16.16 (Helio G25: 2 clusters, 4+4 cores)
.align 4
g_vcpu_hz_ro:
    .long 58000, 58000, 58000, 50296   @ cluster0 (2GHz)
    .long 43500, 43500, 37709, 26836   @ cluster1 (1.5GHz)

@ Layer thresholds Q16.16
.align 4
g_layer_thr:
    .long THR_L1, THR_L2, THR_BUF, 0

@ Layer nomes (1 byte index)
g_layer_names:
    .ascii "L1\0L2\0BF\0RM\0"

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

@ Arena 4MB para buffers hierárquicos
.equ ARENA7_SZ, (4*1024*1024)
.align 6
g_arena7_buf:  .space ARENA7_SZ
g_arena7_bump: .space 4

@ Estado 7D de cada core vCPU (8 cores x 7 dims x 4 bytes)
.align 6
g_core_state:  .space N_VCPU * TORUS_DIM * 4

@ Coerência e entropia por core (8 x 2 x 4 bytes)
.align 4
g_core_C:      .space N_VCPU * 4
g_core_H:      .space N_VCPU * 4

@ Layer assignment por core (8 bytes)
g_core_layer:  .space N_VCPU

@ Commit gate: bitmap por core (8 x 4 bytes)
.align 4
g_cg_map:      .space N_VCPU * 4

@ Snapshot para rollback (8 cores x 7 dims x 4 bytes)
.align 6
g_snapshot7:   .space N_VCPU * TORUS_DIM * 4

@ Rota toroidal atual (índice do próximo core)
g_torus_pos:   .space 4

@ Contadores
.align 4
g_commits:     .space 4
g_rollbacks:   .space 4
g_route_steps: .space 4

@ Buffers por layer (apontam para arena)
.align 4
g_lay_ptr:     .space N_LAY * 4
g_lay_sz:      .space N_LAY * 4
g_lay_crc:     .space N_LAY * 4

@ CRC table
.align 6
g_crc7_tab:    .space 256 * 4

@ Scratch
g_hex7:        .space 16

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    @ init
    bl      crc7_build
    bl      arena7_init
    bl      core_state_init
    bl      layer_assign_init
    bl      mem_layers_alloc

    ldr     r0, =msg_b7
    mov     r1, #msg_b7_len
    bl      ws7

    @ 42 ciclos do commit gate
    ldr     r0, =msg_cg_run
    mov     r1, #msg_cg_run_len
    bl      ws7

    bl      run_commit_gate_42

    @ mostra rota toroidal
    ldr     r0, =msg_route
    mov     r1, #msg_route_len
    bl      ws7

    bl      print_torus_route

    @ estatísticas
    ldr     r0, =msg_stats
    mov     r1, #msg_stats_len
    bl      ws7

    ldr     r0, =g_commits
    ldr     r0, [r0]
    bl      ph7

    ldr     r0, =g_rollbacks
    ldr     r0, [r0]
    bl      ph7

    ldr     r0, =msg_done7
    mov     r1, #msg_done7_len
    bl      ws7

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

@ ===========================================================================
@ arena7_init
@ ===========================================================================
.type arena7_init, %function
arena7_init:
    push    {lr}
    ldr     r0, =g_arena7_bump
    mov     r1, #0
    str     r1, [r0]
    pop     {pc}

.type arena7_alloc, %function
arena7_alloc:
    @ r0=bytes r1=align → r0=ptr ou 0
    push    {r4, r5, lr}
    mov     r5, r0
    add     r4, r1, #-1
    ldr     r2, =g_arena7_bump
    ldr     r3, [r2]
    add     r3, r3, r4
    bic     r3, r3, r4           @ alinha
    add     r4, r3, r5
    ldr     r5, =ARENA7_SZ
    cmp     r4, r5
    bgt     .Ba7_oom
    str     r4, [r2]
    ldr     r0, =g_arena7_buf
    add     r0, r0, r3
    pop     {r4, r5, pc}
.Ba7_oom:
    mov     r0, #0
    pop     {r4, r5, pc}

@ ===========================================================================
@ core_state_init — seeds toroidais por core
@ ===========================================================================
.type core_state_init, %function
core_state_init:
    push    {r4, r5, r6, r7, lr}
    ldr     r4, =g_core_state
    ldr     r5, =g_core_C
    ldr     r6, =g_core_H
    mov     r7, #0              @ core index

.Bcsi_loop:
    cmp     r7, #N_VCPU
    beq     .Bcsi_done

    @ ptr ao estado do core
    mov     r0, #28              @ TORUS_DIM * 4
    mul     r2, r7, r0
    add     r2, r4, r2

    @ seed = SPIRAL * core_idx mod 65536
    ldr     r0, =SPIRAL_Q16
    mul     r1, r7, r0
    and     r1, r1, #0xFFFF

    @ preenche 7 dims com cascata Fibonacci-Rafaeliana
    @ d[i] = (d[i-1] * SPIRAL >> 16) + d[i-2] mod 65536
    mov     r0, r1              @ d[-1] = seed
    ldr     r3, =PHI_Q16
    mul     r3, r1, r3
    lsr     r3, r3, #16         @ d[-2] = seed*PHI

    str     r1, [r2, #0]
    str     r3, [r2, #4]

    mov     r8, #2
.Bfib_dim:
    cmp     r8, #7
    beq     .Bfib_done
    @ d[i] = (d[i-1] * SPIRAL + d[i-2]) mod 65536
    ldr     r9,  [r2, r8, lsl #2]   @ tem lixo ainda, usa r0/r3
    ldr     r10, =SPIRAL_Q16
    mul     r9, r0, r10
    lsr     r9, r9, #16
    add     r9, r9, r3
    and     r9, r9, #0xFFFF
    str     r9, [r2, r8, lsl #2]
    mov     r3, r0
    mov     r0, r9
    add     r8, r8, #1
    b       .Bfib_dim
.Bfib_done:

    @ C = 0x8000, H = 0x8000
    mov     r0, #0x8000
    str     r0, [r5, r7, lsl #2]
    str     r0, [r6, r7, lsl #2]

    @ snapshot = copy do estado
    ldr     r8, =g_snapshot7
    mov     r0, #28
    mul     r0, r7, r0
    add     r8, r8, r0
    add     r2, r4, r7
    mov     r0, #28
    mul     r0, r7, r0
    add     r2, r4, r0
    ldmia   r2, {r0, r1, r3}
    stmia   r8!, {r0, r1, r3}
    add     r2, r2, #12
    ldmia   r2, {r0, r1, r3}
    stmia   r8!, {r0, r1, r3}
    ldr     r0, [r2, #12]
    str     r0, [r8]

    add     r7, r7, #1
    b       .Bcsi_loop
.Bcsi_done:
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ layer_assign_init — atribui layer a cada core baseado em hz
@ ===========================================================================
.type layer_assign_init, %function
layer_assign_init:
    push    {r4, r5, lr}
    ldr     r4, =g_vcpu_hz_ro
    ldr     r5, =g_core_layer
    mov     r0, #0

.Blai_loop:
    cmp     r0, #N_VCPU
    beq     .Blai_done
    ldr     r1, [r4, r0, lsl #2]   @ hz

    cmp     r1, #THR_L1
    movgt   r2, #L_L1
    bgt     .Blai_store

    cmp     r1, #THR_L2
    movgt   r2, #L_L2
    bgt     .Blai_store

    cmp     r1, #THR_BUF
    movgt   r2, #L_BUF
    movle   r2, #L_RAM

.Blai_store:
    strb    r2, [r5, r0]
    add     r0, r0, #1
    b       .Blai_loop
.Blai_done:
    pop     {r4, r5, pc}

@ ===========================================================================
@ mem_layers_alloc — aloca buffers para cada layer na arena
@ L1=8KB L2=32KB BUF=64KB RAM=128KB
@ ===========================================================================
.type mem_layers_alloc, %function
mem_layers_alloc:
    push    {r4, r5, lr}
    ldr     r4, =g_lay_ptr
    ldr     r5, =g_lay_sz

    @ L1: 8KB
    ldr     r0, =(8*1024)
    mov     r1, #64
    bl      arena7_alloc
    str     r0, [r4, #0]
    ldr     r0, =(8*1024)
    str     r0, [r5, #0]

    @ L2: 32KB
    ldr     r0, =(32*1024)
    mov     r1, #64
    bl      arena7_alloc
    str     r0, [r4, #4]
    ldr     r0, =(32*1024)
    str     r0, [r5, #4]

    @ BUF: 64KB
    ldr     r0, =(64*1024)
    mov     r1, #64
    bl      arena7_alloc
    str     r0, [r4, #8]
    ldr     r0, =(64*1024)
    str     r0, [r5, #8]

    @ RAM: 128KB
    ldr     r0, =(128*1024)
    mov     r1, #64
    bl      arena7_alloc
    str     r0, [r4, #12]
    ldr     r0, =(128*1024)
    str     r0, [r5, #12]

    @ CRCs iniciais
    ldr     r4, =g_lay_crc
    mov     r0, #0
    str     r0, [r4, #0]
    str     r0, [r4, #4]
    str     r0, [r4, #8]
    str     r0, [r4, #12]

    pop     {r4, r5, pc}

@ ===========================================================================
@ run_commit_gate_42 — 42 ciclos x 8 cores x 4 fases
@ ===========================================================================
.type run_commit_gate_42, %function
run_commit_gate_42:
    push    {r4, r5, r6, r7, r8, r9, r10, r11, lr}

    @ init torus_pos = 0
    ldr     r0, =g_torus_pos
    mov     r1, #0
    str     r1, [r0]

    mov     r4, #PERIOD     @ ciclo outer

.Bcg42_outer:
    cmp     r4, #0
    beq     .Bcg42_outer_done

    @ rota toroidal: próximo core = (torus_pos + STRIDE) mod N_VCPU
    ldr     r5, =g_torus_pos
    ldr     r6, [r5]
    add     r6, r6, #TORUS_STRIDE
    cmp     r6, #N_VCPU
    subge   r6, r6, #N_VCPU
    str     r6, [r5]        @ atualiza
    @ r6 = core_idx para este ciclo

    @ incrementa route_steps
    ldr     r0, =g_route_steps
    ldr     r1, [r0]
    add     r1, r1, #1
    str     r1, [r0]

    @ ──────────────── FASE 1: LOAD ─────────────────────────────
    @ snapshot do estado do core
    ldr     r7, =g_core_state
    mov     r0, #28
    mul     r0, r6, r0
    add     r7, r7, r0          @ &g_core_state[core]

    ldr     r8, =g_snapshot7
    mov     r0, #28
    mul     r0, r6, r0
    add     r8, r8, r0          @ &g_snapshot7[core]

    ldmia   r7, {r0, r1, r2, r3, r9, r10, r11}
    stmia   r8, {r0, r1, r2, r3, r9, r10, r11}

    @ seta bit LOAD no bitmap do core
    ldr     r0, =g_cg_map
    ldr     r1, [r0, r6, lsl #2]
    orr     r1, r1, #CG_LOAD
    str     r1, [r0, r6, lsl #2]

    @ ──────────────── FASE 2: PROCESS ──────────────────────────
    @ EMA toroidal: s[i] = 0.75*s[i] + 0.25*(s[(i+1)%7])
    @ usa NEON para os 4 primeiros dims
    vpush   {q0-q2}

    vld1.32 {q0}, [r7]      @ s[0..3]

    @ q1 = rotacionado: {s[1], s[2], s[3], s[4]}
    ldr     r0, [r7, #4]
    ldr     r1, [r7, #8]
    ldr     r2, [r7, #12]
    ldr     r3, [r7, #16]
    vmov    q1, q0           @ copia
    vext.8  q1, q0, q0, #4  @ rota 1 lane

    @ EMA NEON: 0.75*q0 + 0.25*q1
    vmov.i32 q2, #49152
    @ como NEON ARM32 neon-vfpv4 não tem vshll/vshrn direto para int,
    @ usamos float32 temporariamente
    vcvt.f32.s32 q0, q0
    vcvt.f32.s32 q1, q1
    vmov.f32 q2, #7.5e-1    @ 0.75 como float
    vmul.f32 q0, q0, q2
    vmov.f32 q2, #2.5e-1    @ 0.25
    vmla.f32 q0, q1, q2
    vcvt.s32.f32 q0, q0
    vst1.32 {q0}, [r7]

    @ atualiza dims 4..6 escalarmente
    ldr     r0, [r7, #16]   @ s[4]
    ldr     r1, [r7, #20]   @ s[5]
    ldr     r2, [r7, #24]   @ s[6]
    ldr     r9, [r7, #0]    @ s[0] (input circular)
    @ s[4] = (3*s[4] + s[5]) / 4
    add     r3, r0, r0, lsl #1  @ 3*s[4]
    add     r3, r3, r1
    lsr     r3, r3, #2
    str     r3, [r7, #16]
    @ s[5] = (3*s[5] + s[6]) / 4
    add     r3, r1, r1, lsl #1
    add     r3, r3, r2
    lsr     r3, r3, #2
    str     r3, [r7, #20]
    @ s[6] = (3*s[6] + s[0]) / 4
    add     r3, r2, r2, lsl #1
    add     r3, r3, r9
    lsr     r3, r3, #2
    str     r3, [r7, #24]

    vpop    {q0-q2}

    @ seta PROCESS
    ldr     r0, =g_cg_map
    ldr     r1, [r0, r6, lsl #2]
    orr     r1, r1, #CG_PROCESS
    str     r1, [r0, r6, lsl #2]

    @ ──────────────── FASE 3: VERIFY (CRC) ─────────────────────
    mov     r0, r7              @ ptr ao estado
    mov     r1, #28
    bl      crc7_compute        @ r0 = crc

    @ verifica: crc != 0 E estado[0] < 0x10000 (sanidade Q16.16)
    cmp     r0, #0
    beq     .Bcg42_rollback
    ldr     r1, [r7]
    ldr     r2, =0x10000
    cmp     r1, r2
    bge     .Bcg42_rollback

    @ seta VERIFY
    ldr     r1, =g_cg_map
    ldr     r2, [r1, r6, lsl #2]
    orr     r2, r2, #CG_VERIFY
    str     r2, [r1, r6, lsl #2]

    @ ──────────────── FASE 4: COMMIT ───────────────────────────
    ldr     r1, =g_cg_map
    ldr     r2, [r1, r6, lsl #2]
    and     r3, r2, #CG_ALL
    cmp     r3, #CG_ALL
    bne     .Bcg42_rollback     @ incompleto

    @ commit ok: reseta bitmap, incrementa commits
    mov     r2, #0
    str     r2, [r1, r6, lsl #2]

    ldr     r0, =g_commits
    ldr     r1, [r0]
    add     r1, r1, #1
    str     r1, [r0]

    @ update C e H do core
    ldr     r0, =g_core_C
    ldr     r1, [r0, r6, lsl #2]
    @ C = 0.75*C + 0.25*hz_normalized
    ldr     r2, =g_vcpu_hz_ro
    ldr     r2, [r2, r6, lsl #2]   @ hz
    lsr     r2, r2, #1              @ hz/2 como C_in (normalização)
    add     r1, r1, r1, lsl #1     @ 3*C
    add     r1, r1, r2
    lsr     r1, r1, #2             @ (3*C + C_in)/4
    str     r1, [r0, r6, lsl #2]

    b       .Bcg42_next

.Bcg42_rollback:
    @ restaura snapshot
    ldmia   r8, {r0, r1, r2, r3, r9, r10, r11}
    stmia   r7, {r0, r1, r2, r3, r9, r10, r11}

    @ reseta bitmap
    ldr     r0, =g_cg_map
    mov     r1, #0
    str     r1, [r0, r6, lsl #2]

    ldr     r0, =g_rollbacks
    ldr     r1, [r0]
    add     r1, r1, #1
    str     r1, [r0]

    @ imprime aviso de rollback a cada 7 rollbacks
    and     r1, r1, #7
    cmp     r1, #0
    bne     .Bcg42_next
    ldr     r0, =msg_rb
    mov     r1, #msg_rb_len
    bl      ws7

.Bcg42_next:
    subs    r4, r4, #1
    b       .Bcg42_outer

.Bcg42_outer_done:
    pop     {r4, r5, r6, r7, r8, r9, r10, r11, pc}

@ ===========================================================================
@ print_torus_route — imprime a sequência de cores visitados em 8 passos
@ com stride 3: 0→3→6→1→4→7→2→5→0
@ ===========================================================================
.type print_torus_route, %function
print_torus_route:
    push    {r4, r5, lr}
    mov     r4, #0          @ current pos
    mov     r5, #0          @ step count

.Bptr_loop:
    cmp     r5, #N_VCPU
    beq     .Bptr_done

    @ imprime core index como hex 1 nibble
    ldr     r0, =g_hex7
    ldr     r1, =hex_t7
    ldrb    r2, [r1, r4]
    strb    r2, [r0]
    mov     r2, #' '
    strb    r2, [r0, #1]
    mov     r0, r0
    mov     r1, #2
    bl      ws7

    @ avança
    add     r4, r4, #TORUS_STRIDE
    cmp     r4, #N_VCPU
    subge   r4, r4, #N_VCPU
    add     r5, r5, #1
    b       .Bptr_loop

.Bptr_done:
    @ newline
    ldr     r0, =g_hex7
    mov     r1, #'\n'
    strb    r1, [r0]
    mov     r1, #1
    bl      ws7
    pop     {r4, r5, pc}

@ ===========================================================================
@ CRC7
@ ===========================================================================
.type crc7_build, %function
crc7_build:
    push    {r4, r5, r6, r7, lr}
    ldr     r4, =g_crc7_tab
    mov     r5, #0
.Bcb7:
    cmp     r5, #256
    beq     .Bcb7d
    mov     r0, r5
    mov     r6, #8
.Bcb7b:
    tst     r0, #1
    lsr     r0, r0, #1
    ldrne   r7, =0x82F63B78
    eorne   r0, r0, r7
    subs    r6, r6, #1
    bne     .Bcb7b
    str     r0, [r4, r5, lsl #2]
    add     r5, r5, #1
    b       .Bcb7
.Bcb7d:
    pop     {r4, r5, r6, r7, pc}

.type crc7_compute, %function
crc7_compute:
    push    {r4, r5, r6, r7, r8, lr}
    mov     r4, r0
    mov     r5, r1
    mvn     r6, #0
    ldr     r7, =g_crc7_tab
.Bcc7:
    cmp     r5, #0
    beq     .Bcc7d
    ldrb    r0, [r4], #1
    eor     r8, r6, r0
    and     r8, r8, #0xFF
    ldr     r0, [r7, r8, lsl #2]
    lsr     r6, r6, #8
    eor     r6, r6, r0
    subs    r5, r5, #1
    b       .Bcc7
.Bcc7d:
    mvn     r0, r6
    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type ws7, %function
ws7:
    push    {lr}
    mov     r2, r1
    mov     r1, r0
    mov     r0, #STDOUT
    mov     r7, #SYS_WRITE
    swi     #0
    pop     {pc}

.type ph7, %function
ph7:
    push    {r4, r5, lr}
    mov     r4, r0
    ldr     r5, =g_hex7
    ldr     r2, =hex_t7
    mov     r1, #28
.Bph7:
    lsr     r0, r4, r1
    and     r0, r0, #0xF
    ldrb    r0, [r2, r0]
    strb    r0, [r5], #1
    subs    r1, r1, #4
    bge     .Bph7
    mov     r0, #'\n'
    strb    r0, [r5]
    ldr     r0, =g_hex7
    mov     r1, #9
    bl      ws7
    pop     {r4, r5, pc}
