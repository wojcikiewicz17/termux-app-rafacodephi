#ifndef RAF_TYPES_H
#define RAF_TYPES_H

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed char s8;
typedef signed short s16;
typedef signed int s32;
typedef signed long long s64;
typedef u64 usize;
typedef s64 ssize;
typedef u8 bool8;

#define RAF_TRUE ((bool8)1)
#define RAF_FALSE ((bool8)0)
#define RAF_INLINE static inline __attribute__((always_inline))
#define RAF_NOINLINE __attribute__((noinline))
#define RAF_NORETURN __attribute__((noreturn))
#define RAF_UNUSED __attribute__((unused))

#define RAF_NULL ((void*)0)
#define RAF_TERMUX_PREFIX_DEFAULT "/data/data/com.termux/files/usr"

#endif
