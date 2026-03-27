#!/usr/bin/env bash
# tsurf.sh — Opinionated wrapper for quickstart init/deploy/status workflows.
# @decision ONBOARD-201-02: The top-level CLI owns a generated local overlay under .tsurf/ so users do not have to assemble a private overlay before the first test deploy.
set -euo pipefail

real_dir() {
  local dir="$1"
  (
    cd "$dir"
    pwd -P
  )
}

abs_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(pwd -P)/$path"
  fi
}

resolve_repo_dir() {
  local candidate=""

  if [[ -n "${TSURF_REPO_DIR:-}" && -f "${TSURF_REPO_DIR}/flake.nix" ]]; then
    real_dir "${TSURF_REPO_DIR}"
    return 0
  fi

  candidate="$PWD"
  while [[ "$candidate" != "/" ]]; do
    if [[ -f "$candidate/flake.nix" && -f "$candidate/README.md" && -f "$candidate/scripts/tsurf.sh" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate="$(dirname "$candidate")"
  done

  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P 2>/dev/null || true)"
    if [[ -f "$candidate/flake.nix" && -f "$candidate/README.md" && -f "$candidate/scripts/tsurf.sh" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  echo "ERROR: could not determine the tsurf repo directory." >&2
  exit 1
}

resolve_script_source_dir() {
  if [[ -n "${TSURF_BUNDLED_SCRIPT_DIR:-}" && -f "${TSURF_BUNDLED_SCRIPT_DIR}/deploy.sh" ]]; then
    printf '%s\n' "${TSURF_BUNDLED_SCRIPT_DIR}"
    return 0
  fi

  printf '%s\n' "${REPO_DIR}/scripts"
}

resolve_flake_template() {
  if [[ -n "${TSURF_BUNDLED_FLAKE_TEMPLATE:-}" && -f "${TSURF_BUNDLED_FLAKE_TEMPLATE}" ]]; then
    printf '%s\n' "${TSURF_BUNDLED_FLAKE_TEMPLATE}"
    return 0
  fi

  printf '%s\n' "${REPO_DIR}/examples/quickstart-overlay/flake.nix.template"
}

resolve_host_template() {
  if [[ -n "${TSURF_BUNDLED_HOST_TEMPLATE:-}" && -f "${TSURF_BUNDLED_HOST_TEMPLATE}" ]]; then
    printf '%s\n' "${TSURF_BUNDLED_HOST_TEMPLATE}"
    return 0
  fi

  printf '%s\n' "${REPO_DIR}/examples/quickstart-overlay/host.nix.template"
}

resolve_overlay_readme() {
  if [[ -n "${TSURF_BUNDLED_OVERLAY_README:-}" && -f "${TSURF_BUNDLED_OVERLAY_README}" ]]; then
    printf '%s\n' "${TSURF_BUNDLED_OVERLAY_README}"
    return 0
  fi

  printf '%s\n' "${REPO_DIR}/examples/quickstart-overlay/README.md"
}

default_config_path() {
  if [[ -n "${TSURF_CONFIG:-}" ]]; then
    abs_path "${TSURF_CONFIG}"
    return 0
  fi

  printf '%s\n' "${REPO_DIR}/.tsurf/config"
}

load_config() {
  CONFIG_PATH="$(default_config_path)"
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    echo "ERROR: missing ${CONFIG_PATH}. Run 'tsurf init <root@host>' first." >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "${CONFIG_PATH}"
}

usage() {
  cat <<'USAGE'
Usage:
  tsurf init <root@host|host> [options]
  tsurf deploy [options]
  tsurf status [node|host|all ...]
  tsurf config

Commands:
  init       Generate a local quickstart overlay in .tsurf/ and a root SSH key
  deploy     Deploy the generated overlay using the saved defaults
  status     Check persistent unit status for the saved node (or explicit targets)
  config     Print the saved quickstart configuration

Init options:
  --name NAME                 Deploy node name (default: quickstart)
  --hostname NAME             NixOS hostname inside the generated config (default: --name)
  --system SYSTEM             Nix system value (default: x86_64-linux)
  --state-version VERSION     NixOS stateVersion (default: 25.11)
  --overlay-dir DIR           Overlay output directory (default: .tsurf/overlay)
  --key-path PATH             Root SSH key path (default: .tsurf/keys/tsurf-root)
  --force                     Replace an existing generated overlay/config

Deploy options:
  --fast                      Local build, single evaluation
  --mode local|remote         Override deploy mode
  --first-deploy              Disable magic rollback for initial adoption
  --magic-rollback            Enable deploy-rs magic rollback
  --target USER@HOST          Override SSH target for checks/locking
  --node NAME                 Override saved deploy node
USAGE
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

render_template() {
  local src="$1"
  local dst="$2"
  sed \
    -e "s/__TSURF_SOURCE__/$(escape_sed_replacement "${TEMPLATE_TSURF_SOURCE}")/g" \
    -e "s/__TSURF_SYSTEM__/$(escape_sed_replacement "${TEMPLATE_SYSTEM}")/g" \
    -e "s/__TSURF_NODE__/$(escape_sed_replacement "${TEMPLATE_NODE}")/g" \
    -e "s/__TSURF_TARGET_HOST__/$(escape_sed_replacement "${TEMPLATE_TARGET_HOST}")/g" \
    -e "s/__TSURF_SSH_USER__/$(escape_sed_replacement "${TEMPLATE_SSH_USER}")/g" \
    -e "s/__TSURF_HOSTNAME__/$(escape_sed_replacement "${TEMPLATE_HOSTNAME}")/g" \
    -e "s/__TSURF_TIMEZONE__/$(escape_sed_replacement "${TEMPLATE_TIMEZONE}")/g" \
    -e "s/__TSURF_STATE_VERSION__/$(escape_sed_replacement "${TEMPLATE_STATE_VERSION}")/g" \
    "$src" > "$dst"
}

sanitize_name() {
  local raw="$1"
  raw="${raw,,}"
  raw="${raw//[^a-z0-9-]/-}"
  raw="${raw#-}"
  raw="${raw%-}"
  if [[ -z "$raw" ]]; then
    raw="quickstart"
  fi
  printf '%s\n' "$raw"
}

parse_target() {
  local raw="$1"
  if [[ "$raw" == *@* ]]; then
    TARGET_SSH_USER="${raw%@*}"
    TARGET_HOST="${raw#*@}"
  else
    TARGET_SSH_USER="root"
    TARGET_HOST="$raw"
  fi

  if [[ -z "$TARGET_HOST" ]]; then
    echo "ERROR: invalid target '$raw'" >&2
    exit 1
  fi

  if [[ "${TARGET_SSH_USER}" != "root" ]]; then
    echo "ERROR: quickstart currently expects root SSH access. Use root@host." >&2
    exit 1
  fi
}

write_config() {
  local config_dir
  config_dir="$(dirname "${CONFIG_PATH}")"
  mkdir -p "${config_dir}"

  {
    printf '# .tsurf/config\n'
    printf '# Generated by tsurf init. Safe to edit locally; kept out of git by .gitignore.\n'
    printf 'TSURF_REPO_DIR=%q\n' "${REPO_DIR}"
    printf 'TSURF_OVERLAY_DIR=%q\n' "${OVERLAY_DIR}"
    printf 'TSURF_KEY_PATH=%q\n' "${KEY_PATH}"
    printf 'TSURF_NODE=%q\n' "${NODE}"
    printf 'TSURF_HOSTNAME=%q\n' "${HOSTNAME_VALUE}"
    printf 'TSURF_TARGET=%q\n' "${TARGET}"
    printf 'TSURF_TARGET_HOST=%q\n' "${TARGET_HOST}"
    printf 'TSURF_SSH_USER=%q\n' "${SSH_USER}"
    printf 'TSURF_SYSTEM=%q\n' "${SYSTEM_VALUE}"
    printf 'TSURF_STATE_VERSION=%q\n' "${STATE_VERSION}"
  } > "${CONFIG_PATH}"
}

copy_helper_scripts() {
  mkdir -p "${OVERLAY_DIR}/scripts"
  install -m 755 "${SCRIPT_SOURCE_DIR}/deploy.sh" "${OVERLAY_DIR}/scripts/deploy.sh"
  install -m 755 "${SCRIPT_SOURCE_DIR}/tsurf-status.sh" "${OVERLAY_DIR}/scripts/tsurf-status.sh"
}

init_command() {
  local target_arg=""
  local force=false
  local overlay_dir_input=""
  local key_path_input=""

  NODE="quickstart"
  HOSTNAME_VALUE=""
  SYSTEM_VALUE="x86_64-linux"
  STATE_VERSION="25.11"
  SSH_USER="root"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        NODE="$(sanitize_name "$2")"
        shift 2
        ;;
      --hostname)
        HOSTNAME_VALUE="$2"
        shift 2
        ;;
      --system)
        SYSTEM_VALUE="$2"
        shift 2
        ;;
      --state-version)
        STATE_VERSION="$2"
        shift 2
        ;;
      --overlay-dir)
        overlay_dir_input="$2"
        shift 2
        ;;
      --key-path)
        key_path_input="$2"
        shift 2
        ;;
      --force)
        force=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        echo "ERROR: unknown init option '$1'" >&2
        exit 1
        ;;
      *)
        if [[ -n "$target_arg" ]]; then
          echo "ERROR: init accepts a single target argument" >&2
          exit 1
        fi
        target_arg="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$target_arg" ]]; then
    echo "ERROR: init requires a target like root@server.example.com" >&2
    exit 1
  fi

  parse_target "$target_arg"
  TARGET="root@${TARGET_HOST}"
  if [[ -z "${HOSTNAME_VALUE}" ]]; then
    HOSTNAME_VALUE="${NODE}"
  fi

  OVERLAY_DIR="${overlay_dir_input:-${REPO_DIR}/.tsurf/overlay}"
  KEY_PATH="${key_path_input:-${REPO_DIR}/.tsurf/keys/tsurf-root}"
  OVERLAY_DIR="$(abs_path "${OVERLAY_DIR}")"
  KEY_PATH="$(abs_path "${KEY_PATH}")"
  CONFIG_PATH="$(default_config_path)"
  SCRIPT_SOURCE_DIR="$(resolve_script_source_dir)"
  FLAKE_TEMPLATE="$(resolve_flake_template)"
  HOST_TEMPLATE="$(resolve_host_template)"
  OVERLAY_README="$(resolve_overlay_readme)"

  if [[ -e "${OVERLAY_DIR}" && "${force}" != true ]]; then
    echo "ERROR: ${OVERLAY_DIR} already exists. Re-run with --force to replace it." >&2
    exit 1
  fi

  if [[ -f "${CONFIG_PATH}" && "${force}" != true ]]; then
    echo "ERROR: ${CONFIG_PATH} already exists. Re-run with --force to replace it." >&2
    exit 1
  fi

  if [[ "${force}" == true ]]; then
    rm -rf "${OVERLAY_DIR}"
    rm -f "${CONFIG_PATH}"
  fi

  mkdir -p "${OVERLAY_DIR}/hosts/${NODE}" "${OVERLAY_DIR}/modules"
  install -m 644 "${OVERLAY_README}" "${OVERLAY_DIR}/README.md"

  TEMPLATE_TSURF_SOURCE="path:${REPO_DIR}"
  TEMPLATE_SYSTEM="${SYSTEM_VALUE}"
  TEMPLATE_NODE="${NODE}"
  TEMPLATE_TARGET_HOST="${TARGET_HOST}"
  TEMPLATE_SSH_USER="${SSH_USER}"
  TEMPLATE_HOSTNAME="${HOSTNAME_VALUE}"
  TEMPLATE_TIMEZONE="$(timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
  TEMPLATE_STATE_VERSION="${STATE_VERSION}"

  render_template "${FLAKE_TEMPLATE}" "${OVERLAY_DIR}/flake.nix"
  render_template "${HOST_TEMPLATE}" "${OVERLAY_DIR}/hosts/${NODE}/default.nix"
  copy_helper_scripts

  bash "${SCRIPT_SOURCE_DIR}/tsurf-init.sh" --key-path "${KEY_PATH}" --overlay-dir "${OVERLAY_DIR}" >/dev/null
  write_config

  cat <<EOF
