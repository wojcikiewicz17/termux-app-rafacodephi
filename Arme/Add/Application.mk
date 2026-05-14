# Application.mk
# RAFAELIA NDK build config
# Coloca em: app/src/main/cpp/lowlevel/Application.mk

# ABI: Motorola E7 Power é ARM32
# Inclui ARM64 para outros dispositivos
APP_ABI := armeabi-v7a arm64-v8a

# minSdkVersion 24 = Android 7.0 (Nougat)
APP_PLATFORM := android-24

# STL: none — puro C, sem libstdc++
APP_STL := none

# Otimização máxima
APP_OPTIM := release

# C11 para designated initializers e _Alignof
APP_CFLAGS := -std=c11

# sem debug symbols no release
APP_DEBUG := false
