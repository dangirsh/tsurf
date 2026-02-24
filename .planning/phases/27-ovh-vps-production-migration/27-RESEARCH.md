# Phase 27: OVH VPS Production Migration - Research

**Researched:** 2026-02-23
**Domain:** NixOS multi-host deployment, nixos-anywhere, deploy-rs, sops-nix, Tailscale, OVH VPS infrastructure
**Confidence:** MEDIUM (OVH-specific details are LOW due to limited official documentation; multi-host NixOS patterns are HIGH from codebase analysis + community patterns)

## Summary

This phase migrates production from a Contabo VPS (161.97.74.121) to a new OVH VPS (135.125.196.143, stock Ubuntu 25) and refactors the single-host flake into a multi-host configuration. The existing neurosys codebase is well-structured for this -- modules are already cleanly separated from host-specific config in `hosts/neurosys/default.nix`, with only static IP, hostname, and srvos overrides being host-specific. The main work is: (1) pre-generate SSH host key for OVH, derive age key, update `.sops.yaml`, (2) create `hosts/ovh/` with OVH-specific hardware/network config, (3) add second `nixosConfigurations` and `deploy.nodes` entry in `flake.nix`, (4) run nixos-anywhere against the OVH VPS, (5) join Tailscale, (6) migrate services and DNS, (7) repurpose Contabo as staging.

**Primary recommendation:** Structure this as 4-5 plans: (1) secrets bootstrap + host key generation for OVH, (2) multi-host flake refactor with shared modules, (3) nixos-anywhere deployment to OVH, (4) service migration + DNS cutover, (5) Contabo staging repurpose. Plans 1-2 are autonomous code changes; Plan 3 is human-interactive (destructive deploy); Plan 4-5 involve DNS and service state migration.

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| nixos-anywhere | latest (github:nix-community/nixos-anywhere) | Remote NixOS installation via kexec+disko | Already used for Contabo deployment in Phase 2; proven workflow |
| deploy-rs | pinned in flake.lock | Multi-node deployment with magic rollback | Already integrated in Phase 25; native multi-node support via `deploy.nodes` |
| sops-nix | pinned in flake.lock | Multi-host secret provisioning via age keys | Already used; supports multiple host keys in `.sops.yaml` creation_rules |
| disko | pinned in flake.lock | Declarative disk partitioning | Already used for Contabo; new disko config needed for OVH disk device |
| ssh-to-age | CLI tool | Derive age public key from SSH host key | Already used during Phase 1 for Contabo host key |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| sops CLI | Re-encrypt secrets with new host key | After adding OVH age key to `.sops.yaml` |
| Tailscale pre-auth key | Automated Tailscale join for new node | Generate in Tailscale admin, inject via sops-nix |
| SSHPASS + --env-password | Password-based SSH for nixos-anywhere | OVH VPS has root password auth, no SSH keys initially |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| nixos-anywhere | OVH rescue mode + manual install | Manual and error-prone; nixos-anywhere automates the entire flow |
| Separate secrets files per host | Single shared secrets file with both host keys | Separate files are cleaner for access control; shared file is simpler for small team |
| systemd-networkd (srvos default) | Scripted networking (current Contabo pattern) | OVH may support DHCP (unlike Contabo), making networkd viable. Investigate during deployment. |

## Architecture Patterns

### Recommended Project Structure After Refactor

```
flake.nix                 # Two nixosConfigurations + two deploy.nodes
hosts/
  common/
    default.nix           # Shared host config (timezone, locale, stateVersion)
  neurosys/               # Contabo (staging) -- existing, renamed role
    default.nix           # Contabo static IP, hostname, srvos overrides
    hardware.nix          # QEMU guest, virtio modules
    disko-config.nix      # /dev/sda BTRFS layout
  ovh/                    # OVH (production)
    default.nix           # OVH IP config, hostname, srvos overrides
    hardware.nix          # OVH-specific hardware (QEMU guest, possibly different modules)
    disko-config.nix      # OVH disk layout (may differ: /dev/sda or /dev/vda)
modules/                  # UNCHANGED -- all modules are already host-agnostic
  default.nix             # Import hub (shared by all hosts)
  base.nix, boot.nix, ... # All existing modules
home/                     # UNCHANGED -- shared by all hosts
secrets/
  neurosys.yaml           # Secrets for Contabo (staging) -- encrypted with admin + host_neurosys keys
  ovh.yaml                # Secrets for OVH (production) -- encrypted with admin + host_ovh keys
  shared.yaml             # (OPTIONAL) Secrets shared between both hosts -- encrypted with all keys
.sops.yaml                # Updated with OVH host key + per-file creation_rules
```

