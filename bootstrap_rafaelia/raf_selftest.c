#include <stdio.h>
#include "raf_mem.h"
#include "raf_hash.h"
#include "raf_arena.h"
#include "raf_bitraf.h"
#include "raf_zipraf.h"
#include "raf_rafstore.h"
#include "raf_toroid.h"
#include "raf_cycle.h"

int raf_bootstrap_entry(void){ return 0; }
static int ok=0,fail=0;
#define T(c) do{ if(c) ok++; else {fail++; printf("FAIL:%s\n",#c);} }while(0)

typedef struct { const char* s; u32 crc32c; u64 fnv1a64; } RafGolden;
static const RafGolden k_gold[] = {
    {"", 0x00000000u, 0xcbf29ce484222325ULL},
    {"a", 0xc1d04330u, 0xaf63dc4c8601ec8cULL},
    {"abc", 0x364b3fb7u, 0xe71fa2190541574bULL},
    {"message digest", 0x02bd79d0u, 0x2dcbcce86fce9934ULL}
};

int main(void){
    u8 a[8]; raf_memset(a,0xAA,8); T(a[0]==0xAA&&a[7]==0xAA);
    u8 b[8]; raf_memcpy(b,a,8); T(raf_memcmp(a,b,8)==0);
    T(raf_strlen("raf")==3);

    for (usize i=0;i<sizeof(k_gold)/sizeof(k_gold[0]);i++) {
        const u8* p=(const u8*)k_gold[i].s; usize n=raf_strlen(k_gold[i].s);
        T(raf_crc32c(p,n)==k_gold[i].crc32c);
        T(raf_hash64_fnv1a(p,n)==k_gold[i].fnv1a64);
    }

    u8 mem[16]; RafArena ar; raf_arena_init(&ar,mem,16); T(raf_arena_alloc(&ar,8)!=0); raf_arena_reset(&ar); T(ar.off==0);
    RafBitraf br; raf_bitraf_init(&br); T(!raf_bitraf_verify(&br)); raf_bitraf_set_witness(&br,RAF_TRUE); raf_bitraf_seal(&br); T(raf_bitraf_verify(&br));
    u8 in[4]={1,2,3,4},cmp[8],out[8]; usize pn=raf_zipraf_pack(in,4,cmp,8); usize un=raf_zipraf_unpack(cmp,pn,out,8); T(un==4&&raf_memcmp(in,out,4)==0);
    RafRing r; u64 v=0; raf_ring_init(&r); T(raf_ring_push(&r,42)&&raf_ring_pop(&r,&v)&&v==42);
    RafKV kv; raf_kv_init(&kv); T(raf_kv_set(&kv,7,99)&&raf_kv_get(&kv,7,&v)&&v==99);
    RafToroid t; raf_toroid_init(&t,8,8); T(raf_toroid_wrap(&t,-1,8)==7);
    RafCycleState cs={0}; RafEthicaVec e1={RAF_TRUE}, e2={RAF_FALSE}; raf_cycle_step(&cs,&e1); T(cs.proceeded==RAF_TRUE); raf_cycle_step(&cs,&e2); T(cs.proceeded==RAF_FALSE);

    printf("ok=%d fail=%d\n",ok,fail);
    return fail?1:0;
}
