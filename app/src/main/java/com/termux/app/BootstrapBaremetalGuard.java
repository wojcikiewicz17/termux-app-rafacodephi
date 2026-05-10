package com.termux.app;

import com.termux.rafacodephi.BuildConfig;
import com.termux.shared.logger.Logger;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

final class BootstrapBaremetalGuard {
    private static final String LOG_TAG = "BootstrapBaremetalGuard";
    private static final int BUFFER_CAPACITY = 2048;
    private static final ByteBuffer SHARED_BUFFER = ByteBuffer.allocateDirect(BUFFER_CAPACITY);
    private static final boolean LIB_LOADED;

    static {
        boolean loaded;
        try {
            System.loadLibrary("termux-baremetal");
            loaded = true;
        } catch (Throwable t) {
            loaded = false;
            Logger.logWarn(LOG_TAG, "Native guard unavailable: " + t.getMessage());
        }
        LIB_LOADED = loaded;
    }

    private BootstrapBaremetalGuard() {}

    private static native int selftestNative(ByteBuffer out, int cap);
    private static native int validatePrefixNative(String prefix, ByteBuffer out, int cap);

    static void selftest() {
        if (!LIB_LOADED) {
            String msg = "selftest skipped: native lib not loaded";
            if (BuildConfig.BOOTSTRAP_BAREMETAL_STRICT) throw new RuntimeException(msg);
            Logger.logWarn(LOG_TAG, msg);
            return;
        }
        int rc;
        String json;
        synchronized (SHARED_BUFFER) {
            clearBuffer();
            try {
                rc = selftestNative(SHARED_BUFFER, BUFFER_CAPACITY);
            } catch (UnsatisfiedLinkError e) {
                String msg = "selftestNative missing JNI symbol: " + e.getMessage();
                if (BuildConfig.BOOTSTRAP_BAREMETAL_STRICT) throw new RuntimeException(msg, e);
                Logger.logWarn(LOG_TAG, msg);
                return;
            }
            json = readBufferString();
        }
        if (rc < 0) {
            String msg = "selftest failed rc=" + rc + " payload=" + json;
            if (BuildConfig.BOOTSTRAP_BAREMETAL_STRICT) throw new RuntimeException(msg);
            Logger.logWarn(LOG_TAG, msg);
        } else {
            Logger.logInfo(LOG_TAG, "selftest ok payload=" + json);
        }
        Logger.logInfo(LOG_TAG, "bootstrap-guard phase=selftest status=ok payload=" + json);
    }

    static void validateAfterBootstrap(String prefix) {
        if (!LIB_LOADED) {
            String msg = "Skipped guard validation: native lib not loaded";
            if (BuildConfig.BOOTSTRAP_BAREMETAL_STRICT) throw new RuntimeException(msg);
            Logger.logWarn(LOG_TAG, msg);
            return;
        }
        int rc;
        String json;
        synchronized (SHARED_BUFFER) {
            clearBuffer();
            try {
                rc = validatePrefixNative(prefix, SHARED_BUFFER, BUFFER_CAPACITY);
            } catch (UnsatisfiedLinkError e) {
                String msg = "validatePrefixNative missing JNI symbol: " + e.getMessage();
                if (BuildConfig.BOOTSTRAP_BAREMETAL_STRICT) throw new RuntimeException(msg, e);
                Logger.logWarn(LOG_TAG, msg);
                return;
            }
            json = readBufferString();
        }
        if (rc < 0) {
            handleStrictFailure("validatePrefix", "critical native return rc=" + rc + " payload=" + json, null);
            return;
        }
        Logger.logInfo(LOG_TAG, "bootstrap-guard phase=validatePrefix status=ok payload=" + json);
    }

    private static void handleStrictFailure(String phase, String cause, Throwable error) {
        String message = "bootstrap-guard phase=" + phase + " status=failed cause=" + cause;
        if (error != null && error.getMessage() != null && !error.getMessage().isEmpty()) {
            message += " detail=" + error.getMessage();
        }
        if (BuildConfig.BOOTSTRAP_BAREMETAL_STRICT) {
            throw new RuntimeException(message, error);
        }
        Logger.logWarn(LOG_TAG, message + " strict=false");
    }

    private static void clearBuffer() {
        SHARED_BUFFER.position(0);
        for (int i = 0; i < BUFFER_CAPACITY; i++) SHARED_BUFFER.put((byte) 0);
        SHARED_BUFFER.position(0);
    }

    private static String readBufferString() {
        byte[] data = new byte[BUFFER_CAPACITY];
        SHARED_BUFFER.position(0);
        SHARED_BUFFER.get(data);
        int len = 0;
        while (len < data.length && data[len] != 0) len++;
        return new String(data, 0, len, StandardCharsets.UTF_8);
    }
}
