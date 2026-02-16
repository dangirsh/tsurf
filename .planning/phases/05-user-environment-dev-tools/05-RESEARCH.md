# Phase 5: User Environment + Dev Tools - Research

**Researched:** 2026-02-16
**Domain:** NixOS home-manager, agent-optimized compute environment, cgroups v2 isolation, llm-agents.nix
**Confidence:** HIGH

## Summary

Phase 5 transforms the deployed NixOS server into an agent-optimized compute environment. The key reframe from the original roadmap: this is NOT a human development environment. It is 100% agent-mediated -- the human launches agents via mosh+tmux and monitors via btop. All human-comfort tooling (zsh, starship, neovim, atuin) is explicitly dropped.

The implementation breaks into four clean areas: (1) home-manager configuration for bash, tmux, git, direnv, and minimal system packages; (2) agent CLI installation via numtide/llm-agents.nix flake overlay; (3) secrets management for API keys and GitHub auth via sops-nix; (4) agent-spawn launcher script with systemd cgroup isolation. The mosh server rounds out the entrypoint story.

**Primary recommendation:** Build this in 2-3 plans: Plan 1 covers home-manager configuration (bash, tmux, git, direnv, mosh, system packages, SSH config). Plan 2 covers agent infrastructure (llm-agents.nix integration, sops secrets for API keys, GH_TOKEN, agent-spawn script, cgroup slice).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Agent isolation via cgroups v2 — Each agent session runs in a systemd cgroup slice for resource isolation. CPU: CPUWeight (dynamic fair-share). Memory: skip limits for now. No microvm.nix, no per-agent user accounts. Single user (dangirsh).
- Shell: bash, not zsh — Default shell is bash. No oh-my-zsh, no starship, no syntax-highlighting, no autosuggestions. No prompt customization. direnv + nix-direnv is the ONLY shell integration.
- No human-comfort tools — No neovim, no starship, no zsh plugins, no atuin. No prompt theme. nano is fine in a pinch.
- Generic compute — project deps from devShells — Base utilities only: git, gh, curl, wget, jq, yq, ripgrep, fd, tmux, mosh. Node.js is the ONE globally installed runtime (required by Codex CLI and MCP servers). direnv + nix-direnv auto-loads project devShells.
- Agent CLIs: Nix-managed via llm-agents.nix — Add numtide/llm-agents.nix as a flake input. Claude Code and Codex CLI installed declaratively.
- MCP servers: per-project only — No global/system-wide MCP server configuration.
- Git identity: Dan Girshovich — git config via home-manager. All agents commit as Dan with Co-Authored-By trailers.
- GitHub auth: PAT via sops-nix — GitHub Personal Access Token stored as sops-nix secret. No SSH key auth for GitHub.
- Launcher script: agent-spawn — Basic launcher: creates named tmux session + cgroup slice, cd's to project dir, launches specified agent CLI. Usage: `agent-spawn <name> <project-dir> [claude|codex]`. No worktree management, no monitoring registry, no cleanup on exit.
- Mosh: primary entrypoint — mosh-server enabled in NixOS config. Human always connects via mosh.
- Tmux: minimal config — Mouse mode ON. Otherwise stock defaults. Agent sessions are separate tmux sessions.
- API keys: sops-nix — ANTHROPIC_API_KEY, OPENAI_API_KEY stored as sops-nix secrets. Exposed as environment variables to agent sessions. No .env files.
- Agent session logs: deferred to Phase 6
- Coordination tooling: lean Phase 5 — No Agent Mail, no NTM dashboard.

### Claude's Discretion
No areas explicitly marked for discretion. All decisions are locked.

### Deferred Ideas (OUT OF SCOPE)
- Session indexing (CASS or alternatives) -- Phase 6
- Agent Mail (inter-agent messaging + file reservation) -- future phase
- NTM dashboard (tmux orchestration with agent health metrics) -- future phase
- Dynamic memory limits -- add MemoryHigh soft limits if agents cause OOM issues
- microvm.nix -- if untrusted agents are ever needed
- `agent-list` monitoring command -- future phase
</user_constraints>

## Standard Stack

### Core

