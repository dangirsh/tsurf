# packages/cass.nix
# @decision SVC-03: CASS pre-built binary from GitHub, patched with autoPatchelfHook
{ stdenv, lib, fetchurl, autoPatchelfHook, openssl, zlib }:
stdenv.mkDerivation rec {
  pname = "cass";
  version = "0.1.64";
  src = fetchurl {
    url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${version}/cass-linux-amd64.tar.gz";
    hash = "sha256-buO1m9emp6rJTHkHUayaNSzAQYAxLwhYrQxCJHUaixE=";
  };
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib openssl zlib ];
  sourceRoot = ".";
  installPhase = ''
    runHook preInstall
    install -m755 -D cass $out/bin/cass
    runHook postInstall
  '';
  meta = with lib; {
    description = "Unified CLI/TUI to index and search coding agent session history";
    homepage = "https://github.com/Dicklesworthstone/coding_agent_session_search";
    platforms = [ "x86_64-linux" ];
  };
}
