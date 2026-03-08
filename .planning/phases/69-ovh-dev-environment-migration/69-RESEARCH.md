# Phase 69 Research: OVH Dev Environment Migration

## Summary

Migrate daily development from acfs (local machine) to OVH VPS (neurosys-dev). The work
is almost entirely in the private overlay (`/data/projects/private-neurosys`). OVH already
runs NixOS gen-3 with impermanence, Tailscale, Syncthing, Docker, and agent-compute. The
migration adds: comprehensive repo cloning, secret-proxy for dev agents, and validation
that a sandboxed Claude Code session works end-to-end.

**Confidence: HIGH** -- all building blocks exist. No novel architecture. Primary risk is
getting the OVH sops secrets populated with real API keys (currently some are placeholders).

---

## Current State

### OVH Host Config (private overlay)

The OVH nixosConfiguration is `self.nixosConfigurations.ovh` built from:

```
commonModules ++ ovhModules ++ [ ./hosts/ovh ]
```

**commonModules** (shared by both hosts):
- `srvos.nixosModules.server` -- server hardening defaults
- `disko.nixosModules.disko` -- disk layout
- `impermanence.nixosModules.impermanence` -- persist paths
- `sops-nix.nixosModules.sops` -- secret decryption
- `home-manager.nixosModules.home-manager` -- user env (imports `./home`)
- `llm-agents.overlays.default` -- claude-code, codex, etc.
- Public modules: `base.nix`, `boot.nix`, `networking.nix`, `secrets.nix`, `docker.nix`, `impermanence.nix`, `dashboard.nix`, `canvas.nix`
- Private replacements: `users.nix` (dangirsh instead of dev), `syncthing.nix` (real device IDs), `agent-compute.nix` (extra packages, dangirsh user refs), `impermanence.nix` (dangirsh home dir)
- Private additions: `secrets.nix` (owner overrides), `repos.nix` (repo cloning), `secret-proxy-generic.nix` (Python proxy module)

**ovhModules** (OVH-only):
- `secrets-ovh-overrides.nix` -- currently empty (all contabo-only secrets are in contaboModules)

**contaboModules** (Contabo-only, NOT imported on OVH):
- claw-swap, restic, matrix, dm-guide, nginx, home-assistant, automaton, automaton-dashboard, openclaw, parts, neurosys-mcp, cachix-auth-token
- `services.secretProxy.services.claw-swap` declaration (port 9091)
- `services.dashboard.extraManifests."neurosys-dev"` (pulls OVH manifest into Contabo dashboard)

### What OVH Currently Has

| Component | Status | Notes |
|-----------|--------|-------|
| NixOS gen-3 | Running | impermanence + btrfs subvols |
| Tailscale | Connected | `neurosys-dev` / `100.113.72.9` |
| SSH | Public (port 22 open) | Key-only, OVH-01 decision |
| Syncthing | Running | Real device IDs, sync folder |
| Docker | Running | iptables=false, NAT configured |
| agent-compute | Installed | claude-code, codex, opencode, gemini-cli, pi, zmx |
| Podman | Enabled | Rootless, for sandbox workflows |
| Agent cgroup slice | Configured | CPUWeight 100, TasksMax 4096 |
| secret-proxy module | Imported | Python version (`secret-proxy-generic.nix`) -- but NO services declared |
| Repos | Minimal | Only 7 repos in current `repos.nix` |
| Dashboard | Entries only | No dashboard service on OVH (dashboard.enable not set) |
| Impermanence | Active | /persist, /home/dangirsh, /data, etc. |

### What OVH Is Missing for Dev Workflow

