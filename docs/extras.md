# Extras

`extras/` holds reusable modules built on top of the public core. The host
fixtures import `extras/cass.nix` by default; the other extras stay opt-in.

## Shipped Extras

| Path | Enable / import | What it adds | Notes |
|------|-----------------|--------------|-------|
| `extras/cass.nix` | Imported by default in the public host fixtures | Low-priority system timer that refreshes the CASS session index | Runs as the dedicated agent user with CPU/memory throttling |
| `extras/codex.nix` | `services.codexAgent.enable = true` | Optional sandboxed `codex` wrapper | Requires `agentLauncher` and `nonoSandbox`; defaults to the `openai-api-key` secret |
| `extras/cost-tracker.nix` | `services.costTracker.enable = true` | Timer-driven Anthropic/OpenAI cost fetcher | Providers are declared under `services.costTracker.providers` |
| `extras/restic.nix` | `services.resticStarter.enable = true` | Restic backups to a Backblaze B2 S3 endpoint | Expects the secrets/template wiring from `modules/secrets.nix` |
| `extras/home/` | `home-manager.users.<name> = import ../../extras/home;` | Home-manager profile for the agent user | Installs git, gh, ssh, and direnv defaults |

## Home Profile

`extras/home/default.nix` is the default home-manager profile used by the public
host fixtures. It provides:

- git with placeholder identity that private overlays should replace
- GitHub CLI with auth left to runtime credentials
- SSH client defaults with multiplexing enabled
- `direnv` + `nix-direnv`
- a clean place for private overlays to layer `agentic-dev-base` and project-specific config

## Custom Agents

Public extras are not the only extension point. The normal way to add more
wrappers is `services.agentLauncher.agents.<name>`.

Each definition can specify:

- the package and command to run
- the wrapper name to expose in `PATH`
- the credential tuples the root-owned launcher may read
- extra `nono` allow or deny entries
- default CLI arguments
- additional persisted files or directories under the agent home

See
[`examples/private-overlay/modules/code-review.nix`](../examples/private-overlay/modules/code-review.nix)
for a minimal scheduled-agent example built on the generic launcher.
