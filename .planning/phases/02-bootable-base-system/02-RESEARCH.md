# Phase 2: Bootable Base System - Research

**Researched:** 2026-02-15
**Domain:** nixos-anywhere deployment, SSH key-only auth, nftables firewall, NixOS user/system config, Nix GC + store optimization
**Confidence:** HIGH

## Summary

Phase 2 takes the flake scaffolding from Phase 1 (already built) and deploys it to the Contabo VPS using nixos-anywhere, then hardens the configuration for production SSH access and firewalling. The work divides cleanly into two concerns: (1) the deployment itself -- running nixos-anywhere with `--extra-files` to inject the pre-generated SSH host key so sops-nix can decrypt secrets on first boot, and (2) filling in the module configs that Phase 1 left minimal -- specifically upgrading networking.nix for nftables + stricter SSH, upgrading users.nix for docker group membership, and verifying base.nix already satisfies the GC/optimization requirements.

The most significant risk in this phase is the **nixos-anywhere deployment to Contabo**. The kexec-based approach requires root SSH access to the existing Ubuntu system, repartitions the disk via disko, and installs NixOS. If the boot config or VirtIO modules are wrong, the server becomes unreachable. The hybrid BIOS+UEFI GRUB config from Phase 1 hedges the boot mode uncertainty. A VNC fallback via the Contabo control panel is the last resort if SSH is lost.

A critical boundary: the existing `flake.nix` is being modified by Phase 3.1 (in a separate worktree) to add the `parts` flake input. Phase 2 must NOT restructure `flake.nix` inputs -- all work happens in module files (`modules/*.nix`, `hosts/acfs/*.nix`). This avoids merge conflicts.

**Primary recommendation:** Split into two plans: (1) module config hardening (SSH, firewall, users, system verification -- can be tested locally with `nix flake check`) and (2) nixos-anywhere deployment (the actual deployment command, post-deploy verification, recovery procedures). Plan 1 is autonomous; Plan 2 requires human interaction (server access, VNC fallback).

## Standard Stack

### Core

| Component | Version/Source | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| nixos-anywhere | `github:nix-community/nixos-anywhere` (run via `nix run`) | Remote NixOS installation over SSH | De facto tool for kexec+disko deployment. Maintained by Mic92/Lassulus. |
| NixOS firewall + nftables | Built-in (`networking.firewall` + `networking.nftables`) | Default-deny firewall with nftables backend | NixOS native module. `networking.nftables.enable = true` switches the firewall backend from iptables to nftables. |
| openssh | Built-in (`services.openssh`) | SSH server with key-only auth | NixOS native module. Declarative SSH hardening. |
| disko | `github:nix-community/disko` (already in flake.nix) | Disk partitioning during deployment | Already wired in Phase 1. nixos-anywhere uses it automatically. |
| sops-nix | `github:Mic92/sops-nix` (already in flake.nix) | Secrets decryption at activation | Already wired in Phase 1. Decrypts via age key from SSH host key. |

### Supporting (CLI tools needed during deployment)

| Tool | Purpose | When Used |
|------|---------|-----------|
| `nix run github:nix-community/nixos-anywhere` | Execute nixos-anywhere from local machine | During initial VPS deployment |
| `ssh-keygen -R <ip>` | Remove stale known_hosts entry after VPS wipe | After nixos-anywhere completes |
| `nmap` or `nc` | External port scan to verify firewall | Post-deployment verification |
| `nixos-rebuild switch --flake .#acfs --target-host` | Subsequent configuration updates | All updates after initial deploy |

### Alternatives Considered

| Instead of | Could Use | Why Not |
|------------|-----------|---------|
| nixos-anywhere | nixos-infect | nixos-infect does in-place conversion (fragile), no disko integration, no declarative disk layout |
| `networking.firewall` + `nftables.enable` | nixos-nftables-firewall (third-party) | Standard NixOS module is sufficient for our needs. Third-party adds complexity. |
| `networking.firewall` + `nftables.enable` | Raw `networking.nftables.tables` | Over-engineering. The high-level `allowedTCPPorts` API is exactly what we need. Custom nftables rules only needed for per-interface or complex chain logic (Phase 3 territory). |
| PermitRootLogin "no" | PermitRootLogin "prohibit-password" | Phase 2 should tighten to "no" per NET-01. Root SSH is not needed after deployment -- `dangirsh` has sudo via wheel group. |

