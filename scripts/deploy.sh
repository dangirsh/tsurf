#!/usr/bin/env bash
# scripts/deploy.sh — Deploy a selected neurosys NixOS flake node
#
# Modes:
#   --mode local   (default) Build locally, deploy remotely via deploy-rs
#   --mode remote  Build remotely via deploy-rs --remote-build
#
# Flags:
#   --node NAME         Flake node to deploy (default: neurosys; choices: neurosys, ovh)
#   --target USER@HOST  Override SSH target (default depends on --node)
#   --first-deploy  Disable magic rollback once for migration from nixos-rebuild
#   --no-magic-rollback  Disable magic rollback for intentional network/SSH changes
#   --skip-update  Skip 'nix flake update parts' step
#   --help         Print usage
#
# @decision Manual deploy only — no CI/CD. NixOS handles incrementality.
# @decision Full deploy-rs system activation every deploy — no partial/container-only.
# @decision Magic rollback enabled by default with 120s confirm timeout.
# @decision Service health polling (30s) — systemd for parts, postgresql, claw-swap-app.
# @decision No auto-commit of flake.lock — print reminder instead.
set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NODE="neurosys"
TARGET=""
TARGET_SET=false
MODE="local"
FIRST_DEPLOY=false
NO_MAGIC_ROLLBACK=false
SKIP_UPDATE=false
SECONDS=0

SYSTEMD_SERVICES=("parts-tools" "parts-agent" "postgresql" "claw-swap-app")
DOCKER_CONTAINERS=()
mkdir -p "$FLAKE_DIR/tmp"

# @decision Two-level deploy locking: local flock + remote mkdir (adapted from parts deploy.sh)
LOCAL_LOCK=""
REMOTE_LOCK_DIR=""
REMOTE_LOCK_HELD=false

cleanup() {
  if [[ "$REMOTE_LOCK_HELD" == true ]]; then
    ssh "$TARGET" "rm -rf '$REMOTE_LOCK_DIR'" 2>/dev/null || true
  fi
}
trap cleanup EXIT

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Deploy neurosys NixOS config to the selected deploy node.

Options:
  --node NAME           Deploy flake node (neurosys|ovh, default: neurosys)
  --mode local          Build locally, deploy remotely (default)
  --mode remote         Build on target host via deploy-rs --remote-build
  --target U@H          Override SSH target (default by node)
  --first-deploy        Disable magic rollback for one-time migration
  --no-magic-rollback   Disable magic rollback for this deploy
  --skip-update         Skip 'nix flake update parts' before building
  --help                Show this help

Examples:
  ./scripts/deploy.sh                              # Deploy staging node (neurosys)
  ./scripts/deploy.sh --node ovh                  # Deploy production node (ovh)
  ./scripts/deploy.sh --node ovh --mode remote    # Remote-build deploy to ovh
  ./scripts/deploy.sh --first-deploy               # First migration deploy from nixos-rebuild
  ./scripts/deploy.sh --no-magic-rollback          # Intentional networking change deploy
  ./scripts/deploy.sh --skip-update                # Deploy without updating parts input
  ./scripts/deploy.sh --target root@1.2.3.4        # Explicit SSH target override
USAGE
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --node)
      NODE="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      TARGET_SET=true
      shift 2
      ;;
    --first-deploy)
      FIRST_DEPLOY=true
      shift
      ;;
    --no-magic-rollback)
      NO_MAGIC_ROLLBACK=true
      shift
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

if [[ "$NODE" != "neurosys" && "$NODE" != "ovh" ]]; then
  echo "Error: --node must be 'neurosys' or 'ovh', got '$NODE'"
  exit 1
fi

if [[ "$TARGET_SET" == false ]]; then
  if [[ "$NODE" == "ovh" ]]; then
    TARGET="root@neurosys-prod"
  else
    TARGET="root@neurosys"
  fi
fi

LOCAL_LOCK="$FLAKE_DIR/tmp/neurosys-${NODE}-deploy.local.lock"
REMOTE_LOCK_DIR="/var/lock/neurosys-${NODE}-deploy.lock"

# --- Local lock (prevent concurrent deploys from same machine) ---
exec 9>"$LOCAL_LOCK"
if command -v flock &>/dev/null; then
  if ! flock --nonblock 9; then
    echo "ERROR: Another deploy is already running on this machine (lock: $LOCAL_LOCK)."
    exit 1
  fi
else
  echo "WARNING: flock not available — local concurrent-deploy protection skipped."
fi

