#include "raf_abi_linear.h"
.section .text
.align 4
.global raf_write_stdout_leaf
.global raf_exit_leaf
.type raf_write_stdout_leaf, %function
.type raf_exit_leaf, %function
#if defined(__aarch64__)
raf_write_stdout_leaf:
  mov x2, x1
  mov x1, x0
  mov x0, #RAF_FD_STDOUT
  mov x8, #RAF_SYS_WRITE
  svc #0
  ret
raf_exit_leaf:
  mov x8, #RAF_SYS_EXIT
  svc #0
1: b 1b
#elif defined(__arm__)
.syntax unified
.arm
raf_write_stdout_leaf:
  mov r2, r1
  mov r1, r0
  mov r0, #RAF_FD_STDOUT
  mov r7, #RAF_SYS_WRITE
  svc #0
  bx lr
raf_exit_leaf:
  mov r7, #RAF_SYS_EXIT
  svc #0
1: b 1b
#elif defined(__x86_64__)
raf_write_stdout_leaf:
  movq %rsi, %rdx
  movq %rdi, %rsi
  movq $RAF_FD_STDOUT, %rdi
  movq $RAF_SYS_WRITE, %rax
  syscall
  ret
raf_exit_leaf:
  movq $RAF_SYS_EXIT, %rax
  syscall
1: jmp 1b
#elif defined(__i386__)
raf_write_stdout_leaf:
  movl $RAF_SYS_WRITE, %eax
  movl $RAF_FD_STDOUT, %ebx
  movl 4(%esp), %ecx
  movl 8(%esp), %edx
  int $0x80
  ret
raf_exit_leaf:
  movl $RAF_SYS_EXIT, %eax
  movl 4(%esp), %ebx
  int $0x80
1: jmp 1b
#else
raf_write_stdout_leaf:
  ret
raf_exit_leaf:
  ret
#endif
