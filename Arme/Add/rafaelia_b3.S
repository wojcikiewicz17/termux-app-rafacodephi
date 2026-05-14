@ ===========================================================================
@ RAFAELIA B3 — MULTICORE clone() + CRC32SW + THROUGHPUT
@ ARM32 · sem root · sem pthread · clone syscall direto
@ Compilar: as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp rafaelia_b3.S -o b3.o && ld b3.o -o rafaelia_b3
@ ===========================================================================

.equ SYS_EXIT,            1
.equ SYS_WRITE,           4
.equ SYS_MMAP2,           192
.equ SYS_CLONE,           120
.equ SYS_WAIT4,           114
.equ SYS_GETTIMEOFDAY,    78
.equ STDOUT,              1
.equ SIGCHLD,             17
.equ N_WORKERS,           4
.equ WORK_SIZE,           0x10000
.equ STACK_SIZE,          0x4000

@ ---------------------------------------------------------------------------
@ RODATA
@ ---------------------------------------------------------------------------
.section .rodata
.align 6

msg_b3_boot:
    .ascii "B3: MULTICORE+CRC32SW\n"
    .equ msg_b3_boot_len, . - msg_b3_boot

msg_worker:
    .ascii "W:"
    .equ msg_worker_len, . - msg_worker

msg_crc:
    .ascii "CRC="
    .equ msg_crc_len, . - msg_crc

msg_tput:
    .ascii "US="
    .equ msg_tput_len, . - msg_tput

msg_done3:
    .ascii "B3:DONE\n"
    .equ msg_done3_len, . - msg_done3

hex_t3: .ascii "0123456789ABCDEF"

@ ---------------------------------------------------------------------------
@ BSS
@ ---------------------------------------------------------------------------
.section .bss
.align 6

.align 3
g_tv_start:   .space 8
g_tv_end:     .space 8

.align 4
g_worker_crc: .space N_WORKERS * 4
g_stacks:     .space N_WORKERS * 4
g_work_data:  .space 4

.align 6
g_crc_tab3:   .space 256 * 4

g_hex_b3:     .space 16
g_worker_idx: .space 4

@ ---------------------------------------------------------------------------
@ TEXT
@ ---------------------------------------------------------------------------
.section .text
.align 2
.global _start
.type _start, %function

_start:
    ldr     r0, =msg_b3_boot
    mov     r1, #msg_b3_boot_len
    bl      ws3

    @ build CRC table
    bl      crc_build3

    @ mmap bloco de trabalho
    mov     r0, #0
    ldr     r1, =(WORK_SIZE * N_WORKERS)
    mov     r2, #3
    mov     r3, #0x22
    mov     r4, #-1
    mov     r5, #0
    mov     r7, #SYS_MMAP2
    swi     #0
    ldr     r1, =g_work_data
    str     r0, [r1]

    @ preenche com padrão Fibonacci
    ldr     r4, [r1]
    ldr     r5, =(WORK_SIZE * N_WORKERS)
    bl      fill_fib3

    @ timestamp inicial
    ldr     r0, =g_tv_start
    mov     r1, #0
    mov     r7, #SYS_GETTIMEOFDAY
    swi     #0

    @ spawn N_WORKERS processos filhos
    mov     r8, #0          @ worker index

