"""Classify probe frames (tools/lua/txr_upload.lua's log.txt): renderer upload (first pattern
write at line >= 249.9: the uploader, not the game's CHR animation), text
cells flushed, publish-only.  Usage: classify.py log first last"""
import re
import sys

path, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
cls = {}
tiles = 0
seq = []
for line in open(path):
    f = int(line.split()[0])
    if not a <= f <= b:
        continue
    m = re.search(r"pat=(\d+) .*patfirst=(\S+) .*txt=(\d+)", line)
    pat, pf, txt = int(m.group(1)), m.group(2), int(m.group(3))
    up = pat > 0 and pf != "-" and float(pf) >= 249.9
    pub = " pub" in line
    if up:
        tiles += pat // 8
    if up and txt:
        c = "U+F"
    elif up:
        c = "U"
    elif txt:
        c = "F"
    elif pub:
        c = "P"
    else:
        c = "."
    cls[c] = cls.get(c, 0) + 1
    seq.append(c if c != "U+F" else "B")
print(f"frames {a}-{b}: {cls}  renderer tiles {tiles}")
print("".join(x[0] for x in seq))
