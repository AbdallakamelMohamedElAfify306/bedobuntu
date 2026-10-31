# مساحة مشتركة (Shared) بين Android و Ubuntu — الخطوات

الفكرة: نعمل partition جديد اسمه `shared` من الـ 20 جيجا الفاضيين (ext4)، يتفتح أوتوماتيك في الاتنين:
Android: فولدر `Shared` في التخزين الداخلي (`/sdcard/Shared`) — Ubuntu: `/mnt/shared` ورابط `~/Shared` وبوكمارك في Files.
مفيش أي حاجة بتلمس `sda31` (بيانات Android) ولا `sda32` (Ubuntu). بنكتب بس جدول الـ GPT (مع نسخة احتياطية قبل كل خطوة).

> كل الأوامر على الماك، سطر واحد. لو ظهر `Operation timed out` بعد أي ريستارت: `sudo ifconfig en6 inet 172.16.42.2 netmask 255.255.255.0 up` وبعدين `ping -c 2 172.16.42.1`.
> لو أي خطوة كتبت `STOP:` — اقف وابعتلي السطر ده (مفيش حاجة اتكتبت وقتها).

## 0) فحص بس (قراءة فقط) — التليفون على Ubuntu
شغّل السطر اللي في `diag.txt` (رقم 1). لازم آخر سطر يقول `VERDICT: READY`. ابعتلي الصورة.

## 1) نزّل الملفات وانسخها للتليفون (الملفات اتبعتتلك، هتلاقيها في Downloads)
```
scp -i "$CHEETAH_SSH_KEY" ~/Downloads/shared-part-create.sh ~/Downloads/shared-part-ubuntu.sh ~/Downloads/shared-part-rollback.sh root@172.16.42.1:/root/
```

## 2) فحص كامل بدون كتابة
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-create.sh check'
```
لازم تشوف `rehearsal OK` و `proposed 'shared': start 25957120 end 31195903 = 20464 MiB` (حوالي 20 جيجا) وبعده `(nothing was written)`.

## 3) نسخة احتياطية من الـ GPT + نسخها للماك
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-create.sh backup pre-grow'
```
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'tar -C /root -cf - shared-part-state' > $HOME/cheetah-dual/backup/shared-part-state-1.tar && tar -tf $HOME/cheetah-dual/backup/shared-part-state-1.tar | head -8
```
لازم تشوف `SHA256SUMS` و `primary.raw` و `backup.raw` و `restore.sh`.

## 4) الخطوة الأولى (اختبار): نزوّد عدد الخانات من 32 لـ 33 (الخانة الجديدة فاضية، مفيش partition لسه)
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-create.sh grow --yes'
```
لازم تشوف `GROWN: 32 -> 33 entries, partitions untouched`.

## 5) لازم تجرّب البوت في الاتنين قبل ما نكمّل (ده الاختبار المهم)
1. Ubuntu يرجع؟
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'sync; reboot'
```
بعد ما يفتح (واعمل أمر ifconfig لو لزم):
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'findmnt -no SOURCE /; bash /root/shared-part-create.sh check | sed -n 2p'
```
لازم `/dev/sda32` و `entries=33`.
2. الـ bootloader شايف الجدول؟
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'reboot-to bootloader'
```
وعلى الماك:
```
fastboot getvar current-slot 2>&1 | head -1; fastboot getvar partition-size:userdata 2>&1 | head -1; fastboot getvar all 2>&1 | grep -c has-slot
```
بعدين `fastboot reboot`.
3. Android يفتح عادي؟ استخدم أيقونة التحويل لـ Android، افتح الموبايل وتأكد إنه شغال طبيعي (الداتا موجودة)، وبعدين ارجع لـ Ubuntu بأيقونة Android→Ubuntu.
**لو أي حاجة من التلاتة فشلت: ماتكمّلش. ابعتلي بس، وفيه سكربت التراجع (الخطوة 10).**

## 6) نعمل الـ partition نفسه (Ubuntu) — نسخة احتياطية جديدة الأول
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-create.sh backup pre-create'
```
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-create.sh create --yes'
```
لازم السطر الأخير `33 ... shared` و `CREATED partition shared` (والـ 31 userdata و32 ubuntu زي ما هما).

## 7) فورمات ext4 (بيرفض لو فيه أي حاجة على الـ partition أو لو مش sda33 بالاسم shared)
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-create.sh format --yes'
```
لازم `FORMATTED /dev/sda33 (ext4, SHARED)`.

## 8) تركيب أوتوماتيك على Ubuntu
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-ubuntu.sh install'
```
اختبر:
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'df -h /mnt/shared; echo hello-from-ubuntu > /mnt/shared/hello-from-ubuntu.txt; ls -la /mnt/shared'
```
وبعدين اعمل ريستارت لـ Ubuntu وتأكد إنه اتركّب لوحده: `... 'sync; reboot'` ثم `... 'findmnt /mnt/shared'`.

## 9) Android — حوّل لـ Android بالأيقونة، افتح الشاشة، وعلى الماك:
```
adb push ~/Downloads/shared-part-android.sh /data/local/tmp/
```
جرّب مرة واحدة (بيطبع كل خطوة):
```
adb shell "su -M -c 'sh /data/local/tmp/shared-part-android.sh once'"
```
لازم `OK: /sdcard/Shared is live`. افتح تطبيق Files ← التخزين الداخلي ← `Shared`: لازم تلاقي `hello-from-ubuntu.txt`. اعمل ملف/فولدر من Android.
لو عايزه يشتغل مع كل بوت:
```
adb shell "su -M -c 'sh /data/local/tmp/shared-part-android.sh install'"
```
فحص الحالة في أي وقت:
```
adb shell "su -M -c 'sh /data/adb/service.d/shared-part.sh status'"
```
ملاحظة: الصور اللي تنقلها من Ubuntu بتظهر في Files فورًا؛ في Gallery بعد ما Android يعمل scan (ريستارت أو شوية وقت).
رجّع لـ Ubuntu واتأكد إنك شايف الملف اللي عملته من Android.

## 10) التراجع (لو عايز تلغي كل ده)
* الأندرويد: `adb shell "su -M -c 'sh /data/adb/service.d/shared-part.sh uninstall'"`
* Ubuntu (بيشيل الـ mount بس، الـ partition والملفات زي ما هي):
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'bash /root/shared-part-rollback.sh soft'
```
* إرجاع جدول الـ GPT زي الأول بالظبط (32 خانة، الـ partition الجديد يختفي؛ الداتا اللي جواه ما بتتمسحش):
```
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'systemctl stop shared-part.service; bash /root/shared-part-rollback.sh gpt --yes'
```
وبعدين `sync; reboot`. (لو عايز ترجع للـ 33 خانة الفاضية: `gpt --to empty33 --yes`.)
* لو Ubuntu مش بيفتح خالص بعد خطوة الـ GPT: Power + Vol-Down للـ bootloader وابعتلي (النسخ الاحتياطية على الماك في `$HOME/cheetah-dual/backup/shared-part-state-1.tar`).

## تحذيرات مهمة
* الـ partition ده **مش مشفّر** (عكس داتا Android): أي حد يشغّل Ubuntu على التليفون يقدر يقراه. ماتحطش فيه حاجات سرية.
* أي `fastboot flash` لـ bootloader أو factory image بيعيد كتابة جدول الـ GPT ويشيل الخانتين 32 و33 (الداتا تفضل موجودة على الفلاش). عندنا النسخ الاحتياطية وسكربتات الإضافة.
* Android بيشوفه فقط بعد أول unlock للموبايل بعد كل بوت (الملفات في /sdcard مشفرة قبل كده).
