---
phase: 05-user-environment-dev-tools
plan: 01
subsystem: infra
tags: [home-manager, bash, tmux, git, ssh, direnv, sops-nix, mosh, nix]

requires:
  - phase: 03-networking-secrets-docker-foundation
    provides: sops-nix secrets infrastructure and SSH access
provides:
  - 5 home-manager modules (bash, tmux, git, ssh, direnv)
  - 11 system packages including Node.js
  - 3 new sops-nix secrets (API keys + GitHub PAT)
  - Mosh server for roaming connections
  - SSH agent forwarding
affects: [05-02-agent-compute, 06-user-services]

tech-stack:
  added: [home-manager bash/tmux/git/ssh/direnv modules, mosh, nix-direnv, yq-go]
  patterns: [secret injection via bash initExtra + cat /run/secrets/, home-manager module-per-concern]

key-files:
  created: [home/bash.nix, home/tmux.nix, home/git.nix, home/ssh.nix, home/direnv.nix]
  modified: [modules/base.nix, modules/networking.nix, modules/secrets.nix, home/default.nix, secrets/acfs.yaml]

key-decisions:
  - "Secret env vars via bash initExtra + cat /run/secrets/ (not sessionVariables)"
  - "gh CLI uses GH_TOKEN env var (no gh settings to avoid read-only symlink issue)"
  - "yq-go package name (not yq which is Python wrapper)"
  - "sops secrets with PLACEHOLDER values (user must replace before deploy)"

duration: 22min
completed: 2026-02-16
---

# Phase 5 Plan 01: Home Environment + System Packages + Secrets Summary

**5 home-manager modules (bash, tmux, git, ssh, direnv), 11 system packages, 3 sops-nix API key secrets, mosh server, and SSH agent — agent-ready user environment**

## Performance

- **Duration:** 22 min
- **Started:** 2026-02-16T14:00:00Z
- **Completed:** 2026-02-16T14:22:00Z
- **Tasks:** 2
- **Files modified:** 10

## Accomplishments
- Bash shell with runtime secret injection (GH_TOKEN, ANTHROPIC_API_KEY, OPENAI_API_KEY)
- 11 system packages on PATH (git, curl, wget, rsync, jq, yq-go, ripgrep, fd, tmux, btop, nodejs)
- Tmux with mouse mode, git identity + gh CLI, SSH client ControlMaster, direnv + nix-direnv
- Mosh server enabled for roaming connections
- 3 sops-nix secrets declared with dangirsh ownership

## Task Commits

1. **Task 1: Add system packages, mosh server, and SSH agent** - `f05d421` (feat)
2. **Task 2: Create home-manager modules and add sops secrets** - `570de5f` (feat)

## Files Created/Modified
- `home/bash.nix` - Bash shell with 3 secret env var exports via initExtra
- `home/tmux.nix` - Tmux with mouse mode, 256color, 50k history
- `home/git.nix` - Git identity (Dan Girshovich) + gh CLI (GH_TOKEN auth)
- `home/ssh.nix` - SSH client with ControlMaster auto, 10m persist
- `home/direnv.nix` - direnv + nix-direnv for devShell auto-loading
- `home/default.nix` - Imports all 5 new modules
- `modules/base.nix` - 11 system packages + programs.ssh.startAgent
- `modules/networking.nix` - programs.mosh.enable = true
- `modules/secrets.nix` - 3 new secrets with owner = dangirsh
- `secrets/acfs.yaml` - Encrypted PLACEHOLDER values for API keys

## Decisions Made
- Secret env vars injected via `bash initExtra` using `cat /run/secrets/...` at shell start (not sessionVariables which writes to ~/.profile unreliably)
- gh CLI auth via GH_TOKEN env var (no `programs.gh.settings` to avoid read-only config.yml symlink issue)
- Used `yq-go` package name (Go-based yq, not `yq` which is Python jq wrapper)
- PLACEHOLDER values in encrypted secrets — user must replace with real API keys before deployment

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] sops encrypt --filename-override needed for worktree**
- **Found during:** Task 2 (secrets encryption)
- **Issue:** `sops encrypt` in worktree failed with "no matching creation rules" because .sops.yaml path rules match `secrets/acfs.yaml` relative to repo root
- **Fix:** Used `--filename-override secrets/acfs.yaml` flag to match .sops.yaml creation rules
- **Files modified:** secrets/acfs.yaml
- **Verification:** Encrypted file contains all 8 secrets with valid AES256_GCM encryption
- **Committed in:** 570de5f (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary fix for sops encryption in worktree context. No scope creep.

## Issues Encountered
- `nix flake check` hangs at NixOS configuration evaluation (known system-level issue, documented in Phase 9). `nix flake show` validates successfully. All code changes verified syntactically correct.

## User Setup Required
**API keys must be set before deployment.** Run `sops secrets/acfs.yaml` and replace PLACEHOLDER values:
- `anthropic-api-key` — from Anthropic Console -> API Keys
- `openai-api-key` — from OpenAI Platform -> API Keys
- `github-pat` — from GitHub -> Settings -> Developer settings -> Personal access tokens

## Next Phase Readiness
- Ready for Plan 05-02 (Agent CLIs + compute infrastructure)
- home-manager modules provide the shell environment that agent-spawn will use
- API key secrets will be available as env vars for claude/codex CLIs

---
*Phase: 05-user-environment-dev-tools*
*Completed: 2026-02-16*
