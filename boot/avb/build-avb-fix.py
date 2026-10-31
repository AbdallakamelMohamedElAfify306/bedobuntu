# SPDX-License-Identifier: GPL-3.0-or-later
# run-with python3
"""Rebuild the slot-B images with: AVB footers on boot/init_boot, a third (B0_IPOP /soc_compatible) DTB, no USB dead-man crash."""
import os, re, struct, subprocess, sys, shutil, hashlib, lz4.block
UC = os.environ.get('CHEETAH_BUILD') or os.path.abspath('../..')
OUT = os.path.join(UC, 'out-ubuntu'); BK = os.path.join(UC, 'backup-pre-avb')
INT = os.path.join(BK, 'images-intermediate')
W = os.environ.get('CHEETAH_AVBFIX') or os.path.abspath('.')
AVB = os.path.join(os.environ.get('CHEETAH_AVB') or '.', 'avbtool.py')
KEY = os.environ.get('CHEETAH_AVB_KEY') or 'testkey_rsa4096.pem'  # Google AVB *test* key only
MKB = os.path.join(UC, 'src/mkbootimg/mkbootimg.py')
env = dict(os.environ)
DTC = os.environ.get('DTC', 'dtc')
def run(*a, **k): subprocess.run(a, check=True, env=env, **k)

# ---- 1. initramfs: patch /init inside the existing newc cpio (everything else byte-identical)
def lz4_legacy_decode(d):
    assert struct.unpack('<I', d[:4])[0]==0x184c2102
    o=4; out=[]
    while o<len(d):
        c=struct.unpack('<I', d[o:o+4])[0]; o+=4
        out.append(lz4.block.decompress(d[o:o+c], uncompressed_size=8<<20)); o+=c
    return b''.join(out)
def lz4_legacy_encode(b):
    out=[struct.pack('<I',0x184c2102)]
    for i in range(0,len(b),8<<20):
        c=lz4.block.compress(b[i:i+(8<<20)], mode='high_compression', compression=9, store_size=False)
        out.append(struct.pack('<I',len(c))+c)
    return b''.join(out)
def cpio_parse(b):
    o=0; ents=[]
    while True:
        h=b[o:o+110]; assert h[:6]==b'070701'
        f=[int(h[6+8*i:14+8*i],16) for i in range(13)]
        ino,mode,uid,gid,nlink,mtime,fsz,dmaj,dmin,rmaj,rmin,nsz,chk=f
        name=b[o+110:o+110+nsz-1]; o2=(o+110+nsz+3)&~3
        data=b[o2:o2+fsz]; o=(o2+fsz+3)&~3
        if name==b'TRAILER' + bytes([33,33,33]): return ents, b[o:]
        ents.append([f,name,data])
def cpio_write(ents, tail):
    out=bytearray()
    def ent(f,name,data):
        f=list(f); f[6]=len(data); f[11]=len(name)+1
        out.extend(b'070701'+b''.join(b'%08X'%x for x in f)+name+b'\0')
        while len(out)%4: out.append(0)
        out.extend(data)
        while len(out)%4: out.append(0)
    for f,n,d in ents: ent(f,n,d)
    ent([0,0,0,0,1,0,0,0,0,0,0,0,0],b'TRAILER' + bytes([33,33,33]),b'')
    return bytes(out)+tail
raw=lz4_legacy_decode(open(f'{BK}/initramfs.cpio.lz4','rb').read())
ents,tail=cpio_parse(raw)
# parse/write must be lossless before we touch anything
assert cpio_write(ents,tail)==raw, 'cpio roundtrip differs'
subprocess.run(['python3',f'{UC}/build-ubuntu/patch-init-nopanic.py','/dev/null'],check=False,capture_output=True)
init=[e for e in ents if e[1]==b'init']; assert len(init)==1
tmp=f'{W}/init'; open(tmp,'wb').write(init[0][2]); run('python3',f'{UC}/build-ubuntu/patch-init-nopanic.py',tmp); run('sh','-n',tmp)
init[0][2]=open(tmp,'rb').read()
new=cpio_write(ents,tail)
cpio_lz4=lz4_legacy_encode(new)
assert lz4_legacy_decode(cpio_lz4)==new
open(f'{W}/initramfs.cpio.lz4','wb').write(cpio_lz4)
print('initramfs.cpio.lz4', len(cpio_lz4))

