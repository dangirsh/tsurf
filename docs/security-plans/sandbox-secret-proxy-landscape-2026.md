# Sandboxing And Secret Proxy Landscape Review

Research date: 2026-07-02

## Executive Decision

Keep `nono` as the default local process sandbox for `tsurf`.

The current `tsurf` use case is lightweight, interactive and unattended coding
agents on personally operated NixOS hosts. For that shape, `nono` remains the
best fit I found: it is a single Linux process sandbox, is already packaged from
pinned source in this repo, maps cleanly to declarative profiles, and uses
Landlock instead of adding a container or VM control plane.

Do not treat `nono` as the complete answer. The market has moved toward a
separate "sandbox plus egress gateway plus secret broker" architecture. `tsurf`
already approximates this with `nono` plus nftables plus sops-nix, but the
general egress and richer credential-brokering layers are weaker than the best
newer tooling.

Recommended direction:

1. Keep `nono` for filesystem, subprocess, and per-agent local sandboxing.
2. Add an optional, then default, destination-aware egress proxy. `iron-proxy`
   is the strongest current candidate for this role.
3. Keep sops-nix as the system of record for secrets.
4. Gradually move provider credential injection from "inside the root-side
   `nono` supervisor path" toward a dedicated broker process where practical.
5. Use microVM or hosted sandbox providers only for higher-risk multi-tenant,
   customer-submitted, browser/desktop, GPU, or burst-scale workloads.

## Current `tsurf` Baseline

The public design today is already stronger than a normal agent CLI launch:

- `modules/nono.nix` installs a base `nono` profile with sensitive home paths
  and `/run/secrets` denied.
- `modules/agent-launcher.nix` generates immutable launchers, per-agent `nono`
  profiles, sudo rules, transient systemd units, resource limits, and credential
  service mappings.
- `scripts/agent-wrapper.sh` scopes the current top-level workspace, refuses the
  project root as a blanket scope, loads only allowlisted secret files, starts
  `nono`, and exposes only provider base URLs plus phantom proxy tokens to the
  final agent child.
- `modules/networking.nix` adds UID-scoped nftables policy, blocks metadata and
  private ranges, and reserves loopback ports for credential proxies.
- `packages/nono.nix` builds `nono` from pinned source and carries two local
  hardening patches: `env://` credential URI support and removal of broad
  upstream `/run` and `/var/run` grants.

The material residual gaps are:

- The agent UID still has broad direct TCP `22`, `80`, and `443` egress, so a
  prompt-injected agent can exfiltrate current workspace data over arbitrary
  public HTTPS unless `nono` network blocking catches the specific path.
- The credentialed path runs the `nono` supervisor from a root-owned transient
  unit. Upstream `nono` emphasizes that its supervisor is normally not a
  privilege-escalation target because it runs unprivileged; `tsurf` deliberately
  changes that boundary so the wrapper can read root-owned secrets and drop
  privileges later. The systemd capability and syscall filters reduce exposure,
  but a root-side supervisor/proxy bug would still be more consequential than
  in upstream's default local workflow.
- `nono`'s reverse proxy is good for static provider API key injection, but it
  is not as complete as purpose-built egress brokers for OAuth minting, AWS/GCP
  signing, per-request durable audit logs, broad secret backend integrations,
  and MCP tool-policy mediation.
- The security properties of network isolation depend on host kernel support
  and on the nftables backstop. `nono`'s Landlock TCP filtering needs Linux
  6.7+; older kernels still get filesystem isolation, but network enforcement
  needs host policy.

## What Professional Agent Tools Are Doing

### Cloud coding agents

GitHub Copilot cloud agent runs in an ephemeral GitHub Actions-powered
development environment, has a configurable firewall, and has dedicated
"Agents" secrets and variables. The important caveat is that those secrets are
still exposed as environment variables to the agent environment, except
MCP-prefixed secrets that are limited to MCP server config. GitHub also
documents firewall limitations: it applies only to processes started by the
agent's Bash tool, not MCP servers or setup steps, and should not be treated as
a comprehensive security solution.

