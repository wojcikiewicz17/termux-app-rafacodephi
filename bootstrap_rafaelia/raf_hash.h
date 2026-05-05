#ifndef RAF_HASH_H
#define RAF_HASH_H
#include "raf_types.h"
RAF_INLINE u32 raf_crc32c(const u8* data, usize len){ u32 crc=0xFFFFFFFFu; for(usize i=0;i<len;i++){ crc^=data[i]; for(u32 b=0;b<8;b++) crc=(crc&1)?((crc>>1)^0x82F63B78u):(crc>>1);} return ~crc; }
RAF_INLINE u64 raf_hash64_fnv1a(const u8* data, usize len){ u64 h=0xcbf29ce484222325ULL; for(usize i=0;i<len;i++){ h^=data[i]; h*=0x100000001b3ULL;} return h; }
RAF_INLINE u64 raf_hash64_u64(u64 x){ return raf_hash64_fnv1a((const u8*)&x,sizeof(x)); }
#endif
