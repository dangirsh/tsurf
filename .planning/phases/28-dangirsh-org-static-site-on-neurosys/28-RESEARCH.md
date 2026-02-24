# Phase 28: dangirsh.org Static Site on Neurosys - Research

**Researched:** 2026-02-23
**Domain:** NixOS nginx, ACME/Let's Encrypt, Hakyll static site generator, DNS migration, Nix builds for Haskell
**Confidence:** HIGH (NixOS nginx+ACME is extremely well-documented; Hakyll is standard Haskell; site is small and simple)

## Summary

This phase moves dangirsh.org from NearlyFreeSpeech (NFS) hosting to the neurosys infrastructure, using NixOS-native nginx with ACME (Let's Encrypt) TLS certificates. The site is a Hakyll-based static site (Haskell generator compiling Org-mode posts into HTML). The existing `default.nix` builds via a pinned nixpkgs-20.03 with `ghcWithPackages`. The site is tiny (~140KB generated output) with 6 blog posts, static pages, CSS, images, and a "Fire Weekly News" interactive page.

**Primary recommendation:** 3 plans: (1) Nix build for dangirsh-site (modernize `default.nix` into a flake or Nix derivation compatible with nixpkgs-25.11, add as flake input or build-time derivation), (2) nginx + ACME NixOS module (public-facing nginx serving the built site, Let's Encrypt certificates, firewall integration), (3) DNS cutover + NFS deprecation (update DNS A record, verify HTTPS, document NFS decommission steps).

## Current State

### dangirsh.org Site Repository

**Location:** `github:dangirsh/dangirsh.org` (cloned locally at `/data/projects/dangirsh-site`)
**Branch:** `master`
**Generator:** Hakyll 4.16 (Haskell static site generator)
**Content format:** Org-mode (`.org` files) and Markdown (`.md` files)
**Build system:** Two paths exist:
1. **Nix build** (`default.nix`): Pinned to nixpkgs-20.03, uses `ghcWithPackages` to compile `generator/site.hs`, then runs the generator on `site/` to produce `_site/`
2. **Cabal build** (`build.sh`): Uses `cabal build` in `generator/`, copies binary, runs generator

**Site structure:**
```
site/
  index.html          # Home page template (Hakyll)
  about.md            # About page
  contact.md          # Contact page
  posts/              # 6 blog posts (.org files)
  misc/               # Misc content
  projects/           # Project pages
  templates/          # Hakyll templates (default.html, post.html, etc.)
  css/                # Stylesheets (default.css, hack-subset.css, syntax.css)
  img/                # Images (favicon.png, headshot.jpg)
  doc/                # Documents (gpg.txt, resume.pdf)
  audio/              # Audio files
  fire/               # Fire Weekly News (standalone HTML app)
  fonts/              # Web fonts
  keybase.txt         # Keybase verification
  .htaccess           # Apache caching config (NFS-specific, not needed for nginx)
```

**Generated output:** `site/_site/` - roughly 17 files, ~140KB total

**Hakyll generator** (`generator/site.hs`):
- Compiles Org/Markdown posts via Pandoc with MathJax support
- Static file passthrough for images, docs, audio, fire/
- CSS compression
- Template-based rendering with post dates
- Dependencies: hakyll >= 4.16, pandoc >= 3.0, containers

**External services referenced in templates:**
- GoatCounter analytics (`dangirsh.goatcounter.com/count`)
- MathJax (for math rendering in posts)

### Current Deployment to NearlyFreeSpeech

- **IP:** 208.94.117.137 (NFS shared hosting)
- **Server:** Apache (visible in HTTP headers)
- **DNS:** Google Domains nameservers (`ns-cloud-d*.googledomains.com`)
- **A record:** `dangirsh.org` -> `208.94.117.137`, `www.dangirsh.org` -> `208.94.117.137`
- **Deploy method:** `publi.sh` runs `build.sh` then `rsync -avz --delete site/_site/ dangirsh.org:/home/public/`
- **Authentication:** NFS password from 1Password (`sshpass -p` with password auth)
- **TLS:** Handled by NFS (likely shared certificate or Let's Encrypt on their end)

### Neurosys Infrastructure (Relevant)

**Firewall already allows ports 80 and 443:**
```nix
# modules/networking.nix line 52
networking.firewall.allowedTCPPorts = [ 80 443 22000 ];
```
These ports are open for claw-swap's Docker-based Caddy. Adding nginx on the host will share these ports.

**No existing nginx service.** Caddy runs inside a Docker container for claw-swap only. The host has no web server.

**Impermanence:** Ephemeral root with `/persist` for stateful data. ACME certificate state needs persistence.

**Multi-host:** `neurosys` (Contabo, staging) and `ovh` (OVH, production). dangirsh.org should be served from the production host (OVH: 135.125.196.143) once Phase 27 is complete.

## Architecture Decisions

### Decision 1: nginx vs Caddy for Static Site Serving

| Option | Pros | Cons |
|--------|------|------|
| **NixOS nginx** | First-class NixOS module, battle-tested, ~5 lines config for static site, fine-grained cache control, `services.nginx.virtualHosts` with built-in ACME | More verbose config than Caddy |
| **NixOS Caddy** | Simpler config syntax, automatic HTTPS | Phase 13 deferred Caddy adoption; claw-swap already uses Caddy in Docker (potential confusion); Caddy on host would conflict with Docker Caddy on ports 80/443 |
| **Docker Caddy** | Consistent with existing pattern | Over-engineered for a static site; adds Docker container overhead; mixes concerns |

**Recommendation: NixOS nginx.** Ports 80/443 are already in `allowedTCPPorts`. The claw-swap Docker Caddy binds to these ports via Docker port mapping. This creates a **port conflict** that must be resolved (see Decision 3). nginx is the standard NixOS choice for static file serving, and `services.nginx` has excellent ACME integration.

### Decision 2: Hakyll Build Strategy

The existing `default.nix` pins nixpkgs-20.03 and uses `ghcWithPackages`. This is 6 years old and will not work with nixpkgs-25.11's GHC/Hakyll versions.

| Option | Pros | Cons |
|--------|------|------|
| **A: Modernize default.nix to flake** | First-class nix flake build, reproducible, can be a flake input | Haskell package builds are notoriously fragile across GHC versions; Hakyll+Pandoc dependency tree is complex |
| **B: Nix derivation in neurosys** | Keep build in neurosys flake, avoid separate flake for tiny project | Mixes site build concerns into server config |
| **C: Pre-build site, serve static output** | Zero build complexity on server; commit `_site/` or build in CI and copy | Not fully declarative; requires separate build step |
| **D: IFD (Import From Derivation) with pinned nixpkgs** | Use the site's own pinned nixpkgs for the Hakyll build, import the result | Works but IFD has eval-time build penalty; complicated |
| **E: Build site in a separate flake, add as input** | Clean separation; `dangirsh-site` flake produces `packages.x86_64-linux.site`; neurosys imports the built output | Best architecture; site repo owns its build; neurosys just serves the output |

**Recommendation: Option E (separate flake in dangirsh-site repo).** The dangirsh-site repo should get a `flake.nix` that produces the built site as a package. Neurosys adds it as a flake input and points nginx at the built output in `/nix/store/`. This is the cleanest separation of concerns and follows the pattern already used for `parts` and `claw-swap` (those repos have their own flakes, neurosys imports their NixOS modules).

**Hakyll build modernization notes:**
- nixpkgs-25.11 ships GHC 9.8.x or 9.10.x with Hakyll 4.16.x and Pandoc 3.x
- The `site.cabal` already declares compatible version bounds: `hakyll >= 4.16 && < 4.17`, `pandoc >= 3.0 && < 3.6`
- The `cabal.project` has `allow-newer` for hakyll:base and pandoc:base, which may or may not be needed with nixpkgs-25.11
- The build is a simple `ghc --make` (not a complex multi-package Haskell project)
- `haskellPackages.ghcWithPackages (p: with p; [ hakyll ])` is the NixOS idiom; confirm this works with current nixpkgs Hakyll

**Risk:** Haskell package builds can be fragile. If `hakyll` in nixpkgs-25.11 has broken tests or incompatible dependencies, may need `haskell.lib.dontCheck` or version pinning. Test the build first.

### Decision 3: Port 80/443 Conflict with claw-swap Docker Caddy

claw-swap runs a Caddy Docker container that port-maps to host ports 80 and 443. NixOS nginx would also want ports 80 and 443. They cannot both bind to the same ports.

| Option | Pros | Cons |
|--------|------|------|
| **A: nginx as reverse proxy, replace Docker Caddy** | Single entrypoint for all HTTP traffic; nginx proxies to claw-swap app directly (bypassing Caddy); cleaner architecture | Requires claw-swap module changes; Docker Caddy handles claw-swap TLS with Cloudflare origin certs |
| **B: nginx on different ports, iptables routing** | No changes to claw-swap | Fragile; non-standard |
| **C: nginx handles dangirsh.org; Docker Caddy handles claw-swap on different host** | Natural with multi-host: dangirsh.org on one host, claw-swap on another | Depends on Phase 27 completion; only works if claw-swap is on OVH and dangirsh.org is on Contabo (or vice versa) |
| **D: nginx as host reverse proxy for ALL public traffic** | nginx terminates TLS for dangirsh.org, proxies claw-swap traffic to Docker app on localhost port | Best long-term architecture; one TLS termination point; but requires claw-swap Caddy removal and TLS cert migration |

**Recommendation: Option C (host-level separation) initially, migrate to Option D later.**

With Phase 27's multi-host setup:
- **OVH (production):** Serves claw-swap (Docker Caddy on ports 80/443) -- this is where claw-swap DNS already points
- **Contabo (staging) or OVH:** dangirsh.org served via NixOS nginx on ports 80/443

If dangirsh.org and claw-swap are on **different hosts**, there's no port conflict. The simplest path is:
- dangirsh.org on whichever host does NOT run claw-swap Docker Caddy
- If both end up on the same host, migrate to Option D (nginx as the single reverse proxy)

**Important consideration:** If both services run on the **same** host (which is likely in a consolidation scenario), then Option D becomes necessary. This would mean:
1. Remove Docker Caddy from claw-swap stack
2. NixOS nginx serves dangirsh.org directly + reverse proxies claw-swap-app on port 3000
3. nginx handles TLS for both domains (ACME for dangirsh.org, Cloudflare origin cert for claw-swap.com)

This is a bigger change and should be a separate plan within this phase or deferred.

### Decision 4: Which Host Serves dangirsh.org

| Option | Pros | Cons |
|--------|------|------|
| **Contabo (staging)** | No port conflict with claw-swap on OVH; staging server still useful | Staging host may be less reliable; IP changes if staging is decommissioned |
| **OVH (production)** | Production-grade; single point of management | Port conflict with claw-swap Docker Caddy; requires Option D above |
| **Both (round-robin or failover)** | Redundancy | Over-engineered for a personal blog |

**Recommendation: Start on whichever host does NOT have the claw-swap port conflict. Likely OVH after Phase 27 completes and the nginx reverse proxy consolidation is done. For now, plan for the host-level module to be host-agnostic (enabled per-host via a flag).**

### Decision 5: ACME Certificate Configuration

NixOS has first-class ACME support via `security.acme`:

```nix
# Pattern for nginx + ACME
security.acme = {
  acceptTerms = true;
  defaults.email = "dan@dangirsh.org";  # or whatever contact email
};

services.nginx = {
  enable = true;
  virtualHosts."dangirsh.org" = {
    enableACME = true;
    forceSSL = true;
    root = pkgs.dangirsh-site;  # or the built site package
    locations."/" = {};
  };
};
```

**Impermanence consideration:** ACME certificate state is stored in `/var/lib/acme/`. This must be added to the impermanence persistence list. Without this, certificates are re-requested on every reboot (rate limits: 5 duplicate certificates per week).

**www redirect:** Both `dangirsh.org` and `www.dangirsh.org` currently resolve to NFS. The nginx config should handle both:
```nix
services.nginx.virtualHosts."www.dangirsh.org" = {
  enableACME = true;
  forceSSL = true;
  globalRedirect = "dangirsh.org";
};
```

### Decision 6: Repo Tracking

The dangirsh-site repo needs to be tracked by neurosys. Options:

| Option | Pros | Cons |
|--------|------|------|
| **Flake input** (`github:dangirsh/dangirsh.org`) | Pinned in flake.lock; `nix flake update dangirsh-site` to update; site rebuilds atomically with system | Every flake lock update triggers a full system rebuild |
| **Activation script clone** (like repos.nix) | Simple; already have the pattern | Not integrated with Nix build; separate deploy step needed |

**Recommendation: Flake input.** This is the cleanest approach and matches the pattern used for `parts` and `claw-swap`. The site repo exports a flake package; neurosys imports it and uses it as the nginx root.

## Key Risks and Mitigations

### Risk 1: Hakyll Build Failure with Modern nixpkgs

**Severity:** MEDIUM
**Likelihood:** MEDIUM
**Description:** The site's Hakyll generator was last built against nixpkgs-20.03 (GHC ~8.8). nixpkgs-25.11 ships GHC 9.8+ with different Hakyll/Pandoc versions. The `allow-newer` constraints in `cabal.project` may or may not be sufficient.
**Mitigation:** Test the build first with a standalone `nix-build`. If it fails, options are: (a) update Haskell code for compatibility, (b) use `haskellPackages.override` to pin versions, (c) use a separate nixpkgs pin just for the Hakyll build. The code is tiny (~130 lines of Haskell) so updating for compatibility should be straightforward.

### Risk 2: Port 80/443 Conflict with claw-swap Caddy

**Severity:** HIGH
**Likelihood:** HIGH (if both services on same host)
**Description:** Docker Caddy for claw-swap already binds host ports 80/443. NixOS nginx cannot also bind these ports.
**Mitigation:** Either (a) host-level separation (different hosts serve different domains) or (b) migrate to nginx as the unified reverse proxy. Plan for both; implement (a) first if Phase 27 provides two hosts, escalate to (b) if consolidation is needed.

### Risk 3: ACME Rate Limits During Testing

**Severity:** LOW
**Likelihood:** LOW
**Description:** Let's Encrypt has rate limits (50 certificates per registered domain per week, 5 duplicate certificates per week). Testing repeatedly could hit limits.
**Mitigation:** Use Let's Encrypt staging server during development (`security.acme.defaults.server = "https://acme-staging-v02.api.letsencrypt.org/directory"`). Switch to production only when ready.

### Risk 4: DNS Propagation Delay

**Severity:** LOW
**Likelihood:** MEDIUM
**Description:** DNS TTL for dangirsh.org may be high (NFS default). After changing A record, some clients see old IP.
**Mitigation:** Lower TTL 24-48 hours before cutover. Verify with `dig` from multiple resolvers.

### Risk 5: GoatCounter Analytics Continuity

**Severity:** LOW
**Likelihood:** NONE (automatic)
**Description:** The site uses GoatCounter analytics via a JS snippet. This is domain-based and will continue working regardless of hosting provider. No action needed.

## NixOS nginx + ACME Implementation Pattern

The standard NixOS pattern for a static site with ACME:

```nix
# modules/nginx.nix (new module)
# @decision NGINX-01: NixOS-native nginx for static site serving (not Docker/Caddy)
# @decision NGINX-02: ACME (Let's Encrypt) for TLS, production server by default
{ config, lib, pkgs, ... }: {

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@dangirsh.org";
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;

    virtualHosts."dangirsh.org" = {
      enableACME = true;
      forceSSL = true;
      root = inputs.dangirsh-site.packages.${pkgs.system}.default;

      # Cache static assets
      locations."/css/".extraConfig = ''
        expires 7d;
        add_header Cache-Control "public, immutable";
      '';
      locations."/img/".extraConfig = ''
        expires 30d;
        add_header Cache-Control "public, immutable";
      '';
      locations."/fonts/".extraConfig = ''
        expires 30d;
        add_header Cache-Control "public, immutable";
      '';
      locations."/doc/".extraConfig = ''
        expires 30d;
        add_header Cache-Control "public, immutable";
      '';
    };

    virtualHosts."www.dangirsh.org" = {
      enableACME = true;
      forceSSL = true;
      globalRedirect = "dangirsh.org";
    };
  };
}
```

**Impermanence addition** (to `modules/impermanence.nix`):
```nix
"/var/lib/acme"  # ACME certificate state (avoid re-request on reboot)
```

## Proposed Plan Breakdown

### Plan 28-01: Hakyll Site Flake Build

**Scope:** Add `flake.nix` to dangirsh-site repo; produce `packages.x86_64-linux.default` that builds the Hakyll generator and generates the site output.

**Tasks:**
1. Create `flake.nix` in dangirsh-site repo with nixpkgs-25.11
2. Define Haskell package for the generator via `haskellPackages.ghcWithPackages` or `haskellPackages.callCabal2nix`
3. Define site derivation that runs the generator on site source
4. Verify `nix build` produces the expected site output
5. Ensure all content (posts, images, CSS, fire/, docs, fonts) is present in output
6. Push flake to `dangirsh/dangirsh.org` repo

**Risks:** Haskell build compatibility (see Risk 1)
**Autonomous:** Yes (code changes to dangirsh-site repo)
**Effort:** Medium (Haskell builds can be fiddly)

### Plan 28-02: nginx + ACME NixOS Module

**Scope:** Add nginx module to neurosys, configure ACME, add dangirsh-site as flake input, update impermanence, verify build.

**Tasks:**
1. Add `dangirsh-site` flake input to neurosys `flake.nix`
2. Create `modules/nginx.nix` with virtualHosts for dangirsh.org + www redirect
3. Configure `security.acme` with acceptTerms and contact email
4. Add `/var/lib/acme` to impermanence persistence list
5. Add nginx module to `modules/default.nix` import list
6. Decide host placement (host-specific enable flag if needed)
7. Handle port 80/443 conflict resolution (if same host as claw-swap)
8. `nix flake check` passes
9. Deploy and verify nginx serves the site over HTTPS

**Risks:** Port conflict with claw-swap Docker Caddy (see Risk 2)
**Autonomous:** Partially (code is autonomous; deploy requires human verification)
**Effort:** Low-Medium

### Plan 28-03: DNS Cutover + NFS Deprecation

**Scope:** Update DNS A record for dangirsh.org, verify HTTPS, document NFS decommission.

**Tasks:**
1. Lower DNS TTL for dangirsh.org 24-48 hours before cutover
2. Update A record from NFS IP (208.94.117.137) to neurosys/OVH IP
3. Update www.dangirsh.org A record similarly
4. Verify HTTPS with `curl -sI https://dangirsh.org`
5. Verify site content is correct
6. Restore DNS TTL to normal
7. Document NFS decommission steps (cancel hosting? keep as backup?)
8. Update homepage dashboard with dangirsh.org entry
9. Add dangirsh-site repo to repos.nix clone list (for local editing on server)

**Autonomous:** No (DNS changes are human-interactive)
**Effort:** Low

## Dependencies

- **Phase 27 (hard dependency):** The host(s) must be deployed and operational before dangirsh.org can be served. Specifically:
  - OVH deployment (Plan 27-03) must be complete if serving from OVH
  - Port conflict resolution depends on knowing which host runs claw-swap vs dangirsh.org
- **dangirsh-site repo access:** Need push access to add `flake.nix` (user owns the repo)

## Questions for Planning

1. **Which host should serve dangirsh.org?** OVH (production) or Contabo (staging)? If OVH, does that mean consolidating with claw-swap on the same host (requiring nginx reverse proxy for both)?
2. **Is NFS still needed after migration?** Should it be kept as a fallback or decommissioned entirely?
3. **Should nginx become the unified reverse proxy?** If both dangirsh.org and claw-swap are on the same host, should we replace Docker Caddy with nginx proxying claw-swap-app directly? (This is architecturally cleaner but a bigger change.)
4. **ACME contact email:** What email should be used for Let's Encrypt certificate notifications?
5. **GoatCounter:** Keep existing analytics, or switch/remove?
6. **Content updates workflow:** After this migration, how will content be updated? Options: (a) edit locally, push to GitHub, `nix flake update dangirsh-site` in neurosys, deploy; (b) edit on server, build locally, push; (c) CI/CD auto-deploy on push.

## Module Change Checklist (Pre-emptive)

Per CLAUDE.md conventions, the nginx module will need:

- [ ] **Port exposure:** Ports 80/443 already in `allowedTCPPorts` -- no change needed. Nginx is public-facing by design.
- [ ] **Secret handling:** ACME account key is managed by NixOS ACME module automatically. Contact email is not secret.
- [ ] **New service:** `services.nginx.enable = true` -- public-facing, justified by `@decision` annotation. NOT added to `internalOnlyPorts` (it IS public).
- [ ] **Sandbox impact:** None (nginx is a system service, not related to agent sandboxing).
- [ ] **Credentials:** ACME uses HTTP-01 challenge (no API keys needed for basic setup). If DNS-01 challenge is needed, would require DNS provider API key in sops.
- [ ] **Validation:** `nix flake check` must pass.
- [ ] **Impermanence:** `/var/lib/acme` added to persistence list.
