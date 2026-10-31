# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash test-repair-upgrade.sh
# Offline mock test: 21-repair-system.sh (journald, fstrim, zram body syntax) and 31-sec-upgrade.sh (protected-package refusal).
KIT=$(cd "$(dirname "$0")/.." && pwd)
exec unshare -rmn bash -c '
KIT='"$KIT"'
T=$(mktemp -d); mkdir -p $T/bin $T/h; cp -a /etc/. $T/etc 2>/dev/null; mount --bind $T/etc /etc; mount -t tmpfs tmpfs /usr/local; mkdir -p /usr/local/sbin
for c in systemctl journalctl timedatectl sysctl modprobe; do printf "# run-with bash\nexit 0\n" > $T/bin/$c; chmod +x $T/bin/$c; done
printf "# run-with bash\nif [ \"\$1\" = is-enabled ]; then exit 0; fi\nexit 0\n" > $T/bin/systemctl
# fake apt-get: simulation output controlled by $SIM_FILE; apt-mark records holds; dpkg-query lists fake installed packages
cat > $T/bin/apt-get <<S
# run-with bash
for a in "\$@"; do [ "\$a" = "-s" ] && { cat \$SIM_FILE; exit 0; }; done
exit 0
S
printf "# run-with bash\nif [ \"\$1\" = hold ]; then echo \"\$2\" >> $T/holds; fi\nif [ \"\$1\" = showhold ]; then cat $T/holds 2>/dev/null; fi\nexit 0\n" > $T/bin/apt-mark
printf "# run-with bash\nprintf \"ii  phosh\\\\nii  mesa-cheetah\\\\nii  curl\\\\n\"\n" > $T/bin/dpkg-query
printf "# run-with bash\nexit 0\n" > $T/bin/dpkg; printf "# run-with bash\nexit 0\n" > $T/bin/ip
chmod +x $T/bin/*
export PATH=$T/bin:$PATH HEALTH_TEST=1 HEALTH_DIR=$T/h
echo "### 21 journald+fstrim dry"; bash $KIT/21-repair-system.sh journald fstrim | grep -E "^\[|RESULT"
echo "### 21 journald+fstrim apply"; bash $KIT/21-repair-system.sh --apply journald fstrim | grep -E "^\[|RESULT"; cat /etc/systemd/journald.conf.d/10-cheetah.conf; cat /etc/systemd/system/fstrim.service.d/*.conf
echo "### 21 idempotent"; bash $KIT/21-repair-system.sh --apply journald fstrim | grep -E "already|RESULT"
echo "### zram body syntax"; sed -n "/^    ZB=/,/^esac.$/p" $KIT/21-repair-system.sh | sed "1s/^    ZB=.//; \$s/.\$//" > $T/zram.sh; sh -n $T/zram.sh && echo ZRAM_SH_SYNTAX_OK; head -3 $T/zram.sh
# 31: plan touching phosh must be refused
printf "Inst curl [1] (2 Ubuntu:24.04/noble-security [arm64])\nInst phosh [0.38.0-1] (0.38.0-1ubuntu1 Ubuntu:24.04/noble-updates [arm64])\n" > $T/sim-bad
printf "Inst curl [1] (2 Ubuntu:24.04/noble-security [arm64])\nInst openssh-server [1] (2 Ubuntu:24.04/noble-security [arm64])\n" > $T/sim-good
printf "Inst curl [1] (2 Ubuntu:24.04/noble-security [arm64])\nRemv libfoo [1]\n" > $T/sim-rem
for s in bad good rem; do echo "### 31 plan=$s"; SIM_FILE=$T/sim-$s bash $KIT/31-sec-upgrade.sh --no-update | grep -E "^\[(OK|FAIL|DRY)\]|RESULT" | cut -c1-170; done
echo "### holds recorded"; cat $T/holds 2>/dev/null
'
