# Phase 74 Research: Open Source Release Prep v3

## Objective

Clean the public neurosys repo for strangers: zero personal identifiers, zero dead code, maximum signal-to-noise, fresh git history. Private overlay must continue to work after all changes.

## Prior Art

Two previous cleanup phases were completed:

- **Phase 37** (2026-02-27): First privacy audit. Replaced `dangirsh` with `myuser`, removed private flake inputs, exported `nixosModules.default`, added `.gitignore` rules for `.planning/`, `secrets/`, `.sops.yaml`.
- **Phase 65** (2026-03-04): Second cleanup. Moved 4 personal modules to private overlay, stripped 13 personal service ports, 10 personal secrets, 13 impermanence paths. Rewrote README with 5 example use cases. Lowered eval check thresholds.

Since Phase 65, Phases 66-73 added new code: nix-secret-proxy integration, agent-sandbox module, OVH deploy tests, and live BATS suites. Some of these reintroduced personal identifiers.

## Current State Assessment

### File Count

The public repo has **73 tracked files** (excluding `.planning/`):
- 15 Nix modules (`modules/*.nix`)
- 3 home-manager files (`home/*.nix`)
- 6 host configs (`hosts/{services,dev}/{default,hardware,disko-config}.nix`)
- 4 scripts (`scripts/*.sh`)
- 6 test suites (`tests/live/*.bats`, `tests/lib/common.bash`, `tests/eval/config-checks.nix`, `tests/vm/ssh-reachability.nix`)
- 1 MCP server (`src/neurosys-mcp/server.py`)
- `flake.nix`, `flake.lock`, `treefmt.nix`, `.sops.yaml`
- `README.md`, `LICENSE`, `CLAUDE.md`
- 2 docs (`docs/oob-recovery.md`, `docs/secret-proxy-architecture.md`)
- `.github/workflows/test.yml`, `.gitignore`
- `.claude/skills/deploy/SKILL.md`, `.claude/.test-status`, `.test-status`
- `tmp/ovh_ssh_host_ed25519_key.pub`
- `secrets/neurosys.yaml`, `secrets/ovh.yaml`

Total source lines (non-planning, non-lock): ~5,173 lines in Nix/shell/Python.

### Git History

728 commits on the current branch. The phase description calls for a clean history (single squashed commit or fresh init).

---

## Finding 1: Personal Identifiers Remaining

The Phase 37/65 grep (`dangirsh|worldcoin|161.97.74|135.125.196|100.104.43|100.113.72`) returns **zero matches** against `modules/ home/ scripts/ src/ docs/ README.md flake.nix`. However, a broader search reveals identifiers that leaked back or were never covered by the Phase 37 criteria.

### Category A: Personal Name / Email / Username

| File | Line | Content | Action |
|------|------|---------|--------|
| `modules/users.nix:19` | SSH key comment | `dan@worldcoin.org` | Replace with generic comment (e.g., `bootstrap-key`) |
| `modules/agent-sandbox.nix:121` | Option description | `"private overlay overrides to /home/dangirsh"` | Remove personal name from description |
| `scripts/deploy.sh:204` | Comment | `"users (dev instead of dangirsh)"` | Replace with generic wording |
| `scripts/bootstrap-ovh.sh:303` | Output text | `"Real SSH keys + dangirsh user"` | Replace with `"Real SSH keys + your user"` |

### Category B: IP Addresses

| File | Line | Content | Action |
|------|------|---------|--------|
| `flake.nix:92` | deploy-rs hostname | `100.104.43.26` (Tailscale IP) + stale comment `100.113.239.14` | Replace with placeholder or hostname-only |
| `scripts/deploy.sh:197-198` | PUBLIC_IP map | `161.97.74.121`, `135.125.196.143` | Replace with `YOUR_CONTABO_IP`, `YOUR_OVH_IP` or remove |
| `scripts/bootstrap-contabo.sh:35` | VPS_IP | `161.97.74.121` | Replace with placeholder |
| `scripts/bootstrap-ovh.sh:29` | VPS_IP | `135.125.196.143` | Replace with placeholder |
| `docs/oob-recovery.md:9-10,93` | IP addresses | Both public IPs | Replace with placeholders |

### Category C: Personal Cachix Cache

