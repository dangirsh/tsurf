# Quick Task 4 — Summary

## What Changed

Added two-level concurrent deploy locking to `scripts/deploy.sh`:

1. **Local lock** — `flock` on `/tmp/neurosys-deploy.local.lock` (fd 9, non-blocking). Prevents two deploys from the same machine. Graceful degradation if `flock` binary missing.
2. **Remote lock** — atomic `mkdir /var/lock/neurosys-deploy.lock` via SSH. Prevents deploys from different machines targeting the same server. Stores metadata in `info.txt` (holder, PID, timestamp, git SHA).
3. **Cleanup trap** — `trap cleanup EXIT` releases remote lock on any exit (success, failure, SIGINT, SIGTERM).
4. **Conflict diagnostics** — blocked deploys show lock holder info and manual removal instructions.

## Decisions

- @decision DL-01: Two-level deploy locking — local flock + remote mkdir (adapted from parts deploy.sh pattern)
- Lock acquisition placed after argument parsing (--help skips locks) but before flake update
- Lock paths namespaced to `neurosys-deploy` to avoid collision with parts deploy locks

## Files Modified

| File | Change |
|------|--------|
| scripts/deploy.sh | +43 lines: lock constants, cleanup(), trap, local flock, remote mkdir with metadata |

## Commit

`ef1fc65` — feat(quick-4): add concurrent deploy lock to deploy.sh
