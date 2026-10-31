# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# Runs as root. Streams a plain tar of /data/media/0 (photos, videos, all internal storage).
# Excluded: Shared (the mounted shared partition), Android/data and Android/obb (saved in the apps step).
# The exclusion is done by building an explicit list, so no tar exclude flag is needed.
R=${ABK_ROOT:-}
T=${ABK_TMP:-/data/local/tmp/abk}
M="$R/data/media/0"
cd "$M" || exit 3
set --
for f in * .*; do
  case $f in .|..|Shared|Android) continue ;; esac
  [ -e "$f" ] || [ -L "$f" ] || continue
  set -- "$@" "$f"
done
for f in Android/* Android/.*; do
  case $f in Android/.|Android/..|Android/data|Android/obb) continue ;; esac
  [ -e "$f" ] || [ -L "$f" ] || continue
  set -- "$@" "$f"
done
[ $# -gt 0 ] || exit 3
exec tar -cf - -C "$M" "$@" 2>>"$T/tar.err"
