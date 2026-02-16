---
phase: 05-user-environment-dev-tools
verified: 2026-02-16T16:00:00Z
status: human_needed
score: 8/8
re_verification: false
human_verification:
  - test: "SSH into server and verify shell environment"
    expected: "User lands in bash, direnv auto-loads project devShells, all 11 system packages on PATH"
    why_human: "Interactive shell behavior, devShell auto-loading requires direnv hooks in live environment"
  - test: "Verify secrets are injected into shell environment"
    expected: "echo $ANTHROPIC_API_KEY, $OPENAI_API_KEY, $GH_TOKEN all show values (not empty)"
    why_human: "Runtime secret injection from /run/secrets/ — requires live sops-nix decryption on deployed system"
  - test: "Verify git and gh CLI authentication"
    expected: "git config user.name returns 'Dan Girshovich', gh auth status shows authenticated"
    why_human: "Git config and gh CLI require live environment with secrets"
  - test: "Verify agent CLIs are available"
    expected: "which claude and which codex return paths to binaries"
    why_human: "Package availability from llm-agents overlay — requires live system with overlay applied"
  - test: "Verify agent-spawn creates isolated tmux sessions"
    expected: "agent-spawn test-agent /tmp claude creates tmux session, tmux ls shows it, systemd-cgls shows agent.slice"
    why_human: "Systemd cgroup isolation and tmux session management — requires live systemd user instance with linger"
  - test: "Verify mosh connectivity"
    expected: "mosh dangirsh@<tailscale-ip> connects successfully"
    why_human: "Mosh server listening on UDP 60000-61000 — requires live network and firewall configuration"
  - test: "Verify tmux mouse mode and persistence"
    expected: "tmux sessions persist across SSH disconnects, mouse mode works (scrolling, pane selection)"
    why_human: "Tmux behavior and configuration — requires interactive tmux usage"
---

# Phase 5: User Environment + Dev Tools Verification Report

**Phase Goal:** The server provides an agent-optimized compute environment where AI coding agents can be launched and managed via tmux

