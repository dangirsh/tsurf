#!/usr/bin/env bash
# Clone project repos on activation. Called from hosts/dev/default.nix activationScript.
# Expects GIT_BIN and GITHUB_PAT_FILE to be set by the Nix caller.
# @decision SEC-124-02: Uses GIT_ASKPASS helper to avoid leaking PAT on command line.
#   The helper reads the token from _GIT_TOKEN env var. git invokes the helper
#   instead of prompting - the token never appears in /proc/*/cmdline.
set -euo pipefail

# Add repos to clone here. Example: repos=("your-org/your-repo")
repos=()
CLONE_DIR="/data/projects"
GH_TOKEN="$(cat "$GITHUB_PAT_FILE" 2>/dev/null || true)"
mkdir -p "$CLONE_DIR"

# Skip if no repos configured or no token available
if [[ ${#repos[@]} -eq 0 || -z "$GH_TOKEN" ]]; then
  exit 0
fi

# Create a temporary GIT_ASKPASS helper that returns the token.
# git calls this helper with a prompt string as $1 - we ignore the prompt
# and return the token for any password request.
ASKPASS_HELPER=$(mktemp /tmp/git-askpass.XXXXXX)
chmod 700 "$ASKPASS_HELPER"
cat > "$ASKPASS_HELPER" << 'HELPER'
#!/usr/bin/env bash
# Return the token for password prompts, empty for username prompts.
case "$1" in
  *Password*|*password*) printf '%s\n' "$_GIT_TOKEN" ;;
  *Username*|*username*) printf '%s\n' "x-access-token" ;;
  *) printf '%s\n' "$_GIT_TOKEN" ;;
esac
HELPER

cleanup() { rm -f "$ASKPASS_HELPER"; }
trap cleanup EXIT

export _GIT_TOKEN="$GH_TOKEN"
export GIT_ASKPASS="$ASKPASS_HELPER"
export GIT_TERMINAL_PROMPT=0

for repo in "${repos[@]}"; do
  name="$(basename "$repo")"
  target="$CLONE_DIR/$name"
  if [[ ! -d "$target" ]]; then
    echo "Cloning $repo to $target..."
    "$GIT_BIN" clone "https://github.com/$repo.git" "$target" \
      || echo "WARNING: Failed to clone $repo (will retry on next activation)"
    chown -R agent:users "$target" 2>/dev/null || true
  fi
done