| File | Line | Content | Action |
|------|------|---------|--------|
| `modules/base.nix:20-27` | Cachix config | `dan-testing.cachix.org` and its signing key | Replace with `YOUR_CACHE.cachix.org` placeholder or remove |
| `scripts/deploy.sh:498,503` | Cachix push | `dan-testing.cachix.org`, `cachix push dan-testing` | Parameterize or replace with placeholder |

### Category D: Personal B2 Bucket

| File | Line | Content | Action |
|------|------|---------|--------|
| `modules/restic.nix:13` | Repository URL | `s3:s3.eu-central-003.backblazeb2.com/SyncBkp` | Replace bucket name with placeholder |

### Category E: Private Overlay Path References

These are not personal identifiers per se, but they reference a specific local filesystem path that only exists on the author's machine:

| File | Lines | Content | Action |
|------|-------|---------|--------|
| `flake.nix:36` | nix-secret-proxy input | `path:/data/projects/nix-secret-proxy` | **Critical**: Must change to a GitHub URL or document how to override |
| `scripts/bootstrap-contabo.sh:38` | FLAKE_TARGET | `"/data/projects/private-neurosys#neurosys"` | Replace with note to set |
| Multiple files | `/data/projects/private-neurosys` | deploy.sh, SKILL.md, CLAUDE.md, docs, bootstrap scripts | Replace with generic path or `$PRIVATE_OVERLAY_DIR` |

### Category F: Age Keys in .sops.yaml

| File | Content | Action |
|------|---------|--------|
| `.sops.yaml` | `age1vma7w9...` (admin key), `age1vxtl4pukn7...` (host_neurosys), `age1rkve23z2...` (host_ovh) | These are **public keys** (safe to expose), but the admin key links to the author. Consider whether to keep. The `.sops.yaml` is already gitignored, but it IS tracked. |

**Note:** `.sops.yaml` is in `.gitignore` (`secrets/`, `.sops.yaml`) -- wait, let me verify. Looking at `.gitignore` lines 3-4: `secrets/` and `.sops.yaml` are gitignored. But `git ls-files` shows `.sops.yaml` and `secrets/neurosys.yaml` and `secrets/ovh.yaml` as tracked. This means they were `git add -f`'d before the gitignore was added. They are in git history and in the current tree.

**Decision needed:** `.sops.yaml` contains real public keys. `secrets/*.yaml` contains encrypted secrets (unreadable without private keys). Both are currently tracked despite being gitignored. If history is reset (fresh init), these can be excluded from the clean commit.

### Category G: SSH Public Key in tmp/

| File | Content | Action |
|------|---------|--------|
| `tmp/ovh_ssh_host_ed25519_key.pub` | Real OVH host public key | Should be removed; `tmp/` is gitignored but this is tracked |

---

## Finding 2: Dead Code / Unnecessary Files

### Files That May Not Justify Their Existence

| File | Concern | Recommendation |
|------|---------|----------------|
| `modules/nginx.nix` | Intentionally empty (6 lines, "extend vhosts in private overlay") | **Keep** -- serves as documented extension point for private overlay |
| `src/neurosys-mcp/server.py` | 366 lines of MCP server with HA + Matrix tools, imports 4 sibling modules (`auth.py`, `google_auth.py`, `gmail.py`, `calendar_tools.py`, `rest_shim.py`) that are NOT tracked in git | **Remove** or document as incomplete. The sibling modules are missing, so this file cannot work standalone. It references personal service integrations (Matrix, HA, Google OAuth). |
| `tmp/ovh_ssh_host_ed25519_key.pub` | Real SSH public key, should not be in public repo | **Remove** (will be excluded by gitignore after history reset) |
| `.claude/.test-status` + `.test-status` (root) | Build artifact, no value to strangers | Exclude from clean commit |
| `.claude/skills/deploy/SKILL.md` | References private-neurosys paths, parts, claw-swap | **Clean or remove** -- contains numerous personal references |
| `docs/oob-recovery.md` | Contains both public IPs, provider-specific login instructions | **Clean** IPs to placeholders, keep structure (genuinely useful for forkers) |

### Modules Assessment (all justify existence)

Every module in `modules/` serves a clear purpose and contains working, non-trivial configuration. No empty stubs beyond `nginx.nix` (intentional). The dashboard (1088 lines) and canvas (1363 lines) are large but fully functional.

