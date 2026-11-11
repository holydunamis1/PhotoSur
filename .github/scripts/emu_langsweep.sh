#!/usr/bin/env bash
APK=app/build/app/outputs/flutter-apk/app-debug.apk
adb wait-for-device
adb install -r "$APK" > /dev/null 2>&1
python3 .github/scripts/emu_langsweep.py 2>&1 | tee /tmp/sweep.txt
rc=${PIPESTATUS[0]}
i=0; grep -v '^$' /tmp/sweep.txt | split -l 25 - /tmp/sweep_part_
for f in /tmp/sweep_part_*; do i=$((i+1)); echo "::notice title=sweep part $i::$(cat $f | tr '\n' '|' | cut -c1-3500)"; done
exit $rc
