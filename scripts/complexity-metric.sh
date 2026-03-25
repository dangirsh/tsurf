#!/usr/bin/env bash
# complexity-metric.sh — Count effective lines of code across tsurf.
# Metric: non-blank, non-comment lines in .nix, .sh, and .py files.
# Usage: complexity-metric [--diff]
#   --diff   Show delta from .complexity-baseline
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BASELINE_FILE="${REPO_ROOT}/.complexity-baseline"
SHOW_DIFF=false

if [[ "${1:-}" == "--diff" ]]; then
  SHOW_DIFF=true
fi

# Count effective lines (non-blank, non-comment) in tracked files only
count_loc() {
  local total=0
  while IFS= read -r file; do
    [[ -f "${REPO_ROOT}/${file}" ]] || continue
    local count
    # Strip blank lines and single-line comments (# for nix/sh/py, // for nix)
    count=$(sed -e '/^[[:space:]]*$/d' \
                -e '/^[[:space:]]*#/d' \
                -e '/^[[:space:]]*\/\//d' \
                "${REPO_ROOT}/${file}" | wc -l)
    total=$((total + count))
  done < <(git -C "${REPO_ROOT}" ls-files -- '*.nix' '*.sh' '*.py')
  echo "${total}"
}

CURRENT=$(count_loc)

if [[ "${SHOW_DIFF}" == "true" ]]; then
  if [[ -f "${BASELINE_FILE}" ]]; then
    PREVIOUS=$(cat "${BASELINE_FILE}")
    DELTA=$((CURRENT - PREVIOUS))
    if [[ ${DELTA} -gt 0 ]]; then
      echo "Complexity: ${CURRENT} eLOC (+${DELTA} since baseline)"
    elif [[ ${DELTA} -lt 0 ]]; then
      echo "Complexity: ${CURRENT} eLOC (${DELTA} since baseline)"
    else
      echo "Complexity: ${CURRENT} eLOC (no change)"
    fi
  else
    echo "Complexity: ${CURRENT} eLOC (no baseline found)"
  fi
else
  echo "Complexity: ${CURRENT} eLOC"
fi

echo "${CURRENT}"
