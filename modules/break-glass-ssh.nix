# modules/break-glass-ssh.nix
# @decision SEC-70-01: Emergency SSH key — hardcoded, independent of sops-nix.
#   This key survives sops activation failures, private overlay users.nix replacement,
#   and any misconfiguration of the normal key-management path. It is the last-resort
#   recovery key when all other access paths are broken.
#   The key comment "break-glass-emergency" is checked by a build-time assertion in
#   networking.nix to prevent accidental removal.
#
#   BEFORE DEPLOYING: replace the placeholder below with a real ed25519 public key.
#   Generate: ssh-keygen -t ed25519 -C break-glass-emergency -f ~/.ssh/break-glass-emergency
#   Store the private key in a password manager AND an offline USB drive.
#   Never store the private key on any server or in any git repository.
{ ... }: {
  users.users.root.openssh.authorizedKeys.keys = [
    # PLACEHOLDER: replace before deploying. Must be replaced by `tsurf init` or private overlay.
    # The comment MUST contain "break-glass-emergency" for the assertion to pass.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIb2ZbEP4YS7INuRcu/myeiajC/KD34yjfSssCnbggAJ break-glass-emergency"
  ];
}
