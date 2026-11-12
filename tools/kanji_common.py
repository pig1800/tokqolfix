#!/usr/bin/env python3
"""Shared kanji inventory/encoding helpers for the SUROM kanji target."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

import textdata

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "decomp" / "text" / "kanji_plan"
INDEX_TSV = ROOT / "assets" / "fonts" / "kanji_index.tsv"

# U+3005 (iteration mark) is a 16x16 glyph too (revision 15).
KANJI_RE = re.compile(r"[\u3005\u3400-\u9fff\uf900-\ufaff]")

# The dialogue sources that define the hack's inventory.  Both are the
# corrected machine drafts; they are the editable source for the kanji target.
# Revision 14: the Opus re-conversion laid out by tools/kanji_layout.py
# (bank1X_messages_kanji_r14.dtx) replaces the machine drafts when present.
_R14 = (PLAN / "bank10_messages_kanji_r14.dtx", PLAN / "bank11_messages_kanji_r14.dtx")
DTX_FILES = _R14 if all(p.exists() for p in _R14) else (
    PLAN / "bank10_messages_kanji_fixed.dtx",
    PLAN / "bank11_messages_kanji_fixed.dtx",
)


# Print helpers ($F8 CALL) that show one of two fixed officer names: bank 13
# $A1D0/$A1D4 print officer $0A (ソウジン) or $0B (ソウユウ) from the runtime
# name table, the talked-to brother first.  The kanji target compiles them
# as a kanji pick on the same test: ptr -> (officer id, name shown when the
# talked-to actor is that officer, name shown otherwise).
KANJI_CALLS = {
    0x21D0: (0x0A, "宋仁", "宋勇"),
    0x21D4: (0x0B, "宋仁", "宋勇"),
}

# Print helpers that add fixed kana tiles after a name.  $D549 (battle
# result, b10_msg_055) draws the target's name ($D49A) and then the tiles
# のへい when the target unit ($60A8,[$4B]) is 8 or up.  The kanji target
# compiles it as <CALL:name helper> plus a troop pick on the same test:
# ptr -> (name helper, text shown when the test passes, text otherwise).
KANJI_TROOP_CALLS = {
    0xD549: (0xD49A, "の兵", ""),
}

# Print helpers whose fixed kana tail has a kanji form of the same width.
# $D565 (strategy name: three messages) draws the name and then のけい
# unconditionally; the kanji target follows the call with $EE $FC n (the
# buffer position goes back n cells, over けい) and the kanji: ptr ->
# (cells, text).
KANJI_SUFFIX_CALLS = {
    0xD565: (2, "計"),
}


def _count_literal(text: str, counts: Counter[str]) -> None:
    """Count kanji outside <...> tokens."""
    out = []
    i = 0
    while i < len(text):
        if text[i] == "<":
            j = text.find(">", i + 1)
            if j < 0:
                break
            i = j + 1
            continue
        out.append(text[i])
        i += 1
    for ch in KANJI_RE.findall("".join(out)):
        counts[ch] += 1


def inventory() -> list[tuple[str, int]]:
    """Return (character, count) in stable code order.

    Codes 0-255 are the most frequent so most text uses the shortest escape
    ($EC nn).  Ties are broken by first appearance.
    """
    counts: Counter[str] = Counter()
    first: dict[str, int] = {}
    order = 0
    for path in DTX_FILES:
        text = path.read_text(encoding="utf-8")
        _count_literal(text, counts)
        for m in re.finditer(r"<(WORD|PLACE|ITEM):([0-9A-Fa-f]{2})", text):
            typ, idx = m.group(1), int(m.group(2), 16)
            table = {
                "WORD": textdata.dictionary_entries,
                "PLACE": textdata.place_entries,
                "ITEM": textdata.item_entries,
            }[typ]()
            data = table.get(idx, b"")
            try:
                s = textdata.encode_record(data)
            except Exception:
                continue
            _count_literal(s, counts)
        for m in re.finditer(r"<CALL:([0-9A-Fa-f]{4})", text):
            ptr = int(m.group(1), 16)
            pick = KANJI_CALLS.get(ptr) or KANJI_TROOP_CALLS.get(ptr)
            if ptr in KANJI_SUFFIX_CALLS:
                pick = (None, KANJI_SUFFIX_CALLS[ptr][1], "")
            if pick:
                for ch in KANJI_RE.findall(pick[1] + pick[2]):
                    counts[ch] += 1
                    first.setdefault(ch, order)
                    order += 1
        for m in KANJI_RE.finditer(text):
            first.setdefault(m.group(0), order)
            order += 1
    # Stable order: frequency desc, first appearance asc.
    chars = sorted(counts, key=lambda ch: (-counts[ch], first.get(ch, 10**9), ord(ch)))
    inv = [(ch, counts[ch]) for ch in chars]
    # The UI kanji (screen labels, battle commands, item and tactic names)
    # follow the message kanji, so adding them moves no message code.
    have = set(chars)
    for ch in ui_kanji():
        if ch not in have:
            have.add(ch)
            inv.append((ch, 0))
    return inv


# Kanji of the screen labels (info screen) and the battle command panel, in
# slot order; the item and tactic names come from kanjiwordlist.csv.
UI_LABELS = "武力知攻撃装度兵士数備策略"
UI_COMMANDS = "戦策略防御道具総攻撃退却武将残"
WORDLIST = ROOT / "kanjiwordlist.csv"


def wordlist() -> list[tuple[str, str, str]]:
    """kanjiwordlist.csv: (type, kana, kanji).  cp932 and tab-separated, or
    UTF-8 (with or without a BOM) and comma-separated, as a spreadsheet
    saves it."""
    raw = WORDLIST.read_bytes()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("cp932")
    sep = "	" if "	" in text.splitlines()[0] else ","
    rows = []
    for line in text.splitlines()[1:]:
        parts = line.split(sep)
        if len(parts) >= 3 and parts[0].strip():
            rows.append((parts[0].strip(), parts[1].strip(), parts[2].strip()))
    return rows


# Map-mode UI (TEXT_RENDERER.md "Kanji UI", 2026-11-12): the kana words of
# the window templates (window, kana, kanji) that the map text renderer
# shows in kanji, and its labels (the gold window's 金 and 兵糧, the
# tavern list's その他).  Item, tactic and place names come from the word
# list and the glossary.
MAP_UI_WORDS = (
    (0x00, "はなす", "話す"), (0x00, "しらべる", "調べる"), (0x00, "たいれつ", "隊列"),
    (0x00, "ぶしょう", "武将"), (0x00, "どうぐ", "道具"),
    (0x04, "ならび", "並び"), (0x04, "ぐんし", "軍師"),
    (0x07, "つかう", "使う"), (0x07, "わたす", "渡す"), (0x07, "そうび", "装備"),
    (0x07, "すてる", "捨てる"),
    (0x1C, "かいにきた", "買いに来た"), (0x1C, "うりにきた", "売りに来た"),
    (0x1F, "のうりょく", "能力"), (0x1F, "くわえる", "加える"), (0x1F, "はずす", "外す"),
    (0x1F, "かいこ", "解雇"),
    (0x24, "きろく", "記録"), (0x24, "よぶ", "呼ぶ"),
    (0x29, "はやい", "速い"), (0x29, "ふつう", "普通"), (0x29, "おそい", "遅い"),
    (0x26, "もどる", "戻る"), (0x26, "すすめ", "進め"), (0x26, "おわる", "終わる"),
)
# Windows shown on the boot screens (title mode): their kanji come from the
# fixed set (FIXED_UI), not the map renderer.
BOOT_WINDOWS = (0x26, 0x29)
# The name-entry screen's title (bank 13 $9331, a draw_string block).
NAME_TITLE = "名前を入れてください"
# The boot menu's four lines (bank 13 $90E9), kana -> kanji.
BOOT_MENU = {
    "げーむをはじめる": "ゲームを始める",
    "れきししょをとうろくする": "歴史書を登録する",
    "れきししょをけす": "歴史書を消す",
    "れきししょのこぴー": "歴史書のコピー",
}
MAP_UI_LABELS = ("金", "兵糧", "その他")
GLOSSARY = ROOT / "decomp" / "text" / "kanji_r14" / "glossary.tsv"


def glossary(kind: str) -> dict[str, str]:
    """glossary.tsv rows of one kind: kana -> kanji (the first row wins)."""
    out: dict[str, str] = {}
    for line in GLOSSARY.read_text(encoding="utf-8").splitlines():
        parts = line.split("	")
        if len(parts) >= 3 and parts[0] == kind:
            out.setdefault(parts[1], parts[2])
    return out


def place_kanji(kana: str) -> str | None:
    """A place name's kanji: the glossary's, or its stem's + 城."""
    g = glossary("PLACE")
    if kana in g:
        return g[kana]
    if kana.endswith("じょう") and kana[:-3] in g:
        return g[kana[:-3]] + "城"
    return None


