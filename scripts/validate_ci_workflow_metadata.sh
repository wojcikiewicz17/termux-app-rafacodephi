#!/usr/bin/env bash
set -euo pipefail

root=".github/workflows"
status=0

for wf in "$root"/*.yml; do
  track=$(sed -n 's/^# ci_track:[[:space:]]*//p' "$wf" | head -n1 | tr -d '\r')
  abis=$(sed -n 's/^# ci_abis:[[:space:]]*//p' "$wf" | head -n1 | tr -d '\r')

  if [[ -z "$track" ]]; then
    echo "[ERROR] missing # ci_track in $wf"
    status=1
    continue
  fi
  if [[ -z "$abis" ]]; then
    echo "[ERROR] missing # ci_abis in $wf"
    status=1
    continue
  fi

  case "$track" in
    debug|internal|official|ops|deprecated) ;;
    *)
      echo "[ERROR] invalid ci_track '$track' in $wf"
      status=1
      ;;
  esac

done

if [[ $status -ne 0 ]]; then
  exit $status
fi

echo "[OK] workflow metadata contract validated"
