# Execution Summary: Plan 47-02 — Service Isolation + Blast Radius

## Result: PASS

## Changes Made

| File | Change |
|------|--------|
| `modules/secret-proxy.nix` | Added 16 systemd hardening directives: NoNewPrivileges, ProtectSystem="strict", ProtectHome, PrivateTmp, CapabilityBoundingSet="", SystemCallFilter, RestrictNamespaces, RestrictAddressFamilies, RestrictSUIDSGID, PrivateDevices, ProtectKernelTunables, ProtectKernelModules, ProtectKernelLogs, ProtectControlGroups, LockPersonality. MemoryDenyWriteExecute intentionally omitted (Python needs W+X). |
| `modules/monitoring.nix` | Added hardening to `prometheus` serviceConfig: NoNewPrivileges, ProtectHome, ProtectKernelTunables/Modules/Logs, RestrictSUIDSGID, LockPersonality. Added hardening to `prometheus-node-exporter` serviceConfig: NoNewPrivileges, ProtectHome (read-only), ProtectKernelModules/Logs. |
| `modules/home-assistant.nix` | Added ProtectHome, PrivateTmp, NoNewPrivileges to `tailscale-serve-ha` oneshot serviceConfig. |
| `modules/agent-compute.nix` | Added @decision SEC47-13 blast radius documentation block with matrix showing sandboxed vs --no-sandbox agent capabilities. |

## Commits

- `17b0f37` feat(47-02): service isolation — systemd hardening + blast radius docs

## Verification

- `nix flake check`: PASS (both neurosys and ovh configurations)
- All `must_haves` satisfied:
  1. secret-proxy hardened with 16 systemd directives
  2. Prometheus and node-exporter hardened
  3. tailscale-serve-ha hardened
  4. Blast radius documented in agent-compute.nix
  5. No functional changes — hardening is additive

## Decisions

- **SEC47-13**: `--no-sandbox` agent is effectively root (wheel + docker + sudo). Documented as accepted risk.
- **MemoryDenyWriteExecute**: Omitted for secret-proxy (Python requires W+X pages for JIT/ctypes).
- **node-exporter ProtectHome**: Set to `read-only` (not `true`) — may need limited home access for textfile collector.
