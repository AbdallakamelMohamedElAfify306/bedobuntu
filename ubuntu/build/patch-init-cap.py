# SPDX-License-Identifier: GPL-3.0-or-later
# Ubuntu build only: cap Omarchy's grow_root at the size in /etc/omamobile-root-cap (MiB) instead of filling userdata.
import sys
p = sys.argv[1]; s = open(p).read()
a1 = '''  fs_bytes=$((blocks * bsize))
  [ $((part_bytes - fs_bytes)) -gt 67108864 ] || return 0
  say "arch: growing the root file system to fill $dev ($((fs_bytes >> 20)) MiB to $((part_bytes >> 20)) MiB)"'''
b1 = '''  fs_bytes=$((blocks * bsize))
  cap_mib=$(cat /etc/omamobile-root-cap 2>/dev/null || echo 0)
  cap_mib=$(printf '%s' "$cap_mib" | tr -cd '0-9'); case $cap_mib in '') cap_mib=0;; esac
  if [ "$cap_mib" -gt 0 ] && [ "$part_bytes" -gt $((cap_mib << 20)) ]; then part_bytes=$((cap_mib << 20)); fi
  [ $((part_bytes - fs_bytes)) -gt 67108864 ] || return 0
  say "arch: growing the root file system ($((fs_bytes >> 20)) MiB to $((part_bytes >> 20)) MiB, capped at $cap_mib MiB)"'''
a2 = 'if resize2fs "$dev" > /run/resize2fs.log 2>&1; then'
b2 = 'if resize2fs "$dev" "$((part_bytes >> 20))M" > /run/resize2fs.log 2>&1; then'
assert a1 in s and a2 in s, "init layout changed"
open(p, 'w').write(s.replace(a1, b1).replace(a2, b2))