## Architecture Patterns

### Existing Project Structure (Phase 2 modifies, does not create)

Phase 2 modifies existing files from Phase 1. No new files are created.

```
.
├── flake.nix                    [DO NOT MODIFY - Phase 3.1 conflict zone]
├── flake.lock                   [DO NOT MODIFY - Phase 3.1 conflict zone]
├── .sops.yaml                   [Phase 1 - no changes]
│
├── hosts/acfs/
│   ├── default.nix              [Phase 1 - already has hostname/tz/locale]
│   ├── hardware.nix             [Phase 1 - already has VirtIO modules]
│   └── disko-config.nix         [Phase 1 - already has hybrid BIOS+UEFI]
│
├── modules/
│   ├── default.nix              [Phase 1 - no changes]
│   ├── base.nix                 [Phase 1 - VERIFY GC/optimization settings]
│   ├── boot.nix                 [Phase 1 - no changes]
│   ├── users.nix                [MODIFY - add docker group]
│   ├── networking.nix           [MODIFY - nftables, SSH hardening]
│   └── secrets.nix              [Phase 1 - no changes]
│
├── home/
│   └── default.nix              [Phase 1 - no changes]
│
├── secrets/
│   └── acfs.yaml                [Phase 1 - already encrypted]
│
└── tmp/
    └── host-key/                [Phase 1 - pre-generated SSH host key]
        ├── ssh_host_ed25519_key
        └── ssh_host_ed25519_key.pub
```

### Pattern 1: nftables Backend with Standard Firewall API

**What:** Enable nftables as the backend while using the standard `networking.firewall` declarative API. This gives modern nftables ruleset generation without writing raw nftables rules.
**When to use:** Always on NixOS 25.11 for new deployments. nftables is the successor to iptables.
**Why:** Setting `networking.nftables.enable = true` causes NixOS to generate a `nixos-fw` nftables table with proper chains. The `networking.firewall.allowedTCPPorts` and related options still work -- they just generate nftables rules instead of iptables rules.

```nix
# modules/networking.nix
{ config, lib, pkgs, ... }: {
  # Use nftables backend (not iptables)
  networking.nftables.enable = true;

  # Firewall: default-deny with explicit port allowlist
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22     # SSH
      80     # HTTP
      443    # HTTPS
      22000  # Syncthing
    ];
    # No allowedUDPPorts needed for Phase 2 scope
  };

  # SSH server: key-only authentication
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
```

