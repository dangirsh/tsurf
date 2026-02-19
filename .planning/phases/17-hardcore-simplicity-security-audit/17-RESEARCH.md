# Phase 17: Hardcore Simplicity & Security Audit - Research

**Researched:** 2026-02-19
**Domain:** NixOS infrastructure audit -- simplicity (YAGNI), security (hardening), agentic guardrails
**Confidence:** HIGH

## Summary

This phase is a comprehensive line-by-line audit of 14 Nix modules (~530 lines), 7 home-manager modules (~70 lines), 2 packages, 1 deploy script (~200 lines), and 1 bubblewrap sandbox script (~220 lines embedded in agent-compute.nix). The codebase is already quite lean -- Phase 9 did an initial audit pass on 2026-02-15 that removed dead code and hardened SSH. However, Phase 10 (deploy pipeline) **reverted** key Phase 9 security changes (re-added port 22 to firewall, restored PermitRootLogin="prohibit-password", restored root authorized_keys) because `nixos-rebuild --target-host` requires root SSH. This is the single largest security regression to address.

The audit has two lenses: (1) **simplicity** -- every line must earn its place (YAGNI violations, over-engineering, dead code, premature generalization), and (2) **security** -- minimum-privilege for every service, secret, network rule, and container. Beyond fixing issues, this phase establishes guardrails in CLAUDE.md and hooks so agents maintain these standards.

**Primary recommendation:** Structure into 3 plans: (1) simplicity audit + fixes across all modules, (2) security audit + hardening across all modules/services/containers/sandbox, (3) guardrails -- CLAUDE.md conventions, assertions, and hooks for ongoing agentic development.

## Codebase Inventory

### Modules (14 files, ~530 lines)

| File | Lines | Concern | Simplicity Notes | Security Notes |
|------|-------|---------|-----------------|----------------|
| `flake.nix` | 54 | Entrypoint + inputs | Clean. 7 inputs, all with `follows`. | `llm-agents` does NOT follow nixpkgs -- brings own nixpkgs (supply chain concern) |
| `modules/default.nix` | 17 | Import hub | Clean. | N/A |
| `modules/base.nix` | 36 | Nix settings + packages | `zmx` built twice (here AND agent-compute.nix). | No kernel hardening. No sysctl hardening. |
| `modules/boot.nix` | 9 | GRUB config | Clean. | Clean. |
| `modules/networking.nix` | 97 | Firewall + SSH + Tailscale + fail2ban | Good assertion for internal ports. | Port 22 open (deploy pipeline). PermitRootLogin=prohibit-password. Root has authorized_keys. |
| `modules/users.nix` | 25 | Users + sudo | `parts-agent@vm` SSH key still present in both dangirsh and root -- is this still needed? | Root SSH keys present. |
| `modules/secrets.nix` | 24 | sops-nix declarations | Clean. 7 secrets + 1 template. | All secrets default to root:root except 3 with `owner = "dangirsh"`. Appropriate. |
| `modules/docker.nix` | 31 | Docker engine + NAT | Clean. | `filterForward = false` (default) means no inter-container isolation. |
| `modules/monitoring.nix` | 130 | Prometheus + node_exporter | Alert rules are verbose but correct. | Prometheus localhost-only. Clean. |
| `modules/home-assistant.nix` | 42 | HA + ESPHome | Clean. | Binds 0.0.0.0 -- relies on firewall for protection. |
| `modules/syncthing.nix` | 60 | Syncthing service | Clean. | GUI localhost-only. Clean. |
| `modules/agent-compute.nix` | 270 | Agent CLI + sandbox + Podman | Largest module. Complex but justified (bwrap sandbox). | Sandbox reviewed separately below. |
| `modules/restic.nix` | 42 | Backup to B2 | Clean. | Backup excludes `.git/objects` but includes `.git/` -- secrets in git history? |
| `modules/repos.nix` | 30 | Clone repos on activation | GitHub PAT used in clone URL. | Token in clone URL appears in process list and logs. |
| `modules/homepage.nix` | 89 | Dashboard | Hardcoded Tailscale IP. | Docker socket access (read-only but still sensitive). |

### Home Manager (7 files, ~70 lines)

