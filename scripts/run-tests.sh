#!/usr/bin/env bash
# scripts/run-tests.sh — Run neurosys test suite
# @decision TEST-48-01: Eval and live tests share a single wrapper for agent automation output.
#
# Usage:
#   ./scripts/run-tests.sh                     # Eval checks only
#   ./scripts/run-tests.sh --live              # Eval + live tests against neurosys
#   ./scripts/run-tests.sh --live --host ovh   # Eval + live tests against ovh
#   ./scripts/run-tests.sh --live-only         # Live tests only

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FLAKE_DIR"

RUN_EVAL=true
RUN_LIVE=false
HOST="neurosys"
FAILURES=0

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
    --host)
      HOST="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: ./scripts/run-tests.sh [--live] [--live-only] [--host HOST]

  --live        Run eval checks + live tests
  --live-only   Run live tests only (skip nix flake check)
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
  if nix run .#test-live -- --host "$HOST"; then
    echo "PASS: all live tests passed"
  else
    echo "FAIL: live tests failed"
    FAILURES=$((FAILURES + 1))
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
