# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 32-sec-harden.sh
# Phase 3c - hardening: unattended security updates, sshd key-only, nftables check/strict mode, sysctl, key replacement, password help.
# shellcheck disable=SC2015,SC2016
# Usage: bash 32-sec-harden.sh [--check|--apply] SECTION [SECTION ...]
# SECTION: unattended | ssh | firewall | firewall-strict | firewall-confirm | sysctl | dropkey | passwords
# Nothing here touches Android, boot or partition data. Every config file is backed up first.
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log
APTO=(-o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)
DEBUG_FP='SHA256:2vHWtjV1ehYXX97F+HLEn4ADK8DkkxVAtFTGUOgVfzs'
set -- "${REST_ARGS[@]}"
[ "$#" -gt 0 ] || { fail "give a SECTION (unattended ssh firewall firewall-strict firewall-confirm sysctl dropkey passwords)"; finish; exit 1; }

write_file() { # write_file PATH MODE CONTENT
  if [ -f "$1" ] && [ "$(cat "$1")" = "$3" ]; then ok "$1 already up to date"; return 0; fi
  if [ "$APPLY" = 1 ]; then mkdir -p "$(dirname "$1")"; backup "$1"; printf '%s\n' "$3" > "$1" && chmod "$2" "$1" && ok "wrote $1" || { fail "cannot write $1"; return 1; }
  else dry "write $1"; fi
}

while [ "$#" -gt 0 ]; do
  sec=$1; shift
  case "$sec" in
  unattended)
    sect "H1. unattended-upgrades (security pocket only, never kernel/Mesa/Phosh)"
    ip route get 1.1.1.1 >/dev/null 2>&1 || warn "no internet route: install may fail (20-fix-network.sh --apply)"
    if dpkg -s unattended-upgrades >/dev/null 2>&1; then ok "unattended-upgrades installed"
    else act "apt-get install unattended-upgrades" env DEBIAN_FRONTEND=noninteractive apt-get "${APTO[@]}" -y --no-install-recommends install unattended-upgrades; fi
    UU='// cheetah: security updates only. Kernel, Mesa, Phosh and omamobile packages are NEVER touched.
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Package-Blacklist {
        "linux-.*";
        "initramfs-tools.*";
        "mesa-cheetah";
        "libegl-mesa0";
        "libgbm1";
        "libgl1-mesa-dri";
        "libglx-mesa0";
        "mesa-libgallium";
        "mesa-vulkan-drivers";
        "phosh.*";
        "libphosh.*";
        "phoc";
        "squeekboard";
        "omamobile-.*";
        ".*-cheetah";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::MinimalSteps "true";'
    PE='// cheetah: the image build disabled all periodic apt jobs (APT::Periodic::Enable "0" in 99cheetah). Re-enable only for security upgrades.
APT::Periodic::Enable "1";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
    write_file /etc/apt/apt.conf.d/52cheetah-unattended 644 "$UU"
    write_file /etc/apt/apt.conf.d/99zz-cheetah-periodic 644 "$PE"
    for t in apt-daily.timer apt-daily-upgrade.timer; do
      if [ "$APPLY" = 1 ]; then systemctl unmask "$t" apt-daily.service apt-daily-upgrade.service >> "$LOG" 2>&1; systemctl enable --now "$t" >> "$LOG" 2>&1 && ok "$t enabled" || fail "$t enable failed"
      else dry "unmask + enable --now $t"; fi
    done
    if dpkg -s unattended-upgrades >/dev/null 2>&1; then
      o=$(unattended-upgrade --dry-run -v 2>&1 | head -n 40); printf '%s\n' "$o" >> "$LOG"
      printf '%s\n' "$o" | grep -q 'Allowed origins are' && ok "unattended-upgrade dry run works: $(printf '%s\n' "$o" | grep 'Allowed origins' | cut -c1-120)" || warn "dry run output unexpected (see log)"
      printf '%s\n' "$o" | grep -qE 'Packages that will be upgraded: .*(linux-|mesa-cheetah|phosh)' && fail "dry run would upgrade a protected package" || ok "dry run does not include protected packages"
    fi ;;

  ssh)
    sect "H2. sshd: key-only login (the debug key keeps working)"
    KEYOK=1
    [ -s /root/.ssh/authorized_keys ] && ok "root has authorized_keys" || { fail "root authorized_keys missing/empty: refusing"; KEYOK=0; }
    ev=$(journalctl -u ssh -u sshd -b --no-pager -q 2>/dev/null | grep -E 'Accepted publickey for root' | tail -n1 | cut -c1-140)
    [ -n "$ev" ] && ok "public-key root login confirmed this boot: $ev" || { fail "no 'Accepted publickey for root' in this boot's log. Log in once with: ssh -i KEY root@172.16.42.1 then retry"; KEYOK=0; }
    [ -n "${SSH_CONNECTION:-}" ] && info "this session: ssh from ${SSH_CONNECTION%% *}"
    SC='# cheetah hardening (file name sorts BEFORE 10-cheetah.conf because sshd uses the FIRST value it reads)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 60
