# Phase 45: Interrogate Design Principles and Rewrite README Principles Section - Context

**Gathered:** 2026-02-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Audit and rewrite the "Design Principles" section of README.md. The current 6 bullets were added incrementally and don't reflect a deliberate, coherent set. This phase nails down the right principles and rewrites the section — nothing else in the README changes.

</domain>

<decisions>
## Implementation Decisions

### Core reframe: agents as first-class users (not workloads)

The headline insight that must lead the section: **agents are the primary users of this system, not humans**. The mental model is:

> Human ↔ Agents ↔ neurosys

Like designing Unix knowing a human would never directly interface with the system. This reframes everything — sandbox design, networking, secrets injection, state management — all serve the agent-as-user model. The word "users" is intentional and important; "workloads" misses the point.

### Principle count

Target ~6 principles. Current 6 bullets will be restructured (not just relabeled) — some merged, some reframed, new ones added.

### Format: brief rationale added

Each principle gets a bold label + 1-line description (current style) **plus 1-2 sentences of rationale** explaining why the principle exists and what it prevents. This is the biggest format change from the current README.

### Additions

Two new principles to add (from discussion):

1. **Minimal untracked state** — If it's not in git, `/persist`, or B2, it doesn't survive a rebuild. This is the governing constraint behind all state decisions.

2. **Secure defaults, explicit exceptions** — Safe by default: sandbox on, public ports closed, secrets encrypted at rest. Opt-out is explicit and documented; there is no "just skip the sandbox today" path.

### Merges

- **"Impermanent root"** (current bullet 5) → becomes the *mechanism* for "Minimal untracked state", not its own principle. The principle is the constraint; BTRFS ephemeral root is how we enforce it.
- **"Tailscale-only internal networking"** and **"Secrets never in the Nix store"** → both become examples or sub-points under "Secure defaults, explicit exceptions". They're specific instantiations of the same principle.

### Demotions

- **"Private config via overlay"** (current bullet 6) → demote out of Design Principles. Move to Quick Start section as a pattern/instruction. It's an architectural pattern for using the project, not a design principle.

### Claude's Discretion

- Exact final count (target ~6, may land at 5-7 depending on merges)
- Whether "Declarative everything" and "Tailscale-only networking" stay as separate named principles vs. fold into others
- Exact wording and ordering of principles
- Whether to add a 1-sentence framing intro before the list (e.g., "These principles reflect the design constraint that agents, not humans, are the primary users of this system.")

</decisions>

<specifics>
## Specific Ideas

- **The mental model line**: "Human ↔ Agents ↔ neurosys" — this should appear somewhere near the principles, either as an intro sentence or inline with the agents principle.
- **The Unix analogy**: "Like designing Unix knowing a human would never directly interface with the system" — may be too long for the README but captures the right intent; use it to guide word choice.
- **Rationale tone**: The rationale sentences should explain *what the principle prevents*, not just what it enables. E.g., "Minimal untracked state" rationale should mention "a server that can be reprovisioned from scratch without losing anything" — consequence, not just description.

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope.

</deferred>

---

*Phase: 45-interrogate-design-principles-and-rewrite-readme-principles-section*
*Context gathered: 2026-02-27*