def map_places() -> dict[int, tuple[bytes, str]]:
    """Bank 12's place-name table (the 神行の札 destination list, $D58C):
    pointers lo $A100 + i / hi $A140 + i for i = $40-$7F, strings from
    byte 0.  Index -> (kana bytes, kanji) for the names the glossary has."""
    b12 = textdata.prg()[12 * 0x4000:13 * 0x4000]
    out = {}
    for i in range(0x40, 0x80):
        ptr = b12[0x2100 + i] | (b12[0x2140 + i] << 8)
        if not 0x8000 <= ptr < 0xC000:
            continue
        o = ptr - 0x8000
        end = b12.find(bytes((0xFF,)), o)
        if end < 0 or end - o > 16:
            continue
        raw = bytes(b12[o:end])
        try:
            kana = "".join(textdata.BYTE_TO_CHAR[b] for b in raw)
        except KeyError:
            continue
        k = place_kanji(kana)
        if k:
            out[i] = (raw, k)
    return out


# Officer names (2026-11-12): namekanjilist.csv (repo root; UTF-8, "Kana,
# Name") gives the kanji of a kana name.  A kana it gives two forms for is
# two officers; NAME_PICK names the record (bank 12 officer record id,
# pointers $A800 / $A900 + id) of each, as the original game's own name
# glyphs (record bytes $10-$13) show them.  NAME_EXTRA: the names the list
# lacks, also from those glyphs.  Record $B3 (１０マメ) is no officer.
NAME_LIST = ROOT / "namekanjilist.csv"
NAME_PICK = {
    0x0A: "宋仁", 0x72: "曹仁",
    0x0D: "張宝", 0xAD: "張苞",
    0x0E: "張梁", 0x83: "張遼",
    0x26: "袁紹", 0x27: "袁尚",
    0x2F: "張郃", 0x68: "張紘",
    0x73: "曹洪", 0x74: "曹昂",
    0x59: "孫桓", 0x9E: "孫乾",
    0x51: "張松",               # (the list's チョウショウ is 張昭, record $67)
}
NAME_EXTRA = {
    "カイゾク": "海賊", "サンゾク": "山賊", "トウゾク": "盗賊", "ヘイシ": "兵士",
    "ザントウ": "残党", "カクシ": "郭汜", "チンリン": "陳琳", "ソンサク": "孫策",
    "ソウソウ": "曹操", "カンサク": "関索", "イセキ": "伊籍", "リュウゼン": "劉禅",
    "ジュンユウ": "荀攸",
}
# The original name font draws these twice (a kanji with two glyphs is
# otherwise a wrong name): 蒋 and 蔣, 苞 in both banks.
NAME_GLYPH_TWINS = {"蒋": {(1, 0xA9), (1, 0xC1)}, "苞": {(1, 0x10), (2, 0x1B)}}
_NAMES: dict[int, str] = {}
NAME_RECORDS = 0xD9             # records $00-$D8 (the rest of the table is no names)
NAME_NONE = (0xB3,)


