# Phase 36: Research stereOS Ecosystem - Context

**Gathered:** 2026-02-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Comprehensive study of the stereOS ecosystem repos (stereOS, masterblaster, stereosd, agentd).
Output: a written report covering what to learn/steal for neurosys and a concrete recommendation
on whether to switch from NixOS to stereOS. No implementation work — research and report only.

</domain>

<decisions>
## Implementation Decisions

### Evaluation lens

Evaluate through neurosys's primary lens: **agent-first self-hosted server platform**.

Priority order for what matters:
1. **Agent orchestration** (primary) — how agentd spawns, supervises, and sandboxes agents;
   how it compares to neurosys's bubblewrap + agent-spawn + cgroup-slice pattern
2. **System configuration style** — declarative vs. imperative; how stereOS modules compare
   to NixOS flake modules; reusability, composability, secret handling patterns
3. **Deployment mechanics** — how masterblaster/stereosd handle deploy + rollback vs.
   deploy-rs + nixos-rebuild; does it have magic rollback, atomic switch, health checks?
4. **Self-hosting philosophy** — what services are in scope, how secrets are managed,
   what the security model looks like for agent workloads

### "Steal" scope

The report must produce **two concrete outputs**:

1. **Adoption table** — for each pattern/tool/approach, a row: What it is | Why it matters
   for neurosys | How hard to adopt | Decision (adopt/steal/defer/skip). Not just "interesting."
2. **Action items** — concrete new phases or TODOs to add to roadmap if adoption is warranted.
   If a pattern is worth stealing, the report should name the phase it would become.

Philosophical observations are fine but must translate into actionable rows.

### Switch recommendation criteria

Neurosys has 36 phases of NixOS investment. The bar for "switch" is high. Frame the
recommendation explicitly against these non-negotiables:

**Must be preserved (non-negotiables):**
- Declarative, reproducible system configuration (no imperative drift)
- Encrypted secrets management (sops-nix equivalent — age-based)
- Agent sandboxing (bubblewrap-equivalent isolation)
- Minimal cloud dependency (self-hosted everything)
- Rollback safety on deploy

**Recommendation tiers:**
- **Switch**: stereOS clearly superior for agent-first use AND migration path is
  tractable (< 2 weeks of work)
- **Partial adoption**: Specific patterns/tools from stereOS worth incorporating into NixOS
  neurosys (most likely outcome)
- **Stay**: stereOS doesn't offer enough beyond what NixOS provides for this use case

Report must state the tier explicitly and back it with evidence from the repos.

### Research depth

Go deep on all 4 repos — not README-level, but actual implementation:

- Read all significant source files in each repo
- Understand the agent lifecycle in agentd (how agents are defined, spawned, supervised,
  sandboxed, communicated with)
- Understand the full deployment flow in masterblaster/stereosd
- Look for: config format, secrets handling, inter-service communication, monitoring hooks
- Check repo maturity signals: commit frequency, open issues, docs quality, test coverage
- If docs reference blog posts or external resources, fetch and read them

**Prioritization within "go deep"**: agentd and masterblaster are highest priority — these
are most novel relative to neurosys's current stack. stereOS and stereosd are important
context but agentd is the main event.

### Claude's Discretion
- How to structure the report (sections, order)
- Whether to use parallel research agents per repo or single sequential pass
- Exact scoring/weighting within the adoption table

</decisions>

<specifics>
## Specific Ideas

- User wants depth over breadth — implementation-level understanding, not surface scanning
- The "steal" framing is deliberate: look for concrete techniques and patterns to extract,
  not just admire from a distance
- agentd is probably the most interesting repo given neurosys's agent-first focus — give
  it extra attention
- The switch recommendation should be honest, not diplomatic: if stereOS is clearly better
  for this use case, say so with evidence

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 36-research-stereos-ecosystem*
*Context gathered: 2026-02-27*
