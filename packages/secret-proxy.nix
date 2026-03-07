{ pkgs, rustPlatform }:
rustPlatform.buildRustPackage {
  pname = "secret-proxy";
  version = "0.1.0";
  src = ./secret-proxy;
  cargoLock.lockFile = ./secret-proxy/Cargo.lock;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];

  meta = with pkgs.lib; {
    description = "Secret placeholder proxy for sandboxed agents";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
