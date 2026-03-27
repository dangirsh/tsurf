#!/usr/bin/env bash
# tests/unit/tsurf-cli.bash — unit tests for the top-level tsurf quickstart wrapper.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORKDIR="${TSURF_TEST_TMPDIR:-$PWD}/tsurf-cli"
FAKE_BIN="${WORKDIR}/bin"
OVERLAY_DIR="${WORKDIR}/generated-overlay"
KEY_PATH="${WORKDIR}/keys/tsurf-root"
CONFIG_PATH="${WORKDIR}/config"
DEPLOY_LOG="${WORKDIR}/deploy.log"
STATUS_LOG="${WORKDIR}/status.log"

rm -rf "${WORKDIR}"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/timedatectl" <<'EOF'
#!/usr/bin/env bash
printf 'UTC\n'
EOF
chmod 700 "${FAKE_BIN}/timedatectl"

cat > "${FAKE_BIN}/ssh" <<EOF
#!${BASH}
set -euo pipefail
target=""
for arg in "\$@"; do
  if [[ "\$arg" == root@test.example ]]; then
    target="\$arg"
    break
  fi
done

if [[ -z "\$target" ]]; then
  echo "unexpected ssh args: \$*" >&2
  exit 1
fi

if [[ "\$*" == *"bash -lc"* ]]; then
  printf 'id=nixos\nversion=24.11\nlabbox\n'
  exit 0
fi

printf '%s\n' "\$*" > "${WORKDIR}/ssh-command.log"
EOF
chmod 700 "${FAKE_BIN}/ssh"

export TSURF_REPO_DIR="${ROOT_DIR}"
export TSURF_CONFIG="${CONFIG_PATH}"
export PATH="${FAKE_BIN}:$PATH"

bash "${ROOT_DIR}/scripts/tsurf.sh" init root@test.example \
  --name lab \
  --overlay-dir "${OVERLAY_DIR}" \
  --key-path "${KEY_PATH}"

[[ -f "${CONFIG_PATH}" ]] || {
  echo "FAIL: tsurf init did not create config"
  exit 1
}
[[ -f "${OVERLAY_DIR}/flake.nix" ]] || {
  echo "FAIL: tsurf init did not create overlay flake"
  exit 1
}
[[ -f "${OVERLAY_DIR}/modules/root-ssh.nix" ]] || {
  echo "FAIL: tsurf init did not generate root-ssh.nix"
  exit 1
}
[[ -f "${KEY_PATH}" && -f "${KEY_PATH}.pub" ]] || {
  echo "FAIL: tsurf init did not generate the root SSH key pair"
  exit 1
}

grep -q "path:${ROOT_DIR}" "${OVERLAY_DIR}/flake.nix" || {
  echo "FAIL: generated overlay did not point back at the local tsurf checkout"
  exit 1
}
grep -q 'networking.hostName = "labbox";' "${OVERLAY_DIR}/hosts/lab/default.nix" || {
  echo "FAIL: generated host config did not adopt the probed hostname"
  exit 1
}
grep -q 'system.stateVersion = "24.11";' "${OVERLAY_DIR}/hosts/lab/default.nix" || {
  echo "FAIL: generated host config did not adopt the probed release"
  exit 1
}
grep -q 'hostname = "test.example";' "${OVERLAY_DIR}/flake.nix" || {
  echo "FAIL: generated overlay did not store the target host"
  exit 1
}
grep -q 'TSURF_NODE=lab' "${CONFIG_PATH}" || {
  echo "FAIL: config file missing saved node"
  exit 1
}

cat > "${OVERLAY_DIR}/scripts/deploy.sh" <<EOF
#!${BASH}
set -euo pipefail
printf '%s\n' "\$*" > "${DEPLOY_LOG}"
EOF
chmod 700 "${OVERLAY_DIR}/scripts/deploy.sh"

cat > "${OVERLAY_DIR}/scripts/tsurf-status.sh" <<EOF
#!${BASH}
set -euo pipefail
printf '%s\n' "\$*" > "${STATUS_LOG}"
EOF
chmod 700 "${OVERLAY_DIR}/scripts/tsurf-status.sh"

bash "${ROOT_DIR}/scripts/tsurf.sh" deploy --fast
bash "${ROOT_DIR}/scripts/tsurf.sh" status
bash "${ROOT_DIR}/scripts/tsurf.sh" ssh uname -a

[[ "$(cat "${DEPLOY_LOG}")" == *"--fast"* ]] || {
  echo "FAIL: tsurf deploy did not forward --fast"
  exit 1
}
[[ "$(cat "${DEPLOY_LOG}")" == *"--node lab --target root@test.example"* ]] || {
  echo "FAIL: tsurf deploy did not use the saved node/target"
  exit 1
}
[[ "$(cat "${STATUS_LOG}")" == "lab" ]] || {
  echo "FAIL: tsurf status did not default to the saved node"
  exit 1
}
[[ "$(cat "${WORKDIR}/ssh-command.log")" == *"root@test.example uname -a"* ]] || {
  echo "FAIL: tsurf ssh did not forward the saved target"
  exit 1
}

echo "PASS: tsurf-cli unit tests"
