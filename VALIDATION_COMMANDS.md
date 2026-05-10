# 🔍 Validation Commands Reference

Quick reference for validating Android 15 compatibility.

## Run All Validations

```bash
./gradlew :app:validateAndroid15Compatibility
```

Expected output:
```
✅ Package name validation passed!
✅ Storage flags validation passed!
✅ Authorities validation passed!
✅ All Android 15 compatibility validations passed!
```

---

## Individual Validations

### Check Package Names
Validates no hardcoded "com.termux" strings exist.

```bash
./gradlew :app:validatePackageNames
```

### Check Storage Flags
Validates no `requestLegacyExternalStorage` with targetSdk >= 30.

```bash
./gradlew :app:validateStorageFlags
```

### Check Authorities
Validates all authorities use `${TERMUX_PACKAGE_NAME}` placeholder.

```bash
./gradlew :app:validateAuthorities
```

---

## Build Commands

### Debug Build
```bash
./gradlew :app:assembleDebug
```

Output: `app/build/outputs/apk/debug/termux-app_*.apk`

### Release Build
```bash
./gradlew :app:assembleRelease
```

Output: `app/build/outputs/apk/release/termux-app_*.apk`

---

## Testing Commands

### Install APK
```bash
adb install app/build/outputs/apk/debug/termux-app_*.apk
```

### Verify Side-by-Side Installation
```bash
adb shell pm list packages | grep termux
```

Expected output:
```
package:com.termux
package:com.termux.rafacodephi
```

### Check Service Type
```bash
adb shell dumpsys activity services com.termux.rafacodephi | grep foregroundServiceType
```

Expected: `foregroundServiceType=dataSync`

### Check Permissions
```bash
adb shell dumpsys package com.termux.rafacodephi | grep -A 20 "declared permissions"
```

Should show unique permissions with `com.termux.rafacodephi` prefix.

---

## Clean Build

```bash
./gradlew clean
./gradlew :app:validateAndroid15Compatibility
./gradlew :app:assembleDebug
```

---

## CI/CD Integration

Add to your CI pipeline:

```yaml
- name: Validate Android 15 Compatibility
  run: ./gradlew :app:validateAndroid15Compatibility

- name: Build Debug APK
  run: ./gradlew :app:assembleDebug
```

---

## Validate Gradle Wrapper (CI)

Use the existing `Validate Gradle Wrapper` workflow to ensure the wrapper JAR and properties are untampered.

Steps:
1. Open GitHub Actions ➜ **Validate Gradle Wrapper**.
2. Click **Run workflow** and choose the branch to check.
3. The workflow executes:
   - Checkout repository
   - `gradle/actions/wrapper-validation@v5` to verify the wrapper artifacts

## APK matrix (assinado + não assinado)

```bash
./scripts/build_apk_matrix.sh
```

No GitHub Actions, execute o workflow manual `APK Matrix Build (signed + unsigned)` para gerar e publicar artefatos em `dist/apk-matrix/`.

Para trilha oficial assinada no workflow, habilite `use_official_signing=true` e configure os secrets:

- `OFFICIAL_RELEASE_KEYSTORE_B64`
- `OFFICIAL_RELEASE_KEY_ALIAS`
- `OFFICIAL_RELEASE_STORE_PASSWORD`
- `OFFICIAL_RELEASE_KEY_PASSWORD`

Sem esses secrets, o workflow mantém a trilha de validação interna com keystore local gerada em `dist/local-release.keystore`.
