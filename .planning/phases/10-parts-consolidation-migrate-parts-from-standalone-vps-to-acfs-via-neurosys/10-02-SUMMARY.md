# Plan 10-02 Summary

**Status:** COMPLETE
**Duration:** ~90min (includes VPS reinstall and iterative debugging)
**Commits:** 1 (aabfb0f)

## What Was Done

1. **End-to-end deploy test** — Ran `scripts/deploy.sh` against acfs server. Multiple iterations required to fix build and deployment issues discovered during live testing.

2. **VPS migration** — Original VPS (62.171.134.33) became unreachable after firewall lockout (port 22 not in allowedTCPPorts). User reinstalled Ubuntu on new Contabo VPS (161.97.74.121). Re-deployed NixOS via nixos-anywhere with pre-generated host key.

3. **Fixes applied during testing:**
   - Updated static IP to 161.97.74.121/18 with new gateway 161.97.64.1
   - Added port 22 to `allowedTCPPorts` (SSH was blocked by nftables)
   - Changed `PermitRootLogin` to `prohibit-password` for deploy pipeline
   - Added root authorized keys for remote deployment via nixos-rebuild
   - Updated CASS binary hash (upstream tarball changed)
   - Added `--target` flag to deploy.sh for IP override
   - Pinned parts input to ce9599a (lockfile + npmDepsHash fix)

4. **Parts repo fixes** — Pushed two commits to parts main:
   - `7edc37d`: Updated npmDepsHash for parts-tools
   - `ce9599a`: Synced gateway/package-lock.json + recomputed npmDepsHash

5. **Final deploy verification** — Deploy script ran successfully. Core services confirmed:
   - parts-tools: Up, port 8080
   - parts-agent: Up
   - sshd, fail2ban, docker: All active
   - sops-nix: Age key imported correctly

## Known Issues (pre-existing, not pipeline)

- claw-swap containers: Images not built on fresh install (need claw-swap repo cloned first)
- Tailscale: Auth key expired, autoconnect fails
- Git clone activation: PLACEHOLDER token doesn't work (cosmetic — repos need manual clone or real token)

## Decisions

- @decision NET-04-update: Port 22 must be in allowedTCPPorts for deploy pipeline (SSH via public interface)
- @decision SSH-ROOT: PermitRootLogin = prohibit-password required for nixos-rebuild --target-host
- @decision ROOT-KEYS: Root authorized keys managed in users.nix alongside dangirsh keys
- @decision DEPLOY-TARGET: deploy.sh --target flag allows IP override when hostname doesn't resolve

## Artifacts

| File | Change |
|------|--------|
| `hosts/acfs/default.nix` | New IP 161.97.74.121/18, gateway 161.97.64.1 |
| `modules/networking.nix` | Port 22 in firewall, PermitRootLogin prohibit-password |
| `modules/users.nix` | Root authorized keys added |
| `packages/cass.nix` | Updated CASS binary hash |
| `scripts/deploy.sh` | Added --target flag |
| `flake.lock` | Parts pinned to ce9599a |

## Next

Phase 10 complete. Merge to main and update ROADMAP.md.
