# Extras

`extras/` holds reusable modules built on top of the public core. All extras
are opt-in: import the module in your host config and set the enable option.

## Shipped Extras

| Path | Enable / import | What it adds | Notes |
|------|-----------------|--------------|-------|
| `extras/cass.nix` | Import + `services.cassIndexer.enable = true` | Low-priority system timer that refreshes the CASS session index | Runs as the dedicated agent user with CPU/memory throttling |
| `extras/codex.nix` | `services.codexAgent.enable = true` | Optional sandboxed `codex` wrapper | Requires `agentLauncher` and `nonoSandbox`; defaults to the `openai-api-key` secret and isolated `/home/agent/.codex-openai` state |
| `extras/codex-openrouter.nix` | `services.codexOpenRouterAgent.enable = true` | Optional OpenRouter-backed `codex-openrouter` wrapper | Defaults to `z-ai/glm-5.2` through the `openrouter-api-key` secret |
| `extras/restic.nix` | `services.resticStarter.enable = true` | Restic backups to a Backblaze B2 S3 endpoint | Requires `services.resticStarter.repository`; declares its own B2/restic SOPS secrets and environment template when enabled |
| `extras/home/` | `home-manager.users.<name> = import ../../extras/home;` | Home-manager profile for the agent user | Installs git, gh, ssh, and direnv defaults |

## OpenRouter Codex

Import `extras/codex-openrouter.nix` on an agent host to expose a sandboxed
`codex-openrouter` wrapper. The wrapper uses nono's credential proxy, so Codex
receives only `NONO_PROXY_TOKEN` and a local `OPENROUTER_BASE_URL`, while the
raw OpenRouter key remains in the root-owned `openrouter-api-key` secret.
Current Codex releases use the Responses API provider wire format here, so the
wrapper explicitly targets OpenRouter's `/api/v1/responses` endpoint.
The wrapper also runs Codex with `CODEX_HOME` set to
`/home/agent/.codex-openrouter`, keeping OpenRouter runs isolated from any
normal `/home/agent/.codex` ChatGPT subscription state.

```nix
{
  imports = [ ./extras/codex-openrouter.nix ];

  services.codexOpenRouterAgent = {
    enable = true;
    model = "z-ai/glm-5.2";
  };
}
```

## OpenAI Codex

Import `extras/codex.nix` to expose a sandboxed `codex` wrapper backed by the
brokered `openai-api-key` secret. The wrapper sets `CODEX_HOME` to
`/home/agent/.codex-openai`; the default `/home/agent/.codex` ChatGPT
subscription cache remains denied by the base nono profile and should not be
mounted into prompt-controlled runs.

```nix
{
  imports = [ ./extras/codex.nix ];

  services.codexAgent.enable = true;
}
```

## Home Profile

`extras/home/default.nix` is a default home-manager profile available for
private overlays to import. It provides:

- git with placeholder identity that private overlays should replace
- GitHub CLI with auth left to runtime credentials
- SSH client defaults with multiplexing enabled
- `direnv` + `nix-direnv`
- a clean place for private overlays to layer `agentic-dev-base` and project-specific config

## Extending tsurf: Custom Agents

Public extras are not the only extension point. The advanced extension API is
`services.agentLauncher.agents.<name>`, which powers custom wrappers on top of
the generic launcher path. `extras/codex.nix` is a real-world example built on
this same API.

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
