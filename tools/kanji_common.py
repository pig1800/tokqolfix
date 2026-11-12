#!/usr/bin/env python3
"""Shared kanji inventory/encoding helpers for the SUROM kanji target."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

import textdata

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "decomp" / "text" / "kanji_plan"
FONT_TTF = ROOT / "JF-Dot-Shinonome16.ttf"
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


# Glyphs missing from the primary font are drawn from these, in order, and
# reported by the font builder.  (JF-Dot-Shinonome16 lacks a few JIS X 0212
# characters such as 鄧 and 瓚.)
FALLBACK_FONTS = (
    ROOT / "DotGothic16-Regular.ttf",
    Path("C:/Windows/Fonts/msgothic.ttc"),
)
FALLBACK_USED: dict[str, str] = {}
DOTGOTHIC_DY = 1               # rows to move DotGothic16 glyphs down


def _covers(path: Path, ch: str) -> bool:
    from fontTools.ttLib import TTFont, TTCollection
    try:
        if path.suffix.lower() == ".ttc":
            fonts = TTCollection(str(path)).fonts
        else:
            fonts = [TTFont(str(path))]
    except Exception:
        return False
    return any(ord(ch) in f.getBestCmap() for f in fonts)


def font_for(ch: str) -> Path:
    if _covers(FONT_TTF, ch):
        return FONT_TTF
    for path in FALLBACK_FONTS:
        if path.exists() and _covers(path, ch):
            FALLBACK_USED[ch] = path.name
            return path
    FALLBACK_USED[ch] = "none"
    return FONT_TTF


# Name kanji the primary font lacks (璝: it draws a placeholder) and the
# fallbacks draw poorly: the original game's own name glyph instead (bank 1
# or 2 at index * 32: 8 bytes each of TL, BL, TR, BR), found through the
# officer records.
NAME_GLYPH_ORIGINAL = "傕彧昱汜玠褚詡邕郃鄧闞顗騭龐璝"
_ORIG_GLYPHS: dict[str, tuple[int, int]] = {}


def original_glyph(ch: str) -> bytes | None:
    """The original name glyph of ch as 16 rows x 2 bytes, or None."""
    if not _ORIG_GLYPHS:
        names = officer_names()
        for i, (_p, _k, gl) in officer_records().items():
            if i in names and len(names[i]) == len(gl):
                for g, c in zip(gl, names[i]):
                    _ORIG_GLYPHS.setdefault(c, g)
    g = _ORIG_GLYPHS.get(ch)
    if g is None:
        return None
    d = textdata.prg()[g[0] * 0x4000 + g[1] * 32:][:32]
    out = bytearray()
    for y in range(16):
        q = 0 if y < 8 else 8
        out += bytes((d[q + y % 8], d[16 + q + y % 8]))
    return bytes(out)


def glyph_bytes(ch: str, font_size: int = 16, threshold: int = 128) -> bytes:
    """Render one kanji to 32-byte 1bpp: 16 rows x 2 bytes (left, right)."""
    from PIL import Image, ImageDraw, ImageFont

    if ch in NAME_GLYPH_ORIGINAL:
        g = original_glyph(ch)
        if g is None:
            raise SystemExit(f"{ch}: no original name glyph")
        FALLBACK_USED[ch] = "original name glyph"
        return g

    path = font_for(ch)
    font = ImageFont.truetype(str(path), font_size)
    img = Image.new("L", (16, 16), 0)
    draw = ImageDraw.Draw(img)
    # DotGothic16 sits one pixel higher than Shinonome on the 16x16 grid.
    dy = DOTGOTHIC_DY if path.name.lower().startswith("dotgothic") else 0
    draw.text((0, dy), ch, font=font, fill=255, anchor="lt")
    out = bytearray()
    for y in range(16):
        left = 0
        right = 0
        for x in range(8):
            if img.getpixel((x, y)) >= threshold:
                left |= 0x80 >> x
            if img.getpixel((x + 8, y)) >= threshold:
                right |= 0x80 >> x
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
