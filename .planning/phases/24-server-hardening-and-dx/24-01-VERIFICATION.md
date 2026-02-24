---
phase: 24-server-hardening-and-dx
verified: 2026-02-23T13:38:28Z
status: human_needed
score: 6/7 must-haves verified
human_verification:
  - test: "Run `nix flake check` in the neurosys repo"
    expected: "Command exits 0 with no evaluation errors"
    why_human: "Cannot run nix flake check from the verifier environment; all other checks pass programmatically"
---

# Phase 24: Server Hardening and DX Verification Report

**Phase Goal:** Adopt srvos server profile for ~40 battle-tested hardening defaults. Add `--unshare-pid` and `--unshare-cgroup` to agent-spawn bubblewrap flags. Improve DX: devShell with sops+age+deploy tooling, treefmt-nix (nixfmt + shellcheck).
**Verified:** 2026-02-23T13:38:28Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                         | Status      | Evidence                                                                                                         |
| --- | ----------------------------------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------- |
| 1   | srvos hardening defaults active: emergency mode off, watchdog, OOM, LLMNR off | VERIFIED    | `srvos.nixosModules.server` at line 57 in flake.nix (first module, before disko); srvos input with nixpkgs.follows |
| 2   | Neurosys config preserved: scripted networking, docs on, command-not-found on  | VERIFIED    | `networking.useNetworkd = lib.mkForce false` (L26), `srvos.server.docs.enable = true` (L28), `programs.command-not-found.enable = true` (L30), `boot.initrd.systemd.enable = lib.mkForce false` (L33) |
| 3   | Agents cannot see host processes via /proc or ps                               | VERIFIED    | `--unshare-pid` at line 118 in BWRAP_ARGS array in modules/agent-compute.nix                                   |
| 4   | Agents cannot see host cgroup hierarchy                                        | VERIFIED    | `--unshare-cgroup` at line 119 in BWRAP_ARGS array in modules/agent-compute.nix                                |
| 5   | `nix develop` provides sops, age, deploy-rs CLI, nixfmt, shellcheck           | VERIFIED    | `devShells.${system}.default` with all 5 packages at lines 93-101 in flake.nix                                 |
| 6   | `nix fmt` formats Nix files with nixfmt and lints shell scripts with shellcheck | VERIFIED  | `formatter.${system} = treefmtEval.config.build.wrapper` (L91); treefmt.nix has nixfmt+shellcheck enabled     |
| 7   | `nix flake check` passes with all changes                                     | HUMAN_NEEDED | Cannot run nix in verifier environment; SUMMARY reports it passes                                              |

**Score:** 6/7 truths verified (1 needs human)

### Required Artifacts

| Artifact                         | Expected                                                      | Status   | Details                                                                                    |
| -------------------------------- | ------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| `flake.nix`                      | srvos + treefmt-nix inputs, srvos module import, devShell, formatter | VERIFIED | srvos at L37-40, treefmt-nix at L41-44, srvos.nixosModules.server at L57, formatter at L91, devShells at L93 |
| `treefmt.nix`                    | treefmt-nix config for nixfmt + shellcheck                    | VERIFIED | File exists (122 bytes), `programs.nixfmt.enable = true` at L3, `programs.shellcheck.enable = true` at L4 |
| `hosts/neurosys/default.nix`     | srvos overrides: networkd off, docs on, command-not-found on, initrd off | VERIFIED | All 4 overrides present at lines 26-33; `lib` in function args (L1) |
| `modules/agent-compute.nix`      | --unshare-pid and --unshare-cgroup in bwrap args              | VERIFIED | Both flags at lines 118-119 inside BWRAP_ARGS array; policy output updated at L96         |

### Key Link Verification

| From       | To                         | Via                              | Status  | Details                                                                                   |
| ---------- | -------------------------- | -------------------------------- | ------- | ----------------------------------------------------------------------------------------- |
| flake.nix  | srvos.nixosModules.server  | nixosSystem modules list         | WIRED   | Line 57 in modules list, before disko at line 58 — ensures mkDefault stays lowest priority |
| flake.nix  | treefmt.nix                | treefmt-nix.lib.evalModule pkgs ./treefmt.nix | WIRED | Line 51 in let binding; treefmtEval used at L91 for formatter output |
| flake.nix  | formatting check in checks | attribute merge with //          | PARTIAL | Per-plan fallback (b) applied: `formatter` output retained, formatting check not merged into `checks` due to repo-wide churn (28 files). SUMMARY acknowledges this explicitly as a documented deviation, not a gap. |

### Requirements Coverage

No REQUIREMENTS.md entries mapped to phase 24 (per roadmap structure).

### Anti-Patterns Found

No anti-patterns (TODO, FIXME, HACK, placeholder, stub returns) found in any of the 4 modified files.

### Human Verification Required

#### 1. nix flake check

**Test:** Run `nix flake check` from the neurosys repo root on the deployed server or a machine with nix available.
**Expected:** Command exits 0; no evaluation errors or type errors from srvos module integration, treefmt-nix evalModule, or devShells output.
**Why human:** Cannot invoke nix from the verifier environment. SUMMARY reports this was validated during execution ("validated repeatedly with `nix flake check` (passing)").

### Notes on Plan Deviations

The SUMMARY documents one intentional deviation from the plan:

- **Formatting check not merged into `checks`:** The plan offered two fallback paths. Path (a) was preferred (run `nix fmt` and include formatting check in `checks`); path (b) was the fallback (keep `formatter` output, drop formatting check from `checks`). Path (b) was applied after 28 files showed formatter churn and existing shellcheck findings in `scripts/deploy.sh`. This is an acknowledged, documented decision — not a verification gap.

- **`nix fmt -- --check .` not supported:** Plan verification command relied on an unsupported flag; the equivalent is `treefmt --ci`. This is a plan documentation issue only and does not affect code correctness.

---

_Verified: 2026-02-23T13:38:28Z_
_Verifier: Claude (gsd-verifier)_
