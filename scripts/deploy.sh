#!/usr/bin/env bash
# shellcheck disable=SC2029
# scripts/deploy.sh — Deploy a tsurf NixOS flake node via deploy-rs
#
# Modes:
#   --mode remote  (default) Build on target host via deploy-rs --remote-build
#   --mode local   Build locally, deploy remotely via deploy-rs
#   --mode remote-detached
#                  Delegate to scripts/deploy-detached.sh
#
# Flags:
#   --node NAME         Flake node to deploy (required)
#   --target USER@HOST  Override deploy, lock, and status SSH target (default: root@<node>)
#   --first-deploy      Disable magic rollback for initial adoption
#   --magic-rollback    Enable deploy-rs magic rollback with 300s confirm timeout (default)
#   --no-magic-rollback Disable deploy-rs magic rollback for this deploy
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FLAKE_DIR="${TSURF_DEPLOY_FLAKE_DIR:-$(resolve_flake_dir "${BASH_SOURCE[0]}")}"
NODE=""
TARGET=""
TARGET_SET=false
MODE="${TSURF_DEPLOY_MODE:-remote}"
FAST_MODE=false
FIRST_DEPLOY=false
MAGIC_ROLLBACK=true
SECONDS=0

# SSH multiplexing: reuse a single connection for locking/health-check calls.
SSH_CTL="${TSURF_DEPLOY_SSH_CTL:-$FLAKE_DIR/tmp/ssh-%C}"
SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=$SSH_CTL" -o "ControlPersist=60s")
SSH_EXTRA_OPTS=()
if [[ -n "${TSURF_DEPLOY_SSH_OPTS:-}" ]]; then
  read -r -a SSH_EXTRA_OPTS <<<"${TSURF_DEPLOY_SSH_OPTS}"
  SSH_OPTS+=("${SSH_EXTRA_OPTS[@]}")
fi

ssh_retry() {
  local attempts="${TSURF_DEPLOY_SSH_RETRIES:-5}"
  local delay="${TSURF_DEPLOY_SSH_RETRY_DELAY:-5}"
  local status=0
  local i

  for ((i = 1; i <= attempts; i++)); do
    if ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; then
      return 0
    fi
    status=$?
    if ((i < attempts)); then
      echo "SSH attempt ${i}/${attempts} failed; retrying in ${delay}s..." >&2
      sleep "${delay}"
    fi
  done

  return "${status}"
}

parse_ssh_target() {
  local raw="$1"
  local user host

  if [[ "$raw" == *@* ]]; then
    user="${raw%@*}"
    host="${raw#*@}"
  else
    user="root"
    host="$raw"
  fi

  if [[ -z "$user" || -z "$host" ]]; then
    echo "ERROR: invalid SSH target '$raw'" >&2
    return 1
  fi

  printf '%s\t%s\n' "$user" "$host"
}

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
  --mode remote-detached
                        Build and activate on target under systemd
  --mode local          Build locally, deploy remotely
  --target U@H          Override deploy and SSH target (default: root@<node>)
  --first-deploy        Disable magic rollback for first adoption
  --fast                Local build, single evaluation (no --remote-build)
  --magic-rollback      Enable deploy-rs magic rollback (default, 300s confirm timeout)
  --no-magic-rollback   Disable deploy-rs magic rollback for this deploy
  --help                Show this help

Examples:
  ./scripts/deploy.sh --node myhost                     # Deploy (remote build)
  ./scripts/deploy.sh --node myhost --fast              # Fast: local build
  ./scripts/deploy.sh --node myhost --mode local        # Local build fallback
  ./scripts/deploy.sh --node myhost --mode remote-detached # Survive SSH drops
  ./scripts/deploy.sh --node myhost --first-deploy      # First deploy
  ./scripts/deploy.sh --node myhost --magic-rollback    # Magic rollback (300s)
  ./scripts/deploy.sh --target root@1.2.3.4 --node myhost  # Override deploy host
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
    --no-magic-rollback) MAGIC_ROLLBACK=false; shift ;;
    --help)        usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

mkdir -p "$FLAKE_DIR/tmp"

if [[ "$MODE" != "local" && "$MODE" != "remote" && "$MODE" != "remote-detached" ]]; then
  echo "Error: --mode must be 'local', 'remote', or 'remote-detached', got '$MODE'"
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
IFS=$'\t' read -r TARGET_SSH_USER TARGET_HOSTNAME < <(parse_ssh_target "$TARGET")

