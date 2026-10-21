"""Numbers about one exported image, printed on one line.
usage: analyze_cutout.py exported_file [source_photo]
Judges a cut-out without eyes: how much is transparent, where the subject
sits, whether it is one solid blob or scattered fragments, edge softness."""
import sys
from PIL import Image
if len(sys.argv)>2 and sys.argv[1]=="--shot":
    # brightness picture of a screenshot, 44x30 characters
    im=Image.open(sys.argv[2]).convert("L").resize((44,30))
    ramp=" .:-=+*#%@"
    px=list(im.getdata())
    for y in range(30): print("".join(ramp[min(9,px[y*44+x]*10//256)] for x in range(44)))
    sys.exit(0)
ascii_mask = "--ascii" in sys.argv
sys.argv=[a for a in sys.argv if a!="--ascii"]
p=sys.argv[1]
try:
    im=Image.open(p); fmt=im.format; im.load()
except Exception as e:
    print(f"UNREADABLE {p}: {e}"); sys.exit(0)
w,h=im.size
out=[f"fmt={fmt}",f"size={w}x{h}"]
if sys.argv[2:]:
    try:
        s=Image.open(sys.argv[2]); out.append(f"source={s.size[0]}x{s.size[1]}")
    except Exception: pass
if im.mode in("RGBA","LA") or "transparency" in im.info:
    a=im.convert("RGBA").split()[3]
    g=a.resize((64,64))
    px=list(g.getdata())
    tr=sum(1 for v in px if v<16)/len(px); op=sum(1 for v in px if v>239)/len(px)
    soft=1-tr-op
    grid=[[px[y*64+x]>=128 for x in range(64)] for y in range(64)]
    seen=[[False]*64 for _ in range(64)]; comps=[]
    for y in range(64):
        for x in range(64):
            if grid[y][x] and not seen[y][x]:
                st=[(x,y)]; seen[y][x]=True; n=0
                while st:
                    cx,cy=st.pop(); n+=1
                    for dx,dy in((1,0),(-1,0),(0,1),(0,-1)):
                        nx,ny=cx+dx,cy+dy
                        if 0<=nx<64 and 0<=ny<64 and grid[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx]=True; st.append((nx,ny))
                comps.append(n)
    comps.sort(reverse=True)
    big=comps[0] if comps else 0; tot=sum(comps) or 1
    bb=a.point(lambda v:255 if v>=128 else 0).getbbox()
    out+= [f"transparent={tr:.0%}",f"opaque={op:.0%}",f"soft_edge={soft:.0%}",
           f"blobs={len(comps)}",f"largest_blob_share={big/tot:.0%}",
           f"bbox={'none' if not bb else f'{bb[0]*100//w}%-{bb[2]*100//w}% x {bb[1]*100//h}%-{bb[3]*100//h}%'}"]
    if ascii_mask:
        m=a.resize((40,20)); mp=list(m.getdata())
        rows=["".join("#" if mp[y*40+x]>=200 else "+" if mp[y*40+x]>=100 else "." if mp[y*40+x]>=20 else " " for x in range(40)) for y in range(20)]
        out.append("\nMASK (# kept, space removed)\n|"+"|\n|".join(rows)+"|")
    if tr<0.02: out.append("VERDICT=NOTHING REMOVED")
    elif op<0.03: out.append("VERDICT=EVERYTHING REMOVED")
    elif big/tot<0.7: out.append("VERDICT=FRAGMENTED")
    else: out.append("VERDICT=ok-looking")
else:
    out.append("no-alpha (flat background export)")
print(" ".join(out))
