#!/usr/bin/env bash
# Resolve Iron placeholder capabilities after the UID drop without ever placing
# a bearer value in process arguments. The root launcher opens descriptor 3;
# this helper runs as the sandboxed agent and closes the descriptor before exec.
set -euo pipefail

umask 077
ulimit -c 0

token_map="${TSURF_IRON_TOKEN_MAP:-}"
if [[ -z "$token_map" ]]; then
  echo "ERROR: missing TSURF_IRON_TOKEN_MAP" >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  echo "ERROR: missing child command" >&2
  exit 1
fi
if ! : <&3 2>/dev/null; then
  echo "ERROR: missing Iron token descriptor" >&2
  exit 1
fi

declare -A token_values=()
while IFS='=' read -r token_name token_value || [[ -n "$token_name" ]]; do
  [[ -n "$token_name" ]] || continue
  if [[ ! "$token_name" =~ ^TSURF_IRON_TOKEN_[A-Z0-9_]+$ || ${#token_value} -lt 32 ]]; then
    echo "ERROR: invalid Iron token descriptor entry" >&2
    exit 1
  fi
  if [[ -n "${token_values[$token_name]+set}" ]]; then
    echo "ERROR: duplicate Iron token descriptor entry" >&2
    exit 1
  fi
  token_values["$token_name"]="$token_value"
done <&3
exec 3<&-

declare -A exported_names=()
IFS=' ' read -ra token_pairs <<< "$token_map"
for pair in "${token_pairs[@]}"; do
  [[ -n "$pair" ]] || continue
  IFS=: read -r env_var token_name extra <<< "$pair"
  if [[ -n "${extra:-}" || ! "$env_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ || ! "$token_name" =~ ^TSURF_IRON_TOKEN_[A-Z0-9_]+$ ]]; then
    echo "ERROR: invalid Iron token mapping" >&2
    exit 1
  fi
  if [[ -n "${exported_names[$env_var]+set}" ]]; then
    echo "ERROR: duplicate Iron token environment name" >&2
    exit 1
  fi
  if [[ -z "${token_values[$token_name]+set}" ]]; then
    echo "ERROR: requested Iron token is unavailable" >&2
    exit 1
  fi
  printf -v "$env_var" '%s' "${token_values[$token_name]}"
  export "$env_var"
  exported_names["$env_var"]=1
done

unset token_map token_pairs pair env_var token_name token_value extra
unset token_values exported_names TSURF_IRON_TOKEN_MAP
exec "$@"
