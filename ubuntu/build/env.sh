# SPDX-License-Identifier: GPL-3.0-or-later
# Shared settings for the cheetah Ubuntu build. Source me.
# Set CHEETAH_BUILD to your checkout of the build tree (kernel + omarchy-mobile sources).
export UC="${CHEETAH_BUILD:?set CHEETAH_BUILD to the build tree root}"
export OMA="${OMA:-$UC/src/omarchy-mobile}"
export KSRC="${KSRC:-$UC/src/linux-omarchy-mobile}"
export KOUT="${KOUT:-$UC/build/kernel-out}"
export WORKDIR="${WORKDIR:-$UC/build/work}"
export UWORK="${UWORK:-$UC/build-ubuntu/work}"
export OUT="${OUT:-$UC/out-ubuntu}"
export LOGS="${LOGS:-$UC/logs}"
export DEVICE=cheetah
export SUITE="${SUITE:-noble}"
export MIRROR="${MIRROR:-https://ports.ubuntu.com/ubuntu-ports}"
export JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
mkdir -p "$UWORK" "$OUT" "$LOGS" "$WORKDIR" "$KOUT"
