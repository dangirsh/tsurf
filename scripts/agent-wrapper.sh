#!/usr/bin/env bash
# Agent sandbox wrapper — called by launcher stubs generated in modules/agent-launcher.nix.
# Configuration is passed via environment variables set by the Nix launcher:
#   AGENT_NAME              — wrapper name (for messages and launch log)
#   AGENT_REAL_BINARY       — full path to the real agent binary
#   AGENT_PROJECT_ROOT      — sandboxed agents must run inside this directory;
#                              the first child under this path becomes the read scope
#   AGENT_NONO_PROFILE      — full path to nono profile JSON
#   AGENT_RUN_AS_USER       — target Unix user for the actual agent binary
#   AGENT_RUN_AS_UID        — target Unix uid for the actual agent binary
#   AGENT_RUN_AS_GID        — target Unix gid for the actual agent binary
#   AGENT_RUN_AS_HOME       — target HOME for the actual agent binary
#   AGENT_CHILD_PATH        — PATH injected into the agent child after privilege drop
#   AGENT_CREDENTIAL_SECRETS — space-separated "ENV_VAR:secret-file-name" pairs
#                              ENV_VAR = env var exported for nono's env:// credential proxy
#                              secret-file-name = filename under /run/secrets/
#   AGENT_CREDENTIAL_SERVICES — space-separated nono credential names to enable
#   AGENT_SCOPE_ACCESS       — "read" (default) or "allow" access to the current top-level workspace
#   AGENT_EXTRA_READ_PATHS   — optional space-separated paths passed to nono with --read
#   AGENT_EXTRA_ALLOW_PATHS  — optional space-separated paths passed to nono with --allow
#
# Launch logging:
#   Single sink: journald via logger -t agent-launch (root-owned, append-only).
#   Only structured metadata is logged — no raw arguments, prompts, or file paths.
#
# @decision AUDIT-117-01: Single-sink journald launch logging. File-based audit log removed.
# @decision SEC-159-01: Raw provider keys brokered through nono's built-in credential proxy.
#   The wrapper exports real keys as env vars (env:// URIs); nono reads them before sandboxing
#   and starts its reverse proxy with phantom tokens. The child never sees real keys.

set -euo pipefail

NPM_MIN_RELEASE_AGE_DAYS=1440 # ~4 years; supply chain hardening (Trail of Bits)

: "${AGENT_NAME:?must be set}"
: "${AGENT_REAL_BINARY:?must be set}"
: "${AGENT_PROJECT_ROOT:?must be set}"
: "${AGENT_NONO_PROFILE:?must be set}"
: "${AGENT_RUN_AS_USER:?must be set}"
: "${AGENT_RUN_AS_UID:?must be set}"
: "${AGENT_RUN_AS_GID:?must be set}"
: "${AGENT_RUN_AS_HOME:?must be set}"
: "${AGENT_CHILD_PATH:?must be set}"

export HOME="$AGENT_RUN_AS_HOME"
export USER="$AGENT_RUN_AS_USER"
export LOGNAME="$AGENT_RUN_AS_USER"

