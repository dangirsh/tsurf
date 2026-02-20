# Phase 19: Generate Comprehensive Project README - Research

**Researched:** 2026-02-20
**Domain:** Documentation generation from NixOS infrastructure codebase
**Confidence:** HIGH

## Summary

This phase generates a README.md for the neurosys repository -- a NixOS flake-based server configuration managing a Contabo VPS with AI agent infrastructure, Docker services, monitoring, backups, and home automation. The README must synthesize information currently spread across 13 NixOS modules, 6 home-manager modules, 2 custom packages, 1 deploy script, 1 recovery runbook, and extensive planning docs into a single skimmable reference.

No new code is written. The task is purely documentation: extract facts from the implementation, organize them into the structure defined by the success criteria, and verify accuracy against the actual Nix expressions. The primary risk is inaccuracy -- stating something the code doesn't actually do, or omitting something it does.

**Primary recommendation:** Write README.md as a single-plan task. Structure it with headers matching the success criteria sections. Pull all facts directly from module source code (not planning docs, which may be stale). Verify every claim against the actual `.nix` files.

## Standard Stack

Not applicable -- this is a documentation-only phase. No libraries, frameworks, or tools are needed beyond a text editor.

## Architecture Patterns

### README Structure (Recommended)

Based on the success criteria and the nature of this project, the README should follow this structure:

```
README.md
  1. Project Overview (what, why, who)
  2. Architecture Summary (flake inputs, module organization)
  3. Hardware / Infrastructure (Contabo VPS specs, static IP, disk layout)
  4. Modules & Services table (all 13 modules + what each does)
  5. Home-Manager Modules table (all 6 home modules)
  6. Security Model (firewall, SSH, Tailscale, sops-nix, sandbox, kernel hardening)
  7. Deployment Quick-Start (prerequisites, deploy command, verification)
  8. Operations
     a. Deploy (scripts/deploy.sh modes + flags)
     b. Backup & Restore (restic to B2, retention, restore commands)
     c. Monitoring (Prometheus, alert rules, querying)
     d. Secrets Management (sops-nix workflow, adding secrets)
     e. Agent Compute (agent-spawn, sandbox, zmx sessions)
  9. Design Decisions table
  10. Accepted Risks table
  11. Project Structure (file tree)
```

### Pattern: Facts from Code, Not Plans

**What:** Every claim in the README must be verifiable against the `.nix` source files. Planning documents (ROADMAP.md, STATE.md, PROJECT.md) contain stale or aspirational information (e.g., PROJECT.md still references "acfs" hostname, lists Ollama and Zsh which were dropped).

**When to use:** Always. This is the single most important pattern for this phase.

**Anti-pattern:** Copying content from `.planning/` docs without cross-checking against actual module source.

### Pattern: Skimmable Format

**What:** Headers, bullet lists, and tables over prose paragraphs. The success criteria explicitly require "skimmable -- bullets, tables, and headers over prose paragraphs."

**Guidelines:**
- Tables for enumerations (modules, services, decisions, risks, ports)
- Bullet lists for features, prerequisites, steps
- Code blocks for concrete commands
- Prose limited to 1-2 sentence introductions per section
- No "wall of text" paragraphs

## Content Inventory

This section catalogs every fact the README must cover, organized by source module. This is the planner's primary reference for building the task checklist.

### From flake.nix

| Fact | Value |
|------|-------|
| Flake inputs | 7: nixpkgs (25.11), home-manager (25.11), sops-nix, disko, parts, claw-swap, llm-agents |
| System architecture | x86_64-linux |
| NixOS configuration name | `neurosys` |
| Overlays | llm-agents.overlays.default (provides claude-code, codex) |
| External NixOS modules | disko, sops-nix, home-manager, parts, claw-swap |

### From hosts/neurosys/

| Fact | Source File |
|------|------------|
| Hostname: `neurosys` | default.nix |
| Timezone: Europe/Berlin | default.nix |
| Locale: C.UTF-8 | default.nix |
| Static IP: 161.97.74.121/18 | default.nix |
| Gateway: 161.97.64.1 | default.nix |
| DNS: 213.136.95.10, 213.136.95.11 | default.nix |
| stateVersion: 25.11 | default.nix |
| QEMU guest profile | hardware.nix |
| Virtio kernel modules | hardware.nix |
| Disk: GPT, BIOS boot + EFI + ext4 root | disko-config.nix |
| GRUB bootloader, EFI + BIOS hybrid | boot.nix (via modules) |

### From modules/ (13 modules)

