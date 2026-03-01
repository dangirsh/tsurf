# Phase 48 Research: Test Automation Infrastructure

## 1. Test Categories and What Each Validates

### Category A: Static Config Evaluation Tests (no VM, no SSH, no secrets)

Tests that validate NixOS configuration correctness by evaluating the flake and inspecting the resulting NixOS system derivation. These run purely in the Nix evaluator/builder -- no QEMU, no SSH, no live host needed.

**What they validate:**
- All `nixosConfigurations` evaluate without errors (both `neurosys` and `ovh`)
- NixOS module assertions pass (e.g., the `internalOnlyPorts` firewall assertion in `networking.nix`)
- Expected systemd services are defined in the config
- Expected packages are in `environment.systemPackages`
- Expected firewall rules, ports, trusted interfaces are configured
- sops secret declarations exist (not their values -- those require the age key)
- `home-manager` config evaluates successfully
- `agentd` option schema validates (duplicate proxy port assertion, custom harness assertion)
- `impermanence.nix` persisted paths include all critical directories
- Boot config (GRUB, initrd modules) is correct per host
- disko partition layout is correct per host

**Framework:** `nix eval` / `nix build` with custom check derivations in `flake.nix` `checks` output. No KVM required.

**Advantage:** These catch ~70% of NixOS config bugs (typos, missing imports, assertion violations, type errors). Fast, deterministic, agent-runnable.

### Category B: Build Tests (derivation builds succeed)

Tests that the NixOS system closure and custom packages actually build.

**What they validate:**
- `nixosConfigurations.neurosys.config.system.build.toplevel` builds
- `nixosConfigurations.ovh.config.system.build.toplevel` builds
- Custom packages build: `neurosys-mcp`, `zmx`, `cass`, `beads`, `automaton`
- deploy-rs activation scripts build

**Framework:** `nix build` / `nix flake check`. Already partially covered by the existing deploy-rs checks.

**Note:** Full system builds are expensive (10+ min). Eval-only tests (Category A) catch most errors faster.

### Category C: Live Service Health Tests (SSH to running hosts)

Tests that run against live hosts via SSH (Tailscale) and verify services are healthy.

**What they validate:**
- systemd units are active/running (not failed)
- Service ports respond (HTTP health endpoints)
- Prometheus is scraping targets and alert rules are loaded
- Docker containers are running
- Tailscale is connected and hostname resolves
- sops secrets were decrypted (files exist in `/run/secrets/` with correct permissions)
- Impermanence mounts are in place (`/persist` subvolume mounted)
- Restic backup timer exists and last run timestamp is fresh

**Framework:** BATS (Bash Automated Testing System) executing via SSH. TAP output for structured results.

**Target hosts:** `neurosys` (Contabo) and `neurosys-prod` (OVH) via Tailscale MagicDNS.

### Category D: Live API Tests (curl/HTTP against running services)

Tests that hit HTTP endpoints on live hosts and validate responses.

**What they validate:**
- Prometheus `/api/v1/targets` returns expected scrape targets
- Prometheus `/-/healthy` returns 200
- Homepage dashboard responds on port 8082
- agentd API proxy responds on ports 9201-9204 (`/v1/agents`)
- neurosys-mcp `/mcp` endpoint responds on port 8400
- Secret proxy on port 9091 responds (without leaking the real key)
- Syncthing GUI responds on port 8384
- Home Assistant responds on port 8123
- nginx vhosts return expected status codes (dangirsh.org, claw-swap.com)
- OpenClaw container ports respond (18789-18792)
- Spacebot health endpoint (`/api/health` on 19898)
- Matrix/Conduit federation-disabled check on port 6167

**Framework:** BATS with `curl` assertions, or a lightweight Python test runner.

### Category E: Security Boundary Tests (live)

Tests that verify security properties are maintained.

