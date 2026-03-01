#!/usr/bin/env bash
# scripts/run-tests.sh — Run neurosys test suite
# @decision TEST-48-01: Eval and live tests share a single wrapper for agent automation output.
# @decision TEST-48-02: JSON mode emits one object per BATS TAP test for agent-parsable failures.
#
# Usage:
#   ./scripts/run-tests.sh                            # Eval checks only
#   ./scripts/run-tests.sh --live                     # Eval + live tests against neurosys
#   ./scripts/run-tests.sh --live --host ovh          # Eval + live tests against ovh
#   ./scripts/run-tests.sh --live-only                # Live tests only
#   ./scripts/run-tests.sh --live --json              # Live tests + JSON summary

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FLAKE_DIR"

RUN_EVAL=true
RUN_LIVE=false
JSON_OUTPUT=false
HOST="neurosys"
FAILURES=0

# Convert BATS TAP output to newline-delimited JSON.
# Each record has the required shape: {name, status, error}.
tap_to_json() {
  local tap_output="$1"

  echo "$tap_output" | awk '
    function esc(str, out) {
      out = str
      gsub(/\\/, "\\\\", out)
      gsub(/"/, "\\\"", out)
      gsub(/\t/, " ", out)
      gsub(/\r/, "", out)
      return out
    }

    function emit(name, status, error) {
      printf("{\"name\":\"%s\",\"status\":\"%s\",\"error\":\"%s\"}\n", esc(name), status, esc(error))
    }

    function flush_fail() {
      if (in_fail) {
        emit(fail_name, "fail", fail_error)
        in_fail = 0
        fail_name = ""
        fail_error = ""
      }
    }

    /^ok [0-9]+ / {
      flush_fail()
      line = $0
      sub(/^ok [0-9]+ -? /, "", line)
      gsub(/[[:space:]]+$/, "", line)

      skip_reason = ""
      if (match(line, / # skip(.*)$/)) {
        skip_reason = substr(line, RSTART + 8)
        line = substr(line, 1, RSTART - 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", skip_reason)
        emit(line, "skip", skip_reason)
      } else {
        emit(line, "pass", "")
      }
      next
    }

    /^not ok [0-9]+ / {
      flush_fail()
      line = $0
      sub(/^not ok [0-9]+ -? /, "", line)
      gsub(/[[:space:]]+$/, "", line)
      in_fail = 1
      fail_name = line
      fail_error = ""
      next
    }

    /^# / {
      if (in_fail) {
        line = substr($0, 3)
        if (fail_error != "") {
          fail_error = fail_error "\n"
        }
        fail_error = fail_error line
      }
      next
    }

    /^1\.\.[0-9]+$/ { next }

    END {
      flush_fail()
    }
  '
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live)
      RUN_LIVE=true
      shift
      ;;
    --live-only)
      RUN_LIVE=true
      RUN_EVAL=false
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: ./scripts/run-tests.sh [--live] [--live-only] [--json] [--host HOST]

  --live        Run eval checks + live tests
  --live-only   Run live tests only (skip nix flake check)
  --json        Emit one JSON object per live test from BATS TAP output
  --host HOST   Target host for live tests (default: neurosys)
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if $JSON_OUTPUT && ! $RUN_LIVE; then
  echo "NOTE: --json has no effect without --live or --live-only"
fi

if $RUN_EVAL; then
  echo "=== Running eval checks (nix flake check) ==="
  if nix flake check; then
    echo "PASS: all eval checks passed"
  else
    echo "FAIL: eval checks failed"
    FAILURES=$((FAILURES + 1))
  fi
  echo
fi

if $RUN_LIVE; then
  echo "=== Running live tests against ${HOST} ==="
  live_output=""
  if live_output="$(nix run .#test-live -- --host "$HOST" 2>&1)"; then
    echo "$live_output"
    echo "PASS: all live tests passed"
  else
    echo "$live_output"
    echo "FAIL: live tests failed"
    FAILURES=$((FAILURES + 1))
  fi

  if $JSON_OUTPUT; then
    echo
    echo "=== JSON Summary (one object per test) ==="
    tap_to_json "$live_output"
  fi
  echo
fi

mkdir -p .claude
if [[ "$FAILURES" -eq 0 ]]; then
  echo "pass|0|$(date +%s)" > .claude/.test-status
  echo "=== ALL TEST SUITES PASSED ==="
else
  echo "fail|${FAILURES}|$(date +%s)" > .claude/.test-status
  echo "=== ${FAILURES} TEST SUITE(S) FAILED ==="
  exit 1
fi