| File | Lines | Concern | Notes |
|------|-------|---------|-------|
| `home/default.nix` | 15 | Import hub | Clean. |
| `home/bash.nix` | 11 | Shell init | Reads secrets at every shell start -- performance note but functionally correct. |
| `home/git.nix` | 13 | Git config | Clean. LFS enabled (is it needed?). |
| `home/ssh.nix` | 9 | SSH client | Clean. hashKnownHosts=true is good. |
| `home/direnv.nix` | 7 | Direnv | Clean. |
| `home/cass.nix` | 27 | CASS indexer | Timer runs every 30 min. Clean. |
| `home/agent-config.nix` | 9 | Agent symlinks | Both .claude and .codex point to same dir. Intentional? |

### Packages (2 files)

| File | Notes |
|------|-------|
| `packages/zmx.nix` | Pre-built binary from zmx.sh. No signature verification. |
| `packages/cass.nix` | Pre-built binary from GitHub releases. No signature verification. |

### Scripts (1 file, ~200 lines)

| File | Notes |
|------|-------|
| `scripts/deploy.sh` | Solid error handling, locking, rollback instructions. Lock file in /tmp. |

## Simplicity Findings

### Finding S1: zmx Package Built Twice
**What:** `packages/zmx.nix` is called in both `modules/base.nix` (line 3) and `modules/agent-compute.nix` (line 11).
**Impact:** No functional issue (Nix deduplicates), but it is confusing maintenance-wise.
**Fix:** Remove from `base.nix`, keep only in `agent-compute.nix` where it is actually used for the sandbox PATH. Add zmx to system packages only in agent-compute.nix.
**Confidence:** HIGH

### Finding S2: homepage.nix Hardcoded Tailscale IP
**What:** `modules/homepage.nix` has `100.127.245.9` hardcoded in multiple places (allowedHosts, HA href).
**Impact:** If the Tailscale IP changes, multiple places must be updated. Minor YAGNI concern -- is the dashboard actually used?
**Fix:** Consider extracting to a let binding at top of file. Or assess whether homepage-dashboard adds value -- agents do not use it, the user accesses services directly.
**Confidence:** MEDIUM -- depends on whether dashboard is actively used.

### Finding S3: Git LFS Enabled Without Usage
**What:** `home/git.nix` has `lfs.enable = true;` but there are no LFS-tracked files in this repo.
**Impact:** Installs git-lfs unnecessarily. Minor.
**Fix:** Remove unless other projects on the server use LFS.
**Confidence:** HIGH

### Finding S4: Monitoring Alert Rules Verbosity
**What:** `modules/monitoring.nix` is 130 lines, with 80+ lines being alert rule JSON. The rules are correct but large.
**Impact:** Makes the module hard to read at a glance. However, the rules are essential.
**Fix:** Consider extracting rules to a separate file `monitoring/alert-rules.nix` and importing. Or accept the verbosity as inherent to Prometheus config. This is a judgment call -- the current structure keeps everything in one file, which has its own simplicity.
**Confidence:** LOW -- this is a style preference, not a real problem.

### Finding S5: CASS Indexer Value Assessment
**What:** CASS (Coding Agent Session Search) runs as a timer indexing agent sessions every 30 minutes.
**Impact:** Is it actually being used? If not, it is dead weight (binary download + systemd timer).
**Fix:** Validate usage. If not used, remove `home/cass.nix` and `packages/cass.nix`.
**Confidence:** LOW -- needs user input on whether CASS is actively used.

### Finding S6: Podman Compose Installed But Likely Unused
**What:** `modules/agent-compute.nix` installs `pkgs.podman-compose` in systemPackages.
**Impact:** Is any agent using podman-compose inside the sandbox? The sandbox uses `docker` (via podman compat shim), not `podman-compose`.
**Fix:** Validate usage. Remove if unused.
**Confidence:** MEDIUM

### Finding S7: Deploy Script /tmp Usage
**What:** `scripts/deploy.sh` uses `LOCAL_LOCK="/tmp/neurosys-deploy.local.lock"` -- project convention says use `tmp/` in project root, not `/tmp/`.
**Impact:** Violates project convention from CLAUDE.md.
**Fix:** Change to `"$FLAKE_DIR/tmp/neurosys-deploy.local.lock"` and ensure `tmp/` is in `.gitignore` (it already is).
**Confidence:** HIGH

## Security Findings

