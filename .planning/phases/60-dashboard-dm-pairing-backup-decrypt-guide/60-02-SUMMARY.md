---
phase: 60-dashboard-dm-pairing-backup-decrypt-guide
plan: 02
subsystem: matrix
tags: [matrix, dm-guide, backup-import, signal, whatsapp, telegram, nixos, python]

requires:
  - phase: 60-01
    provides: dm-guide module + Matrix bridge pairing flow baseline

provides:
  - Backup Upload UI section on dm-guide page (bridge select, drag/drop, passphrase, progress, result)
  - POST /api/backup/upload with manual multipart parser (Python stdlib only)
  - Signal .backup decrypt pipeline via signalbackup-tools subprocess
  - WhatsApp .zip and Telegram JSON parsers writing structured import JSON
  - Import output layout under /var/lib/dm-guide/imports/{bridge}/{timestamp}/
  - Passing public-repo `nix flake check`

affects: [60-03]

key-files:
  created: [.planning/phases/60-dashboard-dm-pairing-backup-decrypt-guide/60-02-SUMMARY.md]
  modified: [modules/dm-guide.nix, .test-status, .planning/STATE.md]

key-decisions:
  - "DMG-05: Keep backup decrypt/parse local to dm-guide state directories and avoid persisting passphrases"
  - "Use manual multipart boundary parsing (no cgi) for Python 3.13 compatibility"
  - "Use signalbackup-tools store path with runtime availability check + 300s timeout"
  - "Normalize outputs to messages.json per bridge/timestamp directory"

duration: 5min
completed: 2026-03-02
---

# Phase 60 Plan 02: Backup Upload + Decrypt/Parse Summary

Extended `dm-guide` with historical backup import support across Signal, WhatsApp, and Telegram, including UI upload workflow, server-side parsing/decrypt, structured JSON output, and passing flake verification.

## Performance Metrics

- Duration: ~5 minutes (first task commit 18:26:50+01:00, verification commit 18:31:12+01:00)
- Tasks in scope: 4 executed (A/B/C/D), 1 skipped (E post-deploy SSH by scope)
- Files modified: 3
- Verification: `nix flake check` passed; `.test-status` set to `pass|0|1772472648`

## Accomplishments

- Task C (pre-check): verified `signalbackup-tools` availability in nixpkgs with:
  - `nix eval nixpkgs#signalbackup-tools.version` -> `20260218-1`
  - resolved runtime store path for server subprocess usage
- Task A: Added **Backup Upload** section to `modules/dm-guide.nix` HTML page:
  - bridge selector (`signal`, `whatsapp`, `telegram`)
  - drag-and-drop + file picker
  - Signal-only passphrase field (via `togglePassphrase()`)
  - upload button and XHR `upload.onprogress` progress bar
  - status text + JSON result panel
  - JS handlers: `togglePassphrase()`, `handleDrop(e)`, `fileSelected(input)`, `uploadBackup()`
- Task B: Extended embedded Python server in `modules/dm-guide.nix`:
  - added `POST /api/backup/upload`
  - manual multipart parser (`parse_multipart_upload`) without `cgi`
  - Signal pipeline (`process_signal_backup`) invoking `signalbackup-tools` with timeout + graceful missing-binary/passphrase handling
  - WhatsApp parser (`process_whatsapp_zip` + `parse_whatsapp_text`) for `_chat.txt` exports
  - Telegram parser (`process_telegram_json`) for `{"chats":{"list":[...]}}`
  - writes structured output to `/var/lib/dm-guide/imports/{bridge}/{timestamp}/messages.json`
  - uploaded temp files deleted in `finally` cleanup
- Task D: ran full `nix flake check` (all checks passed) and updated `.test-status`.

## Task Commits

- Task A: `78b4691` — `feat(60-02): add backup upload ui to dm guide`
- Task B: `229a7b5` — `feat(60-02): add backup decrypt and parsing pipeline`
- Task D: `1591c6c` — `test(60-02): run flake check and stamp test status`

## Files Created/Modified

- `modules/dm-guide.nix` (modified): backup upload UI, upload progress UI, multipart endpoint, bridge-specific backup processing functions, decision annotation DMG-05.
- `.test-status` (modified): updated after passing flake checks.
- `.planning/STATE.md` (modified): phase/plan position and decisions updated.
- `.planning/phases/60-dashboard-dm-pairing-backup-decrypt-guide/60-02-SUMMARY.md` (created): this execution summary.

## Decisions Made

- DMG-05: Keep decrypted/imported backup processing local to `dm-guide` service state directories (`/var/lib/dm-guide/uploads` and `/var/lib/dm-guide/imports`) to minimize exposure.
- Use stdlib-only multipart parsing instead of deprecated/removed `cgi` APIs for Python 3.13 compatibility.
- Use explicit store-path signalbackup-tools invocation (`${pkgs.signalbackup-tools}/bin/signalbackup-tools`) plus runtime existence check for graceful degradation.
- Standardize final artifact path to `/var/lib/dm-guide/imports/{bridge}/{timestamp}/messages.json` for downstream ingestion.

## Deviations from Plan

- [Rule 1 - Bug] During Task B implementation, SQL condition `body != ''` in embedded Python conflicted with Nix indented-string delimiters (`''`) and broke eval. Fixed by switching to `length(body) > 0`.

## Issues Encountered

- `nix search nixpkgs signalbackup` produced excessive output and was not needed because direct `nix eval nixpkgs#signalbackup-tools.version` already confirmed package availability.
- Existing repo-level eval warnings remain (SSH/git option rename warnings, `runCommandNoCC` rename warnings); none were introduced by this plan.

## Skipped Tasks (Scope)

- Task E (post-deploy SSH testing): intentionally skipped per execution scope; requires live host access.
