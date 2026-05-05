#ifndef RAF_TOROID_H
#define RAF_TOROID_H
#include "raf_types.h"
typedef struct { s32 w,h; } RafToroid;
RAF_INLINE void raf_toroid_init(RafToroid* t,s32 w,s32 h){t->w=w;t->h=h;}
RAF_INLINE s32 raf_toroid_wrap(const RafToroid* t,s32 x,s32 m){(void)t; s32 r=x%m; return r<0?r+m:r;}
#endif
