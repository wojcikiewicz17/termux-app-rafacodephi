/*
 * RAFAELIA cross-architecture nucleus lab.
 *
 * This file is intentionally isolated from the Android APK build.  It records
 * corrected ABI/register/timer knowledge for non-APK targets and provides a
 * host-compilable selftest so experimental architecture work does not break
 * Termux RAFCODEΦ APK assembly.
 */
#include <stdint.h>
#include <stddef.h>

#if !defined(RAF_FREESTANDING)
#include <unistd.h>
#endif

typedef uint8_t raf_u8;
typedef uint32_t raf_u32;
typedef int32_t raf_s32;
typedef uint64_t raf_u64;
typedef int64_t raf_s64;

#define RAF_Q16_SQRT3_OVER_2 56756
#define RAF_Q16_PI_SIN_81    203280
#define RAF_Q8_SQRT3_OVER_2  222
#define RAF_Q8_PI_SIN_81     49

struct raf_arch_contract {
    const char *id;
    const char *word_bits;
    const char *syscall_abi;
    const char *timer;
    const char *notes;
};

static const struct raf_arch_contract RAF_CROSS_ARCH_CONTRACTS[] = {
    {"rv32", "32", "Linux: a7=nr, a0-a5=args, ecall; bare-metal: CSR/MMIO only", "rdcycle/rdtime CSR when implemented", "Do not assume UART MMIO across ESP32-C3, CH32V and GD32VF."},
    {"macos-arm64", "64", "Darwin/BSD: x16=nr, x0-x5=args, svc #0x80", "cntvct_el0", "Mach-O + libSystem path; not Linux svc #0."},
    {"macos-x86_64", "64", "Darwin/BSD: rax=0x2000000|nr, rdi/rsi/rdx args, syscall", "rdtsc with serialization", "Universal binaries are a packaging step, not an ISA."},
    {"mips-o32", "32", "Linux O32: v0=nr, a0-a3=args, syscall; a3 carries errno flag", "platform-specific", "Delay slots and endianness must be toolchain-selected."},
    {"loongarch64", "64", "Linux: a7=nr, a0-a5=args, syscall 0", "rdtime.d when available", "Not MIPS-compatible despite historical naming proximity."},
    {"s390x", "64", "Linux: r1=nr, r2-r7=args, svc 0", "stck", "Big-endian Linux-on-Z path."},
    {"ppc32", "32", "Linux: r0=nr, r3-r8=args, sc", "timebase via mftb/mftbu", "Define 32-bit register widths explicitly."},
    {"ppc64", "64", "Linux: r0=nr, r3-r8=args, sc", "timebase via mftb", "ELFv2/ELFv1 ABI selection is a toolchain concern."},
};

static raf_s32 raf_fraf_q16(raf_s32 value, raf_s32 steps)
{
    while (steps-- > 0) {
        value = (raf_s32)(((raf_s64)value * RAF_Q16_SQRT3_OVER_2) >> 16) + RAF_Q16_PI_SIN_81;
    }
    return value;
}

static raf_u8 raf_fraf_q8(raf_u8 start, raf_u8 steps)
{
    raf_s32 value = (raf_s32)start;
    while (steps-- > 0) {
        value = ((value * RAF_Q8_SQRT3_OVER_2) >> 8) + RAF_Q8_PI_SIN_81;
        if (value > 255) value = 255;
        if (value < 0) value = 0;
    }
    return (raf_u8)value;
}

static raf_u32 raf_contract_count(void)
{
    return (raf_u32)(sizeof(RAF_CROSS_ARCH_CONTRACTS) / sizeof(RAF_CROSS_ARCH_CONTRACTS[0]));
}

#if defined(__riscv) && (__riscv_xlen == 32)
static __attribute__((always_inline)) inline raf_s32 raf_rv32_ecall3(raf_s32 nr, raf_s32 a, raf_s32 b, raf_s32 c)
{
    register raf_s32 a0 __asm__("a0") = a;
    register raf_s32 a1 __asm__("a1") = b;
    register raf_s32 a2 __asm__("a2") = c;
    register raf_s32 a7 __asm__("a7") = nr;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return a0;
}

static __attribute__((always_inline)) inline raf_u32 raf_rv32_rdcycle(void)
{
    raf_u32 value;
    __asm__ volatile("rdcycle %0" : "=r"(value) :: "memory");
    return value;
}
#else
static raf_s32 raf_rv32_ecall3(raf_s32 nr, raf_s32 a, raf_s32 b, raf_s32 c)
{
    (void)nr; (void)b; (void)c;
    return a;
}

static raf_u32 raf_rv32_rdcycle(void)
{
    return 0;
}
#endif

#if defined(__APPLE__) && defined(__aarch64__)
static __attribute__((always_inline)) inline long raf_macos_write(int fd, const void *buf, unsigned long n)
{
    register long x16 __asm__("x16") = 4;
    register long x0 __asm__("x0") = fd;
    register long x1 __asm__("x1") = (long)buf;
    register long x2 __asm__("x2") = (long)n;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}
