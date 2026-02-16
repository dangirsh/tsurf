---
phase: 001-replace-tmux-with-zmx
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - flake.nix
  - flake.lock
  - modules/base.nix
  - modules/agent-compute.nix
  - home/default.nix
  - home/tmux.nix
autonomous: true

must_haves:
  truths:
    - "zmx is available in systemPackages"
    - "agent-spawn uses zmx instead of tmux"
    - "No tmux configuration remains"
  artifacts:
    - path: "flake.nix"
      provides: "zmx flake input"
      contains: "zmx"
    - path: "modules/base.nix"
      provides: "zmx package in systemPackages"
      pattern: "inputs\\.zmx\\.packages"
    - path: "modules/agent-compute.nix"
      provides: "zmx commands in agent-spawn"
      pattern: "zmx (run|attach)"
  key_links:
    - from: "flake.nix"
      to: "modules/base.nix"
      via: "inputs.zmx passed to modules"
      pattern: "specialArgs.*inputs"
    - from: "modules/agent-compute.nix"
      to: "zmx binary"
      via: "runtimeInputs"
      pattern: "runtimeInputs.*zmx"
---

<objective>
Replace tmux with zmx for terminal session persistence.

Purpose: Simplify session management by using zmx's zero-config approach instead of tmux's window/split/config complexity.
Output: Working zmx-based agent-spawn script with no tmux dependencies.
</objective>

<execution_context>
@/home/ubuntu/.claude/get-shit-done/workflows/execute-plan.md
@/home/ubuntu/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md

# Current implementation
@flake.nix
@modules/base.nix
@modules/agent-compute.nix
@home/default.nix
@home/tmux.nix
</context>

<tasks>

<task type="auto">
  <name>Add zmx flake input and integrate into modules</name>
  <files>
flake.nix
modules/base.nix
  </files>
  <action>
**flake.nix:**
Add zmx to inputs block (after llm-agents):
```nix
zmx = {
  url = "github:neurosnap/zmx";
};
```

Add `zmx` to the `@ inputs` pattern in outputs line 31.

**modules/base.nix:**
1. Update module signature from `{ config, lib, pkgs, ... }` to `{ config, lib, pkgs, inputs, ... }`
2. Replace `tmux` in environment.systemPackages (line 26) with `inputs.zmx.packages.x86_64-linux.default`

Run `nix flake lock` to add zmx to flake.lock.
  </action>
  <verify>
```bash
nix flake metadata | grep -A2 "Input 'zmx'"
grep -A2 "zmx =" flake.nix
grep "inputs.zmx.packages" modules/base.nix
```
  </verify>
  <done>
- zmx input exists in flake.nix and flake.lock
- modules/base.nix uses inputs.zmx package (no tmux)
  </done>
</task>

<task type="auto">
  <name>Update agent-spawn script to use zmx</name>
  <files>
modules/agent-compute.nix
  </files>
  <action>
In `modules/agent-compute.nix`:

1. Replace `runtimeInputs = with pkgs; [ tmux systemd ];` (line 10) with:
   ```nix
   runtimeInputs = with pkgs; [ inputs.zmx.packages.x86_64-linux.default systemd ];
   ```

2. Add `inputs` parameter to module signature (line 5): `{ config, pkgs, inputs, ... }:`

3. Replace tmux commands in the script (lines 27-32):
   - Change:
     ```bash
     systemd-run --user --scope --slice=agent.slice \
       -p CPUWeight=100 \
       -- tmux new-session -d -s "$NAME" -c "$PROJECT_DIR" "$CMD"

     echo "Agent '$NAME' spawned in tmux session (agent.slice)"
     echo "Attach: tmux attach -t $NAME"
     ```
   - To:
     ```bash
     systemd-run --user --scope --slice=agent.slice \
       -p CPUWeight=100 \
       -- zmx run "$NAME" bash -c "cd '$PROJECT_DIR' && $CMD"

     echo "Agent '$NAME' spawned in zmx session (agent.slice)"
     echo "Attach: zmx attach $NAME"
     ```

Note: zmx handles working directory via bash -c wrapper (zmx has no -c flag).
  </action>
  <verify>
```bash
grep "zmx run" modules/agent-compute.nix
grep "zmx attach" modules/agent-compute.nix
grep -c "tmux" modules/agent-compute.nix  # Should be 0
```
  </verify>
  <done>
- agent-spawn script uses zmx run and zmx attach
- No tmux references remain in agent-compute.nix
  </done>
</task>

<task type="auto">
  <name>Remove tmux home-manager configuration</name>
  <files>
home/default.nix
home/tmux.nix
  </files>
  <action>
1. In `home/default.nix`: Remove `./tmux.nix` from imports list (line 9)
2. Delete `home/tmux.nix` (zmx is zero-config, no home-manager module needed)

Verify build: `nix flake check`
  </action>
  <verify>
```bash
grep -c "tmux" home/default.nix  # Should be 0
[ ! -f home/tmux.nix ] && echo "tmux.nix deleted" || echo "ERROR: tmux.nix still exists"
nix flake check
```
  </verify>
  <done>
- home/tmux.nix deleted
- home/default.nix has no tmux import
- nix flake check passes
  </done>
</task>

</tasks>

<verification>
Final checks:
- `grep -r "tmux" flake.nix modules/ home/` returns no results (except in comments)
- `nix flake show --json | jq -r '.inputs | keys[]' | grep zmx` confirms zmx input
- `nixos-rebuild build --flake .#acfs` succeeds
</verification>

<success_criteria>
- zmx is the only session manager (no tmux references in config)
- agent-spawn script uses zmx run/attach commands
- Flake builds successfully with zmx integration
</success_criteria>

<output>
After completion, create `.planning/quick/001-replace-tmux-with-zmx/001-SUMMARY.md`
</output>
