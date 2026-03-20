# packages/nono.nix — prebuilt binary derivation for nono
{ pkgs }:
pkgs.stdenv.mkDerivation rec {
  pname = "nono";
  version = "0.16.0";
  src = pkgs.fetchurl {
    url = "https://github.com/always-further/nono/releases/download/v${version}/nono-v${version}-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-nQ/SBtU26fU/UZr0SNsIBCRr7qUeayYOKdG70h2/RYc=";
  };
  sourceRoot = ".";
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.dbus.lib pkgs.stdenv.cc.cc.lib ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -m755 -D nono $out/bin/nono
    runHook postInstall
  '';
  meta = with pkgs.lib; {
    description = "Zero-config security sandbox with credential injection";
    homepage = "https://github.com/always-further/nono";
    platforms = [ "x86_64-linux" ];
  };
}