| Gap | What's Needed | Where |
|-----|---------------|-------|
| Secret-proxy for dev agents | Declare `services.secretProxy.services.dev` with anthropic-api-key | ovhModules or inline in private flake |
| Real API keys in OVH sops | `anthropic-api-key` in `secrets/ovh.yaml` appears to be a placeholder (12 bytes encrypted) | Requires sops edit |
| Comprehensive repo list | Only 7 repos cloned; need ~15 from acfs `/data/projects/` | Private `repos.nix` |
| agentic-dev-base activation | Already in home/agentic-dev-base.nix (symlinks), needs agentic-dev-base repo in clone list | repos.nix |
| bwrap env injection | Agent sandbox must get `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>` | secret-proxy bwrapArgs |
| Deploy health checks | `deploy.sh` checks only syncthing + tailscaled for OVH; add secret-proxy | deploy.sh |

---

## Key Architecture Decisions

### 1. Secret-Proxy Wiring for OVH Dev Agents

**Decision (locked):** Wire Phase 66 generic secret-proxy module so dev agents use placeholder keys + proxy.

**Current state:** The private overlay imports `./modules/secret-proxy-generic.nix` (Python version) in commonModules. This module defines `services.secretProxy.services` option. The Contabo host uses it for claw-swap (port 9091). OVH imports the module but has zero service declarations.

**Implementation path:**
- Add a `services.secretProxy.services.dev` declaration to ovhModules (inline in flake.nix or in a new `modules/dev-proxy.nix`)
- Configuration: port (e.g., 9092 to avoid collision if both hosts share module code), placeholder `sk-ant-placeholder-dev`, baseUrlEnvVar = `ANTHROPIC_BASE_URL`, secret = anthropic-api-key from OVH sops
- The `bwrapArgs` output (`["--setenv" "ANTHROPIC_BASE_URL" "http://127.0.0.1:9092"]`) can be consumed by agent-spawn or manual bwrap invocations

**Port choice:** Contabo uses 9091 for claw-swap. OVH can use 9091 (no collision -- different host) or a different port for clarity. Recommendation: use 9091 on OVH too since there's no claw-swap on OVH.

### 2. OVH Sops Secrets Status

**Finding:** The `anthropic-api-key` in `secrets/ovh.yaml` encrypts to only ~12 bytes (`fVYx/kiK6HvSmyw=`). Real Anthropic API keys are 100+ characters. This is likely a placeholder.

**Action needed:** Before deploy, the real `anthropic-api-key` must be injected into `secrets/ovh.yaml`:
```bash
cd /data/projects/private-neurosys
sops --set '["anthropic-api-key"] "sk-ant-api03-..."' secrets/ovh.yaml
```

Other keys that dev agents might need: `openai-api-key`, `google-api-key`, `xai-api-key`, `openrouter-api-key`. These should also be verified/populated.

### 3. Repo List for OVH

**Current repos.nix** (private overlay, shared by both hosts):
```
dangirsh/parts
dangirsh/claw-swap
dangirsh/global-agent-conf
dangirsh/dangirsh.org
dangirsh/conway-dashboard
dangirsh/agentic-dev-base
dangirsh/logseq-agent-suite
```

**Repos on acfs `/data/projects/`** (excluding archive and others):
```
agentic-dev-base       -> dangirsh/agentic-dev-base        (already in repos.nix)
claw-swap              -> dangirsh/claw-swap                (already in repos.nix)
conway                 -> dangirsh/conway
conway-dashboard       -> dangirsh/conway-dashboard         (already in repos.nix)
dangirsh-site          -> dangirsh/dangirsh.org             (already in repos.nix)
home-assistant-config  -> dangirsh/home-assistant-config    (uses SSH remote)
lobster-farm           -> dangirsh/lobster-farm
logseq-agent-suite     -> dangirsh/logseq-agent-suite       (already in repos.nix)
mission-control        -> (no remote)
neurosys               -> dangirsh/neurosys
parts                  -> dangirsh/parts                    (already in repos.nix)
private-neurosys       -> dangirsh/neurosys-private
spacebot               -> spacedriveapp/spacebot
worldcoin-ai           -> worldcoin/ai
```

**Repos to ADD to repos.nix for OVH:**
```
dangirsh/conway
dangirsh/lobster-farm
dangirsh/neurosys
dangirsh/neurosys-private
dangirsh/home-assistant-config
spacedriveapp/spacebot
worldcoin/ai
```

