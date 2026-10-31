# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash check-slot-b.sh
# Read-only status of both slots (writes nothing). Run it after any Android update to see if slot B was touched.
set -euo pipefail
. "$(dirname "$0")/common.sh"
pick_phone; VARS=$(getvar_all)
for k in product unlocked current-slot version-bootloader slot-successful:a slot-unbootable:a slot-retry-count:a slot-successful:b slot-unbootable:b slot-retry-count:b; do
  printf '%-24s %s\n' "$k" "$(var "$k")"; done
echo "state file ($STATE_FILE): $(get_state)"
echo "If slot B is 'unbootable: yes' or its bootloader version changed, run scripts/reflash-slot-b.sh"