def _katakana(s: str) -> str:
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in s)


def officer_records() -> dict[int, tuple[int, bytes, list[tuple[int, int]]]]:
    """Bank 12's officer records: id -> (pointer, kana bytes from byte $14
    up to the first byte >= $FE, the original name glyphs (bank, index))."""
    b12 = textdata.prg()[12 * 0x4000:13 * 0x4000]
    out = {}
    for i in range(NAME_RECORDS):
        ptr = b12[0x2800 + i] | (b12[0x2900 + i] << 8)
        o = ptr - 0x8000
        rec = b12[o:o + 0x20]
        end = next(j for j in range(0x14, 0x20) if rec[j] >= 0xFE)
        gl = []
        for n in range(3):
            if rec[0x11 + n] == 0xFF:
                break
            gl.append((2 if rec[0x10] & (0x80 >> n) else 1, rec[0x11 + n]))
        out[i] = (ptr, bytes(rec[0x14:end]), gl)
    return out


def officer_names() -> dict[int, str]:
    """Record id -> the kanji name (namekanjilist.csv, NAME_PICK,
    NAME_EXTRA).  Fails on a record it cannot name, on a kana with two
    forms and no pick, and on two names that give one original glyph two
    different kanji."""
    raw = NAME_LIST.read_bytes().decode("utf-8-sig")
    forms: dict[str, list[str]] = {}
    for line in raw.splitlines()[1:]:
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 2 and parts[0] and parts[1]:
            forms.setdefault(parts[0], [])
            if parts[1] not in forms[parts[0]]:
                forms[parts[0]].append(parts[1])
    global _NAMES
    if _NAMES:
        return dict(_NAMES)
    out: dict[int, str] = {}
    seen: dict[tuple[int, int], tuple[str, int]] = {}
    glyph_of: dict[str, tuple[int, int]] = {}
    for i, (_ptr, kana_b, gl) in officer_records().items():
        if i in NAME_NONE:
            continue
        kana = _katakana("".join(textdata.BYTE_TO_CHAR[b] for b in kana_b))
        if i in NAME_PICK:
            name = NAME_PICK[i]
        elif len(forms.get(kana, ())) == 1:
            name = forms[kana][0]
        elif kana in forms:
            raise SystemExit(f"officer ${i:02X} {kana}: {forms[kana]}, no NAME_PICK")
        elif kana in NAME_EXTRA:
            name = NAME_EXTRA[kana]
        else:
            raise SystemExit(f"officer ${i:02X} {kana}: no kanji name")
        out[i] = name
        if len(name) == len(gl):
            for g, ch in zip(gl, name):
                if g in seen and seen[g][0] != ch:
                    raise SystemExit(f"officer ${i:02X} {name}: original glyph {g} is "
                                     f"{seen[g][0]} in officer ${seen[g][1]:02X}")
                seen.setdefault(g, (ch, i))
                if glyph_of.setdefault(ch, g) != g and {g, glyph_of[ch]} != NAME_GLYPH_TWINS.get(ch):
                    raise SystemExit(f"officer ${i:02X} {name}: {ch} is original glyph {g} here, "
                                     f"{glyph_of[ch]} elsewhere")
    _NAMES.update(out)
    return out


