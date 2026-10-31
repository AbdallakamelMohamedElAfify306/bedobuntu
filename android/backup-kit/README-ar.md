# باك أب أندرويد كامل (Pixel 7 Pro، روت Magisk)

الأداة دي بتسحب كل حاجة من التليفون على الماك بوك بالروت: التطبيقات وبياناتها، الأرقام والرسايل وسجل المكالمات، الصور والفيديوهات، إعدادات الروت، تطبيق السويتش، الإعدادات، وصور البارتيشنات المهمة. كلها بتتعمل على الماك من الـ Terminal، والتليفون بيتقرا بس ومفيش حاجة بتتغير فيه.

## الخطوات (3 سطور بس)

1. التليفون على أندرويد، مفتوح، ومتوصل بالماك بالكابل، وتصحيح USB شغال.
2. فك الملف:
```
unzip -oq ~/Downloads/android-backup-kit.zip -d $HOME/cheetah-dual
```
3. شغّل الباك أب:
```
bash $HOME/cheetah-dual/android-backup-kit/android-full-backup.sh
```
4. أول ما يبدأ، بص على التليفون. لو Magisk طلب صلاحية روت لـ Shell، اضغط Grant.
5. سيب التليفون والماك مفتوحين ومتوصلين لحد ما تشوف `BACKUP-OK` في الآخر. الشاشة هتفضل صاحية لوحدها، والماك كمان مش هيدخل سكون.

الباك أب بيتحفظ في `$HOME/cheetah-dual/backup/android-YYYYMMDD/` (التاريخ بتاع النهارده).

## لو وقف في النص

شغّل نفس السطر رقم 3 تاني. الحاجات اللي خلصت وسليمة بتتخطى (SKIP)، والباقي بيتكمل. لو عدّى يوم جديد، قول له الفولدر القديم:
```
DEST=$HOME/cheetah-dual/backup/android-20261029 bash $HOME/cheetah-dual/android-backup-kit/android-full-backup.sh
```

## أوامر مفيدة

- فحص الملفات بعد الباك أب (بيقارن SHA256SUMS):
```
bash $HOME/cheetah-dual/android-backup-kit/android-full-backup.sh verify
```
- تشغيل جزء واحد بس، الأجزاء: manifest settings contacts root switch partitions apps media:
```
ONLY=apps bash $HOME/cheetah-dual/android-backup-kit/android-full-backup.sh
```
- لو مساحة الماك مش كفاية، احفظ على هارد خارجي:
```
DEST=/Volumes/اسم-الهارد/android-20261029 bash $HOME/cheetah-dual/android-backup-kit/android-full-backup.sh
```

## إيه اللي بيتعمل

| الجزء | الملف / الفولدر |
|---|---|
| قوائم الجهاز | `manifest/` (getprop، البارتيشنات، pm list، df) و `packages-3.txt` و `packages-all.txt` |
| الإعدادات (system/secure/global، Wi-Fi، Bluetooth، اللانشر، الخلفية، التطبيقات الافتراضية، عدم الإزعاج، Gboard، الساعة) | `settings/` |
| الأرقام والرسايل وسجل المكالمات | `contacts/contacts-sms-calllog.tar.gz` (فيها -wal و -shm) و `contacts/export/*.txt` (نسخة نصية) |
| الروت | `root/data-adb.tar.gz` (modules، service.d فيها shared-part.sh، magisk.db، PIF) و `root/magisk-denylist.txt` |
| تطبيق السويتش بين أندرويد وأوبونتو | `switch-ubuntu/` (الـ APK والداتا والسكريبتات) |
| التطبيقات | `apps/apks/اسم-الحزمة/` (فيها كل الـ splits) و `apps/data/اسم-الحزمة.tar.gz` و `apps/obb.tar.gz` |
| الصور والفيديوهات وكل التخزين الداخلي | `media/internal-storage.tar` (من غير فولدر Shared البارتيشن المشترك) |
| البارتيشنات (قراءة فقط) | `partitions/*.img` (boot وinit_boot وvendor_boot وvendor_kernel_boot وdtbo وvbmeta وefs وpersist وغيرها). مش بنقرا userdata ولا super أبدًا |
| الفحص | `SHA256SUMS` و `backup.log` و `logs/` |

كل أرشيف بيتفحص على الماك بـ `gzip -t` (أو `tar -t` للـ tar العادي) قبل ما يتحسب ناجح.

## الوقت والحجم (تقدير)

- السرعة على الكابل غالبًا 20 إلى 40 ميجا في الثانية، يعني كل 10 جيجا تقريبًا من 5 لـ 10 دقايق.
- البارتيشنات حوالي 0.5 جيجا (دقيقتين تلاتة). الإعدادات والأرقام والروت أقل من دقيقتين.
- التطبيقات وبياناتها: غالبًا من 5 لـ 20 جيجا، حوالي ربع ساعة لنص ساعة.
- الصور والفيديوهات: بحجمها بالظبط، وكل 60 جيجا تقريبًا ساعة.
- الحجم الكلي تقريبًا قد المساحة المستخدمة في التليفون. الأداة بتقارنها بالمساحة الفاضية على الماك وبتوقف قبل ما تبدأ لو مش كفاية (بتحسب كمان 2 جيجا زيادة).

## استرجاع (لنفس التليفون ونفس النسخة بس)

كل الأوامر دي بتتشغل من الماك داخل فولدر الباك أب. بدّل `PKG` باسم الحزمة.

