#!/usr/bin/env python3
"""Prepare the kana source for the revision-14 kanji re-conversion.

Writes out/reconv/:
  source_all.txt      every message: label, original kana text with
                      WORD/PLACE/ITEM/NAME:xx expanded, '/' = line break,
                      '▼' = wait (<PAGE>); runtime tokens kept as <...>
  batch_NN.txt        the same, split into conversion batches
  glossary_input.txt  katakana words, dictionary/place/item entries and the
                      officer names used, with counts and one example each
  tokens.json         per label: the runtime tokens it must keep
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kanji_text as kt  # noqa: E402
import textdata  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out" / "reconv"
RUNTIME = re.compile(r"<(NAME_F[3-7]|CALL:[0-9A-F]{4}(?:=[^>]*)?|JUMP:[0-9A-F]{4}|WAIT|END|END_NOWAIT)>")


def table_text(kind: str, idx: int) -> str:
    if kind == "NAME":
        data = kt.name_table_entry(idx)
    else:
        table = {"WORD": textdata.dictionary_entries, "PLACE": textdata.place_entries,
                 "ITEM": textdata.item_entries}[kind]()
        data = table.get(idx, b"")
    s = textdata.encode_record(data)
    s = re.sub(r"<[0-9A-F]{2}:(.)>", r"\1", s)    # alternate codes such as <D5:ド>
    return re.sub(r"<[^>]*>", "", s)


def expand(text: str, used: Counter, examples: dict) -> str:
    def rep(m: re.Match) -> str:
        kind, idx = m.group(1), int(m.group(2), 16)
        s = table_text(kind, idx)
        used[(kind, idx, s)] += 1
        return s
    text = re.sub(r"<(WORD|PLACE|ITEM|NAME):([0-9A-F]{2})(?:=[^>]*)?>", rep, text)
    text = re.sub(r"<[0-9A-F]{2}:(.)>", r"\1", text)
    text = text.replace("<NL>", "/").replace("<NL2>", "/").replace("<PAGE>", "▼")
    return text


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    used: Counter = Counter()
    examples: dict = {}
    rows = []
    for bank in (10, 11):
        for rec in kt.parse_dtx(ROOT / "decomp" / "text" / f"bank{bank}_messages.dtx"):
            src = expand(rec.text, used, examples)
            rows.append((rec.labels, src, RUNTIME.findall(rec.text)))
    lines = []
    tokens = {}
    for labels, src, rt in rows:
        lines.append("@" + " ".join(labels))
        lines.append(src)
        lines.append("")
        tokens[labels[0]] = rt
    (OUT / "source_all.txt").write_text("\n".join(lines), encoding="utf-8")
    (OUT / "tokens.json").write_text(json.dumps(tokens, ensure_ascii=False, indent=1), encoding="utf-8")
    # batches of consecutive messages (context stays together)
    nb = 8
    per = (len(rows) + nb - 1) // nb
    for b in range(nb):
        part = rows[b * per:(b + 1) * per]
        out = []
        for labels, src, _ in part:
            out += ["@" + " ".join(labels), src, ""]
        (OUT / f"batch_{b:02d}.txt").write_text("\n".join(out), encoding="utf-8")
    # glossary input: katakana runs + table entries
    kata = Counter()
    kex = {}
    for labels, src, _ in rows:
        for w in re.findall(r"[ァ-ヶー]{2,}", re.sub(r"<[^>]*>", "", src)):
            kata[w] += 1
            kex.setdefault(w, src[:80])
    g = ["# katakana words (count, example)"]
    for w, n in kata.most_common():
        g.append(f"KATA\t{w}\t{n}\t{kex[w]}")
    g.append("# table entries used by the messages (kind, index, kana, count)")
    for (kind, idx, s), n in sorted(used.items(), key=lambda x: (x[0][0], x[0][1])):
        g.append(f"{kind}\t{idx:02X}\t{s}\t{n}")
    (OUT / "glossary_input.txt").write_text("\n".join(g) + "\n", encoding="utf-8")
    # runtime-name width budget
    maxname = max(len(table_text("NAME", i)) for i in range(256))
    print(f"messages {len(rows)}; batches {nb} x {per}; katakana words {len(kata)}; "
          f"table entries {len(used)}; longest name-table entry {maxname} cells")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