Devin's documented model is a virtual-machine snapshot per session. That is the
standard professional cloud-agent direction: give the agent its own "computer"
instead of letting it run against the operator's normal host state.

Cursor, GitHub Copilot, Devin, OpenAI Agents SDK providers, Daytona, E2B and
similar services are all converging on managed workspace sandboxes. This is the
right default when the provider owns the runtime, must scale many tenants, or
needs browser/desktop/GPU support. It is less aligned with `tsurf`'s goal of
small personal NixOS hosts where the OS is already the agent execution substrate.

### Local professional CLIs

Claude Code now documents several isolation options. Its built-in sandboxed
Bash tool uses Seatbelt on macOS and bubblewrap on Linux/WSL2, but it covers
only Bash commands and child processes. Claude's own docs recommend running the
whole process inside a sandbox runtime, container, or VM when built-in tools,
MCP servers and hooks must be inside one boundary.

This validates `tsurf`'s design choice to wrap the full agent process outside
the agent's own permission model. Tool-level allow/ask prompts are useful, but
they are not a containment boundary.

### Agent SDKs and sandbox providers

OpenAI's Agents SDK sandbox docs frame sandboxes as a separate execution
boundary with provider choice: Unix-local, Docker, E2B, Daytona, Modal,
Cloudflare, Vercel, Runloop, Blaxel and others. The same docs explicitly call
out the architecture where the harness can run outside the sandbox while the
sandbox handles files, commands, ports and provider state. That split is the
cleaner long-term shape for `tsurf`: trusted orchestration outside, untrusted
execution inside.

E2B, Daytona and Modal are representative of the managed sandbox market:

- E2B focuses on fast, secure Linux VM sandboxes for agents and code execution.
  Its public positioning emphasizes Firecracker microVM isolation.
- Daytona provides composable agent "computers" with dedicated kernel,
  filesystem, network stack, CPU, RAM and disk, plus per-sandbox firewall
  policy.
- Modal positions its sandboxes around gVisor-isolated compute, high
  concurrency and GPU availability.

These are good options for a hosted product or a high-risk sandbox tier. They
are not a better default for `tsurf` because they add an external control plane,
credentials, cost model, provider state and weaker NixOS-native declarative
integration.

## Tool Assessment

### `nono`

Best role in `tsurf`: default local OS sandbox.

Strengths:

- Very lightweight: no daemon, container runtime or VM required.
- Good NixOS fit: source-buildable Rust package, profile JSON can be emitted by
  Nix modules, no mutable runtime control plane required.
- Strong filesystem model for this use case: Landlock-backed allow/deny rules
  map well to "current workspace plus selected runtime paths".
- Credential proxy path matches agent SDK expectations by setting provider base
  URLs and session tokens.
- Good developer ergonomics for interactive CLI agents.

Weaknesses:

- Not a VM boundary. Kernel bugs, Landlock gaps, IPC/socket edges and host
  namespace assumptions still matter.
- Network mediation is less mature than dedicated egress products.
- The root-owned `tsurf` credential path changes upstream's "unprivileged
  supervisor" risk profile.
- Built-in credential handling is simpler than Iron's transform model.

Verdict:

Use it. Do not replace it with Docker, bubblewrap, systemd-nspawn or a hosted
sandbox for the mainline `tsurf` path.

### Iron / `iron-proxy`

Best role in `tsurf`: default-deny egress gateway and richer secret broker.

Strengths:

- Purpose-built for untrusted workloads, AI coding agents and CI.
- Default-deny HTTP/HTTPS egress by hostname, glob, URL path and CIDR.
- Boundary-side credential injection and replacement. Workloads can use proxy
  tokens or no secret at all.
- Supports static secrets, OAuth2 token minting, HMAC, AWS SigV4, GCP service
  accounts, 1Password, AWS Secrets Manager and AWS SSM.
- Per-request structured JSON audit logs and OTel-ready export.
- DNS-rebinding and denied-upstream-CIDR protections.
- MCP interception for Streamable HTTP MCP: tool allowlists, argument matchers,
  filtered `tools/list`, and tool-call audit records.
