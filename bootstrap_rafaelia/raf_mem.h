#ifndef RAF_MEM_H
#define RAF_MEM_H
#include "raf_types.h"

RAF_INLINE void* raf_memset(void* d, u8 v, usize n){u8* p=(u8*)d; for(usize i=0;i<n;i++)p[i]=v; return d;}
RAF_INLINE void* raf_memcpy(void* d,const void* s,usize n){u8* dd=(u8*)d; const u8* ss=(const u8*)s; for(usize i=0;i<n;i++)dd[i]=ss[i]; return d;}
RAF_INLINE s32 raf_memcmp(const void* a,const void* b,usize n){const u8* x=(const u8*)a; const u8* y=(const u8*)b; for(usize i=0;i<n;i++){if(x[i]!=y[i]) return (s32)x[i]-(s32)y[i];} return 0;}
RAF_INLINE usize raf_strlen(const char* s){usize n=0; while(s && s[n]) n++; return n;}
#endif
