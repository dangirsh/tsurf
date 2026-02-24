# Phase 24: Server Hardening + DX - Research

**Researched:** 2026-02-23
**Domain:** NixOS server hardening (srvos), bubblewrap sandbox isolation, devShell/treefmt-nix DX
**Confidence:** HIGH

## Summary

This phase has three independent work streams: (1) adopting srvos server profile for battle-tested hardening defaults, (2) tightening agent-spawn bubblewrap with PID and cgroup namespace isolation, and (3) adding devShell + treefmt-nix for developer experience. All three are well-understood, low-risk changes with clear implementation paths.

The srvos `server` profile is a single import that brings ~40 defaults. After detailed analysis of every srvos source file against the existing neurosys config, I identified 5 settings that need explicit overrides and 3 that are harmlessly redundant (srvos uses `mkDefault`, existing explicit sets win). The bubblewrap changes are two flags added to an existing argument array. The treefmt-nix integration is a standard `evalModule` pattern without flake-parts.

**Primary recommendation:** Import srvos as a flake input, add it as the first module in the NixOS config (so existing explicit settings take priority over its `mkDefault` values), then apply the 5 documented overrides.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Import `srvos.nixosModules.server` as flake input -- get ~48 hardening defaults in one line
- Override `networking.useNetworkd = false` (Contabo static IP uses scripted networking)
- Override `documentation.enable = true` and `documentation.man.enable = true` (dev server, agents and humans need man pages)
- Override `programs.command-not-found.enable = true` (helpful for interactive sessions)
- Override `boot.initrd.systemd.enable = false` (defer to Phase 21 impermanence -- don't change initrd independently)
- Accept everything else: emergency mode off, watchdog timers, sleep disabled, OOM priority, LLMNR off, nix daemon scheduling, disk space guards, serial console, known hosts, sudo lecture off, update-diff, hostname change detection
- gVisor: Skip entirely
- Add `--unshare-pid` and `--unshare-cgroup` to agent-spawn bwrap flags
- Docker commands still work through the socket (PID namespace doesn't affect Unix socket communication)
- Add `devShell` to flake.nix with sops, age, deploy-rs CLI, nixfmt, shellcheck
- Add treefmt-nix with nixfmt + shellcheck; `nix fmt` formats Nix and lints shell
- No pre-commit hook enforcement (agents run manually)

### Claude's Discretion
- Exact devShell package list (sops + age + deploy-rs + nixfmt + shellcheck as baseline, add more if useful)
- treefmt-nix configuration details
- Which srvos overrides need `mkForce` vs `mkDefault` vs direct set
- Order of srvos import vs existing module imports (to get priority right)
- Any additional srvos defaults that need overriding if they conflict with existing config

### Deferred Ideas (OUT OF SCOPE)
- gVisor Docker runtime -- Rejected for now
- Flake check toplevel build -- Skipped for speed
- systemd initrd -- Defer to Phase 21 (impermanence)
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| srvos | latest (nix-community/srvos) | ~40 server hardening defaults in one import | Numtide-maintained, battle-tested across production servers, used by NixOS ecosystem |
| treefmt-nix | latest (numtide/treefmt-nix) | Multi-formatter orchestration via `nix fmt` | Official Nix ecosystem formatter integration, supports 127+ formatters |
| nixfmt | bundled via treefmt-nix | Official Nix code formatter | The official NixOS formatter (NixOS/nixfmt) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shellcheck | via treefmt-nix programs | Shell script linting | Runs on all .sh files via `nix fmt` |
| nvd | bundled via srvos update-diff | Show package diff on deploy | Automatic -- srvos enables update-diff by default |

### Alternatives Considered
None -- all choices are locked decisions from CONTEXT.md.

**Installation (flake inputs to add):**
```nix
srvos = {
  url = "github:nix-community/srvos";
  inputs.nixpkgs.follows = "nixpkgs";
};
treefmt-nix = {
  url = "github:numtide/treefmt-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

## Architecture Patterns

### srvos Module Import Order

**Critical finding:** srvos uses `lib.mkDefault` for almost every setting. This means any explicit value in the neurosys modules (set without `mkDefault`) automatically wins. The import order matters primarily for cases where both srvos and neurosys use `mkDefault`.

**Recommended approach:** Import srvos as the FIRST module in the NixOS config list, before `./hosts/neurosys`. This ensures all explicit settings in neurosys modules override srvos defaults, and any `mkDefault` conflicts are resolved in favor of the module imported later (neurosys).

```nix
modules = [
  srvos.nixosModules.server          # First: lowest priority defaults
  disko.nixosModules.disko
  impermanence.nixosModules.impermanence
  sops-nix.nixosModules.sops
  # ... rest unchanged
];
```

### srvos Conflict Analysis (Complete)

Every srvos setting analyzed against current neurosys config:

#### Conflicts Requiring Override (5)

| srvos Setting | srvos Value | Neurosys Current | Action | Priority Mechanism |
|---------------|-------------|------------------|--------|--------------------|
| `networking.useNetworkd` | `mkDefault true` | Not set (implicit false) | Override with `lib.mkForce false` | srvos mkDefault would win since neurosys doesn't set it -- MUST use mkForce |
| `documentation.enable` | `mkDefault false` (via `srvos.server.docs.enable` default false) | Not set | Set `srvos.server.docs.enable = true` | Use the srvos option directly -- it controls all doc sub-options |
| `programs.command-not-found.enable` | `mkDefault false` | Not set | Set `programs.command-not-found.enable = true` | Direct set beats mkDefault |
| `boot.initrd.systemd.enable` | Not set by srvos | Not set | No action needed | srvos does NOT set this -- the CONTEXT.md override is a no-op safety check. Skip unless srvos adds it later. |
| `time.timeZone` | `mkDefault "UTC"` | `"Europe/Berlin"` (explicit) | No action needed | Explicit set in hosts/neurosys/default.nix already wins over mkDefault |

**Key finding on `boot.initrd.systemd.enable`:** After reading every srvos source file, srvos does NOT set `boot.initrd.systemd.enable`. The CONTEXT.md lists this as an override, but it is unnecessary. The setting is only relevant if a future srvos version adds it. Recommendation: skip this override but add a comment noting the Phase 21 boundary.

#### Harmlessly Redundant Settings (both srvos and neurosys set the same thing)

| Setting | srvos Value | Neurosys Value | Notes |
|---------|-------------|----------------|-------|
| `networking.firewall.enable` | `true` (no mkDefault -- force) | `true` (explicit) | Identical, no conflict |
| `networking.firewall.allowPing` | `true` | `true` | Identical |
| `users.mutableUsers` | `false` | `false` | Identical |
| `security.sudo.wheelNeedsPassword` | `false` | `false` | Identical |
| `security.sudo.execWheelOnly` | `true` | `true` | Identical |
| `services.openssh.enable` | `true` | `true` | Identical |
| `services.openssh.settings.PasswordAuthentication` | `false` | `false` | Identical |
| `services.openssh.settings.KbdInteractiveAuthentication` | `false` | `false` | Identical |
| `nix.settings.experimental-features` | `["nix-command" "flakes"]` | `["nix-command" "flakes"]` | List merge, no conflict |

#### New Settings srvos Adds (accepted per CONTEXT.md)

| Setting | Value | What It Does |
|---------|-------|--------------|
| `systemd.enableEmergencyMode` | `false` | Headless server continues booting on errors instead of dropping to emergency shell |
| `systemd.sleep.extraConfig` | No suspend/hibernate | Prevents accidental sleep on server |
| `systemd.settings.Manager.RuntimeWatchdogSec` | `15s` | Hardware watchdog: forced reboot if system hangs 15s |
| `systemd.settings.Manager.RebootWatchdogSec` | `30s` | Forced reboot if shutdown hangs 30s |
| `systemd.settings.Manager.KExecWatchdogSec` | `1m` | Forced reboot if kexec hangs 1m |
| `systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust` | `250` | Nix builds killed before user sessions on OOM |
| `nix.daemonCPUSchedPolicy` | `"batch"` | Nix daemon uses batch CPU scheduling |
| `nix.daemonIOSchedClass` | `"idle"` | Nix daemon uses idle I/O scheduling |
| `nix.daemonIOSchedPriority` | `7` | Lowest I/O priority for nix daemon |
| `systemd.services.nix-gc.serviceConfig` | batch/idle scheduling | GC doesn't steal I/O from services |
| `nix.optimise.automatic` | `true` | Auto-deduplicate store (complements existing `auto-optimise-store`) |
| `nix.settings.trusted-users` | `["@wheel"]` | Wheel group trusted for Nix operations |
| `nix.channel.enable` | `false` | Disable channels (using flakes) |
| `nix.settings.connect-timeout` | `5` | Fast fallback when substituters unavailable |
| `nix.settings.fallback` | `true` | Build locally if substituter fails |
| `nix.settings.log-lines` | `25` | More build log context (default 10 is too little) |
| `nix.settings.max-free` | `3GB` | Disk space guard for nix store |
| `nix.settings.min-free` | `512MB` | Trigger GC when free space drops |
| `nix.settings.builders-use-substitutes` | `true` | Remote builders fetch from caches directly |
| `services.resolved.settings.Resolve.LLMNR` | `"false"` | Prevent LLMNR poisoning attacks |
| `networking.firewall.logRefusedConnections` | `false` | Don't spam logs with refused connections |
| `boot.loader.grub.configurationLimit` | `5` | Limit boot entries (neurosys has 10, srvos mkDefault 5 -- neurosys wins) |
| `programs.ssh.knownHosts` | GitHub, GitLab, SourceHut | Pre-trusted host keys, prevents TOFU MITM |
| `services.openssh.authorizedKeysFiles` | System-level only | Prevents SSH key injection via user home dirs |
| `services.openssh.settings.UseDns` | `false` | Faster SSH connections |
| `services.openssh.settings.StreamLocalBindUnlink` | `true` | Clean up stale gnupg sockets |
| `services.openssh.settings.X11Forwarding` | `false` | Disable unused X11 forwarding |
| `environment.stub-ld.enable` | `false` | No dynamic linker stubs (server, not needed) |
| `fonts.fontconfig.enable` | `false` | No font rendering on server |
| `xdg.*.enable` | `false` (all) | No desktop autostart/icons/menus/mime/sounds |
| `programs.vim.defaultEditor` | `true` | Vim as default editor |
| Serial console config | ttyS0,115200 + grub serial | IPMI/BMC emergency access |
| `srvos.detect-hostname-change` | enabled | Warns if deploying to wrong host |
| `srvos.update-diff` | enabled (uses nvd) | Shows package diff before switch |
| `networking.hostName` | `mkOverride 1337 ""` | Lowest priority, neurosys explicit "neurosys" wins |
| ZFS defaults | hostId, auto-snapshot, scrub | Only active if ZFS is enabled (it isn't on neurosys) |

#### Potential Concern: `authorizedKeysFiles`

srvos sets `services.openssh.authorizedKeysFiles = mkForce ["/etc/ssh/authorized_keys.d/%u"]` UNLESS gitea/gitlab/forgejo/gitolite/gerrit are enabled. This means SSH authorized keys MUST be in `/etc/ssh/authorized_keys.d/` format instead of `~/.ssh/authorized_keys`.

**Impact on neurosys:** NixOS already manages authorized keys via `users.users.*.openssh.authorizedKeys.keys`, which writes to `/etc/ssh/authorized_keys.d/%u` by default. This should work seamlessly. Verify after deployment that SSH access still works.

#### Potential Concern: `nix.optimise.automatic` vs `nix.settings.auto-optimise-store`

srvos sets `nix.optimise.automatic = true` (periodic systemd timer). Neurosys already has `nix.settings.auto-optimise-store = true` (inline during builds). These are complementary, not conflicting. The periodic optimizer catches anything the inline optimizer missed.

### treefmt-nix Integration (Without flake-parts)

The neurosys flake does NOT use flake-parts. Use the `evalModule` pattern directly.

```nix
# In flake.nix outputs:
let
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
in {
  formatter.x86_64-linux = treefmtEval.config.build.wrapper;
  # Optional: add formatting check to flake checks
  # checks.x86_64-linux.formatting = treefmtEval.config.build.check self;
}
```

```nix
# treefmt.nix (new file at repo root)
{ pkgs, ... }: {
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.shellcheck.enable = true;
}
```

**Note on checks integration:** The existing `checks` attribute uses `builtins.mapAttrs` over deploy-rs checks. Adding the formatting check requires merging the two check sets. Use `//` (attribute merge) or restructure.

### devShell Pattern

```nix
devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
  packages = with nixpkgs.legacyPackages.x86_64-linux; [
    sops
    age
    nixfmt   # or reference from treefmtEval
    shellcheck
    deploy-rs.packages.x86_64-linux.default
  ];
};
```

### Bubblewrap PID + cgroup Isolation

Add two flags to the existing `BWRAP_ARGS` array in `agent-compute.nix`:

```nix
BWRAP_ARGS=(
  --unshare-user --uid "$RUNTIME_UID" --gid "$RUNTIME_GID"
  --unshare-ipc
  --unshare-uts
  --unshare-pid       # NEW: agents cannot see host processes
  --unshare-cgroup    # NEW: agents cannot see host cgroup hierarchy
  --disable-userns
  # ... rest unchanged
)
```

**Interaction with `--proc /proc`:** When `--unshare-pid` is active, `--proc /proc` mounts a new procfs that only shows processes in the sandboxed PID namespace. This is the correct and expected behavior -- agents will see their own process tree starting at PID 1 (bwrap's minimal init), but cannot see host processes.

**Interaction with Docker:** PID namespace isolation does NOT affect Unix socket communication. Agents can still send Docker API commands through the bind-mounted socket. The Docker daemon runs on the host and executes containers normally. This is how Docker-in-namespace works everywhere.

### Recommended Project Structure Changes

```
flake.nix              # Add srvos + treefmt-nix inputs, devShell, formatter outputs
treefmt.nix            # NEW: treefmt-nix configuration (nixfmt + shellcheck)
modules/
  agent-compute.nix    # Add --unshare-pid, --unshare-cgroup to bwrap args
  srvos-overrides.nix  # NEW: srvos overrides (networkd, docs, command-not-found)
  default.nix          # Add import of srvos-overrides.nix
```

**Alternative (simpler):** Instead of a separate `srvos-overrides.nix`, put overrides inline in `hosts/neurosys/default.nix` since there are only 3 actual overrides needed. This avoids creating a new module for <10 lines. Per CLAUDE.md simplicity conventions: "prefer adding to existing modules over creating new ones for <20 lines."

**Recommendation:** Put overrides in `hosts/neurosys/default.nix` (the host-specific config file), since these are host-specific overrides of srvos defaults.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Server hardening defaults | Individual sysctl/systemd settings | srvos server profile | 40+ settings maintained by experts, tested across production |
| Multi-formatter orchestration | Custom script calling nixfmt + shellcheck | treefmt-nix | Handles file discovery, caching, parallel execution |
| Package diff on deploy | Custom diff script | srvos update-diff (nvd) | Already integrated, shows closure diff automatically |
| SSH known hosts | Manual host key management | srvos well-known-hosts | Pre-trusted keys for GitHub/GitLab/SourceHut |

**Key insight:** srvos embodies the "don't hand-roll" principle -- it replaces dozens of individual hardening settings with one import that is maintained upstream.

## Common Pitfalls

### Pitfall 1: networkd Enabling Breaks Contabo Static IP
**What goes wrong:** srvos sets `networking.useNetworkd = mkDefault true`. On Contabo VPS with static IP configured via scripted networking (`networking.interfaces.eth0.ipv4.addresses`), switching to systemd-networkd requires completely different network config and may lose connectivity.
**Why it happens:** srvos assumes modern networkd is better (it usually is), but Contabo's static IP setup uses the legacy scripted approach.
**How to avoid:** Override with `networking.useNetworkd = lib.mkForce false` in the host config. Must use `mkForce` because srvos uses `mkDefault` and without mkForce, if both are mkDefault, import order determines winner.
**Warning signs:** Network unreachable after deploy, SSH connection dropped.

### Pitfall 2: Documentation Disabled Breaks Agent Workflows
**What goes wrong:** srvos disables all documentation by default (`documentation.enable = false`, `documentation.man.enable = false`). Agents that rely on `man` pages or `--help` output fail.
**Why it happens:** srvos targets headless servers where docs waste disk space. Neurosys is a dev/agent server.
**How to avoid:** Set `srvos.server.docs.enable = true` -- this single option re-enables all doc sub-options.
**Warning signs:** `man` command not found, `--help` output missing.

### Pitfall 3: Existing `checks` Attribute Conflict with treefmt
**What goes wrong:** The flake already has `checks = builtins.mapAttrs ...` for deploy-rs. Adding treefmt check requires merging, not replacing.
**Why it happens:** Nix flake outputs are attribute sets; two `checks` definitions conflict.
**How to avoid:** Merge check sets: `checks.x86_64-linux = (deploy-rs checks) // { formatting = treefmtEval... };` or restructure the existing checks to be per-system.
**Warning signs:** `nix flake check` either misses deploy checks or formatting checks.

### Pitfall 4: authorizedKeysFiles mkForce May Surprise
**What goes wrong:** srvos uses `mkForce` on `authorizedKeysFiles` to restrict to `/etc/ssh/authorized_keys.d/%u` only. If any SSH auth relies on `~/.ssh/authorized_keys`, it breaks.
**Why it happens:** srvos prevents SSH key injection via user home directories.
**How to avoid:** NixOS `users.users.*.openssh.authorizedKeys.keys` already writes to `/etc/ssh/authorized_keys.d/%u`, so this should be fine. Verify SSH access immediately after first deploy.
**Warning signs:** SSH access denied after deploy.

### Pitfall 5: --unshare-pid Breaks Process Monitoring Inside Sandbox
**What goes wrong:** `ps aux` inside the sandbox only shows sandbox processes, not host processes. Agents monitoring host health via procfs will see incomplete data.
**Why it happens:** PID namespace isolation is working as intended.
**How to avoid:** This is the desired behavior. Agents that need host process visibility must use `--no-sandbox`.
**Warning signs:** None -- this is a feature, not a bug.

### Pitfall 6: nix.gc Overlap
**What goes wrong:** srvos sets `nix-gc` systemd service scheduling. Neurosys already has `nix.gc.automatic = true` with `dates = "weekly"` and `options = "--delete-older-than 30d"`.
**Why it happens:** srvos adds scheduling priority (batch/idle) to the gc service, not the gc settings. These are complementary.
**How to avoid:** No action needed. srvos's scheduling config applies to the same service that neurosys's gc settings configure. The gc runs weekly per neurosys config, with batch/idle priority per srvos config.

## Code Examples

### srvos Integration in flake.nix
```nix
# Source: Verified against srvos source code (nix-community/srvos)
{
  inputs = {
    # ... existing inputs ...
    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ..., srvos, treefmt-nix, ... } @ inputs:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
  in {
    nixosConfigurations.neurosys = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        srvos.nixosModules.server  # First: base hardening defaults
        disko.nixosModules.disko
        # ... rest of existing modules ...
      ];
    };

    formatter.${system} = treefmtEval.config.build.wrapper;

    devShells.${system}.default = pkgs.mkShell {
      packages = [
        pkgs.sops
        pkgs.age
        pkgs.nixfmt
        pkgs.shellcheck
        deploy-rs.packages.${system}.default
      ];
    };

    # Merge deploy-rs checks with formatting check
    checks = builtins.mapAttrs
      (system: deployLib: deployLib.deployChecks self.deploy // {
        formatting = treefmtEval.config.build.check self;
      })
      deploy-rs.lib;
  };
}
```

### srvos Overrides in hosts/neurosys/default.nix
```nix
# Source: Verified against srvos source analysis
{ config, pkgs, inputs, lib, ... }: {
  # ... existing config ...

  # --- srvos overrides ---
  # Contabo VPS uses scripted networking for static IP, not systemd-networkd
  networking.useNetworkd = lib.mkForce false;
  # Dev server: agents and humans need man pages and --help
  srvos.server.docs.enable = true;
  # Helpful for interactive sessions
  programs.command-not-found.enable = true;
}
```

### treefmt.nix Configuration
```nix
# Source: Verified against treefmt-nix README (numtide/treefmt-nix)
{ pkgs, ... }: {
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.shellcheck.enable = true;
}
```

### Agent-spawn PID + cgroup Isolation
```nix
# Source: bubblewrap manpage (bwrap(1))
# In modules/agent-compute.nix, add to BWRAP_ARGS:
BWRAP_ARGS=(
  --unshare-user --uid "$RUNTIME_UID" --gid "$RUNTIME_GID"
  --unshare-ipc
  --unshare-uts
  --unshare-pid       # Agents cannot see host processes or kill system services
  --unshare-cgroup    # Agents cannot see host cgroup hierarchy
  --disable-userns
  --hostname "sandbox-$NAME"
  --die-with-parent
  --new-session
  # ... rest unchanged ...
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Cherry-pick individual hardening settings | Import srvos server profile | srvos stable since 2023 | One import replaces dozens of manual settings |
| `nixpkgs-fmt` for Nix formatting | `nixfmt` (official NixOS formatter) | 2024 (nixfmt became official) | Use `programs.nixfmt.enable = true` in treefmt |
| `nix-shell` for dev environments | `nix develop` (flake devShells) | 2022+ (flakes stable) | Already using flakes |
| Manual `bwrap --unshare-all` | Selective namespace unsharing | Always | `--unshare-all` is too broad; selective gives control |

**Deprecated/outdated:**
- `nixpkgs-fmt`: Superseded by `nixfmt` as the official Nix formatter
- `alejandra`: Alternative formatter, but `nixfmt` is now official
- srvos repo URL `github:numtide/srvos`: Moved to `github:nix-community/srvos` (numtide donated it)

## Open Questions

1. **srvos `authorizedKeysFiles` mkForce behavior**
   - What we know: srvos uses `mkForce` to restrict SSH authorized keys to `/etc/ssh/authorized_keys.d/%u`. NixOS `users.users.*.openssh.authorizedKeys.keys` writes there by default.
   - What's unclear: Whether impermanence (Phase 21) persists `/etc/ssh/authorized_keys.d/` correctly (it persists `/etc/ssh` which should include this).
   - Recommendation: Verify SSH access immediately after first deploy with srvos. Low risk -- existing impermanence config persists `/etc/ssh`.

2. **treefmt check merge with deploy-rs checks**
   - What we know: Both produce `checks` attributes. The merge pattern (`//`) works.
   - What's unclear: Whether `deploy-rs.lib` mapAttrs produces checks for all systems or just x86_64-linux. The formatting check is only for x86_64-linux.
   - Recommendation: Test with `nix flake check` after integration. May need to guard formatting check to x86_64-linux only.

## Sources

### Primary (HIGH confidence)
- [srvos/nixos/server/default.nix](https://github.com/nix-community/srvos/blob/main/nixos/server/default.nix) - Complete server profile source
- [srvos/shared/server.nix](https://github.com/nix-community/srvos/blob/main/shared/server.nix) - Server docs/packages
- [srvos/nixos/common/networking.nix](https://github.com/nix-community/srvos/blob/main/nixos/common/networking.nix) - networkd default, firewall settings
- [srvos/nixos/common/nix.nix](https://github.com/nix-community/srvos/blob/main/nixos/common/nix.nix) - Nix daemon scheduling, OOM, disk guards
- [srvos/nixos/common/openssh.nix](https://github.com/nix-community/srvos/blob/main/nixos/common/openssh.nix) - SSH hardening, authorizedKeysFiles
- [srvos/nixos/common/sudo.nix](https://github.com/nix-community/srvos/blob/main/nixos/common/sudo.nix) - sudo wheel-only, no lecture
- [srvos/shared/common/nix.nix](https://github.com/nix-community/srvos/blob/main/shared/common/nix.nix) - Flakes, channels, disk guards
- [srvos/shared/common/well-known-hosts.nix](https://github.com/nix-community/srvos/blob/main/shared/common/well-known-hosts.nix) - GitHub/GitLab known hosts
- [srvos/nixos/common/serial.nix](https://github.com/nix-community/srvos/blob/main/nixos/common/serial.nix) - Serial console config
- [srvos/nixos/common/detect-hostname-change.nix](https://github.com/nix-community/srvos/blob/main/nixos/common/detect-hostname-change.nix) - Hostname change detection
- [srvos/shared/common/update-diff.nix](https://github.com/nix-community/srvos/blob/main/shared/common/update-diff.nix) - nvd diff on deploy
- [treefmt-nix README](https://github.com/numtide/treefmt-nix) - evalModule pattern, formatter integration
- [bubblewrap manpage](https://man.archlinux.org/man/extra/bubblewrap/bwrap.1.en) - --unshare-pid, --unshare-cgroup flags

### Secondary (MEDIUM confidence)
- [Arch Wiki Bubblewrap](https://wiki.archlinux.org/title/Bubblewrap) - PID namespace + procfs behavior confirmed
- [NixOS Asia treefmt guide](https://nixos.asia/en/treefmt) - treefmt-nix integration patterns

### Tertiary (LOW confidence)
- None -- all findings verified against primary sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all source code read directly from upstream repos
- Architecture (srvos conflicts): HIGH - every srvos module file read and compared against neurosys config line-by-line
- Architecture (treefmt-nix): HIGH - official README pattern, well-documented
- Architecture (bwrap flags): HIGH - manpage + Arch Wiki confirmation
- Pitfalls: HIGH - derived from conflict analysis above
- devShell: HIGH - standard Nix pattern, no ambiguity

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (stable ecosystem, 30-day validity)
