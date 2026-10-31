# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 21-repair-system.sh
# Phase 2b - repair: dpkg/apt, failed units, zram, journald cap, fstrim, time sync.
# shellcheck disable=SC2015,SC2016,SC2129
# Usage: bash 21-repair-system.sh [--check|--apply] [dpkg] [units] [zram] [journald] [fstrim] [time]    (no section = all)
# Never touches block devices except creating swap on /dev/zramN. fstrim runs on / only (never /mnt/shared).
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log
trap "" HUP   # keep apt/dpkg running if the SSH link drops

SECS=("${REST_ARGS[@]}")
[ "${#SECS[@]}" -gt 0 ] || SECS=(dpkg units zram journald fstrim time)
want() { local s; for s in "${SECS[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }
APTO=(-o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

if want dpkg; then
  sect "R1. dpkg / apt consistency"
  aud=$(dpkg --audit 2>&1)
  if [ -z "$aud" ]; then ok "dpkg --audit clean"; else warn "dpkg --audit reports problems"; say "$aud"; fi
  if [ "$APPLY" = 1 ]; then
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a >> "$LOG" 2>&1 && ok "dpkg --configure -a" || fail "dpkg --configure -a failed (see log)"
    if ip route get 1.1.1.1 >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get "${APTO[@]}" -y -f install >> "$LOG" 2>&1 && ok "apt-get -f install" || fail "apt-get -f install failed (network? run 20-fix-network.sh)"
    else warn "no route to the internet: skipped apt-get -f install"; fi
    apt-get check >> "$LOG" 2>&1 && ok "apt-get check clean" || fail "apt-get check still reports broken packages"
  else dry "dpkg --configure -a; apt-get -f install -y; apt-get check"; fi
fi

if want units; then
  sect "R2. failed systemd units"
  mapfile -t FU < <(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
  if [ "${#FU[@]}" -eq 0 ]; then ok "no failed units"; fi
  for u in "${FU[@]}"; do
    [ -n "$u" ] || continue
    info "failed: $u"; journalctl -u "$u" -b --no-pager -n 6 -q 2>/dev/null | cut -c1-170 >> "$LOG"
    case "$u" in
      pixel-phosh.service|phosh.service|user@*|getty*|ssh.service|NetworkManager.service|*.mount|*.socket|systemd-*)
        warn "$u: not auto-restarted (critical/special). Look: journalctl -u $u -b -n 30" ;;
      ModemManager.service)
        warn "$u failed: expected while no modem is exposed. Safe to leave, or: systemctl disable --now ModemManager" ;;
      *)
        if [ "$APPLY" = 1 ]; then
          systemctl reset-failed "$u" >> "$LOG" 2>&1; systemctl restart "$u" >> "$LOG" 2>&1; sleep 2
          systemctl is-active "$u" >/dev/null 2>&1 && ok "$u restarted and active" || { warn "$u still not active: journalctl -u $u -b -n 30"; systemctl reset-failed "$u" >> "$LOG" 2>&1; }
        else dry "reset-failed + restart $u"; fi ;;
    esac
  done
fi

if want zram; then
  sect "R3. zram swap"
  kr=$(uname -r)
  if grep -q zram /proc/swaps 2>/dev/null; then ok "zram swap already active"
  elif [ -e /sys/block/zram0 ] || grep -q zram /proc/devices 2>/dev/null || find "/usr/lib/modules/$kr" -name 'zram.ko*' 2>/dev/null | grep -q .; then
    info "kernel has zram: installing cheetah-zram.service (50% of RAM, zstd, priority 100)"
    ZB='# run-with sh
# cheetah-zram: zram swap, sized to half of RAM. start|stop. Only ever touches /dev/zramN.
case "$1" in
  start)
    grep -q zram /proc/swaps && exit 0
    modprobe zram 2>/dev/null || true
    mb=$(awk "/MemTotal/{print int(\$2/2048)}" /proc/meminfo)
    dev=$(zramctl --find --size "${mb}M" --algorithm zstd 2>/dev/null) || dev=$(zramctl --find --size "${mb}M" 2>/dev/null) || exit 1
    case "$dev" in /dev/zram[0-9]*) ;; *) exit 1 ;; esac
    mkswap "$dev" >/dev/null && swapon --priority 100 "$dev" ;;
  stop)
    for d in $(awk "/zram/{print \$1}" /proc/swaps); do swapoff "$d" && zramctl --reset "$d"; done ;;
esac'
    ZU='[Unit]
Description=zram compressed swap (cheetah)
DefaultDependencies=no
After=systemd-modules-load.service
Before=swap.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/cheetah-zram start
ExecStop=/usr/local/sbin/cheetah-zram stop

