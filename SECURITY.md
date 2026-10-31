# Security policy

## Warning

These scripts can brick a Pixel 7 Pro, erase userdata, or corrupt the GPT if
run on the wrong device or layout. An unlocked bootloader is required. Use at
your own risk. Keep verified backups of GPT tables and of any data you care about
before running partition or flash helpers.

## Do not publish

- Private SSH keys, keystores, or signing keys
- Device serials, IMEI, MAC addresses, Wi-Fi PSKs, account tokens
- Boot/recovery images, factory zips, proprietary Google firmware
- GPT dumps or full partition backups from a real phone

## Reporting issues

Open a GitHub issue describing the problem. Do not attach logs that contain
serials, tokens, or personal paths. Redact with placeholders first.

## Root-hide helpers

Scripts under android/ are best-effort Magisk helper scripts. They cannot forge
hardware attestation while the bootloader is unlocked. Do not ask for, and do
not commit, stolen attestation keyboxes.