### Finding SEC1: Deploy Pipeline Root SSH (CRITICAL)
**What:** Phase 9 hardened SSH to Tailscale-only + PermitRootLogin="no" + removed root keys. Phase 10 reverted because `nixos-rebuild --target-host root@acfs` needs root SSH on port 22.
**Current state:**
- Port 22 open in `allowedTCPPorts`
- `PermitRootLogin = "prohibit-password"` (key-only root login allowed)
- Root has authorized_keys for dan and parts-agent
**Impact:** Root SSH is accessible from the public internet. This is the largest attack surface.
**Options:**
1. **Restrict port 22 to Tailscale** (remove from allowedTCPPorts, keep SSH accessible via trustedInterfaces). Deploy via Tailscale hostname/IP. Requires Tailscale to be up for deploys.
2. **Use `--target-host dangirsh@acfs --use-remote-sudo`** instead of root SSH. This eliminates root SSH entirely but requires the remote `nixos-rebuild` binary to be present (it is).
3. **Accept the risk** with compensating controls (fail2ban, key-only auth, progressive banning).
**Recommendation:** Option 1 -- deploy over Tailscale. The deploy script already uses `root@acfs` which resolves via Tailscale. Port 22 can be removed from public firewall. If Tailscale is down, Contabo VNC provides emergency access. The deploy lockout that caused the Phase 10 revert was because the VPS had port 22 removed AND Tailscale was not connected after a fresh install -- a deployment-time issue, not an ongoing concern.
**Confidence:** HIGH

### Finding SEC2: No Kernel Hardening (MEDIUM)
**What:** No `boot.kernel.sysctl` hardening is configured.
**Impact:** Default kernel settings leave several attack surfaces:
- No hardlink/symlink protection (`fs.protected_hardlinks`, `fs.protected_symlinks` -- though these may be on by default in recent kernels)
- No dmesg restriction (`kernel.dmesg_restrict`)
- No pointer restriction (`kernel.kptr_restrict`)
- No BPF hardening (`kernel.unprivileged_bpf_disabled`)
- No ICMP redirect protection
**Fix:** Add standard sysctl hardening block:
```nix
boot.kernel.sysctl = {
  "kernel.dmesg_restrict" = 1;
  "kernel.kptr_restrict" = 2;
  "kernel.unprivileged_bpf_disabled" = 1;
  "net.core.bpf_jit_harden" = 2;
  "net.ipv4.conf.all.accept_redirects" = false;
  "net.ipv4.conf.default.accept_redirects" = false;
  "net.ipv4.conf.all.send_redirects" = false;
  "net.ipv4.conf.all.log_martians" = true;
  "net.ipv6.conf.all.accept_redirects" = false;
};
```
**Confidence:** HIGH -- these are standard Linux server hardening and well-documented for NixOS.

### Finding SEC3: Docker Container Hardening Missing (MEDIUM)
**What:** Docker containers (parts-tools, parts-agent, claw-swap-*) are declared in external flake modules (parts, claw-swap repos). Phase 9 research recommended hardening but it was deferred.
**Impact:** Containers may run without read-only rootfs, without capability dropping, without no-new-privileges, without resource limits.
**Fix:** This audit should verify the current state of container declarations in the parts and claw-swap modules. If hardening is missing, document what should be added. Note: changes to parts/claw-swap containers require changes in THOSE repos, not agent-neurosys.
**Recommendation:** For containers declared in agent-neurosys scope, apply hardening. For external repos, document findings and create follow-up issues.
**Confidence:** HIGH (that hardening is missing) -- Phase 9 explicitly deferred this.

### Finding SEC4: Repos Clone Leaks Token (LOW-MEDIUM)
**What:** `modules/repos.nix` clones repos via `https://$GH_TOKEN@github.com/...`. The token appears in:
- Process arguments (visible in `/proc`)
- Systemd journal logs
- The `.git/config` remote URL of cloned repos
**Impact:** Any user who can read journal logs or `/proc` can see the GitHub PAT. The PAT has repo access.
**Fix:**
1. Use `git clone` with token via `GIT_ASKPASS` or `git -c credential.helper=...` instead of URL embedding
2. Or use `git clone` without auth (repos are presumably public on GitHub) and inject auth later for push
3. At minimum, suppress echo: use `set +x` and avoid logging the URL
**Confidence:** HIGH -- this is a well-known credential leak pattern.