Quickstart overlay created.

  Config:  ${CONFIG_PATH}
  Overlay: ${OVERLAY_DIR}
  Target:  ${TARGET}
  Node:    ${NODE}

Next:
  ./tsurf deploy
  ./tsurf status
EOF
}

deploy_command() {
  local args=()

  load_config

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fast|--first-deploy|--magic-rollback)
        args+=("$1")
        shift
        ;;
      --mode|--target|--node)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: $1 requires a value" >&2
          exit 1
        fi
        if [[ "$1" == "--node" ]]; then
          TSURF_NODE="$2"
        elif [[ "$1" == "--target" ]]; then
          TSURF_TARGET="$2"
        else
          args+=("$1" "$2")
        fi
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown deploy option '$1'" >&2
        exit 1
        ;;
    esac
  done

  args+=(--node "${TSURF_NODE}" --target "${TSURF_TARGET}")
  exec bash "${TSURF_OVERLAY_DIR}/scripts/deploy.sh" "${args[@]}"
}

status_command() {
  load_config

  if [[ $# -eq 0 ]]; then
    set -- "${TSURF_NODE}"
  fi

  exec bash "${TSURF_OVERLAY_DIR}/scripts/tsurf-status.sh" "$@"
}

config_command() {
  load_config

  cat <<EOF
config:   ${CONFIG_PATH}
repo:     ${TSURF_REPO_DIR}
overlay:  ${TSURF_OVERLAY_DIR}
key:      ${TSURF_KEY_PATH}
node:     ${TSURF_NODE}
hostname: ${TSURF_HOSTNAME}
target:   ${TSURF_TARGET}
system:   ${TSURF_SYSTEM}
state:    ${TSURF_STATE_VERSION}
EOF
}

REPO_DIR="$(resolve_repo_dir)"

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

case "$1" in
  init)
    shift
    init_command "$@"
    ;;
  deploy)
    shift
    deploy_command "$@"
    ;;
  status)
    shift
    status_command "$@"
    ;;
  config)
    shift
    config_command "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "ERROR: unknown command '$1'" >&2
    usage
    exit 1
    ;;
esac