# --- Remote lock (prevent concurrent deploys from different machines) ---
GIT_SHA=$(git -C "$FLAKE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
LOCK_INFO="holder=$(whoami)@$(hostname)
pid=$$
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
sha=$GIT_SHA"

if ! ssh "$TARGET" "mkdir '$REMOTE_LOCK_DIR' 2>/dev/null"; then
  echo "ERROR: Deploy already in progress on the remote server."
  echo ""
  echo "Lock info:"
  ssh "$TARGET" "cat '$REMOTE_LOCK_DIR/info.txt' 2>/dev/null" || echo "  (could not read lock metadata)"
  echo ""
  echo "If the previous deploy crashed, remove the lock manually:"
  echo "  ssh $TARGET rm -rf $REMOTE_LOCK_DIR"
  exit 1
fi
REMOTE_LOCK_HELD=true
printf '%s\n' "$LOCK_INFO" | ssh "$TARGET" "cat > '$REMOTE_LOCK_DIR/info.txt'" 2>/dev/null || true

# --- Update parts input ---
if [[ "$SKIP_UPDATE" == false ]]; then
  echo "==> Updating parts flake input..."
  nix flake update parts --flake "$FLAKE_DIR"
fi

PARTS_REV=$(nix flake metadata "$FLAKE_DIR" --json 2>/dev/null | jq -r '.locks.nodes.parts.locked.rev // "unknown"')
PARTS_REV_SHORT="${PARTS_REV:0:7}"

echo "==> Parts revision: $PARTS_REV_SHORT"

# --- Build + deploy ---
if [[ "$TARGET_SET" == true ]]; then
  echo "WARNING: --target affects SSH locking/health checks only."
  echo "         deploy-rs deploy target is flake node '$NODE'."
fi

DEPLOY_ARGS=(
  "$FLAKE_DIR#$NODE"
  --confirm-timeout 120
)
if [[ "$FIRST_DEPLOY" == true || "$NO_MAGIC_ROLLBACK" == true ]]; then
  DEPLOY_ARGS+=(--magic-rollback false)
fi

if [[ "$FIRST_DEPLOY" == true ]]; then
  echo "==> First deploy mode enabled: magic rollback disabled for migration."
fi
if [[ "$NO_MAGIC_ROLLBACK" == true ]]; then
  echo "==> Magic rollback disabled for this deploy (intentional networking/SSH changes)."
fi

if [[ "$MODE" == "local" ]]; then
  echo "==> Deploying node '$NODE' to $TARGET with deploy-rs (confirm timeout: 120s)..."
  nix run "$FLAKE_DIR#deploy-rs" -- "${DEPLOY_ARGS[@]}"
else
  echo "==> Deploying node '$NODE' via remote build on $TARGET with deploy-rs..."
  nix run "$FLAKE_DIR#deploy-rs" -- "${DEPLOY_ARGS[@]}" --remote-build
fi

# --- Verify services ---
echo "==> Verifying services (polling up to 30s)..."
FAILED=0
for attempt in $(seq 1 15); do
  FAILED=0
  ALL_RUNNING=true

  # Check systemd services (parts-tools, parts-agent)
  for s in "${SYSTEMD_SERVICES[@]}"; do
    if ! ssh "$TARGET" "systemctl is-active --quiet ${s}.service" 2>/dev/null; then
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
  echo "Service status:"
  for s in "${SYSTEMD_SERVICES[@]}"; do
    STATUS=$(ssh "$TARGET" "systemctl is-active ${s}.service" 2>/dev/null || echo "unknown")
    echo "  ${s}: ${STATUS}"
  done
  echo ""
  if [[ "$SKIP_UPDATE" == false ]]; then
    echo "NOTE: flake.lock was updated. Remember to commit when ready:"
    echo "  git add flake.lock && git commit -m \"chore: update parts input to $PARTS_REV_SHORT\""
  fi
else
  echo "=== Deploy FAILED ==="
  echo "Services not active after 30s:"
  for s in "${SYSTEMD_SERVICES[@]}"; do
    if ! ssh "$TARGET" "systemctl is-active --quiet ${s}.service" 2>/dev/null; then
      echo "  - ${s}.service"
    fi
  done
  echo ""
  echo "All service status:"
  for s in "${SYSTEMD_SERVICES[@]}"; do
    STATUS=$(ssh "$TARGET" "systemctl is-active ${s}.service" 2>/dev/null || echo "unknown")
    echo "  ${s}: ${STATUS}"
  done
  echo ""
  echo "Connectivity failures auto-rollback with deploy-rs magic rollback."
  echo "For non-connectivity issues (for example containers failing after deploy), use manual rollback:"
  echo "  ssh $TARGET nixos-rebuild switch --rollback"
  exit 1
fi