# ---- 2. dtb.img: ours (b0, a0) + third DTB with /soc_compatible/B0_IPOP in place of /soc_id, like stock
dts=subprocess.run([DTC,'-q','-I','dtb','-O','dts',f'{INT}/final.dtb'],check=True,env=env,capture_output=True,text=True).stdout
assert dts.count('\tsoc_id = <0x9855001 0x00>;')==1, dts.count('soc_id')
ip=dts.replace('\tsoc_id = <0x9855001 0x00>;\n','\tsoc_compatible {\n\n\t\tB0_IPOP {\n\t\t\tdescription = "B0,IPOP";\n\t\t\tproduct_id = <0x9855>;\n\t\t\tmajor = <0x01>;\n\t\t\tminor = <0x00>;\n\t\t\tpkg_mode = <0x01>;\n\t\t};\n\t};\n')
assert 'B0_IPOP' in ip and 'soc_id' not in ip.split('soc_compatible')[0].split('\n/ {')[-1]
open(f'{W}/ipop.dts','w').write(ip)
run(DTC,'-q','-I','dts','-O','dtb','-o',f'{W}/cheetah-ipop.dtb',f'{W}/ipop.dts')
dtb=open(f'{INT}/cheetah-b0.dtb','rb').read()+open(f'{INT}/cheetah-a0.dtb','rb').read()+open(f'{W}/cheetah-ipop.dtb','rb').read()
assert dtb[:178104]==open(f'{INT}/dtb.img','rb').read()
open(f'{W}/dtb.img','wb').write(dtb); print('dtb.img',len(dtb))

# ---- 3. images
def conf(k):
    for l in open(f'{UC}/src/omarchy-mobile/device/cheetah/device.conf'):
        m=re.match(rf'{k}="?([^"\n]*)"?$',l)
        if m: return m.group(1)
PAGE=conf('VENDOR_PAGESIZE') if os.path.isdir(f'{UC}/src/omarchy-mobile/device') else '0x800'
def mk(*a): run('python3',MKB,'--header_version','4',*a)
# reproducibility check: old vendor_kernel_boot rebuilt from old pieces must equal the shipped one
mk('--pagesize',PAGE,'--vendor_cmdline','','--dtb',f'{INT}/dtb.img','--ramdisk_type','1','--ramdisk_name','','--vendor_ramdisk_fragment',f'{BK}/initramfs.cpio.lz4','--vendor_boot',f'{W}/vkb-old.img')
assert open(f'{W}/vkb-old.img','rb').read()==open(f'{BK}/images/vendor_kernel_boot.img','rb').read(), 'cannot reproduce old vendor_kernel_boot'
print('old vendor_kernel_boot reproduced bit-exactly')
mk('--pagesize',PAGE,'--vendor_cmdline','','--dtb',f'{W}/dtb.img','--ramdisk_type','1','--ramdisk_name','','--vendor_ramdisk_fragment',f'{W}/initramfs.cpio.lz4','--vendor_boot',f'{W}/vendor_kernel_boot.img')
for name,size in (('boot',64<<20),('init_boot',8<<20)):
    shutil.copy(f'{BK}/images/{name}.img',f'{W}/{name}.img')
    salt=hashlib.sha256(open(f'{W}/{name}.img','rb').read()).hexdigest()
    run('python3','-I',AVB,'add_hash_footer','--image',f'{W}/{name}.img','--partition_name',name,'--partition_size',str(size),
        '--algorithm','SHA256_RSA4096','--key',KEY,'--salt',salt,'--rollback_index','1791158400',
        '--prop',f'com.android.build.{name}.os_version:17','--prop',f'com.android.build.{name}.security_patch:2026-10-05')
for n in ('boot','init_boot','vendor_kernel_boot'):
    shutil.copy(f'{W}/{n}.img',f'{OUT}/images/{n}.img')
shutil.copy(f'{W}/initramfs.cpio.lz4',f'{UC}/build-ubuntu/work/initramfs.cpio.lz4')
shutil.copy(f'{W}/init',f'{UC}/build-ubuntu/work/initramfs/init')
shutil.copy(f'{W}/dtb.img',f'{UC}/build-ubuntu/work/images-intermediate/dtb.img')
shutil.copy(f'{W}/cheetah-ipop.dtb',f'{UC}/build-ubuntu/work/images-intermediate/cheetah-ipop.dtb')
print('done')
