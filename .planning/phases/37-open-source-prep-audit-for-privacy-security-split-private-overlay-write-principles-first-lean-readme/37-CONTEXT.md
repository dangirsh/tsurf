# Phase 32: Open Source Prep - Context

**Gathered:** 2026-02-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Prepare the neurosys NixOS configuration for public open source release. Three distinct outputs: (1) a privacy-audited public repo with personal identifiers removed, (2) a private flake overlay repo that adds personal config on top, and (3) a lean public-facing README. Creating new features or services is out of scope.

</domain>

<decisions>
## Implementation Decisions

### Privacy boundary — what gets redacted

- **IPs**: Scrub all IP addresses (161.97.74.121, 135.125.196.143, etc.) — not in public repo
- **Hostnames**: Keep generic hostnames (neurosys, neurosys-prod) — they're not sensitive
- **Username**: Abstract `dangirsh` to a placeholder (e.g., `myuser`) — SSH keys and tokens become example placeholders; real values in private overlay
- **External repos and domains**: Replace `parts`, `claw-swap`, `dangirsh-site`, `dangirsh.org`, `clawswap.org` with placeholder examples (`example-service`, `myapp`, `example.com`); real wiring in private overlay
- **Secrets files**: Remove `secrets/neurosys.yaml`, `secrets/ovh.yaml`, `.sops.yaml` entirely from public repo — add a `secrets/` README explaining the sops-nix pattern; real secrets in private overlay

### Overlay split design

- **Mechanism**: Separate private GitHub repo (e.g., `neurosys-private`) that imports the public repo as a flake input and overrides/extends it. Public repo = pure infrastructure patterns; private repo = personal config, secrets, hosts.
- **Public/private relationship**: Researcher to investigate and recommend the best module export pattern (nixosModules.default vs mkHost helper vs other). Researcher should look at how similar NixOS config libraries structure this.
- **Private overlay must contain**: secrets files, host configs with real IPs/keys, personal service modules (claw-swap, parts, dangirsh-site), personal flake inputs for private repos — everything personal stays private
- **Public repo standalone-ability**: Claude's discretion — design for whichever approach is simpler and more useful to forkers

### Public README style

- **Audience**: Linux users wanting an agentic-dev platform. Not NixOS beginners. No hand-holding.
- **Style reference**: [stereos by papercompute.co](https://github.com/papercomputeco/stereos) — extremely concise, table-heavy, immediately technical, no verbose setup instructions
- **One-line opener**: Directly state what this is. No preamble.
- **Lead with**: Design philosophy after the one-liner (declarative, batteries-included, agentic-dev-first, Tailscale-only networking)
- **Content approach**: Keep everything from the current README that doesn't reference private config; move private-specific operational content to private overlay's README
- **Format**: Tables over prose, bullets over paragraphs, minimal. Similar density to stereos README.

### Release scope — what goes public vs private

- **Agent tooling (ALL public)**: `agent-compute.nix`, bubblewrap sandbox, secret proxy module, llm-agents overlay — this is the main value prop
- **Infrastructure modules (public)**: Monitoring (Prometheus + node_exporter), Restic backup, networking/firewall patterns, sops-nix patterns, deploy-rs setup, impermanence, srvos hardening, Docker (with `--iptables=false`), fail2ban
- **Generic services (public)**: Syncthing pattern, homepage dashboard (with placeholder URLs)
- **Personal services (private overlay only)**: Home Assistant, ESPHome, Spacebot — too personal/specific to be useful examples
- **Planning docs**: `.planning/` goes in `.gitignore` — not included in public repo. No ROADMAP.md, STATE.md, or phase plans.

### Claude's Discretion

- Whether the public repo should be deployable standalone with placeholders, or purely a library — whichever approach is simpler and serves forkers better
- Exact module export pattern for the public/private repo interface (research this)
- Which exact lines/values to abstract in each module (do a thorough audit)

</decisions>

<specifics>
## Specific Ideas

- stereos README (https://github.com/papercomputeco/stereos) is the style reference for the public README — very sparse, immediately technical, table-heavy
- Audience is "Linux users wanting agentic-dev" — not NixOS beginners, not general sysadmins
- The agent tooling (agent-spawn, bubblewrap, secret proxy) is the primary differentiator worth showing off
- `.planning/` entirely gitignored — no project history in public repo

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 37-open-source-prep**
*Context gathered: 2026-02-27*
