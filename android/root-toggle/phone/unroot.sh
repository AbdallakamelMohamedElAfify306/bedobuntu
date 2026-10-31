# SPDX-License-Identifier: GPL-3.0-or-later
# Hard unroot: flash stock init_boot_a, keep /data/adb and modules on disk, reboot.
# Re-root later needs Mac+fastboot (see mac/reroot.sh). Fully on-phone for THIS direction.
# Run: su -c "sh /data/adb/roottoggle/unroot.sh"

. /data/adb/roottoggle/common.sh

rt_setup_dirs
rt_require_root || exit 10
rt_require_slot_a || exit 11

if [ -e "$INIT_B" ]; then
  rt_log "init_boot_b present (Ubuntu slot) - will NOT touch it"
fi

# Refuse if already unrooted - otherwise we would overwrite the saved Magisk image with stock
if [ -f "$SD_DIR/state" ]; then
  st=$(cat "$SD_DIR/state")
  if [ "$st" = "unrooted" ]; then
    rt_log "STOP: state is already unrooted. Refusing to dump (would clobber patched image)."
    rt_log "Re-root from Mac first: bash $HOME/cheetah-dual/root-toggle/mac/reroot.sh"
    exit 15
  fi
fi
if magisk -v >/dev/null 2>&1; then
  :
else
  rt_log "STOP: Magisk not live. Refusing unroot dump."
  exit 16
fi

# Save currently-running patched image so Mac can reflash it later
rt_dump_current_patched || exit 12

stock=$(rt_find_stock)
if [ -z "$stock" ]; then
  rt_log "STOP: no stock init_boot on phone."
  rt_log "Push it once from Mac:"
  rt_log "  adb push $HOME/cheetah-dual/root/init_boot_stock.img /sdcard/roottoggle/init_boot_stock.img"
  exit 13
fi
rt_log "using stock=$stock"
cp -f "$stock" "$SD_DIR/init_boot_stock.img"
cp -f "$stock" "$RT_DIR/init_boot_stock.img"

# Mark state BEFORE flashing so status works after reboot
echo "unrooted" > "$SD_DIR/state"
echo "unrooted" > "$RT_DIR/state"
date > "$SD_DIR/unrooted_at"
cp -f "$SD_DIR/unrooted_at" "$RT_DIR/unrooted_at"

rt_flash_img "$stock" "$INIT_A" "init_boot_a-stock" || exit 14

rt_log "UNROOT-OK: stock init_boot_a written. Rebooting in 3s."
rt_log "To re-root later on Mac: bash $HOME/cheetah-dual/root-toggle/mac/reroot.sh"
sleep 3
/system/bin/reboot
