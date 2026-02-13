# Pitfalls Research

**Domain:** NixOS Server Configuration (Ubuntu-to-NixOS VPS Migration)
**Researched:** 2026-02-13
**Confidence:** MEDIUM-HIGH (multiple sources corroborate most findings; some Contabo-specific claims are single-source)

---

## Critical Pitfalls

### Pitfall 1: Docker Bypasses NixOS Firewall, Exposing Ports to the Internet

**What goes wrong:**
Docker injects its own iptables rules that operate independently of the NixOS firewall module. When you define `virtualisation.oci-containers.containers.<name>.ports` or use `-p` in Docker, those ports become accessible on the external interface regardless of `networking.firewall.allowedTCPPorts`. You believe the firewall is protecting you, but Docker has punched holes through it. On a server migrating from NO firewall (the current state), this is doubly dangerous because the operator may assume "NixOS firewall is on, so I am protected" when Docker containers are actually wide open.

**Why it happens:**
Docker manages its own iptables DOCKER chain, which takes priority over the NixOS nftables/iptables INPUT chain. The NixOS firewall module does not account for Docker's FORWARD chain manipulation. This is a long-standing architectural conflict (NixOS/nixpkgs#111852, #40507).

**How to avoid:**
1. Set `virtualisation.docker.extraOptions = "--iptables=false";` to prevent Docker from managing its own firewall rules.
2. Bind container ports to `127.0.0.1` only: use `"127.0.0.1:8080:80"` instead of `"8080:80"` in port mappings.
3. Use a reverse proxy (Caddy/nginx) on the host to expose only the ports you intend.
4. For services only needed over Tailscale, bind to the Tailscale IP or `100.0.0.0/8` range.

**Warning signs:**
- Running `nmap` against the VPS external IP shows unexpected open ports
- `iptables -L -n` or `nft list ruleset` shows DOCKER chains with ACCEPT rules you did not configure
- Services are reachable from the internet that should only be internal

**Phase to address:**
Phase 1 (Base system + firewall). This must be verified before ANY Docker containers are deployed.

---

### Pitfall 2: sops-nix Age Key Bootstrap Chicken-and-Egg Problem

**What goes wrong:**
sops-nix decrypts secrets at activation time using the host's SSH ed25519 key (converted to an age key via ssh-to-age). But on a fresh nixos-anywhere deployment, the SSH host key does not exist yet until NixOS generates it on first boot. Your encrypted secrets reference an age public key derived from a host key that has not been created, so decryption fails on the very first activation. The system either fails to boot properly or boots with missing secrets (no Tailscale auth key, no database passwords, etc.).

**Why it happens:**
The age public key in `.sops.yaml` must be known at encryption time (when you run `sops` on your dev machine). But the host's SSH key is generated at install time. If you do not pre-generate or pre-deploy the host key, there is no way to encrypt secrets for a machine that does not yet exist.

**How to avoid:**
1. **Pre-generate the SSH host key locally** before deployment. Generate `ssh_host_ed25519_key` and `ssh_host_ed25519_key.pub` on your dev machine.
2. **Derive the age public key** from this pre-generated key using `ssh-to-age`.
3. **Add that age key to `.sops.yaml`** as a recipient for the new host.
4. **Deploy the pre-generated host key** using nixos-anywhere's `--extra-files` flag to place it at `/etc/ssh/ssh_host_ed25519_key` during installation.
5. **Also encrypt with your personal age key** (derived from your SSH user key) so you always have a fallback decryption path.

**Warning signs:**
- `sops-nix` activation errors during first `nixos-rebuild switch` mentioning "failed to decrypt"
- Services that depend on secrets (Tailscale, PostgreSQL) fail to start after deploy
- The `.sops.yaml` file references a host key age public key that was never actually deployed to the host

**Phase to address:**
Phase 0 (Pre-deployment preparation). The key generation and sops-nix configuration must happen BEFORE nixos-anywhere runs.

---