| Module | Key Facts for README |
|--------|---------------------|
| **base.nix** | Flakes enabled, auto-optimize store, weekly GC (30d), kernel sysctl hardening (dmesg, kptr, bpf, redirects, martians), system packages (git, curl, wget, rsync, jq, yq, rg, fd, btop, nodejs), ssh-agent, allowUnfree for claude-code |
| **boot.nix** | GRUB, EFI support, efiInstallAsRemovable, /dev/sda, 10 config limit |
| **networking.nix** | nftables firewall, public ports 80/443/22000 only, SSH Tailscale-only (port 22 assertion), trustedInterfaces=tailscale0, fail2ban (progressive banning, 5 retries, max 1 week), Tailscale VPN, metadata endpoint blocked (169.254.169.254), mosh enabled, internalOnlyPorts build-time assertion |
| **users.nix** | dangirsh (wheel, docker, subuid/subgid for rootless containers), mutableUsers=false, root SSH key for deploy, passwordless sudo for wheel, execWheelOnly |
| **secrets.nix** | 7 secrets (tailscale-authkey, b2-account-id, b2-account-key, restic-password, anthropic-api-key, openai-api-key, github-pat) + 1 template (restic-b2-env), age key from SSH host key |
| **docker.nix** | Docker with --iptables=false, journald log driver, NAT for 172.16.0.0/12 via eth0, docker0 trusted |
| **monitoring.nix** | Prometheus (localhost:9090, 15s scrape, 90d retention), node_exporter (9100, systemd/processes/tcpstat/textfile collectors), 7 alert rules (InstanceDown, DiskSpaceCritical/Warning, HighMemory, HighCPU, SystemdUnitFailed, BackupStale) |
| **home-assistant.nix** | Native NixOS service (not Docker), port 8123 Tailscale-only, ESPHome on 6052, Hue + ESPHome extraComponents |
| **syncthing.nix** | User dangirsh, localhost GUI (8384), declarative devices (MacBook, Pixel), 1 folder (Sync), staggered versioning (90d), openDefaultPorts for sync (22000) |
| **agent-compute.nix** | claude-code + codex CLI (llm-agents overlay), zmx (pre-built binary), agent-spawn script (bubblewrap sandbox by default, --no-sandbox opt-out), Podman rootless (dockerCompat=false, sandbox-local docker->podman symlink), numtide binary cache, agent.slice cgroup (CPU, tasks), audit logging (spawn.log + journald), user linger for dangirsh |
| **repos.nix** | Activation-time clone of 3 repos (parts, claw-swap, global-agent-conf) to /data/projects/, credential-helper based (no PAT in URLs), clone-only (never pull) |
| **restic.nix** | Blanket "/" backup with --one-file-system, S3-compatible B2 backend, daily timer (randomized 1h delay), 7 daily / 5 weekly / 12 monthly retention, pg_dumpall pre-hook, textfile collector post-hook for Prometheus, exclusions (nix, docker overlay, cache, prometheus, git objects/config, node_modules, etc.), .nobackup sentinel support |
| **homepage.nix** | Dashboard on port 8082, Tailscale-only, Docker socket mounted (SEC6 accepted risk), shows Infrastructure (Prometheus, Syncthing, Restic B2 with last-backup widget), Applications (claw-swap, parts-tools, parts-agent), Home (Home Assistant) |

### From home/ (6 modules)

| Module | Key Facts |
|--------|-----------|
| **default.nix** | User dangirsh, stateVersion 25.11, imports 6 modules |
| **bash.nix** | Bash shell, API keys exported from sops secrets at shell start |
| **git.nix** | Git (Dan Girshovich), gh CLI (auth via GH_TOKEN env var) |
| **ssh.nix** | SSH client: ControlMaster auto, ControlPersist 10m, hashKnownHosts |
| **direnv.nix** | direnv + nix-direnv for automatic devShell loading |
| **cass.nix** | CASS v0.1.64 binary, systemd user timer every 30 min |
| **agent-config.nix** | ~/.claude and ~/.codex symlinked to /data/projects/global-agent-conf |

### From packages/ (2 packages)

| Package | Version | Description |
|---------|---------|-------------|
| zmx | 0.3.0 | Terminal session persistence (pre-built binary, SHA256 verified) |
| cass | 0.1.64 | Agent session indexer (pre-built binary, SHA256 + autoPatchelf) |

### From scripts/

| Script | Purpose |
|--------|---------|
| deploy.sh | Two-mode deploy (local build + remote switch, or remote rebuild). Flags: --mode, --target, --skip-update. Two-level locking (local flock + remote mkdir). Container health polling. Rollback instructions on failure. |

### From docs/

| Document | Purpose |
|----------|---------|
| recovery-runbook.md | 4-phase disaster recovery (deploy NixOS, restore from B2, re-auth, verify). RTO < 2hr, RPO 24hr. |

### From .sops.yaml

