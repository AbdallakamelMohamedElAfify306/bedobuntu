# SPDX-License-Identifier: GPL-3.0-or-later
# Ubuntu build only: find the root by file system label (omamobile-root) on a partition named `ubuntu` or `userdata`,
# and allow `ubuntu` in the storage-guard allowlist. When the root is on `ubuntu`, Android's `userdata` is forced read-only.
import sys
p = sys.argv[1]; s = open(p).read()
a1 = "      boot_b|init_boot_b|vendor_boot_b|vendor_kernel_boot_b|dtbo_b|userdata) ;;"
b1 = "      boot_b|init_boot_b|vendor_boot_b|vendor_kernel_boot_b|dtbo_b|userdata|ubuntu) ;;"
a2 = '''  local dev="" s
  for s in /sys/block/sda/sda*; do
    grep -qx PARTNAME=userdata "$s/uevent" 2>/dev/null && dev=/dev/${s##*/}
  done
  [ -n "$dev" ] || { say "arch: no userdata partition"; return 1; }
'''
b2 = '''  local dev="" s
  find_root
  dev=$ROOT_DEV
  [ -n "$dev" ] || { say "arch: no omamobile-root file system on an ubuntu/userdata partition"; return 1; }
  say "arch: root is $dev ($ROOT_NAME)"
  if [ "$ROOT_NAME" = ubuntu ]; then
    # Android's own userdata sits beside us: never writable from Linux
    for s in /sys/block/sda/sda*; do
      [ "$(ufs_partname "$s")" = userdata ] && blockdev --setro "/dev/${s##*/}"
    done
  fi
'''
a3 = "boot_arch() {\n"
b3 = '''# Sets ROOT_DEV / ROOT_NAME: the ext4 labelled omamobile-root on a partition named ubuntu or userdata
# (ubuntu wins). By label, so the partition's name and number can change.
find_root() {
  local s pn lbl
  ROOT_DEV=""; ROOT_NAME=""
  for s in /sys/block/sda/sda*; do
    pn=$(ufs_partname "$s")
    case "$pn" in ubuntu|userdata) ;; *) continue ;; esac
    lbl=$(dumpe2fs -h "/dev/${s##*/}" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')
    [ "$lbl" = omamobile-root ] || continue
    if [ -z "$ROOT_DEV" ] || [ "$pn" = ubuntu ]; then ROOT_DEV=/dev/${s##*/}; ROOT_NAME=$pn; fi
  done
}
boot_arch() {
'''
for a in (a1, a2): assert s.count(a) == 1, "init layout changed: " + a[:40]
assert s.count(a3) == 1
s = s.replace(a1, b1).replace(a2, b2).replace(a3, b3)
open(p, "w").write(s)