def ui_kanji() -> list[str]:
    """Every UI kanji in first-use order: labels, commands, word list, then
    the map UI's words, labels and places, then the officer names."""
    out: list[str] = []
    text = (UI_LABELS + UI_COMMANDS + "".join(k for _, _, k in wordlist())
            + "".join(k for _, _, k in MAP_UI_WORDS) + "".join(MAP_UI_LABELS)
            + "".join(BOOT_MENU.values()) + NAME_TITLE
            + "".join(k for _, k in map_places().values())
            + "".join(officer_names().values()))
    for ch in KANJI_RE.findall(text):
        if ch not in out:
            out.append(ch)
    return out


GLYPHS_PER_BANK = 359          # glyphs per hack bank (32 tables x 359)
GLYPH_BANKS_MAX = 8            # banks 23-30
MAX_GLYPHS = GLYPHS_PER_BANK * GLYPH_BANKS_MAX


def code_of(index: int) -> int:
    """Text code of inventory entry `index`: bank n holds codes n*512 + 0..358,
    so the NMI reads the bank from the code's high byte directly.  Codes
    0-511 use the 2-byte escape $EC/$ED lo, the rest $EE hi lo."""
    return (index // GLYPHS_PER_BANK) * 512 + index % GLYPHS_PER_BANK


def code_map() -> dict[str, int]:
    return {ch: code_of(i) for i, (ch, _) in enumerate(inventory())}


# Glyphs (the user's choice, 2026-11-12): every kanji is Izumi16's own
# 16-pixel bitmap (JF-Dot-Izumi16.ttf, the 出水 bitmap font series, which its
# authors declare equivalent to public domain): the EBDT strike at 16 ppem,
# never rendered from the outlines.  Izumi16 draws kanji in a 15 x 15 box at
# columns 1-15, rows 0-14; the box is anchored bottom right in the 16 x 16
# cell (the user, 2026-11-12: columns 1-15 as drawn, moved one row down to
# rows 1-15), so a kanji keeps a free column on its left and a free row
# above.
GLYPH_FONT = ROOT / "JF-Dot-Izumi16.ttf"
FALLBACK_USED: dict[str, str] = {}
_GF: dict = {}


def _glyph_font() -> dict:
    if not _GF:
        from fontTools.ttLib import TTFont
        font = TTFont(str(GLYPH_FONT))
        eblc, ebdt = font["EBLC"], font["EBDT"]
        i = next(n for n, st in enumerate(eblc.strikes) if st.bitmapSizeTable.ppemY == 16)
        subs = {}
        for sub in eblc.strikes[i].indexSubTables:
            for name in sub.names:
                subs[name] = sub
        _GF.update(cmap=font.getBestCmap(), data=ebdt.strikeData[i], subs=subs,
                   asc=eblc.strikes[i].bitmapSizeTable.hori.ascender)
    return _GF


def font_rows(ch: str) -> list[list[int]] | None:
    """Izumi16's 16 ppem bitmap of ch, its 15 x 15 box anchored bottom right
    (column 0 and row 0 blank), as 16 rows of 16 pixels; None when the
    strike has no bitmap for it."""
    m = _glyph_font()
    name = m["cmap"].get(ord(ch))
    glyph = m["data"].get(name) if name else None
    if glyph is None:
        return None
    sub = m["subs"][name]
    if sub.imageFormat not in (5, 7):
        raise SystemExit(f"{ch}: Izumi16 bitmap format {sub.imageFormat}")
    met = sub.metrics if sub.indexFormat in (2, 5) else glyph.metrics
    bits = "".join(f"{b:08b}" for b in glyph.imageData)  # bit-aligned rows
    out = [[0] * 16 for _ in range(16)]
    for y in range(met.height):
        for x in range(met.width):
            if bits[y * met.width + x] == "1":
                yy, xx = m["asc"] - met.horiBearingY + y + 1, met.horiBearingX + x
                if not (0 <= yy < 16 and 0 <= xx < 16):
                    raise SystemExit(f"{ch}: Izumi16 bitmap outside the 16 x 16 cell")
                out[yy][xx] = 1
    return out


# Kanji Izumi16 lacks: built from parts of its bitmaps (as font_rows gives
# them).  A part: (donor kanji, columns c0-c1, rows r0-r1, placed at x, y,
# the part's columns dropped); then the pixels erased.
GLYPH_COMPOSE = {
    # 璝: 理's 王 (columns 1-5, rows 1-14: row 15 is 里's base), then 潰's 貴
    # two columns narrower (one column dropped each side of 中's centre) from
    # column 7, so a free column stays between them; column 0 and row 0 stay
    # blank.
    "璝": ((("理", 1, 5, 1, 14, 1, 1, ()), ("潰", 5, 15, 0, 15, 7, 0, (3, 7))), ()),
}


def composed_rows(ch: str) -> list[list[int]] | None:
    if ch not in GLYPH_COMPOSE:
        return None
    parts, erase = GLYPH_COMPOSE[ch]
    out = [[0] * 16 for _ in range(16)]
    for donor, c0, c1, r0, r1, x0, y0, drop in parts:
        src = font_rows(donor)
        if src is None:
            raise SystemExit(f"{ch}: donor {donor} has no Izumi16 bitmap")
        cols = [c for c in range(c0, c1 + 1) if c - c0 not in drop]
        for y in range(r0, r1 + 1):
            for x, c in enumerate(cols):
                if src[y][c]:
                    out[y0 + y - r0][x0 + x] = 1
    for x, y in erase:
        out[y][x] = 0
    return out


def glyph_available(ch: str) -> bool:
    return ch in GLYPH_COMPOSE or font_rows(ch) is not None


def glyph_bytes(ch: str) -> bytes:
    """One kanji as 32-byte 1bpp: 16 rows x 2 bytes (left, right).  Izumi16's
    bitmap, else a GLYPH_COMPOSE composite; else blank, recorded as "none"
    (the font build fails)."""
    rows = font_rows(ch)
    if rows is None and ch in GLYPH_COMPOSE:
        rows = composed_rows(ch)
        FALLBACK_USED[ch] = "composed from Izumi16 bitmaps"
    if rows is None:
        FALLBACK_USED[ch] = "none"
        return bytes(32)
    out = bytearray()
    for row in rows:
        left = sum(0x80 >> x for x in range(8) if row[x])
        right = sum(0x80 >> x for x in range(8) if row[8 + x])
        out += bytes((left, right))
    return bytes(out)


def write_index() -> list[tuple[str, int]]:
    inv = inventory()
    INDEX_TSV.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# code\tchar\tcount"]
    for i, (ch, n) in enumerate(inv):
        lines.append(f"{i:04X}\t{ch}\t{n}")
    INDEX_TSV.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return inv
