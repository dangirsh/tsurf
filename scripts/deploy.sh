#!/usr/bin/env bash
# shellcheck disable=SC2029
# scripts/deploy.sh — Deploy a tsurf NixOS flake node via deploy-rs
#
# Modes:
#   --mode remote  (default) Build on target host via deploy-rs --remote-build
#   --mode local   Build locally, deploy remotely via deploy-rs
#
# Flags:
#   --node NAME         Flake node to deploy (required)
#   --target USER@HOST  Override SSH target for lock/status checks (default: root@<node>)
#   --first-deploy      Disable magic rollback for initial migration
#   --magic-rollback    Enable deploy-rs magic rollback with 300s confirm timeout
#   --help              Print usage
#
# @decision DEPLOY-114-01: Keep deploy.sh intentionally small: no repo-controlled hooks or alternate reachability probes.
set -euo pipefail

resolve_flake_dir() {
  local script_path="$1"
  local candidate
  candidate="$(cd "$(dirname "$script_path")" && pwd -P)"

  while [[ "$candidate" != "/" ]]; do
    if [[ -f "$candidate/flake.nix" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate="$(dirname "$candidate")"
  done

  echo "ERROR: could not find flake.nix above $script_path" >&2
  return 1
}

FLAKE_DIR="$(resolve_flake_dir "${BASH_SOURCE[0]}")"
NODE=""
TARGET=""
TARGET_SET=false
MODE="remote"
FAST_MODE=false
FIRST_DEPLOY=false
MAGIC_ROLLBACK=false
DEPRECATED_FLAGS=()
SECONDS=0

# SSH multiplexing: reuse a single connection for locking/health-check calls.
SSH_CTL="$FLAKE_DIR/tmp/deploy-ssh-%r@%h:%p"
SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=$SSH_CTL" -o "ControlPersist=60s")

# Remote deploy lock (prevents concurrent deploys from any machine).
REMOTE_LOCK_DIR=""
REMOTE_LOCK_HELD=false

cleanup() {
  if [[ "$REMOTE_LOCK_HELD" == true ]]; then
    ssh "${SSH_OPTS[@]}" "$TARGET" "rm -rf '$REMOTE_LOCK_DIR'" 2>/dev/null || true
  fi
  if [[ -n "${TARGET:-}" ]]; then
    ssh "${SSH_OPTS[@]}" -O exit "$TARGET" 2>/dev/null || true
  fi
}
trap cleanup EXIT

usage() {
  cat <<USAGE
Usage: $(basename "$0") --node <NAME> [OPTIONS]

Deploy tsurf NixOS config to the selected deploy node.

Options:
  --node NAME           Flake node to deploy (required)
  --mode remote         Build on target host via deploy-rs --remote-build (default)
  --mode local          Build locally, deploy remotely
  --target U@H          Override SSH target (default: root@<node>)
  --first-deploy        Disable magic rollback for one-time migration
  --fast                Local build, single evaluation (no --remote-build)
  --magic-rollback      Enable deploy-rs magic rollback (300s confirm timeout)
  --update-inputs       Deprecated; update flake inputs explicitly before deploy
  --help                Show this help

Examples:
  ./scripts/deploy.sh --node myhost                     # Deploy (remote build)
  ./scripts/deploy.sh --node myhost --fast              # Fast: local build
  ./scripts/deploy.sh --node myhost --mode local        # Local build fallback
  ./scripts/deploy.sh --node myhost --first-deploy      # First migration deploy
  ./scripts/deploy.sh --node myhost --magic-rollback    # Magic rollback (300s)
  ./scripts/deploy.sh --target root@1.2.3.4 --node myhost  # Explicit SSH target
USAGE
}

if [[ "${TSURF_DEPLOY_LIB_ONLY:-0}" == "1" && "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --node)        NODE="$2";         shift 2 ;;
    --mode)        MODE="$2";         shift 2 ;;
    --target)      TARGET="$2"; TARGET_SET=true; shift 2 ;;
    --fast)        FAST_MODE=true;    shift ;;
    --first-deploy) FIRST_DEPLOY=true; shift ;;
    --magic-rollback) MAGIC_ROLLBACK=true; shift ;;
    --no-magic-rollback) shift ;;  # deprecated no-op
    --update-inputs) DEPRECATED_FLAGS+=("$1"); shift ;;
    --skip-update) DEPRECATED_FLAGS+=("$1"); shift ;;
    --help)        usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if (( ${#DEPRECATED_FLAGS[@]} > 0 )); then
  printf 'Error: %s no longer does anything in deploy.sh.\n' "$(printf '%s ' "${DEPRECATED_FLAGS[@]}" | sed 's/ $//')"
  echo "Update flake inputs explicitly before deploy, for example:"
  echo "  nix flake update"
  exit 1
fi

mkdir -p "$FLAKE_DIR/tmp"

if [[ "$MODE" != "local" && "$MODE" != "remote" ]]; then
  echo "Error: --mode must be 'local' or 'remote', got '$MODE'"
  exit 1
fi

if [[ -z "$NODE" ]]; then
  echo "Error: --node is required"
  usage
  exit 1
fi

# SAFETY GUARD: All deploys MUST come from the private overlay.
# @decision DEPLOY-02: The public flake has no tsurf.url input; detection is reliable.
if ! grep -q 'tsurf\.url' "$FLAKE_DIR/flake.nix" 2>/dev/null; then
  echo ""
  echo "  BLOCKED: Deploy refused from public repo."
  echo ""
  echo "  All real hosts run the PRIVATE overlay config."
  echo "  Deploying from the public repo strips private services, users,"
  echo "  and SSH keys — potentially locking you out."
  echo ""
  echo "  Always deploy from your PRIVATE overlay:"
  echo "    cd /path/to/private-overlay"
  echo "    ./scripts/deploy.sh --node <your-host>"
  echo ""
  exit 1
fi

if [[ "$TARGET_SET" == false ]]; then
  TARGET="root@${NODE}"
fi

# --- Remote lock ---
LOCK_KEY="${TARGET#*@}"
LOCK_KEY="${LOCK_KEY//[^A-Za-z0-9._-]/-}"
REMOTE_LOCK_DIR="/var/lock/deploy-${LOCK_KEY}.lock"
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

# --- Build + deploy ---
if [[ "$TARGET_SET" == true ]]; then
  echo "WARNING: --target affects SSH locking/health checks only."
  echo "         deploy-rs deploy target is flake node '$NODE'."
fi

DEPLOY_ARGS=(
  "$FLAKE_DIR#$NODE"
  --skip-checks
  --fast-connection true
)
if [[ "$MAGIC_ROLLBACK" == true && "$FIRST_DEPLOY" != true ]]; then
  DEPLOY_ARGS+=(--confirm-timeout 300)
  echo "==> Magic rollback enabled (300s confirm timeout)."
else
  DEPLOY_ARGS+=(--magic-rollback false)
  if [[ "$FIRST_DEPLOY" == true ]]; then
    echo "==> First deploy mode: magic rollback disabled for migration."
  fi
fi

if [[ "$FAST_MODE" == "true" ]]; then
  MODE="local"
  echo "==> FAST MODE: local build, single evaluation, no --remote-build"
fi

DEPLOY_RS_EXIT=0
if [[ "$MODE" == "local" ]]; then
  echo "==> Deploying node '$NODE' to $TARGET with deploy-rs..."
  nix run "$FLAKE_DIR#deploy-rs" -- "${DEPLOY_ARGS[@]}" || DEPLOY_RS_EXIT=$?
else
  echo "==> Deploying node '$NODE' via remote build on $TARGET with deploy-rs..."
  nix run "$FLAKE_DIR#deploy-rs" -- "${DEPLOY_ARGS[@]}" --remote-build || DEPLOY_RS_EXIT=$?
fi

if [[ "$DEPLOY_RS_EXIT" -ne 0 ]]; then
  echo "=== Deploy-rs FAILED (exit $DEPLOY_RS_EXIT) ==="
  exit 1
fi

# --- Service verification ---
SYSTEMD_SERVICES=("sshd" "nftables")
echo "==> Verifying services..."
FAILED=0
for s in "${SYSTEMD_SERVICES[@]}"; do
  STATUS=$(ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl is-active ${s}.service" 2>/dev/null || echo "unknown")
  echo "  ${s}: ${STATUS}"
  if [[ "$STATUS" != "active" ]]; then
    FAILED=1
  fi
done

# --- SSH connectivity check ---
# @decision DEPLOY-04: Use non-multiplexed connections to test real SSH paths.
echo "==> Verifying remote access..."
if ssh -o ConnectTimeout=15 -o BatchMode=yes -o ControlPath=none "$TARGET" \
    "systemctl is-active --quiet sshd.service" 2>/dev/null; then
  echo "  Deploy target ($TARGET): SSH OK"
else
  echo "  Deploy target ($TARGET): UNREACHABLE"
  FAILED=1
fi

# --- Result ---
DURATION=$SECONDS
echo ""

if [[ "$FAILED" -eq 0 ]]; then
  echo "=== Deploy SUCCESS ($((DURATION / 60))m $((DURATION % 60))s) ==="
else
  echo "=== Deploy COMPLETED with WARNINGS ==="
  echo ""
  echo "Some services or connectivity checks failed. Manual rollback if needed:"
  echo "  ssh $TARGET nixos-rebuild switch --rollback"
  exit 1
fi
