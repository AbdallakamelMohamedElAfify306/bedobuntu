# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# Runs as root on the phone. Streams a tar.gz of one app's data to stdout.
# Usage: sh pkgtar.sh PACKAGE   (package name is validated here and on the Mac)
R=${ABK_ROOT:-}
T=${ABK_TMP:-/data/local/tmp/abk}
P=${1:-}
printf '%s\n' "$P" | grep -Eq '^[A-Za-z0-9._]+$' || exit 2
set --
for d in "data/data/$P" "data/user_de/0/$P" "data/media/0/Android/data/$P"; do
  [ -e "$R/$d" ] && set -- "$@" "$d"
done
[ $# -gt 0 ] || exit 3
exec tar -czf - -C "${R:-/}" "$@" 2>>"$T/tar.err"
