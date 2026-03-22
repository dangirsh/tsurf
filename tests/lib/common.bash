#!/usr/bin/env bash
# tests/lib/common.bash — Shared helpers for tsurf BATS live tests
# @decision TEST-48-01: Shared SSH + assertion helpers keep BATS cases single-assertion and readable.
#
# Usage: load '../lib/common' at the top of each .bats file
# Requires: TSURF_TEST_HOST env var (default: tsurf)

# --- Configuration ---
SSH_OPTS=(
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o LogLevel=ERROR
  -F /dev/null
)
HOST="${TSURF_TEST_HOST:-tsurf}"
SSH_USER="${TSURF_TEST_USER:-root}"
AGENT_USER="${TSURF_TEST_AGENT_USER:-agent}"

# --- SSH helpers ---
ssh_cmd() {
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" "$@"
}

# Run a command on the remote host, capturing output.
remote() {
  ssh_cmd "$@"
}

# curl via SSH to the remote host (hits localhost on the remote).
remote_curl() {
  local url="$1"
  shift
  ssh_cmd "curl -sf --max-time 10 '$url'" "$@"
}

# Retry helper for transient network/service startup races.
# Usage: retry 3 2 remote systemctl is-active tailscaled.service
retry() {
  local max_attempts="$1"
  local delay_seconds="$2"
  shift 2

  local attempt=1
  while [[ "$attempt" -le "$max_attempts" ]]; do
    if "$@"; then
      return 0
    fi
    if [[ "$attempt" -lt "$max_attempts" ]]; then
      echo "# Attempt ${attempt}/${max_attempts} failed, retrying in ${delay_seconds}s..." >&2
      sleep "$delay_seconds"
    fi
    attempt=$((attempt + 1))
  done

  echo "FAIL: command failed after ${max_attempts} attempts: $*" >&2
  return 1
}

# Run a command on the remote host as the agent user.
# Root SSH is required to reach the host (agent user has no SSH key in the public template).
# We sudo to the agent user for the test so the command runs under the correct principal.
remote_as_agent() {
  local escaped_cmd
  escaped_cmd="$(printf '%q ' "$@")"
  ssh_cmd "sudo -u ${AGENT_USER} bash -c ${escaped_cmd}"
}

# --- Assertion helpers ---
# Assert a systemd unit is active.
assert_unit_active() {
  local unit="$1"
  local result
  result="$(remote systemctl is-active "$unit" 2>&1)" || {
    echo "FAIL: unit '$unit' is not active (state: ${result:-unknown})"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} journalctl -u $unit --no-pager -n 20"
    return 1
  }
  if [[ "$result" != "active" ]]; then
    echo "FAIL: unit '$unit' state is '$result', expected 'active'"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl status $unit"
    return 1
  fi
}

# Assert an HTTP endpoint returns 200.
assert_http_ok() {
  local url="$1"
  local label="${2:-$url}"
  local status
  status="$(remote curl -so /dev/null -w '%{http_code}' --max-time 10 "$url" 2>&1)" || {
    echo "FAIL: $label — could not connect"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -v '$url'"
    return 1
  }
  if [[ "$status" != "200" ]]; then
    echo "FAIL: $label — HTTP $status, expected 200"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -sv '$url'"
    return 1
  fi
}

# Assert a secret file exists with correct ownership.
# Wrapper API keys are agent-owned by declaration in modules/secrets.nix. Other
# secrets may be root-, dev-, or service-owned. Callers should pass the
# expected owner explicitly.
assert_secret_exists() {
  local path="$1"
  local expected_owner="${2:?expected_owner required}"
  remote test -f "$path" || {
    echo "FAIL: secret file '$path' does not exist"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} ls -la /run/secrets/"
    return 1
  }
  local owner
  owner="$(remote stat -c '%U' "$path")"
  if [[ "$owner" != "$expected_owner" ]]; then
    echo "FAIL: secret '$path' owned by '$owner', expected '$expected_owner'"
    return 1
  fi
}

# Assert a sysctl value.
assert_sysctl() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(remote sysctl -n "$key" 2>&1)" || {
    echo "FAIL: sysctl '$key' not readable"
    return 1
  }
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: sysctl $key = '$actual', expected '$expected'"
    return 1
  fi
}

# Assert command output contains a substring.
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="${3:-output}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: expected $label to contain '$needle'"
    echo "DEBUG: actual $label: $haystack"
    return 1
  fi
}

# Check if current host is tsurf (Contabo) vs ovh.
is_tsurf() {
  [[ "$HOST" == "tsurf" ]]
}

is_ovh() {
  [[ "$HOST" == "tsurf-dev" ]] || [[ "$HOST" == "ovh" ]]
}
