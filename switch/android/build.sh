# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash build.sh
# Builds SwitchToUbuntu.apk with plain SDK tools (no gradle). Needs JDK 17 and Android SDK (platform 34, build-tools 34.0.0).
set -euo pipefail
cd "$(dirname "$0")"
export JAVA_HOME=${JAVA_HOME:-$HOME/sdk/jdk-17.0.21+9}; export PATH=$JAVA_HOME/bin:$PATH
SDK=${SDK:-$HOME/sdk/android-sdk}; BT=$SDK/build-tools/34.0.0; JAR=$SDK/platforms/android-34/android.jar
W=build; rm -rf $W; mkdir -p $W/{flat,gen,classes}
$BT/aapt2 compile --dir app/res -o $W/flat
$BT/aapt2 link -I $JAR --manifest app/AndroidManifest.xml --java $W/gen --min-sdk-version 31 --target-sdk-version 34 \
  --version-code 2 --version-name 1.1 -o $W/base.apk $W/flat/*.flat
javac --release 11 -classpath $JAR -d $W/classes $(find app/java $W/gen -name '*.java')
$BT/d8 --release --min-api 31 --lib $JAR --output $W $(find $W/classes -name '*.class')
# add dex + the prebuilt bootctl (from the Magisk v31.1 APK, lib/arm64-v8a/libbootctl.so) as a native lib
mkdir -p $W/stage/lib/arm64-v8a && cp app/libs/arm64-v8a/libbootctl.so $W/stage/lib/arm64-v8a/
cp $W/base.apk $W/unsigned.apk
(cd $W && $BT/aapt add unsigned.apk classes.dex >/dev/null && cd stage && $BT/aapt add ../unsigned.apk lib/arm64-v8a/libbootctl.so >/dev/null)
$BT/zipalign -f -p 4 $W/unsigned.apk $W/aligned.apk
[ -f debug.keystore ] || keytool -genkeypair -keystore debug.keystore -storepass "${KEYSTORE_PASS:-CHANGE_ME_DEBUG_STORE}" -keypass "${KEYSTORE_PASS:-CHANGE_ME_DEBUG_STORE}" -alias androiddebugkey \
  -keyalg RSA -keysize 2048 -validity 36500 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
$BT/apksigner sign --ks debug.keystore --ks-pass "pass:${KEYSTORE_PASS:-CHANGE_ME_DEBUG_STORE}" --key-pass "pass:${KEYSTORE_PASS:-CHANGE_ME_DEBUG_STORE}" --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --out SwitchToUbuntu.apk $W/aligned.apk
$BT/apksigner verify --verbose SwitchToUbuntu.apk | head -5
$BT/aapt dump badging SwitchToUbuntu.apk | egrep "package|application-label|launchable|native-code|sdkVersion"
sha256sum SwitchToUbuntu.apk
