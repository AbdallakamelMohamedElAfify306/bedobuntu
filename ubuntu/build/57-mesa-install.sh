# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 57-mesa-install.sh
# Replace Ubuntu's Mesa in the rootfs with our Mesa 26.2.4 build (Mali-G710 patch), as one package "mesa-cheetah" that
# Provides the Ubuntu package names. Run as root, after 61-mesa-build.sh. Idempotent.
set -euo pipefail
source "$(dirname "$0")/env.sh"
R=$UWORK/rootfs; DEST=${CHEETAH_MESA:-$HOME/cheetah-dual/mesa-build}/chroot/build/dest; MV=26.2.4
[ -d "$DEST/usr/lib/aarch64-linux-gnu" ] || { echo "run 61-mesa-build.sh first"; exit 1; }
D=$UWORK/mesa-cheetah-deb; rm -rf "$D"; mkdir -p "$D/DEBIAN"
cp -a "$DEST/." "$D/"
rm -rf "$D/usr/include" "$D/usr/lib/aarch64-linux-gnu/pkgconfig" "$D/usr/share/man"
PROV=""; for p in libegl-mesa0 libgbm1 libgl1-mesa-dri libglx-mesa0 mesa-libgallium mesa-vulkan-drivers libglapi-mesa; do PROV="$PROV${PROV:+, }$p (= $MV)"; done
CONF=${PROV//(= $MV)/}
cat > "$D/DEBIAN/control" <<X
Package: mesa-cheetah
Version: $MV-0cheetah1
Architecture: arm64
Maintainer: cheetah build <nobody@localhost>
Section: libs
Priority: optional
Depends: libllvm18, libdrm2, libwayland-client0, libwayland-server0, libwayland-egl1, libexpat1, libzstd1, libelf1t64, zlib1g, libglvnd0, libegl1, libgles2, libstdc++6, libgcc-s1
Provides: $PROV
Conflicts: $CONF
Replaces: $CONF
Description: Mesa $MV with Mali-G710 (Pixel 7 Pro) support, panfrost + llvmpipe, GBM/EGL/GLES2
 Built from Mesa $MV with Omarchy Mobile's patches 0001 (G710 model entry) and 0002 (panthor image BOs).
X
printf '# run-with sh\nldconfig\n' > "$D/DEBIAN/postinst"; cp "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"; chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
dpkg-deb -Zxz --build "$D" "$UWORK/mesa-cheetah_${MV}_arm64.deb" >/dev/null
ls -l "$UWORK/mesa-cheetah_${MV}_arm64.deb"
mount -t proc proc "$R/proc"; mount --bind /dev "$R/dev"
mv "$R/etc/resolv.conf" /tmp/resolv.conf.stub.$$ 2>/dev/null || rm -f "$R/etc/resolv.conf"; cp /etc/resolv.conf "$R/etc/resolv.conf"
trap 'rm -f $R/etc/resolv.conf; ln -s /run/systemd/resolve/stub-resolv.conf $R/etc/resolv.conf; umount $R/dev $R/proc 2>/dev/null; rm -rf $R/var/lib/apt/lists/* $R/var/cache/apt/archives/*.deb' EXIT
cp "$UWORK/mesa-cheetah_${MV}_arm64.deb" "$R/tmp/"
chroot "$R" sh -c '
  set -e
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libllvm18 libdrm2 libwayland-client0 libwayland-server0 libwayland-egl1 >/dev/null
  dpkg --force-depends -r libegl-mesa0 libgbm1 libgl1-mesa-dri libglx-mesa0 mesa-libgallium mesa-vulkan-drivers 2>&1 | tail -n 3 || true
  dpkg -i /tmp/mesa-cheetah_'"$MV"'_arm64.deb 2>&1 | tail -n 3
  DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge 2>&1 | tail -n 3
  rm -f /tmp/mesa-cheetah_*.deb
  ldconfig
'
echo "MESA INSTALLED"
