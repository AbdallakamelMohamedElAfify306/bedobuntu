# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash to-android.sh
# Switch the active slot back to Android (slot A). Writes NO partition: only `fastboot --set-active=a` + reboot.
# Because Linux lives in userdata, Android will find a file system it cannot read and will either offer
# "Factory data reset" in recovery or format userdata itself. Say yes: that is the (expected) price of switching.
set -euo pipefail
. "$(dirname "$0")/common.sh"
pick_phone; VARS=$(getvar_all)
[ "$(var product)" = cheetah ] || die "not a cheetah"
note "slot A: successful=$(var slot-successful:a) unbootable=$(var slot-unbootable:a)"
[ "$(var slot-unbootable:a)" = no ] || die "slot A is marked unbootable. Use Google's Android Flash Tool to restore Android (see README_AR.md)."
cat <<'MSG'
Linux's root file system lives in userdata, so after this switch Linux is erased when Android formats userdata.
Android's own data was already erased when Linux was installed. Continue only if you accept that.
MSG
printf 'Type ANDROID to continue: '; read -r a; [ "$a" = ANDROID ] || die "cancelled"
fb --set-active=a; fb reboot
set_state android-booted
echo "If Android shows 'Can't load Android system' choose 'Factory data reset' (this erases only userdata)."
echo "Then turn OFF automatic system updates before connecting to the internet: scripts/android-protect-from-ota.sh"
