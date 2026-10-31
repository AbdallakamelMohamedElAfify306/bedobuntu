# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash 40-images.sh
# Pack the five slot-B boot images for cheetah, mirroring `bin/omamobile images` (android-v4 layout with
# vendor_kernel_boot): boot (Image.lz4 only), init_boot (empty cpio), vendor_boot (cmdline only),
# vendor_kernel_boot (DTB + our initramfs), dtbo (one empty board overlay). Nothing here touches a phone.
set -euo pipefail
source "$(dirname "$0")/env.sh"
MKBOOT=$UC/src/mkbootimg/mkbootimg.py
MKDTBO=$UC/src/libufdt/utils/src/mkdtboimg.py
DTC=$KOUT/scripts/dtc/dtc; FDTO=$KOUT/scripts/dtc/fdtoverlay
BOOT=$KOUT/arch/arm64/boot
IMG=$OUT/images
conf() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$OMA/device/cheetah/device.conf" | head -1; }
DTB=$BOOT/dts/$(conf DTB); SOC_IDS=$(conf SOC_IDS); OVERLAYS=$(conf DTB_OVERLAYS)
CMDLINE=$(conf VENDOR_CMDLINE); PAGESIZE=$(conf VENDOR_PAGESIZE); OSV=$(conf OS_VERSION); OSP=$(conf OS_PATCH_LEVEL)
BID=$(conf DTBO_BOARD_ID); BREV=$(conf DTBO_BOARD_REV); DTBO_SRC=$OMA/device/cheetah/$(conf DTBO_SOURCE)
[ -f "$BOOT/Image" ] && [ -f "$DTB" ] || { echo "build the kernel first"; exit 1; }
[ -f "$UWORK/initramfs.cpio.lz4" ] || { echo "build the initramfs first"; exit 1; }
rm -rf "$IMG"; mkdir -p "$IMG/overlays"
# Overlays, applied in order. A failing overlay (target not in this kernel's DTS) is reported and dropped,
# never silently: the list that was applied is written to images/OVERLAYS.txt.
dtb=$DTB; applied=""; dropped=""
for ov in $OVERLAYS; do
  "$DTC" -q -@ -I dts -O dtb -o "$IMG/overlays/$ov.dtbo" "$OMA/device/cheetah/overlays/$ov.dtso" || { dropped="$dropped $ov(compile)"; continue; }
  if "$FDTO" -i "$dtb" -o "$IMG/step.dtb" "$IMG/overlays/$ov.dtbo" 2>"$IMG/step.err"; then mv "$IMG/step.dtb" "$IMG/cumulative.dtb"; dtb=$IMG/cumulative.dtb; applied="$applied $ov"
  else dropped="$dropped $ov"; fi
