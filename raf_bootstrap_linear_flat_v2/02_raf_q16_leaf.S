#define Q16_SQRT3_2 56756
#define Q16_PI_S279 203280
.section .text
.align 4
.global raf_q16_mul_leaf
.global raf_fraf_step_leaf
.type raf_q16_mul_leaf, %function
.type raf_fraf_step_leaf, %function
#if defined(__aarch64__)
raf_q16_mul_leaf:
  sxtw x0, w0
  sxtw x1, w1
  mul x2, x0, x1
  asr x0, x2, #16
  ret
raf_fraf_step_leaf:
  sxtw x0, w0
  mov x1, #Q16_SQRT3_2
  mul x2, x0, x1
  asr x2, x2, #16
  mov x3, #Q16_PI_S279
  add x0, x2, x3
  ret
#elif defined(__arm__)
.syntax unified
.arm
raf_q16_mul_leaf:
  smull r2, r3, r0, r1
  mov r0, r2, lsr #16
  orr r0, r0, r3, lsl #16
  bx lr
raf_fraf_step_leaf:
  ldr r1, =Q16_SQRT3_2
  smull r2, r3, r0, r1
  mov r0, r2, lsr #16
  orr r0, r0, r3, lsl #16
  ldr r1, =Q16_PI_S279
  add r0, r0, r1
  bx lr
#elif defined(__x86_64__)
raf_q16_mul_leaf:
  movslq %edi, %rax
  movslq %esi, %rsi
  imulq %rsi, %rax
  sarq $16, %rax
  ret
raf_fraf_step_leaf:
  movslq %edi, %rax
  imulq $Q16_SQRT3_2, %rax, %rax
  sarq $16, %rax
  addq $Q16_PI_S279, %rax
  ret
#elif defined(__i386__)
raf_q16_mul_leaf:
  movl 4(%esp), %eax
  imull 8(%esp)
  shrdl $16, %edx, %eax
  ret
raf_fraf_step_leaf:
  movl 4(%esp), %eax
  movl $Q16_SQRT3_2, %ecx
  imull %ecx
  shrdl $16, %edx, %eax
  addl $Q16_PI_S279, %eax
  ret
#else
raf_q16_mul_leaf:
  ret
raf_fraf_step_leaf:
  ret
#endif
