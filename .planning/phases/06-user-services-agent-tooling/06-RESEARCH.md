# Phase 6: User Services + Agent Tooling - Research

**Researched:** 2026-02-16
**Domain:** NixOS declarative services (Syncthing, CASS), activation scripts (repo cloning, symlinks)
**Confidence:** HIGH

## Summary

This phase covers four distinct concerns: (1) Syncthing declarative file sync as a NixOS system service, (2) CASS agent session indexer as a user-level systemd timer via home-manager, (3) idempotent repo cloning via NixOS activation scripts, and (4) symlink management for agent config (`~/.claude`, `~/.codex`). All four are well-understood NixOS patterns with good documentation.

The NixOS `services.syncthing` module provides full declarative device/folder management with `overrideDevices`/`overrideFolders` and staggered versioning. There is a known issue (#326704) with `overrideDevices = true` on some NixOS versions related to CSRF token handling in the config merge script, but this affects only the API-based merging -- the module still works when `overrideDevices = true` and `overrideFolders = true` are set with `settings.devices`/`settings.folders`. The CASS binary is available as a pre-built Linux amd64 tar.gz from GitHub releases and can be wrapped in a Nix derivation using `fetchurl` + `autoPatchelfHook`. Repo cloning uses `system.activationScripts` with an idempotent guard (`if [ ! -d ... ]`). Symlinks use `home.file` with `config.lib.file.mkOutOfStoreSymlink` for out-of-store directory symlinks.

**Primary recommendation:** Split into 3 plans: (1) Syncthing module, (2) CASS derivation + systemd timer, (3) repo cloning activation scripts + agent config symlinks.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Syncthing configuration
- Single "Sync" folder shared across devices (not multiple named folders)
- Send-receive direction -- full bidirectional sync (acfs is an active participant, not just an archive)
- Staggered versioning enabled -- keep deleted/modified file versions with time-based decay
- Web UI bound to Tailscale IP only -- not accessible on public interface or localhost
- 4 devices declared in Nix: MacBook-Pro.local, DC-1, Pixel 10 Pro, MacBook-Pro-von-Theda.local (from Phase 8 decisions)
- Receive-only mode NOT used -- user explicitly chose send-receive

#### CASS indexer
- Install from pre-built GitHub binary release, wrapped in a Nix derivation
- Index `/data/projects/` only -- focused on code repos the agents work with
- Run as periodic systemd timer (not continuous daemon) -- every 30 minutes
- User-level systemd service (`systemctl --user`)

#### Repo management
- Clone 3 repos: `parts`, `claw-swap`, `global-agent-conf`
- All repos live under `/data/projects/<repo-name>`
- NixOS activation script handles cloning -- checks if repo exists, clones if missing (self-healing)
- Clone-only -- never pull/update existing repos (safest, no surprise force-pulls on dirty working trees)
- Clone via HTTPS using GH_TOKEN (already set up in Phase 5), not SSH

#### Agent config layout
- `global-agent-conf` is a shared Claude Code config repo (CLAUDE.md, skills, hooks, keybindings)
- `~/.claude` is a whole-directory symlink -> `/data/projects/global-agent-conf` (not individual file symlinks)
- `~/.codex` also symlinked from the same repo (Codex config lives alongside Claude config)
- No machine-specific overrides needed on acfs -- shared config works as-is

### Claude's Discretion
- Syncthing staggered versioning decay parameters (hourly/daily/weekly retention)
- Syncthing rescan interval
- CASS binary fetch mechanism (fetchurl vs fetchzip in Nix derivation)
- Activation script error handling (what happens if clone fails -- log and continue vs fail activation)
- Exact symlink creation method (home-manager vs activation script)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| NixOS `services.syncthing` | nixos-25.11 | Declarative Syncthing service with devices/folders | Built-in NixOS module, full declarative config |
| CASS (coding_agent_session_search) | v0.1.64 | AI agent session history search/indexer | Pre-built binary from GitHub, active development |
| home-manager `systemd.user.services` | release-25.11 | User-level systemd service/timer units | Standard home-manager pattern for user services |
| `system.activationScripts` | nixos-25.11 | Idempotent repo cloning at activation time | Built-in NixOS mechanism for imperative setup |
| home-manager `home.file` + `mkOutOfStoreSymlink` | release-25.11 | Symlinks to out-of-store directories | Standard home-manager pattern for mutable symlinks |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `autoPatchelfHook` | Patch pre-built Linux binaries for NixOS | CASS binary derivation |
| `fetchurl` | Download CASS binary from GitHub releases | Nix derivation for CASS |
| `STNODEFAULTFOLDER` env var | Prevent Syncthing from creating "Default Folder" | Syncthing systemd service config |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `system.activationScripts` for repos | home-manager `home.activation` | system-level runs as root (can set ownership); home-manager runs as user but ordering is trickier |
| `home.file` + `mkOutOfStoreSymlink` | activation script with `ln -sfn` | home-manager approach is declarative and tracked; activation script is more explicit |
| `fetchurl` for CASS | `fetchzip` | `fetchurl` downloads the .tar.gz, Nix auto-unpacks; `fetchzip` also works but `fetchurl` is simpler for single-file archives |

## Architecture Patterns

### Module Structure
```
modules/
  syncthing.nix          # NixOS system service: Syncthing declarative config
home/
  cass.nix               # home-manager: CASS derivation + systemd user timer
  default.nix            # (existing) add imports for cass.nix
modules/
  repos.nix              # activation scripts: clone repos + create symlinks
                          # OR split symlinks into home/agent-config.nix
```

### Pattern 1: Syncthing Declarative Service
**What:** NixOS `services.syncthing` with `overrideDevices = true`, `overrideFolders = true`, declarative devices and folders in `settings`.
**When to use:** Always -- this is the standard NixOS pattern.

```nix
# modules/syncthing.nix
{ config, ... }: {
  # Prevent Syncthing from creating a "Default Folder"
  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  services.syncthing = {
    enable = true;
    user = "dangirsh";
    group = "users";
    dataDir = "/home/dangirsh";
    configDir = "/home/dangirsh/.config/syncthing";
    openDefaultPorts = true;  # TCP 22000 + UDP 21027

    # Bind GUI to Tailscale IP only
    guiAddress = "100.x.x.x:8384";  # Replace with actual Tailscale IP

    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = {
        "MacBook-Pro.local" = { id = "DEVICE-ID-HERE"; };
        "DC-1"              = { id = "DEVICE-ID-HERE"; };
        "Pixel 10 Pro"      = { id = "DEVICE-ID-HERE"; };
        "MacBook-Pro-von-Theda.local" = { id = "DEVICE-ID-HERE"; };
      };

      folders = {
        "Sync" = {
          path = "/home/dangirsh/Sync";
          devices = [ "MacBook-Pro.local" "DC-1" "Pixel 10 Pro" "MacBook-Pro-von-Theda.local" ];
          type = "sendreceive";
          rescanIntervalS = 60;  # Recommended: 60s for active bidirectional sync
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";     # Check for old versions every hour
              maxAge = "7776000";         # Keep versions for 90 days (90*24*3600)
            };
          };
        };
      };

      options = {
        urAccepted = -1;  # Disable usage reporting
      };
    };
  };
}
```

### Pattern 2: CASS Binary Derivation + User Timer
**What:** Wrap CASS pre-built binary in a Nix derivation, then run `cass index --full` periodically via home-manager systemd user timer.

```nix
# packages/cass.nix (or inline in home module)
{ stdenv, lib, fetchurl, autoPatchelfHook, openssl, zlib }:

stdenv.mkDerivation rec {
  pname = "cass";
  version = "0.1.64";

  src = fetchurl {
    url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${version}/cass-linux-amd64.tar.gz";
    hash = "sha256-bqMZQO9wKGtZjtNeZlqyDTt0JKOuNvqSs+oBDLpQkWU=";  # Must verify
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib openssl zlib ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -m755 -D cass $out/bin/cass
    runHook postInstall
  '';

  meta = with lib; {
    description = "Unified CLI/TUI to index and search coding agent session history";
    homepage = "https://github.com/Dicklesworthstone/coding_agent_session_search";
    platforms = [ "x86_64-linux" ];
  };
}
```

```nix
# home/cass.nix
{ config, pkgs, ... }:
let
  cass = pkgs.callPackage ../packages/cass.nix {};
in
{
  home.packages = [ cass ];

  systemd.user.services.cass-indexer = {
    Unit = {
      Description = "CASS agent session indexer";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${cass}/bin/cass index --full";
      Environment = [
        "HOME=/home/dangirsh"
      ];
    };
  };

  systemd.user.timers.cass-indexer = {
    Unit = {
      Description = "Run CASS indexer every 30 minutes";
    };
    Timer = {
      OnCalendar = "*:00/30";   # Every 30 minutes
      Persistent = true;        # Run missed timers after boot
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
```

### Pattern 3: Idempotent Repo Cloning via Activation Script
**What:** `system.activationScripts` that checks if repo dir exists, clones if missing, using GH_TOKEN for HTTPS auth.

```nix
# modules/repos.nix
{ config, pkgs, ... }: {
  system.activationScripts.clone-repos = {
    deps = [ "users" ];   # Ensure user exists before cloning
    text = ''
      repos=(
        "dangirsh/parts"
        "dangirsh/claw-swap"
        "dangirsh/global-agent-conf"
      )
      CLONE_DIR="/data/projects"
      GH_TOKEN="$(cat ${config.sops.secrets."github-pat".path} 2>/dev/null || true)"

      for repo in "''${repos[@]}"; do
        name="$(basename "$repo")"
        target="$CLONE_DIR/$name"
        if [ ! -d "$target" ]; then
          echo "Cloning $repo to $target..."
          ${pkgs.git}/bin/git clone "https://''${GH_TOKEN:+$GH_TOKEN@}github.com/$repo.git" "$target" || echo "WARNING: Failed to clone $repo"
          # Fix ownership (activation runs as root)
          chown -R dangirsh:users "$target"
        fi
      done
    '';
  };
}
```

### Pattern 4: Agent Config Symlinks via home-manager
**What:** Use `home.file` with `config.lib.file.mkOutOfStoreSymlink` to create `~/.claude` and `~/.codex` symlinks to `/data/projects/global-agent-conf`.

```nix
# home/agent-config.nix (or in repos.nix as part of activation)
{ config, lib, ... }: {
  home.file.".claude".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/global-agent-conf";

  home.file.".codex".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/global-agent-conf";
}
```

**Note:** `mkOutOfStoreSymlink` creates a two-level symlink: `~/.claude -> /nix/store/xxx -> /data/projects/global-agent-conf`. This is the idiomatic home-manager way to symlink to mutable, out-of-store paths. The target does not need to exist at build time.

### Anti-Patterns to Avoid
- **Using `home.file.".claude".source = /data/projects/global-agent-conf`:** This copies the directory into the Nix store at build time, making it read-only and stale. Always use `mkOutOfStoreSymlink` for mutable targets.
- **Using `home.file` with `recursive = true` for a whole-directory symlink:** `recursive = true` creates individual file symlinks via `lndir`, not a single directory symlink. Omit `recursive` to get a single symlink.
- **Running `git pull` in activation scripts:** User explicitly decided clone-only. Never auto-update repos -- dirty working trees would cause failures or data loss.
- **Using `services.syncthing.declarative`:** This is the old (pre-21.11) syntax. Use `services.syncthing.settings` with `overrideDevices`/`overrideFolders` at the top level.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Syncthing config management | Custom XML generation or API scripts | `services.syncthing.settings` with `overrideDevices`/`overrideFolders` | Module handles API merging, restarts, config file management |
| Binary patching for CASS | Manual `patchelf` invocations | `autoPatchelfHook` in derivation | Hook auto-discovers and patches all needed library paths |
| User systemd timer | Raw systemd unit files in `/etc/systemd/user/` | home-manager `systemd.user.services` + `systemd.user.timers` | Declarative, version-controlled, automatically managed |
| Directory symlinks | `ln -sfn` in activation scripts | `home.file` + `mkOutOfStoreSymlink` | Declarative, home-manager manages lifecycle (creates/removes) |

**Key insight:** NixOS and home-manager already have first-class support for every component in this phase. The only "custom" code is the repo cloning activation script (necessary because git clone is inherently imperative).

## Common Pitfalls

### Pitfall 1: Syncthing overrideDevices CSRF Bug
**What goes wrong:** The `merge-syncthing-config` systemd service may fail silently due to CSRF token errors when applying config via the REST API, especially with many devices/folders.
**Why it happens:** The API key extraction and config merge script doesn't handle CSRF token resets properly (nixpkgs issue #326704).
**How to avoid:** After deploying, verify config was applied: check `systemctl status syncthing-init.service` (or `merge-syncthing-config.service`). If it failed, restart the service or manually accept devices in the web UI.
**Warning signs:** `syncthing-init.service` shows failed or devices don't appear in the web UI despite being in the Nix config.

### Pitfall 2: Syncthing GUI Unreachable When Bound to Tailscale IP
**What goes wrong:** Binding `guiAddress` to a Tailscale IP that hasn't been assigned yet (e.g., Tailscale not connected) makes the GUI completely unreachable.
**Why it happens:** The Syncthing service starts before Tailscale has assigned its IP.
**How to avoid:** Use `0.0.0.0:8384` as `guiAddress` but rely on the NixOS firewall to restrict access. Port 8384 is not in `networking.firewall.allowedTCPPorts`, so it's only reachable via `trustedInterfaces = [ "tailscale0" ]` which is already configured. This achieves the same effect (Tailscale-only access) without depending on IP assignment timing.
**Warning signs:** Cannot access Syncthing web UI even via Tailscale.

### Pitfall 3: CASS Indexes Agent Sessions, NOT Code Directories
**What goes wrong:** User expects CASS to index source code in `/data/projects/`, but CASS actually indexes AI agent conversation history from `~/.claude/projects/`, `~/.codex/sessions/`, etc.
**Why it happens:** CASS (Coding Agent Session Search) is specifically designed to search across coding agent session histories (Claude Code, Codex, Cursor, etc.), not arbitrary source code.
**How to avoid:** Understand that CASS auto-discovers session files from well-known provider locations. The `~/.claude` symlink to `global-agent-conf` will make session data available. CASS does NOT need to be pointed at `/data/projects/` -- it finds sessions automatically.
**Warning signs:** `cass index` reports finding sessions from providers but not indexing code files.

### Pitfall 4: Activation Script Runs as Root
**What goes wrong:** Repos cloned by `system.activationScripts` are owned by root, not `dangirsh`.
**Why it happens:** System activation scripts run as root during `nixos-rebuild switch`.
**How to avoid:** Add `chown -R dangirsh:users "$target"` after each clone. Alternatively, use `sudo -u dangirsh git clone` to clone as the user directly.
**Warning signs:** `ls -la /data/projects/parts` shows `root:root` ownership, and agents can't write to repos.

### Pitfall 5: mkOutOfStoreSymlink Target Must Be Absolute Path String
**What goes wrong:** Using a Nix path literal (e.g., `/data/projects/global-agent-conf` without quotes) gets copied into the Nix store.
**Why it happens:** Nix path literals are automatically copied to the store. `mkOutOfStoreSymlink` expects a string.
**How to avoid:** Always pass a string: `config.lib.file.mkOutOfStoreSymlink "/data/projects/global-agent-conf"` (with quotes).
**Warning signs:** `~/.claude` points to `/nix/store/...` instead of `/data/projects/global-agent-conf`.

### Pitfall 6: CASS Binary May Need Runtime Libraries
**What goes wrong:** CASS binary crashes with "not found" or dynamic linker errors on NixOS.
**Why it happens:** Pre-built Linux binaries assume standard FHS library paths that don't exist on NixOS.
**How to avoid:** Use `autoPatchelfHook` in the derivation and add likely runtime deps (`stdenv.cc.cc.lib`, `openssl`, `zlib`) to `buildInputs`. If it still fails, run `ldd` on the binary to identify missing libraries.
**Warning signs:** `cass --version` fails with "No such file or directory" (dynamic linker not found).

### Pitfall 7: Syncthing Device IDs Are Placeholders
**What goes wrong:** Syncthing config deploys but no devices connect.
**Why it happens:** Device IDs in the Nix config are placeholders that need to be replaced with actual device IDs from each device's Syncthing instance.
**How to avoid:** Collect real device IDs from each device before deploying. Device IDs are shown in Syncthing Web UI under Actions > Show ID, or via `syncthing -device-id` CLI.
**Warning signs:** Syncthing web UI shows configured devices but they never connect.

## Code Examples

### HTTPS Clone URL with Token Authentication
```bash
# Pattern: https://TOKEN@github.com/owner/repo.git
git clone "https://${GH_TOKEN}@github.com/dangirsh/global-agent-conf.git" /data/projects/global-agent-conf
```
Source: Standard GitHub HTTPS token auth pattern

### home-manager systemd User Timer
```nix
# Source: home-manager docs + NixOS Discourse
systemd.user.services.my-service = {
  Unit.Description = "My periodic service";
  Service = {
    Type = "oneshot";
    ExecStart = "${pkg}/bin/command";
  };
};

systemd.user.timers.my-service = {
  Unit.Description = "Run my-service periodically";
  Timer = {
    OnCalendar = "*:00/30";  # Every 30 minutes
    Persistent = true;       # Catch up after missed runs
  };
  Install.WantedBy = [ "timers.target" ];
};
```

### Activation Script with Dependencies
```nix
# Source: NixOS nixpkgs activation-script.nix
system.activationScripts.my-script = {
  deps = [ "users" "etc" ];  # Run after users and /etc are set up
  text = ''
    if [ ! -d "/some/path" ]; then
      mkdir -p "/some/path"
    fi
  '';
};
```

### Syncthing Staggered Versioning Parameters
```nix
# Source: Syncthing docs + NixOS module
# Staggered versioning keeps:
#   - One version per 30s for the first hour
#   - One version per hour for the first day
#   - One version per day for the first month
#   - One version per week until maxAge
versioning = {
  type = "staggered";
  params = {
    cleanInterval = "3600";     # Seconds between cleanup runs (1 hour)
    maxAge = "7776000";         # Max age in seconds (90 days = 90*24*3600)
    # Syncthing's built-in retention schedule handles hourly/daily/weekly
    # automatically based on file age. Only cleanInterval and maxAge are
    # configurable params.
  };
};
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `services.syncthing.declarative.devices` | `services.syncthing.settings.devices` | NixOS 21.11 | Old `declarative` attribute renamed; new syntax under `settings` |
| `services.syncthing.declarative.folders` | `services.syncthing.settings.folders` | NixOS 21.11 | Same migration as devices |
| Manual `patchelf` for binaries | `autoPatchelfHook` | nixpkgs 19.09 | Automatic binary patching, no manual invocations |
| `home.file.source = /path` for mutable files | `home.file.source = config.lib.file.mkOutOfStoreSymlink "/path"` | home-manager ~22.11 | Enables symlinks to mutable out-of-store paths |

**Deprecated/outdated:**
- `services.syncthing.declarative`: Renamed to top-level options under `services.syncthing.settings`. Using `declarative` on nixos-25.11 will likely error.

## Discretion Recommendations

### Syncthing Staggered Versioning Parameters
**Recommendation:** `cleanInterval = "3600"` (1 hour), `maxAge = "7776000"` (90 days).
**Rationale:** 90 days provides good recovery window without excessive disk usage. The built-in retention schedule (30s/hourly/daily/weekly) is automatic and not configurable via params -- only `cleanInterval` and `maxAge` are settable. 90 days is a common default in the Syncthing community.

### Syncthing Rescan Interval
**Recommendation:** `rescanIntervalS = 60` (1 minute).
**Rationale:** For an active bidirectional sync setup, 60 seconds balances responsiveness with resource usage. The default is 3600s (1 hour) which is too slow for an active development workflow. Syncthing also uses filesystem watchers (inotify) for instant detection, so rescans are mainly a safety net.

### CASS Binary Fetch Mechanism
**Recommendation:** Use `fetchurl` (not `fetchzip`).
**Rationale:** The CASS release is a `.tar.gz` containing a single `cass` binary. `fetchurl` downloads the archive and Nix's default unpack phase handles tar extraction. `fetchzip` would also work but is typically used for zip files or when you want hash-of-contents rather than hash-of-archive.

### Activation Script Error Handling
**Recommendation:** Log warning and continue (don't fail activation).
**Rationale:** A failed git clone should not prevent the entire NixOS activation from completing. The system should boot and be functional even if a repo clone fails (e.g., due to network issues). Use `|| echo "WARNING: Failed to clone $repo"` pattern. The clone will succeed on the next `nixos-rebuild switch`.

### Symlink Creation Method
**Recommendation:** Use home-manager `home.file` with `config.lib.file.mkOutOfStoreSymlink`.
**Rationale:** This is the idiomatic, declarative approach. home-manager tracks the symlink and will clean it up if removed from config. An activation script `ln -sfn` would work but is imperative and not tracked. The only caveat is that `mkOutOfStoreSymlink` creates a two-level symlink (via store), but this is transparent to applications.

## Open Questions

1. **CASS Runtime Dependencies**
   - What we know: CASS is a Rust binary that uses Tantivy for full-text search. It likely links against libc, openssl, and zlib.
   - What's unclear: Exact shared library dependencies may not be `openssl` + `zlib` -- could need different libs.
   - Recommendation: Build the derivation, run `ldd` on the binary if `autoPatchelfHook` fails, and add missing libraries to `buildInputs`.

2. **CASS Session Discovery with Symlinked ~/.claude**
   - What we know: CASS auto-discovers sessions from `~/.claude/projects/` and other well-known paths.
   - What's unclear: Whether CASS follows symlinks (it should, but untested with the specific `~/.claude -> global-agent-conf` layout).
   - Recommendation: After deploying, run `cass health --json` to verify it discovers sessions correctly. The `global-agent-conf` repo contains config (CLAUDE.md, skills, hooks), while session data is written by Claude Code at runtime -- so sessions may not exist until agents have been used on this server.

3. **Syncthing Device IDs**
   - What we know: 4 devices need their IDs declared. IDs are unique per-device cryptographic identifiers.
   - What's unclear: The actual device IDs are not in the codebase -- they must be collected from each device.
   - Recommendation: Config should use PLACEHOLDER values initially. User must replace with real IDs before deploying. Document how to obtain device IDs.

4. **GitHub Repo Org/Owner Names**
   - What we know: Repos are `parts`, `claw-swap`, `global-agent-conf` under `/data/projects/`.
   - What's unclear: The exact GitHub owner/org for each repo (e.g., `dangirsh/parts` vs some org).
   - Recommendation: Use placeholder owner in the clone URLs. User must fill in correct GitHub paths before deploying.

5. **CASS vs User's Expectation of Code Indexing**
   - What we know: User's CONTEXT.md says "Index `/data/projects/` only" but CASS indexes agent sessions, not code files.
   - What's unclear: Whether user wants a different tool for code indexing, or whether the "index `/data/projects/`" instruction was based on a misunderstanding of what CASS does.
   - Recommendation: Planner should note this discrepancy. CASS will index agent session histories (which is very useful for the agent workflow), but it does NOT index source code files. The `cass index` command scans well-known session directories automatically.

## Sources

### Primary (HIGH confidence)
- NixOS nixpkgs `services/networking/syncthing.nix` - Module source for all Syncthing options
- [NixOS Official Wiki - Syncthing](https://wiki.nixos.org/wiki/Syncthing) - Configuration examples
- [MyNixOS - services.syncthing options](https://mynixos.com/nixpkgs/options/services.syncthing) - Full option reference
- [GitHub - CASS releases](https://github.com/Dicklesworthstone/coding_agent_session_search/releases) - Binary release assets verified via GitHub API
- [NixOS Wiki - Packaging Binaries](https://wiki.nixos.org/wiki/Packaging/Binaries) - autoPatchelfHook pattern
- [home-manager tests/modules/files/out-of-store-symlink.nix](https://github.com/nix-community/home-manager/blob/master/tests/modules/files/out-of-store-symlink.nix) - mkOutOfStoreSymlink test

### Secondary (MEDIUM confidence)
- [Kristoffer Balintona - Syncthing NixOS](https://kristofferbalintona.me/posts/202505042219/) - Working config with new `settings` syntax, verified May 2025
- [NixOS Discourse - systemd user timers](https://discourse.nixos.org/t/implementing-systemd-timers-in-home-manager/32001) - home-manager timer patterns
- [NixOS Discourse - activation scripts](https://discourse.nixos.org/t/system-activationscripts/22924) - Activation script patterns and ordering
- [Syncthing docs - GUI Listen Address](https://docs.syncthing.net/users/guilisten.html) - guiAddress and insecureSkipHostcheck
- [GitHub - nixpkgs issue #326704](https://github.com/NixOS/nixpkgs/issues/326704) - overrideDevices CSRF bug

### Tertiary (LOW confidence)
- CASS runtime library requirements - Based on typical Rust binary dependencies, needs validation with actual `ldd` output
- CASS session discovery with symlinked `~/.claude` - Logical inference, not tested

## Metadata

**Confidence breakdown:**
- Syncthing NixOS module: HIGH - Well-documented, multiple verified sources, module source code reviewed
- CASS derivation: MEDIUM - Binary release verified, derivation pattern standard, but runtime deps unverified
- Repo cloning activation scripts: HIGH - Standard NixOS pattern, well-understood
- Agent config symlinks: HIGH - `mkOutOfStoreSymlink` verified via home-manager test suite
- CASS functionality scope: HIGH - Verified via README and project page that it indexes agent sessions, not code

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days -- all components are stable)
