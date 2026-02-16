# Phase 2 Plan 02 — Deployment Log

## Target
- **Test VPS**: 62.171.134.33 (Contabo, Ubuntu, password: yfp3eab0CYMedbmjz)
- **Purpose**: Test nixos-anywhere deployment before deploying to real production VPS

## What Happened

### Pre-deploy: Host Key Regeneration
The original Phase 1 SSH host key (`tmp/host-key/`) was lost (never committed, previous session).
Generated a new one:
- **Private key**: `tmp/host-key/ssh_host_ed25519_key` (exists locally, NOT in git)
- **Public key**: `tmp/host-key/ssh_host_ed25519_key.pub`
- **Derived age key**: `age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3`
- **Updated `.sops.yaml`**: replaced old `host_acfs` key with new one
- **Re-encrypted `secrets/acfs.yaml`**: `sops updatekeys` succeeded
- These changes are UNCOMMITTED on main (dirty tree)

### Pre-deploy: SSH Access Setup
- Added local SSH public key (`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqNVObi1HflLIV/FkO/rAz/ABdTvADidl5tuIulS3WE parts-agent@vm`) to root@62.171.134.33 authorized_keys
- Verified key auth worked before deployment

### Pre-deploy: VPS Verification
- VPS was running Ubuntu 6.8.0 on x86_64
- kexec enabled (`/proc/sys/kernel/kexec_load_disabled` = 0)
- Disk: `/dev/sda` 150G (QEMU HARDDISK)
- Boot mode: BIOS (no EFI vars directory)
- Confirmed disko-config.nix targets `/dev/sda` and boot.nix has hybrid GRUB

### Deploy Command
```bash
nix run github:nix-community/nixos-anywhere -- \
  --extra-files /tmp/tmp.kPAkHQymnC \
  --flake '.#acfs' \
  --target-host root@62.171.134.33
```

### Deploy Output (key excerpts)
1. **kexec into NixOS installer** — succeeded
2. **disko partitioning** — succeeded (GPT, EF02 boot, ESP, ext4 root)
3. **System closure copy** — succeeded (copied full NixOS system to VPS)
4. **Extra files (host key)** — copied successfully
5. **GRUB install** — succeeded for both i386-pc AND x86_64-efi
6. **sops-nix activation** — PARTIAL FAILURE:
   - `sops-install-secrets: Imported /etc/ssh/ssh_host_ed25519_key as age key with fingerprint age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3` (**correct key imported**)
   - `Cannot read ssh key '/etc/ssh/ssh_host_rsa_key': open /etc/ssh/ssh_host_rsa_key: no such file or directory` (harmless warning)
   - **`failed to decrypt '/nix/store/...-source/secrets/parts.yaml': Error getting data key: 0 successful groups required, got 0`** — the parts flake has its own sops secrets file that still references the OLD host age key
   - `Activation script snippet 'setupSecrets' failed (1)` — THIS MAY BE THE BOOT BLOCKER
7. **Reboot** — nixos-anywhere triggered reboot, then printed `### Done! ###`

### Post-Deploy State
- **Server unreachable**: 100% ping loss to 62.171.134.33
- Waited 3+ minutes, tried root and dangirsh SSH — connection timed out
- **nixos-anywhere exit code was 0** (it considers the install successful)

## Root Cause Hypotheses

### 1. sops-nix `secrets/parts.yaml` blocking boot (MOST LIKELY)
The parts flake's `.sops.yaml` still has the OLD host age key (`age1k55y5yphzwlzl6a0ndpz4jhg70xk9mpwlhltwdywjgwuvkzvrc8qa9yake`). The `setupSecrets` activation script failed, which may prevent NixOS from completing activation and starting services (including SSH).

**Fix**: Update the parts flake's `.sops.yaml` with the new host key, re-encrypt `secrets/parts.yaml`, rebuild, redeploy.

### 2. Network interface name mismatch
`networking.nat.externalInterface = "eth0"` in `modules/docker.nix` but Contabo might use `ens3` or similar. However, this should only affect Docker NAT, not basic SSH connectivity.

### 3. DHCP not working
Contabo VPS might need static IP config. The NixOS config uses dhcpcd which should handle DHCP, but some Contabo setups need manual network config.

### 4. Kernel/boot issue
Less likely since GRUB installed successfully for both BIOS and UEFI.

## What Needs to Happen Next

1. **Check Contabo VNC console** — see what's on screen (boot error? activation failure? login prompt with no network?)
2. **Fix parts.yaml encryption** — update parts flake `.sops.yaml` with new host_acfs key, re-encrypt
3. **Consider removing parts secrets from activation** temporarily to isolate the boot issue
4. **Redeploy** after fixing — can re-run same nixos-anywhere command (VPS is already in NixOS installer or rebooted NixOS)

## Uncommitted Changes on Main

```
M .sops.yaml                    # host_acfs key updated to new age key
M secrets/acfs.yaml             # re-encrypted with new key
? .planning/phases/09-*/        # Phase 9 planning dir (untracked)
```

## Key File Locations
- Host key private: `tmp/host-key/ssh_host_ed25519_key` (local only, NOT in git)
- Host key public: `tmp/host-key/ssh_host_ed25519_key.pub`
- New age key: `age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3`
- Old age key (orphaned): `age1k55y5yphzwlzl6a0ndpz4jhg70xk9mpwlhltwdywjgwuvkzvrc8qa9yake`
- Parts flake `.sops.yaml`: needs updating (still has old key)
- Test VPS: 62.171.134.33 / password: yfp3eab0CYMedbmjz
