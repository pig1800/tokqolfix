#!/usr/bin/env python3
"""List the messages whose text makes the engine scroll: a 4th line in the
window before the window is cleared.

    python tools/scroll_scan.py              (all messages)
    python tools/scroll_scan.py b11_msg_044  (only these labels)

The message window shows 3 lines.  The engine (bank 15 $D1B4 / $D1DE)
counts the lines since the window was last cleared: every line ended by
<NL>, <NL2>, <WAIT>, <PAGE> or <END> adds one, and a <PAGE> clears the
window after its wait (a <WAIT> does not, nor does a line break).  At 4
lines it scrolls:
  - "inside": a 4th line ended by <NL> / <NL2> / <WAIT> / <PAGE>;
  - "at the end": the 4th line ended by <END>.
In battle the scroll is the original's.  In map mode the kanji build turns
it into a page break at run time (bank 26's TXF_LOOK with the fixed bank's
map_lines; map_end4 skips the end's scroll: TEXT_RENDERER.md "in map mode a
page break where the engine would scroll").  With no message listed here,
that run-time code has nothing to do.

The scan reads the compiler's source (kanji_common.DTX_FILES, the r14 dtx)
and lays every message out as the build does (kanji_text: reflow's line
wraps, fit_tokens' page splits), so what it shows is what the ROM holds.  A
line break or page break the compiler added, not in the source, is marked
"(auto)".
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import kanji_text as kt                                   # noqa: E402
from kanji_common import DTX_FILES, code_map              # noqa: E402

ENDS = ("<NL>", "<NL2>", "<WAIT>", "<PAGE>", "<END>", "<END_NOWAIT>")


def compiled_tokens(rec, cmap) -> list[str]:
    """The tokens the build compiles for this record (kanji_text.build)."""
    extra = kt.extra_for(rec)
    tokens = kt.reflow(kt.tokenize(rec.text))
    try:
        return kt.fit_tokens(rec, tokens, extra, False, cmap)[3]
    except RuntimeError:
        return kt.fit_tokens(rec, tokens, extra, True, cmap)[3]


def auto_marks(src: list[str], out: list[str]) -> dict[int, str]:
    """Indexes of out's controls the compiler added or changed (reflow
    inserts <NL2>; a page split turns a line end into <PAGE>, or inserts
    <NL2><PAGE>)."""
    marks = {}
    i = j = 0
    while j < len(out):
        if i < len(src) and out[j] == src[i]:
            i += 1
        elif i < len(src) and out[j] in ENDS and src[i] in ENDS:
            marks[j] = f"(auto: was {src[i]})"
            i += 1
        else:
            marks[j] = "(auto)"
        j += 1
    return marks


def break_line(window) -> int:
    """Index (0-2) of the line after which the page break goes, as the
    run-time rule does: the last <WAIT> before the 4th line, else the 3rd
    line's end."""
    waits = [k for k in range(3) if window[k][1] == "<WAIT>"]
    return waits[-1] if waits else 2


def walk(tokens: list[str], marks: dict[int, str]):
    """The engine's line count; yields (kind, window, k) at each scroll, the
    window being the 4 lines up then: (text, ending control, mark), and k
    the line after which the break goes.  After an inner scroll the scan goes
    on as if that break were made (as map mode does at run time), so every
    entry is a cause of its own, and making them all leaves no scroll."""
    line = 0
    window: list[tuple[str, str, str]] = []
    cur: list[str] = []
    for j, tok in enumerate(tokens):
        if tok.startswith("<JUMP:"):
            return                      # the message goes on in event code
        if tok not in ENDS:
            cur.append(tok)
            continue
        line += 1
        window.append(("".join(cur), tok, marks.get(j, "")))
        cur = []
        if tok in ("<END>", "<END_NOWAIT>"):
            if tok == "<END>" and line == 4:
                yield "at the end", window[-4:], break_line(window[-4:])
            return
        if line == 4:
            k = break_line(window[-4:])
            yield "inside", window[-4:], k
            window = window[-4:][k + 1:]
            line = len(window)
        if tok == "<PAGE>":
            line = 0
            window = []


def advice(kind: str, window, k: int) -> str:
    text, end = window[k][0], window[k][1]
    tail = text[-8:] if len(text) > 8 else text
    what = f"the {end} after 「…{tail}」 (line {k + 1})"
    if kind == "at the end":
        return f"4 lines at the end: make {what} a <PAGE> (or fit the last page into 3 lines)"
    if end == "<WAIT>":
        return f"make {what} a <PAGE>"
    return f"no <WAIT> before the 4th line: a <PAGE> in place of {what} (or fewer lines)"


def label_lines(path: Path) -> dict[str, int]:
    out = {}
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if s.endswith(":") and not s.startswith(("#", ";", '"')):
            out[s[:-1]] = n
    return out


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    want = set(argv)
    cmap = code_map()
    found = 0
    scanned = 0
    for path in DTX_FILES:
        where = label_lines(path)
        for rec in kt.parse_dtx(path):
            if want and not want & set(rec.labels):
                continue
            scanned += 1
            out = compiled_tokens(rec, cmap)
            marks = auto_marks(kt.tokenize(rec.text), out)
            events = list(walk(out, marks))
            if not events:
                continue
            found += 1
            first = rec.labels[0]
            alias = f" (= {', '.join(rec.labels[1:])})" if len(rec.labels) > 1 else ""
            print(f"{first}{alias}  {path.name}:{where.get(first, '?')}")
            for kind, window, k in events:
                print(f"  scroll {kind}: {advice(kind, window, k)}")
                for n, (text, end, mark) in enumerate(window):
                    flag = "  <- 4th line" if n == 3 else ("  <- break here" if n == k else "")
                    print(f"    {n + 1}. {text}{end}{(' ' + mark) if mark else ''}{flag}")
            print()
    print(f"{found} of {scanned} messages scroll.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