### Pitfall 3: Contabo BIOS-Only Boot Despite UEFI Availability

**What goes wrong:**
Contabo advertises UEFI support, but multiple users report that only BIOS/legacy boot actually works on their VPS instances. If you configure disko with a GPT + EFI System Partition expecting UEFI boot, the system may fail to boot after nixos-anywhere completes. You are left with an unbootable system accessible only through Contabo's VNC rescue console.

**Why it happens:**
Contabo's KVM virtualization layer may not fully pass through UEFI firmware to all VPS tiers. The behavior varies by VPS generation and plan. There is no clear documentation from Contabo about which plans support UEFI.

**How to avoid:**
1. **Use a hybrid BIOS+UEFI disko configuration** that works with both boot modes. Use GRUB (not systemd-boot) with `boot.loader.grub.device` set and a BIOS boot partition.
2. **Test the boot mode first** via VNC console before running nixos-anywhere: check if `/sys/firmware/efi` exists on the running rescue/base system.
3. **Include both a 1MB BIOS boot partition and an ESP** in your disko config for maximum compatibility.
4. **Use `boot.loader.grub.efiInstallAsRemovable = true;`** if attempting UEFI, as Contabo may not have proper NVRAM support.

**Warning signs:**
- GRUB installation succeeds but system does not boot (black screen on VNC)
- `efibootmgr` shows entries but firmware ignores them
- nixos-anywhere completes successfully but SSH never comes back up

**Phase to address:**
Phase 1 (Disk partitioning + base deployment). Must test boot mode BEFORE writing the final disko config.

---

### Pitfall 4: Missing VirtIO Kernel Modules Cause Boot Hang

**What goes wrong:**
After nixos-anywhere deploys the system, stage 1 of the boot process hangs because it cannot find the root filesystem. The initrd does not include the virtio kernel modules needed to access the virtual disk. The system is unbootable and requires rescue mode access.

**Why it happens:**
`nixos-generate-config` sometimes fails to detect virtio_scsi as a required module in virtual environments. If you are writing your NixOS config from scratch (not using hardware-configuration.nix from the target), you must manually specify these modules. This is NixOS/nixpkgs#76980.

**How to avoid:**
Always include these modules in your configuration:
```nix
boot.initrd.availableKernelModules = [
  "virtio_pci"
  "virtio_scsi"
  "virtio_blk"
  "virtio_net"
  "virtio_balloon"
  "virtio_ring"
];
```

If using nixos-anywhere, run `lsmod | grep virtio` on the target system before deployment to identify exactly which modules are loaded, and include all of them.

**Warning signs:**
- System does not come back online after nixos-anywhere deployment
- VNC console shows "waiting for device /dev/vda1" or similar stage-1 messages
- Rescue boot shows that the NixOS installation exists on disk but cannot be booted

**Phase to address:**
Phase 1 (Hardware configuration). Must be in the initial configuration before first boot.

---

### Pitfall 5: Firewall + Docker + Tailscale checkReversePath Three-Way Conflict

**What goes wrong:**
NixOS defaults to `networking.firewall.checkReversePath = "strict"`. Tailscale requires `"loose"` for exit nodes and subnet routing. Docker containers require `checkReversePath = false` for inter-container communication. These three requirements conflict. Setting it to `false` fixes Docker but weakens security. Setting it to `"loose"` fixes Tailscale but Docker containers still cannot talk to each other. Setting it to `"strict"` breaks both.

**Why it happens:**
Reverse path filtering (RPF) verifies that the source address of incoming packets could be reached via the interface they arrived on. Tailscale uses policy routing that confuses strict RPF. Docker uses bridge networking with NAT that looks like spoofed packets to RPF. Both tools route packets in ways NixOS's firewall does not expect.

