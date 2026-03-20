# packages/pi-coding-agent.nix — prebuilt binary derivation for pi-coding-agent
# @decision PI-87-01: Pre-built binary from GitHub releases (same pattern as nono.nix).
#   Building from source requires Bun + tsgo + monorepo workspace orchestration.
# @decision PI-87-02: No autoPatchelfHook — Bun-compiled binaries embed JS bytecode
#   at a fixed offset from EOF. patchelf shifts ELF sections, corrupting the offset
#   and causing the binary to fall back to raw Bun mode. Instead: patchelf only sets
#   the interpreter, and LD_LIBRARY_PATH provides shared libraries.
{ pkgs }:
let
  libPath = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
in
pkgs.stdenv.mkDerivation rec {
  pname = "pi-coding-agent";
  version = "0.58.1";
  src = pkgs.fetchurl {
    url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-linux-x64.tar.gz";
    hash = "sha256-A1EQGBbfU/dCl31DfJXOUHc2i0G8v2hV5URjV0TsEQ0=";
  };
  sourceRoot = "pi";
  nativeBuildInputs = [ pkgs.makeWrapper pkgs.patchelf ];
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec $out/bin

    # Install binary + companion assets together in libexec/.
    # Pi resolves theme/WASM/docs relative to the binary's own directory,
    # NOT via PI_PACKAGE_DIR, so assets must be adjacent to the binary.
    install -m755 pi $out/libexec/pi
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $out/libexec/pi
    cp -r theme export-html docs examples package.json photon_rs_bg.wasm $out/libexec/

    # Wrapper script: sets env vars + LD_LIBRARY_PATH, calls the real binary.
    makeWrapper $out/libexec/pi $out/bin/pi \
      --set PI_PACKAGE_DIR "$out/libexec" \
      --set PI_SKIP_VERSION_CHECK "1" \
      --prefix LD_LIBRARY_PATH : "${libPath}"

    runHook postInstall
  '';
  meta = with pkgs.lib; {
    description = "AI coding agent CLI with read, bash, edit, write tools";
    homepage = "https://github.com/badlogic/pi-mono";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
