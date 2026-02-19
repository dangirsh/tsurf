---
phase: quick-8
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - modules/restic.nix
  - docs/recovery-runbook.md
autonomous: true
must_haves:
  truths:
    - "Restic backs up all stateful paths on the root filesystem without requiring manual path additions"
    - "Ephemeral and reproducible paths (nix store, docker layers, caches) are excluded"
    - "Users can opt out any directory by placing a .nobackup sentinel file"
    - "Recovery runbook accurately reflects the new blanket backup scope"
  artifacts:
    - path: "modules/restic.nix"
      provides: "Blanket root backup with exclusion-based approach"
      contains: "paths = [ \"/\" ]"
    - path: "docs/recovery-runbook.md"
      provides: "Updated backup scope documentation"
  key_links:
    - from: "modules/restic.nix"
      to: "services.restic.backups.b2"
      via: "NixOS module option"
      pattern: "paths = \\[ \"/\" \\]"
---

<objective>
Switch restic backups from 8 hard-coded paths to blanket root filesystem backup with exclusion-based approach.

Purpose: Eliminates the risk of forgetting to add new stateful paths to backups. Any new service data, user files, or system state is automatically included. Opt-out via exclusions instead of opt-in via path list.

Output: Updated `modules/restic.nix` with `paths = [ "/" ]` and comprehensive exclusions; updated `docs/recovery-runbook.md` reflecting new scope.
</objective>

<execution_context>
@/home/ubuntu/.claude/get-shit-done/workflows/execute-plan.md
@/home/ubuntu/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@modules/restic.nix
@docs/recovery-runbook.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Switch restic.nix to blanket backup with exclusions</name>
  <files>modules/restic.nix</files>
  <action>
Replace the hard-coded `paths` list and expand `exclude` in `modules/restic.nix`:

1. Change `paths` from the 8 hard-coded entries to:
   ```nix
   paths = [ "/" ];
   ```

2. Add to `extraBackupArgs`:
   ```nix
   extraBackupArgs = [
     "--one-file-system"
     "--exclude-caches"
     "--exclude-if-present .nobackup"
   ];
   ```
   `--one-file-system` automatically skips virtual filesystems mounted on separate mounts (/proc, /sys, /dev, /run, /tmp) since they are different filesystems from root. This is the primary mechanism that makes blanket `/` safe.

3. Replace the current `exclude` list with a comprehensive exclusion set. Group with comments:
   ```nix
   exclude = [
     # Nix store — fully reproducible from flake.lock (50-200 GB)
     "/nix"

     # Docker ephemeral layers — rebuilt from images
     "/var/lib/docker/overlay2"
     "/var/lib/docker/tmp"
     "/var/lib/docker/buildkit"

     # System caches — rebuilt automatically
     "/var/cache"
     "**/.cache"

     # Git internals — objects fetched from remotes, config may contain tokens
     ".git/objects"
     ".git/config"

     # Language/build artifacts — reproducible
     "node_modules"
     "__pycache__"
     ".direnv"
     "result"

     # Prometheus metrics — accepted loss, rebuilt from scratch
     "/var/lib/prometheus"
   ];
   ```

4. Add a new `@decision` annotation at the top of the file:
   ```
   # @decision RESTIC-05: Blanket "/" backup with --one-file-system + exclusions (not hard-coded paths). New stateful data is automatically included; opt-out via .nobackup sentinel or explicit exclude.
   ```

5. Keep `backupPrepareCommand` and `backupCleanupCommand` exactly as-is (they are correct and unaffected).

6. Keep `pruneOpts`, `timerConfig`, `repository`, `passwordFile`, `environmentFile` exactly as-is.
  </action>
  <verify>
Run `nix flake check` from the repo root to validate the NixOS configuration builds. Expected: no errors (exit 0).
  </verify>
  <done>
