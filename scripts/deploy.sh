#!/usr/bin/env bash
# scripts/deploy.sh — Deploy agent-neurosys NixOS config to acfs
#
# Modes:
#   --mode local   (default) Build locally, push + switch remotely
#   --mode remote  SSH into server, pull, rebuild on server
#
# Flags:
#   --skip-update  Skip 'nix flake update parts' step
#   --help         Print usage
#
# @decision Manual deploy only — no CI/CD. NixOS handles incrementality.
# @decision Full nixos-rebuild switch every deploy — no partial/container-only.
# @decision Container health polling (30s) — no app-level checks.
# @decision No auto-commit of flake.lock — print reminder instead.
set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="root@acfs"
MODE="local"
SKIP_UPDATE=false
SECONDS=0

CONTAINERS=("parts-tools" "parts-agent" "claw-swap-db" "claw-swap-app" "claw-swap-caddy")

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Deploy agent-neurosys NixOS config to acfs server.

Options:
  --mode local    Build locally, push closure, switch remotely (default)
  --mode remote   SSH into server, pull repo, rebuild on server
  --skip-update   Skip 'nix flake update parts' before building
  --help          Show this help

Examples:
  ./scripts/deploy.sh                   # Deploy with latest parts (local build)
  ./scripts/deploy.sh --skip-update     # Deploy without updating parts input
  ./scripts/deploy.sh --mode remote     # Build on server instead of locally
USAGE
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --skip-update)
      SKIP_UPDATE=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$MODE" != "local" && "$MODE" != "remote" ]]; then
  echo "Error: --mode must be 'local' or 'remote', got '$MODE'"
  exit 1
fi

# --- Update parts input ---
if [[ "$SKIP_UPDATE" == false ]]; then
  echo "==> Updating parts flake input..."
  nix flake update parts --flake "$FLAKE_DIR"
fi

PARTS_REV=$(nix flake metadata "$FLAKE_DIR" --json 2>/dev/null | jq -r '.locks.nodes.parts.locked.rev // "unknown"')
PARTS_REV_SHORT="${PARTS_REV:0:7}"

echo "==> Parts revision: $PARTS_REV_SHORT"

# --- Build + deploy ---
if [[ "$MODE" == "local" ]]; then
  echo "==> Building locally and deploying to $TARGET..."
  nix shell nixpkgs#nixos-rebuild -c \
    nixos-rebuild switch \
      --flake "$FLAKE_DIR#acfs" \
      --target-host "$TARGET" \
      --build-host localhost
else
  echo "==> Deploying via remote rebuild on $TARGET..."
  ssh "$TARGET" bash -s <<'REMOTE'
    set -euo pipefail
    cd /data/projects/agent-neurosys
    git pull --ff-only
    nixos-rebuild switch --flake .#acfs
REMOTE
fi

# --- Verify containers ---
echo "==> Verifying containers (polling up to 30s)..."
FAILED=0
for attempt in $(seq 1 15); do
  FAILED=0
  ALL_RUNNING=true
  for c in "${CONTAINERS[@]}"; do
    if ! ssh "$TARGET" "docker ps --filter name=^${c}\$ --filter status=running -q" 2>/dev/null | grep -q .; then
      ALL_RUNNING=false
      FAILED=1
    fi
  done
  if [[ "$ALL_RUNNING" == true ]]; then
    break
  fi
  sleep 2
done

# --- Report ---
DURATION=$SECONDS
echo ""

if [[ "$FAILED" -eq 0 ]]; then
  echo "=== Deploy SUCCESS ==="
  echo "Parts revision: $PARTS_REV_SHORT"
  echo "Duration: $((DURATION / 60))m $((DURATION % 60))s"
  echo ""
  echo "Container status:"
  ssh "$TARGET" "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E '(NAMES|parts-|claw-swap-)'"
  echo ""
  if [[ "$SKIP_UPDATE" == false ]]; then
    echo "NOTE: flake.lock was updated. Remember to commit when ready:"
    echo "  git add flake.lock && git commit -m \"chore: update parts input to $PARTS_REV_SHORT\""
  fi
else
  echo "=== Deploy FAILED ==="
  echo "Containers not running after 30s:"
  for c in "${CONTAINERS[@]}"; do
    if ! ssh "$TARGET" "docker ps --filter name=^${c}\$ --filter status=running -q" 2>/dev/null | grep -q .; then
      echo "  - $c"
    fi
  done
  echo ""
  echo "All container status:"
  ssh "$TARGET" "docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -E '(NAMES|parts-|claw-swap-)'" || true
  echo ""
  echo "To rollback:"
  echo "  ssh $TARGET nixos-rebuild switch --rollback"
  exit 1
fi
