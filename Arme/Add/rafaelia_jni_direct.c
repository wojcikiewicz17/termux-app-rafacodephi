/**
 * rafaelia_jni_direct.c
 * JNI bridge zero-copy usando DirectByteBuffer
 * ZERO malloc/NewByteArray por chamada
 *
 * Java lado:
 *   static final ByteBuffer IN  = ByteBuffer.allocateDirect(65536);
 *   static final ByteBuffer OUT = ByteBuffer.allocateDirect(65536);
 *   static native int processNative(ByteBuffer in, int len, ByteBuffer out);
 *   static native int stepNative(ByteBuffer state, int cycle);
 *   static native long profileNative(ByteBuffer out, int cap);
 *
 * Compilar como parte do Android.mk (veja Android_nomalloc.mk)
 */

#include <jni.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#ifdef __ANDROID__
#include <android/log.h>
#define TAG "RafaeliaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)
#else
#define LOGI(...) (void)0
#define LOGE(...) (void)0
#endif

/* ── CRC32C inline (sem dep externa) ──────────────────────────────────── */
static uint32_t _crc_tab[256];
static int      _crc_ready = 0;

static void _crc_build(void) {
    for (uint32_t i=0;i<256;i++){
        uint32_t v=i;
        for(int j=0;j<8;j++) v=(v&1)?(v>>1)^0x82F63B78u:(v>>1);
        _crc_tab[i]=v;
    }
    _crc_ready=1;
}

static uint32_t _crc32(const void *buf, size_t n) {
    if (!_crc_ready) _crc_build();
    const uint8_t *p=(const uint8_t*)buf;
    uint32_t c=0xFFFFFFFFu;
    while(n--) c=(c>>8)^_crc_tab[(c^*p++)&0xFF];
    return ~c;
}

/* ── Estado global do orquestrador (sem malloc) ───────────────────────── */
#define RAF_STATE_DIM  7
#define RAF_PERIOD     42
#define RAF_VCPU       8

/* estado 7D + coerência + entropia + fase + step + crc */
typedef struct __attribute__((packed)) {
    uint32_t s[RAF_STATE_DIM];  /* Q16.16 */
    uint32_t coherence;         /* Q16.16 */
    uint32_t entropy;           /* Q16.16 */
    uint32_t phase;             /* 0..41  */
    uint32_t step;
    uint32_t crc;
} raf_state_t;

/* arena estática de 256KB para JNI — sem malloc */
#define JNI_ARENA_SZ (256u*1024u)
static uint8_t __attribute__((aligned(64))) g_jni_arena[JNI_ARENA_SZ];
static uint32_t g_jni_bump = 0;

static void *jni_alloc(uint32_t n) {
    uint32_t s = (g_jni_bump + 63u) & ~63u;
    if (s+n > JNI_ARENA_SZ) return NULL;
    g_jni_bump = s+n;
    return g_jni_arena+s;
}

static raf_state_t *g_state = NULL;  /* aponta para arena */

static void ensure_state(void) {
    if (g_state) return;
    g_state = (raf_state_t*)jni_alloc(sizeof(raf_state_t));
    if (!g_state) return;
    /* init: toroidal map com constantes irracionais */
    const uint32_t seeds[7] = {
        56755u, 105965u, 205887u,
        46341u, 92682u,  138564u, 184245u
    };
    for (int i=0;i<RAF_STATE_DIM;i++) g_state->s[i] = seeds[i] & 0xFFFFu;
    g_state->coherence = 0x8000u;
    g_state->entropy   = 0x8000u;
    g_state->phase     = 0;
    g_state->step      = 0;
    g_state->crc       = 0;
    g_state->crc = _crc32(g_state, offsetof(raf_state_t, crc));
}

/* EMA update Q16.16 */
static uint32_t ema(uint32_t old, uint32_t in) {
    /* 0.75*old + 0.25*in — sem float */
    return (uint32_t)(((uint64_t)old*49152u + (uint64_t)in*16384u) >> 16);
}

/* ── processNative ────────────────────────────────────────────────────── */
/* Java: int processNative(ByteBuffer in, int inLen, ByteBuffer out)
 * Retorna: bytes escritos em out, ou -1 em erro
 * Zero malloc: opera diretamente nos DirectByteBuffer */
