# From the Mac (works when the phone is on Android, or anywhere)
# Android (unrooted) -> bootloader: needs USB debugging authorised
adb reboot bootloader
# or, no adb: power off, hold Volume Down + Power ~20 s until "Fastboot Mode"
fastboot getvar current-slot
fastboot --set-active=b     # Ubuntu (only valid while Android has not booted since Ubuntu was installed)
fastboot --set-active=a     # Android
fastboot reboot
# From Ubuntu to fastboot without buttons (per Omarchy NOTES; reboot-to is in the rootfs):
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'reboot-to bootloader'
# Existing scripts in $HOME/cheetah-dual/out-ubuntu/scripts: to-linux.sh, to-android.sh, check-slot-b.sh (read-only)
