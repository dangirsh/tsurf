# Out-of-Band Recovery Runbook

**Goal:** Regain SSH access to a locked-out neurosys host within 5 minutes.

## Quick Reference

| Host | Provider | Public IP | Recovery Method |
|------|----------|-----------|-----------------|
| neurosys (Contabo) | Contabo | 161.97.74.121 | KVM VNC Console |
| neurosys-dev (OVH) | OVH | 135.125.196.143 | Rescue Mode SSH |

---

## Contabo: KVM VNC Console

### Access

1. Log in: https://my.contabo.com
2. Navigate to: Your services → VPS/VDS → select the VPS
3. Click the **VNC** tab to find the VNC IP, port, and password
4. Connect with a VNC client: `vncviewer <VNC_IP>::<VNC_PORT>`
5. Log in as `root` (password set during initial nixos-anywhere install)

### Recovery Options (fastest first)

**Option 1: NixOS generation rollback (~1 min)**
```bash
# List available generations
nix-env -p /nix/var/nix/profiles/system --list-generations

# Switch to the previous generation
nixos-rebuild switch --rollback
```

**Option 2: Fix authorized_keys directly (~2 min)**
```bash
# Write your SSH public key to both persistence path and active path
mkdir -p /persist/root/.ssh
chmod 700 /persist/root/.ssh
echo "ssh-ed25519 AAAAC3... your-key-comment" >> /persist/root/.ssh/authorized_keys
chmod 600 /persist/root/.ssh/authorized_keys

# Also update the active authorized_keys.d (survives until next boot)
mkdir -p /etc/ssh/authorized_keys.d
cat /persist/root/.ssh/authorized_keys > /etc/ssh/authorized_keys.d/root
chmod 644 /etc/ssh/authorized_keys.d/root

systemctl restart sshd
```

**Option 3: Boot previous generation from GRUB (~3 min)**
1. Reboot the VPS from the Contabo panel
2. Watch VNC for the GRUB menu (~5s window)
3. Select a previous NixOS generation from the list
4. Once booted, make permanent: `nixos-rebuild switch --rollback`

### Disk Layout (for manual mount)

Contabo disk: `/dev/sda`, GPT:
- Partition 1: 2M BIOS boot
- Partition 2: 512M `/boot` (ESP, vfat)
- Partition 3: remainder (BTRFS)

BTRFS subvolumes on partition 3:
- `root` → `/` (ephemeral — wiped on every boot)
- `persist` → `/persist` (survives reboots: SSH keys, Tailscale state, service data)
- `nix` → `/nix` (Nix store + all NixOS generations)
- `log` → `/var/log`
- `docker` → `/var/lib/docker`

```bash
# Mount persist subvolume from emergency/rescue shell
mount /dev/sda3 /mnt -o subvol=persist
ls /mnt/root/.ssh/           # persisted root SSH keys
ls /mnt/etc/ssh/             # SSH host key (age key derivation chain)
```

---

## OVH: Rescue Mode

### Enable Rescue Mode

1. Log in: https://www.ovh.com/manager/
2. Navigate to: Bare Metal Cloud → Virtual Private Servers → select VPS
3. Click **Boot** tab → select **Rescue** → Confirm
4. Click **Reboot** (takes ~3 minutes)
5. Rescue credentials are emailed to your OVH account email

### SSH Into Rescue

```bash
ssh root@135.125.196.143
# Use the password from the email
```

### Disk Layout in Rescue Mode

**IMPORTANT**: In rescue mode, disk layout may differ:
- Normal boot: VPS disk = `/dev/sda`
- Rescue mode: rescue system = `/dev/sda`, VPS disk = `/dev/sdb` (check with `lsblk`)

```bash
lsblk   # identify the correct disk (400 GB SSD)
```

### Recovery Options

**Option 1: Fix authorized_keys (~3 min)**
```bash
# Mount the persist subvolume (adjust /dev/sda3 → /dev/sdb3 if in rescue mode)
mount /dev/sda3 /mnt -o subvol=persist   # or /dev/sdb3 in rescue mode

mkdir -p /mnt/root/.ssh
chmod 700 /mnt/root/.ssh
echo "ssh-ed25519 AAAAC3... your-key-comment" >> /mnt/root/.ssh/authorized_keys
chmod 600 /mnt/root/.ssh/authorized_keys
umount /mnt
```

**Option 2: NixOS rollback via chroot (~5 min)**
```bash
# Mount all needed subvolumes
DISK=/dev/sda3   # adjust to /dev/sdb3 if in rescue mode
mount "$DISK" /mnt -o subvol=root
mount "$DISK" /mnt/persist -o subvol=persist
mount "$DISK" /mnt/nix -o subvol=nix
mount /dev/sda2 /mnt/boot   # adjust sda/sdb

# Chroot and rollback
nixos-enter --root /mnt -- nixos-rebuild switch --rollback
```

### Exit Rescue Mode

1. In OVH Manager: **Boot** tab → select **Boot from hard disk** → Confirm
2. Reboot the VPS
3. **IMPORTANT**: OVH rescue mode is persistent — the VPS stays in rescue until you
   explicitly switch back to hard disk boot

---

## After Recovery

Once SSH access is restored:

1. **Identify root cause**: `journalctl -b -1 -p err` (previous boot errors)
2. **Always deploy via private overlay**:
   ```bash
   cd /data/projects/private-neurosys
   ./scripts/deploy.sh [--node neurosys|ovh]
   ```
3. **Never use `nixos-rebuild switch` directly** — it bypasses all safety guards
4. **Verify break-glass key is present**:
   ```bash
   grep 'break-glass-emergency' /etc/ssh/authorized_keys.d/root
   ```

---

## Emergency Contacts

- **Contabo support**: https://my.contabo.com/support (ticket system)
- **OVH support**: https://help.ovhcloud.com/ (ticket system)