JNIEXPORT jint JNICALL
Java_com_termux_rafaelia_RafaeliaCore_processNative(
    JNIEnv *env, jclass cls,
    jobject in_buf, jint in_len,
    jobject out_buf)
{
    (void)cls;

    uint8_t *in  = (uint8_t*)(*env)->GetDirectBufferAddress(env, in_buf);
    uint8_t *out = (uint8_t*)(*env)->GetDirectBufferAddress(env, out_buf);
    jlong out_cap = (*env)->GetDirectBufferCapacity(env, out_buf);

    if (!in || !out || in_len <= 0 || out_cap < 8) return -1;

    ensure_state();
    if (!g_state) return -2;

    /* Verifica integridade do estado */
    uint32_t saved_crc = g_state->crc;
    g_state->crc = 0;
    uint32_t check = _crc32(g_state, offsetof(raf_state_t, crc));
    g_state->crc = saved_crc;
    if (check != saved_crc) {
        /* rollback para init */
        g_state->coherence = 0x8000u;
        g_state->entropy   = 0x8000u;
        g_state->phase     = 0;
    }

    /* Processa: CRC do input como C_in, entropia como H_in */
    uint32_t c_in = _crc32(in, (size_t)in_len) & 0xFFFFu;
    /* H_in: shannon approximation — unique bytes / 256 * 65535 */
    uint8_t seen[256];
    memset(seen, 0, 256);
    int uniq = 0;
    for (int i=0; i<in_len && i<4096; i++)
        if (!seen[in[i]]) { seen[in[i]]=1; uniq++; }
    uint32_t h_in = (uint32_t)((uint64_t)uniq * 65535u / 256u);

    /* EMA update */
    g_state->coherence = ema(g_state->coherence, c_in);
    g_state->entropy   = ema(g_state->entropy,   h_in);

    /* phi = (1-H)*C Q16.16 */
    uint32_t H = g_state->entropy;
    uint32_t C = g_state->coherence;
    uint32_t phi = (uint32_t)(((uint64_t)(65535u-H)*C) >> 16);

    /* avança fase */
    g_state->phase = (g_state->phase+1u >= RAF_PERIOD) ? 0 : g_state->phase+1u;
    g_state->step++;

    /* atualiza CRC */
    g_state->crc = 0;
    g_state->crc = _crc32(g_state, offsetof(raf_state_t, crc));

    /* escreve resultado em out (8 bytes): crc(in) | phi | phase | step */
    if (out_cap >= 16) {
        uint32_t r[4] = {
            _crc32(in,(size_t)in_len),
            phi,
            g_state->phase,
            g_state->step
        };
        memcpy(out, r, 16);
        return 16;
    }
    uint32_t r2[2] = { _crc32(in,(size_t)in_len), phi };
    memcpy(out, r2, 8);
    return 8;
}

/* ── stepNative ───────────────────────────────────────────────────────── */
/* Java: int stepNative(ByteBuffer state, int cycle)
 * state: DirectByteBuffer de sizeof(raf_state_t) bytes — lê/escreve
 * cycle: 0..41
 * Retorna: phi Q16.16 */
JNIEXPORT jint JNICALL
Java_com_termux_rafaelia_RafaeliaCore_stepNative(
    JNIEnv *env, jclass cls,
    jobject state_buf, jint cycle)
{
    (void)cls;

    raf_state_t *st = (raf_state_t*)(*env)->GetDirectBufferAddress(env, state_buf);
    jlong cap = (*env)->GetDirectBufferCapacity(env, state_buf);
    if (!st || cap < (jlong)sizeof(raf_state_t)) return -1;

    /* verifica CRC */
    uint32_t sc = st->crc;
    st->crc = 0;
    if (_crc32(st, offsetof(raf_state_t,crc)) != sc) {
        /* corrupção detectada — reinit */
        st->coherence = 0x8000u;
        st->entropy   = 0x8000u;
        st->phase     = 0;
        st->step      = 0;
    }
    st->crc = sc;

    /* input sintético baseado no ciclo */
    uint32_t c_in = (uint32_t)((56755u * (uint32_t)cycle) >> 4) & 0xFFFFu;
    uint32_t h_in = (uint32_t)((65535u - c_in));

    st->coherence = ema(st->coherence, c_in);
    st->entropy   = ema(st->entropy,   h_in);

    /* atualiza 7D state: s[i] = (s[i]*SPIRAL + s[(i+1)%7]) mod 65536 */
    for (int i=0; i<RAF_STATE_DIM; i++) {
        uint32_t next = (uint32_t)(((uint64_t)st->s[i] * 56755u) >> 16);
        next += st->s[(i+1)%RAF_STATE_DIM];
        st->s[i] = next & 0xFFFFu;
    }

    st->phase = ((uint32_t)cycle) % RAF_PERIOD;
    st->step++;

    uint32_t phi = (uint32_t)(((uint64_t)(65535u-st->entropy)*st->coherence)>>16);

    st->crc = 0;
    st->crc = _crc32(st, offsetof(raf_state_t,crc));

    return (jint)phi;
}

