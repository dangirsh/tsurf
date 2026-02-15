# Phase 3: Networking + Secrets + Docker Foundation - Research

**Researched:** 2026-02-15
**Domain:** NixOS Tailscale module, nftables firewall with Docker, fail2ban, sops-nix secrets, Docker engine configuration
**Confidence:** HIGH (core), MEDIUM (Docker+nftables interaction)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Firewall (nftables)
- Default deny inbound on public interface (eth0)
- Public inbound allow: SSH (22), HTTP (80), HTTPS (443), Syncthing (22000)
- Tailscale interface: allow all traffic (already authenticated by Tailscale)
- Docker runs with `--iptables=false` -- NixOS owns the firewall, not Docker
- Container ports bind to 127.0.0.1 or Tailscale IP only; Caddy is the only thing on public 80/443

#### Tailscale
- Auth via sops-encrypted authkey, applied automatically at activation
- Accept routes enabled (reach home network devices)
- MagicDNS enabled
- No exit node (server is not a relay)
- No subnet router
- Reverse path filter set to loose mode on tailscale0 (required for Tailscale routing)

#### fail2ban
- SSH: ban after 5 failures, 10 min ban, progressive escalation for repeat offenders
- Whitelist Tailscale subnet (100.64.0.0/10) -- never ban Tailscale peers
- Monitor SSH only (everything else behind Tailscale or Docker)

#### Docker Engine
- `--iptables=false` -- no Docker firewall bypass
- Bridge networks for inter-container communication
- Container ports needing public access go through Caddy (reverse proxy), not direct port binding
- Docker socket not exposed to containers

#### Secrets (sops-nix)
- Tailscale authkey
- B2 credentials (consumed in Phase 7)
- SSH host keys (already bootstrapped in Phase 1)
- Project-specific secrets imported via flake modules (like parts already does)
- Everything decrypts to /run/secrets/

### Claude's Discretion
- Exact nftables rule structure and chain organization
- fail2ban jail configuration details
- Docker daemon.json structure
- Tailscale NixOS module options beyond what's specified above

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

## Summary

Phase 3 delivers the networking and security infrastructure that all service phases (4, 6, 7) depend on. It integrates four tightly coupled systems: (1) Tailscale VPN for private network access, (2) nftables firewall with per-interface rules for public vs Tailscale traffic, (3) Docker engine configured to NOT manage its own firewall rules, and (4) fail2ban for SSH brute-force protection. These four systems interact in non-obvious ways, which is why the roadmap grouped them together.

The most significant technical challenge is the Docker `--iptables=false` decision. When Docker's iptables management is disabled, Docker no longer creates NAT/masquerade rules for container outbound access or forwarding rules for inter-container communication. NixOS must provide these capabilities through `networking.nat` and `networking.firewall` configuration. This is a well-understood pattern but requires careful configuration: the NixOS NAT module must masquerade Docker bridge traffic, and Docker bridge interfaces must be trusted in the firewall to allow container-to-container traffic. The tradeoff is explicit firewall control (no Docker-punched holes) at the cost of manual NAT/forwarding configuration.

A second key interaction is between nftables and Docker. NixOS's `networking.nftables.enable = true` blacklists the `ip_tables` kernel module, but Docker's default (iptables) mode auto-loads it. With `--iptables=false`, Docker does not attempt to load iptables, so the nftables blacklist works cleanly. Docker 29.0+ has experimental native nftables support via `firewall-backend: nftables`, but this is experimental and not recommended for production. The safest path: keep `--iptables=false` and let NixOS own all firewall rules via nftables.

The secrets work is straightforward: add tailscale-authkey and B2 credentials to `secrets/acfs.yaml`, declare them in `modules/secrets.nix` with per-secret `sopsFile` overrides, and wire them to the consuming services. The existing sops-nix setup from Phase 1 (age key from SSH host key, `.sops.yaml` with creation rules) provides the foundation.

**Primary recommendation:** Split into 2 plans: (1) Tailscale + secrets + fail2ban (networking layer that does not depend on Docker), and (2) Docker engine with `--iptables=false` + NAT/forwarding rules + verification of the complete stack. Plan 1 can be tested with `nix flake check`; Plan 2 requires live deployment testing.

## Standard Stack

### Core

| Component | Version/Source | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| NixOS `services.tailscale` | Built-in NixOS module | Tailscale VPN daemon with declarative config | Official NixOS module; supports `authKeyFile`, `extraUpFlags`, `useRoutingFeatures` for automatic kernel parameter tuning |
| NixOS `networking.firewall` + `networking.nftables` | Built-in NixOS modules | nftables-backed firewall with per-interface rules | Already enabled in Phase 2; extends naturally with `trustedInterfaces` and `allowedUDPPorts` |
| NixOS `services.fail2ban` | Built-in NixOS module | SSH brute-force protection | Auto-selects `nftables-multiport` banaction when `networking.nftables.enable = true`; ships with default SSH jail |
| NixOS `virtualisation.docker` | Built-in NixOS module | Docker engine with `daemon.settings` for daemon.json | `daemon.settings = { iptables = false; }` maps directly to daemon.json; no manual file management |
| sops-nix | `github:Mic92/sops-nix` (already in flake.nix) | Secrets management | Already wired in Phase 1; `sops.secrets` declarations with per-secret `sopsFile` override |
| NixOS `networking.nat` | Built-in NixOS module | NAT/masquerade for Docker container outbound access | Required when Docker `--iptables=false` disables Docker's own NAT rules |

