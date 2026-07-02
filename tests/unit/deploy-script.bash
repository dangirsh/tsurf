#!/usr/bin/env bash
# tests/unit/deploy-script.bash — unit tests for deploy.sh helper behavior.
# shellcheck disable=SC1091

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TSURF_DEPLOY_LIB_ONLY=1
export TSURF_DEPLOY_LIB_ONLY
source "$ROOT_DIR/scripts/deploy.sh"

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
  "$(resolve_flake_dir "$ROOT_DIR/scripts/deploy.sh")" \
  "$ROOT_DIR" \
  "resolve_flake_dir finds repo root from scripts path"

WORKDIR="${TSURF_TEST_TMPDIR:-$PWD}/deploy-script"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd -P)"
mkdir -p "$WORKDIR/scripts"
cp "$ROOT_DIR/scripts/deploy.sh" "$WORKDIR/scripts/deploy.sh"
touch "$WORKDIR/flake.nix"

assert_eq \
  "$(resolve_flake_dir "$WORKDIR/scripts/deploy.sh")" \
  "$WORKDIR" \
  "resolve_flake_dir finds overlay root from copied scripts path"

assert_eq \
  "$(parse_ssh_target root@example.com)" \
  $'root\texample.com' \
  "parse_ssh_target parses explicit user"

assert_eq \
  "$(parse_ssh_target example.com)" \
  $'root\texample.com' \
  "parse_ssh_target defaults to root user"

assert_eq \
  "$(shell_join -o 'ProxyCommand=ssh jump host -W %h:%p' -o ConnectTimeout=10)" \
  "-o ProxyCommand=ssh\\ jump\\ host\\ -W\\ %h:%p -o ConnectTimeout=10" \
  "shell_join preserves SSH option boundaries"

ssh_opts_file="$WORKDIR/ssh-opts"
cat > "$ssh_opts_file" <<'EOF'
-o
ProxyCommand=ssh jump host -W %h:%p
-o
ConnectTimeout=10
EOF
TSURF_DEPLOY_SSH_OPTS_FILE="$ssh_opts_file"
TSURF_DEPLOY_SSH_OPTS="-o ignored"
export TSURF_DEPLOY_SSH_OPTS_FILE TSURF_DEPLOY_SSH_OPTS
load_ssh_extra_opts
assert_eq "${#SSH_EXTRA_OPTS[@]}" "4" "SSH opts file loads one option per line"
assert_eq "${SSH_EXTRA_OPTS[1]}" "ProxyCommand=ssh jump host -W %h:%p" "SSH opts file preserves spaces"
unset TSURF_DEPLOY_SSH_OPTS_FILE TSURF_DEPLOY_SSH_OPTS

if bash "$ROOT_DIR/scripts/deploy.sh" --help | grep -q "Override deploy and SSH target"; then
  :
else
  echo "FAIL: deploy.sh help does not describe --target as a deploy target override"
  exit 1
fi

if bash "$ROOT_DIR/scripts/deploy.sh" --help | grep -q "Explicit unsafe/fast path: pass deploy-rs --skip-checks"; then
  :
else
  echo "FAIL: deploy.sh help does not describe explicit --skip-checks behavior"
  exit 1
fi

echo "PASS: deploy-script unit tests"
