#ifndef RAF_BITRAF_H
#define RAF_BITRAF_H
#include "raf_types.h"
typedef struct { bool8 witness; bool8 sealed; } RafBitraf;
RAF_INLINE void raf_bitraf_init(RafBitraf* b){b->witness=RAF_FALSE; b->sealed=RAF_FALSE;}
RAF_INLINE void raf_bitraf_set_witness(RafBitraf* b, bool8 w){b->witness=w;}
RAF_INLINE void raf_bitraf_seal(RafBitraf* b){if(b->witness) b->sealed=RAF_TRUE;}
RAF_INLINE bool8 raf_bitraf_verify(const RafBitraf* b){ return (b->witness && b->sealed)?RAF_TRUE:RAF_FALSE; }
#endif