### Supporting

| Component | Version/Source | Purpose | When to Use |
|-----------|---------------|---------|-------------|
| `networking.firewall.trustedInterfaces` | Built-in option | Allow all traffic on specified interfaces | For `tailscale0` (Tailscale traffic is already authenticated) and Docker bridge interfaces |
| `services.tailscale.useRoutingFeatures` | Built-in option | Auto-configure kernel params for Tailscale routing | Set to `"client"` -- auto-enables loose reverse path filtering |
| `services.tailscale.extraUpFlags` | Built-in option | Pass flags to `tailscale up` | For `--accept-routes` |
| `networking.firewall.checkReversePath` | Built-in option | Control reverse path filtering | Set automatically by `useRoutingFeatures = "client"` to `"loose"` |

### Alternatives Considered

| Instead of | Could Use | Why Not |
|------------|-----------|---------|
| Docker `--iptables=false` + manual NAT | Docker default (let Docker manage iptables) | Docker bypasses NixOS firewall, exposing container ports on public interface ([NixOS/nixpkgs#111852](https://github.com/NixOS/nixpkgs/issues/111852)). User explicitly chose NixOS-owned firewall. |
| Docker `--iptables=false` + manual NAT | Docker `firewall-backend: nftables` (Docker 29+) | Experimental, "configuration options, behavior and implementation may all change in future releases" per Docker docs. Not suitable for production infrastructure. |
| NixOS `networking.nftables.enable = true` | Keep iptables backend | Phase 2 already enabled nftables. With `--iptables=false`, Docker won't conflict. nftables is the modern standard. |
| `services.tailscale.useRoutingFeatures = "client"` | Manual `boot.kernel.sysctl` for RPF | `useRoutingFeatures` is the official NixOS way; it sets the right sysctls automatically and avoids the Tailscale warning about strict RPF. |

## Architecture Patterns

### Module Structure for Phase 3

Phase 3 modifies existing modules and creates one new module. No changes to `flake.nix` or `flake.lock`.

```
modules/
  default.nix           # MODIFY: add docker.nix import
  networking.nix        # MODIFY: add Tailscale, fail2ban, Docker NAT/forwarding, trustedInterfaces
  secrets.nix           # MODIFY: add tailscale-authkey + B2 credential secrets
  docker.nix            # NEW: Docker engine config with --iptables=false
  base.nix              # NO CHANGE
  boot.nix              # NO CHANGE
  users.nix             # NO CHANGE (docker group already added in Phase 2)
secrets/
  acfs.yaml             # MODIFY: add tailscale-authkey + B2 credentials (encrypted)
.sops.yaml              # NO CHANGE (creation rules already cover secrets/acfs.yaml)
```

### Pattern 1: Tailscale with sops-nix Authkey

**What:** Tailscale auto-authenticates at activation using a sops-encrypted authkey.
**When to use:** Any NixOS server joining a tailnet.

```nix
# In modules/secrets.nix — declare the secret
sops.secrets."tailscale-authkey" = {
  sopsFile = ../../secrets/acfs.yaml;
  restartUnits = [ "tailscaled.service" ];
};

# In modules/networking.nix — consume the secret
services.tailscale = {
  enable = true;
  authKeyFile = config.sops.secrets."tailscale-authkey".path;
  useRoutingFeatures = "client";   # auto-sets checkReversePath = "loose"
  extraUpFlags = [
    "--accept-routes"              # reach home network devices
  ];
};
```

**Source:** [NixOS Wiki: Tailscale](https://wiki.nixos.org/wiki/Tailscale), [MyNixOS: services.tailscale](https://mynixos.com/options/services.tailscale)

**Key details:**
- `useRoutingFeatures = "client"` automatically sets `networking.firewall.checkReversePath = "loose"` and relevant kernel sysctls. No manual sysctl configuration needed.
- `authKeyFile` reads the pre-auth key from the sops-decrypted path. The Tailscale module runs `tailscale up --authkey=$(cat <file>)` on first start.
- `extraUpFlags = [ "--accept-routes" ]` enables receiving subnet routes from other tailnet nodes (the home network router).
- MagicDNS is enabled in the Tailscale admin console, not in NixOS config. The NixOS module respects the tailnet's DNS settings.

### Pattern 2: Firewall with Per-Interface Trust

**What:** Different firewall policies for public interface vs Tailscale interface.
**When to use:** When Tailscale provides an authenticated network alongside an untrusted public interface.

```nix
# In modules/networking.nix
networking.firewall = {
  enable = true;

  # Public interface: explicit port allowlist (already from Phase 2)
  allowedTCPPorts = [ 22 80 443 22000 ];

  # Tailscale UDP port for WireGuard tunnel
  allowedUDPPorts = [ config.services.tailscale.port ];

  # Tailscale interface: trust all traffic (already authenticated)
  trustedInterfaces = [ "tailscale0" ];
};
```

**Source:** [NixOS Wiki: Tailscale](https://wiki.nixos.org/wiki/Tailscale), [NixOS Wiki: Firewall](https://wiki.nixos.org/wiki/Firewall)

**Key detail:** `trustedInterfaces = [ "tailscale0" ]` generates an nftables rule `iifname { "tailscale0" } accept` in the input chain. All inbound traffic on the Tailscale interface is accepted unconditionally. This is safe because Tailscale traffic is already authenticated/encrypted by WireGuard.

### Pattern 3: Docker with `--iptables=false` and NixOS-Managed NAT

**What:** Docker engine that does not manage its own firewall rules, with NixOS providing NAT for container outbound access.
**When to use:** When you want NixOS to be the single owner of firewall rules.

```nix
# In modules/docker.nix
{ config, pkgs, ... }: {
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      iptables = false;          # Docker does NOT create firewall rules
      log-driver = "journald";   # Logs go to systemd journal
    };
  };

  # Container outbound access: NixOS provides NAT/masquerade
  # Without this, containers cannot reach the internet
  networking.nat = {
    enable = true;
    internalInterfaces = [ "docker0" ];
    externalInterface = "eth0";  # Primary public interface
  };

  # Trust Docker bridge for container-to-container traffic
  networking.firewall.trustedInterfaces = [ "docker0" ];
};
```

**Source:** [Docker Docs: Packet filtering](https://docs.docker.com/engine/network/packet-filtering-firewalls/), [NixOS Wiki: Docker](https://wiki.nixos.org/wiki/Docker), [NixOS/nixpkgs#111852](https://github.com/NixOS/nixpkgs/issues/111852)

**Critical details about `--iptables=false`:**

1. **What breaks:** Docker no longer creates: (a) MASQUERADE rules for container internet access, (b) FORWARD rules for inter-container communication, (c) DNAT rules for port publishing. All three must be handled by NixOS.

2. **NAT/Masquerade:** `networking.nat.enable = true` with `internalInterfaces = [ "docker0" ]` creates masquerade rules so containers can reach the internet. Without this, containers have no outbound connectivity.

3. **Inter-container communication:** Adding `"docker0"` to `trustedInterfaces` allows traffic between containers on the default bridge. For user-defined bridge networks (like `agent_net`), Docker creates `br-<hash>` interfaces. These also need trust, but since the interface names are dynamic, a broader approach may be needed (see Pitfall 3).

4. **Port publishing:** With `--iptables=false`, Docker's `-p` flag does NOT create DNAT rules. Published ports only work if the container binds to an address the host can route to. For this project, containers bind to `127.0.0.1` or the Tailscale IP, and Caddy reverse-proxies to them. No DNAT needed.

5. **Forward chain:** NixOS `networking.firewall.filterForward` defaults to `false`, meaning the FORWARD chain accepts all traffic. This is sufficient for Docker bridge networking. If `filterForward` were enabled, explicit forward rules would be needed.

### Pattern 4: fail2ban with Progressive Banning

**What:** fail2ban protects SSH with escalating ban times and Tailscale whitelist.
**When to use:** Any internet-facing SSH server.

```nix
# In modules/networking.nix
services.fail2ban = {
  enable = true;
  maxretry = 5;
  bantime = "10m";

  # Whitelist: never ban Tailscale peers or private networks
  ignoreIP = [
    "127.0.0.0/8"
    "100.64.0.0/10"    # Tailscale CGNAT range
  ];

  # Progressive escalation: each repeat offense increases ban duration
  bantime-increment = {
    enable = true;
    formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
    multipliers = "1 2 4 8 16 32 64";
    maxtime = "168h";     # Max 1 week ban
    overalljails = true;  # Track repeat offenders across all jails
  };
};
```

**Source:** [NixOS Wiki: Fail2ban](https://wiki.nixos.org/wiki/Fail2ban), [Official NixOS Wiki: Fail2ban](https://wiki.nixos.org/wiki/Fail2ban)

**Key details:**
- NixOS ships with a default `sshd` jail that is automatically active when `services.fail2ban.enable = true`. No need to declare it manually.
- When `networking.nftables.enable = true` (already set in Phase 2), fail2ban auto-selects `nftables-multiport` as the ban action. No manual `banaction` configuration needed.
- The `ignoreIP` list should include `100.64.0.0/10` (Tailscale's CGNAT range) to prevent banning Tailscale peers.
- `bantime-increment` with exponential formula means: first ban = 10m, second = 20m, third = 40m, etc., up to 168h (1 week).
- SSH LogLevel is automatically set to `VERBOSE` by the fail2ban module if not explicitly configured, which is required for fail2ban to observe failed login attempts.

### Pattern 5: sops-nix Secrets for Phase 3 Services

**What:** Declare new secrets for Tailscale and B2 in the existing sops infrastructure.
**When to use:** Adding new service credentials.

```nix
# In modules/secrets.nix
{ config, ... }: {
  sops = {
    defaultSopsFile = ../../secrets/acfs.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Tailscale auth key (consumed by services.tailscale.authKeyFile)
    secrets."tailscale-authkey" = {
      restartUnits = [ "tailscaled.service" ];
    };

    # B2 credentials (consumed in Phase 7 by restic)
    secrets."b2-account-id" = {};
    secrets."b2-account-key" = {};
    secrets."restic-password" = {};
  };
}
```

**Source:** [sops-nix README](https://github.com/Mic92/sops-nix), [Michael Stapelberg: Secret Management with sops-nix](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/)

**Key details:**
- All secrets use the `defaultSopsFile` (secrets/acfs.yaml) since they are system-level secrets owned by agent-neurosys, not project-level secrets (those use per-secret `sopsFile` overrides, as parts already does).
- `restartUnits` on tailscale-authkey ensures the Tailscale daemon restarts if the key changes.
- B2 credentials are declared now but consumed in Phase 7. Declaring them early means they will be decrypted and available at `/run/secrets/b2-account-id` etc. when Phase 7 needs them.
- The actual encrypted values must be added to `secrets/acfs.yaml` using `sops secrets/acfs.yaml` (requires the admin age private key).

### Pattern 6: Tailscale nftables Compatibility

**What:** Force tailscaled to use nftables directly instead of the iptables compatibility layer.
**When to use:** When `networking.nftables.enable = true` to avoid iptables-compat translation issues.

```nix
# In modules/networking.nix
# Force tailscaled to use native nftables (avoid iptables-compat issues)
systemd.services.tailscaled.serviceConfig.Environment = [
  "TS_DEBUG_FIREWALL_MODE=nftables"
];
```

**Source:** [NixOS/nixpkgs#285676](https://github.com/NixOS/nixpkgs/issues/285676)

**Key detail:** Without this, tailscaled may fail to detect the nftables firewall mode and fall back to iptables operations, which can conflict with the nftables setup. Setting `TS_DEBUG_FIREWALL_MODE=nftables` forces native nftables mode.

### Anti-Patterns to Avoid

- **Letting Docker manage its own iptables:** Docker injects rules that bypass NixOS firewall, exposing container ports publicly. This is the core problem that `--iptables=false` solves.
- **Using Docker 29+ `firewall-backend: nftables`:** Experimental. Behavior may change. Not suitable for production.
- **Forgetting `networking.nat` when using `--iptables=false`:** Containers will have no outbound internet access. This is the most common breakage with `--iptables=false`.
- **Setting `networking.firewall.checkReversePath = "loose"` manually when using `useRoutingFeatures`:** The `useRoutingFeatures = "client"` option sets this automatically. Setting it manually is redundant and may conflict.
- **Opening Tailscale port on TCP:** Tailscale uses UDP (default port 41641). The firewall needs `allowedUDPPorts`, not `allowedTCPPorts`, for the Tailscale tunnel.
- **Setting `sops.defaultSopsFile` in secrets.nix AND per-secret `sopsFile`:** Pick one. For system secrets (tailscale, B2), use `defaultSopsFile`. For cross-flake secrets (parts), use per-secret `sopsFile`. Don't mix approaches for the same file.
- **Trusting Docker bridge interfaces by name pattern:** Using `"br-+"` to trust all Docker bridges would be tempting but overly broad. For this project, only the default `docker0` bridge needs explicit trust; user-defined networks created by parts (agent_net, tools_net) will work because `filterForward` defaults to false.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tailscale auto-auth | Custom systemd service with `tailscale up` | `services.tailscale.authKeyFile` | NixOS module handles idempotent auth, restarts, state persistence |
| Reverse path filtering | Manual `boot.kernel.sysctl` for RPF | `services.tailscale.useRoutingFeatures = "client"` | Sets all required sysctls automatically, avoids Tailscale warnings |
| SSH ban action for nftables | Manual `banaction = "nftables-multiport"` | Auto-detection (fail2ban module checks `networking.nftables.enable`) | Module auto-selects correct action; manual override may break |
| Docker daemon.json | Manual file at `/etc/docker/daemon.json` | `virtualisation.docker.daemon.settings` | NixOS generates daemon.json from Nix attrset; declarative, no drift |
| Container outbound NAT | Custom nftables masquerade rules | `networking.nat = { enable = true; internalInterfaces = [ "docker0" ]; }` | NixOS NAT module generates correct masquerade rules for nftables |
| Tailscale firewall trust | Custom nftables rules for tailscale0 | `networking.firewall.trustedInterfaces = [ "tailscale0" ]` | Standard NixOS option; generates correct accept rule in input chain |

**Key insight:** Every piece of Phase 3 infrastructure has a dedicated NixOS module. The task is wiring module options together correctly, not building custom solutions. The challenge is the interaction between modules, not the modules themselves.

## Common Pitfalls

### Pitfall 1: No Container Outbound Access After `--iptables=false`

**What goes wrong:** Containers start but cannot reach the internet. DNS resolution fails, package downloads fail, API calls time out.
**Why it happens:** Docker's `--iptables=false` disables NAT/masquerade rules that Docker normally creates for bridge networks. Without masquerade, container traffic from private IPs (172.17.x.x) is not translated to the host's public IP.
**How to avoid:** Enable NixOS NAT: `networking.nat = { enable = true; internalInterfaces = [ "docker0" ]; externalInterface = "eth0"; };`. This creates nftables masquerade rules for traffic originating from docker0.
**Warning signs:** `docker run --rm alpine wget -qO- ifconfig.me` times out. `docker run --rm alpine nslookup google.com` fails.
**Confidence:** HIGH -- this is the documented consequence of `--iptables=false` per Docker docs.

### Pitfall 2: Tailscale Fails to Detect nftables Mode

**What goes wrong:** tailscaled logs warnings about firewall mode detection or creates iptables-compat rules that conflict with pure nftables setup.
**Why it happens:** tailscaled uses heuristics to detect the firewall backend. On NixOS with `networking.nftables.enable = true`, the `ip_tables` module is blacklisted, but tailscaled may still try to use iptables operations.
**How to avoid:** Set `systemd.services.tailscaled.serviceConfig.Environment = [ "TS_DEBUG_FIREWALL_MODE=nftables" ]` to force native nftables mode.
**Warning signs:** `journalctl -u tailscaled` shows "iptables" references or firewall mode detection warnings.
**Confidence:** MEDIUM -- reported in [NixOS/nixpkgs#285676](https://github.com/NixOS/nixpkgs/issues/285676), environment variable is a workaround, not a permanent fix.

### Pitfall 3: Docker User-Defined Bridge Networks and Firewall Trust

**What goes wrong:** Containers on user-defined bridge networks (like `agent_net`, `tools_net` from parts) cannot communicate, but containers on the default `docker0` bridge work fine.
**Why it happens:** User-defined Docker networks create `br-<hash>` interfaces. These are NOT the `docker0` interface. If only `docker0` is in `trustedInterfaces`, traffic on `br-<hash>` may be affected by firewall rules.
**How to avoid:** NixOS `networking.firewall.filterForward` defaults to `false`, meaning all forwarded traffic is accepted. As long as `filterForward` remains `false` (the default), inter-container traffic on any bridge works. Do NOT enable `filterForward` unless you also add explicit forward rules for Docker bridges.
**Warning signs:** `docker exec container1 ping container2` fails on user-defined networks but works on the default bridge.
**Confidence:** HIGH -- `filterForward = false` is the documented NixOS default; verified in [NixOS/nixpkgs#298165](https://github.com/NixOS/nixpkgs/issues/298165).

### Pitfall 4: nftables + Docker ip_tables Module Conflict

**What goes wrong:** Docker fails to start or container networking breaks because the `ip_tables` kernel module is blacklisted by `networking.nftables.enable = true`.
**Why it happens:** `networking.nftables.enable = true` adds `ip_tables` to `boot.blacklistedKernelModules`. Docker's default behavior auto-loads this module. When `--iptables=false` is set, Docker does NOT attempt to load `ip_tables`, so the blacklist is irrelevant.
**How to avoid:** The `--iptables=false` setting resolves this conflict by design. Docker never touches iptables, so the blacklist does not matter. This is a self-solving problem given the user's decision.
**Warning signs:** Docker service fails to start with errors about iptables. This should NOT happen with `--iptables=false`.
**Confidence:** HIGH -- logical conclusion: no iptables operations means no iptables module loading means no conflict with blacklist.

### Pitfall 5: Tailscale Authkey Expiry

**What goes wrong:** Server reboots after the Tailscale authkey expires. Tailscale fails to authenticate and the server is unreachable via Tailscale.
**Why it happens:** Tailscale pre-auth keys have expiration dates (default 90 days, configurable up to no expiry). If the key expires and the Tailscale state is lost, the server cannot re-authenticate.
**How to avoid:** (1) Use a reusable authkey with no expiry from the Tailscale admin console. (2) Tailscale persists its state in `/var/lib/tailscale/` -- after initial authentication, the authkey is only needed for first-time setup, not for reconnection after reboot. As long as the state directory is preserved (not on tmpfs), reboots work without re-auth.
**Warning signs:** `tailscale status` shows "NeedsLogin" after reboot.
**Confidence:** HIGH -- well-documented Tailscale behavior.

### Pitfall 6: Wrong External Interface Name

**What goes wrong:** `networking.nat.externalInterface = "eth0"` fails because the Contabo VPS uses a different interface name (e.g., `ens3`, `enp0s3`).
**Why it happens:** NixOS/systemd predictable interface naming assigns names based on PCI bus location, not `eth0`. The actual name depends on the VPS hardware configuration.
**How to avoid:** Check the actual interface name on the deployed server: `ip link show` or `ip addr`. Contabo VPS typically uses `ens3` or `eth0` depending on the kernel/hypervisor. Update the NAT config to match. Alternatively, use `networking.usePredictableInterfaceNames = false` to force `eth0`.
**Warning signs:** NAT rules reference wrong interface, containers have no outbound access despite NAT being enabled.
**Confidence:** HIGH -- standard Linux networking; interface name must be verified post-deployment.

### Pitfall 7: fail2ban Not Detecting SSH Failures

**What goes wrong:** fail2ban is running but never bans IPs despite SSH brute-force attempts visible in logs.
**Why it happens:** The default SSH jail requires `LogLevel VERBOSE` in sshd configuration. The fail2ban module sets this automatically via `services.openssh.settings.LogLevel = lib.mkDefault "VERBOSE"`. However, if Phase 2 or another module sets a different LogLevel, the default is overridden.
**How to avoid:** Do not explicitly set `services.openssh.settings.LogLevel` unless you set it to `"VERBOSE"` or higher. The fail2ban module handles this via `mkDefault`.
**Warning signs:** `fail2ban-client status sshd` shows 0 banned IPs despite visible brute-force attempts in `journalctl -u sshd`.
**Confidence:** HIGH -- documented in NixOS fail2ban wiki.

### Pitfall 8: Secrets File Not Populated Before Deployment

**What goes wrong:** `nix flake check` passes (it does not decrypt secrets), but `nixos-rebuild switch` on the server fails because `secrets/acfs.yaml` only contains `example_secret` and not the actual secrets referenced by modules.
**Why it happens:** Phase 1 created a placeholder `example_secret`. Phase 3 declares `sops.secrets."tailscale-authkey"` etc., but the keys must actually exist in the encrypted YAML file. sops-nix will fail at activation if a declared key is missing from the file.
**How to avoid:** Before deploying, edit `secrets/acfs.yaml` with `sops secrets/acfs.yaml` (requires admin age private key) and add all declared secret keys with their actual values. Replace `example_secret` with real secrets.
**Warning signs:** sops-nix activation errors: "key not found in sops file".
**Confidence:** HIGH -- this is how sops-nix works; keys must exist.

## Code Examples

### Complete networking.nix for Phase 3

```nix
# modules/networking.nix
# @decision NET-01: key-only SSH, no root login
# @decision NET-02: default-deny nftables firewall
# @decision NET-03: Tailscale VPN connected to tailnet
# @decision NET-04: ports 22, 80, 443, 22000 on public interface
# @decision NET-05: fail2ban SSH protection with progressive banning
# @decision NET-06: Tailscale reverse path filtering set to loose
{ config, lib, pkgs, ... }: {
  # --- nftables backend (Phase 2) ---
  networking.nftables.enable = true;

  # --- Firewall: per-interface trust ---
  networking.firewall = {
    enable = true;

    # Public interface: explicit port allowlist
    allowedTCPPorts = [ 22 80 443 22000 ];

    # Tailscale WireGuard tunnel (UDP)
    allowedUDPPorts = [ config.services.tailscale.port ];

    # Trusted interfaces: all traffic accepted
    trustedInterfaces = [
      "tailscale0"   # Tailscale (already authenticated by WireGuard)
      "docker0"      # Docker default bridge (container-to-container)
    ];
  };

  # --- SSH hardening (Phase 2) ---
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # --- Tailscale VPN ---
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale-authkey".path;
    useRoutingFeatures = "client";  # auto-sets checkReversePath = "loose"
    extraUpFlags = [
      "--accept-routes"   # receive routes from home network router
    ];
  };

  # Force tailscaled to use native nftables
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  # --- fail2ban SSH protection ---
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "10m";

    ignoreIP = [
      "127.0.0.0/8"
      "100.64.0.0/10"   # Tailscale CGNAT range
    ];

    bantime-increment = {
      enable = true;
      formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h";
      overalljails = true;
    };
  };

  # --- NAT for Docker containers (outbound internet access) ---
  # Required because Docker runs with --iptables=false
  networking.nat = {
    enable = true;
    internalInterfaces = [ "docker0" ];
    externalInterface = "eth0";   # VERIFY: may be ens3 on Contabo
  };
}
```

### Complete docker.nix (NEW module)

```nix
# modules/docker.nix
# @decision DOCK-01: Docker engine with --iptables=false
{ config, pkgs, ... }: {
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      iptables = false;           # NixOS owns the firewall, not Docker
      log-driver = "journald";    # Container logs in systemd journal
    };
  };
}
```

### Complete secrets.nix for Phase 3

```nix
# modules/secrets.nix
# @decision SEC-01: sops-nix age decryption at activation
# @decision SEC-03: all service credentials in sops
{ config, ... }: {
  sops = {
    defaultSopsFile = ../../secrets/acfs.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Tailscale auth key
    secrets."tailscale-authkey" = {
      restartUnits = [ "tailscaled.service" ];
    };

    # Backblaze B2 credentials (consumed in Phase 7)
    secrets."b2-account-id" = {};
    secrets."b2-account-key" = {};
    secrets."restic-password" = {};
  };
}
```

### Updated modules/default.nix

```nix
{
  imports = [
    ./base.nix
    ./boot.nix
    ./users.nix
    ./networking.nix
    ./secrets.nix
    ./docker.nix    # NEW: Phase 3
  ];
}
```

### secrets/acfs.yaml Structure (Decrypted View)

```yaml
# After editing with: sops secrets/acfs.yaml
# Replace example_secret with actual secrets

tailscale-authkey: "tskey-auth-XXXXX-XXXXXXXXXXXXXXXXX"
b2-account-id: "00xxxxxxxxx"
b2-account-key: "KXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
restic-password: "a-strong-random-password-for-restic-repo-encryption"
```

### Post-Deployment Verification Commands

```bash
# 1. Tailscale connected
ssh dangirsh@<IP> 'tailscale status'
# Expected: shows machine name, connected peers

# 2. Tailscale IP reachable from another tailnet device
ping <tailscale-ip-of-acfs>

# 3. Secrets decrypted
ssh dangirsh@<IP> 'ls /run/secrets/'
# Expected: tailscale-authkey, b2-account-id, b2-account-key, restic-password

# 4. Docker running with iptables=false
ssh dangirsh@<IP> 'docker info 2>/dev/null | grep -i iptables'
# Expected: iptables: false (or no iptables line)

# 5. Docker containers have outbound access
ssh dangirsh@<IP> 'docker run --rm alpine wget -qO- ifconfig.me'
# Expected: prints the server's public IP

# 6. fail2ban active
ssh dangirsh@<IP> 'sudo fail2ban-client status sshd'
# Expected: shows jail status, filter stats

# 7. External port scan (from another machine)
nmap -sT -p 1-65535 <PUBLIC_IP> --open
# Expected: only 22, 80, 443, 22000 open. No Docker ports exposed.

# 8. Tailscale accept-routes working
ssh dangirsh@<IP> 'tailscale status | grep -i route'
# Expected: routes from home network visible (if home router is advertising)

# 9. Reverse path filter is loose
ssh dangirsh@<IP> 'sysctl net.ipv4.conf.all.rp_filter'
# Expected: net.ipv4.conf.all.rp_filter = 2 (loose mode)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Docker default iptables (bypasses host firewall) | `--iptables=false` + NixOS NAT | Recognized best practice since 2021 ([nixpkgs#111852](https://github.com/NixOS/nixpkgs/issues/111852)) | Prevents Docker from exposing container ports on public interface |
| Manual `checkReversePath = "loose"` sysctl | `services.tailscale.useRoutingFeatures = "client"` | NixOS 23.05+ ([nixpkgs PR#201119](https://github.com/NixOS/nixpkgs/pull/201119)) | Declarative, auto-sets all required kernel params |
| Manual `tailscale up` in oneshot service | `services.tailscale.authKeyFile` | NixOS module, stable since 22.11+ | Built-in auto-auth, handles idempotent reconnection |
| iptables banaction for fail2ban | Auto-detected `nftables-multiport` | NixOS module auto-detection | No manual banaction config needed when nftables enabled |
| Docker `firewall-backend: iptables` (default) | Docker 29+ `firewall-backend: nftables` (EXPERIMENTAL) | Docker 29.0.0 (2024) | Not recommended for production; behavior may change |

**Deprecated/outdated:**
- Manual `tailscale up` systemd oneshot services: replaced by `services.tailscale.authKeyFile`
- `networking.firewall.extraCommands` with iptables syntax: use `extraInputRules` / `extraForwardRules` with nftables syntax when `networking.nftables.enable = true`
- Docker `DOCKER-USER` chain approach: only works with Docker's iptables mode; irrelevant when using `--iptables=false`

## Open Questions

1. **Contabo public interface name**
   - What we know: Contabo VPS may use `eth0` or `ens3` depending on kernel/hypervisor configuration. NixOS with systemd predictable naming may assign a different name.
   - What's unclear: The exact interface name on the deployed server.
   - Recommendation: After Phase 2 deployment, check `ip link show` on the server to determine the actual interface name. Set `networking.nat.externalInterface` accordingly. If uncertain, Phase 2 deployment verification should capture this. Alternatively, use a fallback: if the interface is definitely the only physical interface, `networking.usePredictableInterfaceNames = false` forces `eth0`.
   - **Impact:** Blocks `networking.nat.externalInterface` configuration. Without the correct name, Docker container outbound NAT will not work.

2. **Docker user-defined network interfaces and `trustedInterfaces`**
   - What we know: Docker's default bridge is `docker0`. User-defined networks (from parts module: `agent_net`, `tools_net`) create `br-<hash>` interfaces. `filterForward = false` (default) means forwarded traffic is accepted regardless.
   - What's unclear: Whether adding only `docker0` to `trustedInterfaces` is sufficient, or whether `br-<hash>` interfaces also need trust for INPUT chain rules.
   - Recommendation: `trustedInterfaces` affects the INPUT chain (host-bound traffic), not FORWARD chain (container-to-container). Since containers primarily communicate via FORWARD, and `filterForward = false` by default, `trustedInterfaces = [ "docker0" ]` is sufficient. If a container needs to reach a host service (e.g., host-bound port), the `br-<hash>` interface would need trust, but this is uncommon. Test after deployment.

3. **Tailscale authkey provisioning workflow**
   - What we know: A pre-auth key must be generated from the Tailscale admin console (https://login.tailscale.com/admin/settings/keys). It must be added to `secrets/acfs.yaml` via `sops secrets/acfs.yaml`.
   - What's unclear: Whether the user already has a reusable, non-expiring authkey or needs to generate one.
   - Recommendation: Generate a reusable, non-expiring auth key from the Tailscale admin console. Add it to secrets/acfs.yaml before deployment. This is a manual step that cannot be automated.

4. **B2 credential provisioning**
   - What we know: B2 credentials (account ID, account key) are needed for Phase 7 (restic backups). They come from the Backblaze B2 console.
   - What's unclear: Whether the user already has these credentials or needs to create them.
   - Recommendation: Declare the secret keys now (they will exist but be unused until Phase 7). If the user does not yet have B2 credentials, they can add placeholder values and update later. sops-nix only fails if the KEY is missing from the YAML, not if the value is a placeholder.

## Sources

### Primary (HIGH confidence)
- [NixOS Official Wiki: Tailscale](https://wiki.nixos.org/wiki/Tailscale) -- services.tailscale options, firewall configuration, authKeyFile usage
- [NixOS Official Wiki: Fail2ban](https://wiki.nixos.org/wiki/Fail2ban) -- bantime-increment, ignoreIP, nftables auto-detection, SSH jail defaults
- [NixOS Official Wiki: Firewall](https://wiki.nixos.org/wiki/Firewall) -- nftables.enable, trustedInterfaces, filterForward, extraForwardRules
- [NixOS Official Wiki: Docker](https://wiki.nixos.org/wiki/Docker) -- virtualisation.docker.daemon.settings, daemon.json mapping
- [Docker Docs: Packet filtering and firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/) -- --iptables=false behavior, NAT consequences
- [Docker Docs: Docker with nftables](https://docs.docker.com/engine/network/firewall-nftables/) -- experimental nftables backend, Docker 29.0 status
- [sops-nix README](https://github.com/Mic92/sops-nix) -- per-secret configuration, restartUnits, age key paths
- [MyNixOS: services.tailscale](https://mynixos.com/options/services.tailscale) -- complete option list (19 options)
- Codebase inspection: existing modules/networking.nix, modules/secrets.nix, .sops.yaml, secrets/acfs.yaml

### Secondary (MEDIUM confidence)
- [NixOS/nixpkgs#111852](https://github.com/NixOS/nixpkgs/issues/111852) -- Docker bypasses NixOS firewall; localhost binding as workaround
- [NixOS/nixpkgs#298165](https://github.com/NixOS/nixpkgs/issues/298165) -- Docker container networking fails with checkReversePath; filterForward default behavior
- [NixOS/nixpkgs#285676](https://github.com/NixOS/nixpkgs/issues/285676) -- tailscaled fails to detect nftables; TS_DEBUG_FIREWALL_MODE workaround
- [NixOS/nixpkgs PR#201119](https://github.com/NixOS/nixpkgs/pull/201119) -- useRoutingFeatures option implementation
- [Guekka: NixOS as a server, part 2](https://guekka.github.io/nixos-server-2/) -- Tailscale + sops-nix integration pattern
- [Michael Stapelberg: Secret Management with sops-nix (2025)](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/) -- comprehensive sops-nix guide
- Phase 3.1 Research (`.planning/phases/03.1-*/03.1-RESEARCH.md`) -- sops-nix cross-flake patterns, oci-containers, Docker network creation

### Tertiary (LOW confidence)
- Community reports on Docker+nftables compat layer behavior -- varies by Docker version and NixOS release
- [oneuptime.com: How to Use nftables with Docker](https://oneuptime.com/blog/post/2026-02-08-how-to-use-nftables-with-docker/view) -- general nftables+Docker guidance, not NixOS-specific

## Metadata

**Confidence breakdown:**
- Tailscale configuration: HIGH -- NixOS module is well-documented; authKeyFile, useRoutingFeatures, extraUpFlags all verified across multiple official sources
- fail2ban configuration: HIGH -- NixOS module auto-detects nftables; bantime-increment documented in official wiki with exact formula
- Secrets (sops-nix): HIGH -- existing infrastructure from Phase 1; adding keys is a standard extension of proven pattern
- Docker `--iptables=false`: MEDIUM-HIGH -- consequences well-documented in Docker docs, but NixOS NAT workaround for outbound access needs deployment verification (interface name, bridge trust)
- Docker + nftables interaction: MEDIUM -- `--iptables=false` avoids the conflict by design, but the NAT module behavior with nftables needs live testing
- Firewall per-interface rules: HIGH -- `trustedInterfaces` and `allowedUDPPorts` are standard NixOS options, verified in wiki

**Research date:** 2026-02-15
**Valid until:** 2026-03-15 (30 days -- Docker nftables support is actively evolving; NixOS module options are stable)
