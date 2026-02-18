# Quick Task 3 — Summary

## What Changed

Created `modules/homepage.nix` — a NixOS-native homepage-dashboard linking all server services, with iterative refinements:

1. **Initial dashboard** — 6 services (Grafana, Prometheus, Alertmanager, ntfy, Syncthing, Home Assistant) with Tailscale URLs
2. **Host validation fix** — Added `allowedHosts` with ip:port format for Next.js host validation
3. **Descriptions + icons** — Grouped services into Monitoring, Notifications & Sync, Home categories with detailed descriptions
4. **Global Tailscale note** — Moved Tailscale mention to greeting widget, removed stale details from descriptions
5. **Live status monitoring** — Added `siteMonitor` URLs to all services with `statusStyle = "dot"`
6. **Docker container services** — Added Applications group (claw-swap, Parts Tools, Parts Agent) with Docker socket integration for live container status

## Decisions

- @decision HP-01: Use NixOS-native homepage-dashboard service; listen on 0.0.0.0 for Tailscale reachability
- allowedHosts must include ip:port format (100.127.245.9:8082) for Next.js validation
- Docker socket at /var/run/docker.sock for container status monitoring
- siteMonitor uses localhost health endpoints (not Tailscale IP)

## Files Modified

| File | Change |
|------|--------|
| modules/homepage.nix | New — full homepage dashboard with 4 service groups, status monitoring, Docker integration |
| modules/default.nix | Added `./homepage.nix` to imports |
| modules/networking.nix | Added build-time assertion preventing internal port exposure in allowedTCPPorts |

## Commits

- `48b0182` — feat(quick-3): create homepage-dashboard NixOS module
- `f1f6e33` — fix: allowedHosts for host validation
- `0e63597` — fix: allowedHosts ip:port format
- `9fb4027` — feat: detailed descriptions and icons
- `031240d` — fix: clean up descriptions, global Tailscale note
- `09c84d7` — feat: live service status monitoring
- `ca53c6f` — feat: Docker container services
