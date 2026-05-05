#ifndef RAF_RAFSTORE_H
#define RAF_RAFSTORE_H
#include "raf_types.h"
#define RAF_RING_CAP 16
#define RAF_KV_CAP 16
typedef struct { u64 v[RAF_RING_CAP]; u32 head,tail,count; } RafRing;
typedef struct { u32 key; u64 val; bool8 used; } RafKVEntry;
typedef struct { RafKVEntry e[RAF_KV_CAP]; } RafKV;
RAF_INLINE void raf_ring_init(RafRing* r){r->head=r->tail=r->count=0;}
RAF_INLINE bool8 raf_ring_push(RafRing* r,u64 x){ if(r->count==RAF_RING_CAP) return RAF_FALSE; r->v[r->tail]=x; r->tail=(r->tail+1)%RAF_RING_CAP; r->count++; return RAF_TRUE;}
RAF_INLINE bool8 raf_ring_pop(RafRing* r,u64* out){ if(!r->count) return RAF_FALSE; *out=r->v[r->head]; r->head=(r->head+1)%RAF_RING_CAP; r->count--; return RAF_TRUE;}
RAF_INLINE void raf_kv_init(RafKV* k){for(u32 i=0;i<RAF_KV_CAP;i++)k->e[i].used=RAF_FALSE;}
RAF_INLINE bool8 raf_kv_set(RafKV* k,u32 key,u64 val){ for(u32 i=0;i<RAF_KV_CAP;i++) if(k->e[i].used&&k->e[i].key==key){k->e[i].val=val; return RAF_TRUE;} for(u32 i=0;i<RAF_KV_CAP;i++) if(!k->e[i].used){k->e[i].used=RAF_TRUE;k->e[i].key=key;k->e[i].val=val;return RAF_TRUE;} return RAF_FALSE;}
RAF_INLINE bool8 raf_kv_get(RafKV* k,u32 key,u64* out){ for(u32 i=0;i<RAF_KV_CAP;i++) if(k->e[i].used&&k->e[i].key==key){*out=k->e[i].val; return RAF_TRUE;} return RAF_FALSE;}
#endif