**Note:** `mission-control` has no remote and `global-agent-conf` is already in the list. The `home-assistant-config` repo uses an SSH remote (`git@github.com:...`) but clone-repos uses HTTPS + token. The activation script would need to clone via HTTPS URL instead: `dangirsh/home-assistant-config`.

**Design choice:** Make repos.nix per-host or keep one shared list. Recommendation: make repos configurable per host since Contabo doesn't need all dev repos and OVH doesn't need claw-swap source. Options:
1. **Per-host repos lists in host default.nix** -- simple, explicit
2. **repos.nix with conditional** -- check hostname, different lists
3. **Move OVH repos to ovhModules** -- cleanest separation

Recommendation: option 3 (inline repos in ovhModules or a dedicated `modules/repos-dev.nix`).

### 4. Private Overlay Config Structure Changes

**Files to modify:**

| File | Change |
|------|--------|
| `flake.nix` | Add secret-proxy-dev declaration to ovhModules |
| `modules/repos.nix` or new file | Expand repo list for OVH (option: per-host repos) |
| `secrets/ovh.yaml` | Populate real API keys |
| `hosts/ovh/default.nix` | No changes needed (inherits from commonModules) |

**Files NOT to modify:**
- `flake.nix` commonModules -- secret-proxy-generic.nix is already imported
- Public repo modules -- no changes needed in the public neurosys repo
- `modules/agent-compute.nix` -- already correct (dangirsh user, linger, CLI packages)

### 5. Python vs Rust Secret Proxy

**Current state:** Private overlay uses Python `secret-proxy-generic.nix`. Public repo has Rust `modules/secret-proxy.nix`. Phase 68 plans to converge to Rust.

**For Phase 69:** Use the existing Python proxy. Phase 69 depends on Phase 66 (which delivered the generic module interface), NOT Phase 68 (which extracts to standalone flake). The Python proxy is tested and deployed on Contabo -- it works. Adding a second service declaration for OVH dev agents is trivial with the existing module.

**No risk:** The Python and Rust modules define the same NixOS option interface (`services.secretProxy.services`). When Phase 68 converges to Rust, the service declarations don't change -- only the underlying binary switches.

### 6. Dashboard Cross-Host Visibility

**Current state:** Contabo already pulls OVH's dashboard manifest:
```nix
services.dashboard.extraManifests."neurosys-dev" =
  self.nixosConfigurations.ovh.config.environment.etc."dashboard/manifest.json".text;
```

This means any new services on OVH (e.g., `secret-proxy-dev`) will automatically appear in the Contabo dashboard. No additional work needed.

**Discretion item:** Whether to update the Contabo dashboard to show OVH agent status. Answer: it already does this via the manifest merge. New dashboard entries from `services.dashboard.entries.*` on OVH will appear on the Contabo dashboard automatically.

---

## Risk Analysis

### Low Risk
- **Module wiring:** The secret-proxy module is already imported on OVH. Adding a service declaration is 10 lines of Nix.
- **Repo cloning:** Activation script pattern is proven (used on both hosts today). Adding repos to the list is mechanical.
- **Deploy pipeline:** `deploy.sh --node ovh` works today. No changes to deploy mechanism needed.

### Medium Risk
- **OVH sops secrets may be placeholders:** The `anthropic-api-key` in OVH sops appears to be a placeholder (very short encrypted value). If other keys are also placeholders, they must all be populated before the secret-proxy can function. This is a manual sops edit step.
- **Impermanence persistence:** `/data/projects` is persisted via `/data` in impermanence.nix. New repo clones will survive reboots. But if the OVH host hasn't been rebooted since gen-3 install, there could be stale state. The deploy-on-top approach (not wiping) mitigates this.

### Low-Medium Risk
- **home-assistant-config repo** uses SSH remote (`git@github.com:...`) on acfs but the clone script uses HTTPS + token. Must use HTTPS URL in repos list.
- **mission-control has no remote** -- cannot be cloned via activation script. Must be created manually or skipped.

