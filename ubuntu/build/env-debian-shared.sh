# SPDX-License-Identifier: GPL-3.0-or-later
# Shared settings for the cheetah Debian/shared kernel build. Source me.
export UC="${CHEETAH_BUILD:?set CHEETAH_BUILD to the build tree root}"
export OMA="${OMA:-$UC/src/omarchy-mobile}"
export KSRC="${KSRC:-$UC/src/linux-omarchy-mobile}"
export KOUT="${KOUT:-$UC/build/kernel-out}"
export WORKDIR="${WORKDIR:-$UC/build/work}"
export OUT="${OUT:-$UC/out}"
export LOGS="${LOGS:-$UC/logs}"
export DEVICE=cheetah
export JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
mkdir -p "$WORKDIR" "$OUT" "$LOGS" "$KOUT"
