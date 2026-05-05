#ifndef RAF_CYCLE_H
#define RAF_CYCLE_H
#include "raf_policy_kernel.h"
#include "raf_types.h"
typedef struct { bool8 proceeded; } RafCycleState;
RAF_INLINE void raf_cycle_step(RafCycleState* s,const RafEthicaVec* e){ s->proceeded=raf_ethica_should_proceed(e); }
#endif
