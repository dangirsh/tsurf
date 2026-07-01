#!/usr/bin/env bash
# shellcheck disable=SC2029
# scripts/deploy.sh — Deploy a tsurf NixOS flake node via deploy-rs
#
# Modes:
#   --mode remote  (default) Build on target host via deploy-rs --remote-build
#   --mode local   Build locally, deploy remotely via deploy-rs
#   --mode remote-detached
#                  Build and activate on target under systemd so SSH drops do not
#                  kill the deploy
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
# Keep the socket path short enough for macOS' Unix socket limit.
SSH_CTL="/tmp/tsurf-deploy-%C"
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

shell_quote() {
  printf '%q' "$1"
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

copy_derivation_to_remote() {
  local drv="$1"
  local attempts="${TSURF_DEPLOY_COPY_RETRIES:-3}"
  local delay="${TSURF_DEPLOY_COPY_RETRY_DELAY:-10}"
  local nix_sshopts="-o BatchMode=yes"
  local status=0
  local i

  if (( ${#SSH_EXTRA_OPTS[@]} > 0 )); then
    nix_sshopts+=" ${SSH_EXTRA_OPTS[*]}"
  fi

  echo "==> Copying activation derivation closure to $TARGET..."
  for ((i = 1; i <= attempts; i++)); do
    if NIX_SSHOPTS="${nix_sshopts}" nix copy --to "ssh://${TARGET}" "$drv"; then
      return 0
    fi
    status=$?
    if ((i < attempts)); then
      echo "nix copy attempt ${i}/${attempts} failed; retrying in ${delay}s..." >&2
      sleep "${delay}"
    fi
  done

  return "${status}"
}

upload_remote_detached_script() {
  local run_path="$1"
  local run_path_q
  run_path_q="$(shell_quote "$run_path")"

  ssh "${SSH_OPTS[@]}" "$TARGET" "cat > ${run_path_q} && chmod 0700 ${run_path_q}" <<'REMOTE_SCRIPT'
#!/run/current-system/sw/bin/bash
set -euo pipefail
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"

state_dir="$1"
drv="$2"
lock_dir="$3"
service_list="${4:-}"
log_file="${state_dir}/log"
status_file="${state_dir}/status"
exit_file="${state_dir}/exit-code"
result_file="${state_dir}/result"
old_system_file="${state_dir}/old-system"
current_system_file="${state_dir}/current-system"
old_system=""
activating=0
activated=0
rolled_back=0

mkdir -p "${state_dir}"
exec >>"${log_file}" 2>&1

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

set_status() {
  printf '%s\n' "$1" >"${status_file}"
}

rollback_old_system() {
  if [[ "${rolled_back}" == "1" ]]; then
    return 0
  fi
  rolled_back=1

  if [[ -n "${old_system}" && -x "${old_system}/bin/switch-to-configuration" ]]; then
    echo "$(timestamp) rolling back to ${old_system}"
    "${old_system}/bin/switch-to-configuration" switch || true
  else
    echo "$(timestamp) rollback skipped; previous system path is unavailable"
  fi
}

finish() {
  local code=$?
  set +e

  if [[ "${code}" -ne 0 && ( "${activating}" == "1" || "${activated}" == "1" ) ]]; then
    rollback_old_system
  fi

  if [[ "${code}" -eq 0 ]]; then
    set_status success
  else
    set_status failed
  fi
  printf '%s\n' "${code}" >"${exit_file}"
  rm -rf "${lock_dir}" 2>/dev/null || true
  echo "$(timestamp) detached deploy finished with exit ${code}"
}
trap finish EXIT

set_status running
echo "$(timestamp) detached deploy started"
echo "$(timestamp) drv ${drv}"

old_system="$(readlink -f /run/current-system)"
printf '%s\n' "${old_system}" >"${old_system_file}"
echo "$(timestamp) previous system ${old_system}"

echo "$(timestamp) building activation derivation"
result="$(nix-store -r "${drv}" | tail -n 1)"
printf '%s\n' "${result}" >"${result_file}"
echo "$(timestamp) build result ${result}"

if [[ ! -x "${result}/deploy-rs-activate" ]]; then
  echo "$(timestamp) missing deploy-rs-activate in ${result}"
  exit 11
fi

echo "$(timestamp) activating"
activating=1
PROFILE="${result}" "${result}/deploy-rs-activate"
activating=0
activated=1
readlink -f /run/current-system >"${current_system_file}"
echo "$(timestamp) activated $(cat "${current_system_file}")"

read -r -a services <<<"${service_list}"
if (( ${#services[@]} > 0 )); then
  echo "$(timestamp) verifying services: ${service_list}"
fi

failed=0
for service in "${services[@]}"; do
  [[ -n "${service}" ]] || continue
  unit="${service}"
  if [[ "${unit}" != *.* ]]; then
    unit="${unit}.service"
  fi

  if systemctl is-active --quiet "${unit}"; then
    echo "$(timestamp) ${unit} active"
  else
    echo "$(timestamp) ${unit} not active"
    failed=1
  fi
done

if [[ "${failed}" -ne 0 ]]; then
  echo "$(timestamp) service verification failed"
  rollback_old_system
  exit 20
fi

echo "$(timestamp) detached deploy succeeded"
REMOTE_SCRIPT
}

wait_remote_detached_deploy() {
  local unit="$1"
  local state_dir="$2"
  local timeout="${TSURF_DEPLOY_DETACHED_TIMEOUT:-7200}"
  local interval="${TSURF_DEPLOY_DETACHED_POLL_INTERVAL:-15}"
  local deadline=$((SECONDS + timeout))
  local state_dir_q unit_q log_q exit_q status_q payload exit_code status unit_state stopped_without_exit

  state_dir_q="$(shell_quote "$state_dir")"
  unit_q="$(shell_quote "$unit")"
  log_q="$(shell_quote "${state_dir}/log")"
  exit_q="$(shell_quote "${state_dir}/exit-code")"
  status_q="$(shell_quote "${state_dir}/status")"
  stopped_without_exit=0

  echo "==> Waiting for detached remote deploy unit ${unit}..."
  while true; do
    payload="$(ssh_retry "if test -f ${exit_q}; then printf 'exit='; cat ${exit_q}; fi; if test -f ${status_q}; then printf 'status='; cat ${status_q}; fi; systemctl is-active ${unit_q} 2>/dev/null | sed 's/^/unit=/' || true" 2>/dev/null || true)"
    exit_code="$(printf '%s\n' "${payload}" | sed -n 's/^exit=//p' | tail -n 1)"
    status="$(printf '%s\n' "${payload}" | sed -n 's/^status=//p' | tail -n 1)"
    unit_state="$(printf '%s\n' "${payload}" | sed -n 's/^unit=//p' | tail -n 1)"

    if [[ -n "${status}" || -n "${exit_code}" ]]; then
      # The host-side script is now running and its EXIT trap owns lock cleanup.
      REMOTE_LOCK_HELD=false
    fi

    if [[ -n "${exit_code}" ]]; then
      echo "==> Detached deploy log tail:"
      ssh_retry "tail -n 120 ${log_q}" || true
      return "${exit_code}"
    fi

    if [[ "${unit_state}" == "failed" || "${unit_state}" == "inactive" || "${unit_state}" == "unknown" ]]; then
      stopped_without_exit=$((stopped_without_exit + 1))
      if ((stopped_without_exit >= 4)); then
        echo "ERROR: detached deploy unit stopped without writing an exit code." >&2
        ssh_retry "systemctl status --no-pager ${unit_q}; echo; test -f ${log_q} && tail -n 120 ${log_q}" || true
        return 1
      fi
    else
      stopped_without_exit=0
    fi

    if ((SECONDS >= deadline)); then
      echo "ERROR: detached deploy timed out after ${timeout}s." >&2
      ssh_retry "test -f ${log_q} && tail -n 120 ${log_q}" || true
      return 124
    fi

    echo "  detached deploy status: ${status:-unknown}, unit: ${unit_state:-unknown}"
    sleep "${interval}"
  done
}

run_remote_detached_deploy() {
  local installable="$FLAKE_DIR#deploy.nodes.${NODE}.profiles.system.path"
  local drv deploy_id unit state_dir run_path services unit_q state_dir_q run_path_q drv_q lock_q services_q

  echo "==> Evaluating deploy-rs activation derivation for '$NODE'..."
  drv="$(nix path-info --derivation "${installable}")"
  echo "  ${drv}"

  copy_derivation_to_remote "${drv}"

  deploy_id="$(date -u '+%Y%m%dT%H%M%SZ')-${GIT_SHA}-$$"
  deploy_id="${deploy_id//[^A-Za-z0-9._-]/-}"
  unit="tsurf-deploy-${NODE}-${deploy_id}.service"
  unit="${unit//[^A-Za-z0-9_.@-]/-}"
  state_dir="/var/lib/tsurf-deploy/${NODE}-${deploy_id}"
  run_path="${state_dir}/run.sh"
  services="${TSURF_DEPLOY_VERIFY_SERVICES:-}"

  state_dir_q="$(shell_quote "${state_dir}")"
  run_path_q="$(shell_quote "${run_path}")"
  unit_q="$(shell_quote "${unit}")"
  drv_q="$(shell_quote "${drv}")"
  lock_q="$(shell_quote "${REMOTE_LOCK_DIR}")"
  services_q="$(shell_quote "${services}")"

  echo "==> Installing detached deploy runner on $TARGET..."
  ssh_retry "install -d -m 0700 ${state_dir_q}"
  upload_remote_detached_script "${run_path}"

  echo "==> Starting detached deploy unit ${unit}..."
  ssh_retry "systemd-run --unit=${unit_q} --property=Type=exec /run/current-system/sw/bin/bash ${run_path_q} ${state_dir_q} ${drv_q} ${lock_q} ${services_q}"

  wait_remote_detached_deploy "${unit}" "${state_dir}"
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

if [[ "$FAST_MODE" == "true" ]]; then
  MODE="local"
  echo "==> FAST MODE: local build, single evaluation, no --remote-build"
fi

DEPLOY_RS_EXIT=0
if [[ "$MODE" == "local" ]]; then
  echo "==> Deploying node '$NODE' to $TARGET with deploy-rs..."
  nix run "$FLAKE_DIR#deploy-rs" -- "${DEPLOY_ARGS[@]}" || DEPLOY_RS_EXIT=$?
elif [[ "$MODE" == "remote-detached" ]]; then
  echo "==> Deploying node '$NODE' via detached remote build on $TARGET..."
  if [[ "$MAGIC_ROLLBACK" == true && "$FIRST_DEPLOY" != true ]]; then
    echo "==> Detached mode uses host-side verification rollback instead of deploy-rs magic rollback."
  fi
  run_remote_detached_deploy || DEPLOY_RS_EXIT=$?
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
