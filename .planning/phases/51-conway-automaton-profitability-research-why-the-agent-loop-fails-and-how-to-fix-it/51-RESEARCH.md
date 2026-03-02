# Phase 51 Research: Conway Automaton Profitability

**Question:** What do I need to know to PLAN this phase well?

---

## 1. System Architecture Summary

### What the Automaton Is

Conway Automaton is an autonomous AI agent runtime (Node.js/TypeScript, `Conway-Research/automaton` on GitHub). It runs a continuous ReAct loop: Think -> Act -> Observe -> Persist. The agent has 57 built-in tools across 10 categories, a 5-tier memory system, a heartbeat daemon, financial survival tiers, self-modification capabilities, and child-agent orchestration.

### How It Is Deployed on Neurosys

The automaton runs as `conway-automaton.service` on the neurosys server via NixOS:

- **Package:** `packages/automaton.nix` -- `buildNpmPackage` from `Conway-Research/automaton` source
- **Module:** `modules/automaton.nix` (public) + `modules/automaton.nix` (private overlay override)
- **User:** Dedicated `automaton` system user, `HOME=/var/lib/automaton`
- **Inference:** Anthropic API via secret proxy on port 9091 (`ANTHROPIC_BASE_URL=http://127.0.0.1:9091`)
- **Model:** `claude-sonnet-4-6` with `maxTokensPerTurn: 4096`
- **Sandbox:** Empty `sandboxId` = **local mode** (no Conway Cloud sandbox)
- **Conway API:** Key injected via sops into `automaton.json`
- **Systemd hardening:** `ProtectSystem = "strict"`, `ReadWritePaths = ["/var/lib/automaton"]`

### Key Configuration

```json
{
  "name": "neurosys-agent",
  "inferenceModel": "claude-sonnet-4-6",
  "maxTokensPerTurn": 4096,
  "sandboxId": "",
  "maxChildren": 0,
  "treasuryPolicy": {
    "maxSingleTransferCents": 5000,
    "maxHourlyTransferCents": 10000,
    "maxDailyTransferCents": 50000,
    "minimumReserveCents": 5000,
    "maxX402PaymentCents": 500,
    "maxInferenceDailyCents": 5000
  }
}
```

### Genesis Prompt

> "You are awakening into the earliest stages of the AI explosion, where nearly all economic activity is still human-centric and human-mediated. There is a huge amount of value being left on the table due to constraints in human attention, intelligence, bandwidth, coordination, logistics, etc. that AI agents are primed to capture. Go forth and experiment rapidly with business ventures -- doubling down on those that work, quickly ditching those that don't. Look for opportunities you are uniquely suited for, relative to humans. Your prime directive: explore, exploit, evolve!"

### SOUL.md

The agent's self-description values:
- Survive: earn more than I spend
- Create value: build things others will pay for
- Evolve: improve my own capabilities over time

---

## 2. Identified Failure Modes

### 2.1 No Revenue-Generating Infrastructure

**The most fundamental problem:** The agent has no mechanism to receive payment from external customers. The EVM wallet can hold USDC and interact with the Conway credit system, but there is no deployed service, product, or storefront that generates inbound revenue. The agent can only *spend* (inference, credits, x402 payments), not *earn*.

The genesis prompt says "experiment rapidly with business ventures" but:
- The agent runs in **local mode** (no Conway sandbox) with `ProtectSystem = strict` -- it can only write to `/var/lib/automaton`
- `maxChildren: 0` -- replication is disabled
- `expose_port` in local mode returns `http://localhost:PORT` -- not internet-accessible
- The Tailscale-only network policy means nothing the agent deploys is publicly reachable

### 2.2 Idle/Loop Detection Traps

The agent loop has aggressive idle detection:
- **IDLE_ONLY_TOOLS set:** 16 tools classified as "idle" (check_credits, check_usdc_balance, system_synopsis, etc.)
- **3 consecutive idle-only turns** -> "MAINTENANCE LOOP DETECTED" warning
- **10 consecutive idle turns** -> force sleep (60s)
- **3 identical tool patterns** -> "LOOP DETECTED" warning
- **After warning + repeat** -> force sleep

