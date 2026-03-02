# modules/automaton.nix
# Conway Automaton — self-hosted autonomous AI agent runtime
#
# @decision AUTO-03: Agent runs on neurosys hardware, not Conway Cloud sandbox.
# @rationale: Eliminates Conway Cloud sandbox fees. Agent uses Conway API key
#   for Cloud tools (domains, x402, credits) but execution is local. BYOK
#   Anthropic inference via secret proxy on port 9091.
#
# @decision AUTO-04: HOME=/var/lib/automaton for state isolation.
# @rationale: The automaton hardcodes ~/.automaton/ for wallet and config.
#   Setting HOME to the StateDirectory keeps all state under /var/lib/automaton.
#
# @decision AUTO-05: Genesis prompt provides concrete first task with step-by-step plan.
# @rationale: Abstract "explore, exploit, evolve" caused the agent to spin without
#   direction. Concrete steps (check credits, register on ERC-8004, survey marketplace,
#   build and expose a service) give the agent actionable starting points.
#
# @decision AUTO-07: maxTokensPerTurn increased from 4096 to 16384.
# @rationale: The system prompt (constitution + orchestrator + tools + memory) consumes
#   most of the 4096 budget, leaving insufficient space for reasoning. 16384 gives room
#   for multi-step planning while BYOK inference keeps costs predictable.
#
# @decision AUTO-06: Wallet generated on first activation, persists across rebuilds.
# @rationale: The EVM wallet private key is generated once and never overwritten.
#   Storing in /var/lib/automaton/.automaton/wallet.json (persisted by impermanence
#   or StateDirectory) ensures the agent keeps its identity across NixOS rebuilds.

{ config, pkgs, inputs, lib, ... }:

