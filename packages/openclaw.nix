# packages/openclaw.nix
# @decision OCL-PKG-01: Build from npm registry tarball, not source repo.
# @rationale: Published npm package ships pre-built dist/ assets and avoids pnpm
#   workspace conversion in Nix.
#
# @decision OCL-PKG-02: Strip node-llama-cpp from the output.
# @rationale: This deployment uses Anthropic API-only and does not run local
#   inference, so shipping llama artifacts has no runtime value.
{ lib, buildNpmPackage, fetchurl, runCommand, gnutar, gzip, nodejs_22, python3 }:

let
  version = "2026.3.2";

  upstreamTarball = fetchurl {
    url = "https://registry.npmjs.org/openclaw/-/openclaw-${version}.tgz";
    hash = "sha256-PsmckwA3JcOvs9jDI29/twVGR9FR3Ce54CVuADcvMbc=";
  };

  # Upstream tarball does not ship package-lock.json. Inject a generated lockfile
  # so npm dependency prefetch remains deterministic.
  srcWithLock = runCommand "openclaw-${version}-src-with-lock" {
    nativeBuildInputs = [ gnutar gzip ];
  } ''
    mkdir -p "$out"
    tar -xzf ${upstreamTarball} --strip-components=1 -C "$out"
    cp ${./openclaw-package-lock.json} "$out/package-lock.json"
  '';
in
buildNpmPackage rec {
  pname = "openclaw";
  inherit version;

  src = srcWithLock;
  nodejs = nodejs_22;
  makeCacheWritable = true;
  dontNpmBuild = true;

  npmDepsHash = "sha256-KvawSBKYVjJx1WVShtR4WpyeOuVPNJTbuzABrPsUpFI=";
  npmFlags = [ "--ignore-scripts" "--legacy-peer-deps" ];
  nativeBuildInputs = [ python3 nodejs_22 ];

  buildPhase = ''
    runHook preBuild
    npm rebuild better-sqlite3 2>/dev/null || true
    npm rebuild sqlite-vec 2>/dev/null || true
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/node_modules/openclaw"
    cp -r . "$out/lib/node_modules/openclaw/"

    # OCL-PKG-02: remove local-LLM dependency trees when present.
    find "$out/lib/node_modules/openclaw" -type d -name 'node-llama-cpp' -prune -exec rm -rf {} +

    mkdir -p "$out/bin"
    cat > "$out/bin/openclaw" <<EOF
#!/bin/sh
exec ${nodejs_22}/bin/node "$out/lib/node_modules/openclaw/openclaw.mjs" "\$@"
EOF
    chmod +x "$out/bin/openclaw"
    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenClaw - self-hosted AI assistant with messaging integrations";
    homepage = "https://openclaw-ai.online";
    mainProgram = "openclaw";
    platforms = platforms.linux;
    license = licenses.mit;
  };
}
