#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="matrix"
if [[ "${1:-}" == "--full" ]]; then
  MODE="full"
elif [[ "${1:-}" == "--assemble-only" ]]; then
  MODE="assemble"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--full|--assemble-only]" >&2
  echo "  (default)        run matrix pipeline (includes preflight + hashes + debug/release + signing)" >&2
  echo "  --full           run explicit preflight+hashes+assemble and then matrix pipeline" >&2
  echo "  --assemble-only  run explicit preflight+hashes+assemble only" >&2
  exit 2
fi

run_preflight_and_hashes() {
  echo "[preflight] Android SDK/NDK bootstrap"
  ./scripts/ci_android_preflight.sh

  echo "[preflight] Export bootstrap hash env"
  eval "$(./scripts/prepare_bootstrap_env.sh --print-env)"
}

run_assemble() {
  echo "[build] assembleDebug + assembleRelease"
  ./gradlew :app:assembleDebug :app:assembleRelease --no-daemon
}

run_matrix() {
  echo "[build] signed+unsigned APK matrix"
  ./scripts/build_apk_matrix.sh
}

case "$MODE" in
  full)
    run_preflight_and_hashes
    run_assemble
    run_matrix
    ;;
  assemble)
    run_preflight_and_hashes
    run_assemble
    ;;
  matrix)
    run_matrix
    ;;
esac

echo "✅ done"
echo "Unsigned APKs: dist/apk-matrix/unsigned"
echo "Signed APKs: dist/apk-matrix/signed"
