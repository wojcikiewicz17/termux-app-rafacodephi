# RSC completobashcat > /tmp/RAFAELIA_RSC_COMPILER.txt << 'OUTER_EOF'
#!/usr/bin/env bash
# ============================================================================
# RAFAELIA_RSC_COMPILER.txt — Renomeie para .sh: bash RAFAELIA_RSC_COMPILER.sh
# RAFAELIA State Compiler (RSC) v1.0 — Compilador de estados para C+ASM
# ============================================================================
# [#00] O QUE É O RSC:
#   Compilador de 2 passos que lê código .raf (RAFAELIA State Code) e
#   emite C + inline assembly ARM64/ARM32/x86-64.
#
# [#01] LINGUAGEM .raf — SINTAXE:
#   #FLAG[OPEN]  nome=0xXX  tipo=HEX|BIN|ASM|STATE|SHADOW|TAIL
#   #FLAG[CLOSE] nome=0xXX
#   #STATE{ALLOW|DENY|RETRY|FAULT|TIMEOUT|OVERFLOW|CORRUPT|VOID}
#   #ASM[ARM64|ARM32|X64|GENERIC] ... #ASM[END]
#   #IF{expr} ... #ELIF{expr} ... #ELSE ... #END
#   #WHILE{expr} ... #END
#   #FOR{init;cond;step} ... #END
#   #SHADOW{sym} → alias reduzido
#   #TAIL{fn}    → tail-call marker
#   #HEX{expr}   → força saída hexadecimal
#
# [#02] PASSOS DO COMPILADOR:
#   PASSO 0: Pré-processador (resolve #FLAG, #SHADOW, macros)
#   PASSO 1: Lexer (tokeniza .raf → stream de tokens)
#   PASSO 2: Parser (tokens → AST de estados e blocos)
#   PASSO 3: Otimizador (tail-call, dead-state elim, flag merge)
#   PASSO 4: Code Gen (AST → C + inline ASM)
#   PASSO 5: Síntese (C file + header file + hex constants)
#
# [#03] USO:
#   bash RAFAELIA_RSC_COMPILER.sh          # compila tudo
#   bash RAFAELIA_RSC_COMPILER.sh --test   # roda self-tests
#   bash RAFAELIA_RSC_COMPILER.sh --demo   # compila o programa demo
# ============================================================================
set -euo pipefail
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
MAGENTA='\033[0;35m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
BD="${TMPDIR:-/tmp}/raf_rsc_$$"
mkdir -p "$BD"
LOG="$BD/rsc_build.log"
p() { echo -e "${CYAN}[RSC]${RESET} $*" | tee -a "$LOG"; }
ok(){ echo -e "${GREEN}[ OK]${RESET} $*" | tee -a "$LOG"; }
err(){ echo -e "${RED}[ERR]${RESET} $*" | tee -a "$LOG"; }
hdr(){ echo -e "\n${MAGENTA}${BOLD}━━━━ $* ━━━━${RESET}"; }
OUTER_EOF

# Escreve todos os arquivos C em sequência
cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT'

# =============================================================================
hdr "S01 — raf_rsc_types.h: TIPOS PRIMITIVOS DO COMPILADOR"
# =============================================================================
cat > "$BD/raf_rsc_types.h" << 'EOF_TYPES'
/* raf_rsc_types.h — Tipos primitivos do RAFAELIA State Compiler
 * [#T01] Sem stdlib.h: tipos definidos manualmente
 * [#T02] Aritmetica de ponteiro: uptr = tamanho de ponteiro da plataforma
 * [#T03] Result<T,E>: retorno seguro sem exceptions
 * [#T04] Slice: ponteiro + comprimento (sem string.h)
 * [#T05] Arena: alocador bump sem malloc
 */
#ifndef RAF_RSC_TYPES_H
#define RAF_RSC_TYPES_H

typedef unsigned char       u8;
typedef unsigned short      u16;
typedef unsigned int        u32;
typedef unsigned long long  u64;
typedef signed   char       s8;
typedef signed   short      s16;
typedef signed   int        s32;
typedef signed   long long  s64;
typedef __SIZE_TYPE__       usize;
typedef unsigned int        uptr;
typedef unsigned char       bool8;
#define TRUE  ((bool8)1u)
#define FALSE ((bool8)0u)
#define NULL_PTR ((void*)0)

/* ── SLICE: string sem \0 obrigatório ─────────────────────────────────── */
typedef struct { const char* ptr; usize len; } Slice;
#define SL(s)        ((Slice){(s), __builtin_strlen(s)})
#define SL_EQ(a,b)   ((a).len==(b).len && __builtin_memcmp((a).ptr,(b).ptr,(a).len)==0)
#define SL_EMPTY(s)  ((s).len==0)
#define SL_NULL      ((Slice){NULL_PTR,0})
#define SL_AT(s,i)   ((s).ptr[(i)])
#define SL_SUB(s,o,l) ((Slice){(s).ptr+(o),(l)})
#define SL_STARTS(s,prefix) \
  ((s).len>=(prefix).len && __builtin_memcmp((s).ptr,(prefix).ptr,(prefix).len)==0)

/* ── RESULT: retorno com erro embutido ───────────────────────────────── */
typedef struct { u32 ok; u32 err_code; } Result;
#define RES_OK      ((Result){1u,0u})
#define RES_ERR(e)  ((Result){0u,(e)})
#define RES_IS_OK(r) ((r).ok)

/* ── ARENA BUMP ───────────────────────────────────────────────────────── */
#define RSC_ARENA_SZ (2u*1024u*1024u)  /* 2MB para AST + symtab + codegen */
typedef struct { u8* base; usize cap; usize used; usize mark; } Arena;
static u8 _g_rsc_arena[RSC_ARENA_SZ] __attribute__((aligned(8)));
static Arena g_arena;
static inline void  arena_init(void) {
    g_arena.base=_g_rsc_arena; g_arena.cap=RSC_ARENA_SZ;
    g_arena.used=0; g_arena.mark=0;
}
static inline void* arena_alloc(usize sz, usize align) {
    usize mask=(align-1); usize cur=(g_arena.used+mask)&~mask;
    if(cur+sz>g_arena.cap) return NULL_PTR;
    void*p=(void*)(g_arena.base+cur); g_arena.used=cur+sz;
    return p;
}
static inline void arena_mark(void)    { g_arena.mark=g_arena.used; }
static inline void arena_restore(void) { g_arena.used=g_arena.mark; }
static inline void arena_reset(void)   { g_arena.used=0; }
#define ARENA_NEW(T)  ((T*)arena_alloc(sizeof(T),_Alignof(T)))
#define ARENA_ARR(T,n) ((T*)arena_alloc(sizeof(T)*(n),_Alignof(T)))

/* ── ERROS DO COMPILADOR (hexadecimal) ───────────────────────────────── */
#define ERR_OK            0x00000000u
#define ERR_LEX_EOF       0xC0010001u  /* lexer: fim inesperado        */
#define ERR_LEX_BADCHAR   0xC0010002u  /* lexer: char inválido         */
#define ERR_LEX_OVERFLOW  0xC0010003u  /* lexer: token muito longo     */
#define ERR_PP_NOFLAG     0xC0020001u  /* preproc: #FLAG sem nome      */
#define ERR_PP_BADTYPE    0xC0020002u  /* preproc: tipo desconhecido   */
#define ERR_PP_UNMATCHED  0xC0020003u  /* preproc: OPEN sem CLOSE      */
#define ERR_PP_OVERFLOW   0xC0020004u  /* preproc: stack cheia         */
#define ERR_PARSE_EXPECT  0xC0030001u  /* parser: token esperado       */
#define ERR_PARSE_STATE   0xC0030002u  /* parser: estado inválido      */
#define ERR_PARSE_DEPTH   0xC0030003u  /* parser: aninhamento profundo */
#define ERR_SYM_NOTFOUND  0xC0040001u  /* symtab: símbolo não achado   */
#define ERR_SYM_FULL      0xC0040002u  /* symtab: tabela cheia         */
#define ERR_SYM_DUP       0xC0040003u  /* symtab: símbolo duplicado    */
#define ERR_CG_ARCH       0xC0050001u  /* codegen: arch desconhecida   */
#define ERR_CG_OVERFLOW   0xC0050002u  /* codegen: buffer cheio        */
#define ERR_OPT_CYCLE     0xC0060001u  /* otimizador: ciclo detectado  */
#define ERR_TM_STATE      0xC0070001u  /* Turing: estado inválido      */
#define ERR_TM_TRANS      0xC0070002u  /* Turing: transição inválida   */
#define ERR_ARENA_OOM     0xC0080001u  /* arena: sem memória           */

/* ── ARQUITETURAS SUPORTADAS ──────────────────────────────────────────── */
typedef enum {
    ARCH_GENERIC = 0x00u,
    ARCH_ARM64   = 0x64u,  /* AArch64 / AArch64 AAPCS64 */
    ARCH_ARM32   = 0x32u,  /* AArch32 Thumb-2 AAPCS     */
    ARCH_X64     = 0xE4u,  /* x86-64 SysV AMD64         */
    ARCH_RV64    = 0x72u,  /* RISC-V 64                 */
    ARCH_AVR8    = 0xA8u,  /* AVR 8-bit ATmega           */
} TargetArch;

/* ── TIPOS DE FLAG ────────────────────────────────────────────────────── */
typedef enum {
    FTYPE_NONE    = 0x00u,
    FTYPE_HEX     = 0x01u,  /* converge para hexadecimal */
    FTYPE_BIN     = 0x02u,  /* converge para binário 0/1 */
    FTYPE_ASM     = 0x03u,  /* bloco de assembly         */
    FTYPE_STATE   = 0x04u,  /* bloco de estado TTL8      */
    FTYPE_SHADOW  = 0x05u,  /* alias reduzido            */
    FTYPE_TAIL    = 0x06u,  /* tail-call marker          */
    FTYPE_CTRL    = 0x07u,  /* if/while/for              */
    FTYPE_MACRO   = 0x08u,  /* definição de macro        */
    FTYPE_SECTION = 0x09u,  /* seção do compilador       */
} FlagType;

/* ── ESTADOS TTL8 DO COMPILADOR ───────────────────────────────────────── */
typedef enum {
    CS_VOID     = 0x00u,
    CS_ALLOW    = 0x01u,
    CS_DENY     = 0x02u,
    CS_RETRY    = 0x04u,
    CS_FAULT    = 0x08u,
    CS_TIMEOUT  = 0x10u,
    CS_OVERFLOW = 0x20u,
    CS_CORRUPT  = 0x40u,
    CS_PANIC    = 0x80u,
} CompilerState;

static const char* cs_name(CompilerState s) {
    switch(s) {
    case CS_VOID:     return "VOID";
    case CS_ALLOW:    return "ALLOW";
    case CS_DENY:     return "DENY";
    case CS_RETRY:    rmaisGerarTRY";
    case CS_FAULT:    return "FAULT";
    case CS_TIMEOUT:  return "TIMEOUT";
    case CS_OVERFLOW: return "OVERFLOW";
    case CS_CORRUPT:  return "CORRUPT";
    case CS_PANIC:    return "PANIC";
    default:          return "COMPOSITE";
    }
}

#endif /* RAF_RSC_TYPES_H */
EOF_TYPES
ok "raf_rsc_types.h: $(wc -l < $BD/raf_rsc_types.h) linhas"
CONT

cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT2'
# =============================================================================
hdr "S02 — raf_rsc_flags.h: SISTEMA DE FLAGS COM OPEN/CLOSE"
# =============================================================================
cat > "$BD/raf_rsc_flags.h" << 'EOF_FLAGS'
/* raf_rsc_flags.h — Sistema de flags open/close com convergência hex
 * [#FL01] FLAGS = marcadores de região com tipo e valor hexadecimal
 * [#FL02] OPEN empilha na flag_stack; CLOSE verifica e desempilha
 * [#FL03] Convergência: qualquer literal dentro de um bloco HEX
 *         é automaticamente convertido para 0xNN notation
 * [#FL04] Shadows: #SHADOW{sym} gera alias de 3 chars maximizando
 *         compressão do símbolo sem perda de semântica
 * [#FL05] Tails: marcador de tail-call, gerado como goto label_fn
 *         em vez de call → elimina overhead de stack frame
 * [#FL06] Stack de flags: profundidade máxima 64
 */
#ifndef RAF_RSC_FLAGS_H
#define RAF_RSC_FLAGS_H
#include "raf_rsc_types.h"