done
printf 'applied:%s\ndropped:%s\n' "$applied" "$dropped" | tee "$IMG/OVERLAYS.txt"
# Debugging aid (the only change to Omarchy's DTB bootargs): drop "quiet splash plymouth.force-scale=1" so the
# initramfs status lines and the kernel log show on the screen (Omarchy hides them behind its Plymouth splash,
# which this image does not have).
"$DTC" -q -I dtb -O dts "$dtb" | sed 's/ quiet splash plymouth.force-scale=1//' | "$DTC" -q -I dts -O dtb -o "$IMG/final.dtb" -
"$DTC" -q -I dtb -O dts "$IMG/final.dtb" | grep -q 'bootargs = "console=tty0 fbcon=font:TER16x32 vt.global_cursor_default=0 panic=10' || { echo "bootargs rewrite failed"; exit 1; }
dtb=$IMG/final.dtb
lz4 -l -9 -f -q "$BOOT/Image" "$IMG/Image.lz4"
# one DTB per soc_id (ABL picks by /soc_id), concatenated
dtbs=(); base=""
for entry in $SOC_IDS; do
  label=${entry%%:*}; id=${entry#*:}; out=$IMG/cheetah-$label.dtb
  if [ -z "$base" ]; then
    base=$id; "$DTC" -q -I dtb -O dts "$dtb" | grep -c "soc_id = <$base " >/dev/null || { echo "DTB lacks soc_id $base"; exit 1; }
    cp "$dtb" "$out"
  else
    "$DTC" -q -I dtb -O dts "$dtb" | sed "s/soc_id = <$base /soc_id = <$id /" | "$DTC" -q -I dts -O dtb -o "$out" -
    "$DTC" -q -I dtb -O dts "$out" | grep -c "soc_id = <$id " >/dev/null || { echo "soc_id rewrite failed"; exit 1; }
  fi
  dtbs+=("$out")
done
# Third DTB, as in Google's own vendor_kernel_boot for cheetah (CP3A): same tree with /soc_compatible/B0_IPOP instead of
# /soc_id, for phones whose SoC is the IPOP package (ABL matches those on /soc_compatible, not /soc_id).
"$DTC" -q -I dtb -O dts "$dtb" | python3 -c '
import sys; s = sys.stdin.read(); a = "\tsoc_id = <0x9855001 0x00>;\n"; assert s.count(a) == 1
sys.stdout.write(s.replace(a, "\tsoc_compatible {\n\n\t\tB0_IPOP {\n\t\t\tdescription = \"B0,IPOP\";\n\t\t\tproduct_id = <0x9855>;\n\t\t\tmajor = <0x01>;\n\t\t\tminor = <0x00>;\n\t\t\tpkg_mode = <0x01>;\n\t\t};\n\t};\n"))' \
  | "$DTC" -q -I dts -O dtb -o "$IMG/cheetah-ipop.dtb" -
dtbs+=("$IMG/cheetah-ipop.dtb")
cat "${dtbs[@]}" > "$IMG/dtb.img"
# dtbo: one empty overlay keyed to cheetah's board id/rev
grep -c "board_id = <$BID>;" "$DTBO_SRC" >/dev/null; grep -c "board_rev = <$BREV>;" "$DTBO_SRC" >/dev/null
"$DTC" -q -@ -I dts -O dtb -o "$IMG/cheetah-m1-overlay.dtbo" "$DTBO_SRC"
python3 "$MKDTBO" create "$IMG/dtbo.img" --page_size=4096 --id="$BID" --rev="$BREV" "$IMG/cheetah-m1-overlay.dtbo"
: | cpio -o -H newc --quiet > "$IMG/empty.cpio"
python3 "$MKBOOT" --header_version 4 --kernel "$IMG/Image.lz4" --cmdline '' --output "$IMG/boot.img"
python3 "$MKBOOT" --header_version 4 --ramdisk "$IMG/empty.cpio" --os_version "$OSV" --os_patch_level "$OSP" --output "$IMG/init_boot.img"
python3 "$MKBOOT" --header_version 4 --pagesize "$PAGESIZE" --vendor_cmdline "$CMDLINE" --ramdisk_type 1 --ramdisk_name '' \
  --vendor_ramdisk_fragment "$IMG/empty.cpio" --vendor_boot "$IMG/vendor_boot.img"
python3 "$MKBOOT" --header_version 4 --pagesize "$PAGESIZE" --vendor_cmdline '' --dtb "$IMG/dtb.img" --ramdisk_type 1 --ramdisk_name '' \
  --vendor_ramdisk_fragment "$UWORK/initramfs.cpio.lz4" --vendor_boot "$IMG/vendor_kernel_boot.img"
echo cheetah > "$IMG/DEVICE"; cat "$KOUT/include/config/kernel.release" > "$IMG/KERNEL_RELEASE"
# AVB hash footers on boot and init_boot, like Omarchy's AVB_FOOTERS (stock vbmeta chains these two partitions and newer
# bootloaders can refuse an unfootered one): AOSP test key, stock CP3A.261005.002.A1 rollback index and security patch,
# padded to the partition size (boot 64 MiB, init_boot 8 MiB).
AVBTOOL=${AVBTOOL:-$CHEETAH_AVB/avbtool.py}; AVB_KEY=${AVB_KEY:-$CHEETAH_AVB/test/data/testkey_rsa4096.pem}
for e in boot:67108864 init_boot:8388608; do
  n=${e%%:*}; salt=$(sha256sum "$IMG/$n.img" | cut -d' ' -f1)
  python3 -I "$AVBTOOL" add_hash_footer --image "$IMG/$n.img" --partition_name "$n" --partition_size "${e#*:}" \
    --algorithm SHA256_RSA4096 --key "$AVB_KEY" --salt "$salt" --rollback_index 1791158400 \
    --prop "com.android.build.$n.os_version:17" --prop "com.android.build.$n.security_patch:2026-10-05"
done
# partition size limits (BRINGUP-M1.md 1.1): boot 64 MiB, init_boot 8 MiB, vendor_boot 64 MiB, vendor_kernel_boot 64 MiB, dtbo 16 MiB
chk() { local s; s=$(stat -c %s "$IMG/$1.img"); [ "$s" -le $(( $2 * 1048576 )) ] || { echo "$1.img too big ($s)"; exit 1; }; }
chk boot 64; chk init_boot 8; chk vendor_boot 64; chk vendor_kernel_boot 64; chk dtbo 16
ls -l "$IMG"/*.img
