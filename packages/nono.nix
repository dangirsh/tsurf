# packages/nono.nix — source build derivation for nono
# @decision SEC-160-05: Build nono from source to eliminate the prebuilt binary trust gap.
#   The nono-cli crate produces the nono binary, keeping the sandbox enforcer in the
#   launch path reproducible from pinned source.
{ pkgs }:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "nono";
  version = "0.22.0";

  src = pkgs.fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-O+zUbJja5SLeikYfIHp17zkAoyCSMnV4tm0U3oi0NfI=";
  };

  cargoHash = "sha256-QnopMhmWHn5aFqlk3xWr79jVPjz1keI5B7t1rxfdXpE=";
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