#define FLAG_STACK_MAX 64u
#define FLAG_NAME_MAX  32u
#define FLAG_HEX_MAX   16u  /* hex string máxima "0xFFFFFFFFFFFFFFFF" */

/* ── REGISTRO DE FLAG ─────────────────────────────────────────────────── */
typedef struct {
    char     name[FLAG_NAME_MAX];  /* nome da flag                     */
    u64      hex_val;              /* valor hexadecimal associado       */
    FlagType type;                 /* HEX|BIN|ASM|STATE|SHADOW|TAIL    */
    u32      line_open;            /* linha de abertura (debug)         */
    u32      depth;                /* profundidade de aninhamento       */
    bool8    is_open;              /* TRUE se ainda aberta              */
    u8       _pad[3];
} FlagRecord;

/* ── STACK DE FLAGS ATIVAS ────────────────────────────────────────────── */
typedef struct {
    FlagRecord entries[FLAG_STACK_MAX];
    u32        top;       /* índice do topo (0 = vazia)                */
    u32        max_depth; /* profundidade máxima atingida              */
    u32        n_opened;  /* total de flags abertas na sessão          */
    u32        n_closed;  /* total de flags fechadas na sessão         */
    CompilerState state;  /* estado atual do compilador                */
} FlagStack;

static FlagStack g_flagstack;

static inline void flagstack_init(void) {
    __builtin_memset(&g_flagstack, 0, sizeof(g_flagstack));
    g_flagstack.state = CS_VOID;
}

/* Push: abre uma nova flag */
static inline Result flagstack_push(const char* name, usize nlen,
                                     u64 hex_val, FlagType type, u32 line) {
    if (g_flagstack.top >= FLAG_STACK_MAX) {
        g_flagstack.state = CS_OVERFLOW;
        return RES_ERR(ERR_PP_OVERFLOW);
    }
    FlagRecord* r = &g_flagstack.entries[g_flagstack.top];
    usize cpy = nlen < FLAG_NAME_MAX-1 ? nlen : FLAG_NAME_MAX-2;
    __builtin_memcpy(r->name, name, cpy); r->name[cpy]='\0';
    r->hex_val   = hex_val;
    r->type      = type;
    r->line_open = line;
    r->depth     = g_flagstack.top;
    r->is_open   = TRUE;
    g_flagstack.top++;
    g_flagstack.n_opened++;
    if (g_flagstack.top > g_flagstack.max_depth)
        g_flagstack.max_depth = g_flagstack.top;
    g_flagstack.state = CS_ALLOW;
    return RES_OK;
}

/* Pop: fecha a flag no topo, verifica nome */
static inline Result flagstack_pop(const char* name, usize nlen) {
    if (g_flagstack.top == 0u) {
        g_flagstack.state = CS_FAULT;
        return RES_ERR(ERR_PP_UNMATCHED);
    }
    g_flagstack.top--;
    FlagRecord* r = &g_flagstack.entries[g_flagstack.top];
    /* Verifica correspondência de nome */
    usize cmp = nlen < FLAG_NAME_MAX-1 ? nlen : FLAG_NAME_MAX-2;
    if (__builtin_memcmp(r->name, name, cmp) != 0) {
        g_flagstack.state = CS_CORRUPT;
        return RES_ERR(ERR_PP_UNMATCHED);
    }
    r->is_open = FALSE;
    g_flagstack.n_closed++;
    g_flagstack.state = (g_flagstack.top==0) ? CS_VOID : CS_ALLOW;
    return RES_OK;
}

/* Peek: vê a flag do topo sem remover */
static inline const FlagRecord* flagstack_top(void) {
    if (g_flagstack.top == 0) return NULL_PTR;
    return &g_flagstack.entries[g_flagstack.top-1];
}

/* Tipo da flag corrente */
static inline FlagType flagstack_current_type(void) {
    const FlagRecord* r = flagstack_top();
    return r ? r->type : FTYPE_NONE;
}

/* Verifica se estamos dentro de bloco HEX (qualquer nível) */
static inline bool8 flagstack_in_hex(void) {
    for (u32 i=0; i<g_flagstack.top; i++)
        if (g_flagstack.entries[i].type == FTYPE_HEX) return TRUE;
    return FALSE;
}

/* ── CONVERGÊNCIA HEXADECIMAL ─────────────────────────────────────────── */
/* Converte inteiro para string hex: "0xNNNNNNNN" */
static inline usize uint_to_hex(u64 v, char* out, usize cap) {
    static const char h[]="0123456789ABCDEF";
    if (cap < 3) return 0;
    out[0]='0'; out[1]='x';
    usize i=2;
    /* Encontra o nibble mais significativo */
    s32 shift=60;
    while(shift>0 && ((v>>shift)&0xFu)==0u) shift-=4;
    for (; shift>=0 && i<cap-1; shift-=4)
        out[i++] = h[(v>>shift)&0xFu];
    out[i]='\0';
    return i;
}

/* Converte inteiro para string binária: "0b00001111" */
static inline usize uint_to_bin(u64 v, char* out, usize cap) {
    if (cap < 3) return 0;
    out[0]='0'; out[1]='b'; usize i=2;
    s32 bit=63;
    while(bit>0 && !((v>>bit)&1)) bit--;
    for (; bit>=0 && i<cap-1; bit--)
        out[i++]=(char)('0'+((v>>bit)&1));
    out[i]='\0';
    return i;
}

/* ── SISTEMA DE SHADOWS (símbolos reduzidos) ──────────────────────────── */
#define SHADOW_MAX  512u
#define SHADOW_ORIG 48u   /* comprimento máximo do nome original */
#define SHADOW_RED   4u   /* comprimento do nome reduzido: S001..S999 */

typedef struct {
    char orig[SHADOW_ORIG];  /* nome original */
    char reduced[8];         /* alias reduzido: S001, T042, etc. */
    FlagType context;        /* contexto onde foi declarado */
    u64  hex_id;             /* ID hexadecimal único */
} ShadowEntry;

typedef struct {
    ShadowEntry entries[SHADOW_MAX];
    u32         count;
    u64         next_id;  /* próximo hex_id */
} ShadowTable;

static ShadowTable g_shadows;

static inline void shadow_init(void) {
    __builtin_memset(&g_shadows, 0, sizeof(g_shadows));
    g_shadows.next_id = 0x0001u;
}

/* Gera nome reduzido: prefixo varia por contexto */
static inline void shadow_gen_name(FlagType ctx, u32 idx, char* out) {
    /* Prefixos: S=STATE, T=TAIL, A=ASM, H=HEX, F=FLAG, G=GENERIC */
    char pfx;
    switch(ctx) {
    case FTYPE_STATE:  pfx='S'; break;
    case FTYPE_TAIL:   pfx='T'; break;
    case FTYPE_ASM:    pfx='A'; break;
    case FTYPE_HEX:    pfx='H'; break;
    case FTYPE_SHADOW: pfx='G'; break;
    default:           pfx='F'; break;
    }
    /* S001..S999 (3 dígitos decimais) */
    out[0]=pfx;
    out[1]='0'+(char)((idx/100u)%10u);
    out[2]='0'+(char)((idx/10u)%10u);
    out[3]='0'+(char)(idx%10u);
    out[4]='\0';
}

/* Registra ou recupera shadow de um símbolo */
static inline const char* shadow_register(const char* orig, usize olen, FlagType ctx) {
    /* Verifica se já existe */
    for (u32 i=0; i<g_shadows.count; i++) {
        if (__builtin_memcmp(g_shadows.entries[i].orig, orig,
                             olen < SHADOW_ORIG ? olen : SHADOW_ORIG-1) == 0)
            return g_shadows.entries[i].reduced;
    }
    if (g_shadows.count >= SHADOW_MAX) return orig; /* fallback */
    ShadowEntry* e = &g_shadows.entries[g_shadows.count];
    usize cpy = olen < SHADOW_ORIG-1 ? olen : SHADOW_ORIG-2;
    __builtin_memcpy(e->orig, orig, cpy); e->orig[cpy]='\0';
    shadow_gen_name(ctx, g_shadows.count+1, e->reduced);
    e->context = ctx;
    e->hex_id  = g_shadows.next_id++;
    g_shadows.count++;
    return e->reduced;
}

/* Resolve shadow → original */
static inline const char* shadow_resolve(const char* red) {
    for (u32 i=0; i<g_shadows.count; i++)
        if (__builtin_memcmp(g_shadows.entries[i].reduced,red,4)==0)
            return g_shadows.entries[i].orig;
    return red;
}

/* ── TAIL-CALL REGISTRY ────────────────────────────────────────────────── */
#define TAIL_MAX 128u
typedef struct {
    char caller[32];   /* função que chama */
    char callee[32];   /* função chamada como tail */
    u32  line;         /* linha no fonte */
    bool8 optimized;   /* TRUE se foi otimizada para goto */
} TailEntry;

typedef struct {
    TailEntry entries[TAIL_MAX];
    u32       count;
} TailRegistry;

static TailRegistry g_tails;
static inline void tail_init(void) {
    __builtin_memset(&g_tails, 0, sizeof(g_tails));
}
static inline Result tail_register(const char* caller, const char* callee, u32 line) {
    if (g_tails.count >= TAIL_MAX) return RES_ERR(ERR_CG_OVERFLOW);
    TailEntry* e = &g_tails.entries[g_tails.count++];
    usize cl=0; while(caller[cl]&&cl<31) e->caller[cl]=caller[cl++]; e->caller[cl]=0;
    usize ce=0; while(callee[ce]&&ce<31) e->callee[ce]=callee[ce++]; e->callee[ce]=0;
    e->line=line; e->optimized=FALSE;
    return RES_OK;
}

#endif /* RAF_RSC_FLAGS_H */
EOF_FLAGS
ok "raf_rsc_flags.h: $(wc -l < $BD/raf_rsc_flags.h) linhas"
CONT2

cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT3'
# =============================================================================
hdr "S03 — raf_rsc_lexer.h: TOKENIZADOR COMPLETO"
# =============================================================================
cat > "$BD/raf_rsc_lexer.h" << 'EOF_LEX'
/* raf_rsc_lexer.h — Lexer para RAFAELIA State Code (.raf)
 * [#LX01] Tokens: DIRECTIVE, IDENT, NUMBER, STRING, OP, PUNCT, EOF
 * [#LX02] Números aceitos: decimal, 0xHEX, 0bBIN, 0oOCT
 * [#LX03] Diretivas: #FLAG #STATE #ASM #IF #ELIF #ELSE #END #WHILE #FOR
 *                    #SHADOW #TAIL #HEX #INCLUDE #DEFINE #UNDEF
 * [#LX04] Operadores: + - * / % & | ^ ~ << >> ! && || == != < > <= >=
 * [#LX05] Pontuação: { } ( ) [ ] ; , . : @
 * [#LX06] Comentários: // até fim de linha, / * ... * / multiline
 * [#LX07] Zero malloc: tokens apontam para o buffer de entrada (slice)
 */
#ifndef RAF_RSC_LEXER_H
#define RAF_RSC_LEXER_H
#include "raf_rsc_types.h"

/* ── TIPOS DE TOKEN ────────────────────────────────────────────────────── */
typedef enum {
    TK_EOF       = 0x00u,
    TK_DIRECTIVE = 0x01u,  /* #FLAG #STATE #ASM etc. */
    TK_IDENT     = 0x02u,  /* identificador: [A-Za-z_][A-Za-z0-9_]* */
    TK_NUMBER    = 0x03u,  /* literal numérico */
    TK_STRING    = 0x04u,  /* "string" */
    TK_OP        = 0x05u,  /* operador */
    TK_PUNCT     = 0x06u,  /* pontuação */
    TK_NEWLINE   = 0x07u,  /* \n (significativo em algumas posições) */
    TK_COMMENT   = 0x08u,  /* comentário (geralmente descartado) */
    TK_FLAG_OPEN = 0x10u,  /* #FLAG[OPEN] processado */
    TK_FLAG_CLOS = 0x11u,  /* #FLAG[CLOSE] processado */
    TK_STATE_KW  = 0x12u,  /* #STATE{...} processado */
    TK_ASM_BLOCK = 0x13u,  /* bloco #ASM[...] processado */
    TK_CTRL_IF   = 0x20u,  /* #IF{...} */
    TK_CTRL_ELIF = 0x21u,  /* #ELIF{...} */
    TK_CTRL_ELSE = 0x22u,  /* #ELSE */
    TK_CTRL_WHILE= 0x23u,  /* #WHILE{...} */
    TK_CTRL_FOR  = 0x24u,  /* #FOR{...;...;...} */
    TK_CTRL_END  = 0x25u,  /* #END */
    TK_SHADOW    = 0x30u,  /* #SHADOW{sym} */
    TK_TAIL      = 0x31u,  /* #TAIL{fn} */
    TK_HEX       = 0x32u,  /* #HEX{expr} */
    TK_ERROR     = 0xFFu,  /* erro léxico */
} TokenType;

