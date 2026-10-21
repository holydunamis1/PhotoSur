#!/usr/bin/env bash
# Stress scenarios on a real emulator, release build (what stores ship).
# Reads the screen through uiautomator (Flutter exposes its labels), so it
# can tap by visible text. Every scenario prints PASS / FAIL / INFO.
PKG=com.zdmgold.photosur
REL=app/build/app/outputs/flutter-apk/app-release.apk
R=${R:-/tmp/photo_results.txt}; : > $R
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

