# tests/vm/sandbox-behavioral.nix — NixOS VM test for sandbox boundary behavior.
#
# Tests the user privilege separation model: agent user exists, is not in
# wheel, cannot read root-owned wrapper secrets, and cannot read other
# operator-only secrets. This is an OS-level smoke test for the user and
# secret-ownership model, NOT a full nono Landlock test. The live BATS tests in
# tests/live/sandbox-behavioral.bats exercise the full nono sandbox on a
# deployed host.
#
# Run: nix build .#vm-test-sandbox
# Requires: KVM (not available on GitHub Actions ubuntu-latest)
{ pkgs, lib, impermanenceModule, ... }:
pkgs.testers.nixosTest {
  name = "sandbox-behavioral";

  nodes.machine = { config, pkgs, ... }: {
    imports = [
      impermanenceModule
      ../../modules/users.nix
    ];

    # Gate insecure template defaults (passwordless login for eval)
    tsurf.template.allowUnsafePlaceholders = true;

    # Create fake secret files via activation script.
    # sops-nix cannot be used in VM tests (no age key, no encrypted secrets
    # file). Model both ownership classes explicitly:
    # - anthropic-api-key: wrapper-consumed API secret, root-owned
    # - root-only-example: operator-only secret, unreadable to the agent user
    system.activationScripts.test-secrets = ''
      mkdir -p /run/secrets
      echo "test-key-value" > /run/secrets/anthropic-api-key
      chmod 400 /run/secrets/anthropic-api-key
      chown root:root /run/secrets/anthropic-api-key

      echo "root-only-value" > /run/secrets/root-only-example
      chmod 600 /run/secrets/root-only-example
      chown root:root /run/secrets/root-only-example
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
      chown -R ${config.tsurf.agent.user}:${config.tsurf.agent.user} /data/projects/test-repo
    '';
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    agent_user = machine.succeed(
        "getent passwd | awk -F: '$3 >= 1000 && $1 != \"dev\" { print $1; exit }'"
    ).strip()
    assert agent_user != "", "Could not determine configured agent user"

    # 1. Agent user identity — verify user exists and is not privileged
    result = machine.succeed(f"sudo -u {agent_user} whoami").strip()
    assert result == agent_user, f"Expected '{agent_user}', got '{result}'"

    result = machine.succeed(f"sudo -u {agent_user} id")
    assert "wheel" not in result, f"Agent in wheel group: {result}"
    assert "docker" not in result, f"Agent in docker group: {result}"

    # Verify agent is not root
    uid = machine.succeed(f"sudo -u {agent_user} id -u").strip()
    assert uid != "0", f"Agent has root UID: {uid}"

    # 2. Wrapper-consumed API secrets are root-owned in this fixture, so the
    #    agent user cannot read them by normal Unix permissions. The live BATS
    #    tests exercise the full brokered path separately.
    machine.fail(f"sudo -u {agent_user} cat /run/secrets/anthropic-api-key")

    # 3. Agent can read files in a project directory it owns
    result = machine.succeed(
        f"sudo -u {agent_user} cat /data/projects/test-repo/test-file.txt"
    ).strip()
    assert result == "test content", f"Expected 'test content', got '{result}'"

    # 4. Agent cannot read root-owned operator secrets by standard Unix permissions.
    machine.fail(f"sudo -u {agent_user} cat /run/secrets/root-only-example")
    machine.fail(f"sudo -u {agent_user} bash -c 'cat /run/secrets/root-only-example'")
  '';
}
