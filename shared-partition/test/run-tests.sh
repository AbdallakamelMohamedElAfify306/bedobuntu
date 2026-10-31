# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash run-tests.sh
# Re-runnable test of the GPT part on a synthetic Pixel-like disk (4096-B sectors, 32 entries, real sgdisk 1.0.10 verifying).
# Needs: sudo, losetup, python3, sgdisk (SGD_DIR with usr/sbin/sgdisk + libs), run from $CHEETAH_SHARED/test
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd); IMG=/tmp/sp-test.img; SGDIR=${SGDIR:-/tmp/gdx}
python3 "$HERE/test/mk32.py" $IMG 32 >/dev/null
LOOP=$(sudo losetup -b 4096 -f --show $IMG); trap 'sudo losetup -d $LOOP' EXIT
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu; ST=/tmp/sp-state-run; sudo rm -rf $ST
E="SP_DISK=$LOOP SP_SS=4096 SP_NOSYS=1 SP_STATE=$ST PATH=$SGDIR/usr/sbin:/usr/sbin:/sbin:$PATH LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
C="sudo env $E bash $HERE/shared-part-create.sh"; R="sudo env $E bash $HERE/shared-part-rollback.sh"; SG="sudo env LD_LIBRARY_PATH=$LD_LIBRARY_PATH $SGDIR/usr/sbin/sgdisk"
t() { echo; echo "### $*"; }
t "check (read-only)";                $C check | sed -n '1,6p;/proposed/p;/rehearsal OK/p'
t "create before grow must STOP";     $C create --yes 2>&1 | tail -1
t "grow without backup must STOP";    $C grow --yes 2>&1 | tail -1
t "backup pre-grow";                  $C backup pre-grow | tail -1
t "grow 32->33";                      $C grow --yes | tail -2
t "grow twice must STOP";             $C grow --yes 2>&1 | tail -1
t "create with stale backup must STOP"; $C create --yes 2>&1 | tail -1
t "backup pre-create";                $C backup pre-create | tail -1
t "create";                           $C create --yes | tail -3
t "sgdisk -p / -i 33 / -v";           $SG -p $LOOP | grep -E "holds|^ +3[0-3] "; $SG -i 33 $LOOP | grep -E "First|Last|name"; $SG -v $LOOP | head -1
t "create twice must STOP";           $C create --yes 2>&1 | tail -1
t "tamper GPT, rollback must STOP";   printf '\x01' | sudo dd of=$LOOP bs=1 seek=10 count=1 conv=notrunc 2>/dev/null; $R gpt --yes 2>&1 | tail -1; printf '\x00' | sudo dd of=$LOOP bs=1 seek=10 count=1 conv=notrunc 2>/dev/null
t "rollback to original 32-entry table"; $R gpt --yes 2>&1 | tail -3
t "after rollback: sgdisk";           $SG -p $LOOP | grep -E "holds|^ +3[0-3] "
python3 "$HERE/test/mk32.py" /tmp/sp-ref.img 32 >/dev/null; head -c 24576 /tmp/sp-ref.img > /tmp/r1; sudo head -c 24576 $LOOP > /tmp/r2; tail -c 20480 /tmp/sp-ref.img > /tmp/r3; sudo tail -c 20480 $LOOP > /tmp/r4
t "byte-compare front 6 sectors + tail 5 sectors with the pristine table"; cmp /tmp/r1 /tmp/r2 && cmp /tmp/r3 /tmp/r4 && echo IDENTICAL
# --- Android diag (v2, 32-bit-arithmetic safe): fake /sys in 512-byte units + real mksh R59 (32-bit $(( ))) if built
t "Android diag on the synthetic layout (userdata start512=117633024, ubuntu start512=19066672 as on the phone)"
python3 "$HERE/test/mk32.py" $IMG 32 >/dev/null; rm -rf /tmp/fakesys; python3 "$HERE/test/mk-fake-android.py" $IMG /tmp/fakesys
for SH in dash "${MKSH:-/tmp/mk/mksh-cvs2git-mksh-R59c/mksh}"; do [ -x "$(command -v $SH)" ] || continue
  echo "-- $SH"; SP_DISK=$IMG SP_SYS=/tmp/fakesys $SH "$HERE/shared-part-android.sh" diag | sed -n '/SUMMARY/,$p'; done
