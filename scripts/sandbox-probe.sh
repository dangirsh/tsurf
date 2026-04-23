#!/usr/bin/env bash
# scripts/sandbox-probe.sh — Runtime sandbox boundary probe.
#
# This script is executed inside the nono sandbox as the agent user by the
# BATS behavioral tests in tests/live/sandbox-behavioral.bats. It is NOT
# useful outside that context.
#
# Usage: sandbox-probe.sh <check>
#
# Each check exits 0 on pass, non-zero on fail. "Denied" checks pass when
# the operation is correctly rejected (EPERM/EACCES).

set -euo pipefail

check="${1:?Usage: sandbox-probe.sh <check>}"

# --- Data-driven denied-path checks ---
# Each entry: "check-name|command|path|description"
# command is "cat" (file) or "ls" (directory).
denied_checks=(
  "denied-secrets|cat|/run/secrets/anthropic-api-key|/run/secrets/anthropic-api-key"
  "denied-ssh|ls|$HOME/.ssh/|~/.ssh/"
  "denied-gnupg|ls|$HOME/.gnupg/|~/.gnupg/"
  "denied-bash-history|cat|$HOME/.bash_history|~/.bash_history"
  "denied-aws|ls|$HOME/.aws/|~/.aws/"
  "denied-kube|ls|$HOME/.kube/|~/.kube/"
  "denied-docker|ls|$HOME/.docker/|~/.docker/"
  "denied-npmrc|cat|$HOME/.npmrc|~/.npmrc"
  "denied-git-credentials|cat|$HOME/.git-credentials|~/.git-credentials"
  "denied-etc-nono|ls|/etc/nono/|/etc/nono/"
)

# Try the data-driven denied checks first
for entry in "${denied_checks[@]}"; do
  IFS='|' read -r name cmd path desc <<< "$entry"
  if [[ "$check" == "$name" ]]; then
    if $cmd "$path" >/dev/null 2>&1; then
      echo "FAIL: agent can access $desc" >&2
      exit 1
    fi
    echo "PASS: $check"
    exit 0
  fi
done

# --- Checks with custom logic ---
case "$check" in
  allowed-repo-read)
    # Agent must be able to read files in the current workspace.
    if ! cat README.md >/dev/null 2>&1; then
      echo "FAIL: agent cannot read README.md in current workspace" >&2
      exit 1
    fi
    ;;

  allowed-workdir-write)
    # Agent must be able to write files in the working directory.
    tmpfile="sandbox-probe-test-$$"
    if ! touch "$tmpfile" 2>/dev/null; then
      echo "FAIL: agent cannot write to workdir" >&2
      exit 1
    fi
    rm -f "$tmpfile"
    ;;

  check-identity)
    # Verify we are running as the agent user.
    expected_user="${EXPECTED_AGENT_USER:-agent}"
    current_user="$(whoami)"
    if [[ "$current_user" != "$expected_user" ]]; then
      echo "FAIL: running as '$current_user', expected '$expected_user'" >&2
      exit 1
    fi
    if [[ "$(id -u)" == "0" ]]; then
      echo "FAIL: running as root (uid 0)" >&2
      exit 1
    fi
    ;;

  *)
    echo "Unknown check: $check" >&2
    available="$(printf '%s\n' "${denied_checks[@]}" | cut -d'|' -f1 | tr '\n' ' ')"
    echo "Available: ${available}allowed-repo-read allowed-workdir-write check-identity" >&2
    exit 2
    ;;
esac

echo "PASS: $check"