/* ── profileNative ────────────────────────────────────────────────────── */
/* Java: long profileNative(ByteBuffer out, int cap)
 * Escreve JSON de hw_profile em out sem malloc
 * Retorna: bytes escritos */
JNIEXPORT jlong JNICALL
Java_com_termux_rafaelia_RafaeliaCore_profileNative(
    JNIEnv *env, jclass cls,
    jobject out_buf, jint cap)
{
    (void)cls;
    char *out = (char*)(*env)->GetDirectBufferAddress(env, out_buf);
    if (!out || cap < 64) return -1;

    /* lê dados sem malloc — buffers na stack */
    char cpu_online[64]={0}, freq0[32]={0}, freq1[32]={0};
    char pg[16]={0};

    int fd;
    ssize_t n;

    fd=open("/sys/devices/system/cpu/online",O_RDONLY|O_CLOEXEC);
    if(fd>=0){n=read(fd,cpu_online,63);close(fd);if(n>0)cpu_online[n]=0;}

    fd=open("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq",O_RDONLY|O_CLOEXEC);
    if(fd>=0){n=read(fd,freq0,31);close(fd);if(n>0)freq0[n]=0;}

    fd=open("/sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq",O_RDONLY|O_CLOEXEC);
    if(fd>=0){n=read(fd,freq1,31);close(fd);if(n>0)freq1[n]=0;}

    long pgsz = sysconf(_SC_PAGESIZE);
    if (pgsz>0) {
        int pi=0; long v=pgsz;
        char tmp[12]; int tl=0;
        while(v){tmp[tl++]=(char)('0'+v%10);v/=10;}
        for(int k=tl-1;k>=0;k--) pg[pi++]=tmp[k];
        pg[pi]=0;
    }

    /* remove newlines */
    for(char*p=cpu_online;*p;p++) if(*p=='\n')*p=0;
    for(char*p=freq0;*p;p++) if(*p=='\n')*p=0;
    for(char*p=freq1;*p;p++) if(*p=='\n')*p=0;

    /* monta JSON sem snprintf */
    const char *arch =
#if defined(__aarch64__)
        "arm64-v8a";
#elif defined(__arm__)
        "armeabi-v7a";
#else
        "generic";
#endif

#define HAS_NEON_STR (defined(HAS_NEON) ? "true" : "false")

    /* escreve JSON manualmente no buffer out */
    int pos = 0;
#define WSTR(s) do { \
    const char *_s=(s); \
    while(*_s && pos<cap-1) out[pos++]=*_s++; \
} while(0)

    WSTR("{\"abi\":\""); WSTR(arch);
    WSTR("\",\"cpus\":\""); WSTR(cpu_online);
    WSTR("\",\"freq0\":\""); WSTR(freq0);
    WSTR("\",\"freq1\":\""); WSTR(freq1);
    WSTR("\",\"page_sz\":\""); WSTR(pg);
#ifdef HAS_NEON
    WSTR("\",\"neon\":true");
#else
    WSTR("\",\"neon\":false");
#endif
    WSTR("}");
    if (pos < cap) out[pos] = 0;
#undef WSTR

    return (jlong)pos;
}

/* ── arenaSizeNative ──────────────────────────────────────────────────── */
/* Retorna bytes usados na arena JNI */
JNIEXPORT jint JNICALL
Java_com_termux_rafaelia_RafaeliaCore_arenaSizeNative(
    JNIEnv *env, jclass cls)
{
    (void)env; (void)cls;
    return (jint)g_jni_bump;
}

/* ── crc32Native ──────────────────────────────────────────────────────── */
/* Java: int crc32Native(ByteBuffer buf, int len) */
JNIEXPORT jint JNICALL
Java_com_termux_rafaelia_RafaeliaCore_crc32Native(
    JNIEnv *env, jclass cls,
    jobject buf, jint len)
{
    (void)cls;
    uint8_t *p = (uint8_t*)(*env)->GetDirectBufferAddress(env, buf);
    if (!p || len<=0) return 0;
    return (jint)_crc32(p,(size_t)len);
}
