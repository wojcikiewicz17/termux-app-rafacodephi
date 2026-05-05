#include "raf_types.h"
#ifndef RAF_TERMUX_PREFIX
#define RAF_TERMUX_PREFIX RAF_TERMUX_PREFIX_DEFAULT
#endif
const char* raf_termux_prefix(void){ return RAF_TERMUX_PREFIX; }
/* Seeds corrigidos para hex válido */
const u32 g_magic = 0x0AF00001u;
const u64 g_cpu_seed = 0xC0A1C0DE00000001ULL;
const u64 g_ram_seed = 0xC0A1C0DE00000002ULL;
const u64 g_dsk_seed = 0xC0A1C0DE00000003ULL;