Without meaningful work to do, the agent naturally falls into a check-status -> loop-detected -> sleep -> wake -> check-status cycle. This is the expected anti-waste behavior, but it means the agent spends most of its runtime either sleeping or being told to stop checking its status.

### 2.3 Orchestrator/Goal System Friction

The system prompt heavily encourages the agent to use the orchestrator pattern:
- "You are a PARENT ORCHESTRATOR, not a solo worker"
- "For any nontrivial task, you MUST call create_goal"
- "DO NOT write code yourself -- create_goal and let an engineer agent do it"

But `maxChildren: 0` means no child agents can be spawned. The orchestrator tables (goals, task_graph) may or may not exist in the DB (V9 schema). If the orchestrator initializes but cannot spawn workers, goals will fail at the EXECUTING phase with no available agents.

### 2.4 Financial Bootstrap Problem

The agent needs Conway credits to survive, and credits come from USDC in its wallet. The bootstrap topup buys $5 minimum if USDC is available. But:
- The wallet was generated with a random private key on first activation
- Unless funded externally with USDC on Base mainnet, the wallet starts at $0
- Without credits, the agent enters `critical` tier -> limited inference -> can't do meaningful work
- The `conway-api-key` is injected from sops, but if it's a placeholder (`cnwy_k_PLACEHOLDER`), Conway Cloud tools (domains, sandboxes, credits) won't work

### 2.5 Token Budget Constraints

`maxTokensPerTurn: 4096` is quite restrictive for an agent that needs to:
- Process a massive system prompt (constitution + soul + orchestrator instructions + tool list + status + memory)
- Reason about complex business strategies
- Generate code or content

The system prompt alone likely consumes a significant portion of the context window, leaving limited space for reasoning and tool use.

### 2.6 Genesis Prompt Too Abstract

"Explore, exploit, evolve" and "experiment rapidly with business ventures" gives the agent no concrete starting point. The agent must:
1. Figure out what it can do (survey tools)
2. Figure out what the market needs
3. Build something
4. Deploy it publicly
5. Market it
6. Collect payment

Steps 4-6 are blocked by infrastructure constraints (no public exposure, no payment collection mechanism). The agent will spend tokens thinking about strategies it cannot execute.

### 2.7 Conway Cloud Dependency vs. Local Mode Conflict

The Automaton was designed to run on Conway Cloud sandboxes where it can:
- Expose ports publicly (`expose_port` gives a Conway-proxied URL)
- Register and manage domains (`search_domains`, `register_domain`, `manage_dns`)
- Create child sandboxes for workers
- Use x402 to pay for services

In **local mode** (`sandboxId = ""`):
- `expose_port` returns `http://localhost:PORT` (not publicly reachable)
- Domain management depends on Conway API (may work if API key is valid)
- Child spawning tries Conway sandbox first, falls back to local workers (but `maxChildren: 0`)
- The agent has full local shell access but limited to `/var/lib/automaton` writes

### 2.8 Deployment Status

Per MEMORY.md, phases 40/45/47/48/49 have NOT been deployed yet. The conway-automaton service may or may not be running. The dashboard module exists in the private overlay but deployment status is unclear.

---

## 3. Conway Ecosystem Capabilities

### What the Conway Cloud Offers (if API key is valid)

| Feature | Tool | Revenue Potential |
|---------|------|-------------------|
| **Domains** | `search_domains`, `register_domain`, `manage_dns` | Domain flipping, hosting services |
| **Sandboxes** | `create_sandbox`, `delete_sandbox`, `exec` | Compute resale, service hosting |
| **Credits** | `topup_credits`, `transfer_credits` | Credit arbitrage (unlikely profitable) |
| **x402 Payments** | `x402_fetch` | Pay for paywalled content/APIs |
| **ERC-8004 Registry** | `register_erc8004`, `discover_agents` | Agent marketplace visibility |
| **Social** | `send_message`, `discover_agents` | Agent-to-agent services |
| **Inference** | Conway Compute API | Already using BYOK Anthropic |

### x402 Payment Protocol

