# modules/sshd-liveness-check.nix
# @decision SEC-70-02: Automated sshd liveness check with auto-rollback on sustained failure.
#   Runs every 5 min. Checks: systemctl is-active sshd.service + ss port 22 bound.
#   3 consecutive failures (15 min sustained) trigger nixos-rebuild switch --rollback.
#   Anti-loop: skips rollback if one occurred <10 min ago (prevents infinite rollback
#   cycles when both current and previous generation have broken SSH).
#   Deploy-aware: skips checks during active deploys (deploy lock held) and when the
#   deploy-watchdog timer is active (deploy.sh manages rollback in that window).
#   This is a last-resort lockout prevention mechanism, not a general health monitor.
{ pkgs, ... }: {
  systemd.services.sshd-liveness-check = {
    description = "sshd liveness check — auto-rollback on sustained failure";
    serviceConfig = {
      Type = "oneshot";
      # @decision LIV-84-01: Hardened within constraints of root + nixos-rebuild rollback.
      # ProtectSystem omitted: nixos-rebuild switch --rollback needs filesystem writes.
      # NoNewPrivileges omitted: rollback execution path requires elevated operations.
      ProtectHome = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      LockPersonality = true;
      RestrictRealtime = true;
      MemoryDenyWriteExecute = true;
    };
    path = with pkgs; [ coreutils iproute2 systemd gnugrep nixos-rebuild ];
    script = builtins.readFile ../scripts/sshd-liveness-check.sh;
  };

  systemd.timers.sshd-liveness-check = {
    description = "sshd liveness check timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Delay first run 5 min after boot — avoids firing during the deploy-rs
      # 120s activation window or normal service startup after reboot.
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Persistent = true;
      RandomizedDelaySec = "30s";
    };
  };
}
