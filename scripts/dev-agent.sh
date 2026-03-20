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

# Write the claude invocation to an executable script, then have zmx run that
# script directly. zmx run sends args through bash in the session, stripping
# quotes — shell metacharacters in inline prompts cause syntax errors. A
# pre-built script sidesteps this entirely.
TASK_SCRIPT=$(mktemp /tmp/dev-agent-task.XXXXXX)
chmod +x "$TASK_SCRIPT"
cat > "$TASK_SCRIPT" << 'TASK'
#!/usr/bin/env bash
exec claude -p --permission-mode=bypassPermissions \
  'Conduct a literature search for projects similar to tsurf - NixOS configurations combined with AI agent infrastructure. Focus on projects with commits in the last few weeks. Check GitHub for recent activity. Document findings in /data/projects/tsurf/RESEARCH.md with: project name, repo URL, last commit date, key features, relevance score 1-10, and adoption recommendations. Use WebSearch and WebFetch tools.'
TASK

exec zmx run dev-agent "$TASK_SCRIPT"
