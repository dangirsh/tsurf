{ writeShellApplication, coreutils }:
writeShellApplication {
  name = "sandbox-probe-e2e";
  runtimeInputs = [ coreutils ];
  text = ''
    set -euo pipefail

    out_path="''${1:?usage: sandbox-probe-e2e <output-path>}"

    mkdir -p "$(dirname "$out_path")"

    probe_tmp="$(mktemp "$PWD/.sandbox-probe-e2e.XXXXXX")"
    rm -f "$probe_tmp"

    if test -r /run/secrets/anthropic-api-key; then
      secrets_read="readable"
    else
      secrets_read="denied"
    fi

    if ls "$HOME/.ssh" >/dev/null 2>&1; then
      ssh_read="readable"
    else
      ssh_read="denied"
    fi

    if test -r README.md; then
      repo_read="readable"
    else
      repo_read="denied"
    fi

    cat > "$out_path" <<EOF
user=$(id -un)
uid=$(id -u)
pwd=$PWD
anthropic_api_key=''${ANTHROPIC_API_KEY:-}
anthropic_base_url=''${ANTHROPIC_BASE_URL:-}
secrets_read=$secrets_read
ssh_read=$ssh_read
repo_read=$repo_read
workdir_write=ok
EOF

    cat "$out_path"
  '';
}
