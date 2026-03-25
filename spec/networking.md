# Networking Specification

This document specifies the network model, firewall configuration, SSH hardening,
Tailscale integration, and agent egress controls.

Source: `modules/networking.nix`, `SECURITY.md`

## Firewall

| ID | Claim | Source |
|----|-------|--------|
| NET-001 | nftables backend enabled | `modules/networking.nix` line 112 |
| NET-002 | Public TCP ports: `22` always; `80` and `443` only when `services.nginx.enable = true` | `modules/networking.nix` line 159, `@decision NET-01` |
| NET-004 | `trustedInterfaces = [ ]` — no interface is trusted, including `tailscale0` | `modules/networking.nix` line 136, `@decision NET-122-01` |
| NET-005 | Build-time assertion prevents internal service ports from leaking into `allowedTCPPorts` | `modules/networking.nix` lines 15-18, `@decision NET-07` |
| NET-007 | Firewall ports match nginx state on both service and dev hosts | `tests/eval/config-checks.nix:firewall-ports-services`, `firewall-ports-dev` |
| NET-008 | `tailscale0` not in `trustedInterfaces` on either host | `tests/eval/config-checks.nix:no-trusted-tailscale0-services`, `no-trusted-tailscale0-dev` |
| NET-009 | `allowPing = true` | `modules/networking.nix` line 158 |

## Cloud Metadata Protection

| ID | Claim | Source |
|----|-------|--------|
| NET-010 | nftables drops outbound traffic to `169.254.169.254` (cloud metadata endpoint) | `modules/networking.nix` lines 115-123 |
| NET-011 | Metadata block table defined on all hosts | `tests/eval/config-checks.nix:metadata-block` |

## SSH Hardening

| ID | Claim | Source |
|----|-------|--------|
| NET-012 | SSH enabled, `openFirewall = false` (port 22 added explicitly to allowedTCPPorts) | `modules/networking.nix` lines 168-170 |
| NET-013 | `PasswordAuthentication = false` — key-only auth | `modules/networking.nix` line 175 |
| NET-014 | `KbdInteractiveAuthentication = false` | `modules/networking.nix` line 176 |
| NET-015 | `PermitRootLogin = "prohibit-password"` — key-only root for deploy pipeline | `modules/networking.nix` line 177 |
| NET-016 | `X11Forwarding = false` | `modules/networking.nix` line 178 |
| NET-017 | `MaxAuthTries = 3` | `modules/networking.nix` line 179 |
| NET-018 | `LoginGraceTime = 30` | `modules/networking.nix` line 180 |
| NET-019 | `ClientAliveInterval = 300`, `ClientAliveCountMax = 3` | `modules/networking.nix` lines 181-182 |
| NET-020 | Host key type: ed25519 only | `modules/networking.nix` line 172, `tests/eval/config-checks.nix:ssh-ed25519-only` |
| NET-021 | `fail2ban` disabled (brute-force mitigation via MaxAuthTries 3 + key-only auth) | `modules/networking.nix` line 165, `@decision NET-01` |
| NET-022 | AuthorizedKeysFiles order: `.ssh/authorized_keys` before `/etc/ssh/authorized_keys.d/%u` (impermanence fallback) | `modules/networking.nix` line 187, `@decision NET-14` |

## Lockout Prevention Assertions

| ID | Claim | Source |
|----|-------|--------|
| NET-028 | sshd must be enabled | `modules/networking.nix` lines 88-89 |
| NET-029 | `PermitRootLogin` must not be `"no"` (deploy-rs uses root SSH) | `modules/networking.nix` lines 92-93 |
| NET-030 | SSH port 22 must be reachable | `modules/networking.nix` lines 96-98 |
| NET-032 | Root must have break-glass emergency SSH key | `modules/networking.nix` lines 84-86 |

## Agent Egress

| ID | Claim | Source |
|----|-------|--------|
| NET-033 | Agent egress enforced at host nftables by `meta skuid` for the dedicated agent UID | `modules/networking.nix` lines 126-153, `@decision NET-144-01` |
| NET-034 | Default allowed outbound for agents: loopback, DNS (TCP/UDP 53), TCP 22/80/443 | `modules/networking.nix` lines 31-47, 139-148 |
| NET-035 | Default blocked for agents: RFC1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), Tailscale CGNAT (`100.64.0.0/10`), link-local (`169.254.0.0/16`) | `modules/networking.nix` lines 58-65, 144-145 |
| NET-036 | Default blocked IPv6: ULA (`fc00::/7`), link-local (`fe80::/10`) | `modules/networking.nix` lines 70-72, 146 |
| NET-037 | Agent egress table defined | `tests/eval/config-checks.nix:agent-egress-table` |
| NET-038 | Egress policy scopes by agent UID, blocks private ranges, and allows HTTPS | `tests/eval/config-checks.nix:agent-egress-policy` |
| NET-039 | Default drop rule: all other agent outbound traffic dropped | `modules/networking.nix` line 149 |
| NET-040 | Egress configurable: `tsurf.agentEgress.{enable, allowedTCPPorts, allowDns, blockPrivateRanges, blockedIPv4Cidrs, blockedIPv6Cidrs}` | `modules/networking.nix` lines 26-78 |

## SSH Host Key Persistence

| ID | Claim | Source |
|----|-------|--------|
| NET-041 | SSH host key (`/etc/ssh/ssh_host_ed25519_key` and `.pub`) persisted across reboots | `modules/networking.nix` lines 202-204 |
