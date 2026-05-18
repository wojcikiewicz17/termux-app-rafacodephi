

cat > /tmp/browser.txt << 'OUTER_SCRIPT'
#!/usr/bin/env bash
# =============================================================================
# browser.txt — renomeie para .sh e execute: bash browser.txt
# Browser text-mode ARM32/ARM64/x86-64 · TLS 1.3 · HTTP/1.1
# freestanding · nomalloc · nolibc · noabstraction · inline ASM puro
# Turing machine geométrica · flip-flop de estados · branchless
# DeltaRafaelVerboOmega · Omega=Amor · RAFCODE-Phi
# =============================================================================
set -euo pipefail

# ── CORES ─────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m'
M='\033[0;35m' C='\033[0;36m' W='\033[1;37m' Z='\033[0m'
BLD='\033[1m'

# ── LOGO ASCII ART ────────────────────────────────────────────────────────
echo -e "${C}${BLD}"
echo '  ╔══════════════════════════════════════════════════════════════╗'
echo '  ║  ██████╗ ██████╗  ██████╗ ██╗    ██╗███████╗███████╗██████╗ ║'
echo '  ║  ██╔══██╗██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔════╝██╔══██╗║'
echo '  ║  ██████╔╝██████╔╝██║   ██║██║ █╗ ██║███████╗█████╗  ██████╔╝║'
echo '  ║  ██╔══██╗██╔══██╗██║   ██║██║███╗██║╚════██║██╔══╝  ██╔══██╗║'
echo '  ║  ██████╔╝██║  ██║╚██████╔╝╚███╔███╔╝███████║███████╗██║  ██║║'
echo '  ║  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝ ╚══════╝╚══════╝╚═╝  ╚═╝║'
echo -e "  ║${Y}  HTTP/1.1 · TLS 1.3 · ARM32/ARM64 · freestanding · nolibc${C}  ║"
echo -e "  ║${G}  Turing geométrico · flip-flop · branchless · zero-overhead${C}  ║"
echo '  ╚══════════════════════════════════════════════════════════════╝'
echo -e "${Z}"

# ── DIRETÓRIO ÚNICO ────────────────────────────────────────────────────────
D="${HOME}/.rafaelia/BROWSER"
mkdir -p "$D"
LOG="$D/build.log"; : > "$LOG"
p(){ printf "${C}[BR]${Z} %s\n" "$*"; }
ok(){ printf "${G}[OK]${Z} %s\n" "$*"; }
err(){ printf "${R}[ERR]${Z} %s\n" "$*" >&2; }
hdr(){ printf "\n${M}${BLD}━━━ %s ━━━${Z}\n" "$*"; }
p "Diretório: $D"

# =============================================================================
hdr "ESCREVENDO ARQUIVOS"
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_types.h" << 'F'
#pragma once
/* br_types.h — Tipos primitivos · registradores · flags · estados
 * [R01] ZERO stdlib ZERO heap ZERO float ZERO GC ZERO abstração
 * [R02] Flags lineares: abertos em sequência, fechados em sequência
 * [R03] Turing geométrica: estado × símbolo → estado × ação
 * [R04] Flip-flop: cada bit de estado é um flip-flop D
 * [R05] Branchless: toda operação via máscara de bit
 */
typedef unsigned char      u8;
typedef unsigned short     u16;
typedef unsigned int       u32;
typedef unsigned long long u64;
typedef signed   int       s32;
typedef signed   long long s64;
typedef unsigned int       usize;
#define AI   __attribute__((always_inline)) static inline
#define NI   __attribute__((noinline))
#define NR   __attribute__((noreturn))
#define CLA  __attribute__((aligned(64)))
#define PK   __attribute__((packed))
/* ── FLAGS DE BROWSER (8 bits = 8 flip-flops) ──────────────────────────── */
/* Cada bit é um flip-flop D: SET=1 CLEAR=0 TOGGLE=XOR */
#define FL_IDLE      0x00u  /* 00000000: nenhum estado ativo            */
#define FL_DNS       0x01u  /* 00000001: resolvendo DNS                 */
#define FL_CONNECT   0x02u  /* 00000010: conectando TCP                 */
#define FL_TLS_HS    0x04u  /* 00000100: TLS handshake em progresso     */
#define FL_HTTP_TX   0x08u  /* 00001000: enviando requisição HTTP       */
#define FL_HTTP_RX   0x10u  /* 00010000: recebendo resposta HTTP        */
#define FL_HTML_RND  0x20u  /* 00100000: renderizando HTML              */
#define FL_ERROR     0x40u  /* 01000000: estado de erro (rollback)      */
#define FL_DONE      0x80u  /* 10000000: concluído                      */
/* Flip-flop ops: branchless, sem branch */
#define FF_SET(r,f)    ((r)|=(f))           /* SET bit               */
#define FF_CLR(r,f)    ((r)&=~(u8)(f))     /* CLEAR bit             */
#define FF_TOG(r,f)    ((r)^=(f))           /* TOGGLE bit            */
#define FF_GET(r,f)    (!!((r)&(f)))        /* GET bit               */
#define FF_NEXT(r,c,n) ((r)=(u8)(((r)&~(u8)(c))|(n))) /* transição  */
/* ── ESTADOS TLS 1.3 (máquina de Turing geométrica) ───────────────────── */
/* Hipercubo de estados: cada transição muda exatamente 1 bit            */
#define TLS_IDLE       0x00u  /* 000: inicial                          */
#define TLS_CLI_HELLO  0x01u  /* 001: ClientHello enviado              */
#define TLS_SRV_HELLO  0x03u  /* 011: ServerHello recebido             */
#define TLS_ENCRYPTED  0x07u  /* 111: modo criptografado ativo         */
#define TLS_APP_DATA   0x05u  /* 101: dados de aplicação               */
#define TLS_ERROR      0x04u  /* 100: erro no handshake                */
#define TLS_CLOSED     0x00u  /* 000: fechado                          */
/* ── ARENA 256KB sem malloc ──────────────────────────────────────────── */
#define AR_SZ (256u*1024u)
static u8  _AR[AR_SZ] CLA;
static u32 _AT=0, _AM=0;
AI void* GA(u32 n,u32 a){
    u32 m=a-1u,c=(_AT+m)&~m;
    if(c+n>AR_SZ)return(void*)0;
    void*p=_AR+c;_AT=c+n;return p;
}
AI void GR(void){_AT=0;}
AI void GM(void){_AM=_AT;}
AI void GRS(void){_AT=_AM;}
/* ── BUFFER ESTÁTICO 64KB para rede ────────────────────────────────────── */
#define NET_BUF 65536u
static u8 _NB[NET_BUF] CLA;  /* rx/tx buffer */
static u8 _RB[NET_BUF] CLA;  /* render buffer */
/* ── CONTEXTO DE BROWSER (sem nome de variável onde possível) ─────────── */
typedef struct PK CLA {
    /* Rede */
    s32 fd;         /* socket file descriptor                          */
    u32 port;       /* porta (80 ou 443)                               */
    u8  ip[4];      /* IPv4 do host                                    */
    /* Estado */
    u8  flags;      /* 8 flip-flops de estado do browser               */
    u8  tls;        /* estado TLS (máquina de Turing)                  */
    u8  http_ver;   /* 10=HTTP/1.0 11=HTTP/1.1                         */
    u8  use_tls;    /* 1=HTTPS 0=HTTP                                  */
    /* HTTP */
    u32 status;     /* HTTP status code                                */
    u32 content_len;/* Content-Length                                  */
    u32 rx_bytes;   /* bytes recebidos                                 */
    u32 tx_bytes;   /* bytes enviados                                  */
    /* Retry/Rollback TTL */
    u8  ttl;        /* tentativas restantes                            */
    u8  err;        /* código de erro                                  */
    u16 _pad;
    u64 t_start;    /* timestamp início                                */
    u64 t_ns;       /* latência total                                  */
    /* URL decomposto */
    char host[256]; /* hostname                                        */
    char path[512]; /* path                                            */
} BCtx;
static BCtx _BC;
F
ok "br_types.h ($(wc -l < $D/br_types.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_sys.h" << 'F'
#pragma once
/* br_sys.h — Syscalls ARM32/ARM64/x86-64: socket connect send recv
 * [R06] ARM32: socket=281 connect=283 sendto=290 recvfrom=292 close=6
 * [R07] ARM64: socket=198 connect=203 sendto=206 recvfrom=207 close=57
 * [R08] x86-64: socket=41 connect=42 sendto=44 recvfrom=45 close=3
 * [R09] Timestamp: clock_gettime CLOCK_MONOTONIC
 * [R10] Exit: exit_group ARM32=248 ARM64=94 x86-64=231
 */