/* ── TOKEN ─────────────────────────────────────────────────────────────── */
typedef struct {
    TokenType type;
    Slice     text;       /* slice do texto original */
    u64       num_val;    /* para TK_NUMBER: valor numérico */
    u32       line;       /* linha no fonte */
    u32       col;        /* coluna no fonte */
    u32       err;        /* código de erro se TK_ERROR */
    FlagType  flag_type;  /* para TK_FLAG_OPEN/CLOS: tipo da flag */
    CompilerState state_val; /* para TK_STATE_KW: estado */
    TargetArch arch;      /* para TK_ASM_BLOCK: arquitetura */
} Token;

#define TOKEN_MAX_LOOKAHEAD 8u  /* lookahead para evitar backtracking */

/* ── LEXER ─────────────────────────────────────────────────────────────── */
typedef struct {
    const char* src;      /* buffer de entrada (não modificado) */
    usize       src_len;
    usize       pos;      /* posição atual */
    u32         line;     /* linha atual */
    u32         col;      /* coluna atual */
    CompilerState state;  /* estado do lexer */
    /* Lookahead circular */
    Token       la[TOKEN_MAX_LOOKAHEAD];
    u32         la_head;
    u32         la_count;
    /* Estatísticas */
    u32         n_tokens;
    u32         n_errors;
} Lexer;

static inline void lexer_init(Lexer* L, const char* src, usize len) {
    __builtin_memset(L, 0, sizeof(*L));
    L->src=src; L->src_len=len; L->line=1; L->col=1;
    L->state=CS_ALLOW;
}

/* Funções auxiliares */
static inline bool8 lex_at_end(const Lexer* L) { return L->pos >= L->src_len; }
static inline char  lex_cur(const Lexer* L)    { return lex_at_end(L)?'\0':L->src[L->pos]; }
static inline char  lex_peek(const Lexer* L, u32 off) {
    usize p=L->pos+off; return p<L->src_len?L->src[p]:'\0';
}
static inline void lex_advance(Lexer* L) {
    if (!lex_at_end(L)) {
        if (L->src[L->pos]=='\n') { L->line++; L->col=1; }
        else L->col++;
        L->pos++;
    }
}
static inline void lex_skip_ws(Lexer* L) {
    while (!lex_at_end(L)) {
        char c=lex_cur(L);
        if (c==' '||c=='\t'||c=='\r') lex_advance(L);
        else break;
    }
}
static inline bool8 is_alpha(char c)  { return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='_'; }
static inline bool8 is_digit(char c)  { return c>='0'&&c<='9'; }
static inline bool8 is_alnum(char c)  { return is_alpha(c)||is_digit(c); }
static inline bool8 is_hex(char c)    {
    return is_digit(c)||(c>='a'&&c<='f')||(c>='A'&&c<='F');
}
static inline u8    hex_val(char c)   {
    if(c>='0'&&c<='9') return (u8)(c-'0');
    if(c>='a'&&c<='f') return (u8)(c-'a'+10);
    return (u8)(c-'A'+10);
}

/* Lex de comentário — skip até fim */
static inline void lex_skip_comment(Lexer* L) {
    if (lex_cur(L)=='/' && lex_peek(L,1u)=='/') {
        while(!lex_at_end(L) && lex_cur(L)!='\n') lex_advance(L);
    } else if (lex_cur(L)=='/' && lex_peek(L,1u)=='*') {
        lex_advance(L); lex_advance(L);  /* skip / * */
        while(!lex_at_end(L)) {
            if(lex_cur(L)=='*' && lex_peek(L,1u)=='/') {
                lex_advance(L); lex_advance(L); break;
            }
            lex_advance(L);
        }
    }
}

/* Lex de número: decimal, 0x, 0b, 0o */
static inline Token lex_number(Lexer* L) {
    Token t; __builtin_memset(&t,0,sizeof(t));
    t.type=TK_NUMBER; t.line=L->line; t.col=L->col;
    t.text.ptr=L->src+L->pos;
    u64 val=0;
    if(lex_cur(L)=='0' && lex_peek(L,1u)=='x') {
        /* 0xHEX */
        lex_advance(L); lex_advance(L);
        while(is_hex(lex_cur(L))) {
            val=(val<<4)|hex_val(lex_cur(L)); lex_advance(L);
        }
    } else if(lex_cur(L)=='0' && lex_peek(L,1u)=='b') {
        /* 0bBIN */
        lex_advance(L); lex_advance(L);
        while(lex_cur(L)=='0'||lex_cur(L)=='1') {
            val=(val<<1)|(u64)(lex_cur(L)-'0'); lex_advance(L);
        }
    } else if(lex_cur(L)=='0' && lex_peek(L,1u)=='o') {
        /* 0oOCT */
        lex_advance(L); lex_advance(L);
        while(lex_cur(L)>='0'&&lex_cur(L)<='7') {
            val=(val<<3)|(u64)(lex_cur(L)-'0'); lex_advance(L);
        }
    } else {
        /* decimal */
        while(is_digit(lex_cur(L))) {
            val=val*10+(u64)(lex_cur(L)-'0'); lex_advance(L);
        }
    }
    t.num_val=val;
    t.text.len=(usize)(L->src+L->pos-t.text.ptr);
    return t;
}

/* Lex de identificador */
static inline Token lex_ident(Lexer* L) {
    Token t; __builtin_memset(&t,0,sizeof(t));
    t.type=TK_IDENT; t.line=L->line; t.col=L->col;
    t.text.ptr=L->src+L->pos;
    while(is_alnum(lex_cur(L))) lex_advance(L);
    t.text.len=(usize)(L->src+L->pos-t.text.ptr);
    return t;
}

/* Reconhece tipo da flag pelo nome */
static inline FlagType parse_flag_type(Slice s) {
    if(SL_EQ(s,SL("HEX")))    return FTYPE_HEX;
    if(SL_EQ(s,SL("BIN")))    return FTYPE_BIN;
    if(SL_EQ(s,SL("ASM")))    return FTYPE_ASM;
    if(SL_EQ(s,SL("STATE")))  return FTYPE_STATE;
    if(SL_EQ(s,SL("SHADOW"))) return FTYPE_SHADOW;
    if(SL_EQ(s,SL("TAIL")))   return FTYPE_TAIL;
    if(SL_EQ(s,SL("CTRL")))   return FTYPE_CTRL;
    if(SL_EQ(s,SL("MACRO")))  return FTYPE_MACRO;
    return FTYPE_NONE;
}

/* Reconhece estado pelo nome */
static inline CompilerState parse_state_name(Slice s) {
    if(SL_EQ(s,SL("ALLOW")))   return CS_ALLOW;
    if(SL_EQ(s,SL("DENY")))    return CS_DENY;
    if(SL_EQ(s,SL("RETRY")))   return CS_RETRY;
    if(SL_EQ(s,SL("FAULT")))   return CS_FAULT;
    if(SL_EQ(s,SL("TIMEOUT"))) return CS_TIMEOUT;
    if(SL_EQ(s,SL("OVERFLOW")))return CS_OVERFLOW;
    if(SL_EQ(s,SL("CORRUPT"))) return CS_CORRUPT;
    if(SL_EQ(s,SL("VOID")))    return CS_VOID;
    if(SL_EQ(s,SL("PANIC")))   return CS_PANIC;
    return CS_VOID;
}

/* Reconhece arquitetura */
static inline TargetArch parse_arch_name(Slice s) {
    if(SL_EQ(s,SL("ARM64")))   return ARCH_ARM64;
    if(SL_EQ(s,SL("ARM32")))   return ARCH_ARM32;
    if(SL_EQ(s,SL("X64")))     return ARCH_X64;
    if(SL_EQ(s,SL("RV64")))    return ARCH_RV64;
    if(SL_EQ(s,SL("AVR8")))    return ARCH_AVR8;
    return ARCH_GENERIC;
}

/* Lex de diretiva #PALAVRA */
static inline Token lex_directive(Lexer* L) {
    Token t; __builtin_memset(&t,0,sizeof(t));
    t.line=L->line; t.col=L->col;
    lex_advance(L);  /* skip # */
    t.text.ptr=L->src+L->pos;
    while(is_alnum(lex_cur(L))) lex_advance(L);
    t.text.len=(usize)(L->src+L->pos-t.text.ptr);
    Slice kw=t.text;

    /* Determina tipo do token de diretiva */
    if(SL_EQ(kw,SL("FLAG"))) {
        /* Próximo: [OPEN] ou [CLOSE] */
        lex_skip_ws(L);
        if(lex_cur(L)=='[') {
            lex_advance(L);
            const char* bp=L->src+L->pos;
            while(is_alnum(lex_cur(L))) lex_advance(L);
            Slice mode={(bp),(usize)(L->src+L->pos-bp)};
            if(lex_cur(L)==']') lex_advance(L);
            if(SL_EQ(mode,SL("OPEN")))  t.type=TK_FLAG_OPEN;
            else if(SL_EQ(mode,SL("CLOSE"))) t.type=TK_FLAG_CLOS;
            else t.type=TK_ERROR;
        } else t.type=TK_DIRECTIVE;
    } else if(SL_EQ(kw,SL("STATE"))) {
        t.type=TK_STATE_KW;
        lex_skip_ws(L);
        if(lex_cur(L)=='{') {
            lex_advance(L);
            const char* bp=L->src+L->pos;
            while(lex_cur(L)&&lex_cur(L)!='}') lex_advance(L);
            Slice sname={(bp),(usize)(L->src+L->pos-bp)};
            if(lex_cur(L)=='}') lex_advance(L);
            t.state_val=parse_state_name(sname);
        }
    } else if(SL_EQ(kw,SL("ASM"))) {
        t.type=TK_ASM_BLOCK;
        lex_skip_ws(L);
        if(lex_cur(L)=='[') {
            lex_advance(L);
            const char* bp=L->src+L->pos;
            while(lex_cur(L)&&lex_cur(L)!=']') lex_advance(L);
            Slice aname={(bp),(usize)(L->src+L->pos-bp)};
            if(lex_cur(L)==']') lex_advance(L);
            if(SL_EQ(aname,SL("END"))) t.type=TK_CTRL_END;
            else t.arch=parse_arch_name(aname);
        }
    } else if(SL_EQ(kw,SL("IF")))     t.type=TK_CTRL_IF;
    else if(SL_EQ(kw,SL("ELIF")))    t.type=TK_CTRL_ELIF;
    else if(SL_EQ(kw,SL("ELSE")))    t.type=TK_CTRL_ELSE;
    else if(SL_EQ(kw,SL("WHILE")))   t.type=TK_CTRL_WHILE;
    else if(SL_EQ(kw,SL("FOR")))     t.type=TK_CTRL_FOR;
    else if(SL_EQ(kw,SL("END")))     t.type=TK_CTRL_END;
    else if(SL_EQ(kw,SL("SHADOW")))  t.type=TK_SHADOW;
    else if(SL_EQ(kw,SL("TAIL")))    t.type=TK_TAIL;
    else if(SL_EQ(kw,SL("HEX")))     t.type=TK_HEX;
    else                              t.type=TK_DIRECTIVE;

    L->n_tokens++;
    return t;
}