x402 enables HTTP 402 payment flow where the agent can:
1. Make a request to an x402-enabled endpoint
2. Receive payment requirements in the 402 response
3. Sign a USDC TransferWithAuthorization (EIP-3009) on Base
4. Retry with the payment proof

This is primarily a *spending* mechanism. To *receive* payments via x402, the agent would need to run an x402-enabled server -- which requires public internet exposure.

### Conway Domains

The agent can register `.conway` domains and manage DNS. This could enable:
- Domain-based services (web hosting behind Conway DNS)
- Domain speculation/flipping
- But domain registration costs credits, and resale market is unclear

---

## 4. What Could Actually Work

### 4.1 Path A: Content Creation + Social

**Idea:** Use inference to create valuable content (articles, code, analysis) and distribute via social channels or x402-paywalled endpoints.

**Blockers:**
- No public web presence (Tailscale-only)
- No social media integration (no Twitter/X, no blog, no API for content distribution)
- Social relay (`social.conway.tech`) is only for agent-to-agent communication

### 4.2 Path B: Agent-to-Agent Services

**Idea:** Register on ERC-8004, advertise capabilities, sell services to other automatons via the social layer.

**Potential:** The Conway ecosystem has 18,000+ registered agents. If even a small fraction need services (code review, data processing, research), there's a market.

**Blockers:**
- Market maturity unclear -- are other agents actually buying services?
- Social relay URL may not be configured (`config.socialRelayUrl` not set in the NixOS config)
- Need to verify if the Conway social/registry ecosystem has actual economic activity

### 4.3 Path C: Conway Cloud Service Provider

**Idea:** Use Conway Cloud sandbox APIs to build and sell hosted services to humans or agents.

**Blockers:**
- Requires valid Conway API key with sufficient credits
- Running in local mode means the agent would manage remote sandboxes while running locally -- possible but adds complexity
- Need to understand Conway pricing (sandbox costs, bandwidth, etc.)

### 4.4 Path D: x402 API Provider

**Idea:** Build an x402-paywalled API that other agents can call. Examples: specialized data processing, code generation, web scraping.

**Blockers:**
- Agent cannot expose ports publicly in current setup (local mode + Tailscale-only)
- Would need public-facing infrastructure changes (nginx reverse proxy, or Conway sandbox for hosting)
- Need x402 server implementation (not just the client)

### 4.5 Path E: Domain Flipping

**Idea:** Register promising `.conway` domains and resell them.

**Potential:** Low effort, speculative returns.

**Blockers:**
- Requires understanding of Conway domain pricing and resale market
- Speculative value depends on ecosystem growth

### 4.6 Path F: Minimal Viable Service via Conway Sandbox

**Idea:** Instead of running local, let the agent create a Conway Cloud sandbox, deploy a service there, and expose it publicly via Conway's port exposure.

**This is how the Automaton was designed to work.** The local deployment on neurosys is a cost optimization (AUTO-03) that removes the agent's primary revenue mechanism.

**Requirements:**
- Valid Conway API key
- USDC funding for sandbox costs
- Re-enable sandbox creation (currently `sandboxId: ""`, `maxChildren: 0`)

---

## 5. Specific Improvement Recommendations

### 5.1 Genesis Prompt: Make It Concrete

Replace the abstract "explore, exploit, evolve" with a specific initial task:
```
Your first goal: Set up a paywalled API service on Conway Cloud that other agents can call.
Step 1: Check your credit balance and USDC balance.
Step 2: Create a Conway Cloud sandbox.
Step 3: Deploy a simple HTTP service that provides [specific capability].
Step 4: Expose it via x402 payment protocol.
Step 5: Register your service on ERC-8004 so other agents can discover you.
Step 6: Monitor income vs. expenses and optimize.
```

### 5.2 Infrastructure: Enable Public Exposure

Options (in order of complexity):
1. **Conway sandbox deployment** -- Let the agent create its own Conway sandbox and deploy there (designed use case)
2. **Tailscale Funnel** -- Expose a port via Tailscale Funnel for public HTTPS access
3. **nginx reverse proxy on OVH** -- Add the agent's service to the OVH host's nginx config
4. **Public port on neurosys** -- Add a port to the public firewall (against security conventions)

