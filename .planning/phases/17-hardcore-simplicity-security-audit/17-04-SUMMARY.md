---
phase: 17-hardcore-simplicity-security-audit
plan: 04
subsystem: infra, docs
tags: [docker, security, sandbox, audit]
duration: 20min
completed: 2026-02-19
---

# Phase 17 Plan 04: Docker Container Audit + Sandbox Assessment + Audit Log Hardening

**Audited all Docker containers for security hardening, confirmed sandbox escape vectors, documented findings, and added journald dual-logging for tamper resistance.**

## Accomplishments
- Audited all 5 Docker containers across parts and claw-swap repos
- Confirmed sandbox escape vectors and documented mitigations in CLAUDE.md
- Added GHSA-ff64-7w26-62rf CVE reference to --no-sandbox "Never" rule
- Added journald dual-logging to agent-spawn for tamper-resistant audit trail
- Documented SEC-17-04 tamper risk on spawn.log in agent-compute.nix

## Docker Container Hardening Audit

### claw-swap (FULLY HARDENED)

| Container | read-only | cap-drop ALL | no-new-privileges | memory limit | cpu limit | Docker socket | privileged |
|-----------|-----------|-------------|-------------------|-------------|-----------|--------------|-----------|
| claw-swap-db | YES | YES (+5 minimal caps) | YES | 512m | 1.0 | No | No |
| claw-swap-app | YES | YES | YES | 512m | 1.0 | No | No |
| claw-swap-caddy | YES | YES (+NET_BIND_SERVICE) | YES | 256m | 0.5 | No | No |

All claw-swap containers use tmpfs with noexec,nosuid for writable scratch areas. Exemplary hardening.

### parts (NO HARDENING)

| Container | read-only | cap-drop ALL | no-new-privileges | memory limit | cpu limit | Docker socket | privileged |
|-----------|-----------|-------------|-------------------|-------------|-----------|--------------|-----------|
| parts-tools | NO | NO | NO | NO | NO | No | No |
| parts-agent | NO | NO | NO | NO | NO | No | No |

**Missing items for parts containers (remediation in external repo `dangirsh/personal-agent-runtime`):**

1. **SEC3-parts-tools-readonly:** Add `--read-only` + `--tmpfs /tmp:rw,noexec,nosuid` to parts-tools extraOptions
2. **SEC3-parts-tools-capdrop:** Add `--cap-drop=ALL` + minimal cap-adds as needed to parts-tools
3. **SEC3-parts-tools-noprivesc:** Add `--security-opt=no-new-privileges` to parts-tools
4. **SEC3-parts-tools-limits:** Add `--memory=2g --cpus=2.0` (or appropriate) to parts-tools
5. **SEC3-parts-agent-readonly:** Add `--read-only` + `--tmpfs /tmp:rw,noexec,nosuid` to parts-agent
6. **SEC3-parts-agent-capdrop:** Add `--cap-drop=ALL` to parts-agent
7. **SEC3-parts-agent-noprivesc:** Add `--security-opt=no-new-privileges` to parts-agent
8. **SEC3-parts-agent-limits:** Add `--memory=1g --cpus=1.0` (or appropriate) to parts-agent

**Mitigating factors:** Both parts containers run on internal Docker networks (agent_net, tools_net), not exposed to public internet. parts-agent is network-isolated (no internet access). Neither mounts Docker socket or runs privileged.

### homepage-dashboard

- Docker socket mounted at `/var/run/docker.sock` for container status display
- **Risk:** SEC6 — accepted, mitigated by Tailscale-only access (port 8082 in internalOnlyPorts)

## Sandbox Escape Vector Assessment

### Confirmed findings (from agent-compute.nix bwrap config):

1. **SEC5 -- .claude writable in --no-sandbox mode:** `--ro-bind-try /home/dangirsh/.claude` in bwrap protects sandbox mode. In --no-sandbox, agents can modify ~/.claude/settings.json freely. **Accepted risk** — --no-sandbox requires explicit user opt-in.

2. **SEC6 -- Homepage Docker socket:** `homepage.nix` line 22 mounts `/var/run/docker.sock`. **Accepted risk** — Tailscale-only, read-only socket usage.

3. **Cross-project read access:** `--ro-bind /data/projects /data/projects` then `--bind "$PROJECT_DIR" "$PROJECT_DIR"` makes all sibling projects readable. **Deliberate design choice** — agents need cross-repo references.

4. **Network not sandboxed:** `--unshare-net` is NOT used. **Deliberate design choice** — agents need network for API calls, git, package management. Metadata endpoint (169.254.169.254) blocked at nftables level.

5. **Audit log tamper risk:** `/data/projects/.agent-audit/spawn.log` writable by dangirsh. **Mitigated** — added journald dual-logging via `systemd-cat -t agent-spawn` (root-owned journal, agents cannot modify).

## Task Commits
1. **Task 1 + Task 2: Audit findings, sandbox docs, journald logging** — `ddcc347`

## Files Modified
- `modules/agent-compute.nix` — Added SEC-17-04 tamper risk comment, journald dual-logging via systemd-cat
- `CLAUDE.md` — Added CVE reference to --no-sandbox rule, sandbox escape findings to Accepted Risks

## Decisions Made
- Kept spawn.log directory owned by dangirsh (needed for agent-spawn writes) — tamper resistance via journald, not filesystem permissions
- Parts container hardening tracked as documentation items (changes needed in external repo, not neurosys)

## Deviations from Plan
- Plan suggested BEADS entries for parts container gaps — documented as numbered remediation items in SUMMARY instead (BEADS creation is a separate workflow step)

## Issues Encountered
None

## Next Phase Readiness
All Phase 17 plans (01-04) are complete. Ready for phase verification and merge.

## Self-Check: PASSED
