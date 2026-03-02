#!/usr/bin/env bash
# scripts/deploy.sh — Deploy a selected neurosys NixOS flake node
#
# Modes:
#   --mode remote  (default) Build on target host via deploy-rs --remote-build
#   --mode local   Build locally, deploy remotely via deploy-rs
#
# Flags:
#   --node NAME         Flake node to deploy (default: neurosys; choices: neurosys, ovh)
#   --target USER@HOST  Override SSH target (default depends on --node)
#   --first-deploy  Disable magic rollback once for migration from nixos-rebuild
#   --no-magic-rollback  Disable magic rollback for intentional network/SSH changes
#   --skip-update  (no-op; parts update is skipped by default — use --update-parts to pull)
#   --update-parts  Pull latest parts flake input before building
#   --help         Print usage
#
# @decision Manual deploy only — no CI/CD. NixOS handles incrementality.
# @decision Full deploy-rs system activation every deploy — no partial/container-only.
# @decision Magic rollback enabled by default with 120s confirm timeout.
# @decision Service health polling (30s) — systemd for parts, postgresql, claw-swap-app.
# @decision No auto-commit of flake.lock — print reminder instead.
# @decision Remote build default (DEPLOY-01): neurosys has 18 vCPU / 96 GB RAM — faster than
#   local build + closure upload. Use --mode local for first deploys or when server is unreachable.
set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NODE="neurosys"
TARGET=""
TARGET_SET=false
MODE="remote"
FIRST_DEPLOY=false
NO_MAGIC_ROLLBACK=false
SKIP_UPDATE=true
SECONDS=0

SYSTEMD_SERVICES=()
DOCKER_CONTAINERS=()
mkdir -p "$FLAKE_DIR/tmp"

# @decision Two-level deploy locking: local flock + remote mkdir (adapted from parts deploy.sh)
LOCAL_LOCK=""
REMOTE_LOCK_DIR=""
REMOTE_LOCK_HELD=false

# SSH multiplexing: reuse a single connection for all locking/health-check calls.
# ControlPersist=60s keeps the master alive 60s after the last client exits.
SSH_CTL="$FLAKE_DIR/tmp/deploy-ssh-%r@%h:%p"
SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=$SSH_CTL" -o "ControlPersist=60s")

cleanup() {
  if [[ "$REMOTE_LOCK_HELD" == true ]]; then
    ssh "${SSH_OPTS[@]}" "$TARGET" "rm -rf '$REMOTE_LOCK_DIR'" 2>/dev/null || true
  fi
  # Close the SSH control master socket if one was opened.
  if [[ -n "${TARGET:-}" ]]; then
    ssh "${SSH_OPTS[@]}" -O exit "$TARGET" 2>/dev/null || true
  fi
}
trap cleanup EXIT

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Deploy neurosys NixOS config to the selected deploy node.

Options:
  --node NAME           Deploy flake node (neurosys|ovh, default: neurosys)
  --mode remote         Build on target host via deploy-rs --remote-build (default)
  --mode local          Build locally, deploy remotely
  --target U@H          Override SSH target (default by node)
  --first-deploy        Disable magic rollback for one-time migration
  --no-magic-rollback   Disable magic rollback for this deploy
  --update-parts        Pull latest parts flake input before building
  --skip-update         No-op (skipping parts update is now the default)
  --help                Show this help

Examples:
  ./scripts/deploy.sh                              # Deploy neurosys (remote build, skip parts update)
  ./scripts/deploy.sh --update-parts               # Deploy and pull latest parts first
  ./scripts/deploy.sh --node ovh                  # Deploy production node (ovh)
  ./scripts/deploy.sh --mode local                # Local build (fallback if server unreachable)
  ./scripts/deploy.sh --first-deploy               # First migration deploy from nixos-rebuild
  ./scripts/deploy.sh --no-magic-rollback          # Intentional networking change deploy
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
    --update-parts)
      SKIP_UPDATE=false
      shift
      ;;
    --skip-update)
      # no-op: parts update is skipped by default; use --update-parts to enable
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

# SAFETY GUARD: All deploys MUST come from the private overlay.
# @decision DEPLOY-02: Both neurosys and ovh run the private overlay config.
#   The public flake's nixosConfigurations have placeholder SSH keys, no real
#   users (dev instead of dangirsh), and no private services (nginx, parts,
#   openclaw, HA, etc.). Deploying from the public repo to EITHER host strips
#   all private config and can LOCK YOU OUT.
#
# Detection: the private overlay has `neurosys.url` as a flake input; the
# public repo does not. This is a reliable self-detection marker.
if ! grep -q 'neurosys\.url' "$FLAKE_DIR/flake.nix" 2>/dev/null; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  BLOCKED: Deploy refused from public repo                      ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Both hosts (neurosys + ovh) run the PRIVATE overlay config."
  echo "  Deploying from the public repo strips private services, users,"
  echo "  and SSH keys — potentially locking you out."
  echo ""
  echo "  Always deploy from the PRIVATE overlay:"
  echo ""
  echo "    cd /data/projects/private-neurosys"
  echo "    ./scripts/deploy.sh [--node neurosys|ovh]"
  echo ""
  exit 1
