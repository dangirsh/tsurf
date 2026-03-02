# Plan 51-02 Summary: Reconfiguration — Genesis Prompt, Token Budget, Agent Mode

## Status: COMPLETE

## What Was Done

Updated `modules/automaton.nix` and patched the live server configuration to address all root causes.

### Changes Made

| Setting | Before | After | Rationale |
|---------|--------|-------|-----------|
| genesisPrompt | "explore, exploit, evolve" (abstract) | 8-step plan: check credits → survey marketplace → build service → deploy to sandbox | Concrete actionable steps |
| maxTokensPerTurn | 4096 | 16384 | System prompt consumed most of 4096 budget |
| maxChildren | 0 | 2 | Enable orchestrator to delegate to worker agents |
| socialRelayUrl | not set | `https://social.conway.tech` | Marketplace participation |
| SOUL.md | Generic | Grounded in actual constraints (local exec, no USDC, sandbox for public services) | Agent knows its real capabilities |
| Heartbeat | 300s intervals | 600s intervals | Less wasteful status checking |
| ERC-8004 registration | Step 2 in prompt | Explicitly skipped (requires ETH) | Wallet has no ETH for gas |

### Live Server Fixes

1. Stopped service
2. Cleared stuck goals (SQL UPDATE to cancelled)
3. Cleared dead workers from children table
4. Reset orchestrator KV state (was pointing to old cancelled goal)
5. Cleared turn history (fresh context for agent)
6. Patched automaton.json with new config values (atomic jq pipeline)
7. Updated SOUL.md
8. Restarted service

### Verification

After restart, the agent:
- Checked credits ($416+ — high tier)
- Created goal: "Launch a paid micro-API on Conway: URL-to-Markdown + readability extraction"
- Spawned local worker (Conway sandbox creation returned 403)
- Worker actively building: 17+ turns, writing Python/FastAPI service
- No backoff loop — productive multi-turn execution

### Commit

`50881c8` on branch `gsd/phase-51-automaton-profitability` — `nix flake check` passes.

## Self-Check: PASSED

- [x] Genesis prompt is concrete and actionable
- [x] maxTokensPerTurn increased to 16384
- [x] maxChildren set to 2
- [x] Social relay configured
- [x] SOUL.md reflects real constraints
- [x] Agent no longer stuck in backoff loop
- [x] Agent actively building a service

## Time

~25 minutes (config changes + live patching + monitoring)
