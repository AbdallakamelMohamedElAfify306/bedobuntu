# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# Runs as root. Prints the size in bytes of /dev/block/by-name/NAME, or NONE.
R=${ABK_ROOT:-}
n=${1:-}
printf '%s\n' "$n" | grep -Eq '^[a-z0-9_]+$' || { echo NONE; exit 0; }
l="$R/dev/block/by-name/$n"
[ -e "$l" ] || { echo NONE; exit 0; }
t=$(readlink -f "$l")
b=${t##*/}
s=$(cat "$R/sys/class/block/$b/size" 2>/dev/null)
if [ -n "$s" ]; then echo $((s * 512)); else echo NONE; fi
