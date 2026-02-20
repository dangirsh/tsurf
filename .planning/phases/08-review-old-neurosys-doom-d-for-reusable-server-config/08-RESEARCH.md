# Phase 8: Review Old Neurosys + Doom.d for Reusable Server Config - Research

**Researched:** 2026-02-14
**Domain:** NixOS configuration audit / migration analysis
**Confidence:** HIGH

## Summary

Both repos (`dangirsh/neurosys` and `dangirsh/.doom.d`) have been fully reviewed. The old neurosys is a literate Org-mode NixOS configuration (NixOS 20.03, pre-flakes, niv-pinned) targeting a Linode VPS running as a remote dev server with XMonad. The `.doom.d` repo is a Doom Emacs configuration -- almost entirely desktop/editor-specific with one notable exception (a neurosys deployment module).

The old neurosys contains **7 server-relevant candidates** worth evaluating for neurosys, and the `.doom.d` repo contains **0 directly portable items** (everything is Emacs/desktop-specific). The highest-value findings are: (1) the Syncthing declarative config pattern with device IDs, folder versioning, and receive-only semantics; (2) the `settings.nix` pattern for centralizing user identity constants; (3) the Tarsnap backup pattern (informing the Restic migration); (4) system packages for a server CLI baseline; and (5) SSH hardening patterns.

**Primary recommendation:** Cherry-pick the Syncthing declarative pattern, settings constants, system packages list, and SSH agent/controlMaster patterns. All other items are either already handled by neurosys or are desktop-specific and should be discarded.

## Repo Overview

### dangirsh/neurosys (GitHub, master branch)

A literate NixOS configuration using Org-mode tangling. Structure:

```
README.org                # Literate source (tangles to all .nix files)
nixos/
  configuration.nix       # System config (tangled)
  hardware-configuration.nix  # Linode QEMU guest (tangled)
  home.nix                # home-manager user config (tangled)
  settings.nix            # Global constants module (tangled)
  nix/sources.json        # niv pinning (emacs-overlay, nixpkgs-20.03)
  nix/sources.nix         # niv resolver
home/
  .doom.d/                # Git submodule -> dangirsh/.doom.d
  .xmonad/                # XMonad config (Haskell)
rsync.sh                  # Deployment script (rsync to host)
```

**Key characteristics:**
- NixOS 20.03 (ancient -- many options renamed/deprecated)
- Pre-flakes (uses niv for pinning)
- Targets a Linode VPS (QEMU guest, GRUB, ext4)
- home-manager via channel, not flake input
- Literate Org-mode: README.org tangles to all config files
- Deployment via rsync + `nixos-rebuild switch` over SSH

### dangirsh/.doom.d (GitHub, master branch)

A Doom Emacs configuration. Structure:

```
init.el       # Doom module declarations
config.el     # Main config (keybindings, UI, org-mode, tools)
packages.el   # Package declarations
funcs.el      # Utility functions
custom.el     # Emacs custom.el (auto-generated)
modules/personal/neurosys/config.el  # Remote deployment functions
```

**Key characteristics:**
- 100% Emacs/desktop-specific
- The neurosys module has deployment helpers (rsync + nixos-rebuild via TRAMP)
- References Syncthing dirs (Sync, Work, Media) -- confirms folder structure
- Uses pass (password-store), gnupg, org-roam, teleport (Teleport TRAMP integration)

## Candidate Findings

