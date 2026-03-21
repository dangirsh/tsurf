# tests/vm/sandbox-behavioral.nix — NixOS VM test for sandbox boundary behavior.
#
# Tests the user privilege separation model: agent user exists, is not in
# wheel/docker, and cannot read root-owned secrets. This is an OS-level smoke
# test for the user privilege model, NOT a full nono Landlock test. The live
# BATS tests in tests/live/sandbox-behavioral.bats exercise the full nono
# sandbox on a deployed host.
#
# Run: nix build .#vm-test-sandbox
# Requires: KVM (not available on GitHub Actions ubuntu-latest)
{ pkgs, lib, ... }:
pkgs.testers.nixosTest {
  name = "sandbox-behavioral";

  nodes.machine = { config, pkgs, ... }: {
    imports = [
      ../../modules/users.nix
    ];

    # Gate insecure template defaults (passwordless login for eval)
    tsurf.template.allowUnsafePlaceholders = true;

    # Create a fake secret file via activation script.
    # sops-nix cannot be used in VM tests (no age key, no encrypted secrets file).
    # This creates a root-owned 0600 file to test that the agent user is denied
    # by standard Unix file permissions.
    system.activationScripts.test-secrets = ''
      mkdir -p /run/secrets
      echo "test-key-value" > /run/secrets/anthropic-api-key
      chmod 600 /run/secrets/anthropic-api-key
      chown root:root /run/secrets/anthropic-api-key
    '';

    # Create a test git repo for the read-access check
    system.activationScripts.test-repo = ''
      mkdir -p /data/projects/test-repo
      cd /data/projects/test-repo
      if [ ! -d .git ]; then
        ${pkgs.git}/bin/git init
        echo "test content" > test-file.txt
        ${pkgs.git}/bin/git add .
        ${pkgs.git}/bin/git -c user.email=test@test -c user.name=test commit -m "init"
      fi
      chown -R agent:agent /data/projects/test-repo
    '';
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # 1. Agent user identity — verify user exists and is not privileged
    result = machine.succeed("sudo -u agent whoami").strip()
    assert result == "agent", f"Expected 'agent', got '{result}'"

    result = machine.succeed("sudo -u agent id")
    assert "wheel" not in result, f"Agent in wheel group: {result}"
    assert "docker" not in result, f"Agent in docker group: {result}"

    # Verify agent is not root
    uid = machine.succeed("sudo -u agent id -u").strip()
    assert uid != "0", f"Agent has root UID: {uid}"

    # 2. Denied: /run/secrets (OS file permission check)
    #    NOTE: This tests OS-level user privilege separation, NOT nono Landlock.
    #    The file is owned root:root mode 0600 — the agent user (non-root, non-wheel)
    #    must be denied by standard Unix permissions. The live BATS tests exercise
    #    the full nono Landlock sandbox on a deployed host.
    machine.fail("sudo -u agent cat /run/secrets/anthropic-api-key")

    # 3. Agent can read files in a project directory it owns
    result = machine.succeed(
        "sudo -u agent cat /data/projects/test-repo/test-file.txt"
    ).strip()
    assert result == "test content", f"Expected 'test content', got '{result}'"

    # 4. Agent cannot read root-owned secrets via alternate paths
    machine.fail("sudo -u agent bash -c 'cat /run/secrets/anthropic-api-key'")
  '';
}