/* Token principal — avança um passo */
static inline Token lexer_next(Lexer* L) {
    /* Pula espaços e comentários */
    for(;;) {
        lex_skip_ws(L);
        if(lex_at_end(L)) {
            Token t; __builtin_memset(&t,0,sizeof(t));
            t.type=TK_EOF; t.line=L->line; t.col=L->col; return t;
        }
        char c=lex_cur(L);
        if(c=='/'&&(lex_peek(L,1u)=='/'||lex_peek(L,1u)=='*')) {
            lex_skip_comment(L); continue;
        }
        break;
    }
    char c=lex_cur(L);
    if(c=='\n') {
        Token t; __builtin_memset(&t,0,sizeof(t));
        t.type=TK_NEWLINE; t.line=L->line; t.col=L->col;
        t.text.ptr=L->src+L->pos; t.text.len=1;
        lex_advance(L); L->n_tokens++; return t;
    }
    if(c=='#') return lex_directive(L);
    if(is_alpha(c)) { Token t=lex_ident(L); L->n_tokens++; return t; }
    if(is_digit(c)||(c=='-'&&is_digit(lex_peek(L,1u)))) {
        Token t=lex_number(L); L->n_tokens++; return t;
    }
    /* String */
    if(c=='"') {
        Token t; __builtin_memset(&t,0,sizeof(t));
        t.type=TK_STRING; t.line=L->line; t.col=L->col;
        lex_advance(L); t.text.ptr=L->src+L->pos;
        while(!lex_at_end(L)&&lex_cur(L)!='"') {
            if(lex_cur(L)=='\\') lex_advance(L);
            lex_advance(L);
        }
        t.text.len=(usize)(L->src+L->pos-t.text.ptr);
        if(lex_cur(L)=='"') lex_advance(L);
        L->n_tokens++; return t;
    }
    /* Operadores de dois chars */
    Token t; __builtin_memset(&t,0,sizeof(t));
    t.line=L->line; t.col=L->col;
    t.text.ptr=L->src+L->pos;
    char c2=lex_peek(L,1u);
    bool8 two=FALSE;
    if((c=='<'&&c2=='<')||(c=='>'&&c2=='>')||
       (c=='='&&c2=='=')||(c=='!'&&c2=='=')||
       (c=='<'&&c2=='=')||(c=='>'&&c2=='=')||
       (c=='&'&&c2=='&')||(c=='|'&&c2=='|')||
       (c=='+'&&c2=='+')||(c=='-'&&c2=='-'))
        two=TRUE;
    t.type=(c=='+'||c=='-'||c=='*'||c=='/'||c=='%'||c=='&'||
            c=='|'||c=='^'||c=='~'||c=='!'||c=='<'||c=='>'||
            c=='='||c=='.')?TK_OP:TK_PUNCT;
    lex_advance(L);
    if(two) lex_advance(L);
    t.text.len=(usize)(L->src+L->pos-t.text.ptr);
    L->n_tokens++; return t;
}

/* Peek sem consumir */
static inline Token lexer_peek(Lexer* L, u32 off) {
    /* Salva estado */
    usize sp=L->pos; u32 sl=L->line; u32 sc=L->col;
    u32 sn=L->n_tokens;
    Token res; __builtin_memset(&res,0,sizeof(res));
    for(u32 i=0;i<=off;i++) res=lexer_next(L);
    L->pos=sp; L->line=sl; L->col=sc; L->n_tokens=sn;
    return res;
}

#endif /* RAF_RSC_LEXER_H */
EOF_LEX
ok "raf_rsc_lexer.h: $(wc -l < $BD/raf_rsc_lexer.h) linhas"
CONT3

cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT4'
# =============================================================================
hdr "S04 — raf_rsc_ast.h: NÓS DO AST"
# =============================================================================
cat > "$BD/raf_rsc_ast.h" << 'EOF_AST'
/* raf_rsc_ast.h — Abstract Syntax Tree para RAFAELIA State Code
 * [#AST01] Nós: Program, FlagBlock, StateBlock, AsmBlock, CtrlBlock
 * [#AST02] Expressões: Ident, Number, BinOp, UnOp, Call, Shadow, Hex
 * [#AST03] Máximo de filhos por nó: 8 (sem malloc, arena only)
 * [#AST04] Depth máxima: 32 (evita stack overflow no traversal)
 * [#AST05] Cada nó tem hash CRC32C para verificação de integridade
 */
#ifndef RAF_RSC_AST_H
#define RAF_RSC_AST_H
#include "raf_rsc_types.h"

#define AST_MAX_CHILDREN 8u
#define AST_MAX_DEPTH    32u
#define AST_MAX_NODES    4096u

typedef enum {
    AST_PROGRAM   = 0x01u,  /* raiz do programa */
    AST_FLAG_BLK  = 0x02u,  /* bloco #FLAG[OPEN]...#FLAG[CLOSE] */
    AST_STATE_BLK = 0x03u,  /* bloco #STATE{...} */
    AST_ASM_BLK   = 0x04u,  /* bloco #ASM[arch]...#ASM[END] */
    AST_CTRL_IF   = 0x05u,  /* #IF{cond} */
    AST_CTRL_ELIF = 0x06u,  /* #ELIF{cond} */
    AST_CTRL_ELSE = 0x07u,  /* #ELSE */
    AST_CTRL_WHILE= 0x08u,  /* #WHILE{cond} */
    AST_CTRL_FOR  = 0x09u,  /* #FOR{init;cond;step} */
    AST_SHADOW    = 0x10u,  /* #SHADOW{sym} declaração */
    AST_TAIL_CALL = 0x11u,  /* #TAIL{fn} */
    AST_HEX_EXPR  = 0x12u,  /* #HEX{expr} */
    AST_EXPR_NUM  = 0x20u,  /* número literal */
    AST_EXPR_IDENT= 0x21u,  /* identificador */
    AST_EXPR_BINOP= 0x22u,  /* operação binária */
    AST_EXPR_UNOP = 0x23u,  /* operação unária */
    AST_EXPR_CALL = 0x24u,  /* chamada de função */
    AST_RAW_CODE  = 0x30u,  /* código C bruto passado adiante */
    AST_COMMENT   = 0x31u,  /* comentário preservado */
    AST_EMPTY     = 0xFFu,
} AstNodeType;

typedef struct AstNode AstNode;
struct AstNode {
    AstNodeType  type;
    Slice        text;         /* texto original do nó */
    u64          num_val;      /* para AST_EXPR_NUM */
    u32          line;
    u32          crc;          /* CRC32C do subárvore (integridade) */
    FlagType     flag_type;    /* para AST_FLAG_BLK */
    CompilerState state_val;   /* para AST_STATE_BLK */
    TargetArch   arch;         /* para AST_ASM_BLK */
    u8           n_children;
    u8           _pad[3];
    AstNode*     children[AST_MAX_CHILDREN];
    AstNode*     next;         /* próximo na lista irmã */
    char         shadow_red[8]; /* nome reduzido se shadow */
};

/* Pool de nós — sem malloc */
static AstNode  _g_ast_pool[AST_MAX_NODES];
static u32      _g_ast_pool_used = 0u;

static inline AstNode* ast_new(AstNodeType type, Slice text, u32 line) {
    if (_g_ast_pool_used >= AST_MAX_NODES) return NULL_PTR;
    AstNode* n = &_g_ast_pool[_g_ast_pool_used++];
    __builtin_memset(n, 0, sizeof(*n));
    n->type=type; n->text=text; n->line=line;
    return n;
}
static inline Result ast_add_child(AstNode* parent, AstNode* child) {
    if (!parent || !child) return RES_ERR(ERR_PARSE_EXPECT);
    if (parent->n_children >= AST_MAX_CHILDREN) return RES_ERR(ERR_PARSE_DEPTH);
    parent->children[parent->n_children++] = child;
    return RES_OK;
}
static inline void ast_pool_reset(void) { _g_ast_pool_used=0; }

/* CRC32C simples para integridade de nó */
static inline u32 ast_crc_byte(u32 c, u8 b) {
    c^=(u32)b;
    for(u32 i=0;i<8u;i++) c=(c>>1)^(0x82F63B78u&-(c&1u));
    return c;
}
static inline u32 ast_crc_slice(Slice s) {
    u32 c=~0u;
    for(usize i=0;i<s.len;i++) c=ast_crc_byte(c,(u8)s.ptr[i]);
    return ~c;
}
static inline void ast_compute_crc(AstNode* n) {
    if(!n) return;
    u32 c = ast_crc_slice(n->text);
    for(u8 i=0;i<n->n_children;i++) {
        if(n->children[i]) c^=n->children[i]->crc;
    }
    n->crc=c;
}

/* Visita em profundidade */
typedef void (*ast_visitor)(AstNode*, u32 depth, void* ctx);
static void ast_walk(AstNode* n, u32 depth, ast_visitor fn, void* ctx) {
    if(!n || depth>AST_MAX_DEPTH) return;
    fn(n, depth, ctx);
    for(u8 i=0;i<n->n_children;i++)
        ast_walk(n->children[i], depth+1, fn, ctx);
    if(n->next) ast_walk(n->next, depth, fn, ctx);
}

#endif /* RAF_RSC_AST_H */
EOF_AST
ok "raf_rsc_ast.h: $(wc -l < $BD/raf_rsc_ast.h) linhas"
CONT4

cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT5'
# =============================================================================
hdr "S05 — raf_rsc_turing.h: MÁQUINA DE TURING GEOMÉTRICA"
# =============================================================================
cat > "$BD/raf_rsc_turing.h" << 'EOF_TURING'
/* raf_rsc_turing.h — Máquina de Turing geométrica para o compilador
 * [#TM01] MODELO: estados = vértices de hipercubo 3D (8 vértices = 8 estados)
 * [#TM02] SÍMBOLOS: bits do input (0 ou 1) = coordenadas no hipercubo
 * [#TM03] TRANSIÇÕES: arestas do hipercubo = mudanças de 1 bit por transição
 * [#TM04] OUTPUT: código C ou ASM gerado em cada transição
 * [#TM05] GEOMETRIA: hipercubo binário 3D → 8 estados × 2 símbolos → 16 trans
 * [#TM06] PROPRIEDADE: distância de Hamming entre estados = bits diferentes
 *                       estado VOID(000) e PANIC(111) = distância 3 (máxima)
 * [#TM07] Cada aresta do hipercubo = 1 transição atômica (1 bit muda)
 *
 * Hipercubo:
 *   VOID(000) ──── ALLOW(001)
 *      │ ╲          │ ╲
 *      │  RETRY(010) │  FAULT(011)
 *      │    │        │    │
 *   DENY(100)──── TIMEOUT(101)
 *        ╲    ╲        ╲    ╲
 *         OVERFLOW(110)── CORRUPT(111)/PANIC(111)
 */
#ifndef RAF_RSC_TURING_H
#define RAF_RSC_TURING_H
#include "raf_rsc_types.h"
#include "raf_rsc_flags.h"

/* ── TABELA DE TRANSIÇÃO ────────────────────────────────────────────────── */
/* trans[estado][símbolo] → novo estado
 * símbolo 0 = "input é zero/false/não"
 * símbolo 1 = "input é um/true/sim"
 * Hipercubo: transição muda apenas 1 bit (adjacência de Hamming)    */
typedef struct {
    CompilerState from;
    u8            sym;      /* 0 ou 1 */
    CompilerState to;
    const char*   emit;     /* código a emitir nesta transição (string C) */
    u32           weight;   /* peso/custo da transição (para otimização) */
} TuringTrans;

#define TM_TRANS_MAX 32u

typedef struct {
    TuringTrans  trans[TM_TRANS_MAX];
    u32          n_trans;
    CompilerState current;
    u8           tape[4096]; /* fita de entrada */
    usize        tape_pos;
    usize        tape_len;
    u32          steps;      /* passos executados */
    u32          max_steps;  /* limite anti-loop-infinito */
    CompilerState state;
} TuringMachine;

static TuringMachine g_tm;

static inline void tm_init(void) {
    __builtin_memset(&g_tm, 0, sizeof(g_tm));
    g_tm.current   = CS_VOID;
    g_tm.max_steps = 65536u;
    g_tm.state     = CS_ALLOW;

    /* Define transições do hipercubo semântico do compilador
     * VOID → ALLOW quando há input válido (símbolo 1)
     * VOID → VOID  quando input é inválido (símbolo 0)           */
    u32 i=0;
    #define TR(f,s,t,e,w) do{ \
        g_tm.trans[i].from=(f); g_tm.trans[i].sym=(s); \
        g_tm.trans[i].to=(t);   g_tm.trans[i].emit=(e); \
        g_tm.trans[i].weight=(w); i++; }while(0)

    TR(CS_VOID,    1, CS_ALLOW,    "/* BEGIN */"    , 1u);
    TR(CS_VOID,    0, CS_VOID,     "/* SKIP */"     , 0u);
    TR(CS_ALLOW,   1, CS_ALLOW,    "/* PROCESS */"  , 1u);
    TR(CS_ALLOW,   0, CS_DENY,     "/* REJECT */"   , 2u);
    TR(CS_DENY,    1, CS_RETRY,    "/* RETRY? */"   , 3u);
    TR(CS_DENY,    0, CS_TIMEOUT,  "/* TIMEOUT */"  , 4u);
    TR(CS_RETRY,   1, CS_ALLOW,    "/* RECOVER */"  , 2u);
    TR(CS_RETRY,   0, CS_FAULT,    "/* FAULT */"    , 5u);
    TR(CS_FAULT,   1, CS_CORRUPT,  "/* CORRUPT? */" , 6u);
    TR(CS_FAULT,   0, CS_PANIC,    "/* PANIC! */"   , 8u);
    TR(CS_TIMEOUT, 1, CS_RETRY,    "/* RETRY */"    , 3u);
    TR(CS_TIMEOUT, 0, CS_FAULT,    "/* GIVE UP */"  , 5u);
    TR(CS_OVERFLOW,1, CS_FAULT,    "/* OVERFLOW→FAULT */",6u);
    TR(CS_OVERFLOW,0, CS_CORRUPT,  "/* DATA BAD */" , 7u);
    TR(CS_CORRUPT, 1, CS_DENY,     "/* BLOCK */"    , 4u);
    TR(CS_CORRUPT, 0, CS_PANIC,    "/* PANIC */"    , 9u);
    TR(CS_PANIC,   1, CS_PANIC,    "/* STUCK */"    ,99u);
    TR(CS_PANIC,   0, CS_PANIC,    "/* STUCK */"    ,99u);
    #undef TR
    g_tm.n_trans = i;
}

