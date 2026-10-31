# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash flash-linux.sh
# Install Ubuntu 24.04 + Phosh on slot B of a Pixel 7 Pro, mirroring Omarchy Mobile's tools/install-phone:
#   fastboot flash boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b   (slot B boot images)
#   fastboot flash userdata                                                       (ERASES ANDROID'S DATA)
#   fastboot --set-active=b ; fastboot reboot
# It never writes slot A, the bootloader, radio/modem, persist, efs, vbmeta, devinfo or any other partition,
# and it never runs `fastboot erase`, `fastboot -w`, `flashing lock` or anything that touches the GPT.
# EXPERIMENTAL, UNTESTED ON REAL HARDWARE.
set -euo pipefail
. "$(dirname "$0")/common.sh"
DRY=0; SLOTS_MATCH=""
while [ $# -gt 0 ]; do case $1 in
  --dry-run) DRY=1;;
  --bootloader-slots-match) SLOTS_MATCH=${2:?}; shift;;
  -h|--help) sed -n '2,9p' "$0"; echo "options: --dry-run  --bootloader-slots-match <version-bootloader>"; exit 0;;
  *) die "unknown argument $1";; esac; shift; done

say "Checking the files"
sha_check "$OUTDIR" || die "a file does not match SHA256SUMS: re-download / re-copy the out/ folder"
for p in $BOOT_IMAGES; do [ -f "$IMAGES/$p.img" ] || die "missing $IMAGES/$p.img"; done
USERDATA=$OUTDIR/userdata.simg; [ -f "$USERDATA" ] || die "missing $USERDATA"
note "checksums OK"

say "Checking the phone"
pick_phone; check_phone
cur=$(var current-slot); curbl=$(var version-bootloader)
bla=$(printf '%s\n' "$VARS" | sed -nE 's/^version-bootloader[-_:]a:[ ]*//p' | head -1)
blb=$(printf '%s\n' "$VARS" | sed -nE 's/^version-bootloader[-_:]b:[ ]*//p' | head -1)
if [ -n "$bla" ] && [ -n "$blb" ]; then
  [ "$bla" = "$blb" ] || die "the bootloader differs between slots (a: $bla, b: $blb). Flash Google's FULL factory image first (Android Flash Tool, 'force flash all partitions') so both slots match, then re-run."
  note "bootloader $bla on both slots"
elif [ -n "$SLOTS_MATCH" ]; then
  [ "$SLOTS_MATCH" = "$curbl" ] || die "--bootloader-slots-match $SLOTS_MATCH but the phone reports $curbl"
  note "bootloader $curbl (other slot confirmed by you)"
else
  die "the phone only reports slot ${cur:-?}'s bootloader ($curbl). Setting slot B active runs slot B's bootloader, so both must match. Easiest: flash Google's full factory image once (both slots then match) and re-run with --bootloader-slots-match $curbl"
fi
for p in $BOOT_IMAGES; do
  ps=$(printf '%s\n' "$VARS" | sed -nE "s/^partition-size:${p}_b:[ ]*(0x[0-9a-fA-F]+)\$/\1/p" | head -1)
  [ -n "$ps" ] || die "the phone reports no partition-size for ${p}_b"
  is=$(wc -c < "$IMAGES/$p.img" | tr -d ' ')
  [ "$is" -le $((ps)) ] || die "$p.img ($is bytes) is larger than ${p}_b ($((ps)) bytes)"
done
note "product cheetah, unlocked, current slot $cur, image sizes fit"

say "The plan"
echo "These commands, and only these, will run:"
for p in $BOOT_IMAGES; do echo "    fastboot flash ${p}_b $IMAGES/$p.img"; done
echo "    fastboot flash userdata $USERDATA"
echo "    fastboot --set-active=b"
echo "    fastboot reboot"
cat <<'MSG'

*** THIS ERASES EVERYTHING IN ANDROID'S USER DATA (photos, apps, accounts). Android's slot A system stays
*** installed, but it will need a factory reset / re-setup if you boot it again. You cannot have Android's data
*** and this Linux side by side on one phone (see README_AR.md, section "ليه مفيش dual boot").
*** Linux will use at most 50 GB of the phone's storage (its root file system is capped at 50 GB at first boot);
*** the rest of userdata stays unused until you go back to Android (which reformats it).
*** Android OTA updates would overwrite slot B: turn off automatic system updates (scripts/android-protect-from-ota.sh).
MSG
[ "$DRY" = 1 ] && { say "Dry run: nothing was written."; exit 0; }
printf 'Type the phone codename (cheetah) to continue: '; read -r a; [ "$a" = cheetah ] || die "not confirmed; nothing was written"
printf 'Type ERASE ANDROID DATA to confirm that you backed up and accept the wipe: '; read -r a; [ "$a" = "ERASE ANDROID DATA" ] || die "not confirmed; nothing was written"

say "Flashing slot B boot images"
for p in $BOOT_IMAGES; do safe_flash "${p}_b" "$IMAGES/$p.img"; done
say "Flashing userdata (several chunks; takes a few minutes)"
safe_flash userdata "$USERDATA"
say "Activating slot B and rebooting"
fb --set-active=b; fb reboot
set_state linux-installed
say "Done. First boot can take a few minutes. Watch the README_AR.md section on first boot."
