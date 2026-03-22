# packages/zmx.nix — prebuilt binary derivation for zmx
# @decision AGENT-132-01: Keep zmx as a pinned prebuilt binary in packages/.
#   zig2nix/source builds are not reliable under the repo's restricted
#   user-namespace/AppArmor environment, so the flake exports one canonical
#   SHA256-pinned derivation via overlays.default.
{ pkgs }:
pkgs.stdenv.mkDerivation rec {
  pname = "zmx";
  version = "0.3.0";
  src = pkgs.fetchurl {
    url = "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz";
    hash = "sha256-/K/xWB61pqPll4Gq13qMoGm0Q1vC/sQT3TI7RaTf3zI=";
  };
  sourceRoot = ".";
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -m755 -D zmx $out/bin/zmx
    runHook postInstall
  '';
  meta = with pkgs.lib; {
    description = "Session persistence for terminal processes";
    homepage = "https://github.com/neurosnap/zmx";
    platforms = [ "x86_64-linux" ];
  };
}
