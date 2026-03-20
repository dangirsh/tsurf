---
name: nix-module
description: Create a new NixOS module for the tsurf repo
user_invocable: true
---

# nix-module Skill

Create or extend NixOS modules in this repo using tsurf-specific patterns.

## 1. Decide: new file or extend existing?

- If the change is <20 lines and belongs to an existing concern, add to that module.
- If it is a new service (own systemd unit, user, secrets, or port), create a new file.

## 2. Create the module file

- Location: `modules/<name>.nix`
- Header: add `@decision` annotations for security-relevant choices.
- Function signature: `{ config, lib, pkgs, ... }:`
- For services: define system user + group, systemd unit, and `services.dashboard.entries.<name>` declaration.
- Use `let` bindings for values referenced more than once.
- Use `lib.mkDefault` for hardening defaults that modules may need to override.

## 3. Register the service (if applicable)

Add a dashboard entry and register the port:

```nix
services.dashboard.entries.<name> = {
  name = "Display Name";
  description = "What it does";
  port = 8090;  # if applicable
  icon = "mdi-server";
  systemdUnit = "<name>.service";
  module = "<name>.nix";
  order = 50;
};
```

Then add the port to `internalOnlyPorts` in `modules/networking.nix`:

```nix
"8090" = "<name>";
```

## 4. Add secrets (if needed)

In `modules/secrets.nix`:

```nix
sops.secrets."<name>-token" = { owner = "<name>"; };
sops.templates."<name>-env" = {
  content = ''
    TOKEN=${config.sops.placeholder."<name>-token"}
  '';
};
```

Then encrypt the real value:

```bash
sops secrets/neurosys.yaml
# or
sops secrets/ovh.yaml
```

## 5. Persist state (if needed)

In `modules/impermanence.nix`, add to the `directories` list:

```nix
{ directory = "/var/lib/<name>"; user = "<name>"; group = "<name>"; mode = "0700"; }
```

## 6. Import in host config

Add the module path to `hosts/services/default.nix` or `hosts/dev/default.nix`:

```nix
../../modules/<name>.nix
```

## 7. git add + validate

```bash
git add modules/<name>.nix
nix flake check
```

Flakes only see tracked files. `git add` is mandatory before `nix flake check`.

## 8. Add eval check (recommended)

In `tests/eval/config-checks.nix`, add a check with `mkCheck`:

```nix
<name>-service-defined = mkCheck
  "<name>-service-defined"
  "<name> systemd service is defined"
  "<name> service missing — check modules/<name>.nix import"
  (builtins.hasAttr "<name>" neurosysCfg.systemd.services);
```

## Checklist before committing

- [ ] `@decision` annotations on security-relevant choices
- [ ] `openFirewall = false` for network services
- [ ] `services.dashboard.entries.<name>` declared and port added to `internalOnlyPorts`
- [ ] Secrets use sops-nix, not hardcoded values
- [ ] `nix flake check` passes
- [ ] `.test-status` updated
