#!/usr/bin/env bash
# Clone project repos on activation. Called from hosts/dev/default.nix activationScript.
# Expects GIT_BIN and GITHUB_PAT_FILE to be set by the Nix caller.
set -euo pipefail

# Add repos to clone here. Example: repos=("your-org/your-repo")
repos=()
CLONE_DIR="/data/projects"
GH_TOKEN="$(cat "$GITHUB_PAT_FILE" 2>/dev/null || true)"
mkdir -p "$CLONE_DIR"
for repo in "${repos[@]}"; do
  name="$(basename "$repo")"
  target="$CLONE_DIR/$name"
  if [[ ! -d "$target" ]]; then
    echo "Cloning $repo to $target..."
    GIT_TERMINAL_PROMPT=0 "$GIT_BIN" \
      -c "http.https://github.com/.extraheader=Authorization: Bearer $GH_TOKEN" \
      clone "https://github.com/$repo.git" "$target" \
      || echo "WARNING: Failed to clone $repo (will retry on next activation)"
    chown -R dev:users "$target" 2>/dev/null || true
  fi
done