**Verified:** 2026-02-16T16:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SSH/mosh into server drops user into bash with direnv auto-loading project devShells | ✓ VERIFIED | home/bash.nix enables bash, home/direnv.nix enables direnv + nix-direnv with enableBashIntegration = true, home/default.nix imports both |
| 2 | Tmux sessions persist across disconnects with mouse mode enabled | ✓ VERIFIED | home/tmux.nix sets mouse = true, terminal = screen-256color, historyLimit = 50000 |
| 3 | git, gh, curl, wget, jq, yq, rg, fd, node, tmux, btop are all on PATH | ✓ VERIFIED | modules/base.nix declares all 11 packages in environment.systemPackages |
| 4 | git config user.name returns "Dan Girshovich" and GH_TOKEN env var authenticates gh CLI | ✓ VERIFIED | home/git.nix sets userName/userEmail, home/bash.nix exports GH_TOKEN from /run/secrets/github-pat |
| 5 | claude and codex CLI commands are available on PATH via llm-agents.nix | ✓ VERIFIED | flake.nix adds llm-agents input + overlay, modules/agent-compute.nix adds pkgs.claude-code and pkgs.codex to systemPackages |
| 6 | agent-spawn <name> <dir> [claude\|codex] creates an isolated tmux session in a cgroup slice | ✓ VERIFIED | modules/agent-compute.nix defines agent-spawn writeShellApplication with systemd-run --user --scope --slice=agent.slice launching tmux |
| 7 | ANTHROPIC_API_KEY and OPENAI_API_KEY are exported from sops-nix secrets | ✓ VERIFIED | modules/secrets.nix declares anthropic-api-key and openai-api-key with owner=dangirsh, home/bash.nix exports both from /run/secrets/ |
| 8 | home-manager is integrated as a NixOS module with bash, tmux, git, ssh, direnv modules | ✓ VERIFIED | flake.nix imports home-manager.nixosModules.home-manager, home/default.nix imports all 5 modules |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `home/bash.nix` | Bash shell with secret env var exports via initExtra | ✓ VERIFIED | 11 lines, exports GH_TOKEN, ANTHROPIC_API_KEY, OPENAI_API_KEY from /run/secrets/ using cat with 2>/dev/null |
| `home/tmux.nix` | Tmux with mouse mode | ✓ VERIFIED | 8 lines, mouse = true, terminal = screen-256color, historyLimit = 50000 |
| `home/git.nix` | Git identity + gh CLI | ✓ VERIFIED | 14 lines, userName = "Dan Girshovich", userEmail set, gh enabled without settings (uses GH_TOKEN env var) |
| `home/ssh.nix` | SSH client config with ControlMaster | ✓ VERIFIED | 9 lines, controlMaster = "auto", controlPersist = "10m", serverAliveInterval = 60 |
| `home/direnv.nix` | direnv + nix-direnv for devShell auto-loading | ✓ VERIFIED | 7 lines, enableBashIntegration = true, nix-direnv.enable = true |
| `home/default.nix` | Imports all 5 home modules | ✓ VERIFIED | 14 lines, imports bash.nix, tmux.nix, git.nix, ssh.nix, direnv.nix |
| `modules/base.nix` | System packages and SSH agent | ✓ VERIFIED | 28 lines, 11 packages including yq-go, ripgrep, fd, nodejs, btop; programs.ssh.startAgent = true |
| `modules/networking.nix` | Mosh server enabled | ✓ VERIFIED | 70 lines, programs.mosh.enable = true at line 10 |
| `modules/secrets.nix` | sops-nix secret declarations for API keys and GitHub PAT | ✓ VERIFIED | 18 lines, declares anthropic-api-key, openai-api-key, github-pat all with owner = "dangirsh" |
| `modules/agent-compute.nix` | Agent spawn script, systemd slice, linger, binary cache | ✓ VERIFIED | 64 lines, defines agent-spawn writeShellApplication, systemd.slices.agent with CPUWeight=100, users.users.dangirsh.linger=true, Numtide binary cache |
| `flake.nix` | llm-agents.nix flake input with overlay | ✓ VERIFIED | 54 lines, llm-agents input at line 26 (no follows), overlay applied at line 42 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| home/bash.nix | modules/secrets.nix | $(cat /run/secrets/...) in initExtra reads sops-decrypted secrets | ✓ WIRED | bash.nix lines 6-8 read /run/secrets/github-pat, anthropic-api-key, openai-api-key; secrets.nix lines 13-15 declare all 3 with owner=dangirsh |
| home/default.nix | home/bash.nix | import | ✓ WIRED | default.nix line 8 imports ./bash.nix |
| modules/agent-compute.nix | flake.nix | pkgs.claude-code and pkgs.codex from overlay | ✓ WIRED | agent-compute.nix lines 39-40 reference pkgs.claude-code and pkgs.codex; flake.nix line 42 applies llm-agents.overlays.default |
| modules/agent-compute.nix | home/bash.nix | agent-spawn launches CLI in env where bash initExtra has exported API keys | ✓ WIRED | agent-spawn script (lines 27-29) launches tmux with CMD in session; bash.nix exports API keys that CLIs will consume in shell environment |
| modules/default.nix | agent-compute.nix | import | ✓ WIRED | default.nix line 9 imports ./agent-compute.nix |

### Requirements Coverage

Not applicable (Phase 5 focused on success criteria from ROADMAP, not formal requirements).

### Anti-Patterns Found

None. No TODO/FIXME/PLACEHOLDER comments in home/ modules or agent-compute.nix. No empty implementations or console.log-only stubs. All files are substantive (7-64 lines each).

### Human Verification Required

All automated checks passed. The following items require human verification on the deployed server:

#### 1. Shell environment and direnv auto-loading

**Test:** SSH into server via Tailscale: `ssh dangirsh@<tailscale-ip>`
**Expected:** 
- User lands in bash shell (not zsh or other)
- `ls` triggers direnv to ask for approval
- `direnv allow` enables devShell auto-loading for that directory
- Subsequent `cd` into the directory auto-activates the devShell

**Why human:** Interactive shell behavior, direnv hooks require live bash session with direnv integration active.

#### 2. Secret injection into shell environment

**Test:** After SSH, run: `echo $ANTHROPIC_API_KEY && echo $OPENAI_API_KEY && echo $GH_TOKEN`
**Expected:** All three commands show non-empty values (not "PLACEHOLDER" and not empty strings)
**Why human:** Runtime secret injection from /run/secrets/ — requires live sops-nix decryption on deployed system. Secrets file is encrypted and can't be verified locally.

#### 3. Git identity and GitHub CLI authentication

**Test:** Run: `git config user.name && git config user.email && gh auth status`
**Expected:** 
- `git config user.name` returns "Dan Girshovich"
- `git config user.email` returns "dan.girshovich@gmail.com"
- `gh auth status` shows "Logged in to github.com as <username>" (using GH_TOKEN env var)