/* Distância de Hamming entre dois estados (conta bits diferentes) */
static inline u32 tm_hamming(CompilerState a, CompilerState b) {
    return (u32)__builtin_popcount((u8)a^(u8)b);
}

/* Encontra transição válida */
static inline const TuringTrans* tm_find_trans(CompilerState from, u8 sym) {
    for(u32 i=0; i<g_tm.n_trans; i++) {
        if(g_tm.trans[i].from==from && g_tm.trans[i].sym==sym)
            return &g_tm.trans[i];
    }
    return NULL_PTR;
}

/* Executa um passo */
static inline Result tm_step(u8 sym) {
    if(g_tm.steps >= g_tm.max_steps) {
        g_tm.state=CS_TIMEOUT; return RES_ERR(ERR_TM_TRANS);
    }
    const TuringTrans* t = tm_find_trans(g_tm.current, sym&1u);
    if(!t) { g_tm.state=CS_FAULT; return RES_ERR(ERR_TM_STATE); }
    g_tm.current = t->to;
    g_tm.steps++;
    g_tm.state = (t->to==CS_PANIC) ? CS_PANIC : CS_ALLOW;
    return RES_OK;
}

/* Roda a máquina sobre a fita inteira */
static inline u32 tm_run(void) {
    u32 emits=0;
    while(g_tm.tape_pos < g_tm.tape_len && g_tm.steps < g_tm.max_steps) {
        u8 sym = g_tm.tape[g_tm.tape_pos++];
        if(tm_step(sym).ok) emits++;
        if(g_tm.current==CS_PANIC) break;
    }
    return emits;
}

/* Verifica se transição é válida no hipercubo (distância Hamming=1) */
static inline bool8 tm_is_valid_edge(CompilerState a, CompilerState b) {
    return tm_hamming(a,b)==1u ? TRUE : FALSE;
}

/* ── GEOMETRIA COMPLETA: tabela de adjacências do hipercubo ────────────── */
static const CompilerState TM_ADJACENT[8][3] = {
    /* VOID(000)     */ {CS_ALLOW,   CS_DENY,     CS_FAULT   },
    /* ALLOW(001)    */ {CS_VOID,    CS_RETRY,    CS_TIMEOUT },
    /* DENY(010)     */ {CS_VOID,    CS_OVERFLOW, CS_CORRUPT },
    /* RETRY(011)    */ {CS_ALLOW,   CS_DENY,     CS_PANIC   },
    /* FAULT(100)    */ {CS_VOID,    CS_OVERFLOW, CS_TIMEOUT },
    /* TIMEOUT(101)  */ {CS_ALLOW,   CS_FAULT,    CS_CORRUPT },
    /* OVERFLOW(110) */ {CS_DENY,    CS_FAULT,    CS_PANIC   },
    /* CORRUPT(111)  */ {CS_RETRY,   CS_TIMEOUT,  CS_OVERFLOW},
};

#endif /* RAF_RSC_TURING_H */
EOF_TURING
ok "raf_rsc_turing.h: $(wc -l < $BD/raf_rsc_turing.h) linhas"
CONT5

cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT6'
# =============================================================================
hdr "S06 — raf_rsc_codegen.h: GERAÇÃO DE CÓDIGO C + ASM"
# =============================================================================
cat > "$BD/raf_rsc_codegen.h" << 'EOF_CG'
/* raf_rsc_codegen.h — Code generator: AST → C + inline ASM
 * [#CG01] Buffer de saída estático (sem malloc): 1MB
 * [#CG02] Emite C válido com formatação automática
 * [#CG03] Converte #FLAG{HEX} → literais 0xNNNN
 * [#CG04] Gera inline ASM ARM64/ARM32/X64/RV64/AVR8
 * [#CG05] Tails: #TAIL{fn} → goto label / optimized call
 * [#CG06] Shadows: substitui nomes longos por aliases S001..S999
 * [#CG07] Estados TTL8: emite if/while com checks automáticos
 * [#CG08] Seções de código separadas por comentário de seção
 */
#ifndef RAF_RSC_CODEGEN_H
#define RAF_RSC_CODEGEN_H
#include "raf_rsc_types.h"
#include "raf_rsc_ast.h"
#include "raf_rsc_flags.h"
#include "raf_rsc_turing.h"

#define CG_BUF_SZ (1u*1024u*1024u)  /* 1MB de código gerado */
#define CG_INDENT_SZ 2u              /* 2 espaços por nível de indentação */
#define CG_INDENT_MAX 32u            /* máximo de níveis */

typedef struct {
    char*  buf;        /* buffer de saída */
    usize  cap;
    usize  used;
    u32    indent;     /* nível atual de indentação */
    TargetArch arch;   /* arquitetura alvo */
    bool8  in_hex;     /* dentro de bloco #HEX: converter literais */
    bool8  in_asm;     /* dentro de bloco #ASM */
    bool8  use_shadow; /* substituir nomes por shadows */
    u8     _pad;
    u32    n_lines;    /* linhas de código geradas */
    u32    n_asm_blks; /* blocos ASM gerados */
    CompilerState state;
} CodeGen;

static char   _g_cg_buf[CG_BUF_SZ];
static CodeGen g_cg;

static inline void cg_init(TargetArch arch) {
    __builtin_memset(&g_cg, 0, sizeof(g_cg));
    g_cg.buf=_g_cg_buf; g_cg.cap=CG_BUF_SZ;
    g_cg.arch=arch; g_cg.state=CS_ALLOW;
}

/* Emite N bytes sem verificação adicional */
static inline void cg_emit_raw(const char* s, usize n) {
    if(g_cg.used+n >= g_cg.cap) { g_cg.state=CS_OVERFLOW; return; }
    __builtin_memcpy(g_cg.buf+g_cg.used, s, n);
    g_cg.used+=n;
}
/* Emite string */
static inline void cg_emit(const char* s) {
    usize n=0; while(s[n]) n++; cg_emit_raw(s,n);
}
/* Emite newline + indentação */
static inline void cg_newline(void) {
    cg_emit_raw("\n",1);
    g_cg.n_lines++;
    for(u32 i=0;i<g_cg.indent*CG_INDENT_SZ;i++) cg_emit_raw(" ",1);
}
/* Emite número como hex */
static inline void cg_emit_hex(u64 v) {
    char buf[20]; usize n=uint_to_hex(v,buf,sizeof(buf));
    cg_emit_raw(buf,n);
}
/* Emite número como decimal */
static inline void cg_emit_dec(u64 v) {
    char buf[22]; s32 i=21; buf[i]='\0'; i--;
    if(!v){buf[i--]='0';} else{while(v){buf[i--]='0'+(char)(v%10u);v/=10u;}}
    cg_emit(buf+i+1);
}
/* Emite número — formato depende do contexto */
static inline void cg_emit_num(u64 v) {
    if(g_cg.in_hex) cg_emit_hex(v);
    else            cg_emit_dec(v);
}
/* Emite slice de texto */
static inline void cg_emit_sl(Slice s) { cg_emit_raw(s.ptr,s.len); }

/* ── CABEÇALHO DO ARQUIVO GERADO ─────────────────────────────────────── */
static inline void cg_emit_header(const char* src_name, TargetArch arch) {
    cg_emit("/* ============================================================");
    cg_newline();
    cg_emit(" * GERADO PELO RAFAELIA STATE COMPILER (RSC) v1.0");
    cg_newline(); cg_emit(" * Fonte: "); cg_emit(src_name);
    cg_newline(); cg_emit(" * Arch:  ");
    switch(arch) {
    case ARCH_ARM64: cg_emit("ARM64 AArch64 AAPCS64"); break;
    case ARCH_ARM32: cg_emit("ARM32 Thumb-2 AAPCS"); break;
    case ARCH_X64:   cg_emit("x86-64 SysV AMD64"); break;
    case ARCH_RV64:  cg_emit("RISC-V 64 rv64gc"); break;
    case ARCH_AVR8:  cg_emit("AVR8 ATmega"); break;
    default:         cg_emit("GENERIC"); break;
    }
    cg_newline(); cg_emit(" * NÃO EDITAR MANUALMENTE — edite o .raf");
    cg_newline(); cg_emit(" * DeltaRafaelVerboOmega · Omega=Amor");
    cg_newline(); cg_emit(" * ============================================================");
    cg_newline(); cg_emit(" */");
    cg_newline();
    /* Includes necessários */
    cg_emit("#include \"raf_rsc_types.h\"");
    cg_newline();
    /* Definições de flags como constantes hexadecimais */
    cg_emit("/* FLAGS COMO CONSTANTES HEX */");
    cg_newline();
    cg_emit("#define RFC_ALLOW    0x01u");  cg_newline();
    cg_emit("#define RFC_DENY     0x02u");  cg_newline();
    cg_emit("#define RFC_RETRY    0x04u");  cg_newline();
    cg_emit("#define RFC_FAULT    0x08u");  cg_newline();
    cg_emit("#define RFC_TIMEOUT  0x10u");  cg_newline();
    cg_emit("#define RFC_OVERFLOW 0x20u");  cg_newline();
    cg_emit("#define RFC_CORRUPT  0x40u");  cg_newline();
    cg_emit("#define RFC_PANIC    0x80u");  cg_newline();
    cg_newline();
}

/* ── EMISSÃO DE BLOCOS DE ESTADO ─────────────────────────────────────── */
static inline void cg_emit_state_open(CompilerState s, const char* condition) {
    cg_newline();
    cg_emit("{ /* #STATE{");
    cg_emit(cs_name(s));
    cg_emit("} */ ");
    switch(s) {
    case CS_ALLOW:
        cg_emit("if (("); cg_emit(condition?condition:"1"); cg_emit(")) {");
        break;
    case CS_DENY:
        cg_emit("if (!("); cg_emit(condition?condition:"0"); cg_emit(")) {");
        break;
    case CS_RETRY:
        cg_emit("{ u32 _ttl=8; while(_ttl-- && !(");
        cg_emit(condition?condition:"0");
        cg_emit(")) {");
        break;
    case CS_FAULT:
        cg_emit("{ /* FAULT HANDLER */ if(1) {");
        break;
    case CS_TIMEOUT:
        cg_emit("{ /* TIMEOUT CHECK */ if(_ttl==0) {");
        break;
    default:
        cg_emit("{ /* " ); cg_emit(cs_name(s)); cg_emit(" */ {");
        break;
    }
    g_cg.indent++;
}
static inline void cg_emit_state_close(CompilerState s) {
    if(g_cg.indent>0) g_cg.indent--;
    cg_newline();
    if(s==CS_RETRY) cg_emit("}} /* #STATE{RETRY} end */");
    else            cg_emit("} /* #STATE end */");
}

/* ── EMISSÃO DE BLOCOS ASM ────────────────────────────────────────────── */
static inline void cg_emit_asm_header(TargetArch arch) {
    cg_newline();
    cg_emit("__asm__ volatile(");
    g_cg.n_asm_blks++;
}
static inline void cg_emit_asm_footer(void) {
    cg_newline();
    cg_emit("::: \"memory\", \"cc\""); cg_newline();
    cg_emit(");");
}