- Single Go binary plus YAML, so a NixOS module should be straightforward.

Costs and risks:

- It is not a filesystem/process sandbox. It complements `nono`; it does not
  replace it.
- For transparent HTTPS inspection and header rewriting, it terminates TLS and
  requires a trusted CA in the workload environment. In `tsurf`, that CA should
  be scoped to the agent runtime, not installed broadly into operator trust if
  avoidable.
- Routing enforcement still needs nftables or TPROXY-style plumbing to prevent
  direct non-proxy egress.
- It is a newer project than Envoy/Squid/gVisor/Firecracker. Start as an
  optional module and test the failure modes before making it default.

Verdict:

This is the most interesting upgrade. It should replace the planned custom
local egress proxy work unless a prototype finds a hard incompatibility. It may
eventually replace `nono`'s provider credential proxy for some services, but the
first integration should be additive.

### Containers, bubblewrap, nsjail, systemd-nspawn

Best role in `tsurf`: optional compatibility boundary, not default.

Strengths:

- Familiar ecosystem and a lot of operational knowledge.
- Good for packaging full dev environments.
- bubblewrap is already used by Claude Code on Linux for its Bash sandbox.
- systemd-nspawn integrates with NixOS better than Docker for simple machine
  containers.

Weaknesses:

- Containers share the host kernel and usually require a broader daemon,
  namespace, mount and image lifecycle.
- Docker membership is effectively host root, which conflicts with `tsurf`'s
  agent user model.
- More mutable state and image-building friction than `nono`.

Verdict:

Useful as a per-agent override when a workflow needs a containerized dev
environment. Not a better default for `tsurf`.

### gVisor, Kata, Firecracker, microvm.nix

Best role in `tsurf`: high-risk execution tier.

Strengths:

- Stronger tenant isolation than Landlock or ordinary containers.
- Better fit for arbitrary customer-submitted code, malware-adjacent tasks,
  browser automation, untrusted MCP servers, or agents running infrastructure
  repos.
- Firecracker/microVM models align with E2B/Vercel/Blaxel and many production
  agent sandbox platforms.

Weaknesses:

- Heavier startup, image, networking, snapshot, storage and orchestration
  complexity.
- Harder to make "lightweight and highly configurable" inside the existing
  NixOS module model.
- Requires a second environment lifecycle beside the host's project checkout.

Verdict:

Do not make this the default. Add a separate "high risk sandbox" path later,
likely via `microvm.nix`, Cloud Hypervisor/Firecracker, or a hosted provider for
workloads that are not appropriate for the main `agent` user.

### AppArmor, SELinux, systemd hardening and nftables

Best role in `tsurf`: defense-in-depth host policy.

Strengths:

- systemd and nftables are already NixOS-native and should remain in the core.
- AppArmor/SELinux can enforce host-level policy independent of the agent
  wrapper.

Weaknesses:

- LSM profiles are operationally heavier than per-agent JSON/Nix policy.
- They do not solve secret brokering or destination-aware HTTP policy by
  themselves.

Verdict:

Keep strengthening systemd/nftables. Consider AppArmor only if a concrete
escape class or compliance requirement justifies the profile maintenance cost.

## Recommended `tsurf` Architecture

Target shape:

```text
root/operator/sops-nix
  -> root-owned launcher
    -> trusted egress/secret broker service
    -> nono sandbox boundary
      -> setpriv/drop to agent user
        -> agent process
```

Network:

```text
agent direct network:
  allow loopback only

provider API traffic:
  agent -> nono credential proxy, or iron-proxy once proven -> upstream

general approved HTTP(S):
  agent -> iron-proxy -> approved upstream

everything else:
  nftables drop or proxy 403, with audit log
```

Phased implementation:

1. Package `iron-proxy` from source in `packages/iron-proxy.nix`.
2. Add `modules/agent-egress-proxy.nix` as opt-in, with declarative per-agent
   host/path allowlists and sops-backed secret sources.