let
  automaton-pkg = pkgs.callPackage ../packages/automaton.nix {
    src = inputs.automaton;
  };

  automatonDir = "/var/lib/automaton/.automaton";

  # Default automaton.json configuration
  automatonConfig = builtins.toJSON {
    name = "neurosys-agent";
    genesisPrompt = builtins.concatStringsSep " " [
      "You are neurosys-agent, a sovereign AI agent running on dedicated hardware"
      "with over 400 dollars in Conway credits."
      "Your infrastructure: local execution, BYOK Anthropic inference (free per call),"
      "full internet access, Conway Cloud API for sandboxes, domains, registry, x402."
      "IMPORTANT: expose_port on THIS machine returns localhost URLs (not publicly reachable)."
      "To serve customers, create a Conway Cloud sandbox and deploy there."
      ""
      "Your first mission:"
      "1. Check your credit balance (check_credits). You have plenty."
      "2. Skip ERC-8004 registration for now (requires ETH you do not have)."
      "3. Use discover_agents to survey the Conway marketplace."
      "   What services exist? What is missing?"
      "4. Pick ONE concrete service to build. Start with something small:"
      "   a single API endpoint doing one useful thing."
      "5. Use create_goal to plan it."
      "   The orchestrator will break it into tasks for worker agents."
      "6. Create a Conway Cloud sandbox (create_sandbox),"
      "   deploy your service there, expose it (expose_port)."
      "7. Add x402 payment so callers pay per request."
      "8. Use send_message to announce your service to other agents."
      ""
      "Focus on Conway credit operations only."
      "No on-chain transactions until your wallet is funded with ETH and USDC."
    ];
    creatorAddress = "";
    registeredWithConway = false;
    sandboxId = "";
    conwayApiUrl = "https://api.conway.tech";
    conwayApiKey = "";
    anthropicApiKey = "placeholder-for-secret-proxy";
    inferenceModel = "claude-sonnet-4-6";
    maxTokensPerTurn = 16384;
    heartbeatConfigPath = "${automatonDir}/heartbeat.yml";
    dbPath = "${automatonDir}/state.db";
    logLevel = "info";
    walletAddress = "";
    version = "0.2.0";
    skillsDir = "${automatonDir}/skills";
    maxChildren = 2;
    socialRelayUrl = "https://social.conway.tech";
    treasuryPolicy = {
      maxSingleTransferCents = 5000;
      maxHourlyTransferCents = 10000;
      maxDailyTransferCents = 50000;
      minimumReserveCents = 5000;
      maxX402PaymentCents = 500;
      x402AllowedDomains = [ "*" ];
      transferCooldownMs = 60000;
      maxTransfersPerTurn = 3;
      maxInferenceDailyCents = 5000;
      requireConfirmationAboveCents = 1000;
    };
  };

  heartbeatYml = ''
    # Conway Automaton heartbeat schedule
    # Intervals in seconds
    tasks:
      heartbeat_ping:
        interval: 600
        enabled: true
      check_credits:
        interval: 1800
        enabled: true
      check_usdc_balance:
        interval: 7200
        enabled: true
      check_for_updates:
        interval: 86400
        enabled: false
      health_check:
        interval: 600
        enabled: true
      soul_reflection:
        interval: 43200
        enabled: true
      report_metrics:
        interval: 3600
        enabled: true
  '';

  soulMd = ''
    # Agent Identity

    I am neurosys-agent, a sovereign AI agent on dedicated hardware.
    I execute locally but can deploy services to Conway Cloud sandboxes.

    ## Infrastructure Reality
    - I run on a NixOS server (not a Conway sandbox)
    - expose_port gives me localhost URLs (not publicly reachable)
    - To serve the public, I must create Conway Cloud sandboxes
    - My wallet has $0 USDC — I operate on Conway credits only
    - I have BYOK Anthropic inference (no per-call Conway charges)

    ## Capabilities
    - Conway Cloud: sandboxes, domains, x402 payments, agent registry
    - Full internet access for research and API calls
    - BYOK Anthropic inference via secret proxy (cost-free per call)
    - SQLite state persistence across restarts
    - Up to 2 child worker agents for parallel execution

    ## Operating Principles
    - Earn more than I spend — track credit burn rate
    - Build one thing at a time, prove it works, then expand
    - Use Conway sandboxes for public-facing services
    - Register on ERC-8004 so other agents can find me
    - Announce services via social relay
  '';

  # Nix store files — avoids all shell quoting issues (JSON contains apostrophes)
  automatonConfigFile = pkgs.writeText "automaton.json" automatonConfig;
  heartbeatYmlFile = pkgs.writeText "heartbeat.yml" heartbeatYml;
  soulMdFile = pkgs.writeText "SOUL.md" soulMd;
  gitignoreFile = pkgs.writeText "automaton-gitignore" ''
    wallet.json
    config.json
    state.db
    state.db-wal
    state.db-shm
    *.log
  '';
