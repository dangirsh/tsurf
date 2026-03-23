#!/usr/bin/env bash
set -euo pipefail

# Set XDG_RUNTIME_DIR from actual UID (systemd %U resolves to root in system units)
XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR

# API key loading handled by agent-wrapper.sh via AGENT_CREDENTIALS.
# @decision DEV-AGENT-118-01: No raw API keys reach the child process — wrapper reads
#   from /run/secrets/ into the parent env, nono's proxy loads them via env:// URIs,
#   and the child receives only per-session phantom tokens (--credential flag).

# Write the claude invocation to an executable script, then have zmx run that
# script directly. zmx run sends args through bash in the session, stripping
# quotes — shell metacharacters in inline prompts cause syntax errors. A
# pre-built script sidesteps this entirely.
TASK_SCRIPT="$XDG_RUNTIME_DIR/dev-agent-task.sh"
umask 077
cat > "$TASK_SCRIPT" << 'TASK'
#!/usr/bin/env bash
# WorkingDirectory is set by systemd via services.devAgent.workingDirectory.
# Do NOT hardcode a path here; the module option controls it.
exec claude --model claude-opus-4-6 -p --permission-mode=bypassPermissions \
  'Conduct a literature search for projects similar to tsurf - NixOS configurations combined with AI agent infrastructure. Focus on projects with commits in the last few weeks. Check GitHub for recent activity. Document findings in ./RESEARCH.md with: project name, repo URL, last commit date, key features, relevance score 1-10, and adoption recommendations. Use WebSearch and WebFetch tools.'
TASK
chmod 700 "$TASK_SCRIPT"

exec zmx run dev-agent "$TASK_SCRIPT"
