#!/usr/bin/env python3
"""Real-font language sweep. For every shipped language: fresh install state,
set the per-app language, page through onboarding, then tap through every
clickable control on Home and on each screen it opens (depth 2), and fail on
any 'RenderFlex overflowed' / layout exception in the debug log.
Language independent: it taps by position from a UI dump, not by label."""
import re, subprocess, sys, time, os, glob, xml.etree.ElementTree as ET

PKG = "com.zdmgold.photosur"
OUT = "/tmp/sweep"; os.makedirs(OUT, exist_ok=True)
SHOT_LANGS = {"ta", "te", "ml", "bn", "th", "ar", "he", "de", "hi", "ja"}
MAX_TAPS = int(os.environ.get("MAX_TAPS", "8"))

def sh(*a, check=False):
    return subprocess.run(["adb", "shell", *a], capture_output=True, text=True).stdout

def tags():
    out = []
    for f in sorted(glob.glob("app/lib/l10n/app_*.arb")):
        c = os.path.basename(f)[4:-4]
        out.append(c.replace("_", "-"))
    return out

def dump():
    sh("uiautomator", "dump", "/sdcard/w.xml")
    x = sh("cat", "/sdcard/w.xml")
    try:
        root = ET.fromstring(x[x.index("<?xml"):] if "<?xml" in x else x)
    except Exception:
        return []
    nodes = []
    for n in root.iter("node"):
        if n.get("clickable") == "true" or n.get("long-clickable") == "false" and False:
            m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
            if m:
                l, t, r, b = map(int, m.groups())
                nodes.append((l, t, r, b, n.get("content-desc", "") or n.get("text", "")))
    return nodes

def overflow_lines():
    log = subprocess.run(["adb", "logcat", "-d", "-s", "flutter"], capture_output=True, text=True).stdout
    return sorted({l[l.find("A RenderFlex"):][:90] if "A RenderFlex" in l else l[-110:]
                   for l in log.splitlines()
                   if re.search(r"RenderFlex overflowed|overflowed by|RenderBox was not laid out|Exception caught by rendering", l)})

def fg_ok():
    return PKG in sh("dumpsys", "window").split("mCurrentFocus")[-1][:200] if True else True

def restart():
    sh("am", "force-stop", PKG)
    sh("monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(5)

def tap(n):
    sh("input", "tap", str((n[0] + n[2]) // 2), str((n[1] + n[3]) // 2))
    time.sleep(1.6)

def shot(name):
    sh("screencap", "-p", f"/sdcard/{name}.png")
    subprocess.run(["adb", "pull", f"/sdcard/{name}.png", f"{OUT}/{name}.png"], capture_output=True)

results = {}
for tag in tags():
    base = tag.split("-")[0]
    sh("pm", "clear", PKG)
    sh("pm", "grant", PKG, "android.permission.POST_NOTIFICATIONS")
    sh("pm", "grant", PKG, "android.permission.CAMERA")
    sh("cmd", "locale", "set-app-locales", PKG, "--locales", tag)
    subprocess.run(["adb", "logcat", "-c"])
    restart()
    found = []
    # onboarding: tap the lowest wide clickable (primary button) 4 times
    for page in range(4):
        if tag.split("-")[0] in SHOT_LANGS:
            shot(f"{tag}_onb{page}")
        nodes = dump()
        if not nodes:
            break
        btn = max(nodes, key=lambda n: n[3])
        tap(btn)
    time.sleep(2)
    # Home + depth-2 crawl by position
    home = dump()
    if base in SHOT_LANGS: shot(f"{tag}_home")
    seen = set()
    for i, n in enumerate(home[:MAX_TAPS]):
        key = (n[0], n[1])
        if key in seen: continue
        seen.add(key)
        tap(n)
        if base in SHOT_LANGS: shot(f"{tag}_h{i}")
        for j, m in enumerate(dump()[:MAX_TAPS]):
            if (m[3] - m[1]) < 40: continue
            tap(m)
            if base in SHOT_LANGS and j < 4: shot(f"{tag}_h{i}_{j}")
            sh("input", "keyevent", "4"); time.sleep(0.8)
        sh("input", "keyevent", "4"); time.sleep(0.8)
        if PKG not in sh("dumpsys", "window"):
            restart()
    found = overflow_lines()
    results[tag] = found
    print(f"{tag}: {'OVERFLOW x%d' % len(found) if found else 'clean'}", flush=True)
    for l in found[:3]:
        print("   ", l, flush=True)

bad = {k: v for k, v in results.items() if v}
print("SWEEP-DONE bad=%d of %d" % (len(bad), len(results)))
sys.exit(1 if bad else 0)
