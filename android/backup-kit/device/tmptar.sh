# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# Runs as root. Streams a tar.gz of /data/local/tmp (loose scripts), skipping our own work dir
# and any single entry bigger than 1 GiB (it is named in tar.err instead).
R=${ABK_ROOT:-}
T=${ABK_TMP:-/data/local/tmp/abk}
M="$R/data/local/tmp"
cd "$M" || exit 3
set --
for f in * .*; do
  case $f in .|..|abk) continue ;; esac
  [ -e "$f" ] || [ -L "$f" ] || continue
  kb=$(du -sk "$f" 2>/dev/null | cut -f1)
  if [ "${kb:-0}" -gt 1048576 ]; then echo "skipped big entry: $f ${kb}KB" >> "$T/tar.err"; continue; fi
  set -- "$@" "$f"
done
[ $# -gt 0 ] || exit 3
exec tar -czf - -C "$M" "$@" 2>>"$T/tar.err"
