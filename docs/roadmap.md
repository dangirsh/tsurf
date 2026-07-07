# Roadmap

This file tracks intentionally deferred work that should not be implemented as
part of incidental cleanup.

## Agent Egress Mediation

Status: Initial Iron-backed implementation added; continue hardening with live
tests and provider-specific rollout validation.

The current agent-host path keeps `nono` as the local filesystem/process
sandbox and uses [Iron](https://iron.sh/) / `iron-proxy` as the preferred
egress and credential-broker layer when the Iron egress proxy is enabled.
Iron-backed generated profiles allow loopback proxy access, while nftables
switches the agent UID to mediated-only egress and drops direct DNS and public
network traffic.

The remaining target shape is:

- default-deny egress for untrusted workloads
- boundary-side credential injection
- per-request audit logs
- policy management that can scale across multiple agent hosts

Keep provider credential brokering and general egress mediation aligned. Avoid
creating two unrelated policy systems unless there is a clear reason.

Review status: the 2026-07-02 landscape review in
[`docs/security-plans/sandbox-secret-proxy-landscape-2026.md`](security-plans/sandbox-secret-proxy-landscape-2026.md)
recommended keeping `nono` as the default local sandbox and prototyping
`iron-proxy` as the egress and richer credential-broker layer.

Implementation status: `modules/agent-egress-proxy.nix` packages and runs
`iron-proxy`, generated agents use Iron for credential replacement, and
nftables switches to mediated-only agent UID egress when Iron is enabled.
Remaining work is live-host validation, provider SDK compatibility hardening,
and richer per-agent policy bundles.

## Validation Integrity

Status: TODO.

The public checks intentionally use a mix of eval assertions, source-text
guards, VM tests, and live tests. Improve the split so broad security claims are
backed by behavioral evidence where practical.

Next steps:

- keep the existing Linux CI path healthy, and document how non-Linux
  workstations should use `--all-systems --no-build` for local evaluation
- reduce source-text guards and keep only structural checks that cannot be
  expressed behaviorally
- add more focused runtime tests for egress denial and wrapper execution paths
  beyond the existing Iron-backed credential replacement VM proof