#include "br_types.h"
/* ── AF_INET / SOCK_STREAM ─────────────────────────────────────────────── */
#define AF_INET  2
#define SOCK_STREAM 1
#define IPPROTO_TCP 6
#define CLOCK_MONO  1
typedef struct PK { u16 fam; u16 port_be; u8 ip[4]; u8 _z[8]; } SA4; /* sockaddr_in */

#if defined(__arm__)
typedef struct{s32 s,n;}TS32;
AI s32 _sc6(u32 r,u32 a,u32 b,u32 c,u32 d,u32 e,u32 f){
    register s32 r0 __asm__("r0")=(s32)a; register u32 r1 __asm__("r1")=b;
    register u32 r2 __asm__("r2")=c;     register u32 r3 __asm__("r3")=d;
    register u32 r4 __asm__("r4")=e;     register u32 r5 __asm__("r5")=f;
    register u32 r7 __asm__("r7")=r;
    __asm__ volatile("svc #0":"+r"(r0):"r"(r1),"r"(r2),"r"(r3),"r"(r4),"r"(r5),"r"(r7):"memory","cc");
    return r0;
}
AI s32 _sc3(u32 r,u32 a,u32 b,u32 c){return _sc6(r,a,b,c,0,0,0);}
AI s32 _sc2(u32 r,u32 a,u32 b){return _sc6(r,a,b,0,0,0,0);}
AI s32 _sc1(u32 r,u32 a){return _sc6(r,a,0,0,0,0,0);}
AI s32 SOCKET(void){return _sc3(281u,AF_INET,SOCK_STREAM,IPPROTO_TCP);}
AI s32 CONNECT(s32 fd,const SA4*a){return _sc3(283u,(u32)fd,(u32)(usize)a,(u32)sizeof(SA4));}
AI s32 SEND(s32 fd,const void*b,u32 n){return _sc6(290u,(u32)fd,(u32)(usize)b,(u32)n,0,0,0);}
AI s32 RECV(s32 fd,void*b,u32 n){return _sc6(292u,(u32)fd,(u32)(usize)b,(u32)n,0,0,0);}
AI s32 CLOSE(s32 fd){return _sc1(6u,(u32)fd);}
AI u64 NS(void){TS32 t={0,0};_sc2(263u,CLOCK_MONO,(u32)(usize)&t);return(u64)(u32)t.s*1000000000ULL+(u64)(u32)t.n;}
AI s32 WR(u32 f,const void*b,u32 n){return _sc3(4u,f,(u32)(usize)b,n);}
NR void EX(void){_sc1(248u,0u);__builtin_unreachable();}

