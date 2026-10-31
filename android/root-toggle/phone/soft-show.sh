# SPDX-License-Identifier: GPL-3.0-or-later
# Undo soft-hide. Re-enables modules and Zygisk. Fully on-phone.

. /data/adb/roottoggle/common.sh

rt_setup_dirs
rt_require_root || exit 40

rt_log "soft-show start"

for d in /data/adb/modules/*; do
  if [ -d "$d" ]; then
    rm -f "$d/disable" 2>/dev/null || true
    rt_log "enabled module $(basename $d)"
  fi
done

if [ -f /data/adb/magisk.db ]; then
  magisk --sqlite "UPDATE settings SET value=1 WHERE key=\"zygisk\"" 2>/dev/null || true
fi

# Leave denylist as-is (still useful with Zygisk-Assistant)

echo "rooted" > "$SD_DIR/state"
echo "rooted" > "$RT_DIR/state"
rt_log "SOFT-SHOW-OK: reboot recommended"