**How to avoid:**
1. Set `networking.firewall.checkReversePath = "loose";` as the baseline.
2. Add `"docker0"` and `"tailscale0"` to `networking.firewall.trustedInterfaces`.
3. If Docker containers still cannot communicate, add explicit nftables forward rules instead of disabling RPF entirely.
4. Bind Docker containers to `127.0.0.1` and use Tailscale for cross-machine communication.
5. Enable `networking.nftables.enable = true;` for more predictable firewall behavior with Tailscale.
6. Set `TS_DEBUG_FIREWALL_MODE=nftables` for tailscaled.

**Warning signs:**
- Tailscale connects but cannot route traffic through exit nodes
- Docker compose services cannot resolve each other by name
- `journalctl -u firewall` shows RPF-related packet drops
- Docker containers can reach the internet but not each other

**Phase to address:**
Phase 2 (Networking layer: firewall + Tailscale + Docker). These must be configured and tested together because they interact.

---

### Pitfall 6: Locking Yourself Out of the VPS

**What goes wrong:**
After deploying NixOS via nixos-anywhere, you lose all access to the server. This can happen through multiple paths: (a) firewall blocks SSH but you did not realize; (b) SSH authorized_keys are not in the NixOS config; (c) root password was not set and key auth fails; (d) Tailscale was supposed to be the backup access path but it was not authenticated yet; (e) boot fails and the Contabo VNC console cannot help because there is no rescue user.

**Why it happens:**
NixOS is a clean-slate deployment. Unlike upgrading Ubuntu in-place, nixos-anywhere wipes the disk. Every access path must be explicitly declared in the NixOS configuration. There is no fallback `ubuntu` user with a password. If SSH keys are wrong or missing from the config, there is no way in.

**How to avoid:**
1. **Always include your SSH public keys** in `users.users.root.openssh.authorizedKeys.keys` AND in your personal user account.
2. **Set a root password** (hashed) as a fallback: `users.users.root.hashedPassword = "...";`
3. **Verify SSH config** includes `services.openssh.enable = true;` and `services.openssh.settings.PermitRootLogin = "prohibit-password";`
4. **NixOS auto-opens port 22** when openssh is enabled -- but verify this.
5. **Test the full config in a local VM** (using `nixos-rebuild build-vm`) before deploying to the VPS.
6. **Keep the Contabo VNC console open** during first deployment.
7. **Do not enable the firewall** on the very first deploy until you have confirmed SSH access works. Enable it in a follow-up `nixos-rebuild switch`.

**Warning signs:**
- You cannot SSH after nixos-anywhere completes
- Contabo VNC shows login prompt but you have no password
- `ssh -vvv` shows "Permission denied (publickey)"

