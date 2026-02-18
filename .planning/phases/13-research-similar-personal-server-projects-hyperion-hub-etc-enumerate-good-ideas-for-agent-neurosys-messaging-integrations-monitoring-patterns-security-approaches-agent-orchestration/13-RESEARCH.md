# Phase 13: Research Similar Personal Server Projects - Research

**Researched:** 2026-02-18
**Domain:** NixOS personal server infrastructure, monitoring, messaging, security, agent orchestration
**Confidence:** MEDIUM (broad survey across multiple domains; individual tool recommendations are HIGH where NixOS modules exist)

## Summary

This phase surveys the ecosystem of personal/homelab server projects (both NixOS-specific and general self-hosted) to identify good ideas for agent-neurosys across four domains: messaging integrations, monitoring patterns, security approaches, and agent orchestration. The research covers real-world NixOS homelab configurations (rwiankowski/homeserver-nixos, badele/nix-homelab, arsfeld's multi-host setup), agent sandboxing approaches (Stapelberg's microvm.nix, rymcg's immutable VMs, the sandbox-comparison survey), the 2026 homelab stack consensus, and the emerging multi-agent orchestration landscape.

The project "hyperion-hub" referenced in the phase name does not appear to be a specific identifiable open-source project. The closest matches are agiliq/hyperion (a Pingdom alternative for uptime monitoring) and the Hyperion ambient lighting project -- neither is a personal server management system. Research proceeded by surveying the broader ecosystem instead.

**Primary recommendation:** agent-neurosys should prioritize adding (1) a lightweight monitoring stack (Prometheus + node_exporter + Grafana + ntfy for alerts), (2) push notifications via ntfy for server events, (3) CrowdSec + endlessh-go for security hardening, and (4) evaluate Claude Code's native Agent Teams feature before building custom orchestration.

## Reference Projects

### NixOS-Specific Projects

| Project | URL | Relevance | Key Ideas |
|---------|-----|-----------|-----------|
| rwiankowski/homeserver-nixos | https://github.com/rwiankowski/homeserver-nixos | HIGH | 20+ services, zero-trust networking, Authentik SSO, CrowdSec, Caddy reverse proxy, Restic to Azure, vars.nix pattern |
| badele/nix-homelab | https://github.com/badele/nix-homelab | MEDIUM | Multi-host (VPS + RPi), Clan deployment, Authentik/Kanidm/LLDAP auth options |
| arsfeld's homelab (blog) | https://blog.arsfeld.dev/posts/2025/06/10/managing-homelab-with-nixos/ | MEDIUM | Constellation pattern (90% shared config), GitHub Actions deploy, LLDAP + Dex + Authelia auth stack |
| shinbunbun/nixos-observability | https://github.com/shinbunbun/nixos-observability | HIGH | Complete observability flake: Prometheus, Grafana, Loki, Alertmanager, OpenSearch, Fluent Bit, SNMP exporter |
| Stapelberg microvm.nix agents | https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/ | MEDIUM | Ephemeral microVMs for coding agents, cloud-hypervisor, virtiofs shared workspace, read-only nix store |
| rymcg code agent VMs | https://blog.rymcg.tech/blog/linux/code-agent-vm/ | MEDIUM | Composable mixin profiles (claude, dev, docker), thin provisioning, SSH deploy keys per repo, immutable root |

### General Homelab/Self-Hosted Projects

| Project/Resource | URL | Key Ideas |
|------------------|-----|-----------|
| 2026 Homelab Stack survey | https://blog.elest.io/the-2026-homelab-stack-what-self-hosters-are-actually-running-this-year/ | Uptime Kuma, Authentik, Vaultwarden, Headscale, Ollama, AdGuard Home |
| Cybersecurity tools survey | https://blog.elest.io/open-source-cybersecurity-tools-every-self-hoster-should-know-in-2026/ | CrowdSec, HashiCorp Vault/OpenBao, WG-Easy, Vaultwarden, Fail2Ban |
| Agent sandbox comparison | https://michaellivs.com/blog/sandbox-comparison-2026/ | Simulated, OS-level (bwrap), containers (gVisor), microVMs (Firecracker) |

## Good Ideas Catalog

### Category 1: Monitoring & Observability

#### Idea 1.1: Prometheus + node_exporter + Grafana Stack
**What:** Declarative system monitoring with time-series metrics collection, dashboards, and alerting.
**Confidence:** HIGH (first-class NixOS modules exist for all components)
**From:** shinbunbun/nixos-observability, rwiankowski/homeserver-nixos, 2026 homelab consensus
**agent-neurosys fit:** Single-server deployment. node_exporter scrapes CPU, memory, disk, network. Prometheus stores metrics. Grafana visualizes. All configured declaratively in NixOS.
**Recommendation:** USE. Start minimal: node_exporter + Prometheus + Grafana. Add exporters as needed.

**NixOS pattern:**
```nix
# modules/monitoring.nix
{
  services.prometheus = {
    enable = true;
    exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" "processes" ];
    };
    scrapeConfigs = [{
      job_name = "node";
      static_configs = [{ targets = [ "localhost:9100" ]; }];
    }];
  };
  services.grafana = {
    enable = true;
    settings.server.http_port = 3000;
    provision.datasources.settings.datasources = [{
      name = "Prometheus";
      type = "prometheus";
      url = "http://localhost:9090";
    }];
  };
}
```

#### Idea 1.2: Uptime Kuma for Service Health
**What:** Lightweight, self-hosted service status page with push notifications.
**Confidence:** HIGH (nixpkgs package exists, 2026 homelab survey consensus pick)
**From:** 2026 homelab stack survey
**agent-neurosys fit:** Monitor Docker containers (parts-agent, parts-tools, claw-swap), Syncthing, Home Assistant, SSH. Simple web UI dashboard.
**Recommendation:** CONSIDER. Useful if you want a simple "is everything running?" dashboard. Overlaps somewhat with Prometheus alerting but much simpler to set up.

#### Idea 1.3: VictoriaMetrics as Prometheus Alternative
**What:** Lighter-weight, single-binary time-series database compatible with Prometheus scrape format and Grafana.
**Confidence:** MEDIUM (NixOS package exists but less community documentation for NixOS-specific setup)
**From:** 2026 homelab stack survey, community recommendations
**agent-neurosys fit:** If Prometheus memory/CPU overhead is a concern on the VPS. Drop-in replacement.
**Recommendation:** DEFER. Start with Prometheus. VictoriaMetrics is the escape hatch if resource usage becomes a problem.

#### Idea 1.4: Loki + Alloy for Log Aggregation
**What:** Centralized log search and aggregation. Loki stores logs, Grafana Alloy collects them (replacing deprecated Promtail).
**Confidence:** MEDIUM (Loki has NixOS module; Alloy is newer and NixOS support uncertain)
**From:** shinbunbun/nixos-observability, Grafana ecosystem
**agent-neurosys fit:** Single server means journald is already centralized. Loki adds persistent log search in Grafana. Most useful for Docker container logs and agent audit logs.
**Critical note:** Promtail is deprecated (EOL March 2026). Grafana Alloy is the replacement. Check NixOS packaging before committing.
**Recommendation:** CONSIDER for Phase 14+. Not urgent for single-server setup where `journalctl` works fine.

### Category 2: Messaging & Notifications

#### Idea 2.1: ntfy for Push Notifications
**What:** Simple HTTP pub-sub notification service. Self-hosted, no signup required. Supports phone, desktop, email notifications via REST API.
**Confidence:** HIGH (NixOS module exists: `services.ntfy-sh`)
**From:** ntfy.sh, alertmanager-ntfy project, 2026 homelab consensus
**agent-neurosys fit:** Notify on: deploy success/failure, agent completion, backup status, service health changes, security events (fail2ban bans). Single `curl` command to send. Phone app available for iOS/Android.
**Recommendation:** USE. Lightweight, self-hosted, integrates with everything via HTTP POST.

**Integration points:**
- Alertmanager -> ntfy (via alertmanager-ntfy NixOS flake module)
- Deploy script -> ntfy (curl POST on success/failure)
- Agent-spawn -> ntfy (agent session completed)
- Fail2ban -> ntfy (ban action)
- Restic backup -> ntfy (timer completion)
- Home Assistant -> ntfy (automation triggers)

**NixOS pattern:**
```nix
# modules/ntfy.nix
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = ":2586";
      base-url = "https://ntfy.example.com";
      behind-proxy = true;
      auth-default-access = "deny-all";
    };
  };
}
```

#### Idea 2.2: Telegram Bot for Alerts
**What:** Send alerts to Telegram via bot API.
**Confidence:** HIGH (well-documented, Alertmanager has native Telegram receiver)
**From:** Community patterns, Alertmanager native support
**agent-neurosys fit:** If user already uses Telegram. Alertmanager has built-in Telegram receiver config.
**Recommendation:** CONSIDER as alternative to ntfy. ntfy is more flexible (HTTP API, phone app, self-hosted). Telegram requires internet connectivity and external dependency.

#### Idea 2.3: Home Assistant as Notification Hub
**What:** Use HA's automation engine to route notifications from multiple sources.
**Confidence:** MEDIUM (HA already deployed on agent-neurosys, but notification integrations need HA UI config)
**From:** Home Assistant 2025-2026 releases, AI Task integration
**agent-neurosys fit:** HA is already running. Could route ntfy notifications, trigger automations based on server state. HA's new AI Task integration (2025.8+) can generate structured data from AI, usable in automations.
**Recommendation:** DEFER. Useful later once monitoring and ntfy are in place. HA becomes the orchestration layer for cross-service automation.

### Category 3: Security Approaches

#### Idea 3.1: CrowdSec Intrusion Prevention
**What:** Real-time log analysis + collaborative threat intelligence. Detects brute force, port scans, web exploits. Shares blocklists with community.
**Confidence:** MEDIUM (NixOS community module exists as flake, not in mainline nixpkgs)
**From:** rwiankowski/homeserver-nixos, cybersecurity tools survey, CrowdSec community
**agent-neurosys fit:** Complements existing fail2ban. CrowdSec adds collaborative threat intelligence (shared blocklists). Analyzes fail2ban-style patterns plus web server logs if Caddy/nginx are added.
**Recommendation:** CONSIDER. Adds value over fail2ban via collaborative blocklists. Community NixOS module available. Deploy alongside fail2ban initially, migrate later if desired.

#### Idea 3.2: endlessh-go SSH Tarpit
**What:** SSH tarpit that wastes attacker resources by slowly sending an infinite SSH banner.
**Confidence:** HIGH (NixOS module exists: `services.endlessh-go`)
**From:** NixOS security wiki, cybersecurity tools survey
**agent-neurosys fit:** Move real SSH to non-standard port (e.g., 2222), bind endlessh-go to port 22. Attackers waste time on the tarpit. Minimal resource usage.
**Recommendation:** CONSIDER. Low effort, high entertainment value. Pairs well with CrowdSec (endlessh-go logs feed CrowdSec for threat intel). Only useful if SSH is exposed publicly (currently Tailscale-only access reduces the attack surface).

#### Idea 3.3: Authentik/Authelia SSO
**What:** Single sign-on portal for all web services behind a reverse proxy.
**Confidence:** MEDIUM (NixOS support exists but requires reverse proxy setup)
**From:** rwiankowski/homeserver-nixos, arsfeld's homelab, 2026 homelab consensus
**agent-neurosys fit:** Protects Grafana, Syncthing, Home Assistant, Uptime Kuma behind a single login. Authelia is lightweight (forward-auth proxy companion). Authentik is full OIDC provider.
**Recommendation:** DEFER. Only valuable when multiple web services are exposed. Currently, services are Tailscale-only which provides implicit authentication. If services ever become internet-facing, Authelia is the simpler choice for agent-neurosys's scale.

#### Idea 3.4: NixOS Hardened Profile
**What:** NixOS ships a `profiles/hardened.nix` that enables kernel hardening, restricts modules, enables apparmor.
**Confidence:** HIGH (built into NixOS)
**From:** NixOS security wiki, hardening guides
**agent-neurosys fit:** Phase 12 (security audit) should evaluate which hardened profile options are compatible with the agent workload. Some options (e.g., `security.lockKernelModules`) may conflict with Docker.
**Recommendation:** EVALUATE in Phase 12. Don't adopt blindly -- test each option against agent-spawn + Docker + Podman compatibility.

#### Idea 3.5: Headscale (Self-Hosted Tailscale Control)
**What:** Open-source, self-hosted implementation of the Tailscale coordination server.
**Confidence:** HIGH (active project, NixOS module exists)
**From:** 2026 homelab stack, multiple homelab configs
**agent-neurosys fit:** Eliminates dependency on Tailscale's hosted control plane. Full privacy. Uses official Tailscale clients.
**Recommendation:** CONSIDER for future. Tailscale's free tier is sufficient for personal use. Headscale adds operational complexity (running your own coordination server). Worth evaluating if Tailscale's pricing or policies change, or if privacy requirements escalate.

### Category 4: Agent Orchestration

#### Idea 4.1: Claude Code Agent Teams (Native)
**What:** Built-in multi-agent orchestration in Claude Code. One session acts as team lead, spawns teammates, shared task list, inbox-based communication.
**Confidence:** HIGH (documented feature, experimental flag)
**From:** Claude Code docs, community guides
**agent-neurosys fit:** Already using Claude Code. Agent Teams enables parallel work without external tooling. Teammates can work in different worktrees. Enable via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true`.
**Recommendation:** USE. This is the native solution. Evaluate before building any custom orchestration.

#### Idea 4.2: microvm.nix Ephemeral Agent VMs
**What:** Disposable NixOS VMs for each agent session. Full kernel isolation, shared workspace via virtiofs, ephemeral state.
**Confidence:** HIGH (well-documented by Stapelberg, active project)
**From:** Michael Stapelberg's blog (Feb 2026), microvm.nix project
**agent-neurosys fit:** BLOCKED. Contabo VPS does not provide KVM/nested virtualization. microvm.nix requires hardware virtualization support. This approach is only viable if agent-neurosys moves to a host with KVM access.
**Recommendation:** NOT APPLICABLE for current VPS. Document as aspirational pattern for future hardware. The existing bubblewrap sandbox (Phase 11) is the correct approach for this VPS.

#### Idea 4.3: claude-flow Multi-Agent Framework
**What:** Third-party orchestration platform for Claude with swarm intelligence, MCP integration, 60+ agents.
**Confidence:** LOW (marketing-heavy, unverified claims about performance)
**From:** github.com/ruvnet/claude-flow
**agent-neurosys fit:** Heavy external dependency. Claude Code's native Agent Teams feature covers the same use case with less complexity. claude-flow adds MCP-based orchestration which may be useful for specific workflows.
**Recommendation:** DEFER. Evaluate only if Claude Code's native Agent Teams prove insufficient for specific multi-agent workflows.

#### Idea 4.4: Composable Agent Profiles (from rymcg)
**What:** Mixin-based profiles for agent environments (core, docker, podman, dev, python, rust, claude).
**Confidence:** MEDIUM (pattern from rymcg blog, not a formal project)
**From:** rymcg code agent VMs blog
**agent-neurosys fit:** agent-spawn could support profiles that pre-configure sandbox environments. E.g., `agent-spawn --profile python myproject /data/projects/myproject` would include Python toolchain in the sandbox.
**Recommendation:** CONSIDER for Phase 11 iteration. Current agent-spawn is one-size-fits-all. Profiles would reduce friction for specialized workloads.

#### Idea 4.5: MCP-NixOS Server
**What:** MCP server providing real-time NixOS package/option information to Claude. Prevents hallucination about NixOS configs.
**Confidence:** HIGH (active project, documented Claude Code integration)
**From:** mcp-nixos.io, utensils/mcp-nixos
**agent-neurosys fit:** Install as MCP server for Claude Code sessions working on agent-neurosys. Provides accurate NixOS option lookup, package search, Home Manager option discovery.
**Recommendation:** USE. Low effort, high value for NixOS configuration work. Add to `.mcp.json` in project root.

### Category 5: Backup & Recovery

#### Idea 5.1: Restic to B2 with NixOS Module
**What:** Declarative Restic backup configuration with systemd timers, automatic initialization, retention policies.
**Confidence:** HIGH (first-class NixOS module, well-documented community patterns)
**From:** NixOS wiki, community blogs, rwiankowski/homeserver-nixos
**agent-neurosys fit:** Already planned for Phase 7. NixOS has excellent Restic module. Pair with ntfy for backup status notifications.
**Recommendation:** ALREADY PLANNED (Phase 7). Add ntfy notification hook.

### Category 6: Reverse Proxy & Service Exposure

#### Idea 6.1: Caddy as Reverse Proxy
**What:** Automatic HTTPS, simple configuration, reverse proxy for internal services.
**Confidence:** HIGH (NixOS module exists, 2026 homelab consensus pick)
**From:** rwiankowski/homeserver-nixos, 2026 homelab stack survey
**agent-neurosys fit:** If services need to be exposed (even internally on Tailscale with proper DNS). Caddy auto-provisions Let's Encrypt certs. Simpler config than nginx.
**Recommendation:** CONSIDER when adding DNS-based service routing. Currently not needed if all access is via Tailscale IP:port.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Push notifications | Custom webhook/email system | ntfy-sh | HTTP API, phone apps, NixOS module, integrates with everything |
| System metrics | Custom scripts checking disk/CPU | Prometheus + node_exporter | Battle-tested, standard exporters, Grafana dashboards available |
| Service uptime checks | Cron + curl scripts | Uptime Kuma | Web UI, notification integrations, status pages, NixOS package |
| Threat intelligence | Custom fail2ban rules | CrowdSec | Collaborative blocklists, ML-based detection, community scenarios |
| Multi-agent coordination | Custom tmux orchestration | Claude Code Agent Teams | Native feature, shared task list, inter-agent communication |
| NixOS option lookup for agents | Manual docs searching | MCP-NixOS server | Real-time accurate data, prevents hallucination |
| Log aggregation | grep/journalctl scripts | Loki + Alloy (when needed) | Persistent search, Grafana integration, structured queries |
| SSO for web services | Per-service auth config | Authelia (when needed) | Forward-auth, works with any reverse proxy, NixOS configurable |

**Key insight:** NixOS's declarative model means most of these tools are a module import + a few lines of config away. The ecosystem has mature, well-maintained modules for monitoring, notifications, and security. Building custom solutions is never justified at this scale.

## Common Pitfalls

### Pitfall 1: Over-Engineering the Monitoring Stack
**What goes wrong:** Deploying full Prometheus + Loki + Grafana + Alertmanager + OpenSearch for a single server, creating 5+ new services to monitor the existing 5 services.
**Why it happens:** Monitoring stacks are designed for fleet management. Single-server setups need a fraction of the capability.
**How to avoid:** Start with node_exporter + Prometheus + Grafana only. Add Loki/Alertmanager only when you have a specific use case (e.g., agent audit log search). Use Uptime Kuma for simple health checks.
**Warning signs:** More monitoring services than application services. Dashboard pages nobody looks at.

### Pitfall 2: Exposing Services Without Authentication
**What goes wrong:** Running Grafana/ntfy/Uptime Kuma on public ports without auth, assuming Tailscale is always the access path.
**Why it happens:** Tailscale provides implicit authentication, so auth feels redundant. But firewall misconfigurations or service binding to 0.0.0.0 can expose services.
**How to avoid:** Bind monitoring services to 127.0.0.1 or Tailscale interface. If binding to 0.0.0.0, use trustedInterfaces pattern (same as Syncthing in Phase 6). Consider Authelia if services multiply.
**Warning signs:** Services accessible from public IP scan.

### Pitfall 3: Notification Fatigue
**What goes wrong:** Alerting on every metric, every container restart, every SSH attempt. Notifications become noise and get ignored.
**Why it happens:** Easy to add alerts, hard to tune thresholds.
**How to avoid:** Start with critical alerts only: disk >90%, service down >5min, backup failure, security events. Add alerts incrementally based on actual incidents.
**Warning signs:** Muting notification channels. Ignoring alerts. More than 5 alerts per day in steady state.

### Pitfall 4: Agent Orchestration Complexity Creep
**What goes wrong:** Building elaborate multi-agent coordination systems when simple sequential agent sessions suffice.
**Why it happens:** Multi-agent frameworks are exciting. But most personal server tasks are sequential, not parallel.
**How to avoid:** Use Claude Code's native Agent Teams for the few genuinely parallel tasks. Use agent-spawn for sequential isolated sessions. Only add orchestration tooling when you hit a specific scaling bottleneck.
**Warning signs:** More time configuring orchestration than doing actual work.

### Pitfall 5: Promtail EOL Surprise
**What goes wrong:** Deploying Promtail for log collection, then discovering it hits EOL in March 2026 with no further updates.
**Why it happens:** Many existing guides and NixOS configs still reference Promtail.
**How to avoid:** If deploying log collection, use Grafana Alloy from the start. If NixOS Alloy packaging is not yet available, use Fluent Bit (used by shinbunbun/nixos-observability).
**Warning signs:** References to Promtail in new configuration.

## Architecture Patterns

### Pattern 1: Layered Monitoring for Single Server
**What:** Separate health checks (is it running?) from metrics (how is it performing?) from logs (what happened?).
**When to use:** Single-server deployment where full observability stack is overkill initially.

```
Layer 1 (minimal):  node_exporter + Prometheus + Grafana
                    → "How are CPU/memory/disk doing?"

Layer 2 (add when needed): Uptime Kuma or Alertmanager + ntfy
                    → "Is service X up? Tell me when it's not."

Layer 3 (add when needed): Loki + Alloy + Grafana
                    → "What happened in the logs at 3am?"
```

### Pattern 2: Notification Hierarchy
**What:** Route notifications by severity to appropriate channels.
**When to use:** When ntfy is deployed and multiple alert sources exist.

```
CRITICAL (immediate):  ntfy high-priority → phone push
  - Service down >5min
  - Disk >95%
  - Backup failure
  - Security breach (CrowdSec critical)

WARNING (batched):     ntfy default-priority → phone notification
  - Disk >80%
  - Agent session failed
  - Container restart
  - Unusual traffic pattern

INFO (silent):         ntfy low-priority → app badge only
  - Deploy completed
  - Backup completed
  - Agent session completed
  - Routine maintenance
```

### Pattern 3: vars.nix Centralized Configuration
**What:** Single file defining all hostnames, ports, domains, storage paths used across modules.
**When to use:** When multiple modules reference the same values (ports, paths, domain names).
**From:** rwiankowski/homeserver-nixos

```nix
# vars.nix
{
  hostname = "acfs";
  domain = "acfs.local";
  ports = {
    grafana = 3000;
    prometheus = 9090;
    ntfy = 2586;
    uptimeKuma = 3001;
  };
  paths = {
    data = "/data";
    projects = "/data/projects";
    backups = "/data/backups";
  };
}
```

### Anti-Patterns to Avoid
- **Monitoring everything from day one:** Start with Layer 1, add layers based on actual needs
- **Running Headscale to replace working Tailscale:** Only adds operational burden without clear benefit for personal use
- **Building custom agent orchestration:** Claude Code Agent Teams is the native solution; use it first
- **Deploying Authentik for 3 services behind Tailscale:** Tailscale already provides network-level authentication

## State of the Art

| Old Approach | Current Approach (2026) | When Changed | Impact |
|--------------|-------------------------|--------------|--------|
| Promtail for log collection | Grafana Alloy | Feb 2025 (deprecation) | Must use Alloy for new deployments |
| OpenVPN for remote access | WireGuard / Tailscale / Headscale | 2020-2024 | agent-neurosys already uses Tailscale |
| Pi-hole for DNS ad blocking | AdGuard Home | 2024-2025 community shift | Modern UI, more features |
| Self-hosted Bitwarden | Vaultwarden | 2023-2024 | Same API, 1/10th resources |
| Manual agent sessions | Claude Code Agent Teams | Feb 2026 | Native multi-agent in Claude Code |
| Docker-only sandboxing | bubblewrap + cgroup (OS primitives) | 2025-2026 | agent-neurosys Phase 11 already uses this |
| Custom monitoring scripts | Prometheus + Grafana | Long-established | Declarative NixOS modules available |
| Email alerts | ntfy push notifications | 2023-2025 | Self-hosted, phone app, REST API |

## Open Questions

1. **NixOS Grafana Alloy packaging**
   - What we know: Grafana Alloy replaces Promtail (EOL March 2026). Alloy is the new standard.
   - What's unclear: Whether nixpkgs has an Alloy module yet, or if it needs custom packaging.
   - Recommendation: Check nixpkgs for `services.alloy` or `grafana-alloy` package before planning log aggregation.

2. **CrowdSec NixOS module maturity**
   - What we know: Community NixOS module exists as a flake. CrowdSec is packaged in nixpkgs.
   - What's unclear: Whether the community module is production-stable, or if manual configuration is needed.
   - Recommendation: Evaluate the community flake (https://discourse.crowdsec.net/t/ive-created-a-nixos-module-for-crowdsec/1695) before committing.

3. **Agent Teams stability and availability**
   - What we know: Claude Code Agent Teams is documented and available behind experimental flag.
   - What's unclear: Whether the feature is stable enough for production use on the server, and whether it works well inside bubblewrap sandboxes.
   - Recommendation: Test `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true` in an agent-spawn session before building workflows around it.

4. **MCP-NixOS server in sandboxed environments**
   - What we know: MCP-NixOS provides real-time NixOS option lookup for Claude. Runs via Python/uvx.
   - What's unclear: Whether it works inside bubblewrap sandboxes (needs network access to query NixOS APIs).
   - Recommendation: Test in both sandboxed and non-sandboxed agent sessions.

5. **Monitoring resource overhead on VPS**
   - What we know: Prometheus + Grafana + node_exporter are standard. VPS has 96GB RAM and 18 vCPU.
   - What's unclear: Actual resource consumption on this specific workload. Probably negligible given VPS specs.
   - Recommendation: Deploy and measure. VictoriaMetrics is the fallback if overhead is surprising.

## Priority Ranking for Implementation

Based on value-to-effort ratio for agent-neurosys:

| Priority | Idea | Effort | Value | Phase |
|----------|------|--------|-------|-------|
| 1 | ntfy push notifications | LOW | HIGH | New or Phase 7 |
| 2 | Prometheus + node_exporter + Grafana | MEDIUM | HIGH | New phase |
| 3 | MCP-NixOS server for Claude | LOW | MEDIUM | Immediate (.mcp.json) |
| 4 | Claude Code Agent Teams | LOW | MEDIUM | Configuration change |
| 5 | Uptime Kuma | LOW | MEDIUM | New phase |
| 6 | CrowdSec | MEDIUM | MEDIUM | Phase 12 or new |
| 7 | endlessh-go | LOW | LOW | Phase 12 or new |
| 8 | Caddy reverse proxy | MEDIUM | LOW (Tailscale) | When needed |
| 9 | Authelia SSO | MEDIUM | LOW (Tailscale) | When needed |
| 10 | Headscale | HIGH | LOW | Only if Tailscale becomes problematic |
| 11 | Loki + Alloy logs | MEDIUM | LOW (single server) | When needed |

## Sources

### Primary (HIGH confidence)
- NixOS Wiki: Prometheus - https://wiki.nixos.org/wiki/Prometheus
- NixOS Wiki: Grafana - https://wiki.nixos.org/wiki/Grafana
- NixOS Wiki: Security - https://wiki.nixos.org/wiki/Security
- NixOS Wiki: Uptime Kuma - https://wiki.nixos.org/wiki/Uptime_Kuma
- NixOS Wiki: Fail2ban - https://wiki.nixos.org/wiki/Fail2ban
- NixOS Wiki: Grafana Loki - https://wiki.nixos.org/wiki/Grafana_Loki
- NixOS Wiki: Restic - https://wiki.nixos.org/wiki/Restic
- NixOS Wiki: Home Assistant - https://wiki.nixos.org/wiki/Home_Assistant
- Claude Code Agent Teams docs - https://code.claude.com/docs/en/agent-teams
- ntfy.sh official docs - https://docs.ntfy.sh/
- MCP-NixOS project - https://mcp-nixos.io/
- Michael Stapelberg microvm.nix blog - https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/

### Secondary (MEDIUM confidence)
- rwiankowski/homeserver-nixos - https://github.com/rwiankowski/homeserver-nixos
- shinbunbun/nixos-observability - https://github.com/shinbunbun/nixos-observability
- badele/nix-homelab - https://github.com/badele/nix-homelab
- arsfeld homelab blog - https://blog.arsfeld.dev/posts/2025/06/10/managing-homelab-with-nixos/
- rymcg code agent VMs - https://blog.rymcg.tech/blog/linux/code-agent-vm/
- Agent sandbox comparison - https://michaellivs.com/blog/sandbox-comparison-2026/
- 2026 Homelab Stack - https://blog.elest.io/the-2026-homelab-stack-what-self-hosters-are-actually-running-this-year/
- Cybersecurity tools for self-hosters - https://blog.elest.io/open-source-cybersecurity-tools-every-self-hoster-should-know-in-2026/
- Grafana Alloy migration - https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/
- CrowdSec NixOS module - https://discourse.crowdsec.net/t/ive-created-a-nixos-module-for-crowdsec/1695
- alertmanager-ntfy - https://github.com/alexbakker/alertmanager-ntfy

### Tertiary (LOW confidence)
- claude-flow - https://github.com/ruvnet/claude-flow (marketing-heavy, unverified claims)
- "hyperion-hub" - could not identify as a specific project; no matching repository found

## Metadata

**Confidence breakdown:**
- Monitoring stack: HIGH - NixOS modules well-documented, community consensus clear
- Messaging/notifications: HIGH - ntfy has NixOS module, straightforward deployment
- Security approaches: MEDIUM - CrowdSec NixOS module is community-maintained, needs evaluation
- Agent orchestration: MEDIUM - Claude Code Agent Teams is new/experimental, microvm.nix blocked by VPS hardware
- Reference projects: HIGH - Multiple real-world examples examined with consistent patterns

**Research date:** 2026-02-18
**Valid until:** 2026-03-18 (30 days - stable domain, established tools)
