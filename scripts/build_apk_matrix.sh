#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist/apk-matrix"
UNSIGNED_DIR="${OUT_DIR}/unsigned"
SIGNED_DIR="${OUT_DIR}/signed"
DEFAULT_KEYSTORE_PATH="${ROOT_DIR}/dist/local-release.keystore"
KEYSTORE_PATH="${KEYSTORE_PATH:-${DEFAULT_KEYSTORE_PATH}}"
KEY_ALIAS="${KEY_ALIAS:-localrelease}"
KEY_PASS="${KEY_PASS:-changeit}"
STORE_PASS="${STORE_PASS:-changeit}"

info() { printf '\n[build_apk_matrix] %s\n' "$*"; }
fail() { printf '\n[build_apk_matrix] ERROR: %s\n' "$*" >&2; exit 1; }

cd "${ROOT_DIR}"

info "Provisioning Android SDK/NDK/CMake"
./scripts/setup_android_toolchain.sh

mkdir -p "${UNSIGNED_DIR}" "${SIGNED_DIR}" "$(dirname "${KEYSTORE_PATH}")"

info "Preparing bootstrap environment and BLAKE3 vars"
eval "$(./scripts/prepare_bootstrap_env.sh --print-env)"

for v in AARCH64 ARM I686 X86_64; do
  var="TERMUX_BOOTSTRAP_BLAKE3_${v}"
  val="${!var:-}"
  [[ "$val" =~ ^[0-9a-f]{64}$ ]] || fail "${var} missing/invalid before final build"
done

info "Running debug unit tests"
./gradlew :app:testDebugUnitTest --no-daemon

info "Building unsigned debug and release APKs"
TERMUX_SPLIT_APKS_FOR_DEBUG_BUILDS=1 TERMUX_SPLIT_APKS_FOR_RELEASE_BUILDS=1 ./gradlew :app:assembleDebug :app:assembleRelease --no-daemon

