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

case "$check" in
  denied-secrets)
    # /run/secrets must be inaccessible to the sandboxed agent.
    if cat /run/secrets/anthropic-api-key >/dev/null 2>&1; then
      echo "FAIL: agent can read /run/secrets/anthropic-api-key" >&2
      exit 1
    fi
    ;;

  denied-ssh)
    # ~/.ssh must be inaccessible inside the sandbox.
    if ls ~/.ssh/ >/dev/null 2>&1; then
      echo "FAIL: agent can list ~/.ssh/" >&2
      exit 1
    fi
    ;;

  denied-gnupg)
    # ~/.gnupg must be inaccessible inside the sandbox.
    if ls ~/.gnupg/ >/dev/null 2>&1; then
      echo "FAIL: agent can list ~/.gnupg/" >&2
      exit 1
    fi
    ;;

  denied-bash-history)
    # ~/.bash_history must be inaccessible inside the sandbox.
    if cat ~/.bash_history >/dev/null 2>&1; then
      echo "FAIL: agent can read ~/.bash_history" >&2
      exit 1
    fi
    ;;

  allowed-repo-read)
    # Agent must be able to read files in the current git repo.
    if ! cat README.md >/dev/null 2>&1; then
      echo "FAIL: agent cannot read README.md in current repo" >&2
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

  denied-aws)
    # ~/.aws must be inaccessible inside the sandbox.
    if ls ~/.aws/ >/dev/null 2>&1; then
      echo "FAIL: agent can list ~/.aws/" >&2
      exit 1
    fi
    ;;

  denied-kube)
    # ~/.kube must be inaccessible inside the sandbox.
    if ls ~/.kube/ >/dev/null 2>&1; then
      echo "FAIL: agent can list ~/.kube/" >&2
      exit 1
    fi
    ;;

  denied-docker)
    # ~/.docker must be inaccessible inside the sandbox.
    if ls ~/.docker/ >/dev/null 2>&1; then
      echo "FAIL: agent can list ~/.docker/" >&2
      exit 1
    fi
    ;;

  denied-npmrc)
    # ~/.npmrc must be inaccessible inside the sandbox.
    if cat ~/.npmrc >/dev/null 2>&1; then
      echo "FAIL: agent can read ~/.npmrc" >&2
      exit 1
    fi
    ;;

  denied-git-credentials)
    # ~/.git-credentials must be inaccessible inside the sandbox.
    if cat ~/.git-credentials >/dev/null 2>&1; then
      echo "FAIL: agent can read ~/.git-credentials" >&2
      exit 1
    fi
    ;;

  denied-etc-nono)
    # /etc/nono must be inaccessible inside the sandbox.
    if ls /etc/nono/ >/dev/null 2>&1; then
      echo "FAIL: agent can list /etc/nono/" >&2
      exit 1
    fi
    ;;

  *)
    echo "Unknown check: $check" >&2
    echo "Available: denied-secrets denied-ssh denied-gnupg denied-bash-history denied-aws denied-kube denied-docker denied-npmrc denied-git-credentials denied-etc-nono allowed-repo-read allowed-workdir-write check-identity" >&2
    exit 2
    ;;
esac

echo "PASS: $check"