3. Start Iron as a hardened systemd service or per-agent transient sidecar:
   `NoNewPrivileges`, tight `CapabilityBoundingSet`, `PrivateTmp`,
   `ProtectSystem=strict`, `ProtectHome=true`, explicit `LoadCredential` or
   sops template inputs, and structured logs to journald.
4. Inject proxy environment only into the final agent child. Install the Iron
   CA into an agent-scoped trust path if MITM mode is used.
5. Change default agent UID egress to loopback-only when the egress proxy is
   enabled. Remove direct DNS and public `22/80/443` from the default path.
6. Keep current `nono` provider credential proxy initially. Once Iron is stable,
   compare each provider:
   - simple OpenAI/Anthropic/OpenRouter static keys can stay on `nono` or move
     to Iron replacement mode;
   - OAuth, AWS/GCP, database, MCP and path/method-scoped secrets should prefer
     Iron.
7. Add VM/live tests:
   - arbitrary HTTPS exfil fails;
   - approved dependency/API host succeeds;
   - denied host is logged;
   - raw provider key is not in child env;
   - proxy token cannot be used from another local UID;
   - Iron crash fails closed.

## Decision Matrix

| Option | Keep agents off private files | Keep secrets out of child | Destination-aware egress | NixOS fit | Weight | Decision |
| --- | --- | --- | --- | --- | --- | --- |
| Current `nono` + nftables | Good | Good for supported providers | Partial | Excellent | Light | Keep |
| `nono` + Iron | Good | Excellent | Strong | Good | Light-medium | Recommended target |
| Docker/devcontainer | Medium | Depends on env | Needs extra proxy | Good | Medium | Optional |
| bubblewrap/nsjail only | Medium-good | No broker | Needs extra proxy | Medium | Light | Not better than `nono` |
| systemd-nspawn | Good | Needs broker | Needs extra proxy | Good | Medium | Optional |
| gVisor/Kata/Firecracker | Excellent | Needs broker | Needs proxy | Medium | Heavy | High-risk tier |
| E2B/Daytona/Modal hosted | Excellent | Provider-specific | Provider-specific | Low-medium | External | Special cases |

## Bottom Line

`nono` is still the right default sandbox for `tsurf`, but the best modern
professional pattern is not "one sandbox binary does everything". It is:

- a local OS sandbox for least-privilege execution,
- a default-deny egress gateway,
- a credential broker that owns real secrets,
- host firewall rules that make bypasses fail closed,
- stronger VM isolation only for workloads whose risk justifies the weight.

For `tsurf`, that means: keep `nono`, add Iron-style egress and secret brokering,
and reserve microVMs/hosted sandboxes for a separate high-risk execution mode.

## Sources

- `tsurf` local implementation:
  - `modules/nono.nix`
  - `modules/agent-launcher.nix`
  - `modules/networking.nix`
  - `scripts/agent-wrapper.sh`
  - `packages/nono.nix`
- Iron:
  - https://iron.sh/
  - https://docs.iron.sh/
  - https://docs.iron.sh/use-cases/ai-coding-agents
  - https://docs.iron.sh/credential-proxying/static-secrets
  - https://docs.iron.sh/credential-proxying/oauth-token
  - https://docs.iron.sh/policies/mcp-interception
  - https://github.com/ironsh/iron-proxy
- `nono`:
  - https://github.com/nolabs-ai/nono
  - https://nono.sh/docs/cli/features/credential-injection
  - https://nono.sh/docs/cli/features/networking
  - https://nono.sh/docs/cli/internals/security-model
  - https://nono.sh/docs/cli/internals/landlock
- Professional agent tools and sandbox providers:
  - https://code.claude.com/docs/en/sandbox-environments
  - https://code.claude.com/docs/en/sandboxing
  - https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent
  - https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-firewall
  - https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/configure-secrets-and-variables
  - https://developers.openai.com/api/docs/guides/agents/sandboxes
  - https://e2b.dev/docs
  - https://www.daytona.io/docs/en/sandboxes/
  - https://modal.com/resources/best-code-execution-sandboxes-ai-agents
  - https://docs.devin.ai/onboard-devin/repo-setup
