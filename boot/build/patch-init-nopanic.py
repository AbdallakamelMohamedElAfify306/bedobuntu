# SPDX-License-Identifier: GPL-3.0-or-later
# Ubuntu build only: disable Omarchy's USB dead-man switch. Upstream's init crashes the phone (sysrq 'c' -> panic=10 reboot)
# 65 s after boot when no USB host configures the gadget, which burns a slot-B retry per boot. Here it only prints the same
# diagnostics on the screen and lets the boot continue. grow_root and its /run/omamobile-resizing guard are untouched.
import sys
p = sys.argv[1]; s = open(p).read()
a = s.index('    echo "omamobile: no USB host, crashing in 20 s so ABL falls back to slot A"')
e = s.index('echo c > /proc/sysrq-trigger', a)
e = s.index('\n', e) + 1
b = '''    echo "omamobile: no USB host seen; boot continues (the dead-man crash is disabled in this build)"
  } > $SCREEN
'''
assert s.count('echo c > /proc/sysrq-trigger') == 1, "init layout changed"
s = s[:a] + b + s[e:]
open(p, 'w').write(s)
