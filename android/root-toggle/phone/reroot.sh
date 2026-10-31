# SPDX-License-Identifier: GPL-3.0-or-later
# On-phone re-root: ONLY works if Magisk/su is still alive (e.g. you have not rebooted
# after a Restore Images, or you are still on a patched boot). After a real unroot+reboot,
# su is gone and this script cannot run - use Mac mac/reroot.sh instead.

. /data/adb/roottoggle/common.sh

rt_setup_dirs
rt_require_root || {
  rt_log "STOP: no root. Re-root from Mac:"
  rt_log "  bash $HOME/cheetah-dual/root-toggle/mac/reroot.sh"
  exit 20
}
rt_require_slot_a || exit 21

patched=$(rt_find_patched)
if [ -z "$patched" ]; then
  rt_log "STOP: no patched init_boot saved. Cannot re-root on phone."
  exit 22
fi
rt_log "using patched=$patched"

echo "rooted" > "$SD_DIR/state"
echo "rooted" > "$RT_DIR/state"
date > "$SD_DIR/rooted_at"
cp -f "$SD_DIR/rooted_at" "$RT_DIR/rooted_at"

rt_flash_img "$patched" "$INIT_A" "init_boot_a-patched" || exit 23

rt_log "REROOT-OK: patched init_boot_a written. Rebooting in 3s."
sleep 3
/system/bin/reboot
