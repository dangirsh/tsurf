#!/usr/bin/env bash
# Agent sandbox wrapper — called by launcher stubs generated in modules/agent-launcher.nix.
# Configuration is passed via environment variables set by the Nix launcher:
#   AGENT_NAME              — wrapper name (for messages and launch log)
#   AGENT_REAL_BINARY       — full path to the real agent binary
#   AGENT_PROJECT_ROOT      — sandboxed agents must run inside this directory
#   AGENT_NONO_PROFILE      — full path to nono profile JSON
#   AGENT_RUN_AS_USER       — target Unix user for the actual agent binary
#   AGENT_RUN_AS_UID        — target Unix uid for the actual agent binary
#   AGENT_RUN_AS_GID        — target Unix gid for the actual agent binary
#   AGENT_RUN_AS_HOME       — target HOME for the actual agent binary
#   AGENT_CHILD_PATH        — PATH injected into the agent child after privilege drop
#   AGENT_CREDENTIALS       — space-separated "SERVICE:ENV_VAR:secret-file-name" triples
#                             SERVICE = provider key understood by credential-proxy.py
#                             ENV_VAR = env var exposed to the child as a session token
#                             secret-file-name = filename under /run/secrets/
#
# Launch logging:
#   Single sink: journald via logger -t agent-launch (root-owned, append-only).
#   Only structured metadata is logged — no raw arguments, prompts, or file paths.
#
# @decision AUDIT-117-01: Single-sink journald launch logging. File-based audit log removed.
# @decision SEC-145-01: Raw provider keys stay on the root-owned side of the broker.
#   The child gets only per-session loopback tokens and base URLs.

set -euo pipefail

: "${AGENT_NAME:?must be set}"
: "${AGENT_REAL_BINARY:?must be set}"
: "${AGENT_PROJECT_ROOT:?must be set}"
: "${AGENT_NONO_PROFILE:?must be set}"
: "${AGENT_CREDENTIAL_PROXY:?must be set}"
: "${AGENT_RUN_AS_USER:?must be set}"
: "${AGENT_RUN_AS_UID:?must be set}"
: "${AGENT_RUN_AS_GID:?must be set}"
: "${AGENT_RUN_AS_HOME:?must be set}"
: "${AGENT_CHILD_PATH:?must be set}"

