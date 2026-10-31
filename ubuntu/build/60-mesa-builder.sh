# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 60-mesa-builder.sh
# Create an Ubuntu noble arm64 build chroot (under qemu-user) with what Mesa 26.2.4 needs. Run as root. Resumable.
set -euo pipefail
source "$(dirname "$0")/env.sh"
B=${CHEETAH_MESA:-$HOME/cheetah-dual/mesa-build}/chroot
[ -f "$B/.builder-done" ] && { echo "builder exists"; exit 0; }
rm -rf "$B"
PK="build-essential,pkg-config,python3,python3-pip,python3-mako,python3-yaml,python3-ply,python3-packaging,python3-pycparser,python3-setuptools,ninja-build,bison,flex,cmake,git,xz-utils,curl,ca-certificates,llvm-18-dev,libclang-18-dev,libclang-cpp18-dev,clang-18,libclc-18-dev,libllvmspirvlib-18-dev,spirv-tools,glslang-tools,libdrm-dev,libwayland-dev,libwayland-egl-backend-dev,wayland-protocols,libglvnd-dev,libexpat1-dev,zlib1g-dev,libzstd-dev,libelf-dev,libxml2-dev,libx11-dev,libxcb1-dev,libxext-dev,libxfixes-dev,libxrandr-dev,libxshmfence-dev,libx11-xcb-dev,libxcb-dri3-dev,libxcb-present-dev,libxcb-sync-dev,libxcb-xfixes0-dev,libxcb-randr0-dev,libxcb-dri2-0-dev,libxcb-glx0-dev,libxxf86vm-dev,libudev-dev,ubuntu-keyring"
mmdebstrap --mode=root --arch=arm64 --variant=minbase --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
  --aptopt='APT::Install-Recommends "false"' --include="$PK" noble "$B" - <<SRC
deb $MIRROR noble main universe
deb $MIRROR noble-updates main universe
deb $MIRROR noble-security main universe
SRC
touch "$B/.builder-done"; echo "BUILDER DONE"
