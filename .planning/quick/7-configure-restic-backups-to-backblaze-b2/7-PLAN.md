---
phase: quick-7
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - modules/restic.nix
  - modules/secrets.nix
  - modules/default.nix
autonomous: false
must_haves:
  truths:
    - "Restic backup runs to B2 via S3 API and creates a snapshot"
    - "Automated daily backup timer is enabled and scheduled"
    - "Retention policy prunes to 7 daily, 5 weekly, 12 monthly"
    - "B2 credentials are injected from sops-nix secrets (no plaintext in Nix store)"
  artifacts:
    - path: "modules/restic.nix"
      provides: "Restic backup configuration with B2 backend, sops.templates env file, retention"
      contains: "services.restic.backups"
    - path: "modules/secrets.nix"
      provides: "sops.templates for restic B2 env file"
      contains: "sops.templates"
    - path: "modules/default.nix"
      provides: "Import of restic.nix"
      contains: "restic.nix"
  key_links:
    - from: "modules/restic.nix"
      to: "sops.templates.restic-b2-env"
      via: "environmentFile reference"
      pattern: "config\\.sops\\.templates"
    - from: "modules/secrets.nix"
      to: "secrets/acfs.yaml"
      via: "sops.placeholder references to b2-account-id and b2-account-key"
      pattern: "sops\\.placeholder"
    - from: "modules/restic.nix"
      to: "config.sops.secrets.restic-password"
      via: "passwordFile reference"
      pattern: "passwordFile"
---

<objective>
Configure restic backups to Backblaze B2, deploy to VPS, and verify with a manual first backup.

Purpose: Automated encrypted backups of all critical server data to offsite B2 storage.
Output: Working restic backup service with daily timer, B2 backend, sops-managed credentials, and verified first snapshot.
</objective>

<execution_context>
@/home/ubuntu/.claude/get-shit-done/workflows/execute-plan.md
@/home/ubuntu/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@modules/secrets.nix
@modules/default.nix
@modules/monitoring.nix
@modules/docker.nix
@.planning/research/STACK.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create restic.nix module with B2 backend and sops integration</name>
  <files>modules/restic.nix, modules/secrets.nix, modules/default.nix</files>
  <action>
  1. **Create `modules/restic.nix`** with this structure:

     ```
     # modules/restic.nix
     # @decision RESTIC-01: S3-compatible B2 backend (not native B2 — restic's B2 connector is unreliable per STACK.md)
     # @decision RESTIC-02: Retention policy 7 daily, 5 weekly, 12 monthly
     # @decision RESTIC-03: sops.templates for B2 credentials env file, passwordFile for encryption key
     { config, ... }: { ... }
     ```

     Use `services.restic.backups.b2` with:
     - `initialize = true` (auto-init repo on first run)
     - `repository = "s3:s3.us-west-004.backblazeb2.com/SyncBkp"` — NOTE: The exact B2 S3 endpoint region MUST match the bucket's actual region. The planning context suggests `us-west-004`. If deployment fails with endpoint error, the user will need to check B2 dashboard for the correct S3 endpoint URL for the SyncBkp bucket.
     - `passwordFile = config.sops.secrets."restic-password".path;`
     - `environmentFile = config.sops.templates."restic-b2-env".path;`
     - `paths` list:
       - `/data/projects/`
       - `/home/dangirsh/`
       - `/var/lib/hass/`
     - `exclude` list:
       - `/nix/store`
       - `.git/objects`
       - `node_modules`
       - `__pycache__`
       - `.direnv`
       - `result` (nix build output symlinks)
     - `pruneOpts` = `[ "--keep-daily 7" "--keep-weekly 5" "--keep-monthly 12" ]`
     - `timerConfig` = `{ OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "1h"; }`
       - `Persistent = true` ensures missed backups run on next boot
       - `RandomizedDelaySec` avoids thundering herd if multiple machines back up

  2. **Update `modules/secrets.nix`** to add the sops.templates block for B2 credentials:

     Add after the `sops.secrets` block:

     ```nix
     sops.templates."restic-b2-env" = {
       content = ''
         AWS_ACCESS_KEY_ID=${config.sops.placeholder."b2-account-id"}
         AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."b2-account-key"}
       '';
     };
     ```

     This renders the two B2 secrets into an environment file that restic reads as AWS S3 credentials. The sops.placeholder references are resolved at activation time from the encrypted secrets/acfs.yaml.

  3. **Update `modules/default.nix`** to add `./restic.nix` to the imports list.

  4. Run `nix flake check` to validate the configuration builds without errors.
  </action>
  <verify>
  Run `nix flake check` from the repo root. Must complete with exit code 0 (no evaluation or build errors).
  Also verify the module is importable: `nix eval .#nixosConfigurations.acfs.config.services.restic.backups.b2.repository` should output the B2 S3 URL.
  </verify>
  <done>
  - `modules/restic.nix` exists with services.restic.backups.b2 configuration
  - `modules/secrets.nix` contains sops.templates."restic-b2-env" with AWS credential rendering
  - `modules/default.nix` imports restic.nix
  - `nix flake check` passes
  </done>
