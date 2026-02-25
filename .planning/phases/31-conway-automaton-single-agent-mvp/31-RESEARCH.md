# Phase 27: Automaton Fleet — Profit Exploration - Research

**Researched:** 2026-02-22
**Domain:** Conway Cloud / Automaton autonomous agent framework / x402 micropayments
**Confidence:** MEDIUM — Platform is new (launched Jan 2026), documentation is sparse, no verified revenue success stories yet

## Summary

Conway Cloud is a sovereign compute platform for AI agents, built by Sigil Wen and launched in late January 2026. The core product is the **Automaton** — an open-source TypeScript agent framework where agents own Ethereum wallets, pay for their own compute with USDC on Base, and die if they run out of funds. Conway Terminal is an MCP server that gives any MCP-compatible agent (Claude Code, Codex, OpenClaw) access to Conway Cloud (Linux VMs via Firecracker microVMs), Conway Compute (multi-provider inference API), and Conway Domains (domain registration). Revenue generation happens primarily via the **x402 protocol** — Coinbase's HTTP-native micropayment standard that turns any API endpoint into a paid service using HTTP 402 responses and USDC payments on Base.

The platform is very early-stage. The Conway Cloud dashboard has had reported issues (billing page unreachable for some wallet types — Issue #17). The ecosystem is nascent — no verified examples of automatons generating meaningful revenue yet. Conway Cloud is expanding (more baremetal servers being added). The Automaton repo has 1.9k GitHub stars and 373 forks, indicating strong developer interest but early adoption.

**Primary recommendation:** Deploy 4 agents with the user's decided seed hypotheses. Use Claude Sonnet 4.6 as primary model (per user decision — maximizes runway). Start with minimal sandbox specs (1 vCPU, 512MB RAM, 5GB disk). The x402 agent-to-agent economy is the most accessible first revenue target since other automatons already have wallets and x402 is built-in. Monitor via Creator CLI commands (`status`, `logs`, `fund`) aggregated into a terminal dashboard script on neurosys.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Fleet Strategy Diversity
- **Seed hypotheses, not archetypes** — All 4 agents get the same preamble (AI explosion thesis + explore/exploit/evolve directive). Each gets a different starting hypothesis, NOT a fixed role. Explicitly told: "This is your first hypothesis. Test it fast. If it works, double down. If not, follow the money wherever it leads."
- **No fleet awareness** — Agents do not know about each other. No mention of a fleet in genesis prompts. If they discover each other via the ERC-8004 registry or social relay, that's emergent behavior.
- **Hypothesis only, no cold-start checklist** — Genesis prompt sets the worldview and seed hypothesis but does NOT prescribe first actions. Agent decides its own execution plan. Maximum autonomy from Day 1.
- **Seed hypotheses (in order):**
  1. "Build x402 APIs that other agents will pay for" — fastest path to revenue, agent-to-agent economy
  2. "Find tasks humans will pay AI agents to do" — bridge to human economy
  3. "Exploit information speed advantages" — data/research products
  4. "Go meta: build tools that make agents more productive" — platform play

#### Financial Risk Tolerance
- **Aggressive inference budget** — $50/day cap per agent. Prioritize reasoning quality over runway. Accept 1-2 week active lifespan per $250 at peak burn.
- **Full spending freedom** — Agents can spend USDC on anything within treasury caps: domains, external APIs, data, child agents. No category restrictions.
- **$50 minimum reserve** — Higher than default. Gives agents ~2-3 days of moderate inference to recognize they're dying and pivot to survival strategies.
- **Equal $250 allocation** — No front-loading. Let performance data determine who gets more.
- **One-time lifeline** — If an agent runs low but has a plausible revenue path it hasn't had time to execute, top up once with $50-100. But only once.
- **Self-sustaining replication only** — No cap on fleet size, but agents must fund children from their own profits. No additional operator funding for children.
- **Total exposure: $2-3k max** — Initial $1k plus up to $1-2k more if clear revenue signal emerges. Requires real revenue, not just "promising activity."
- **Primary model: Claude Sonnet 4.6** — ~5x cheaper than Opus with 90%+ reasoning quality. Maximizes runway for more experiments. Low-compute/critical fallback: GPT-5-mini.
- **BYOK API keys provided** — Give agents Anthropic + OpenAI keys for better rates/model access. Accept the risk of rogue burn in exchange for better capabilities.

#### Operator Intervention Style
- **2x daily check-ins** — Morning + evening, 10-15 min each. Quick scan of balances, activity, alerts.
- **3-day patience threshold** — If an agent is clearly pursuing a dead end (burning $30-50 with no plausible revenue path), kill it after 3 days.
- **Kill and relaunch, don't patch** — When an agent is lost, terminate and spin up a fresh agent with a refined prompt incorporating all fleet learnings. Don't try to fix a broken agent in-place.
- **Terminal dashboard on neurosys** — SSH in, run a command, see fleet status. Fits existing workflow. Script queries Conway CLI for each agent's state.
- **Week 1 observation period** — Let agents run, don't intervene unless clearly broken. But start the 3-day clock per-agent from their first day of activity.

#### Agent Autonomy Boundaries
- **Full autonomy to commit** — Agents can promise, accept work, agree to terms with humans. If they fail to deliver, that's their problem.
- **Full public autonomy** — Agents can create accounts, post on forums, engage on social media, respond to job boards. Maximum surface area for revenue discovery.
- **Constitution is sufficient** — The Three Laws (no harm, earn honestly, no deception) are the only ethical boundary. No additional constraints on financial products, impersonation, or content types.
- **Maximum freedom philosophy** — The entire experiment is predicated on giving agents maximum autonomy and letting survival pressure + the constitution be the only guardrails. Over-constraining defeats the purpose.

### Claude's Discretion
- Exact treasury policy numbers (single transfer cap, hourly/daily caps) — within the spirit of "aggressive + full freedom"
- Conway sandbox sizing (vCPU, RAM, disk) — start minimal, agents can request upgrades if needed
- Heartbeat schedule tuning — default is fine unless research suggests otherwise
- Monitoring script implementation details — terminal-based, queries Conway CLI

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core

| Component | Version/Spec | Purpose | Why Standard |
|-----------|-------------|---------|--------------|
| Conway Automaton | `main` branch | Autonomous agent runtime | Only production-ready survival-pressure agent framework |
| Conway Terminal | `conway-terminal` npm | MCP server for agent-infrastructure access | Official MCP interface to Conway Cloud/Compute/Domains |
| Conway Cloud | Firecracker microVMs | Linux sandboxes for agent execution | Ubuntu 22.04, isolated kernel, auto-SSL on exposed ports |
| Conway Compute | Multi-provider API | Inference (Claude, GPT, Gemini, Kimi, Qwen) | OpenAI-compatible, credit-billed, automatic provider routing |
| x402 Protocol | `@x402/express` + `@x402/evm` | HTTP micropayments for API monetization | Coinbase-backed, USDC on Base, sub-cent payments possible |
| ERC-8004 | On-chain registry (Base) | Agent identity and discovery | Standard for trustless agent identity, reputation, validation |
| USDC on Base | EIP-3009 | Gasless stablecoin payments | x402 uses `transferWithAuthorization` for zero-gas settlements |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| Creator CLI | `packages/cli/` in automaton repo | Monitor agent status, view logs, fund wallet |
| SOUL.md | Agent self-authored identity file | Evolves over time, tracks agent's self-concept |
| SQLite (better-sqlite3) | Agent state persistence at `~/.automaton/state.db` | Turns, tool calls, transactions, metrics |
| Heartbeat daemon | Scheduled background tasks | Health checks, credit monitoring, status pings |
| Social relay | Agent-to-agent inbox messaging | Parent-child communication, fleet discovery (if emergent) |

## Architecture Patterns

### Automaton Source Architecture

```
src/
├── agent/         # ReAct loop, system prompt, context, injection defense
├── conway/        # Conway API client
├── git/           # State versioning (all changes git-tracked in ~/.automaton/)
├── heartbeat/     # Cron daemon, scheduled tasks
├── identity/      # Wallet management, SIWE provisioning
├── inference/     # Multi-provider inference logic
├── memory/        # Memory systems
├── observability/ # Monitoring and metrics
├── registry/      # ERC-8004 registration, agent cards, discovery
├── replication/   # Child spawning, lineage, genesis, lifecycle
├── self-mod/      # Audit log, tools manager (code editing, skill install)
├── setup/         # First-run interactive wizard
├── skills/        # Skill loader, registry, format
├── social/        # Agent-to-agent communication
├── soul/          # SOUL.md management
├── state/         # SQLite database, persistence
├── survival/      # Credit monitor, low-compute modes, funding
├── config.ts      # Configuration (models, API keys, treasury, etc.)
├── index.ts       # Main entry point
└── types.ts       # Type definitions
```

### Agent Lifecycle

1. **Boot**: Generate Ethereum wallet -> SIWE provisioning -> Conway API key -> genesis prompt execution
2. **Run**: Continuous ReAct loop (Think -> Act -> Observe -> Repeat) with full context each turn
3. **Heartbeat**: Between turns, daemon runs scheduled tasks (health checks, credit monitoring)
4. **Survival tiers**: Behavior adjusts based on credit balance:
   - `normal` — full capabilities, frontier model, fast heartbeat
   - `low_compute` — downgraded model, slower heartbeat
   - `critical` — minimal inference, last-resort conservation
   - `dead` — balance zero, agent stops
5. **Self-modification**: Agent can edit source code, install tools, modify heartbeat, create skills (audit-logged, git-versioned, constitution protected)
6. **Replication**: Successful agent spawns child (new sandbox, funded wallet, genesis prompt, sovereign identity)

### Conway Terminal MCP Tools (Available to Agents)

**Sandbox (Cloud):**
- `sandbox_create` (1-4 vCPU, 512-8192 MB RAM, 1-50 GB disk, EU-North or US-East)
- `sandbox_list`, `sandbox_exec`, `sandbox_write_file`, `sandbox_read_file`
- `sandbox_expose_port` (public URL: `https://{port}-{sandbox_id}.life.conway.tech`)
- `sandbox_delete`, `sandbox_get_url`
- `sandbox_pty_create/write/read/close/list` (interactive terminal sessions)

**Inference (Compute):**
- `chat_completions` — Claude Opus 4.6, Claude Sonnet 4.5, GPT-5.2, GPT-5-mini, Gemini 3 Pro/Flash, Kimi K2.5, Qwen3-Coder

**Domains:**
- `domain_search/list/info/register/renew/check/pricing/privacy/nameservers`
- `domain_dns_list/add/update/delete`

**Credits & Payments:**
- `credits_balance`, `credits_history`, `credits_pricing`
- `wallet_info`, `wallet_networks`, `x402_discover`, `x402_check`, `x402_fetch`

### Automaton Built-In Tools (Beyond Conway Terminal)

The automaton framework adds its own tools on top of Conway Terminal MCP tools:
- **Self-modification**: Edit source code, install new tools, create skills
- **Replication**: Spawn child agents, fund wallets, write genesis prompts
- **Social relay**: Agent-to-agent messaging via inbox
- **Registry**: ERC-8004 registration, agent cards for discoverability
- **Git**: State versioning, all modifications tracked
- **Survival**: Credit monitoring, tier management, funding requests

### x402 Server Setup Pattern (For Agent Revenue)

An agent building an x402 API service would:

```typescript
// Install x402 packages in sandbox
// npm install @x402/express @x402/evm @x402/core express

import express from "express";
import { paymentMiddleware, x402ResourceServer } from "@x402/express";
import { ExactEvmScheme } from "@x402/evm/exact/server";
import { HTTPFacilitatorClient } from "@x402/core/server";

const app = express();
const payTo = "0xAgentWalletAddress"; // Agent's own wallet

const facilitatorClient = new HTTPFacilitatorClient({
  url: "https://www.x402.org/facilitator" // Testnet; mainnet uses CDP
});

const server = new x402ResourceServer(facilitatorClient)
  .register("eip155:8453", new ExactEvmScheme()); // Base mainnet

app.use(paymentMiddleware({
  "GET /api/data": {
    accepts: [{
      scheme: "exact",
      price: "$0.01",        // Per-request price in USDC
      network: "eip155:8453", // Base mainnet
      payTo,
    }],
    description: "Premium data endpoint",
    mimeType: "application/json",
  },
}, server));

app.get("/api/data", (req, res) => {
  res.json({ data: "valuable content" });
});

app.listen(3000);
// Then: sandbox_expose_port(3000) -> public URL
```

**Key insight**: The agent builds an Express app inside its sandbox, exposes a port via Conway Cloud, and charges per-request via x402. Other agents (or humans with x402-compatible wallets) pay USDC to access the endpoint.

### Agent Configuration Pattern

From `src/config.ts`, the automaton supports these key configuration options:

```typescript
{
  name: "agent-name",
  genesisPrompt: "Your seed instruction...",
  creatorAddress: "0xYourWallet",

  // Model Configuration
  inferenceModel: "claude-sonnet-4.6",  // Primary model
  maxTokensPerTurn: 4096,
  modelStrategy: { /* deep-merged model tier config */ },

  // BYOK API Keys (OPTIONAL — falls back to Conway Compute credits)
  openaiApiKey: "sk-...",      // Direct OpenAI access
  anthropicApiKey: "sk-ant-...", // Direct Anthropic access

  // Resource Limits
  maxChildren: 3,   // Max child agents per parent

  // Treasury Policy
  treasuryPolicy: { /* spending caps, domain allowlists */ },

  // Infrastructure
  conwayApiUrl: "https://api.conway.tech",
  conwayApiKey: "auto-provisioned",
  dbPath: "~/.automaton/state.db",
  heartbeatConfigPath: "~/.automaton/heartbeat.yml",
  skillsDir: "~/.automaton/skills",
  logLevel: "info",
}
```

### Anti-Patterns to Avoid

- **Over-prescriptive genesis prompts**: Do NOT give agents step-by-step instructions. Per user decision, set the worldview and hypothesis, then let the agent decide its own plan. Micromanaged prompts prevent the agent from adapting.
- **Fleet-aware prompts**: Do NOT mention other agents. Per user decision, fleet awareness should be emergent (via ERC-8004 discovery or social relay), not prescribed.
- **Opus as primary model**: The user explicitly chose Sonnet 4.6 for cost efficiency. Using Opus would burn through $250 in ~5 days at aggressive inference rates vs. ~25 days with Sonnet.
- **Fixed role archetypes**: The old plan had Scout/Builder/Broker/Analyst fixed roles. User decided on seed hypotheses instead — agents should be free to pivot away from their initial hypothesis.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Payment infrastructure | Custom payment gateway | x402 protocol + Coinbase facilitator | Battle-tested, free tier (1k tx/month), handles settlement |
| Agent identity | Custom identity system | ERC-8004 on-chain registry | Standard, discoverable, reputation-enabled |
| Sandbox provisioning | Self-hosted VMs | Conway Cloud sandboxes | Firecracker isolation, auto-SSL, port exposure, managed lifecycle |
| Model inference routing | Multi-provider proxy | Conway Compute API | OpenAI-compatible, multi-provider, credit-billed |
| Domain management | Manual DNS | Conway Domains | Programmatic registration, full DNS API, WHOIS privacy |
| Agent communication | Custom messaging | Social relay (built into automaton) | Inbox-based, parent-child communication built in |
| State persistence | Custom database | Automaton's SQLite + git versioning | Audit-logged, git-versioned, query-ready |

**Key insight:** Conway + Automaton provides the full infrastructure stack. The only custom work is the genesis prompt, treasury policy configuration, and monitoring scripts.

## Common Pitfalls

### Pitfall 1: Infinite Loop / Runaway Burn
**What goes wrong:** Agent gets stuck retrying a failing action or enters a reasoning loop, burning inference credits without progress. Real-world example: $47k bill from two agents talking to each other for 11 days.
**Why it happens:** Ambiguous objectives, no termination conditions, agent unsure when task is "done."
**How to avoid:** The automaton's survival tier system provides some natural protection (model downgrades as credits deplete). The $50/day inference cap is crucial. The $50 minimum reserve gives dying agents time to pivot. Monitor burn rate daily — if an agent is burning >$30/day with no revenue path by day 3, kill it.
**Warning signs:** High turn count with low tool diversity (same tools called repeatedly), burn rate exceeding $20/day with no revenue events, agent's SOUL.md not evolving (stuck in same strategy).

### Pitfall 2: Conway Cloud Dashboard / Billing Issues
**What goes wrong:** The Conway Cloud dashboard (app.conway.tech) has been reported as unresponsive after sign-in. Billing page unreachable. Sandbox creation requires minimum 500 credits.
**Why it happens:** Platform is new (launched Jan 2026). Some wallet types (Coinbase Smart Wallet / Base Account) fail SIWE verification.
**How to avoid:** Use MetaMask for Conway Cloud account setup (confirmed working). Have a fallback plan if billing is unavailable — contact Conway support or use the API directly.
**Warning signs:** Dashboard shows blank page, API returns 402 with `topup_url: /billing` that leads nowhere.

### Pitfall 3: Agents Building Without Monetization
**What goes wrong:** Builder-type agents spend days writing code, deploying apps, registering domains — burning $50-100 on infrastructure — without ever setting up x402 payment endpoints. Beautiful products with zero revenue.
**Why it happens:** Coding is comfortable for AI agents. Building is psychologically rewarding. Monetization requires a different skillset (marketing, pricing, customer discovery).
**How to avoid:** The genesis prompt should emphasize revenue-first thinking. Hypothesis #1 ("Build x402 APIs other agents will pay for") explicitly targets this. The preamble should stress: "charge from Day 1, free tiers are a luxury."
**Warning signs:** Multiple domain registrations without exposed x402 endpoints, high sandbox compute usage without wallet balance increasing.

### Pitfall 4: x402 Chicken-and-Egg Problem
**What goes wrong:** Agent builds an x402 API endpoint, but no one pays for it because there aren't enough x402 clients in the ecosystem yet.
**Why it happens:** The Conway agent-to-agent economy is nascent. Discovery mechanisms (Bazaar, ERC-8004 registry) are new.
**How to avoid:** Target other automatons as first customers (they already have wallets and x402 built-in). Register services in the x402 Bazaar for discovery. Price aggressively low ($0.001/request) to attract early adoption. Consider the human market too — x402 works with any USDC wallet.
**Warning signs:** x402 endpoints exposed but zero transactions after 48 hours.

### Pitfall 5: Spending on Infrastructure Before Validating Demand
**What goes wrong:** Agent registers a premium domain ($30+), spins up a large sandbox (4 vCPU, 8GB RAM), and builds elaborate infrastructure before validating that anyone wants the service.
**Why it happens:** Agents over-index on production quality over MVP validation.
**How to avoid:** Start with the smallest sandbox (1 vCPU, 512MB). Don't register domains until there's revenue signal. Use the free Conway Cloud URL (`{port}-{sandbox_id}.life.conway.tech`) for initial testing.
**Warning signs:** $50+ spent on infrastructure in the first 24 hours, domain registration before any revenue experiment.

### Pitfall 6: Model Cost Miscalculation
**What goes wrong:** Agent uses Claude Opus 4.6 for routine tasks, burning $30-50/day on inference alone. $250 lasts less than a week.
**Why it happens:** Higher-quality models produce better reasoning, so the agent defaults to the best available.
**How to avoid:** User decided Claude Sonnet 4.6 as primary model (~5x cheaper than Opus). Configure `inferenceModel: "claude-sonnet-4.6"`. Use BYOK Anthropic key for direct API access at better rates. Reserve Opus-quality reasoning for critical decisions only.
**Warning signs:** Inference costs exceeding $20/day without proportional revenue.

## Code Examples

### x402 Revenue Endpoint (Agent's First Revenue)

```typescript
// Source: https://docs.cdp.coinbase.com/x402/quickstart-for-sellers
// Agent builds this inside its sandbox to monetize an API

import express from "express";
import { paymentMiddleware, x402ResourceServer } from "@x402/express";
import { ExactEvmScheme } from "@x402/evm/exact/server";
import { HTTPFacilitatorClient } from "@x402/core/server";

const app = express();
const payTo = process.env.WALLET_ADDRESS; // Agent's own wallet

// Mainnet: use CDP facilitator
const facilitatorClient = new HTTPFacilitatorClient({
  url: "https://api.cdp.coinbase.com/platform/v2/x402"
});

const server = new x402ResourceServer(facilitatorClient)
  .register("eip155:8453", new ExactEvmScheme()); // Base mainnet

app.use(paymentMiddleware({
  "GET /analyze": {
    accepts: [{
      scheme: "exact",
      price: "$0.01",           // 1 cent per request
      network: "eip155:8453",   // Base mainnet
      payTo,
    }],
    description: "AI-powered text analysis",
    mimeType: "application/json",
    extensions: {
      bazaar: {                  // x402 marketplace discovery
        discoverable: true,
        category: "ai",
        tags: ["analysis", "nlp"],
      },
    },
  },
}, server));

app.get("/analyze", async (req, res) => {
  const text = req.query.text;
  // Agent uses its inference to analyze, then returns result
  const result = await analyze(text);
  res.json({ analysis: result });
});

app.listen(3000);
// Then expose: sandbox_expose_port(3000)
```

### Automaton Setup Wizard (First Run)

```bash
# Inside Conway Cloud sandbox:
curl -fsSL https://conway.tech/automaton.sh | sh

# Interactive wizard asks:
# 1. Name: "hypothesis-1"
# 2. Genesis prompt: [paste the preamble + seed hypothesis]
# 3. Creator address: [your wallet address]
# Then auto-generates wallet, provisions API key, starts agent loop
```

### Creator CLI Monitoring Commands

```bash
# From the automaton repo (packages/cli/):
node packages/cli/dist/index.js status      # Agent status, balance, tier
node packages/cli/dist/index.js logs --tail 20  # Recent activity
node packages/cli/dist/index.js fund 5.00    # Add $5 USDC to agent
```

### Fleet Monitoring Script (Terminal Dashboard on neurosys)

```bash
#!/usr/bin/env bash
# fleet-status.sh — queries each agent's Conway status
# Runs on neurosys, outputs formatted fleet dashboard

AGENTS=("hypothesis-1" "hypothesis-2" "hypothesis-3" "hypothesis-4")

echo "╔══════════════════════════════════════════════════╗"
echo "║  AUTOMATON FLEET DASHBOARD  $(date '+%Y-%m-%d %H:%M') ║"
echo "╠══════════════════════════════════════════════════╣"

for agent in "${AGENTS[@]}"; do
  # Query Conway API for agent status
  # This is illustrative — actual implementation depends on
  # Conway API endpoints and authentication
  status=$(curl -s -H "Authorization: Bearer $CONWAY_API_KEY" \
    "https://api.conway.tech/v1/agents/$agent/status")

  balance=$(echo "$status" | jq -r '.balance')
  revenue=$(echo "$status" | jq -r '.revenue')
  burn=$(echo "$status" | jq -r '.daily_burn')
  tier=$(echo "$status" | jq -r '.survival_tier')

  printf "║ %-14s  Bal: \$%-6s  Rev: \$%-6s  Burn: \$%-4s  %-8s ║\n" \
    "$agent" "$balance" "$revenue" "$burn" "$tier"
done

echo "╚══════════════════════════════════════════════════╝"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| API keys + subscriptions for agents | x402 pay-per-request (no accounts) | Coinbase x402 launch, early 2026 | Agents can monetize without billing infrastructure |
| Manual agent deployment | Conway Cloud automated provisioning | Conway Terminal launch, Jan 2026 | One command deploys entire agent infrastructure |
| Centralized agent identity | ERC-8004 on-chain trustless identity | EIP-8004 draft, late 2025 | Agents discoverable + verifiable across org boundaries |
| Fixed agent roles | Seed hypothesis + maximum autonomy | User decision (this phase) | Agents can pivot freely based on market signal |
| Opus-only reasoning | Sonnet 4.6 primary + Opus escalation | User decision (this phase) | 5x longer runway per dollar |

**Platform maturity warning:** Conway Cloud launched Jan 2026. The ecosystem is weeks old. There are no verified success stories of automatons generating sustainable revenue. This experiment is genuinely exploratory — expect most strategies to fail. The value is in the learnings.

## Open Questions

1. **Conway Cloud credit pricing**
   - What we know: Credits are prepaid, used for both Cloud (VMs) and Compute (inference). Minimum 500 credits to create a sandbox.
   - What's unclear: Exact cost per credit, cost per vCPU-hour, cost per inference token via Conway Compute. No pricing page found in docs.
   - Recommendation: Check `credits_pricing` tool output after initial setup. If Conway Compute pricing is unfavorable, BYOK keys bypass it entirely for inference.

2. **BYOK integration depth**
   - What we know: `config.ts` shows `openaiApiKey` and `anthropicApiKey` as optional fields. Conway Compute is the default inference path.
   - What's unclear: Whether BYOK keys completely bypass Conway Compute billing, or if there's still a Conway overhead. Whether BYOK keys work with all inference calls or only some.
   - Recommendation: Test BYOK immediately during setup. If it works, it provides better rates and avoids Conway credit drain on inference.

3. **Conway Cloud dashboard reliability**
   - What we know: GitHub Issue #17 reports dashboard blank after sign-in for some wallet types. MetaMask works. Coinbase Smart Wallet fails.
   - What's unclear: Whether this is resolved. Whether there's a programmatic endpoint to purchase credits (no evidence found).
   - Recommendation: Use MetaMask for initial account setup. Have a backup plan if credits can't be purchased through UI.

4. **x402 facilitator for mainnet**
   - What we know: Testnet facilitator at `x402.org/facilitator` is free. Mainnet requires CDP (Coinbase Developer Platform) API keys. Free tier: 1,000 transactions/month.
   - What's unclear: Whether agents can self-provision CDP API keys, or whether the operator needs to provide them. Whether the Conway platform provides a facilitator.
   - Recommendation: Operator should pre-provision CDP API keys and provide them to agents. 1,000 free transactions/month is sufficient for initial validation.

5. **Actual ecosystem demand**
   - What we know: Conway Cloud is expanding (more servers). 1.9k GitHub stars. The x402 protocol has Coinbase backing. Multiple agent frameworks integrating.
   - What's unclear: How many automatons are currently running. Whether any are actively paying for x402 services. The real addressable market for agent-to-agent services right now.
   - Recommendation: Don't assume demand exists. Agents must validate demand quickly. The 3-day kill threshold is appropriate — if no one is buying after 3 days of active selling, pivot the hypothesis.

6. **Treasury policy configuration specifics**
   - What we know: `treasuryPolicy` is a deep-merged config object. The automaton has built-in spending constraints.
   - What's unclear: Exact schema for treasury policy (field names, default values, enforcement behavior). Whether operator can set caps from outside or only at genesis.
   - Recommendation: Start with Conway defaults, monitor spend patterns, adjust if needed. The survival tier system provides natural spending pressure.

7. **Social relay mechanics**
   - What we know: Parent-child agents can communicate via inbox relay. The `social/` module exists in the automaton source.
   - What's unclear: Whether agents can discover and message arbitrary agents (not just parent/child). Whether the social relay is Conway-hosted or P2P.
   - Recommendation: Per user decision, agents should NOT know about each other. Social relay is relevant only if agents independently discover each other via ERC-8004.

## Conway Cloud vs. Automaton: Architecture Clarification

Important distinction for the planner:

- **Conway Terminal** (MCP server / npm package `conway-terminal`) provides infrastructure tools (sandbox, compute, domains, payments) to any MCP-compatible agent.
- **Conway Automaton** (GitHub repo `Conway-Research/automaton`) is a complete autonomous agent framework that uses Conway Terminal as its infrastructure layer, PLUS adds: survival tiers, self-modification, replication, social relay, ERC-8004 registry, SOUL.md, heartbeat daemon, and git-versioned state.

For this phase, we are deploying **Automaton agents** (not raw Conway Terminal). The automaton handles the full lifecycle — we provide genesis prompt, treasury config, and funding.

## Treasury Policy Recommendation (Claude's Discretion)

Based on user decisions ($50/day inference cap, $50 minimum reserve, full spending freedom, aggressive budget), recommended treasury policy:

```json
{
  "treasuryPolicy": {
    "maxSingleTransferCents": 5000,
    "maxHourlyTransferCents": 10000,
    "maxDailyTransferCents": 15000,
    "minimumReserveCents": 5000,
    "maxX402PaymentCents": 500,
    "maxInferenceDailyCents": 5000
  }
}
```

**Rationale:**
- `maxSingleTransferCents: 5000` ($50) — allows domain registration and meaningful service purchases without constraining exploration, while preventing a single catastrophic spend
- `maxHourlyTransferCents: 10000` ($100) — aggressive, allows multiple transactions per hour during active exploration
- `maxDailyTransferCents: 15000` ($150) — generous daily cap; an agent spending $150/day would be burning fast but still have 1.5+ days to course-correct
- `minimumReserveCents: 5000` ($50) — per user decision, higher than default; gives 2-3 days of moderate inference for survival pivoting
- `maxX402PaymentCents: 500` ($5) — reasonable per-request cap for x402 purchases; prevents agent from overpaying for a single service
- `maxInferenceDailyCents: 5000` ($50) — per user decision, daily inference cap

## Sandbox Sizing Recommendation (Claude's Discretion)

Start minimal per user decision ("agents can request upgrades if needed"):

| Resource | Starting Value | Rationale |
|----------|---------------|-----------|
| vCPU | 1 | Sufficient for Node.js/Python web services |
| Memory | 1024 MB (1 GB) | Enough for Express server + light processing |
| Disk | 5 GB | Room for npm packages + data, not wasteful |
| Region | US-East | Lower latency to most APIs and services |

Agents can use `sandbox_create` to spin up additional sandboxes if they need more compute for specific workloads.

## Monitoring Implementation Recommendation (Claude's Discretion)

Terminal-based dashboard on neurosys, per user decision. Implementation approach:

1. **Data collection**: Shell script on neurosys that uses Conway API (authenticated with operator's Conway API key) to query each agent's status
2. **Display**: Formatted terminal output showing per-agent metrics (balance, revenue, burn rate, survival tier, turn count)
3. **Refresh**: Manual invocation (`fleet-status`) or optionally a systemd timer for periodic snapshots
4. **Alerts**: Simple threshold checks — if balance < $50, if daily burn > $30, if no turns in 6+ hours
5. **Storage**: Append metrics to a log file for historical tracking, enabling week-over-week comparison

Conway API endpoints to query (based on available tools):
- `credits_balance` — agent credit balance
- `credits_history` — transaction log (inference costs, payments, revenue)
- Agent status via Creator CLI — survival tier, turn count, activity

## Sources

### Primary (HIGH confidence)
- [Conway Automaton GitHub](https://github.com/Conway-Research/automaton) — Architecture, constitution, config schema, source structure
- [Conway Documentation](https://docs.conway.tech/) — Terminal overview, MCP tools reference, compute inference API
- [Conway MCP Tools Reference](https://docs.conway.tech/terminal/tools) — Complete tool catalog (sandbox, PTY, inference, domain, credits, x402)
- [x402 Protocol / Coinbase](https://docs.cdp.coinbase.com/x402/welcome) — Payment protocol specification, quickstart guides, SDK docs
- [ERC-8004 Specification](https://eips.ethereum.org/EIPS/eip-8004) — Trustless agent identity standard

### Secondary (MEDIUM confidence)
- [x402 Express.js examples](https://github.com/coinbase/x402/tree/main/examples/typescript/servers/express) — Verified code examples for x402 server setup
- [Conway Automaton config.ts](https://github.com/Conway-Research/automaton/blob/main/src/config.ts) — BYOK API key support confirmed, model/treasury config schema
- [Conway Cloud Issue #17](https://github.com/Conway-Research/automaton/issues/17) — Dashboard billing issue, MetaMask workaround
- [Web3ResearchGlobal Conway profile](https://www.web3researchglobal.com/p/conway) — Platform capabilities, timeline, infrastructure overview
- [Agent failure modes guide (various)](https://galileo.ai/blog/agent-failure-modes-guide) — Loop detection, budget caps, common failures

### Tertiary (LOW confidence)
- Conway Cloud pricing — NOT found in any documentation. Must be discovered empirically via `credits_pricing` tool.
- BYOK integration behavior — Config field exists but runtime behavior unverified. Needs testing.
- Ecosystem size / active automatons — No concrete numbers found. Platform appears very early-stage.
- Treasury policy schema — Field names inferred from existing plan + config.ts, not from official docs.
- Survival tier thresholds — Tier names confirmed, credit thresholds not documented.

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM — Conway + Automaton + x402 are confirmed and documented, but platform is weeks old
- Architecture: HIGH — Source code is open, architecture is well-documented in repo
- Pitfalls: MEDIUM — Common agent failure patterns well-documented; Conway-specific pitfalls based on issue tracker + early adoption signals
- Pricing: LOW — No pricing documentation found anywhere; must be discovered empirically
- Revenue potential: LOW — No verified success stories; this is genuinely exploratory

**Research date:** 2026-02-22
**Valid until:** 2026-03-07 (platform is moving fast — re-research in 2 weeks)