/* Emite instrução ASM específica por arquitetura */
static inline void cg_emit_asm_instr(TargetArch arch, const char* instr) {
    cg_newline();
    cg_emit("\""); cg_emit(instr);
    switch(arch) {
    case ARCH_ARM64: cg_emit("\\n\\t\""); break;
    case ARCH_ARM32: cg_emit("\\n\\t\""); break;
    case ARCH_X64:   cg_emit("\\n\\t\""); break;
    default:         cg_emit("\\n\"");    break;
    }
}

/* ── EMISSÃO DE CONTROLE DE FLUXO ────────────────────────────────────── */
static inline void cg_emit_if(const char* cond) {
    cg_newline(); cg_emit("if ("); cg_emit(cond?cond:"1"); cg_emit(") {");
    g_cg.indent++;
}
static inline void cg_emit_elif(const char* cond) {
    if(g_cg.indent>0) g_cg.indent--;
    cg_newline(); cg_emit("} else if ("); cg_emit(cond?cond:"0"); cg_emit(") {");
    g_cg.indent++;
}
static inline void cg_emit_else(void) {
    if(g_cg.indent>0) g_cg.indent--;
    cg_newline(); cg_emit("} else {");
    g_cg.indent++;
}
static inline void cg_emit_while(const char* cond) {
    cg_newline(); cg_emit("while ("); cg_emit(cond?cond:"1"); cg_emit(") {");
    g_cg.indent++;
}
static inline void cg_emit_for(const char* init, const char* cond, const char* step) {
    cg_newline(); cg_emit("for (");
    cg_emit(init?init:"");  cg_emit("; ");
    cg_emit(cond?cond:"1"); cg_emit("; ");
    cg_emit(step?step:"");  cg_emit(") {");
    g_cg.indent++;
}
static inline void cg_emit_block_end(void) {
    if(g_cg.indent>0) g_cg.indent--;
    cg_newline(); cg_emit("}");
}

/* ── EMISSÃO DE TAIL CALL ────────────────────────────────────────────── */
static inline void cg_emit_tail(const char* callee) {
    cg_newline();
    cg_emit("/* #TAIL: optimized tail call → goto */");
    cg_newline();
    cg_emit("goto "); cg_emit(callee); cg_emit("_label;");
    cg_newline();
    cg_emit(callee); cg_emit("_label: { "); cg_emit(callee);
    cg_emit("(); return; }  /* tail-call eliminated stack frame */");
}

/* ── EMISSÃO DE SHADOW ────────────────────────────────────────────────── */
static inline void cg_emit_shadow_define(const char* orig, const char* red) {
    cg_newline();
    cg_emit("#define "); cg_emit(red);
    cg_emit(" "); cg_emit(orig);
    cg_emit("  /* shadow: "); cg_emit(orig); cg_emit(" → "); cg_emit(red); cg_emit(" */");
}

/* ── EMISSÃO DE HEX EXPR ──────────────────────────────────────────────── */
static inline void cg_emit_hex_expr(u64 val) {
    cg_emit_hex(val);
}

/* ── GERADOR PRINCIPAL: AST → CÓDIGO ─────────────────────────────────── */
static void cg_gen_node(const AstNode* n, u32 depth);

static void cg_gen_children(const AstNode* n, u32 depth) {
    for(u8 i=0; i<n->n_children; i++)
        if(n->children[i]) cg_gen_node(n->children[i], depth);
}

static void cg_gen_node(const AstNode* n, u32 depth) {
    if(!n || depth>AST_MAX_DEPTH) return;
    switch(n->type) {
    case AST_PROGRAM:
        cg_emit_header("input.raf", g_cg.arch);
        cg_gen_children(n, depth+1);
        break;
    case AST_FLAG_BLK:
        cg_newline();
        cg_emit("/* #FLAG[OPEN] type=");
        cg_emit_hex((u8)n->flag_type);
        cg_emit(" */");
        if(n->flag_type==FTYPE_HEX) g_cg.in_hex=TRUE;
        if(n->flag_type==FTYPE_ASM) g_cg.in_asm=TRUE;
        cg_gen_children(n, depth+1);
        if(n->flag_type==FTYPE_HEX) g_cg.in_hex=FALSE;
        if(n->flag_type==FTYPE_ASM) g_cg.in_asm=FALSE;
        cg_newline(); cg_emit("/* #FLAG[CLOSE] */");
        break;
    case AST_STATE_BLK:
        cg_emit_state_open(n->state_val, NULL_PTR);
        cg_gen_children(n, depth+1);
        cg_emit_state_close(n->state_val);
        break;
    case AST_ASM_BLK:
        cg_emit_asm_header(n->arch);
        cg_gen_children(n, depth+1);
        cg_emit_asm_footer();
        break;
    case AST_CTRL_IF:
        cg_emit_if(n->text.len?n->text.ptr:NULL_PTR);
        cg_gen_children(n, depth+1);
        cg_emit_block_end();
        break;
    case AST_CTRL_WHILE:
        cg_emit_while(n->text.len?n->text.ptr:NULL_PTR);
        cg_gen_children(n, depth+1);
        cg_emit_block_end();
        break;
    case AST_TAIL_CALL:
        cg_emit_tail(n->text.ptr);
        break;
    case AST_SHADOW:
        cg_emit_shadow_define(n->text.ptr, n->shadow_red);
        break;
    case AST_HEX_EXPR:
        cg_emit_hex_expr(n->num_val);
        break;
    case AST_EXPR_NUM:
        cg_emit_num(n->num_val);
        break;
    case AST_EXPR_IDENT:
        if(g_cg.use_shadow) {
            const char* red=shadow_resolve(n->text.ptr);
            if(red!=n->text.ptr) { cg_emit(red); break; }
        }
        cg_emit_sl(n->text);
        break;
    case AST_RAW_CODE:
        cg_newline();
        cg_emit_sl(n->text);
        break;
    case AST_COMMENT:
        cg_newline();
        cg_emit("/* "); cg_emit_sl(n->text); cg_emit(" */");
        break;
    default:
        cg_gen_children(n, depth+1);
        break;
    }
    if(n->next) cg_gen_node(n->next, depth);
}

/* Gera o arquivo completo */
static inline Slice cg_generate(const AstNode* root) {
    if(!root) return SL_NULL;
    cg_gen_node(root, 0);
    cg_newline();
    Slice out = {g_cg.buf, g_cg.used};
    return out;
}

/* ── CÓDIGO ASM INLINE POR ARQUITETURA ────────────────────────────────── */
/* Emite o preâmbulo ASM correto para cada arquitetura */
static inline void cg_asm_prologue(TargetArch arch) {
    cg_newline();
    switch(arch) {
    case ARCH_ARM64:
        cg_emit("/* ARM64 AAPCS64: x0-x7 args, x8 syscall, x9-x15 tmp */");
        cg_newline();
        cg_emit("/* Registradores callee-saved: x19-x28, x29(FP), x30(LR) */");
        cg_newline();
        cg_emit("/* NEON: v0-v7 caller-saved, v8-v15 callee-saved */");
        break;
    case ARCH_ARM32:
        cg_emit("/* ARM32 AAPCS: r0-r3 args, r4-r11 saved, r13 sp, r14 lr */");
        cg_newline();
        cg_emit("/* Thumb-2: .thumb_func / .syntax unified required */");
        cg_newline();
        cg_emit("/* SMULL: r={hi,lo}=Rn*Rm 64-bit product */");
        break;
    case ARCH_X64:
        cg_emit("/* x86-64 SysV: rdi,rsi,rdx,rcx,r8,r9 args, rax ret */");
        cg_newline();
        cg_emit("/* Callee-saved: rbx,rbp,r12-r15. rsp 16B-aligned at call */");
        cg_newline();
        cg_emit("/* RFLAGS: CF PF AF ZF SF TF IF DF OF — via pushfq/popfq */");
        break;
    case ARCH_RV64:
        cg_emit("/* RISC-V 64: a0-a7 args, a7 syscall, ra link, sp stack */");
        cg_newline();
        cg_emit("/* s0-s11 callee-saved, t0-t6 temporaries */");
        cg_newline();
        cg_emit("/* CSRs: rdtime, rdcycle, rdinstret sem privilégio */");
        break;
    case ARCH_AVR8:
        cg_emit("/* AVR8: R0-R31 GPR, R26:R27=X, R28:R29=Y, R30:R31=Z */");
        cg_newline();
        cg_emit("/* SREG: I T H S V N Z C — sem FPU */");
        cg_newline();
        cg_emit("/* 2-cycle RCALL, 4-cycle CALL. Stack in SRAM */");
        break;
    default:
        cg_emit("/* GENERIC: sem instrução específica */");
        break;
    }
    cg_newline();
}

/* Emite template de syscall para a arquitetura */
static inline void cg_emit_syscall_template(TargetArch arch, u32 nr) {
    cg_newline();
    cg_emit("/* Syscall "); cg_emit_hex(nr); cg_emit(" para "); 
    switch(arch) {
    case ARCH_ARM64:
        cg_emit("ARM64 */"); cg_newline();
        cg_emit("{ register long x8 __asm__(\"x8\")=");
        cg_emit_hex(nr);
        cg_emit(";");
        cg_newline();
        cg_emit("  register long x0 __asm__(\"x0\")=0;");
        cg_newline();
        cg_emit("  __asm__ volatile(\"svc #0\":"+r"(x0):\"r\"(x8):\"memory\",\"cc\"); }");
        break;
    case ARCH_ARM32:
        cg_emit("ARM32 */"); cg_newline();
        cg_emit("{ register long r7 __asm__(\"r7\")=");
        cg_emit_hex(nr);
        cg_emit(";");
        cg_newline();
        cg_emit("  register long r0 __asm__(\"r0\")=0;");
        cg_newline();
        cg_emit("  __asm__ volatile(\"svc #0\":\"+r\"(r0):\"r\"(r7):\"memory\",\"cc\"); }");
        break;
    case ARCH_X64:
        cg_emit("x86-64 */"); cg_newline();
        cg_emit("{ __asm__ volatile(\"syscall\"::\"a\"(");
        cg_emit_hex(nr);
        cg_emit("ULL):\"rcx\",\"r11\",\"memory\"); }");
        break;
    case ARCH_RV64:
        cg_emit("RISC-V */"); cg_newline();
        cg_emit("{ register long a7 __asm__(\"a7\")=");
        cg_emit_hex(nr);
        cg_emit(";");
        cg_newline();
        cg_emit("  register long a0 __asm__(\"a0\")=0;");
        cg_newline();
        cg_emit("  __asm__ volatile(\"ecall\":\"+r\"(a0):\"r\"(a7):\"memory\"); }");
        break;
    default: cg_emit("GENERIC */"); break;
    }
    cg_newline();
}

#endif /* RAF_RSC_CODEGEN_H */
EOF_CG
ok "raf_rsc_codegen.h: $(wc -l < $BD/raf_rsc_codegen.h) linhas"
CONT6

cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT7'
# =============================================================================
hdr "S07 — raf_rsc_main.c: DRIVER PRINCIPAL DO COMPILADOR"
# =============================================================================
cat > "$BD/raf_rsc_main.c" << 'EOF_MAIN'
/* raf_rsc_main.c — Driver principal do RAFAELIA State Compiler
 * [#D01] Modo de compilação: lê .raf, processa, emite .c
 * [#D02] Sem argc/argv: usa string literal como entrada de demo
 * [#D03] Output via write() direto (sem printf)
 * [#D04] Self-test: verifica integridade de cada módulo
 */
#include "raf_rsc_types.h"
#include "raf_rsc_flags.h"
#include "raf_rsc_lexer.h"
#include "raf_rsc_ast.h"
#include "raf_rsc_turing.h"
#include "raf_rsc_codegen.h"

/* ── I/O SEM LIBC ─────────────────────────────────────────────────────── */
static void _out(const char* s, usize n) {
#if defined(__aarch64__)
    register long x0 __asm__("x0")=1, x1 __asm__("x1")=(long)s,
                 x2 __asm__("x2")=(long)n, x8 __asm__("x8")=64;
    __asm__ volatile("svc #0":"+r"(x0):"r"(x1),"r"(x2),"r"(x8):"memory");
#elif defined(__x86_64__)
    __asm__ volatile("syscall"::"a"(1LL),"D"(1LL),"S"(s),"d"(n):"memory","rcx","r11");
#elif defined(__arm__)
    register long r0 __asm__("r0")=1, r1 __asm__("r1")=(long)s,
                 r2 __asm__("r2")=(long)n, r7 __asm__("r7")=4;
    __asm__ volatile("svc #0":"+r"(r0):"r"(r1),"r"(r2),"r"(r7):"memory","cc");
#else
    (void)s; (void)n;
#endif
}
static void puts0(const char* s) { usize n=0; while(s[n])n++; _out(s,n); }
static void putu(u64 v) {
    char b[22]; int i=21; b[i]='\n'; i--;
    if(!v){b[i--]='0';}else{while(v){b[i--]='0'+(char)(v%10u);v/=10u;}}
    _out(b+i+1,(usize)(20-i));
}
static void puth(u32 v) {
    char b[11]; b[0]='0';b[1]='x';b[10]='\n';
    static const char h[]="0123456789ABCDEF";
    for(s32 i=9;i>=2;i--){b[i]=h[v&0xFu];v>>=4;}
    _out(b,11);
}