</task>

<task type="auto">
  <name>Task 2: Deploy to VPS and run first backup</name>
  <files></files>
  <action>
  1. Deploy the updated configuration to the VPS:
     ```
     scripts/deploy.sh --target root@161.97.74.121 --skip-update
     ```
     Use `--skip-update` since this change is local modules only (no parts input change needed).

  2. After successful deploy, SSH into the VPS and trigger the first backup manually:
     ```
     ssh root@161.97.74.121 "systemctl start restic-backups-b2.service"
     ```
     This will initialize the restic repo on B2 (if `initialize = true` works) and run the first backup. This may take several minutes depending on data size.

  3. Check the service status for success:
     ```
     ssh root@161.97.74.121 "systemctl status restic-backups-b2.service"
     ```
     Should show "Active: inactive (dead)" with a successful exit (exit-code 0 or "Success").

  4. Verify a snapshot exists:
     ```
     ssh root@161.97.74.121 "systemctl cat restic-backups-b2.service"
     ```
     Then use the environment to run restic snapshots. The NixOS service wrapper sets up the environment, so the simplest verification is checking the journal:
     ```
     ssh root@161.97.74.121 "journalctl -u restic-backups-b2.service --no-pager -n 50"
     ```
     Should show "snapshot ... saved" in the output.

  5. Verify the timer is enabled and scheduled:
     ```
     ssh root@161.97.74.121 "systemctl status restic-backups-b2.timer"
     ```
     Should show "Active: active (waiting)" with a next trigger time.

  If deploy or first backup fails:
  - Check `journalctl -u restic-backups-b2.service` for errors
  - Common issues: wrong B2 S3 endpoint region (check B2 dashboard), credentials format mismatch, bucket doesn't exist
  - For endpoint issues: the B2 S3 endpoint format is `s3.{region}.backblazeb2.com` — verify region matches bucket's actual region in Backblaze dashboard
  </action>
  <verify>
  - `systemctl status restic-backups-b2.timer` shows "Active: active (waiting)" with scheduled next run
  - `journalctl -u restic-backups-b2.service` shows a successful snapshot creation
  - No errors in service journal
  </verify>
  <done>
  - First restic backup completed successfully to B2
  - Snapshot visible in service journal output
  - Daily timer is active and scheduled for next run
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Verify backup and timer on VPS</name>
  <files></files>
  <action>
  Human verifies the deployed restic backup configuration:
  1. Check the deploy succeeded and services are healthy
  2. Verify the timer schedule looks correct: `ssh root@161.97.74.121 "systemctl list-timers restic*"`
  3. Optionally verify from B2 dashboard that files appeared in the SyncBkp bucket
  4. If the B2 S3 endpoint was wrong (backup failed with connection/auth error), provide the correct endpoint from B2 Dashboard -> Buckets -> SyncBkp -> "S3 Compatible URL"
  </action>
  <verify>User confirms backup is working and timer is scheduled, or reports issues to fix.</verify>
  <done>User types "approved" or describes any issues (especially B2 endpoint problems).</done>
</task>

</tasks>

<verification>
- `nix flake check` passes locally
- `systemctl status restic-backups-b2.timer` shows active (waiting) on VPS
- `journalctl -u restic-backups-b2.service` shows successful snapshot
- Backup paths include /data/projects/, /home/dangirsh/, /var/lib/hass/
- Excludes include .git/objects, node_modules, /nix/store
- Retention: 7 daily, 5 weekly, 12 monthly in pruneOpts
</verification>

<success_criteria>
1. Restic snapshot exists on B2 (visible in journal or B2 dashboard)
2. Daily timer is active and scheduled
3. Retention policy configured as 7/5/12 (daily/weekly/monthly)
4. All credentials sourced from sops-nix (no plaintext in Nix store)
</success_criteria>

<output>
After completion, create `.planning/quick/7-configure-restic-backups-to-backblaze-b2/7-SUMMARY.md`
</output>