#elif defined(__APPLE__) && defined(__x86_64__)
static __attribute__((always_inline)) inline long raf_macos_write(int fd, const void *buf, unsigned long n)
{
    long result;
    __asm__ volatile("syscall" : "=a"(result) : "a"(0x2000004L), "D"((long)fd), "S"(buf), "d"(n) : "rcx", "r11", "memory");
    return result;
}
#else
static long raf_macos_write(int fd, const void *buf, unsigned long n)
{
#if defined(RAF_FREESTANDING)
    (void)fd; (void)buf;
    return (long)n;
#else
    return (long)write(fd, buf, n);
#endif
}
#endif

#if defined(__mips__)
static __attribute__((always_inline)) inline raf_s32 raf_mips_o32_write(raf_s32 fd, const void *buf, raf_u32 n)
{
    register raf_s32 v0 __asm__("$2") = 4004;
    register raf_s32 a0 __asm__("$4") = fd;
    register raf_s32 a1 __asm__("$5") = (raf_s32)(uintptr_t)buf;
    register raf_s32 a2 __asm__("$6") = (raf_s32)n;
    register raf_s32 a3 __asm__("$7");
    __asm__ volatile("syscall" : "+r"(v0), "=r"(a3) : "r"(a0), "r"(a1), "r"(a2) : "memory");
    return a3 ? -v0 : v0;
}
#else
static raf_s32 raf_mips_o32_write(raf_s32 fd, const void *buf, raf_u32 n)
{
    (void)fd; (void)buf;
    return (raf_s32)n;
}
#endif

#if defined(__loongarch64)
static __attribute__((always_inline)) inline raf_s64 raf_loongarch64_write(raf_s32 fd, const void *buf, raf_u64 n)
{
    register raf_s64 a0 __asm__("$a0") = fd;
    register raf_s64 a1 __asm__("$a1") = (raf_s64)(uintptr_t)buf;
    register raf_s64 a2 __asm__("$a2") = (raf_s64)n;
    register raf_s64 a7 __asm__("$a7") = 64;
    __asm__ volatile("syscall 0" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return a0;
}
#else
static raf_s64 raf_loongarch64_write(raf_s32 fd, const void *buf, raf_u64 n)
{
    (void)fd; (void)buf;
    return (raf_s64)n;
}
#endif

#if defined(__s390x__)
static __attribute__((always_inline)) inline raf_s64 raf_s390x_write(raf_s32 fd, const void *buf, raf_u64 n)
{
    register raf_u64 r1 __asm__("1") = 1; /* __NR_write on Linux s390x */
    register raf_u64 r2 __asm__("2") = (raf_u64)(raf_u32)fd;
    register raf_u64 r3 __asm__("3") = (raf_u64)(uintptr_t)buf;
    register raf_u64 r4 __asm__("4") = n;
    __asm__ volatile("svc 0" : "+r"(r2) : "r"(r1), "r"(r3), "r"(r4) : "memory", "cc");
    return (raf_s64)r2;
}
#else
static raf_s64 raf_s390x_write(raf_s32 fd, const void *buf, raf_u64 n)
{
    (void)fd; (void)buf;
    return (raf_s64)n;
}
#endif

#if defined(__powerpc__) || defined(__powerpc64__) || defined(__ppc__) || defined(__ppc64__)
static __attribute__((always_inline)) inline raf_s64 raf_ppc_write(raf_s32 fd, const void *buf, raf_u64 n)
{
    register unsigned long r0 __asm__("r0") = 4;
    register unsigned long r3 __asm__("r3") = (unsigned long)fd;
    register unsigned long r4 __asm__("r4") = (unsigned long)(uintptr_t)buf;
    register unsigned long r5 __asm__("r5") = (unsigned long)n;
    __asm__ volatile("sc" : "+r"(r3) : "r"(r0), "r"(r4), "r"(r5) : "memory", "cr0");
    return (raf_s64)(long)r3;
}
#else
static raf_s64 raf_ppc_write(raf_s32 fd, const void *buf, raf_u64 n)
{
    (void)fd; (void)buf;
    return (raf_s64)n;
}
#endif

#ifdef RAF_CROSS_ARCH_SELFTEST
#include <stdio.h>

int main(void)
{
    const char msg[] = "RAFAELIA cross-arch host smoke\n";
    raf_s32 q16 = raf_fraf_q16(65536, 48);
    raf_u8 q8 = raf_fraf_q8(56u, 32u);
    raf_u32 contracts = raf_contract_count();

    if (contracts != 8u) return 10;
    if (q16 <= 0) return 11;
    if (q8 == 0u) return 12;
    if (raf_rv32_ecall3(0, 7, 0, 0) != 7) return 13;
    if (raf_macos_write(1, msg, sizeof(msg) - 1u) < 0) return 14;
    if (raf_mips_o32_write(1, msg, 3) != 3) return 15;
    if (raf_loongarch64_write(1, msg, 4) != 4) return 16;
    if (raf_s390x_write(1, msg, 5) != 5) return 17;
    if (raf_ppc_write(1, msg, 6) != 6) return 18;
    (void)raf_rv32_rdcycle();

    printf("contracts=%u q16=%d q8=%u\n", contracts, q16, (unsigned)q8);
    return 0;
}
#endif
