# 99-02 Summary: @decision Annotation Consolidation

## What was done

Removed 40+ redundant `@decision` annotations across 11 files. Each annotation was
either restating what the code already expressed, documenting a historical migration
that is no longer actionable, or using a duplicate/unnamed ID.

## Files modified

| File | Removed | Kept |
|------|---------|------|
| `modules/networking.nix` | NET-02, NET-03, NET-04, NET-06, NET-08, NET-10, NET-11, NET-12, NET-13, NET-15, NET-16 | NET-01, NET-07, NET-122-01, NET-14 |
| `extras/syncthing.nix` | SVC-02, SVC-03, SYNC-84-01, SEC47-21 + @rationale | SYNC-116-01, SYNC-93-01, SYNC-125-01 |
| `extras/dashboard.nix` | DASH-01 through DASH-05 (replaced with 3-line summary) | -- |
| `extras/restic.nix` | RESTIC-02 through RESTIC-06 | RESTIC-01, SEC-116-04 |
| `extras/cost-tracker.nix` | COST-01 through COST-04 | COST-05, SEC-116-05 |
| `extras/scripts/deploy.sh` | 6 unnamed/redundant header annotations + DEPLOY-01 | DEPLOY-02, DEPLOY-03, DEPLOY-04, DEPLOY-05, DEPLOY-114-01 |
| `modules/impermanence.nix` | IMP-04, IMP-138-01 | IMP-01, IMP-05, IMP-06 |
| `extras/home/cass.nix` | Duplicate SVC-03 | -- |
| `scripts/run-tests.sh` | TEST-48-01 | -- |
| `extras/codex.nix` | SEC-127-EXTRAS-01, EXTRAS-PRUNE-01 | -- |
| `extras/pi.nix` | SEC-127-EXTRAS-01, EXTRAS-PRUNE-01 | -- |
| `modules/agent-compute.nix` | Unnamed @decision (package names) | SANDBOX-139-01 |

## Validation

`nix flake check` passes (all eval assertions, shellcheck, unit tests).
No code lines were modified -- only comment lines.
