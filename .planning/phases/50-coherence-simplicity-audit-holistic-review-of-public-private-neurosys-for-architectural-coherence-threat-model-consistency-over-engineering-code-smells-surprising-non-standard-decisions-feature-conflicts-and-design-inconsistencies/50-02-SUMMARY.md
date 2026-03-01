# Summary 50-02: Private Overlay Module Consolidation

```yaml
status: complete
commit_private: 5d277a1
commit_public: b13e080
wave: 2
```

## Changes

| Task | File | Change |
|------|------|--------|
| A | private:modules/{automaton,openclaw,spacebot}.nix | Deleted 3 duplicate modules + 4 .orig backup files |
| B | private:flake.nix | Updated imports to use `${inputs.neurosys}/modules/*.nix` for 4 modules |
| C | private:modules/matrix-overrides.nix | Created 21-line override file (replaces 164-line matrix.nix) |
| D | private:modules/agent-compute.nix | Added @decision AGENT-50-02 (explains why disabledModules required) |
| E | private:modules/home-assistant.nix | Added ProtectHome, PrivateTmp, NoNewPrivileges to tailscale-serve-ha |
| F | private:modules/homepage.nix | Removed 3 unnecessary mkForce calls + updated HP-03 annotation |
| G | private:modules/secrets.nix | Added mkOverride 40 on conway-api-key sopsFile + SEC-03 annotation |
| H | private:tests/eval/private-checks.nix | Created 8 private eval checks wired into flake.nix |
| I | CLAUDE.md | Added SEC50-01, SEC50-02 accepted risks + disabledModules convention |
| J | — | `nix flake check` passed — 33 checks (deploy + public + private eval) |

## Net Impact

- **695 lines deleted**, 34 lines added across private overlay
- 4 modules eliminated (3 deleted, 1 rewritten as 21-line override)
- 8 new eval-time assertions for private overlay security invariants
- All accepted risks documented

## Verification

All must_haves confirmed:
1. automaton.nix, openclaw.nix, spacebot.nix deleted from private overlay
2. matrix-overrides.nix is 21 lines with 3 mkOverride 40 declarations
3. agent-compute.nix has @decision AGENT-50-02
4. home-assistant.nix has 3 systemd hardening directives
5. homepage.nix has zero mkForce usage (only in comment)
6. private-checks.nix exists with 8 assertions wired into flake checks
7. `nix flake check` passes for both neurosys and ovh configurations
8. CLAUDE.md has SEC50-01 and SEC50-02
9. conway-api-key uses mkOverride 40 in private secrets.nix