### Pattern 1: Multi-Host Flake Configuration

**What:** Define a helper function or inline both configurations sharing the same module set.
**When to use:** When hosts share 95%+ of their config (which they do here -- only IP/hostname/hardware differ).
**Confidence:** HIGH -- verified against codebase analysis and community patterns.

```nix
# flake.nix pattern
outputs = { self, nixpkgs, ... } @ inputs:
  let
    system = "x86_64-linux";
    commonModules = [
      srvos.nixosModules.server
      disko.nixosModules.disko
      impermanence.nixosModules.impermanence
      sops-nix.nixosModules.sops
      home-manager.nixosModules.home-manager
      inputs.parts.nixosModules.default
      inputs.claw-swap.nixosModules.default
      { nixpkgs.overlays = [ llm-agents.overlays.default ]; }
      ./modules
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit inputs; };
        home-manager.users.dangirsh = import ./home;
      }
    ];
    mkHost = hostDir: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = commonModules ++ [ hostDir ];
    };
  in {
    nixosConfigurations.neurosys = mkHost ./hosts/neurosys;
    nixosConfigurations.ovh = mkHost ./hosts/ovh;

    deploy.nodes.neurosys = { /* existing config */ };
    deploy.nodes.ovh = {
      hostname = "neurosys-prod";  # Tailscale MagicDNS name
      sshUser = "root";
      magicRollback = true;
      autoRollback = true;
      confirmTimeout = 120;
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.ovh;
      };
    };
  };
```

### Pattern 2: Per-Host Secrets with Shared `.sops.yaml`

**What:** Each host has its own secrets file encrypted with admin + that host's key. Shared secrets go in a third file encrypted with all keys.
**When to use:** When some secrets differ between hosts (e.g., Tailscale auth key) and others are shared (e.g., API keys, B2 credentials).
**Confidence:** HIGH -- directly extends existing `.sops.yaml` pattern.

```yaml
# .sops.yaml
keys:
  - &admin          age1vma7w9nqlg9da8z60a99g8wv53ufakfmzxpkdnnzw39y34grug7qklz3xz
  - &host_neurosys  age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3
  - &host_ovh       age1<derived-from-ovh-ssh-host-key>
creation_rules:
  - path_regex: secrets/neurosys\.yaml$
    key_groups:
      - age:
        - *admin
        - *host_neurosys
  - path_regex: secrets/ovh\.yaml$
    key_groups:
      - age:
        - *admin
        - *host_ovh
  - path_regex: secrets/shared\.yaml$
    key_groups:
      - age:
        - *admin
        - *host_neurosys
        - *host_ovh
```

### Pattern 3: Host-Specific Secrets Module

**What:** Each host's `default.nix` sets `sops.defaultSopsFile` to its own secrets file, with per-secret overrides for shared secrets.
**Confidence:** HIGH -- extends existing `modules/secrets.nix` pattern.

```nix
# hosts/ovh/default.nix (excerpt)
{ config, ... }: {
  imports = [ ./hardware.nix ./disko-config.nix ../../modules ];

  networking.hostName = "neurosys-prod";

  # Host-specific sops file
  sops.defaultSopsFile = ../../secrets/ovh.yaml;

  # Override specific secrets to use shared file
  sops.secrets."b2-account-id".sopsFile = ../../secrets/shared.yaml;
  sops.secrets."b2-account-key".sopsFile = ../../secrets/shared.yaml;
  # ... etc
}
```

**Alternative (simpler):** Keep ALL secrets in host-specific files (duplicate the values). For 7 secrets, duplication is manageable and avoids cross-file complexity. This is probably the better choice given the small secret count.

### Pattern 4: deploy-rs Multi-Node Targeting

**What:** Deploy to specific nodes using flake path syntax.
**Confidence:** HIGH -- verified from deploy-rs README.

