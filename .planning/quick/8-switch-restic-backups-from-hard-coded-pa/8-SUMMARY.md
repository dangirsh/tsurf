# Quick Task 8 Summary: Switch restic to blanket backup

## What Changed

### modules/restic.nix
- Replaced 8 hard-coded `paths` with `paths = [ "/" ]`
- Added `extraBackupArgs`: `--one-file-system`, `--exclude-caches`, `--exclude-if-present .nobackup`
- Expanded `exclude` list: `/nix`, Docker layers, `/var/cache`, `**/.cache`, `/var/lib/prometheus`, git internals, build artifacts
- Added `@decision RESTIC-05` annotation documenting the blanket approach
- Updated `RESTIC-04` annotation (removed path-specific language)

### docs/recovery-runbook.md
- Added blanket backup explanation to Section 3 (What's Where)
- Added "All other `/var/lib/*` state" row to data table
- Replaced Steps 2.4-2.7 (individual restores) with Option A (full restore) and Option B (selective)
- Retitled Section 9 from "What's NOT Backed Up" to "Excluded from Backup" with full exclusion table
- Documented `.nobackup` sentinel and `CACHEDIR.TAG` auto-exclusion
- Updated "When to re-test" section

## Key Decisions
- **RESTIC-05**: Blanket `/` backup with `--one-file-system` + exclusions. New stateful data auto-included; opt-out via `.nobackup` sentinel or explicit exclude.

## Newly Covered Paths (previously missed)
- `/var/lib/syncthing/` — device certificates and database
- `/var/lib/nixos/` — UID/GID mappings (important for ownership stability)
- `/var/lib/fail2ban/` — ban database
- `/var/lib/esphome/` — ESPHome configs
- `/boot` — bootloader (tiny, harmless to include)

## Verification
- `nix flake check` passes