| Component | Version / Source | Purpose | Why Standard |
|-----------|-----------------|---------|--------------|
| home-manager | release-25.11 (already in flake.nix) | User config management | Already integrated as NixOS module; manages bash, tmux, git, direnv declaratively |
| numtide/llm-agents.nix | github:numtide/llm-agents.nix (latest) | Claude Code + Codex CLI packages | 60+ AI agent packages, daily auto-updates, Numtide binary cache, overlay for pkgs namespace |
| sops-nix | Already in flake.nix | API key + GitHub PAT secrets | Already deployed for Tailscale/B2 secrets; extend with new secrets |
| systemd cgroups v2 | Built into NixOS systemd | Agent resource isolation | Native to systemd, no additional packages; CPUWeight for fair-share |
| direnv + nix-direnv | Via home-manager programs.direnv | Auto-load project devShells | Standard Nix ecosystem pattern for per-project environments |

### Supporting

| Component | Source | Purpose | When to Use |
|-----------|--------|---------|-------------|
| mosh | programs.mosh.enable = true | Roaming SSH alternative | Primary human entrypoint; UDP 60000-61000 |
| tmux | Via home-manager programs.tmux | Terminal multiplexer | Agent session management; mouse mode ON |
| nodejs | pkgs.nodejs in environment.systemPackages | Global Node.js runtime | Required by Codex CLI and MCP servers |
| pkgs.writeShellApplication | nixpkgs trivial builder | agent-spawn script | Nix-native script packaging with runtime deps |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GH_TOKEN env var | gh auth login --with-token | GH_TOKEN is simpler -- no activation script needed, no mutable config.yml issue |
| writeShellApplication | writeShellScriptBin | writeShellApplication auto-handles PATH via runtimeInputs, preferred |
| systemd-run --scope | Persistent systemd services | Scopes are transient and auto-cleanup; services would need manual lifecycle management |

## Architecture Patterns

### Module Structure for Phase 5

New and modified files:
```
flake.nix                        # Add llm-agents input + overlay + binary cache
modules/
  base.nix                       # ADD: system packages (git, curl, wget, rsync, jq, tmux, mosh, btop)
  secrets.nix                    # ADD: new secrets (anthropic-api-key, openai-api-key, github-pat)
  agent-compute.nix              # NEW: agent-spawn script, cgroup slice, mosh config
home/
  default.nix                    # Imports new modules
  bash.nix                       # NEW: programs.bash + direnv integration
  tmux.nix                       # NEW: programs.tmux with mouse mode
  git.nix                        # NEW: programs.git identity + programs.gh
  ssh.nix                        # NEW: SSH client config (controlMaster, etc.)
  direnv.nix                     # NEW: programs.direnv + nix-direnv
```

### Pattern 1: llm-agents.nix Flake Integration

**What:** Add llm-agents.nix as flake input, apply overlay, install agent CLIs as system packages.
**When to use:** All agent CLI installations.
**Example:**
```nix
# flake.nix
{
  inputs = {
    # ... existing inputs ...
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      # NOTE: llm-agents pins its own nixpkgs -- do NOT use follows
      # The overlay adapts to the consumer's pkgs
    };
  };

  outputs = { self, nixpkgs, llm-agents, ... } @ inputs: {
    nixosConfigurations.acfs = nixpkgs.lib.nixosSystem {
      # ...
      modules = [
        # ... existing modules ...
        {
          nixpkgs.overlays = [ llm-agents.overlays.default ];
          environment.systemPackages = with pkgs; [
            llm-agents.claude-code
            llm-agents.codex
          ];
        }
      ];
    };
  };
}
```

**Binary cache configuration:**
```nix
# In modules/base.nix or a dedicated nix-settings module
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://cache.numtide.com"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
};
```
**Confidence:** HIGH -- verified from llm-agents.nix README and flake.nix

### Pattern 2: GH_TOKEN via sops-nix (Not gh auth login)

