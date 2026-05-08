#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="--print-env"
if [[ ${1:-} == "--github-env" || ${1:-} == "--print-env" ]]; then
  MODE="$1"
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--print-env|--github-env]" >&2
  exit 1
fi

./scripts/ci_android_preflight.sh >&2

BOOTSTRAP_SOURCE="${RAF_BOOTSTRAP_SOURCE:-local}"
case "$BOOTSTRAP_SOURCE" in
  local)
    ./scripts/build_rafaelia_bootstraps.sh >&2
    ;;
  upstream)
    ./gradlew :app:downloadBootstraps --no-daemon >&2
    ;;
  *)
    echo "Unsupported RAF_BOOTSTRAP_SOURCE=$BOOTSTRAP_SOURCE (allowed: local, upstream)" >&2
    exit 2
    ;;
esac

./scripts/verify_bootstrap_contract.sh --check >&2

if ! python3 -c 'import blake3' >/dev/null 2>&1; then
  python3 -m pip install --user blake3 >&2
fi

readarray -t HASH_LINES < <(python3 - <<'PY'
from pathlib import Path
from blake3 import blake3
import hashlib
import re

base = Path('app/src/main/cpp')
mapping = {
    'TERMUX_BOOTSTRAP_SHA256_AARCH64': 'bootstrap-aarch64.zip',
    'TERMUX_BOOTSTRAP_SHA256_ARM': 'bootstrap-arm.zip',
    'TERMUX_BOOTSTRAP_SHA256_I686': 'bootstrap-i686.zip',
    'TERMUX_BOOTSTRAP_SHA256_X86_64': 'bootstrap-x86_64.zip',
    'TERMUX_BOOTSTRAP_BLAKE3_AARCH64': 'bootstrap-aarch64.zip',
    'TERMUX_BOOTSTRAP_BLAKE3_ARM': 'bootstrap-arm.zip',
    'TERMUX_BOOTSTRAP_BLAKE3_I686': 'bootstrap-i686.zip',
    'TERMUX_BOOTSTRAP_BLAKE3_X86_64': 'bootstrap-x86_64.zip',
}
for env_key, file_name in mapping.items():
    path = base / file_name
    if not path.is_file():
        raise SystemExit(f"Missing bootstrap archive: {path}")
    data = path.read_bytes()
    if env_key.startswith('TERMUX_BOOTSTRAP_BLAKE3_'):
        digest = blake3(data).hexdigest()
        algo = 'BLAKE3'
    else:
        digest = hashlib.sha256(data).hexdigest()
        algo = 'SHA256'
    if not re.fullmatch(r'[0-9a-f]{64}', digest):
        raise SystemExit(f"Invalid {algo} for {path}: {digest}")
    print(f"{env_key}={digest}")
PY
)

if [[ ${#HASH_LINES[@]} -ne 8 ]]; then
  echo "Expected 8 bootstrap hash lines (BLAKE3+SHA256), got ${#HASH_LINES[@]}" >&2
  exit 1
fi

if [[ "$MODE" == "--github-env" ]]; then
  : "${GITHUB_ENV:?GITHUB_ENV must be set for --github-env mode}"
  for line in "${HASH_LINES[@]}"; do
    echo "$line" >> "$GITHUB_ENV"
  done
else
  for line in "${HASH_LINES[@]}"; do
    echo "export $line"
  done
fi


if [[ "$MODE" == "--print-env" ]]; then
  echo "# bootstrap-hashes: BLAKE3 + SHA256 generated for aarch64/arm/i686/x86_64" >&2
fi
