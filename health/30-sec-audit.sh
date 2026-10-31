# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 30-sec-audit.sh
# Phase 3a - security AUDIT (read-only): listening services, firewall, sshd, keys, passwords, sudo, sysctl, pending security updates.
# shellcheck disable=SC2015,SC2016
# Usage: bash 30-sec-audit.sh [--quiet]
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log
DEBUG_FP='SHA256:2vHWtjV1ehYXX97F+HLEn4ADK8DkkxVAtFTGUOgVfzs'   # fingerprint of the PUBLIC debug key shipped in out-ubuntu/debug_ssh

sect "S1. listening sockets"
cap ss -tulpn
unexp=$(ss -H -tulnp 2>/dev/null | awk '{print $1, $5, $7}' | grep -vE '127\.0\.0\.|\[::1\]|%lo|127\.0\.0\.53|:68 |:546 ' | grep -E '0\.0\.0\.0|\*:|\[::\]' | grep -vE ':22 ')
[ -z "$unexp" ] && rec "Listening services" OK "only loopback/DHCP/ssh" || { rec "Listening services" WARN "externally bindable sockets (besides ssh:22): $(printf '%s' "$unexp" | tr '\n' ';' | cut -c1-200)"; }
ss -H -tln 2>/dev/null | grep -qE ':22 ' && info "sshd listens on :22" || info "sshd not listening"

sect "S2. firewall (nftables is the firewall of this image; ufw is NOT used)"
if have nft; then
  nft list ruleset >> "$LOG" 2>&1
  if nft list table inet cheetah >/dev/null 2>&1; then rec "nftables table inet cheetah" OK "loaded"; else rec "nftables table inet cheetah" FAIL "not loaded: ssh is reachable on every interface (32-sec-harden.sh firewall --apply)"; fi
  nft list ruleset 2>/dev/null | grep -qE "tcp dport 22" && rec "SSH only on usb0" OK 'rule tcp dport 22 restricted to usb0/lo is active' || rec "SSH only on usb0" FAIL "rule not active"
else rec "nft" FAIL "nft not installed"; fi
systemctl is-enabled nftables >/dev/null 2>&1 && rec "nftables at boot" OK enabled || rec "nftables at boot" WARN "nftables.service not enabled: rules vanish after reboot"
dpkg -s ufw >/dev/null 2>&1 && rec "ufw" WARN "ufw is installed: its rules and /etc/nftables.conf (flush ruleset) overwrite each other" || rec "ufw" OK "not installed (good: avoids conflict with nftables.conf)"

sect "S3. sshd effective configuration"
if have sshd; then
  sshd -T 2>/dev/null | grep -E '^(passwordauthentication|permitrootlogin|pubkeyauthentication|kbdinteractiveauthentication|permitemptypasswords|x11forwarding|maxauthtries|allowtcpforwarding|usepam) ' | sort | tee -a "$LOG" > "$HEALTH_DIR/.sshd-eff"
  [ "$QUIET" = 1 ] || sed 's/^/  /' "$HEALTH_DIR/.sshd-eff"
  grep -q '^passwordauthentication no' "$HEALTH_DIR/.sshd-eff" && rec "SSH password login" OK "disabled" || rec "SSH password login" WARN "enabled (only reachable via usb0; disable with 32-sec-harden.sh ssh --apply after key test)"
  grep -q '^permitrootlogin \(prohibit-password\|without-password\|no\)' "$HEALTH_DIR/.sshd-eff" && rec "Root SSH login" OK "key-only" || rec "Root SSH login" FAIL "root can log in with a password"
  grep -q '^permitemptypasswords no' "$HEALTH_DIR/.sshd-eff" && rec "Empty passwords" OK "refused" || rec "Empty passwords" FAIL "allowed"
else rec "sshd" WARN "sshd binary not found"; fi
cap ls -la /etc/ssh/sshd_config.d

sect "S4. authorized keys"
for f in /root/.ssh/authorized_keys /home/user/.ssh/authorized_keys; do
  [ -f "$f" ] || { info "$f missing"; continue; }
  say "  $f ($(stat -c '%a %U' "$f")):"
  ssh-keygen -lf "$f" 2>/dev/null | sed 's/^/    /' | tee -a "$LOG" >/dev/null
  [ "$QUIET" = 1 ] || ssh-keygen -lf "$f" 2>/dev/null | sed 's/^/    /'
  if ssh-keygen -lf "$f" 2>/dev/null | grep -q "$DEBUG_FP"; then
    rec "Debug SSH key in $f" WARN "the PUBLICLY SHIPPED debug key is authorized: anyone who has the build zip can log in as this user over the USB cable. Replace it (32-sec-harden.sh dropkey)"
  fi