.Bspawn:
    cmp     r8, #N_WORKERS
    beq     .Bspawn_done

    @ aloca stack
    mov     r0, #0
    ldr     r1, =STACK_SIZE
    mov     r2, #3
    mov     r3, #0x22
    mov     r4, #-1
    mov     r5, #0
    mov     r7, #SYS_MMAP2
    swi     #0
    ldr     r1, =STACK_SIZE
    add     r1, r0, r1      @ stack top

    @ salva ptr
    ldr     r2, =g_stacks
    str     r0, [r2, r8, lsl #2]

    @ clone(SIGCHLD, stack_top)
    mov     r0, #SIGCHLD
    mov     r7, #SYS_CLONE
    swi     #0

    cmp     r0, #0
    beq     .Bchild         @ filho

    @ pai continua
    add     r8, r8, #1
    b       .Bspawn

.Bchild:
    @ FILHO: calcula CRC do seu bloco
    ldr     r4, =g_work_data
    ldr     r4, [r4]
    ldr     r5, =WORK_SIZE
    mul     r0, r8, r5
    add     r4, r4, r0      @ ptr para o bloco deste worker

    mov     r0, r4
    mov     r1, r5
    bl      crc_compute3

    ldr     r1, =g_worker_crc
    str     r0, [r1, r8, lsl #2]

    @ imprime "W:N"
    ldr     r0, =msg_worker
    mov     r1, #msg_worker_len
    bl      ws3

    mov     r0, r8
    bl      print_nibble3

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

.Bspawn_done:
    @ pai espera todos os filhos
    mov     r9, #N_WORKERS

.Bwait:
    cmp     r9, #0
    beq     .Bwait_done
    mov     r0, #-1
    mov     r1, #0
    mov     r2, #0
    mov     r3, #0
    mov     r7, #SYS_WAIT4
    swi     #0
    subs    r9, r9, #1
    b       .Bwait

.Bwait_done:
    @ timestamp final
    ldr     r0, =g_tv_end
    mov     r1, #0
    mov     r7, #SYS_GETTIMEOFDAY
    swi     #0

    @ delta_us = (sec_end-sec_start)*1e6 + (usec_end-usec_start)
    ldr     r0, =g_tv_end
    ldmia   r0, {r0, r1}
    ldr     r2, =g_tv_start
    ldmia   r2, {r2, r3}
    sub     r0, r0, r2
    sub     r1, r1, r3
    ldr     r4, =1000000
    mul     r0, r0, r4
    add     r0, r0, r1

    push    {r0}
    ldr     r0, =msg_tput
    mov     r1, #msg_tput_len
    bl      ws3
    pop     {r0}
    bl      print_hex32_b3

    @ XOR de todos os CRCs
    ldr     r0, =g_worker_crc
    ldr     r1, [r0, #0]
    ldr     r2, [r0, #4]
    ldr     r3, [r0, #8]
    ldr     r4, [r0, #12]
    eor     r0, r1, r2
    eor     r0, r0, r3
    eor     r0, r0, r4

    push    {r0}
    ldr     r0, =msg_crc
    mov     r1, #msg_crc_len
    bl      ws3
    pop     {r0}
    bl      print_hex32_b3

    ldr     r0, =msg_done3
    mov     r1, #msg_done3_len
    bl      ws3

    mov     r7, #SYS_EXIT
    mov     r0, #0
    swi     #0

@ ===========================================================================
@ fill_fib3 — r4=ptr r5=len — padrão Fibonacci mod 65536
@ ===========================================================================
.type fill_fib3, %function
fill_fib3:
    push    {r4, r5, r6, r7, lr}
    mov     r6, #1
    mov     r7, #1
    mov     r0, #0
.Bfib:
    cmp     r0, r5
    bge     .Bfib_done
    add     r2, r6, r7
    and     r2, r2, #0xFFFF
    strh    r2, [r4, r0]
    mov     r6, r7
    mov     r7, r2
    add     r0, r0, #2
    b       .Bfib
.Bfib_done:
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ crc_build3 — constrói g_crc_tab3
@ ===========================================================================
.type crc_build3, %function
crc_build3:
    push    {r4, r5, r6, r7, lr}
    ldr     r4, =g_crc_tab3
    mov     r5, #0
.Bcb:
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
    b       .Bcb
.Bcb_done:
    pop     {r4, r5, r6, r7, pc}

@ ===========================================================================
@ crc_compute3 — r0=ptr r1=len → r0=crc32c
@ ===========================================================================
.type crc_compute3, %function
crc_compute3:
    push    {r4, r5, r6, r7, r8, lr}
    mov     r4, r0
    mov     r5, r1
    mvn     r6, #0
    ldr     r7, =g_crc_tab3

    @ loop desdobrado: 4 bytes por iteração
.Bcc4:
    cmp     r5, #4
    blt     .Bcc1
    ldr     r0, [r4], #4

    eor     r8, r6, r0;     and r8, r8, #0xFF
    ldr     r8, [r7, r8, lsl #2]; lsr r6, r6, #8; eor r6, r6, r8

    lsr     r0, r0, #8
    eor     r8, r6, r0;     and r8, r8, #0xFF
    ldr     r8, [r7, r8, lsl #2]; lsr r6, r6, #8; eor r6, r6, r8

    lsr     r0, r0, #8
    eor     r8, r6, r0;     and r8, r8, #0xFF
    ldr     r8, [r7, r8, lsl #2]; lsr r6, r6, #8; eor r6, r6, r8

    lsr     r0, r0, #8
    eor     r8, r6, r0;     and r8, r8, #0xFF
    ldr     r8, [r7, r8, lsl #2]; lsr r6, r6, #8; eor r6, r6, r8

    sub     r5, r5, #4
    b       .Bcc4

.Bcc1:
    cmp     r5, #0
    beq     .Bcc_done
    ldrb    r0, [r4], #1
    eor     r8, r6, r0;     and r8, r8, #0xFF
    ldr     r8, [r7, r8, lsl #2]; lsr r6, r6, #8; eor r6, r6, r8
    subs    r5, r5, #1
    b       .Bcc1

.Bcc_done:
    mvn     r0, r6
    pop     {r4, r5, r6, r7, r8, pc}

@ ===========================================================================
@ Utilitários
@ ===========================================================================
.type print_nibble3, %function
print_nibble3:
    push    {lr}
    ldr     r1, =hex_t3
    and     r0, r0, #0xF
    ldrb    r0, [r1, r0]
    ldr     r1, =g_hex_b3
    strb    r0, [r1]
    mov     r2, #'\n'
    strb    r2, [r1, #1]
    mov     r0, r1
    mov     r1, #2
    bl      ws3
    pop     {pc}

.type print_hex32_b3, %function
print_hex32_b3:
    push    {r4, r5, lr}
    mov     r4, r0
    ldr     r5, =g_hex_b3
    ldr     r2, =hex_t3
    mov     r1, #28
.Ph3:
    lsr     r0, r4, r1
    and     r0, r0, #0xF
    ldrb    r0, [r2, r0]
    strb    r0, [r5], #1
    subs    r1, r1, #4
    bge     .Ph3
    mov     r0, #'\n'
    strb    r0, [r5]
    ldr     r0, =g_hex_b3
    mov     r1, #9
    bl      ws3
    pop     {r4, r5, pc}

.type ws3, %function
ws3:
    push    {lr}
    mov     r2, r1
    mov     r1, r0
    mov     r0, #STDOUT
    mov     r7, #SYS_WRITE
    swi     #0
    pop     {pc}