ClientAliveCountMax 3'
    F=/etc/ssh/sshd_config.d/00-cheetah-hardening.conf
    if [ "$KEYOK" = 1 ]; then
      if [ "$APPLY" = 1 ]; then
        backup "$F"; printf '%s\n' "$SC" > "$F"
        if sshd -t >> "$LOG" 2>&1; then
          systemctl reload ssh >> "$LOG" 2>&1 && ok "sshd reloaded (existing sessions stay open)" || fail "reload failed"
          pw=$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2}'); [ "$pw" = no ] && ok "effective PasswordAuthentication=no" || fail "effective PasswordAuthentication=$pw (another file wins?)"
          info "NOW test from the Mac in a NEW terminal (guide step 3.6). To undo: rm $F && systemctl reload ssh"
        else
          fail "sshd -t rejected the config: removing $F"; rm -f "$F"
        fi
      else dry "write $F ; sshd -t ; systemctl reload ssh"; fi
    else warn "key login not confirmed: sshd NOT changed"; fi ;;

  firewall)
    sect "H3. firewall check (nftables; ufw deliberately not used)"
    nft list table inet cheetah >/dev/null 2>&1 && ok "table inet cheetah loaded" || { warn "table missing"; [ -f /etc/nftables.conf ] && act "load /etc/nftables.conf" nft -f /etc/nftables.conf; }
    nft list ruleset 2>/dev/null | grep -qE "tcp dport 22" && ok 'ssh only from usb0 (rule present)' || fail "ssh rule missing"
    systemctl is-enabled nftables >/dev/null 2>&1 && ok "nftables enabled at boot" || act "enable nftables" systemctl enable nftables
    info "ufw is not installed on purpose: /etc/nftables.conf starts with 'flush ruleset', so ufw and nftables.service would wipe each other's rules."
    info "for a default-drop policy use: firewall-strict (45 s auto-rollback), then firewall-confirm" ;;

  firewall-strict)
    sect "H3b. strict nftables policy with automatic rollback"
    NS=$HEALTH_DIR/nftables-strict.conf
    cat > "$NS" <<'NFT'
