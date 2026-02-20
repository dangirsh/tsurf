---
phase: quick-3
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - modules/homepage.nix
  - modules/default.nix
autonomous: true

must_haves:
  truths:
    - "Visiting http://100.127.245.9:8082 over Tailscale shows the homepage dashboard"
    - "All six services appear as clickable links on the dashboard"
    - "nix flake check passes with the new module"
  artifacts:
    - path: "modules/homepage.nix"
      provides: "homepage-dashboard NixOS service declaration"
    - path: "modules/default.nix"
      provides: "imports homepage.nix"
  key_links:
    - from: "modules/default.nix"
      to: "modules/homepage.nix"
      via: "imports list entry"
      pattern: "\\.\/homepage\\.nix"
---

<objective>
Add the NixOS-native `services.homepage-dashboard` module, configured with all six
services running on the acfs server, and wire it into the module set.

Purpose: Single browser bookmark that links to every service on the Tailscale network.
Output: modules/homepage.nix + updated modules/default.nix
</objective>

<execution_context>
@/home/ubuntu/.claude/get-shit-done/workflows/execute-plan.md
@/home/ubuntu/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@modules/grafana.nix
@modules/networking.nix
@modules/default.nix
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create modules/homepage.nix with all service links</name>
  <files>modules/homepage.nix</files>
  <action>
Create a new NixOS module that enables the built-in homepage-dashboard service.

Listen on 0.0.0.0 (same pattern as Grafana's `http_addr`) so it is reachable over
Tailscale via trustedInterfaces — no allowedTCPPorts entry needed.

Use port 8082 (the NixOS default).

For `services.homepage-dashboard.services`, declare a single group "Services" containing:

- Grafana        — href http://100.127.245.9:3000   description "Metrics dashboards"
- Prometheus     — href http://100.127.245.9:9090   description "Metrics scraper"
- Alertmanager   — href http://100.127.245.9:9093   description "Alert routing"
- ntfy           — href http://100.127.245.9:2586   description "Push notifications"
- Syncthing      — href http://100.127.245.9:8384   description "File sync"
- Home Assistant — href http://100.127.245.9:8123   description "Home automation"

For `services.homepage-dashboard.settings`, set title to "acfs" and optionally a
background color or theme that suits a server dashboard (use theme "dark").

Use the Nix list-of-attrsets structure that maps to YAML. For example:

```nix
{ config, pkgs, ... }: {
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    settings = {
      title = "acfs";
      theme = "dark";
      color = "slate";
    };
    services = [
      {
        "Services" = [
          { "Grafana" = { href = "http://100.127.245.9:3000"; description = "Metrics dashboards"; }; }
          { "Prometheus" = { href = "http://100.127.245.9:9090"; description = "Metrics scraper"; }; }
          { "Alertmanager" = { href = "http://100.127.245.9:9093"; description = "Alert routing"; }; }
          { "ntfy" = { href = "http://100.127.245.9:2586"; description = "Push notifications"; }; }
          { "Syncthing" = { href = "http://100.127.245.9:8384"; description = "File sync"; }; }
          { "Home Assistant" = { href = "http://100.127.245.9:8123"; description = "Home automation"; }; }
        ];
      }
    ];
  };
}
```

Add a file header comment and a @decision annotation:
  # @decision HP-01: Use NixOS-native homepage-dashboard service; listen on 0.0.0.0 for Tailscale reachability.
  </action>
  <verify>nix flake check from /data/projects/neurosys (after git add)</verify>
  <done>modules/homepage.nix exists and `nix flake check` evaluates without errors</done>
</task>

<task type="auto">
  <name>Task 2: Wire homepage.nix into modules/default.nix</name>
  <files>modules/default.nix</files>
  <action>
Add `./homepage.nix` to the imports list in modules/default.nix.

Place it after `./repos.nix` (last entry) so it is clear it is a new addition.

Run `git add modules/homepage.nix modules/default.nix` then
`nix flake check` to confirm the full flake evaluates.

If flake check fails due to an option type mismatch in the services or settings
attribute (homepage-dashboard NixOS options expect specific YAML-mapped types),
inspect the error and adjust the Nix value structure accordingly — for example,
some versions want `settings` as a plain attrset vs a string. Check with:
  `nix-instantiate --eval -E '(import <nixpkgs> {}).lib.nixosSystem { modules = [ ./flake-derived-config ]; }'`
or just iterate on `nix flake check` error messages.
  </action>
  <verify>
    git add modules/homepage.nix modules/default.nix
    nix flake check
  </verify>
  <done>modules/default.nix imports ./homepage.nix and `nix flake check` passes</done>
</task>

</tasks>

<verification>
After both tasks complete, the flake evaluates cleanly. Deploy with:

  scripts/deploy.sh --target root@161.97.74.121

Then visit http://100.127.245.9:8082 from a Tailscale-connected browser and confirm
the dashboard shows all six service tiles with working links.
</verification>

<success_criteria>
- modules/homepage.nix exists with `services.homepage-dashboard.enable = true`
- modules/default.nix imports ./homepage.nix
- `nix flake check` passes
- Dashboard is reachable at http://100.127.245.9:8082 after deploy
- All six services are listed and their href links resolve
</success_criteria>

<output>
After completion, create `.planning/quick/3-add-a-nixos-native-homepage-dashboard-li/3-SUMMARY.md`
</output>