**Phase to address:**
Phase 1 (Base system). SSH access must be the FIRST thing verified. Firewall should be a SECOND step.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Using `networking.firewall.enable = false` to fix Docker/Tailscale issues | Everything works immediately | No firewall protection on internet-facing VPS; every port is exposed | Never on a production server |
| Putting secrets in plain text in the Nix flake | No sops-nix setup needed | Secrets in world-readable `/nix/store` and in git history | Never |
| Not setting up garbage collection | Fewer config lines | Nix store grows unbounded; 484GB disk fills in months | Never -- always configure from day one |
| Using `nix-env -i` instead of declarative packages | Quick package install | Creates mutable state, breaks reproducibility, not tracked in config | Only for temporary debugging |
| Skipping the `flake.lock` commit | Avoids merge conflicts | Different machines get different nixpkgs versions; "works on my machine" | Never |
| Home-manager standalone instead of NixOS module | Faster iteration, no sudo needed | Two separate rebuild commands, can drift from system state, harder rollback | Only if multiple non-NixOS machines share the config |
| Not configuring `nix.settings.auto-optimise-store = true` | No config needed | Duplicate files waste disk; significant on a 484GB VPS | Never -- single-line fix |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Tailscale auth key | Hardcoding auth key in nix config (ends up in `/nix/store`) | Use `services.tailscale.authKeyFile` pointing to a sops-nix managed secret |
| Tailscale + NixOS firewall | Using strict reverse path filtering | Set `networking.firewall.checkReversePath = "loose"` and add `tailscale0` to trusted interfaces |
| Tailscale node key expiry | Using a regular auth key; node re-authenticates and becomes unreachable | Use a **tagged** auth key which automatically disables node key expiration |
| Docker port exposure | Using `"8080:80"` port mapping | Use `"127.0.0.1:8080:80"` to bind only to localhost; expose via reverse proxy |
| Docker + NixOS firewall | Trusting that NixOS firewall controls Docker ports | Set `--iptables=false` on Docker daemon; manage exposure explicitly |
| sops-nix + systemd DynamicUser | Setting `owner` on a sops secret for a DynamicUser service | Use systemd `LoadCredential` instead of direct file ownership |
| sops-nix + service restart | Changing a secret value but service keeps using old value | Configure `sops.secrets.<name>.restartUnits = [ "myservice.service" ]` |
| PostgreSQL Docker volume | Migrating volume data between hosts; UID/GID mismatch | Ensure postgres UID inside container matches host volume ownership; use `pg_dump`/`pg_restore` instead of raw file copy |
| SSH authorized_keys | Putting keys only in `~/.ssh/authorized_keys` (mutable state) | Use `users.users.<name>.openssh.authorizedKeys.keys` in NixOS config for declarative management |
| disko + nixos-anywhere | Device path in disko config does not match target VPS | Run `lsblk` on target via SSH before deployment to verify device names (e.g., `/dev/sda` vs `/dev/vda`) |
| Home-manager overwriting manual config | Home-manager silently overwrites dconf/dotfile changes | Never manually edit files that home-manager manages; always change via nix config |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Nix store bloat without garbage collection | Disk usage climbs steadily; `df -h` shows `/nix/store` consuming >50% of disk | Set `nix.gc.automatic = true; nix.gc.options = "--delete-older-than 14d";` | Months after deployment; rebuild fails with "No space left on device" |
| Keeping all NixOS generations | Each generation is ~500MB-1GB; 50 generations = 25-50GB | Set `boot.loader.grub.configurationLimit = 10;` or `boot.loader.systemd-boot.configurationLimit = 10;` | After ~30 rebuilds |
| nixpkgs source copy in flake closure | ~170MB of nixpkgs source in `/nix/store` per evaluation | Use `nix.registry.nixpkgs.flake = inputs.nixpkgs;` to deduplicate; consider `nix.channel.enable = false;` | Immediate; adds bloat from first deploy |
| Docker images + Nix store competing for disk | Both grow independently on a shared filesystem | Put Docker data-root on a separate partition or set pruning policy; set `nix.settings.min-free` and `nix.settings.max-free` | When total exceeds 400GB on 484GB disk |
| Full system rebuild downloads entire nixpkgs | Slow rebuilds on VPS with limited bandwidth | Use a binary cache; ensure `cache.nixos.org` is in substituters; do not set `--option substitute false` | Every rebuild |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Secrets in flake files (plain text) | All flake contents are copied to world-readable `/nix/store`; anyone with shell access can read them | Use sops-nix with age encryption; secrets are decrypted to `/run/secrets` at activation time with proper permissions |
| Root login with password over SSH | Brute-force attacks on internet-facing SSH | Set `services.openssh.settings.PermitRootLogin = "prohibit-password"` and use key-only auth |
| No fail2ban or rate limiting on SSH | Brute-force consumes resources and may eventually succeed | Enable `services.fail2ban.enable = true;` or restrict SSH to Tailscale only |
| Docker group membership without rootless mode | Docker group = root equivalent; any user in the group has full system access | Use rootless Docker (`virtualisation.docker.rootless.enable = true`) or limit docker group membership |
| Not using `hashedPassword` (using `password` instead) | Plain-text password in `/nix/store` | Always use `hashedPassword` or `hashedPasswordFile` with sops-nix |
| sops-nix age key not backed up | If VPS disk dies, all secrets are unrecoverable | Encrypt secrets with BOTH host key AND personal key; store personal age key securely offline |
| No firewall (current state of Ubuntu server) | All ports exposed to internet | Enable `networking.firewall.enable = true;` from the start; SSH port 22 is auto-allowed when openssh is enabled |

