# Git Policy

- Normal agent-authored changes should be made on `codex/...` branches and
  landed through pull requests.
- Do not push directly to `main` unless the user explicitly requests it for the
  current task.
- Codex should still commit completed work unless the user explicitly asks not
  to commit.
- `tsurf` is intentionally public.
- Every related repo outside `tsurf` should stay backed by a private GitHub repo.

# Deploy Policy

- Real host deploys should come from the private overlay, not directly from this public repo.
- Use the private overlay wrapper `./scripts/deploy.sh --node <node>` as the canonical deploy path.
- Avoid direct `nixos-rebuild switch` on the target host except for explicit emergency recovery.
