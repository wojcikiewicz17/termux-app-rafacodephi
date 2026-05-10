#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

info() { printf '\n[smoke_release_gate] %s\n' "$*"; }
fail() { printf '\n[smoke_release_gate] ERROR: %s\n' "$*" >&2; exit 1; }

info "Preflight: strict release flag wiring"
rg -n 'BOOTSTRAP_BAREMETAL_STRICT' app/build.gradle >/dev/null || fail "BOOTSTRAP_BAREMETAL_STRICT missing in app/build.gradle"
rg -n 'TERMUX_BOOTSTRAP_BAREMETAL_STRICT' app/build.gradle >/dev/null || fail "TERMUX_BOOTSTRAP_BAREMETAL_STRICT env wiring missing in app/build.gradle"

info "Preflight: guard must enforce strict failures on native load/JNI symbol issues"
rg -n 'if \(BuildConfig\.BOOTSTRAP_BAREMETAL_STRICT\)' app/src/main/java/com/termux/app/BootstrapBaremetalGuard.java >/dev/null || fail "Strict guard condition missing"
rg -n 'native lib not loaded|missing JNI symbol' app/src/main/java/com/termux/app/BootstrapBaremetalGuard.java >/dev/null || fail "Expected strict failure surfaces not found"

info "Build + sign + matrix artifact validation"
TERMUX_BOOTSTRAP_BAREMETAL_STRICT=true ./scripts/build_apk_matrix.sh

info "Post-check: signed/unsigned release ARM32+ARM64 artifacts"
for abi in arm64-v8a armeabi-v7a; do
  find dist/apk-matrix/unsigned -maxdepth 1 -type f -name "*release*${abi}*.apk" | grep -q . || fail "unsigned release missing for ${abi}"
  find dist/apk-matrix/signed -maxdepth 1 -type f -name "*release*${abi}*-signed.apk" | grep -q . || fail "signed release missing for ${abi}"
done

info "Gate passed"
