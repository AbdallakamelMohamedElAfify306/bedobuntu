# SPDX-License-Identifier: GPL-3.0-or-later
# Shared helpers for the cheetah scripts. Works with macOS bash 3.2 and Linux bash.
FASTBOOT=${FASTBOOT:-fastboot}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUTDIR=$(cd "$HERE/.." && pwd)
IMAGES=$OUTDIR/images
STATE_FILE=${CHEETAH_STATE_FILE:-$HOME/.cheetah-linux-state}
say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"; }
sha_check() { # sha_check <dir>: verify SHA256SUMS
  ( cd "$1" && if command -v sha256sum >/dev/null 2>&1; then sha256sum -c --quiet SHA256SUMS; else shasum -a 256 -c --quiet SHA256SUMS; fi )
}
pick_phone() { # sets SERIAL; exactly one phone in fastboot
  need "$FASTBOOT" "Install Google platform-tools (https://developer.android.com/tools/releases/platform-tools)."
  local list n
  list=$("$FASTBOOT" devices 2>/dev/null | awk '$2=="fastboot"{print $1}')
  n=$(printf '%s\n' "$list" | grep -c . || true)
  [ "$n" = 1 ] || die "expected exactly one phone in fastboot mode, found $n. (adb reboot bootloader, or Power + Volume Down)"
  SERIAL=$list
}
fb() { "$FASTBOOT" -s "$SERIAL" "$@"; }
getvar_all() { fb getvar all 2>&1 | sed -E 's/^\(bootloader\) //'; }
var() { # var <name> from $VARS. <name> may contain ':' (e.g. slot-unbootable:a); handles "k: v" and "k:v" output.
  printf '%s\n' "$VARS" | tr -d '\r' | awk -v k="$1" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      if ((k ~ /:/) == 0 && v ~ /^[ab]:/) next          # "version-bootloader:a: x" is not plain "version-bootloader"
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }'
}
# The ONLY partitions these scripts may ever write (mirrors Omarchy's storage-guard allowlist UFS_RW):
ALLOWED="boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata"
BOOT_IMAGES="boot init_boot vendor_boot vendor_kernel_boot dtbo"
safe_flash() { # safe_flash <partition> <file>
  case " $ALLOWED " in *" $1 "*) ;; *) die "REFUSING to write '$1': not on the allowlist ($ALLOWED)";; esac
  printf '    fastboot flash %s %s\n' "$1" "$2"
  fb flash "$1" "$2" || die "fastboot flash $1 failed. The phone is still in fastboot; slot A is untouched. Fix the cause and re-run."
}
check_phone() { # product, unlocked
  VARS=$(getvar_all)
  [ "$(var product)" = cheetah ] || die "this phone reports product '$(var product)', not cheetah (Pixel 7 Pro). Wrong phone or wrong images."
  [ "$(var unlocked)" = yes ] || die "the bootloader is locked. Unlock it first (this erases the phone): fastboot flashing unlock"
}
set_state() { printf '%s %s\n' "$1" "$(date +%Y-%m-%dT%H:%M:%S)" > "$STATE_FILE"; }
get_state() { [ -f "$STATE_FILE" ] && cut -d' ' -f1 "$STATE_FILE" || echo none; }
