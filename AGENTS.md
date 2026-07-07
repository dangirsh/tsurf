# Git Policy

- Agent-authored changes should be committed on `main` and pushed directly to
  `origin/main`, unless the user explicitly asks for a branch or pull request.
- Do not open pull requests unless the user explicitly requests one.
- Codex should still commit and push completed work unless the user explicitly
  asks not to.
- `tsurf` is intentionally public.
- Every related repo outside `tsurf` should stay backed by a private GitHub repo.

# Deploy Policy

- Real host deploys should come from the private overlay, not directly from this public repo.
- Use the private overlay wrapper `./scripts/deploy.sh --node <node>` as the canonical deploy path.
- Avoid direct `nixos-rebuild switch` on the target host except for explicit emergency recovery.