**1) تثبيت التطبيق (مع الـ splits)**
```
cd $HOME/cheetah-dual/backup/android-YYYYMMDD/apps/apks/PKG && adb install-multiple -r *.apk
```
المهم الـ APK يكون من نفس الإصدار اللي اتاخد منه الباك أب.

**2) استرجاع بيانات التطبيق** (بعد ما التطبيق يتثبت ويتفتح مرة واحدة، وبعدين تقفله):
```
PKG=com.example.app
adb push $HOME/cheetah-dual/backup/android-YYYYMMDD/apps/data/$PKG.tar.gz /data/local/tmp/
adb shell "su -c 'am force-stop $PKG; U=\$(stat -c %u /data/data/$PKG); tar -xzf /data/local/tmp/$PKG.tar.gz -C /; chown -R \$U:\$U /data/data/$PKG /data/user_de/0/$PKG; chown -R \$U:1078 /data/media/0/Android/data/$PKG; restorecon -RF /data/data/$PKG /data/user_de/0/$PKG /data/media/0/Android/data/$PKG; rm /data/local/tmp/$PKG.tar.gz'"
```
الفكرة: التطبيق بياخد رقم مستخدم جديد (uid) بعد التثبيت، فلازم نعمل `chown` للـ uid الجديد، وبعدها `restorecon` عشان تسميات SELinux. لو التطبيق مش بيفتح بعد كده، امسح بياناته من الإعدادات وسجّل دخول من جديد.

**3) الـ OBB**: فك `apps/obb.tar.gz` على الماك وبعدين `adb push` لفولدر `/sdcard/Android/obb/`.

**4) الصور والتخزين الداخلي:**
```
mkdir -p $HOME/cheetah-dual/restore-media && tar -xf $HOME/cheetah-dual/backup/android-YYYYMMDD/media/internal-storage.tar -C $HOME/cheetah-dual/restore-media && adb push $HOME/cheetah-dual/restore-media/. /sdcard/
```

**5) الأرقام والرسايل:** الأسهل والأأمن تعمل Sync من حساب Google للأرقام. الملفات `contacts/export/*.txt` نص للقراءة بس. لو لازم ترجّع قواعد البيانات نفسها: افتح الأرشيف على الماك، وعلى التليفون اقفل `am force-stop com.android.providers.contacts` (أو telephony)، وانسخ ملفات `contacts2.db` مع -wal و -shm (كلهم مع بعض) لمكانهم الأصلي، واعمل `chown` للمستخدم اللي كان مالكهم و`restorecon -R`، وبعدين Reboot. ده بيشتغل لنفس النسخة بس، وجرّبه الأول على نسخة تانية لو تقدر.

**6) الإعدادات:** استخدم `settings/restore.sh` (جوه فولدر الباك أب) على التليفون. الجدول في `settings/RESTORE-SAFETY.md` بيقول إيه اللي آمن ترجّعه وإيه لأ. مفيش استرجاع كامل لـ system/secure/global، رجّع مفتاح مفتاح بـ `settings put`.

**7) الروت:** فك `root/data-adb.tar.gz` على الماك، وارفع بس الـ modules والـ service.d (مش الـ magisk كله) لـ `/data/adb/` بالروت، واعمل `chmod 755` للسكريبتات و`restorecon -R /data/adb`، وبعدين Reboot. لو كان فيه تعارض مع نسخة Magisk جديدة، سيب ملفات Magisk نفسها.

**8) البارتيشنات:** دي للطوارئ بس (لو الجهاز اتبوّظ). مثلًا `fastboot flash boot_a partitions/boot_a.img`. صور `efs` و`persist` فيها الـ IMEI وبيانات الراديو، ماتفلشهاش إلا لو الراديو بايظ فعلًا ولنفس الجهاز بالظبط.

## تنبيهات مهمة

- **الـ eSIM**: البروفايلات مش بتتنسخ ومش بتترجع. هتحتاج تنزّلها من شركة الاتصالات من جديد.
- **مفاتيح الأمان (keystore) والمفاتيح اللي في الهاردوير**: مش ممكن تتنسخ. تطبيقات البنوك والمحافظ ومعظم التطبيقات اللي بتستخدم بصمة أو مفتاح محمي هتطلب تسجيل دخول من جديد بعد الاسترجاع. كمان الـ DRM (زي Widevine) وبعض المحتوى المحمي مش بيتنسخ.
- **بيانات التطبيقات بين إصدارات مختلفة** ممكن توقّع التطبيق أو تبوّظ بياناته. رجّع نفس إصدار الـ APK اللي في الباك أب.
- **النسخة بتحتوي أسرار**: باسوردات الـ Wi-Fi، مفاتيح البلوتوث، وبيانات التطبيقات (جلسات دخول). خلّي الفولدر متشفّر ومتوديش حد. مثال لعمل صورة متشفرة (هيطلب منك باسورد):
```
hdiutil create -encryption AES-256 -srcfolder $HOME/cheetah-dual/backup/android-YYYYMMDD -volname android-backup $HOME/cheetah-dual/backup/android-YYYYMMDD.dmg
```
  وبعد ما تتأكد إنها اتفتحت صح، امسح الفولدر العادي. لازم يكون عندك مساحة فاضية بقد حجم الباك أب تاني للصورة المتشفرة، أو شغّل الأمر على هارد خارجي.
- الباك أب بيتعمل والتليفون شغال، فملفات بتتغير وقت النسخ (قواعد بيانات) ممكن تطلع مش متزامنة 100%. وده طبيعي، ومعظم التطبيقات بترجع تفتح عادي.
- أي رسالة من tar على التليفون بتتسجل في `logs/device-tar-errors.txt`.