# nftables ruleset
flush ruleset
table inet cheetah {
  chain input {
    type filter hook input priority 0; policy drop;
    iifname "lo" accept
    ct state established,related accept
    ct state invalid drop
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
    udp sport 67 udp dport 68 accept
    udp sport 547 udp dport 546 accept
    iifname "usb0" tcp dport 22 accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
  }
}
NFT
    nft -c -f "$NS" >> "$LOG" 2>&1 && ok "strict ruleset syntax OK ($NS)" || { fail "ruleset syntax error"; continue; }
    if [ "$APPLY" = 1 ]; then
      nft list ruleset > "$HEALTH_DIR/backup/nft-ruleset-before-$TS.nft" && ok "current rules saved: $HEALTH_DIR/backup/nft-ruleset-before-$TS.nft"
      rm -f /run/cheetah-fw-ok
      nohup bash -c "sleep 45; [ -e /run/cheetah-fw-ok ] || { nft flush ruleset; nft -f '$HEALTH_DIR/backup/nft-ruleset-before-$TS.nft'; }" >/dev/null 2>&1 &
      nft -f "$NS" && ok "strict rules LIVE. If SSH still works in a NEW terminal within 45 s, run: 32-sec-harden.sh --apply firewall-confirm. Otherwise they roll back by themselves." || fail "could not load strict rules"
    else dry "load $NS with 45 s automatic rollback"; fi ;;

  firewall-confirm)
    sect "H3c. confirm strict firewall"
    if [ "$APPLY" = 1 ]; then
      NS=$HEALTH_DIR/nftables-strict.conf
      [ -f "$NS" ] || { fail "no strict ruleset prepared"; continue; }
      nft list ruleset 2>/dev/null | grep -q 'policy drop' || { fail "strict rules are not live (they were rolled back). Nothing persisted."; continue; }
      touch /run/cheetah-fw-ok; backup /etc/nftables.conf; cp "$NS" /etc/nftables.conf && ok "persisted to /etc/nftables.conf (rollback timer cancelled)"
      systemctl enable nftables >> "$LOG" 2>&1
    else dry "persist strict rules to /etc/nftables.conf"; fi ;;

  sysctl)
    sect "H4. sysctl hardening"
    SY='# cheetah hardening
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_bpf_disabled=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.rp_filter=1
net.ipv6.conf.all.accept_redirects=0
fs.protected_hardlinks=1
fs.protected_symlinks=1'
    write_file /etc/sysctl.d/60-cheetah-hardening.conf 644 "$SY"
    [ "$APPLY" = 1 ] && { sysctl --system >> "$LOG" 2>&1; ok "sysctl --system applied"; } ;;

  dropkey)
    sect "H5. replace the publicly shipped debug SSH key"
    for f in /root/.ssh/authorized_keys /home/user/.ssh/authorized_keys; do
      [ -f "$f" ] || continue
      total=$(grep -cE '^(ssh-|ecdsa-)' "$f"); dbg=0
      while IFS= read -r line; do
        fp=$(printf '%s\n' "$line" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
        [ "$fp" = "${DEBUG_FP#SHA256:}" ] || [ "$fp" = "$DEBUG_FP" ] && dbg=$((dbg+1))
      done < <(grep -E '^(ssh-|ecdsa-)' "$f")
      info "$f: $total key(s), $dbg of them the shipped debug key"
      if [ "$dbg" -gt 0 ] && [ "$total" -le "$dbg" ]; then warn "$f has ONLY the debug key: add your own key first (guide 3.7), then re-run"; continue; fi
      if [ "$dbg" -gt 0 ]; then
        if [ "$APPLY" = 1 ]; then
          backup "$f"
          grep -E '^(ssh-|ecdsa-)' "$f" | while IFS= read -r line; do
            fp=$(printf '%s\n' "$line" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
            if [ "$fp" = "$DEBUG_FP" ]; then :; else printf '%s\n' "$line"; fi
          done > "$f.new"
          if [ -s "$f.new" ]; then cat "$f.new" > "$f" && rm -f "$f.new" && ok "removed the debug key from $f (your own key stays; owner/mode preserved)"; else rm -f "$f.new"; fail "result would be empty; original kept"; fi
        else dry "remove the debug key from $f"; fi
      else ok "$f has no debug key"; fi
    done
    warn "AFTER this, the old $CHEETAH_SSH_KEY on the Mac no longer works: use your own key in every ssh command." ;;

  passwords)
    sect "H6. passwords (interactive - YOU type them)"
    info "run from the Mac, one at a time (they prompt twice):"
    info "  ssh -t -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'passwd user && /usr/local/sbin/cheetah-clear-password-marker'"
    info "root is locked by design (key-only). Do NOT unlock it."
    for u in user root; do
      s=$(passwd -S "$u" 2>/dev/null | awk '{print $2}'); info "$u password state: ${s:-?} (P=set, L=locked)"
    done ;;

  *) fail "unknown section '$sec'" ;;
  esac
done
[ "$APPLY" = 1 ] || info "CHECK/DRY RUN only. Re-run with --apply."
finish
