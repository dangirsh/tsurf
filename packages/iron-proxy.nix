# packages/iron-proxy.nix — source build derivation for iron-proxy
{ pkgs }:

pkgs.buildGoModule rec {
  pname = "iron-proxy";
  version = "0.45.0";

  src = pkgs.fetchFromGitHub {
    owner = "ironsh";
    repo = "iron-proxy";
    rev = "v${version}";
    hash = "sha256-f3fbf5C9Ima3qJkVakrydtra5gxNEyTSKk2oVv+Zjg4=";
  };

  vendorHash = "sha256-6KUQeShcgeOJwlP/aE8RlgfmtmGNC9MJjJtJ1BMREe4=";

  subPackages = [ "cmd/iron-proxy" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/ironsh/iron-proxy/internal/version.Version=v${version}"
  ];

  doCheck = false;
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/iron-proxy" version | grep -F "v${version}" >/dev/null
    "$out/bin/iron-proxy" generate-ca --outdir "$TMPDIR" --name "tsurf install check" --expiry-hours 1 >/dev/null
    test -s "$TMPDIR/ca.crt"
    test -s "$TMPDIR/ca.key"
    runHook postInstallCheck
  '';

  meta = with pkgs.lib; {
    description = "MITM egress proxy with allowlists, credential injection, and audit logs";
    homepage = "https://github.com/ironsh/iron-proxy";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "iron-proxy";
  };
}
