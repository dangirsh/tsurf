# Private Overlay Template

Minimal starting point for a one-owner private `tsurf` deployment.

This template will not evaluate as-is. Replace placeholders, add real hardware
config, configure sops, and deploy from the private repo.

## Model

- `root`: operator, deploy user, secret owner, recovery path.
- `agent`: sandboxed execution user for agent wrappers. No `wheel`, no
  `docker`, no general root access.
- public `tsurf`: reusable modules, checks, and examples.
- private overlay: real hosts, secrets, domains, ACLs, apps, and deploy nodes.

## Setup Checklist

1. Copy this directory into a private repo.
2. Edit `flake.nix`: replace `github:your-org/tsurf`, host names, and `REPLACE`
   values.
3. Replace hardware and disk config under `hosts/example/`.
4. Generate the root SSH key:

   ```bash
   nix run /path/to/tsurf#tsurf-init -- --overlay-dir .
   ```

5. Replace `.sops.yaml` recipients and create an encrypted host secrets file.
6. Import secrets only after persisted SSH host keys and sops files are real.
7. Lock inputs and deploy:

   ```bash
   nix flake lock
   ./scripts/deploy.sh --node example --first-deploy
   ```

## Agent Hosts

Agent hosts import the public agent modules:

- `agent-compute`
- `agent-egress-proxy`
- `agent-launcher`
- `agent-sandbox`
- `nono`

The core interactive path is the sandboxed `claude` wrapper. Additional wrappers
are data entries under `services.agentLauncher.agents.<name>` or small private
modules that lower to that same shape.

Minimal custom agent:

```nix
{ pkgs, ... }:
{
  services.agentLauncher.agents.review = {
    command = "claude";
    package = pkgs.claude-code;
    wrapperName = "review";
    credentialServices = [ "anthropic" ];
    defaultArgs = [ "-p" "Review this repo for deployment risk." ];
  };
}
```

Use per-agent `nonoProfile.extraAllow` only for non-secret writable state the
agent genuinely needs. Keep raw provider keys root-owned and brokered through
Iron.

## Core Private Responsibilities

- Headscale domain, ACLs, DNS, subnet routers, and exposure policy.
- Harmonia signing/trust keys, cache host, and client allowlists.
- Provider secrets consumed by Iron.
- App vhosts, background jobs, and app-specific deploy scripts.
- File sync, Docker, home LAN policy, and project-specific dev environments.

## Validation

From the private overlay:

```bash
nix flake check --no-build --all-systems
./scripts/deploy.sh --node example
```

From the public base:

```bash
./scripts/run-tests.sh
```

See the public [`SECURITY.md`](../../SECURITY.md) for the detailed access model.
