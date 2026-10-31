# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# Runs as root. Prints TAB separated lines: package, apk path, size in bytes.
# No argument: all third-party apps. With a package name: only that package.
if [ -n "${1:-}" ]; then
  LIST="package:$1"
else
  LIST=$(pm list packages -3 2>/dev/null < /dev/null)
fi
printf '%s\n' "$LIST" | while read -r l; do
  p=${l#package:}
  [ -n "$p" ] || continue
  pm path "$p" 2>/dev/null < /dev/null | while read -r a; do
    f=${a#package:}
    sz=$(stat -c %s "$f" 2>/dev/null)
    [ -n "$sz" ] && printf '%s\t%s\t%s\n' "$p" "$f" "$sz"
  done
done
exit 0
