# Roadmap

This file tracks intentionally deferred work that should not be implemented as
part of incidental cleanup.

## Agent Egress Mediation

Status: Initial Iron-backed implementation added; continue hardening with live
tests and provider-specific rollout validation.

The current default blocks direct sandbox networking in nono and uses a
UID-scoped nftables policy as a host-level backstop. This prevents configured
credential proxy routes from becoming an allow-all CONNECT proxy, but it is
still not a general destination-aware egress mediation layer for every workflow.

Before building a local egress proxy in tsurf, evaluate whether tsurf should use
or integrate with [Iron](https://iron.sh/) / `iron-proxy` instead. The relevant
shape to compare is:

- default-deny egress for untrusted workloads
- boundary-side credential injection
- per-request audit logs
- policy management that can scale across multiple agent hosts

Keep provider credential brokering and general egress mediation aligned. Avoid
creating two unrelated policy systems unless there is a clear reason.

Review status: the 2026-07-02 landscape review in
[`docs/security-plans/sandbox-secret-proxy-landscape-2026.md`](security-plans/sandbox-secret-proxy-landscape-2026.md)
recommends keeping `nono` as the default local sandbox and prototyping
`iron-proxy` as the egress and richer credential-broker layer.

Implementation status: `modules/agent-egress-proxy.nix` packages and runs
`iron-proxy`, generated agents can use Iron as the default credential proxy,
and nftables switches to mediated-only agent UID egress when Iron is enabled.
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
- keep source-text guards, but label them as structural checks
- keep the fake-provider credential proxy VM test healthy, including the
  no-raw-key and no-generic-proxy assertions
- add more focused runtime tests for egress denial and wrapper execution paths
- add a bounded `nono` patched-behavior test instead of relying only on
  `nono --help`