## "Looks Done But Isn't" Checklist

- [ ] **Firewall:** Enabled in NixOS config, but Docker is bypassing it -- verify with `nmap` from an external host, not just `iptables -L` locally
- [ ] **sops-nix secrets:** Decrypted at activation, but services not restarted -- verify services actually loaded the new secret values
- [ ] **Tailscale connected:** Node appears in admin console, but exit node routing broken because `checkReversePath` is strict -- test actual traffic flow
- [ ] **SSH access:** Can SSH as root, but personal user account has no authorized_keys -- verify ALL user accounts you need
- [ ] **Garbage collection:** Configured with `nix.gc.automatic = true`, but timer never fires because interval syntax is wrong -- verify with `systemctl list-timers | grep gc`
- [ ] **Disko partitions:** Created successfully, but boot partition is wrong mode (UEFI when Contabo needs BIOS) -- verify system actually boots, not just that install succeeds
- [ ] **Docker networking:** Containers start, but cannot talk to each other because of firewall RPF -- verify inter-container communication, not just container startup
- [ ] **Nix store optimisation:** Set `auto-optimise-store = true`, but old generations still pinned -- verify `nix-collect-garbage --dry-run` shows reasonable cleanup
- [ ] **PostgreSQL migration:** Docker container starts, but data directory has wrong permissions/ownership -- verify the database is actually queryable, not just that the container runs
- [ ] **Home-manager:** Packages installed, but dotfiles not symlinked because `home.stateVersion` mismatch -- verify actual file contents, not just build success
- [ ] **Activation scripts for repo cloning:** Script defined, but runs before network is ready -- verify with `systemctl status` after reboot, not just after manual switch

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Locked out of VPS (no SSH, no password) | MEDIUM | Use Contabo VNC console + rescue mode to mount filesystem and fix `/etc/nixos/configuration.nix`; alternatively, re-run nixos-anywhere with corrected config |
| Unbootable system (wrong boot mode) | MEDIUM | Boot Contabo rescue system; mount NixOS partitions; chroot and fix GRUB config; or re-run nixos-anywhere with corrected disko config |
| Unbootable system (missing virtio modules) | MEDIUM | Same as above; add virtio modules to config in chroot; run `nixos-rebuild switch --install-bootloader` |
| sops-nix decryption failure on first boot | LOW | SSH into system (if SSH works without secrets); manually place the correct age key; run `nixos-rebuild switch` |
| Docker exposed ports to internet | HIGH (if exploited) | Immediately set `--iptables=false`; audit for compromise; rotate any exposed credentials |
| Nix store fills disk | MEDIUM | Boot rescue; run `nix-collect-garbage -d`; set up automatic GC; if truly full, delete old generations manually from `/nix/var/nix/profiles/` |
| Tailscale auth key expired | LOW | Generate new auth key from Tailscale admin console; manually run `tailscale up --auth-key=NEW_KEY` on the server |
| PostgreSQL data corruption during migration | HIGH | Restore from pg_dump backup (which is why you must take a dump, not just copy files) |
| Firewall checkReversePath breaks networking | LOW | Set `networking.firewall.checkReversePath = "loose"` and `nixos-rebuild switch` |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| sops-nix bootstrap chicken-and-egg | Phase 0: Pre-deployment prep | `sops -d secrets.yaml` works locally with the host's age key |
| Contabo BIOS-only boot | Phase 1: Disk + base system | System boots after nixos-anywhere; SSH is reachable |
| Missing virtio kernel modules | Phase 1: Hardware config | System boots; `lsmod | grep virtio` shows modules loaded |
| SSH lockout | Phase 1: Base system | Can SSH as both root and personal user after deploy |
| Docker firewall bypass | Phase 2: Docker setup | `nmap` from external host shows only intended ports open |
| Tailscale + firewall RPF conflict | Phase 2: Tailscale setup | Tailscale traffic flows correctly; exit nodes work if needed |
| Docker inter-container networking | Phase 2: Docker compose | Docker compose services can resolve and reach each other |
| Nix store bloat | Phase 1: Base system | `systemctl list-timers` shows GC timer; `nix-store --gc --print-dead | wc -l` is reasonable |
| Secrets in plain text | Phase 0: sops-nix setup | `grep` through `/nix/store` finds no plain-text secrets |
| PostgreSQL migration data loss | Phase 3: Service migration | `pg_dump` taken from old server; restored and verified on new server |
| Activation scripts need network | Phase 3: Service deployment | Use systemd services with `after = [ "network-online.target" ]` instead of activation scripts; verify after reboot |
| Node key expiration (Tailscale) | Phase 2: Tailscale setup | Auth key is tagged; `tailscale status` shows key expiry disabled |
| Home-manager state conflicts | Phase 3: User environment | `home-manager switch` succeeds; dotfiles are correct |

