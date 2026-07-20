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

  postPatch = ''
    substituteInPlace internal/transform/audit.go \
      --replace-fail $'import (\n\t"log/slog"\n)' $'import (\n\t"log/slog"\n\t"strings"\n)'
    substituteInPlace internal/transform/audit.go \
      --replace-fail 'slog.String("path", result.Path)' 'slog.String("path", redactAuditPath(result.Host, result.Path))'
    substituteInPlace internal/transform/audit.go \
      --replace-fail 'func buildTraceEntries(traces []TransformTrace) []traceEntry {' $'func redactAuditPath(host, path string) string {\n\thostOnly := host\n\tif before, _, ok := strings.Cut(host, ":"); ok {\n\t\thostOnly = before\n\t}\n\tif !strings.EqualFold(hostOnly, "api.telegram.org") || !strings.HasPrefix(path, "/bot") {\n\t\treturn path\n\t}\n\n\tremainder := path[len("/bot"):]\n\tseparator := strings.IndexByte(remainder, \'/\')\n\tif separator < 0 {\n\t\treturn "/bot[REDACTED]"\n\t}\n\treturn "/bot[REDACTED]" + remainder[separator:]\n}\n\nfunc buildTraceEntries(traces []TransformTrace) []traceEntry {'
    substituteInPlace internal/transform/audit_test.go \
      --replace-fail 'func TestAudit_RejectedRequest(t *testing.T) {' $'func TestAudit_RedactsTelegramBotTokenPath(t *testing.T) {\n\tconst token = "123456789:real-telegram-bot-token"\n\tresult := &PipelineResult{\n\t\tHost:       "api.telegram.org:443",\n\t\tMethod:     "POST",\n\t\tPath:       "/bot" + token + "/getUpdates",\n\t\tRemoteAddr: "127.0.0.1:12345",\n\t\tSNI:        "api.telegram.org",\n\t\tStartedAt:  time.Now(),\n\t\tDuration:   time.Millisecond,\n\t\tAction:     ActionContinue,\n\t\tStatusCode: 200,\n\t}\n\n\tparsed, raw := captureAuditLog(result)\n\taudit := parsed["audit"].(map[string]any)\n\trequire.Equal(t, "/bot[REDACTED]/getUpdates", audit["path"])\n\trequire.NotContains(t, raw, token)\n}\n\nfunc TestAudit_RejectedRequest(t *testing.T) {'
  '';

  vendorHash = "sha256-6KUQeShcgeOJwlP/aE8RlgfmtmGNC9MJjJtJ1BMREe4=";

  subPackages = [ "cmd/iron-proxy" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/ironsh/iron-proxy/internal/version.Version=v${version}"
  ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    go test ./internal/transform
    runHook postCheck
  '';
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
