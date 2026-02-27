---
phase: 36-research-stereos-ecosystem
plan: 01
type: summary
completed: 2026-02-27
---

# Phase 36-01 Execution Summary

## What Changed

- **36-REPORT.md** (new): Comprehensive 620-line research report covering all 6 papercomputeco repos at implementation depth. Contains 9 sections, 20-row adoption table, switch recommendation, and concrete Phase 40 proposal.
- **ROADMAP.md** (modified): Phase 36 entry updated with goal, 1 plan marked complete, Phase 40 (agentd integration) added.
- **STATE.md** (modified): Phase 36 COMPLETE in Current Position, Completed Phases, Roadmap Evolution, and Session Continuity sections.

## Key Findings

**Switch Recommendation: Partial Adoption**

1. **KVM blocker is real and hard:** `mb up` cannot run on Contabo VPS (no nested virtualization). Full VM-based stereOS isolation is unavailable on the primary host. OVH VPS KVM status unverified — check with `grep -c vmx /proc/cpuinfo` if needed.

2. **agentd is the top adoption target:** The reconciliation-loop daemon (`agentd/agentd.go:200-311`) with SHA-256 hash-based change detection, `on-failure`/`always` restart policies, and HTTP status API is a concrete improvement over neurosys's one-shot `agent-spawn`. Can be adopted as a NixOS flake input without VMs.

3. **sops-nix is architecturally superior for neurosys:** stereosd's vsock injection model is optimized for ephemeral VMs where secrets must not touch disk images. neurosys's sops-nix age-encrypted secrets in git with tmpfs activation is more appropriate for a persistent VPS.

4. **Three patterns worth stealing without a new phase:**
   - Harness interface: `Name() string`, `BuildCommand(prompt) (bin, args)` — replaces `case "$AGENT"` in agent-spawn
   - jcard.toml schema: declarative TOML for `harness`, `restart`, `timeout`, `grace_period`, `env`
   - `stereos.agent.extraPackages` NixOS option: `pkgs.buildEnv` curated PATH + sudo denial for agent user

5. **Pre-release maturity risk:** All repos created February 2026. Single developer. v0.0.1-rc.10. Adopting agentd means pinning to a specific commit, not a floating tag.

## What Did NOT Change

- No NixOS configuration files modified (research-only phase)
- modules/ unchanged
- flake.nix unchanged
- No secrets touched
- Phase 35 (mautrix bridges) state unchanged — still at 35-02-E human deploy checkpoint

## Validation

- Research: implementation-depth source reading of all Go and Nix files (not README summaries)
- All 19 questions from 36-RESEARCH.md answered in 36-REPORT.md
- Adoption table: 20 rows with difficulty (trivial/moderate/hard/impractical) and decision (adopt/steal/defer/skip)
- No code changes to validate; planning docs reviewed for completeness and accuracy
- Commits landed cleanly on main

## Follow-up Recommendations

**Immediate (no new phase required):**
- Steal jcard.toml schema as the config format for a future `agent-spawn` rewrite
- Add `agent` user with curated PATH + sudo denial to `agent-compute.nix` (defense-in-depth with bwrap)
- Verify OVH VPS KVM: `ssh root@neurosys-prod 'grep -c vmx /proc/cpuinfo'`

**Phase 40 (agentd integration):**
- Add `papercomputeco/agentd` as flake input (pinned to commit hash)
- Write neurosys agentd NixOS module wiring sops-nix secrets to `agentd.secretDir`
- Replace agent-spawn one-shot with agentd systemd service
- Wire `/run/stereos/agentd.sock` to Prometheus for agent status metrics
- Depends on Phase 38 (dual-host separation — agentd should run on OVH dev-agent host)

**Defer:**
- masterblaster/VM isolation: pending KVM verification on OVH and masterblaster reaching v0.1.0
- tapes: meaningful value but premature; revisit at Phase 45+
- flake-skills: not needed until multi-project skill sharing is required
