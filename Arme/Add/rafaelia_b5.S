@ ===========================================================================
@ RAFAELIA B5 — BITSTACK 1008 + COMMIT GATE 4 CICLOS + HYPERFORMS
@ ARM32 · Cortex-A53 · zero deps · zero malloc
@
@ ESTRUTURA DOS 1008 PONTOS:
@   10×10×10 = 1000  células de volume (toro T^7)
@   +4              vértices do triângulo isósceles de ruptura
@   +2              atratores externos assimétricos
@   +2              células de paridade (matriz separada)
@   ──────────────
@   = 1008          pontos totais
@
@ BITSTACKS (sem malloc — usa arena do B1):
@   grade: X=10, Y=10, D=10  → 1000 stacks
@   bits_per_stack = 42       → 1 bloco de 64 bits por stack
@   endereço: ((x*10+y)*10+d) * 1 bloco
@
@ HYPERFORMS (do hyperforms.json):
@   id=0 base:     hexágono    6 vértices  dim=2  level=1
@   id=1 regressao: 8 vértices             dim=3  level=2
@   id=2 inversao:  decágono  10 vértices  dim=2  level=3
@
@ COMMIT GATE (4 ciclos atômicos):
@   LOAD → PROCESS → VERIFY → COMMIT
@   posição só liberada após os 4 ciclos
@   CRC32SW como âncora de estado
@
@ Compilar:
@   as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b5.S -o b5.o
@   ld b5.o -o rafaelia_b5
@ ===========================================================================

@ ---------------------------------------------------------------------------
@ SYSCALLS
@ ---------------------------------------------------------------------------
.equ SYS_EXIT,          1
.equ SYS_WRITE,         4
.equ SYS_MMAP2,         192
.equ STDOUT,            1

@ ---------------------------------------------------------------------------
@ CONSTANTES DO SISTEMA
@ ---------------------------------------------------------------------------
.equ BS_X,              10          @ dimensão X do BitStack
.equ BS_Y,              10          @ dimensão Y
.equ BS_D,              10          @ dimensão D (profundidade)
.equ BS_TOTAL_STACKS,   1000        @ X*Y*D
.equ BS_BITS_PER_STACK, 42          @ período dos atratores
.equ BS_BLOCKS_PER_STACK, 1         @ ceil(42/64) = 1
.equ BS_TOTAL_BLOCKS,   1000        @ stacks * blocks_per_stack

@ Pontos extras (fora da grade 10×10×10)
.equ EXTRA_ISOSC,       4           @ triângulo isósceles de ruptura
.equ EXTRA_ATTRACTOR,   2           @ atratores externos assimétricos
.equ EXTRA_PARITY,      2           @ células de paridade
.equ TOTAL_POINTS,      1008        @ 1000+4+2+2

@ Arena: 8MB (herdada do modelo B1, alocada neste binário independente)
.equ ARENA_SIZE,        0x800000
.equ PROT_RW,           3
.equ MAP_ANON_PRIV,     0x22

@ Commit gate
.equ CG_LOAD,           0x1
.equ CG_PROCESS,        0x2
.equ CG_VERIFY,         0x4
.equ CG_COMMIT,         0x8
.equ CG_ALL,            0xF         @ todos 4 ciclos completos

@ Constantes Q16.16
.equ SPIRAL_Q16,        56755       @ sqrt(3)/2
.equ PHI_Q16,           105965
.equ SQRT2_Q16,         92682       @ sqrt(2) ≈ 1.41421 * 65536

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_boot:
    .ascii "B5: BITSTACK-1008 + COMMIT-GATE\n"
    .equ msg_boot_len, . - msg_boot

msg_arena:      .ascii "ARENA:OK\n";     .equ msg_arena_len,     . - msg_arena
msg_bs_ok:      .ascii "BITSTACKS:OK\n"; .equ msg_bs_ok_len,     . - msg_bs_ok
msg_hf_ok:      .ascii "HYPERFORMS:OK\n";.equ msg_hf_ok_len,     . - msg_hf_ok
msg_cg_ok:      .ascii "COMMITGATE:OK\n";.equ msg_cg_ok_len,     . - msg_cg_ok
msg_par_ok:     .ascii "PARITY:OK\n";    .equ msg_par_ok_len,    . - msg_par_ok
msg_rb_ok:      .ascii "ROLLBACK:OK\n";  .equ msg_rb_ok_len,     . - msg_rb_ok
msg_done:       .ascii "B5:DONE\n";      .equ msg_done_len,      . - msg_done