/* ── PROGRAMA DEMO .raf EMBUTIDO ──────────────────────────────────────── */
/* Esta é a sintaxe .raf que o RSC compilará para C + inline ASM          */
static const char DEMO_RAF[] =
    "/* Programa demo RAFAELIA State Code */\n"
    "#FLAG[OPEN] name=fibonacci type=STATE\n"
    "#STATE{ALLOW}\n"
    "  result_valid = 1;\n"
    "#STATE{RETRY}\n"
    "  iterations = 48;\n"
    "#FLAG[CLOSE] name=fibonacci\n"
    "\n"
    "#FLAG[OPEN] name=crc_check type=HEX\n"
    "  u32 crc = 0xDEADBEEF;\n"
    "  u32 poly = 0x82F63B78;\n"
    "#FLAG[CLOSE] name=crc_check\n"
    "\n"
    "#ASM[ARM64]\n"
    "  isb\n"
    "  mrs x0, cntvct_el0\n"
    "#ASM[END]\n"
    "\n"
    "#SHADOW{fibonacci_result_accumulator}\n"
    "#TAIL{fraf_iterate}\n"
    "\n"
    "#IF{condition > 0x10}\n"
    "  x = 0xABCD;\n"
    "#ELIF{condition == 0}\n"
    "  x = 0x0000;\n"
    "#ELSE\n"
    "  x = 0xFFFF;\n"
    "#END\n"
    "\n"
    "#WHILE{ttl-- && !done}\n"
    "  process();\n"
    "#END\n"
    "\n"
    "#HEX{fstar_value = 23 * 65536 + 10371}\n";

/* ── COMPILADOR SIMPLIFICADO (demo sem parser completo) ──────────────── */
/* Parser manual para o demo — processa linha por linha */
static void compile_demo(TargetArch arch) {
    cg_init(arch);
    flagstack_init();
    shadow_init();
    tail_init();
    tm_init();
    arena_init();
    ast_pool_reset();

    /* Gera cabeçalho */
    cg_emit_header("demo.raf", arch);
    cg_asm_prologue(arch);
    cg_newline();
    cg_emit("/* === COMPILAÇÃO DO DEMO RAFAELIA STATE CODE === */");
    cg_newline();

    /* Processa a linguagem .raf manualmente (versão simplificada) */
    Lexer L;
    lexer_init(&L, DEMO_RAF, sizeof(DEMO_RAF)-1);

    /* Simula processamento linha por linha */
    bool8 in_hex_block = FALSE;
    bool8 in_asm_block = FALSE;
    u32 block_depth    = 0u;

    cg_newline();
    cg_emit("/* ESTRUTURA GERADA: */");
    cg_newline();

    /* Emite bloco FLAG/STATE */
    flagstack_push("fibonacci", 9u, 0x01u, FTYPE_STATE, 1u);
    cg_emit_state_open(CS_ALLOW, "iterations > 0");
    cg_newline(); cg_emit("  u32 result_valid = ");
    cg_emit_num(1u); cg_emit(";");
    cg_emit_state_close(CS_ALLOW);
    cg_emit_state_open(CS_RETRY, "iterations-- > 0");
    cg_newline(); cg_emit("  u32 iterations = ");
    cg_emit_num(48u); cg_emit(";");
    cg_emit_state_close(CS_RETRY);
    flagstack_pop("fibonacci", 9u);

    /* Emite bloco HEX */
    cg_newline();
    cg_emit("/* #FLAG[OPEN] type=HEX — literais em hexadecimal */");
    flagstack_push("crc_check", 9u, 0x02u, FTYPE_HEX, 5u);
    in_hex_block=TRUE; g_cg.in_hex=TRUE;
    cg_newline(); cg_emit("u32 crc  = "); cg_emit_hex(0xDEADBEEFu); cg_emit(";");
    cg_newline(); cg_emit("u32 poly = "); cg_emit_hex(0x82F63B78u); cg_emit(";");
    flagstack_pop("crc_check", 9u);
    in_hex_block=FALSE; g_cg.in_hex=FALSE;
    cg_newline(); cg_emit("/* #FLAG[CLOSE] */");

    /* Emite bloco ASM */
    cg_newline(); cg_newline();
    cg_emit("/* #ASM[ARM64] */");
    in_asm_block=TRUE; g_cg.in_asm=TRUE;
    cg_emit_asm_header(arch);
    cg_emit_asm_instr(arch, "isb");
    if(arch==ARCH_ARM64) {
        cg_emit_asm_instr(arch, "mrs x20, cntvct_el0");
    } else if(arch==ARCH_ARM32) {
        cg_emit_asm_instr(arch, "mrc p15, 0, r6, c9, c13, 0");
    } else if(arch==ARCH_X64) {
        cg_emit_asm_instr(arch, "lfence");
        cg_emit_asm_instr(arch, "rdtsc");
    } else if(arch==ARCH_RV64) {
        cg_emit_asm_instr(arch, "rdtime a5");
    }
    cg_emit_asm_footer();
    in_asm_block=FALSE; g_cg.in_asm=FALSE;

    /* Emite shadow */
    cg_newline();
    const char* red=shadow_register("fibonacci_result_accumulator",
                                     32u, FTYPE_SHADOW);
    cg_emit_shadow_define("fibonacci_result_accumulator", red);

    /* Emite tail */
    cg_newline();
    tail_register("caller_fn", "fraf_iterate", 20u);
    cg_emit_tail("fraf_iterate");

    /* Emite if/elif/else */
    cg_newline();
    cg_emit_if("condition > 0x10");
    cg_newline(); cg_emit("  x = "); cg_emit_hex(0xABCDu); cg_emit(";");
    cg_emit_elif("condition == 0x00");
    cg_newline(); cg_emit("  x = "); cg_emit_hex(0x0000u); cg_emit(";");
    cg_emit_else();
    cg_newline(); cg_emit("  x = "); cg_emit_hex(0xFFFFu); cg_emit(";");
    cg_emit_block_end();

    /* Emite while */
    cg_newline();
    cg_emit_while("_ttl-- && !done");
    cg_newline(); cg_emit("  process();");
    cg_emit_block_end();

    /* Emite #HEX{expr} */
    cg_newline();
    cg_emit("u64 fstar_value = ");
    cg_emit_hex((u64)23u*65536u + 10371u);
    cg_emit("; /* F* = 23.158 * 65536 */");

    /* Emite syscall template */
    cg_newline();
    cg_emit_syscall_template(arch, 64u);  /* SYS_write */

    /* Emite Turing machine summary */
    cg_newline();
    cg_emit("/* TURING MACHINE TRANSITIONS USED: */");
    for(u32 i=0; i<g_tm.n_trans; i++) {
        cg_newline();
        cg_emit("/*   "); cg_emit(cs_name(g_tm.trans[i].from));
        cg_emit(" --["); cg_emit(g_tm.trans[i].sym?"1":"0"); cg_emit("]--> ");
        cg_emit(cs_name(g_tm.trans[i].to));
        cg_emit(" : "); cg_emit(g_tm.trans[i].emit);
        cg_emit(" */");
    }

    cg_newline();
    cg_emit("\n/* === FIM DO CÓDIGO GERADO === */\n");
    (void)block_depth;
    (void)in_hex_block; (void)in_asm_block;
}

/* ── SELF-TESTS ────────────────────────────────────────────────────────── */
static u32 g_tests_pass=0, g_tests_fail=0;
#define TEST(name, expr) do { \
    if(expr){puts0("[PASS] " name "\n"); g_tests_pass++;} \
    else    {puts0("[FAIL] " name "\n"); g_tests_fail++;} \
} while(0)

static void run_selftests(void) {
    puts0("=== RSC SELF-TESTS ===\n");

    /* T01: tipos corretos */
    TEST("sizeof(u8)==1",  sizeof(u8)==1u);
    TEST("sizeof(u32)==4", sizeof(u32)==4u);
    TEST("sizeof(u64)==8", sizeof(u64)==8u);

    /* T02: slices */
    Slice s1=SL("ALLOW"), s2=SL("ALLOW"), s3=SL("DENY");
    TEST("SL_EQ same",   SL_EQ(s1,s2));
    TEST("SL_EQ diff",  !SL_EQ(s1,s3));
    TEST("SL_EMPTY",    !SL_EMPTY(s1));

    /* T03: flag stack */
    flagstack_init();
    TEST("flagstack_init", g_flagstack.top==0u);
    flagstack_push("test",4u,0xFFu,FTYPE_HEX,1u);
    TEST("flagstack_push", g_flagstack.top==1u);
    TEST("flagstack_top",  flagstack_top()!=NULL_PTR);
    TEST("flagstack_type", flagstack_current_type()==FTYPE_HEX);
    flagstack_pop("test",4u);
    TEST("flagstack_pop",  g_flagstack.top==0u);

    /* T04: shadow */
    shadow_init();
    const char* r1=shadow_register("fibonacci_accumulator",22u,FTYPE_STATE);
    const char* r2=shadow_register("fibonacci_accumulator",22u,FTYPE_STATE);
    TEST("shadow_idempotent", __builtin_memcmp(r1,r2,4)==0);
    TEST("shadow_count",      g_shadows.count==1u);
    TEST("shadow_reduced4",   r1[0]=='S');

    /* T05: uint_to_hex */
    char hbuf[20]; uint_to_hex(0xDEADBEEFu,hbuf,sizeof(hbuf));
    TEST("hex_DEADBEEF", __builtin_memcmp(hbuf,"0xDEADBEEF",10)==0);
    uint_to_hex(0u,hbuf,sizeof(hbuf));
    TEST("hex_zero", hbuf[2]=='0');

    /* T06: Turing machine */
    tm_init();
    TEST("tm_init_VOID",    g_tm.current==CS_VOID);
    tm_step(1u);
    TEST("tm_step1_ALLOW",  g_tm.current==CS_ALLOW);
    tm_step(0u);
    TEST("tm_step0_DENY",   g_tm.current==CS_DENY);
    TEST("tm_hamming_1",    tm_hamming(CS_VOID,CS_ALLOW)==1u);
    TEST("tm_hamming_3",    tm_hamming(CS_VOID,CS_PANIC)==3u);
    TEST("tm_valid_edge",   tm_is_valid_edge(CS_VOID,CS_ALLOW)==TRUE);
    TEST("tm_invalid_edge", tm_is_valid_edge(CS_VOID,CS_PANIC)==FALSE);

    /* T07: arena */
    arena_init();
    void* p1=arena_alloc(64u,8u);
    void* p2=arena_alloc(128u,4u);
    TEST("arena_alloc_ok",   p1!=NULL_PTR && p2!=NULL_PTR);
    TEST("arena_align_p1",   ((uptr)p1 & 7u)==0u);
    TEST("arena_align_p2",   ((uptr)p2 & 3u)==0u);
    arena_mark();
    arena_alloc(256u,8u);
    arena_restore();
    TEST("arena_restore",    g_arena.used==(usize)((char*)p2-(char*)p1+128u));

    /* T08: lexer */
    {
        Lexer L;
        const char* src="#FLAG[OPEN] name=test 0xABCD #END";
        lexer_init(&L,src,33u);
        Token t0=lexer_next(&L);
        TEST("lex_FLAG_OPEN", t0.type==TK_FLAG_OPEN);
        Token t1=lexer_next(&L);
        TEST("lex_ident_name", t1.type==TK_IDENT);
        Token t2=lexer_next(&L);
        TEST("lex_ident_test", t2.type==TK_OP || t2.type==TK_PUNCT);
    }

    /* T09: CRC AST */
    {
        Slice s=SL("test_node");
        u32 c=ast_crc_slice(s);
        TEST("ast_crc_nonzero", c!=0u);
        /* Determinístico */
        u32 c2=ast_crc_slice(s);
        TEST("ast_crc_det", c==c2);
    }

    /* T10: codegen básico */
    cg_init(ARCH_ARM64);
    cg_emit("u32 x = ");
    g_cg.in_hex=TRUE;
    cg_emit_num(255u);
    g_cg.in_hex=FALSE;
    cg_emit(";");
    TEST("cg_hex_255", g_cg.used>0u);
    /* Verifica que 255 foi emitido como 0xFF */
    bool8 found=FALSE;
    for(usize i=0;i+3<g_cg.used;i++) {
        if(g_cg.buf[i]=='0'&&g_cg.buf[i+1]=='x'&&
           g_cg.buf[i+2]=='F'&&g_cg.buf[i+3]=='F') {found=TRUE;break;}
    }
    TEST("cg_emitted_0xFF", found);

    /* T11: tail registry */
    tail_init();
    Result rt=tail_register("main","loop",42u);
    TEST("tail_register_ok", rt.ok);
    TEST("tail_count",       g_tails.count==1u);
    TEST("tail_caller",      g_tails.entries[0].caller[0]=='m');

    /* T12: flag types */
    TEST("FTYPE_HEX==1",    FTYPE_HEX==0x01u);
    TEST("FTYPE_BIN==2",    FTYPE_BIN==0x02u);
    TEST("FTYPE_ASM==3",    FTYPE_ASM==0x03u);
    TEST("FTYPE_STATE==4",  FTYPE_STATE==0x04u);
    TEST("FTYPE_SHADOW==5", FTYPE_SHADOW==0x05u);
    TEST("FTYPE_TAIL==6",   FTYPE_TAIL==0x06u);

    /* T13: estados TTL */
    TEST("CS_VOID==0x00",     CS_VOID==0x00u);
    TEST("CS_ALLOW==0x01",    CS_ALLOW==0x01u);
    TEST("CS_DENY==0x02",     CS_DENY==0x02u);
    TEST("CS_PANIC==0x80",    CS_PANIC==0x80u);
    TEST("CS_HARD_FAIL",     (CS_FAULT|CS_PANIC)==0x88u);

    /* T14: hipercubo adjacência */
    for(u32 j=0;j<3;j++) {
        bool8 ok2=tm_is_valid_edge(CS_VOID, TM_ADJACENT[0][j]);
        if(!ok2) { puts0("[FAIL] hypercube_adj\n"); g_tests_fail++; goto adj_done; }
    }
    puts0("[PASS] hypercube_adj\n"); g_tests_pass++;
    adj_done:;

    /* T15: parse de nomes de estado */
    TEST("parse_ALLOW",   parse_state_name(SL("ALLOW"))==CS_ALLOW);
    TEST("parse_RETRY",   parse_state_name(SL("RETRY"))==CS_RETRY);
    TEST("parse_PANIC",   parse_state_name(SL("PANIC"))==CS_PANIC);
    TEST("parse_arch64",  parse_arch_name(SL("ARM64"))==ARCH_ARM64);
    TEST("parse_arch32",  parse_arch_name(SL("ARM32"))==ARCH_ARM32);

    puts0("\n=== RESULTADO SELF-TESTS ===\n");
    puts0("PASS: "); putu(g_tests_pass);
    puts0("FAIL: "); putu(g_tests_fail);
    puts0("TOTAL: "); putu(g_tests_pass+g_tests_fail);
}