| Fact | Value |
|------|-------|
| Admin age key | age1vma7w9nqlg9da8z60a99g8wv53ufakfmzxpkdnnzw39y34grug7qklz3xz |
| Host age key | age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3 |
| Encrypted secrets file | secrets/neurosys.yaml |

### Design Decisions (for table)

Collected from @decision annotations across all modules:

| ID | Decision | Module |
|----|----------|--------|
| NET-01 | SSH via Tailscale only (port 22 not on public firewall) | networking.nix |
| NET-02 | Default-deny nftables firewall | networking.nix |
| NET-04 | Public ports: 80, 443, 22000 only | networking.nix |
| NET-05 | fail2ban with progressive banning | networking.nix |
| NET-07 | Build-time assertion prevents internal port exposure | networking.nix |
| DOCK-01 | Docker --iptables=false, NixOS owns firewall | docker.nix |
| DOCK-02 | NAT via internalIPs (not interfaces) for all Docker networks | docker.nix |
| SYS-01 | mutableUsers=false, execWheelOnly=true | users.nix |
| MON-05 | Prometheus-only (Alertmanager, ntfy, Grafana removed) | monitoring.nix |
| MON-06 | Prometheus localhost-only, agents query API | monitoring.nix |
| MON-07 | Textfile collector for restic backup staleness | monitoring.nix |
| HA-01 | Home Assistant as native NixOS service, not Docker | home-assistant.nix |
| HA-02 | HA GUI Tailscale-only via trustedInterfaces | home-assistant.nix |
| HP-01 | homepage-dashboard Tailscale-only | homepage.nix |
| SVC-02 | Syncthing fully declarative devices/folders | syncthing.nix |
| SANDBOX-11-01 | bubblewrap sandbox by default for agents | agent-compute.nix |
| RESTIC-01 | S3-compatible B2 backend (not native B2) | restic.nix |
| RESTIC-02 | Retention: 7 daily, 5 weekly, 12 monthly | restic.nix |
| RESTIC-05 | Blanket "/" backup with exclusions (not path list) | restic.nix |
| AGENT-01/02 | Clone-only repos, agent config symlinks | repos.nix, agent-config.nix |
| SEC-17-01 | Kernel sysctl hardening | base.nix |

### Accepted Risks (for table)

From CLAUDE.md and module annotations:

| ID | Risk | Mitigation |
|----|------|------------|
| SEC3 | Docker containers (parts) lack read-only rootfs, cap-drop | Containers declared in external repos; changes needed there |
| SEC5 | --no-sandbox agents can modify ~/.claude/settings.json | Default sandbox-on; --no-sandbox requires explicit flag |
| SEC6 | Docker socket mounted in homepage-dashboard | Tailscale-only access (port 8082 in internalOnlyPorts) |
| SEC9 | Systemd service hardening deferred (ProtectHome, PrivateTmp) | NixOS provides baseline defaults; custom overrides risk breaks |
| SEC11 | Pre-built binaries (zmx, cass) lack signature verification | SHA256 hash pinning |
| - | Cross-project read access in sandbox | Deliberate for sibling repo reference |
| - | No network sandboxing for agents | Agents need API/git access; metadata endpoint blocked |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File tree diagram | Manual ASCII art | `tree` command or copy from CLAUDE.md | Already maintained in CLAUDE.md project structure |
| Service port table | Manually enumerate from each module | Extract from `internalOnlyPorts` + `allowedTCPPorts` in networking.nix | Single source of truth for port assignments |
| Decision annotations | Manually list from memory | `grep -r '@decision' modules/ home/ packages/` | Ensures completeness, catches any missed annotations |

## Common Pitfalls

### Pitfall 1: Stale Information from Planning Docs

**What goes wrong:** README states capabilities from ROADMAP.md or PROJECT.md that were later dropped or changed (e.g., PROJECT.md still references Ollama, Zsh, rustup, Atuin -- all dropped in Phase 9).

**Why it happens:** Planning docs represent intent at planning time, not current implementation state.

**How to avoid:** For every claim in the README, verify against the actual `.nix` source file. If the module doesn't declare it, it's not real.

**Warning signs:** Any mention of: Ollama, Zsh, Atuin, rustup, Bun, pnpm, Go, Python, Neovim, Grafana, ntfy, Alertmanager -- all were either dropped or removed. If these appear in the README, something is wrong.

### Pitfall 2: Wrong Port Numbers or Service Endpoints

**What goes wrong:** README lists wrong ports or access methods.

**How to avoid:** Extract all ports from the actual module configs. Key port facts:
- 80, 443, 22000: public firewall
- 22: Tailscale-only (not in allowedTCPPorts, assertion enforces)
- 8082: homepage (Tailscale-only)
- 8123: Home Assistant (Tailscale-only)
- 6052: ESPHome (Tailscale-only)
- 8384: Syncthing GUI (localhost-only)
- 9090: Prometheus (localhost-only)
- 9100: node_exporter (Tailscale-only via trustedInterfaces)

