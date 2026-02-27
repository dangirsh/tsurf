# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision: Using `systemd-run --user --scope` for agent-spawn so myuser can run
#   without root. Requires linger (set below) for persistent user systemd instance.
# @decision SANDBOX-11-01: agent-spawn runs in bubblewrap by default; --no-sandbox is explicit opt-out.
# @decision SANDBOX-11-01: Podman is enabled rootless; dockerCompat=false (conflicts with Docker)
#   — sandbox uses a PATH-local docker->podman symlink derivation instead.
{ config, pkgs, ... }:

let
  zmx = pkgs.callPackage ../packages/zmx.nix {};
  # Sandbox-local docker -> podman symlink so agents see `docker` without
  # system-wide dockerCompat (which conflicts with virtualisation.docker).
  sandbox-docker-compat = pkgs.runCommandNoCC "sandbox-docker-compat" {} ''
    mkdir -p $out/bin
    ln -s ${pkgs.podman}/bin/podman $out/bin/docker
  '';
  agent-spawn = pkgs.writeShellApplication {
    name = "agent-spawn";
    runtimeInputs = [ zmx pkgs.systemd pkgs.bubblewrap pkgs.coreutils ];
    text = ''
      set -euo pipefail

      usage() {
        cat <<'EOF'
      Usage: agent-spawn <name> <project-dir> [claude|codex|opencode|gemini|pi] [--no-sandbox] [--show-policy]
      EOF
      }

      if [ "$#" -lt 2 ]; then
        usage >&2
        exit 1
      fi

      NAME="$1"
      PROJECT_INPUT="$2"
      shift 2

      AGENT="claude"
      AGENT_SET=0
      NO_SANDBOX=0
      SHOW_POLICY=0

      for arg in "$@"; do
        case "$arg" in
          --no-sandbox)
            NO_SANDBOX=1
            ;;
          --show-policy)
            SHOW_POLICY=1
            ;;
          claude|codex|opencode|gemini|pi)
            if [ "$AGENT_SET" -eq 1 ]; then
              echo "Error: Agent type specified multiple times" >&2
              usage >&2
              exit 1
            fi
            AGENT="$arg"
            AGENT_SET=1
            ;;
          *)
            echo "Error: Unknown argument '$arg'" >&2
            usage >&2
            exit 1
            ;;
        esac
      done

      if [ ! -d "$PROJECT_INPUT" ]; then
        echo "Error: Project directory does not exist: $PROJECT_INPUT" >&2
        exit 1
      fi

      PROJECT_DIR="$(realpath "$PROJECT_INPUT")"

      case "$AGENT" in
        claude)
          CMD="claude"
          ;;
        codex)
          CMD="codex"
          ;;
        opencode)
          CMD="opencode"
          ;;
        gemini)
          CMD="gemini"
          ;;
        pi)
          CMD="pi"
          ;;
        *)
          echo "Unknown agent: $AGENT (expected: claude, codex, opencode, gemini, pi)" >&2
          exit 1
          ;;
      esac

      if [ "$SHOW_POLICY" -eq 1 ]; then
        cat <<EOF
      Sandbox policy for agent '$NAME'
      Project (rw): $PROJECT_DIR
      Visible (ro): /nix/store, /run/current-system, /etc (selected), /data/projects (siblings)
      Visible (rw): $PROJECT_DIR, /home/myuser/.local/share/containers, /run/user/$(id -u)/containers
      Hidden: /run/secrets, /home/myuser/.ssh, /var/run/docker.sock
      Namespaces: PID (isolated /proc), cgroup (isolated), user, IPC, UTS
      Limits: systemd slice=agent.slice CPUWeight=100 TasksMax=4096, /tmp tmpfs=4GiB
      Podman: enabled (rootless, docker->podman via sandbox PATH shim)
      Default mode: sandbox on (use --no-sandbox to bypass)
      EOF
        exit 0
      fi

      # Read API credentials before sandbox entry.
      ANTHROPIC_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null || true)"
      OPENAI_KEY="$(cat /run/secrets/openai-api-key 2>/dev/null || true)"
      GITHUB_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null || true)"
      GOOGLE_KEY="$(cat /run/secrets/google-api-key 2>/dev/null || true)"
      XAI_KEY="$(cat /run/secrets/xai-api-key 2>/dev/null || true)"
      OPENROUTER_KEY="$(cat /run/secrets/openrouter-api-key 2>/dev/null || true)"

      RUNTIME_UID="$(id -u)"
      RUNTIME_GID="$(id -g)"
      RUNTIME_DIR="/run/user/$RUNTIME_UID"
      TERM_VALUE="''${TERM:-xterm-256color}"

      BWRAP_ARGS=(
        --unshare-user --uid "$RUNTIME_UID" --gid "$RUNTIME_GID"
        --unshare-ipc
        --unshare-uts
        --unshare-pid
        --unshare-cgroup
        --disable-userns
        --hostname "sandbox-$NAME"
        --die-with-parent
        --new-session

        --ro-bind /nix/store /nix/store
        --bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
        --ro-bind /nix/var/nix/db /nix/var/nix/db
        --ro-bind /nix/var/nix/gcroots /nix/var/nix/gcroots

        --ro-bind /run/current-system /run/current-system
        --ro-bind-try /etc/profiles/per-user/myuser /etc/profiles/per-user/myuser
        --ro-bind-try /home/myuser/.nix-profile /home/myuser/.nix-profile

        --ro-bind /etc/resolv.conf /etc/resolv.conf
        --ro-bind /etc/passwd /etc/passwd
        --ro-bind /etc/group /etc/group
        --ro-bind /etc/ssl /etc/ssl
        --ro-bind /etc/nix /etc/nix
        --ro-bind /etc/static /etc/static
        --ro-bind-try /etc/hosts /etc/hosts
        --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
        --ro-bind-try /etc/login.defs /etc/login.defs
        --ro-bind-try /etc/subuid /etc/subuid
        --ro-bind-try /etc/subgid /etc/subgid
        --ro-bind-try /etc/containers /etc/containers

        --proc /proc
        --dev /dev
        --size 4294967296 --tmpfs /tmp

        --ro-bind /data/projects /data/projects
        --bind "$PROJECT_DIR" "$PROJECT_DIR"

        --dir /home/myuser
        --dir /home/myuser/.config
        --dir /home/myuser/.local
        --dir /home/myuser/.local/share
        --ro-bind-try /home/myuser/.gitconfig /home/myuser/.gitconfig
        --ro-bind-try /home/myuser/.npmrc /home/myuser/.npmrc
        --ro-bind-try /home/myuser/.claude /home/myuser/.claude
        --ro-bind-try /home/myuser/.codex /home/myuser/.codex
        --ro-bind-try /home/myuser/.config/opencode /home/myuser/.config/opencode
        --bind-try /home/myuser/.local/share/opencode /home/myuser/.local/share/opencode
        --bind-try /home/myuser/.pi/agent /home/myuser/.pi/agent
        --bind-try /home/myuser/.gemini /home/myuser/.gemini
        --ro-bind-try /home/myuser/.config/git /home/myuser/.config/git
        --bind-try /home/myuser/.local/share/containers /home/myuser/.local/share/containers

        --dir /run/user
        --dir "$RUNTIME_DIR"
        --bind-try "$RUNTIME_DIR/containers" "$RUNTIME_DIR/containers"
        --ro-bind-try "$RUNTIME_DIR/podman" "$RUNTIME_DIR/podman"

        --clearenv
        --setenv HOME /home/myuser
        --setenv USER myuser
        --setenv SHELL /bin/bash
        --setenv TERM "$TERM_VALUE"
        --setenv LANG C.UTF-8
        --setenv PATH ${sandbox-docker-compat}/bin:${zmx}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/myuser/bin:/home/myuser/.nix-profile/bin:/nix/var/nix/profiles/default/bin
        --setenv SANDBOX 1
        --setenv SANDBOX_NAME "$NAME"
        --setenv SANDBOX_PROJECT "$PROJECT_DIR"
        --setenv NIX_REMOTE daemon
        --chdir "$PROJECT_DIR"
      )

      if [ -n "''${NIX_PATH:-}" ]; then
        BWRAP_ARGS+=( --setenv NIX_PATH "$NIX_PATH" )
      fi

      if [ -n "$ANTHROPIC_KEY" ]; then
        # Private overlay: wire ANTHROPIC_BASE_URL for projects using the secret proxy.
        # Example: if [[ "$PROJECT_DIR" == /data/projects/my-project* ]]; then
        #   BWRAP_ARGS+=( --setenv ANTHROPIC_BASE_URL "http://127.0.0.1:9091" )
        # fi
        BWRAP_ARGS+=( --setenv ANTHROPIC_API_KEY "$ANTHROPIC_KEY" )
      fi

      if [ -n "$OPENAI_KEY" ]; then
        BWRAP_ARGS+=( --setenv OPENAI_API_KEY "$OPENAI_KEY" )
      fi

      if [ -n "$GITHUB_TOKEN" ]; then
        BWRAP_ARGS+=( --setenv GITHUB_TOKEN "$GITHUB_TOKEN" )
        BWRAP_ARGS+=( --setenv GH_TOKEN "$GITHUB_TOKEN" )
      fi

      if [ -n "$GOOGLE_KEY" ]; then
        BWRAP_ARGS+=( --setenv GEMINI_API_KEY "$GOOGLE_KEY" )
        BWRAP_ARGS+=( --setenv GOOGLE_API_KEY "$GOOGLE_KEY" )
      fi
      if [ -n "$XAI_KEY" ]; then
        BWRAP_ARGS+=( --setenv XAI_API_KEY "$XAI_KEY" )
      fi
      if [ -n "$OPENROUTER_KEY" ]; then
        BWRAP_ARGS+=( --setenv OPENROUTER_API_KEY "$OPENROUTER_KEY" )
      fi

      AUDIT_DIR="/data/projects/.agent-audit"
      mkdir -p "$AUDIT_DIR"
      SANDBOX_STATE="on"
      if [ "$NO_SANDBOX" -eq 1 ]; then
        SANDBOX_STATE="off"
      fi
      printf "%s SPAWN agent=%s name=%s project=%s sandbox=%s\n" \
        "$(date -Iseconds)" "$AGENT" "$NAME" "$PROJECT_DIR" "$SANDBOX_STATE" >> "$AUDIT_DIR/spawn.log"
      # Tamper-resistant copy via journald (root-owned journal, agents cannot modify)
      printf "AGENT_SPAWN agent=%s name=%s project=%s sandbox=%s" \
        "$AGENT" "$NAME" "$PROJECT_DIR" "$SANDBOX_STATE" | systemd-cat -t agent-spawn -p info

      if [ "$NO_SANDBOX" -eq 1 ]; then
        systemd-run --user --scope --slice=agent.slice \
          -p TasksMax=4096 \
          -p CPUWeight=100 \
          -- zmx run "$NAME" bash -c "cd '$PROJECT_DIR' && $CMD"
      else
        systemd-run --user --scope --slice=agent.slice \
          -p TasksMax=4096 \
          -p CPUWeight=100 \
          -- bwrap "''${BWRAP_ARGS[@]}" -- zmx run "$NAME" bash -c "$CMD"
      fi

      echo "Agent '$NAME' spawned in zmx session (agent.slice, sandbox=$SANDBOX_STATE)"
      echo "Attach: zmx attach $NAME"
    '';
  };
in
{
  # Agent CLI packages from llm-agents.nix overlay
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.opencode
    pkgs.gemini-cli
    pkgs.llm-agents.pi
    zmx
    agent-spawn
  ];

  # Rootless Podman for sandboxed agent container workflows.
  # dockerCompat = false because virtualisation.docker.enable = true in docker.nix —
  # NixOS asserts they cannot coexist. Instead, a sandbox-local docker->podman symlink
  # (sandbox-docker-compat derivation below) is added to the sandbox PATH so agents
  # see `docker` resolving to `podman` without affecting the host Docker daemon.
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    defaultNetwork.settings.dns_enabled = true;
  };

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
      TasksMax = 4096;
    };
  };

  # Pre-create audit log directory for agent-spawn.
  # NOTE (SEC-17-04): spawn.log is writable by myuser -- a compromised agent
  # could tamper with it. For forensic-grade audit integrity, forward spawn events
  # to journald (systemd-cat) in a future hardening pass. Current risk: LOW
  # (operational log, not security boundary).
  systemd.tmpfiles.rules = [
    "d /data/projects/.agent-audit 0750 myuser users -"
  ];

  # User linger for persistent systemd user instance (needed for systemd-run --user)
  users.users.myuser.linger = true;
}
