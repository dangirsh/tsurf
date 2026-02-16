# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision: Using `systemd-run --user --scope` for agent-spawn so dangirsh can run
#   without root. Requires linger (set below) for persistent user systemd instance.
{ config, pkgs, ... }:

let
  zmx = pkgs.callPackage ../packages/zmx.nix {};
  agent-spawn = pkgs.writeShellApplication {
    name = "agent-spawn";
    runtimeInputs = [ zmx pkgs.systemd ];
    text = ''
      NAME="''${1:?Usage: agent-spawn <name> <project-dir> [claude|codex]}"
      PROJECT_DIR="''${2:?Usage: agent-spawn <name> <project-dir> [claude|codex]}"
      AGENT="''${3:-claude}"

      case "$AGENT" in
        claude) CMD="claude" ;;
        codex)  CMD="codex" ;;
        *)      echo "Unknown agent: $AGENT (expected: claude, codex)"; exit 1 ;;
      esac

      if [ ! -d "$PROJECT_DIR" ]; then
        echo "Error: Project directory does not exist: $PROJECT_DIR"
        exit 1
      fi

      systemd-run --user --scope --slice=agent.slice \
        -p CPUWeight=100 \
        -- zmx run "$NAME" bash -c "cd '$PROJECT_DIR' && $CMD"

      echo "Agent '$NAME' spawned in zmx session (agent.slice)"
      echo "Attach: zmx attach $NAME"
    '';
  };
in
{
  # Agent CLI packages from llm-agents.nix overlay
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.codex
    agent-spawn
  ];

  # Numtide binary cache for fast agent CLI builds
  nix.settings = {
    substituters = [
      "https://cache.numtide.com"
    ];
    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  # Systemd cgroup slice for agent workload isolation
  systemd.slices."agent" = {
    description = "Agent workload isolation slice";
    sliceConfig = {
      CPUWeight = 100;
    };
  };

  # User linger for persistent systemd user instance (needed for systemd-run --user)
  users.users.dangirsh.linger = true;
}