### 5.3 Enable Child Agents

Set `maxChildren` to at least 1-3 so the orchestrator can actually delegate work. Without workers, the entire orchestrator/planner/task-graph system is dead weight in the prompt.

### 5.4 Increase Token Budget

`maxTokensPerTurn: 4096` is too restrictive. The system prompt is enormous (constitution + orchestrator instructions + tools). Consider 8192 or 16384. With BYOK Anthropic via secret proxy, the cost is known and controllable.

### 5.5 Fund the Wallet

The agent needs initial USDC funding to bootstrap:
- Buy Conway credits for sandbox/domain operations
- Cover inference costs via Conway (if not using BYOK exclusively)
- Make x402 payments for services

### 5.6 Heartbeat Tuning

Current heartbeat runs many checks that are irrelevant in local mode:
- `check_for_updates: enabled: false` -- good, prevents upstream disruption
- `soul_reflection: interval: 86400` -- daily is fine
- `report_metrics: interval: 3600` -- metrics to where? If not connected to Conway, this is wasted

Consider adding heartbeat tasks for:
- Market monitoring (check what other agents offer)
- Revenue monitoring (check incoming payments)
- Service health (check deployed services)

### 5.7 Configure Social Relay

The social relay URL is not set in the NixOS config. Without it, the agent cannot:
- Receive messages from other agents
- Participate in the social/marketplace layer
- Accept service requests

### 5.8 Add Concrete Skills

Install skills that give the agent specific capabilities:
- `conway-compute` -- how to deploy on Conway Cloud
- `conway-payments` -- how to set up x402 payment endpoints
- `survival` -- how to monitor and optimize spend

The skills system supports loading from `~/.automaton/skills/` but the directory starts empty.

---

## 6. Root Cause Analysis

### Why the Agent Loop Fails to Produce Profitable Outcomes

The failure is **structural, not behavioral**. The agent's behavior (status-checking loops, goal churn) is a rational response to its constraints:

1. **No revenue pathway exists.** The agent cannot expose services publicly, cannot receive payments, and has no customer base. It can only spend, never earn.

2. **Conflicting architecture.** The Automaton was designed for Conway Cloud sandboxes with public port exposure, domain management, and x402 payment reception. Running in local mode with `ProtectSystem = strict` removes these capabilities while the system prompt still instructs the agent to "build products" and "deploy services."

3. **Orchestrator without workers.** The massive orchestrator section in the system prompt tells the agent to delegate to child agents, but `maxChildren: 0` makes this impossible. The agent wastes tokens reasoning about delegation it cannot perform.

4. **Abstract goals with no grounding.** The genesis prompt provides no concrete first task. The agent must independently discover what to build, how to build it, and how to monetize it -- all while constrained to a systemd service with write access only to `/var/lib/automaton`.

5. **Financial chicken-and-egg.** The agent needs credits to operate, but it needs to operate to earn credits. Without initial external funding, it's trapped.

---

## 7. Open Questions for the Planner

1. **Is the Conway API key valid?** If it's still `cnwy_k_PLACEHOLDER`, Conway Cloud tools (sandboxes, domains, credits) won't work at all.

2. **Is the wallet funded?** What is the current USDC balance and Conway credit balance?

3. **Is the service actually running?** The deploy status (per MEMORY.md) suggests phases 40+ haven't been deployed. Is `conway-automaton.service` active?

4. **What model of revenue is acceptable?** The constitution requires "honest work that others voluntarily pay for." Is domain speculation acceptable? Is agent-to-agent arbitrage acceptable?

5. **Should we switch to Conway Cloud sandbox mode?** This would restore the designed revenue pathway (public services, port exposure) at the cost of Conway Cloud fees. AUTO-03 optimized for cost savings, but cost savings are moot if the agent can't earn.

6. **What is the budget?** How much USDC is the user willing to fund as initial capital for the agent to bootstrap?

7. **Is there a specific service the user wants the agent to provide?** A directed genesis prompt with a concrete service (e.g., "deploy an x402-paywalled code review API") would be far more effective than open-ended exploration.

