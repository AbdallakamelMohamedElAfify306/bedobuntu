# SPDX-License-Identifier: GPL-3.0-or-later
# Zip boot scripts (no userdata.simg, no private keys) into a release zip.
# Run with: python3 80-zip.py
import zipfile, os
src = os.environ.get("CHEETAH_OUT", "out-ubuntu")
dst = os.environ.get("CHEETAH_ZIP", "cheetah-boot-scripts.zip")
os.chdir(src)
skip = {"userdata.simg", "debug_ssh/id_ed25519", "debug_ssh/id_ed25519.pub"}
with zipfile.ZipFile(dst + ".part", "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, _, fs in os.walk("."):
        for f in sorted(fs):
            p = os.path.join(root, f)[2:]
            if p in skip or p.endswith(".img") or p.endswith(".simg"):
                continue
            zi = zipfile.ZipInfo.from_file(p, "out-ubuntu/" + p)
            zi.compress_type = zipfile.ZIP_DEFLATED
            with open(p, "rb") as fh:
                z.writestr(zi, fh.read(), compresslevel=9)
os.replace(dst + ".part", dst)
print("ZIP_DONE", dst)
