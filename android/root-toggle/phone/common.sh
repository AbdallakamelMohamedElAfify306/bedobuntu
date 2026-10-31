# SPDX-License-Identifier: GPL-3.0-or-later
# Shared helpers for root-toggle. Sourced by other scripts. No shebang.
# Invoked as: sh /data/adb/roottoggle/unroot.sh
# NEVER touches: bootloader, slot b, sda31/32/33, userdata content, SwitchToUbuntu.

RT_DIR=/data/adb/roottoggle
SD_DIR=/sdcard/roottoggle
LOG=$SD_DIR/last.log
SLOT_PROP=ro.boot.slot_suffix
INIT_A=/dev/block/by-name/init_boot_a
INIT_B=/dev/block/by-name/init_boot_b

rt_log() {
  echo "$1" | tee -a "$LOG"
}

rt_setup_dirs() {
  mkdir -p "$RT_DIR" "$SD_DIR"
  touch "$LOG"
  rt_log "==== $(date) pid=$$ ===="
}

rt_require_slot_a() {
  s=$(getprop "$SLOT_PROP")
  rt_log "slot_suffix=$s"
  if [ "$s" = "_a" ]; then
    return 0
  fi
  rt_log "STOP: must be on Android slot a (got $s). Refusing."
  return 1
}

rt_require_root() {
  id_out=$(id)
  rt_log "id=$id_out"
  case "$id_out" in
    uid=0*) return 0 ;;
  esac
  rt_log "STOP: not running as root."
  return 1
}

rt_block_size() {
  blockdev --getsize64 "$1" 2>/dev/null
}

rt_file_size() {
  wc -c < "$1" | tr -d " "
}

rt_find_stock() {
  # Prefer user-pushed stock, then Magisk backup.
  if [ -f "$SD_DIR/init_boot_stock.img" ]; then
    echo "$SD_DIR/init_boot_stock.img"
    return 0
  fi
  if [ -f "$RT_DIR/init_boot_stock.img" ]; then
    echo "$RT_DIR/init_boot_stock.img"
    return 0
  fi
  # Magisk backup: /data/magisk_backup_*/boot.img.gz (contains the stock init_boot dump)
  for d in /data/magisk_backup_*; do
    if [ -f "$d/boot.img.gz" ]; then
      gz="$d/boot.img.gz"
      out="$RT_DIR/init_boot_stock_from_magisk.img"
      gzip -d -c "$gz" > "$out"
      echo "$out"
      return 0
    fi
  done
  return 1
}

rt_find_patched() {
  if [ -f "$SD_DIR/init_boot_patched.img" ]; then
    echo "$SD_DIR/init_boot_patched.img"
    return 0
  fi
  if [ -f "$RT_DIR/init_boot_patched.img" ]; then
    echo "$RT_DIR/init_boot_patched.img"
    return 0
  fi
  return 1
}

rt_dump_current_patched() {
  dest="$SD_DIR/init_boot_patched.img"
  rt_log "dumping current init_boot_a to $dest"
  dd if="$INIT_A" of="$dest" bs=4096 conv=fsync
  cp -f "$dest" "$RT_DIR/init_boot_patched.img"
  sz=$(rt_file_size "$dest")
  rt_log "patched dump size=$sz"
  if [ "$sz" = "0" ]; then
    rt_log "STOP: patched dump empty"
    return 1
  fi
  return 0
}

rt_flash_img() {
  img="$1"
  dev="$2"
  label="$3"
  isz=$(rt_file_size "$img")
  bsz=$(rt_block_size "$dev")
  rt_log "flash $label: img=$img isz=$isz dev=$dev bsz=$bsz"
  if [ -z "$isz" ]; then
    rt_log "STOP: bad image size"
    return 1
  fi
  if [ -z "$bsz" ]; then
    rt_log "STOP: bad block size"
    return 1
  fi
  # Refuse if image larger than partition (compare as strings via expr)
  if [ "$(expr "$isz" \> "$bsz")" = "1" ]; then
    rt_log "STOP: image larger than partition"
    return 1
  fi
  blockdev --setrw "$dev"
  ro=$(blockdev --getro "$dev")
  rt_log "dev_ro=$ro"
  if [ "$ro" = "1" ]; then
    rt_log "STOP: partition is read-only"
    return 1
  fi
  # Write image then pad remainder with zeros (Magisk flash_image style)
  dd if="$img" of="$dev" bs=4096 conv=fsync
  # If image shorter than partition, zero the rest via dd seek
  if [ "$(expr "$isz" \< "$bsz")" = "1" ]; then
    pad=$(expr "$bsz" - "$isz")
    rt_log "padding zeros bytes=$pad"
    dd if=/dev/zero of="$dev" bs=1 seek="$isz" count="$pad" conv=fsync
  fi
  sync
  rt_log "flash $label done"
  return 0
}

rt_is_magisk_live() {
  if [ -e /data/adb/magisk ]; then
    if magisk -v >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}
