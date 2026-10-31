# cheetah-health kit (Ubuntu 24.04 Phosh on Pixel 7 Pro)

Scripts are run ON THE PHONE (as root, over the USB SSH link). Every script: bash, idempotent, logs to /root/health/*.log,
backs up before editing (/root/health/backup), prints [OK]/[WARN]/[FAIL] markers, has a check mode (default) and --apply.

| file | phase | mode |
|---|---|---|
| lib.sh | helpers | sourced |
| 00-step0-undo-wallpaper.sh | step 0 | --check / --apply |
| 10-check.sh | 1 full health check | read-only |
| 11-lockscreen-check.sh | 1b lock screen inspection | read-only |
| 12-lockscreen-fix.sh | 1c lock screen fixes | dry-run / --apply FIX... |
| 20-fix-network.sh | 2a apt over Wi-Fi | --check / --apply |
| 21-repair-system.sh | 2b dpkg/units/zram/journald/fstrim/time | --check / --apply [section] |
| 30-sec-audit.sh | 3a security audit | read-only |
| 31-sec-upgrade.sh | 3b guarded full-upgrade | --check / --apply |
| 32-sec-harden.sh | 3c unattended/ssh/firewall/sysctl/keys | dry-run / --apply SECTION |
| 40-hw-check.sh | 4 hardware verdicts | read-only |
| 50-final-verify.sh | 5 final table | read-only |
| COMMANDS.txt | every Mac command, one line each | |
| tests/ | offline mock tests + command linter | run on a PC, not the phone |

Hard rules baked in: no script runs mkfs/dd/sgdisk/parted/wipefs/fastboot or writes to any /dev/sd* node; the only
device node ever written is /dev/zramN (swap). fstrim is limited to `/`. Android partitions, sda31, boot/init_boot_a,
the GPT, the bootloader and sda33 formatting are never touched. Files are moved to backup, never deleted.
