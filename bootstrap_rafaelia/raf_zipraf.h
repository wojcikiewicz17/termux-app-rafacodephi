#ifndef RAF_ZIPRAF_H
#define RAF_ZIPRAF_H
#include "raf_types.h"
#include "raf_mem.h"
/* ZIPRAF experimental: formato próprio, não extrai ZIP real */
RAF_INLINE usize raf_zipraf_pack(const u8* in, usize n, u8* out, usize cap){ if(cap<n+1) return 0; out[0]=0x5A; raf_memcpy(out+1,in,n); return n+1; }
RAF_INLINE usize raf_zipraf_unpack(const u8* in, usize n, u8* out, usize cap){ if(n<1||in[0]!=0x5A||cap<(n-1)) return 0; raf_memcpy(out,in+1,n-1); return n-1; }
#endif