### Finding SEC5: Sandbox Escape Vector -- .claude Directory Writable (MEDIUM)
**What:** The agent sandbox (`agent-compute.nix` line 157) mounts `~/.claude` as read-only (`--ro-bind-try`). However, per the Claude Code GHSA-ff64-7w26-62rf advisory, if `settings.json` does not exist at startup, a compromised agent could create it to inject persistent hooks.
**Current mitigation:** The sandbox mounts `.claude` as read-only, so the file cannot be created inside the sandbox. This is correct.
**Remaining concern:** The `--no-sandbox` mode has no such protection. An agent running with `--no-sandbox` can modify `~/.claude/settings.json` freely.
**Recommendation:** Document that `--no-sandbox` should only be used for trusted operations. Consider adding a pre-flight check that validates `.claude/settings.json` integrity before unsandboxed agent launch.
**Confidence:** HIGH -- based on published CVE (GHSA-ff64-7w26-62rf).

### Finding SEC6: Homepage Dashboard Docker Socket Access (LOW)
**What:** `modules/homepage.nix` mounts the Docker socket: `docker.local.socket = "/var/run/docker.sock"`. This gives the homepage-dashboard service full read access to Docker (and potentially write if the socket permissions allow).
**Impact:** The homepage service is Tailscale-only, so external exploitation is unlikely. But Docker socket access is a common privilege escalation vector.
**Fix:** Evaluate whether container status on the dashboard is worth the Docker socket exposure. If needed, consider a read-only Docker socket proxy (but that adds complexity). Alternatively, remove Docker integration from the dashboard -- the container status is easily checked via CLI.
**Confidence:** MEDIUM -- low practical risk given Tailscale-only access, but violates least-privilege.

### Finding SEC7: Restic Backup Includes Potentially Sensitive Paths (LOW)
**What:** `modules/restic.nix` backs up `/data/projects/`, `/home/dangirsh/`, `/var/lib/hass/`. The exclude list skips `.git/objects` but NOT `.git/config` (which may contain tokens from the repos.nix clone).
**Impact:** If repos were cloned with a PAT in the URL, `.git/config` contains the token, and restic backs it up to B2.
**Fix:** Either fix the clone mechanism (SEC4) so tokens are not in `.git/config`, or add `.git/config` to exclude list (but this breaks backup completeness for repos).
**Confidence:** HIGH -- direct consequence of SEC4.

### Finding SEC8: parts-agent@vm SSH Key Purpose (LOW)
**What:** `modules/users.nix` has an SSH key labeled `parts-agent@vm` in both dangirsh and root authorized_keys. This appears to be from the old VM-based parts setup.
**Impact:** If the VM no longer exists, this is a stale credential providing unnecessary SSH access.
**Fix:** Verify if parts-agent@vm is still active. If not, remove the key.
**Confidence:** MEDIUM -- depends on whether this key is still in use.

### Finding SEC9: No Systemd Service Hardening (MEDIUM)
**What:** None of the NixOS services (Prometheus, node_exporter, homepage-dashboard, Syncthing, Home Assistant, ESPHome) have explicit systemd hardening options. Services run with default systemd security (no ProtectHome, no PrivateTmp, no NoNewPrivileges).
**Impact:** A compromised service has broader system access than necessary.
**Fix:** Run `systemd-analyze security <service>` for each service on the live system. Apply relevant hardening from NixOS service config overrides. Focus on services that face the network (HA, ESPHome, Syncthing GUI).
**Recommendation:** Most of these services have hardening options already built into their NixOS modules. Verify what the defaults provide before adding custom overrides. Do not over-harden -- breaking services in the name of security creates operational risk.
**Confidence:** MEDIUM -- some NixOS service modules apply hardening by default. Need to verify on the live system.

### Finding SEC10: Supply Chain -- llm-agents Input Does Not Follow nixpkgs (LOW-MEDIUM)
**What:** The `llm-agents` flake input does not have `inputs.nixpkgs.follows = "nixpkgs"`. The flake.lock shows llm-agents brings its own nixpkgs (`nixpkgs-unstable`, node `nixpkgs` in lock) which is a DIFFERENT nixpkgs than the root (`nixos-25.11`, node `nixpkgs_2`).
**Impact:** Two different nixpkgs are evaluated. The llm-agents nixpkgs may have different security patches than the root nixpkgs. Also increases closure size and evaluation time.
**Fix:** Add `inputs.nixpkgs.follows = "nixpkgs"` to the llm-agents input in flake.nix. This forces llm-agents to use the same nixpkgs as the rest of the system.
**Note:** This may break if llm-agents depends on packages/features only in nixpkgs-unstable. Test with `nix flake check` after the change.
**Confidence:** HIGH -- verified by examining flake.lock nodes.

