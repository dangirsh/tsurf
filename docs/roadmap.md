# Roadmap

This file tracks intentionally deferred work that should not be implemented as
part of incidental cleanup.

## Agent Egress Mediation

Status: TODO, do not implement until the design is re-evaluated.

The current agent egress policy is UID-scoped and port-based. It blocks private
and link-local ranges, but it still allows arbitrary external HTTPS and is not
strong containment for prompt-injected agents.

Before building a local egress proxy in tsurf, evaluate whether tsurf should use
or integrate with [Iron](https://iron.sh/) / `iron-proxy` instead. The relevant
shape to compare is:

- default-deny egress for untrusted workloads
- boundary-side credential injection
- per-request audit logs
- policy management that can scale across multiple agent hosts

Keep provider credential brokering and general egress mediation aligned. Avoid
creating two unrelated policy systems unless there is a clear reason.

## Validation Integrity

Status: TODO.

The public checks intentionally use a mix of eval assertions, source-text
guards, VM tests, and live tests. Improve the split so broad security claims are
backed by behavioral evidence where practical.

Next steps:

- keep the existing Linux CI path healthy, and document how non-Linux
  workstations should use `--all-systems --no-build` for local evaluation
- keep source-text guards, but label them as structural checks
- add focused runtime tests for credential proxying, egress denial, and wrapper
  execution paths
- add a fake-provider credential proxy test that proves the child receives only
  phantom credentials while the upstream sees the real injected header
- add a bounded `nono` patched-behavior test instead of relying only on
  `nono --help`