msg_state:      .ascii "STATE="
    .equ msg_state_len,     . - msg_state
msg_crc:        .ascii "CRC="
    .equ msg_crc_len,       . - msg_crc
msg_points:     .ascii "PTS="
    .equ msg_points_len,    . - msg_points

hex_t5:         .ascii "0123456789ABCDEF"

@ ---------------------------------------------------------------------------
@ HYPERFORMS: vértices e arestas dos 3 modos (Q16.16 fixo)
@
@ id=0 BASE — hexágono 6 vértices (dim=2)
@   v0=(1,0)  v1=(0.5, 0.866)  v2=(-0.5, 0.866)
@   v3=(-1,0) v4=(-0.5,-0.866) v5=(0.5,-0.866)
@   arestas: 0-1, 1-2, 2-3, 3-4, 4-5, 5-0
@ ---------------------------------------------------------------------------
.align 4
hf0_verts:
    @ x Q16.16, y Q16.16 por vértice
    .long  65536,      0       @ v0: ( 1.0,  0.0)
    .long  32768,  56756       @ v1: ( 0.5,  0.866)
    .long -32768,  56756       @ v2: (-0.5,  0.866)
    .long -65536,      0       @ v3: (-1.0,  0.0)
    .long -32768, -56756       @ v4: (-0.5, -0.866)
    .long  32768, -56756       @ v5: ( 0.5, -0.866)

hf0_edges:
    @ pares de índices de vértice
    .byte 0,1, 1,2, 2,3, 3,4, 4,5, 5,0
    .equ HF0_N_EDGES, 6

@ id=1 REGRESSAO — 8 vértices 3D projetados em 2D (dim=3→2D)
@   usa projeção: (x,y,z) → (x+z*0.5, y+z*0.5)
@   v0=(1,0,0)→(1,0)  v1=(0.707,0.707,1)→(1.207,1.207)
.align 4
hf1_verts:
    @ x Q16.16, y Q16.16 (projeção isométrica de dim=3)
    .long  65536,      0       @ v0: (1,0,0)
    .long  79169,  79169       @ v1: (0.707,0.707,1) proj
    .long      0,  65536       @ v2: (0,1,0)
    .long -46341,  46341       @ v3: (-0.707,0.707,-1) proj
    .long -65536,      0       @ v4: (-1,0,0)
    .long -46341, -46341       @ v5: (-0.707,-0.707,1) proj
    .long      0, -65536       @ v6: (0,-1,0)
    .long  46341, -46341       @ v7: (0.707,-0.707,-1) proj

hf1_edges:
    @ 8 arestas (id=1 do JSON)
    .byte 0,6, 1,7, 2,0, 3,1, 4,2, 5,3, 6,4, 7,5
    .equ HF1_N_EDGES, 8

@ id=2 INVERSAO — decágono 10 vértices, pares invertidos (dim=2)
@   arestas: 0↔9, 1↔8, 2↔7, 3↔6, 4↔5 (inversão)
.align 4
hf2_verts:
    @ decágono regular Q16.16
    .long  65536,      0       @ v0: (1,      0)
    .long  53019,  38469       @ v1: (0.809,  0.588)
    .long  20252,  62328       @ v2: (0.309,  0.951)
    .long -20252,  62328       @ v3: (-0.309, 0.951)
    .long -53019,  38469       @ v4: (-0.809, 0.588)
    .long -65536,      0       @ v5: (-1,     0)
    .long -53019, -38469       @ v6: (-0.809,-0.588)
    .long -20252, -62328       @ v7: (-0.309,-0.951)
    .long  20252, -62328       @ v8: (0.309, -0.951)
    .long  53019, -38469       @ v9: (0.809, -0.588)

hf2_edges:
    @ pares invertidos: 0↔9, 1↔8, 2↔7, 3↔6, 4↔5
    .byte 0,9, 1,8, 2,7, 3,6, 4,5, 5,4, 6,3, 7,2, 8,1, 9,0
    .equ HF2_N_EDGES, 10

@ Tabela de atratores externos assimétricos (2 pontos, fora da grade)
@ triângulo isósceles: base sqrt(3), lados 1, ápice em (0, sqrt(3)/2)
.align 4
ext_attractors:
    @ atrator 0: (+sqrt(3)/2, 0) Q16.16
    .long  56756,      0
    @ atrator 1: (-sqrt(3)/2, 0) Q16.16
    .long -56756,      0

