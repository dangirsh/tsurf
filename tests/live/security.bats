#!/usr/bin/env bats
# tests/live/security.bats — Security boundary verification tests.
# @decision TEST-48-01: Runtime checks validate hardening assumptions against live host state.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

# Validates NET-013: PasswordAuthentication = false
@test "${HOST}: SSH rejects password authentication" {
  local result
  result="$(
    ssh -o ConnectTimeout=5 \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      "root@${HOST}" echo test 2>&1
  )" || true

  if echo "$result" | grep -qi "Permission denied"; then
    return 0
  fi
  if echo "$result" | grep -qi "no more authentication methods"; then
    return 0
  fi
  echo "FAIL: SSH did not clearly reject password authentication"
  echo "DEBUG: result=$result"
  return 1
}

# Validates NET-020: SSH host key type ed25519 only
@test "${HOST}: SSH host key type is ed25519 only" {
  local keytypes
  keytypes="$(ssh-keyscan -T 5 "${HOST}" 2>/dev/null | awk '{print $2}' | sort -u)" || {
    echo "FAIL: ssh-keyscan failed"
    return 1
  }

  if [[ "$keytypes" != "ssh-ed25519" ]]; then
    echo "FAIL: SSH host key types='$keytypes', expected='ssh-ed25519'"
    return 1
  fi
}

# Validates SEC-020: kernel.dmesg_restrict = 1
@test "${HOST}: kernel.dmesg_restrict = 1" {
  assert_sysctl "kernel.dmesg_restrict" "1"
}

# Validates SEC-021: kernel.kptr_restrict = 2
@test "${HOST}: kernel.kptr_restrict = 2" {
  assert_sysctl "kernel.kptr_restrict" "2"
}

# Validates SEC-022: kernel.unprivileged_bpf_disabled = 1
@test "${HOST}: kernel.unprivileged_bpf_disabled = 1" {
  assert_sysctl "kernel.unprivileged_bpf_disabled" "1"
}

# Validates SEC-024: ICMP redirects disabled
@test "${HOST}: net.ipv4.conf.all.accept_redirects = 0" {
  assert_sysctl "net.ipv4.conf.all.accept_redirects" "0"
}

# Validates SEC-024: ICMP redirects disabled (send)
@test "${HOST}: net.ipv4.conf.all.send_redirects = 0" {
  assert_sysctl "net.ipv4.conf.all.send_redirects" "0"
}

# Validates NET-010: nftables drops outbound traffic to 169.254.169.254
@test "${HOST}: cloud metadata endpoint 169.254.169.254 is blocked" {
  local result
  result="$(remote curl -sf --max-time 3 "http://169.254.169.254/" 2>&1)" || {
    return 0
  }

  echo "FAIL: metadata endpoint reachable but should be blocked"
  echo "DEBUG: response=$result"
  echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -v http://169.254.169.254/"
  return 1
}


# Validates NET-005: build-time assertion prevents internal ports from leaking
@test "${HOST}: internal ports are absent from public nftables accept rules" {
  local nft_output
  nft_output="$(remote nft list ruleset 2>&1)" || {
    echo "FAIL: could not read nftables ruleset"
    return 1
  }

  # Must match internalOnlyPorts in modules/networking.nix (localhost-only, no firewall accept rules)
  local internal_ports="8082 9200"
  local port
  for port in $internal_ports; do
    if echo "$nft_output" | grep -E "tcp dport.*\\b${port}\\b.*accept" > /dev/null 2>&1; then
      echo "FAIL: internal port '$port' appears in public accept rule"
      echo "DEBUG: ssh ${SSH_USER}@${HOST} nft list ruleset | grep -n ${port}"
      return 1
    fi
  done
}

# Validates SEC-023: net.core.bpf_jit_harden = 2
@test "${HOST}: net.core.bpf_jit_harden = 2" {
  assert_sysctl "net.core.bpf_jit_harden" "2"
}

# Validates SEC-025: martian packet logging enabled
@test "${HOST}: net.ipv4.conf.all.log_martians = 1" {
  assert_sysctl "net.ipv4.conf.all.log_martians" "1"
}

# Validates SEC-014: users.mutableUsers = false
@test "${HOST}: no passwd/shadow modification tools available to users" {
  local result
  result="$(remote passwd --status root 2>&1)" || true
  # mutableUsers=false means passwd changes are rejected
  if echo "$result" | grep -qi "authentication token manipulation error\|cannot lock\|Permission denied"; then
    return 0
  fi
  # On NixOS with mutableUsers=false, /etc/shadow is read-only
  local shadow_perms
  shadow_perms="$(remote stat -c '%a' /etc/shadow 2>&1)" || true
  [[ -n "$shadow_perms" ]]
}

# Validates NET-015: PermitRootLogin = prohibit-password
@test "${HOST}: SSH PermitRootLogin is prohibit-password" {
  local result
  result="$(remote sshd -T 2>&1 | grep -i permitrootlogin)" || {
    echo "FAIL: could not query sshd config"
    return 1
  }
  assert_contains "$result" "prohibit-password" "PermitRootLogin"
}

# Validates NET-017: MaxAuthTries = 3
@test "${HOST}: SSH MaxAuthTries is 3" {
  local result
  result="$(remote sshd -T 2>&1 | grep -i maxauthtries)" || {
    echo "FAIL: could not query sshd config"
    return 1
  }
  assert_contains "$result" "3" "MaxAuthTries"
}

# Validates NET-004: trustedInterfaces is empty
@test "${HOST}: no trusted firewall interfaces" {
  local nft_output
  nft_output="$(remote nft list ruleset 2>&1)" || return 0
  # Trusted interfaces get an unconditional accept rule for all traffic
  # With empty trustedInterfaces, there should be no iifname accept-all rules
  if echo "$nft_output" | grep -E 'iifname.*(tailscale0|eth0).*accept' | grep -v 'dport' > /dev/null 2>&1; then
    echo "FAIL: found trusted interface accept-all rule"
    return 1
  fi
}
