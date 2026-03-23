#!/usr/bin/env bash
# shellcheck disable=SC2029
# scripts/deploy.sh — Deploy a tsurf NixOS flake node
#
# Modes:
#   --mode remote  (default) Build on target host via deploy-rs --remote-build
#   --mode local   Build locally, deploy remotely via deploy-rs
#
# Flags:
#   --node NAME         Flake node to deploy (required)
#   --target USER@HOST  Override SSH target (default: root@<node>)
#   --first-deploy  Disable magic rollback once for migration from nixos-rebuild
#   --magic-rollback  Enable deploy-rs magic rollback with 300s confirm timeout
#   --help         Print usage
#
# @decision Manual deploy only — no CI/CD. NixOS handles incrementality.
# @decision Full deploy-rs system activation every deploy — no partial/container-only.
# @decision Magic rollback opt-in via --magic-rollback (300s confirm timeout).
# @decision Single-pass service health check after deploy.
# @decision No auto-commit of flake.lock — print reminder instead.
# @decision DEPLOY-114-01: No repo-controlled post-deploy hooks — require explicit --post-hook.
# @decision Remote build default (DEPLOY-01): --mode remote is faster on beefy servers.
#   Use --mode local for first deploys or when server is unreachable.
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
POST_HOOK=""
PUBLIC_IP=""
SECONDS=0

SYSTEMD_SERVICES=()
DEPLOY_COMPLETED=false
PREV_SYSTEM=""
WATCHDOG_ACTIVE=false
DEPLOY_SUMMARY=""

# Write deploy status JSON to remote host for dashboard consumption.
# Called from success, failure, and rollback paths.
write_deploy_status() {
  local status="$1"
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local json
  if command -v python3 &>/dev/null; then
    json=$(python3 -c "
import json,sys
print(json.dumps({
    'status': sys.argv[1],
    'timestamp': sys.argv[2],
    'sha': sys.argv[3],
    'node': sys.argv[4],
    'duration_seconds': int(sys.argv[5]),
    'summary': sys.argv[6]
}, separators=(',', ':')))" "$status" "$ts" "$GIT_SHA" "$NODE" "$SECONDS" "$DEPLOY_SUMMARY")
  else
    # Fallback: basic escaping for git log output
    local esc
    esc=$(printf '%s' "$DEPLOY_SUMMARY" | sed 's/\\/\\\\/g;s/"/\\"/g' | tr '\n' '|' | sed 's/|/\\n/g;s/\\n$//')
    json=$(printf '{"status":"%s","timestamp":"%s","sha":"%s","node":"%s","duration_seconds":%d,"summary":"%s"}' \
      "$status" "$ts" "$GIT_SHA" "$NODE" "$SECONDS" "$esc")
  fi
  printf '%s\n' "$json" | ssh "${SSH_OPTS[@]}" "$TARGET" \
    "mkdir -p /var/lib/deploy-status && cat > /var/lib/deploy-status/status.json" 2>/dev/null || true
}

# @decision Remote mkdir deploy locking (prevents concurrent deploys from any machine).
REMOTE_LOCK_DIR=""
REMOTE_LOCK_HELD=false

# SSH multiplexing: reuse a single connection for all locking/health-check calls.
# ControlPersist=60s keeps the master alive 60s after the last client exits.
SSH_CTL="$FLAKE_DIR/tmp/deploy-ssh-%r@%h:%p"
SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=$SSH_CTL" -o "ControlPersist=60s")

cleanup() {
  # Cancel watchdog if deploy hasn't completed (early exit / Ctrl+C before activation)
  if [[ "$WATCHDOG_ACTIVE" == true && "$DEPLOY_COMPLETED" != true ]]; then
    echo "==> Cancelling rollback watchdog (deploy did not complete)..."
    ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl stop deploy-watchdog.timer deploy-watchdog.service 2>/dev/null" || true
  fi
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
  --public-ip IP        Public IP for post-deploy connectivity check (optional)
  --post-hook PATH      Run script at absolute PATH after successful deploy (subprocess, not sourced)
  --update-inputs       Pull latest flake inputs before building
  --help                Show this help

Examples:
  ./scripts/deploy.sh --node myhost                # Deploy myhost (remote build)
  ./scripts/deploy.sh --node myhost --fast         # Fast mode: local build, single eval
  ./scripts/deploy.sh --node myhost --update-inputs  # Deploy and update flake inputs first
  ./scripts/deploy.sh --node myhost --mode local   # Local build (fallback if server unreachable)
  ./scripts/deploy.sh --node myhost --first-deploy # First migration deploy from nixos-rebuild
  ./scripts/deploy.sh --node myhost --magic-rollback  # Enable magic rollback with 300s confirm
  ./scripts/deploy.sh --target root@1.2.3.4 --node myhost  # Explicit SSH target override
USAGE
}

if [[ "${TSURF_DEPLOY_LIB_ONLY:-0}" == "1" && "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

mkdir -p "$FLAKE_DIR/tmp"

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
    --fast)
      FAST_MODE=true
      shift
      ;;
    --first-deploy)
      FIRST_DEPLOY=true
      shift
      ;;
    --magic-rollback)
      MAGIC_ROLLBACK=true
      shift
      ;;
    --no-magic-rollback)
      # Deprecated alias (magic rollback is now off by default)
      shift
      ;;
    --update-inputs)
      shift
      ;;
    --post-hook)
      POST_HOOK="$2"
      shift 2
      ;;
    --public-ip)
      PUBLIC_IP="$2"
      shift 2
      ;;
    --skip-update)
      # no-op: input update is skipped by default; use --update-inputs to enable
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