**What they validate:**
- Public firewall does NOT respond on internal-only ports from outside Tailscale
- SSH rejects password auth
- SSH only accepts ed25519 host key
- Metadata endpoint (169.254.169.254) is blocked from the host
- Docker `--iptables=false` is set (Docker is not managing firewall)
- Kernel sysctl hardening values are set (`dmesg_restrict`, `kptr_restrict`, etc.)
- bubblewrap sandbox env does NOT have `/run/secrets` visible
- bubblewrap sandbox env does NOT have `~/.ssh` visible
- Agent sandbox `SANDBOX=1` env var is set when sandboxed

**Framework:** BATS via SSH, plus `nmap`/`nc` probing from the test machine.

### Category F: Private Overlay Tests (eval + live)

Tests specific to the private overlay (`private-neurosys`).

**What they validate:**
- Private `nixosConfigurations` evaluate without errors
- `disabledModules` + replacements compose correctly (no duplicate option errors)
- Agent fleet declarations (4 agents with correct ports 9201-9204)
- nginx vhost config generates valid config (dangirsh.org, claw-swap.com, staging)
- ACME cert declarations exist for all domains
- OpenClaw container declarations (4 instances, correct port mappings)
- Matrix/Conduit + bridge declarations (3 bridges)
- sops secrets from both `neurosys.yaml` and `ovh.yaml` are referenced correctly

**Framework:** Mix of `nix eval` (Category A style) and live tests (Category C/D style).


## 2. Framework Selection

### Recommended: Two-layer approach

#### Layer 1: Nix-native eval checks (Categories A, B, F-eval)

**Implementation:** Add custom `checks.${system}` derivations to `flake.nix` that evaluate config properties.

```nix
checks.${system} = {
  # Existing deploy-rs checks
  # ...

  # Custom eval checks
  eval-neurosys = pkgs.runCommandNoCC "eval-neurosys" {} ''
    # This derivation succeeds only if the config evaluates
    echo "${self.nixosConfigurations.neurosys.config.system.build.toplevel}" > $out
  '';

  config-assertions = pkgs.runCommandNoCC "config-assertions" {
    configJson = builtins.toJSON {
      firewall-ports = self.nixosConfigurations.neurosys.config.networking.firewall.allowedTCPPorts;
      trusted-interfaces = self.nixosConfigurations.neurosys.config.networking.firewall.trustedInterfaces;
      # ... more config properties to check
    };
    passAsFile = [ "configJson" ];
  } ''
    # Shell script that parses JSON and asserts expected values
    ${pkgs.jq}/bin/jq ... < $configJsonPath
    touch $out
  '';
};
```

**Pros:**
- Runs via `nix flake check` -- agents already know this command
- No KVM required
- Catches eval errors, assertion failures, type errors
- Deterministic, reproducible
- Fast (~seconds for eval-only, minutes for build)

**Cons:**
- Cannot test runtime behavior
- Cannot test secret decryption (no age key in builder sandbox)
- Limited to config properties accessible via `config.*` attribute paths

#### Layer 2: BATS live tests (Categories C, D, E, F-live)

**Implementation:** A `tests/` directory with BATS test files, invocable via `nix run .#test-live` or directly.

```bash
# tests/live/service-health.bats
@test "prometheus is active" {
  run ssh root@neurosys systemctl is-active prometheus.service
  [ "$status" -eq 0 ]
  [ "$output" = "active" ]
}

@test "prometheus healthy endpoint" {
  run ssh root@neurosys curl -sf http://localhost:9090/-/healthy
  [ "$status" -eq 0 ]
}
```

**Pros:**
- Natural for infrastructure testing (SSH + curl + systemctl)
- TAP output is structured, machine-parseable
- bats-core has `bats-support` and `bats-assert` helper libraries
- Agents can read PASS/FAIL per test with clear error messages
- Available in nixpkgs as `pkgs.bats` with `pkgs.bats.libraries.bats-support` and `pkgs.bats.libraries.bats-assert`
- No KVM required -- just SSH access

**Cons:**
- Requires live hosts reachable via Tailscale
- Tests are not hermetic (depend on host state)
- Cannot test "from scratch" deployment scenarios

### Why NOT NixOS VM tests (nixos-test):

