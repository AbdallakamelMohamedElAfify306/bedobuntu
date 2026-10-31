# Install outline

Detailed Arabic notes from the build live in `docs/ubuntu-build-notes.ar.md`
(paths sanitized). Offline validation summary: `docs/offline-validation.md`.

Minimum sequence:

1. Backup anything important. Unlock bootloader (erases the phone).
2. Prepare build inputs (kernel tree, omarchy-mobile checkout). Export `CHEETAH_BUILD`.
3. Build images with `ubuntu/` + `boot/build/` scripts (`bash script.sh`).
4. Put SHA256SUMS next to images. Run `bash boot/scripts/flash-linux.sh --dry-run`
   then the real flash after confirmations.
5. First boot with USB cable attached. Set host USB net to 172.16.42.2/24.
6. Optional shared partition: read `shared-partition/README.md` and verify GPT.
7. Install switch helpers from `switch/`.
8. Optional Android Magisk helpers from `android/` — download modules yourself.
