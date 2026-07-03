#!/usr/bin/env bash
# tests/unit/init-script.bash — unit tests for tsurf-init key generation modes.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORKDIR="${TSURF_TEST_TMPDIR:-$PWD}/init-script"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

fail() {
  echo "FAIL: $*"
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$label"
}

set +e
NONINTERACTIVE_OUTPUT="$(
  bash "$ROOT_DIR/scripts/tsurf-init.sh" --key-path "$WORKDIR/noninteractive-root" 2>&1 < /dev/null
)"
NONINTERACTIVE_STATUS=$?
set -e

[[ "$NONINTERACTIVE_STATUS" -ne 0 ]] || fail "tsurf-init should refuse noninteractive key generation without passphrase mode"
assert_contains "$NONINTERACTIVE_OUTPUT" "Refusing to generate an unencrypted root SSH key noninteractively" \
  "noninteractive refusal should explain the unsafe default"
[[ ! -f "$WORKDIR/noninteractive-root" ]] || fail "noninteractive refusal should not leave a private key"

bash "$ROOT_DIR/scripts/tsurf-init.sh" --key-path "$WORKDIR/plain-root" --no-passphrase >/dev/null
[[ -f "$WORKDIR/plain-root" ]] || fail "--no-passphrase should generate a private key"
[[ -f "$WORKDIR/plain-root.pub" ]] || fail "--no-passphrase should generate a public key"
ssh-keygen -y -P "" -f "$WORKDIR/plain-root" >/dev/null \
  || fail "--no-passphrase key should be readable with an empty passphrase"

printf '%s\n' "test-passphrase" > "$WORKDIR/passphrase.txt"
bash "$ROOT_DIR/scripts/tsurf-init.sh" \
  --key-path "$WORKDIR/passphrase-root" \
  --passphrase-file "$WORKDIR/passphrase.txt" >/dev/null
ssh-keygen -y -P "test-passphrase" -f "$WORKDIR/passphrase-root" >/dev/null \
  || fail "--passphrase-file key should require the supplied passphrase"

touch "$WORKDIR/empty-passphrase.txt"
set +e
EMPTY_OUTPUT="$(
  bash "$ROOT_DIR/scripts/tsurf-init.sh" \
    --key-path "$WORKDIR/empty-passphrase-root" \
    --passphrase-file "$WORKDIR/empty-passphrase.txt" 2>&1
)"
EMPTY_STATUS=$?
set -e

[[ "$EMPTY_STATUS" -ne 0 ]] || fail "empty passphrase files should fail"
assert_contains "$EMPTY_OUTPUT" "Passphrase file is empty" \
  "empty passphrase file error should be explicit"

set +e
CONFLICT_OUTPUT="$(
  bash "$ROOT_DIR/scripts/tsurf-init.sh" \
    --key-path "$WORKDIR/conflict-root" \
    --passphrase-file "$WORKDIR/passphrase.txt" \
    --no-passphrase 2>&1
)"
CONFLICT_STATUS=$?
set -e

[[ "$CONFLICT_STATUS" -ne 0 ]] || fail "conflicting passphrase modes should fail"
assert_contains "$CONFLICT_OUTPUT" "Choose either --passphrase-file or --no-passphrase" \
  "conflicting mode error should be explicit"

echo "PASS: init-script unit tests"
