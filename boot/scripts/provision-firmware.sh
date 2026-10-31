# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash provision-firmware.sh
# Put Google's Wi-Fi / Bluetooth / haptics / audio firmware on the phone, taken from YOUR OWN Google factory image
# (Google's firmware is not redistributable, so it is not in this package). Runs on a Linux PC (or in Docker on a Mac):
#   ./provision-firmware.sh cheetah-<build>-factory-<id>.zip        # then it pushes over USB networking
# Needs: unzip, e2fsprogs (debugfs), android-sdk-libsparse-utils (simg2img), lpunpack (android-sdk-libsparse-utils or
# 'lpunpack' pkg), erofs-utils; on the phone side: ssh to user@172.16.42.1 (set your Mac/PC to 172.16.42.2/24 first).
# Mac users: docker run --rm -it -v "$PWD":/w -w /w debian:trixie bash -c 'apt-get update && apt-get install -y unzip e2fsprogs android-sdk-libsparse-utils erofs-utils python3 openssh-client android-tools-fsutils; ./scripts/provision-firmware.sh <zip> --stage-only'
set -euo pipefail
ZIP=${1:?usage: provision-firmware.sh FACTORY.zip [--stage-only]}
HERE=$(cd "$(dirname "$0")" && pwd)
STAGE=${STAGE:-$PWD/cheetah-firmware-stage}
"$HERE/extract-vendor-firmware" -o "$STAGE" "$ZIP"
[ "${2:-}" = "--stage-only" ] && { echo "staged in $STAGE; push it with: tar -C $STAGE -cf - usr | ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'tar -C / -xf - && depmod -a'"; exit 0; }
KEY=${KEY:-${CHEETAH_SSH_KEY:?set CHEETAH_SSH_KEY to your private key path}}
tar -C "$STAGE" -cf - usr | ssh -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new root@172.16.42.1 'tar -C / -xf - && depmod -a && echo "firmware installed; reboot the phone"'