**What:** Use the `GH_TOKEN` environment variable instead of `gh auth login --with-token`.
**When to use:** GitHub CLI authentication.
**Why:** `gh` automatically uses `GH_TOKEN` env var for authentication -- no activation script needed, no writable config.yml issue with home-manager. Simpler and more robust.
**Example:**
```nix
# modules/secrets.nix -- add the secret
sops.secrets."github-pat" = {
  owner = "dangirsh";
};

# home/bash.nix -- export from shell init
programs.bash.initExtra = ''
  # GitHub CLI authentication via PAT
  export GH_TOKEN="$(cat /run/secrets/github-pat)"
  # Agent API keys
  export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic-api-key)"
  export OPENAI_API_KEY="$(cat /run/secrets/openai-api-key)"
'';
```
**Confidence:** HIGH -- GH_TOKEN is documented in `gh help environment` as the primary env var auth method

### Pattern 3: Systemd Cgroup Slice + systemd-run Scope

**What:** Declare a custom systemd slice for agent workloads; use `systemd-run --scope --slice` in the agent-spawn script.
**When to use:** Every agent-spawn invocation.
**Example:**
```nix
# modules/agent-compute.nix
systemd.slices."agent" = {
  description = "Agent workload isolation slice";
  sliceConfig = {
    CPUWeight = 100;  # Default weight; all agents share equally within this slice
  };
};
```

```bash
# agent-spawn script
systemd-run --user --scope --slice=agent.slice \
  -p CPUWeight=100 \
  -- tmux new-session -d -s "$NAME" -c "$PROJECT_DIR" "$AGENT_CLI"
```
**Confidence:** MEDIUM -- NixOS systemd.slices is documented but examples of `--user` slices with CPUWeight in NixOS are sparse. The systemd-run --scope pattern is well-established in Linux but NixOS-specific validation needed. See Open Questions.

### Pattern 4: Home-Manager Bash + Direnv Configuration

**What:** Minimal bash with direnv + nix-direnv for auto-loading project devShells.
**When to use:** User shell configuration.
**Example:**
```nix
# home/bash.nix
{ config, pkgs, ... }: {
  programs.bash = {
    enable = true;
    # initExtra runs in every interactive shell
    initExtra = ''
      export GH_TOKEN="$(cat /run/secrets/github-pat)"
      export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic-api-key)"
      export OPENAI_API_KEY="$(cat /run/secrets/openai-api-key)"
    '';
  };
}

# home/direnv.nix
{ config, pkgs, ... }: {
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;  # Hooks into .bashrc automatically
    nix-direnv.enable = true;      # Cached nix shell evaluations
  };
}
```
**Confidence:** HIGH -- standard home-manager pattern, well-documented

### Pattern 5: agent-spawn as writeShellApplication

**What:** Package the agent-spawn launcher as a Nix-managed script with explicit runtime dependencies.
**When to use:** System-wide agent launcher.
**Example:**
```nix
# modules/agent-compute.nix
let
  agent-spawn = pkgs.writeShellApplication {
    name = "agent-spawn";
    runtimeInputs = [ pkgs.tmux pkgs.systemd ];
    text = ''
      set -euo pipefail
      NAME="''${1:?Usage: agent-spawn <name> <project-dir> [claude|codex]}"
      PROJECT_DIR="''${2:?Usage: agent-spawn <name> <project-dir> [claude|codex]}"
      AGENT="''${3:-claude}"

      case "$AGENT" in
        claude) CMD="claude" ;;
        codex)  CMD="codex" ;;
        *)      echo "Unknown agent: $AGENT"; exit 1 ;;
      esac

      # Launch in cgroup-isolated tmux session
      systemd-run --user --scope --slice=agent.slice \
        -p CPUWeight=100 \
        -- tmux new-session -d -s "$NAME" -c "$PROJECT_DIR" "$CMD"

      echo "Agent '$NAME' spawned in tmux session (agent.slice)"
      echo "Attach: tmux attach -t $NAME"
    '';
  };
in {
  environment.systemPackages = [ agent-spawn ];
}
```
**Confidence:** HIGH for writeShellApplication pattern; MEDIUM for systemd-run --user integration (see Open Questions)

### Anti-Patterns to Avoid

