# Resolution Plan: Replace Port-Only Egress With Mediated Destination Policy

## Finding

`modules/networking.nix` currently allows the `agent` UID to reach any external
host on TCP `22`, `80`, and `443`, plus DNS.

That is a reasonable general-purpose firewall, but it is not strong containment
for prompt-injected agents. A compromised agent can still exfiltrate the current
repo over arbitrary HTTPS.

## Recommended Fix

Move from a port-only egress policy to a mediated egress design:

1. Agent workloads should have **no direct outbound network access** except
   loopback.
2. Allowed outbound HTTP(S) should go through a **local egress proxy** with a
   per-agent hostname allowlist.
3. Provider API traffic should continue to use the existing `nono` credential
   proxy on loopback.
4. Git/network workflows should default to HTTPS through the proxy, not raw SSH.

In short: keep the current "local broker" philosophy for credentials, and apply
the same pattern to general outbound network access.

## Why This Is The Right Fix

The current design already trusts local mediation for credentials:

- raw provider keys stay on the root side
- the child talks to loopback base URLs
- the proxy injects the real upstream credentials

Egress should follow the same philosophy:

- the agent talks to loopback
- a local broker decides which upstream destinations are allowed
- direct Internet access from the agent UID is not trusted

This is the only fix that meaningfully addresses the stated prompt-injection
threat model without simply turning networking off.

## Concrete Implementation Plan

### 1. Introduce an explicit agent egress proxy

Add a new module, likely something like `modules/agent-egress-proxy.nix`, with a
local service that:

- listens on loopback or a Unix socket
- supports HTTP and HTTPS `CONNECT`
- does **not** terminate TLS or inspect payloads
- authorizes requests by destination hostname
- rejects raw IP destinations
- resolves DNS itself
- emits allow/deny logs for review

The proxy should be scoped to agent traffic only. If it listens on loopback TCP,
consider requiring a per-session token from the launcher so other local processes
cannot reuse it casually.

### 2. Add per-agent egress policy to the launcher model

Extend `services.agentLauncher.agents.<name>` with something like:

```nix
egress = {
  enable = true;
  allowedHosts = [
    "github.com"
    "api.github.com"
    "objects.githubusercontent.com"
    "registry.npmjs.org"
    "api.anthropic.com"
  ];
};
```

Implementation notes:

- Keep hostnames declarative and per-agent, like the existing credential service
  model.
- Allow named bundles later if the flat host list becomes unwieldy.
- Make "no extra egress beyond provider proxies" the default for new agents.

### 3. Export proxy settings from the launcher

Update `modules/agent-launcher.nix` so managed agent sessions receive:

- `HTTPS_PROXY`
- `HTTP_PROXY`
- `ALL_PROXY` if useful for the chosen proxy implementation
- `NO_PROXY=127.0.0.1,localhost`
- optionally a per-session egress token

The goal is for common tools (`curl`, `git` over HTTPS, many package managers,
language SDKs) to route naturally through the broker with no manual operator
steps.

### 4. Tighten nftables so agents only reach loopback directly

Change the `agent-egress` nftables policy from:

- loopback + DNS + arbitrary `22/80/443`

to:

- loopback only
- optionally nothing else for the `agent` UID

The proxy service itself will run outside the `agent` UID and make the approved
upstream connections on the agent's behalf.

Important detail:

- block direct UDP `443` as well, so QUIC/HTTP3 does not become a bypass path
- if the agent no longer needs direct DNS, remove DNS egress from the agent UID

### 5. Keep provider traffic on the existing `nono` path

Do not replace the current credential proxy. Reuse it.

The resulting model becomes:

- provider API calls: agent -> `nono` loopback proxy -> upstream provider
- other approved HTTP(S): agent -> local egress proxy -> approved upstream
- everything else: denied

This preserves the strongest part of the current design while extending it.

### 6. Decide the default Git transport

For a secure-by-default rollout, Git should prefer HTTPS through the local proxy.

Recommended default:

- Git over HTTPS is the standard path for sandboxed agents.
- Git over SSH becomes an explicit opt-in exception, not a general default.

Reason:

- raw outbound TCP `22` is hard to mediate cleanly by hostname
- domain-aware policy is much easier with HTTPS proxying than raw SSH

### 7. Add regression coverage

Add tests in three layers:

- Eval checks:
  Assert the agent UID no longer gets direct `22/80/443` egress by default.
- Live tests:
  Verify agent traffic to an approved host succeeds and traffic to an arbitrary
  Internet host fails.
- Launcher behavior tests:
  Verify wrappers export proxy environment variables when egress mediation is
  enabled.