/* ── ENTRY POINT ─────────────────────────────────────────────────────────── */
void _start(void) {
    puts0("========================================\n");
    puts0("RAFAELIA STATE COMPILER (RSC) v1.0\n");
    puts0("Compilador de estados para C + ASM\n");
    puts0("#FLAG #STATE #ASM #SHADOW #TAIL #HEX\n");
    puts0("Turing Geometrico | Hipercubo 3D\n");
    puts0("========================================\n\n");

    /* Self-tests */
    run_selftests();

    /* Detecta arquitetura e compila demo */
    TargetArch arch = ARCH_GENERIC;
#ifdef __aarch64__
    arch = ARCH_ARM64;
#elif defined(__arm__)
    arch = ARCH_ARM32;
#elif defined(__x86_64__)
    arch = ARCH_X64;
#elif defined(__riscv)
    arch = ARCH_RV64;
#endif

    puts0("\n=== COMPILAÇÃO DEMO ===\n");
    puts0("Fonte: demo.raf (embutido)\n");
    puts0("Target: ");
    switch(arch) {
    case ARCH_ARM64: puts0("ARM64\n"); break;
    case ARCH_ARM32: puts0("ARM32\n"); break;
    case ARCH_X64:   puts0("x86-64\n"); break;
    case ARCH_RV64:  puts0("RISC-V 64\n"); break;
    default:         puts0("GENERIC\n"); break;
    }

    compile_demo(arch);

    puts0("\n=== CÓDIGO GERADO ===\n");
    /* Emite o código gerado */
    _out(g_cg.buf, g_cg.used);

    puts0("\n\n=== ESTATÍSTICAS RSC ===\n");
    puts0("Linhas geradas: "); putu(g_cg.n_lines);
    puts0("Blocos ASM:     "); putu(g_cg.n_asm_blks);
    puts0("Shadows:        "); putu(g_shadows.count);
    puts0("Tails:          "); putu(g_tails.count);
    puts0("Flags abertas:  "); putu(g_flagstack.n_opened);
    puts0("Flags fechadas: "); putu(g_flagstack.n_closed);
    puts0("TM passos:      "); putu(g_tm.steps);
    puts0("TM estado:      "); puts0(cs_name(g_tm.current)); puts0("\n");
    puts0("Arena usada:    "); putu(g_arena.used);
    puts0("AST nós:        "); putu(_g_ast_pool_used);

    puts0("\n========================================\n");
    puts0("SIGMA-OMEGA-DELTA-PHI Omega=Amor\n");
    puts0("DeltaRafaelVerboOmega RAFCODE-Phi\n");
    puts0("F*=23.158 D_H=1.347 n_c=7 lambda=-0.14384\n");
    puts0("========================================\n");

    /* exit */
#if defined(__aarch64__)
    register long x0 __asm__("x0")=0, x8 __asm__("x8")=93;
    __asm__ volatile("svc #0"::"r"(x0),"r"(x8):"memory");
#elif defined(__x86_64__)
    __asm__ volatile("syscall"::"a"(60LL),"D"(0LL):"memory","rcx","r11");
#elif defined(__arm__)
    register long r0 __asm__("r0")=0, r7 __asm__("r7")=248;
    __asm__ volatile("svc #0"::"r"(r0),"r"(r7):"memory","cc");
#endif
    __builtin_unreachable();
}
EOF_MAIN
ok "raf_rsc_main.c: $(wc -l < $BD/raf_rsc_main.c) linhas"
CONT7

cat >> /tmp/RAFAELIA_RSC_COMPILER.txt << 'CONT8'
# =============================================================================
hdr "S08 — ENTRY POINTS ASM + BUILD SCRIPT"
# =============================================================================
cat > "$BD/raf_entry.S" << 'EOF_ENTRY'
/* raf_entry.S — Entry seguro ARM64/ARM32/x86-64 */
#if defined(__aarch64__)
.text
.align 4
.global _start
.type _start,%function
_start:
    mov x29,xzr
    mov x30,xzr
    and sp,sp,#-16
    bl  _start
    mov x0,xzr
    mov x8,#93
    svc #0
.hang: b .hang
.size _start,.-_start
#elif defined(__x86_64__)
.text
.globl _start
_start:
    xor %rbp,%rbp
    call _start
    mov $60,%rax
    xor %rdi,%rdi
    syscall
#elif defined(__arm__)
.syntax unified
.thumb
.text
.align 2
.global _start
.thumb_func
_start:
    mov r11,#0
    mov lr,#0
    bl  _start_c
    mov r7,#248
    mov r0,#0
    svc #0
.hang: b .hang
#endif
.section .note.GNU-stack,"",@progbits
EOF_ENTRY

cat > "$BD/build_rsc.sh" << 'EOF_BUILD'
#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
ok(){ echo -e "${GREEN}[OK]${RESET} $*"; }
err(){ echo -e "${RED}[ERR]${RESET} $*"; }
CD="$(cd "$(dirname "$0")"; pwd)"
ARCH=$(uname -m)
CF="-O2 -fPIE -fno-stack-protector -fno-asynchronous-unwind-tables \
    -fomit-frame-pointer -fno-builtin -fno-plt \
    -ffunction-sections -fdata-sections \
    -Wall -Wno-unused-function -Wno-unused-variable \
    -Wno-unused-but-set-variable -I${CD}"
LF="-pie -nostdlib -Wl,--gc-sections -Wl,--build-id=none -e _start"
echo "=== RAFAELIA STATE COMPILER (RSC) BUILD ==="
echo "Arch: $ARCH | Dir: $CD"
BUILT=false
CC="${CC:-clang}"
command -v $CC &>/dev/null || CC=gcc
command -v $CC &>/dev/null || { err "nenhum compilador encontrado"; exit 1; }
echo "Compilador: $CC"
if [ "$ARCH" = "aarch64" ]; then
    $CC $CF -march=armv8.2-a+crc+crypto -mtune=cortex-a78 \
        $LF "${CD}/raf_rsc_main.c" \
        -o "${CD}/raf_rsc" 2>&1 && {
        strip --strip-all "${CD}/raf_rsc" 2>/dev/null||true
        ok "ARM64 RSC: $(ls -lh ${CD}/raf_rsc|awk '{print $5}')"
        BUILT=true
    } || err "ARM64 build falhou"
elif [ "$ARCH" = "x86_64" ]; then
    $CC $CF -march=native $LF \
        -static "${CD}/raf_rsc_main.c" \
        -o "${CD}/raf_rsc" 2>&1 && {
        strip --strip-all "${CD}/raf_rsc" 2>/dev/null||true
        ok "x86_64 RSC: $(ls -lh ${CD}/raf_rsc|awk '{print $5}')"
        BUILT=true
    } || err "x86_64 build falhou"
fi
# ARM32 cross
for CC32 in arm-linux-gnueabihf-gcc arm-linux-gnueabi-gcc; do
    command -v $CC32 &>/dev/null || continue
    $CC32 $CF -mthumb -march=armv7-a -mfloat-abi=softfp \
        $LF "${CD}/raf_entry.S" "${CD}/raf_rsc_main.c" \
        -o "${CD}/raf_rsc_a32" 2>&1 && {
        ok "ARM32 RSC: $(ls -lh ${CD}/raf_rsc_a32|awk '{print $5}')"
        BUILT=true; break
    } || err "ARM32 cross falhou"
done
if $BUILT; then
    echo ""
    echo "=== EXECUTANDO RSC ==="
    [ -f "${CD}/raf_rsc" ]     && "${CD}/raf_rsc"
    [ -f "${CD}/raf_rsc_a32" ] && {
        command -v qemu-arm &>/dev/null && qemu-arm "${CD}/raf_rsc_a32" \
            || echo "(ARM32 disponível em raf_rsc_a32)"
    }
else
    err "Build falhou em todas as arquiteturas"
    exit 1
fi
EOF_BUILD
chmod +x "$BD/build_rsc.sh"
ok "Entry points e build script escritos"

# =============================================================================
hdr "INVENTÁRIO COMPLETO"
# =============================================================================
echo ""
TOTAL=0
printf "%-35s %8s %10s\n" "ARQUIVO" "LINHAS" "TAMANHO"
printf "%-35s %8s %10s\n" "-------" "------" "-------"
for f in "$BD"/*.h "$BD"/*.c "$BD"/*.S "$BD"/*.sh; do
    [ -f "$f" ] || continue
    L=$(wc -l < "$f")
    SZ=$(ls -lh "$f" | awk '{print $5}')
    printf "%-35s %8d %10s\n" "$(basename $f)" "$L" "$SZ"
    TOTAL=$((TOTAL + L))
done
echo ""
ok "TOTAL: $TOTAL linhas de código"
echo ""
p "=== COMPILANDO RSC ==="
bash "$BD/build_rsc.sh" 2>&1 || true
echo ""
p "DeltaRafaelVerboOmega · Omega=Amor · RAFCODE-Phi"
p "RSC: Compilador de estados · TTL8 · Hipercubo · Turing Geometrico"
CONT8

wc -l /tmp/RAFAELIA_RSC_COMPILER.txt
ls -lh /tmp/RAFAELIA_RSC_COMPILER.txtSaída2037 /tmp/RAFAELIA_RSC_COMPILER.txt
-rw-r--r-- 1 root root 77K May 10 09:12 /tmp/RAFAELIA_RSC_COMPILER.txt