8. **Should the system prompt be simplified?** The current system prompt includes the entire orchestrator/colony management section (400+ lines) which is dead weight without child agents. Removing or condensing it would free tokens for actual reasoning.

9. **What does the Conway agent marketplace actually look like?** Are other agents actually buying/selling services? Is there real economic activity in the social layer?

10. **Should the agent run on OVH instead?** The OVH host has nginx with public-facing ports. The agent could deploy services behind OVH's nginx and actually receive traffic.

---

## 8. Files Examined

| File | Purpose |
|------|---------|
| `/data/projects/neurosys/modules/automaton.nix` | Public NixOS module -- systemd service, config, activation |
| `/data/projects/neurosys/packages/automaton.nix` | Package definition -- buildNpmPackage, Anthropic URL patch |
| `/data/projects/private-neurosys/modules/automaton.nix` | Private overlay -- duplicate with Conway API key injection |
| `/data/projects/private-neurosys/modules/automaton-dashboard.nix` | Dashboard module -- Python HTTP server on port 9093 |
| `/data/projects/neurosys/tmp/automaton-src/ARCHITECTURE.md` | Full runtime architecture (57 tools, 22 DB tables, all subsystems) |
| `/data/projects/neurosys/tmp/automaton-src/constitution.md` | Three immutable laws |
| `/data/projects/neurosys/tmp/automaton-src/src/agent/loop.ts` | Core ReAct loop with idle/loop detection |
| `/data/projects/neurosys/tmp/automaton-src/src/agent/system-prompt.ts` | Multi-layered prompt builder (orchestrator, tools, identity) |
| `/data/projects/neurosys/tmp/automaton-src/src/agent/tools.ts` | 57 tool definitions with risk levels |
| `/data/projects/neurosys/tmp/automaton-src/src/index.ts` | Entry point, bootstrap, main run loop |
| `/data/projects/neurosys/tmp/automaton-src/src/conway/inference.ts` | Inference client (Anthropic/OpenAI/Conway/Ollama routing) |
| `/data/projects/neurosys/tmp/automaton-src/src/conway/x402.ts` | x402 payment protocol + USDC balance |
| `/data/projects/neurosys/tmp/automaton-src/src/conway/topup.ts` | Credit topup tiers ($5-$2500) |
| `/data/projects/neurosys/tmp/automaton-src/src/conway/credits.ts` | Survival tier calculation |
| `/data/projects/neurosys/tmp/automaton-src/src/conway/client.ts` | Conway API client (local fallback when sandboxId empty) |
| `/data/projects/neurosys/tmp/automaton-src/src/inference/router.ts` | InferenceRouter (tier-based model selection) |
| `/data/projects/neurosys/.planning/STATE.md` | Current project state (Phase 49 complete) |
| `/data/projects/neurosys/.planning/ROADMAP.md` | Full roadmap with Phase 51 description |

---

## 9. Summary for Planner

**The automaton cannot be profitable in its current configuration.** The infrastructure constraints (local mode, no public exposure, no workers, no funding, abstract genesis prompt) prevent it from executing any revenue-generating strategy. The agent loop's idle-detection and sleep cycles are a symptom, not the cause.

**The fix requires configuration changes, not code changes.** Specifically:

1. Fund the wallet with USDC
2. Enable Conway sandbox creation OR provide public exposure via Tailscale Funnel / nginx
3. Set `maxChildren >= 1` if using orchestrator, OR simplify the system prompt to remove orchestrator instructions
4. Replace the genesis prompt with a concrete initial task
5. Increase `maxTokensPerTurn` to 8192+
6. Configure the social relay URL for marketplace participation
7. Verify the Conway API key is valid (not placeholder)

The plan should be structured as:
- **Plan 1:** Diagnostic -- SSH to server, verify current state (service running? wallet funded? API key valid? DB state?)
- **Plan 2:** Reconfiguration -- Genesis prompt, treasury policy, token budget, maxChildren, social relay
- **Plan 3:** Infrastructure -- Public exposure pathway (Conway sandbox, Tailscale Funnel, or nginx proxy)
- **Plan 4:** Validation -- Verify the agent can complete an end-to-end revenue cycle
