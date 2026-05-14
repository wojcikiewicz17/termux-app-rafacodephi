/**
 * ARM NEON Assembly Optimizations
 * Architecture-specific SIMD operations
 * 
 * Copyright (c) instituto-Rafael
 * License: GPLv3
 */

#ifdef __arm__

.syntax unified
.arch armv7-a
.fpu neon
.text
.align 4

/**
 * Vector dot product - ARM NEON optimized
 * float bm_dot_neon(const float* a, const float* b, uint32_t n)
 */
.global bm_dot_neon
.type bm_dot_neon, %function
bm_dot_neon:
    vmov.f32    q0, #0.0            @ Initialize accumulator to zero
    
.L_dot_loop:
    cmp         r2, #4              @ Check if we have at least 4 elements
    blt         .L_dot_remainder
    
    vld1.32     {d2, d3}, [r0]!     @ Load 4 floats from a
    vld1.32     {d4, d5}, [r1]!     @ Load 4 floats from b
    
    vmla.f32    q0, q1, q2          @ Multiply-accumulate
    
    sub         r2, r2, #4          @ Decrement counter
    b           .L_dot_loop
    
.L_dot_remainder:
    @ Handle remaining elements
    cmp         r2, #0
    beq         .L_dot_sum
    
.L_dot_rem_loop:
    vld1.32     {d2[0]}, [r0]!
    vld1.32     {d4[0]}, [r1]!
    vmla.f32    d0, d2, d4
    subs        r2, r2, #1
    bne         .L_dot_rem_loop
    
.L_dot_sum:
    @ Horizontal add of q0
    vadd.f32    d0, d0, d1          @ Add high and low parts
    vpadd.f32   d0, d0, d0          @ Pairwise add
    vmov        r0, s0              @ Move result to return register
    bx          lr

/**
 * Vector addition - ARM NEON optimized
 * void bm_vadd_neon(const float* a, const float* b, float* r, uint32_t n)
 */
.global bm_vadd_neon
.type bm_vadd_neon, %function
bm_vadd_neon:
    push        {r4, lr}
    
.L_vadd_loop:
    cmp         r3, #4
    blt         .L_vadd_remainder
    
    vld1.32     {d0, d1}, [r0]!     @ Load 4 floats from a
    vld1.32     {d2, d3}, [r1]!     @ Load 4 floats from b
    vadd.f32    q2, q0, q1          @ Add vectors
    vst1.32     {d4, d5}, [r2]!     @ Store result
    
    sub         r3, r3, #4
    b           .L_vadd_loop
    
.L_vadd_remainder:
    cmp         r3, #0
    beq         .L_vadd_done
    
.L_vadd_rem_loop:
    vld1.32     {d0[0]}, [r0]!
    vld1.32     {d2[0]}, [r1]!
    vadd.f32    d4, d0, d2
    vst1.32     {d4[0]}, [r2]!
    subs        r3, r3, #1
    bne         .L_vadd_rem_loop
    
.L_vadd_done:
    pop         {r4, pc}

/**
 * Fast memory copy - ARM NEON optimized
 * void* bm_memcpy_neon(void* dst, const void* src, size_t n)
 */
.global bm_memcpy_neon
.type bm_memcpy_neon, %function
bm_memcpy_neon:
    push        {r4, lr}
    mov         r3, r0              @ Save dst for return
    
.L_memcpy_loop:
    cmp         r2, #32             @ Check if we have 32 bytes
    blt         .L_memcpy_remainder
    
    vld1.8      {d0-d3}, [r1]!      @ Load 32 bytes
    vst1.8      {d0-d3}, [r0]!      @ Store 32 bytes
    
    sub         r2, r2, #32
    b           .L_memcpy_loop
    
.L_memcpy_remainder:
    cmp         r2, #0
    beq         .L_memcpy_done
    
.L_memcpy_byte:
    ldrb        r4, [r1], #1
    strb        r4, [r0], #1
    subs        r2, r2, #1
    bne         .L_memcpy_byte
    
.L_memcpy_done:
    mov         r0, r3              @ Return original dst
    pop         {r4, pc}

#endif /* __arm__ */

/**
 * ARM64 (AArch64) optimizations
 */
#ifdef __aarch64__

.text
.align 4

/**
 * Vector dot product - ARM64 NEON optimized
 * float bm_dot_neon(const float* a, const float* b, uint32_t n)
 */
.global bm_dot_neon
.type bm_dot_neon, %function
bm_dot_neon:
    movi        v0.4s, #0           // Initialize accumulator
    
.L_dot64_loop:
    cmp         w2, #4
    b.lt        .L_dot64_remainder
    
    ld1         {v1.4s}, [x0], #16  // Load 4 floats from a
    ld1         {v2.4s}, [x1], #16  // Load 4 floats from b
    
    fmla        v0.4s, v1.4s, v2.4s // Fused multiply-add
    
    sub         w2, w2, #4
    b           .L_dot64_loop
    
.L_dot64_remainder:
    cbz         w2, .L_dot64_sum
    
.L_dot64_rem_loop:
    ldr         s1, [x0], #4
    ldr         s2, [x1], #4
    fmadd       s0, s1, s2, s0
    subs        w2, w2, #1
    b.ne        .L_dot64_rem_loop
    
.L_dot64_sum:
    // Horizontal sum of v0
    faddp       v0.4s, v0.4s, v0.4s
    faddp       v0.4s, v0.4s, v0.4s
    fmov        w0, s0
    ret

/**
 * Vector addition - ARM64 NEON optimized
 * void bm_vadd_neon(const float* a, const float* b, float* r, uint32_t n)
 */
.global bm_vadd_neon
.type bm_vadd_neon, %function
bm_vadd_neon:
.L_vadd64_loop:
    cmp         w3, #4
    b.lt        .L_vadd64_remainder
    
    ld1         {v0.4s}, [x0], #16
    ld1         {v1.4s}, [x1], #16
    fadd        v2.4s, v0.4s, v1.4s
    st1         {v2.4s}, [x2], #16
    
    sub         w3, w3, #4
    b           .L_vadd64_loop
    
.L_vadd64_remainder:
    cbz         w3, .L_vadd64_done
    
.L_vadd64_rem_loop:
    ldr         s0, [x0], #4
    ldr         s1, [x1], #4
    fadd        s2, s0, s1
    str         s2, [x2], #4
    subs        w3, w3, #1
    b.ne        .L_vadd64_rem_loop
    
.L_vadd64_done:
    ret

/**
 * Fast memory copy - ARM64 optimized
 * void* bm_memcpy_neon(void* dst, const void* src, size_t n)
 */
.global bm_memcpy_neon
.type bm_memcpy_neon, %function
bm_memcpy_neon:
    mov         x3, x0              // Save dst
    
.L_memcpy64_loop:
    cmp         x2, #64
    b.lt        .L_memcpy64_remainder
    
    ldp         q0, q1, [x1], #32
    ldp         q2, q3, [x1], #32
    stp         q0, q1, [x0], #32
    stp         q2, q3, [x0], #32
    
    sub         x2, x2, #64
    b           .L_memcpy64_loop
    
.L_memcpy64_remainder:
    cbz         x2, .L_memcpy64_done
    
.L_memcpy64_byte:
    ldrb        w4, [x1], #1
    strb        w4, [x0], #1
    subs        x2, x2, #1
    b.ne        .L_memcpy64_byte
    
.L_memcpy64_done:
    mov         x0, x3
    ret

#endif /* __aarch64__ */
