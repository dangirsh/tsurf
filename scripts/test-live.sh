#!/usr/bin/env bash
set -euo pipefail

HOST=""
BATS_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host|-h)
      HOST="$2"
      shift 2
      ;;
    *)
      BATS_FILES+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "Usage: test-live -- --host <hostname> [test-files...]"
  exit 1
fi

export TSURF_TEST_HOST="$HOST"
if [[ -n "${TSURF_TEST_HOSTS_JSON:-}" ]]; then
  agent_user="$(jq -r --arg host "$HOST" '.[$host].agentUser // empty' <<<"$TSURF_TEST_HOSTS_JSON")"
  has_sandbox="$(
    jq -r --arg host "$HOST" \
      'if .[$host].hasSandbox == true then "1" elif .[$host].hasSandbox == false then "0" else "" end' \
      <<<"$TSURF_TEST_HOSTS_JSON"
  )"

  if [[ -n "$agent_user" ]]; then
    export TSURF_TEST_AGENT_USER="$agent_user"
  else
    echo "WARNING: unknown host '$HOST' — TSURF_TEST_AGENT_USER not set"
  fi

  if [[ -n "$has_sandbox" ]]; then
    export TSURF_TEST_HAS_SANDBOX="$has_sandbox"
  fi
fi

tests_dir="${TSURF_TESTS_DIR:?TSURF_TESTS_DIR is not set}"
if [[ ! -d "$tests_dir" ]]; then
  echo "ERROR: tests directory not found: $tests_dir"
  exit 1
fi

if [[ "${#BATS_FILES[@]}" -eq 0 ]]; then
  echo "=== Running all live tests against $HOST ==="
  bats --tap "$tests_dir"/*.bats
else
  echo "=== Running selected live tests against $HOST ==="
  bats --tap "${BATS_FILES[@]}"
fi
