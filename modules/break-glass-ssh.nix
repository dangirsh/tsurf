# modules/break-glass-ssh.nix
# @decision SEC-70-01: Emergency SSH key — hardcoded, independent of sops-nix.
#   Survives sops failures, overlay misconfiguration, and key-management errors.
#   The "break-glass-emergency" comment is checked by a build-time assertion.
#
#   BEFORE DEPLOYING: replace the placeholder with a real ed25519 public key.
#   Generate: ssh-keygen -t ed25519 -C break-glass-emergency -f ~/.ssh/break-glass-emergency
#   Store the private key in a password manager AND an offline USB drive.
{ ... }: {
  users.users.root.openssh.authorizedKeys.keys = [
    # PLACEHOLDER: replace before deploying. Must be replaced by `tsurf init` or private overlay.
    # The comment MUST contain "break-glass-emergency" for the assertion to pass.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIb2ZbEP4YS7INuRcu/myeiajC/KD34yjfSssCnbggAJ break-glass-emergency"
  ];
}