## Moderate Pitfalls

### Pitfall 7: Activation Scripts Run Before Network Is Ready

**What goes wrong:**
If you use NixOS activation scripts (e.g., `system.activationScripts`) to clone git repos or fetch remote resources, they execute during system activation which happens before `network-online.target` is reached. The scripts fail silently or with connection errors.

**How to avoid:**
Do not use activation scripts for anything that requires network access. Instead, create a oneshot systemd service with:
```nix
systemd.services.clone-repos = {
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig.Type = "oneshot";
  script = ''
    # clone repos here
  '';
};
```

**Warning signs:**
- Git clone failures in `journalctl` after reboot
- Resources expected to exist at boot time are missing
- Services that depend on cloned repos fail

**Phase to address:**
Phase 3 (Service deployment).

---

### Pitfall 8: Home-Manager as NixOS Module Requires Root for User Config Changes

**What goes wrong:**
When using home-manager as a NixOS module, every change to user-level configuration (shell aliases, git config, vim plugins) requires running `sudo nixos-rebuild switch`. This rebuilds the entire system, creates a new system generation, and requires root privileges. For a single-user server, this is acceptable. But it is surprising if you expected home-manager to work independently.

**How to avoid:**
For a single-user server, use home-manager as a NixOS module. The benefits outweigh the cost:
- Single `nixos-rebuild switch` updates everything
- System and user config are always in sync
- Rollback covers both system and user state
- No separate `home-manager switch` to remember

Accept the trade-off that user config changes need `sudo`.

**Warning signs:**
- Running `home-manager switch` on a system where HM is a NixOS module causes conflicts
- System has two sets of generations (NixOS + home-manager) that can diverge

**Phase to address:**
Phase 1 (Base system architecture decision). Decide module vs. standalone before writing any home-manager config.

---

### Pitfall 9: flake.lock Drift Between Development and Production

**What goes wrong:**
You run `nix flake update` on your dev machine, which updates the lock file to the latest nixpkgs. You push the config and rebuild the server. The new nixpkgs pulls in updated packages that may have breaking changes, new dependencies, or different default configurations. Your server config that worked yesterday now fails to build or behaves differently.

**How to avoid:**
1. **Never run `nix flake update` before a production deploy.** Update and test separately.
2. **Pin nixpkgs to a specific release branch** (e.g., `nixos-24.11`) not `nixpkgs-unstable`.
3. **Always commit `flake.lock`** to version control.
4. **Use `nix flake lock --update-input nixpkgs`** to update only nixpkgs, not all inputs at once.
5. **Test in a VM** after any lock file update before deploying to production.

**Warning signs:**
- `nixos-rebuild switch` fails after a `nix flake update` that was not intentional
- Different behavior between local testing and server deployment
- Build errors referencing removed or renamed nixpkgs options

