# Plan 03-02 Summary: Docker engine + NixOS NAT + full stack validation

## What Changed

### modules/docker.nix (NEW)
- Docker engine with `iptables = false` — NixOS owns the firewall
- `log-driver = "journald"` — container logs in systemd journal
- `networking.nat` for docker0 outbound internet (masquerade via eth0)
- `docker0` in `trustedInterfaces` for container-to-host traffic
- `filterForward` defaults to false (NixOS default) allowing inter-container traffic on user-defined bridges

### modules/default.nix
- Added `./docker.nix` to imports list

### modules/users.nix
- Added `"docker"` to dangirsh's `extraGroups`

## Decisions

- **externalInterface = "eth0"**: Must verify on Contabo post-deploy — may be `ens3`. If wrong, NAT won't work and containers have no outbound access.
- **No filterForward**: Relying on NixOS default (`false`) to allow FORWARD chain traffic. This means containers on user-defined bridges can talk to each other without explicit rules.

## Verification

- `nix flake check` passes with complete Phase 3 stack
- `trustedInterfaces` merges correctly across modules: `["tailscale0"]` from networking.nix + `["docker0"]` from docker.nix
- Docker, Tailscale, fail2ban, and all secrets evaluate without conflicts
