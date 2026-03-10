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
DEPLOY_COMPLETED=false
PREV_SYSTEM=""
WATCHDOG_ACTIVE=false
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
Usage: $(basename "$0") [OPTIONS]

Deploy neurosys NixOS config to the selected deploy node.

Options:
  --node NAME           Deploy flake node (neurosys|ovh|all, default: neurosys)
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
  ./scripts/deploy.sh --node ovh                  # Deploy OVH dev node only
  ./scripts/deploy.sh --node all                  # Deploy BOTH nodes in parallel
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

if [[ "$NODE" != "neurosys" && "$NODE" != "ovh" && "$NODE" != "all" ]]; then
  echo "Error: --node must be 'neurosys', 'ovh', or 'all', got '$NODE'"
  exit 1
fi

# --- Parallel deploy: --node all spawns independent processes ---
if [[ "$NODE" == "all" ]]; then
  echo "==> Deploying ALL nodes in parallel..."
  PIDS=()
  LOGS=()
  for n in neurosys ovh; do
    LOG="$FLAKE_DIR/tmp/deploy-${n}.log"
    LOGS+=("$LOG")
    # Forward all flags except --node
    EXTRA_ARGS=()
    [[ "$MODE" != "remote" ]] && EXTRA_ARGS+=(--mode "$MODE")
    [[ "$FIRST_DEPLOY" == true ]] && EXTRA_ARGS+=(--first-deploy)
    [[ "$NO_MAGIC_ROLLBACK" == true ]] && EXTRA_ARGS+=(--no-magic-rollback)
    [[ "$SKIP_UPDATE" == false ]] && EXTRA_ARGS+=(--update-parts)
    "$0" --node "$n" "${EXTRA_ARGS[@]}" >"$LOG" 2>&1 &
    PIDS+=($!)
    echo "  Started $n deploy (PID $!, log: $LOG)"
  done
  echo ""
  FAILED_NODES=()
  for i in "${!PIDS[@]}"; do
    n=$( [[ $i -eq 0 ]] && echo "neurosys" || echo "ovh" )
    if wait "${PIDS[$i]}"; then
      echo "  ✓ $n deploy succeeded"
    else
      echo "  ✗ $n deploy FAILED (see ${LOGS[$i]})"
      FAILED_NODES+=("$n")
    fi
  done
  echo ""
  if [[ ${#FAILED_NODES[@]} -eq 0 ]]; then
    echo "=== All deploys SUCCESS ==="
  else
    echo "=== Deploy FAILED for: ${FAILED_NODES[*]} ==="
    echo "Review logs:"
    for n in "${FAILED_NODES[@]}"; do
      echo "  $FLAKE_DIR/tmp/deploy-${n}.log"
    done
    exit 1
  fi
  exit 0
fi

# Public IPs for post-deploy connectivity verification (independent of Tailscale).
case "$NODE" in
  neurosys) PUBLIC_IP="161.97.74.121" ;;
  ovh) PUBLIC_IP="135.125.196.143" ;;
esac

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
    TARGET="root@neurosys-dev"
  else
    TARGET="root@neurosys"
  fi
fi

# --- Node-specific service health checks ---
if [[ "$NODE" == "neurosys" ]]; then  # parts postgresql claw-swap-app
  SYSTEMD_SERVICES=("parts" "postgresql" "claw-swap-app")
elif [[ "$NODE" == "ovh" ]]; then  # syncthing tailscaled secret-proxy-dev
  SYSTEMD_SERVICES=("syncthing" "tailscaled" "secret-proxy-dev")
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

# --- Pre-deploy: safety checks when magic rollback is disabled ---
# @decision DEPLOY-03: When magic rollback is off, schedule a self-managed watchdog process on the
# server that auto-reverts to the previous NixOS generation after 5 minutes. The watchdog runs as a
# nohup process (survives systemd reload during activation). deploy.sh cancels it after verifying
# remote access post-deploy. If SSH breaks, the watchdog fires and restores access automatically.
if [[ "$FIRST_DEPLOY" == true || "$NO_MAGIC_ROLLBACK" == true ]]; then
  echo "==> Magic rollback disabled — running pre-deploy safety checks..."

  # Evaluate the target config to trigger NixOS remote-access assertions
  echo "==> Evaluating $NODE config (remote access assertions)..."
  if ! nix eval "$FLAKE_DIR#nixosConfigurations.$NODE.config.system.build.toplevel" --raw >/dev/null 2>&1; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║  BLOCKED: Config evaluation failed                             ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  NixOS assertions failed for node '$NODE'."
    echo "  Cannot deploy without magic rollback when assertions fail."
    echo "  Run for details:"
    echo "    nix eval .#nixosConfigurations.$NODE.config.system.build.toplevel"
    exit 1
  fi
  echo "==> Config assertions passed."

  # Save current system path for watchdog rollback
  PREV_SYSTEM=$(ssh "${SSH_OPTS[@]}" "$TARGET" "readlink -f /nix/var/nix/profiles/system" 2>/dev/null)
  if [[ -z "$PREV_SYSTEM" ]]; then
    echo "ERROR: Cannot read current system generation — cannot proceed without magic rollback."
    exit 1
  fi
  echo "==> Previous system: $PREV_SYSTEM"

  # Schedule watchdog: auto-rollback in 5 minutes if not cancelled.
  # @decision DEPLOY-05: Uses systemd-run transient timer instead of nohup bash.
  # nohup processes are killed by systemd cgroup cleanup when sshd restarts during
  # activation (deploy-rs issue #153). systemd-run creates an independent unit that
  # survives sshd restarts, cgroup kills, and session cleanup.
  echo "==> Scheduling rollback watchdog (5 min timeout via systemd-run)..."
  if ssh "${SSH_OPTS[@]}" "$TARGET" \
    "systemd-run --on-active=300 --timer-property=AccuracySec=5s \
      --unit=deploy-watchdog --description='Deploy rollback watchdog (300s)' -- \
      /bin/bash -c '$PREV_SYSTEM/bin/switch-to-configuration switch && \
        nix-env -p /nix/var/nix/profiles/system --set $PREV_SYSTEM && \
        echo \"\$(date -u): WATCHDOG FIRED -- rolled back to $PREV_SYSTEM\" >> /tmp/deploy-watchdog.log'" \
    2>/dev/null; then
    WATCHDOG_ACTIVE=true
    echo "==> Watchdog scheduled — auto-rollback in 5 min if not cancelled."
  else
    echo "WARNING: Failed to schedule watchdog — proceeding without rollback safety net."
  fi
fi

# --- Belt-and-suspenders watchdog for magic-rollback deploys ---
# @decision DEPLOY-06: Even with magic rollback enabled, schedule a longer watchdog (10 min)
# as a safety net. Magic rollback can fail if activate-rs is killed by cgroup cleanup
# (deploy-rs issue #153). The 600s timeout is well beyond the 120s confirm timeout,
# so it only fires if magic rollback itself failed.
if [[ "$WATCHDOG_ACTIVE" != true && "$FIRST_DEPLOY" != true ]]; then
  PREV_SYSTEM=$(ssh "${SSH_OPTS[@]}" "$TARGET" "readlink -f /nix/var/nix/profiles/system" 2>/dev/null || true)
  if [[ -n "$PREV_SYSTEM" ]]; then
    if ssh "${SSH_OPTS[@]}" "$TARGET" \
      "systemd-run --on-active=600 --timer-property=AccuracySec=5s \
        --unit=deploy-watchdog --description='Deploy rollback watchdog (600s, belt-and-suspenders)' -- \
        /bin/bash -c '$PREV_SYSTEM/bin/switch-to-configuration switch && \
          nix-env -p /nix/var/nix/profiles/system --set $PREV_SYSTEM && \
          echo \"\$(date -u): BELT-AND-SUSPENDERS WATCHDOG FIRED -- rolled back to $PREV_SYSTEM\" >> /tmp/deploy-watchdog.log'" \
      2>/dev/null; then
      WATCHDOG_ACTIVE=true
      echo "==> Belt-and-suspenders watchdog scheduled (10 min)."
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
DEPLOY_COMPLETED=true

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
if ssh -o ConnectTimeout=15 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ControlPath=none \
    "root@$PUBLIC_IP" "systemctl is-active --quiet sshd.service" 2>/dev/null; then
  echo "  Public IP ($PUBLIC_IP): SSH + sshd OK"
else
  echo "  Public IP ($PUBLIC_IP): UNREACHABLE or sshd down"
  REMOTE_ACCESS_OK=false
fi

# Handle watchdog based on remote access results
if [[ "$WATCHDOG_ACTIVE" == true ]]; then
  if [[ "$REMOTE_ACCESS_OK" == true ]]; then
    echo "==> Remote access verified — cancelling rollback watchdog..."
    ssh "${SSH_OPTS[@]}" "$TARGET" "systemctl stop deploy-watchdog.timer deploy-watchdog.service 2>/dev/null" || \
      ssh -o ConnectTimeout=10 -o BatchMode=yes -o ControlPath=none "root@$PUBLIC_IP" \
        "systemctl stop deploy-watchdog.timer deploy-watchdog.service 2>/dev/null" || true
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
    echo "║    ssh root@$PUBLIC_IP systemctl stop deploy-watchdog.timer    ║"
    echo "║                                                                ║"
    echo "║  To rollback NOW:                                              ║"
    echo "║    ssh root@$PUBLIC_IP $PREV_SYSTEM/bin/switch-to-configuration switch"
    echo "╚══════════════════════════════════════════════════════════════════╝"
  fi
elif [[ "$REMOTE_ACCESS_OK" != true ]]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  WARNING: Remote access issues detected!                       ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  deploy-rs magic rollback should catch SSH failures, but       ║"
  echo "║  Tailscale may be down while public SSH still works.           ║"
  echo "║  Manual rollback if needed:                                    ║"
  echo "║    ssh root@$PUBLIC_IP nixos-rebuild switch --rollback"
  echo "╚══════════════════════════════════════════════════════════════════╝"
fi

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
