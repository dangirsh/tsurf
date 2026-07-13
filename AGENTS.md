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

# Security-Sensitive Agent Work

- Never pass bearer tokens, OAuth secrets, cookies, or credential placeholders in process arguments. Use a root-only `EnvironmentFile` or an already-open descriptor, and add a regression test that polls `/proc/*/cmdline` with a fake sentinel.
- Credential launcher changes must preserve the UID drop, nono sandbox, Iron substitution, and per-session PID isolation. Run the credential-proxy VM test before pushing.
- Never print complete environments or secret-bearing configuration in task output. Query only the specific non-secret field needed for diagnosis.
