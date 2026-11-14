#!/usr/bin/env python3
"""List the messages whose text makes the engine scroll: a 4th line in the
window before a page break clears it.

    python tools/scroll_scan.py              (all messages)
    python tools/scroll_scan.py b11_msg_044  (only these labels)

The line controls (bank 15 $D1A5-$D1CB, $D2C3; the names since 2026-11-14):

    <NL>      $FA  new line, the next line indented one cell ($5F)
    <NLNI>    $FB  new line, no indent                 (was <NL2>)
    <PAGE>    $FC  page break: wait, the next line indented
    <PAGENI>  $FD  page break: wait, no indent         (was <WAIT>)
    <END>     $FF  end

The window shows 3 lines.  The engine counts the lines since the window
was cleared; at a 4th line ended by <NL> / <NLNI> / <PAGE> / <PAGENI> it
scrolls ("inside"), at a 4th line ended by <END> too ("at the end").  The
original game never clears the window: both page codes only wait, and the
lines scroll.  The kanji build clears it after the wait at both page codes
(a page record each), so only 4 lines between page breaks scroll; a page
break that keeps the next line's indent fixes it: a <PAGE> for an <NL>, a
<PAGENI> for an <NLNI>.  In battle a page may share the window with the
lines above when its kanji fit the pool (the original's scroll there).

The scan reads the compiler's source (kanji_common.DTX_FILES, the r14 dtx)
and lays every message out as the build does (kanji_text: reflow's line
wraps, fit_tokens' page splits), so what it shows is what the ROM holds.  A
line or page break the compiler added, not in the source, is marked
"(auto)".
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import kanji_text as kt                                   # noqa: E402
from kanji_common import DTX_FILES, code_map              # noqa: E402

ENDS = ("<NL>", "<NLNI>", "<PAGENI>", "<PAGE>", "<END>", "<END_NOWAIT>")
BREAKS = ("<PAGE>", "<PAGENI>")
KEEP_INDENT = {"<NL>": "<PAGE>", "<NLNI>": "<PAGENI>"}


def compiled_tokens(rec, cmap) -> list[str]:
    """The tokens the build compiles for this record (kanji_text.build)."""
    return kt.fit_tokens(rec, kt.reflow(kt.tokenize(rec.text)), cmap)[2]


def auto_marks(src: list[str], out: list[str]) -> dict[int, str]:
    """Indexes of out's controls the compiler added or changed (reflow
    inserts <NLNI>; a page split turns a line break into a page break, or
    inserts <NLNI><PAGE>)."""
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


def walk(tokens: list[str], marks: dict[int, str]):
    """The engine's line count; yields (kind, window) at each scroll, the
    window being the 4 lines up then: (text, ending control, mark).  After
    an inner scroll the scan goes on as if the 3rd line's break were a page
    break, so every entry is a cause of its own."""
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
                yield "at the end", window[-4:]
            return
        if line == 4:
            yield "inside", window[-4:]
            window = window[-1:]
            line = 1
        if tok in BREAKS:
            line = 0
            window = []


def advice(window) -> str:
    text, end = window[2][0], window[2][1]
    tail = text[-8:] if len(text) > 8 else text
    to = KEEP_INDENT.get(end)
    if to:
        return f"make the 3rd line's {end} (after 「…{tail}」) a {to} (the next line keeps its indent)"
    return f"the 3rd line ends with {end}: a page break there, or fewer lines"


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
            for kind, window in events:
                print(f"  scroll {kind}: {advice(window)}")
                for n, (text, end, mark) in enumerate(window):
                    flag = "  <- 4th line" if n == 3 else ("  <- break here" if n == 2 else "")
                    print(f"    {n + 1}. {text}{end}{(' ' + mark) if mark else ''}{flag}")
            print()
    print(f"{found} of {scanned} messages scroll.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