### Private-Overlay-Specific References in Deploy Script

`scripts/deploy.sh` has extensive private-overlay-specific logic:
- `SYSTEMD_SERVICES` lists `parts`, `postgresql`, `claw-swap-app` for neurosys node
- `--update-parts` flag and parts-specific rev tracking
- Cachix push to `dan-testing`
- Public IP hardcoded for connectivity checks

This script is intentionally non-functional in the public repo (it refuses to deploy, line 210-226). A forker would need to rewrite most of it. **Decision needed:** Simplify to a minimal deploy template, or keep the full script as documentation of the deploy pattern?

---

## Finding 3: README Assessment

The current README (`README.md`, 73 lines) is already clean and well-structured:
- Clear value proposition (agents + NixOS)
- Design principles (3)
- Features list with module links
- Example use cases (5)
- Quick start (4 steps)
- MIT license

**Issues:**
- Line 17: Links to `secret-proxy.nix` which does not exist in the public repo (the module is from the `nix-secret-proxy` flake input, not a local file)
- No GitHub badges (stars, CI status, license)
- No architecture diagram
- "My personal services" language in the note is slightly informal
- Does not mention the test suite

**Recommendation:** Fix broken link, add CI badge, add "Testing" section. The README quality is already high.

---

## Finding 4: CLAUDE.md Assessment

`CLAUDE.md` (164 lines) is the project's AI-agent instruction file. It contains:
- Extensive security conventions (agent-critical)
- Accepted risks with SEC-* identifiers
- Module change checklist
- Test instructions

**Issues for public release:**
- References `private-neurosys` paths (`/data/projects/private-neurosys`)
- References `dangirsh` indirectly via accepted risks (SEC49-01: "CONTABO_PASS default")
- References `parts`, `claw-swap`, `openclaw` (private services) in accepted risks and conventions
- References Contabo/OVH IPs in deployment rules

**Recommendation:** CLAUDE.md is valuable as-is for showing how to write agent instructions for NixOS. Clean personal references, but preserve the structure. It is a selling point of the project.

---

## Finding 5: Git History Reset Strategy

728 commits with personal identifiers baked throughout history. Options:

### Option A: Fresh `git init` with single commit
- **Pros:** Cleanest result, zero risk of leaked identifiers in history
- **Cons:** Loses blame, bisect, and context for decisions
- **Private overlay impact:** Private overlay's `neurosys.url` input will need to be updated to the new repo/commit

### Option B: Squash all commits into one
- **Pros:** Same cleanliness as Option A, uses familiar git tooling
- **Cons:** Same as Option A

### Option C: Interactive rebase / filter-repo to remove identifiers
- **Pros:** Preserves history structure
- **Cons:** Extremely fragile for 728 commits, high risk of missed identifiers, much more effort

**Recommendation:** Option A (fresh init). The git history of a NixOS config has little value to strangers. Decisions are documented in `@decision` annotations and CLAUDE.md.

---

## Finding 6: `nix flake check` Considerations

The current `nix flake check` passes 23+ checks. Changes that could break it:

1. **`flake.nix` nix-secret-proxy input**: Currently `path:/data/projects/nix-secret-proxy`. This **must** be changed to a fetchable URL (e.g., `github:owner/nix-secret-proxy`) or the flake won't evaluate on anyone else's machine.

2. **deploy-rs hostname**: Currently `100.104.43.26`. deploy-rs checks will fail if the hostname doesn't resolve, but these are `deployChecks` which run as part of `nix flake check`. Need to verify if deploy checks require reachability or just evaluability.

3. **`.sops.yaml` and `secrets/*.yaml`**: If removed from the tree, `modules/secrets.nix` references `sops.defaultSopsFile = ../../secrets/neurosys.yaml` which will fail at eval time unless the file exists.

4. **Placeholder SSH keys**: The current `users.nix` and `break-glass-ssh.nix` use the same real SSH public key as a placeholder. This will evaluate fine but it's a real key.

**Critical blocker:** The `path:/data/projects/nix-secret-proxy` input makes the flake non-evaluable on any machine except the author's. This must be resolved before anything else.

---

## Finding 7: Files That Should Be Excluded from Clean Commit

Files that are currently tracked but should NOT be in the public release:

| File | Reason |
|------|--------|
| `.planning/*` | Already gitignored but tracked -- project planning history |
| `secrets/neurosys.yaml` | Encrypted secrets (safe but useless to strangers) |
| `secrets/ovh.yaml` | Encrypted secrets |
| `.sops.yaml` | Contains real age public keys |
| `tmp/ovh_ssh_host_ed25519_key.pub` | Real SSH public key |
| `.claude/.test-status` | Build artifact |
| `.test-status` | Build artifact |
| `src/neurosys-mcp/server.py` | Incomplete (missing sibling modules), personal integrations |
| `flake.lock` | Will need to be regenerated after flake.nix changes |

---

## Finding 8: Private Overlay Compatibility

The private overlay (`/data/projects/private-neurosys`) imports the public repo as a flake input (`neurosys.url`). Key compatibility concerns:

1. **Module paths**: Private overlay imports individual modules like `${inputs.neurosys}/modules/base.nix`. If any public module file is renamed or removed, the private overlay breaks.

2. **User/home paths**: Private overlay's `users.nix` replaces the public one entirely (`disabledModules`). As long as the public `users.nix` continues to exist and be importable, this works.

3. **Option namespaces**: Private overlay sets options like `services.agentSandbox.homeDir`, `services.dashboard.extraManifests`, etc. These options must remain defined in public modules.

4. **`nix-secret-proxy` input**: If changed from `path:` to `github:`, the private overlay's `follows` pin may need updating.

5. **flake.nix structure**: Private overlay expects `nixosConfigurations.neurosys` and `nixosConfigurations.ovh`. Renaming these breaks the private overlay.

**Recommendation:** No module renames or removals. Only content changes within files. The option namespaces are stable.

---

## Recommendations for Planning

### Plan 1: Identifier Scrub + Flake Fix (~30 min)

1. Fix `flake.nix` nix-secret-proxy input (path -> GitHub URL)
2. Replace all personal identifiers (Categories A-D above)
3. Parameterize IP addresses in scripts and docs
4. Replace Cachix references with placeholders
5. Replace B2 bucket name with placeholder
6. Clean CLAUDE.md personal references
7. Clean deploy SKILL.md
8. Verify `nix flake check` passes after each change

### Plan 2: Dead Code Removal + README Polish (~20 min)

1. Remove `src/neurosys-mcp/server.py` (incomplete without sibling modules)
2. Fix README broken link to `secret-proxy.nix`
3. Add CI badge and Testing section to README
4. Clean `docs/oob-recovery.md` IPs
5. Verify `nix flake check` still passes

### Plan 3: Git History Reset + Final Verification (~15 min)

1. Create a clean branch from current main
2. Remove files that should not be in public release (`.planning/`, `secrets/`, `.sops.yaml`, `tmp/`, test-status files)
3. Create fresh initial commit with all cleaned files
4. Run `nix flake check` on the clean commit
5. Run the Phase 74 success criteria grep
6. Verify private overlay still builds against the cleaned repo

---

## Key Risks

1. **nix-secret-proxy URL change**: If the nix-secret-proxy repo is not yet public on GitHub, changing from `path:` to `github:` will break the flake. **Mitigation:** Verify repo availability before changing.

2. **Private overlay breakage**: Any module rename or option removal breaks the private overlay. **Mitigation:** Content-only changes, no structural changes.

3. **deploy-rs checks in CI**: If deploy-rs checks require hostname resolution, placeholder hostnames may fail in CI. **Mitigation:** Test with `nix flake check` after hostname changes.

4. **Secrets files in git history**: Even after fresh init, if someone already cloned the repo, they have the encrypted secrets. **Risk level:** Low (secrets are encrypted with age keys, unusable without private key).

## Questions for the User

1. **nix-secret-proxy**: Is the nix-secret-proxy repo public on GitHub? If not, what URL should be used in `flake.nix`?
2. **src/neurosys-mcp/**: Should this be removed (missing dependencies) or kept with a note that sibling modules live in the private overlay?
3. **deploy.sh complexity**: Should the deploy script be simplified to a minimal template, or kept as-is (with cleaned identifiers) to show the full deploy pattern?
4. **Cachix cache**: Should the Cachix cache reference be removed entirely, or replaced with a placeholder?