done

sect "S5. passwords (weak/default test; hashes are never printed)"
weak_users=""
for u in user root; do
  h=$(awk -F: -v u="$u" '$1==u{print $2}' /etc/shadow 2>/dev/null)
  case "$h" in ''|'*'*) info "$u: password locked/empty-hash (prefix=${h:0:1})"; continue;; esac
  for cand in 1234 user root password 12345678 123456 0000 toor admin cheetah pixel; do
    if have perl && [ "$(perl -e 'print crypt($ARGV[0],$ARGV[1])' "$cand" "$h" 2>/dev/null)" = "$h" ]; then weak_users="$weak_users $u"; say "  WEAK: account '$u' still uses a guessable password"; break; fi
  done
done
[ -z "$weak_users" ] && rec "Weak passwords" OK "no common password matched (or accounts locked)" || rec "Weak passwords" FAIL "weak/default password on:$weak_users -> run: passwd (see 32-sec-harden.sh passwords)"
awk -F: '$2==""{print $1}' /etc/shadow 2>/dev/null | grep -q . && rec "Empty password fields" FAIL "$(awk -F: '$2==""{print $1}' /etc/shadow | tr '\n' ' ')" || rec "Empty password fields" OK none
awk -F: '$3==0{print $1}' /etc/passwd | grep -vx root | grep -q . && rec "Extra uid-0 accounts" FAIL "$(awk -F: '$3==0{print $1}' /etc/passwd | tr '\n' ' ')" || rec "Extra uid-0 accounts" OK none
grep -rhE 'NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | sed 's/^/  sudo NOPASSWD: /' >> "$LOG"
np=$(grep -rhE '^[^#].*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -vc cheetah-clear-password-marker)
[ "$np" -eq 0 ] && rec "sudo NOPASSWD" OK "only the password-marker helper" || rec "sudo NOPASSWD" WARN "$np extra NOPASSWD rules"

sect "S6. kernel/network hardening sysctls"
chk() { local k=$1 want=$2 v; v=$(sysctl -n "$k" 2>/dev/null); [ "$v" = "$want" ] && ok "$k=$v" || warn "$k=${v:-n/a} (recommended $want)"; }
chk kernel.kptr_restrict 2; chk kernel.dmesg_restrict 1; chk kernel.unprivileged_bpf_disabled 1
chk net.ipv4.tcp_syncookies 1; chk net.ipv4.conf.all.accept_redirects 0; chk net.ipv4.conf.all.send_redirects 0; chk net.ipv4.conf.all.rp_filter 1
chk fs.protected_hardlinks 1; chk fs.protected_symlinks 1; chk kernel.yama.ptrace_scope 1
info "to apply these: 32-sec-harden.sh sysctl --apply"
f=$(find / -xdev -path /proc -prune -o -type f -perm -0002 \( -path '/etc/*' -o -path '/usr/*' -o -path '/opt/*' \) -print 2>/dev/null | head -n 10)
[ -z "$f" ] && rec "World-writable files (etc/usr/opt)" OK none || rec "World-writable files (etc/usr/opt)" WARN "$(printf '%s' "$f" | tr '\n' ' ' | cut -c1-200)"

sect "S7. pending security updates (from cached apt lists)"
age=$(find /var/lib/apt/lists -maxdepth 1 -type f -name '*Packages*' -mtime -3 2>/dev/null | wc -l)
[ "$age" -gt 0 ] && info "apt lists are fresh (<3 days)" || warn "apt lists are old/empty: run 31-sec-upgrade.sh (it runs apt update) for a real answer"
n=$(apt-get -s upgrade 2>/dev/null | grep '^Inst' | grep -c -- '-security'); a=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst')
info "upgradable packages: $a (of which from -security: $n)"
apt-get -s upgrade 2>/dev/null | grep '^Inst' | grep -- '-security' | cut -c1-120 | head -n 25 >> "$LOG"
[ "$n" -eq 0 ] && rec "Security updates pending" OK "0 (per cached lists)" || rec "Security updates pending" WARN "$n packages have security updates: 31-sec-upgrade.sh"
rec "Out-of-distro components" INFO "kernel ($(uname -r)) and mesa-cheetah are custom builds: Ubuntu security updates do NOT cover them; watch upstream (omarchy-mobile / Mesa)"
dpkg -s unattended-upgrades >/dev/null 2>&1 && rec "unattended-upgrades" OK "installed" || rec "unattended-upgrades" WARN "not installed (32-sec-harden.sh unattended --apply)"

sect "TABLE"
print_table "$TSV"
finish
