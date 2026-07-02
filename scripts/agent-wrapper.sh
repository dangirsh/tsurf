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
#   AGENT_CREDENTIAL_PROXY     — "nono" (legacy provider proxy) or "iron"
#   AGENT_IRON_CREDENTIAL_TOKENS — space-separated "ENV_VAR:proxy-token" pairs
#                              exported to the child when AGENT_CREDENTIAL_PROXY=iron
#   AGENT_EGRESS_PROXY_URL / CA_CERT / NO_PROXY — explicit Iron proxy settings
#   AGENT_SCOPE_ACCESS       — "read" (default) or "allow" access to the current top-level workspace
#   AGENT_EXTRA_READ_PATHS_FILE — optional /nix/store newline-delimited paths passed to nono with --read
#   AGENT_EXTRA_ALLOW_PATHS_FILE — optional /nix/store newline-delimited paths passed to nono with --allow
#   AGENT_CHILD_ENVIRONMENT_FILE — optional /nix/store file of non-secret NAME=value env entries
#   AGENT_NONO_PROXY_PORT_START / END — loopback port range reserved for nono's credential proxy
#
# Launch logging:
#   Single sink: journald via logger -t agent-launch (root-owned, append-only).
#   Only structured metadata is logged — no raw arguments, prompts, or file paths.
#
# @decision AUDIT-117-01: Single-sink journald launch logging. File-based audit log removed.
# @decision SEC-159-01: Legacy nono credential mode brokers raw provider keys through
#   nono's built-in credential proxy. The wrapper exports real keys as env vars
#   (env:// URIs); nono reads them before sandboxing and starts its reverse proxy
#   with phantom tokens. The child never sees real keys.
# @decision SEC-IRON-01: Iron credential mode never loads raw secrets in this wrapper.
#   The child gets provider-shaped placeholder tokens plus explicit proxy/CA env vars.

set -euo pipefail

NPM_MIN_RELEASE_AGE_DAYS=1
PNPM_MIN_RELEASE_AGE_MINUTES=1440

: "${AGENT_NAME:?must be set}"
: "${AGENT_REAL_BINARY:?must be set}"
: "${AGENT_PROJECT_ROOT:?must be set}"
: "${AGENT_NONO_PROFILE:?must be set}"
: "${AGENT_RUN_AS_USER:?must be set}"
: "${AGENT_RUN_AS_UID:?must be set}"
: "${AGENT_RUN_AS_GID:?must be set}"
: "${AGENT_RUN_AS_HOME:?must be set}"
: "${AGENT_CHILD_PATH:?must be set}"
AGENT_CREDENTIAL_PROXY="${AGENT_CREDENTIAL_PROXY:-nono}"

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
  local reason="${2:-none}"
  logger -t "agent-launch" --id=$$ \
    "mode=$mode agent=$AGENT_NAME user=$(whoami) uid=$(id -u) repo_scope=${repo_scope:-unknown} workspace=${workspace_name:-unknown} reason=$reason" \
    2>/dev/null || true
}

fail_launch() {
  local reason="$1"
  local message="$2"
  journal_log "refused" "$reason"
  echo "ERROR: $message" >&2
  exit 1
}