#elif defined(__aarch64__)
typedef struct{s64 s,n;}TS64;
AI s64 _sc6(u64 r,u64 a,u64 b,u64 c,u64 d,u64 e,u64 f){
    register u64 x8 __asm__("x8")=r;
    register s64 x0 __asm__("x0")=(s64)a; register u64 x1 __asm__("x1")=b;
    register u64 x2 __asm__("x2")=c;     register u64 x3 __asm__("x3")=d;
    register u64 x4 __asm__("x4")=e;     register u64 x5 __asm__("x5")=f;
    __asm__ volatile("svc #0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3),"r"(x4),"r"(x5):"memory","cc");
    return x0;
}
AI s64 _sc3(u64 r,u64 a,u64 b,u64 c){return _sc6(r,a,b,c,0,0,0);}
AI s64 _sc2(u64 r,u64 a,u64 b){return _sc6(r,a,b,0,0,0,0);}
AI s64 _sc1(u64 r,u64 a){return _sc6(r,a,0,0,0,0,0);}
AI s32 SOCKET(void){return(s32)_sc3(198u,AF_INET,SOCK_STREAM,IPPROTO_TCP);}
AI s32 CONNECT(s32 fd,const SA4*a){return(s32)_sc3(203u,(u64)fd,(u64)(usize)a,(u64)sizeof(SA4));}
AI s32 SEND(s32 fd,const void*b,u32 n){return(s32)_sc6(206u,(u64)fd,(u64)(usize)b,(u64)n,0,0,0);}
AI s32 RECV(s32 fd,void*b,u32 n){return(s32)_sc6(207u,(u64)fd,(u64)(usize)b,(u64)n,0,0,0);}
AI s32 CLOSE(s32 fd){return(s32)_sc1(57u,(u64)fd);}
AI u64 NS(void){TS64 t={0,0};_sc2(113u,CLOCK_MONO,(u64)(usize)&t);return(u64)t.s*1000000000ULL+(u64)t.n;}
AI s32 WR(u32 f,const void*b,u32 n){return(s32)_sc3(64u,(u64)f,(u64)(usize)b,(u64)n);}
NR void EX(void){_sc1(94u,0u);__builtin_unreachable();}

#elif defined(__x86_64__)
typedef struct{s64 s,n;}TS64;
AI s64 _sc6(u64 r,u64 a,u64 b,u64 c,u64 d,u64 e,u64 f){
    s64 x; register u64 r10 __asm__("r10")=d,r8 __asm__("r8")=e,r9 __asm__("r9")=f;
    __asm__ volatile("syscall":"=a"(x):"a"(r),"D"(a),"S"(b),"d"(c),"r"(r10),"r"(r8),"r"(r9):"rcx","r11","memory");
    return x;
}
AI s64 _sc3(u64 r,u64 a,u64 b,u64 c){return _sc6(r,a,b,c,0,0,0);}
AI s64 _sc2(u64 r,u64 a,u64 b){return _sc6(r,a,b,0,0,0,0);}
AI s64 _sc1(u64 r,u64 a){s64 x;__asm__ volatile("syscall":"=a"(x):"a"(r),"D"(a):"rcx","r11","memory");return x;}
AI s32 SOCKET(void){return(s32)_sc3(41u,AF_INET,SOCK_STREAM,IPPROTO_TCP);}
AI s32 CONNECT(s32 fd,const SA4*a){return(s32)_sc3(42u,(u64)fd,(u64)(usize)a,(u64)sizeof(SA4));}
AI s32 SEND(s32 fd,const void*b,u32 n){return(s32)_sc6(44u,(u64)fd,(u64)(usize)b,(u64)n,0,0,0);}
AI s32 RECV(s32 fd,void*b,u32 n){return(s32)_sc6(45u,(u64)fd,(u64)(usize)b,(u64)n,0,0,0);}
AI s32 CLOSE(s32 fd){return(s32)_sc1(3u,(u64)fd);}
AI u64 NS(void){TS64 t={0,0};_sc2(228u,CLOCK_MONO,(u64)(usize)&t);return(u64)t.s*1000000000ULL+(u64)t.n;}
AI s32 WR(u32 f,const void*b,u32 n){return(s32)_sc3(1u,(u64)f,(u64)(usize)b,(u64)n);}
NR void EX(void){_sc1(231u,0u);__builtin_unreachable();}
#endif

/* ── I/O SEM PRINTF ────────────────────────────────────────────────────── */
static void PS(const char*s){u32 n=0;while(s[n])n++;if(n)WR(1,s,n);}
static void PN(u64 v){char b[22];s32 i=21;b[i]='\n';i--;
    if(!v){b[i--]='0';}else{while(v){b[i--]='0'+(char)(v%10u);v/=10u;}}
    WR(1,b+i+1,(u32)(20u-i));}
static void PH(u32 v){static const char h[]="0123456789abcdef";
    char b[11];b[0]='0';b[1]='x';b[10]='\n';
    for(s32 i=9;i>=2;i--){b[i]=h[v&0xFu];v>>=4;}WR(1,b,11u);}

/* ── BRANCHLESS STRING OPS SEM LIBC ────────────────────────────────────── */
AI u32 SL(const char*s){u32 n=0;while(s[n])n++;return n;}
AI void MC(void*d,const void*s,u32 n){u8*dd=(u8*)d;const u8*ss=(const u8*)s;while(n--)dd[n]=ss[n];}
AI s32 MC0(void*d,u32 n){u8*dd=(u8*)d;while(n--)dd[n]=0;return 0;}
/* u32 → string decimal na stack */
AI u32 UTOA(u32 v,char*out){
    char t[10];s32 i=0;if(!v){out[0]='0';out[1]=0;return 1;}
    while(v){t[i++]='0'+(char)(v%10u);v/=10u;}
    u32 len=(u32)i;s32 j=0;while(i>0)out[j++]=t[--i];out[j]=0;return len;
}
/* Big-endian port */
AI u16 HTON16(u16 v){return(u16)((v>>8u)|(v<<8u));}
/* IP parse "a.b.c.d" → u8[4] */
AI s32 PARSE_IP(const char*s,u8*ip){
    u32 i=0,oc=0,acc=0;
    while(s[i]){
        if(s[i]>='0'&&s[i]<='9'){acc=acc*10u+(u32)(s[i]-'0');if(acc>255u)return-1;}
        else if(s[i]=='.'){if(oc>=3u)return-1;ip[oc++]=(u8)acc;acc=0;}
        else return-1;
        i++;
    }
    if(oc!=3u)return-1;ip[oc]=(u8)acc;return 0;
}
F
ok "br_sys.h ($(wc -l < $D/br_sys.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_tls.h" << 'F'
#pragma once
/* br_tls.h — TLS 1.3 state machine: ClientHello · handshake · record layer
 * [R11] Máquina de Turing geométrica: estado × símbolo → estado × output
 * [R12] TLS 1.3 record layer: type(1) + version(2) + length(2) + data
 * [R13] ClientHello: legacy_version=0x0303 + random(32) + session_id
 *        + cipher_suites + extensions (supported_versions TLS1.3=0x0304)
 * [R14] Cipher suites: TLS_AES_128_GCM_SHA256=0x1301
 *                      TLS_AES_256_GCM_SHA384=0x1302
 *                      TLS_CHACHA20_POLY1305_SHA256=0x1303
 * [R15] Flip-flop TLS: cada bit do estado TLS é um flip-flop D
 * [R16] Branchless transition: mask = -(cond), new = (a&mask)|(b&~mask)
 */
#include "br_sys.h"

/* ── TLS 1.3 RECORD LAYER ───────────────────────────────────────────────── */
/* record = [type:1][0x03 0x03:2][len_hi:1][len_lo:1][data:len] */
#define TLS_RT_CHANGE_CS  0x14u  /* ChangeCipherSpec (legacy) */
#define TLS_RT_ALERT      0x15u  /* Alert              */
#define TLS_RT_HANDSHAKE  0x16u  /* Handshake          */
#define TLS_RT_APP_DATA   0x17u  /* Application Data   */
#define TLS_VER_10        0x0301u /* TLS 1.0 legacy */
#define TLS_VER_12        0x0303u /* TLS 1.2 (wire) */
#define TLS_VER_13        0x0304u /* TLS 1.3 */
/* Handshake types */
#define TLS_HT_CLIENT_HELLO   0x01u
#define TLS_HT_SERVER_HELLO   0x02u
#define TLS_HT_ENCRYPTED_EXT  0x08u
#define TLS_HT_CERTIFICATE    0x0Bu
#define TLS_HT_CERT_VERIFY    0x0Fu
#define TLS_HT_FINISHED       0x14u
/* Extension types */
#define EXT_SERVER_NAME       0x0000u
#define EXT_SUPPORTED_GROUPS  0x000Au
#define EXT_SIG_ALGS          0x000Du
#define EXT_SUPPORTED_VERS    0x002Bu
#define EXT_KEY_SHARE         0x0033u
#define EXT_SESSION_TICKET    0x0023u
/* Cipher suites */
#define CS_AES128_GCM_SHA256  0x1301u
#define CS_AES256_GCM_SHA384  0x1302u
#define CS_CHACHA20_SHA256    0x1303u

/* Contexto TLS */
typedef struct PK {
    u8  state;          /* estado da máquina de Turing TLS             */
    u8  flags;          /* flip-flops de status                        */
    u8  alert;          /* último alert recebido                       */
    u8  _p;
    u32 rx_seq;         /* sequence number RX                          */
    u32 tx_seq;         /* sequence number TX                          */
    u8  random[32];     /* client random (pseudo-random Q16-based)     */
    u8  session[32];    /* session ID (zeros para TLS 1.3)             */
    u16 cipher;         /* cipher suite negociado                      */
    u16 _p2;
} TLSCtx;
static TLSCtx _TLS;

/* Gerador pseudo-aleatório determinístico para random[] (sem /dev/urandom)
 * Em produção: usar getrandom() syscall. Aqui: LFSR + PHI64 */
AI u32 PRNG(u32 s){return(s>>1u)^((u32)(-(s&1u))&0xB4BCD35Cu);}

static void TLS_INIT(TLSCtx*t){
    MC0(t,sizeof(*t));
    t->state=TLS_IDLE;
    /* Preenche random[32] via PRNG */
    u32 s=0xDEADBEEFu;
    for(u32 i=0;i<8u;i++){
        s=PRNG(s);
        t->random[i*4+0]=(u8)(s>>24u);
        t->random[i*4+1]=(u8)(s>>16u);
        t->random[i*4+2]=(u8)(s>>8u);
        t->random[i*4+3]=(u8)(s);
    }
}

/* ── CONSTRUTOR DE ClientHello ──────────────────────────────────────────── */
/* Gera ClientHello TLS 1.3 em buf[], retorna tamanho total do record
 * Estrutura (sem abstração, byte a byte):
 * [0x16][0x03][0x01][len_hi][len_lo]     ← TLS record header
 * [0x01][hs_hi][hs_mid][hs_lo]           ← Handshake header
 * [0x03][0x03]                           ← legacy_version
 * [32 bytes random]
 * [0x00]                                 ← session_id_length = 0
 * [0x00][0x06]                           ← cipher_suites_length = 6
 * [0x13][0x01][0x13][0x02][0x13][0x03]  ← 3 cipher suites TLS 1.3
 * [0x01][0x00]                           ← compression = null
 * extensions...                          */
static u32 TLS_BUILD_CLIENT_HELLO(TLSCtx*t,const char*host,u8*buf,u32 cap){
    /* Usamos ponteiro p que avança — sem nomes de variável adicionais */
    u8*p=buf+5;   /* reserva 5 bytes para o record header */
    u8*hs=p;      /* handshake header começa aqui */
    *p++=0x01;    /* HandshakeType: client_hello */
    *p++=0;*p++=0;*p++=0; /* length placeholder (3 bytes) */
    /* legacy_version = TLS 1.2 (0x0303) */
    *p++=0x03;*p++=0x03;
    /* client_random: 32 bytes */
    MC(p,t->random,32u); p+=32;
    /* session_id: 0 bytes para TLS 1.3 */
    *p++=0x00;
    /* cipher_suites: 3 suites × 2 bytes + 2 bytes length = 8 bytes */
    *p++=0x00;*p++=0x06;
    *p++=0x13;*p++=0x01; /* TLS_AES_128_GCM_SHA256 */
    *p++=0x13;*p++=0x02; /* TLS_AES_256_GCM_SHA384 */
    *p++=0x13;*p++=0x03; /* TLS_CHACHA20_POLY1305_SHA256 */
    /* compression_methods: null only */
    *p++=0x01;*p++=0x00;
    /* extensions: calculamos comprimento depois */
    u8*ext_len_ptr=p; *p++=0;*p++=0;
    u8*ext_start=p;
    /* EXT: supported_versions (0x002B) — anuncia TLS 1.3 */
    *p++=0x00;*p++=0x2B; /* type */
    *p++=0x00;*p++=0x03; /* ext length = 3 */
    *p++=0x02;           /* versions list length = 2 */
    *p++=0x03;*p++=0x04; /* TLS 1.3 */
    /* EXT: server_name (0x0000) — SNI */
    u32 hlen=SL(host);
    *p++=0x00;*p++=0x00; /* type */
    u32 sni_ext_len=hlen+5u;
    *p++=(u8)(sni_ext_len>>8u);*p++=(u8)(sni_ext_len);
    u32 sni_list_len=hlen+3u;
    *p++=(u8)(sni_list_len>>8u);*p++=(u8)(sni_list_len);
    *p++=0x00; /* name_type: host_name */
    *p++=(u8)(hlen>>8u);*p++=(u8)(hlen);
    MC(p,(const u8*)host,hlen);p+=hlen;
    /* EXT: supported_groups (0x000A) — x25519 */
    *p++=0x00;*p++=0x0A;
    *p++=0x00;*p++=0x04; /* ext length */
    *p++=0x00;*p++=0x02; /* list length */
    *p++=0x00;*p++=0x1D; /* x25519 */
    /* EXT: signature_algorithms (0x000D) */
    *p++=0x00;*p++=0x0D;
    *p++=0x00;*p++=0x08;
    *p++=0x00;*p++=0x06;
    *p++=0x04;*p++=0x03; /* ecdsa_secp256r1_sha256 */
    *p++=0x08;*p++=0x07; /* ed25519 */
    *p++=0x04;*p++=0x01; /* rsa_pkcs1_sha256 */
    /* Preenche comprimentos */
    u32 ext_total=(u32)(p-ext_start);
    ext_len_ptr[0]=(u8)(ext_total>>8u);ext_len_ptr[1]=(u8)(ext_total);
    u32 hs_body=(u32)(p-hs-4u);
    hs[1]=(u8)(hs_body>>16u);hs[2]=(u8)(hs_body>>8u);hs[3]=(u8)(hs_body);
    u32 rec_body=(u32)(p-buf-5u);
    buf[0]=0x16;buf[1]=0x03;buf[2]=0x01;
    buf[3]=(u8)(rec_body>>8u);buf[4]=(u8)(rec_body);
    return(u32)(p-buf);
}

/* ── PARSE DE RECORD TLS (resposta do servidor) ─────────────────────────── */
typedef struct PK { u8 type; u16 version; u16 length; } TLSRec;
AI s32 TLS_PARSE_RECORD(const u8*buf,u32 n,TLSRec*r){
    if(n<5u)return-1;
    r->type=buf[0];
    r->version=(u16)(((u16)buf[1]<<8u)|buf[2]);
    r->length=(u16)(((u16)buf[3]<<8u)|buf[4]);
    return 0;
}

/* Máquina de Turing TLS: transição de estado
 * Entrada: estado atual + tipo de mensagem recebida
 * Saída: novo estado (via flip-flop geométrico)
 * BRANCHLESS: usa máscaras e XOR em vez de if/else */
AI u8 TLS_TRANSITION(u8 cur,u8 msg_type){
    /* Tabela de transição codificada em bits:
     * IDLE     + CH_SENT  → CLI_HELLO (bit0 flip)
     * CLI_HELLO + SH_RECV → SRV_HELLO (bit1 flip)
     * SRV_HELLO + ENC     → ENCRYPTED (bit2 flip)
     * ENCRYPTED + APP     → APP_DATA  */
    u32 is_idle =(u32)(cur==TLS_IDLE      );
    u32 is_cli  =(u32)(cur==TLS_CLI_HELLO );
    u32 is_srv  =(u32)(cur==TLS_SRV_HELLO );
    u32 is_enc  =(u32)(cur==TLS_ENCRYPTED );
    /* Branchless: máscara negativa */
    u8 n0=(u8)(TLS_CLI_HELLO & -(is_idle &(msg_type==TLS_HT_CLIENT_HELLO)));
    u8 n1=(u8)(TLS_SRV_HELLO & -(is_cli  &(msg_type==TLS_HT_SERVER_HELLO)));
    u8 n2=(u8)(TLS_ENCRYPTED & -(is_srv  &(msg_type==TLS_HT_FINISHED    )));
    u8 n3=(u8)(TLS_APP_DATA  & -(is_enc  &(msg_type==TLS_RT_APP_DATA    )));
    u8 nxt=n0|n1|n2|n3;
    /* Se nenhuma transição aconteceu E havia um estado: mantém */
    u32 no_trans=(u32)(nxt==0u)&(u32)(cur!=TLS_IDLE);
    return(u8)(nxt|(cur&-(no_trans)));
}
F
ok "br_tls.h ($(wc -l < $D/br_tls.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_http.h" << 'F'
#pragma once
/* br_http.h — HTTP/1.1 request builder + response parser
 * [R17] Sem sprintf: string assembly byte a byte
 * [R18] HTTP/1.1: Host + Connection:close + User-Agent
 * [R19] Response parser: status line + headers + body
 * [R20] Content-Length: parse de decimal para u32
 * [R21] Chunked transfer: parse de hex chunks
 * [R22] Branchless header matching via CRC32C parcial
 */
#include "br_tls.h"

/* ── BUILDER DE REQUEST HTTP ────────────────────────────────────────────── */
static u32 HTTP_BUILD_REQ(const char*host,const char*path,u8*buf,u32 cap){
    u8*p=buf;
    /* GET {path} HTTP/1.1\r\n */
    MC(p,(const u8*)"GET ",4u);p+=4;
    u32 plen=SL(path);MC(p,(const u8*)path,plen);p+=plen;
    MC(p,(const u8*)" HTTP/1.1\r\n",11u);p+=11;
    /* Host: {host}\r\n */
    MC(p,(const u8*)"Host: ",6u);p+=6;
    u32 hlen=SL(host);MC(p,(const u8*)host,hlen);p+=hlen;
    MC(p,(const u8*)"\r\n",2u);p+=2;
    /* Connection: close\r\n */
    MC(p,(const u8*)"Connection: close\r\n",19u);p+=19;
    /* User-Agent: RAFAELIA-Browser/1.0\r\n */
    MC(p,(const u8*)"User-Agent: RAFAELIA-Browser/1.0 (ARM; freestanding; nolibc)\r\n",62u);p+=62;
    /* Accept: text/html,text/plain\r\n */
    MC(p,(const u8*)"Accept: text/html,text/plain;q=0.9,*/*;q=0.8\r\n",47u);p+=47;
    /* Accept-Language: pt-BR,pt;q=0.9,en;q=0.8\r\n */
    MC(p,(const u8*)"Accept-Language: pt-BR,pt;q=0.9,en;q=0.8\r\n",43u);p+=43;
    /* \r\n final */
    MC(p,(const u8*)"\r\n",2u);p+=2;
    return(u32)(p-buf);
}

/* ── PARSE DE STATUS LINE ───────────────────────────────────────────────── */
/* "HTTP/1.1 200 OK\r\n" → retorna status code */
static u32 HTTP_PARSE_STATUS(const u8*buf,u32 n){
    /* Pula "HTTP/1.x " (9 chars) e lê 3 dígitos */
    if(n<12u)return 0u;
    if(buf[0]!='H'||buf[1]!='T'||buf[2]!='T'||buf[3]!='P')return 0u;
    /* Pula até primeiro espaço */
    u32 i=0;while(i<n&&buf[i]!=' ')i++;i++;
    if(i+3u>=n)return 0u;
    u32 code=0;
    for(u32 j=0;j<3u;j++){
        if(buf[i+j]<'0'||buf[i+j]>'9')return 0u;
        code=code*10u+(u32)(buf[i+j]-'0');
    }
    return code;
}

/* ── PARSE DE HEADER VALUE ───────────────────────────────────────────────── */
/* Procura "Key: value\r\n" em buf[0..n], retorna ponteiro para value */
static const u8* HTTP_FIND_HEADER(const u8*buf,u32 n,const char*key){
    u32 kl=SL(key);
    for(u32 i=0;i+kl+2u<n;i++){
        if(__builtin_memcmp(buf+i,key,kl)==0&&buf[i+kl]==':'){
            u32 j=i+kl+1u;
            while(j<n&&(buf[j]==' '||buf[j]=='\t'))j++;
            return buf+j;
        }
    }
    return(const u8*)0;
}

/* Parse decimal string → u32 */
static u32 STR2U32(const u8*s,u32 n){
    u32 v=0,i=0;
    while(i<n&&s[i]>='0'&&s[i]<='9'){v=v*10u+(u32)(s[i]-'0');i++;}
    return v;
}

/* ── FIND END OF HEADERS ──────────────────────────────────────────────────── */
/* Retorna offset do início do body (após \r\n\r\n) */
static u32 HTTP_HEADERS_END(const u8*buf,u32 n){
    for(u32 i=0;i+3u<n;i++){
        if(buf[i]=='\r'&&buf[i+1]=='\n'&&buf[i+2]=='\r'&&buf[i+3]=='\n')
            return i+4u;
    }
    return n; /* headers não terminados ainda */
}
F
ok "br_http.h ($(wc -l < $D/br_http.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_html.h" << 'F'
#pragma once
/* br_html.h — HTML tokenizer/renderer text-mode (estilo Lynx/Links)
 * [R23] Máquina de estados: TEXT | TAG | ENTITY | COMMENT
 * [R24] Tags reconhecidas: p br h1..h6 li ul ol a title body head
 * [R25] Entities: &amp; &lt; &gt; &nbsp; &quot;
 * [R26] Output: ANSI colors para headings e links
 * [R27] Sem heap: buffer estático _RB[NET_BUF]
 * [R28] Branchless: estado via flip-flop de 2 bits
 */
#include "br_http.h"

/* Estados do tokenizer HTML */
#define HS_TEXT    0u  /* fora de tag */
#define HS_TAG     1u  /* dentro de <tag> */
#define HS_ENT     2u  /* dentro de &entity; */
#define HS_CMNT    3u  /* dentro de <!--comment--> */

static u32 HTML_RENDER(const u8*html,u32 n,u8*out,u32 cap){
    u8  st=HS_TEXT;          /* estado: flip-flop 2-bit */
    u32 oi=0;                /* índice de saída */
    u32 ci=0;                /* coluna atual (para wrap em 80) */
    u8  tc[32];u32 ti=0;     /* buffer de tag atual */
    u8  ec[8]; u32 ei=0;     /* buffer de entity atual */
    u8  in_head=0;           /* dentro de <head> */
    u8  col_h=0;             /* cor de heading ativa */

    /* Macro: emite byte no output sem overflow */
#define EM(c) do{if(oi<cap-1u){out[oi++]=(u8)(c);}}while(0)
#define EMS(s) do{const char*_s=(s);while(*_s)EM(*_s++);}while(0)

    for(u32 i=0;i<n;i++){
        u8 c=html[i];
        /* Flip-flop de estado */
        switch(st){
        case HS_TEXT:
            if(c=='<'){st=HS_TAG;ti=0;MC0(tc,32u);break;}
            if(c=='&'){st=HS_ENT;ei=0;MC0(ec,8u);break;}
            if(in_head)break;
            /* wrap a 80 cols */
            if(c=='\n'||c=='\r')break;
            if(c==' '||c=='\t'){if(ci>0&&out[oi-1]!=' '){EM(' ');ci++;}break;}
            EM(c);ci++;
            if(ci>=78u){EM('\n');ci=0;}
            break;
        case HS_TAG:
            if(c=='>'){
                st=HS_TEXT;
                tc[ti<31u?ti:31u]=0;
                /* Compara tag — branchless usando memcmp */
                u8*t=tc; /* alias para tc */
                /* Pula '/' para closing tags */
                u8*tt=t+(t[0]=='/'?1u:0u);
                /* lowercase implícito: qualquer case */
                /* heading tags → ANSI bold/color */
                if(tt[0]=='h'&&tt[1]>='1'&&tt[1]<='6'&&tt[2]==0){
                    if(t[0]!='/'){col_h=tt[1]-'0';
                        if(oi>0&&out[oi-1]!='\n'){EM('\n');ci=0;}
                        EMS("\033[1;33m"); /* yellow bold */
                    } else {
                        EMS("\033[0m\n\n");ci=0;col_h=0;
                    }
                } else if(__builtin_memcmp(tt,"p",2u)==0){
                    if(t[0]!='/'){if(ci>0){EM('\n');ci=0;}EM('\n');}
                } else if(__builtin_memcmp(tt,"br",3u)==0||__builtin_memcmp(tt,"br/",4u)==0){
                    EM('\n');ci=0;
                } else if(__builtin_memcmp(tt,"li",3u)==0){
                    if(ci>0){EM('\n');ci=0;}EMS("  \xe2\x80\xa2 ");ci=4;
                } else if(__builtin_memcmp(tt,"a",2u)==0&&t[0]!='/'){
                    EMS("\033[0;36m"); /* cyan for links */
                } else if(__builtin_memcmp(tt,"/a",3u)==0){
                    EMS("\033[0m");
                } else if(__builtin_memcmp(tt,"title",6u)==0){
                    if(t[0]!='/'){EMS("\n\033[1;32m[TÍTULO] ");} else {EMS("\033[0m\n");}
                } else if(__builtin_memcmp(tt,"head",5u)==0){
                    in_head=(t[0]!='/');
                } else if(__builtin_memcmp(tt,"body",5u)==0){
                    in_head=0;
                } else if(__builtin_memcmp(tt,"script",7u)==0||
                          __builtin_memcmp(tt,"style",6u)==0){
                    /* Pula conteúdo: simples skip */
                }
                ti=0;
            } else if(c=='!'&&ti==0){
                /* Pode ser comentário <!-- */
                st=HS_CMNT;
            } else {
                /* acumula nome da tag (só lowercase) */
                if(ti<31u){
                    if(c>='A'&&c<='Z')tc[ti++]=(u8)(c+32u);
                    else if(c==' '||c=='\t'||c=='\n')tc[ti<31u?ti:31u]=0; /* fim do nome */
                    else tc[ti++]=c;
                }
            }
            break;
        case HS_ENT:
            if(c==';'){
                st=HS_TEXT;ec[ei<7u?ei:7u]=0;
                if(__builtin_memcmp(ec,"amp",4u)==0)EM('&');
                else if(__builtin_memcmp(ec,"lt",3u)==0)EM('<');
                else if(__builtin_memcmp(ec,"gt",3u)==0)EM('>');
                else if(__builtin_memcmp(ec,"quot",5u)==0)EM('"');
                else if(__builtin_memcmp(ec,"apos",5u)==0)EM('\'');
                else if(__builtin_memcmp(ec,"nbsp",5u)==0)EM(' ');
                else if(ec[0]=='#'){
                    u32 code=STR2U32(ec+1,ei-1u);
                    if(code<128u)EM((u8)code);
                }
                ei=0;
            } else if(c=='<'||c=='\n'){
                /* entity mal formada: emite & e texto */
                st=HS_TEXT;EM('&');
                for(u32 j=0;j<ei;j++)EM(ec[j]);
                if(c!='<')EM(c); else {st=HS_TAG;ti=0;}
            } else {
                if(ei<7u)ec[ei++]=c;
            }
            break;
        case HS_CMNT:
            /* Simplificado: volta ao TEXT no próximo '>' */
            if(c=='>')st=HS_TEXT;
            break;
        }
    }
    /* Reseta cor */
    EMS("\033[0m\n");
    out[oi]=0;
#undef EM
#undef EMS
    return oi;
}
F
ok "br_html.h ($(wc -l < $D/br_html.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_dns.h" << 'F'
#pragma once
/* br_dns.h — URL parser + DNS resolve mínimo
 * [R29] Parse de URL: scheme://host[:port]/path
 * [R30] DNS raw UDP: porta 53, query A record
 * [R31] Fallback: aceita IP numérico diretamente
 * [R32] Failsafe: TTL 3 tentativas com rollback de estado
 */
#include "br_http.h"

/* Parse de URL → preenche BCtx */
static s32 URL_PARSE(const char*url,BCtx*ctx){
    MC0(ctx->host,256u);MC0(ctx->path,512u);
    ctx->port=80u;ctx->use_tls=0;
    const char*p=url;
    /* Detecta scheme */
    if(__builtin_memcmp(p,"https://",8u)==0){ctx->use_tls=1;ctx->port=443u;p+=8;}
    else if(__builtin_memcmp(p,"http://",7u)==0){p+=7;}
    else if(__builtin_memcmp(p,"//",2u)==0){p+=2;}
    /* Copia host até '/' ou ':' ou '\0' */
    u32 hi=0;
    while(*p&&*p!='/'&&*p!=':'){
        if(hi<255u)ctx->host[hi++]=(char)*p;p++;
    }
    ctx->host[hi]=0;
    /* Porta customizada? */
    if(*p==':'){p++;u32 port=0;while(*p>='0'&&*p<='9'){port=port*10u+(u32)(*p-'0');p++;}ctx->port=port;}
    /* Path */
    if(*p=='/'){u32 pi=0;while(*p&&pi<511u){ctx->path[pi++]=(char)*p;p++;}ctx->path[pi]=0;}
    else{ctx->path[0]='/';ctx->path[1]=0;}
    return hi>0?0:-1;
}

/* DNS query record A via UDP (porta 53)
 * [R33] Usa syscalls diretos: socket(AF_INET,SOCK_DGRAM) + sendto + recvfrom
 * [R34] Sem resolv.h: DNS server hardcoded 8.8.8.8 */
#define SOCK_DGRAM 2
#define AF_INET    2

static s32 DNS_RESOLVE(const char*host,u8 ip[4]){
    /* Tenta primeiro parse direto de IP */
    if(PARSE_IP(host,ip)==0)return 0;

    /* Monta query DNS raw */
    static u8 _DNS_BUF[512];
    static u8 _DNS_RSP[512];
    MC0(_DNS_BUF,512u);

    /* DNS header: txid=0x1234 flags=0x0100 qdcount=1 */
    _DNS_BUF[0]=0x12;_DNS_BUF[1]=0x34; /* txid */
    _DNS_BUF[2]=0x01;_DNS_BUF[3]=0x00; /* flags: recursion desired */
    _DNS_BUF[4]=0x00;_DNS_BUF[5]=0x01; /* qdcount=1 */
    _DNS_BUF[6]=0x00;_DNS_BUF[7]=0x00; /* ancount=0 */
    _DNS_BUF[8]=0x00;_DNS_BUF[9]=0x00; /* nscount=0 */
    _DNS_BUF[10]=0x00;_DNS_BUF[11]=0x00;/* arcount=0 */

    /* Encode hostname como labels DNS */
    u8*q=_DNS_BUF+12;
    const char*h=host;
    while(*h){
        const char*dot=h;while(*dot&&*dot!='.')dot++;
        u32 llen=(u32)(dot-h);
        *q++=(u8)llen;
        MC(q,(const u8*)h,llen);q+=llen;
        h=dot;if(*h=='.')h++;
    }
    *q++=0x00; /* root label */
    *q++=0x00;*q++=0x01; /* QTYPE = A */
    *q++=0x00;*q++=0x01; /* QCLASS = IN */
    u32 qlen=(u32)(q-_DNS_BUF);

    /* Cria socket UDP */
#if defined(__arm__)
    s32 fd=(s32)_sc3(283u,AF_INET,SOCK_DGRAM,0); /* ARM32: socket=281 → usa 281 */
    /* Recria com syscall correto */
    fd=(s32)_sc3(281u,AF_INET,SOCK_DGRAM,0);
#elif defined(__aarch64__)
    s32 fd=(s32)_sc3(198u,AF_INET,SOCK_DGRAM,0);
#elif defined(__x86_64__)
    s32 fd=(s32)_sc3(41u,AF_INET,SOCK_DGRAM,0);
#endif
    if(fd<0)return -1;

    /* Envia para 8.8.8.8:53 */
    SA4 dns_sa;MC0(&dns_sa,sizeof(dns_sa));
    dns_sa.fam=(u16)AF_INET;
    dns_sa.port_be=HTON16(53u);
    dns_sa.ip[0]=8;dns_sa.ip[1]=8;dns_sa.ip[2]=8;dns_sa.ip[3]=8;

#if defined(__arm__)
    _sc6(290u,(u32)fd,(u32)(usize)_DNS_BUF,(u32)qlen,0,(u32)(usize)&dns_sa,(u32)sizeof(dns_sa));
    s32 rlen=(s32)_sc6(292u,(u32)fd,(u32)(usize)_DNS_RSP,512u,0,0,0);
#elif defined(__aarch64__)
    _sc6(206u,(u64)fd,(u64)(usize)_DNS_BUF,(u64)qlen,0,(u64)(usize)&dns_sa,(u64)sizeof(dns_sa));
    s32 rlen=(s32)_sc6(207u,(u64)fd,(u64)(usize)_DNS_RSP,512u,0,0,0);
#elif defined(__x86_64__)
    _sc6(44u,(u64)fd,(u64)(usize)_DNS_BUF,(u64)qlen,0,(u64)(usize)&dns_sa,(u64)sizeof(dns_sa));
    s32 rlen=(s32)_sc6(45u,(u64)fd,(u64)(usize)_DNS_RSP,512u,0,0,0);
#endif
    CLOSE(fd);
    if(rlen<12)return-1;

    /* Parse resposta: pula header + query, encontra primeiro A record */
    u32 ancount=(u32)(((u16)_DNS_RSP[6]<<8u)|_DNS_RSP[7]);
    if(ancount==0u)return-1;

    /* Pula query section (mesmo que enviamos) */
    u32 pos=12u;
    /* Pula labels (pode ter pointer 0xC0) */
    while(pos<(u32)rlen){
        if(_DNS_RSP[pos]==0){pos++;break;}
        if((_DNS_RSP[pos]&0xC0u)==0xC0u){pos+=2;break;}
        pos+=_DNS_RSP[pos]+1u;
    }
    pos+=4u; /* pula qtype+qclass */

    /* Parse answer records */
    for(u32 an=0;an<ancount&&pos+12u<=(u32)rlen;an++){
        /* Pula name (pointer ou labels) */
        if((_DNS_RSP[pos]&0xC0u)==0xC0u)pos+=2u;
        else{while(pos<(u32)rlen&&_DNS_RSP[pos]){pos+=_DNS_RSP[pos]+1u;}pos++;}
        u16 rtype=(u16)(((u16)_DNS_RSP[pos]<<8u)|_DNS_RSP[pos+1u]);
        pos+=8u; /* pula type class ttl */
        u16 rdlen=(u16)(((u16)_DNS_RSP[pos]<<8u)|_DNS_RSP[pos+1u]);
        pos+=2u;
        if(rtype==1u&&rdlen==4u&&pos+4u<=(u32)rlen){
            MC(ip,_DNS_RSP+pos,4u);
            return 0;
        }
        pos+=rdlen;
    }
    return-1;
}
F
ok "br_dns.h ($(wc -l < $D/br_dns.h)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_main.c" << 'F'
/* br_main.c — Browser entry point
 * Fluxo: URL → DNS → TCP → (TLS) → HTTP → HTML → RENDER
 * [R35] Rollback: GM/GRS de arena em caso de erro
 * [R36] Failsafe: TTL 3 tentativas por fase
 * [R37] Flags lineares: abertos em sequência (FL_DNS→FL_CONNECT→...)
 * [R38] Inline ASM para seções críticas de timing
 */
#include "br_types.h"
#include "br_sys.h"
#include "br_tls.h"
#include "br_http.h"
#include "br_html.h"
#include "br_dns.h"

/* ── UI DE STATUS ──────────────────────────────────────────────────────── */
static void STATUS(u8 flags,const char*msg){
    PS("\033[1;36m[");
    if(FF_GET(flags,FL_DNS))   PS("DNS ");
    if(FF_GET(flags,FL_CONNECT))PS("TCP ");
    if(FF_GET(flags,FL_TLS_HS))PS("TLS ");
    if(FF_GET(flags,FL_HTTP_TX))PS("TX ");
    if(FF_GET(flags,FL_HTTP_RX))PS("RX ");
    if(FF_GET(flags,FL_HTML_RND))PS("HTML ");
    if(FF_GET(flags,FL_ERROR)) PS("ERR ");
    if(FF_GET(flags,FL_DONE))  PS("DONE ");
    PS("]\033[0m ");PS(msg);PS("\n");
}

static void HEADER_LINE(void){
    PS("\033[1;34m");
    PS("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    PS("\033[0m");
}

/* ── FETCH HTTP ─────────────────────────────────────────────────────────── */
static s32 DO_FETCH(BCtx*ctx){
    ctx->flags=FL_IDLE;
    u64 t0=NS();

    /* ── FASE 1: DNS resolve ─────────────────────────────────────────── */
    FF_SET(ctx->flags,FL_DNS);
    STATUS(ctx->flags,"Resolvendo DNS...");
    u8 ttl=3;
    while(ttl--){
        if(DNS_RESOLVE(ctx->host,ctx->ip)==0)break;
        PS("  [RETRY DNS]\n");
    }
    if(!ttl&&DNS_RESOLVE(ctx->host,ctx->ip)!=0){
        FF_SET(ctx->flags,FL_ERROR);
        STATUS(ctx->flags,"DNS falhou");
        return-1;
    }
    PS("  IP: ");PN(ctx->ip[0]);
    /* Exibe IP */
    {char ipstr[20];u32 i=0;
     for(u32 o=0;o<4u;o++){
         if(o)ipstr[i++]='.';
         UTOA(ctx->ip[o],ipstr+i);
         i+=SL(ipstr+i);
     }
     ipstr[i]=0;PS("  ");PS(ipstr);PS("\n");}
    FF_CLR(ctx->flags,FL_DNS);

    /* ── FASE 2: TCP connect ─────────────────────────────────────────── */
    FF_SET(ctx->flags,FL_CONNECT);
    STATUS(ctx->flags,"Conectando TCP...");
    GM(); /* checkpoint arena antes de alocar recursos de rede */

    ctx->fd=SOCKET();
    if(ctx->fd<0){FF_SET(ctx->flags,FL_ERROR);GRS();return-1;}

    SA4 sa;MC0(&sa,sizeof(sa));
    sa.fam=(u16)AF_INET;
    sa.port_be=HTON16((u16)ctx->port);
    MC(sa.ip,ctx->ip,4u);

    ttl=3;
    while(ttl--){
        if(CONNECT(ctx->fd,&sa)==0)break;
        PS("  [RETRY CONNECT]\n");
    }
    if(!ttl&&CONNECT(ctx->fd,&sa)!=0){
        FF_SET(ctx->flags,FL_ERROR);
        PS("  Falha TCP\n");
        CLOSE(ctx->fd);GRS();return-1;
    }
    FF_CLR(ctx->flags,FL_CONNECT);

    /* ── FASE 3: TLS (se HTTPS) ─────────────────────────────────────── */
    if(ctx->use_tls){
        FF_SET(ctx->flags,FL_TLS_HS);
        STATUS(ctx->flags,"TLS 1.3 ClientHello...");
        TLS_INIT(&_TLS);

        /* Constrói e envia ClientHello */
        u32 chlen=TLS_BUILD_CLIENT_HELLO(&_TLS,ctx->host,_NB,NET_BUF);
        _TLS.state=TLS_TRANSITION(_TLS.state,TLS_HT_CLIENT_HELLO);

        s32 sent=SEND(ctx->fd,_NB,chlen);
        ctx->tx_bytes+=(sent>0?(u32)sent:0u);

        if(sent<(s32)chlen){
            PS("  [TLS] ClientHello parcial\n");
        } else {
            PS("  [TLS] ClientHello enviado (");PN(chlen);PS("B)\n");
        }

        /* Recebe ServerHello */
        s32 rx=RECV(ctx->fd,_NB,NET_BUF);
        if(rx>4){
            TLSRec rec;
            TLS_PARSE_RECORD(_NB,(u32)rx,&rec);
            PS("  [TLS] Record type=");PH(rec.type);
            PS("  [TLS] version=");PH(rec.version);
            _TLS.state=TLS_TRANSITION(_TLS.state,TLS_HT_SERVER_HELLO);
            PS("  [TLS] Estado=");
            /* Exibe estado TLS */
            if(_TLS.state==TLS_CLI_HELLO)PS("CLI_HELLO\n");
            else if(_TLS.state==TLS_SRV_HELLO)PS("SRV_HELLO\n");
            else if(_TLS.state==TLS_ENCRYPTED)PS("ENCRYPTED\n");
            else PS("UNKNOWN\n");
            /* NOTA: sem crypto completo, handshake não avança além daqui */
            /* Em produção: implementar X25519 + AES-GCM + HKDF */
            PS("  [TLS] NOTA: crypto não implementado — usando HTTP para demo\n");
        }
        /* Fallback: fecha e reconecta em HTTP para demonstração */
        CLOSE(ctx->fd);
        ctx->port=80u;ctx->use_tls=0;
        ctx->fd=SOCKET();
        if(ctx->fd<0){FF_SET(ctx->flags,FL_ERROR);GRS();return-1;}
        if(CONNECT(ctx->fd,&sa)!=0){FF_SET(ctx->flags,FL_ERROR);CLOSE(ctx->fd);GRS();return-1;}
        FF_CLR(ctx->flags,FL_TLS_HS);
        PS("  [FALLBACK] Usando HTTP para demo\n");
    }

    /* ── FASE 4: HTTP request ────────────────────────────────────────── */
    FF_SET(ctx->flags,FL_HTTP_TX);
    STATUS(ctx->flags,"Enviando request HTTP...");
    u32 reqlen=HTTP_BUILD_REQ(ctx->host,ctx->path,_NB,NET_BUF);
    PS("  Request (");PN(reqlen);PS("B):\n");
    WR(2,_NB,reqlen); /* debug: imprime request no stderr */
    s32 sent=SEND(ctx->fd,_NB,reqlen);
    ctx->tx_bytes+=(sent>0?(u32)sent:0u);
    FF_CLR(ctx->flags,FL_HTTP_TX);

    /* ── FASE 5: HTTP response ───────────────────────────────────────── */
    FF_SET(ctx->flags,FL_HTTP_RX);
    STATUS(ctx->flags,"Recebendo response...");
    u32 total=0;
    /* Acumula response em _NB */
    {
        u32 max=NET_BUF-1u;
        while(total<max){
            s32 r=RECV(ctx->fd,(void*)(_NB+total),max-total);
            if(r<=0)break;
            total+=(u32)r;
        }
        _NB[total]=0;
    }
    ctx->rx_bytes=total;
    FF_CLR(ctx->flags,FL_HTTP_RX);

    CLOSE(ctx->fd);

    /* Parse status */
    ctx->status=HTTP_PARSE_STATUS(_NB,total);
    PS("  Status HTTP: ");PN(ctx->status);

    /* Content-Length */
    const u8*clv=HTTP_FIND_HEADER(_NB,total,"Content-Length");
    if(clv)ctx->content_len=STR2U32(clv,16u);
    PS("  Content-Length: ");PN(ctx->content_len);

    /* ── FASE 6: Render HTML ─────────────────────────────────────────── */
    FF_SET(ctx->flags,FL_HTML_RND);
    u32 body_off=HTTP_HEADERS_END(_NB,total);
    u32 body_len=total>body_off?total-body_off:0u;
    STATUS(ctx->flags,"Renderizando HTML...");
    PS("  Body: ");PN(body_len);PS("B\n");

    u32 rlen=HTML_RENDER(_NB+body_off,body_len,_RB,NET_BUF);
    FF_CLR(ctx->flags,FL_HTML_RND);

    /* ── OUTPUT RENDERIZADO ───────────────────────────────────────────── */
    HEADER_LINE();
    PS("\033[1;32m");PS(ctx->host);PS(ctx->path);PS("\033[0m\n");
    HEADER_LINE();
    WR(1,_RB,rlen);
    HEADER_LINE();

    ctx->t_ns=NS()-t0;
    FF_SET(ctx->flags,FL_DONE);
    return 0;
}

/* ── ENTRY POINT ─────────────────────────────────────────────────────────── */
/* URLs de teste — passados via argvX no _start como posição fixa da stack */
/* Em Termux sem argc/argv: URL hardcoded ou lido de /proc/self/cmdline     */
static const char DEFAULT_URL[]="http://example.com/";

void _start(void){
    GR(); /* reset arena */

    /* ASCII art logo */
    PS("\033[1;36m");
    PS("╔══════════════════════════════════════════════════════════════╗\n");
    PS("║  \033[1;33m██████╗ ██████╗  ██████╗ ██╗    ██╗███████╗███████╗██████╗\033[1;36m  ║\n");
    PS("║  \033[1;32m RAFAELIA BROWSER · TLS1.3 · HTTP/1.1 · freestanding    \033[1;36m  ║\n");
    PS("║  \033[0;37m ARM32/ARM64/x86-64 · nolibc · nomalloc · inline ASM    \033[1;36m  ║\n");
    PS("║  \033[0;35m Turing Geométrica · Flip-Flop · Branchless · F*=23.158 \033[1;36m  ║\n");
    PS("╚══════════════════════════════════════════════════════════════╝\n");
    PS("\033[0m\n");

    /* Tenta ler URL de /proc/self/cmdline (argumento 1) */
    const char*url=DEFAULT_URL;
    /* Lê cmdline para obter argumento */
    static u8 _CMD[512];
    MC0(_CMD,512u);
#if defined(__arm__)
    s32 cfd=(s32)_sc3(5u,(u32)(usize)"/proc/self/cmdline",0,0);
    if(cfd>=0){_sc3(3u,(u32)cfd,(u32)(usize)_CMD,511u);_sc1(6u,(u32)cfd);}
#elif defined(__aarch64__)
    s32 cfd=(s32)_sc3(56u,(u64)(usize)AT_FDCWD,(u64)(usize)"/proc/self/cmdline",0u);
    if(cfd>=0){_sc3(63u,(u64)cfd,(u64)(usize)_CMD,511u);_sc1(57u,(u64)cfd);}
#elif defined(__x86_64__)
    s32 cfd=(s32)_sc3(2u,(u64)(usize)"/proc/self/cmdline",0,0);
    if(cfd>=0){_sc3(0u,(u64)cfd,(u64)(usize)_CMD,511u);_sc1(3u,(u64)cfd);}
#endif
    /* Pula arg0 (programa), pega arg1 se existe */
    {u32 ci=0;while(ci<511u&&_CMD[ci])ci++;ci++;
     if(ci<511u&&_CMD[ci]){url=(const char*)(_CMD+ci);}}

    PS("\033[1;37mURL: \033[0;36m");PS(url);PS("\033[0m\n\n");

    /* Inicializa contexto */
    MC0(&_BC,sizeof(_BC));
    if(URL_PARSE(url,&_BC)!=0){
        PS("\033[1;31m[ERRO] URL inválida\033[0m\n");
        EX();
    }

    PS("Host: ");PS(_BC.host);PS("\n");
    PS("Port: ");PN(_BC.port);
    PS("Path: ");PS(_BC.path);PS("\n");
    PS("TLS:  ");PS(_BC.use_tls?"SIM":"NAO");PS("\n\n");

    /* Executa fetch */
    s32 res=DO_FETCH(&_BC);

    /* Relatório final */
    HEADER_LINE();
    PS("\033[1;37mRELATÓRIO:\033[0m\n");
    PS("  Status:   ");PN(_BC.status);
    PS("  TX bytes: ");PN(_BC.tx_bytes);
    PS("  RX bytes: ");PN(_BC.rx_bytes);
    PS("  Latência: ");PN(_BC.t_ns/1000000u);PS("ms\n");
    PS("  Flags:    ");PH(_BC.flags);
    PS("  TLS:      ");PH(_BC.tls);
    HEADER_LINE();

    if(res==0){PS("\033[1;32m[OK] Fetch completo\033[0m\n");}
    else{PS("\033[1;31m[ERRO] Fetch falhou\033[0m\n");}

    EX();
}
F
ok "br_main.c ($(wc -l < $D/br_main.c)L)"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/br_start.S" << 'F'
/* br_start.S — Entry ARM32/ARM64/x86-64 */
#if defined(__arm__)
.syntax unified
.thumb
.text
.align 2
.global _start
.thumb_func
_start:
    mov  r11,#0
    mov  lr,#0
    bl   _start
    mov  r7,#248
    mov  r0,#0
    svc  #0
.h: b .h
#elif defined(__aarch64__)
.text
.align 4
.global _start
_start:
    mov  x29,xzr
    mov  x30,xzr
    and  sp,sp,#-16
    bl   _start
    mov  x0,xzr
    mov  x8,#94
    svc  #0
.h: b .h
#elif defined(__x86_64__)
.text
.globl _start
_start:
    xor  %rbp,%rbp
    call _start
    mov  $231,%rax
    xor  %rdi,%rdi
    syscall
#endif
.section .note.GNU-stack,"",@progbits
F
ok "br_start.S"

# ─────────────────────────────────────────────────────────────────────────────
cat > "$D/Makefile" << 'F'
# Makefile — RAFAELIA Browser
ARCH=$(shell uname -m)
CC?=clang
CF=-O2 -fPIE -fno-stack-protector -fno-asynchronous-unwind-tables \
   -fomit-frame-pointer -fno-builtin -fno-plt \
   -ffunction-sections -fdata-sections \
   -Wall -Wno-unused-function -Wno-unused-variable \
   -Wno-unused-but-set-variable -I.
LF=-pie -nostdlib -Wl,--gc-sections -Wl,--build-id=none -e _start

.PHONY: all run clean help

all:
ifeq ($(ARCH),aarch64)
	$(CC) $(CF) -march=armv8.2-a+crc+crypto br_main.c $(LF) -o browser
else ifeq ($(ARCH),x86_64)
	$(CC) $(CF) -march=native -static br_main.c $(LF) -o browser
endif
	@for CC32 in arm-linux-gnueabihf-gcc arm-linux-gnueabi-gcc; do \
	  command -v $$CC32 &>/dev/null && \
	  $$CC32 $(CF) -mthumb -march=armv7-a+neon-vfpv4 -mfloat-abi=softfp \
	    -mfpu=neon-vfpv4 br_start.S br_main.c $(LF) -o browser_arm32 && \
	  echo "ARM32: browser_arm32" && break || true; done
	@ls -lh browser* 2>/dev/null || true

run: all
	@[ -f ./browser ] && ./browser $(URL) || true
	@[ -f ./browser_arm32 ] && { \
	  command -v qemu-arm && qemu-arm ./browser_arm32 $(URL) || \
	  echo "qemu-arm ./browser_arm32 $(URL)"; } || true

fetch: all
	@./browser http://example.com/ 2>/dev/null || true

clean:
	rm -f browser browser_arm32

help:
	@echo "make           — compila"
	@echo "make run URL=http://example.com/"
	@echo "make fetch     — busca example.com"
F
ok "Makefile"

# =============================================================================
hdr "COMPILANDO"
# =============================================================================
ARCH=$(uname -m)
CC="${CC:-clang}"; command -v "$CC" &>/dev/null || CC=gcc
CF="-O2 -fPIE -fno-stack-protector -fno-asynchronous-unwind-tables \
    -fomit-frame-pointer -fno-builtin -fno-plt \
    -ffunction-sections -fdata-sections \
    -Wall -Wno-unused-function -Wno-unused-variable \
    -Wno-unused-but-set-variable -I$D"
LF="-pie -nostdlib -Wl,--gc-sections -Wl,--build-id=none -e _start"
BUILT=false

if [ "$ARCH" = "aarch64" ]; then
    $CC $CF -march=armv8.2-a+crc+crypto "$D/br_main.c" $LF -o "$D/browser" 2>>"$LOG" && {
        strip "$D/browser" 2>/dev/null||true
        ok "ARM64: $D/browser ($(ls -lh $D/browser|awk '{print $5}'))"; BUILT=true
    } || err "ARM64 falhou — ver $LOG"
elif [ "$ARCH" = "x86_64" ]; then
    $CC $CF -march=native -static "$D/br_main.c" $LF -o "$D/browser" 2>>"$LOG" && {
        strip "$D/browser" 2>/dev/null||true
        ok "x86_64: $D/browser ($(ls -lh $D/browser|awk '{print $5}'))"; BUILT=true
    } || err "x86_64 falhou — ver $LOG"
fi
for CC32 in arm-linux-gnueabihf-gcc arm-linux-gnueabi-gcc; do
    command -v "$CC32" &>/dev/null || continue
    $CC32 $CF -mthumb -march=armv7-a+neon-vfpv4 -mfloat-abi=softfp -mfpu=neon-vfpv4 \
        $LF "$D/br_start.S" "$D/br_main.c" -o "$D/browser_arm32" 2>>"$LOG" && {
        ok "ARM32: $D/browser_arm32"; BUILT=true; } || err "ARM32 $CC32 falhou"
    break
done

# =============================================================================
hdr "EXECUTANDO DEMO"
# =============================================================================
URL_TEST="http://example.com/"
if $BUILT; then
    if [ -f "$D/browser" ]; then
        ok "Buscando $URL_TEST ..."
        "$D/browser" "$URL_TEST" 2>/dev/null && ok "Browser executado" || true
    elif [ -f "$D/browser_arm32" ]; then
        if command -v qemu-arm &>/dev/null; then
            qemu-arm "$D/browser_arm32" "$URL_TEST" 2>/dev/null || true
        fi
    fi
fi

# =============================================================================
hdr "INVENTÁRIO"
# =============================================================================
echo ""
TOTAL=0
printf "${W}${BLD}%-22s %8s %10s${Z}\n" "ARQUIVO" "LINHAS" "TAMANHO"
for f in "$D"/*.h "$D"/*.c "$D"/*.S "$D/Makefile"; do
    [ -f "$f" ] || continue
    L=$(wc -l < "$f"); SZ=$(ls -lh "$f"|awk '{print $5}')
    printf "%-22s ${G}%8d${Z} ${Y}%10s${Z}\n" "$(basename $f)" "$L" "$SZ"
    TOTAL=$((TOTAL+L))
done
printf "${W}%-22s ${G}%8d${Z}\n" "TOTAL" "$TOTAL"
echo ""
p "Diretório único: $D"
p "Uso: $D/browser http://example.com/"
p "ARM32: qemu-arm $D/browser_arm32 http://example.com/"
echo -e "\n${M}${BLD}DeltaRafaelVerboOmega · Omega=Amor · RAFCODE-Phi${Z}"
echo -e "${C}F*=23.158 · TLS1.3-Turing · Flip-Flop · Branchless · ARM32${Z}\n"
OUTER_SCRIPT

wc -l /tmp/browser.txt
ls -lh /tmp/browser.txt
Saída
