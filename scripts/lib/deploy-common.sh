#!/usr/bin/env bash
# Shared helpers for tsurf deploy entrypoints.
# shellcheck disable=SC2029

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

shell_quote() {
  printf '%q' "$1"
}

shell_join() {
  local out="" arg
  for arg in "$@"; do
    printf -v out '%s%q ' "$out" "$arg"
  done
  printf '%s\n' "${out% }"
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

load_ssh_extra_opts() {
  SSH_EXTRA_OPTS=()
  if [[ -n "${TSURF_DEPLOY_SSH_OPTS_FILE:-}" ]]; then
    while IFS= read -r opt || [[ -n "$opt" ]]; do
      [[ -n "$opt" ]] || continue
      SSH_EXTRA_OPTS+=("$opt")
    done < "$TSURF_DEPLOY_SSH_OPTS_FILE"
  elif [[ -n "${TSURF_DEPLOY_SSH_OPTS:-}" ]]; then
    read -r -a SSH_EXTRA_OPTS <<<"${TSURF_DEPLOY_SSH_OPTS}"
  fi
}

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

deploy_cleanup_remote_lock() {
  if [[ "${REMOTE_LOCK_HELD:-false}" == true ]]; then
    ssh "${SSH_OPTS[@]}" "$TARGET" "rm -rf '$REMOTE_LOCK_DIR'" 2>/dev/null || true
  fi
  if [[ -n "${TARGET:-}" ]]; then
    ssh "${SSH_OPTS[@]}" -O exit "$TARGET" 2>/dev/null || true
  fi
}

deploy_acquire_remote_lock() {
  local lock_key lock_info

  lock_key="${TARGET_HOSTNAME}"
  lock_key="${lock_key//[^A-Za-z0-9._-]/-}"
  REMOTE_LOCK_DIR="/var/lock/deploy-${lock_key}.lock"
  GIT_SHA=$(git -C "$FLAKE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  lock_info="holder=$(whoami)@$(hostname)
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
    return 1
  fi
  REMOTE_LOCK_HELD=true
  printf '%s\n' "$lock_info" | ssh "${SSH_OPTS[@]}" "$TARGET" "cat > '$REMOTE_LOCK_DIR/info.txt'" 2>/dev/null || true
}

deploy_verify_remote() {
  local failed=0
  local status service
  local systemd_services=("sshd" "nftables")

  if [[ -n "${TSURF_DEPLOY_VERIFY_SERVICES:-}" ]]; then
    read -r -a systemd_services <<<"${TSURF_DEPLOY_VERIFY_SERVICES}"
  fi

  echo "==> Verifying services..."
  for service in "${systemd_services[@]}"; do
    status=$(ssh_retry "systemctl is-active ${service}.service" 2>/dev/null || echo "unknown")
    echo "  ${service}: ${status}"
    if [[ "$status" != "active" ]]; then
      failed=1
    fi
  done

  # @decision DEPLOY-04: Use non-multiplexed connections to test real SSH paths.
  echo "==> Verifying remote access..."
  REMOTE_ACCESS_SSH_OPTS=(-o BatchMode=yes -o ControlPath=none -o ConnectTimeout=15)
  REMOTE_ACCESS_SSH_OPTS+=("${SSH_EXTRA_OPTS[@]}")
  if ssh "${REMOTE_ACCESS_SSH_OPTS[@]}" "$TARGET" \
      "systemctl is-active --quiet sshd.service" 2>/dev/null; then
    echo "  Deploy target ($TARGET): SSH OK"
  else
    echo "  Deploy target ($TARGET): UNREACHABLE"
    failed=1
  fi

  return "$failed"
}

deploy_finish_result() {
  local failed="$1"
  local duration="$SECONDS"

  echo ""
  if [[ "$failed" -eq 0 ]]; then
    echo "=== Deploy SUCCESS ($((duration / 60))m $((duration % 60))s) ==="
  else
    echo "=== Deploy COMPLETED with WARNINGS ==="
    echo ""
    echo "Some services or connectivity checks failed. Manual rollback if needed:"
    echo "  ssh $TARGET nixos-rebuild switch --rollback"
    exit 2
  fi
}
