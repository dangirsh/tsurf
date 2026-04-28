# Git Policy

- Always finish work with a commit on `main` and push `main` to `origin`.
- Codex should do this automatically after finishing work unless the user
  explicitly asks not to commit or not to push.
- `tsurf` is intentionally public.
- Every related repo outside `tsurf` should stay backed by a private GitHub repo.

# Deploy Policy

- Real host deploys should come from the private overlay, not directly from this public repo.
- Use the private overlay wrapper `./scripts/deploy.sh --node <node>` as the canonical deploy path.
- Avoid direct `nixos-rebuild switch` on the target host except for explicit emergency recovery.
