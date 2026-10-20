#!/usr/bin/env bash
# Stress scenarios on a real emulator, release build (what stores ship).
# Reads the screen through uiautomator (Flutter exposes its labels), so it
# can tap by visible text. Every scenario prints PASS / FAIL / INFO.
PKG=com.zdmgold.photosur
REL=app/build/app/outputs/flutter-apk/app-release.apk
R=/tmp/stress_results.txt; : > $R
say(){ echo "$*" | tee -a $R; }
alive(){ adb shell pidof "$PKG" | tr -d '\r'; }
launch(){ adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; }
dump(){ for t in 1 2 3; do adb shell rm -f /sdcard/ui.xml; adb shell uiautomator dump /sdcard/ui.xml >/tmp/dump_err.txt 2>&1; X=$(adb shell cat /sdcard/ui.xml 2>/dev/null); [ -n "$X" ] && { echo "$X"; return; }; sleep 1; done; }
# has_text "Label" -> 0 if any node has that text/description
has_text(){ dump | python3 -c "
import sys,re
x=sys.stdin.read(); t=sys.argv[1].lower()
sys.exit(0 if any(t in v.lower() for v in re.findall(r'(?:text|content-desc)=\"([^\"]*)\"',x)) else 1)" "$1"; }
tap_text(){ dump | python3 -c "
import sys,re,subprocess
x=sys.stdin.read(); t=sys.argv[1].lower()
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    a=re.search(r'(?:text|content-desc)=\"([^\"]*)\"',n)
    d=re.search(r'content-desc=\"([^\"]*)\"',n); tx=re.search(r' text=\"([^\"]*)\"',n)
    vals=[v.group(1).lower() for v in (d,tx) if v]
    b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',n)
    if b and any(t in v for v in vals):
        x1,y1,x2,y2=map(int,b.groups()); 
        subprocess.call(['adb','shell','input','tap',str((x1+x2)//2),str((y1+y2)//2)]); sys.exit(0)
sys.exit(1)" "$1"; }
wait_text(){ for i in $(seq 1 ${2:-15}); do has_text "$1" && return 0; sleep 2; done; return 1; }
check(){ # name, command...
  n="$1"; shift; if "$@"; then say "PASS $n"; else say "FAIL $n"
    say "   diag: pid=$(alive) top=$(adb shell dumpsys activity activities | grep -m1 topResumedActivity | sed 's/.*ActivityRecord//' | cut -c1-90)"
    say "   diag: dump_err=$(head -c 120 /tmp/dump_err.txt | tr '\n' ' ') dump_bytes=$(adb shell cat /sdcard/ui.xml 2>/dev/null | wc -c) texts=$(dump | grep -o '\(text\|content-desc\)="[^"]\+"' | head -12 | tr '\n' ' ')"
    say "   diag: log=$(adb logcat -d -v brief | grep -E "$PKG|flutter|AndroidRuntime|ActivityManager.*(Killing|died)" | tail -4 | cut -c1-140 | tr '\n' '|')"
  fi; }
crashes(){ adb logcat -d -v threadtime | grep -E -A2 "FATAL EXCEPTION|Fatal signal|ANR in $PKG|am_crash.*$PKG" | grep -E "Process: $PKG|ANR in $PKG|am_crash.*$PKG|Fatal signal.*$PKG|>>> $PKG" | head -3; }

adb wait-for-device
adb uninstall "$PKG" >/dev/null 2>&1
adb install -r "$REL" > /tmp/i.txt 2>&1; say "INFO install: $(tail -1 /tmp/i.txt)"
adb logcat -c

# 1 First launch -> onboarding
launch; sleep 8
check "01 first launch shows onboarding" wait_text "Next" 10
check "01b process alive" test -n "$(alive)"

# 2 Walk onboarding with taps
for i in 1 2 3; do tap_text "Next"; sleep 1; done
check "02 reaches Get Started on page 4" wait_text "Get Started" 5
tap_text "Get Started"; sleep 3
# notification / ATT-style system dialogs: allow if shown
for i in 1 2; do adb shell input keyevent KEYCODE_TAB >/dev/null 2>&1; tap_text "Allow" ; sleep 1; done
check "02b Home shown after onboarding" wait_text "Gallery" 10

# 3 Kill + relaunch must stay on Home (the old loop bug)
adb shell am force-stop "$PKG"; sleep 2; launch; sleep 6
check "03 restart opens Home, not onboarding" wait_text "Gallery" 10
has_text "Get Started" && say "FAIL 03b onboarding reappeared"

# 4 Rotate repeatedly, then back
adb shell settings put system accelerometer_rotation 0
for r in 1 0 3 0 1 0; do adb shell settings put system user_rotation $r; sleep 1; done
check "04 survives 6 rotations" test -n "$(alive)"
check "04b Home still drawn" has_text "Gallery"

# 5 Background / foreground cycles, memory pressure
for i in 1 2 3 4 5; do adb shell input keyevent KEYCODE_HOME; sleep 1; launch; sleep 2; done
adb shell am send-trim-memory "$PKG" COMPLETE >/dev/null 2>&1
adb shell input keyevent KEYCODE_HOME; sleep 2; launch; sleep 3
check "05 survives 5 background cycles + memory trim" test -n "$(alive)"
adb shell am kill "$PKG"; sleep 2; launch; sleep 6
check "05b recovers after system kill" has_text "Gallery"

# 6 Settings and sub-screens open and close
tap_text "Settings"; sleep 2; check "06 Settings opens" wait_text "Animated home background" 6
tap_text "Animated home background"; sleep 1
adb shell input keyevent KEYCODE_BACK; sleep 1
tap_text "Help"; sleep 2; check "06b Help opens" wait_text "Help" 5
adb shell input keyevent KEYCODE_BACK; sleep 1
tap_text "Language"; sleep 2; check "06c Language picker opens" wait_text "Arabic" 5
adb shell input keyevent KEYCODE_BACK; sleep 1
check "06d back on Home" has_text "Gallery"

# 7 Pick a real image from the gallery
python3 - <<'PY'
import struct,zlib
def png(w,h):
    raw=b''.join(b'\x00'+bytes([(x*255//w),(y*255//h),128])*1 if False else b'\x00'+b''.join(bytes([x*255//w,y*255//h,128]) for x in range(w)) for y in range(h))
    def ch(t,d): c=struct.pack('>I',len(d))+t+d; return c+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b'')
open('/tmp/test_photo.png','wb').write(png(900,1200))
PY
adb push /tmp/test_photo.png /sdcard/Pictures/test_photo.png >/dev/null 2>&1
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/test_photo.png >/dev/null 2>&1
sleep 3
tap_text "Gallery"; sleep 4
say "INFO picker screen has: $(dump | grep -o 'content-desc="[^"]*"' | head -8 | tr '\n' ' ')"
tap_text "Photo taken" || adb shell input tap 200 600
sleep 10
say "INFO after picking: alive=$(alive) screen: $(dump | grep -o 'content-desc="[^"]*"' | head -8 | tr '\n' ' ')"
check "07 process alive after picking an image" test -n "$(alive)"
say "INFO 07 texts on screen after pick: $(dump | grep -o '\(text\|content-desc\)="[^"]\+"' | head -14 | tr '\n' ' ')"
# leave whatever is on top (picker / editor) and return to a clean Home
for i in 1 2 3; do adb shell input keyevent KEYCODE_BACK; sleep 1; done
adb shell am force-stop com.google.android.providers.media.module >/dev/null 2>&1
adb shell am force-stop "$PKG"; sleep 1; launch; sleep 5
check "07b Home after leaving the picked image" wait_text "Gallery" 8

# 8 Permissions denied
adb shell pm revoke "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null
adb shell pm revoke "$PKG" android.permission.CAMERA 2>/dev/null
adb shell am force-stop "$PKG"; sleep 1; launch; sleep 6
check "08 starts with notifications+camera denied" wait_text "Gallery" 8

# 9 Low-storage: fill most of /data/local/tmp free space and relaunch
FREE=$(adb shell df /data | tail -1 | awk '{print $4}')
say "INFO free /data KB: $FREE"
adb shell "dd if=/dev/zero of=/data/local/tmp/fill bs=1M count=$(( (FREE/1024) - 60 ))" >/dev/null 2>&1
adb shell am force-stop "$PKG"; sleep 1; launch; sleep 6
check "09 starts with ~60 MB free storage" wait_text "Gallery" 8
adb shell rm -f /data/local/tmp/fill

# 10 Airplane mode (ads must fail quietly)
adb shell cmd connectivity airplane-mode enable >/dev/null 2>&1
adb shell am force-stop "$PKG"; sleep 1; launch; sleep 8
check "10 starts offline, Home usable" has_text "Gallery"
adb shell cmd connectivity airplane-mode disable >/dev/null 2>&1

# 11 Random UI abuse: 3 seeds x 4000 events
adb shell settings put system user_rotation 0
for seed in 11 22 33; do
  adb shell monkey -p "$PKG" --pct-syskeys 0 --pct-appswitch 0 --throttle 40 -s $seed -v 4000 > /tmp/m$seed.txt 2>&1
  say "INFO monkey seed $seed: $(grep -E 'Monkey finished|CRASH|ANR|Events injected' /tmp/m$seed.txt | tr '\n' ' ' | cut -c1-160)"
  sleep 2; launch; sleep 2
done
check "11 alive after 12000 random events" test -n "$(alive)"

# 12 Locale sweep at system level (app follows its own setting; check boot in each)
for loc in ar-EG hi-IN ja-JP de-DE; do
  adb shell "setprop persist.sys.locale $loc" 2>/dev/null
  adb shell am force-stop "$PKG"; sleep 1; launch; sleep 5
  check "12 boots with system locale $loc" test -n "$(alive)"
done

C=$(crashes)
[ -z "$C" ] && say "PASS 99 no FATAL/ANR/native crash anywhere in the log" || say "FAIL 99 crash lines: $C"
adb logcat -d -v threadtime | grep -E "E flutter|F flutter|APPERR|Process: $PKG|ANR in $PKG" | cut -c7-230 | head -n 25 > /tmp/errs.txt
{ echo "=== RESULTS ==="; cat $R; echo "=== flutter/app errors in log ==="; cat /tmp/errs.txt; } > /tmp/final.txt
cat /tmp/final.txt
python3 - <<'PY'
t=open('/tmp/final.txt').read()
esc=lambda s:s.replace('%','%25').replace('\r','%0D').replace('\n','%0A')
ch=[];cur=''
for l in t.split('\n'):
    if len(cur)+len(l)+1>3400: ch.append(cur);cur=''
    cur+=l+'\n'
ch.append(cur)
for i,c in enumerate(ch[:6],1): print(f"::notice title=STRESS {i}/{len(ch)}::{esc(c)}")
PY
