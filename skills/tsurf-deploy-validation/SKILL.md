---
name: tsurf-deploy-validation
description: Validate a tsurf public repo or private overlay before deployment. Use when an agent is about to run checks, prepare a deploy, override a deploy target, verify rollback/recovery safety, or decide whether a tsurf host change is safe enough to push.
---

# Tsurf Deploy Validation

Use this skill after a public tsurf or private overlay edit. Separate validation
from deployment; a green eval is not authorization to deploy a real host.

## Public Repo Validation

1. Run `nix flake check --all-systems --no-build` for cross-system evaluation.
2. If a Linux builder is available, build `.#checks.x86_64-linux.shellcheck-tests`
   and `.#checks.x86_64-linux.unit-tests`.
3. Run direct shell tests on the workstation when changing scripts:
   `for test in tests/unit/*.bash; do bash "$test"; done`.
4. Explain any skipped Linux/VM/live checks explicitly.
5. Do not claim credential proxy runtime proof unless an end-to-end fake-provider
   or live-provider test actually exercised the brokered request path.

## Private Overlay Validation

1. Confirm the public repo worktree is clean or only contains intended changes.
2. In the private overlay, run `nix flake check --no-build` first. Use full
   builds only when the builder and secrets/state requirements are clear.
3. Verify deploy nodes point at the intended hosts. If using `--target`, confirm
   it overrides both SSH checks and deploy-rs hostname.
4. Confirm root SSH access and rollback path before any real deploy.
5. Treat direct public HTTPS egress from the agent UID as an accepted risk unless
   the overlay has implemented additional egress mediation.

## Deploy Rules

- Deploy only from a private overlay.
- Prefer `./scripts/deploy.sh --node <node>`.
- Use `--target user@host` only when intentionally overriding the deploy node's
  configured hostname, such as recovery or migration testing.
- Avoid direct `nixos-rebuild switch` except for explicit emergency recovery.
