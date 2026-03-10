---
status: passed
---

# Phase 71 Verification

## Must-Haves Check

### Plan 71-01

- ✓ **README.md credits Stanislas Polu's Netclode post with the full URL**
  README.md line 9 links to the full URL:
  `https://stanislas.blog/2026/02/netclode-self-hosted-cloud-coding-agent/#secret-proxy-api-keys-never-enter-the-sandbox`

- ✓ **`docs/architecture.md` exists**
  Present at `/data/projects/nix-secret-proxy/docs/architecture.md`.

- ✓ **architecture.md: pattern overview**
  "What problem does this solve?" section describes the placeholder substitution pattern.

- ✓ **architecture.md: ASCII data flow diagram**
  Full ASCII diagram with sandbox box, proxy steps (1–6), and upstream arrow present (lines 29–52).

- ✓ **architecture.md: security model with explicit "does not protect" section**
  "What the proxy protects against" and "What the proxy does NOT protect against" sections both present (lines 88–101).

- ✓ **architecture.md: Netclode comparison**
  "Prior art and attribution" section (lines 10–24) details the full URL, Netclode's HTTPS MITM + ServiceAccount token validation additions, and the tradeoff.

- ✓ **architecture.md: placeholder format note**
  "Placeholder format and SDK compatibility" section (lines 112–115) explains the `sk-ant-api03-*` prefix requirement.

- ✓ **`docs/deployment-nixos.md` covers bwrapArgs wiring**
  "Wiring into bubblewrap" section (lines 79–100) shows the `bwrapArgs` attribute, expands to `["--setenv" "ANTHROPIC_BASE_URL" "http://127.0.0.1:9091"]`, and shows full bwrap invocation.

- ✓ **deployment-nixos.md covers the sops-nix owner requirement**
  "Access control" section (lines 120–124) explicitly states the secret file must be readable by the `secret-proxy-<name>` user and shows `sops.secrets."anthropic-api-key".owner = "secret-proxy-my-agent"`.

- ✓ **`docs/deployment-docker.md` documents the loopback binding limitation explicitly**
  First section "Limitation: loopback binding" (lines 5–9) explicitly states Docker containers cannot reach host loopback by default and documents the `network_mode: host` workaround.

- ✓ **`docs/deployment-systemd.md` includes a complete systemd unit with `LoadCredential=`**
  Full unit at lines 29–68 includes `LoadCredential=anthropic-api-key:/etc/secret-proxy/anthropic-api-key.encrypted` and comprehensive hardening directives.

- ✓ **No code changes made — documentation files only**
  Git log shows all 71-01/71-02 commits are prefixed `docs(71-0*)`:
  - `docs(71-02): add known-issues.md with 12 code-verified issue entries`
  - `docs(71-01): add deployment-systemd.md with LoadCredential example and hardening`
  - `docs(71-01): add deployment-docker.md with loopback limitation and Swarm example`
  - `docs(71-01): add deployment-nixos.md with sops-nix, agenix, bwrapArgs wiring`
  - `docs(71-01): add architecture.md with pattern overview, security model, attribution`
  - `docs(71-01): rewrite README as canonical pattern entry point`
  No Rust source, Nix, or TOML changes in these commits.

### Plan 71-02

- ✓ **`docs/known-issues.md` exists with all 12 issues**
  Summary table lists exactly 12 entries: BLOCK-01, BLOCK-02, DEG-01–DEG-04, INFO-01–INFO-06.

- ✓ **2 BLOCKING entries present**
  BLOCK-01 (Bind address hardcoded) and BLOCK-02 (Placeholder format rejected by Anthropic SDK).

- ✓ **4 DEGRADED entries present**
  DEG-01 (no upstream timeout), DEG-02 (2 MB body limit), DEG-03 (plain-text 502), DEG-04 (no graceful shutdown).

- ✓ **6 INFORMATIONAL entries present**
  INFO-01 through INFO-06.

- ✓ **Each BLOCKING/DEGRADED entry includes: severity, status, affected deployments, description with code reference, and proposed mitigation**
  Verified for all 6 entries. Each has `**Severity:**`, `**Status:**`, `**Affects:**`, `**Description:**` with inline code snippet from the relevant source file, and `**Proposed mitigation**` with concrete implementation detail.

- ✓ **BLOCK-01 explicitly states the Docker implication and workaround**
  "Impact" paragraph states: "Any Docker Compose deployment where the proxy and agent are on different container network namespaces cannot use the proxy without `network_mode: host`." Workaround links to deployment-docker.md.

- ✓ **BLOCK-02 explicitly states the `sk-ant-api03-*` prefix requirement**
  "Description" states: "Keys must match the prefix `sk-ant-api03-`." Shows the default placeholder from `module.nix` (`sk-placeholder-${name}`) that fails this check.

- ✓ **INFO-02 cross-references Netclode in architecture.md as a more capable alternative**
  INFO-02 "Rationale" states: "Stanislas Polu's Netclode implementation (see [architecture.md](architecture.md)) adds per-caller ServiceAccount token validation and per-caller key pools for stronger isolation at higher setup cost."

- ✓ **Summary table covers all 12 entries**
  Table at lines 222–235 lists all 12 IDs with title, severity, and status.

## Phase Goal Assessment

The phase goal was to transform `nix-secret-proxy` into a canonical reference for the "API key placeholder substitution proxy" pattern, making it adoptable by non-NixOS projects without code changes.

This is fully achieved:

- The README is rewritten as a pattern entry point with quick-start examples for NixOS, Docker Compose, and plain systemd — not just NixOS-centric.
- `docs/architecture.md` provides a standalone conceptual description (problem statement, data flow diagram, security model, Netclode comparison, SDK compatibility note) that any reader can understand without NixOS knowledge.
- Three concrete deployment guides cover the main non-NixOS adoption paths: Docker Compose, plain systemd, and NixOS. Each is self-contained with config examples.
- `docs/known-issues.md` gives adopters accurate expectations about limitations before they invest in integration — BLOCK-01 and BLOCK-02 are the most practically important for new users.
- All changes are documentation only; no source code was modified.

## Issues

None — all must-haves are met.