- **No KVM on Contabo VPS** -- the primary test runner location
- QEMU software emulation is ~10x slower
- VMs cannot test the actual sops secrets (need real age key)
- VMs cannot test Docker container images (need network/registry access)
- VMs cannot test Tailscale connectivity
- VMs are great for testing module composition in isolation, but this project's value is in testing the DEPLOYED system
- Could be added later for CI (GitHub Actions has KVM) but is NOT Plan 1

### Why NOT pytest:

- Adds Python dependency complexity for what is fundamentally SSH + curl + jq testing
- BATS is more natural for infrastructure ops testing
- BATS TAP output is simpler to parse than pytest output
- The neurosys-mcp server already has Python, but the test infra should be bash-native


## 3. Repo Structure

```
tests/
  README.md              # How to run tests, what each suite covers
  lib/
    common.bash          # Shared helpers: SSH wrappers, retry logic, host vars
  eval/
    config-checks.nix    # Nix expressions that inspect config properties
    module-assertions.nix # Tests for custom assertion behavior
  live/
    service-health.bats  # systemd unit health for both hosts
    api-endpoints.bats   # HTTP endpoint checks
    security.bats        # Firewall, SSH hardening, sandbox boundaries
    secrets.bats         # Secret decryption verification (existence + permissions)
    monitoring.bats      # Prometheus scrape targets, alert rules
    agentd.bats          # agentd API proxy, jcard generation
    impermanence.bats    # Persist mounts, boot rollback state
    networking.bats      # Firewall rules, Tailscale, DNS
  private/
    overlay-eval.nix     # Private overlay eval tests (lives in private repo)
    private-services.bats # Tests for nginx, openclaw, matrix, etc.

flake.nix additions:
  checks.${system}.eval-neurosys    # Config evaluates
  checks.${system}.eval-ovh         # OVH config evaluates
  checks.${system}.config-checks    # Property assertions
  checks.${system}.shellcheck-tests # Lint the BATS test files
  packages.${system}.test-live      # BATS runner wrapped with dependencies
  apps.${system}.test-live          # `nix run .#test-live` entry point
```

### Invocation patterns:

```bash
# Static eval tests (no SSH needed, no KVM)
nix flake check

# Live tests against neurosys (Contabo)
nix run .#test-live -- --host neurosys

# Live tests against ovh (OVH)
nix run .#test-live -- --host ovh

# Run specific test file
nix run .#test-live -- tests/live/service-health.bats

# Run from the tests directory directly (if bats is in PATH)
bats tests/live/service-health.bats
```

### Private overlay test structure:

The private repo (`private-neurosys`) would add its own `tests/private/` directory and extend the flake checks. Since the private repo has full access to the public modules, it can test the composed system.


## 4. Highest-Value Tests per Component

### Tier 1: Catch-on-every-commit (eval checks, `nix flake check`)

| Component | Test | Value |
|-----------|------|-------|
| All configs | Both `nixosConfigurations` evaluate | Catches ~70% of NixOS config bugs |
| networking.nix | `internalOnlyPorts` assertion fires when port leaked | Prevents accidental public exposure |
| agentd.nix | Duplicate proxy port assertion fires | Prevents port collision |
| agentd.nix | Custom harness requires command assertion fires | Prevents broken agent service |
| firewall | `allowedTCPPorts` contains exactly [22, 80, 443, 22000] | Prevents firewall drift |
| firewall | `trustedInterfaces` contains `tailscale0` and `docker0` | Ensures internal services reachable |
| impermanence | All critical paths listed in persist dirs | Prevents data loss on reboot |
| packages | neurosys-mcp, zmx build successfully | Catches upstream breakage |
| deploy-rs | Deploy checks pass | Validates activation scripts |

### Tier 2: Pre-deploy verification (live tests, `nix run .#test-live`)

