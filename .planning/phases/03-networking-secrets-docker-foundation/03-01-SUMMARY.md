# Plan 03-01 Summary: Tailscale VPN + sops-nix secrets + fail2ban + firewall hardening

## What Changed

### modules/secrets.nix
- Added 4 secret declarations: `tailscale-authkey` (with `restartUnits`), `b2-account-id`, `b2-account-key`, `restic-password`
- Fixed `defaultSopsFile` path from `../../secrets/acfs.yaml` to `../secrets/acfs.yaml` (was resolving above flake root)

### modules/networking.nix
Full rewrite from 14-line stub to comprehensive networking module:
- **nftables**: `networking.nftables.enable = true`
- **Firewall**: TCP 22/80/443/22000, UDP for Tailscale, trust `tailscale0`
- **SSH**: hardened — `PermitRootLogin = "no"`, `KbdInteractiveAuthentication = false`
- **Tailscale**: `authKeyFile` from sops, `useRoutingFeatures = "client"` (auto loose rp_filter), `--accept-routes`
- **tailscaled**: `TS_DEBUG_FIREWALL_MODE=nftables` environment variable
- **fail2ban**: 5 retries, 10m ban, progressive multipliers (1-64x), 168h max, Tailscale CGNAT whitelist

### .sops.yaml
- Replaced orphaned `admin_dangirsh` key (`age1q4cgep7...`) with working `admin` key (`age1vma7w9...`)

### secrets/acfs.yaml
- Re-encrypted from scratch with correct admin + host keys
- Contains placeholder values for all 5 secrets (user must edit with `sops secrets/acfs.yaml`)

## Decisions

- **fail2ban**: Removed `formula` option (mutually exclusive with `multipliers` in NixOS) — kept `multipliers = "1 2 4 8 16 32 64"` for simpler progressive banning
- **sopsFile path**: `../secrets/acfs.yaml` is correct relative path from `modules/` to flake root `secrets/`

## User Action Required

Before deployment, run `sops secrets/acfs.yaml` and replace all `placeholder-replace-me` values with real credentials:
- `tailscale-authkey`: from Tailscale Admin Console
- `b2-account-id` / `b2-account-key`: from Backblaze B2 Console
- `restic-password`: generate a strong random password

## Verification

- `nix flake check` passes
- All secrets decrypt correctly with local admin key
