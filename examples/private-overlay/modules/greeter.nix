# modules/greeter.nix — Minimal example: a sandboxed agent that runs daily
#
# This is the simplest possible agent module. It demonstrates:
#   1. Defining a custom nono profile (filesystem allow/deny, network, credentials)
#   2. Installing the profile to /etc/nono/profiles/
#   3. Running the agent via a systemd timer with proxy credential injection
#      (phantom tokens — the child process never sees the real API key)
#
# For the full credential architecture, see SECURITY.md in the tsurf repo.
# @decision EXAMPLE-130-01: Timer/service agents that call nono directly must
#   exec the raw store binary, not the interactive PATH wrapper from
#   agent-sandbox.nix. The wrapper enforces the git-worktree launch model and
#   intentionally fails outside repo-scoped interactive sessions.
{ config, lib, pkgs, ... }:
let
  # --- 1. Define a nono profile ---
  # This controls what the agent can and cannot access.
  # `extends = "claude-code"` inherits safe defaults for nix, node, python, etc.
  greeterProfile = {
    extends = "claude-code";
    meta = {
      name = "greeter";
      version = "1.0.0";
      description = "Example: daily greeting agent";
      author = "tsurf";
    };
    # Filesystem access beyond what claude-code provides.
    # The agent can read/write its working directory (workdir.access below),
    # plus any paths listed here.
    filesystem = {
      allow = [
        "/var/lib/greeter"     # where the agent writes its output
      ];
      allow_file = [
        "/var/lib/greeter/greeting.txt"
      ];
      # deny list is inherited from claude-code (blocks ~/.ssh, ~/.gnupg, etc.)
    };
    network = {
      block = false;           # agent needs API access
      # Proxy credential injection: nono reads the real API key from parent env
      # via env:// URI, starts a reverse proxy, and passes only a per-session
      # phantom token to the child process. The real key never reaches the agent.
      custom_credentials = {
        anthropic = {
          upstream = "https://api.anthropic.com";
          credential_key = "env://ANTHROPIC_API_KEY";
          inject_header = "x-api-key";
          credential_format = "{}";
          env_var = "ANTHROPIC_API_KEY";
        };
      };
    };
    workdir = {
      access = "readwrite";    # CWD is writable (the agent works here)
    };
    interactive = false;         # non-interactive (systemd timer, no TTY)
  };

  greeterProfileFile = pkgs.writeText "greeter-nono-profile.json"
    (builtins.toJSON greeterProfile);

  # --- 2. The agent launch script ---
  # Loads the API key into parent env for nono proxy (env:// URI).
  # The child process receives only a per-session phantom token.
  greeterScript = pkgs.writeShellScript "greeter-agent" ''
    set -euo pipefail
    # Load API key into parent env for nono's proxy credential injection.
    # nono reads this via env://ANTHROPIC_API_KEY, generates a phantom token,
    # and the child process only sees the phantom token + localhost proxy URL.
    export ANTHROPIC_API_KEY="$(cat "$ANTHROPIC_API_KEY_FILE")"
    exec nono run \
      --profile /etc/nono/profiles/greeter.json \
      --net-allow \
      --credential anthropic \
      -- ${pkgs.claude-code}/bin/claude -p \
      --permission-mode=bypassPermissions \
      "Write a short, cheerful greeting with today's date to /var/lib/greeter/greeting.txt. One sentence only."
  '';
in {
  # --- 3. Install the nono profile ---
  environment.etc."nono/profiles/greeter.json".source = greeterProfileFile;

  # --- 4. Create the output directory ---
  systemd.tmpfiles.rules = [
    "d /var/lib/greeter 0755 ${config.tsurf.agent.user} users -"
  ];

  # --- 5. Define the systemd service + timer ---
  systemd.services.greeter = {
    description = "Example daily greeting agent";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = config.tsurf.agent.user;
      WorkingDirectory = "/var/lib/greeter";
      ExecStart = greeterScript;

      # API key file for proxy credential injection (parent env only — child gets phantom token)
      Environment = [
        "ANTHROPIC_API_KEY_FILE=${config.sops.secrets."anthropic-api-key".path}"
      ];

      # Resource limits (within the agent slice)
      Slice = "tsurf-agents.slice";
      MemoryMax = "2G";
      TasksMax = 64;

      # Systemd hardening baseline
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
    };
  };

  systemd.timers.greeter = {
    description = "Run greeter agent daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
