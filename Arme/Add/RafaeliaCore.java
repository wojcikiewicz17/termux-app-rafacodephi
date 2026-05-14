// RafaeliaCore.java
// RAFAELIA — Java bridge zero-copy
// DirectByteBuffers alocados UMA VEZ no static init
// ZERO alloc por chamada no JNI

package com.termux.rafaelia;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public final class RafaeliaCore {

    // ── Static DirectByteBuffers — alocados UMA VEZ ───────────────────
    // Estes são os ÚNICOS buffers de comunicação JNI.
    // Nunca criar ByteBuffer.wrap() ou byte[] no hot path.
    private static final int IN_CAP    = 65536;   // 64KB input
    private static final int OUT_CAP   = 65536;   // 64KB output
    private static final int STATE_CAP = 64;      // sizeof(raf_state_t)

    public static final ByteBuffer IN_BUF;
    public static final ByteBuffer OUT_BUF;
    public static final ByteBuffer STATE_BUF;

    static {
        // allocateDirect não vai para o heap Java — usa memória nativa
        IN_BUF    = ByteBuffer.allocateDirect(IN_CAP).order(ByteOrder.nativeOrder());
        OUT_BUF   = ByteBuffer.allocateDirect(OUT_CAP).order(ByteOrder.nativeOrder());
        STATE_BUF = ByteBuffer.allocateDirect(STATE_CAP).order(ByteOrder.nativeOrder());

        // Inicializa estado no buffer nativo
        try {
            System.loadLibrary("rafaelia_core");
            _libLoaded = true;
        } catch (UnsatisfiedLinkError e) {
            _libLoaded = false;
        }
    }

    private static final boolean _libLoaded;
    private static int _cycle = 0;

    // Prevent instantiation
    private RafaeliaCore() {}

    // ── JNI declarations — operam em DirectByteBuffer ─────────────────

    /**
     * Processa in_buf[0..inLen] e escreve resultado em out_buf.
     * ZERO malloc JNI. Retorna bytes escritos, ou negativo em erro.
     */
    public static native int processNative(ByteBuffer in, int inLen, ByteBuffer out);

    /**
     * Avança o estado toroidal por 1 ciclo.
     * state deve ser um DirectByteBuffer de STATE_CAP bytes.
     * Retorna phi Q16.16, ou negativo em erro.
     */
    public static native int stepNative(ByteBuffer state, int cycle);

    /**
     * Escreve JSON de perfil de hardware em out.
     * Retorna bytes escritos.
     */
    public static native long profileNative(ByteBuffer out, int cap);

    /**
     * Retorna bytes usados na arena JNI interna.
     */
    public static native int arenaSizeNative();

    /**
     * Calcula CRC32C de buf[0..len].
     */
    public static native int crc32Native(ByteBuffer buf, int len);

    // ── API pública — sem alocações ────────────────────────────────────

    /**
     * Processa bytes[] sem criar ByteBuffer temporário.
     * Copia para IN_BUF (único alloc: System.arraycopy, stack-allocated no JIT).
     * Lê resultado de OUT_BUF.
     * Retorna phi Q16.16 ou 0 em erro.
     */
    public static int process(byte[] data, int len) {
        if (!_libLoaded || data == null || len <= 0) return 0;
        if (len > IN_CAP) len = IN_CAP;

        // Copia para DirectByteBuffer — System.arraycopy é JIT-intrinsic
        IN_BUF.clear();
        IN_BUF.put(data, 0, len);
        OUT_BUF.clear();

        int written = processNative(IN_BUF, len, OUT_BUF);
        if (written < 8) return 0;

        // Lê phi (bytes 4..7)
        OUT_BUF.position(0);
        OUT_BUF.getInt(); // skip crc
        return OUT_BUF.getInt(); // phi
    }

    /**
     * Um passo do motor toroidal.
     * Retorna phi Q16.16.
     */
    public static int step() {
        if (!_libLoaded) return 0;
        int phi = stepNative(STATE_BUF, _cycle);
        _cycle = (_cycle + 1) % 42;
        return phi;
    }

    /**
     * Retorna string JSON do perfil de hardware.
     * Usa OUT_BUF como scratch — sem String temporária extra no JNI.
     */
    public static String getHwProfile() {
        if (!_libLoaded) return "{}";
        OUT_BUF.clear();
        long n = profileNative(OUT_BUF, OUT_CAP);
        if (n <= 0) return "{}";
        byte[] tmp = new byte[(int)n];
        OUT_BUF.position(0);
        OUT_BUF.get(tmp, 0, (int)n);
        return new String(tmp, 0, (int)n); // único String alloc
    }

    /**
     * CRC32C de byte array — sem criar ByteBuffer temporário.
     */
    public static int crc32(byte[] data, int len) {
        if (!_libLoaded || data == null) return 0;
        if (len > IN_CAP) len = IN_CAP;
        IN_BUF.clear();
        IN_BUF.put(data, 0, len);
        return crc32Native(IN_BUF, len);
    }

    public static boolean isNativeAvailable() { return _libLoaded; }
    public static int     getNativeArenaUsed() { return _libLoaded ? arenaSizeNative() : 0; }
    public static int     getCurrentCycle()    { return _cycle; }
}