`modules/restic.nix` uses `paths = [ "/" ]` with `--one-file-system`, `--exclude-caches`, `--exclude-if-present .nobackup`, and explicit exclusions for /nix, docker layers, caches, git internals, and build artifacts. All 5 @decision annotations present. `nix flake check` passes.
  </done>
</task>

<task type="auto">
  <name>Task 2: Update recovery runbook for blanket backup scope</name>
  <files>docs/recovery-runbook.md</files>
  <action>
Update `docs/recovery-runbook.md` to reflect the new blanket backup approach:

1. In Section 1 "Overview", no changes needed (it describes sources generically).

2. In Section 3 "What's Where" table: Update the descriptions to reflect that ALL stateful paths under `/` are backed up (not just specific ones). The table should still list key items but note the blanket approach. Specifically:
   - Add a row at the top or a note: "All paths on root filesystem are backed up by default (exclusion-based). Key items listed below."
   - Keep existing rows as they are useful for recovery reference.

3. In Section 5 Phase 2 "Restore Stateful Data from B2":
   - Steps 2.4 through 2.7 currently restore specific paths individually. Since the blanket backup includes everything, the restore can now use a single `restic restore latest --target /` command (with service stops still needed). Update to show:
     - Option A (full restore): `restic restore latest --target /` to restore everything at once
     - Option B (selective restore, same as before): Individual `--include` commands for when you only need specific paths
   - Keep the service stop/start steps (2.3 and 2.9) unchanged.

4. In Section 9 "Appendix -- What's NOT Backed Up":
   - Remove `/var/lib/prometheus/` from the "not backed up" table -- it IS now explicitly excluded (move to a new section or note it as "Explicitly Excluded")
   - Remove `/var/lib/fail2ban/` -- it IS now backed up (auto-included by blanket approach)
   - Remove `/var/lib/esphome/` -- it IS now backed up (auto-included by blanket approach)
   - `/nix/store/` stays as excluded
   - Retitle or restructure to "Appendix -- Excluded from Backup" and list the explicit exclusions from restic.nix with rationale
   - Add a note about the `.nobackup` sentinel file for ad-hoc opt-out

5. In Section 10 "Appendix -- Testing This Runbook":
   - Update the "When to re-test" section: remove the bullet about "Adding or removing backup paths in modules/restic.nix" since paths are no longer manually maintained. Replace with "Adding new exclusions to modules/restic.nix".

6. Update the "Last verified" date at the top to 2026-02-19 (keep as-is if already that date).
  </action>
  <verify>
Read `docs/recovery-runbook.md` and confirm: (a) blanket backup approach is documented, (b) restore instructions include full-restore option, (c) "What's NOT Backed Up" section accurately reflects exclusions not paths, (d) .nobackup sentinel documented.
  </verify>
  <done>
Recovery runbook accurately describes the blanket `/` backup with exclusion-based approach, includes both full and selective restore options, documents all explicit exclusions with rationale, and mentions `.nobackup` sentinel for ad-hoc opt-out.
  </done>
</task>

</tasks>

<verification>
1. `nix flake check` passes (NixOS config valid)
2. `modules/restic.nix` contains `paths = [ "/" ]`, `--one-file-system`, `--exclude-caches`, `--exclude-if-present .nobackup`, and exclusions for /nix, docker layers, caches
3. `docs/recovery-runbook.md` documents the blanket approach, full restore option, and exclusion list
4. All 5 @decision annotations present in restic.nix (RESTIC-01 through RESTIC-05)
</verification>

<success_criteria>
- Restic config uses blanket root backup with comprehensive exclusions instead of hard-coded paths
- `nix flake check` passes
- Recovery runbook updated to match new backup scope
- No data previously backed up is now excluded (only newly excluded items are ephemeral/reproducible)
</success_criteria>

<output>
After completion, create `.planning/quick/8-switch-restic-backups-from-hard-coded-pa/8-SUMMARY.md`
</output>