if [[ -z "$NODE" ]]; then
  echo "Error: --node is required"
  usage
  exit 1
fi

if [[ -n "$POST_HOOK" ]]; then
  if [[ "$POST_HOOK" != /* ]]; then
    echo "Error: --post-hook must be an absolute path, got '$POST_HOOK'"
    exit 1
  fi
  if [[ ! -f "$POST_HOOK" ]]; then
    echo "Error: --post-hook path does not exist: $POST_HOOK"
    exit 1
  fi
fi

# SAFETY GUARD: All deploys MUST come from the private overlay.
# @decision DEPLOY-02: Real hosts run the private overlay config.
#   The public flake's nixosConfigurations have placeholder SSH keys, no real
#   users (dev instead of your-user), and no private services. Deploying from
#   the public repo to EITHER host strips
#   all private config and can LOCK YOU OUT.
#
# Detection: the private overlay has `tsurf.url` as a flake input; the
# public repo does not. This is a reliable self-detection marker.
if ! grep -q 'tsurf\.url' "$FLAKE_DIR/flake.nix" 2>/dev/null; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  BLOCKED: Deploy refused from public repo                      ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  All real hosts run the PRIVATE overlay config."
  echo "  Deploying from the public repo strips private services, users,"
  echo "  and SSH keys — potentially locking you out."
  echo ""
  echo "  Always deploy from your PRIVATE overlay:"
  echo ""
  echo "    cd /path/to/private-overlay"
  echo "    ./scripts/deploy.sh --node <your-host>"
  echo ""
  exit 1
fi

if [[ "$TARGET_SET" == false ]]; then
  TARGET="root@${NODE}"
fi

# --- Service health checks ---
# Base services checked on all nodes. Private overlay can extend this list.
SYSTEMD_SERVICES=("tailscaled" "sshd")

REMOTE_LOCK_DIR="/var/lock/deploy-${NODE}.lock"

# --- Remote lock (prevent concurrent deploys from any machine) ---
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

# --- Compute deploy summary from git log ---
DEPLOY_STATUS_JSON="$(ssh "${SSH_OPTS[@]}" "$TARGET" \
  "cat /var/lib/deploy-status/status.json 2>/dev/null" 2>/dev/null || true)"
PREV_DEPLOY_SHA=""
if [[ -n "$DEPLOY_STATUS_JSON" ]]; then
  if command -v python3 &>/dev/null; then
    PREV_DEPLOY_SHA="$(python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('sha', ''))
except Exception:
    print('')
" <<< "$DEPLOY_STATUS_JSON")"
  else
    PREV_DEPLOY_SHA="$(printf '%s\n' "$DEPLOY_STATUS_JSON" \
      | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1)"
  fi
fi

if [[ -n "$PREV_DEPLOY_SHA" ]] && git -C "$FLAKE_DIR" cat-file -t "$PREV_DEPLOY_SHA" &>/dev/null; then
  DEPLOY_SUMMARY=$(git -C "$FLAKE_DIR" log --oneline "${PREV_DEPLOY_SHA}..HEAD" -- 2>/dev/null | head -5)
else
  DEPLOY_SUMMARY=$(git -C "$FLAKE_DIR" log --oneline -1 HEAD 2>/dev/null || echo "unknown")
fi

# Private overlay: add flake input update logic here if needed.

# --- Pre-deploy: schedule rollback watchdog ---
# @decision DEPLOY-03: Always schedule a 5-min watchdog via systemd-run that auto-reverts
# to the previous NixOS generation. deploy.sh cancels it after verifying SSH post-deploy.
# @decision DEPLOY-05: Uses systemd-run transient timer (survives sshd restarts and cgroup
# cleanup during activation — deploy-rs issue #153).
if [[ "$FIRST_DEPLOY" != true ]]; then
  PREV_SYSTEM=$(ssh "${SSH_OPTS[@]}" "$TARGET" "readlink -f /nix/var/nix/profiles/system" 2>/dev/null)
  if [[ -z "$PREV_SYSTEM" ]]; then
    echo "WARNING: Cannot read current system generation — no watchdog safety net."
  else
    echo "==> Previous system: $PREV_SYSTEM"
    echo "==> Scheduling rollback watchdog (5 min timeout via systemd-run)..."
    if ssh "${SSH_OPTS[@]}" "$TARGET" \
      "systemd-run --on-active=300 --timer-property=AccuracySec=5s \
        --unit=deploy-watchdog --description='Deploy rollback watchdog (300s)' -- \
        /bin/bash -c '$PREV_SYSTEM/bin/switch-to-configuration switch && \
          nix-env -p /nix/var/nix/profiles/system --set $PREV_SYSTEM && \
          mkdir -p /var/lib/deploy-status && \
          echo \"\$(date -u): WATCHDOG FIRED -- rolled back to $PREV_SYSTEM\" >> /var/lib/deploy-status/watchdog.log'" \
      2>/dev/null; then
      WATCHDOG_ACTIVE=true
      echo "==> Watchdog scheduled — auto-rollback in 5 min if not cancelled."
    else
      echo "WARNING: Failed to schedule watchdog — proceeding without rollback safety net."
    fi
  fi
fi

# --- Build + deploy ---
if [[ "$TARGET_SET" == true ]]; then
  echo "WARNING: --target affects SSH locking/health checks only."
  echo "         deploy-rs deploy target is flake node '$NODE'."
fi

DEPLOY_ARGS=(
  "$FLAKE_DIR#$NODE"
  --skip-checks          # Pre-deploy test gate (nix flake check) in MC adapter handles this
  --fast-connection true  # VPS-to-VPS / Tailscale links are stable enough for fast mode
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

# Fast mode overrides MODE to local (single evaluation, no remote-build)
if [[ "$FAST_MODE" == "true" ]]; then
  MODE="local"
  echo "==> FAST MODE: local build, single evaluation, no --remote-build"
fi

DEPLOY_RS_EXIT=0
if [[ "$MODE" == "local" ]]; then
  echo "==> Deploying node '$NODE' to $TARGET with deploy-rs (confirm timeout: 300s)..."
  nix run "$FLAKE_DIR#deploy-rs" -- "${DEPLOY_ARGS[@]}" || DEPLOY_RS_EXIT=$?
else
  echo "==> Deploying node '$NODE' via remote build on $TARGET with deploy-rs..."
  nix run "$FLAKE_DIR#deploy-rs" -- "${DEPLOY_ARGS[@]}" --remote-build || DEPLOY_RS_EXIT=$?
fi

if [[ "$DEPLOY_RS_EXIT" -ne 0 ]]; then
  echo "=== Deploy-rs FAILED (exit $DEPLOY_RS_EXIT) — likely rolled back ==="
  write_deploy_status "rolled-back"
  exit 1
fi
DEPLOY_COMPLETED=true

# --- Verify services (single-pass) ---
echo "==> Verifying services..."
FAILED=0
if ! ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl is-active --quiet ${SYSTEMD_SERVICES[*]}" 2>/dev/null; then
  FAILED=1
  echo "  WARN: Some services not ready"
  ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl --failed --no-legend" 2>/dev/null || true
fi

# --- Post-deploy: verify remote access ---
# @decision DEPLOY-04: After deploy, verify SSH connectivity via both the deploy target (Tailscale)
# and the public IP (fallback). Uses non-multiplexed connections (-o ControlPath=none) to test real
# connectivity, not cached SSH channels from before the deploy.
echo "==> Verifying remote access..."
REMOTE_ACCESS_OK=true

# Fresh SSH to deploy target (non-multiplexed — tests real path, usually Tailscale)
if ssh -o ConnectTimeout=15 -o BatchMode=yes -o ControlPath=none "$TARGET" \
    "systemctl is-active --quiet sshd.service && systemctl is-active --quiet tailscaled.service" 2>/dev/null; then
  echo "  Deploy target ($TARGET): sshd + tailscaled OK"
else
  echo "  Deploy target ($TARGET): UNREACHABLE or critical services down"
  REMOTE_ACCESS_OK=false
fi

# Independent SSH to public IP (separate from Tailscale path)
if [[ -n "$PUBLIC_IP" ]]; then
  if ssh -o ConnectTimeout=15 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ControlPath=none \
      "root@$PUBLIC_IP" "systemctl is-active --quiet sshd.service" 2>/dev/null; then
    echo "  Public IP ($PUBLIC_IP): SSH + sshd OK"
  else
    echo "  Public IP ($PUBLIC_IP): UNREACHABLE or sshd down"
    REMOTE_ACCESS_OK=false
  fi
else
  echo "  Public IP check skipped (no --public-ip provided)"
fi

# Handle watchdog based on remote access results
if [[ "$WATCHDOG_ACTIVE" == true ]]; then
  if [[ "$REMOTE_ACCESS_OK" == true ]]; then
    echo "==> Remote access verified — cancelling rollback watchdog..."
    if ! ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl stop deploy-watchdog.timer deploy-watchdog.service 2>/dev/null"; then
      if [[ -n "$PUBLIC_IP" ]]; then
        ssh -o ConnectTimeout=10 -o BatchMode=yes -o ControlPath=none "root@$PUBLIC_IP" \
          "systemctl stop deploy-watchdog.timer deploy-watchdog.service 2>/dev/null" || true
      fi
    fi
    WATCHDOG_ACTIVE=false
  else
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  REMOTE ACCESS ISSUES DETECTED                                 ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║  Rollback watchdog is active — system will auto-revert in      ║"
    echo "║  ~5 minutes unless cancelled.                                  ║"
    echo "║                                                                ║"
    echo "║  To KEEP the new config (cancel watchdog):                     ║"
    if [[ -n "$PUBLIC_IP" ]]; then
      echo "║    ssh root@$PUBLIC_IP systemctl stop deploy-watchdog.timer    ║"
    else
      echo "║    ssh $TARGET systemctl stop deploy-watchdog.timer            ║"
    fi
    echo "║                                                                ║"
    echo "║  To rollback NOW:                                              ║"
    if [[ -n "$PUBLIC_IP" ]]; then
      echo "║    ssh root@$PUBLIC_IP $PREV_SYSTEM/bin/switch-to-configuration switch"
    else
      echo "║    ssh $TARGET $PREV_SYSTEM/bin/switch-to-configuration switch"
    fi
    echo "╚══════════════════════════════════════════════════════════════════╝"
  fi
elif [[ "$REMOTE_ACCESS_OK" != true ]]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  WARNING: Remote access issues detected!                       ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  deploy-rs magic rollback should catch SSH failures, but       ║"
  echo "║  Tailscale may be down while another SSH path still works.     ║"
  echo "║  Manual rollback if needed:                                    ║"
  if [[ -n "$PUBLIC_IP" ]]; then
    echo "║    ssh root@$PUBLIC_IP nixos-rebuild switch --rollback"
  else
    echo "║    ssh $TARGET nixos-rebuild switch --rollback"
  fi
  echo "╚══════════════════════════════════════════════════════════════════╝"
fi

# --- Report ---
DURATION=$SECONDS
echo ""

if [[ "$FAILED" -eq 0 ]]; then
  echo "=== Deploy SUCCESS ==="
  echo "Duration: $((DURATION / 60))m $((DURATION % 60))s"
  echo ""
  echo "Service status:"
  for s in "${SYSTEMD_SERVICES[@]}"; do
    STATUS=$(ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl is-active ${s}.service" 2>/dev/null || echo "unknown")
    echo "  ${s}: ${STATUS}"
  done
  echo ""

  # --- Post-deploy hook (optional, explicit opt-in via --post-hook) ---
  # @decision DEPLOY-114-01: No repo-controlled post-deploy hooks.
  #   Sourcing repo-controlled scripts is a local code execution vector
  #   (agent edits repo -> operator runs deploy -> arbitrary code runs).
  #   Post-hooks must be an absolute path outside the mutable repo,
  #   executed as a subprocess (not sourced).
  if [[ -n "$POST_HOOK" ]]; then
    echo "==> Running post-deploy hook: $POST_HOOK"
    bash --noprofile --norc "$POST_HOOK"
  fi

  write_deploy_status "success"
else
  echo "=== Deploy FAILED ==="
  echo "Services not active:"
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
  write_deploy_status "failed"

  echo "Connectivity failures auto-rollback with deploy-rs magic rollback."
  echo "For non-connectivity issues (for example containers failing after deploy), use manual rollback:"
  echo "  ssh $TARGET nixos-rebuild switch --rollback"
  exit 1
fi