### CANDIDATE 1: Syncthing Declarative Configuration
**Confidence:** HIGH
**Source:** `neurosys/nixos/configuration.nix` -> `services.syncthing`
**What it does:** Full declarative Syncthing setup with:
- Device IDs for 3 devices (nixos-dev, x1carbon9, pixel6-pro)
- 3 synced folders (Sync, Media, Work) with paths under `/bkp/`
- `receiveonly` mode (server receives, doesn't originate changes)
- Simple versioning with `keep = "5"`
- Hourly rescan for Sync, 6-hour rescan for Media/Work
- `openDefaultPorts = true` (ports 22000/tcp and 21027/udp)
- Config/data dirs set explicitly under user home

**Where it lived:** `nixos/configuration.nix` (tangled from README.org `Services > Syncthing`)

**What's new vs neurosys:**
neurosys already has `modules/syncthing.nix` in the CLAUDE.md project structure, and networking.nix already opens port 22000. The old config provides a **concrete reference implementation** for the declarative device/folder config that Phase 6 will need to implement.

**Relevant patterns to port:**
- `receiveonly` type for server-as-backup-target
- Simple versioning with retention count
- Explicit rescan intervals (no inotify watch -- reduces resource use)
- Explicit `configDir` and `dataDir` paths
- Device ID declarations

**Target phase:** Phase 6 (User Services + Agent Tooling)
**Target module:** `modules/syncthing.nix`
**Priority:** HIGH -- this is the most complete reference for Syncthing declarative config
**Effort:** LOW -- patterns can be directly adapted with updated device IDs/paths

---

### CANDIDATE 2: Settings Module (Centralized User Constants)
**Confidence:** HIGH
**Source:** `neurosys/nixos/settings.nix`
**What it does:** A NixOS module that defines `settings.name`, `settings.username`, `settings.email` as module options with defaults. Other modules reference `config.settings.username` instead of hardcoding values.

```nix
{config, pkgs, lib, ...}:
with lib;
{
  options = {
    settings = {
      name = mkOption {
        default = "Dan Girshovich";
        type = with types; uniq str;
      };
      username = mkOption {
        default = "dan";
        type = with types; uniq str;
      };
      email = mkOption {
        default = "dan.girsh@gmail.com";
        type = with types; uniq str;
      };
    };
  };
}
```

**Where it lived:** `nixos/settings.nix` (tangled from README.org `Global Constants`)

**What's new vs neurosys:**
neurosys currently hardcodes `"dangirsh"` in `modules/users.nix` and `home/default.nix`, and `"acfs"` in `hosts/acfs/default.nix`. There is no centralized settings module.

**Relevant patterns to port:**
- Central module with `mkOption` for name, username, email
- All other modules reference `config.settings.*` instead of string literals
- Eliminates scattered hardcoded values

**Target phase:** Phase 2 (Bootable Base System) or Phase 5 (User Environment)
**Target module:** New `modules/settings.nix` or fold into `modules/base.nix`
**Priority:** MEDIUM -- reduces duplication, improves maintainability
**Effort:** LOW -- straightforward NixOS module pattern

---

### CANDIDATE 3: System Packages Baseline
**Confidence:** HIGH
**Source:** `neurosys/nixos/configuration.nix` -> `environment.systemPackages`
**What it does:** Installs a curated set of server CLI utilities:

```nix
environment.systemPackages = with pkgs; [
  coreutils binutils
  curl wget
  zip unzip
  git
  killall
  syncthing-cli
  sshfs
  mtr        # traceroute/network diagnostic
  sysstat    # system performance stats (sar, iostat, mpstat)
  htop
];
```

**Where it lived:** `nixos/configuration.nix` (tangled from README.org `Packages`)

**What's new vs neurosys:**
neurosys `modules/base.nix` currently only sets `nix.settings` and `nix.gc`. There are no system packages declared yet. The dev-tools module (mentioned in CLAUDE.md but not yet implemented) will cover development toolchains, but these are **system-level** utilities that should be available regardless.

**Relevant packages to port:**
- `curl`, `wget` -- HTTP clients
- `zip`, `unzip` -- archive tools
- `git` -- version control (system-level, separate from home-manager git config)
- `killall` -- process management
- `mtr` -- network diagnostics (better than traceroute)
- `sysstat` -- system performance monitoring
- `htop` -- interactive process viewer
- `sshfs` -- mount remote filesystems (useful for server management)

**Not relevant:**
- `syncthing-cli` -- Syncthing is managed via NixOS service, CLI optional
- `coreutils`, `binutils` -- already in NixOS base

**Target phase:** Phase 2 (Bootable Base System)
**Target module:** `modules/base.nix` (add `environment.systemPackages`)
**Priority:** MEDIUM -- nice to have from Phase 2 onwards
**Effort:** TRIVIAL -- single attribute set

---

### CANDIDATE 4: Nix Settings (GC, Sandbox, Store Optimization)
**Confidence:** HIGH
**Source:** `neurosys/nixos/configuration.nix` -> `nix`
**What it does:**
- `useSandbox = true` -- build sandboxing (now default, renamed to `nix.settings.sandbox`)
- `autoOptimiseStore = true` -- already in neurosys
- `maxJobs = 3` -- parallel build jobs (should match CPU cores)
- `gc.automatic = true` with `dates = "23:00"` and `--delete-older-than 30d` -- already in neurosys (weekly)
- Binary caches with public keys for ghcide, hercules-ci, iohk (Haskell-specific -- NOT relevant)

**Where it lived:** `nixos/configuration.nix` (tangled from README.org `Nix`)

**What's new vs neurosys:**
neurosys `modules/base.nix` already handles `nix.settings.auto-optimise-store` and `nix.gc`. Two items worth noting:
1. `nix.settings.sandbox = true` -- not explicitly set in neurosys (it's the default on NixOS, but being explicit is good practice)
2. `nix.settings.max-jobs` -- not set in neurosys (should match Contabo VPS CPU count)

**Target phase:** Phase 2 (Bootable Base System)
**Target module:** `modules/base.nix`
**Priority:** LOW -- mostly already covered, minor additions
**Effort:** TRIVIAL

---

### CANDIDATE 5: SSH Hardening + User Auth
**Confidence:** HIGH
**Source:** `neurosys/nixos/configuration.nix` -> `services.openssh` and `users`
**What it does:**
- SSH key-only auth (password disabled) -- already in neurosys
- `forwardX11 = true` -- NOT relevant for headless server
- `permitRootLogin = "without-password"` -- neurosys uses `"prohibit-password"` (equivalent)
- `users.mutableUsers = false` -- makes user management purely declarative
- `security.sudo.wheelNeedsPassword = false` -- passwordless sudo for wheel group
- `programs.ssh.startAgent = true` -- SSH agent for outbound connections

**Where it lived:** `nixos/configuration.nix` (tangled from README.org `SSH` and `User Definition`)

**What's new vs neurosys:**
1. `users.mutableUsers = false` -- NOT in neurosys. Forces all user management through Nix (no `passwd`, no `useradd`). Highly recommended for declarative servers.
2. `security.sudo.wheelNeedsPassword = false` -- NOT in neurosys. Useful for automation/agents.
3. `programs.ssh.startAgent = true` -- NOT in neurosys. Needed if the server initiates outbound SSH (git push, rsync to other hosts).

**Target phase:** Phase 2 (Bootable Base System)
**Target module:** `modules/users.nix` and `modules/networking.nix`
**Priority:** MEDIUM -- `users.mutableUsers = false` is a best practice for declarative NixOS
**Effort:** TRIVIAL

---

### CANDIDATE 6: SSH Client Configuration (home-manager)
**Confidence:** HIGH
**Source:** `neurosys/nixos/home.nix` -> `programs.ssh`
**What it does:** home-manager SSH client configuration:
- `controlMaster = "auto"` -- SSH connection multiplexing
- `controlPath = "/tmp/ssh-%u-%r@%h:%p"` -- control socket path
- `controlPersist = "1800"` -- keep master connection alive 30min
- `forwardAgent = true` -- forward SSH agent to remote hosts
- `serverAliveInterval = 60` -- keepalive every 60s
- `hashKnownHosts = true` -- hash known_hosts entries for privacy
- `matchBlocks` -- named SSH host shortcuts (droplet, dangirsh.org, nixos-dev)

**Where it lived:** `nixos/home.nix` (tangled from README.org `Programs > SSH`)

**What's new vs neurosys:**
neurosys `home/default.nix` is minimal (just username, homeDirectory, stateVersion). No SSH client config exists. The server will likely SSH to GitHub (for git operations), other hosts, etc.

**Relevant patterns to port:**
- `controlMaster`/`controlPersist` for connection multiplexing (big performance win for repeated SSH connections)
- `serverAliveInterval` to prevent dropped connections
- `hashKnownHosts` for security
- `matchBlocks` for named host shortcuts (with updated hosts relevant to neurosys)

**NOT relevant:**
- The specific matchBlocks (droplet, dangirsh.org, nixos-dev) -- those hosts are old/gone
- `forwardAgent = true` -- security risk on a server; should only be enabled for specific hosts if needed

**Target phase:** Phase 5 (User Environment + Dev Tools)
**Target module:** `home/ssh.nix` (new, or add to existing home module)
**Priority:** LOW -- nice-to-have for developer ergonomics
**Effort:** LOW

---

### CANDIDATE 7: Tarsnap Backup Configuration (Pattern Reference for Restic)
**Confidence:** HIGH
**Source:** `neurosys/nixos/configuration.nix` -> `services.tarsnap`
**What it does:** Tarsnap backup with:
- Key file stored in Syncthing-synced directory
- Single archive covering `/bkp/Sync`, `/bkp/Work`, `/bkp/Media`
- Tarsnap's built-in deduplication

**Where it lived:** `nixos/configuration.nix` (tangled from README.org `Services > Tarsnap`)

**What's new vs neurosys:**
neurosys plans Restic to B2 (Phase 7), not Tarsnap. However, the pattern of **what to back up** is informative:
- Syncthing data directories (the canonical data the server holds)
- Key files stored in synced directories (bootstrap problem -- keys needed before sync works)

**Relevant patterns to port:**
- The set of directories worth backing up maps to Restic include paths
- The key storage pattern (key in synced dir) has a chicken-and-egg problem worth noting

**Target phase:** Phase 7 (Backups)
**Target module:** `modules/restic.nix`
**Priority:** LOW -- informational reference only, Restic has different config surface
**Effort:** N/A -- pattern reference, not code to port

## Items Explicitly NOT Relevant

The following items from both repos are **desktop/laptop/Emacs-specific** and should be discarded:

### From neurosys:
| Item | Why Not Relevant |
|------|-----------------|
| XMonad config (`.xmonad/`) | Desktop window manager -- headless server |
| X11/xserver services | No display server on a headless VPS |
| Fonts (corefonts, hack-font) | No GUI |
| Emacs (emacs-overlay, emacsGit) | Server uses Claude Code/CLI tools, not Emacs |
| Rofi, xclip, arandr, xtrlock-pam, maim | All X11/GUI tools |
| Firefox | Browser -- desktop only |
| pass/gnupg user packages | Desktop-oriented password management |
| Bash shell config with vterm integration | Emacs-specific; neurosys uses Zsh |
| niv/sources.nix pinning | Replaced by flake.lock in neurosys |
| rsync.sh deployment | Replaced by nixos-anywhere + `nixos-rebuild` via SSH |
| Linode-specific hardware config | Different VPS provider (Contabo) |
| Binary caches (ghcide, hercules, iohk) | Haskell-specific caches not needed |

### From .doom.d:
| Item | Why Not Relevant |
|------|-----------------|
| All of init.el, config.el, packages.el | Doom Emacs configuration -- entirely editor-specific |
| neurosys deployment module | Emacs-based deployment via TRAMP -- replaced by CLI tools |
| funcs.el utility functions | All Emacs Lisp functions for editor use |
| Key chord, org-mode, org-roam config | Editor workflow |
| Teleport TRAMP integration | Interesting but Emacs-specific; Teleport CLI could be separate Phase 5 consideration |
| claude-code-emacs package | Emacs integration for Claude Code -- server uses CLI directly |

### Potential future interest (NOT for current phases):
- **Teleport**: The .doom.d config references Teleport (TRAMP method). If Teleport is used for server access, its NixOS service could be a future addition. Not relevant to current roadmap phases.
- **Direnv**: Commented out in old neurosys but appears in .doom.d init.el. Could be useful for project-level dev environments on the server. Phase 5 consideration.

## Architecture Patterns

### Pattern 1: Centralized Settings Module
**What:** A dedicated NixOS module that defines site-wide constants (username, email, name) as module options. All other modules reference `config.settings.*`.
**When to use:** Any multi-module NixOS configuration where user identity or host-specific constants appear in multiple places.
**Example:**
```nix
# modules/settings.nix
{ lib, ... }:
with lib;
{
  options.settings = {
    name = mkOption { default = "Dan Girshovich"; type = types.str; };
    username = mkOption { default = "dangirsh"; type = types.str; };
    email = mkOption { default = "dan.girsh@gmail.com"; type = types.str; };
  };
}

# Usage in other modules:
{ config, ... }: {
  users.users.${config.settings.username} = { ... };
  home-manager.users.${config.settings.username} = import ./home;
}
```

### Pattern 2: Declarative Syncthing with Receive-Only Server
**What:** Server acts as a sync target (receive-only) with explicit device IDs, versioned folders, and no inotify watch (periodic rescan only).
**When to use:** When the server is a backup/sync target, not an originator of changes.
**Example:** See Candidate 1 above.

### Pattern 3: Immutable Users
**What:** `users.mutableUsers = false` ensures all user accounts are managed purely through NixOS configuration. No `passwd`, `useradd`, etc. work at runtime.
**When to use:** Declarative servers where user management should be 100% reproducible.
**Caveat:** Initial password must be set via `hashedPassword` or `hashedPasswordFile` in the user config, or login is key-only (which is fine for SSH-only servers).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Centralized config values | String literals everywhere | NixOS module options (`mkOption`) | Type-checked, documented, refactorable |
| Syncthing device management | Imperative web UI config | `services.syncthing.settings.devices` | Declarative, reproducible, version-controlled |
| SSH connection multiplexing | Manual ssh_config | home-manager `programs.ssh` | Manages known_hosts, control sockets, matchBlocks |
| Backup directory selection | Ad-hoc scripts | Restic NixOS module `paths` | Integrated with systemd timers, retention policies |

## Common Pitfalls

### Pitfall 1: Stale Device IDs in Syncthing Config
**What goes wrong:** Old device IDs from the neurosys config are copy-pasted into neurosys. Syncthing fails to connect because devices have been replaced/regenerated.
**Why it happens:** Device IDs are hardware/identity-specific. The old nixos-dev, x1carbon9, pixel6-pro IDs are from 2020-era devices.
**How to avoid:** Generate fresh device IDs from current devices. Only use the old config as a **structural template**, never copy IDs verbatim.
**Warning signs:** Syncthing logs showing "unknown device" or connection failures.

### Pitfall 2: NixOS 20.03 Option Names
**What goes wrong:** Old option names from NixOS 20.03 are used in neurosys (NixOS 25.11). Many have been renamed or removed.
**Why it happens:** Direct copy-paste from old neurosys without checking current option names.
**How to avoid:** Always verify option names against current NixOS manual or `nixos-option`. Known renames:
- `nix.useSandbox` -> `nix.settings.sandbox`
- `nix.autoOptimiseStore` -> `nix.settings.auto-optimise-store`
- `nix.binaryCaches` -> `nix.settings.substituters`
- `nix.binaryCachePublicKeys` -> `nix.settings.trusted-public-keys`
- `services.openssh.permitRootLogin` -> `services.openssh.settings.PermitRootLogin`
- `services.openssh.passwordAuthentication` -> `services.openssh.settings.PasswordAuthentication`
- `services.openssh.forwardX11` -> `services.openssh.settings.X11Forwarding`
- `boot.cleanTmpDir` -> `boot.tmp.cleanOnBoot`
- `syncthing.declarative` -> `syncthing.settings` (structure changed significantly)
- `users.extraUsers` -> `users.users`
**Warning signs:** `nixos-rebuild` errors about unknown options.

### Pitfall 3: users.mutableUsers = false Without Password Strategy
**What goes wrong:** Setting `users.mutableUsers = false` locks out interactive login if no password hash is provided and SSH keys aren't working.
**Why it happens:** The old neurosys relied on SSH keys exclusively. If neurosys needs console access (e.g., recovery), no password means no login.
**How to avoid:** Either set `hashedPasswordFile` pointing to a sops-nix secret, or ensure at least one SSH key is always configured and the network is reachable. For VPS recovery consoles, consider having a rescue password.
**Warning signs:** Locked out of server after applying config.

## State of the Art

| Old Approach (neurosys 2020) | Current Approach (neurosys 2026) | Impact |
|------------------------------|---------------------------------------|--------|
| niv for pinning | Flake inputs + flake.lock | Better reproducibility, no external tool |
| home-manager via channel | home-manager as flake input | Lockfile-pinned, version-matched |
| Org literate tangling | Direct .nix files | Simpler, no tangle step, IDE-friendly |
| rsync deployment | nixos-anywhere + nixos-rebuild | Atomic, rollback-capable |
| Tarsnap backups | Restic to B2 | Cheaper, S3-compatible, more flexible |
| `syncthing.declarative` | `syncthing.settings` | New API structure in recent NixOS |
| `users.extraUsers` | `users.users` | Renamed in NixOS ~21.x |
| Pre-flakes binary caches | `nix.settings.substituters` | Renamed settings namespace |

## Summary Table: Candidates by Phase

| # | Candidate | Target Phase | Target Module | Priority | Effort |
|---|-----------|-------------|---------------|----------|--------|
| 1 | Syncthing declarative config | Phase 6 | `modules/syncthing.nix` | HIGH | LOW |
| 2 | Settings module (user constants) | Phase 2 | `modules/settings.nix` (new) | MEDIUM | LOW |
| 3 | System packages baseline | Phase 2 | `modules/base.nix` | MEDIUM | TRIVIAL |
| 4 | Nix settings (sandbox, max-jobs) | Phase 2 | `modules/base.nix` | LOW | TRIVIAL |
| 5 | SSH hardening (mutableUsers, sudo, agent) | Phase 2 | `modules/users.nix` | MEDIUM | TRIVIAL |
| 6 | SSH client config (home-manager) | Phase 5 | `home/ssh.nix` (new) | LOW | LOW |
| 7 | Tarsnap pattern (backup paths) | Phase 7 | `modules/restic.nix` | LOW | N/A |

## Open Questions

1. **Syncthing folder structure on new server**
   - What we know: Old server used `/bkp/Sync`, `/bkp/Work`, `/bkp/Media` on a separate Linode Volume
   - What's unclear: Does the Contabo VPS have a similar separate storage volume, or should Syncthing folders go under `/data/syncthing/` or similar?
   - Recommendation: Defer to Phase 6 planning. The structural pattern (explicit paths, receive-only) is portable regardless of mount point.

2. **Current Syncthing device IDs**
   - What we know: Old device IDs are for nixos-dev, x1carbon9, pixel6-pro (likely all replaced)
   - What's unclear: What are the current devices that need to sync with the new server?
   - Recommendation: User provides current device IDs during Phase 6 implementation.

3. **Teleport usage**
   - What we know: .doom.d references Teleport TRAMP integration. Teleport is an access management tool.
   - What's unclear: Is Teleport currently in use for server access? Should it be part of the neurosys networking story?
   - Recommendation: Ask user. If yes, add as Phase 3 or Phase 6 consideration.

4. **Direnv on server**
   - What we know: Commented out in old neurosys, enabled in .doom.d init.el
   - What's unclear: Is per-project direnv useful on the agent server (e.g., for project-specific dev environments)?
   - Recommendation: Consider for Phase 5 dev tools. `programs.direnv.enable = true` in home-manager is trivial to add.

## Sources

### Primary (HIGH confidence)
- `gh api repos/dangirsh/neurosys/contents/...` -- Full source code of all .nix files and README.org
- `gh api repos/dangirsh/.doom.d/contents/...` -- Full source code of all .el files
- Agent-neurosys local codebase (`/data/projects/neurosys/`) -- All current .nix modules

### Secondary (MEDIUM confidence)
- NixOS option renames verified against known migration patterns (20.03 -> 25.11 is a 5-year gap with multiple major renames)

## Metadata

**Confidence breakdown:**
- Repo audit completeness: HIGH -- both repos are small and fully reviewed
- Candidate identification: HIGH -- every file in both repos was read
- Phase mapping: HIGH -- roadmap phases are well-defined with clear module targets
- NixOS option renames: MEDIUM -- some renames may be missing for the 20.03->25.11 gap

**Research date:** 2026-02-14
**Valid until:** No expiry (repos are static/archived; neurosys roadmap is the moving target)
