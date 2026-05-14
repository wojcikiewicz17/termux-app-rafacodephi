LOCAL_PATH:= $(call my-dir)

# Bootstrap library
include $(CLEAR_VARS)
LOCAL_MODULE := libtermux-bootstrap
LOCAL_SRC_FILES := termux-bootstrap-zip.S termux-bootstrap.c
# Critical: 16KB page alignment for Android 15/16 compatibility
LOCAL_LDFLAGS := -Wl,-z,max-page-size=16384
include $(BUILD_SHARED_LIBRARY)

# Bare-metal low-level library
include $(CLEAR_VARS)
LOCAL_MODULE := termux-baremetal
LOCAL_SRC_FILES := lowlevel/baremetal.c lowlevel/baremetal_jni.c lowlevel/rafaelia_gpu_orchestrator.c lowlevel/rafaelia_commit_gate_ll.c
# Assembly optimizations enabled when the target ABI guarantees SIMD support
ifeq ($(TARGET_ARCH_ABI),arm64-v8a)
    LOCAL_SRC_FILES += lowlevel/baremetal_asm.S
    LOCAL_CFLAGS += -DHAS_BM_NEON_ASM=1
endif
ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)
    LOCAL_SRC_FILES += lowlevel/baremetal_asm.S
    LOCAL_CFLAGS += -DHAS_BM_NEON_ASM=1
endif
LOCAL_CFLAGS += -std=c11 -Wall -Wextra -Werror -Os -fno-stack-protector
LOCAL_CFLAGS += -ffast-math
LOCAL_CFLAGS += -ffunction-sections -fdata-sections
# Critical: 16KB page alignment for Android 15/16 compatibility
LOCAL_LDFLAGS := -Wl,--gc-sections -Wl,-z,max-page-size=16384

# Architecture-specific optimizations
ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)
    # Keep ARM32 baseline-compatible and rely on runtime capability checks.
    LOCAL_CFLAGS += -march=armv7-a -mfloat-abi=softfp -mfpu=neon -ftree-vectorize
endif

ifeq ($(TARGET_ARCH_ABI),arm64-v8a)
    LOCAL_CFLAGS += -march=armv8-a -ftree-vectorize
endif

ifeq ($(TARGET_ARCH_ABI),x86)
    LOCAL_CFLAGS += -msse2 -msse4.2 -ftree-vectorize
endif

ifeq ($(TARGET_ARCH_ABI),x86_64)
    LOCAL_CFLAGS += -msse2 -msse4.2 -mavx -ftree-vectorize
endif

# Link against log and math libraries
LOCAL_LDLIBS := -llog -lm -ldl
include $(BUILD_SHARED_LIBRARY)
