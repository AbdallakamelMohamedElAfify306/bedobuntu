# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash test-static.sh
# Static gates: bash -n, shellcheck (if installed), forbidden commands, exclamation marks in COMMANDS.txt, SHA256SUMS freshness.
KIT=$(cd "$(dirname "$0")/.." && pwd); cd "$KIT" || exit 1; bad=0
for f in *.sh tests/*.sh; do bash -n "$f" || { echo "SYNTAX $f"; bad=1; }; done
SC=$(command -v shellcheck || ls "$KIT/../venv-sc/bin/shellcheck" 2>/dev/null)
if [ -n "$SC" ]; then for f in *.sh; do "$SC" -x -s bash "$f" >/dev/null || { echo "SHELLCHECK $f"; bad=1; }; done; else echo "shellcheck not installed (skipped)"; fi
# forbidden: anything that can write a partition table / filesystem / flash. (mkswap only on zram, checked separately)
if grep -nE '(^|[ ;|&(`])(mkfs[.a-z0-9]*|dd|sgdisk|sfdisk|fdisk|parted|wipefs|blkdiscard|fastboot|tune2fs|resize2fs|e2fsck|badblocks|losetup|blockdev|mke2fs)( |$)' -- [0-9]*.sh lib.sh | grep -v '^\S*:[0-9]*:\s*#'; then echo "FORBIDDEN command found"; bad=1; fi
grep -nE 'mkswap +(/dev/(sd|mmc|nvme)|"?\$[A-Za-z_]*(PART|DEV_?SD))' [0-9]*.sh && { echo "mkswap on a non-zram device"; bad=1; }
grep -n 'case "\$dev" in /dev/zram' 21-repair-system.sh >/dev/null || { echo "zram device guard missing"; bad=1; }
grep -n '/dev/sd' [0-9]*.sh lib.sh | grep -vE '^\S*:[0-9]*:\s*#|sda3[123]|findmnt|grep -q sda32|grep -qE|mount \|' && { echo "unexpected /dev/sd reference"; bad=1; }
grep -qF "$(printf '\41')" COMMANDS.txt && { echo "exclamation mark in COMMANDS.txt"; bad=1; }
bash tests/lint-commands.sh || bad=1
[ -f SHA256SUMS ] && { sha256sum -c SHA256SUMS --quiet 2>/dev/null || { echo "SHA256SUMS stale"; bad=1; }; }
[ "$bad" = 0 ] && echo "ALL STATIC GATES PASS" || echo "STATIC GATES FAILED"; exit $bad