```bash
# Deploy only to OVH (production)
nix run .#deploy-rs -- .#ovh

# Deploy only to Contabo (staging)
nix run .#deploy-rs -- .#neurosys

# Deploy to both (sequential, atomic rollback on failure)
nix run .#deploy-rs -- --targets .#neurosys .#ovh
```

### Anti-Patterns to Avoid

- **Shared host config in `hosts/common/default.nix` for small differences:** With only 3-4 lines differing between hosts (IP, hostname, gateway), extracting common host config into a separate file adds indirection without value. Keep `hosts/*/default.nix` self-contained with the 5 host-specific lines; all shared config is already in `modules/`.
- **Single secrets file for both hosts:** Each host can only decrypt with its own key. Using one file encrypted with both keys means a compromised staging host can decrypt production secrets. Use separate files per host.
- **DNS cutover before verification:** Change DNS only AFTER the OVH node is fully verified (services running, Tailscale connected, deploy-rs works). DNS TTL must be lowered in advance.
- **Deploying impermanence to OVH before it's tested on Contabo:** Phase 21-02 (impermanence deploy) is still pending. Deploy OVH without impermanence first, then enable it after testing on Contabo staging.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SSH host key generation | Manual ssh-keygen on VPS | `ssh-keygen -t ed25519` locally + `--extra-files` with nixos-anywhere | Keeps key under our control before deploy, enables pre-populating `.sops.yaml` |
| Age key derivation | Manual age-keygen | `ssh-to-age < host_key.pub` | Standard sops-nix pattern, already used for Contabo |
| Multi-node deploy orchestration | Custom shell scripts | deploy-rs `--targets` | deploy-rs handles rollback, confirmation, profile ordering |
| Tailscale node join | Interactive `tailscale up` | `services.tailscale.authKeyFile` with sops-nix secret | Fully declarative, works on first boot |
| Network config discovery | Guess from provider docs | `nixos-anywhere --generate-hardware-config nixos-generate-config ./hardware-configuration.nix` | Auto-detects disk devices, kernel modules, network interfaces |

**Key insight:** The existing codebase already has all the patterns needed. The Contabo deployment (Phase 2) established the exact nixos-anywhere + sops-nix + Tailscale flow. This phase is a second execution of the same playbook with multi-host refactoring layered on top.

## Common Pitfalls

### Pitfall 1: OVH kexec Image Hang

**What goes wrong:** nixos-anywhere's default kexec image may hang on OVH VPS infrastructure. Multiple reports confirm recent kexec images are broken on OVH.
**Why it happens:** OVH's KVM hypervisor has compatibility issues with newer NixOS kexec images. The exact cause is unclear but well-documented in community reports.
**How to avoid:** Use the `--kexec` flag with an older, known-working image (NixOS 22.11 confirmed working on OVH). Build command:
```bash
nix run github:nix-community/nixos-anywhere -- \
  --kexec "$(nix build --print-out-paths github:nix-community/nixos-images#packages.x86_64-linux.kexec-installer-nixos-22.11)/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz" \
  --flake .#ovh root@135.125.196.143
```
**Warning signs:** nixos-anywhere appears to hang after "kexec" step with no further output. If this happens, try the older image.
**Confidence:** MEDIUM -- based on community reports (raghavsood.com/blog, discourse.nixos.org), not personal verification. The VPS may work fine with the default image. Have the older image fallback ready.

### Pitfall 2: OVH Network Configuration (DHCP vs Static)

**What goes wrong:** After nixos-anywhere installs NixOS, the server loses network connectivity because the network config is wrong.
**Why it happens:** OVH VPS behavior varies: some use DHCP, some require static IP. Unlike Contabo (which is definitively static-only), OVH's stance is less clear. The current stock Ubuntu 25 likely uses DHCP.
**How to avoid:** Two approaches:
1. **Test DHCP first:** Configure `networking.useDHCP = true` for OVH host. If it works, great -- simpler than static.
2. **Fall back to static:** If DHCP fails, configure static IP like Contabo: `networking.interfaces.ens3.ipv4.addresses` (note: OVH may use `ens3` not `eth0`).
3. **Use `--generate-hardware-config`** during nixos-anywhere to auto-detect the right interface name.
**Warning signs:** nixos-anywhere completes but SSH to the new IP fails post-reboot.
**Confidence:** LOW for specific OVH network details. The operator should SSH into the stock Ubuntu VPS first to inspect `/etc/netplan/`, `ip addr`, and `lsblk` before writing the NixOS config.

