#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Android preflight"
./scripts/ci_android_preflight.sh

echo "[2/4] Bootstrap hash env"
eval "$(./scripts/prepare_bootstrap_env.sh --print-env)"

echo "[3/4] Build unsigned debug+release"
./gradlew :app:assembleDebug :app:assembleRelease --no-daemon

echo "[4/4] Build signed+unsigned matrix (local validation signing when official secrets are absent)"
./scripts/build_apk_matrix.sh

echo "✅ done"
echo "Unsigned APKs: dist/apk-matrix/unsigned"
echo "Signed APKs: dist/apk-matrix/signed"