### Finding SEC11: Pre-Built Binaries Without Signature Verification (LOW)
**What:** `packages/zmx.nix` fetches from `zmx.sh` and `packages/cass.nix` fetches from GitHub releases. Both use SHA256 hash verification (which prevents tampering after the hash is computed) but there is no GPG/sigstore signature verification.
**Impact:** If the upstream binaries are compromised BEFORE the hash is initially set, the hash would be wrong but you would compute the "correct" (compromised) hash. For ongoing updates, hash changes would be noticed.
**Fix:** This is an inherent limitation of pre-built binary distribution without signature infrastructure. The SHA256 hash provides integrity (same binary every time) but not provenance (was the binary built from claimed source?). Accept the risk or switch to building from source.
**Recommendation:** Accept for now. Both projects are small, the binaries are from known maintainers, and the hash verification prevents supply chain attacks after initial trust establishment. Document the risk.
**Confidence:** HIGH

## Sandbox Security Assessment

The bubblewrap sandbox in `agent-compute.nix` is well-constructed. Specific assessment:

### Good
- `--new-session` prevents TIOCSTI terminal escape
- `--disable-userns` prevents nested user namespace escape
- `--clearenv` + explicit `--setenv` prevents env leaking
- `--die-with-parent` prevents orphaned sandbox processes
- `/run/secrets` is NOT mounted -- secrets are invisible to sandboxed agents
- `~/.ssh` is NOT mounted -- SSH keys are invisible
- `/data/projects` is mounted read-only with only the target project writable
- API keys are read before sandbox entry and injected via env vars (not files)
- Docker socket is NOT accessible inside the sandbox

### Potential Concerns
- **Audit log** (`/data/projects/.agent-audit/spawn.log`) is writable by all agents (pre-created tmpfiles rule). A compromised agent could tamper with audit logs. Consider making the audit log append-only or owned by root.
- **`/etc/passwd` and `/etc/group`** are mounted read-only. These reveal system users but are standard and needed for uid/gid resolution.
- **`/etc/nix`** is mounted read-only. This reveals nix configuration but is needed for nix operations.
- **Network is NOT sandboxed** (`--unshare-net` is NOT used). Agents have full network access. The metadata endpoint (169.254.169.254) is blocked at the nftables level. This is a design choice -- agents need network for API calls, git, and package management.
- **`--ro-bind /data/projects /data/projects`** then **`--bind "$PROJECT_DIR" "$PROJECT_DIR"`** is correct (overlay write on top of read-only parent). But a compromised agent in project A can READ files in project B (all of `/data/projects` is readable). This is documented in the sandbox policy.

### Recommendation
The sandbox is solid for its threat model (prevent prompt-injected agents from exfiltrating secrets or modifying other projects). The main limitation -- cross-project read access -- is a deliberate tradeoff for agents that need to reference sibling repos.

## Supply Chain Assessment

### Flake Inputs (7 direct)

| Input | Follows nixpkgs? | Pinned? | Branch | Notes |
|-------|-------------------|---------|--------|-------|
| nixpkgs | N/A (root) | Yes (lock) | `nixos-25.11` | Stable release. Good. |
| home-manager | Yes (`follows`) | Yes (lock) | `release-25.11` | Matches nixpkgs. Good. |
| sops-nix | Yes (`follows`) | Yes (lock) | `main` | Follows nixpkgs. Good. |
| disko | Yes (`follows`) | Yes (lock) | `main` | Follows nixpkgs. Good. |
| parts | Yes (`follows` both) | Yes (lock) | `main` | User's own repo. Follows nixpkgs and sops-nix. Good. |
| claw-swap | Yes (`follows` both) | Yes (lock) | `main` | User's own repo. Follows nixpkgs and sops-nix. Good. |
| llm-agents | **NO** | Yes (lock) | `main` | **Brings own nixpkgs-unstable.** See SEC10. |

### Transitive Inputs (via llm-agents)
- `blueprint` (numtide)
- `treefmt-nix` (numtide)
- `nixpkgs` (unstable -- the extra nixpkgs)

### Transitive Inputs (via parts)
- `clawvault` (Versatly) -- pinned to `v2.4.6` ref. Good.
- `qmd` (tobi) -- brings yet another nixpkgs-unstable. This is via parts, which follows root nixpkgs, but qmd has its own nixpkgs.

