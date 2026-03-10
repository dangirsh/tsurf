# modules/ssh-canary.nix
# @decision SEC-70-02: Automated SSH canary with auto-rollback on sustained failure.
#   Runs every 5 min. Checks: systemctl is-active sshd.service + ss port 22 bound.
#   3 consecutive failures (15 min sustained) trigger nixos-rebuild switch --rollback.
#   Anti-loop: skips rollback if one occurred <10 min ago (prevents infinite rollback
#   cycles when both current and previous generation have broken SSH).
#   Deploy-aware: skips checks during active deploys (deploy lock held) and when the
#   deploy-watchdog timer is active (deploy.sh manages rollback in that window).
#   This is a last-resort lockout prevention mechanism, not a general health monitor.
{ pkgs, ... }: {
  systemd.services.ssh-canary = {
    description = "SSH connectivity canary — auto-rollback on sustained failure";
    serviceConfig = {
      Type = "oneshot";
      # Run as root — required for nixos-rebuild switch --rollback
    };
    path = with pkgs; [ coreutils iproute2 systemd gnugrep nixos-rebuild ];
    script = ''
      set -euo pipefail

      STATE_DIR="/var/lib/ssh-canary"
      FAILURE_FILE="$STATE_DIR/failure-count"
      LAST_ROLLBACK_FILE="$STATE_DIR/last-rollback"
      mkdir -p "$STATE_DIR"

      # Skip during active deploys — deploy-rs has its own rollback mechanism.
      if [ -d /var/lock/neurosys-neurosys-deploy.lock ] || \
         [ -d /var/lock/neurosys-ovh-deploy.lock ]; then
        echo "ssh-canary: deploy in progress — skipping check"
        exit 0
      fi

      # Skip when deploy-watchdog timer is active (deploy.sh manages rollback)
      if systemctl is-active --quiet deploy-watchdog.timer 2>/dev/null; then
        echo "ssh-canary: deploy watchdog active — skipping check"
        exit 0
      fi

      # Check 1: sshd.service is active
      SSHD_OK=true
      if ! systemctl is-active --quiet sshd.service; then
        echo "ssh-canary: FAIL — sshd.service is not active"
        SSHD_OK=false
      fi

      # Check 2: port 22 is bound
      PORT_OK=true
      if ! ss -tlnp | grep -q ':22 '; then
        echo "ssh-canary: FAIL — port 22 is not bound"
        PORT_OK=false
      fi

      # Both checks passed — reset failure counter
      if [ "$SSHD_OK" = true ] && [ "$PORT_OK" = true ]; then
        echo "ssh-canary: OK"
        echo 0 > "$FAILURE_FILE"
        exit 0
      fi

      # Increment failure counter
      FAILURES=$(cat "$FAILURE_FILE" 2>/dev/null || echo 0)
      FAILURES=$((FAILURES + 1))
      echo "$FAILURES" > "$FAILURE_FILE"
      echo "ssh-canary: failure $FAILURES/3"

      # Only rollback after 3 consecutive failures (15 min of sustained breakage)
      if [ "$FAILURES" -lt 3 ]; then
        exit 0
      fi

      # Anti-loop: skip rollback if one occurred <10 min ago
      if [ -f "$LAST_ROLLBACK_FILE" ]; then
        LAST_TIME=$(cat "$LAST_ROLLBACK_FILE")
        NOW=$(date +%s)
        ELAPSED=$((NOW - LAST_TIME))
        if [ "$ELAPSED" -lt 600 ]; then
          echo "ssh-canary: SKIPPING rollback (rolled back ''${ELAPSED}s ago, <10 min)"
          echo "Manual recovery required — see docs/oob-recovery.md"
          echo 0 > "$FAILURE_FILE"
          exit 1
        fi
      fi

      # 3 consecutive failures, no recent rollback — trigger rollback
      echo "ssh-canary: 3 consecutive failures — triggering NixOS generation rollback"
      echo 0 > "$FAILURE_FILE"
      date +%s > "$LAST_ROLLBACK_FILE"
      nixos-rebuild switch --rollback 2>&1 || {
        echo "ssh-canary: rollback FAILED — manual recovery required (see docs/oob-recovery.md)"
        exit 1
      }
      echo "ssh-canary: rollback completed"
    '';
  };

  systemd.timers.ssh-canary = {
    description = "SSH connectivity canary timer";
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
