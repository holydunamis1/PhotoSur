#!/usr/bin/env bash
# Extra coverage sections, sourced by emu_photos.sh (needs its helpers):
#   edit, bg, interrupt, large, exportedge, screens, sizes, camera, notif
# Run with EMU_SECTIONS=edit,bg,... Each prints PASS / FAIL / INFO lines.

gt(){ awk "BEGIN{exit !($1 > $2)}"; }          # gt 1.5 0.5 -> true
lt(){ awk "BEGIN{exit !($1 < $2)}"; }
screen_size(){ read SW SH < <(adb shell wm size | tail -1 | grep -o '[0-9]*x[0-9]*' | tr x ' '); }
px(){ echo $(( SW * $1 / 100 )); }              # x at N percent of the width
py(){ echo $(( SH * $1 / 100 )); }              # y at N percent of the height
snap(){ adb exec-out screencap -p > "/tmp/snap_$1.png" 2>/dev/null; }
# percent of canvas-band pixels that differ clearly between two screenshots
diffpct(){ python3 -W ignore - "/tmp/snap_$1.png" "/tmp/snap_$2.png" <<'PY'
from PIL import Image, ImageChops
import sys
try:
    a=Image.open(sys.argv[1]).convert('RGB'); b=Image.open(sys.argv[2]).convert('RGB')
    if a.size!=b.size: print('100.0'); sys.exit()
    W,H=a.size; box=(0,int(H*.12),W,int(H*.70))
    d=ImageChops.difference(a.crop(box),b.crop(box)).convert('L').point(lambda v:255 if v>24 else 0)
    n=sum(1 for v in d.getdata() if v); print('%.2f'%(100.0*n/(d.size[0]*d.size[1])))
except Exception as e:
    print('0.00')
PY
}
brightness(){ python3 -W ignore - "/tmp/snap_$1.png" <<'PY'
from PIL import Image
import sys
im=Image.open(sys.argv[1]).convert('L'); print('%.1f'%(sum(im.getdata())/(im.size[0]*im.size[1])))
PY
}
airplane(){ adb shell cmd connectivity airplane-mode "$1" >/dev/null 2>&1; }
in_editor(){ has_text "Cut-out" && has_text "Export"; }
strokes(){ # drag several lines across the middle of the canvas
  for p in 28 33 38 43 48 53; do adb shell input swipe $(px 18) $(py $p) $(px 82) $(py $p) 250; done; }
