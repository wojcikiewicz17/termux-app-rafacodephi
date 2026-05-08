#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MIN_FREE_MB="${MIN_FREE_MB:-1024}"
BOOTSTRAP_DIR="app/src/main/cpp"
BOOTSTRAPS=(bootstrap-aarch64.zip bootstrap-arm.zip bootstrap-i686.zip bootstrap-x86_64.zip)

log(){ printf '[bootstrap-contract] %s\n' "$*"; }
fail(){ printf '[bootstrap-contract] ERROR: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }

check_free_space(){
  local free_mb
  free_mb="$(df -Pm "$ROOT_DIR" | awk 'NR==2{print $4}')"
  [[ "$free_mb" =~ ^[0-9]+$ ]] || fail "Unable to parse free disk space: $free_mb"
  (( free_mb >= MIN_FREE_MB )) || fail "Free space ${free_mb}MB below required MIN_FREE_MB=${MIN_FREE_MB}MB"
  log "Free space check OK: ${free_mb}MB >= ${MIN_FREE_MB}MB"
}

check_zip_valid_lowlevel(){
  local f="$1"
  [[ -f "$f" ]] || fail "Missing bootstrap archive: $f"
  [[ -s "$f" ]] || fail "Bootstrap archive is empty: $f"
  /tmp/bootstrap_zip_contract_check "$f" >/dev/null 2>&1 || fail "Invalid ZIP structure in $f"
}

emit_hashes_lowlevel(){
  need sha256sum
  local has_b3=0
  command -v b3sum >/dev/null 2>&1 && has_b3=1
  local z p sha b3
  for z in "${BOOTSTRAPS[@]}"; do
    p="$BOOTSTRAP_DIR/$z"
    sha="$(sha256sum "$p" | awk '{print $1}')"
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid SHA256 for $p"
    printf 'SHA256 %s %s\n' "$z" "$sha"
    if (( has_b3 == 1 )); then
      b3="$(b3sum "$p" | awk '{print $1}')"
      [[ "$b3" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid BLAKE3 for $p"
      printf 'BLAKE3 %s %s\n' "$z" "$b3"
    fi
  done
  (( has_b3 == 1 )) || log "b3sum unavailable; BLAKE3 skipped (SHA256 emitted)."
}


check_bootstrap_metadata(){
  python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile

base = Path('app/src/main/cpp')
expected_package = 'com.termux.rafacodephi'
expected_page = '16384'
archives = {
    'bootstrap-aarch64.zip': ('aarch64', '21'),
    'bootstrap-arm.zip': ('arm', '28'),
    'bootstrap-i686.zip': ('i686', '21'),
    'bootstrap-x86_64.zip': ('x86_64', '21'),
}
for name, (arch, min_api) in archives.items():
    path = base / name
    with ZipFile(path) as zf:
        info = zf.read('BOOTSTRAP_INFO').decode('utf-8')
        names = set(zf.namelist())
    metadata = {}
    for line in info.splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            metadata[key.strip()] = value.strip()
    required_entries = {'BOOTSTRAP_INFO', 'SYMLINKS.txt', 'bin/sh', 'bin/pkg', 'bin/busybox', 'bin/proot'}
    missing = sorted(required_entries - names)
    if missing:
        raise SystemExit(f'{path}: missing entries: {missing}')
    expected = {
        'TERMUX_PACKAGE_NAME': expected_package,
        'TERMUX_ARCH': arch,
        'TERMUX_PAGE_SIZE': expected_page,
        'TERMUX_MIN_API': min_api,
        'RAFCODEPHI_BOOTSTRAP': 'local-ci',
    }
    for key, value in expected.items():
        actual = metadata.get(key)
        if actual != value:
            raise SystemExit(f'{path}: {key} expected {value!r}, got {actual!r}')
print('metadata OK for RAFCODEPHI local bootstraps')
PY
}

check_runtime_prefix(){
  local p="${PREFIX:-${TERMUX_PREFIX:-}}"
  [[ -n "$p" ]] || { log "PREFIX/TERMUX_PREFIX not set; runtime check skipped (build mode)."; return 0; }
  [[ -d "$p" ]] || fail "PREFIX directory not found: $p"
  [[ -x "$p/bin/sh" ]] || fail "Missing runtime shell: $p/bin/sh"
  [[ -x "$p/bin/pkg" ]] || fail "Missing runtime pkg: $p/bin/pkg"
  log "Runtime PREFIX contract OK: $p"
}

check_bootstraps(){
  need cc
  cc -O2 -std=c11 -Wall -Wextra -Werror scripts/bootstrap_zip_contract_check.c -o /tmp/bootstrap_zip_contract_check
  check_free_space
  local z
  for z in "${BOOTSTRAPS[@]}"; do
    check_zip_valid_lowlevel "$BOOTSTRAP_DIR/$z"
    log "Zip validation OK: $BOOTSTRAP_DIR/$z"
  done
  check_bootstrap_metadata
  log "BOOTSTRAP_INFO metadata OK"
  emit_hashes_lowlevel
}

case "${1:-}" in
  --prepare)
    check_free_space
    ./gradlew :app:downloadBootstraps --no-daemon
    check_bootstraps
    check_runtime_prefix
    ;;
  --prepare-dev)
    check_free_space
    bash scripts/generate_developer_bootstraps.sh
    check_bootstraps
    check_runtime_prefix
    ;;
  --check)
    check_bootstraps
    check_runtime_prefix
    ;;
  --runtime-prefix-only)
    check_runtime_prefix
    ;;
  *)
    echo "Usage: bash scripts/verify_bootstrap_contract.sh [--prepare|--prepare-dev|--check|--runtime-prefix-only]" >&2
    exit 1
    ;;
esac