**Why human:** Git config from home-manager and gh CLI authentication using env var — requires live home-manager activation and valid GitHub PAT in secrets.

#### 4. Agent CLI availability

**Test:** Run: `which claude && which codex && claude --version && codex --version`
**Expected:** 
- `which claude` returns a path (e.g., /nix/store/.../bin/claude)
- `which codex` returns a path
- Both `--version` commands succeed (or show help if --version not supported)

**Why human:** Package availability from llm-agents overlay — requires live system with overlay applied and packages substituted from Numtide binary cache.

#### 5. agent-spawn isolated tmux sessions

**Test:** Run: `agent-spawn test-agent /tmp claude`
**Expected:** 
- Command succeeds with message "Agent 'test-agent' spawned in tmux session (agent.slice)"
- `tmux ls` shows a session named "test-agent"
- `systemd-cgls` shows agent.slice with the tmux process under it
- `tmux attach -t test-agent` connects to the session running claude CLI
- Inside tmux: `echo $ANTHROPIC_API_KEY` shows a value (env var inherited from bash)

**Why human:** Systemd cgroup isolation and tmux session management — requires live systemd user instance with linger enabled. Can't verify systemd-run --user without deployed system.

#### 6. Mosh connectivity

**Test:** From a machine on the Tailscale network, run: `mosh dangirsh@<tailscale-ip>`
**Expected:** 
- Mosh connects successfully
- Can type commands and see responsive terminal (not waiting for SSH round-trip)
- Can suspend/resume network connection (e.g., close laptop lid) and mosh reconnects

**Why human:** Mosh server listening on UDP 60000-61000 — requires live network, firewall configuration, and mosh-server service running.

#### 7. Tmux mouse mode and persistence

**Test:** After SSH, run: `tmux new -s test && exit` then `tmux ls`
**Expected:** 
- Tmux session created successfully
- Inside tmux, mouse scrolling works (scrolls tmux history, not terminal scrollback)
- Mouse clicking on panes selects them
- After detaching (Ctrl+B, D) and re-attaching, session state persists
- After SSH disconnect and reconnect, `tmux ls` still shows the session

**Why human:** Tmux behavior and configuration — requires interactive tmux usage to verify mouse mode works correctly.

### User Setup Required Before Deployment

**API keys must be replaced in secrets/acfs.yaml before deployment:**

1. Run: `sops secrets/acfs.yaml`
2. Replace PLACEHOLDER values for:
   - `anthropic-api-key` — from Anthropic Console -> API Keys
   - `openai-api-key` — from OpenAI Platform -> API Keys
   - `github-pat` — from GitHub -> Settings -> Developer settings -> Personal access tokens (classic)
3. Save file (sops re-encrypts automatically)

Without real API keys, the agent CLIs will fail to authenticate.

### Implementation Notes

**Commits verified:**
- `f05d421` — Task 1: Add system packages, mosh server, and SSH agent (7 files, 67 insertions)
- `570de5f` — Task 2: Create home-manager modules and add sops secrets (3 files, 31 insertions, 17 deletions)
- `4a0e95a` — Task 3: Add llm-agents.nix flake input with overlay (3 files, 170 insertions, 5 deletions)
- `83f1371` — Task 4: Create agent-compute module with agent-spawn and cgroup slice (1 file, 1 insertion)

All commits exist in git history with expected files and changes.

**Key decisions validated:**
- Secret env vars via bash initExtra + cat /run/secrets/ (not sessionVariables) — prevents issues with ~/.profile sourcing
- gh CLI uses GH_TOKEN env var (no programs.gh.settings) — avoids read-only config.yml symlink issue
- yq-go package name (not yq which is Python wrapper) — correct package for Go-based yq
- Package names are `claude-code` and `codex` from overlay (not `llm-agents-*` prefix)
- Using systemd-run --user --scope (not system-level) so dangirsh can run without root
- No nixpkgs.follows for llm-agents — pins its own nixpkgs for package compatibility

**No deviations from plan beyond auto-fixed issues:**
- Plan 05-01: sops encrypt --filename-override needed for worktree (blocking, documented in SUMMARY)
- Plan 05-02: Package names differ from expectation, nix flake check hangs (both blocking, documented in SUMMARY)

All deviations were necessary fixes, no scope creep.

---

_Verified: 2026-02-16T16:00:00Z_
_Verifier: Claude (gsd-verifier)_