[Install]
WantedBy=swap.target'
    SY='vm.swappiness=100
vm.page-cluster=0'
    if [ "$APPLY" = 1 ]; then
      printf '%s\n' "$ZB" > /usr/local/sbin/cheetah-zram && chmod 755 /usr/local/sbin/cheetah-zram && sh -n /usr/local/sbin/cheetah-zram && ok "wrote /usr/local/sbin/cheetah-zram"
      backup /etc/systemd/system/cheetah-zram.service; printf '%s\n' "$ZU" > /etc/systemd/system/cheetah-zram.service
      backup /etc/sysctl.d/99-cheetah-zram.conf; printf '%s\n' "$SY" > /etc/sysctl.d/99-cheetah-zram.conf
      systemctl daemon-reload >> "$LOG" 2>&1
      systemctl enable --now cheetah-zram.service >> "$LOG" 2>&1 && ok "cheetah-zram.service enabled+started" || fail "cheetah-zram.service failed: journalctl -u cheetah-zram"
      sysctl -q --system >> "$LOG" 2>&1
      grep -q zram /proc/swaps && ok "zram active: $(awk '/zram/{print $1, int($3/1024) " MB"}' /proc/swaps)" || fail "zram not in /proc/swaps"
    else dry "install /usr/local/sbin/cheetah-zram + cheetah-zram.service + sysctl (swappiness=100, page-cluster=0); enable --now"; fi
  else
    warn "the kernel was built WITHOUT zram (no zram module, no /sys/block/zram0). It cannot be enabled from userspace. Needs a kernel rebuild with CONFIG_ZRAM=m and CONFIG_ZSMALLOC=y (guide phase 3 note)."
  fi
fi

if want journald; then
  sect "R4. journald size cap"
  JD=/etc/systemd/journald.conf.d/10-cheetah.conf
  JB='[Journal]
SystemMaxUse=150M
RuntimeMaxUse=48M
MaxFileSec=1week
Compress=yes'
  if [ -f "$JD" ] && [ "$(cat "$JD")" = "$JB" ]; then ok "$JD already set"
  elif [ "$APPLY" = 1 ]; then mkdir -p "$(dirname "$JD")"; backup "$JD"; printf '%s\n' "$JB" > "$JD" && systemctl restart systemd-journald >> "$LOG" 2>&1 && ok "journald capped (150M persistent, 48M volatile)" || fail "journald config failed"
  else dry "write $JD (SystemMaxUse=150M RuntimeMaxUse=48M); restart systemd-journald"; fi
  cap journalctl --disk-usage
fi

if want fstrim; then
  sect "R5. fstrim (root filesystem only)"
  FD=/etc/systemd/system/fstrim.service.d/10-cheetah-root-only.conf
  FB='[Service]
ExecStart=
ExecStart=/sbin/fstrim --verbose --quiet-unsupported /'
  if [ -f "$FD" ] && [ "$(cat "$FD")" = "$FB" ] && systemctl is-enabled fstrim.timer >/dev/null 2>&1; then ok "fstrim already limited to / and timer enabled"
  elif [ "$APPLY" = 1 ]; then
    mkdir -p "$(dirname "$FD")"; backup "$FD"; printf '%s\n' "$FB" > "$FD"
    systemctl daemon-reload >> "$LOG" 2>&1
    systemctl enable --now fstrim.timer >> "$LOG" 2>&1 && ok "fstrim.timer enabled (weekly, / only; /mnt/shared and Android partitions are never trimmed)" || fail "fstrim.timer enable failed"
  else dry "drop-in $FD (fstrim only /) + enable --now fstrim.timer"; fi
  systemctl list-timers fstrim.timer --no-pager 2>/dev/null | head -n 3 >> "$LOG"
fi

if want time; then
  sect "R6. time sync"
  cap timedatectl
  sy=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
  if [ "$sy" = yes ]; then ok "clock is NTP-synchronized"
  else
    warn "clock is NOT synchronized"
    if [ "$APPLY" = 1 ]; then
      systemctl enable --now systemd-timesyncd >> "$LOG" 2>&1; timedatectl set-ntp true >> "$LOG" 2>&1
      systemctl restart systemd-timesyncd >> "$LOG" 2>&1
      for _ in $(seq 1 15); do sleep 2; [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] && break; done
      [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] && ok "NTP synchronized now: $(date '+%F %T %Z')" || warn "still not synchronized (needs working internet: run 20-fix-network.sh --apply first)"
    else dry "enable systemd-timesyncd, timedatectl set-ntp true"; fi
  fi
fi
[ "$APPLY" = 1 ] || info "CHECK only. Run with --apply to change things."
finish
