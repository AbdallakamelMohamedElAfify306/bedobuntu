# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 00-step0-undo-wallpaper.sh
# Step 0 - make sure the Phosh wallpaper/stylesheet override is gone (idempotent).
# shellcheck disable=SC2015
# Usage: bash 00-step0-undo-wallpaper.sh [--check|--apply]
# Nothing is deleted: removed files are MOVED to $HEALTH_DIR/backup/wallpaper-undo-<ts>/.
# Keeps: /opt/phosh-overlay/sm/puri/phosh/ui (top-panel.ui) and 20-clock-right.conf.
. "$(dirname "$0")/lib.sh"
parse_args "$@"; init_log

S=/opt/phosh-overlay/sm/puri/phosh/stylesheet
B="$HEALTH_DIR/backup/wallpaper-undo-$TS"
found=0

sect "0.1 stylesheet override directory"
if [ -e "$S" ]; then
  found=1; info "found $S"; ls -la "$S" >> "$LOG" 2>&1
  if [ "$APPLY" = 1 ]; then mkdir -p "$B" && mv "$S" "$B/stylesheet" && ok "moved $S -> $B/stylesheet"; else dry "mv $S $B/stylesheet"; fi
else
  ok "no stylesheet override at $S"
fi

sect "0.2 systemd drop-ins named zz-wallpaper.conf"
for f in /etc/systemd/system/*.d/zz-wallpaper.conf; do
  [ -e "$f" ] || continue
  found=1; info "found $f"
  if [ "$APPLY" = 1 ]; then mkdir -p "$B/dropins" && mv "$f" "$B/dropins/$(basename "$(dirname "$f")").zz-wallpaper.conf" && ok "moved $f"; else dry "mv $f $B/dropins/"; fi
done
[ -e /etc/systemd/system/pixel-phosh.service.d/zz-wallpaper.conf ] || [ -e /etc/systemd/system/phosh.service.d/zz-wallpaper.conf ] || ok "no zz-wallpaper.conf drop-in left"

sect "0.3 other drop-ins that mention the stylesheet path (reported, never touched)"
others=$(grep -l 'phosh/stylesheet' /etc/systemd/system/*.d/*.conf /etc/systemd/system/*.service 2>/dev/null)
if [ -n "$others" ]; then warn "these files still mention phosh/stylesheet - review manually: $others"; else ok "no other file mentions phosh/stylesheet"; fi

sect "0.4 *.bak-wall backups -> restore originals"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  found=1; orig=${f%.bak-wall}
  if [ "$APPLY" = 1 ]; then
    mkdir -p "$B/restored"
    [ -e "$orig" ] && cp -a "$orig" "$B/restored/$(printf '%s' "$orig" | tr '/' '_')"
    mv -f "$f" "$orig" && ok "restored $orig"
  else
    dry "restore $orig from $f"
  fi
done < <(find /etc /usr/local /usr/lib/systemd /opt /home/user/.config -name '*.bak-wall' 2>/dev/null)

sect "0.5 per-user gtk.css left by earlier attempts"
for g in /home/user/.config/gtk-3.0/gtk.css /home/user/.config/gtk-4.0/gtk.css; do
  [ -f "$g" ] || continue
  if grep -qE 'phosh-(home|lockscreen|overview)|lockshield|my-wall|wallpaper' "$g"; then
    found=1; info "$g contains wallpaper/lockscreen CSS"
    if [ "$APPLY" = 1 ]; then mkdir -p "$B/gtk" && mv "$g" "$B/gtk/$(basename "$(dirname "$g")").gtk.css" && ok "moved $g"; else dry "mv $g $B/gtk/"; fi
  else
    ok "$g has no wallpaper CSS (left alone)"
  fi
done

sect "0.6 what is the RUNNING phosh using?"
P=$(phosh_pid); U=$(phosh_unit)
info "phosh pid=${P:-none} unit=${U:-unknown}"
ov=$(phosh_env G_RESOURCE_OVERLAYS)
info "G_RESOURCE_OVERLAYS(running)=${ov:-<none>}"
need_restart=0
case "$ov" in *stylesheet=*) need_restart=1; warn "running phosh still loads the stylesheet override";; esac
if [ "$found" = 1 ]; then need_restart=1; fi

sect "0.7 apply: reload + restart phosh only if needed"
if [ "$need_restart" = 1 ] && [ -n "$U" ]; then
  if [ "$APPLY" = 1 ]; then
    systemctl daemon-reload >> "$LOG" 2>&1 && ok "daemon-reload"
    systemctl restart "$U" >> "$LOG" 2>&1 && ok "restarted $U (open apps on the phone are closed)" || fail "restart $U failed"
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 2; phosh_pid >/dev/null && break; done
    sleep 3
  else
    dry "systemctl daemon-reload; systemctl restart $U"
  fi
else
  ok "no restart needed"
fi

sect "0.8 verification"
if [ "$APPLY" = 1 ] || [ "$need_restart" = 0 ]; then
  ov=$(phosh_env G_RESOURCE_OVERLAYS)
  info "G_RESOURCE_OVERLAYS now=${ov:-<none>}"
  case "$ov" in *stylesheet=*) fail "stylesheet override still active";; *) ok "no stylesheet override in the running phosh";; esac
  case "$ov" in *"/sm/puri/phosh/ui="*) ok "UI overlay (top-panel.ui) still active";; *) warn "UI overlay missing from G_RESOURCE_OVERLAYS - expected 20-clock-right.conf to set /sm/puri/phosh/ui=/opt/phosh-overlay/sm/puri/phosh/ui";; esac
  phosh_pid >/dev/null && ok "phosh is running (pid $(phosh_pid))" || fail "phosh is not running: journalctl -u ${U:-pixel-phosh} -n 30"
fi
[ -f /opt/phosh-overlay/sm/puri/phosh/ui/top-panel.ui ] && ok "top-panel.ui overlay present" || warn "top-panel.ui overlay missing (clock will be visible again)"
[ -f /etc/systemd/system/pixel-phosh.service.d/20-clock-right.conf ] && ok "20-clock-right.conf present" || warn "20-clock-right.conf not found in pixel-phosh.service.d"
[ -n "$(find /opt/phosh-overlay -name '*.css' 2>/dev/null)" ] && fail "css files remain under /opt/phosh-overlay" || ok "no css under /opt/phosh-overlay"
[ "$APPLY" = 1 ] || info "this was a CHECK. To fix, run again with --apply"
finish
