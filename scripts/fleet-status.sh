#!/usr/bin/env bash
# fleet-status.sh — Conway Automaton agent monitoring dashboard
# @decision FLT-01: Queries Conway Cloud API directly (no Creator CLI dependency)
# @decision FLT-02: Single-agent initially; extend AGENTS array to add more
# @decision FLT-03: Graceful degradation — shows placeholder if API unavailable
#
# Usage:
#   scripts/fleet-status.sh [--watch] [--json]
#
# Environment:
#   CONWAY_API_KEY — Conway Cloud API key (required)

set -euo pipefail

CONWAY_API="https://api.conway.tech/v1"
# @decision FLT-02: Extend this array when adding agents
AGENTS=("hypothesis-1")
WATCH=false
JSON=false

usage() {
  echo "Usage: $0 [--watch] [--json]"
  echo ""
  echo "Options:"
  echo "  --watch    Refresh every 60 seconds"
  echo "  --json     Output raw JSON for each agent"
  echo ""
  echo "Environment:"
  echo "  CONWAY_API_KEY  Conway Cloud API key (required)"
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --watch) WATCH=true ;;
    --json) JSON=true ;;
    --help|-h) usage ;;
    *) echo "Unknown flag: $arg" >&2; usage ;;
  esac
done

if [[ -z "${CONWAY_API_KEY:-}" ]]; then
  echo "Error: CONWAY_API_KEY is not set." >&2
  echo "Export it or add to your shell profile: export CONWAY_API_KEY=..." >&2
  exit 1
fi

# Fetch agent status from Conway Cloud API.
# Returns JSON blob or empty string on failure.
fetch_agent() {
  local name="$1"
  curl -sf \
    -H "Authorization: Bearer $CONWAY_API_KEY" \
    -H "Accept: application/json" \
    "$CONWAY_API/agents/$name/status" 2>/dev/null || echo ""
}

# Extract a field from JSON, with a fallback value.
jq_or() {
  local json="$1" query="$2" fallback="$3"
  echo "$json" | jq -r "$query" 2>/dev/null || echo "$fallback"
}

# Format a cents integer as a dollar string (e.g. 25000 → "$250.00").
cents_to_dollars() {
  local cents="$1"
  if [[ "$cents" =~ ^[0-9]+$ ]]; then
    printf "\$%d.%02d" $((cents / 100)) $((cents % 100))
  else
    echo "$cents"
  fi
}

print_agent_block() {
  local name="$1"
  local raw
  raw=$(fetch_agent "$name")

  if [[ -z "$raw" ]]; then
    echo "$name"
    echo "  Status:  UNREACHABLE"
    echo "  (check CONWAY_API_KEY and agent name)"
    return
  fi

  if [[ "$JSON" == "true" ]]; then
    echo "=== $name ==="
    echo "$raw" | jq . 2>/dev/null || echo "$raw"
    return
  fi

  local balance revenue burn tier turns days
  balance=$(jq_or "$raw" '.balance_cents' "?")
  revenue=$(jq_or "$raw" '.revenue_cents' "?")
  burn=$(jq_or "$raw" '.daily_burn_cents' "?")
  tier=$(jq_or "$raw" '.survival_tier' "unknown")
  turns=$(jq_or "$raw" '.turn_count' "?")
  days=$(jq_or "$raw" '.days_active' "?")

  local bal_fmt rev_fmt burn_fmt run_est
  bal_fmt=$(cents_to_dollars "$balance")
  rev_fmt=$(cents_to_dollars "$revenue")
  burn_fmt=$(cents_to_dollars "$burn")/day

  if [[ "$balance" =~ ^[0-9]+$ && "$burn" =~ ^[0-9]+$ && "$burn" -gt 0 ]]; then
    run_est="$(( balance / burn ))d runway"
  else
    run_est="—"
  fi

  # Tier color coding (if terminal supports it)
  local tier_fmt="$tier"
  if [[ -t 1 ]]; then
    case "$tier" in
      normal)       tier_fmt="\033[32m$tier\033[0m" ;;   # green
      low_compute)  tier_fmt="\033[33m$tier\033[0m" ;;   # yellow
      critical)     tier_fmt="\033[31m$tier\033[0m" ;;   # red
      dead)         tier_fmt="\033[1;31m$tier\033[0m" ;; # bold red
    esac
  fi

  echo "$name"
  printf "  Balance: %-12s  Revenue: %-12s\n" "$bal_fmt" "$rev_fmt"
  printf "  Burn:    %-12s  Runway:  %-12s\n" "$burn_fmt" "$run_est"
  printf "  Tier:    %-12b  Turns:   %-8s  Days: %s\n" "$tier_fmt" "$turns" "$days"
}

print_dashboard() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "╔══════════════════════════════════════════════════════╗"
  printf "║  AUTOMATON STATUS   %-34s║\n" "$ts"
  echo "╠══════════════════════════════════════════════════════╣"
  echo "║                                                      ║"
  for agent in "${AGENTS[@]}"; do
    while IFS= read -r line; do
      # Pad to fixed width and wrap in box
      printf "║  %-50b  ║\n" "$line"
    done < <(print_agent_block "$agent")
    echo "║                                                      ║"
  done
  echo "╚══════════════════════════════════════════════════════╝"
}

if [[ "$JSON" == "true" ]]; then
  for agent in "${AGENTS[@]}"; do
    print_agent_block "$agent"
  done
elif [[ "$WATCH" == "true" ]]; then
  while true; do
    clear
    print_dashboard
    echo "(refreshing every 60s — ctrl+c to stop)"
    sleep 60
  done
else
  print_dashboard
fi