**Phase to address:**
Phase 0 (Flake structure). Establish update discipline from the start.

---

### Pitfall 10: PostgreSQL UID/GID Mismatch During Docker Volume Migration

**What goes wrong:**
You copy PostgreSQL data files from the old Ubuntu server's Docker volume to the new NixOS server. The postgres user inside the Docker container has UID 999, but on NixOS the host filesystem may assign different UIDs/GIDs. PostgreSQL refuses to start with "data directory has invalid permissions" or "config owner and data owner do not match."

**How to avoid:**
1. **Do not copy raw PostgreSQL data directories.** Use `pg_dump` on the source and `pg_restore` on the target.
2. If you must copy files, ensure the UID inside the container matches the volume ownership on the host.
3. Use Docker named volumes instead of bind mounts -- Docker manages permissions internally.
4. Test the restore on a local Docker instance before deploying to production.

**Warning signs:**
- PostgreSQL container starts but immediately exits
- Container logs show permission denied errors
- `ls -la` on the mounted volume shows unexpected ownership

**Phase to address:**
Phase 3 (Data migration).

---

### Pitfall 11: Docker Network Subnet Conflicts

**What goes wrong:**
Docker's default bridge network uses `172.17.0.0/16`. If your VPS provider, VPN, or Tailscale uses overlapping subnets, containers lose connectivity or route traffic to the wrong destination. Contabo's internal networking or Tailscale's CGNAT range (`100.64.0.0/10`) typically does not conflict, but Docker's secondary networks (created by docker-compose) use `172.18.0.0/16`, `172.19.0.0/16`, etc., which can conflict with provider infrastructure.

**How to avoid:**
Configure Docker's address pools explicitly:
```nix
virtualisation.docker.daemon.settings = {
  default-address-pools = [
    { base = "10.10.0.0/16"; size = 24; }
  ];
};
```

**Warning signs:**
- Containers can reach the internet but not specific internal services
- DNS resolution works but connections time out
- Problems appear only on the VPS, not in local testing

**Phase to address:**
Phase 2 (Docker setup).

## Minor Pitfalls

### Pitfall 12: NixOS Hostname RFC 1035 Compliance

**What goes wrong:**
Contabo sets the default hostname to something like `vmi123456.contaboserver.net`. NixOS requires RFC 1035 compliant hostnames (no dots, limited characters). If you do not set a hostname in your NixOS config, the system may inherit the provider's hostname and fail to build.

**How to avoid:**
Always explicitly set `networking.hostName = "your-hostname";` in your NixOS config. Keep it short, lowercase, alphanumeric with hyphens only.

**Phase to address:** Phase 1 (Base system config).

---

### Pitfall 13: `NetworkManager-wait-online` Causes Slow/Failed Rebuilds

**What goes wrong:**
The `NetworkManager-wait-online.service` can timeout and cause `nixos-rebuild switch` to hang or fail. On a server, you likely do not need NetworkManager at all.

**How to avoid:**
Do not enable NetworkManager on a server. Use `systemd-networkd` or basic `networking` options instead. If you must use NetworkManager:
```nix
systemd.services.NetworkManager-wait-online.enable = false;
```

**Phase to address:** Phase 1 (Networking).

---

### Pitfall 14: Nix Flake Secrets Leak to /nix/store

**What goes wrong:**
Any file referenced in a flake (including by import) gets copied to the world-readable `/nix/store`. If you accidentally include a secrets file, API key, or password in your flake directory, it becomes readable by any user on the system and persists across garbage collections until the referencing generation is deleted.

**How to avoid:**
1. Add secrets files to `.gitignore` (flakes only include git-tracked files by default).
2. Never `import` or reference secret files from Nix expressions.
3. Use sops-nix, which keeps encrypted files in the flake and decrypts to `/run/secrets` at activation.
4. Audit with: `nix path-info -rsh /run/current-system | sort -hk2 | tail -20` to check for unexpected large or sensitive files.

