# Ubuntu 24.04 LTS + Phosh على Google Pixel 7 Pro (cheetah) — تجريبي

> ## ⚠️ تنبيه مهم: ده **ما اتجربش على موبايل حقيقي**
> كل الملفات اتبنت واتفحصت على السيرفر بس (الـ checksums، الـ headers بتاعة الـ boot images، الـ rootfs بيعدّي fsck، والسكريبتات `bash -n`).
> محدش ركّب الصورة دي على Pixel 7 Pro فعلاً. الأساس هو مشروع **Omarchy Mobile** (kernel + initramfs + صور الـ boot الخاصة بـ cheetah)،
> وهو نفسه مشروع جديد وفيه حاجات ناقصة. ممكن الموبايل يفتح على شاشة سودا أو يرجع لأندرويد لوحده. **اعمل ده على مسؤوليتك.**

## إيه اللي اتعمل بالظبط
- مفيش مشروع بيدعم Pixel 7 Pro رسمي: UBports/Ubuntu Touch "مش متعمله port"، postmarketOS مكتوب إنه "not booting"، Droidian مفيهوش غير sargo، Mobian مش مدعومه.
- فاتبنى **Ubuntu 24.04 LTS (noble) arm64** (من ports.ubuntu.com، بدون snapd) بواجهة **Phosh** (واجهة تاتش) فوق نفس خط إنتاج Omarchy Mobile:
  نفس الـ kernel (`7.3.0-rc6-omamobile-push1`)، نفس الـ initramfs، نفس صور `boot / init_boot / vendor_boot / vendor_kernel_boot / dtbo` ونفس تقسيم الـ userdata (ext4 اسمه `omamobile-root`).
- فيه: NetworkManager، الـ modules، SSH على كابل USB، المستخدم `user` وباسورده `user` (**بيتغيّر إجباري أول دخول**).
- Phosh موجود في Ubuntu 24.04 universe (إصدار 0.38) فمفيش داعي لواجهة تانية.
- **تسريع الـ GPU:** Ubuntu 24.04 فيها Mesa 25.2.8 وهي **مفيهاش** Mali-G710 (مش موجود في أي Mesa رسمي ولا PPA). عشان كده اتبنى **Mesa 26.2.4 (نفس نسخة Omarchy) + باتش Omarchy بتاع G710** وبقى باكدج `mesa-cheetah` جوه الصورة (panfrost فوق driver الـ panthor في الـ kernel، و llvmpipe احتياطي). كمان فيه firmware الـ GPU (`mali_csffw.bin`).
- **حد التخزين: 50GB:** الـ initramfs اتعدّل في نقطة واحدة بس (`grow_root`): أول إقلاع بيكبّر الـ root لحد **50GB كحد أقصى** (50,000,000,000 بايت) مش لكل الـ userdata. باقي الـ userdata بيفضل فاضي (وأندرويد هيعمله format لما ترجع له).
- مفيش حاجة تانية بتكبّر الـ root تلقائي. لو عايز من غير تكبير خالص: ضيف `omamobile.noresize` في الـ cmdline (محتاج تبني الصور تاني).

## الملفات
| الملف | الوصف |
|---|---|
| `images/boot.img`, `init_boot.img`, `vendor_boot.img`, `vendor_kernel_boot.img`, `dtbo.img` | الصور اللي بتتفلاش على **slot B** |
| `userdata.simg` | نظام Ubuntu 24.04 (sparse، ~1.4GB) بيتفلاش على `userdata` |
| `SHA256SUMS` | checksums لكل حاجة (السكريبت بيتحقق منها) |
| `scripts/` | `flash-linux.sh` `to-android.sh` `to-linux.sh` `reflash-slot-b.sh` `check-slot-b.sh` `android-protect-from-ota.sh` `provision-firmware.sh` |
| `build/` | سكريبتات البناء (قابلة للإعادة) |
| `debug_ssh/` | مفتاح SSH للـ debug (مش سر. أي حد معاه الفولدر يقدر يدخل root **من كابل USB** بس) |
| `DUAL_BOOT_ANALYSIS.md` | ليه مفيش أندرويد + لينكس مع بعض من غير ما تخسر داتا |

## 0) قبل أي حاجة: نسخة احتياطية
- **كل حاجة على الموبايل هتتمسح** (فتح البوت لودر بيعمل wipe، وفلاش Linux بيمسح الـ userdata تاني).
- خد نسخة من الصور والفيديوهات (Google Photos / كمبيوتر)، وفعّل نسخ الواتساب والـ authenticator، وخد backup لأكواد الـ 2FA، واعمل logout من حسابات مهمة لو محتاج.
- اتأكد إن البطارية فوق 50%.