### Assessment
- **Good:** All direct inputs are pinned in flake.lock. Most use `follows` to deduplicate nixpkgs.
- **Issue:** 3 distinct nixpkgs evaluations in the closure (nixos-25.11, llm-agents' unstable, qmd's unstable). This increases evaluation time and may introduce version conflicts.
- **Recommendation:** Add `follows` for llm-agents nixpkgs. For qmd (via parts), this would need a change in the parts repo.

## Architecture Patterns

### Audit Execution Pattern

For a thorough line-by-line audit, process modules in dependency order:

1. **Foundation:** `flake.nix` -> `hosts/acfs/` -> `modules/boot.nix` -> `modules/base.nix`
2. **Identity:** `modules/users.nix` -> `modules/secrets.nix`
3. **Network:** `modules/networking.nix` -> `modules/docker.nix`
4. **Services:** `modules/monitoring.nix` -> `modules/syncthing.nix` -> `modules/home-assistant.nix` -> `modules/homepage.nix`
5. **Agent infra:** `modules/agent-compute.nix` -> `modules/repos.nix`
6. **Backup:** `modules/restic.nix`
7. **Home:** `home/*.nix`
8. **Deploy:** `scripts/deploy.sh`
9. **Supply chain:** `flake.lock` + `.sops.yaml`

### Fix-Then-Verify Pattern

For each finding:
1. Implement the fix
2. Run `nix flake check` (catches syntax and evaluation errors)
3. For security changes, describe what to verify on the live server
4. Commit atomically per logical change

### Guardrail Pattern

For CLAUDE.md conventions:
1. **Security assertions** -- NixOS `assertions` blocks that prevent insecure configurations at build time (already done for internal ports in networking.nix -- extend this pattern)
2. **CLAUDE.md rules** -- Explicit "never" rules for agents (never expose internal services publicly, never commit unencrypted secrets, never weaken sandbox defaults)
3. **Review checklist** -- Section in CLAUDE.md for security review on any module change

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Port exposure assertions | Custom scripts | NixOS `assertions` in modules | Build-time enforcement, cannot be bypassed |
| Kernel hardening | Individual sysctl calls | `boot.kernel.sysctl` attrset | Declarative, survives reboots, version-controlled |
| Service hardening | Custom systemd units | `systemd.services.<name>.serviceConfig` overrides | NixOS handles systemd config generation |
| Secret rotation | Custom scripts | sops-nix `restartUnits` + deployment | Declarative restart triggers on secret change |
| Container security | Wrapper scripts | `extraOptions` in oci-containers | Managed by NixOS module, consistent |

## Common Pitfalls

### Pitfall 1: Breaking Deploy Pipeline With Security Changes
**What goes wrong:** Removing port 22 or root SSH breaks `nixos-rebuild --target-host root@acfs`.
**Why it happens:** Phase 9 did this, Phase 10 had to revert after a VPS lockout.
**How to avoid:** Test deploy script BEFORE committing firewall changes. Use Tailscale for deploy (deploy script already uses `acfs` hostname which resolves via Tailscale). Verify Tailscale is connected first.
**Warning signs:** `ssh root@acfs` fails after firewall change = lockout risk.

### Pitfall 2: Over-Hardening Services
**What goes wrong:** Enabling ProtectHome=true on a service that needs /home causes silent failures.
**Why it happens:** Systemd hardening is restrictive by design. Services may need paths you do not expect.
**How to avoid:** Test each hardening change individually. Start with `systemd-analyze security` to see current score, then enable options one at a time. Some NixOS service modules already apply hardening -- check before adding custom overrides.
**Warning signs:** Service starts but fails to function (e.g., Syncthing cannot access /home/dangirsh).

### Pitfall 3: llm-agents Nixpkgs Follow Breaking Builds
**What goes wrong:** Adding `inputs.nixpkgs.follows = "nixpkgs"` to llm-agents causes evaluation errors because llm-agents packages depend on nixpkgs-unstable features not in nixos-25.11.
**Why it happens:** llm-agents is developed against unstable. Claude-code and codex packages may use newer package versions.
**How to avoid:** Test with `nix flake check` after adding follows. If it breaks, revert the follows and accept the separate nixpkgs evaluation.
**Warning signs:** `nix flake check` errors mentioning undefined attributes or missing packages.

