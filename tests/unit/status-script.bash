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
#!/usr/bin/env bash
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

OUTPUT="$(
  PATH="$FAKE_BIN:$PATH" \
    bash "$ROOT_DIR/scripts/tsurf-status.sh" testhost
)"

[[ "$OUTPUT" == *"tsurf-cost-tracker.timer"* ]] || {
  echo "FAIL: expected tsurf-status.sh to check tsurf-cost-tracker.timer"
  exit 1
}
[[ "$OUTPUT" == *"restic-backups-b2.timer"* ]] || {
  echo "FAIL: expected tsurf-status.sh to check restic-backups-b2.timer"
  exit 1
}
[[ "$OUTPUT" != *"agent-launch-claude"* ]] || {
  echo "FAIL: tsurf-status.sh still reports ephemeral agent-launch-claude"
  exit 1
}
[[ "$OUTPUT" != *" cost-tracker "* ]] || {
  echo "FAIL: tsurf-status.sh still reports the wrong cost-tracker unit name"
  exit 1
}

echo "PASS: status-script unit tests"
