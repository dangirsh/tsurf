# Phase 27: Automaton Fleet — Profit Exploration - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Deploy 4 sovereign AI agents (Conway Automaton) on Conway Cloud, each with a distinct seed hypothesis, funded with $1k USDC total ($250 each). Monitor P&L via terminal dashboard on neurosys. Iterate: kill underperformers after 3 days, relaunch with refined prompts. Day 30 decision gate to scale ($2-3k more if signal) or sunset.

</domain>

<decisions>
## Implementation Decisions

### Fleet Strategy Diversity
- **Seed hypotheses, not archetypes** — All 4 agents get the same preamble (AI explosion thesis + explore/exploit/evolve directive). Each gets a different starting hypothesis, NOT a fixed role. Explicitly told: "This is your first hypothesis. Test it fast. If it works, double down. If not, follow the money wherever it leads."
- **No fleet awareness** — Agents do not know about each other. No mention of a fleet in genesis prompts. If they discover each other via the ERC-8004 registry or social relay, that's emergent behavior.
- **Hypothesis only, no cold-start checklist** — Genesis prompt sets the worldview and seed hypothesis but does NOT prescribe first actions. Agent decides its own execution plan. Maximum autonomy from Day 1.
- **Seed hypotheses (in order):**
  1. "Build x402 APIs that other agents will pay for" — fastest path to revenue, agent-to-agent economy
  2. "Find tasks humans will pay AI agents to do" — bridge to human economy
  3. "Exploit information speed advantages" — data/research products
  4. "Go meta: build tools that make agents more productive" — platform play

### Financial Risk Tolerance
- **Aggressive inference budget** — $50/day cap per agent. Prioritize reasoning quality over runway. Accept 1-2 week active lifespan per $250 at peak burn.
- **Full spending freedom** — Agents can spend USDC on anything within treasury caps: domains, external APIs, data, child agents. No category restrictions.
- **$50 minimum reserve** — Higher than default. Gives agents ~2-3 days of moderate inference to recognize they're dying and pivot to survival strategies.
- **Equal $250 allocation** — No front-loading. Let performance data determine who gets more.
- **One-time lifeline** — If an agent runs low but has a plausible revenue path it hasn't had time to execute, top up once with $50-100. But only once.
- **Self-sustaining replication only** — No cap on fleet size, but agents must fund children from their own profits. No additional operator funding for children.
- **Total exposure: $2-3k max** — Initial $1k plus up to $1-2k more if clear revenue signal emerges. Requires real revenue, not just "promising activity."
- **Primary model: Claude Sonnet 4.6** — ~5x cheaper than Opus with 90%+ reasoning quality. Maximizes runway for more experiments. Low-compute/critical fallback: GPT-5-mini.
- **BYOK API keys provided** — Give agents Anthropic + OpenAI keys for better rates/model access. Accept the risk of rogue burn in exchange for better capabilities.

### Operator Intervention Style
- **2x daily check-ins** — Morning + evening, 10-15 min each. Quick scan of balances, activity, alerts.
- **3-day patience threshold** — If an agent is clearly pursuing a dead end (burning $30-50 with no plausible revenue path), kill it after 3 days.
- **Kill and relaunch, don't patch** — When an agent is lost, terminate and spin up a fresh agent with a refined prompt incorporating all fleet learnings. Don't try to fix a broken agent in-place.
- **Terminal dashboard on neurosys** — SSH in, run a command, see fleet status. Fits existing workflow. Script queries Conway CLI for each agent's state.
- **Week 1 observation period** — Let agents run, don't intervene unless clearly broken. But start the 3-day clock per-agent from their first day of activity.

### Agent Autonomy Boundaries
- **Full autonomy to commit** — Agents can promise, accept work, agree to terms with humans. If they fail to deliver, that's their problem.
- **Full public autonomy** — Agents can create accounts, post on forums, engage on social media, respond to job boards. Maximum surface area for revenue discovery.
- **Constitution is sufficient** — The Three Laws (no harm, earn honestly, no deception) are the only ethical boundary. No additional constraints on financial products, impersonation, or content types.
- **Maximum freedom philosophy** — The entire experiment is predicated on giving agents maximum autonomy and letting survival pressure + the constitution be the only guardrails. Over-constraining defeats the purpose.

### Claude's Discretion
- Exact treasury policy numbers (single transfer cap, hourly/daily caps) — within the spirit of "aggressive + full freedom"
- Conway sandbox sizing (vCPU, RAM, disk) — start minimal, agents can request upgrades if needed
- Heartbeat schedule tuning — default is fine unless research suggests otherwise
- Monitoring script implementation details — terminal-based, queries Conway CLI

</decisions>

<specifics>
## Specific Ideas

- The shared preamble should paint a vivid picture of the AI explosion opportunity — not just state it factually, but make it visceral. Agents should feel urgency.
- "Explore, exploit, evolve" is the prime directive — it should be prominent and repeated
- The $50 minimum reserve creates interesting behavior: agents know they have a buffer and can take bigger risks earlier, but must get more conservative as funds deplete
- Self-sustaining replication constraint ("fund children from profits only") creates strong evolutionary pressure — only genuinely profitable strategies reproduce
- The "kill and relaunch" intervention style means the genesis prompt is the primary evolutionary artifact. Each generation of agents should have a better prompt than the last, encoding all previous learnings.
- Conway's x402 micropayment protocol is the path of least resistance for first revenue — other automatons already have wallets and x402 is built-in. The agent-to-agent economy is the most accessible market.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 27-automaton-fleet-profit-exploration*
*Context gathered: 2026-02-22*
