/*
 * 00_raf_start_linear_panel.S
 */

#include "raf_abi_linear.h"

.section .rodata
.align 4
msg_linear:
#if defined(__aarch64__)
  .ascii "RAFCODEPHI V2 LINEAR PANEL: X0 X1 X2 X3 X4 X5 X6 X7 X8 X9 X10 X11 X12 X13 X14 X15 X16 X17 X18 X19 X20 X21 X22 X23 X24 X25 X26 X27 X28 X29 X30\n"
#elif defined(__arm__)
  .ascii "RAFCODEPHI V2 LINEAR PANEL: R0 R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12 R13/SP R14/LR R15/PC ; SAFE MODE DOES NOT WRITE SP/PC\n"
#elif defined(__x86_64__)
  .ascii "RAFCODEPHI V2 LINEAR PANEL: RAX RBX RCX RDX RSI RDI RBP R8 R9 R10 R11 R12 R13 R14 R15\n"
#elif defined(__i386__)
  .ascii "RAFCODEPHI V2 LINEAR PANEL: EAX EBX ECX EDX ESI EDI EBP ESP EIP ; SAFE MODE DOES NOT WRITE ESP/EIP\n"
#else
  .ascii "RAFCODEPHI V2 LINEAR PANEL: UNKNOWN\n"
#endif
msg_linear_end:

.section .text
.align 4
.global _start
.global raf_start_linear_panel
.type _start, %function
.type raf_start_linear_panel, %function

#if defined(__aarch64__)
_start:
raf_start_linear_panel:
  mov x0,  #0
  mov x1,  #1
  mov x2,  #2
  mov x3,  #3
  mov x4,  #4
  mov x5,  #5
  mov x6,  #6
  mov x7,  #7
  mov x8,  #8
  mov x9,  #9
  mov x10, #10
  mov x11, #11
  mov x12, #12
  mov x13, #13
  mov x14, #14
  mov x15, #15
  mov x16, #16
  mov x17, #17
  mov x18, #18
  mov x19, #19
  mov x20, #20
  mov x21, #21
  mov x22, #22
  mov x23, #23
  mov x24, #24
  mov x25, #25
  mov x26, #26
  mov x27, #27
  mov x28, #28
  mov x29, #29
  mov x30, #30

  mov  x0, #RAF_FD_STDOUT
  adrp x1, msg_linear
  add  x1, x1, :lo12:msg_linear
  adrp x2, msg_linear_end
  add  x2, x2, :lo12:msg_linear_end
  sub  x2, x2, x1
  mov  x8, #RAF_SYS_WRITE
  svc  #0

  mov x0, #0
  mov x8, #RAF_SYS_EXIT
  svc #0
1: b 1b
#elif defined(__arm__)
.syntax unified
.arm
_start:
raf_start_linear_panel:
  mov r0,  #0
  mov r1,  #1
  mov r2,  #2
  mov r3,  #3
  mov r4,  #4
  mov r5,  #5
  mov r6,  #6
  mov r7,  #7
  mov r8,  #8
  mov r9,  #9
  mov r10, #10
  mov r11, #11
  mov r12, #12
  mov r14, #14

  mov r0, #RAF_FD_STDOUT
  ldr r1, =msg_linear
  ldr r2, =msg_linear_end
  sub r2, r2, r1
  mov r7, #RAF_SYS_WRITE
  svc #0

  mov r0, #0
  mov r7, #RAF_SYS_EXIT
  svc #0
1: b 1b
#elif defined(__x86_64__)
_start:
raf_start_linear_panel:
  movq $0,  %rax
  movq $1,  %rbx
  movq $2,  %rcx
  movq $3,  %rdx
  movq $4,  %rsi
  movq $5,  %rdi
  movq $6,  %rbp
  movq $8,  %r8
  movq $9,  %r9
  movq $10, %r10
  movq $11, %r11
  movq $12, %r12
  movq $13, %r13
  movq $14, %r14
  movq $15, %r15

  movq $RAF_SYS_WRITE, %rax
  movq $RAF_FD_STDOUT, %rdi
  leaq msg_linear(%rip), %rsi
  movq $(msg_linear_end - msg_linear), %rdx
  syscall

  movq $RAF_SYS_EXIT, %rax
  xorq %rdi, %rdi
  syscall
1: jmp 1b
#elif defined(__i386__)
_start:
raf_start_linear_panel:
  movl $0, %eax
  movl $1, %ebx
  movl $2, %ecx
  movl $3, %edx
  movl $4, %esi
  movl $5, %edi
  movl $6, %ebp

  movl $RAF_SYS_WRITE, %eax
  movl $RAF_FD_STDOUT, %ebx
  movl $msg_linear, %ecx
  movl $(msg_linear_end - msg_linear), %edx
  int $0x80

  movl $RAF_SYS_EXIT, %eax
  xorl %ebx, %ebx
  int $0x80
1: jmp 1b
#else
_start:
raf_start_linear_panel:
  ret
#endif