## 1) نسخة الأندرويد/الـ firmware المطلوبة على slot A
- Omarchy اتطوّر على **Android 17** وبوتلودر **`cloudripper-17.0-15199429`** (الفرع اللي اتجرب `CP2A.260705.006`). استخدم **أحدث Android 17 factory image** لـ cheetah من developers.google.com/android/images.
- **الـ slot A و slot B لازم يكون عليهم نفس نسخة البوتلودر** (السكريبت هيرفض غير كده). أسهل طريقة: Android Flash Tool (https://flash.android.com) وتختار **Force flash all partitions** مرة واحدة — بيكتب الاتنين slots.
  (ده بيمسح الموبايل كمان.) لو السكريبت قالك إنه شايف بوتلودر slot واحد بس، شغّله بـ `--bootloader-slots-match <نسخة البوتلودر>` بعد ما تتأكد بنفسك.
- **ممنوع تفلاش factory image أقدم من اللي على الموبايل** (حماية anti-rollback في البوتلودر — ممكن تعمل brick).
- نزّل الـ factory zip لنفس النسخة (حوالي 3GB) واحتفظ بيه: محتاجه لل firmware (الخطوة 6) ولرجوعك لأندرويد.

## 2) فتح البوت لودر (⚠️ بيمسح الموبايل)
1. Settings → About phone → اضغط Build number 7 مرات (Developer options).
2. Settings → System → Developer options → فعّل **OEM unlocking** و **USB debugging**. (لازم النت شغال وحسابك متسجل؛ لو الخيار رمادي استنى يوم أو اتأكد إن الموبايل مش مقفول من شركة.)
3. `adb reboot bootloader` (أو Power + Volume Down).
4. على الماك: `fastboot flashing unlock` ← وافق من الموبايل بزرار الصوت + Power. الموبايل هيتمسح ويفتح تاني.
5. بعد الإقلاع الأول من جديد فعّل USB debugging تاني (اختياري).

## 3) الفلاش من الماك
1. نزّل **platform-tools** من Google وحطه في الـ PATH (`fastboot --version`). لازم نسخة حديثة.
2. فك فولدر `out/` في مكان بدون مسافات. موصّل الموبايل بكابل USB-C كويس (من غير هَب).
3. ادخل fastboot (`adb reboot bootloader`). وتأكد إن `fastboot devices` شايف جهاز واحد بس.
4. جرّب الأول **من غير ما يكتب أي حاجة**:
   ```
   cd out
   ./scripts/flash-linux.sh --dry-run
   ```
   بيتحقق من الـ checksums، ومن إن الموبايل cheetah ومفتوح، ومن البوتلودر، ومن مقاسات الصور، ويعرض الأوامر اللي هتتنفذ.
5. لو كله تمام:
   ```
   ./scripts/flash-linux.sh
   ```
   هيطلب منك تكتب `cheetah` ثم `ERASE ANDROID DATA`. الأوامر بالترتيب (زي Omarchy بالظبط):
   ```
   fastboot flash boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b   (واحدة واحدة)
   fastboot flash userdata userdata.simg      (بيتقسم لقطع تلقائي)
   fastboot --set-active=b
   fastboot reboot
   ```
   السكريبت **مابيكتبش** غير الأقسام دي: `boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata`.
   مفيش `fastboot erase` ولا `-w` ولا `flashing lock` ولا أي كتابة على الـ GPT أو البوتلودر أو slot A.

## 4) أول إقلاع
- ممكن ياخد كذا دقيقة (أول مرة بيكبّر الـ ext4 لحد 50GB بس — مش كل الـ userdata — ويعمل SSH keys). الشاشة بتعرض رسايل الـ kernel/initramfs (قصدنا نشيل الـ splash عشان تشوف إيه اللي بيحصل).
- لو **3 مرات** الإقلاع فشل، البوتلودر بيرجع لـ slot A (أندرويد) لوحده.
- **الدخول بالـ SSH** (أهم وسيلة تشخيص): وصّل الكابل، وعلى الماك اضبط الـ USB Ethernet على `172.16.42.2` / `255.255.255.0`، وبعدين:
  ```
  ssh user@172.16.42.1        # الباسورد: user  (هيطلب تغييره)
  ```
  أو بالمفتاح: `ssh -i $CHEETAH_SSH_KEY root@172.16.42.1`.
- الباسورد `user` بيتغيّر **إجباري أول دخول** (في SSH أو في نافذة Terminal اللي بتفتح لوحدها على الشاشة).
  الـ SSH بالباسورد مسموح من كابل USB بس (جدار nftables بيمنعه من Wi-Fi).
- الشاشة المفروض تفتح على Phosh (شاشة القفل ← اتفتح). لو الواجهة صغيرة جداً، اضبط الـ scale من Settings.

### الـ firmware (Wi-Fi / Bluetooth / صوت / هزاز / شحن)
جوجل مش بتسمح بإعادة توزيع الـ firmware، فبيتسحب من **الـ factory zip بتاعك** (مش من الباكدج دي):
```
./scripts/provision-firmware.sh cheetah-<build>-factory-<id>.zip
```
(على الماك: استخدم Docker زي ما مكتوب في أول السكريبت، أو جهاز Linux.) وبعدها اعمل reboot. من غير الخطوة دي Wi-Fi والبلوتوث مش هيشتغلوا.

## ما المتوقع يشتغل وما المتوقع ميشتغلش
| | الحالة المتوقعة (بدون ما تتجرب على الجهاز) |
|---|---|
| الشاشة والتاتش والأزرار | **غالباً شغالة** (120Hz، حسب Omarchy) |
| USB networking / SSH | **غالباً شغال** |
| Wi-Fi / Bluetooth / صوت / هزاز / شاشة البطارية والشحن | **محتمل بعد خطوة الـ firmware** |
| الرسوم / الـ GPU | **المفروض تسريع بالـ GPU (Mali-G710 عبر panfrost/panthor)** بس **ما اتجربش**: لو الـ GPU ما اشتغلش (مثلاً firmware أو drive الـ panthor) هيرجع تلقائي لـ llvmpipe (سوفتوير) والواجهة هتبقى أبطأ. تأكد من ده بـ `ssh` ثم `ls /dev/dri` و `journalctl -b -k \| grep -i panthor` |
| المودم / SIM / مكالمات / SMS / داتا | **غير مجرّب** — اعتبره مش شغال |
| الكاميرا | **مش شغالة** (مفيش libcamera/إعداد) |
| Deep sleep | مش موجود (s2idle بس) — البطارية هتخلص أسرع |
| GPS / البصمة / NFC | غير مدعومة |
| تطبيقات أندرويد / Google Play | لأ |

## 5) الرجوع لأندرويد
**ملحوظة:** لأن Linux كان على الـ userdata، أندرويد هيلاقي filesystem مش فاهمه وهيعمل format أو يعرض Factory reset — ده متوقع، وفيه خسارة لداتا Linux.
1. من الـ fastboot: `./scripts/to-android.sh` (بيعمل `fastboot --set-active=a` و reboot بس).
   أو يدوياً: `fastboot --set-active=a` ثم `fastboot reboot`. لو ظهر Recovery → "Factory data reset".
2. **أضمن طريقة:** Android Flash Tool (https://flash.android.com) من Chrome على جهاز تاني: اختار Pixel 7 Pro (cheetah) → Force flash all partitions → (اختياري) Lock bootloader في الآخر.
   **ماتقفلش البوتلودر (`flashing lock`) قبل ما تتأكد إن أندرويد الأصلي شغال سليم.**
   ممكن بدل كده تفلاش الـ factory zip بنفسك بـ `flash-all.sh`، بس **نفس النسخة أو أحدث** من اللي على الموبايل.

## 6) ليه مفيش أندرويد + لينكس مع بعض (dual boot) من غير ما تخسر داتا؟
مفيش طريقة آمنة، والتفاصيل في `DUAL_BOOT_ANALYSIS.md`. باختصار:
- **صورة ext4 جوه userdata بتاعة أندرويد:** مستحيل لأن الـ userdata متشفرة (FBE + metadata encryption) ومفتاحها مع أندرويد بس.
- **تصغير userdata وإضافة قسم:** معناه تعديل الـ GPT على Tensor G2؛ ده بيفتح باب الـ brick، وده اللي طلبنا نتجنبه بشكل قاطع.
- **قسم فاضي:** مفيش قسم فاضي آمن وكبير كفاية.
- فالمتاح: Linux على **slot B** وأندرويد (النظام نفسه، من غير داتا) على **slot A**، والتبديل بـ `fastboot --set-active=a|b`.
  - من Linux لأندرويد: `./scripts/to-android.sh` (أندرويد هيعمل format للـ userdata).
  - من أندرويد لـ Linux: `./scripts/flash-linux.sh` تاني (بيمسح داتا أندرويد). `to-linux.sh` بيشتغل فقط لو أندرويد ما اتفتحش بعد آخر فلاش.

## 7) حماية slot B من تحديثات أندرويد (OTA) وإصلاحه
- أندرويد لما بيتحدّث (وهو شغال على A) بيكتب على الـ slot **غير النشط** = slot B، يعني ممكن يمسح صور Linux. وبعد التحديث ممكن كمان يبدّل الـ slot النشط. (ولو اشتغلت على Linux فقط، أندرويد مش شغال فمفيش OTA.)
- **قفل التحديثات التلقائية:** Settings → System → Software updates → اقفل التحديث التلقائي، وكمان Developer options → اقفل "Automatic system updates". ممكن كمان `./scripts/android-protect-from-ota.sh` (بيستخدم `adb` وإعداد `ota_disable_automatic_update`؛ اسم الإعداد ده **غير متأكد منه**، فاعتمد على الإعدادات اليدوية). لازم تعيد ده بعد أي factory reset.
- **لو slot B اتكتب عليه:** `./scripts/check-slot-b.sh` (قراءة فقط) ثم `./scripts/reflash-slot-b.sh` — بيعيد فلاش الـ 5 صور بتاعة slot B **من غير ما يلمس الـ userdata**، يعني Linux وداتاه يفضلوا. (`--with-userdata` = إعادة تثبيت كاملة.)
- ملحوظة: لو أندرويد بوّت على A وعرض Factory reset، **ارفض** لو عايز تحتفظ بـ Linux.

## الأداء والسلاسة (إعدادات متضمنة)
- Phosh بـ scale = 3 (480×1040 logical، زي Omarchy) عن طريق `/etc/phosh/phoc.ini` — لو اسم شاشة الـ DSI مختلف عن `DSI-1/DSI-2` والـ scale ما اتطبقش، عدّله من `ssh`.
- `WLR_RENDERER=gles2` و `GSK_RENDERER=ngl` (رسم بالـ GPU)، Xwayland مقفول، أولوية أعلى لـ phosh.
- الـ governor بتاع الـ CPU = schedutil (الافتراضي في الـ kernel).
- خدمات اتقفلت: apt-daily / apt-daily-upgrade / motd-news / e2scrub / dpkg-db-backup / man-db / sysupdate، و snapd مش متثبت ومحجوب (pin).
- **مفيش ضمان إن الأداء هيبقى "سلس"** من غير تجربة على جهاز حقيقي؛ ده أفضل ما أمكن بناؤه من الكود المتاح.

## المخاطر
1. **مش متجرّب على جهاز حقيقي** — أي خطوة ممكن تفشل.
2. فتح البوت لودر بيمسح الموبايل، وبيبوّظ بعض إمكانيات الأمان (Play Integrity، تطبيقات بنوك)، ويمكن يلغي الضمان.
3. لازم نسخة البوتلودر تتطابق على الـ slotين، وممنوع فلاش نسخة أقدم (anti-rollback).
4. أندرويد OTA ممكن يكتب على slot B (انظر الجزء 7).
5. مفتاح الـ debug SSH متاح في `debug_ssh/` (root بالمفتاح، من USB فقط) — غيّره/احذفه من `/root/.ssh/authorized_keys` ومن `/home/user/.ssh/authorized_keys` بعد أول دخول، وعدّل الـ initramfs لو هتسيب الجهاز.
6. تغيير الباسورد الإجباري على الشاشة (autostart) وخدمة Phosh/PAM **ماتجربوش**. لو الواجهة ماظهرتش: ادخل SSH وشوف `journalctl -u phosh`.
7. الـ firmware من جوجل مطلوب لـ Wi-Fi وغيره، ولازم تستخرجه من الـ factory image بتاعك.
8. **Mesa مبنية يدوي** (26.2.4 + باتش G710) وأي `apt upgrade` للـ Mesa محجوب بـ pin عشان ما يرجّعش نسخة Ubuntu؛ لو الـ GPU عمل مشاكل: `sudo apt-mark`/pin أو `MESA_LOADER_DRIVER_OVERRIDE=swrast` عشان تجبر السوفتوير.
9. تحميل: ~1.4GB (`userdata.simg`) + ~26MB صور boot + الـ factory zip بتاعك (~3GB) + platform-tools.

مصادر: Omarchy Mobile (github.com/derekross/omarchy-mobile, linux-omarchy-mobile)، توثيق Google للـ factory images و Android Flash Tool، تقارير مجتمع Pixel.
