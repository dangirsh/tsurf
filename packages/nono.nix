# packages/nono.nix — prebuilt binary derivation for nono
{ pkgs }:
pkgs.stdenv.mkDerivation rec {
  pname = "nono";
  version = "0.22.0";
  src = pkgs.fetchurl {
    url = "https://github.com/always-further/nono/releases/download/v${version}/nono-v${version}-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-z8Bk7ylg1GPAoPEa3f8IoflnkyDPw2VtlK7wiqQD6Jo=";
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
