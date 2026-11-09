#!/usr/bin/env python3
"""Compare two screen_digest.lua logs (A = reference build, B = test build).

Usage: python -I tools/sd_compare.py A.txt B.txt
Prints the frames whose NTSC picture (lines 8-231) differs, the frames
that differ only in the overscan lines (0-7, 232-239), and the same for the
BG digest from the nametables (sprites cannot disturb it), and finally the
sequences of distinct BG states, which tolerate the builds drifting a frame
apart (the exit code follows this last check).
"""
import sys


def load(p):
    out = {}
    for line in open(p):
        f, h0, h1, h2, sx, sy, ctrl, bh, be = line.split()
        out[int(f)] = (h0, h1, h2, sx, sy, ctrl, bh, be)
    return out


def runs(fs):
    fs = sorted(fs)
    out, s, prev = [], None, None
    for f in fs:
        if s is None:
            s = prev = f
        elif f == prev + 1:
            prev = f
        else:
            out.append((s, prev)); s = prev = f
    if s is not None:
        out.append((s, prev))
    return ", ".join(f"{a}" if a == b else f"{a}-{b}" for a, b in out)


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    common = sorted(set(a) & set(b))
    pic = [f for f in common if a[f][1] != b[f][1]]
    over = [f for f in common if a[f][1] == b[f][1] and (a[f][0] != b[f][0] or a[f][2] != b[f][2])]
    scroll = [f for f in common if a[f][3:5] != b[f][3:5]]
    bg = [f for f in common if a[f][6] != b[f][6]]
    bge = [f for f in common if a[f][6] == b[f][6] and a[f][7] != b[f][7]]
    print(f"frames compared {len(common)}")
    print(f"picture (lines 8-231) differs: {len(pic)}  {runs(pic)}")
    print(f"overscan only differs: {len(over)}  {runs(over)}")
    print(f"scroll differs: {len(scroll)}  {runs(scroll)}")
    print(f"BG nametable cells, screen rows 1-28, differ: {len(bg)}  {runs(bg)}")
    print(f"BG differs only in screen rows 0/29: {len(bge)}  {runs(bge)}")
    # The builds' main threads can drift a frame apart (different cycle
    # counts in a task); compare the sequences of distinct BG states.
    def seq(d):
        out = []
        for f in sorted(d):
            if not out or out[-1][0] != d[f][6]:
                out.append((d[f][6], f))
        return out
    sa, sb = seq(a), seq(b)
    import difflib
    sm = difflib.SequenceMatcher(a=[x[0] for x in sa], b=[x[0] for x in sb], autojunk=False)
    bad = [op for op in sm.get_opcodes() if op[0] != "equal"]
    print(f"BG state sequence: A {len(sa)} states, B {len(sb)} states, mismatching blocks {len(bad)}")
    for tag, i1, i2, j1, j2 in bad[:12]:
        fa = f"A frames {sa[i1][1]}-{sa[i2 - 1][1]}" if i2 > i1 else "A -"
        fb = f"B frames {sb[j1][1]}-{sb[j2 - 1][1]}" if j2 > j1 else "B -"
        print(f"  {tag}: {fa} | {fb}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