### Pitfall 4: Editing sops-encrypted Files Without Correct Keys
**What goes wrong:** Trying to edit `secrets/acfs.yaml` fails because the local machine does not have the admin age key or the host age key.
**Why it happens:** sops requires at least one of the keys listed in `.sops.yaml` creation_rules.
**How to avoid:** Ensure the admin age key (age1vma7...) private key is available on the machine performing the edit. Use `SOPS_AGE_KEY_FILE` environment variable.
**Warning signs:** `sops secrets/acfs.yaml` errors with "could not decrypt data key".

## Code Examples

### Kernel Sysctl Hardening (to add to base.nix or new security.nix)

```nix
# Standard Linux server hardening via sysctl
boot.kernel.sysctl = {
  # Restrict dmesg to root
  "kernel.dmesg_restrict" = 1;
  # Hide kernel pointers from non-root
  "kernel.kptr_restrict" = 2;
  # Disable unprivileged eBPF
  "kernel.unprivileged_bpf_disabled" = 1;
  # Harden eBPF JIT compiler
  "net.core.bpf_jit_harden" = 2;
  # Disable ICMP redirects (prevent MITM)
  "net.ipv4.conf.all.accept_redirects" = false;
  "net.ipv4.conf.default.accept_redirects" = false;
  "net.ipv4.conf.all.send_redirects" = false;
  "net.ipv6.conf.all.accept_redirects" = false;
  "net.ipv6.conf.default.accept_redirects" = false;
  # Log martian packets
  "net.ipv4.conf.all.log_martians" = true;
};
```

