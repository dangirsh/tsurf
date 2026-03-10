# tests/vm/ssh-reachability.nix
# @decision TEST-70-01: VM-level integration test for SSH reachability.
#   Boots a VM with core neurosys modules and verifies sshd is functional end-to-end.
#   Catches SSH-breaking regressions that eval checks cannot detect (runtime config issues).
#
#   REQUIRES KVM — do not run on Contabo or OVH VPS (no nested virtualization).
#   Run locally or in KVM-capable CI:
#     nix build .#vm-test-ssh
#
#   What this tests:
#     - sshd.service starts and reaches active state
#     - Port 22 is bound and listening
#     - sshd config: no password auth, prohibit-password root login
#     - Root has authorized keys (from users.nix + break-glass-ssh.nix)
#     - Break-glass emergency key is present in authorized_keys
#     - AuthorizedKeysFile includes .ssh/authorized_keys (NET-14 fallback)
#     - SSH connection actually succeeds end-to-end via loopback
#
#   What this does NOT test:
#     - Impermanence (no BTRFS subvolumes in VM)
#     - sops secrets (no age key in VM, Tailscale disabled)
#     - External network reachability (loopback only)
#
#   Why networking.nix is NOT imported:
#     networking.nix has build-time assertions requiring Tailscale to be enabled and
#     SSH host key persisted via impermanence — both are legitimately absent in a VM test
#     environment. These assertions ARE covered by the eval checks in config-checks.nix.
#     The SSH settings from networking.nix that matter for this test are inlined below.
{ self, pkgs, lib, ... }:
pkgs.testers.runNixOSTest {
  name = "ssh-reachability";

  nodes.server = { config, lib, ... }: {
    imports = [
      ../../modules/users.nix
      ../../modules/break-glass-ssh.nix
    ];

    # --- SSH config (mirrors networking.nix settings) ---
    services.openssh = {
      enable = true;
      openFirewall = true;
      hostKeys = lib.mkForce [
        { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
        X11Forwarding = false;
        MaxAuthTries = 3;
        LoginGraceTime = 30;
      };
      # @decision NET-14: .ssh/authorized_keys listed first for impermanence fallback
      authorizedKeysFiles = lib.mkForce [ ".ssh/authorized_keys" "/etc/ssh/authorized_keys.d/%u" ];
    };

    # No GRUB in VM (NixOS test framework manages boot)
    boot.loader.grub.enable = lib.mkForce false;
  };

  testScript = ''
    server.start()
    server.wait_for_unit("sshd.service")
    server.wait_for_open_port(22)

    # sshd is listening on port 22
    server.succeed("ss -tlnp | grep ':22 '")

    # sshd config: no password auth, root login allowed (key-only)
    server.succeed("sshd -T | grep -i 'passwordauthentication no'")
    server.succeed("sshd -T | grep -i 'permitrootlogin prohibit-password'")

    # Root has authorized keys from users.nix and break-glass-ssh.nix
    server.succeed("test -s /etc/ssh/authorized_keys.d/root")

    # Break-glass emergency key is present
    server.succeed("grep 'break-glass-emergency' /etc/ssh/authorized_keys.d/root")

    # AuthorizedKeysFile includes .ssh/authorized_keys (NET-14 fallback)
    server.succeed("sshd -T | grep -i 'authorizedkeysfile' | grep '.ssh/authorized_keys'")

    # SSH loopback connection succeeds with a generated test key
    server.succeed(
      "ssh-keygen -t ed25519 -f /tmp/test-key -N '''' -q && "
      "mkdir -p /root/.ssh && "
      "cat /tmp/test-key.pub >> /root/.ssh/authorized_keys && "
      "chmod 600 /root/.ssh/authorized_keys && "
      "ssh -o StrictHostKeyChecking=no -o BatchMode=yes "
      "    -i /tmp/test-key root@127.0.0.1 true"
    )
  '';
}
