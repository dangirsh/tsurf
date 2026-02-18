---
phase: quick-4
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/deploy.sh
autonomous: true

must_haves:
  truths:
    - "Two concurrent deploy.sh runs cannot overlap — second is blocked with a clear message"
    - "Lock is released on any exit (success, failure, SIGINT, SIGTERM)"
    - "Blocked run shows who holds the lock, when they took it, and what git SHA they deployed"
    - "Missing flock binary produces a warning but does not abort the deploy"
  artifacts:
    - path: "scripts/deploy.sh"
      provides: "Local flock + remote mkdir locking with metadata"
      contains: "flock"
  key_links:
    - from: "trap cleanup EXIT"
      to: "ssh $TARGET rm -rf /var/lock/neurosys-deploy.lock"
      via: "cleanup() function"
      pattern: "cleanup\\(\\)"
    - from: "ssh $TARGET mkdir"
      to: "/var/lock/neurosys-deploy.lock"
      via: "atomic mkdir (fails if exists)"
      pattern: "mkdir.*neurosys-deploy\\.lock"
---

<objective>
Add two-level concurrent deploy locking to scripts/deploy.sh to prevent simultaneous deploys from multiple agents or terminals.

Purpose: NixOS rebuilds are non-reentrant — two concurrent nixos-rebuild switch runs against the same host corrupt the system profile and can leave the server in a broken state.
Output: Updated scripts/deploy.sh with local flock + remote mkdir locking, cleanup trap, and informative conflict messages.
</objective>

<execution_context>
@/home/ubuntu/.claude/get-shit-done/workflows/execute-plan.md
@/home/ubuntu/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@scripts/deploy.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add local flock + remote mkdir locking with cleanup trap</name>
  <files>scripts/deploy.sh</files>
  <action>
Insert locking logic into scripts/deploy.sh between the variable declarations (after line 26, CONTAINERS array) and the argument parsing section. Add the following in order:

1. Add lock path constants after the CONTAINERS line (before `usage()`):
```bash
LOCAL_LOCK="/tmp/neurosys-deploy.local.lock"
REMOTE_LOCK_DIR="/var/lock/neurosys-deploy.lock"
REMOTE_LOCK_HELD=false
```

2. Add a `cleanup()` function just before `usage()`:
```bash
cleanup() {
  if [[ "$REMOTE_LOCK_HELD" == true ]]; then
    ssh "$TARGET" "rm -rf '$REMOTE_LOCK_DIR'" 2>/dev/null || true
  fi
}
trap cleanup EXIT
```

3. After argument parsing (after the `--mode` validation block, before the `# --- Update parts input ---` section), add the two-level lock acquisition:

```bash
# --- Local lock (prevent concurrent deploys from same machine) ---
exec 9>"$LOCAL_LOCK"
if command -v flock &>/dev/null; then
  if ! flock --nonblock 9; then
    echo "ERROR: Another deploy is already running on this machine (local lock held: $LOCAL_LOCK)."
    exit 1
  fi
else
  echo "WARNING: flock not available — local concurrent-deploy protection skipped."
fi

# --- Remote lock (prevent concurrent deploys from different machines) ---
GIT_SHA=$(git -C "$FLAKE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
LOCK_INFO="holder=$(whoami)@$(hostname)\npid=$$\ntimestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')\nsha=$GIT_SHA"

if ! ssh "$TARGET" "mkdir '$REMOTE_LOCK_DIR' 2>/dev/null && printf '$LOCK_INFO' > '$REMOTE_LOCK_DIR/info.txt'"; then
  echo "ERROR: Deploy already in progress on the remote server."
  echo ""
  echo "Lock info:"
  ssh "$TARGET" "cat '$REMOTE_LOCK_DIR/info.txt' 2>/dev/null" || echo "  (could not read lock metadata)"
  echo ""
  echo "If the previous deploy crashed, remove the lock manually:"
  echo "  ssh $TARGET rm -rf $REMOTE_LOCK_DIR"
  exit 1
fi
REMOTE_LOCK_HELD=true
```

Place the `cleanup()` + `trap` block before `usage()` so it's defined before any early exits. Place the lock acquisition block AFTER argument parsing and mode validation (so --help and bad-flag paths don't try to acquire locks), but BEFORE the flake update step.

Do NOT use printf with escape sequences in the SSH heredoc — use `echo -e` or a local variable approach. The `LOCK_INFO` variable with `\n` will be interpreted by `printf` server-side, which is correct.
  </action>
  <verify>
    1. `bash -n scripts/deploy.sh` passes (no syntax errors).
    2. Review the diff: lock constants, cleanup(), trap, local flock block, and remote mkdir block are all present.
    3. `grep -n "flock\|REMOTE_LOCK\|cleanup\|trap" scripts/deploy.sh` shows all five insertion points.
  </verify>
  <done>
    scripts/deploy.sh has: LOCAL_LOCK + REMOTE_LOCK_DIR constants, cleanup() that SSH-removes the remote lock dir, trap cleanup EXIT, local flock with graceful degradation warning, remote mkdir with info.txt write, and REMOTE_LOCK_HELD flag set to true on success. bash -n passes.
  </done>
</task>

</tasks>

<verification>
After implementation:
- `bash -n scripts/deploy.sh` — syntax check passes
- `grep -c "flock\|REMOTE_LOCK\|cleanup\|trap" scripts/deploy.sh` — returns >= 5 matches
- Visually confirm cleanup trap is registered before lock acquisition
- Confirm local flock block comes after argument parsing (not before --help path)
</verification>

<success_criteria>
scripts/deploy.sh rejects a second concurrent invoke with a clear error message, releases the remote lock on any exit, and degrades gracefully when flock is absent.
</success_criteria>

<output>
After completion, create `.planning/quick/4-add-concurrent-deploy-lock-to-deploy-sh/4-01-SUMMARY.md` following the summary template.
</output>
