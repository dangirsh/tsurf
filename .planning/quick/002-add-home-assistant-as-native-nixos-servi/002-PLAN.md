---
phase: quick-002
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - modules/home-assistant.nix
  - modules/default.nix
autonomous: true
must_haves:
  truths:
    - "Home Assistant service starts and is reachable on port 8123"
    - "Home Assistant UI is accessible over Tailscale (tailnet-only, not public)"
    - "NixOS build succeeds with home-assistant module included"
  artifacts:
    - path: "modules/home-assistant.nix"
      provides: "Home Assistant NixOS service declaration"
      contains: "services.home-assistant"
    - path: "modules/default.nix"
      provides: "Module import list including home-assistant"
      contains: "./home-assistant.nix"
  key_links:
    - from: "modules/default.nix"
      to: "modules/home-assistant.nix"
      via: "imports list"
      pattern: "./home-assistant.nix"
---

<objective>
Add Home Assistant as a native NixOS service, following the project's one-module-per-concern pattern.

Purpose: Run Home Assistant natively on the acfs server using the NixOS `services.home-assistant` module, accessible via Tailscale only.
Output: `modules/home-assistant.nix` with working HA config, registered in `modules/default.nix`.
</objective>

<execution_context>
@/home/ubuntu/.claude/get-shit-done/workflows/execute-plan.md
@/home/ubuntu/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@flake.nix
@modules/default.nix
@modules/networking.nix
@modules/syncthing.nix
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create Home Assistant NixOS module</name>
  <files>modules/home-assistant.nix</files>
  <action>
Create `modules/home-assistant.nix` following the project's module pattern (see syncthing.nix for style reference).

The module should:

1. Add a file header comment with `@decision` annotations:
   - `@decision HA-01: Native NixOS service, not Docker container`
   - `@decision HA-02: GUI accessible via Tailscale only (same pattern as Syncthing)`

2. Enable `services.home-assistant` with:
   - `enable = true`
   - `openFirewall = false` — port 8123 is NOT opened publicly. The tailscale0 trusted interface in networking.nix means HA is reachable over tailnet automatically (same security model as Syncthing GUI on port 8384).
   - `config` attribute set with at minimum:
     - `homeassistant.name = "Home";`
     - `homeassistant.unit_system = "metric";`
     - `homeassistant.time_zone = "Europe/Berlin";` (matches host timezone in hosts/acfs/default.nix)
     - `http.server_host = "0.0.0.0";` — listen on all interfaces so tailscale0 works (same pattern as Syncthing's guiAddress)
     - `http.server_port = 8123;`
     - `default_config = {};` — enables the standard set of default integrations (frontend, automation, script, scene, etc.)

3. Use the module argument pattern `{ config, pkgs, ... }:` consistent with other modules.

4. Do NOT add any extraComponents or extraPackages yet — keep it minimal for initial setup. The user can add integrations later.

Note: The NixOS home-assistant module manages configuration.yaml declaratively. Settings in `config` are merged into HA's configuration.yaml. The `default_config` key enables the standard HA defaults.
  </action>
  <verify>
Run `nix flake check` from the project root (after Task 2 adds the import). If that fails, run `nix eval .#nixosConfigurations.acfs.config.services.home-assistant.enable` to check evaluation.
  </verify>
  <done>modules/home-assistant.nix exists with services.home-assistant enabled, listening on 0.0.0.0:8123, firewall not opened publicly.</done>
</task>

<task type="auto">
  <name>Task 2: Register module in default.nix and validate build</name>
  <files>modules/default.nix</files>
  <action>
Add `./home-assistant.nix` to the imports list in `modules/default.nix`. Place it alphabetically among the other service imports (after `./docker.nix`, before `./networking.nix`).

The updated imports list should look like:
```nix
{
  imports = [
    ./base.nix
    ./boot.nix
    ./users.nix
    ./networking.nix
    ./secrets.nix
    ./docker.nix
    ./home-assistant.nix
    ./syncthing.nix
    ./agent-compute.nix
    ./repos.nix
  ];
}
```

After adding the import, validate by running:
1. `git add modules/home-assistant.nix` (flakes only see tracked files)
2. `nix flake check` — must pass without errors
3. If `nix flake check` fails, diagnose and fix the issue in home-assistant.nix

Note: The actual build (`nixos-rebuild`) will happen on deploy. `nix flake check` validates the Nix evaluation succeeds.
  </action>
  <verify>
`nix flake check` passes. `nix eval .#nixosConfigurations.acfs.config.services.home-assistant.enable` returns `true`.
  </verify>
  <done>`modules/default.nix` imports home-assistant.nix, `nix flake check` passes, HA service evaluates as enabled.</done>
</task>

</tasks>

<verification>
1. `nix flake check` passes without errors
2. `nix eval .#nixosConfigurations.acfs.config.services.home-assistant.enable` returns `true`
3. `nix eval .#nixosConfigurations.acfs.config.services.home-assistant.config` shows the declared config values
4. Port 8123 is NOT in `networking.firewall.allowedTCPPorts` (tailnet-only access)
</verification>

<success_criteria>
- modules/home-assistant.nix exists with proper NixOS service declaration
- modules/default.nix imports the new module
- nix flake check passes
- Home Assistant is configured to listen on 0.0.0.0:8123 (reachable over Tailscale)
- Port 8123 is not opened in the public firewall
</success_criteria>

<output>
After completion, create `.planning/quick/002-add-home-assistant-as-native-nixos-servi/002-SUMMARY.md`
</output>
