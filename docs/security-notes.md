# Security notes

- Default image account `user` uses a placeholder password (`user` unless
  `CHEETAH_USER_PASSWORD` is set at build). First login must change it.
- Do not ship a debug SSH private key. Pass `CHEETAH_SSH_PUBKEY` at build time.
- Root-hide scripts cannot forge hardware attestation on an unlocked bootloader.
- Never commit keyboxes, Magisk module zips from third parties, or device dumps.
