# SPDX-License-Identifier: GPL-3.0-or-later
# Soft hide: fully on-phone, reversible. Does NOT remove Magisk from boot.
# Turns Zygisk off, enables Enforce DenyList, adds bank packages.
# Honest: HSBC/NBE/Instapay/AnaVodafone/PayPal already defeated this once.

. /data/adb/roottoggle/common.sh

rt_setup_dirs
rt_require_root || exit 30

PKGS="com.htsu.hsbcpersonalbanking com.ofss.obdx.and.nbe.com.eg com.emeint.android.myservices com.egyptianbanks.instapay com.payoneer.android com.paypal.android.p2pmobile com.google.android.gms.policy_sidecar_aps com.android.vending"

rt_log "soft-hide start"

# Prefer Magisk CLI
magisk --denylist enable 2>/dev/null || true
for p in $PKGS; do
  magisk --denylist add "$p" 2>/dev/null || true
  am force-stop "$p" 2>/dev/null || true
done

# Disable Zygisk via Magisk DB if present (zygisk=0)
if [ -f /data/adb/magisk.db ]; then
  magisk --sqlite "UPDATE settings SET value=0 WHERE key=\"zygisk\"" 2>/dev/null || true
fi

# Disable all modules temporarily (creates disable flag; soft-show removes it)
for d in /data/adb/modules/*; do
  if [ -d "$d" ]; then
    # Keep nothing special; user can soft-show later
    touch "$d/disable" 2>/dev/null || true
    rt_log "disabled module $(basename $d)"
  fi
done

echo "soft-hidden" > "$SD_DIR/state"
echo "soft-hidden" > "$RT_DIR/state"
rt_log "SOFT-HIDE-OK: reboot recommended"