**Source:** [NixOS Official Wiki: Firewall](https://wiki.nixos.org/wiki/Firewall), [NixOS Wiki: Firewall](https://nixos.wiki/wiki/Firewall)

**Key detail:** `networking.nftables.enable = true` and `networking.firewall.enable = true` work together. The firewall module detects nftables and generates nftables rules instead of iptables rules. They are NOT mutually exclusive.

### Pattern 2: SSH Key-Only Authentication (NET-01)

**What:** Disable all password-based SSH authentication and disable root login entirely.
**When to use:** Always on production servers after initial deployment.

```nix
services.openssh = {
  enable = true;
  settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };
};
```

**Source:** [NixOS Official Wiki: SSH](https://wiki.nixos.org/wiki/SSH)

**Critical detail:** The current Phase 1 config has `PermitRootLogin = "prohibit-password"` which still allows root login via SSH key. NET-01 requires root login to be *rejected*. Phase 2 must change this to `"no"`.

**Critical detail 2:** `KbdInteractiveAuthentication = false` must be added. Without it, keyboard-interactive auth (PAM-based) could still be attempted. Phase 1 did not set this.

**Post-deployment implication:** With `PermitRootLogin = "no"`, remote `nixos-rebuild` must use `--target-host dangirsh@<ip> --use-remote-sudo`. This works because `dangirsh` is in the `wheel` group. Phase 2.1 will add `security.sudo.wheelNeedsPassword = false` to make this seamless.

### Pattern 3: nixos-anywhere Deployment with --extra-files

**What:** Deploy NixOS to the Contabo VPS using nixos-anywhere, injecting the pre-generated SSH host key so sops-nix can decrypt secrets on first boot.
**When to use:** One-time initial deployment.

```bash
#!/usr/bin/env bash
# Deploy NixOS to Contabo VPS

temp=$(mktemp -d)
cleanup() { rm -rf "$temp"; }
trap cleanup EXIT

# Stage the pre-generated SSH host key for --extra-files
install -d -m755 "$temp/etc/ssh"
cp tmp/host-key/ssh_host_ed25519_key "$temp/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$temp/etc/ssh/ssh_host_ed25519_key"

# Deploy
nix run github:nix-community/nixos-anywhere -- \
  --extra-files "$temp" \
  --flake '.#acfs' \
  --target-host root@<CONTABO_IP>
```

**Source:** [nixos-anywhere secrets howto](https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/secrets.md), [nixos-anywhere quickstart](https://nix-community.github.io/nixos-anywhere/quickstart.html)

**How `--extra-files` works:**
1. nixos-anywhere creates a temp NixOS installer via kexec
2. disko partitions the disk per `disko-config.nix`
3. NixOS is installed to the new partitions
4. The contents of `--extra-files <path>` are tar'd and extracted to `/` on the new system
5. A file at `$temp/etc/ssh/ssh_host_ed25519_key` ends up at `/etc/ssh/ssh_host_ed25519_key` on the target

**Directory structure requirements:**
```
$temp/
└── etc/
    └── ssh/
        └── ssh_host_ed25519_key    # permissions: 600
```

The directory `/etc/ssh` must exist with mode 755. The private key must be mode 600. The public key is NOT needed in `--extra-files` -- NixOS regenerates it from the private key.

### Pattern 4: User with Docker Group Membership (SYS-01)

**What:** Create the `dangirsh` user with wheel (sudo) and docker group membership.
**When to use:** From Phase 2 onward. Docker engine is Phase 3, but the group must exist when the user is created to avoid activation ordering issues later.

```nix
# modules/users.nix
{ config, pkgs, ... }: {
  users.users.dangirsh = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
    ];
  };

  # Remove root SSH access entirely (was fallback for initial deployment)
  # After Phase 2 deploy, dangirsh + sudo is sufficient
};
```

**Source:** [NixOS Official Wiki: Docker](https://wiki.nixos.org/wiki/Docker), [NixOS Official Wiki: User Management](https://wiki.nixos.org/wiki/User_management)

**Note on docker group:** Adding `"docker"` to `extraGroups` before `virtualisation.docker.enable = true` (Phase 3) is safe -- NixOS will create the group when Docker is enabled. The user declaration just records the intent. If the `docker` group doesn't exist yet, it will be created implicitly when Docker is enabled in Phase 3.

**IMPORTANT UPDATE:** Actually, the `docker` group may NOT exist until `virtualisation.docker.enable = true` is set. Adding a user to a non-existent group could cause a warning or be silently ignored. The safer approach is to add `"docker"` to `extraGroups` in Phase 3 when Docker is actually enabled. For Phase 2, keep only `"wheel"`. This matches the principle of not configuring things before their dependencies exist.

**Decision: Add `"docker"` to extraGroups now.** Even though Docker is Phase 3, NixOS handles this gracefully -- the group reference in `extraGroups` does not fail if the group doesn't exist yet. It will simply be a no-op until Docker creates the group. The SYS-01 requirement explicitly lists docker group membership, and having it in the user config from the start is cleaner than modifying users.nix again in Phase 3.

### Pattern 5: Post-Deployment Remote Updates

**What:** After initial nixos-anywhere deployment, all subsequent config changes are pushed via `nixos-rebuild`.
**When to use:** Every time after the initial deployment.

```bash
# From local machine, targeting the VPS
nixos-rebuild switch \
  --flake .#acfs \
  --target-host dangirsh@<CONTABO_IP> \
  --use-remote-sudo
```

**Source:** [NixOS Official Wiki: nixos-rebuild](https://wiki.nixos.org/wiki/Nixos-rebuild), [NixOS & Flakes Book: Remote Deployment](https://nixos-and-flakes.thiscute.world/best-practices/remote-deployment)

**Requires:**
- `dangirsh` in `wheel` group (for sudo)
- `security.sudo.wheelNeedsPassword = false` (Phase 2.1, but can work with password prompt until then)
- SSH key-based auth working for `dangirsh`

### Anti-Patterns to Avoid

- **Modifying flake.nix inputs in Phase 2:** Phase 3.1 is actively modifying flake.nix in a separate worktree. Touching inputs in Phase 2 will create merge conflicts. All Phase 2 changes are in module files.
- **Using PermitRootLogin "prohibit-password" for production:** This still allows root SSH via key. Use `"no"` per NET-01.
- **Keeping root authorized_keys after deployment:** The root SSH key in users.nix was a Phase 1 fallback. After confirming dangirsh+sudo works, remove root's authorizedKeys. However, this must be done carefully -- remove it only AFTER verifying dangirsh SSH access works.
- **Writing raw nftables rules when the firewall API suffices:** The standard `allowedTCPPorts` API generates correct nftables rules. Custom `networking.nftables.tables` is for complex scenarios (per-interface rules, Docker iptables conflicts) which are Phase 3 territory.
- **Deploying without verifying `nix flake check` first:** Always run `nix flake check` locally before deploying. A broken config means an unreachable server.
- **Forgetting to clear known_hosts:** After nixos-anywhere wipes the VPS, the SSH host key changes. `ssh-keygen -R <ip>` must be run before reconnecting.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Firewall rules | Raw nftables rules in `networking.nftables.tables` | `networking.firewall.allowedTCPPorts` + `networking.nftables.enable` | The high-level API generates correct default-deny nftables rules. Custom rules are error-prone and can flush existing chains. |
| SSH host key deployment | Manual scp of key files | `nixos-anywhere --extra-files` | nixos-anywhere handles the tar/copy to /mnt during install. Manual copy risks wrong permissions or timing. |
| Remote NixOS deployment | Manual nixos-install via SSH | `nixos-anywhere` | Handles kexec, disko, install, and reboot in one command. Manual process has many failure modes. |
| Subsequent deployments | SSH in and edit files | `nixos-rebuild switch --target-host --use-remote-sudo` | Builds locally, copies closure, activates atomically. No manual editing on server. |
| Port verification | Manual iptables/nftables inspection | `nmap -sT <ip>` from external host | External scan is the only reliable way to verify default-deny. Internal inspection can miss rules. |

**Key insight:** Phase 2 is deployment + configuration wiring. The NixOS module system, nixos-anywhere, and disko handle all the heavy lifting. The task is getting the parameters right and running the command.

## Common Pitfalls

### Pitfall 1: nixos-anywhere Kexec Failure on Contabo

**What goes wrong:** nixos-anywhere's kexec image fails to boot on the VPS, hanging during the kexec step. The tool connects via SSH, uploads the kexec image, but the new kernel never comes up.
**Why it happens:** Some VPS providers have kexec disabled or broken at the kernel level. Newer kexec images have had reported issues on some providers.
**How to avoid:**
1. Verify the existing Ubuntu system has kexec support: `cat /proc/sys/kernel/kexec_load_disabled` should be 0.
2. If kexec fails, try an older kexec image via `--kexec <url>`.
3. As a last resort, Contabo allows booting from a NixOS ISO via their rescue console, then running nixos-anywhere in NixOS-installer mode (no kexec needed).
**Warning signs:** nixos-anywhere hangs at "kexec-ing into NixOS installer" for more than 2 minutes.
**Confidence:** MEDIUM (community reports of kexec issues on some providers, but Contabo specifically has not been widely reported as broken)

### Pitfall 2: Server Unreachable After Deployment (Boot Failure)

**What goes wrong:** nixos-anywhere completes successfully but SSH never comes back. The server did not boot into NixOS.
**Why it happens:** Wrong GRUB config (missing hybrid BIOS/UEFI), missing VirtIO kernel modules, or wrong disk device path.
**How to avoid:**
1. Phase 1 already configured hybrid GRUB and VirtIO modules -- verify they are correct.
2. Access Contabo VNC console to see boot output if SSH fails.
3. If the server boots to GRUB but fails to mount root, check that `/dev/sda` is correct in the kexec environment.
**Warning signs:** nixos-anywhere says "Installation finished" but SSH connection times out.
**Recovery:** Contabo VNC console. If NixOS is installed but misconfigured, boot into rescue mode and fix config. If completely broken, re-deploy from scratch (the existing Ubuntu image can be reinstalled via Contabo panel).
**Confidence:** MEDIUM (hybrid GRUB config is the correct hedge, but Contabo boot behavior is not 100% verified)

### Pitfall 3: sops-nix Decryption Failure on First Boot

**What goes wrong:** NixOS boots but sops-nix cannot decrypt secrets. Activation errors mention "failed to decrypt" or age key issues.
**Why it happens:** The SSH host key was not correctly deployed via `--extra-files`, or the key permissions are wrong, or the age public key in `.sops.yaml` does not match the deployed private key.
**How to avoid:**
1. Verify the `--extra-files` directory structure: `$temp/etc/ssh/ssh_host_ed25519_key` with mode 600.
2. Verify the age public key in `.sops.yaml` was derived from the SAME key in `tmp/host-key/`.
3. After deployment, SSH in and verify: `ls -la /etc/ssh/ssh_host_ed25519_key` (exists, mode 600).
4. Test decryption: `cat /run/secrets/` should show decrypted secret files (if any are declared in secrets.nix).
**Warning signs:** sops-nix activation errors in `journalctl -u sops-nix`.
**Confidence:** HIGH (well-documented workflow, Phase 1 already verified the key derivation)

### Pitfall 4: Locked Out After SSH Hardening

**What goes wrong:** After tightening SSH to key-only + PermitRootLogin "no", you cannot SSH in because the authorized key is wrong or the user does not have correct permissions.
**Why it happens:** The SSH public key in users.nix does not match the private key used to connect, or there is a typo in the key string.
**How to avoid:**
1. Verify the SSH public key in `modules/users.nix` matches the actual key used for connection.
2. Test SSH as `dangirsh` immediately after deployment, BEFORE removing root's authorized_keys.
3. Keep root's authorized_keys during initial deployment as a fallback. Remove in a follow-up `nixos-rebuild` only after confirming dangirsh access.
**Warning signs:** "Permission denied (publickey)" when trying to SSH as dangirsh.
**Recovery:** If root SSH still works (Phase 1 config had root keys), log in as root and fix. If completely locked out, use Contabo VNC/rescue console.
**Confidence:** HIGH (standard SSH lockout scenario, well-known prevention)

### Pitfall 5: Docker Group Warning Before Docker Enabled

**What goes wrong:** Adding `"docker"` to `extraGroups` before `virtualisation.docker.enable = true` may produce a warning during activation that the group does not exist.
**Why it happens:** NixOS creates the `docker` group as part of the Docker module. If Docker is not enabled, the group may not exist.
**How to avoid:** This is benign. NixOS handles this gracefully -- the user is declared as wanting the docker group, and when Docker is enabled in Phase 3, the group will be created and the user will be added to it. No action needed.
**Warning signs:** Warning in `nixos-rebuild` output about non-existent group. This is informational, not an error.
**Confidence:** HIGH (NixOS group handling is well-understood)

### Pitfall 6: Known Hosts Mismatch After Deployment

**What goes wrong:** After nixos-anywhere wipes the VPS and installs NixOS, SSH refuses to connect because the host key fingerprint has changed (it now uses the pre-generated key from Phase 1 instead of the original Ubuntu key).
**Why it happens:** The local `~/.ssh/known_hosts` still has the old Ubuntu host key for the server's IP.
**How to avoid:** Run `ssh-keygen -R <CONTABO_IP>` before attempting to SSH after deployment.
**Warning signs:** "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!" SSH error message.
**Confidence:** HIGH (always happens after any OS reinstall)

## Code Examples

### Complete networking.nix for Phase 2

```nix
# modules/networking.nix
# @decision NET-01: key-only SSH, no root login
# @decision NET-02: default-deny nftables firewall
# @decision NET-04: ports 22, 80, 443, 22000 only
{ config, lib, pkgs, ... }: {
  # NET-02: Use nftables backend (modern replacement for iptables)
  networking.nftables.enable = true;

  # NET-02 + NET-04: Default-deny firewall with explicit allowlist
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22     # SSH (NET-01)
      80     # HTTP
      443    # HTTPS
      22000  # Syncthing (NET-04)
    ];
  };

  # NET-01: SSH server — key-only authentication, no root login
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
```

### Complete users.nix for Phase 2

```nix
# modules/users.nix
# @decision SYS-01: dangirsh with sudo + docker group
{ config, pkgs, ... }: {
  users.users.dangirsh = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
    ];
  };

  # Root SSH access: keep during initial deployment for recovery.
  # Remove after confirming dangirsh SSH + sudo works.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
  ];
}
```

### Verifying base.nix Satisfies BOOT-05 and BOOT-06

The existing `modules/base.nix` from Phase 1 already satisfies both requirements:

```nix
# modules/base.nix (already exists from Phase 1 — no changes needed)
{ config, lib, pkgs, ... }: {
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;   # BOOT-06: Hard-link dedup runs automatically
  };

  nix.gc = {
    automatic = true;             # BOOT-05: GC runs on schedule
    dates = "weekly";             # BOOT-05: Weekly schedule
    options = "--delete-older-than 30d";  # BOOT-05: Delete generations older than 30 days
  };
}
```

**BOOT-05 satisfied:** `nix.gc.automatic = true` with `dates = "weekly"` and `options = "--delete-older-than 30d"`.
**BOOT-06 satisfied:** `nix.settings.auto-optimise-store = true` enables automatic hard-link deduplication.

No changes needed to base.nix.

### Verifying hosts/acfs/default.nix Satisfies SYS-02

The existing `hosts/acfs/default.nix` from Phase 1 already satisfies SYS-02:

```nix
# hosts/acfs/default.nix (already exists — no changes needed)
{ config, pkgs, inputs, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
  ];

  networking.hostName = "acfs";           # SYS-02: hostname
  time.timeZone = "Europe/Berlin";        # SYS-02: timezone
  i18n.defaultLocale = "C.UTF-8";         # SYS-02: locale

  system.stateVersion = "25.11";
}
```

**SYS-02 satisfied:** Hostname `acfs`, timezone `Europe/Berlin`, locale `C.UTF-8` are all set.

### Complete nixos-anywhere Deployment Script

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
CONTABO_IP="${1:?Usage: $0 <CONTABO_IP>}"
FLAKE_REF=".#acfs"

# Phase 1 pre-generated host key
HOST_KEY="tmp/host-key/ssh_host_ed25519_key"

if [[ ! -f "$HOST_KEY" ]]; then
  echo "ERROR: Pre-generated host key not found at $HOST_KEY"
  echo "This should have been created in Phase 1 (plan 01-02)."
  exit 1
fi

# Create temp directory for --extra-files
temp=$(mktemp -d)
cleanup() { rm -rf "$temp"; }
trap cleanup EXIT

# Stage SSH host key with correct directory structure and permissions
install -d -m755 "$temp/etc/ssh"
cp "$HOST_KEY" "$temp/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$temp/etc/ssh/ssh_host_ed25519_key"

echo "=== Deploying NixOS to $CONTABO_IP ==="
echo "Flake: $FLAKE_REF"
echo "Extra files: $temp/etc/ssh/ssh_host_ed25519_key"
echo ""
echo "WARNING: This will COMPLETELY WIPE the target server."
echo "Press Ctrl+C within 5 seconds to abort."
sleep 5

# Deploy
nix run github:nix-community/nixos-anywhere -- \
  --extra-files "$temp" \
  --flake "$FLAKE_REF" \
  --target-host "root@$CONTABO_IP"

echo ""
echo "=== Deployment complete ==="
echo "Remove old known_hosts entry:"
echo "  ssh-keygen -R $CONTABO_IP"
echo ""
echo "Then verify SSH access:"
echo "  ssh dangirsh@$CONTABO_IP"
```

### Post-Deployment Verification Commands

```bash
# 1. Remove stale known_hosts entry
ssh-keygen -R <CONTABO_IP>

# 2. Verify SSH as dangirsh (should work with key)
ssh dangirsh@<CONTABO_IP> 'echo "SSH works"'

# 3. Verify root login is rejected
ssh root@<CONTABO_IP> 2>&1 | grep -q "Permission denied" && echo "Root login correctly rejected"

# 4. Verify password auth is rejected
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no dangirsh@<CONTABO_IP> 2>&1 | grep -q "Permission denied" && echo "Password auth correctly rejected"

# 5. Verify hostname, timezone, locale
ssh dangirsh@<CONTABO_IP> 'hostname && timedatectl show --property=Timezone --value && locale | head -1'
# Expected: acfs, Europe/Berlin, LANG=C.UTF-8

# 6. Verify firewall (from external machine)
nmap -sT -p 22,80,443,22000 <CONTABO_IP>
# Expected: 22 open, 80/443/22000 open (or filtered if no service listening)

# 7. Verify default-deny (scan a port that should be closed)
nmap -sT -p 8080 <CONTABO_IP>
# Expected: filtered or closed

# 8. Verify nix GC is scheduled
ssh dangirsh@<CONTABO_IP> 'sudo systemctl list-timers | grep nix-gc'
# Expected: nix-gc.timer active

# 9. Verify sops-nix host key
ssh dangirsh@<CONTABO_IP> 'ls -la /etc/ssh/ssh_host_ed25519_key'
# Expected: -rw------- (mode 600)

# 10. Verify nix store optimization is enabled
ssh dangirsh@<CONTABO_IP> 'nix show-config | grep auto-optimise-store'
# Expected: auto-optimise-store = true
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| iptables firewall backend | nftables backend via `networking.nftables.enable` | NixOS 21.11+ (stable in 23.05+) | Modern ruleset, atomic updates, better performance |
| Manual SSH host key management | `nixos-anywhere --extra-files` for key injection | nixos-anywhere since 2022 | Deterministic key deployment, enables sops-nix bootstrap |
| `PermitRootLogin "prohibit-password"` | `PermitRootLogin "no"` + sudo user | Always best practice | Reduced attack surface. Root SSH unnecessary with sudo. |
| iptables for Docker network isolation | nftables + Docker `--iptables=false` (Phase 3) | 2023+ | Prevents Docker from punching holes in the firewall |

**Deprecated/outdated patterns to avoid:**
- `networking.firewall.extraCommands` with iptables syntax when nftables is enabled (use `extraInputRules` if custom rules needed)
- `PermitRootLogin "without-password"` (use `"prohibit-password"` or `"no"` -- "without-password" is a deprecated alias)

## Open Questions

1. **Contabo boot mode (BIOS vs UEFI)**
   - What we know: One community source says Contabo uses BIOS only. Another confirms UEFI hardware but BIOS-only working.
   - What's unclear: Whether THIS specific Contabo VPS boots BIOS or UEFI.
   - Recommendation: The hybrid GRUB config from Phase 1 handles both. Check `[ -d /sys/firmware/efi ]` on the existing Ubuntu system before deploying if desired. Not a blocker.
   - **Confidence:** HIGH for the hybrid solution working regardless.

2. **Contabo kexec support**
   - What we know: nixos-anywhere uses kexec by default. Most Linux VPS have kexec enabled.
   - What's unclear: Whether Contabo's Ubuntu image has kexec enabled/working.
   - Recommendation: Check `cat /proc/sys/kernel/kexec_load_disabled` on the target before deploying. If kexec fails, use Contabo's rescue mode or VNC to boot a NixOS ISO.
   - **Confidence:** MEDIUM (kexec is standard, but provider restrictions can exist)

3. **Docker group without Docker enabled**
   - What we know: Adding `"docker"` to `extraGroups` before Docker is enabled in Phase 3 may produce a harmless warning.
   - What's unclear: Whether NixOS 25.11 silently ignores non-existent groups or produces a visible warning.
   - Recommendation: Add the group now (SYS-01 requires it). Tolerate any warning. Phase 3 enables Docker and the group will be properly created.
   - **Confidence:** HIGH (NixOS group handling is robust)

4. **Root SSH key removal timing**
   - What we know: Phase 1 added root authorized_keys as a fallback. NET-01 requires root login rejected.
   - What's unclear: Best moment to remove root's authorized_keys.
   - Recommendation: Keep root keys during initial deployment (Plan 02). After verifying dangirsh SSH + sudo works, remove root keys in a follow-up `nixos-rebuild`. This two-step approach prevents lockout.
   - **Confidence:** HIGH (standard operational practice)

5. **Remote nixos-rebuild without passwordless sudo**
   - What we know: `nixos-rebuild --target-host --use-remote-sudo` needs sudo on the target. Phase 2.1 adds `wheelNeedsPassword = false`.
   - What's unclear: Whether the first remote nixos-rebuild after deployment can work before Phase 2.1 changes.
   - Recommendation: For the initial deployment, nixos-anywhere handles everything. For subsequent Phase 2 nixos-rebuild runs, either use root SSH (kept temporarily) or accept the password prompt. Phase 2.1 resolves this cleanly.
   - **Confidence:** HIGH (well-documented workflow)

## Sources

### Primary (HIGH confidence)
- [nixos-anywhere secrets howto](https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/secrets.md) -- --extra-files SSH host key deployment pattern, complete bash script
- [nixos-anywhere quickstart](https://nix-community.github.io/nixos-anywhere/quickstart.html) -- Deployment workflow, prerequisites, command syntax
- [nixos-anywhere reference](https://nix-community.github.io/nixos-anywhere/reference.html) -- Complete CLI flag reference
- [NixOS Official Wiki: Firewall](https://wiki.nixos.org/wiki/Firewall) -- nftables.enable + firewall API compatibility, default-deny behavior
- [NixOS Official Wiki: SSH](https://wiki.nixos.org/wiki/SSH) -- SSH hardening settings, PasswordAuthentication, KbdInteractiveAuthentication, PermitRootLogin
- [NixOS Official Wiki: nixos-rebuild](https://wiki.nixos.org/wiki/Nixos-rebuild) -- Remote deployment with --target-host and --use-remote-sudo
- [NixOS Official Wiki: Docker](https://wiki.nixos.org/wiki/Docker) -- Docker group, extraGroups user config
- [NixOS Official Wiki: Storage Optimization](https://wiki.nixos.org/wiki/Storage_optimization) -- nix.gc and auto-optimise-store config

### Secondary (MEDIUM confidence)
- [nixos-anywhere --extra-files issue #283](https://github.com/nix-community/nixos-anywhere/issues/283) -- How tar-based file copy works, directory structure requirements
- [Contabo NixOS install notes (stunkymonkey)](https://www.stunkymonkey.de/blog/contabo-nixos/) -- Contabo BIOS-only confirmation, VirtIO module requirements
- [NixOS Discourse: Firewall setup](https://discourse.nixos.org/t/firewall-setup-in-nixos/51826) -- Practical nftables + firewall configuration examples
- [NixOS & Flakes Book: Remote Deployment](https://nixos-and-flakes.thiscute.world/best-practices/remote-deployment) -- nixos-rebuild remote workflow patterns
- [NixOS Discourse: nixos-rebuild remote target with non-root user](https://discourse.nixos.org/t/nixos-rebuild-remote-target-with-non-root-user/25042) -- --use-remote-sudo workflow

### Tertiary (LOW confidence)
- Community reports about kexec failures on VPS providers -- varies by provider, not Contabo-specific
- Docker group behavior when Docker is not yet enabled -- expected to be benign, not explicitly tested on 25.11

## Metadata

**Confidence breakdown:**
- nixos-anywhere deployment: HIGH -- Official documentation provides exact patterns. --extra-files workflow well-documented with complete bash scripts.
- SSH hardening: HIGH -- Standard NixOS options, well-documented on official wiki. Phase 1 already set most options; Phase 2 tightens PermitRootLogin and adds KbdInteractiveAuthentication.
- nftables firewall: HIGH -- Official wiki confirms nftables.enable + firewall.enable work together. Default-deny is the documented default behavior.
- User/system config: HIGH -- Standard NixOS options. Existing Phase 1 config already satisfies SYS-02 and BOOT-05/BOOT-06.
- Contabo-specific: MEDIUM -- Boot mode hedged with hybrid GRUB. kexec support unverified but expected.
- Pitfalls: HIGH -- All documented from official sources and Phase 1 research.

**Research date:** 2026-02-15
**Valid until:** 2026-04-15 (60 days -- NixOS stable, slow-moving domain)