append_path_file_args() {
  local kind="$1"
  local path_file="$2"
  local flag="$3"
  local path

  [[ -n "$path_file" ]] || return 0
  case "$path_file" in
    /nix/store/*) ;;
    *) fail_launch "invalid_${kind}_path_file" "AGENT_${kind}_PATHS_FILE must be in /nix/store" ;;
  esac
  [[ -f "$path_file" ]] || return 0

  while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -n "$path" ]] || continue
    nono_args+=("$flag" "$path")
  done < "$path_file"
}

allocate_nono_proxy_port() {
  local start="${AGENT_NONO_PROXY_PORT_START:-20000}"
  local end="${AGENT_NONO_PROXY_PORT_END:-20199}"
  local lock_dir="/run/tsurf-agent-proxy-ports"
  local port lock_fd

  [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ && "$start" -le "$end" ]] \
    || fail_launch "invalid_proxy_port_range" "invalid nono proxy port range"

  install -d -m 0700 "$lock_dir"
  for ((port = start; port <= end; port++)); do
    exec {lock_fd}>"$lock_dir/$port.lock"
    if flock -n "$lock_fd"; then
      if ! (: >"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1; then
        NONO_PROXY_PORT="$port"
        NONO_PROXY_LOCK_FD="$lock_fd"
        export NONO_PROXY_PORT NONO_PROXY_LOCK_FD
        return 0
      fi
    fi
    eval "exec ${lock_fd}>&-"
  done

  fail_launch "proxy_port_exhausted" "no free nono proxy port in reserved range ${start}-${end}"
}

# Enforce PWD inside project root
project_root="$(readlink -f "$AGENT_PROJECT_ROOT")"
cwd="$(readlink -f "$PWD")"
case "$cwd" in
  "$project_root"/*|"$project_root") ;;
  *)
    fail_launch "outside_project_root" "$AGENT_NAME must run inside $project_root (current: $cwd)"
    ;;
esac

# Scope sandbox read access to the current top-level workspace directory.
# A workspace is the first path component beneath AGENT_PROJECT_ROOT, for
# example /data/projects/my-repo from /data/projects/my-repo/subdir.
if [[ "$cwd" == "$project_root" ]]; then
  fail_launch "project_root_scope" "refusing to grant read access to the entire project root ($project_root)"
fi

workspace_rel="${cwd#"$project_root"/}"
workspace_name="${workspace_rel%%/*}"
workspace_root="${project_root}/${workspace_name}"
if [[ ! -d "$workspace_root" ]]; then
  fail_launch "workspace_resolution" "could not resolve top-level workspace beneath $project_root (current: $cwd)"
fi
repo_scope="top-level-workspace:${workspace_name}"

IFS=' ' read -ra cred_pairs <<< "${AGENT_CREDENTIAL_SECRETS:-}"
use_nono_credentials=0
if [[ "$AGENT_CREDENTIAL_PROXY" == "nono" && ${#cred_pairs[@]} -gt 0 ]]; then
  use_nono_credentials=1
  # Load real API keys from sops-managed /run/secrets/ into env vars.
  # nono's credential proxy reads these via env:// URIs in the profile's
  # custom_credentials, then exposes only phantom tokens to the child.
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
elif [[ "$AGENT_CREDENTIAL_PROXY" != "iron" && "$AGENT_CREDENTIAL_PROXY" != "nono" ]]; then
  fail_launch "invalid_credential_proxy" "AGENT_CREDENTIAL_PROXY must be 'nono' or 'iron'"
elif [[ "$AGENT_CREDENTIAL_PROXY" == "iron" && ${#cred_pairs[@]} -gt 0 && -z "${AGENT_EGRESS_PROXY_URL:-}" ]]; then
  fail_launch "iron_proxy_unconfigured" "credentialProxy=iron requires AGENT_EGRESS_PROXY_URL"
fi

# Build nono arguments. Credential proxy is configured in the nono profile
# (custom_credentials with env:// URIs); nono starts the reverse proxy and
# injects phantom tokens into the child environment automatically.
nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback)
IFS=' ' read -ra credential_services <<< "${AGENT_CREDENTIAL_SERVICES:-}"
if ((use_nono_credentials)); then
  for service in "${credential_services[@]}"; do
    [[ -n "$service" ]] || continue
    nono_args+=(--credential "$service")
  done
fi

case "${AGENT_SCOPE_ACCESS:-read}" in
  read)
    nono_args+=(--read "$workspace_root")
    ;;
  allow)
    nono_args+=(--allow "$workspace_root")
    ;;
  *)
    fail_launch "invalid_scope_access" "AGENT_SCOPE_ACCESS must be 'read' or 'allow'"
    ;;
esac

append_path_file_args "EXTRA_READ" "${AGENT_EXTRA_READ_PATHS_FILE:-}" "--read"
append_path_file_args "EXTRA_ALLOW" "${AGENT_EXTRA_ALLOW_PATHS_FILE:-}" "--allow"

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
if [[ -n "${AGENT_EGRESS_PROXY_URL:-}" ]]; then
  agent_env+=("HTTP_PROXY=$AGENT_EGRESS_PROXY_URL")
  agent_env+=("HTTPS_PROXY=$AGENT_EGRESS_PROXY_URL")
  agent_env+=("http_proxy=$AGENT_EGRESS_PROXY_URL")
  agent_env+=("https_proxy=$AGENT_EGRESS_PROXY_URL")
  agent_env+=("ALL_PROXY=$AGENT_EGRESS_PROXY_URL")
  agent_env+=("all_proxy=$AGENT_EGRESS_PROXY_URL")
  agent_env+=("NO_PROXY=${AGENT_EGRESS_PROXY_NO_PROXY:-127.0.0.1,localhost}")
  agent_env+=("no_proxy=${AGENT_EGRESS_PROXY_NO_PROXY:-127.0.0.1,localhost}")
fi
if [[ -n "${AGENT_EGRESS_PROXY_CA_CERT:-}" ]]; then
  agent_env+=("SSL_CERT_FILE=$AGENT_EGRESS_PROXY_CA_CERT")
  agent_env+=("REQUESTS_CA_BUNDLE=$AGENT_EGRESS_PROXY_CA_CERT")
  agent_env+=("CURL_CA_BUNDLE=$AGENT_EGRESS_PROXY_CA_CERT")
  agent_env+=("NODE_EXTRA_CA_CERTS=$AGENT_EGRESS_PROXY_CA_CERT")
  agent_env+=("GIT_SSL_CAINFO=$AGENT_EGRESS_PROXY_CA_CERT")
fi
if [[ "$AGENT_CREDENTIAL_PROXY" == "iron" ]]; then
  IFS=' ' read -ra iron_pairs <<< "${AGENT_IRON_CREDENTIAL_TOKENS:-}"
  for pair in "${iron_pairs[@]}"; do
    [[ -n "$pair" ]] || continue
    IFS=: read -r env_var proxy_token <<< "$pair"
    if [[ ! "$env_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ || -z "$proxy_token" ]]; then
      fail_launch "invalid_iron_credential_token" "invalid Iron credential token entry for $AGENT_NAME"
    fi
    agent_env+=("$env_var=$proxy_token")
  done
fi
if [[ -n "${AGENT_CHILD_ENVIRONMENT_FILE:-}" ]]; then
  case "$AGENT_CHILD_ENVIRONMENT_FILE" in
    /nix/store/*) ;;
    *)
      fail_launch "invalid_child_environment_file" "AGENT_CHILD_ENVIRONMENT_FILE must be in /nix/store"
      ;;
  esac
  if [[ -f "$AGENT_CHILD_ENVIRONMENT_FILE" ]]; then
    while IFS= read -r assignment || [[ -n "$assignment" ]]; do
      [[ -n "$assignment" ]] || continue
      name="${assignment%%=*}"
      if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ || "$assignment" != *=* ]]; then
        fail_launch "invalid_child_environment" "invalid child environment entry for $AGENT_NAME"
      fi
      agent_env+=("$assignment")
    done < "$AGENT_CHILD_ENVIRONMENT_FILE"
  fi
fi
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
agent_env+=("NPM_CONFIG_MIN_RELEASE_AGE=${NPM_MIN_RELEASE_AGE_DAYS}")
agent_env+=("NPM_CONFIG_MINIMUM_RELEASE_AGE=${PNPM_MIN_RELEASE_AGE_MINUTES}")
agent_env+=("PNPM_CONFIG_MINIMUM_RELEASE_AGE=${PNPM_MIN_RELEASE_AGE_MINUTES}")
agent_env+=("PYTHONDONTWRITEBYTECODE=1")
# Telemetry suppression (ecosystem review: Trail of Bits config pattern)
agent_env+=("DISABLE_TELEMETRY=1")
agent_env+=("DISABLE_ERROR_REPORTING=1")
agent_env+=("CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1")

if ((use_nono_credentials == 0)); then
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
  if [[ "$env_var" == *_API_KEY ]]; then
    credential_env_names+=("${env_var%_API_KEY}_BASE_URL")
  fi
done
credential_env_names_str="${credential_env_names[*]}"
allocate_nono_proxy_port
nono_args+=(--proxy-port "$NONO_PROXY_PORT")

# shellcheck disable=SC2016
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
  for name in NONO_PROXY_TOKEN; do
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
