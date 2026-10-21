#!/usr/bin/env bash
# Real photos through the real flow on the release build:
# pick -> crop -> automatic cut-out -> editor tools -> export (3 formats) ->
# verify the saved file -> batch. Outputs are copied to stress_out/ so they
# can be opened from the Actions artifact.
PKG=com.zdmgold.photosur
REL=app/build/app/outputs/flutter-apk/app-release.apk
OUT=$PWD/stress_out; mkdir -p "$OUT"
R=/tmp/photo_results.txt
source .github/scripts/emu_lib.sh
python3 -m pip install -q --break-system-packages pillow > /tmp/pip.txt 2>&1 || python3 -m pip install -q pillow >> /tmp/pip.txt 2>&1
python3 -c 'import PIL;print("pillow",PIL.__version__)' 2>&1 | tee -a $R

new_files(){ adb shell "find /sdcard/Pictures /sdcard/DCIM -type f -newer /sdcard/marker \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null" | tr -d '\r' | grep -v '/\.' | grep -v '/ps_'; }
tap_nth(){ dump | python3 -c "
import sys,re,subprocess
x=sys.stdin.read(); t=sys.argv[1].lower(); k=int(sys.argv[2]); c=0
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    d=re.search(r'content-desc=\"([^\"]*)\"',n); tx=re.search(r' text=\"([^\"]*)\"',n)
    b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',n)
    if b and any(v and t in v.group(1).lower() for v in (d,tx)):
        c+=1
        if c==k:
            x1,y1,x2,y2=map(int,b.groups()); subprocess.call(['adb','shell','input','tap',str((x1+x2)//2),str((y1+y2)//2)]); sys.exit(0)
sys.exit(1)" "$1" "$2"; }
tap_exact(){ dump | python3 -c "
import sys,re,subprocess
x=sys.stdin.read(); t=sys.argv[1].lower()
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    d=re.search(r'content-desc=\"([^\"]*)\"',n); tx=re.search(r' text=\"([^\"]*)\"',n)
    b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',n)
    if b and any(v and v.group(1).strip().lower()==t for v in (d,tx)):
        x1,y1,x2,y2=map(int,b.groups()); subprocess.call(['adb','shell','input','tap',str((x1+x2)//2),str((y1+y2)//2)]); sys.exit(0)
sys.exit(1)" "$1"; }
open_photo(){ # P -> leaves you in the editor with the automatic cut-out done
  fresh_photo "$1"; go_home
  tap_text "Gallery"; sleep 4
  tap_text "Photo taken" || adb shell input tap 200 600
  sleep 5
  wait_text "Continue" 10 || { say "FAIL $1 no crop screen: $(onscreen)"; return 1; }
  tap_text "Continue"
  wait_text "Export" 40 || { say "FAIL $1 editor never opened: $(onscreen)"; return 1; }
  sleep 12; return 0; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
onscreen(){ dump | grep -o '\(text\|content-desc\)="[^"]\+"' | head -${1:-14} | tr '\n' ' '; }
fresh_photo(){ # push exactly one photo as the newest picture
  adb shell 'rm -f /sdcard/Pictures/*.jpg /sdcard/Pictures/*.png /sdcard/DCIM/Camera/*' >/dev/null 2>&1
  adb push "/tmp/photos/$1.jpg" "/sdcard/Pictures/ps_$1.jpg" >/dev/null 2>&1
  adb shell touch "/sdcard/Pictures/ps_$1.jpg"
  adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/Pictures/ps_$1.jpg" >/dev/null 2>&1
  sleep 3; }
go_home(){ for i in 1 2 3; do adb shell input keyevent KEYCODE_BACK; sleep 1; done
  adb shell am force-stop com.google.android.providers.media.module >/dev/null 2>&1
  adb shell am force-stop "$PKG"; sleep 1; launch; sleep 5; }
# Export the current editor image in a given format; saves into the gallery
export_as(){ # label format
  adb shell touch /sdcard/marker; sleep 1
  tap_text "Export"; sleep 2
  case "$2" in PNG|JPG|WEBP) tap_text "$2"; sleep 1;; esac
  tap_text "Save to Gallery"; sleep 6
  if has_text "Allow"; then tap_text "Allow"; sleep 4; fi
  if has_text "Test Ad"; then say "INFO ad shown after export (closing it)"; tap_text "Close"; sleep 2; fi
  F=$(new_files | head -1)
  if [ -n "$F" ]; then
    EXT="${F##*.}"; adb exec-out "cat '$F'" > "$OUT/$1_$2.$EXT" 2>/dev/null
    say "PASS $1 export $2 saved: $(basename "$F") ($(stat -c%s "$OUT/$1_$2.$EXT") bytes)"
    say "     $(python3 -W ignore .github/scripts/analyze_cutout.py "$OUT/$1_$2.$EXT" /tmp/photos/$1.jpg ${3:-} 2>&1 | tail -30)"
  else
    say "FAIL $1 export $2: nothing new in the gallery. screen: $(onscreen 10)"
  fi
  # leave the sheet if it is still open; never press Back from the editor itself
  has_text "Save to Gallery" && { adb shell input keyevent KEYCODE_BACK; sleep 1; }
  has_text "Test Ad" && { tap_text "Close"; sleep 2; }
  wait_text "Cut-out" 5 || say "INFO not in editor after export: $(onscreen 8)"; }

SECTIONS=${SECTIONS:-photos,formats,hd,batch}
sec(){ case ",$SECTIONS," in *,$1,*) return 0;; *) return 1;; esac; }
adb wait-for-device
adb uninstall "$PKG" >/dev/null 2>&1
adb install -r "$REL" >/dev/null 2>&1
adb logcat -c
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null
adb shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES 2>/dev/null
launch; sleep 8
for i in 1 2 3; do tap_text "Next"; sleep 1; done
tap_text "Get Started"; sleep 3
for i in 1 2; do tap_text "Allow"; sleep 1; done
wait_text "Gallery" 10 || say "FAIL setup: Home not reached: $(onscreen)"

sec photos && for P in apple messi5 fruits orange butterfly building lena; do
  say "---- $P"
  open_photo $P || continue
  say "INFO $P editor: $(onscreen 18)"
  has_text "doesn't support automatic" && say "FAIL $P app reports: device does not support automatic removal"
  check "$P alive in editor" test -n "$(alive)"
  if [ "$P" = apple ]; then
    shot "${P}_editor"
    for tool in "Brush" "Background" "Layout" "Templates" "Cut-out"; do
      tap_text "$tool"; sleep 1
      check "tool $tool opens and app alive" test -n "$(alive)"
    done
    tap_text "Brush"; sleep 1
    adb shell input swipe 300 700 600 900 400; adb shell input swipe 600 900 300 1100 400
    tap_text "Undo"; sleep 1; tap_text "Redo"; sleep 1
    check "brush drag + undo/redo alive" test -n "$(alive)"
    tap_text "Layout"; sleep 1
    adb shell input swipe 400 800 500 900 300
    check "layout drag alive" test -n "$(alive)"
    tap_text "Cut-out"; sleep 1
  fi
  export_as "$P" PNG --ascii
done

if sec formats; then
say "---- export formats and sizes (apple, each from a fresh editor)"
for fmt in JPG WEBP; do open_photo apple && export_as apple "$fmt"; done
fi
if sec formats && open_photo apple; then
  tap_text "Export"; sleep 2; tap_text "Custom"; sleep 1
  say "INFO custom resize sheet: $(onscreen 24)"
  tap_text "Width"; sleep 1; adb shell input keyevent KEYCODE_MOVE_END; for i in 1 2 3 4 5 6; do adb shell input keyevent KEYCODE_DEL; done; adb shell input text 800; sleep 1
  tap_text "Height"; sleep 1; adb shell input keyevent KEYCODE_MOVE_END; for i in 1 2 3 4 5 6; do adb shell input keyevent KEYCODE_DEL; done; adb shell input text 600; sleep 1
  adb shell input keyevent KEYCODE_ESCAPE; sleep 1
  say "INFO custom sizes typed: $(onscreen 30)"
  adb shell touch /sdcard/marker; sleep 1
  tap_text "Save to Gallery"; sleep 6; has_text "Test Ad" && { tap_text "Close"; sleep 2; }
  F=$(new_files | head -1); if [ -n "$F" ]; then adb exec-out "cat '$F'" > "$OUT/apple_custom.${F##*.}" 2>/dev/null; say "PASS custom-size export saved $(basename "$F")"; say "     $(python3 -W ignore .github/scripts/analyze_cutout.py "$OUT/apple_custom.${F##*.}" 2>&1 | tail -3 | head -1)"; else say "FAIL custom-size export: nothing saved. screen: $(onscreen 14)"; fi
fi
for MP in Amazon eBay; do
  if sec formats && open_photo apple; then
    adb shell touch /sdcard/marker; sleep 1
    tap_text "Export"; sleep 2; tap_text "Marketplace"; sleep 1; tap_text "$MP"; sleep 1
    say "INFO $MP sheet: $(onscreen 18)"
    tap_text "Save to Gallery"; sleep 6; has_text "Test Ad" && { tap_text "Close"; sleep 2; }
    F=$(new_files | head -1)
    if [ -n "$F" ]; then adb exec-out "cat '$F'" > "$OUT/apple_$MP.${F##*.}" 2>/dev/null
      say "PASS marketplace $MP saved $(basename "$F")"; say "     $(python3 -W ignore .github/scripts/analyze_cutout.py "$OUT/apple_$MP.${F##*.}" 2>&1 | tail -3 | head -1)"
    else say "FAIL marketplace $MP: nothing saved"; fi
  fi
done

sec hd && say "---- HD model: real download, then redo in HD (apple, then the portrait)"
for P in apple lena; do
  if sec hd && open_photo $P; then
    tap_text "Cut-out"; sleep 1
    if has_text "Get HD cut-out"; then
      tap_text "Get HD cut-out"; sleep 2
      say "INFO HD dialog: $(onscreen 10)"
      tap_exact "Download"; say "INFO tap Download rc=$?"; HD0=$(date +%s); sleep 3; say "INFO 3s after Download: $(onscreen 12)"
      for i in $(seq 1 120); do has_text "Downloading" || break; sleep 4; done
      say "INFO HD download took ~$(( $(date +%s)-HD0 ))s; screen: $(onscreen 12)"
      has_text "didn" && say "FAIL HD download reported failure"
    fi
    if has_text "Redo cut-out in HD"; then
      tap_text "Redo cut-out in HD"; HD1=$(date +%s); sleep 3
      for i in $(seq 1 60); do sleep 4; has_text "Redo cut-out in HD" && break; done
      say "INFO HD redo took ~$(( $(date +%s)-HD1 ))s"
      check "$P alive after HD redo" test -n "$(alive)"
      export_as "$P" "HD" --ascii
    else
      say "FAIL $P: HD redo button not available after download. screen: $(onscreen 14)"
    fi
  fi
done

if sec batch; then
# Batch: 3 photos at once
say "---- batch"
adb shell 'rm -f /sdcard/Pictures/*.jpg /sdcard/Pictures/*.png'
for P in apple orange fruits; do
  adb push /tmp/photos/$P.jpg /sdcard/Pictures/ps_$P.jpg >/dev/null 2>&1; adb shell touch /sdcard/Pictures/ps_$P.jpg
  adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/ps_$P.jpg >/dev/null 2>&1; sleep 1
done
go_home; sleep 2
adb shell touch /sdcard/marker; sleep 1
tap_text "Batch"; sleep 3
say "INFO batch screen: $(onscreen 12)"
tap_text "Photo taken" >/dev/null 2>&1   # picker may open straight away
sleep 1
for i in 1 2 3; do tap_nth "Photo taken" $i; sleep 1; done
say "INFO batch picker after 3 taps: $(onscreen 16)"
tap_text "Add" || tap_text "Done" || tap_text "Select" || true
sleep 4
say "INFO batch setup screen: $(onscreen 20)"
# where is the Start button?
dump | python3 -c "
import sys,re
for m in re.finditer(r'<node [^>]*>',sys.stdin.read()):
    n=m.group(0)
    if re.search(r'(text|content-desc)=\"(Start|Stop|Done)',n): print('NODE',re.sub(r'\\s+',' ',n)[:200])
" | head -3 | while read -r l; do say "INFO $l"; done
adb shell input swipe 500 1500 500 500 300; sleep 1
tap_text "Start"; sleep 2
say "INFO batch after Start: $(onscreen 40)"
for i in $(seq 1 60); do [ $((i%10)) = 0 ] && say "INFO batch t=$((i*4))s: $(onscreen 40)"; has_text "saved to your gallery" && break; has_text "Test Ad" && { tap_text "Close"; sleep 2; }; sleep 4; done
shot batch_result
say "INFO batch end: $(onscreen 40)"
N=$(new_files | wc -l)
[ "$N" -ge 3 ] && say "PASS batch saved $N real files" || say "FAIL batch saved only $N files"
i=0; new_files | while IFS= read -r F; do i=$((i+1)); EXT="${F##*.}"; adb exec-out "cat '$F'" > "$OUT/batch_$i.$EXT" 2>/dev/null
  say "     batch_$i ($(basename "$F")): $(python3 -W ignore .github/scripts/analyze_cutout.py "$OUT/batch_$i.$EXT" 2>&1 | tail -22)"; done

fi

C=$(crashes); [ -z "$C" ] && say "PASS 99 no app crash/ANR in the whole run" || say "FAIL 99 $C"
adb logcat -d -v threadtime | grep -E "E flutter|F flutter|APPERR|Process: $PKG|ANR in $PKG|Gal save|Gal\.|GalException|export failed|Export failed|Segmentation|segmentation|HD " | cut -c7-260 | head -n 40 > /tmp/errs.txt
{ echo "=== PHOTO RESULTS ==="; cat $R; echo "=== flutter/app errors ==="; cat /tmp/errs.txt; } > /tmp/final.txt
cp /tmp/final.txt "$OUT/results.txt"
cat /tmp/final.txt
python3 - <<'PY'
t=open('/tmp/final.txt').read()
esc=lambda s:s.replace('%','%25').replace('\r','%0D').replace('\n','%0A')
ch=[];cur=''
for l in t.split('\n'):
    if len(cur)+len(l)+1>3400: ch.append(cur);cur=''
    cur+=l+'\n'
ch.append(cur)
for i,c in enumerate(ch[:9],1): print(f"::notice title=PHOTOS {i}/{len(ch)}::{esc(c)}")
PY
