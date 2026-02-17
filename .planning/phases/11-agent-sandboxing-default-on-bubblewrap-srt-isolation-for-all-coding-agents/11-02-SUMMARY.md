---
plan: 11-02
status: complete
commits:
  - "8752e02 fix(11-01): dockerCompat=false — conflicts with virtualisation.docker"
  - "8c03c0b fix(11-02): bwrap sandbox fixes from live testing"
  - "d66d019 fix(11-02): pre-create audit log dir with tmpfiles rule"
  - "90861ba fix(11-02): add zmx to sandbox PATH"
  - "70cc255 fix(11-02): unpack zmx tarball — was installing gzip as binary"
---

# Plan 11-02 Summary: Deploy + Live Testing

## What was done

Deployed the sandboxed agent-spawn to the VPS and iteratively fixed 5 issues discovered during live testing. All 10 test cases from the plan now pass.

## Issues found and fixed

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Deploy failure: dockerCompat assertion | `dockerCompat = true` conflicts with `virtualisation.docker.enable = true` | Set `dockerCompat = false`, created `sandbox-docker-compat` derivation (docker→podman symlink in sandbox PATH) |
| bwrap `--size must be followed by --tmpfs` | Arg ordering: `--size` must precede `--tmpfs` | Swapped order to `--size 4294967296 --tmpfs /tmp` |
| Nix "lock file permission denied" in sandbox | User namespace (`--unshare-user`) prevents access to root-owned lock file | Set `NIX_REMOTE=daemon` env var; daemon-socket bind changed to rw |
| Audit dir: permission denied | `/data/projects` is root-owned, dangirsh can't mkdir | Added `systemd.tmpfiles.rules` to pre-create `.agent-audit` with dangirsh ownership |
| zmx "Exec format error" | `dontUnpack = true` installed the .tar.gz as the binary | Removed `dontUnpack`, set `sourceRoot = "."` to extract tarball |
| zmx not found inside sandbox | `--clearenv` removes runtimeInputs PATH; zmx not in sandbox PATH | Added `${zmx}/bin` to the sandbox `--setenv PATH` |

## Test results (all pass)

1. **zmx binary**: `zmx 0.3.0` — works correctly
2. **Sandbox isolation**: SANDBOX=1, /run/secrets hidden, ~/.ssh hidden, docker.sock hidden
3. **Project dir**: writable inside sandbox
4. **Sibling projects**: read-only (write fails)
5. **Nix**: `nix shell nixpkgs#hello --command hello` → "Hello, world!" (daemon mode)
6. **Network**: curl to github.com works, DNS resolves
7. **Git**: works with correct identity
8. **Podman**: `podman 5.7.0` accessible inside sandbox
9. **--no-sandbox**: full spawn + zmx session, no bwrap
10. **--show-policy**: prints correct policy and exits
11. **Audit log**: spawn.log captures all events with sandbox=on/off
12. **Claude CLI**: `claude 2.1.25` accessible inside sandbox

## Research questions resolved

- **bwrap user namespace on NixOS**: `--unshare-user` + `--disable-userns` works correctly
- **Rootless Podman inside bwrap**: accessible (podman 5.7.0), `--disable-userns` does not block podman --version
- **NixOS /etc/static symlinks**: `--ro-bind /etc/static /etc/static` works
- **zmx socket location**: zmx uses `/run/user/UID` — must bind-mount runtime dir
- **Nix daemon mode**: `NIX_REMOTE=daemon` required; daemon-socket needs rw bind for Unix socket connection
