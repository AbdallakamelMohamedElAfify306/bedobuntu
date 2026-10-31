# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash to-linux.sh
# Switch to Linux (slot B) WITHOUT reflashing: only valid while userdata still holds the Linux root,
# i.e. Android has not been booted since the last flash-linux.sh. Otherwise use flash-linux.sh again.
set -euo pipefail
. "$(dirname "$0")/common.sh"
st=$(get_state)
[ "$st" = linux-installed ] || die "state is '$st': Android has booted (or Linux was never installed) since the last flash, so userdata no longer holds the Linux root. Run scripts/flash-linux.sh to reinstall (this erases Android's userdata again)."
pick_phone; check_phone
[ "$(var slot-unbootable:b)" = no ] || { echo "slot B is marked unbootable: re-flash with scripts/reflash-slot-b.sh"; exit 1; }
fb --set-active=b; fb reboot
