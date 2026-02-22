# Phase 23: Tailscale Security and Self-Sovereignty - Research

**Researched:** 2026-02-22
**Domain:** Tailscale Tailnet Lock (TKA), ACL policy hardening, key management, NixOS Tailscale module
**Confidence:** HIGH

## Summary

This phase hardens the existing Tailscale deployment by enabling Tailnet Key Authority (TKA / "Tailnet Lock"), tightening ACL policies, and establishing key hygiene practices. The core operational change is running `tailscale lock init` on the live server, which transitions the tailnet's trust model from "trust Tailscale coordination server" to "trust self-custodied signing nodes." This is a well-documented, GA feature available on the free Personal plan.

The NixOS configuration changes are minimal: the current `modules/networking.nix` needs no structural changes for TKA (it is enabled via CLI, not NixOS config). The main config change is restoring the port 22 assertion that was temporarily disabled for nixos-anywhere migration. ACL policy changes happen in the Tailscale admin console (or via API/GitOps), not in the NixOS codebase.

**Primary recommendation:** Enable Tailnet Lock via CLI on neurosys (as a signing node), sign all existing nodes, then harden ACLs in the admin console. NixOS config changes are limited to restoring the port 22 assertion and potentially adding a `tag:server` to the neurosys auth key.

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Tailscale (tailscaled) | 1.82+ (nixos-25.11 pinned) | VPN mesh, TKA enforcement | Already deployed; TKA is built into the daemon |
| Tailscale admin console | N/A (SaaS) | ACL policy, device management | Web UI for policy + key management |
| `tailscale lock` CLI | Built into tailscale binary | TKA init, sign, status, revoke | Only way to enable/manage TKA |
| sops-nix | Latest (flake pinned) | Encrypted tailscale-authkey | Already in use for auth key |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `tailscale lock sign` | Sign new nodes or pre-auth keys | Adding any new device to the tailnet |
| Tailscale ACL policy (huJSON) | Access control rules | Admin console or GitOps via API |
| Tailscale grants (huJSON) | Next-gen ACL syntax | Recommended for new rules; coexists with ACLs |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| TKA (Tailnet Lock) | Headscale (self-hosted) | Headscale = full control plane ownership but massive operational overhead; TKA covers the key sovereignty concern without running infrastructure. **Rejected in Phase 13.** |
| Admin console ACLs | GitOps via Tailscale API | GitOps is better for teams; for a single-user tailnet, admin console is simpler and sufficient. Consider GitOps if policy becomes complex. |
| Grants | Legacy ACLs | ACLs work but won't get new features. Tailscale recommends grants for new configs. Can coexist during migration. |

## Architecture Patterns

### Current Tailscale Config (modules/networking.nix)
```nix
services.tailscale = {
  enable = true;
  authKeyFile = config.sops.secrets."tailscale-authkey".path;
  useRoutingFeatures = "client";   # auto-sets checkReversePath = "loose"
  extraUpFlags = [ "--accept-routes" ];
};

# Force nftables backend
systemd.services.tailscaled.serviceConfig.Environment = [
  "TS_DEBUG_FIREWALL_MODE=nftables"
];
```

### Pattern 1: TKA Initialization (Operational, Not NixOS Config)
**What:** Tailnet Lock is enabled via CLI commands on the live server, not via NixOS module options.
**When to use:** One-time setup, then ongoing signing of new nodes.

```bash
# Step 1: On a signing node (e.g., neurosys), initialize TKA
# The admin console generates this command with pre-populated key values
tailscale lock init

# Step 2: Verify all nodes are signed
tailscale lock status

# Step 3: Sign any locked-out nodes
tailscale lock sign nodekey:<key> tlpub:<key>
```

**Key requirement:** Minimum 2 signing nodes required. For a personal tailnet, this means neurosys + at least one laptop/desktop.

### Pattern 2: Pre-Signed Auth Keys for Server Rebuilds
**What:** When TKA is enabled, new auth keys must be pre-signed before use.
**When to use:** Before NixOS rebuilds that might trigger re-authentication.

```bash
# On a signing node, sign an auth key for automated use
export AUTH_KEY="tskey-auth-XXXXCTRL-NNNNNN"
tailscale lock sign $AUTH_KEY
# Use the resulting signed key in sops-nix
```

**Critical note:** The current `authKeyFile` in sops-nix stores a pre-auth key. After TKA is enabled, this key must be pre-signed. However, if `/var/lib/tailscale` is persisted (it is, via impermanence.nix), the server won't need to re-authenticate on normal rebuilds -- the existing node identity persists. The auth key is only used for initial setup or if state is lost.

