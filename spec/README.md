# tsurf Technical Specification

Comprehensive specification of core features, security claims, and behavioral expectations.
Each claim has a unique ID for cross-referencing with test cases.

## Spec Files

| File | Scope | Claim Prefix |
|------|-------|-------------|
| [security-model.md](security-model.md) | Core security invariants, threat model, privilege separation, supply chain | `SEC-` |
| [sandbox.md](sandbox.md) | Agent sandbox boundary: launch path, nono/Landlock, deny lists, defense-in-depth | `SBX-` |
| [networking.md](networking.md) | nftables, SSH hardening, agent egress, and public firewall policy | `NET-` |
| [secrets.md](secrets.md) | sops-nix, secret ownership, credential proxy/broker model | `SCR-` |
| [agent-compute.md](agent-compute.md) | Agent slice, resource limits, shared tooling, and CASS indexing | `AGT-` |
| [impermanence.md](impermanence.md) | BTRFS rollback, persistence manifest, activation ordering | `IMP-` |
| [backup.md](backup.md) | Restic B2 backup and retention | `BAK-` |
| [deployment.md](deployment.md) | Deploy safety, locking, and post-deploy verification | `DEP-` |
| [boot-and-base.md](boot-and-base.md) | Bootloader, Nix config, base packages, srvos, flake inputs | `BAS-` |
| [users-and-privileges.md](users-and-privileges.md) | User model, launcher sudo rules, root SSH requirement, template safety | `USR-` |
| [extras.md](extras.md) | Codex wrapper, CASS, cost tracker, home-manager, hardening baseline | `EXT-` |
| [testing.md](testing.md) | Test architecture, eval/live/VM layers, coverage map | `TST-` |

## Claim ID Reference

| Prefix | Domain |
|--------|--------|
| `SEC-` | Security model |
| `SBX-` | Sandbox |
| `NET-` | Networking |
| `SCR-` | Secrets |
| `AGT-` | Agent compute |
| `IMP-` | Impermanence |
| `BAK-` | Backup |
| `DEP-` | Deployment |
| `BAS-` | Boot and base |
| `USR-` | Users and privileges |
| `EXT-` | Extras |
| `TST-` | Testing |

## How to Use

1. **Derive test cases**: Each claim (e.g., `SBX-027: /run/secrets denied`) maps to a testable behavior.
2. **Cross-reference**: Test comments should cite the claim ID they validate (e.g., `# Validates SBX-027`).
3. **Coverage gaps**: See `testing.md` coverage map for claims without test coverage.
4. **Maintenance**: When modules change, update the corresponding spec file. Claim IDs are stable — add new IDs, don't renumber.

## Source of Truth

This spec is derived from the implementation. When the spec and code disagree, the code is authoritative. The spec should then be updated to match.
