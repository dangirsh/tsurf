# Resolution Plan: Remove Root-Side Git Parsing From The Launch Path

> Note: the repo ultimately chose the simpler "top-level workspace under
> `/data/projects`" boundary instead of the filesystem-walk approach described
> here. This document remains the more flexible alternative plan for review.

## Finding

`scripts/agent-wrapper.sh` currently loads real provider keys from `/run/secrets`
and then runs `git rev-parse --show-toplevel` against the current repo before the
process enters `nono` or drops to the `agent` UID.

That means the privileged side of the launcher is still touching attacker-writable
repository metadata after secrets are in memory.

## Recommended Fix

Replace root-side Git-based repo discovery with filesystem-only repo-root
discovery, and complete all repo-scoping work before loading any secrets.

The preferred shape is:

1. Canonicalize and validate `PWD` against `AGENT_PROJECT_ROOT`.
2. Resolve the repo root with a pure filesystem walk that looks for a `.git`
   file or directory while walking parents upward.
3. Reject the launch if the resolved root is exactly the project root.
4. Only after the repo root is fixed, load allowlisted secrets from
   `/run/secrets`.
5. Launch `nono` with the resolved repo root and keep the existing credential
   proxy model.

This removes Git from the privileged path entirely.

## Why This Is The Right Fix

The core design intent in this repo is:

- root handles immutable policy and secret brokering
- the `agent` user handles attacker-controlled workspace state
- the child process sees phantom credentials, not raw ones

Running Git as root inside a mutable repo cuts against that model. A
filesystem-only walk restores the intended trust boundary without changing the
user-facing workflow.

## Concrete Implementation Plan

### 1. Replace `git rev-parse` with a path walk

In `scripts/agent-wrapper.sh`, add a helper similar to:

```bash
resolve_repo_root() {
  local dir="$1"
  local boundary="$2"

  while :; do
    if [[ -e "$dir/.git" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi

    if [[ "$dir" == "$boundary" ]]; then
      return 1
    fi

    dir="$(dirname "$dir")"
  done
}
```

Implementation details:

- Keep the existing `readlink -f` canonicalization for `PWD`.
- Ensure both `cwd` and `AGENT_PROJECT_ROOT` are canonicalized before walking.
- Treat either `.git` directory or `.git` file as sufficient. That supports
  normal repos and linked worktrees without parsing `.git/config`.
- Remove `git -c safe.directory='*' -C "$cwd" rev-parse --show-toplevel`.
- Remove the need for `safe.directory='*'` entirely.

### 2. Reorder the wrapper so secrets are loaded later

Keep the same secret-loading logic, but move it after repo-root resolution.

The new root-side order should be:

1. Validate environment and binary path.
2. Validate `cwd` is under `AGENT_PROJECT_ROOT`.
3. Resolve repo root with a path walk.
4. Reject `git_root == AGENT_PROJECT_ROOT`.
5. Load secrets from `/run/secrets`.
6. Invoke `nono`.

This shortens the time window in which raw secrets are present before `nono`
starts its credential proxy.

### 3. Preserve the current read-scope model

Keep `nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback --read "$git_root")`.

The point is to remove privileged parsing of repo metadata, not to widen the
sandbox. The current "active repo readable, broad project root not readable"
boundary should stay intact.

### 4. Add regression coverage

Add tests in three layers:

- Source-text regression check:
  Assert `scripts/agent-wrapper.sh` no longer contains
  `git rev-parse --show-toplevel` or `safe.directory='*'`.
- Behavioral wrapper test:
  Verify the wrapper still works from a normal repo and from a linked worktree
  where the repo root contains a `.git` file instead of a directory.
- Negative test:
  Verify launches still fail when the working directory is directly at
  `AGENT_PROJECT_ROOT`.

If you want one higher-value security regression, create a repo fixture with a
deliberately malformed `.git/config` and verify that wrapper repo discovery is
unaffected because it no longer parses Git metadata.

## Example Attack Scenario

### Current behavior

1. A prompt-injected agent modifies repo metadata under `.git/`.
2. The operator launches the agent again.
3. The root-owned wrapper loads real provider keys into its environment.
4. The wrapper runs Git in the attacker-controlled repo to discover the repo
   root.
5. Any Git parsing bug, unsafe metadata behavior, or future Git vulnerability
   now sits on the root side of the boundary while raw secrets are live.

### After the fix

1. The agent can still mutate `.git/config`, but the root wrapper never invokes
   Git or parses Git metadata.
2. Repo detection is reduced to path canonicalization plus checking whether a
   `.git` marker exists in parent directories.
3. Raw secrets are loaded only after the repo root is already fixed.

This does not depend on proving a current Git RCE path. It removes the entire
class of "privileged repo parsing after secret load" from the design.

## How This Fits The Overall Design

This change strengthens the existing architecture rather than changing it:

- It keeps `nono` as the sandbox primitive.
- It keeps the phantom-token credential flow intact.
- It keeps repo-scoped read access intact.
- It makes the root side more policy-only and less workspace-aware.

That is consistent with the repo's stated least-privilege and defense-in-depth
goals.

## Estimated Complexity

Estimated complexity: **Medium**

Roughly:

- 1 wrapper script change
- 1-3 test updates
- minor SECURITY/docs wording updates if you want the docs to describe the new
  repo-root resolution behavior precisely

This is a contained change with a clear acceptance criterion.

## Alternatives To Consider

### Alternative A: Move Git-based repo discovery after privilege drop

Idea:

- Drop to the `agent` UID first.
- Run `git rev-parse` as the unprivileged user.

Pros:

- Better than root-side Git parsing.

Cons:

- Hard to preserve the current repo-scoped `nono --read "$git_root"` model,
  because the repo root must be known before the sandbox is constructed.
- Often pushes you toward a wider initial read scope or a two-stage launcher.

Assessment:

- Better than today, but more awkward than a filesystem-only root walk.

### Alternative B: Trust a caller-supplied repo root

Idea:

- Let the wrapper accept a precomputed repo root from the caller.

Pros:

- Minimal wrapper logic.

Cons:

- Bad trust model.
- Easy to misuse or forge.
- Introduces a new footgun in exactly the part of the system that should be hard
  to misuse.

Assessment:

- Not recommended.

### Alternative C: Use a different repo parser or libgit implementation as root

Idea:

- Replace Git CLI with libgit2 or another parser.

Pros:

- Could give more structured behavior.

Cons:

- Still parses attacker-controlled repo metadata in a privileged context.
- Adds dependency and audit complexity without removing the trust-boundary flaw.

Assessment:

- Solves the wrong problem.

## Review Checklist

When reviewing the eventual patch, check these points:

- The root side no longer invokes `git` at all.
- Secrets are loaded only after repo root and path validation are complete.
- The wrapper still supports linked worktrees.
- The wrapper still rejects blanket access to `AGENT_PROJECT_ROOT`.
- The patch does not widen `nono` read permissions to compensate.
- Tests cover both normal repos and `.git`-file worktrees.

## Important Security And Design Considerations

- Do not widen the read boundary just to simplify implementation.
- Do not replace Git parsing with some other privileged parser of repo metadata.
- Keep symlink/canonicalization handling strict.
- Treat bare repos as unsupported unless you explicitly want to support them.
- Make sure the docs stop describing Git-based repo discovery if that behavior is
  removed.

## Suggested Acceptance Criteria

- Wrapper repo discovery no longer depends on Git.
- No privileged process touches mutable repo metadata after secrets are loaded.
- Existing launch UX remains unchanged for normal repos and worktrees.
- Test coverage proves the regression boundary.
