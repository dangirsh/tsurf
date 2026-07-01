# packages/nono.nix — source build derivation for nono
# @decision SEC-160-05: Build nono from source to eliminate the prebuilt binary trust gap.
#   The nono-cli crate produces the nono binary, keeping the sandbox enforcer in the
#   launch path reproducible from pinned source.
{ pkgs }:
let
  upstreamVersion = "0.66.0";
in
pkgs.rustPlatform.buildRustPackage rec {
  pname = "nono";
  version = "${upstreamVersion}-tsurf.1";

  src = pkgs.fetchFromGitHub {
    owner = "nolabs-ai";
    repo = "nono";
    rev = "v${upstreamVersion}";
    hash = "sha256-8Bol6B3c0pb25FG7214e6rXSKcACeOOQAd+c+1lblV4=";
  };

  patches = [
    ./nono-env-uri.patch
    ./nono-no-run.patch
  ];

  cargoHash = "sha256-WqOiB+TylLsy44ZOwdGMwdKAmhqi8OXDqsKse67GOgs=";
  cargoBuildFlags = [
    "-p"
    "nono-cli"
  ];
  # Upstream cargo tests are not a practical gate here: on the target x86_64 host
  # they exceeded an hour. Keep a bounded installed-binary smoke check instead.
  doCheck = false;
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/nono" --help >/dev/null
    runHook postInstallCheck
  '';

  nativeBuildInputs = with pkgs; [ pkg-config ];
  buildInputs = with pkgs; [
    dbus.dev
    dbus.lib
    openssl
    stdenv.cc.cc.lib
  ];

  meta = with pkgs.lib; {
    description = "Zero-config security sandbox with credential injection";
    homepage = "https://github.com/always-further/nono";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
