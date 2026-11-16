#!/usr/bin/env python3
"""Write MEMORY_MAP.md: the kanji target's PRG ROM, bank by bank (16 KiB and
8 KiB), with every region, free hole and bank cluster, measured from the
current build.

    python tools/memory_map.py            (after python decomp/build.py --target kanji)

decomp/build.py runs it after every kanji build, so the map follows the
ROM.  Sources: the built ROM and the original (byte comparison), the build
images and listings in decomp/build/kanji (sizes, label anchors), the text
compiler's report, bank15_lint.py's registered patch ranges and
kanji_build.py's constants.  Free space is only what the build owns and
does not use, or fill bytes ($00 / $FF runs) inside original-byte areas
that nothing reads; the original game banks' own data is never counted.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "decomp" / "build" / "kanji"
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
KANJI = ROOT / "decomp" / "build" / "rom_kanji.nes"
DOC = ROOT / "MEMORY_MAP.md"
B = 0x4000
FILL_MIN = 32                    # a $00 / $FF run this long counts as fill


def kinc() -> dict[str, int]:
    """The numeric constants of decomp/include/kanji.inc."""
    out = {}
    for line in (ROOT / "decomp" / "include" / "kanji.inc").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Z_0-9]+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)\b", line)
        if m:
            v = m.group(2)
            out[m.group(1)] = int(v[1:], 16) if v.startswith("$") else int(v)
    return out


def label_addr(listing: Path, label: str) -> int | None:
    for line in listing.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^0([0-9A-F]{4})\s+(?:[0-9A-F]{2}\s+)*" + re.escape(label) + r":", line)
        if m:
            return int(m.group(1), 16)
    return None


def include_addr(listing: Path, name: str) -> int | None:
    for line in listing.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^0([0-9A-F]{4})\s+\.include \"[^\"]*" + re.escape(name) + "\"", line)
        if m:
            return int(m.group(1), 16)
    return None


def h(n: int) -> str:
    return f"${n:04X}"


def kib(n: int) -> str:
    return f"{n / 1024:.1f}"


class Region:
    def __init__(self, lo: int, hi: int, kind: str, text: str):
        self.lo, self.hi, self.kind, self.text = lo, hi, kind, text   # offsets in the 16 KiB bank, hi inclusive

    @property
    def size(self) -> int:
        return self.hi - self.lo + 1


def runs(data: bytes, lo: int, hi: int):
    """Split data[lo..hi] into fill runs ($00 / $FF, >= FILL_MIN) and the rest."""
    out = []
    i = lo
    while i <= hi:
        j = i
        if data[i] in (0x00, 0xFF):
            while j + 1 <= hi and data[j + 1] == data[i]:
                j += 1
            if j - i + 1 >= FILL_MIN:
                out.append((i, j, True))
                i = j + 1
                continue
        # a non-fill stretch: up to the next long fill run
        k = i
        while k <= hi:
            if data[k] in (0x00, 0xFF):
                m = k
                while m + 1 <= hi and data[m + 1] == data[k]:
                    m += 1
                if m - k + 1 >= FILL_MIN:
                    break
                k = m + 1
            else:
                k += 1
        out.append((i, k - 1, False))
        i = k
    return out


def diff_ranges(a: bytes, b: bytes, gap: int = 8):
    out = []
    i = 0
    n = len(a)
    while i < n:
        if a[i] != b[i]:
            j = i
            last = i
            while j < n and j - last <= gap:
                if a[j] != b[j]:
                    last = j
                j += 1
            out.append((i, last))
            i = last + 1
        else:
            i += 1
    return out


def original_labels() -> dict[int, list[tuple[int, str]]]:
    out: dict[int, list[tuple[int, str]]] = {}
    for line in (ROOT / "decomp" / "labels.txt").read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^bank (\d+)\s+\$([0-9A-F]{4})\s+(\S+)", line)
        if m:
            out.setdefault(int(m.group(1)), []).append((int(m.group(2), 16), m.group(3)))
    for v in out.values():
        v.sort()
    return out


def near(labels: list[tuple[int, str]], addr: int) -> str:
    best = None
    for a, name in labels:
        if a <= addr:
            best = (a, name)
        else:
            break
    if not best:
        return ""
    return best[1] if best[0] == addr else f"{best[1]}+{addr - best[0]}"


def bank_roles() -> dict[int, str]:
    out = {}
    for line in (ROOT / "decomp" / "BANKS.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*(\d+)\s*\|\s*`\$[0-9A-F]+`\s*\|\s*([^|]+?)\s*\|", line)
        if m:
            out[int(m.group(1))] = m.group(2)
    return out


def main() -> int:
    if not ORIGINAL.exists() or not KANJI.exists():
        print("memory_map: build the kanji target first", file=sys.stderr)
        return 2
    orig = ORIGINAL.read_bytes()[16:]
    rom = KANJI.read_bytes()[16:]
    if len(rom) != 32 * B:
        print("memory_map: the kanji ROM is not 512 KiB", file=sys.stderr)
        return 2
    sys.path.insert(0, str(ROOT / "tools"))
    import kanji_build as kb
    import kanji_text as kt
    import bank15_lint as lint
    K = kinc()
    report = json.loads((OUT / "kanji_text_report.json").read_text(encoding="utf-8"))
    roles = bank_roles()
    olabels = original_labels()
    size = lambda name: (OUT / name).stat().st_size

    HACK, ATT, TXR, UI = K["KANJI_HACK_BANK"], kb.ATT_BANK, K["TXR_BANK"], K["UI_BANK"]
    STORE = K["STORE_16K"]
    text_banks = report["data_banks"]
    regions: dict[int, list[Region]] = {b: [] for b in range(32)}
    kind_of: dict[int, str] = {}
    notes: dict[int, str] = {}

    def add(b, lo, hi, kind, text):
        if hi >= lo:
            regions[b].append(Region(lo, hi, kind, text))

    def add_orig(b, lo, hi, what):
        """Original bytes [lo, hi]: fill runs ($00 / $FF) are free, the rest data."""
        for a, z, fill in runs(rom[b * B:(b + 1) * B], lo, hi):
            if fill:
                add(b, a, z, "fill", f"{what}: $00 / $FF fill (the build reads none of it; not checked at runtime)")
            else:
                add(b, a, z, "orig", f"{what}")

    # ---------------- banks 0-14: the original game (patched where noted)
    patched_note = {
        9: "step B: the UI glyphs' plane 1 (the kanji UI's tiles)",
        13: "boot screens, attract entry, map-canvas save records",
        14: "step B windows, map UI, battle shake, kanji sites",
    }
    for b in range(15):
        a, k = orig[b * B:(b + 1) * B], rom[b * B:(b + 1) * B]
        role = roles.get(b, "?")
        if b in (10, 11):
            continue
        d = diff_ranges(a, k, gap=16)
        kind_of[b] = "original" if not d else "original, patched"
        if not d:
            add(b, 0, B - 1, "orig", f"original: {role}")
            continue
        notes[b] = patched_note.get(b, "")
        pos = 0
        for lo, hi in d:
            if lo > pos:
                add(b, pos, lo - 1, "orig", f"original: {role}")
            lab = near(olabels.get(b, []), 0x8000 + lo)
            add(b, lo, hi, "patch", "changed" + (f" (at {lab})" if lab else ""))
            pos = hi + 1
        if pos < B:
            add(b, pos, B - 1, "orig", f"original: {role}")
    # The original officer-name glyphs (16x16, 64 bytes each), unread since
    # 2026-11-13: every kanji name comes from the kanji store.  The bytes stay
    # (the banks are the original's); free only while bank 1 / 2 is mapped,
    # which the game does for its graphics (TEXT_RENDERER.md "The old name
    # glyphs freeable", 2026-11-17: no code reads them, and a CPU-read log of
    # five runs found no read).
    for b, lo, hi, n in ((1, 0x0010, 0x1A0F, 104), (2, 0x0010, 0x080F, 32)):
        new = []
        for r in regions[b]:
            if r.hi < lo or r.lo > hi:
                new.append(r)
                continue
            if r.kind != "orig":
                raise SystemExit(f"memory_map: bank {b}'s name glyphs are not original bytes")
            if r.lo < lo:
                new.append(Region(r.lo, lo - 1, r.kind, r.text))
            new.append(Region(max(r.lo, lo), min(r.hi, hi), "free",
                              f"the original officer-name glyphs ({n}; unread since 2026-11-13: names come "
                              "from the kanji store): freeable, usable while this bank is mapped"))
            if r.hi > hi:
                new.append(Region(hi + 1, r.hi, r.kind, r.text))
        regions[b] = new
    # bank 13's filler ($8D20-$8FFF): the boot title and boot routines, then fill
    b13_end = None
    for r in list(regions[13]):
        pass
    # re-split bank 13's filler area into used / fill
    fill_lo, fill_hi = 0x0D20, 0x0FFF
    new = []
    for r in regions[13]:
        if r.hi < fill_lo or r.lo > fill_hi:
            new.append(r)
            continue
        if r.lo < fill_lo:
            new.append(Region(r.lo, fill_lo - 1, r.kind, r.text))
        if r.hi > fill_hi:
            tail = Region(fill_hi + 1, r.hi, r.kind, r.text)
        else:
            tail = None
        lo, hi = max(r.lo, fill_lo), min(r.hi, fill_hi)
        if r.kind == "patch":
            new.append(Region(lo, hi, "code", "kanji build: the name-entry title block, b13_k_restore / _check / _speed / _set / _oath / _oathend (bank 13's filler)"))
        else:
            for a, z, fill in runs(rom[13 * B:14 * B], lo, hi):
                new.append(Region(a, z, "free" if fill else "orig",
                                  "the original filler ($00 / $FF, never read): free" if fill else "original"))
        if tail:
            new.append(tail)
    regions[13] = new

    # ---------------- banks 10 / 11: pointer tables, stubs, freed text, trampoline
    for b in (10, 11):
        info = kt.BANK_INFO[b]
        cnt, start, tail = info["count"], kt.DATA_START[b], info["tail"]
        k = rom[b * B:(b + 1) * B]
        stub_end = start
        nstub = 0
        for i in range(cnt):
            a = (k[info["lo"] + i] | k[info["hi"] + i] << 8) - 0x8000
            ln = 6 if k[a] == 0xF8 else 3
            stub_end = max(stub_end, a + ln)
        seen = set()
        for i in range(cnt):
            seen.add(k[info["lo"] + i] | k[info["hi"] + i] << 8)
        kind_of[b] = "messages (stubs)"
        add(b, info["lo"], info["lo"] + cnt - 1, "data", f"message pointer table, low bytes ({cnt} messages)")
        if info["lo"] + cnt < info["hi"]:
            add_orig(b, info["lo"] + cnt, info["hi"] - 1, "original bytes between the tables")
        add(b, info["hi"], info["hi"] + cnt - 1, "data", "message pointer table, high bytes")
        add(b, start, stub_end - 1, "data", f"{len(seen)} stubs: F8 far stubs (6 bytes: F8, far head, text chunk and victory flag, text address) and JUMP-only messages (3 bytes)")
        add(b, stub_end, tail - 1, "free", "the original message text, zeroed (2026-11-14 debloat; usable while this bank is mapped)")
        toff = kt.TRAMPOLINE_ADDR - 0x8000
        add_orig(b, tail, toff - 1, "original bytes after the text")
        tl = size("trampoline.bin")
        add(b, toff, toff + tl - 1, "code", f"F8 trampoline ({tl} bytes): makes the message bank current (the message engine at R6, the text chunk at R7), enters the engine")
        add_orig(b, toff + tl, B - 1, "original bank trailer")

    # ---------------- bank 15 (slot): free, JAM bytes
    kind_of[15] = "free (JAM)"
    s15 = rom[15 * B:16 * B]
    if s15 == bytes((0x02,)) * B:
        add(15, 0, B - 1, "free", "free since the 2026-11-14 debloat: JAM bytes ($02), a tripwire (nothing maps bank 15; the fixed bank is bank 31)")
    else:
        add(15, 0, B - 1, "orig", "the original fixed bank's image (unexpected: the debloat freed it)")

    # ---------------- banks 16-17: the kanji store (8 KiB banks 32-35)
    nglyph = size("kanji_font.bin") // 32
    store_free: dict[tuple[int, int, int], int] = {}
    for b in (STORE, STORE + 1):
        kind_of[b] = "kanji store"
        for half in (0, 1):
            k8 = 2 * b + half
            first = (k8 - K["STORE_8K"]) * 256
            used = max(0, min(256, nglyph - first))
            lo = half * 0x2000
            if used == 256:
                add(b, lo, lo + 0x1FFF, "data", f"kanji store, 8 KiB bank {k8}: glyphs {first}-{first + 255}; byte b of pos p at $A000 + 256 b + p (mapped at R7)")
            elif used:
                store_free[(b, lo, lo + 0x1FFF)] = 32 * (256 - used)
                add(b, lo, lo + 0x1FFF, "data", f"kanji store, 8 KiB bank {k8}: glyphs {first}-{first + used - 1} at pos $00-${used - 1:02X}; "
                    f"pos ${used:02X}-$FF free in every byte row ({256 - used} glyph slots, {32 * (256 - used)} bytes interleaved)")
            else:
                add(b, lo, lo + 0x1FFF, "free", f"kanji store, 8 KiB bank {k8}: no glyphs")

    # ---------------- text chunks (8 KiB banks TEXT_8K.., read at R7)
    msgs: dict[int, set[int]] = {}
    for b in (10, 11):
        info = kt.BANK_INFO[b]
        k = rom[b * B:(b + 1) * B]
        for i in range(info["count"]):
            a = (k[info["lo"] + i] | k[info["hi"] + i] << 8) - 0x8000
            if k[a] == 0xF8:
                msgs.setdefault(k[a + 3] & 0x3F, set()).add(k[a + 4] | k[a + 5] << 8)
    chunk_used = {int(c): n for c, n in report["text_chunks"].items()}
    for b in text_banks:
        kind_of[b] = "text"
        for half in (0, 1):
            k8 = 2 * b + half
            used = chunk_used.get(k8, 0)
            lo = half * 0x2000
            add(b, lo, lo + used - 1, "data", f"text chunk, 8 KiB bank {k8} (at R7, $A000-$BFFF): "
                f"{len(msgs.get(k8, ()))} messages, {used} bytes; no metadata (the message engine scans each page)")
            add(b, lo + used, lo + 0x1FFF, "free", f"text chunk {k8}'s free end (room for text; a message never crosses a chunk)")

    # ---------------- the hack bank
    kind_of[HACK] = "hack bank"
    hl = size("hack.bin")
    pal = K["KANJI_PAL_DATA"] - 0x8000
    pal_len = 0xC6D1 - 0xC5EF + 1
    hlab = kb.read_labels(OUT / "hack.lst")
    m0, m1 = hlab["msg_entry"] - 0x8000, hlab["msg_end"] - 0x8000
    add(HACK, 0, m0 - 1, "code", f"hack code ({m0} bytes): the battle pool's uploads and guard, the palette copy, reset")
    add(HACK, m0, m1 - 1, "code", f"the message engine ({m1 - m0} bytes, kanji_msg.asm): the text engine's kanji half, "
        f"at R6 while a message prints (MSG_BANK)")
    add(HACK, m1, hl - 1, "code", "hack code") if m1 < hl else None
    add(HACK, max(hl, m1), pal - 1, "free", "free")
    add(HACK, pal, pal + pal_len - 1, "data", f"load_text_graphics' palette tables ({pal_len} bytes, from $C5EF-$C6D1)")
    add(HACK, pal + pal_len, 0x1FFF, "free", "free")
    add(HACK, 0x2000, B - 1, "free", "free (R7 is a window here: a kanji store bank while the hack code uploads, the text chunk while a message prints)")

    # ---------------- the attract bank
    kind_of[ATT] = "title / attract"
    al = size("attract.bin")
    alst = OUT / "attract.lst"
    lo_inc = include_addr(alst, "attract_lo.inc")
    hi_inc = include_addr(alst, "attract_hi.inc")
    a_img = rom[ATT * B:ATT * B + al]
    add(ATT, 0, lo_inc - 0x8000 - 1, "code", "title and attract mode code (attract.asm)")
    lo_end = max(i for i in range(lo_inc - 0x8000, hi_inc - 0x8000) if a_img[i]) + 1
    add(ATT, lo_inc - 0x8000, lo_end - 1, "data", "tile sets, phrases, layouts (attract_lo.inc)")
    add(ATT, lo_end, hi_inc - 0x8000 - 1, "free", "free (to the upper half's data)")
    add(ATT, hi_inc - 0x8000, al - 1, "data", "upper-half data (attract_hi.inc: portraits' parts, glyph lists)")
    add(ATT, al, B - 1, "free", "free")

    # ---------------- the text renderer
    kind_of[TXR] = "map text renderer"
    tl = size("txr.bin")
    tinc = include_addr(OUT / "txr.lst", "txr_ui.inc") - 0x8000
    add(TXR, 0, min(tinc, 0x2000) - 1, "code", "renderer code; the NMI parts must stay here ($8000-$9FFF: the NMI maps this half alone)")
    if tinc > 0x2000:
        add(TXR, 0x2000, tinc - 1, "code", "renderer code (main thread)")
    add(TXR, tinc, tl - 1, "data", "txr_ui.inc: map UI words, labels, boot / oath fixed sets, names' codes")
    add(TXR, tl, B - 1, "free", "free")

    # ---------------- the UI bank
    kind_of[UI] = "UI bank"
    ul = size("ui.bin")
    uinc = include_addr(OUT / "ui.lst", "ui_data.inc") - 0x8000
    add(UI, 0, uinc - 1, "code", "UI code (info screen, battle windows, army screen; store routines kept in $8000-$9FFF)")
    add(UI, uinc, ul - 1, "data", "ui_data.inc: glyph codes, name table, fixed groups")
    add(UI, ul, B - 1, "free", "free")

    # ---------------- unclaimed extension banks
    for b in range(16, 31):
        if kind_of.get(b):
            continue
        if not any(rom[b * B:(b + 1) * B]):
            kind_of[b] = "free"
            add(b, 0, B - 1, "free", "free (blank)")
        else:
            kind_of[b] = "?"
            add(b, 0, B - 1, "orig", "unclaimed, not blank (update tools/memory_map.py)")

    # ---------------- the fixed bank (31)
    kind_of[31] = "fixed bank"
    fixed_rows = []
    owned = []
    for lo, hi in lint.PATCHES:
        owned.append((lo, hi))
    four = [(lo, hi) for lo, hi, _ in kb.FOURSCREEN_REGIONS]
    # comments of the registered ranges
    comments = {}
    for line in (ROOT / "tools" / "bank15_lint.py").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*\(0x([0-9A-F]{4}), 0x([0-9A-F]{4})\),\s*#\s*(.*)", line)
        if m:
            comments[(int(m.group(1), 16), int(m.group(2), 16))] = m.group(3)
    # free tails of the build's own regions: the mmc3_b15 blocks with a limit check
    lst = (OUT / "mmc3_b15.lst").read_text(encoding="utf-8", errors="ignore").splitlines()
    holes = []
    asm_lines = (ROOT / "tools" / "asm" / "mmc3_b15.asm").read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lst):
        m = re.match(r"^0([0-9A-F]{4})\s+\.if \$ > \$([0-9A-F]{4})", line)
        if m:
            cur, lim = int(m.group(1), 16), int(m.group(2), 16)
            if lim > cur:
                holes.append((cur, lim - 1))
    k31 = rom[31 * B:32 * B]
    o15 = orig[15 * B:16 * B]
    pos = 0
    for lo, hi in sorted(set(owned + four)):
        if lo - 0xC000 > pos:
            add(31, pos, lo - 0xC000 - 1, "orig", "original bank 15 code / data")
        lab = near(olabels.get(15, []), lo)
        txt = comments.get((lo, hi), (f"map-canvas: rewritten in place (at {lab})" if lab else "map-canvas: rewritten in place")
                           if (lo, hi) in four else "registered patch")
        add(31, lo - 0xC000, hi - 0xC000, "patch", txt)
        pos = max(pos, hi - 0xC000 + 1)
    if pos < B:
        add(31, pos, B - 1, "orig", "original bank 15 code / data")
    # mark the measured holes inside owned regions
    newr = []
    for r in regions[31]:
        cut = [(max(r.lo, a - 0xC000), min(r.hi, z - 0xC000)) for a, z in holes
               if a - 0xC000 <= r.hi and z - 0xC000 >= r.lo]
        if not cut or r.kind != "patch":
            newr.append(r)
            continue
        p = r.lo
        for a, z in sorted(cut):
            if a > p:
                newr.append(Region(p, a - 1, r.kind, r.text))
            newr.append(Region(a, z, "free", "free: the rest of the build's region (limit-checked in mmc3_b15.asm)"))
            p = z + 1
        if p <= r.hi:
            newr.append(Region(p, r.hi, r.kind, r.text))
    regions[31] = newr

    for b in range(32):
        regions[b].sort(key=lambda r: r.lo)
        merged = []
        for r in regions[b]:
            if merged and merged[-1].kind == r.kind and merged[-1].text == r.text and merged[-1].hi + 1 == r.lo:
                merged[-1].hi = r.hi
            else:
                merged.append(r)
        regions[b] = merged
        # sanity: contiguous cover
        p = 0
        for r in regions[b]:
            if r.lo != p:
                raise SystemExit(f"memory_map: bank {b} region gap/overlap at {h(r.lo)} (expected {h(p)})")
            p = r.hi + 1
        if p != B:
            raise SystemExit(f"memory_map: bank {b} ends at {h(p)}")

    # ---------------------------------------------------------------- doc
    base = lambda b: 0xC000 if b == 31 else 0x8000
    def free_of(b, lo=0, hi=B - 1):
        n = sum(min(r.hi, hi) - max(r.lo, lo) + 1 for r in regions[b]
                if r.kind == "free" and r.hi >= lo and r.lo <= hi)
        for (eb, elo, ehi), extra in store_free.items():   # the store's interleaved free slots
            if eb == b and elo >= lo and ehi <= hi:
                n += extra
        return n
    sha = hashlib.sha256(KANJI.read_bytes()).hexdigest()
    L = []
    w = L.append
    w("# PRG ROM memory map (kanji target)")
    w("")
    w(f"Generated by `tools/memory_map.py` from the current build (`rom_kanji.nes` sha256 `{sha[:16]}…`).  "
      "`decomp/build.py --target kanji` regenerates it after every build, so it follows the ROM; edit the "
      "tool, not this file.")
    w("")
    w("- **Mapper:** MMC3, PRG mode 0, 512 KiB = 32 banks of 16 KiB = 64 banks of 8 KiB.  16 KiB bank *n* "
      "is 8 KiB banks 2*n* (`$8000-$9FFF`, R6) and 2*n*+1 (`$A000-$BFFF`, R7).  The fixed bank is 16 KiB bank 31 "
      "(8 KiB banks 62 / 63 at `$C000-$DFFF` / `$E000-$FFFF`).")
    w("- **The game's `set_bank n`** maps both halves of 16 KiB bank *n*.  The kanji store is read in 8 KiB "
      "units at R7 (banks 32-35); the NMI maps the renderer's first half alone.")
    w("- **Free** counts only what the build owns and does not use, plus original bytes known never to be read "
      "(bank 13's filler `$8D20-$8FFF`; the original officer-name glyphs in banks 1 and 2, the bytes kept).  "
      "**Fill** is `$00` / `$FF` runs "
      f"({FILL_MIN}+ bytes) left in original-byte areas of banks 10/11: the build reads none of it, but nothing checked it "
      "at runtime, so it is listed apart.  Original game data is never counted.")
    w("")

    total_free = sum(free_of(b) for b in range(32))
    fill_of = lambda b: sum(r.size for r in regions[b] if r.kind == "fill")
    total_fill = sum(fill_of(b) for b in range(32))
    w("## Banks at a glance")
    w("")
    w("| 16 KiB bank | 8 KiB banks | CPU | Role | Used KiB | Free KiB | Fill KiB | Free holes |")
    w("|---:|---|---|---|---:|---:|---:|---|")
    for b in range(32):
        fr = free_of(b)
        fl = fill_of(b)
        holes_b = [r for r in regions[b] if r.kind == "free"]
        hs = ", ".join(f"`{h(base(b) + r.lo)}-{h(base(b) + r.hi)}`" for r in holes_b[:4])
        if len(holes_b) > 4:
            hs += f" (+{len(holes_b) - 4})"
        role = kind_of[b]
        if b < 15 and b not in (10, 11):
            role = f"{role}: {roles.get(b, '')}"
        w(f"| {b:02d} | {2 * b}, {2 * b + 1} | `{h(base(b))}` | {role} | {kib(B - fr - fl)} | {kib(fr)} | {kib(fl) if fl else '-'} | {hs or '-'} |")
    w(f"| **all** | | | | **{kib(32 * B - total_free - total_fill)}** | **{kib(total_free)}** | **{kib(total_fill)}** | |")
    w("")

    # clusters
    w("## Bank clusters (consecutive banks of one kind)")
    w("")
    w("| 16 KiB banks | 8 KiB banks | Size | Kind | Free KiB |")
    w("|---|---|---:|---|---:|")
    group = lambda b: ("original game" if b < 15 else kind_of[b])
    b = 0
    while b < 32:
        e = b
        while e + 1 < 32 and group(e + 1) == group(b):
            e += 1
        rng = f"{b:02d}" if b == e else f"{b:02d}-{e:02d}"
        w(f"| {rng} | {2 * b}-{2 * e + 1} | {(e - b + 1) * 16} KiB | {group(b)} | {kib(sum(free_of(x) for x in range(b, e + 1)))} |")
        b = e + 1
    w("")

    # 8 KiB banks
    w("## 8 KiB banks")
    w("")
    w("| 8 KiB | 16 KiB bank, half | CPU when mapped | Content | Free bytes |")
    w("|---:|---|---|---|---:|")
    for k8 in range(64):
        b, half = divmod(k8, 2)
        lo, hi = half * 0x2000, half * 0x2000 + 0x1FFF
        cpu = (0xC000 if b == 31 else 0x8000) + lo
        if b == 31:
            win = f"`{h(cpu)}` (fixed)"
        elif STORE <= b <= STORE + 1:
            win = "`$A000` (R7, the store)"
        elif b in text_banks:
            win = "`$A000` (R7, a text chunk)"
        else:
            win = f"`{h(cpu)}` (R{6 + half})"
        parts = []
        if b == 31:
            np_ = sum(1 for r in regions[b] if r.kind == "patch" and r.hi >= lo and r.lo <= hi)
            parts.append(f"the original bank 15 (fixed), {np_} patched / rewritten ranges")
        for r in ([] if b == 31 else regions[b]):
            if r.hi >= lo and r.lo <= hi and r.kind != "free":
                t = r.text.split(":")[0] if r.kind == "orig" else r.text.split(";")[0].split("(")[0].strip()
                if t not in parts:
                    parts.append(t)
        content = "; ".join(parts[:3]) + (" …" if len(parts) > 3 else "") if parts else "free"
        w(f"| {k8} | {b:02d} {'lower' if half == 0 else 'upper'} | {win} | {content} | {free_of(b, lo, hi)} |")
    w("")

    # per bank
    w("## Bank by bank")
    w("")
    kind_label = {"orig": "original", "patch": "patched", "code": "code", "data": "data", "free": "**free**", "fill": "fill"}
    for b in range(32):
        rs = regions[b]
        title = kind_of[b] + (f": {roles.get(b, '')}" if b < 15 and b not in (10, 11) else "")
        w(f"### Bank {b:02d} (8 KiB banks {2 * b} / {2 * b + 1}): {title}")
        w("")
        if b in notes and notes[b]:
            w(f"Changes: {notes[b]}.")
            w("")
        if len(rs) == 1:
            r = rs[0]
            w(f"`{h(base(b))}-{h(base(b) + B - 1)}`: " + (r.text if r.kind == "orig" else f"{kind_label[r.kind]}, {r.text}") + ".")
            w("")
            continue
        only_changes = (b < 15 and b not in (10, 11)) or b == 31
        if only_changes:
            orig_bytes = sum(r.size for r in rs if r.kind == "orig")
            w(f"Everything not listed is the original's ({orig_bytes} bytes); "
              + ("the fixed bank keeps every address (`tools/bank15_lint.py`)." if b == 31
                 else "the changed or freed ranges by address:"))
            w("")
        w("| Address | Half | Bytes | Kind | Content |")
        w("|---|---|---:|---|---|")
        for r in rs:
            if only_changes and r.kind == "orig":
                continue
            half = "lower" if r.hi < 0x2000 else ("upper" if r.lo >= 0x2000 else "both")
            w(f"| `{h(base(b) + r.lo)}-{h(base(b) + r.hi)}` | {half} | {r.size} | {kind_label[r.kind]} | {r.text} |")
        w("")

    # CHR RAM (static, from the code)
    w("## CHR RAM (16 KiB, 1 KiB banks; from the code, not measured)")
    w("")
    w("| CHR | 1 KiB banks | Register | Use |")
    w("|---|---|---|---|")
    for row in (
        ("`$0000-$0FFF`", "0-3", "R2-R5", "sprites"),
        ("`$1000-$17FF`", "4-5", "R0 = 4", "the scene page, BG tiles `$00-$7F`: the font, the window frame (screens may borrow font tiles, e.g. the oath's `$42-$5B`)"),
        ("`$1800-$1FFF`", "6-7", "R1 = 6", "the scene page, BG tiles `$80-$FF`: map, battle and scene tiles; the battle pool `$A4-$DF`; the boot screens' fixed set `$80-$E3`"),
        ("`$2000-$27FF`", "8-9", "R0 = 8", "map mode: the renderer's part 2 (rows 9-14)"),
        ("`$2800-$2FFF`", "10-11", "R0 = 10", "map mode: part 3 (rows 15-20)"),
        ("`$3000-$37FF`", "12-13", "R0 = 12", "map mode: part 4 (rows 21-29)"),
        ("`$3800-$3FFF`", "14-15", "R1 = 14", "the opening oath's kanji page (tiles `$80-$CF`, below the line-130 split); the band page until 2026-11-14"),
    ):
        w("| " + " | ".join(row) + " |")
    w("")
    DOC.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"memory map: {DOC.name} ({kib(total_free)} KiB free, {kib(total_fill)} KiB fill, of 512)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