---

## Implementation Sequence

### Plan 1: Config Changes (private overlay)
1. Populate real API keys in `secrets/ovh.yaml` (sops edit)
2. Add `services.secretProxy.services.dev` to ovhModules in private flake.nix
3. Expand repo list for OVH (either in repos.nix with per-host logic or new ovh-specific module)
4. Verify with `nix flake check` in private overlay
5. Commit all changes

### Plan 2: Deploy and Validate
1. Deploy to OVH: `./scripts/deploy.sh --node ovh`
2. Verify services: `ssh root@neurosys-dev systemctl status secret-proxy-dev`
3. Verify repos: `ssh root@neurosys-dev ls /data/projects/`
4. Verify secret-proxy responds: `ssh root@neurosys-dev curl -s http://127.0.0.1:9091/`
5. Run acceptance test: SSH in as dangirsh, start sandboxed Claude Code session
6. Verify Contabo dashboard shows OVH entries

### Plan 3: Live Tests and Cleanup
1. Add OVH-specific live test assertions (secret-proxy, repos, agent sandbox)
2. Update eval checks for new OVH services
3. Run full test suite against both hosts
4. Update STATE.md, ROADMAP.md

---

## Detailed Findings

### Secret-Proxy Module Interface

The `services.secretProxy.services.<name>` submodule accepts:

```nix
{
  port = <port>;           # Loopback port (127.0.0.1 only)
  placeholder = "sk-...";  # Placeholder token for agent env
  baseUrlEnvVar = "ANTHROPIC_BASE_URL";  # Env var name
  secrets.<secretName> = {
    headerName = "x-api-key";     # HTTP header to inject
    secretFile = <path>;           # Runtime path to real key
    allowedDomains = ["api.anthropic.com"];  # Upstream domain
  };
}
```

The module generates:
- `systemd.services.secret-proxy-<name>` -- proxy process
- `users.users.secret-proxy-<name>` -- dedicated system user
- `config.bwrapArgs` -- read-only computed list for sandbox env injection

### OVH Dev Proxy Declaration (recommended)

```nix
# In ovhModules list in private flake.nix
({ config, ... }: {
  services.secretProxy.services.dev = {
    port = 9091;
    placeholder = "sk-ant-placeholder-dev-xxxxxxxxxxxxxxxx";
    baseUrlEnvVar = "ANTHROPIC_BASE_URL";
    secrets.anthropic-api-key = {
      headerName = "x-api-key";
      secretFile = config.sops.secrets."anthropic-api-key".path;
      allowedDomains = [ "api.anthropic.com" ];
    };
  };
})
```

### Repo List Expansion (recommended)

Current `modules/repos.nix` is shared by both hosts. Options:

**Option A: Per-host conditional in repos.nix** (simplest, slightly ugly):
```nix
{ config, pkgs, ... }:
let
  baseRepos = [ ... ];  # shared
  devRepos = [ ... ];   # OVH-only
  allRepos = baseRepos ++ (if config.networking.hostName == "neurosys-dev" then devRepos else []);
in { ... }
```

**Option B: Separate repos module for OVH** (cleanest):
```nix
# In ovhModules:
({ config, pkgs, ... }: {
  system.activationScripts.clone-repos = {
    deps = [ "users" ];
    text = ''
      repos=(
        "dangirsh/neurosys"
        "dangirsh/neurosys-private"
        "dangirsh/parts"
        "dangirsh/claw-swap"
        "dangirsh/lobster-farm"
        "dangirsh/conway"
        "dangirsh/conway-dashboard"
        "dangirsh/dangirsh.org"
        "dangirsh/home-assistant-config"
        "dangirsh/agentic-dev-base"
        "dangirsh/logseq-agent-suite"
        "dangirsh/global-agent-conf"
        "spacedriveapp/spacebot"
        "worldcoin/ai"
      )
      ...
    '';
  };
})
```

