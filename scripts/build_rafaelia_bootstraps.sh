#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${TERMUX_BOOTSTRAP_PACKAGE_NAME:=com.termux.rafacodephi}"
: "${TERMUX_BOOTSTRAP_PAGE_SIZE:=16384}"

builder="${TMPDIR:-/tmp}/bootstrap_zip_builder.$$"
trap 'rm -f "$builder"' EXIT

cc -O2 -std=c11 -Wall -Wextra -Werror scripts/bootstrap_zip_builder.c -o "$builder"
mkdir -p app/src/main/cpp
TERMUX_BOOTSTRAP_PACKAGE_NAME="$TERMUX_BOOTSTRAP_PACKAGE_NAME" TERMUX_BOOTSTRAP_PAGE_SIZE="$TERMUX_BOOTSTRAP_PAGE_SIZE" "$builder" app/src/main/cpp/bootstrap-aarch64.zip aarch64
TERMUX_BOOTSTRAP_PACKAGE_NAME="$TERMUX_BOOTSTRAP_PACKAGE_NAME" TERMUX_BOOTSTRAP_PAGE_SIZE="$TERMUX_BOOTSTRAP_PAGE_SIZE" "$builder" app/src/main/cpp/bootstrap-arm.zip arm
TERMUX_BOOTSTRAP_PACKAGE_NAME="$TERMUX_BOOTSTRAP_PACKAGE_NAME" TERMUX_BOOTSTRAP_PAGE_SIZE="$TERMUX_BOOTSTRAP_PAGE_SIZE" "$builder" app/src/main/cpp/bootstrap-i686.zip i686
TERMUX_BOOTSTRAP_PACKAGE_NAME="$TERMUX_BOOTSTRAP_PACKAGE_NAME" TERMUX_BOOTSTRAP_PAGE_SIZE="$TERMUX_BOOTSTRAP_PAGE_SIZE" "$builder" app/src/main/cpp/bootstrap-x86_64.zip x86_64

echo "RAFCODEPHI bootstraps generated for package=${TERMUX_BOOTSTRAP_PACKAGE_NAME} page_size=${TERMUX_BOOTSTRAP_PAGE_SIZE}"
