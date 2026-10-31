# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash build.sh
set -eu
cd "$(dirname "$0")"
python3 -m py_compile omamobile-reboot-android omamobile-reboot-android-gui
python3 - <<'PY'
import base64, gzip
files = [("helper","omamobile-reboot-android"),("gui","omamobile-reboot-android-gui"),("svg","omamobile-reboot-android.svg"),
         ("desktop","omamobile-reboot-android.desktop"),("sudoers","omamobile-reboot-android.sudoers")]
out = []
for var, fn in files:
    b = base64.b64encode(open(fn,"rb").read()).decode()
    out.append("echo %s | base64 -d > \"$T/%s\"" % (b, var))
s = open("install.sh.in").read().replace("@@FILES@@", "\n".join(out))
open("install.sh","w").write(s)
z = base64.b64encode(gzip.compress(s.encode(), 9, mtime=0)).decode()
open("cmd-install.txt","w").write("ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'echo %s | base64 -d | gunzip | bash'\n" % z)
PY
bash -n install.sh && echo built; wc -c cmd-install.txt; grep -cF "$(printf '\41')" cmd-install.txt || true