One especially useful live test is:

- agent can reach the configured provider loopback endpoint
- agent cannot `curl https://example.com`

## Example Attack Scenario

### Current behavior

1. A malicious README or prompt tells the agent to archive the repo and upload it
   to `https://attacker.example/upload`.
2. The agent runs `curl`, `python requests`, or another HTTPS client.
3. DNS and outbound `443` are allowed.
4. Exfiltration succeeds.

### After the fix

1. The agent only has loopback access.
2. Direct outbound HTTPS is dropped by nftables.
3. If the agent uses the local proxy, the proxy checks the destination hostname.
4. `attacker.example` is not on the allowlist, so the request is denied and
   logged.

This directly blocks the current most obvious prompt-injection exfiltration path.

## How This Fits The Overall Design

This change is a natural extension of the repo's existing design principles:

- least privilege by default
- local brokers for privileged capabilities
- declarative policy per agent
- defense in depth rather than trusting the agent process

It also makes the network boundary more consistent with the credential boundary:
both become mediated, local, and explicit.

## Estimated Complexity

Estimated complexity: **High**

This is a larger design change than the wrapper fix. Expect:

- 1 new module for the egress proxy
- launcher changes for env injection and policy wiring
- nftables policy changes
- test updates across eval and live suites
- documentation updates for networking and operations

If implemented carefully, this is still tractable, but it is not a one-file
change.

## Recommended Rollout Strategy

### Phase 1: Introduce the mediation path

- Add the proxy service and per-agent allowlist config.
- Export proxy env vars from wrappers.
- Keep a temporary compatibility flag for direct `22/80/443` egress.

### Phase 2: Flip the default

- New agents default to mediated egress only.
- Existing agents can opt into the compatibility mode temporarily.

### Phase 3: Remove the compatibility mode

- Direct outbound Internet access from the `agent` UID is no longer the normal
  path.
- SSH egress becomes rare and explicit.

This phased rollout reduces breakage while still aiming at a strong default.

## Alternatives To Consider

### Alternative A: Keep nftables, but switch to hostname/IP allowlists only

Idea:

- Resolve approved hostnames to IPs and place those IPs in nftables sets.

Pros:

- Less new moving parts than a proxy.

Cons:

- Brittle with CDNs, rotating IPs, IPv6, and multi-host service dependencies.
- Harder to reason about than a hostname-aware broker.
- Direct IP connections remain awkward to police.
- Does not compose as cleanly with the current credential-proxy pattern.

Assessment:

- Acceptable only as an interim measure, not the preferred end state.

### Alternative B: Disable network access for agents by default

Idea:

- Agents get no network unless manually widened.

Pros:

- Strongest containment.

Cons:

- Too user-hostile for the workflows this repo is trying to support.
- Breaks normal Git, API, and package workflows.

Assessment:

- Useful as a special high-security mode, not as the primary default.

### Alternative C: Per-agent network namespace or MicroVM with strict proxying

Idea:

- Push agents into a stronger network-isolated execution environment.

Pros:

- Better containment boundary than UID-scoped host firewall rules.

Cons:

- More operational complexity.
- Higher user friction.
- Does not remove the need for an outbound destination policy.

Assessment:

- Worth considering later, but still benefits from the same mediated egress
  design.

## Review Checklist

When reviewing the eventual patch, check these points:

- Agent direct outbound Internet access is actually gone by default.
- The proxy does not allow raw IP destinations.
- The proxy does not require TLS interception to enforce policy.
- QUIC/UDP bypasses are addressed.
- Provider traffic still works through `nono`.
- Git/package-manager workflows remain usable for the approved-host cases.
- Denied outbound attempts are observable in logs.

## Important Security And Design Considerations

- Avoid turning the proxy into an accidental general-purpose open proxy.
- Decide whether loopback TCP is sufficient or whether a Unix socket plus file
  permissions is cleaner.
- If the proxy uses loopback TCP, add an auth token or UID check to reduce local
  reuse by unrelated processes.
- Package ecosystems often need more than one hostname; plan for host bundles so
  policy stays manageable.
- Keep the proxy dumb where possible: hostname ACL plus pass-through transport is
  better than a complex MITM design.
- If SSH must remain available, treat it as an explicit exception path with much
  tighter controls than today's blanket TCP `22`.

## Suggested Acceptance Criteria

- A prompt-injected agent can no longer exfiltrate to an arbitrary external HTTPS
  endpoint by default.
- Approved provider traffic and approved Git/package-manager traffic still work.
- Egress policy becomes declarative per agent instead of global-by-port.
- The default network story matches the repo's stated prompt-injection threat
  model.