fi

if [[ "$TARGET_SET" == false ]]; then
  if [[ "$NODE" == "ovh" ]]; then
    TARGET="root@neurosys-prod"
  else
    TARGET="root@neurosys"
  fi
fi

# --- Node-specific service health checks ---
if [[ "$NODE" == "neurosys" ]]; then  # parts-tools parts-agent postgresql claw-swap-app
  SYSTEMD_SERVICES=("parts-tools" "parts-agent" "postgresql" "claw-swap-app")
elif [[ "$NODE" == "ovh" ]]; then  # prometheus syncthing tailscaled
  SYSTEMD_SERVICES=("prometheus" "syncthing" "tailscaled")
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

if ! ssh "${SSH_OPTS[@]}" "$TARGET" "mkdir '$REMOTE_LOCK_DIR' 2>/dev/null"; then
  echo "ERROR: Deploy already in progress on the remote server."
  echo ""
  echo "Lock info:"
  ssh "${SSH_OPTS[@]}" "$TARGET" "cat '$REMOTE_LOCK_DIR/info.txt' 2>/dev/null" || echo "  (could not read lock metadata)"
  echo ""
  echo "If the previous deploy crashed, remove the lock manually:"
  echo "  ssh $TARGET rm -rf $REMOTE_LOCK_DIR"
  exit 1
fi
REMOTE_LOCK_HELD=true
printf '%s\n' "$LOCK_INFO" | ssh "${SSH_OPTS[@]}" "$TARGET" "cat > '$REMOTE_LOCK_DIR/info.txt'" 2>/dev/null || true

# --- Update parts input ---
if [[ "$SKIP_UPDATE" == false && "$NODE" == "neurosys" ]]; then
  echo "==> Updating parts flake input..."
  nix flake update parts --flake "$FLAKE_DIR"
elif [[ "$SKIP_UPDATE" == false ]]; then
  echo "==> Skipping parts update for node '$NODE' (Contabo-only)."
fi

PARTS_REV_SHORT=""
if [[ "$NODE" == "neurosys" ]]; then
  PARTS_REV=$(nix flake metadata "$FLAKE_DIR" --json 2>/dev/null | jq -r '.locks.nodes.parts.locked.rev // "unknown"')
  PARTS_REV_SHORT="${PARTS_REV:0:7}"
  echo "==> Parts revision: $PARTS_REV_SHORT"
fi

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
    if ! ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl is-active --quiet ${s}.service" 2>/dev/null; then
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
  if [[ -n "${PARTS_REV_SHORT:-}" ]]; then
    echo "Parts revision: $PARTS_REV_SHORT"
  fi
  echo "Duration: $((DURATION / 60))m $((DURATION % 60))s"
  echo ""
  echo "Service status:"
  for s in "${SYSTEMD_SERVICES[@]}"; do
    STATUS=$(ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl is-active ${s}.service" 2>/dev/null || echo "unknown")
    echo "  ${s}: ${STATUS}"
  done
  echo ""

  # --- Push system closure to Cachix (Contabo-only) ---
  if [[ "$NODE" == "neurosys" ]]; then
    echo "==> Pushing system closure to dan-testing.cachix.org..."
    if ssh "${SSH_OPTS[@]}" "$TARGET" 'command -v cachix &>/dev/null' 2>/dev/null; then
      ssh "${SSH_OPTS[@]}" "$TARGET" \
        'CACHIX_AUTH_TOKEN=$(cat /run/secrets/cachix-auth-token) \
         nix path-info --recursive /nix/var/nix/profiles/system \
         | cachix push dan-testing' \
        && echo "==> Cachix push complete." \
        || echo "WARNING: Cachix push failed (non-fatal)."
    else
      echo "  cachix not yet in PATH — will push on next deploy after this one installs it."
    fi
    echo ""
  fi

  if [[ "$SKIP_UPDATE" == false && -n "${PARTS_REV_SHORT:-}" ]]; then
    echo "NOTE: flake.lock was updated. Remember to commit when ready:"
    echo "  git add flake.lock && git commit -m \"chore: update parts input to $PARTS_REV_SHORT\""
  fi
else
  echo "=== Deploy FAILED ==="
  echo "Services not active after 30s:"
  for s in "${SYSTEMD_SERVICES[@]}"; do
    if ! ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl is-active --quiet ${s}.service" 2>/dev/null; then
      echo "  - ${s}.service"
    fi
  done
  echo ""
  echo "All service status:"
  for s in "${SYSTEMD_SERVICES[@]}"; do
    STATUS=$(ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl is-active ${s}.service" 2>/dev/null || echo "unknown")
    echo "  ${s}: ${STATUS}"
  done
  echo ""
  echo "Connectivity failures auto-rollback with deploy-rs magic rollback."
  echo "For non-connectivity issues (for example containers failing after deploy), use manual rollback:"
  echo "  ssh $TARGET nixos-rebuild switch --rollback"
  exit 1
fi
