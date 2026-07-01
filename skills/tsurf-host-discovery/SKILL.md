---
name: tsurf-host-discovery
description: Inspect an existing or prospective NixOS host before applying tsurf. Use when an agent needs to choose a safe tsurf setup path, adapt to unknown disk/network/provider details, determine whether a host can use the public roles directly, or collect facts for a private overlay.
---

# Tsurf Host Discovery

Use this skill before writing a host config or running a deploy. Treat the
target host and private overlay as the source of truth; do not assume the public
QEMU `/dev/sda` examples fit the machine.

## Workflow

1. Identify the operator intent: evaluation, first production install, migration
   of an existing NixOS host, rescue/recovery, or adding an agent role to an
   already managed host.
2. Inspect the host with non-destructive commands only:
   `ssh root@host '. /etc/os-release; hostnamectl --static; uname -m; findmnt --real; ip -brief addr; ip route; lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL'`.
3. Classify the storage path:
   existing NixOS root, fresh disko install, provider rescue mode, or unknown.
   Never write a disko device path from a template without matching it to
   `lsblk` evidence.
4. Classify networking:
   DHCP, static IPv4, `/32` provider gateway, systemd-networkd requirement,
   Tailscale/headscale dependency, or public SSH bootstrap.
5. Choose modules:
   use exported `inputs.tsurf.nixosModules.*` modules when possible; use the
   public `agent-host` role only when the host should run brokered agents.
6. Hand off to `tsurf-overlay-authoring` with the discovered facts and any
   uncertainty that needs an explicit operator decision.

## Guardrails

- Do not run `nixos-rebuild switch`, `disko`, partitioning, or deploy commands
  from this skill.
- Keep root SSH recovery in scope. If the host has no confirmed root key path,
  stop before deploy planning.
- Keep public and private boundaries clear. Real hostnames, secrets, extra
  services, and personal users belong in the private overlay.
