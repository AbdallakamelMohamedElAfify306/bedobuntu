# SPDX-License-Identifier: GPL-3.0-or-later
# Magisk service.d props spoof. Idempotent. Copied to /data/adb/service.d/99-props-spoof.sh
# Softens common bootloader-unlocked property signals for apps that only read getprop.
# Cannot fake hardware attestation / STRONG integrity.

MODDIR=${0%/*}
LOG=/data/local/tmp/props-spoof.log
echo "props-spoof start $(date)" >"$LOG"

rp() {
  k="$1"; v="$2"
  cur=$(getprop "$k")
  echo "set $k=$v (was $cur)" >>"$LOG"
  resetprop "$k" "$v" >>"$LOG" 2>&1 || resetprop -n "$k" "$v" >>"$LOG" 2>&1 || true
}

# Delay so late props settle, then re-apply.
sleep 3
rp ro.boot.verifiedbootstate green
rp ro.boot.flash.locked 1
rp ro.boot.vbmeta.device_state locked
rp ro.debuggable 0
rp ro.secure 1
rp ro.build.tags release-keys
rp ro.build.type user

# Some OEMs expose warranty bits
if [ -n "$(getprop ro.boot.warranty_bit)" ]; then
  rp ro.boot.warranty_bit 0
fi
if [ -n "$(getprop ro.warranty_bit)" ]; then
  rp ro.warranty_bit 0
fi

# Re-apply once more after boot_completed for props that get overwritten
i=0
while [ "$i" -lt 60 ]; do
  bc=$(getprop sys.boot_completed)
  if [ "$bc" = "1" ]; then
    break
  fi
  sleep 2
  i=$((i+1))
done
sleep 5
rp ro.boot.verifiedbootstate green
rp ro.boot.flash.locked 1
rp ro.boot.vbmeta.device_state locked
rp ro.debuggable 0
rp ro.secure 1
rp ro.build.tags release-keys
rp ro.build.type user

echo "props-spoof done $(date)" >>"$LOG"