### Pitfall 3: Deploy Quick-Start Missing Prerequisites

**What goes wrong:** First-time deployer cannot follow instructions because prerequisites are assumed (Nix installed, admin age key available, SSH access to VPS).

**How to avoid:** List all prerequisites explicitly. Cross-reference with recovery-runbook.md section 2 which has a thorough prerequisite list.

### Pitfall 4: Inconsistency Between README and CLAUDE.md

**What goes wrong:** README and CLAUDE.md describe the same things differently (different file tree, different module descriptions).

**How to avoid:** README should complement CLAUDE.md, not duplicate it. README is for external/operator audience ("what does this system do and how do I use it"). CLAUDE.md is for AI agents working on the codebase ("what are the rules and patterns"). The file tree in CLAUDE.md is authoritative -- if the README includes one, it should match exactly.

### Pitfall 5: Listing Docker Containers Without Noting External Ownership

**What goes wrong:** README implies all containers are defined in this repo, when parts and claw-swap containers are declared in their respective external repos (imported as flake inputs).

**How to avoid:** Clearly note that container definitions come from `inputs.parts.nixosModules.default` and `inputs.claw-swap.nixosModules.default`, not from this repo directly.

## Code Examples

Not applicable -- this phase writes Markdown, not code. However, the README will contain command examples. These should be sourced from:

1. **Deploy commands:** From `scripts/deploy.sh --help` output and the actual script
2. **Restic commands:** From `modules/restic.nix` configuration and `docs/recovery-runbook.md`
3. **Agent commands:** From `agent-spawn --help` (the usage block in agent-compute.nix)
4. **Nix validation:** `nix flake check`, `nixos-rebuild build --flake .#neurosys`

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Grafana + Alertmanager + ntfy | Prometheus-only (agents query API) | Quick-005 | README should NOT mention Grafana, ntfy, or Alertmanager |
| Hard-coded backup paths | Blanket "/" with exclusions | Quick-008 | README backup section describes blanket approach |
| Port 22 on public firewall | SSH Tailscale-only | Phase 17-02 | README must state SSH is NOT on public firewall |
| Hostname "acfs" | Hostname "neurosys" | 2026-02-19 | README uses "neurosys" everywhere |
| tmux | zmx | Quick-001 | README mentions zmx, not tmux |

## Open Questions

1. **Audience specificity**
   - What we know: The success criteria say "first-time deployer" and "someone who needs to understand and operate this system quickly"
   - What's unclear: Whether this is exclusively the repo owner (Dan) or also potential collaborators
   - Recommendation: Write for a competent NixOS user who has never seen this specific config. This covers both audiences without over-explaining NixOS basics.

2. **README length**
   - What we know: Must be "concise" and "skimmable" but must also cover all modules, services, security, operations, decisions, and risks
   - What's unclear: Whether there's a target word count
   - Recommendation: Use collapsed details (`<details>`) for lengthy sections (recovery commands, full exclusion list) to keep the main flow scannable. Estimate ~300-500 lines of Markdown.

3. **Relationship to CLAUDE.md**
   - What we know: CLAUDE.md already contains a project structure and security conventions section
   - What's unclear: Whether README should duplicate, reference, or supersede CLAUDE.md content
   - Recommendation: README covers what the system does and how to operate it. CLAUDE.md covers development rules for agents. Minimal overlap. README can reference CLAUDE.md for contributor/agent guidelines.

## Sources

### Primary (HIGH confidence)
- All 13 NixOS module source files in `modules/` -- read line by line
- All 6 home-manager module source files in `home/` -- read line by line
- `flake.nix` -- complete flake configuration
- `hosts/neurosys/*.nix` -- host configuration + hardware + disko
- `scripts/deploy.sh` -- full deploy script
- `docs/recovery-runbook.md` -- disaster recovery procedures
- `.sops.yaml` -- secrets configuration
- `packages/*.nix` -- custom package definitions
- `CLAUDE.md` -- project conventions and structure

### Secondary (MEDIUM confidence)
- `.planning/ROADMAP.md` -- phase completion status (used for context, not as source of truth for features)
- `.planning/STATE.md` -- decision log (cross-verified against module source)
- `.planning/PROJECT.md` -- original project context (STALE in parts -- not used as feature source)

## Metadata

**Confidence breakdown:**
- Content inventory: HIGH -- every module read line-by-line, all facts extracted from source code
- Structure recommendation: HIGH -- directly maps to success criteria requirements
- Pitfalls: HIGH -- identified from actual stale content in planning docs vs current implementation

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (stable -- documentation of existing implementation)
