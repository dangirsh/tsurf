# packages/beads.nix
# @decision PKG-01: beads_rust pre-built binary from GitHub releases.
#   Building from source fails due to zipsign-api crate not compiling in the Nix sandbox.
#   SHA256 pinned per-release; accepted risk SEC11 (no signature verification).
{ stdenv, lib, fetchurl, autoPatchelfHook }:
stdenv.mkDerivation rec {
  pname = "br";
  version = "0.1.19";
  src = fetchurl {
    url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${version}/br-v${version}-linux_amd64.tar.gz";
    hash = "sha256-rL0PabvZxOLr+iOmZfmpB2tgoCxc/CQLVDFB8NRWHYY=";
  };
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  sourceRoot = ".";
  installPhase = ''
    runHook preInstall
    install -m755 -D br $out/bin/br
    runHook postInstall
  '';
  meta = with lib; {
    description = "Agent-first issue tracker (SQLite + JSONL)";
    homepage = "https://github.com/Dicklesworthstone/beads_rust";
    mainProgram = "br";
    platforms = [ "x86_64-linux" ];
  };
}
