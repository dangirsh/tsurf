#!/usr/bin/env bash
# scripts/btrfs-rollback.sh — BTRFS root subvolume rollback (runs in initrd)
# Moves current root to old_roots/<timestamp>, prunes snapshots >30d, creates fresh root.
#
# Why this exists: nix-community/impermanence only handles the persistence side
# (bind-mounting paths from /persist onto the ephemeral root). It does not provide
# a wipe mechanism. This script is the wipe — it deletes and recreates the root
# BTRFS subvolume each boot ("Erase your darlings" pattern). We use BTRFS rollback
# instead of tmpfs root because server workloads need disk-backed root (see @decision
# IMP-01 in modules/impermanence.nix).
#
# Environment: NixOS traditional (non-systemd) initrd via boot.initrd.postResumeCommands.
# Requires: bash, mount, btrfs, stat, date, find, mkdir, mv (all available in NixOS initrd).

cleanup() {
  if mountpoint -q /btrfs_tmp 2>/dev/null; then
    umount /btrfs_tmp 2>/dev/null || true
  fi
  rmdir /btrfs_tmp 2>/dev/null || true
}
trap cleanup EXIT

mkdir /btrfs_tmp || { echo "btrfs-rollback: failed to create /btrfs_tmp"; exit 1; }
mount /dev/disk/by-partlabel/disk-main-root /btrfs_tmp || { echo "btrfs-rollback: failed to mount root"; exit 1; }
if [[ -e /btrfs_tmp/root ]]; then
  mkdir -p /btrfs_tmp/old_roots
  timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
  mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
fi

delete_subvolume_recursively() {
  local saved_IFS="$IFS"
  IFS=$'\n'
  for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
    delete_subvolume_recursively "/btrfs_tmp/$i"
  done
  IFS="$saved_IFS"
  btrfs subvolume delete "$1"
}

for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
  delete_subvolume_recursively "$i"
done

btrfs subvolume create /btrfs_tmp/root
umount /btrfs_tmp
trap - EXIT
