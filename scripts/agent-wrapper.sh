#!/usr/bin/env bash
# Agent sandbox wrapper — called by wrapper stubs generated in modules/agent-sandbox.nix.
# Configuration is passed via environment variables set by the Nix wrapper stub:
#   AGENT_NAME              — wrapper name (for messages and audit log)
#   AGENT_REAL_BINARY       — full path to the real agent binary
#   AGENT_PROJECT_ROOT      — sandboxed agents must run inside this directory
#   AGENT_AUDIT_LOG         — path to TSV audit log file
#   AGENT_NONO_PROFILE      — full path to nono profile JSON
#   AGENT_CREDENTIALS       — space-separated "ENV_VAR:secret-file-name" pairs
#   AGENT_ALLOW_NIX_DAEMON  — non-empty to grant /nix/var/nix/daemon-socket access

set -euo pipefail

audit_log() {
  local mode="$1"; shift
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Iseconds)" "$(whoami)" "$$" "$mode" "$PWD" "$AGENT_NAME" "$*" \
    >> "$AGENT_AUDIT_LOG" 2>/dev/null || true
}

# --no-sandbox escape hatch: requires AGENT_ALLOW_NOSANDBOX=1
if [[ "${1:-}" == "--no-sandbox" ]]; then
  if [[ "${AGENT_ALLOW_NOSANDBOX:-}" != "1" ]]; then
    echo "ERROR: --no-sandbox requires AGENT_ALLOW_NOSANDBOX=1" >&2
    exit 1
  fi
  echo "WARNING: Running $AGENT_NAME WITHOUT sandbox. All secrets accessible." >&2
  audit_log "nosandbox" "${@:2}"
  shift
  exec "$AGENT_REAL_BINARY" "$@"
fi

# Enforce PWD inside project root
cwd="$(readlink -f "$PWD")"
case "$cwd" in
  "$AGENT_PROJECT_ROOT"/*|"$AGENT_PROJECT_ROOT") ;;
  *)
    echo "ERROR: $AGENT_NAME must run inside $AGENT_PROJECT_ROOT (current: $cwd)" >&2
    exit 1 ;;
esac

# Load API keys from /run/secrets/ for this wrapper's credential set
IFS=' ' read -ra cred_pairs <<< "$AGENT_CREDENTIALS"
for pair in "${cred_pairs[@]}"; do
  env_var="${pair%%:*}"
  secret_file="/run/secrets/${pair#*:}"
  if [[ -f "$secret_file" ]]; then
    declare -x "${env_var}=$(cat "$secret_file")"
  else
    echo "WARNING: $env_var not loaded — $secret_file not found" >&2
    declare -x "${env_var}="
  fi
done

# Scope sandbox read access to the current git repository root
git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || git_root="$cwd"

# Build nono arguments
nono_args=(run --profile "$AGENT_NONO_PROFILE" --net-allow --no-rollback --read "$git_root")
[[ -n "${AGENT_ALLOW_NIX_DAEMON:-}" ]] && nono_args+=(--read /nix/var/nix/daemon-socket)

# Inject non-empty, non-placeholder credentials into the sandbox
for pair in "${cred_pairs[@]}"; do
  env_var="${pair%%:*}"
  val="${!env_var:-}"
  if [[ -n "$val" && "$val" != PLACEHOLDER* ]]; then
    nono_args+=(--env-credential-map "env://$env_var" "$env_var")
  fi
done

nono_args+=(-- "$AGENT_REAL_BINARY" "$@")
audit_log "sandboxed" "$@"
exec nono "${nono_args[@]}"