- **Managing gh config via home-manager programs.gh.settings:** Creates read-only config.yml symlink that breaks `gh auth login`. Use GH_TOKEN env var instead.
- **Using builtins.readFile for secrets:** Places plaintext secrets in the Nix store, world-readable. Always use runtime file reads with `$(cat /run/secrets/...)`.
- **Global npm install:** The Nix store is read-only; `npm install -g` fails. All global Node.js tools must come from nixpkgs or overlays.
- **Putting language runtimes in system packages:** Only Node.js belongs globally. All other runtimes come from project devShells via direnv.
- **Using nixpkgs.follows for llm-agents.nix:** The llm-agents flake pins its own nixpkgs for package compatibility. Using `follows` would force it to use our nixpkgs, which may break builds.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Agent CLI packaging | Custom derivations for Claude/Codex | llm-agents.nix overlay | 60+ packages, daily updates, binary cache, multi-platform |
| Shell environment management | Manual bashrc/profile scripts | home-manager programs.bash | Declarative, reproducible, manages dotfiles correctly |
| Per-project dev environments | Global language runtimes | direnv + nix-direnv + project flakes | Each project defines its own deps; no version conflicts |
| Secret injection to env vars | .env files, manual exports | sops-nix secrets + bash initExtra | Encrypted at rest, auto-decrypted, no plaintext on disk |
| Script PATH management | Manual PATH exports | pkgs.writeShellApplication + runtimeInputs | Nix handles dependency resolution automatically |

**Key insight:** This phase wires together existing NixOS/Nix ecosystem tools. There is zero custom infrastructure to build -- every piece has a well-tested Nix-native solution.

## Common Pitfalls

### Pitfall 1: sops-nix Secrets Not Readable by User

**What goes wrong:** Secrets in /run/secrets/ default to root:root 0400. dangirsh can't read them.
**Why it happens:** sops-nix defaults to root ownership for security.
**How to avoid:** Set `owner = "dangirsh"` on each user-facing secret:
```nix
sops.secrets."anthropic-api-key" = { owner = "dangirsh"; };
```
**Warning signs:** `cat /run/secrets/anthropic-api-key` returns "Permission denied" as dangirsh.

### Pitfall 2: gh config.yml Symlink Conflict

**What goes wrong:** home-manager creates an immutable config.yml symlink for gh, breaking `gh auth login`.
**Why it happens:** home-manager makes all managed files read-only nix store symlinks.
**How to avoid:** Do NOT use `programs.gh.settings` in home-manager. Instead, use `GH_TOKEN` env var. Only use `programs.gh.enable = true` to install the binary.
**Warning signs:** `gh auth login` fails with "read-only file system" error.

### Pitfall 3: Mosh Firewall Ports on Tailscale-Only SSH

**What goes wrong:** mosh needs both SSH (for initial handshake) and UDP 60000-61000 (for session).
**Why it happens:** Current config has SSH on Tailscale only (port 22 not in public firewall). mosh client connects via Tailscale IP, so SSH handshake works. But mosh UDP ports also need to be reachable.
**How to avoid:** Since `tailscale0` is already a trustedInterface (all ports open), mosh over Tailscale works without additional firewall rules. The `programs.mosh.enable = true` opens UDP 60000-61000 on the public firewall, which is also fine (mosh session requires SSH auth first). Both paths work.
**Warning signs:** mosh connection hangs after "mosh-server started" message.

### Pitfall 4: New Files Not git-added Before nix flake check

**What goes wrong:** `nix flake check` fails because new .nix files aren't tracked by git.
**Why it happens:** Nix flakes only see git-tracked files.
**How to avoid:** `git add` every new file before running `nix flake check`. This is a known pattern from previous phases.
**Warning signs:** "file not found" or "No such file or directory" during flake evaluation.

### Pitfall 5: systemd --user Slice Not Available for Root-Level systemd-run

**What goes wrong:** `systemd-run --user` requires a user-level systemd instance (via `loginctl enable-linger`).
**Why it happens:** Without lingering enabled, user systemd instances are only active when the user has an active session.
**How to avoid:** Enable lingering for dangirsh so the user systemd instance persists:
```nix
# Ensure user systemd instance is always running
users.users.dangirsh.linger = true;
```
**Warning signs:** `systemd-run --user` fails with "Failed to connect to bus" or "No such file or directory".

### Pitfall 6: Shell initExtra Runs Before sops Secrets Available