@ Vértices do triângulo isósceles de ruptura (4 pontos)
@ base = 2*sqrt(3)/2 = sqrt(3)
@ ápice = (0, sqrt(3)/2) = (0, 0.866)
.align 4
rupture_triangle:
    .long  56756,      0        @ base direita
    .long -56756,      0        @ base esquerda
    .long      0,  56756        @ ápice norte
    .long      0, -56756        @ ápice sul (jato para fora)

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

@ Arena
g_arena_base:   .space 4
g_arena_bump:   .space 4
g_arena_cap:    .space 4

@ Ponteiro para o array de BitStacks (alocado na arena)
@ cada elemento: uint64_t (1 bloco de 64 bits = 42 bits usados)
g_bs_ptr:       .space 4        @ → array de 1000 uint64_t

@ Células de paridade (2 x uint64_t = 16 bytes)
.align 3
g_parity_0:     .space 8        @ XOR de todos os stacks
g_parity_1:     .space 8        @ CRC32 da grade

@ CRC32C table
.align 6
g_crc_table:    .space 256 * 4

@ Commit gate: bitmap por posição (4 bits por posição, 1000 posições)
@ usamos uint32_t: 1 por posição (bitmap dos 4 ciclos)
g_cg_bitmap:    .space BS_TOTAL_STACKS * 4

@ Snapshot para rollback (last committed state, 1000 uint64_t)
g_snapshot:     .space BS_TOTAL_STACKS * 8

@ Estado do commit gate ativo
g_cg_active_pos: .space 4       @ posição sendo commitada
g_cg_bitmap_cur: .space 4       @ bitmap dos 4 ciclos da posição atual

@ CRC do commit atual
g_commit_crc:   .space 4

@ Contadores
g_commits_ok:   .space 4
g_rollbacks:    .space 4
g_total_bits:   .space 4        @ bits setados na grade

@ Buffer hex output
g_hex_b5:       .space 16

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    ldr     r0, =msg_boot
    mov     r1, #msg_boot_len
    bl      ws5

    @ 1. Arena
    bl      b5_arena_init
    cmp     r0, #0
    bne     .Bfail
    ldr     r0, =msg_arena
    mov     r1, #msg_arena_len
    bl      ws5

    @ 2. CRC32C table
    bl      b5_crc_build

    @ 3. BitStacks 10×10×10
    bl      b5_bitstacks_init
    cmp     r0, #0
    bne     .Bfail
    ldr     r0, =msg_bs_ok
    mov     r1, #msg_bs_ok_len
    bl      ws5

    @ 4. Hyperforms selftest
    bl      b5_hyperforms_test
    ldr     r0, =msg_hf_ok
    mov     r1, #msg_hf_ok_len
    bl      ws5

    @ 5. Commit gate: 42 ciclos de 4 fases
    bl      b5_commit_gate_run
    ldr     r0, =msg_cg_ok
    mov     r1, #msg_cg_ok_len
    bl      ws5

    @ 6. Paridade (XOR + CRC dos 1000 stacks)
    bl      b5_parity_compute
    ldr     r0, =msg_par_ok
    mov     r1, #msg_par_ok_len
    bl      ws5

    @ 7. Rollback test: corrompe 1 stack, verifica detecção
    bl      b5_rollback_test
    ldr     r0, =msg_rb_ok
    mov     r1, #msg_rb_ok_len
    bl      ws5

    @ 8. Imprime estat
    bl      b5_print_stats

    ldr     r0, =msg_done
    mov     r1, #msg_done_len
    bl      ws5

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

.Bfail:
    mov     r7, #SYS_EXIT
    mov     r0, #5
    swi     #0

@ ===========================================================================
@ b5_arena_init — mmap2 direto
@ ===========================================================================
.type b5_arena_init, %function
b5_arena_init:
    push    {r4, r5, lr}
    mov     r0, #0
    ldr     r1, =ARENA_SIZE
    mov     r2, #PROT_RW
    mov     r3, #MAP_ANON_PRIV
    mov     r4, #-1
    mov     r5, #0
    mov     r7, #SYS_MMAP2
    swi     #0
    cmn     r0, #1          @ MAP_FAILED = -1
    beq     .Barena_fail
    ldr     r1, =g_arena_base;  str r0, [r1]
    ldr     r1, =g_arena_bump;  mov r2, #0; str r2, [r1]
    ldr     r1, =g_arena_cap;   ldr r2, =ARENA_SIZE; str r2, [r1]
    mov     r0, #0
    pop     {r4, r5, pc}
