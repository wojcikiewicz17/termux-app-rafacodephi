#ifndef RAF_POLICY_KERNEL_H
#define RAF_POLICY_KERNEL_H
#include "raf_types.h"
typedef struct { bool8 ethica_ok; } RafEthicaVec;
RAF_INLINE bool8 raf_ethica_should_proceed(const RafEthicaVec* v){ return v->ethica_ok?RAF_TRUE:RAF_FALSE; }
#endif
