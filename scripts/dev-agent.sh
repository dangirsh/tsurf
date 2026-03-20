#!/usr/bin/env bash
set -euo pipefail

# Set XDG_RUNTIME_DIR from actual UID (systemd %U resolves to root in system units)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# API key loading handled by agent-wrapper.sh via AGENT_CREDENTIALS.
# @decision DEV-AGENT-114-01: No raw API keys in parent env — wrapper reads
#   from /run/secrets/ and injects via nono --env-credential-map.

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
