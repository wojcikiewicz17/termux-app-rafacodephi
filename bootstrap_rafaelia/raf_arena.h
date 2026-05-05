#ifndef RAF_ARENA_H
#define RAF_ARENA_H
#include "raf_types.h"

typedef struct { u8* base; usize cap; usize off; } RafArena;
RAF_INLINE void raf_arena_init(RafArena* a, void* mem, usize cap){a->base=(u8*)mem;a->cap=cap;a->off=0;}
RAF_INLINE void* raf_arena_alloc(RafArena* a, usize n){ if(a->off+n>a->cap) return RAF_NULL; void* p=a->base+a->off; a->off+=n; return p; }
RAF_INLINE void raf_arena_reset(RafArena* a){a->off=0;}
#endif
