---
phase: 02-bootable-base-system
plan: 02
one_liner: "NixOS deployed to Contabo VPS via nixos-anywhere — all services running, SSH verified"
duration: ~45min
---

## What Was Done

Deployed the hardened NixOS configuration to the Contabo VPS (62.171.134.33) using nixos-anywhere.

### Pre-Deploy Fixes (from Codex 5.3 audit + investigation)

1. **Static IP configuration** — Contabo VPS uses static IP, not DHCP. Added explicit config:
   - `networking.useDHCP = false`
   - `networking.interfaces.eth0.ipv4.addresses = [{ address = "62.171.134.33"; prefixLength = 19; }]`
   - Gateway: `62.171.128.1`, DNS: `213.136.95.10`, `213.136.95.11`

2. **PermitRootLogin = "prohibit-password"** — Changed from "no" to allow key-only root access during deployment recovery

3. **allowPing = true** — Added to firewall for diagnostics

4. **BIOS boot partition 2M** — Increased from 1M for alignment safety

5. **Removed kvm-amd kernel module** — Host CPU may be Intel

6. **Agent SSH key** — Added `parts-agent@vm` key to both dangirsh and root authorized_keys

7. **Parts sops key fix** — Updated `parts/.sops.yaml` with new host key, re-encrypted `secrets/parts.yaml`

### Deployment

- nixos-anywhere deployed successfully (kexec → disko → system closure → GRUB install → reboot)
- Initial boot had sops parts.yaml decryption failure (stale flake.lock narHash)
- Fixed: `nix flake lock --recreate-lock-file` to pick up committed parts.yaml
- Added `security.sudo.wheelNeedsPassword = false` for dangirsh
- Applied via `nix copy --to ssh://` + remote `switch-to-configuration switch`

### Verification Results

| Check | Status | Detail |
|-------|--------|--------|
| Hostname | PASS | `acfs` |
| Timezone | PASS | `Europe/Berlin` |
| Firewall | PASS | nftables, ports 22/80/443/22000 TCP, Tailscale UDP, ping |
| SSH (dangirsh) | PASS | Key auth, passwordless sudo |
| SSH (root) | PASS | Key auth only (prohibit-password) |
| Password auth | PASS | Disabled |
| Docker | PASS | Active, parts-tools container running |
| Tailscale | PASS | Active |
| Nix GC timer | PASS | Daily schedule |
| sops secrets | PASS | 15 secrets decrypted to /run/secrets/ |
| Disk | PASS | 147G root (12% used), 511M boot |
| User groups | PASS | dangirsh: wheel, docker |

## Key Decisions

- @decision DEPLOY-01: Contabo VPS uses static IP — all NixOS configs must hardcode IP/gateway/DNS
- @decision DEPLOY-02: For non-NixOS build hosts, use `nix copy --to ssh://` + remote `switch-to-configuration switch` instead of nixos-rebuild
- @decision DEPLOY-03: `nix flake lock --recreate-lock-file` required when path inputs change (narHash caching)

## Commits

- `376bc68` — fix(02): harden NixOS config for reliable nixos-anywhere deployment
- `775d9d6` — fix(deploy): passwordless sudo + update parts flake lock
- `fd68607` (parts repo) — fix(sops): re-encrypt parts.yaml with new acfs host key

## Blockers Resolved

- Previous deployment failure: static IP config missing + stale sops keys
- parts.yaml decryption: flake.lock narHash caching prevented pickup of re-encrypted file
- dangirsh sudo: no password set, needed wheelNeedsPassword = false
