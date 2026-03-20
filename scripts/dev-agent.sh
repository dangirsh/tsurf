#!/usr/bin/env bash
set -euo pipefail

# Set XDG_RUNTIME_DIR from actual UID (systemd %U resolves to root in system units)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Load API key from secrets — the nono sandbox wrapper reads this from parent env
if [[ -f "$ANTHROPIC_API_KEY_FILE" ]]; then
  ANTHROPIC_API_KEY="$(cat "$ANTHROPIC_API_KEY_FILE")"
  export ANTHROPIC_API_KEY
else
  echo "WARNING: ANTHROPIC_API_KEY not loaded from $ANTHROPIC_API_KEY_FILE" >&2
fi

exec zmx run dev-agent claude -p --permission-mode=bypassPermissions \
  "Conduct a literature search for projects similar to tsurf - NixOS configurations combined with AI agent infrastructure. Focus on projects with commits in the last few weeks (check GitHub). Document findings in /data/projects/tsurf/RESEARCH.md with: project name, repo URL, last commit date, key features, relevance score (1-10), and adoption recommendations. Use WebSearch and WebFetch tools."
