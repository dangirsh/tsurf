# modules/agent-sandbox.nix
# @decision SANDBOX-73-01: Wrapper scripts replace bare agent binaries on dev hosts.
#   nono sandbox is the default; --no-sandbox requires AGENT_ALLOW_NOSANDBOX=1.
# @decision AUDIT-117-01: Launch logging via journald only (logger -t agent-launch).
#   File-based audit log removed — was user-owned/tamperable and leaked raw arguments.
# @decision NONO-118-02: API keys loaded from /run/secrets/ by scripts/agent-wrapper.sh
#   into the parent env. nono's reverse proxy reads them via env:// URIs and injects
#   per-session phantom tokens into the sandboxed child (--credential flag).
#   The child never sees real API keys.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentSandbox;
  agentCfg = config.tsurf.agent;

  # Build a sandboxed wrapper for an agent binary.
  # The Nix stub sets env vars consumed by scripts/agent-wrapper.sh.
  # credentials: list of "SERVICE:ENV_VAR:secret-file-name" triples (per-wrapper allowlist).
  #   SERVICE matches custom_credentials key in nono profile (proxy mode).
  mkWrapper = { name, realPkg, realBin, credentials }:
    (pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.nono pkgs.git pkgs.coreutils pkgs.util-linux ];
      text = ''
        export AGENT_NAME="${name}"
        export AGENT_REAL_BINARY="${realPkg}/bin/${realBin}"
        export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
        export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf.json"
        export AGENT_CREDENTIALS="${lib.concatStringsSep " " credentials}"
        ${lib.optionalString cfg.allowNixDaemon "export AGENT_ALLOW_NIX_DAEMON=1"}
        exec bash ${../scripts/agent-wrapper.sh} "$@"
      '';
    }).overrideAttrs (old: { meta = (old.meta or {}) // { priority = 4; }; });

  pi-sandboxed = mkWrapper {
    name = "pi";
    realPkg = pkgs.pi-coding-agent;
    realBin = "pi";
    credentials = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" ];
  };
in
{
  options.services.agentSandbox = {
    enable = lib.mkEnableOption "sandboxed agent wrappers for claude, codex, and pi";

    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.projectRoot;
      description = "Root directory for sandboxed agent execution. PWD must be inside this path.";
    };

    allowNixDaemon = lib.mkEnableOption "access to /nix/var/nix/daemon-socket inside the sandbox";

    egressControl = {
      enable = lib.mkEnableOption "UID-based nftables egress filtering for agent user";
      allowedPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ 53 80 443 22 9418 ];
        description = "TCP destination ports the agent user may connect to.";
      };
      # @decision SEC-115-03: Egress control defaults to agent user, not operator.
      user = lib.mkOption {
        type = lib.types.str;
        default = config.tsurf.agent.user;
        description = "Username whose egress is restricted.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure API key secrets are readable by the agent user.
    # mkDefault so private overlay can override ownership.
    sops.secrets."anthropic-api-key".owner = lib.mkDefault agentCfg.user;
    sops.secrets."openai-api-key".owner = lib.mkDefault agentCfg.user;

    # Replace bare agent binaries with sandboxed wrappers (meta.priority = 4 wins over default 5).
    environment.systemPackages = [
      (mkWrapper { name = "claude"; realPkg = pkgs.claude-code;      realBin = "claude"; credentials = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" ]; })
      (mkWrapper { name = "codex";  realPkg = pkgs.codex;            realBin = "codex";  credentials = [ "openai:OPENAI_API_KEY:openai-api-key" ]; })
      pi-sandboxed
    ];

    # @decision SANDBOX-NET-01: UID-based nftables egress filtering restricts the agent
    #   user to a whitelist of TCP destination ports. DNS (UDP 53) is always allowed.
    #   Tailscale traffic is unrestricted. All other outbound traffic is dropped.
    # checkRuleset disabled: `meta skuid` with symbolic usernames fails in the nix build
    # sandbox (no /etc/passwd). Rules are correct and work at runtime.
    networking.nftables.checkRuleset = lib.mkIf cfg.egressControl.enable false;

    networking.nftables.tables.agent-egress = lib.mkIf cfg.egressControl.enable {
      family = "inet";
      content =
        let
          portList = lib.concatMapStringsSep ", " toString cfg.egressControl.allowedPorts;
          user = cfg.egressControl.user;
        in ''
          chain output {
            type filter hook output priority 0; policy accept;
            meta skuid != "${user}" accept
            oifname "lo" accept
            ct state established,related accept
            meta l4proto udp th dport 53 accept
            meta l4proto tcp th dport { ${portList} } accept
            oifname "tailscale0" accept
            log prefix "agent-egress-deny: " drop
          }
        '';
    };
  };
}
