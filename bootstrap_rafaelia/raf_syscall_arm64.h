#ifndef RAF_SYSCALL_ARM64_H
#define RAF_SYSCALL_ARM64_H
#include "raf_types.h"
#if defined(__aarch64__)
RAF_INLINE s64 raf_syscall1(u64 nr,u64 a1){ register u64 x8 __asm__("x8")=nr; register u64 x0 __asm__("x0")=a1; __asm__ __volatile__("svc #0":"+r"(x0):"r"(x8):"memory","cc"); return (s64)x0; }
#else
RAF_INLINE s64 raf_syscall1(u64 nr,u64 a1){(void)nr;(void)a1; return -1;}
#endif
#endif