### Pattern 3: ACL Policy with Tags (Admin Console)
**What:** Tag-based access control for server vs. personal devices.

```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["autogroup:self:*"]
    },
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:server:*"]
    }
  ]
}
```

**Or using grants (recommended for new rules):**
```json
{
  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["tag:server"],
      "ip": ["*"]
    }
  ]
}
```

### Anti-Patterns to Avoid
- **Enabling both TKA and Device Approval:** These are mutually exclusive. TKA is strictly superior for self-sovereignty since it uses cryptographic signing instead of admin-console approval (which trusts Tailscale's infrastructure).
- **Long-lived reusable auth keys in sops-nix:** The current auth key in sops-nix should be one-time or tagged. Reusable keys are dangerous if leaked.
- **Forgetting disablement secrets:** TKA initialization generates 10 disablement secrets. Losing ALL of them without Tailscale support backup = permanent lock-in. Must be stored securely.
- **Running `tailscale lock init` without a second signing node:** Minimum 2 signing nodes required. Planning must identify which 2+ devices will be signing nodes before init.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Node identity verification | Custom certificate pinning | Tailnet Lock (`tailscale lock`) | Cryptographic chain of trust maintained by TKA subsystem |
| ACL management | NixOS-managed ACL files | Tailscale admin console or API | ACLs are a Tailscale coordination server concern, not a NixOS config concern |
| Key rotation | Custom cron scripts | Tailscale key expiry settings + admin console | Built-in key expiry with configurable duration (1-180 days) |
| DNS privacy | Custom DNS resolver | MagicDNS (built-in) | All private DNS resolution happens locally on-device; no external queries for tailnet names |

**Key insight:** Most of this phase is operational (CLI commands, admin console settings) rather than NixOS configuration changes. The planner should structure tasks around operations, not code changes.

## Common Pitfalls

### Pitfall 1: TKA State Not Persisted (Impermanence)
**What goes wrong:** After enabling TKA, if the Tailscale state directory is wiped on reboot, the node cannot enforce TKA signing checks.
**Why it happens:** Impermanence wipes `/var/lib/tailscale` if not persisted.
**How to avoid:** Already handled -- `impermanence.nix` persists `/var/lib/tailscale`. Verify this is in place before enabling TKA.
**Warning signs:** `tailscale lock status` shows "disabled" or "unavailable" after reboot.

### Pitfall 2: Locked Out After TKA Init
**What goes wrong:** After enabling TKA, a device that wasn't signed can't connect.
**Why it happens:** All existing nodes receive automatic signatures during init, but any node offline during init will need manual signing.
**How to avoid:** Ensure all nodes are online and connected when running `tailscale lock init`. Verify with `tailscale lock status` on every node.
**Warning signs:** "Locked out" badge in admin console; device can't reach other nodes.

### Pitfall 3: TS-2025-008 Vulnerability (State Directory)
**What goes wrong:** Nodes without `--statedir` silently skip TKA enforcement.
**Why it happens:** Bug in Tailscale < 1.90.8 where missing state dir caused silent bypass of signing checks.
**How to avoid:** Ensure Tailscale >= 1.90.8. NixOS systemd service uses `/var/lib/tailscale` as default statedir, so this is not normally an issue. Verify version after `nix flake lock --update-input nixpkgs`.
**Warning signs:** `tailscale version` reports < 1.90.8.

### Pitfall 4: Auth Key After TKA
**What goes wrong:** sops-nix `tailscale-authkey` stops working for new deployments because the key isn't pre-signed.
**Why it happens:** TKA requires auth keys to be signed before use.
**How to avoid:** After enabling TKA, regenerate the auth key in admin console and pre-sign it with `tailscale lock sign`. Update sops-nix with the signed key.
**Warning signs:** New NixOS deployment from scratch fails to join tailnet.

### Pitfall 5: Port 22 Assertion Still Disabled
**What goes wrong:** Port 22 is currently exposed on the public firewall (temporarily for nixos-anywhere migration).
**Why it happens:** The assertion was commented out in `networking.nix` and port 22 was added to `allowedTCPPorts` with a `TEMPORARY` comment.
**How to avoid:** This phase should restore the assertion and remove port 22 from allowedTCPPorts as a prerequisite, since the nixos-anywhere migration is complete.
**Warning signs:** `grep "TEMPORARY" modules/networking.nix` returns results.

### Pitfall 6: Signing Node Accumulation
**What goes wrong:** Automation that signs auth keys can accumulate signing keys in the TKA, eventually hitting the 512 key limit.
**Why it happens:** Each pre-signed auth key may create a new TLK entry.
**How to avoid:** Use a small, fixed set of signing nodes (max 20 per tailnet). Don't automate signing of ephemeral auth keys.
**Warning signs:** `tailscale lock log` shows rapid TLK growth.

## Code Examples

### NixOS Config Change: Restore Port 22 Assertion
```nix
# In modules/networking.nix - uncomment and restore:
assertions = [
  {
    assertion = exposed == [];
    message = "SECURITY: Internal service ports leaked into allowedTCPPorts: ...";
  }
  {
    assertion = !builtins.elem 22 config.networking.firewall.allowedTCPPorts;
    message = "SECURITY: Port 22 must NOT be in allowedTCPPorts. SSH is Tailscale-only.";
  }
];

# Remove port 22 from allowedTCPPorts:
networking.firewall.allowedTCPPorts = [ 80 443 22000 ];
```

### TKA CLI Operations Sequence
```bash
# 1. Check current Tailscale version (must be >= 1.46.1 for TKA, >= 1.90.8 for TS-2025-008 fix)
tailscale version

# 2. Check current lock status
tailscale lock status

# 3. Enable TKA (generated from admin console with node keys pre-populated)
tailscale lock init
# -> Outputs 10 disablement secrets. SAVE THESE.

# 4. Verify all nodes are signed
tailscale lock status
# Should show all nodes as signed, all TLK keys listed

# 5. On each other node, verify
tailscale lock status
# TLK key set should match across all nodes

# 6. Pre-sign a new auth key for disaster recovery
tailscale lock sign tskey-auth-XXXXCTRL-NNNNNN
```

### ACL Policy Hardening (Admin Console)
```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["tag:server"],
      "ip": ["*"]
    },
    {
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "ip": ["*"]
    }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["autogroup:member"],
      "dst": ["tag:server"],
      "users": ["root", "dangirsh"]
    }
  ]
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Trust Tailscale coordination server | TKA / Tailnet Lock (self-custodied signing keys) | GA 2024 | Coordination server compromise cannot inject rogue nodes |
| ACLs (deny-by-default rules) | Grants (next-gen syntax) | GA 2025 | Grants recommended for new rules; ACLs still supported but frozen |
| Device approval (admin UI) | TKA (cryptographic signing) | 2024 | TKA is strictly superior for sovereignty; mutually exclusive with device approval |
| Default 180-day key expiry | Customizable 1-180 day + per-device overrides | Stable | Tagged servers auto-disable expiry; personal devices should keep expiry |

**Deprecated/outdated:**
- Device approval is superseded by TKA for self-sovereignty use cases (they are mutually exclusive)
- Legacy `.beta.tailscale.net` MagicDNS domains ended support September 2024; all tailnets now use `.ts.net`
- ACLs won't receive new features; grants are the forward path

## Tailscale Plan Compatibility

TKA / Tailnet Lock is available on:
- Personal (free) -- up to 3 users, 100 devices
- Personal Plus ($5/month) -- up to 6 users, 100 devices
- Enterprise

The user's single-user personal server setup is fully compatible with the free Personal plan.

## Impermanence Interaction

The `/var/lib/tailscale` directory is already persisted in `modules/impermanence.nix`. This directory contains:
- Device node keys
- Auth state
- **TKA signing keys and authority chain** (after `tailscale lock init`)

This persistence is **critical** for TKA -- if the TKA state is lost, the node cannot enforce or participate in signing. Since it's already persisted, no impermanence changes are needed.

## Success Criteria Feasibility Assessment

| Criterion | Feasibility | Notes |
|-----------|-------------|-------|
| 1. TKA enabled, all nodes signed | HIGH | CLI operation, well-documented |
| 2. New nodes require TKA signing | HIGH | Automatic after init |
| 3. ACLs reviewed and tightened | HIGH | Admin console operation |
| 4. Device auto-approval disabled | N/A | **Mutually exclusive with TKA.** TKA replaces device approval with cryptographic signing. |
| 5. Auth key rotation documented | HIGH | Document in runbook; update sops-nix key |
| 6. MagicDNS reviewed | HIGH | Low risk; DNS resolution is local, no information leakage by design |
| 7. Node key expiry configured | HIGH | Admin console setting; 180-day default is reasonable |
| 8. SSH hardened (no public IP fallback) | HIGH | Restore port 22 assertion + remove from allowedTCPPorts |
| 9. `nix flake check` passes | HIGH | Only small config change (port 22 assertion) |

**Important note on criterion 4:** The success criteria says "Device auto-approval disabled." Since TKA and device approval are mutually exclusive, enabling TKA inherently means device approval cannot be enabled. TKA provides a stronger guarantee (cryptographic signing vs. admin UI approval). The planner should reinterpret this criterion as "New devices cannot join without cryptographic signing (TKA)."

## Open Questions

1. **Which devices are currently in the tailnet?**
   - What we know: neurosys is the server. The user likely has laptops and phones.
   - What's unclear: Exact device count and which can be signing nodes (Android cannot be a signing node).
   - Recommendation: Run `tailscale status` on neurosys to enumerate all devices before planning. Select 2+ non-Android devices as signing nodes.

2. **Current ACL policy state**
   - What we know: The project enforces Tailscale-only access via NixOS firewall (`trustedInterfaces`). ACL rules are in the admin console, not in this codebase.
   - What's unclear: What ACL rules are currently configured in the admin console (default allow-all, or already customized?).
   - Recommendation: Audit current ACLs via admin console before planning specific tightening.

3. **Auth key type in sops-nix**
   - What we know: `tailscale-authkey` is stored in sops-nix and restarts `tailscaled.service` on change.
   - What's unclear: Is it one-time, reusable, tagged, or ephemeral? Is it still valid or expired?
   - Recommendation: Check current key properties. For a persistent server, a tagged one-time key is ideal. After TKA, it should be pre-signed.

4. **Tailscale version in nixos-25.11**
   - What we know: nixos-25.05 shipped with 1.82.5. The flake uses nixos-25.11.
   - What's unclear: Exact version in nixos-25.11 (need >= 1.90.8 for TS-2025-008 fix).
   - Recommendation: Check `tailscale version` on the live server. If < 1.90.8, consider updating nixpkgs before enabling TKA.

5. **Disablement secret storage**
   - What we know: TKA init generates 10 disablement secrets. Only 1 is needed to disable. Loss of all = permanent lock-in.
   - What's unclear: Where the user wants to store these (password manager, printed, etc.).
   - Recommendation: Store at least 2 disablement secrets in different locations (password manager + offline backup). Optionally enable Tailscale support backup during init.

## Sources

### Primary (HIGH confidence)
- [Tailnet Lock documentation](https://tailscale.com/kb/1226/tailnet-lock) - Full TKA feature reference
- [Security hardening best practices](https://tailscale.com/kb/1196/security-hardening) - Official recommendations
- [Device approval](https://tailscale.com/kb/1099/device-approval) - Mutually exclusive with TKA
- [Key expiry](https://tailscale.com/kb/1028/key-expiry) - Node key expiry configuration
- [Tags documentation](https://tailscale.com/kb/1068/tags) - Tag-based access control
- [ACLs documentation](https://tailscale.com/kb/1018/acls) - Policy structure and migration to grants
- [Auth keys](https://tailscale.com/docs/features/access-control/auth-keys) - Key types, expiry, pre-signing
- [MagicDNS](https://tailscale.com/kb/1081/magicdns) - DNS privacy architecture
- [Grants vs ACLs](https://tailscale.com/kb/1467/grants-vs-acls) - Migration guidance
- [Key and secret management](https://tailscale.com/kb/1252/key-secret-management) - Best practices

### Secondary (MEDIUM confidence)
- [NixOS Tailscale wiki](https://wiki.nixos.org/wiki/Tailscale) - NixOS module options and patterns
- [ACL policy examples](https://tailscale.com/kb/1192/acl-samples) - Practical policy patterns
- [Tailscale pricing](https://tailscale.com/pricing) - TKA available on Personal (free) plan
- [TS-2025-008 security bulletin](https://tailscale.com/security-bulletins) - State directory enforcement fix

### Tertiary (LOW confidence)
- Tailscale version in nixos-25.11: exact version unconfirmed (need to check live server)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Tailscale TKA is well-documented GA feature, NixOS module is established
- Architecture: HIGH - Mostly CLI operations, minimal NixOS config changes needed
- Pitfalls: HIGH - Key pitfalls well-documented (impermanence, mutual exclusivity, auth key signing)
- ACL specifics: MEDIUM - Depends on current admin console state (unknown without live audit)

**Research date:** 2026-02-22
**Valid until:** 2026-04-22 (60 days - stable, slow-moving domain)
