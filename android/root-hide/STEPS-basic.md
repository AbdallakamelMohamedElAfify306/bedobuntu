# إخفاء الروت لتطبيقات البنوك والمحافظ — Pixel 7 Pro / Magisk 31.1 / Android 17

## حدود مهمة (اقرأها)
- الـ bootloader مفتوح، فـ Play Integrity على أندرويد 13+ مش هيمرر DEVICE ولا STRONG بشكل حقيقي.
- اللي نقدر نصلّحه: كشف الروت الخاص بالتطبيق نفسه + BASIC integrity.
- تطبيقات كثيرة (خصوصًا بنوك كبيرة وGoogle Wallet) بتطلب DEVICE/STRONG وهتفضل ترفض.
- Stripe و Lemon Squeezy غالبًا موقع/Dashboard مش تطبيق موبايل بنكي؛ لو فيه تطبيق نزّله ضيفه في DenyList.
- مفيش طريقة قانونية/آمنة تضمن 100% لكل التطبيقات والبلوتلودر مفتوح.

## الملفات
- PlayIntegrityFork-v18.zip (sha256: 625ebe65631f761e1521009f10a205d74255adf2e35732923d65106643cad9a6)
- denylist-packages.txt — أسماء الـ packages

## الخطوات (من التليفون، أندرويد شغّال + Magisk)

### 1) Zygisk و DenyList
1. افتح Magisk → Settings.
2. فعّل Zygisk → ريستارت.
3. افتح Magisk تاني → Settings → فعّل Enforce DenyList.
4. Configure DenyList → علّم كل التطبيقات اللي تحت (وكل الـ processes جواها).
5. متعلّمش `Google Play services` / `com.google.android.gms`.

### 2) سطّب PlayIntegrityFork
من الماك (الملف في Downloads):
```
adb push ~/Downloads/PlayIntegrityFork-v18.zip /sdcard/Download/ && adb shell 'su -c magisk --install-module /sdcard/Download/PlayIntegrityFork-v18.zip'
```
بعدين `adb reboot`.

أو من Magisk → Modules → Install from storage → اختار الـ zip → ريستارت.

بعد الريستارت: Magisk → Modules → PlayIntegrityFork → Action (autopif) لو موجود، أو من root shell:
```
adb shell su -c 'cd /data/adb/modules/playintegrityfix && sh autopif4.sh --strong'
```
وبعدها:
```
adb shell su -c 'cd /data/adb/modules/playintegrityfix && sh killpi.sh'
```

### 3) اختياري: شيل تطبيق Magisk من الشاشة
في Magisk 31.1 مفيش Hide the Magisk app. بعد ما تظبط DenyList والموديولات، تقدر تمسح تطبيق Magisk من Settings → Apps؛ الروت والموديولات بيفضلوا شغالين. لو احتجته تاني سطّب نفس الـ APK.

### 4) اختبر
نزّل من Play Store: "Play Integrity API Checker" (من 1nikolas أو مشابه).
المتوقّع المعقول: MEETS_BASIC_INTEGRITY = نعم. DEVICE/STRONG غالبًا لا والبلوتلودر مفتوح.

امسح بيانات كل تطبيق بنك/محفظة قبل أول فتح بعد التعديل:
Settings → Apps → [التطبيق] → Storage → Clear data.

### 5) قايمة DenyList (علّم الكل)
انظر denylist-packages.txt. بعد ما تنزّل أي تطبيق جديد مشابه، ضيفه:
```
adb shell pm list packages | grep -iE 'nbe|hsbc|binance|paypal|wise|vodafone|etisalat|redot|grey|blockchain|payoneer|bmc|wewallet|stripe'
```

## لو تطبيق لسه بيرفض
1. تأكد إنه متعلم في DenyList بكل الـ processes.
2. Clear data + ريستارت.
3. تأكد إن Magisk app مش ظاهر أو اتمسح.
4. لو التطبيق بيطلب DEVICE/STRONG صراحة — مش هينفع والبلوتلودر مفتوح، من غير حلول فيها مفاتيح attestation مسروقة/ملغية (وده مش هعمله).

## الرجوع
احذف الموديول من Magisk → Modules → Remove → ريستارت. الروت نفسه بيفضل.