**What goes wrong:** On first boot or activation, bash initExtra may try to `cat /run/secrets/...` before sops-nix has decrypted.
**Why it happens:** Shell initialization happens at login time; sops-nix decrypts during system activation (before login). This is typically fine -- sops runs early in activation. But if a user is already logged in during `nixos-rebuild switch`, the running shell won't see the new secrets until a new login.
**How to avoid:** This is a non-issue for normal operations. The `$(cat ...)` pattern reads at shell-start time, not at build time. New shells after activation will always see decrypted secrets.
**Warning signs:** Empty environment variables in agent sessions after a rebuild without re-login.

## Code Examples

### Complete home/default.nix with All Imports

```nix
# home/default.nix
{ config, pkgs, ... }: {
  home.username = "dangirsh";
  home.homeDirectory = "/home/dangirsh";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    ./bash.nix
    ./tmux.nix
    ./git.nix
    ./ssh.nix
    ./direnv.nix
  ];
}
```

### Complete home/tmux.nix

```nix
# home/tmux.nix
{ config, pkgs, ... }: {
  programs.tmux = {
    enable = true;
    mouse = true;              # Easy pane switching for human monitoring
    terminal = "screen-256color";
    historyLimit = 50000;
  };
}
```

### Complete home/git.nix

```nix
# home/git.nix
{ config, pkgs, ... }: {
  programs.git = {
    enable = true;
    userName = "Dan Girshovich";
    userEmail = "dan.girshovich@gmail.com";  # Verify actual email
  };

  programs.gh = {
    enable = true;
    # Do NOT set settings -- breaks gh auth due to read-only config.yml
  };
}
```

### Complete home/ssh.nix

```nix
# home/ssh.nix
# @decision SSH-CLIENT-01: ControlMaster for connection reuse, ServerAlive for keep-alive
{ config, pkgs, ... }: {
  programs.ssh = {
    enable = true;
    controlMaster = "auto";
    controlPersist = "10m";
    serverAliveInterval = 60;
    hashKnownHosts = true;
  };
}
```

### Secrets Addition for modules/secrets.nix

```nix
# Additional secrets to add to modules/secrets.nix
sops.secrets."anthropic-api-key" = { owner = "dangirsh"; };
sops.secrets."openai-api-key" = { owner = "dangirsh"; };
sops.secrets."github-pat" = { owner = "dangirsh"; };
```

### System Packages for modules/base.nix