**Issue:** NixOS activation scripts merge by name. If both repos.nix and the inline module define `system.activationScripts.clone-repos`, only one wins (or they concatenate depending on merge semantics). The safe approach is either:
- Remove repos.nix from commonModules and put host-specific repos inline in each host config
- Use a different activation script name for OVH-extra repos

**Recommendation:** Option B with the existing repos.nix providing the base list and an additional `clone-dev-repos` activation script for OVH-specific repos, OR replace repos.nix entirely with per-host inline declarations.

### Deploy Health Check Updates

Current OVH health checks in deploy.sh:
```bash
SYSTEMD_SERVICES=("syncthing" "tailscaled")
```

Should add after Phase 69:
```bash
SYSTEMD_SERVICES=("syncthing" "tailscaled" "secret-proxy-dev")
```

### Eval Test Updates

Add to `private-checks.nix`:
```nix
secret-proxy-dev-service = mkCheck
  "secret-proxy-dev-service"
  "secret-proxy-dev service is defined in OVH config"
  "secret-proxy-dev service is missing"
  (builtins.hasAttr "secret-proxy-dev" ovhCfg.systemd.services);
```

### Live Test Updates

Add to live test suite (neurosys-dev host):
```bash
@test "neurosys-dev: secret-proxy-dev is active" {
  if ! is_ovh; then skip "OVH only"; fi
  remote systemctl is-active --quiet secret-proxy-dev.service
}

@test "neurosys-dev: secret-proxy-dev responds on port 9091" {
  if ! is_ovh; then skip "OVH only"; fi
  assert_http_responds "http://localhost:9091"
}

@test "neurosys-dev: all dev repos are cloned" {
  if ! is_ovh; then skip "OVH only"; fi
  for repo in neurosys private-neurosys parts claw-swap lobster-farm; do
    remote test -d "/data/projects/$repo"
  done
}
```

---

## Pre-Deploy Checklist

Before executing Phase 69:

1. **Verify OVH SSH access:** `ssh root@neurosys-dev hostname` returns `neurosys-dev`
2. **Verify Tailscale is up:** `ssh root@neurosys-dev tailscale status` shows connected
3. **Populate real API keys:** Edit `secrets/ovh.yaml` with sops -- at minimum `anthropic-api-key`, optionally all other API keys
4. **Verify sops decryption on OVH:** After deploy, `ssh root@neurosys-dev cat /run/secrets/anthropic-api-key` returns a real key
5. **Private overlay evaluates cleanly:** `cd /data/projects/private-neurosys && nix flake check`

---

## Open Questions (Discretion Items)

### Q1: Should the repo list be per-host or one shared list?
**Recommendation:** Per-host. Move OVH repos to ovhModules (inline or new file). Contabo repos stay in repos.nix (which is in commonModules but could be moved to contaboModules). The two hosts have fundamentally different purposes -- services vs dev -- so their repo needs diverge.

### Q2: What port for OVH dev secret-proxy?
**Recommendation:** 9091 (same as Contabo claw-swap). No collision risk -- different hosts. Keeps mental model simple. The service is named `secret-proxy-dev` (not `secret-proxy-claw-swap`) so there's no naming confusion.

### Q3: Should we add multiple secret-proxy services on OVH (one per API provider)?
**Recommendation:** Start with one (Anthropic) since that's the primary agent provider. Add OpenAI, Google, etc. later if dev agents need them. The module supports multiple services trivially.

### Q4: How to handle `mission-control` (no git remote)?
**Recommendation:** Skip it. If the user needs it on OVH, they can create it manually or add a remote first. Don't block the migration on one repo with no remote.

### Q5: Update deploy.sh health checks?
**Recommendation:** Yes, add `secret-proxy-dev` to OVH's SYSTEMD_SERVICES list. This is a one-line change in the deploy script's node-specific section.

---

*Research completed: 2026-03-08*
*Confidence: HIGH*
*Estimated plans: 2-3 (config + deploy/validate + tests)*
