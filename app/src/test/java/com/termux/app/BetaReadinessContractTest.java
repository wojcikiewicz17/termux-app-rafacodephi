package com.termux.app;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;

import static org.junit.Assert.assertTrue;

/**
 * Source-level beta gate for the terminal lifecycle path that cannot be executed in a
 * host JVM because the actual session path depends on Android pty JNI.
 */
public class BetaReadinessContractTest {

    @Test
    public void terminalSessionHasDefensiveStartupAndIdempotentCleanup() throws Exception {
        String source = read("terminal-emulator/src/main/java/com/termux/terminal/TerminalSession.java");

        assertTrue(source.contains("Failed to create terminal subprocess"));
        assertTrue(source.contains("mTerminalFileDescriptor = -1"));
        assertTrue(source.contains("mResourcesCleaned"));
        assertTrue(source.contains("if (mResourcesCleaned) return"));
        assertTrue(source.contains("if (terminalFileDescriptor >= 0)"));
    }

    @Test
    public void terminalCloseKillsProcessGroupBeforeShellFallback() throws Exception {
        String source = read("terminal-emulator/src/main/java/com/termux/terminal/TerminalSession.java");
        int groupKill = source.indexOf("Os.kill(-shellPid, OsConstants.SIGKILL)");
        int shellKill = source.indexOf("Os.kill(shellPid, OsConstants.SIGKILL)");

        assertTrue("terminal close must try the process group", groupKill >= 0);
        assertTrue("terminal close must keep shell-pid fallback", shellKill > groupKill);
    }

    @Test
    public void nativeWaitForHandlesInterruptedWaitpid() throws Exception {
        String source = read("terminal-emulator/src/main/jni/termux.c");

        assertTrue(source.contains("#include <errno.h>"));
        assertTrue(source.contains("errno == EINTR"));
        assertTrue(source.contains("return -1"));
    }

    @Test
    public void terminalStartupDoesNotHardGateOnBash() throws Exception {
        String source = read("termux-shared/src/main/java/com/termux/shared/termux/shell/command/runner/terminal/TermuxSession.java");

        assertTrue(source.contains("Do not hard-gate terminal startup on bash"));
        assertTrue(source.contains("LOGIN_SHELL_BINARIES"));
        assertTrue(source.contains("/system/bin/sh"));
        assertTrue("terminal boot must not fail before shell fallback just because bash is absent",
            !source.contains("Collections.singletonList(\"bash\")"));
    }

    private static String read(String path) throws Exception {
        java.nio.file.Path candidate = Paths.get(path);
        if (!Files.exists(candidate)) {
            candidate = Paths.get("..").resolve(path);
        }
        return new String(Files.readAllBytes(candidate), StandardCharsets.UTF_8);
    }
}