case "$AGENT_REAL_BINARY" in
  /nix/store/*) ;;
  *)
    echo "ERROR: AGENT_REAL_BINARY must be in /nix/store" >&2
    exit 1
    ;;
esac

proxy_dir=""
proxy_pid=""

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ -n "$proxy_pid" ]]; then
    kill "$proxy_pid" 2>/dev/null || true
    wait "$proxy_pid" 2>/dev/null || true
  fi
  if [[ -n "$proxy_dir" && -d "$proxy_dir" ]]; then
    rm -rf "$proxy_dir"
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

journal_log() {
  local mode="$1"
  logger -t "agent-launch" --id=$$ \
    "mode=$mode agent=$AGENT_NAME user=$(whoami) uid=$(id -u) repo_scope=${repo_scope:-unknown}" \
    2>/dev/null || true
}

generate_session_token() {
  od -An -tx1 -N 32 /dev/urandom | tr -d ' \n'
}

# Enforce PWD inside project root
cwd="$(readlink -f "$PWD")"
case "$cwd" in
  "$AGENT_PROJECT_ROOT"/*|"$AGENT_PROJECT_ROOT") ;;
  *)
    echo "ERROR: $AGENT_NAME must run inside $AGENT_PROJECT_ROOT (current: $cwd)" >&2
    exit 1
    ;;
esac

# Load provider keys as root, start a root-owned loopback proxy, and expose only
# per-session tokens/base URLs to the sandboxed child.
declare -a child_env
declare -a proxy_env
declare -a proxy_open_ports
IFS=' ' read -ra cred_triples <<< "${AGENT_CREDENTIALS:-}"
route_count=0
for triple in "${cred_triples[@]}"; do
  [[ -n "$triple" ]] || continue
  IFS=: read -r service env_var secret_name <<< "$triple"
  secret_file="/run/secrets/$secret_name"
  if [[ ! -f "$secret_file" ]]; then
    echo "WARNING: $env_var not loaded — $secret_file not found" >&2
    continue
  fi

  secret_value="$(cat "$secret_file")"
  if [[ -z "$secret_value" || "$secret_value" == PLACEHOLDER* ]]; then
    continue
  fi

  session_token="$(generate_session_token)"
  base_var="${env_var%_API_KEY}_BASE_URL"
  child_env+=(
    "${env_var}=${session_token}"
    "${base_var}=http://127.0.0.1:PORT_PLACEHOLDER/${service}"
  )
  proxy_env+=(
    "TSURF_PROXY_ROUTE_${route_count}_SERVICE=${service}"
    "TSURF_PROXY_ROUTE_${route_count}_SESSION_TOKEN=${session_token}"
    "TSURF_PROXY_ROUTE_${route_count}_REAL_KEY=${secret_value}"
  )
  route_count=$((route_count + 1))
done

if (( route_count > 0 )); then
  proxy_dir="$(mktemp -d /run/tsurf-credential-proxy.XXXXXX)"
  proxy_port_file="$proxy_dir/port"
  env \
    "TSURF_PROXY_ROUTE_COUNT=$route_count" \
    "${proxy_env[@]}" \
    python3 "$AGENT_CREDENTIAL_PROXY" --port-file "$proxy_port_file" &
  proxy_pid="$!"

  for _ in $(seq 1 50); do
    if [[ -s "$proxy_port_file" ]]; then
      break
    fi
    sleep 0.1
  done

  if [[ ! -s "$proxy_port_file" ]]; then
    echo "ERROR: credential proxy failed to publish its listen port" >&2
    exit 1
  fi

  proxy_port="$(cat "$proxy_port_file")"
  proxy_open_ports+=("$proxy_port")
  for idx in "${!child_env[@]}"; do
    child_env[idx]="${child_env[idx]//PORT_PLACEHOLDER/${proxy_port}}"
  done
fi

# Scope sandbox read access to the current git repository root.
# Fail closed: refuse to run outside a git worktree (no silent fallback to $cwd).
git_root="$(git -c safe.directory='*' -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: $AGENT_NAME must run inside a git worktree beneath $AGENT_PROJECT_ROOT" >&2
  exit 1
}
git_root="$(readlink -f "$git_root")"
if [[ "$git_root" == "$AGENT_PROJECT_ROOT" ]]; then
  echo "ERROR: refusing to grant read access to the entire project root ($AGENT_PROJECT_ROOT)" >&2
  exit 1
fi
repo_scope="git-worktree"

# Build nono arguments. Raw provider keys stay in the root-owned proxy process;
# the child receives only per-session loopback tokens/base URLs.
nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback --read "$git_root")
for port in "${proxy_open_ports[@]}"; do
  nono_args+=(--open-port "$port")
done

setpriv_bin="$(command -v setpriv)"
env_bin="$(command -v env)"
child_args=(
  "$setpriv_bin"
  --reuid "$AGENT_RUN_AS_UID"
  --regid "$AGENT_RUN_AS_GID"
  --init-groups
  --reset-env
  "$env_bin"
  "HOME=$AGENT_RUN_AS_HOME"
  "USER=$AGENT_RUN_AS_USER"
  "LOGNAME=$AGENT_RUN_AS_USER"
  "PATH=$AGENT_CHILD_PATH"
)
if [[ -n "${TERM:-}" ]]; then
  child_args+=("TERM=$TERM")
fi
if [[ -n "${LANG:-}" ]]; then
  child_args+=("LANG=$LANG")
fi
# Agent managed settings: defense-in-depth deny rules
if [[ -f "/etc/${AGENT_NAME}-agent-settings.json" ]]; then
  child_args+=("CLAUDE_CODE_MANAGED_SETTINGS_FILE=/etc/${AGENT_NAME}-agent-settings.json")
fi
# Supply chain hardening (ecosystem review: Trail of Bits devcontainer pattern)
child_args+=("NPM_CONFIG_IGNORE_SCRIPTS=true")
child_args+=("NPM_CONFIG_AUDIT=true")
child_args+=("NPM_CONFIG_SAVE_EXACT=true")
child_args+=("NPM_CONFIG_MINIMUM_RELEASE_AGE=1440")
child_args+=("PYTHONDONTWRITEBYTECODE=1")
# Telemetry suppression (ecosystem review: Trail of Bits config pattern)
child_args+=("DISABLE_TELEMETRY=1")
child_args+=("DISABLE_ERROR_REPORTING=1")
child_args+=("CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1")

child_args+=("${child_env[@]}" "$AGENT_REAL_BINARY" "$@")

nono_args+=(-- "${child_args[@]}")
journal_log "sandboxed"
nono "${nono_args[@]}"