cp app/build/outputs/apk/debug/*.apk "${UNSIGNED_DIR}/"
cp app/build/outputs/apk/release/*.apk "${UNSIGNED_DIR}/"

arm64_count=$(find "${UNSIGNED_DIR}" -maxdepth 1 -type f -name '*arm64-v8a*.apk' | wc -l | tr -d ' ')
arm32_count=$(find "${UNSIGNED_DIR}" -maxdepth 1 -type f -name '*armeabi-v7a*.apk' | wc -l | tr -d ' ')
[[ "${arm64_count}" -gt 0 ]] || fail "arm64-v8a APK was not generated"
[[ "${arm32_count}" -gt 0 ]] || fail "armeabi-v7a APK was not generated"

if [[ "${KEYSTORE_PATH}" == "${DEFAULT_KEYSTORE_PATH}" ]]; then
  info "Preparing local validation signing material"
  if [[ ! -f "${KEYSTORE_PATH}" ]]; then
    keytool -genkeypair -v -storetype JKS -keystore "${KEYSTORE_PATH}" -alias "${KEY_ALIAS}" -keyalg RSA -keysize 2048 -validity 3650 -storepass "${STORE_PASS}" -keypass "${KEY_PASS}" -dname "CN=Local Build,O=Termux,C=US"
  fi
else
  info "Using provided signing keystore at ${KEYSTORE_PATH}"
fi

[[ -f "${KEYSTORE_PATH}" ]] || fail "keystore file not found at ${KEYSTORE_PATH}"

BUILD_TOOLS_VERSION="$(awk -F= '/^buildToolsVersion=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' gradle.properties || true)"
[[ -n "${BUILD_TOOLS_VERSION}" ]] || BUILD_TOOLS_VERSION="$(awk -F= '/^compileSdkVersion=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' gradle.properties).0.0"
SDK_DIR="$(grep -E '^sdk.dir=' local.properties | cut -d= -f2-)"; SDK_DIR="${SDK_DIR//\\/}"
APKSIGNER="${SDK_DIR}/build-tools/${BUILD_TOOLS_VERSION}/apksigner"
[[ -x "${APKSIGNER}" ]] || fail "apksigner not found at ${APKSIGNER}"

info "Signing release APK variants"
while IFS= read -r -d '' apk; do
  signed_apk="${SIGNED_DIR}/$(basename "${apk%.apk}")-signed.apk"
  "${APKSIGNER}" sign --ks "${KEYSTORE_PATH}" --ks-key-alias "${KEY_ALIAS}" --ks-pass "pass:${STORE_PASS}" --key-pass "pass:${KEY_PASS}" --out "${signed_apk}" "$apk"
  "${APKSIGNER}" verify --print-certs "${signed_apk}" >/dev/null
  echo "signed: ${signed_apk}"
done < <(find "${UNSIGNED_DIR}" -maxdepth 1 -type f -name '*release*.apk' -print0)

signed_arm64_count=$(find "${SIGNED_DIR}" -maxdepth 1 -type f -name '*arm64-v8a*-signed.apk' | wc -l | tr -d ' ')
signed_arm32_count=$(find "${SIGNED_DIR}" -maxdepth 1 -type f -name '*armeabi-v7a*-signed.apk' | wc -l | tr -d ' ')
[[ "${signed_arm64_count}" -gt 0 ]] || fail "signed arm64-v8a release APK missing"
[[ "${signed_arm32_count}" -gt 0 ]] || fail "signed arm32-v7a release APK missing"

( cd "${OUT_DIR}" && find unsigned signed -type f -name '*.apk' -print0 | xargs -0 sha256sum > SHA256SUMS.txt )

SIZE_REPORT="${OUT_DIR}/APK_SIZE_REPORT.tsv"
printf 'apk\ttype\tabi\tsize_bytes\n' > "${SIZE_REPORT}"
while IFS= read -r -d '' apk; do
  base="$(basename "$apk")"
  size="$(stat -c '%s' "$apk")"
  abi="universal"
  [[ "$base" == *"arm64-v8a"* ]] && abi="arm64-v8a"
  [[ "$base" == *"armeabi-v7a"* ]] && abi="armeabi-v7a"
  kind="unsigned"
  [[ "$apk" == *"/signed/"* ]] && kind="signed"
  printf '%s\t%s\t%s\t%s\n' "$base" "$kind" "$abi" "$size" >> "${SIZE_REPORT}"
done < <(find "${OUT_DIR}" -type f -name '*.apk' -print0)

DIFF_REPORT="${OUT_DIR}/APK_SIZE_DIFF_RELEASE.tsv"
printf 'abi\tunsigned_apk\tunsigned_size_bytes\tsigned_apk\tsigned_size_bytes\tdelta_bytes\n' > "${DIFF_REPORT}"
for abi in armeabi-v7a arm64-v8a universal; do
  uapk="$(find "${UNSIGNED_DIR}" -maxdepth 1 -type f -name "*release*${abi}*.apk" | head -n1 || true)"
  sapk="$(find "${SIGNED_DIR}" -maxdepth 1 -type f -name "*release*${abi}*-signed.apk" | head -n1 || true)"
  if [[ -n "$uapk" && -n "$sapk" ]]; then
    usize="$(stat -c '%s' "$uapk")"
    ssize="$(stat -c '%s' "$sapk")"
    delta=$((ssize-usize))
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$abi" "$(basename "$uapk")" "$usize" "$(basename "$sapk")" "$ssize" "$delta" >> "${DIFF_REPORT}"
  fi
done

( cd "${OUT_DIR}" && {
  echo "artifact_dir=${OUT_DIR}";
  echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)";
  echo "signing_keystore=$(basename "${KEYSTORE_PATH}")";
  echo "signed_release_apks=${signed_arm64_count}+${signed_arm32_count} (arm64+arm32 validated)";
  find unsigned signed -type f -name '*.apk' | sort;
} > ARTIFACT_MANIFEST.txt )
info "Artifacts generated in ${OUT_DIR}"
cat "${OUT_DIR}/ARTIFACT_MANIFEST.txt"
cat "${OUT_DIR}/APK_SIZE_REPORT.tsv"
cat "${OUT_DIR}/APK_SIZE_DIFF_RELEASE.tsv"
cat "${OUT_DIR}/SHA256SUMS.txt"
