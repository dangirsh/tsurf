# packages/zmx.nix
# @decision: zmx pre-built static binary from zmx.sh (zig2nix flake build requires
#   bwrap which fails under apparmor-restricted user namespaces)
{ stdenv, lib, fetchurl }:
stdenv.mkDerivation rec {
  pname = "zmx";
  version = "0.3.0";
  src = fetchurl {
    url = "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz";
    hash = "sha256-/K/xWB61pqPll4Gq13qMoGm0Q1vC/sQT3TI7RaTf3zI=";
  };
  sourceRoot = ".";
  installPhase = ''
    runHook preInstall
    install -m755 -D zmx $out/bin/zmx
    runHook postInstall
  '';
  meta = with lib; {
    description = "Session persistence for terminal processes";
    homepage = "https://github.com/neurosnap/zmx";
    platforms = [ "x86_64-linux" ];
  };
}
