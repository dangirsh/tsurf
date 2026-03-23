#!/usr/bin/env bash
# Agent sandbox wrapper — called by wrapper stubs generated in modules/agent-sandbox.nix.
# Configuration is passed via environment variables set by the Nix wrapper stub:
#   AGENT_NAME              — wrapper name (for messages and launch log)
#   AGENT_REAL_BINARY       — full path to the real agent binary
#   AGENT_PROJECT_ROOT      — sandboxed agents must run inside this directory
#   AGENT_NONO_PROFILE      — full path to nono profile JSON
#   AGENT_CREDENTIALS       — space-separated "SERVICE:ENV_VAR:secret-file-name" triples
#                             SERVICE = nono credential service name (matches custom_credentials key)
#                             ENV_VAR = env var name (loaded into parent env for env:// URI)
#                             secret-file-name = filename under /run/secrets/
# Launch logging:
#   Single sink: journald via logger -t agent-launch (root-owned, append-only).
#   Only structured metadata is logged — no raw arguments, prompts, or file paths.
#   Query: journalctl -t agent-launch
#
# @decision AUDIT-117-01: Single-sink journald launch logging. File-based audit log removed
#   (was user-owned/tamperable and leaked raw arguments). journald is root-owned and
#   append-only from the agent user's perspective.

set -euo pipefail

: "${AGENT_NAME:?must be set}"
: "${AGENT_REAL_BINARY:?must be set}"
: "${AGENT_PROJECT_ROOT:?must be set}"
: "${AGENT_NONO_PROFILE:?must be set}"

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
    exit 1 ;;
esac

# Load API keys from /run/secrets/ into parent env for nono's env:// credential URIs.
# Format: "SERVICE:ENV_VAR:secret-file-name" triples.
IFS=' ' read -ra cred_triples <<< "$AGENT_CREDENTIALS"
for triple in "${cred_triples[@]}"; do
  # Split SERVICE:ENV_VAR:secret-file-name
  IFS=: read -r _service env_var secret_name <<< "$triple"
  secret_file="/run/secrets/$secret_name"
  if [[ -f "$secret_file" ]]; then
    declare -x "${env_var}=$(cat "$secret_file")"
  else
    echo "WARNING: $env_var not loaded — $secret_file not found" >&2
    declare -x "${env_var}="
  fi
done

# Scope sandbox read access to the current git repository root.
# Fail closed: refuse to run outside a git worktree (no silent fallback to $cwd).
git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: $AGENT_NAME must run inside a git worktree beneath $AGENT_PROJECT_ROOT" >&2
  exit 1
}
git_root="$(readlink -f "$git_root")"
if [[ "$git_root" == "$AGENT_PROJECT_ROOT" ]]; then
  echo "ERROR: refusing to grant read access to the entire project root ($AGENT_PROJECT_ROOT)" >&2
  exit 1
fi
repo_scope="git-worktree"

# Build nono arguments — proxy credential mode (phantom token pattern).
# nono's reverse proxy reads real keys from parent env via env:// URIs,
# generates per-session phantom tokens, and only exposes those to the child.
nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback --read "$git_root")

# Enable proxy credential injection for each loaded service
for triple in "${cred_triples[@]}"; do
  IFS=: read -r service env_var _secret_name <<< "$triple"
  val="${!env_var:-}"
  if [[ -n "$val" && "$val" != PLACEHOLDER* ]]; then
    nono_args+=(--credential "$service")
  fi
done

nono_args+=(-- "$AGENT_REAL_BINARY" "$@")
journal_log "sandboxed"
exec nono "${nono_args[@]}"
