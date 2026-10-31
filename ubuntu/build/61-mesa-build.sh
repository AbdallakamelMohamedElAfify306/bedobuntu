# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 61-mesa-build.sh
# Build Mesa 26.2.4 (the version Omarchy Mobile uses) + Omarchy's Mali-G710 model patch (0001) and the panthor image-BO fix (0002)
# natively inside the Ubuntu noble arm64 build chroot (under qemu-user). Run as root. Resumable (ninja is incremental).
# Result: ${CHEETAH_MESA:-$HOME/cheetah-dual/mesa-build}/chroot/build/dest (DESTDIR tree, prefix /usr, libdir lib/aarch64-linux-gnu)
set -euo pipefail
source "$(dirname "$0")/env.sh"
B=${CHEETAH_MESA:-$HOME/cheetah-dual/mesa-build}/chroot; MV=26.2.4
mkdir -p $B/build
mount -t proc proc $B/proc 2>/dev/null || true; mount --bind /dev $B/dev 2>/dev/null || true
cp /etc/resolv.conf $B/etc/resolv.conf
cp "$OMA"/packages/mesa/0001-*.patch "$OMA"/packages/mesa/0002-*.patch $B/build/
[ -f ${CHEETAH_MESA:-$HOME/cheetah-dual/mesa-build}/mesa-$MV.tar.xz ] && cp -n ${CHEETAH_MESA:-$HOME/cheetah-dual/mesa-build}/mesa-$MV.tar.xz $B/build/
cat > $B/build/run.sh <<'IN'
# run-with bash
set -euo pipefail
cd /build
export PATH=/usr/local/bin:$PATH PKG_CONFIG_PATH=/usr/local/share/pkgconfig:/usr/local/lib/pkgconfig
[ -x /usr/local/bin/meson ] || pip3 install --break-system-packages 'meson>=1.4,<1.10' >/dev/null
pkg-config --atleast-version=1.41 wayland-protocols
if [ $? -ne 0 ]; then
  [ -d wayland-protocols-1.41 ] || { curl -fsSL -o wp.tar.xz https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/1.41/downloads/wayland-protocols-1.41.tar.xz && tar xf wp.tar.xz; }
  (cd wayland-protocols-1.41 && meson setup b --prefix=/usr/local -Dtests=false && ninja -C b install)
fi
if { [ -d mesa-26.2.4  ]; [ $? -ne 0 ]; }; then tar xf mesa-26.2.4.tar.xz; (cd mesa-26.2.4 && patch -p1 < ../0001-*.patch && patch -p1 < ../0002-*.patch); fi
cd mesa-26.2.4
if { [ -f ../b/build.ninja  ]; [ $? -ne 0 ]; }; then
  LLVM_CONFIG=llvm-config-18 meson setup ../b --prefix=/usr --libdir=lib/aarch64-linux-gnu --buildtype=release -Db_ndebug=true \
    -Dgallium-drivers=panfrost,llvmpipe -Dvulkan-drivers= -Dplatforms=wayland -Dglx=disabled -Dgbm=enabled -Degl=enabled \
    -Dgles1=disabled -Dgles2=enabled -Dopengl=true -Dllvm=enabled -Dshared-llvm=enabled -Dvalgrind=disabled -Dlibunwind=disabled \
    -Dlmsensors=disabled -Dgallium-va=disabled -Dgallium-rusticl=false -Dvideo-codecs= -Dglvnd=enabled \
    -Dbuild-tests=false -Dxlib-lease=disabled
fi
ninja -C ../b -j${JOBS:-7}
rm -rf /build/dest; DESTDIR=/build/dest meson install -C ../b --strip
echo MESA_BUILD_DONE
IN
chmod +x $B/build/run.sh
chroot $B /build/run.sh
