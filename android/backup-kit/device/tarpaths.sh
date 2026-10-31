# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# Runs as root. Streams a tar.gz of the given paths (relative to /, no leading slash).
# Missing paths are skipped. Exit 3 and no output if none exist.
R=${ABK_ROOT:-}
T=${ABK_TMP:-/data/local/tmp/abk}
LIST=
for a in "$@"; do
  if [ -e "$R/$a" ]; then LIST="$LIST $a"; else echo "missing: $a" >> "$T/tar.err"; fi
done
[ -n "$LIST" ] || exit 3
# shellcheck disable=SC2086
exec tar -czf - -C "${R:-/}" $LIST 2>>"$T/tar.err"