```nix
# Add to modules/base.nix
environment.systemPackages = with pkgs; [
  git
  curl
  wget
  rsync
  jq
  yq-go
  ripgrep
  fd
  tmux
  btop
  nodejs  # Global -- required by Codex CLI and MCP servers
];
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual dotfiles | home-manager | Mature (years) | Declarative, reproducible user config |
| Custom agent CLI builds | llm-agents.nix | 2025 | Daily auto-updates, binary cache, 60+ packages |
| .env files for secrets | sops-nix | Mature (years) | Encrypted at rest, declarative, auto-decrypted |
| Docker-based agent isolation | systemd cgroups v2 | Always available | Lighter weight, native to systemd, no container overhead |
| SSH-only remote access | mosh over Tailscale | Mature | Roaming, UDP-based, resilient to network changes |

**Deprecated/outdated:**
- llm-agents.nix was formerly called nix-ai-tools (renamed). Use the new name.
- `programs.bash.sessionVariables` writes to ~/.profile which may not be sourced. Use `initExtra` for reliable environment variable exports.
- `home.sessionVariables` has the same ~/.profile sourcing issue. Prefer `programs.bash.initExtra` for bash shells.

## Open Questions

1. **systemd --user slice declaration in NixOS**
   - What we know: `systemd.slices."agent"` creates a system-level slice. `systemd-run --user --scope --slice=agent.slice` needs a user-level slice.
   - What's unclear: Can we declare user-level slices via NixOS config (`systemd.user.slices`?), or must we use system-level slices with `systemd-run --scope` (without --user)?
   - Recommendation: Try system-level first: `systemd-run --scope --slice=agent.slice` (runs as root-adjacent scope under dangirsh's session). If that doesn't work, use `systemd.user.slices` or skip the slice entirely and just use `systemd-run --scope` for basic process grouping. The CPUWeight fair-share is the goal, not the slice itself -- and CPUWeight works at any level.

2. **llm-agents.nix follows policy**
   - What we know: The README shows `llm-agents.url = "github:numtide/llm-agents.nix"` without follows. The flake pins its own nixpkgs.
   - What's unclear: Does using `inputs.nixpkgs.follows = "nixpkgs"` break builds? The overlay should adapt, but the packages (especially claude-code) download prebuilt binaries, so nixpkgs version may not matter.
   - Recommendation: Start without follows. If the closure is too large (two nixpkgs copies in flake.lock), test with follows later. Binary-distributed packages (claude-code) should be unaffected.

3. **Numtide binary cache key**
   - What we know: README says `niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=` but older references show `numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE=`.
   - What's unclear: Which key is current? They may have migrated from cachix to self-hosted.
   - Recommendation: Use the key from the README (`niks3.numtide.com-1:...`) as primary. Add both if needed. Verify during `nix flake check` by watching substitution logs.

4. **dangirsh git email address**
   - What we know: Git identity is "Dan Girshovich" -- email not specified in CONTEXT.md.
   - What's unclear: Exact email address to use.
   - Recommendation: Check existing git config or ask user. Use placeholder and note in plan.

## Sources

### Primary (HIGH confidence)
- [numtide/llm-agents.nix README](https://github.com/numtide/llm-agents.nix) -- flake input URL, overlay pattern, binary cache config, package list
- [numtide/llm-agents.nix packages/claude-code/package.nix](https://raw.githubusercontent.com/numtide/llm-agents.nix/main/packages/claude-code/package.nix) -- claude-code build details (prebuilt binary, bubblewrap sandboxing)
- [numtide/llm-agents.nix packages/codex/package.nix](https://raw.githubusercontent.com/numtide/llm-agents.nix/main/packages/codex/package.nix) -- codex build details (Rust buildRustPackage from source)
- [home-manager programs.direnv module](https://github.com/nix-community/home-manager/blob/master/modules/programs/direnv.nix) -- direnv + nix-direnv config options
- [sops-nix README](https://github.com/Mic92/sops-nix) -- secret ownership, per-secret options, templates
- [gh help environment](https://cli.github.com/manual/gh_help_environment) -- GH_TOKEN env var as auth method
- [systemd.resource-control(5)](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html) -- CPUWeight, cgroup v2 resource controls
- [NixOS Mosh wiki](https://wiki.nixos.org/wiki/Mosh) -- programs.mosh.enable, UDP 60000-61000
- [NixOS systemd.slices options](https://mynixos.com/options/systemd.slices.%3Cname%3E) -- sliceConfig, unit options

### Secondary (MEDIUM confidence)
- [NixOS Discourse: How to set environment variables with sops-nix](https://discourse.nixos.org/t/how-to-set-environment-variables-with-sops-nix/38980) -- verified pattern of `$(cat /run/secrets/...)` in shell init
- [NixOS Discourse: Logging in with gh auth and home-manager](https://discourse.nixos.org/t/logging-in-with-gh-auth-and-home-manager/61590) -- config.yml read-only issue confirmed
- [gh CLI issue #4955](https://github.com/cli/cli/issues/4955) -- gh auth login requires writable config.yml, confirming GH_TOKEN workaround
- [fraggod blog: cgroup-v2 resource limits](https://blog.fraggod.net/2019/10/02/cgroup-v2-resource-limits-for-apps-with-systemd-scopes-and-slices.html) -- systemd-run --scope pattern

### Tertiary (LOW confidence)
- systemd --user slice interaction with NixOS `users.users.*.linger` -- pattern is clear from systemd docs but NixOS-specific examples are sparse. Needs validation during implementation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components are well-established NixOS/Nix ecosystem tools with verified documentation
- Architecture: HIGH -- module structure follows existing project patterns; home-manager configuration is thoroughly documented
- Pitfalls: HIGH -- gh config.yml issue is well-documented; sops-nix ownership is documented; mosh+Tailscale interaction is logical from existing firewall config
- Agent isolation (cgroups): MEDIUM -- systemd-run --scope is well-established but NixOS user-level slice declaration lacks concrete examples
- llm-agents.nix integration: MEDIUM -- overlay pattern is documented but follows/cache key details need validation

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days -- llm-agents.nix updates daily but the integration pattern is stable)
