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
#   AGENT_CREDENTIAL_SECRETS — space-separated "ENV_VAR:secret-file-name" pairs
#                              ENV_VAR = env var exported for nono's env:// credential proxy
#                              secret-file-name = filename under /run/secrets/
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
cwd="$(readlink -f "$PWD")"
case "$cwd" in
  "$AGENT_PROJECT_ROOT"/*|"$AGENT_PROJECT_ROOT") ;;
  *)
    echo "ERROR: $AGENT_NAME must run inside $AGENT_PROJECT_ROOT (current: $cwd)" >&2
    exit 1
    ;;
esac

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

# Scope sandbox read access to the current git repository root.
# The public repo does not try to classify "safe" infrastructure repos; operators
# keep agents out of security-boundary repos by policy.
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

# Build nono arguments. Credential proxy is configured in the nono profile
# (custom_credentials with env:// URIs); nono starts the reverse proxy and
# injects phantom tokens into the child environment automatically.
nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback --read "$git_root")

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
child_args+=("NPM_CONFIG_MINIMUM_RELEASE_AGE=${NPM_MIN_RELEASE_AGE_DAYS}")
child_args+=("PYTHONDONTWRITEBYTECODE=1")
# Telemetry suppression (ecosystem review: Trail of Bits config pattern)
child_args+=("DISABLE_TELEMETRY=1")
child_args+=("DISABLE_ERROR_REPORTING=1")
child_args+=("CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1")

child_args+=("$AGENT_REAL_BINARY" "$@")

nono_args+=(-- "${child_args[@]}")
journal_log "sandboxed"
nono "${nono_args[@]}"