Source: [Ryan Seipp: Hardening NixOS](https://ryanseipp.com/posts/hardening-nixos/), NixOS Wiki Security, Lynis recommendations (NixOS/nixpkgs#63768)

### Deploy Script Tailscale-Only SSH Fix

```bash
# In scripts/deploy.sh, the default TARGET is already "root@acfs"
# which resolves via Tailscale (MagicDNS).
# The fix is in networking.nix -- remove port 22 from public firewall.
# Deploy script needs NO changes if acfs resolves via Tailscale.
```

### NixOS Assertion Pattern for Security Guardrails

```nix
# Extend the existing assertion pattern in networking.nix
assertions = [
  {
    assertion = !config.services.openssh.settings.PermitRootLogin
      || config.services.openssh.settings.PermitRootLogin == "no"
      || config.services.openssh.settings.PermitRootLogin == "prohibit-password";
    message = "SECURITY: PermitRootLogin must be 'no' or 'prohibit-password', never 'yes'.";
  }
];
```

### CLAUDE.md Security Conventions (to add)

```markdown
## Security Conventions

- **Never** add ports to `networking.firewall.allowedTCPPorts` without documenting why
  in a @decision annotation (the internalOnlyPorts assertion catches known services,
  but new services must be considered)
- **Never** commit unencrypted secrets to any file. Use sops-nix for all credentials.
- **Never** weaken the bubblewrap sandbox defaults (--no-sandbox is for trusted ops only)
- **Never** mount the Docker socket into a service unless strictly required
- **Never** embed credentials in URLs or command-line arguments (use env vars or files)
- All network-facing services must have openFirewall=false unless explicitly justified
- All new modules must include @decision annotations for security-relevant choices
- Prefer Tailscale-only access for all internal services (trustedInterfaces pattern)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Phase 9 SSH hardening (PermitRootLogin="no") | Reverted to prohibit-password for deploy | Phase 10 (2026-02-17) | Root SSH on public internet |
| No container hardening | Deferred since Phase 9 | Ongoing | Containers run with default privileges |
| No kernel hardening | Standard practice since 2020+ | N/A | Missing standard server hardening |
| No systemd service hardening | NixOS Pre-RFC tracking (nixpkgs#377827) | Ongoing | Services run with default systemd permissions |

## CLAUDE.md Guardrail Recommendations

### Section 1: Security Rules for Agents

Add to CLAUDE.md under a new `## Security` section:
- Checklist for any module change that touches networking, firewall, services, or secrets
- Explicit prohibitions (never expose internal ports, never weaken sandbox, never embed credentials)
- Assertion pattern: any new service MUST add its port to `internalOnlyPorts` in networking.nix if it should not be public

### Section 2: Simplicity Rules for Agents

Add to CLAUDE.md under a new `## Simplicity` section:
- Every new module must justify its existence (avoid premature abstraction)
- Prefer inline over separate files for <20 lines
- No dead code -- unused options/packages must be removed
- YAGNI: do not add features "for later" unless they are in an active phase plan

### Section 3: Module Change Checklist

A checklist agents must follow before committing module changes:
1. Does this change expose a new port? If yes, add to internalOnlyPorts assertion or justify public exposure
2. Does this change add a new secret? If yes, verify owner/permissions are minimal
3. Does this change add a new service? If yes, set openFirewall=false and add @decision annotation
4. Does this change modify the sandbox? If yes, verify secrets remain hidden
5. Does `nix flake check` pass?

## Open Questions

1. **Is the homepage dashboard actively used?**
   - What we know: It is deployed and accessible via Tailscale
   - What is unclear: Whether anyone looks at it. Agents do not use it.
   - Recommendation: Ask user. If not used, remove to reduce attack surface (Docker socket access).

2. **Is CASS actively used?**
   - What we know: Timer runs every 30 minutes, binary is installed
   - What is unclear: Whether anyone queries CASS output
   - Recommendation: Ask user. If not used, remove.

3. **Is parts-agent@vm SSH key still active?**
   - What we know: Key is in both dangirsh and root authorized_keys
   - What is unclear: Whether the VM still exists
   - Recommendation: Ask user. If VM no longer exists, remove key.

4. **Should deploy use `dangirsh@acfs --use-remote-sudo` instead of `root@acfs`?**
   - What we know: `nixos-rebuild --target-host user@host --use-remote-sudo` is supported
   - What is unclear: Whether this works reliably with the current sudo config (wheelNeedsPassword=false)
   - Recommendation: Test on the live system. If it works, eliminates need for root SSH entirely.

5. **Can llm-agents follow root nixpkgs?**
   - What we know: llm-agents currently brings nixpkgs-unstable
   - What is unclear: Whether claude-code/codex packages build against nixos-25.11
   - Recommendation: Test with `nix flake check` after adding follows.

## Sources

### Primary (HIGH confidence)
- All 14 modules + 7 home files + 2 packages + 1 script read directly from `/data/projects/agent-neurosys/`
- `flake.lock` analyzed for supply chain (7 direct inputs, transitive dependencies)
- Phase 9 research and summaries (09-RESEARCH.md, 09-01-SUMMARY.md)
- Phase 10 summary (10-02-SUMMARY.md) documenting SSH revert
- Phase 11 research and summaries (sandbox design)
- [Claude Code GHSA-ff64-7w26-62rf](https://github.com/anthropics/claude-code/security/advisories/GHSA-ff64-7w26-62rf) -- sandbox escape via settings.json
- [bubblewrap GitHub](https://github.com/containers/bubblewrap) -- sandbox security model

### Secondary (MEDIUM confidence)
- [Ryan Seipp: Hardening NixOS](https://ryanseipp.com/posts/hardening-nixos/) -- kernel sysctl options
- [NixOS Wiki: Security](https://wiki.nixos.org/wiki/Security) -- security overview
- [NixOS Wiki: Systemd/Hardening](https://wiki.nixos.org/wiki/Systemd/Hardening) -- service hardening
- [Determinate Systems: Flake Checker](https://determinate.systems/blog/flake-checker/) -- supply chain best practices
- [NixOS/nixpkgs#63768](https://github.com/NixOS/nixpkgs/issues/63768) -- Lynis hardening recommendations
- [NixOS/nixpkgs#377827](https://github.com/NixOS/nixpkgs/issues/377827) -- systemd hardening tracking
- [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config) -- CLAUDE.md security guardrails
- [Docker Security Cheat Sheet (OWASP)](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html) -- container hardening
- [NixOS/nixpkgs#111852](https://github.com/NixOS/nixpkgs/issues/111852) -- Docker bypasses NixOS firewall

### Tertiary (LOW confidence)
- [nix-mineral](https://github.com/cynicsketch/nix-mineral) -- comprehensive NixOS hardening module (not directly used, referenced for completeness)

## Metadata

**Confidence breakdown:**
- Codebase simplicity: HIGH -- all files read line-by-line, findings verified against code
- Security (SSH/firewall): HIGH -- verified against Phase 9/10 history, NixOS docs
- Security (kernel hardening): HIGH -- standard Linux hardening, well-documented
- Security (containers): MEDIUM -- container declarations are in external repos, not fully visible
- Security (sandbox): HIGH -- bwrap config reviewed against known CVEs
- Supply chain: HIGH -- flake.lock analyzed directly
- Guardrails: MEDIUM -- CLAUDE.md conventions are recommendations, effectiveness depends on implementation

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (stable domain, NixOS options do not change frequently)
