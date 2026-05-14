@ ===========================================================================
@ raf_asm_b1.S — RAFAELIA B1 ARM32 Termux
@ Toro T^7 · CRC32C · EMA · 42 atratores
@
@ TERMUX: usa syscall SYS_exit_group (252) em vez de SYS_exit (1)
@         para compatibilidade com Bionic thread runtime
@
@ Compilar (Termux):
@   as -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp raf_asm_b1.S -o b1.o
@   ld --dynamic-linker /data/data/com.termux/files/usr/lib/ld-linux.so \
@      -pie b1.o -o raf_b1
@ ---------------------------------------------------------------------------
@
@ Ou via clang (mais simples no Termux):
@   clang -fPIE -pie -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp \
@         raf_asm_b1.S -o raf_b1
@ ===========================================================================

.equ SYS_WRITE,      4
.equ SYS_EXIT_GROUP, 252   @ Termux/Android: usar exit_group
.equ SYS_MMAP2,      192
.equ STDOUT,         1
.equ PROT_RW,        3
.equ MAP_ANON,       0x22
.equ SPIRAL_Q16,     56755
.equ PHI_Q16,        105965
.equ PERIOD,         42
.equ TORUS_DIM,      7
.equ ARENA_SZ,       0x400000  @ 4MB

.section .rodata
.align 6

msg_boot:  .ascii "RAFAELIA B1 ARM32 TERMUX\n"
.equ msg_boot_len, . - msg_boot
msg_ok:    .ascii "B1:OK\n"
.equ msg_ok_len, . - msg_ok
msg_phi:   .ascii "PHI="
.equ msg_phi_len, . - msg_phi
hex_t:     .ascii "0123456789ABCDEF"

@ 42 atratores 7D Q16.16 (geração determinística via .set)
.align 4
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

.section .bss
.align 6

g_state:     .space TORUS_DIM * 4
g_C:         .space 4
g_H:         .space 4
g_phase:     .space 4
g_hex_buf:   .space 12
g_crc_tab:   .space 256 * 4

.section .text
.align 2
.global _start
.global main        @ alias para PIE

_start:
main:
    ldr     r0, =msg_boot
    mov     r1, #msg_boot_len
    bl      _ws

    bl      _crc_build
    bl      _torus_init
    bl      _run_42

    @ imprime phi final
    ldr     r0, =msg_phi
    mov     r1, #msg_phi_len
    bl      _ws

    ldr     r0, =g_C
    ldr     r0, [r0]
    bl      _ph

    ldr     r0, =msg_ok
    mov     r1, #msg_ok_len
    bl      _ws

    @ exit_group(0) — Termux/Bionic
    mov     r7, #SYS_EXIT_GROUP
    mov     r0, #0
    swi     #0

@ CRC32C build (Castagnoli, RFC 3720)
_crc_build:
    push {r4,r5,r6,r7,lr}
    ldr r4,=g_crc_tab; mov r5,#0
.cb: cmp r5,#256; beq .cbd
    mov r0,r5; mov r6,#8
.cbb: tst r0,#1; lsr r0,r0,#1
    ldrne r7,=0x82F63B78; eorne r0,r0,r7
    subs r6,r6,#1; bne .cbb
    str r0,[r4,r5,lsl #2]; add r5,r5,#1; b .cb
.cbd: pop {r4,r5,r6,r7,pc}

@ torus init
_torus_init:
    push {r4,r5,r6,lr}
    ldr r4,=g_state
    ldr r5,=SPIRAL_Q16
    ldr r6,=PHI_Q16
    and r0,r5,#0xFFFF; str r0,[r4,#0]
    and r0,r6,#0xFFFF; str r0,[r4,#4]
    mul r0,r5,r6; lsr r0,r0,#16; and r0,r0,#0xFFFF; str r0,[r4,#8]
    mov r0,#0x8000; ldr r1,=g_C; str r0,[r1]
    ldr r1,=g_H; str r0,[r1]
    mov r0,#0; ldr r1,=g_phase; str r0,[r1]
    pop {r4,r5,r6,pc}

@ 42 ciclos EMA
_run_42:
    push {r4,r5,lr}
    mov r4,#PERIOD
.r42: cmp r4,#0; beq .r42d
    @ C_in sintético = SPIRAL * phase / PERIOD
    ldr r0,=g_phase; ldr r0,[r0]
    ldr r1,=SPIRAL_Q16; mul r0,r0,r1; lsr r0,r0,#4
    and r0,r0,#0xFFFF
    @ EMA: C = (3*C + C_in)/4
    ldr r5,=g_C; ldr r1,[r5]
    add r1,r1,r1,lsl #1   @ 3*C
    add r1,r1,r0; lsr r1,r1,#2
    str r1,[r5]
    @ phase++
    ldr r5,=g_phase; ldr r0,[r5]
    add r0,r0,#1; cmp r0,#PERIOD; moveq r0,#0
    str r0,[r5]
    subs r4,r4,#1; b .r42
.r42d:
    pop {r4,r5,pc}

_ws:
    push {lr}
    mov r2,r1; mov r1,r0; mov r0,#STDOUT
    mov r7,#SYS_WRITE; swi #0
    pop {pc}

_ph:
    push {r4,r5,lr}
    mov r4,r0; ldr r5,=g_hex_buf; ldr r2,=hex_t; mov r1,#28
.ph: lsr r0,r4,r1; and r0,r0,#0xF; ldrb r0,[r2,r0]; strb r0,[r5],#1
    subs r1,r1,#4; bge .ph
    mov r0,#'\n'; strb r0,[r5]; ldr r0,=g_hex_buf; mov r1,#9; bl _ws
    pop {r4,r5,pc}