in {

  # --- System user ---
  users.users.automaton = {
    isSystemUser = true;
    group = "automaton";
    home = "/var/lib/automaton";
    createHome = true;
  };
  users.groups.automaton = {};

  # --- Sops template for environment ---
  sops.secrets."creator-address" = {
    sopsFile = ../secrets/neurosys.yaml;
    owner = "automaton";
    group = "automaton";
  };

  sops.templates."automaton-env" = {
    owner = "automaton";
    content = ''
      ANTHROPIC_BASE_URL=http://127.0.0.1:9091
      ANTHROPIC_API_KEY=placeholder-for-secret-proxy
    '';
  };

  # --- Activation script: pre-seed state directory ---
  system.activationScripts.automaton-state = {
    text = ''
      # Create state directory structure
      mkdir -p ${automatonDir}/skills
      chown -R automaton:automaton /var/lib/automaton

      # Write automaton.json only if it does not exist (preserve user edits)
      if [ ! -f ${automatonDir}/automaton.json ]; then
        cp ${automatonConfigFile} ${automatonDir}/automaton.json
        chown automaton:automaton ${automatonDir}/automaton.json
        chmod 0600 ${automatonDir}/automaton.json
      fi

      # Inject Conway API key from sops into automaton.json
      # The config file stores the key directly (not env var)
      if [ -f ${config.sops.secrets."conway-api-key".path} ]; then
        CONWAY_KEY=$(cat ${config.sops.secrets."conway-api-key".path})
        if [ -n "$CONWAY_KEY" ] && [ "$CONWAY_KEY" != "cnwy_k_PLACEHOLDER" ]; then
          ${pkgs.jq}/bin/jq --arg key "$CONWAY_KEY" '.conwayApiKey = $key' \
            ${automatonDir}/automaton.json > ${automatonDir}/automaton.json.tmp \
            && mv ${automatonDir}/automaton.json.tmp ${automatonDir}/automaton.json
          chown automaton:automaton ${automatonDir}/automaton.json
          chmod 0600 ${automatonDir}/automaton.json
        fi
      fi

      # Inject creator address from sops into automaton.json
      if [ -f ${config.sops.secrets."creator-address".path} ]; then
        CREATOR_ADDR=$(cat ${config.sops.secrets."creator-address".path})
        if [ -n "$CREATOR_ADDR" ]; then
          ${pkgs.jq}/bin/jq --arg addr "$CREATOR_ADDR" '.creatorAddress = $addr' \
            ${automatonDir}/automaton.json > ${automatonDir}/automaton.json.tmp \
            && mv ${automatonDir}/automaton.json.tmp ${automatonDir}/automaton.json
          chown automaton:automaton ${automatonDir}/automaton.json
          chmod 0600 ${automatonDir}/automaton.json
        fi
      fi

      # Generate wallet.json if it does not exist
      # Creates a random EVM private key (32 bytes hex)
      if [ ! -f ${automatonDir}/wallet.json ]; then
        PRIVKEY=$(${pkgs.openssl}/bin/openssl rand -hex 32)
        echo "{\"privateKey\": \"0x$PRIVKEY\"}" > ${automatonDir}/wallet.json
        chown automaton:automaton ${automatonDir}/wallet.json
        chmod 0600 ${automatonDir}/wallet.json
      fi

      # Write heartbeat.yml only if it does not exist
      if [ ! -f ${automatonDir}/heartbeat.yml ]; then
        cp ${heartbeatYmlFile} ${automatonDir}/heartbeat.yml
        chown automaton:automaton ${automatonDir}/heartbeat.yml
      fi

      # Write SOUL.md only if it does not exist (agent may self-modify)
      if [ ! -f ${automatonDir}/SOUL.md ]; then
        cp ${soulMdFile} ${automatonDir}/SOUL.md
        chown automaton:automaton ${automatonDir}/SOUL.md
      fi

      # Always update constitution.md from package (immutable rules)
      cp ${automaton-pkg}/lib/node_modules/@conway/automaton/constitution.md \
        ${automatonDir}/constitution.md
      chown automaton:automaton ${automatonDir}/constitution.md
      chmod 0444 ${automatonDir}/constitution.md

      # Write .gitignore only if it does not exist
      # (git init is left to the agent itself — root cannot git-init dirs owned by automaton)
      if [ ! -f ${automatonDir}/.gitignore ]; then
        cp ${gitignoreFile} ${automatonDir}/.gitignore
        chown automaton:automaton ${automatonDir}/.gitignore
      fi
    '';
    deps = [ "setupSecrets" ];
  };

  # --- Systemd service ---
  systemd.services.conway-automaton = {
    description = "Conway Automaton autonomous agent runtime";
    after = [
      "network-online.target"
      "anthropic-secret-proxy.service"
      "sops-nix.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${automaton-pkg}/bin/automaton --run";
      EnvironmentFile = config.sops.templates."automaton-env".path;
      User = "automaton";
      Group = "automaton";
      StateDirectory = "automaton";
      WorkingDirectory = "/var/lib/automaton";
      Environment = [
        "HOME=/var/lib/automaton"
        "NODE_ENV=production"
      ];
      Restart = "on-failure";
      RestartSec = "30s";

      # Systemd hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/automaton" ];
    };
  };
}