| Component | Test | Value |
|-----------|------|-------|
| systemd | All expected units active (no failed units) | Broadest health signal |
| sops-nix | `/run/secrets/` files exist with correct owner/permissions | Secrets decryption working |
| Prometheus | `/-/healthy` returns 200 | Monitoring operational |
| Prometheus | `/api/v1/targets` shows node-exporter UP | Scraping working |
| Prometheus | Alert rules loaded (query `/api/v1/rules`) | Alerting configured |
| node-exporter | Port 9100 responds with metrics | Metrics collection working |
| Homepage | Port 8082 returns 200 | Dashboard operational |
| agentd | Each proxy port (9201-9204) returns `/v1/agents` JSON | Agent fleet accessible |
| Tailscale | `tailscale status` shows connected | VPN operational |
| Docker | All expected containers running | Container services healthy |
| SSH | Password auth rejected | Security boundary |
| Firewall | Internal ports not reachable from public IP | Security boundary |
| Impermanence | `/persist` mounted, `/` is ephemeral btrfs | Rollback mechanism working |

### Tier 3: Deep validation (extended live tests)

| Component | Test | Value |
|-----------|------|-------|
| restic | Backup timer exists, last run < 36h ago | Backup freshness |
| kernel sysctl | `dmesg_restrict=1`, `kptr_restrict=2`, etc. | Hardening verified |
| metadata block | `curl 169.254.169.254` fails | Cloud metadata protection |
| Secret proxy | Port 9091 proxies without exposing real key | Proxy function verified |
| neurosys-mcp | `/mcp` endpoint returns FastMCP response | MCP server operational |
| Syncthing | Port 8384 responds | Sync operational |
| bwrap sandbox | `/run/secrets` not visible inside sandbox | Secret isolation |
| Home Assistant | Port 8123 returns HA API | HA operational |

### Tier 4: Private overlay (private repo tests)

| Component | Test | Value |
|-----------|------|-------|
| nginx | dangirsh.org returns 200 over HTTPS | Public site operational |
| nginx | claw-swap.com proxies to port 3000 | App proxy working |
| ACME | All 4 cert domains have valid certs | TLS operational |
| OpenClaw | 4 containers running on 18789-18792 | Gateway fleet healthy |
| Matrix/Conduit | Port 6167 responds, federation disabled | Homeserver operational |
| mautrix bridges | 3 bridge services active | Bridges operational |
| Agent fleet | 4 agents declared with correct workdirs | Fleet config correct |


## 5. Plan Scope: Plan 1 vs Plan 2

### Plan 1: Foundation + Tier 1 + Tier 2 (highest-value, fastest ROI)

**Scope:**
1. Create `tests/` directory structure with `lib/common.bash` helpers
2. Add Nix eval checks to `flake.nix` `checks` output:
   - Config evaluation for both hosts
   - Firewall port assertions (test that the assertion mechanism works)
   - Expected services list check
   - Expected packages check
   - Impermanence critical paths check
3. Create BATS live test suite with:
   - `service-health.bats` -- systemd unit checks for both hosts
   - `api-endpoints.bats` -- HTTP endpoint health checks
   - `security.bats` -- SSH hardening, firewall boundary, kernel sysctl
   - `secrets.bats` -- secret file existence and permissions
4. Create `nix run .#test-live` wrapper with proper dependencies
5. Create `tests/README.md` with agent-runnable instructions
6. Add shellcheck linting for BATS files as a flake check

**Deliverables:**
- `nix flake check` catches eval/config errors (expanded from current deploy-rs-only checks)
- `nix run .#test-live -- --host neurosys` runs full live test suite
- TAP output gives agents PASS/FAIL per test with clear error context
- Estimated: 15-20 eval checks + 30-40 live tests

### Plan 2: Tier 3 + Tier 4 + Agent Integration Polish

**Scope:**
1. Deep validation tests:
   - `monitoring.bats` -- Prometheus scrape targets, alert rules, retention config
   - `agentd.bats` -- detailed agentd API testing, jcard validation
   - `impermanence.bats` -- mount verification, persist path completeness
   - `networking.bats` -- Tailscale status, DNS resolution, nftables rules
   - `sandbox.bats` -- bubblewrap isolation verification