if [[ "$FAST_MODE" == "true" ]]; then
  MODE="local"
  echo "==> FAST MODE: local build, single evaluation, no --remote-build"
fi

if [[ "$MODE" == "remote-detached" ]]; then
  DETACHED_SCRIPT="${TSURF_DEPLOY_DETACHED_SCRIPT:-$SCRIPT_DIR/deploy-detached.sh}"
  DETACHED_ARGS=(--flake-dir "$FLAKE_DIR" --node "$NODE" --target "$TARGET")
  if [[ "$FIRST_DEPLOY" == true ]]; then
    DETACHED_ARGS+=(--first-deploy)
  fi
  if [[ "$MAGIC_ROLLBACK" == true ]]; then
    DETACHED_ARGS+=(--magic-rollback)
  else
    DETACHED_ARGS+=(--no-magic-rollback)
  fi

  if [[ ! -x "$DETACHED_SCRIPT" ]]; then
    echo "ERROR: detached deploy helper is missing or not executable: $DETACHED_SCRIPT" >&2
    exit 1
  fi

  exec "$DETACHED_SCRIPT" "${DETACHED_ARGS[@]}"
fi

# --- Remote lock ---
LOCK_KEY="${TARGET_HOSTNAME}"
LOCK_KEY="${LOCK_KEY//[^A-Za-z0-9._-]/-}"
REMOTE_LOCK_DIR="/var/lock/deploy-${LOCK_KEY}.lock"
GIT_SHA=$(git -C "$FLAKE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
LOCK_INFO="holder=$(whoami)@$(hostname)
pid=$$
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
sha=$GIT_SHA"

if ! ssh_retry "mkdir '$REMOTE_LOCK_DIR' 2>/dev/null"; then
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
  echo "==> Overriding deploy-rs hostname to ${TARGET_HOSTNAME} and SSH user to ${TARGET_SSH_USER}."
fi

DEPLOY_ARGS=(
  "$FLAKE_DIR#$NODE"
  --skip-checks
  --fast-connection true
)
if [[ "$TARGET_SET" == true ]]; then
  DEPLOY_ARGS+=(--hostname "${TARGET_HOSTNAME}" --ssh-user "${TARGET_SSH_USER}")
fi
if (( ${#SSH_EXTRA_OPTS[@]} > 0 )); then
  DEPLOY_ARGS+=(--ssh-opts "${TSURF_DEPLOY_SSH_OPTS}")
fi
if [[ "$MAGIC_ROLLBACK" == true && "$FIRST_DEPLOY" != true ]]; then
  DEPLOY_ARGS+=(--confirm-timeout 300)
  echo "==> Magic rollback enabled (300s confirm timeout)."
else
  DEPLOY_ARGS+=(--magic-rollback false)
  if [[ "$FIRST_DEPLOY" == true ]]; then
    echo "==> First deploy mode: magic rollback disabled."
  fi
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
if [[ -n "${TSURF_DEPLOY_VERIFY_SERVICES:-}" ]]; then
  read -r -a SYSTEMD_SERVICES <<<"${TSURF_DEPLOY_VERIFY_SERVICES}"
fi
echo "==> Verifying services..."
FAILED=0
for s in "${SYSTEMD_SERVICES[@]}"; do
  STATUS=$(ssh_retry "systemctl is-active ${s}.service" 2>/dev/null || echo "unknown")
  echo "  ${s}: ${STATUS}"
  if [[ "$STATUS" != "active" ]]; then
    FAILED=1
  fi
done

# --- SSH connectivity check ---
# @decision DEPLOY-04: Use non-multiplexed connections to test real SSH paths.
echo "==> Verifying remote access..."
REMOTE_ACCESS_SSH_OPTS=(-o BatchMode=yes -o ControlPath=none)
if (( ${#SSH_EXTRA_OPTS[@]} == 0 )); then
  REMOTE_ACCESS_SSH_OPTS+=(-o ConnectTimeout=15)
else
  REMOTE_ACCESS_SSH_OPTS+=("${SSH_EXTRA_OPTS[@]}")
fi
if ssh "${REMOTE_ACCESS_SSH_OPTS[@]}" "$TARGET" \
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
