#!/usr/bin/env bash
# Runs inside the emulator: install the debug APK, launch it, wait, and
# collect the app's own startup log so a hang/crash can be diagnosed
# without a phone. Output is split into <4 KB annotations.
APK=app/build/app/outputs/flutter-apk/app-debug.apk
PKG=com.zdmgold.photosur
adb wait-for-device
adb install -r "$APK" > /tmp/install.txt 2>&1
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 6
PID=$(adb shell pidof "$PKG" | tr -d '\r')
# Ask the (frozen) app where its Dart code is, via the VM service.
sleep 22
VMLINE=$(adb logcat -d | grep -m1 "Dart VM service is listening on")
PORT=$(echo "$VMLINE" | sed -n 's#.*127.0.0.1:\([0-9]*\)/.*#\1#p')
TOKEN=$(echo "$VMLINE" | sed -n 's#.*127.0.0.1:[0-9]*/\([^/ ]*\)/.*#\1#p')
echo "vm service port=$PORT token_len=${#TOKEN}" > /tmp/dartstack.txt
if [ -n "$PORT" ]; then
  adb forward "tcp:$PORT" "tcp:$PORT" >> /tmp/dartstack.txt 2>&1
  ( cd .github/scripts/dart_stack && dart pub get > /tmp/dartstack_pub.txt 2>&1 \
    && timeout 90 dart run bin/stack.dart "ws://127.0.0.1:$PORT/$TOKEN/ws" >> /tmp/dartstack.txt 2>&1 ) \
    || echo "stack tool failed: $(tail -3 /tmp/dartstack_pub.txt)" >> /tmp/dartstack.txt
fi
sleep 30
ALIVE=$(adb shell pidof "$PKG" | tr -d '\r')
# The system saves an ANR trace (all thread stacks) when it reports an ANR.
adb root > /dev/null 2>&1; sleep 3
adb shell 'ls -t /data/anr 2>/dev/null' > /tmp/anr_files.txt
adb shell 'cat /data/anr/anr_* 2>/dev/null' > /tmp/anr_all.txt
PID2=$(adb shell pidof "$PKG" | tr -d '\r')
[ -n "$PID2" ] && adb shell "debuggerd -b $PID2" > /tmp/debuggerd.txt 2>&1
adb logcat -d -v threadtime > /tmp/full.txt
{
  echo "install: $(tail -1 /tmp/install.txt) | first pid: $PID | pid after 76s: ${ALIVE:-NONE (process gone)}"
  adb shell dumpsys activity activities | grep -E "topResumedActivity" | head -1 | cut -c1-140
  echo "=== BOOT trace + flutter errors (all pids) ==="
  grep -E "I flutter *: (BOOT|APPERR)|E flutter|F flutter|Unhandled|FATAL EXCEPTION|Fatal signal|ANR in $PKG|am_crash|am_proc_died" /tmp/full.txt | grep -v -E "AppOps|PeoplePU|Corpus|MediaScanner|Cronet" | cut -c7-260 | head -n 75
  echo "=== DART STACK of the running app (VM service) ==="
  head -n 90 /tmp/dartstack.txt | cut -c1-210
  echo "=== ANR reason ==="
  grep -A 6 "ANR in $PKG" /tmp/full.txt | cut -c7-240 | head -n 12
  echo "=== anr files: $(tr '\r\n' '  ' < /tmp/anr_files.txt | cut -c1-120)  (anr bytes: $(wc -c < /tmp/anr_all.txt))"
  echo "=== MAIN THREAD (ANR trace) ==="
  awk '/^"main" /{f=1} f{print; n++} n>=28{exit}' /tmp/anr_all.txt | cut -c1-200
  echo "=== MAIN THREAD (debuggerd native) ==="
  awk '/^"main"|name: main|tid=1\)/{f=1} f{print; n++} n>=22{exit}' /tmp/debuggerd.txt | cut -c1-200
  echo "=== ad/notification related lines from the app process ==="
  grep -E "^[0-9-]+ [0-9:.]+ +[0-9]+ +[0-9]+ [A-Z] (Ads|gads|MobileAds|FlutterLocalNotif|FlutterLocalNotifications|GoogleMobileAds)" /tmp/full.txt | cut -c7-240 | head -n 20
  echo "=== activity lifecycle (our package) ==="
  grep -E "ActivityTaskManager|ActivityManager" /tmp/full.txt | grep -E "$PKG" | grep -E "START|Displayed|Killing|died|restart|relaunch|finish" | cut -c7-220 | head -n 14
} > /tmp/filtered.txt
cat /tmp/filtered.txt
python3 - <<'PY'
import re
t=open('/tmp/filtered.txt').read()
esc=lambda s:s.replace('%','%25').replace('\r','%0D').replace('\n','%0A')
chunks=[];cur=''
for line in t.split('\n'):
    if len(cur)+len(line)+1>3400: chunks.append(cur);cur=''
    cur+=line+'\n'
chunks.append(cur)
for i,c in enumerate(chunks[:9],1):
    print(f"::notice title=EMU LOG {i}/{len(chunks)}::{esc(c)}")
PY

# ---- Phase 2: the RELEASE build (what testers/stores get) ----
REL=app/build/app/outputs/flutter-apk/app-release.apk
adb uninstall "$PKG" > /dev/null 2>&1
adb install -r "$REL" > /tmp/rinstall.txt 2>&1
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
sleep 45
RALIVE=$(adb shell pidof "$PKG" | tr -d '\r')
adb logcat -d -v threadtime > /tmp/rfull.txt
{
  echo "RELEASE install: $(tail -1 /tmp/rinstall.txt) | pid after 45s: ${RALIVE:-NONE (process gone)}"
  adb shell dumpsys activity activities | grep -E "topResumedActivity" | head -1 | cut -c1-140
  grep -E "I flutter *: (BOOT|APPERR)|E flutter|ANR in $PKG|FATAL EXCEPTION|Fatal signal" /tmp/rfull.txt | cut -c7-240 | head -n 30
} > /tmp/release.txt
cat /tmp/release.txt
python3 - <<'PY'
t=open('/tmp/release.txt').read()
esc=lambda s:s.replace('%','%25').replace('\r','%0D').replace('\n','%0A')
print("::notice title=EMU LOG release::"+esc(t[:3500]))
PY
exit 0