2. Private overlay test framework:
   - `tests/private/overlay-eval.nix` in private repo
   - `tests/private/private-services.bats` for nginx, openclaw, matrix
3. Agent integration polish:
   - Structured JSON output mode (in addition to TAP)
   - Test result summary suitable for agent consumption
   - Integration with `.claude/.test-status` for the guard hook
4. CI integration guide (GitHub Actions with KVM for VM tests, if desired later)

**Deliverables:**
- 20-30 additional deep tests
- Private overlay test harness
- Agent-optimized output format
- Guard hook integration


## 6. How Agents Run Tests and Interpret Output

### Running static checks:

```bash
# Agent runs:
nix flake check 2>&1

# Output interpretation:
# - Exit 0 = all checks pass
# - Exit 1 = shows which check failed with error message
# - NixOS assertion failures show the assertion message text
```

### Running live tests:

```bash
# Agent runs:
nix run .#test-live -- --host neurosys 2>&1

# BATS TAP output format:
# 1..42
# ok 1 prometheus is active
# ok 2 prometheus healthy endpoint
# not ok 3 homepage responds on 8082
# # (in test file tests/live/api-endpoints.bats, line 15)
# #   `[ "$status" -eq 0 ]' failed
# #   status: 7 (couldn't connect to host)
# ok 4 ssh rejects password auth
# ...
# 41 tests, 1 failure

# Agent interprets:
# - "ok N" = PASS
# - "not ok N" = FAIL, with error context indented below
# - Summary line at end: "N tests, M failures"
# - Exit code: 0 if all pass, 1 if any fail
```

### Integration with guard hook:

After tests pass, the agent writes the test-status file:

```bash
# After nix flake check passes:
echo "pass|0|$(date +%s)" > .claude/.test-status

# After live tests pass:
nix run .#test-live -- --host neurosys && echo "pass|0|$(date +%s)" > .claude/.test-status
```

### Agent error-correction workflow:

1. Agent runs `nix flake check` -- catches eval errors immediately
2. Agent fixes Nix config, re-runs `nix flake check`
3. After deploy, agent runs `nix run .#test-live -- --host neurosys`
4. BATS TAP output tells agent exactly which service/endpoint failed
5. Agent SSH-es to host, checks `journalctl -u <service>`, fixes config
6. Re-deploys, re-runs live tests
7. All tests pass -> writes `.test-status` -> commits

### Key design for agent feedback:

- **One test per assertion** -- never bundle multiple checks in one test (agents need to know WHICH thing failed)
- **Error context in test name** -- "homepage responds on 8082" not "test_3"
- **Failure output includes how to debug** -- e.g., "curl returned status 7 (connection refused)" not just "assertion failed"
- **Tests are idempotent** -- safe to run multiple times
- **Tests have no side effects** -- read-only queries, no state mutations


## 7. NixOS-Specific Testing Patterns

### Pattern 1: Config property extraction via `nix eval`

```nix
# Extract config values as JSON for shell-based assertions
checks.config-firewall = pkgs.runCommandNoCC "config-firewall" {
  nativeBuildInputs = [ pkgs.jq ];
} ''
  expected='[22,80,443,22000]'
  actual='${builtins.toJSON config.networking.firewall.allowedTCPPorts}'
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: allowedTCPPorts = $actual, expected $expected"
    exit 1
  fi
  touch $out
'';
```

### Pattern 2: Assertion testing with `builtins.tryEval`

To verify that NixOS assertions correctly REJECT bad configs:

```nix
# Test that adding port 9090 to allowedTCPPorts triggers the assertion
checks.assertion-internal-ports = let
  badConfig = nixpkgs.lib.nixosSystem {
    modules = commonModules ++ [{
      networking.firewall.allowedTCPPorts = [ 22 9090 ]; # 9090 is internal-only
    }];
  };
  result = builtins.tryEval (badConfig.config.system.build.toplevel);
in pkgs.runCommandNoCC "assertion-internal-ports" {} ''
  ${if result.success then ''
    echo "FAIL: config with port 9090 should have failed assertion"
    exit 1
  '' else ''
    echo "PASS: assertion correctly rejects internal port in allowedTCPPorts"
    touch $out
  ''}
'';
```