swipe_node(){ # label, from%, to% : drag along the node's own width
  dump | python3 -c "
import sys,re,subprocess
x=sys.stdin.read(); t=sys.argv[1].lower(); f=int(sys.argv[2]); e=int(sys.argv[3])
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    d=re.search(r'content-desc=\"([^\"]*)\"',n); tx=re.search(r' text=\"([^\"]*)\"',n)
    b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',n)
    if b and any(v and t in v.group(1).lower() for v in (d,tx)):
        x1,y1,x2,y2=map(int,b.groups()); w=x2-x1; y=(y1+y2)//2
        subprocess.call(['adb','shell','input','swipe',str(x1+w*f//100),str(y),str(x1+w*e//100),str(y),'400']); sys.exit(0)
sys.exit(1)" "$1" "$2" "$3"; }
seekbar(){ # k from% to% : drag the k-th slider on screen along its own width
  dump | python3 -c "
import sys,re,subprocess
x=sys.stdin.read(); k=int(sys.argv[1]); f=int(sys.argv[2]); e=int(sys.argv[3]); c=0
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    if 'android.widget.SeekBar' in n:
        c+=1
        if c==k:
            b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',n)
            x1,y1,x2,y2=map(int,b.groups()); w=x2-x1; y=(y1+y2)//2
            print('seekbar',k,x1,y1,x2,y2)
            subprocess.call(['adb','shell','input','swipe',str(x1+w*f//100),str(y),str(x1+w*e//100),str(y),'500']); sys.exit(0)
print('no seekbar',k,'of',c); sys.exit(1)" "$1" "$2" "$3"; }
tap_class(){ dump | python3 -c "
import sys,re,subprocess
x=sys.stdin.read()
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    if sys.argv[1] in n:
        b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',n)
        x1,y1,x2,y2=map(int,b.groups()); subprocess.call(['adb','shell','input','tap',str((x1+x2)//2),str((y1+y2)//2)]); sys.exit(0)
sys.exit(1)" "$1"; }
fresh_install(){
  adb uninstall "$PKG" >/dev/null 2>&1; adb install -r "$REL" >/dev/null 2>&1
  adb shell pm grant "$PKG" android.permission.READ_MEDIA_IMAGES 2>/dev/null
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null
  launch; sleep 8
  for i in 1 2 3; do tap_text "Next"; sleep 1; done; tap_text "Get Started"; sleep 3
  for i in 1 2; do tap_text "Allow"; sleep 1; done; }

screen_size
say "INFO screen ${SW}x${SH}"

# ---------------------------------------------------------------- edit
if sec edit && open_photo apple; then
  say "---- editing results (does each tool really change the picture?)"
  snap e0
  tap_text "Brush"; sleep 1; say "INFO brush panel: $(onscreen 24)"
  tap_exact "Erase"; sleep 1
  strokes; sleep 1; snap e1
  D=$(diffpct e0 e1); say "INFO erase strokes changed $D% of the canvas"
  check "erase brush changes the picture" gt "$D" 0.4
  for i in 1 2 3 4 5 6 7 8; do tap_text "Undo"; sleep 0.5; done; sleep 1; snap e2
  D2=$(diffpct e0 e2); say "INFO after undo x8: $D2% differs from the start"
  check "undo brings the picture back" lt "$D2" 3.5
  for i in 1 2 3 4 5 6 7 8; do tap_text "Redo"; sleep 0.5; done; sleep 1; snap e3
  D3=$(diffpct e1 e3); say "INFO after redo x8: $D3% differs from the erased version"
  check "redo re-applies the strokes" lt "$D3" 3.5
  tap_exact "Restore"; sleep 1; strokes; sleep 1; snap e4
  D4=$(diffpct e0 e4); say "INFO erase then restore: $D4% differs from the start (was $D% after erase)"
  check "restore brush paints the subject back" lt "$D4" "$D"
  tap_text "Reset"; sleep 2; say "INFO after Reset tap: $(onscreen 12)"
  has_text "Reset" && has_text "Cancel" && { tap_exact "Reset"; sleep 2; }
  snap e5; D5=$(diffpct e0 e5); say "INFO after Reset: $D5% differs from the start"
  check "reset returns to the first cut-out" lt "$D5" 3.5
  check "alive after the brush work" test -n "$(alive)"

  tap_text "Layout"; sleep 1; say "INFO layout panel: $(onscreen 20)"
  snap l0
  adb shell input swipe $(px 50) $(py 40) $(px 72) $(py 55) 400; sleep 1; snap l1
  D=$(diffpct l0 l1); say "INFO layout drag moved $D%"; check "layout drag moves the subject" gt "$D" 0.3
  tap_text "Auto-center"; sleep 2; snap l2; D=$(diffpct l1 l2); say "INFO auto-center moved $D%"
  check "auto-center moves it back" gt "$D" 0.2
  say "INFO $(seekbar 2 5 95)"; sleep 2; snap l3; D=$(diffpct l2 l3); say "INFO shadow slider moved: canvas changed $D%"
  check "shadow slider changes the picture" gt "$D" 0.2
  say "INFO $(seekbar 1 95 20)"; sleep 2; snap l4; D=$(diffpct l3 l4); say "INFO size slider moved: canvas changed $D%"
  check "size slider changes the picture" gt "$D" 0.3
  check "alive after layout work" test -n "$(alive)"
  export_as apple EDITED --ascii
fi

# ---------------------------------------------------------------- bg
if sec bg && open_photo apple; then
  say "---- backgrounds"
  tap_text "Background"; sleep 2; say "INFO background panel: $(onscreen 30)"
  snap b_0; PREV=b_0
  for L in White Black Blur Transparent White; do
    tap_exact "$L"; sleep 2
    if [ "$L" = Blur ]; then sleep 6; say "INFO blur selected: $(onscreen 30)"; say "INFO $(seekbar 1 5 95)"; sleep 5; fi
    snap "b_$L"
    D=$(diffpct $PREV "b_$L"); say "INFO background $L changed $D% vs the previous one"
    check "background $L changes the canvas" gt "$D" 0.3
    PREV="b_$L"
  done
  tap_text "Custom color"; sleep 2; say "INFO custom colour sheet: $(onscreen 24)"
  snap b_cc; adb shell input tap $(px 30) $(py 70); sleep 1; adb shell input tap $(px 75) $(py 60); sleep 1
  adb shell input keyevent KEYCODE_BACK; sleep 1; snap b_cc2
  say "INFO colour picked: canvas changed $(diffpct b_White b_cc2)%"
  check "alive after custom colour" test -n "$(alive)"
  in_editor || { adb shell input keyevent KEYCODE_BACK; sleep 1; }
  fresh_photo orange
  tap_text "Add custom background"; sleep 4; say "INFO after Add custom background: $(onscreen 12)"
  tap_text "Photo taken" || adb shell input tap 200 600; sleep 5
  has_text "Continue" && { tap_text "Continue"; sleep 4; }
  snap b_photo; D=$(diffpct b_cc2 b_photo)
  say "INFO own photo as background changed $D%"; check "own photo becomes the background" gt "$D" 5
  tap_text "Templates"; sleep 3; say "INFO templates: $(onscreen 30)"
  adb shell input tap $(px 25) $(py 40); sleep 3; snap b_tpl
  say "INFO a template tapped: changed $(diffpct b_photo b_tpl)%; screen $(onscreen 12)"
  check "alive after templates" test -n "$(alive)"
  has_text "Export" || { adb shell input keyevent KEYCODE_BACK; sleep 1; }
  export_as apple BG --ascii
fi

# ---------------------------------------------------------------- interrupt
if sec interrupt; then
  say "---- interruptions"
  if open_photo apple; then
    # phone call while editing
    adb emu gsm call 5551234 >/dev/null 2>&1; sleep 6
    check "alive during an incoming call" test -n "$(alive)"
    adb emu gsm cancel 5551234 >/dev/null 2>&1; sleep 3
    check "still in the editor after the call" in_editor
    # rotate in the editor and with the export sheet open
    adb shell settings put system accelerometer_rotation 0
    adb shell settings put system user_rotation 1; sleep 3
    check "editor survives rotating to landscape" in_editor
    tap_text "Export"; sleep 2
    adb shell settings put system user_rotation 0; sleep 3
    check "export sheet survives rotating back" has_text "Save to Gallery"
    # leave the app during the save
    adb shell touch /sdcard/marker; sleep 1
    tap_text "Save to Gallery"; sleep 0.5; adb shell input keyevent KEYCODE_HOME; sleep 8
    launch; sleep 5
    check "alive after leaving during the save" test -n "$(alive)"
    F=$(new_files | head -1); [ -n "$F" ] && say "PASS the save finished while in the background: $(basename "$F")" || say "INFO nothing saved when leaving during the save (screen: $(onscreen 8))"
    has_text "Test Ad" && { tap_text "Close"; sleep 2; }
    # kill the app while editing, then relaunch
    adb shell am force-stop "$PKG"; sleep 1; launch; sleep 6
    check "relaunch after a kill lands on a usable Home" has_text "Gallery"
  fi
  # HD download interrupted by losing the network (fresh install: it starts by itself)
  say "---- HD download with the network cut"
  fresh_install; fresh_photo lena
  airplane enable; sleep 3
  tap_text "Gallery"; sleep 4; tap_text "Photo taken" || adb shell input tap 200 600; sleep 5
  wait_text "Continue" 10 && tap_text "Continue"; wait_text "Export" 40; sleep 12
  say "INFO network off while the editor opened: $(onscreen 18)"
  if has_text "didn"; then say "PASS download failure message appears when there is no network"; else say "FAIL no failure message with no network"; fi
  check "alive with the download failed" test -n "$(alive)"
  check "photo still editable (standard cut-out kept)" in_editor
  airplane disable; sleep 8
  if has_text "Get HD cut-out"; then
    tap_text "Get HD cut-out"; sleep 2; tap_exact "Download"; sleep 2
    say "INFO retry started: $(onscreen 12)"
    for i in $(seq 1 120); do has_text "Redo cut-out in HD" && break; sleep 4; done
    if has_text "Redo cut-out in HD"; then say "PASS manual retry after a failure completes"; else say "FAIL manual retry did not complete: $(onscreen 14)"; fi
  else say "FAIL no Get HD button after the failure: $(onscreen 14)"; fi
  # slow network: progress must move, and cutting it mid-way must fail cleanly
  adb shell pm clear "$PKG" >/dev/null 2>&1
  fresh_install; fresh_photo lena
  adb emu network speed gsm >/dev/null 2>&1; adb emu network delay gsm >/dev/null 2>&1
  tap_text "Gallery"; sleep 4; tap_text "Photo taken" || adb shell input tap 200 600; sleep 5
  wait_text "Continue" 10 && tap_text "Continue"; wait_text "Export" 40; sleep 15
  say "INFO slow network, 15s in: $(onscreen 18)"
  has_text "in progress" && say "PASS progress shown on a slow network" || say "INFO no progress text on the slow network"
  airplane enable; sleep 45
  say "INFO network cut mid-download: $(onscreen 18)"
  has_text "didn" && say "PASS cut mid-download ends in the failure message" || say "FAIL no failure message after cutting mid-download"
  check "alive after the mid-download cut" test -n "$(alive)"
  airplane disable; adb emu network speed full >/dev/null 2>&1; adb emu network delay none >/dev/null 2>&1; sleep 5

  # batch: leave the app while it runs
  say "---- batch interrupted"
  adb shell 'rm -f /sdcard/Pictures/*.jpg /sdcard/Pictures/*.png'
  for P in apple orange fruits; do
    adb push /tmp/photos/$P.jpg /sdcard/Pictures/ps_$P.jpg >/dev/null 2>&1; adb shell touch /sdcard/Pictures/ps_$P.jpg
    adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/ps_$P.jpg >/dev/null 2>&1; sleep 1
  done
  go_home; adb shell touch /sdcard/marker; sleep 1
  tap_text "Batch"; sleep 3; tap_text "Photo taken" >/dev/null 2>&1; sleep 1
  for i in 1 2 3; do tap_nth "Photo taken" $i; sleep 1; done
  tap_text "Add" || tap_text "Done" || tap_text "Select" || true; sleep 4
  adb shell input swipe 500 1500 500 500 300; sleep 1
  tap_text "Start"; sleep 6
  say "INFO batch running: $(onscreen 30)"
  adb shell input keyevent KEYCODE_HOME; sleep 12; launch; sleep 4
  say "INFO batch after coming back: $(onscreen 30)"
  for i in $(seq 1 60); do has_text "saved to your gallery" && break; has_text "Test Ad" && { tap_text "Close"; sleep 2; }; sleep 4; done
  N=$(new_files | wc -l); say "INFO batch with a background break saved $N files; screen: $(onscreen 14)"
  [ "$N" -ge 3 ] && say "PASS batch finished all 3 despite leaving the app" || say "FAIL batch interrupted: only $N of 3 saved"
fi

# ---------------------------------------------------------------- large
if sec large; then
  say "---- large, small and odd photos"
  python3 -W ignore - <<'PY'
from PIL import Image
a=Image.open('/tmp/photos/apple.jpg').convert('RGB')
def noisy(size):
    big=a.resize(size,Image.LANCZOS)
    n=Image.effect_noise(size,25).convert('RGB')
    return Image.blend(big,n,0.12)
Image.MAX_IMAGE_PIXELS=None
noisy((8000,6000)).save('/tmp/photos/big8k.jpg',quality=92)
noisy((12000,9000)).save('/tmp/photos/huge108.jpg',quality=88)
noisy((12000,1500)).save('/tmp/photos/pano.jpg',quality=90)
noisy((1500,12000)).save('/tmp/photos/tall.jpg',quality=90)
a.resize((64,64)).save('/tmp/photos/tiny.jpg')
a.resize((320,240)).save('/tmp/photos/small.jpg')
noisy((3000,3000)).save('/tmp/photos/square3k.jpg',quality=92)
r=a.resize((1200,900)).convert('RGBA'); px=r.load()
for y in range(900):
    for x in range(1200):
        if x<300 and y<300: px[x,y]=(255,0,0,0)
r.save('/tmp/photos/alpha.png')
print('generated')
PY
  ls -la /tmp/photos | awk '{print $5, $9}' | tr '\n' ' ' | sed 's/^/INFO photo sizes: /' | tee -a $R
  for P in tiny small alpha square3k pano tall big8k huge108; do
    say "---- $P"; T0=$(date +%s)
    EDITOR_WAIT=150 open_photo $P || { check "$P alive after failing to open" test -n "$(alive)"; has_text "Export" || go_home; continue; }
    say "INFO $P reached the editor in ~$(( $(date +%s)-T0 ))s (includes the 5s+12s waits)"
    check "$P alive in editor" test -n "$(alive)"
    export_as "$P" PNG
    C=$(crashes); [ -n "$C" ] && say "FAIL crash/ANR after $P: $C"
  done
fi

# ---------------------------------------------------------------- exportedge
if sec exportedge; then
  say "---- export edge cases (the app returns to Home after every save, by design)"
  for n in 1 2 3 4; do open_photo apple && export_as apple "REPEAT$n"; done
  go_home
  say "INFO home with exports: $(onscreen 16)"
  if has_text "See all"; then
    tap_text "Today" || adb shell input tap $(px 20) $(py 40); sleep 3
    say "INFO export viewer: $(onscreen 16)"
    check "export viewer opens" test -n "$(alive)"
    adb shell input swipe $(px 80) $(py 50) $(px 20) $(py 50) 300; sleep 2
    adb shell input swipe $(px 20) $(py 50) $(px 80) $(py 50) 300; sleep 2
    tap_text "Share"; sleep 3; say "INFO after Share: $(onscreen 10)"
    check "alive after tapping Share" test -n "$(alive)"
    adb shell input keyevent KEYCODE_BACK; sleep 2      # closes the share sheet
    has_text "Share" && { tap_text "Close"; sleep 2; }  # then the viewer
    tap_text "See all"; sleep 3; say "INFO all exports: $(onscreen 16)"
    check "See all opens" has_text "Select"
    tap_text "Select"; sleep 1; adb shell input tap $(px 20) $(py 22); sleep 1
    say "INFO selecting: $(onscreen 12)"
    tap_text "Delete"; sleep 2; say "INFO delete dialog: $(onscreen 10)"
    tap_exact "Delete"; sleep 3
    say "INFO after deleting one: $(onscreen 12)"
    check "alive after deleting" test -n "$(alive)"
    tap_nth "More options" 1; sleep 2; say "INFO more options menu: $(onscreen 10)"
    tap_text "Delete all exports"; sleep 2; say "INFO delete-all dialog: $(onscreen 10)"; tap_exact "Delete"; sleep 3
    adb shell input keyevent KEYCODE_BACK; sleep 2
    say "INFO back on Home: $(onscreen 12)"
    check "empty state returns after deleting everything" has_text "Tap Camera or Gallery to start"
  else say "FAIL no See all on Home after four exports: $(onscreen 14)"; fi
fi

# ---------------------------------------------------------------- screens
if sec screens; then
  say "---- Help, Settings, language and theme"
  go_home
  tap_text "Help"; sleep 3; say "INFO help: $(onscreen 10)"
  for i in $(seq 1 14); do adb shell input swipe $(px 50) $(py 80) $(px 50) $(py 25) 300; done
  check "help scrolls to the end without a crash" test -n "$(alive)"
  adb shell input keyevent KEYCODE_BACK; sleep 2
  tap_text "Settings"; sleep 3; say "INFO settings: $(onscreen 30)"
  tap_text "Animated home background"; sleep 1; say "INFO animated background toggled off"
  adb shell input keyevent KEYCODE_BACK; sleep 2
  has_text "Gallery" && snap s_off
  tap_text "Settings"; sleep 2; tap_text "Animated home background"; sleep 1
  adb shell input keyevent KEYCODE_BACK; sleep 2
  check "settings switch round trip alive" has_text "Gallery"
  # theme
  tap_text "Theme"; sleep 2; tap_exact "Light"; sleep 3; snap s_light
  tap_text "Theme"; sleep 2; tap_exact "Dark"; sleep 3; snap s_dark
  BL=$(brightness s_light); BD=$(brightness s_dark); say "INFO mean brightness light=$BL dark=$BD"
  check "light theme is brighter than dark" gt "$BL" "$BD"
  # large system text
  adb shell settings put system font_scale 2.0; sleep 1; adb shell am force-stop "$PKG"; launch; sleep 6
  check "Home usable at 200% text size" has_text "Gallery"
  snap s_big; say "INFO 200% text Home: $(onscreen 14)"
  if open_photo apple; then
    check "editor usable at 200% text size" in_editor
    tap_text "Export"; sleep 2; check "export sheet usable at 200% text size" has_text "Save to Gallery"
    say "INFO 200% export sheet: $(onscreen 20)"
  fi
  adb shell settings put system font_scale 1.0
  # animations off (reduce motion)
  adb shell settings put global animator_duration_scale 0; adb shell settings put global transition_animation_scale 0
  go_home; check "Home with animations off" has_text "Gallery"
  adb shell settings put global animator_duration_scale 1; adb shell settings put global transition_animation_scale 1
  # language, including right-to-left (the Language button is named in each language)
  tap_lang(){ # name of the Language button in the current language, English search word, native name of the row
    tap_text "$1" || { say "INFO no Language button named '$1'"; return 1; }; sleep 2
    say "INFO language sheet: $(onscreen 14)"
    tap_class "android.widget.EditText"; sleep 1; adb shell input text "$2"; sleep 2
    tap_text "$3" || { say "INFO row '$3' not found after searching '$2': $(onscreen 14)"; adb shell input keyevent KEYCODE_BACK; sleep 1; adb shell input keyevent KEYCODE_BACK; return 1; }; sleep 3; }
  for trio in "Language|German|Deutsch" "Sprache|Japanese|日本語" "言語|Hindi|हिन्दी" "भाषा|Arabic|العربية" "اللغة|English|English"; do
    IFS='|' read -r BTN Q TO <<<"$trio"
    if tap_lang "$BTN" "$Q" "$TO"; then say "PASS switched to $TO: $(onscreen 8)"; else say "FAIL could not switch to $TO"; fi
    check "Home alive after switching to $TO" test -n "$(alive)"
  done
  check "back to English Home" has_text "Gallery"
  fresh_install
fi

# ---------------------------------------------------------------- sizes
if sec sizes; then
  say "---- screen sizes"
  for M in "480x800 240" "720x1280 320" "1600x2560 320" "1080x2400 420"; do
    set -- $M; adb shell wm size $1; adb shell wm density $2; sleep 2
    go_home
    check "Home at $1 density $2" has_text "Gallery"
    if open_photo apple; then
      check "editor at $1" in_editor
      tap_text "Export"; sleep 2
      check "export sheet at $1 shows Save to Gallery" has_text "Save to Gallery"
      adb shell input keyevent KEYCODE_BACK; sleep 1
    fi
  done
  adb shell wm size reset; adb shell wm density reset
fi

# ---------------------------------------------------------------- camera
if sec camera; then
  say "---- camera"
  adb shell pm grant "$PKG" android.permission.CAMERA 2>/dev/null
  go_home; screen_size
  tap_text "Camera"; sleep 5; say "INFO camera screen: $(onscreen 12)"
  has_text "No camera found" && say "FAIL camera: no camera found on the emulator"
  has_text "Could not start" && say "FAIL camera: could not start"
  check "camera screen alive" test -n "$(alive)"
  adb shell input tap $(px 50) $(py 88); sleep 5
  say "INFO after shutter: $(onscreen 12)"
  if wait_text "Continue" 10; then say "PASS the camera took a photo and reached the crop screen"
    tap_text "Continue"; wait_text "Export" 40 && say "PASS camera photo reached the editor" || say "FAIL camera photo never reached the editor: $(onscreen 10)"
  else say "FAIL camera: no crop screen after the shutter: $(onscreen 14)"; fi
  adb shell pm revoke "$PKG" android.permission.CAMERA 2>/dev/null
  go_home; tap_text "Camera"; sleep 4
  say "INFO camera without permission: $(onscreen 14)"
  check "camera permission denied is handled" test -n "$(alive)"
fi

# ---------------------------------------------------------------- notif
if sec notif; then
  say "---- unfinished-edit reminder"
  if open_photo apple; then
    adb shell input keyevent KEYCODE_HOME; sleep 4
    A=$(adb shell dumpsys alarm | grep -c "$PKG")
    say "INFO alarms registered for the app after leaving an unexported edit: $A"
    [ "$A" -ge 1 ] && say "PASS a reminder is scheduled after leaving an edit" || say "FAIL no reminder scheduled after leaving an edit"
    launch; sleep 4
  fi
fi
