{
  imports = [
    ./base.nix
    ./boot.nix
    ./users.nix
    ./networking.nix
    ./secrets.nix
    ./docker.nix
    ./monitoring.nix
    ./syncthing.nix
    ./agent-compute.nix
    ./secret-proxy.nix
    ./impermanence.nix
    ./restic.nix
    ./homepage.nix
  ];
}