case "$AGENT_REAL_BINARY" in
  /nix/store/*) ;;
  *)
    echo "ERROR: AGENT_REAL_BINARY must be in /nix/store" >&2
    exit 1
    ;;
esac

journal_log() {
  local mode="$1"
  logger -t "agent-launch" --id=$$ \
    "mode=$mode agent=$AGENT_NAME user=$(whoami) uid=$(id -u) repo_scope=${repo_scope:-unknown}" \
    2>/dev/null || true
}

# Enforce PWD inside project root
project_root="$(readlink -f "$AGENT_PROJECT_ROOT")"
cwd="$(readlink -f "$PWD")"
case "$cwd" in
  "$project_root"/*|"$project_root") ;;
  *)
    echo "ERROR: $AGENT_NAME must run inside $project_root (current: $cwd)" >&2
    exit 1
    ;;
esac

# Scope sandbox read access to the current top-level workspace directory.
# A workspace is the first path component beneath AGENT_PROJECT_ROOT, for
# example /data/projects/my-repo from /data/projects/my-repo/subdir.
if [[ "$cwd" == "$project_root" ]]; then
  echo "ERROR: refusing to grant read access to the entire project root ($project_root)" >&2
  exit 1
fi

workspace_rel="${cwd#"$project_root"/}"
workspace_name="${workspace_rel%%/*}"
workspace_root="${project_root}/${workspace_name}"
if [[ ! -d "$workspace_root" ]]; then
  echo "ERROR: could not resolve top-level workspace beneath $project_root (current: $cwd)" >&2
  exit 1
fi
repo_scope="top-level-workspace"

# Load real API keys from sops-managed /run/secrets/ into env vars.
# nono's credential proxy reads these via env:// URIs in the profile's
# custom_credentials, then exposes only phantom tokens to the child.
IFS=' ' read -ra cred_pairs <<< "${AGENT_CREDENTIAL_SECRETS:-}"
for pair in "${cred_pairs[@]}"; do
  [[ -n "$pair" ]] || continue
  IFS=: read -r env_var secret_name <<< "$pair"
  secret_file="/run/secrets/$secret_name"
  if [[ ! -f "$secret_file" ]]; then
    echo "WARNING: $env_var not loaded — $secret_file not found" >&2
    continue
  fi
  secret_value="$(cat "$secret_file")"
  if [[ -z "$secret_value" || "$secret_value" == PLACEHOLDER* ]]; then
    continue
  fi
  export "${env_var}=${secret_value}"
done

# Build nono arguments. Credential proxy is configured in the nono profile
# (custom_credentials with env:// URIs); nono starts the reverse proxy and
# injects phantom tokens into the child environment automatically.
nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback)
IFS=' ' read -ra credential_services <<< "${AGENT_CREDENTIAL_SERVICES:-}"
for service in "${credential_services[@]}"; do
  [[ -n "$service" ]] || continue
  nono_args+=(--credential "$service")
done

case "${AGENT_SCOPE_ACCESS:-read}" in
  read)
    nono_args+=(--read "$workspace_root")
    ;;
  allow)
    nono_args+=(--allow "$workspace_root")
    ;;
  *)
    echo "ERROR: AGENT_SCOPE_ACCESS must be 'read' or 'allow'" >&2
    exit 1
    ;;
esac

IFS=' ' read -ra extra_read_paths <<< "${AGENT_EXTRA_READ_PATHS:-}"
for path in "${extra_read_paths[@]}"; do
  [[ -n "$path" ]] || continue
  nono_args+=(--read "$path")
done

IFS=' ' read -ra extra_allow_paths <<< "${AGENT_EXTRA_ALLOW_PATHS:-}"
for path in "${extra_allow_paths[@]}"; do
  [[ -n "$path" ]] || continue
  nono_args+=(--allow "$path")
done

setpriv_bin="$(command -v setpriv)"
env_bin="$(command -v env)"
nono_bin="$(command -v nono)"
bash_bin="$(command -v bash)"
agent_env=(
  "HOME=$AGENT_RUN_AS_HOME"
  "USER=$AGENT_RUN_AS_USER"
  "LOGNAME=$AGENT_RUN_AS_USER"
  "PATH=$AGENT_CHILD_PATH"
)
if [[ -n "${TERM:-}" ]]; then
  agent_env+=("TERM=$TERM")
fi
if [[ -n "${LANG:-}" ]]; then
  agent_env+=("LANG=$LANG")
fi
# Agent managed settings: defense-in-depth deny rules
if [[ -f "/etc/${AGENT_NAME}-agent-settings.json" ]]; then
  agent_env+=("CLAUDE_CODE_MANAGED_SETTINGS_FILE=/etc/${AGENT_NAME}-agent-settings.json")
fi
# Supply chain hardening (ecosystem review: Trail of Bits devcontainer pattern)
agent_env+=("NPM_CONFIG_IGNORE_SCRIPTS=true")
agent_env+=("NPM_CONFIG_AUDIT=true")
agent_env+=("NPM_CONFIG_SAVE_EXACT=true")
agent_env+=("NPM_CONFIG_MINIMUM_RELEASE_AGE=${NPM_MIN_RELEASE_AGE_DAYS}")
agent_env+=("PYTHONDONTWRITEBYTECODE=1")
# Telemetry suppression (ecosystem review: Trail of Bits config pattern)
agent_env+=("DISABLE_TELEMETRY=1")
agent_env+=("DISABLE_ERROR_REPORTING=1")
agent_env+=("CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1")

if ((${#cred_pairs[@]} == 0)); then
  nono_args+=(-- "$AGENT_REAL_BINARY" "$@")
  journal_log "sandboxed"
  exec "$setpriv_bin" \
    --reuid "$AGENT_RUN_AS_UID" \
    --regid "$AGENT_RUN_AS_GID" \
    --init-groups \
    --reset-env \
    "$env_bin" "${agent_env[@]}" \
    "$nono_bin" "${nono_args[@]}"
fi

credential_env_names=()
for pair in "${cred_pairs[@]}"; do
  [[ -n "$pair" ]] || continue
  IFS=: read -r env_var _secret_name <<< "$pair"
  [[ -n "$env_var" ]] || continue
  credential_env_names+=("$env_var")
  if [[ "$env_var" == *_API_KEY ]]; then
    credential_env_names+=("${env_var%_API_KEY}_BASE_URL")
  fi
done
credential_env_names_str="${credential_env_names[*]}"

child_script='
  set -euo pipefail

  setpriv_bin="$1"
  env_bin="$2"
  real_binary="$3"
  run_uid="$4"
  run_gid="$5"
  credential_env_names="$6"
  shift 6

  agent_env=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    agent_env+=("$1")
    shift
  done
  if [[ "$#" -gt 0 && "$1" == "--" ]]; then
    shift
  fi

  proxy_env=()
  for name in NONO_PROXY_TOKEN HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY; do
    if [[ -n "${!name:-}" ]]; then
      proxy_env+=("$name=${!name}")
    fi
  done
  for name in $credential_env_names; do
    if [[ -n "${!name:-}" ]]; then
      proxy_env+=("$name=${!name}")
    fi
  done

  exec "$setpriv_bin" \
    --reuid "$run_uid" \
    --regid "$run_gid" \
    --init-groups \
    --reset-env \
    "$env_bin" "${agent_env[@]}" "${proxy_env[@]}" \
    "$real_binary" "$@"
'

nono_args+=(
  -- "$bash_bin" -c "$child_script" bash
  "$setpriv_bin"
  "$env_bin"
  "$AGENT_REAL_BINARY"
  "$AGENT_RUN_AS_UID"
  "$AGENT_RUN_AS_GID"
  "$credential_env_names_str"
  "${agent_env[@]}"
  --
  "$@"
)
journal_log "sandboxed"
exec "$nono_bin" "${nono_args[@]}"
