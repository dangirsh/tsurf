#!/usr/bin/env bash
# tests/unit/status-script.bash — unit tests for tsurf-status.sh unit selection.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORKDIR="${TSURF_TEST_TMPDIR:-$PWD}/status-script"
FAKE_BIN="$WORKDIR/bin"
SSH_LOG="$WORKDIR/ssh.log"
mkdir -p "$FAKE_BIN"
rm -f "$SSH_LOG"

cat > "$FAKE_BIN/ssh" <<EOF
#!${BASH}
set -euo pipefail
printf '%s\n' "\$*" >> "${SSH_LOG}"
case "\$*" in
  *"root@testhost true") exit 0 ;;
  *"systemctl is-enabled"*) printf 'enabled\n' ;;
  *"systemctl is-active"*) printf 'active\n' ;;
  *) exit 1 ;;
esac
EOF
chmod 700 "$FAKE_BIN/ssh"

PATH="$FAKE_BIN:$PATH" \
  bash "$ROOT_DIR/scripts/tsurf-status.sh" testhost >/dev/null

SSH_TRACE="$(cat "$SSH_LOG")"

[[ "$SSH_TRACE" == *"systemctl is-enabled 'tsurf-cost-tracker.timer'"* ]] || {
  echo "FAIL: expected tsurf-status.sh to query tsurf-cost-tracker.timer"
  exit 1
}
[[ "$SSH_TRACE" == *"systemctl is-enabled 'restic-backups-b2.timer'"* ]] || {
  echo "FAIL: expected tsurf-status.sh to query restic-backups-b2.timer"
  exit 1
}
[[ "$SSH_TRACE" != *"agent-launch-claude.service"* ]] || {
  echo "FAIL: tsurf-status.sh still queries ephemeral agent-launch-claude"
  exit 1
}
[[ "$SSH_TRACE" != *"cost-tracker.service"* ]] || {
  echo "FAIL: tsurf-status.sh still queries the wrong cost-tracker unit name"
  exit 1
}

echo "PASS: status-script unit tests"
