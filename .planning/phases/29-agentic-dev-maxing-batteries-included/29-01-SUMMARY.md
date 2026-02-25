---
phase: 29-agentic-dev-maxing-batteries-included
plan: 01
subsystem: infra
tags: [nixos, agent-spawn, bubblewrap, sops-nix, api-keys, opencode, gemini-cli, pi]
key-decisions:
  - "Both GOOGLE_API_KEY and GEMINI_API_KEY exported from same google-api-key secret"
  - ".config/opencode ro-bound, .local/share/opencode rw-bound (session storage)"
duration: 13min
completed: 2026-02-25
---

# Phase 29 Plan 01: Batteries-Included Agentic Dev Platform Summary

**opencode, gemini-cli, and pi added to systemPackages; agent-spawn extended to sandbox all three with Google/xAI/OpenRouter API key injection and config dir bind mounts; four new API key exports in bash.nix**

## Performance
- **Duration:** 13 min
- **Tasks:** 7 completed (6 auto + 1 human)
- **Files modified:** 4

## Accomplishments
- Three new agent CLIs (opencode, gemini-cli, pi) installed as system packages
- agent-spawn accepts opencode|gemini|pi with bubblewrap isolation and correct key injection
- Google, xAI, OpenRouter API keys encrypted in sops and exported at shell startup
- Both GOOGLE_API_KEY and GEMINI_API_KEY exported from single google-api-key secret

## Task Commits
1. **Task 1: sops declarations** - `2139020` (feat)
2. **Task 2: secrets encrypted** - human (no commit)
3. **Task 3: bash.nix exports** - `af0c1f6` (feat)
4. **Tasks 4+5: agent-compute.nix** - `cb01099` (feat)
5. **Task 6: validation** - nix flake check passed
6. **Task 7: secrets/neurosys.yaml** - `e61339b` (feat, marker commit)

## Files Created/Modified
- `modules/secrets.nix` - Three new sops.secrets declarations
- `secrets/neurosys.yaml` - Three new encrypted API key entries
- `home/bash.nix` - GOOGLE/GEMINI/XAI/OPENROUTER exports
- `modules/agent-compute.nix` - New packages + extended agent-spawn

## Decisions Made
- GEMINI_API_KEY aliases GOOGLE_API_KEY (same secret, two env names for different agents)
- opencode config dir is ro (config only); session dirs are rw

## Deviations from Plan
- [Rule 3 - Blocking] `nix flake check` failed with `attribute 'pi' missing` for `pkgs.pi`; fixed by using `pkgs.llm-agents.pi` in `modules/agent-compute.nix`, verified by re-running `nix flake check` to pass, committed in `377ed17`.
- Task 7 file content had already been committed during blocker-fix commit because `secrets/neurosys.yaml` remained staged from Task 6 prep; recorded Task 7 explicitly with marker commit `e61339b`.

## Issues Encountered
- Staged-index spillover from Task 6 command included `secrets/neurosys.yaml` in blocker-fix commit; no content loss, but task commit ordering required a marker commit.

## Next Phase Readiness
Ready for Task 8 (human): deploy to neurosys and smoke-test all three new agents.

---
*Phase: 29-agentic-dev-maxing-batteries-included*
*Completed: 2026-02-25*
