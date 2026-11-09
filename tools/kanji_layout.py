#!/usr/bin/env python3
"""Lay out the re-converted kanji text (revision 14) into game lines/pages.

Input: decomp/text/kanji_r14/batch_NN.txt (agent output: one line per message with
`|` phrase boundaries, 、。 punctuation, `▼` waits, `/` forced breaks).
Output: decomp/text/kanji_plan/bank1X_messages_kanji_r14.dtx, the compiler's
source, with <NL>/<NL2>/<PAGE> placed by rule:

- a line holds 18 cells; the line after <NL> or <PAGE> starts with the
  engine's one-cell indent (17 left); kanji are 2 cells, kana 1;
- dialogue (a part that the original laid out with <NL>) breaks lines with
  <NL> so continuation lines align after 「; narration uses <NL2>;
- 、 and a mid-line 。 become one space; at a line end they are dropped;
  ！？ followed by more text on the same line get one space;
- waits: the writer's ▼ (sentence ends) are kept; when more than three
  lines would pass without a wait, one is added at the latest sentence end
  that fits, else the latest clause (、), else the latest phrase boundary.

Usage: python -I tools/kanji_layout.py [--report out/reconv/layout_report.txt]
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import kanji_text as kt  # noqa: E402
import textdata  # noqa: E402

REC = ROOT / "out" / "reconv"
SRC = ROOT / "decomp" / "text" / "kanji_r14"      # converted batches (tracked)
PLAN = ROOT / "decomp" / "text" / "kanji_plan"
LINE = 18
LINES_PER_WAIT = 3
KANJI = re.compile(r"[々㐀-鿿豈-﫿]")
TOKEN = re.compile(r"<[^<>]*>")
END_TOKENS = ("<END>", "<END_NOWAIT>")
FALLTHROUGH: list[str] = []


def runtime_width(tok: str) -> int:
    key = tok[1:-1]
    if key == "NAME_F3":
        return ITEM_MAX
    if key.startswith("NAME_F"):
        return NAME_MAX
    if key.startswith("CALL:"):
        pick = kt.KANJI_CALLS.get(int(key[5:9], 16))
        if pick:                # compiled as two kanji (kanji pick)
            return 2 * max(len(pick[1]), len(pick[2]))
        troop = kt.KANJI_TROOP_CALLS.get(int(key[5:9], 16))
        if troop:               # a name, then the longer variant
            return NAME_MAX + max(sum(char_width(c) for c in v) for v in troop[1:])
        ann = key.split("=", 1)[1] if "=" in key else ""
        return max(len(ann), ITEM_MAX)
    return 0


def _table_max() -> tuple[int, int]:
    names = []
    for i in range(256):
        try:
            s = re.sub(r"<[^>]*>", "", textdata.encode_record(kt.name_table_entry(i)))
        except Exception:
            continue
        if 0 < len(s) <= 10:
            names.append(len(s))
    items = []
    for data in textdata.item_entries().values():
        try:
            s = re.sub(r"<[^>]*>", "", textdata.encode_record(data))
        except Exception:
            continue
        if 0 < len(s) <= 12:
            items.append(len(s))
    return max(names), max(items)


NAME_MAX, ITEM_MAX = _table_max()


def char_width(ch: str) -> int:
    return 2 if KANJI.match(ch) else 1


@dataclass
class Seg:
    toks: list[str]          # visible chars and runtime tokens
    tail: str = ""           # "", "、", "。", "！", "？" (break opportunity after)
    hard: str = ""           # "", "/", "▼", "<WAIT>" (after this segment)

    @property
    def width(self) -> int:
        return sum(runtime_width(t) if t.startswith("<") else char_width(t) for t in self.toks)


def split_body(body: str) -> tuple[list[Seg], list[str]]:
    """Body -> segments + trailing control tokens (<END>, <JUMP:..>)."""
    items = []
    i = 0
    while i < len(body):
        if body[i] == "<":
            j = body.index(">", i)
            items.append(body[i:j + 1])
            i = j + 1
        else:
            items.append(body[i])
            i += 1
    trailing: list[str] = []
    while items and (items[-1] in END_TOKENS or items[-1].startswith("<JUMP:")):
        trailing.insert(0, items.pop())
    segs: list[Seg] = []
    cur = Seg([])

    def close(tail: str = "", hard: str = "") -> None:
        nonlocal cur
        if cur.toks or (hard and not segs):
            cur.tail = cur.tail or tail
            cur.hard = hard or cur.hard
            segs.append(cur)
        elif segs:
            if tail and not segs[-1].tail:
                segs[-1].tail = tail
            if hard:
                segs[-1].hard = hard
        cur = Seg([])

    for k, it in enumerate(items):
        nxt = items[k + 1] if k + 1 < len(items) else ""
        if it == "|":
            close()
        elif it in ("/", "▼", "<WAIT>"):
            close(hard=it)
        elif it in ("、", "。"):
            close(tail=it)
        elif it in ("！", "？"):
            cur.toks.append(it)
            if nxt not in ("！", "？", "-", "|", "/", "▼", "、", "。") and nxt:
                close(tail=it)
        else:
            cur.toks.append(it)
    close()
    return segs, trailing


def wrap(segs: list[Seg], first_cap: int, cap: int) -> list[list[Seg]]:
    """Greedy wrap of segments into lines (no hard breaks inside)."""
    lines: list[list[Seg]] = [[]]
    width = 0
    limit = first_cap
    for s in segs:
        sep = 1 if lines[-1] and lines[-1][-1].tail else 0
        if lines[-1] and width + sep + s.width > limit:
            lines.append([])
            width, limit, sep = 0, cap, 0
        if not lines[-1] and s.width > limit:
            # one over-long phrase: split it by characters
            part = Seg([])
            for t in s.toks:
                w = runtime_width(t) if t.startswith("<") else char_width(t)
                if part.toks and part.width + w > limit:
                    lines[-1].append(part)
                    lines.append([])
                    part = Seg([])
                    limit = cap
                part.toks.append(t)
            part.tail = s.tail
            lines[-1].append(part)
            width = part.width
            continue
        lines[-1].append(s)
        width += sep + s.width
    return [l for l in lines if l]


def render_line(line: list[Seg]) -> str:
    out = []
    for k, s in enumerate(line):
        out.append("".join(s.toks))
        if s.tail and k + 1 < len(line):
            out.append("　")
    return "".join(out)


def paginate(segs: list[Seg], first_cap: int, cap: int) -> list[list[list[Seg]]]:
    """Split a wait-free run of segments into pages of <= 3 lines."""
    pages = []
    rest = segs
    fcap = first_cap
    while rest:
        lines = wrap(rest, fcap, cap)
        if len(lines) <= LINES_PER_WAIT:
            pages.append(lines)
            break
        # candidate split points: after segment k, if the first k+1 segments
        # wrap into <= 3 lines
        best = None
        for k in range(len(rest) - 1):
            if len(wrap(rest[:k + 1], fcap, cap)) > LINES_PER_WAIT:
                break
            tail = rest[k].tail
            rank = 3 if tail in ("。", "！", "？") or "".join(rest[k].toks).endswith("-") else (2 if tail == "、" else 1)
            if best is None or rank >= best[0]:
                best = (rank, k)
        k = best[1] if best else 0
        pages.append(wrap(rest[:k + 1], fcap, cap))
        rest = rest[k + 1:]
        fcap = 17                    # the line after <PAGE> is indented
    return pages


@dataclass
class Out:
    toks: list[str] = field(default_factory=list)
    lines: int = 0
    waits: int = 0
    added_waits: int = 0
    mid_waits: int = 0


def original_modes(text: str) -> list[str]:
    """Per <WAIT>-separated part of the original: 'dlg' if it breaks lines
    with <NL> (or opens with 「), else 'nar'."""
    parts = text.split("<WAIT>")
    modes = []
    for p in parts:
        v = re.sub(r"<(NAME|WORD|PLACE|ITEM|CALL|JUMP)[^>]*>", "x", p)
        first_nl = re.search(r"<(NL|NL2|PAGE)>", v)
        if v.lstrip().startswith("「") or (first_nl and first_nl.group(1) in ("NL", "PAGE") and "<NL2>" not in v[:first_nl.end()]):
            modes.append("dlg")
        else:
            modes.append("nar")
    return modes


def layout(body: str, orig: str) -> Out:
    segs, trailing = split_body(body)
    modes = original_modes(orig)
    out = Out()
    part = 0
    # runs separated by hard breaks
    run: list[Seg] = []
    cap_next = LINE                      # capacity of the next line start
    pending_nl = None

    def mode() -> str:
        return modes[min(part, len(modes) - 1)]

    def flush(hard: str) -> None:
        nonlocal run, cap_next, pending_nl, part
        if run:
            dlg = mode() == "dlg"
            cont = 17 if dlg else LINE
            pages = paginate(run, cap_next, cont)
            for pi, page in enumerate(pages):
                if pi > 0:
                    out.toks.append("<PAGE>")
                    out.waits += 1
                    out.added_waits += 1
                    last = page_last[-1] if (page_last := pages[pi - 1][-1]) else None
                    if last is not None and not (last.tail in ("。", "！", "？") or "".join(last.toks).endswith("-")):
                        out.mid_waits += 1
                for li, line in enumerate(page):
                    if li > 0:
                        out.toks.append("<NL>" if dlg else "<NL2>")
                    out.toks.append(render_line(line))
                    out.lines += 1
            run = []
        if hard == "▼":
            out.toks.append("<PAGE>")
            out.waits += 1
            cap_next = 17
        elif hard == "<WAIT>":
            out.toks.append("<WAIT>")
            out.waits += 1
            part += 1
            cap_next = LINE
        elif hard == "/":
            dlg = mode() == "dlg"
            out.toks.append("<NL>" if dlg else "<NL2>")
            cap_next = 17 if dlg else LINE
        else:
            cap_next = 17

    first = True
    for s in segs:
        if first:
            cap_next = LINE
            first = False
        run.append(s)
        if s.hard:
            flush(s.hard)
    flush("")
    # a hard break right before the end: drop the dangling separator
    while out.toks and out.toks[-1] in ("<NL>", "<NL2>"):
        out.toks.pop()
    # The engine runs <JUMP> at the start of a line: keep the original's
    # line-ending control in front of it (mostly <NL2>).
    if trailing and trailing[0].startswith("<JUMP:"):
        m = re.search(r"(<NL>|<NL2>|<PAGE>|<WAIT>)<JUMP:", orig)
        if m and out.toks and out.toks[-1] not in ("<PAGE>", "<WAIT>", "<NL>", "<NL2>"):
            out.toks.append(m.group(1))
    out.toks += trailing
    return out


def read_blocks(path: Path) -> list[tuple[list[str], str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    out = []
    i = 0
    while i < len(lines):
        if lines[i].startswith("@"):
            out.append((lines[i][1:].split(), lines[i + 1] if i + 1 < len(lines) else ""))
            i += 2
        else:
            i += 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", type=Path, default=REC / "layout_report.txt")
    ap.add_argument("--suffix", default="r14")
    ap.add_argument("--force", action="store_true",
                    help="overwrite existing dtx files (they are hand-edited sources)")
    args = ap.parse_args()
    targets = [PLAN / f"bank{bank}_messages_kanji_{args.suffix}.dtx" for bank in (10, 11)]
    existing = [t for t in targets if t.exists()]
    if existing and not args.force:
        print("refusing to overwrite hand-edited text: " + ", ".join(str(t) for t in existing)
              + " (use --force, or another --suffix)")
        return 2
    orig = {}
    for bank in (10, 11):
        for rec in kt.parse_dtx(ROOT / "decomp" / "text" / f"bank{bank}_messages.dtx"):
            orig[rec.labels[0]] = rec.text
    blocks = []
    for p in sorted(SRC.glob("batch_*.txt")):
        blocks += read_blocks(p)
    # Records without a terminator fall through into the next record's bytes
    # in the original ROM.  The kanji banks store page data after each
    # message, so the continuation is appended to the record itself.
    order: dict[str, str] = {}
    for bank in (10, 11):
        recs = kt.parse_dtx(ROOT / "decomp" / "text" / f"bank{bank}_messages.dtx")
        for a, b in zip(recs, recs[1:]):
            order[a.labels[0]] = b.labels[0]
    body_of = {labels[0]: body.strip() for labels, body in blocks}
    term = re.compile(r"(<END>|<END_NOWAIT>|<JUMP:[0-9A-F]{4}>)\s*$")

    def joined(label: str, depth: int = 0) -> tuple[str, str]:
        body, src = body_of[label], orig.get(label, "")
        if term.search(src) or not src.strip() or depth > 4 or label not in order:
            return body, src
        nb, ns = joined(order[label], depth + 1)
        sep = "" if src.rstrip().endswith("<WAIT>") else ("▼" if src.rstrip().endswith("<PAGE>") else "/")
        FALLTHROUGH.append(f"{label} -> {order[label]}")
        return body + sep + nb, src + ns
    joined_blocks = []
    for labels, body in blocks:
        b, src = joined(labels[0])
        joined_blocks.append((labels, b))
        orig[labels[0]] = src
    blocks = joined_blocks
    by_bank: dict[int, list[str]] = {10: [], 11: []}
    report = []
    tot = Out()
    over = 0
    for labels, body in blocks:
        res = layout(body.strip(), orig.get(labels[0], ""))
        text = "".join(res.toks)
        # width check (the compiler re-checks)
        for li, line in enumerate(re.split(r"<NL>|<NL2>|<PAGE>|<WAIT>", text)):
            v = TOKEN.sub(lambda m: "x" * runtime_width(m.group(0)), line)
            w = sum(char_width(c) for c in v)
            if w > LINE:
                over += 1
                report.append(f"OVER {labels[0]} line {li}: {w} cells")
        bank = 10 if labels[0].startswith("b10_") else 11
        block = "".join(f"{l}:\n" for l in labels) + f'    "{text}"\n'
        by_bank[bank].append(block)
        for k in ("lines", "waits", "added_waits", "mid_waits"):
            setattr(tot, k, getattr(tot, k) + getattr(res, k))
        if res.mid_waits:
            report.append(f"MIDWAIT {labels[0]}: {res.mid_waits} wait(s) inside a sentence")
    for bank, recs in by_bank.items():
        head = (f"# Tenchi o Kurau dialogue bank {bank} -- kanji text, revision 14\n"
                "#\n# Generated by tools/kanji_layout.py from out/reconv/out/batch_*.txt.\n"
                "# Edit the batch files (or this file) and rebuild.\n\n")
        (PLAN / f"bank{bank}_messages_kanji_{args.suffix}.dtx").write_text(head + "\n".join(recs), encoding="utf-8")
    summary = (f"messages {len(blocks)}, lines {tot.lines}, waits {tot.waits} "
               f"(added {tot.added_waits}, inside a sentence {tot.mid_waits}), "
               f"lines over {LINE} cells {over}; name width {NAME_MAX}, item width {ITEM_MAX}")
    report += ["FALLTHROUGH " + x for x in FALLTHROUGH]
    args.report.write_text(summary + "\n" + "\n".join(report) + "\n", encoding="utf-8")
    print(summary)
    return 1 if over else 0


if __name__ == "__main__":
    raise SystemExit(main())
