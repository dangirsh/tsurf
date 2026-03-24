#!/usr/bin/env bash
# tests/unit/deploy-script.bash — unit tests for deploy.sh helper behavior.
# shellcheck disable=SC1091

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TSURF_DEPLOY_LIB_ONLY=1
export TSURF_DEPLOY_LIB_ONLY
source "$ROOT_DIR/examples/scripts/deploy.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
}

assert_eq \
  "$(resolve_flake_dir "$ROOT_DIR/examples/scripts/deploy.sh")" \
  "$ROOT_DIR" \
  "resolve_flake_dir finds repo root from examples/scripts path"

WORKDIR="${TSURF_TEST_TMPDIR:-$PWD}/deploy-script"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/scripts"
cp "$ROOT_DIR/examples/scripts/deploy.sh" "$WORKDIR/scripts/deploy.sh"
touch "$WORKDIR/flake.nix"

assert_eq \
  "$(resolve_flake_dir "$WORKDIR/scripts/deploy.sh")" \
  "$WORKDIR" \
  "resolve_flake_dir finds overlay root from copied scripts path"

echo "PASS: deploy-script unit tests"