### Pitfall 3: srvos `networking.useNetworkd` Conflict

**What goes wrong:** srvos server module enables `networking.useNetworkd = true` by default. If OVH needs scripted networking (like Contabo), this must be overridden.
**Why it happens:** The current Contabo host already has `networking.useNetworkd = lib.mkForce false` as a srvos override (decision [24-01]). The OVH host needs the same analysis.
**How to avoid:** If OVH uses DHCP, systemd-networkd may actually work fine (it's the modern default). Only force scripted networking if static IP is required AND networkd has issues.
**Warning signs:** Network doesn't come up after boot; `journalctl -u systemd-networkd` shows errors.
**Confidence:** HIGH -- this is a known pattern from Phase 24.

### Pitfall 4: Disk Device Name Mismatch

**What goes wrong:** disko config references `/dev/sda` but OVH uses `/dev/vda` or `/dev/nvme0n1`.
**Why it happens:** Different hypervisors present disks differently. OVH VPS historically uses `/dev/sda` but this varies.
**How to avoid:** SSH into the stock Ubuntu VPS and run `lsblk` before writing the disko config. Use the exact device name shown.
**Warning signs:** nixos-anywhere fails during partitioning with "device not found" errors.
**Confidence:** HIGH -- this exact issue was handled during Phase 2 Contabo deployment.

### Pitfall 5: UEFI vs BIOS Boot Mode

**What goes wrong:** disko config has wrong boot partition type (EF02 for BIOS vs EF00 for UEFI).
**Why it happens:** OVH VPS boot mode varies by plan. Older/cheaper VPS plans use BIOS; newer ones may use UEFI.
**How to avoid:** SSH into stock Ubuntu and check: `ls /sys/firmware/efi` (exists = UEFI, not found = BIOS). The current disko-config.nix has BOTH a BIOS boot partition (EF02, 2M) and an ESP partition (EF00, 512M), which is a hybrid layout that works for both. Keep this pattern.
**Warning signs:** System fails to boot after nixos-anywhere install; OVH console shows "No bootable device".
**Confidence:** HIGH -- existing disko-config.nix already handles both modes.

### Pitfall 6: Tailscale Auth Key Expiration

**What goes wrong:** The Tailscale pre-auth key in sops-nix expires before or shortly after deployment.
**Why it happens:** Tailscale pre-auth keys have a configurable TTL (default 90 days, can be set to 1 day minimum). The existing neurosys Tailscale auth key may be expired.
**How to avoid:** Generate a fresh pre-auth key immediately before the nixos-anywhere deployment. Use a reusable key if both hosts need it. Store in sops-nix.
**Warning signs:** `tailscaled` service fails to start; `journalctl -u tailscaled` shows auth errors.
**Confidence:** HIGH -- standard Tailscale operational concern.

### Pitfall 7: Losing SSH Access During Migration

**What goes wrong:** After nixos-anywhere deploys to OVH, SSH keys change, and the operator cannot connect.
**Why it happens:** nixos-anywhere generates new SSH host keys (or uses pre-generated ones via `--extra-files`). The old Ubuntu host keys are gone.
**How to avoid:** Run `ssh-keygen -R 135.125.196.143` after nixos-anywhere completes. Use `--extra-files` to inject the pre-generated host key so the key is known in advance.
**Warning signs:** "HOST KEY VERIFICATION FAILED" when trying to SSH after deployment.
**Confidence:** HIGH -- documented in nixos-anywhere quickstart.

### Pitfall 8: Password Auth for Initial nixos-anywhere Deploy

**What goes wrong:** nixos-anywhere cannot SSH to the OVH VPS because it requires password authentication.
**Why it happens:** Stock Ubuntu VPS has root password (6f2d2gQSdW2P), not SSH key auth.
**How to avoid:** Use `SSHPASS` environment variable with `--env-password` flag:
```bash
SSHPASS="6f2d2gQSdW2P" nix run github:nix-community/nixos-anywhere -- \
  --env-password --flake .#ovh root@135.125.196.143
```
**Warning signs:** nixos-anywhere prompts for password or hangs at SSH connection.
**Confidence:** HIGH -- documented in nixos-anywhere official docs.

## Code Examples

### Example 1: Pre-generate SSH Host Key and Derive Age Key

```bash
# Generate SSH host key for OVH
ssh-keygen -t ed25519 -f tmp/ovh_ssh_host_ed25519_key -N "" -C "host_ovh"

# Derive age public key
nix-shell -p ssh-to-age --run 'ssh-to-age < tmp/ovh_ssh_host_ed25519_key.pub'
# Output: age1<new_public_key>

# Prepare --extra-files directory structure
mkdir -p tmp/ovh-host-keys/persist/etc/ssh
cp tmp/ovh_ssh_host_ed25519_key tmp/ovh-host-keys/persist/etc/ssh/ssh_host_ed25519_key
chmod 600 tmp/ovh-host-keys/persist/etc/ssh/ssh_host_ed25519_key
```

Source: Phase 2 deployment experience (MEMORY.md), sops-nix README, nixos-anywhere docs.

### Example 2: Update `.sops.yaml` for Multi-Host

```yaml
keys:
  - &admin          age1vma7w9nqlg9da8z60a99g8wv53ufakfmzxpkdnnzw39y34grug7qklz3xz
  - &host_neurosys  age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3
  - &host_ovh       age1<derived-key-here>
creation_rules:
  - path_regex: secrets/neurosys\.yaml$
    key_groups:
      - age:
        - *admin
        - *host_neurosys
  - path_regex: secrets/ovh\.yaml$
    key_groups:
      - age:
        - *admin
        - *host_ovh
```

Source: Existing `.sops.yaml` pattern + sops-nix multi-host documentation.

### Example 3: OVH Host Configuration

```nix
# hosts/ovh/default.nix
{ config, pkgs, inputs, lib, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
  ];

  networking.hostName = "neurosys-prod";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # --- Network config (determine DHCP vs static during pre-deploy recon) ---
  # Option A: DHCP (try first)
  networking.useDHCP = true;
  # Option B: Static (fallback if DHCP fails)
  # networking.useDHCP = false;
  # networking.interfaces.ens3.ipv4.addresses = [{
  #   address = "135.125.196.143";
  #   prefixLength = <discovered>;
  # }];
  # networking.defaultGateway = {
  #   address = "<discovered>";
  #   interface = "ens3";
  # };
  # networking.nameservers = [ "213.186.33.99" ];  # OVH DNS

  # --- srvos overrides ---
  # If using DHCP, systemd-networkd (srvos default) may work fine.
  # Only force scripted networking if static IP is needed:
  # networking.useNetworkd = lib.mkForce false;

  srvos.server.docs.enable = true;
  programs.command-not-found.enable = true;
  boot.initrd.systemd.enable = lib.mkForce false;

  # --- sops secrets (host-specific file) ---
  sops.defaultSopsFile = ../../secrets/ovh.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  system.stateVersion = "25.11";
}
```

Source: Existing `hosts/neurosys/default.nix` adapted for OVH.

### Example 4: deploy.sh Multi-Target Support

```bash
# Updated deploy.sh argument parsing (add --node flag)
NODE="neurosys"  # default to staging
# ...
--node)
  NODE="$2"
  shift 2
  ;;
# ...
DEPLOY_ARGS=(
  "$FLAKE_DIR#$NODE"
  --confirm-timeout 120
)
```

Source: Existing `scripts/deploy.sh` structure.

### Example 5: nixos-anywhere Deployment Command

```bash
# Full command with all workarounds
SSHPASS="6f2d2gQSdW2P" nix run github:nix-community/nixos-anywhere -- \
  --env-password \
  --extra-files tmp/ovh-host-keys \
  --flake .#ovh \
  root@135.125.196.143

# If kexec hangs, add --kexec with older image:
SSHPASS="6f2d2gQSdW2P" nix run github:nix-community/nixos-anywhere -- \
  --env-password \
  --kexec "$(nix build --print-out-paths github:nix-community/nixos-images#packages.x86_64-linux.kexec-installer-nixos-22.11)/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz" \
  --extra-files tmp/ovh-host-keys \
  --flake .#ovh \
  root@135.125.196.143
```

Source: nixos-anywhere quickstart docs, OVH community reports.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single nixosConfigurations entry | Multiple entries with shared module list | Standard pattern | Enables multi-host from same repo |
| nixos-rebuild --target-host | deploy-rs with per-node targeting | Phase 25 (2026-02-21) | Magic rollback, atomic multi-node deploys |
| One secrets file for all hosts | Per-host secrets files in sops-nix | sops-nix best practice | Host compromise doesn't leak other host secrets |
| Manual Tailscale join | services.tailscale.authKeyFile | NixOS 23.05+ | Fully declarative, first-boot join |

**Deprecated/outdated:**
- `nixos-rebuild switch --target-host` for deployment: Replaced by deploy-rs in Phase 25. Still available as emergency fallback.
- Single `.sops.yaml` creation_rule: Multiple creation_rules needed for per-host secrets.

## Key Codebase Observations

### What's Already Host-Agnostic (shared modules -- NO changes needed)

All 13 modules in `modules/` are host-agnostic:
- `base.nix` -- system packages, nix settings, kernel sysctl
- `boot.nix` -- GRUB config (device comes from disko, but initrd rollback references `disk-main-root` partition label which is set by disko)
- `networking.nix` -- firewall rules, SSH, Tailscale, fail2ban (all use `config.services.*` references, no hardcoded IPs)
- `secrets.nix` -- sops declarations (uses `defaultSopsFile` which is set per-host, or can be overridden per-host)
- `docker.nix` -- Docker engine + NAT (NOTE: `externalInterface = "eth0"` is hardcoded -- needs parameterization if OVH uses different interface name)
- `monitoring.nix` -- Prometheus + node_exporter (localhost bindings)
- `home-assistant.nix`, `syncthing.nix` -- services with Tailscale-only access
- `homepage.nix` -- dashboard (NOTE: `tailscaleIP` is hardcoded as `100.127.245.9` -- needs parameterization per host)
- `agent-compute.nix` -- agent spawn, bubblewrap, podman
- `impermanence.nix` -- persist paths
- `restic.nix` -- B2 backup config
- `repos.nix` -- activation scripts for repo cloning

### What Needs Parameterization

1. **`modules/docker.nix`**: `externalInterface = "eth0"` -- must match host's primary interface. If OVH uses `ens3`, this breaks. **Solution:** Pass interface name from host config via a module option or `networking.nat.externalInterface` set in host config.
2. **`modules/homepage.nix`**: `tailscaleIP = "100.127.245.9"` -- hardcoded to current Contabo Tailscale IP. **Solution:** Each host gets its own Tailscale IP; either parameterize or make homepage host-specific.
3. **`modules/secrets.nix`**: `defaultSopsFile = ../secrets/neurosys.yaml` -- must point to host-specific secrets file. **Solution:** Move `sops.defaultSopsFile` to each `hosts/*/default.nix` and remove from `modules/secrets.nix`.
4. **`modules/boot.nix`**: References `disk-main-root` partition label, and `device = "/dev/sda"` -- partition label is set by disko (consistent), but GRUB device must match host disk. **Solution:** Move `boot.loader.grub.device` to host-specific disko-config or host default.nix.

### What Differs Per Host (host-specific config in `hosts/*/default.nix`)

| Setting | Contabo (staging) | OVH (production) |
|---------|-------------------|-------------------|
| `networking.hostName` | `"neurosys"` | `"neurosys-prod"` |
| Static IP / DHCP | Static: 161.97.74.121/18 | TBD (inspect Ubuntu first) |
| Default gateway | 161.97.64.1 | TBD |
| DNS servers | 213.136.95.10, 213.136.95.11 | TBD (OVH: 213.186.33.99) |
| Network interface | `eth0` | TBD (`eth0`, `ens3`, or other) |
| `networking.useNetworkd` | `mkForce false` | TBD (may work with networkd if DHCP) |
| Disk device | `/dev/sda` | TBD (likely `/dev/sda`) |
| Boot mode | Hybrid BIOS+UEFI | TBD (check `/sys/firmware/efi`) |
| sops.defaultSopsFile | `secrets/neurosys.yaml` | `secrets/ovh.yaml` |
| Tailscale IP | 100.127.245.9 | Assigned at join time |

## Service Migration Strategy

### Services That Run on Both Hosts

| Service | Notes |
|---------|-------|
| SSH, firewall, fail2ban | Identical config |
| Tailscale | Each gets own identity/IP |
| Prometheus + node_exporter | Local metrics per host |
| Restic backups | Both back up to same B2 bucket (separate snapshots) |
| Agent tooling (bubblewrap, podman) | Identical config |

### Services That Move to Production (OVH) Only

| Service | Migration Notes |
|---------|----------------|
| Docker containers (parts, claw-swap) | State in `/persist/var/lib/claw-swap` and `/persist/var/lib/parts` -- restore from restic backup or migrate via rsync |
| Home Assistant + ESPHome | State in `/persist/var/lib/hass` and `/persist/var/lib/private/esphome` |
| Syncthing | State in `/persist/home/dangirsh/.config/syncthing` and `/persist/home/dangirsh/Sync` |
| Homepage dashboard | Tailscale IP differs -- update `allowedHosts` |
| CASS indexer | Depends on agent sessions in `/data/projects/` |

### DNS Cutover

- `claw-swap.com` currently resolves to Contabo IP (161.97.74.121)
- Caddy on the claw-swap container handles TLS termination
- **Migration steps:**
  1. Lower DNS TTL to 60s (24+ hours before cutover)
  2. Verify claw-swap is running on OVH
  3. Update DNS A record to OVH IP (135.125.196.143)
  4. Wait for TTL propagation
  5. Verify `curl -sk https://claw-swap.com/`
  6. Restore DNS TTL to normal

## Open Questions

1. **OVH VPS disk device name**
   - What we know: OVH VPS typically uses `/dev/sda`, but may use `/dev/vda` in some configurations
   - What's unclear: The specific device name on this VPS (135.125.196.143)
   - Recommendation: SSH into stock Ubuntu with password and run `lsblk` before writing disko config
   - **Confidence:** LOW -- must be verified empirically

2. **OVH VPS network interface name and DHCP support**
   - What we know: Stock Ubuntu 25 likely uses netplan with DHCP. OVH may or may not provide DHCP after NixOS install.
   - What's unclear: Whether DHCP persists after OS change, or if static IP is required
   - Recommendation: SSH into Ubuntu and inspect `/etc/netplan/`, `ip addr show`, and `ip route`. Try DHCP first in NixOS config; have static config ready as fallback.
   - **Confidence:** LOW -- must be verified empirically

3. **OVH VPS boot mode (UEFI vs BIOS)**
   - What we know: Existing disko-config.nix has hybrid layout that handles both
   - What's unclear: Which mode this specific VPS uses
   - Recommendation: SSH into Ubuntu and check `ls /sys/firmware/efi`. Either way, the hybrid disko layout should work.
   - **Confidence:** MEDIUM -- hybrid layout covers both cases

4. **kexec compatibility on this specific OVH VPS**
   - What we know: Multiple community reports of kexec hanging on OVH. NixOS 22.11 image reported as working.
   - What's unclear: Whether this specific VPS is affected
   - Recommendation: Try default kexec first. If it hangs, fall back to `--kexec` with NixOS 22.11 image. Have OVH rescue mode as last resort.
   - **Confidence:** MEDIUM -- well-documented issue with known workaround

5. **Impermanence status for OVH**
   - What we know: Phase 21-01 wrote the config (disko BTRFS, impermanence module, initrd rollback). Phase 21-02 (deploy + verify) is pending.
   - What's unclear: Should OVH deploy with impermanence from day 1, or add it later?
   - Recommendation: Deploy OVH with the same config as current Contabo (which includes impermanence config but hasn't been deployed with it yet). If Contabo doesn't have impermanence active, don't activate it on OVH either. The disko config already creates BTRFS subvolumes for it.
   - **Confidence:** HIGH -- conservative approach, same config

6. **Homepage Tailscale IP parameterization**
   - What we know: `modules/homepage.nix` hardcodes `tailscaleIP = "100.127.245.9"` (Contabo's TS IP)
   - What's unclear: OVH's Tailscale IP won't be known until after Tailscale joins
   - Recommendation: Either (a) make homepage.nix host-specific, (b) use a module option, or (c) use `allowedHosts = "*"` since Tailscale already provides access control. Option (c) is simplest and safe given trustedInterfaces.
   - **Confidence:** HIGH -- minor config issue with clear solutions

7. **Which services run on staging vs production**
   - What we know: Phase description says Contabo becomes staging, OVH becomes production
   - What's unclear: Does staging run all services (including Docker containers)? Or is staging a minimal test target?
   - Recommendation: Production (OVH) runs everything. Staging (Contabo) runs the same NixOS config for rapid-iteration testing, but Docker containers and stateful services may be empty/non-critical. The user should decide during planning.
   - **Confidence:** N/A -- this is a policy decision, not a technical question

8. **Docker NAT externalInterface**
   - What we know: `modules/docker.nix` hardcodes `externalInterface = "eth0"` for container NAT
   - What's unclear: OVH interface name
   - Recommendation: Parameterize by setting `networking.nat.externalInterface` in host default.nix (NixOS merges module configs). Or use a module option.
   - **Confidence:** HIGH -- straightforward NixOS pattern

## Sources

### Primary (HIGH confidence)
- Existing codebase: `flake.nix`, `hosts/neurosys/default.nix`, `modules/*.nix`, `.sops.yaml`, `scripts/deploy.sh` -- direct source analysis
- Phase 25 summary (deploy-rs integration): `.planning/phases/25-deploy-safety-with-deploy-rs/25-01-SUMMARY.md`
- Phase 21-02 plan (impermanence deploy): `.planning/phases/21-impermanence-ephemeral-root/21-02-PLAN.md`
- [deploy-rs README](https://github.com/serokell/deploy-rs) -- multi-node targeting, `--targets`, profile ordering
- [sops-nix README](https://github.com/Mic92/sops-nix) -- multi-host keys, creation_rules, age key derivation
- [nixos-anywhere quickstart](https://nix-community.github.io/nixos-anywhere/quickstart.html) -- `--env-password`, `--extra-files`, `--generate-hardware-config`

### Secondary (MEDIUM confidence)
- [nixos-anywhere custom kexec howto](https://nix-community.github.io/nixos-anywhere/howtos/custom-kexec.html) -- `--kexec` flag syntax for older images
- [OVH NixOS install guide (raghavsood.com)](https://raghavsood.com/blog/2024/06/21/ovh-nixos-install/) -- OVH kexec issues, static IP requirement, `/dev/sda` constraint, BIOS boot mode
- [Install NixOS on OVH VPS (edouard.paris)](https://edouard.paris/notes/install-nixos-on-an-ovh-vps-with-nixos-anywhere/) -- nixos-anywhere on OVH, basic command syntax
- [NixOS multi-host flake pattern (discourse)](https://discourse.nixos.org/t/how-to-make-one-flake-nix-for-multiple-hosts/62056) -- mkHostConfig factory function pattern
- [Tailscale NixOS Wiki](https://wiki.nixos.org/wiki/Tailscale) -- authKeyFile, pre-auth key workflow
- [sops-nix secret management (michael.stapelberg.ch)](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/) -- multi-host workflow with --extra-files

### Tertiary (LOW confidence)
- [NixOS friendly hosters (wiki)](https://wiki.nixos.org/wiki/NixOS_friendly_hosters) -- minimal OVH-specific info
- [OVH VPS rescue mode docs](https://support.us.ovhcloud.com/hc/en-us/articles/360010553920-How-to-Recover-Your-VPS-in-Rescue-Mode) -- fallback if kexec fails

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already in use; just extending to second host
- Architecture (multi-host refactor): HIGH -- codebase analysis confirms minimal changes needed; clean module separation already exists
- Architecture (nixos-anywhere on OVH): MEDIUM -- kexec issues documented but not personally verified; workarounds exist
- Pitfalls (OVH-specific): LOW-MEDIUM -- disk device, interface name, DHCP must be verified empirically before deployment
- Pitfalls (NixOS patterns): HIGH -- sops-nix, deploy-rs, Tailscale patterns are well-established

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (30 days -- OVH infrastructure details may change with provider updates)
