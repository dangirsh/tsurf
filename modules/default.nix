# Shared modules imported by all hosts. Host-specific modules added in hosts/*/default.nix.
{
  imports = [
    ./base.nix
    ./boot.nix
    ./users.nix
    ./networking.nix
    ./secrets.nix
    ./docker.nix
    ./syncthing.nix
    ./agent-compute.nix
    ./secret-proxy.nix
    ./impermanence.nix
  ];
}
