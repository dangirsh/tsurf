# Execution Summary: Plan 47-01 — Network Hardening + Port Audit

## Result: PASS

## Changes Made

| File | Change |
|------|--------|
| `modules/networking.nix` | Removed `programs.mosh.enable = true` (SEC47-08: closed UDP 60000-61000). Added `6052` (ESPHome) and `8123` (Home Assistant) to `internalOnlyPorts`. Updated NET-01 annotation to reflect deliberate public SSH for recovery (not temporary). Updated NET-04 to clarify all other services are internal. Added NET-10 (ports 80/443 nginx), NET-11 (port 22000 Syncthing BEP), NET-12 (fail2ban via srvos), NET-13 (SSH hardening settings). Added `X11Forwarding = false`, `MaxAuthTries = 3`, `LoginGraceTime = 30`, `ClientAliveInterval = 300`, `ClientAliveCountMax = 3` to SSH settings. |
| `CLAUDE.md` | Fixed SSH documentation contradiction: changed "SSH via Tailscale only" to "SSH hardened: Port 22 on public firewall (key-only, fail2ban-protected)". Updated `networking.nix` description from "SSH (Tailscale-only)" to "SSH (hardened)". |

## Commits

- `17b0f37` feat(47-02): service isolation — systemd hardening + blast radius docs (combined commit with 47-02 changes)
- `887706e` chore(47-01): record nix flake check pass for security review branch

## Verification

- `nix flake check`: PASS (both neurosys and ovh configurations)
- All `must_haves` satisfied:
  1. Port 22 documented accurately in both networking.nix and CLAUDE.md
  2. Mosh removed (SEC47-08) — 1001 UDP ports closed
  3. All known internal ports in `internalOnlyPorts` (6052, 8082, 8123, 8384, 8400, 9090, 9091, 9100, 9201-9204)
  4. No new ports added to `allowedTCPPorts`
  5. SSH hardened with X11Forwarding=false, MaxAuthTries=3, etc.

## Decisions

- **SEC47-01**: Port 22 public SSH is deliberate for bootstrap/recovery, not temporary
- **SEC47-02**: Port 22000 (Syncthing BEP) kept — encrypted, device-authenticated
- **SEC47-08**: Mosh removed — unused, 1001 UDP ports closed
- **NET-12**: fail2ban comes from srvos server profile, no explicit config needed
- **NET-13**: No explicit cipher restrictions — NixOS 25.11 OpenSSH defaults sufficient