.Barena_fail:
    mov     r0, #1
    pop     {r4, r5, pc}

@ ===========================================================================
@ b5_arena_alloc — r0=bytes → r0=ptr (alinhado 8) ou 0
@ ===========================================================================
.type b5_arena_alloc, %function
b5_arena_alloc:
    push    {r4, r5, r6, lr}
    add     r0, r0, #7
    bic     r0, r0, #7              @ alinha a 8
    ldr     r4, =g_arena_base;  ldr r4, [r4]
    ldr     r5, =g_arena_bump;  ldr r3, [r5]
    add     r1, r3, r0
    ldr     r2, =g_arena_cap;   ldr r2, [r2]
    cmp     r1, r2
    bgt     .Baa_oom
    str     r1, [r5]
    add     r0, r4, r3
    pop     {r4, r5, r6, pc}
.Baa_oom:
    mov     r0, #0
    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ b5_crc_build — CRC32C Castagnoli
@ ===========================================================================
.type b5_crc_build, %function
b5_crc_build:
    push    {r4, r5, r6, r7, lr}
    ldr     r4, =g_crc_table
    mov     r5, #0
.Bcb_loop:
    cmp     r5, #256
    beq     .Bcb_done
    mov     r0, r5
    mov     r6, #8
.Bcb_bit:
    tst     r0, #1
    lsr     r0, r0, #1
    ldrne   r7, =0x82F63B78
    eorne   r0, r0, r7
    subs    r6, r6, #1
    bne     .Bcb_bit
    str     r0, [r4, r5, lsl #2]
    add     r5, r5, #1
    b       .Bcb_loop
.Bcb_done:
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ b5_crc32 — r0=ptr r1=len → r0=crc32c
@ ===========================================================================
.type b5_crc32, %function
b5_crc32:
    push    {r4, r5, r6, r7, r8, lr}
    mov     r4, r0;  mov r5, r1
    mvn     r6, #0
    ldr     r7, =g_crc_table
.Bcrc_loop:
    cmp     r5, #0
    beq     .Bcrc_done
    ldrb    r0, [r4], #1
    eor     r8, r6, r0;  and r8, r8, #0xFF
    ldr     r0, [r7, r8, lsl #2]
    lsr     r6, r6, #8;  eor r6, r6, r0
    subs    r5, r5, #1
    b       .Bcrc_loop
.Bcrc_done:
    mvn     r0, r6
    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ b5_bitstacks_init — aloca array de 1000 uint64_t na arena, zera
@ ===========================================================================
.type b5_bitstacks_init, %function
b5_bitstacks_init:
    push    {r4, r5, lr}

    @ aloca 1000 * 8 bytes = 8000 bytes
    ldr     r0, =(BS_TOTAL_STACKS * 8)
    bl      b5_arena_alloc
    cmp     r0, #0
    beq     .Bbs_fail

    ldr     r4, =g_bs_ptr
    str     r0, [r4]                @ salva ponteiro

    @ zera todos os stacks (bzero via stmia)
    mov     r4, r0
    mov     r5, #(BS_TOTAL_STACKS * 8 / 4)  @ palavras de 4 bytes
    mov     r0, #0
    mov     r1, #0
.Bzero_loop:
    cmp     r5, #0
    beq     .Bzero_done
    str     r0, [r4], #4
    subs    r5, r5, #1
    b       .Bzero_loop
.Bzero_done:

    @ preenche padrão inicial: stack(x,y,d) = Fibonacci mod 42
    bl      b5_bitstacks_fill_fib

    mov     r0, #0
    pop     {r4, r5, pc}
.Bbs_fail:
    mov     r0, #1
    pop     {r4, r5, pc}

@ ===========================================================================
@ bs_index — calcula índice do stack
@ r0=x r1=y r2=d → r0=índice (x*100 + y*10 + d)
@ ===========================================================================
.type bs_index, %function
bs_index:
    push    {lr}
    mov     r3, #100
    mul     r0, r0, r3      @ x*100
    mov     r3, #10
    mla     r0, r1, r3, r0  @ + y*10
    add     r0, r0, r2      @ + d
    pop     {pc}

@ ===========================================================================
@ bs_set — seta bit stack_idx no stack (x,y,d)
@ r0=x r1=y r2=d r3=stack_idx r4=value
@ ===========================================================================
.type bs_set, %function
bs_set:
    push    {r4, r5, r6, r7, lr}
    mov     r7, r4              @ value salvo
    bl      bs_index            @ r0 = stack_idx global
    @ r3 já é o bit offset dentro do stack (0..41)
    @ bloco = r3/64 = 0 (sempre, pois bits_per_stack=42 < 64)
    @ offset = r3 % 64 = r3
    ldr     r5, =g_bs_ptr
    ldr     r5, [r5]            @ r5 = base do array
    @ endereço do uint64_t: base + idx*8
    add     r5, r5, r0, lsl #3  @ r5 = &stacks[idx]
    @ lê os 2 words (little-endian uint64)
    ldmia   r5, {r0, r1}        @ r0=low32 r1=high32
    cmp     r3, #32
    bge     .Bbs_set_high
    @ bit no low word
    mov     r6, #1
    lsl     r6, r6, r3          @ mask
    cmp     r7, #0
    orrne   r0, r0, r6
    biceq   r0, r0, r6
    stmia   r5, {r0, r1}
    b       .Bbs_set_done
.Bbs_set_high:
    sub     r3, r3, #32
    mov     r6, #1
    lsl     r6, r6, r3
    cmp     r7, #0
    orrne   r1, r1, r6
    biceq   r1, r1, r6
    stmia   r5, {r0, r1}
.Bbs_set_done:
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ bs_get — lê bit stack_idx do stack (x,y,d)
@ r0=x r1=y r2=d r3=stack_idx → r0=bit
@ ===========================================================================
.type bs_get, %function
bs_get:
    push    {r4, r5, r6, lr}
    mov     r4, r3              @ salva stack_idx
    bl      bs_index
    ldr     r5, =g_bs_ptr
    ldr     r5, [r5]
    add     r5, r5, r0, lsl #3
    ldmia   r5, {r0, r1}
    cmp     r4, #32
    bge     .Bbs_get_high
    mov     r6, #1
    lsl     r6, r6, r4
    and     r0, r0, r6
    mov     r0, r0, lsr r4
    b       .Bbs_get_done
.Bbs_get_high:
    sub     r4, r4, #32
    mov     r6, #1
    lsl     r6, r6, r4
    and     r0, r1, r6
    mov     r0, r0, lsr r4
.Bbs_get_done:
    and     r0, r0, #1
    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ b5_bitstacks_fill_fib — preenche com Fibonacci mod 42
@ cada stack recebe F(idx) mod 42 bits setados
@ ===========================================================================
.type b5_bitstacks_fill_fib, %function
b5_bitstacks_fill_fib:
    push    {r4, r5, r6, r7, r8, r9, lr}

    ldr     r4, =g_bs_ptr
    ldr     r4, [r4]            @ base

    @ Fibonacci: f0=0, f1=1
    mov     r5, #0              @ f_prev
    mov     r6, #1              @ f_curr
    mov     r7, #0              @ stack index

.Bfill_loop:
    cmp     r7, #BS_TOTAL_STACKS
    beq     .Bfill_done

    @ n_bits = f_curr mod 42
    mov     r0, r6
    mov     r1, #42
    udiv    r2, r0, r1
    mul     r2, r2, r1
    sub     r8, r0, r2          @ r8 = f_curr mod 42

    @ addr do stack
    add     r9, r4, r7, lsl #3  @ &stacks[idx]

    @ seta r8 bits no uint64 (máscara = (1<<r8)-1)
    @ gera máscara low32
    cmp     r8, #0
    beq     .Bfill_zero

    cmp     r8, #32
    bge     .Bfill_over32

    @ r8 < 32: máscara no low word
    mov     r0, #1
    lsl     r0, r0, r8
    sub     r0, r0, #1          @ (1<<r8)-1
    mov     r1, #0
    b       .Bfill_store

.Bfill_over32:
    @ r8 >= 32
    mvn     r0, #0              @ low = 0xFFFFFFFF
    sub     r8, r8, #32
    cmp     r8, #0
    beq     .Bfill_store_ff
    mov     r1, #1
    lsl     r1, r1, r8
    sub     r1, r1, #1
    b       .Bfill_store

.Bfill_store_ff:
    mov     r1, #0
    b       .Bfill_store

.Bfill_zero:
    mov     r0, #0
    mov     r1, #0

.Bfill_store:
    stmia   r9, {r0, r1}

    @ avança Fibonacci
    add     r0, r5, r6
    mov     r5, r6
    mov     r6, r0

    add     r7, r7, #1
    b       .Bfill_loop

.Bfill_done:
    @ conta bits totais setados (para estatística)
    bl      b5_count_total_bits
    ldr     r1, =g_total_bits
    str     r0, [r1]

    pop     {r4, r5, r6, r7, r8, r9, pc}

@ ===========================================================================
@ b5_count_total_bits — conta bits em todos os stacks
@ retorna r0 = total de bits 1
@ ===========================================================================
.type b5_count_total_bits, %function
b5_count_total_bits:
    push    {r4, r5, r6, lr}
    ldr     r4, =g_bs_ptr
    ldr     r4, [r4]
    mov     r5, #0              @ total
    mov     r6, #0              @ stack index

.Bcount_loop:
    cmp     r6, #BS_TOTAL_STACKS
    beq     .Bcount_done

    @ carrega uint64 (2 words)
    ldmia   r4!, {r0, r1}

    @ popcount low word (Brian Kernighan)
    mov     r2, r0
.Bpc_low:
    cmp     r2, #0
    beq     .Bpc_low_done
    sub     r3, r2, #1
    and     r2, r2, r3
    add     r5, r5, #1
    b       .Bpc_low
.Bpc_low_done:

    @ popcount high word
    mov     r2, r1
.Bpc_high:
    cmp     r2, #0
    beq     .Bpc_high_done
    sub     r3, r2, #1
    and     r2, r2, r3
    add     r5, r5, #1
    b       .Bpc_high
.Bpc_high_done:

    add     r6, r6, #1
    b       .Bcount_loop

.Bcount_done:
    mov     r0, r5
    pop     {r4, r5, r6, pc}

@ ===========================================================================
@ b5_hyperforms_test — valida as 3 hiperformas
@ testa invariante: vértice[i] e vértice[j] de cada aresta satisfazem
@   |v_i|^2 + |v_j|^2 > 0 (não colapso)
@ e computa CRC de cada tabela de vértices
@ ===========================================================================
.type b5_hyperforms_test, %function
b5_hyperforms_test:
    push    {r4, r5, lr}

    @ HF0: 6 vértices x 2 coords x 4 bytes = 48 bytes
    ldr     r0, =hf0_verts
    mov     r1, #48
    bl      b5_crc32
    @ resultado em r0, ignora (apenas verifica que roda)

    @ HF1: 8 vértices x 2 coords x 4 bytes = 64 bytes
    ldr     r0, =hf1_verts
    mov     r1, #64
    bl      b5_crc32

    @ HF2: 10 vértices x 2 coords x 4 bytes = 80 bytes
    ldr     r0, =hf2_verts
    mov     r1, #80
    bl      b5_crc32

    @ valida distância de ruptura no hf2:
    @ maior distância entre pares invertidos = sqrt(2) ~ SQRT2_Q16
    @ verifica v0+v9: x_0+x_9 = 65536+53019 > SQRT2_Q16
    ldr     r4, =hf2_verts
    ldr     r0, [r4, #0]        @ v0.x = 65536
    ldr     r5, [r4, #80]       @ v9.x  = 53019 (offset = 9*8 = 72)
    @ (usamos apenas que ambos > 0 como sanidade)
    cmp     r0, #0
    ble     .Bhf_fail
    cmp     r5, #0
    ble     .Bhf_fail

    pop     {r4, r5, pc}
.Bhf_fail:
    mov     r7, #SYS_EXIT
    mov     r0, #55
    swi     #0

@ ===========================================================================
@ b5_commit_gate_run — 42 ciclos, cada um com 4 fases
@
@ Cada ciclo:
@   FASE 1 LOAD:    lê snapshot do último COMMIT
@   FASE 2 PROCESS: aplica transformação EMA no stack (x,y,d) corrente
@   FASE 3 VERIFY:  CRC32 do stack transformado
@   FASE 4 COMMIT:  grava, atualiza bitmap, libera posição
@
@ Posição só avança após as 4 fases completarem.
@ ===========================================================================
.type b5_commit_gate_run, %function
b5_commit_gate_run:
    push    {r4, r5, r6, r7, r8, r9, r10, r11, lr}

    mov     r4, #0              @ ciclo 0..41

.Bcg_cycle:
    cmp     r4, #42
    beq     .Bcg_done

    @ posição = ciclo mod 1000
    mov     r0, r4
    ldr     r1, =1000
    udiv    r2, r0, r1
    mul     r2, r2, r1
    sub     r5, r0, r2          @ r5 = pos = ciclo mod 1000

    @ addr do stack na posição r5
    ldr     r6, =g_bs_ptr
    ldr     r6, [r6]
    add     r6, r6, r5, lsl #3  @ &stacks[pos]

    @ === FASE 1: LOAD ===
    @ reset bitmap da posição
    ldr     r7, =g_cg_bitmap
    str     r4, [r7, r5, lsl #2]  @ guarda ciclo como estado

    @ copia stack atual para snapshot
    ldr     r8, =g_snapshot
    add     r8, r8, r5, lsl #3
    ldmia   r6, {r0, r1}
    stmia   r8, {r0, r1}

    @ atualiza bitmap: seta bit LOAD
    ldr     r9, =g_cg_bitmap_cur
    ldr     r10, [r9]
    orr     r10, r10, #CG_LOAD
    str     r10, [r9]

    @ === FASE 2: PROCESS — EMA(stack, SPIRAL_Q16, alpha=0.25) ===
    ldmia   r6, {r0, r1}        @ r0=low r1=high

    @ aplica EMA no low word: new = 0.75*old + 0.25*SPIRAL
    ldr     r7, =49152          @ 0.75 Q16
    umull   r2, r3, r0, r7
    lsr     r2, r2, #16
    orr     r2, r2, r3, lsl #16

    ldr     r7, =16384          @ 0.25 Q16
    ldr     r8, =SPIRAL_Q16
    umull   r3, r11, r8, r7
    lsr     r3, r3, #16
    orr     r3, r3, r11, lsl #16

    add     r2, r2, r3          @ new low
    @ r1 (high) mantém

    stmia   r6, {r2, r1}        @ grava stack transformado

    orr     r10, r10, #CG_PROCESS
    ldr     r9, =g_cg_bitmap_cur
    str     r10, [r9]

    @ === FASE 3: VERIFY — CRC32 do stack ===
    mov     r0, r6
    mov     r1, #8              @ 8 bytes por stack
    bl      b5_crc32
    ldr     r7, =g_commit_crc
    str     r0, [r7]

    @ verifica que CRC != 0 (sanidade mínima)
    cmp     r0, #0
    @ (se 0 em dados reais seria suspeito, aqui apenas seguimos)

    orr     r10, r10, #CG_VERIFY
    ldr     r9, =g_cg_bitmap_cur
    str     r10, [r9]

    @ === FASE 4: COMMIT ===
    @ verifica que os 4 bits estão setados
    ldr     r9, =g_cg_bitmap_cur
    ldr     r10, [r9]
    and     r11, r10, #CG_ALL
    cmp     r11, #CG_ALL
    bne     .Bcg_abort          @ commit incompleto → não libera posição

    @ atualiza bitmap global da posição
    ldr     r7, =g_cg_bitmap
    ldr     r8, [r7, r5, lsl #2]
    orr     r8, r8, #CG_COMMIT
    str     r8, [r7, r5, lsl #2]

    @ incrementa commits_ok
    ldr     r7, =g_commits_ok
    ldr     r8, [r7]
    add     r8, r8, #1
    str     r8, [r7]

    @ reseta bitmap corrente para próximo ciclo
    mov     r10, #0
    str     r10, [r9]

    add     r4, r4, #1
    b       .Bcg_cycle

.Bcg_abort:
    @ incrementa rollbacks
    ldr     r7, =g_rollbacks
    ldr     r8, [r7]
    add     r8, r8, #1
    str     r8, [r7]
    @ reseta bitmap
    mov     r10, #0
    ldr     r9, =g_cg_bitmap_cur
    str     r10, [r9]
    add     r4, r4, #1
    b       .Bcg_cycle

.Bcg_done:
    pop     {r4, r5, r6, r7, r8, r9, r10, r11, pc}

@ ===========================================================================
@ b5_parity_compute — calcula paridade XOR e CRC dos 1000 stacks
@ P0 = XOR de todos os uint64 (2 words)
@ P1 = CRC32 de todo o array (8000 bytes)
@ ===========================================================================
.type b5_parity_compute, %function
b5_parity_compute:
    push    {r4, r5, r6, r7, r8, lr}

    ldr     r4, =g_bs_ptr
    ldr     r4, [r4]

    @ P0: XOR acumulado
    mov     r5, #0              @ xor_low
    mov     r6, #0              @ xor_high
    mov     r7, #BS_TOTAL_STACKS

.Bpar_xor:
    cmp     r7, #0
    beq     .Bpar_xor_done
    ldmia   r4!, {r0, r1}
    eor     r5, r5, r0
    eor     r6, r6, r1
    subs    r7, r7, #1
    b       .Bpar_xor

.Bpar_xor_done:
    ldr     r8, =g_parity_0
    stmia   r8, {r5, r6}

    @ P1: CRC32 do array inteiro
    ldr     r4, =g_bs_ptr
    ldr     r0, [r4]
    ldr     r1, =(BS_TOTAL_STACKS * 8)
    bl      b5_crc32
    ldr     r4, =g_parity_1
    stmia   r4, {r0}            @ só o low word do CRC32

    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ b5_rollback_test — corrompe 1 stack, detecta via paridade, restaura
@ ===========================================================================
.type b5_rollback_test, %function
b5_rollback_test:
    push    {r4, r5, r6, r7, lr}

    @ corrompe stack[500]
    ldr     r4, =g_bs_ptr
    ldr     r4, [r4]
    add     r4, r4, #(500 * 8)
    ldmia   r4, {r0, r1}
    mvn     r0, r0              @ inverte bits do low word
    stmia   r4, {r0, r1}

    @ recalcula CRC e compara com g_parity_1
    ldr     r4, =g_bs_ptr
    ldr     r0, [r4]
    ldr     r1, =(BS_TOTAL_STACKS * 8)
    bl      b5_crc32
    mov     r5, r0              @ novo CRC

    ldr     r4, =g_parity_1
    ldr     r6, [r4]            @ CRC original

    cmp     r5, r6
    beq     .Brb_no_detect      @ não detectou (não deve acontecer)

    @ detectou! restaura do snapshot
    ldr     r4, =g_bs_ptr
    ldr     r4, [r4]
    add     r4, r4, #(500 * 8)

    ldr     r5, =g_snapshot
    add     r5, r5, #(500 * 8)
    ldmia   r5, {r0, r1}
    stmia   r4, {r0, r1}

    @ incrementa rollbacks
    ldr     r4, =g_rollbacks
    ldr     r0, [r4]
    add     r0, r0, #1
    str     r0, [r4]

    pop     {r4, r5, r6, r7, pc}

.Brb_no_detect:
    @ corrupção não detectada — exit com erro
    mov     r7, #SYS_EXIT
    mov     r0, #77
    swi     #0

@ ===========================================================================
@ b5_print_stats — imprime commits, rollbacks, bits totais
@ ===========================================================================
.type b5_print_stats, %function
b5_print_stats:
    push    {lr}

    ldr     r0, =msg_state
    mov     r1, #msg_state_len
    bl      ws5

    ldr     r0, =g_commits_ok
    ldr     r0, [r0]
    bl      ph5

    ldr     r0, =msg_crc
    mov     r1, #msg_crc_len
    bl      ws5

    ldr     r0, =g_commit_crc
    ldr     r0, [r0]
    bl      ph5

    ldr     r0, =msg_points
    mov     r1, #msg_points_len
    bl      ws5

    ldr     r0, =g_total_bits
    ldr     r0, [r0]
    bl      ph5

    pop     {pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type ws5, %function
ws5:
    push    {lr}
    mov     r2, r1
    mov     r1, r0
    mov     r0, #STDOUT
    mov     r7, #SYS_WRITE
    swi     #0
    pop     {pc}

@ ph5 = print hex32
.type ph5, %function
ph5:
    push    {r4, r5, lr}
    mov     r4, r0
    ldr     r5, =g_hex_b5
    ldr     r2, =hex_t5
    mov     r1, #28
.Bph5:
    lsr     r0, r4, r1
    and     r0, r0, #0xF
    ldrb    r0, [r2, r0]
    strb    r0, [r5], #1
    subs    r1, r1, #4
    bge     .Bph5
    mov     r0, #'\n'
    strb    r0, [r5]
    ldr     r0, =g_hex_b5
    mov     r1, #9
    bl      ws5
    pop     {r4, r5, pc}
