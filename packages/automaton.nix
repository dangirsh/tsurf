# packages/automaton.nix
# @decision AUTO-01: buildNpmPackage with pnpm lockfile conversion
# @rationale: Matches claw-swap pattern; pnpm-lock.yaml converted to
#   package-lock.json for buildNpmPackage compatibility. better-sqlite3
#   native addon requires makeCacheWritable + explicit npm rebuild.
# @decision AUTO-02: Patch Anthropic API base URL to read ANTHROPIC_BASE_URL env var
# @rationale: Upstream hardcodes https://api.anthropic.com. Patch enables
#   the existing anthropic-secret-proxy (port 9091) for BYOK inference.
{ lib, buildNpmPackage, nodejs_22, python3, pnpm, src }:

buildNpmPackage rec {
  pname = "automaton";
  version = "0.2.0";
  inherit src;

  nodejs = nodejs_22;
  makeCacheWritable = true;
  npmDepsHash = "sha256-4obUMjlCE1J9g4dVsIuFz5eXyhabty6SigqWPUkzqW8=";

  postPatch = ''
    # Vendored lockfile generated from upstream pnpm lock to support buildNpmPackage.
    cp ${./automaton-package-lock.json} package-lock.json

    # Route Anthropic API calls through an environment-selectable base URL.
    substituteInPlace src/conway/inference.ts \
      --replace-fail \
        '"https://api.anthropic.com/v1/messages"' \
        '(process.env.ANTHROPIC_BASE_URL || "https://api.anthropic.com") + "/v1/messages"'
  '';

  nativeBuildInputs = [ python3 nodejs_22 ];

  buildPhase = ''
    runHook preBuild
    npx tsc
    npm rebuild better-sqlite3
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/@conway/automaton
    cp -r dist node_modules package.json $out/lib/node_modules/@conway/automaton/
    cp constitution.md $out/lib/node_modules/@conway/automaton/

    mkdir -p $out/bin
    echo '#!/bin/sh' > $out/bin/automaton
    echo "exec ${nodejs_22}/bin/node $out/lib/node_modules/@conway/automaton/dist/index.js \"\$@\"" >> $out/bin/automaton
    chmod +x $out/bin/automaton

    runHook postInstall
  '';

  meta = with lib; {
    description = "Conway Automaton - autonomous AI agent runtime";
    homepage = "https://github.com/Conway-Research/automaton";
    mainProgram = "automaton";
    platforms = [ "x86_64-linux" ];
  };
}
