# Execution Summary: Plan 47-03 — Secret Scoping + Attack Surface Minimization

## Result: PASS

## Changes Made

| File | Change |
|------|--------|
| `home/bash.nix` | Replaced eager export of all 7 API keys with on-demand `load-api-keys()` shell function (SEC47-34). Only `GH_TOKEN` auto-loaded (needed for gh CLI). Other keys loaded explicitly when needed. |
| `modules/base.nix` | Removed `wget` from `environment.systemPackages` (SEC47-18). Added inline `@decision` comments for `nodejs` (SEC47-19) and `cachix` (SEC47-20). |
| `modules/syncthing.nix` | Changed `insecureSkipHostcheck` from `true` to `false` (SEC47-21). Docker bridge comment was outdated — only localhost access via homepage siteMonitor. |
| `modules/agentd.nix` | Added `@decision SEC47-15` comment documenting deliberate cross-project read access via `--ro-bind /data/projects`. |
| `CLAUDE.md` | Updated Accepted Risks section: SEC3/SEC9 now "PARTIALLY ADDRESSED in Phase 47-02". Added SEC47-13, SEC47-15, SEC47-16 as new accepted risks. |

## Commits

- `70e77a9` feat(47-03): secret scoping + attack surface minimization

## Verification

- `nix flake check`: PASS (both neurosys and ovh configurations)
- All `must_haves` satisfied:
  1. API keys in bash.nix loaded on-demand (only GH_TOKEN auto-exported)
  2. `wget` removed from system packages
  3. Accepted risks updated with Phase 47 findings
  4. No weakening of existing security controls

## Decisions

- **SEC47-34**: GH_TOKEN stays auto-loaded (gh CLI dependency). All other keys on-demand.
- **SEC47-21**: Syncthing hostcheck re-enabled. Docker bridge access was never actually used.
- **SEC47-15**: Cross-project read access documented as deliberate tradeoff.

## Skipped (Private Overlay)

- **47-03-F**: Homepage allowedHosts tightening — private overlay change
- **47-03-G**: Sops template mode audit — private overlay change