**Note:** `builtins.tryEval` does NOT catch assertion failures in NixOS (assertions are throw, which tryEval catches, but the error propagation behavior is nuanced). A more reliable pattern is to check the config properties directly rather than trying to provoke assertion failures.

### Pattern 3: systemd service existence check at eval time

```nix
# Verify expected services are defined in the config
checks.expected-services = let
  cfg = self.nixosConfigurations.neurosys.config;
  expectedServices = [
    "prometheus" "prometheus-node-exporter" "tailscaled"
    "syncthing" "homepage-dashboard" "docker"
  ];
  defined = builtins.attrNames cfg.systemd.services;
  missing = builtins.filter (s: !(builtins.elem s defined)) expectedServices;
in pkgs.runCommandNoCC "expected-services" {} ''
  ${if missing == [] then ''
    echo "PASS: all expected services defined"
    touch $out
  '' else ''
    echo "FAIL: missing services: ${builtins.concatStringsSep ", " missing}"
    exit 1
  ''}
'';
```

### Pattern 4: BATS test with SSH helper

```bash
# tests/lib/common.bash
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"

ssh_cmd() {
  local host="$1"; shift
  ssh $SSH_OPTS "root@${host}" "$@"
}

curl_host() {
  local host="$1"
  local url="$2"
  ssh_cmd "$host" "curl -sf --max-time 5 '$url'"
}

# tests/live/service-health.bats
load '../lib/common'

setup() {
  HOST="${NEUROSYS_TEST_HOST:-neurosys}"
}

@test "prometheus.service is active on $HOST" {
  run ssh_cmd "$HOST" "systemctl is-active prometheus.service"
  assert_success
  assert_output "active"
}
```

### Pattern 5: Nix wrapper for BATS with all dependencies

```nix
# Wrap bats with all needed tools in PATH
packages.test-live = pkgs.writeShellApplication {
  name = "test-live";
  runtimeInputs = with pkgs; [ bats openssh curl jq nmap ];
  text = ''
    HOST="''${1:-neurosys}"
    BATS_LIB_PATH="${pkgs.bats.libraries.bats-support}/share/bats"
    BATS_LIB_PATH="$BATS_LIB_PATH:${pkgs.bats.libraries.bats-assert}/share/bats"
    export BATS_LIB_PATH
    export NEUROSYS_TEST_HOST="$HOST"
    bats ${./tests/live}/*.bats
  '';
};
```

### Pattern 6: Private overlay extends public test suite

```nix
# In private-neurosys flake.nix
checks.${system} = {
  # Include all public checks
  inherit (inputs.neurosys.checks.${system})
    eval-neurosys eval-ovh config-checks;

  # Add private checks
  eval-private-neurosys = /* ... */;
  eval-private-ovh = /* ... */;
};

packages.${system}.test-live = /* extended BATS suite including private tests */;
```


## Constraints and Risks

1. **No KVM on Contabo** -- NixOS VM tests cannot run on the primary host. Not a blocker; eval checks + live BATS tests cover more ground for this project.

2. **Tailscale required for live tests** -- The test runner machine must be on the same Tailscale tailnet. Agents on neurosys/OVH can test localhost directly.

3. **sops secrets not available in Nix builder** -- Eval tests can verify secret DECLARATIONS exist, but cannot verify the encrypted values. Live tests verify decrypted files exist at `/run/secrets/`.

4. **Docker image pull in eval** -- Some services use OCI container images that are pulled at activation time, not build time. Eval tests can verify the container declaration exists but not that the image is valid.

5. **BATS test files must be `git add`-ed** -- Nix flakes only see tracked files. New test files must be staged before `nix flake check` sees them.

6. **Live tests are not hermetic** -- They depend on the current state of running hosts. A failed test might mean a broken service OR a network issue. The common.bash helpers should include retry logic and clear error messages distinguishing connectivity from service failures.


## RESEARCH COMPLETE