**Phase to address:** Phase 0 (Flake structure).

---

### Pitfall 15: systemd-boot vs GRUB Choice Impacts Recovery Options

**What goes wrong:**
systemd-boot is simpler but only works with UEFI. On a Contabo VPS that may need BIOS boot, choosing systemd-boot means the system will not boot. Even if UEFI works initially, having GRUB provides better recovery options (can edit boot parameters, select older generations).

**How to avoid:**
Use GRUB for VPS deployments. It supports both BIOS and UEFI, has an interactive menu accessible via VNC, and allows editing kernel parameters at boot time for recovery.

**Phase to address:** Phase 1 (Boot configuration).

---

## Sources

- [NixOS is a good server OS, except when it isn't](https://sidhion.com/blog/nixos_server_issues/) - Server-specific bloat and design issues (MEDIUM confidence)
- [Secret Management on NixOS with sops-nix (2025)](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/) - sops-nix bootstrap and configuration (HIGH confidence)
- [nixos-anywhere secrets documentation](https://nix-community.github.io/nixos-anywhere/howtos/secrets.html) - Host key deployment during install (HIGH confidence)
- [Install NixOS on a Contabo VPS - Felix Buehler](https://www.stunkymonkey.de/blog/contabo-nixos/) - Contabo BIOS-only boot, virtio modules (MEDIUM confidence, single source for BIOS claim)
- [Docker bypasses NixOS firewall - NixOS/nixpkgs#111852](https://github.com/NixOS/nixpkgs/issues/111852) - Docker iptables bypass (HIGH confidence)
- [Docker container networking fails - NixOS/nixpkgs#298165](https://github.com/NixOS/nixpkgs/issues/298165) - checkReversePath and Docker (HIGH confidence)
- [Tailscale - Official NixOS Wiki](https://wiki.nixos.org/wiki/Tailscale) - Tailscale firewall configuration (HIGH confidence)
- [Docker - Official NixOS Wiki](https://wiki.nixos.org/wiki/Docker) - Docker NixOS configuration (HIGH confidence)
- [Firewall - NixOS Wiki](https://nixos.wiki/wiki/Firewall) - NixOS firewall basics (HIGH confidence)
- [Storage optimization - Official NixOS Wiki](https://wiki.nixos.org/wiki/Storage_optimization) - Garbage collection and store optimization (HIGH confidence)
- [VirtIO SCSI kernel module not detected - NixOS/nixpkgs#76980](https://github.com/NixOS/nixpkgs/issues/76980) - virtio module detection failure (HIGH confidence)
- [trustedInterfaces not working with filterForward - NixOS/nixpkgs#437920](https://github.com/nixos/nixpkgs/issues/437920) - Firewall + Docker + RPF interaction (MEDIUM confidence)
- [sops-nix GitHub](https://github.com/Mic92/sops-nix) - Official sops-nix documentation (HIGH confidence)
- [Home Manager - NixOS Wiki](https://nixos.wiki/wiki/Home_Manager) - Module vs standalone comparison (MEDIUM confidence)
- [NixOS & Flakes Book](https://nixos-and-flakes.thiscute.world/) - Flakes best practices (MEDIUM confidence)
- [SSH public key authentication - Official NixOS Wiki](https://wiki.nixos.org/wiki/SSH_public_key_authentication) - SSH key management (HIGH confidence)
- [Disko - NixOS Wiki](https://nixos.wiki/wiki/Disko) - Disk partitioning configuration (MEDIUM confidence)
- [Bootstrap fresh install using agenix - NixOS Discourse](https://discourse.nixos.org/t/bootstrap-fresh-install-using-agenix-for-secrets-management/17240) - Bootstrap chicken-and-egg problem (MEDIUM confidence)

---
*Pitfalls research for: NixOS Server Configuration (Ubuntu-to-NixOS VPS Migration)*
*Researched: 2026-02-13*
