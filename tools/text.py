#!/usr/bin/env python3
"""Export, compile, and verify the editable message-bank text.

Commands:
    python tools/text.py export   # ROM -> decomp/text/bankNN_messages.dtx
    python tools/text.py build    # .dtx -> decomp/build/text/bankNN_*.inc
    python tools/text.py verify   # .dtx -> compare with original ROM
"""
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

from textdata import (
    BANK_INFO,
    BYTE_TO_CHAR,
    CHAR_TO_BYTE,
    TextBank,
    bank_bytes,
    decode_record,
    encode_record,
    parse_bank,
)

ROOT = Path(__file__).resolve().parent.parent
TEXT_DIR = ROOT / "decomp" / "text"
BUILD_DIR = ROOT / "decomp" / "build" / "text"


def dtx_name(bank: int) -> Path:
    return TEXT_DIR / f"bank{bank:02d}_messages.dtx"


def export_bank(bank: int) -> None:
    tb = parse_bank(bank)
    lines = [
        f"# Tenchi o Kurau message bank {bank:02d}",
        "#",
        "# Edit the quoted strings, then run: python decomp/build.py",
        "#",
        "# Literal characters map to the game's 8x8 font.  High bytes $80-$EE",
        "# are dakuten/handakuten combinations (for example 0x90 = が, 0xD5 = ド).",
        "# The full tile table is in tools/textdata.py (FONT_ROWS).",
        "#",
        "# Named tokens:",
        "#   <NL>          $FA  new line, with the automatic indent",
        "#   <NLNI>        $FB  new line, no indent",
        "#   <PAGE>        $FC  page break: wait for the player, the next line indented",
        "#   <PAGENI>      $FD  page break: wait for the player, no indent",
        "#   <END>         $FF  end of message",
        "#   <END_NOWAIT>  $FE  end without waiting",
        "#   <NAME_F3>..<NAME_F7>  insert a runtime name",
        "#   <NAME:xx>     $F2 xx  insert the name of party slot xx",
        "#   <WORD:xx=...> $F0 xx  dictionary word xx",
        "#   <PLACE:xx=...> $EF xx place-name entry xx",
        "#   <ITEM:xx=...> $F1 xx item-name entry xx",
        "#   <CALL:xxxx>   $F8 xx xx  call the print helper at xxxx",
        "#   <JUMP:xxxx>   $F9 xx xx  jump to the script at xxxx",
        "#   <FRAME_...>   frame/tab tiles from the font",
        "#   <XX>          one raw byte",
        "#   <XX:char>     an alternate byte for a character (for example",
        "#                 <D5:ド>), used when the same glyph has two codes",
        "#",
        "# Text after '=' in a WORD/PLACE/ITEM/CALL token is only an annotation;",
        "# the compiler ignores it and emits the original two-byte reference.",
        "# The compiler rebuilds the message bytes and the split low/high pointer",
        "# table; changing a string length automatically moves later messages.",
        "#",
        f"# data starts at ${tb.data_start:04X}; {tb.count} table entries;",
        f"# {len(tb.records)} unique records.",
        "",
    ]
    for rec in tb.records:
        idx = ",".join(str(i) for i in rec.indices)
        lines.append(f"# {tb.label(rec.indices[0])}  ${rec.start:04X}  len={len(rec.data)}  refs={idx}")
        for i in rec.indices:
            lines.append(f"{tb.label(i)}:")
        if rec.data:
            lines.append(f'    "{encode_record(rec.data)}"')
        else:
            lines.append('    ""')
        lines.append("")
    TEXT_DIR.mkdir(parents=True, exist_ok=True)
    dtx_name(bank).write_text("\n".join(lines), encoding="utf-8")
    print(f"exported {dtx_name(bank)} ({len(tb.records)} records)")


@dataclass
class DtxRecord:
    labels: list[str]
    data: bytes


def parse_dtx(path: Path) -> list[DtxRecord]:
    records: list[DtxRecord] = []
    pending: list[str] = []
    strings: list[str] = []
    text = path.read_text(encoding="utf-8")

    def flush():
        nonlocal pending, strings
        if not pending:
            return
        data = decode_record("".join(strings))
        records.append(DtxRecord(pending, data))
        pending = []
        strings = []

    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):$", line)
        if m:
            if strings:
                flush()
            pending.append(m.group(1))
            continue
        m = re.match(r'^"(.*)"$', line)
        if m:
            if not pending:
                raise ValueError(f"{path}:{lineno}: string without a label")
            strings.append(m.group(1))
            continue
        raise ValueError(f"{path}:{lineno}: expected 'label:' or '\"...\"'")
    flush()
    return records


def compile_bank(bank: int, records: list[DtxRecord]) -> tuple[bytes, bytes]:
    """Return (table_bytes, data_bytes) for one bank."""
    info = BANK_INFO[bank]
    count = info["count"]
    by_index: dict[int, DtxRecord] = {}
    label_to_record: dict[str, DtxRecord] = {}
    for rec in records:
        for label in rec.labels:
            if label in label_to_record:
                raise ValueError(f"duplicate label {label}")
            label_to_record[label] = rec
            m = re.match(rf"^b{bank:02d}_msg_(\d{{3}})$", label)
            if m:
                idx = int(m.group(1))
                if idx >= count:
                    raise ValueError(f"{label}: index {idx} >= {count}")
                by_index[idx] = rec
    missing = [i for i in range(count) if i not in by_index]
    if missing:
        raise ValueError(f"bank {bank}: missing table indices {missing[:10]}")

    data = bytearray()
    for rec in records:
        data += rec.data
    tail = bytearray(bank_bytes(bank)[info["tail"]:])
    max_len = 0x4000 - info["data"]
    # If edited text grows, consume trailing padding (00/FF) from the tail
    # first instead of failing immediately.
    while len(data) + len(tail) > max_len and tail and tail[-1] in (0x00, 0xFF):
        tail.pop()
    # Some banks put padding at the start of the tail; consume that too.
    while len(data) + len(tail) > max_len and tail and tail[0] in (0x00, 0xFF):
        tail = tail[1:]
    data += tail
    if len(data) > max_len:
        raise ValueError(
            f"bank {bank}: messages + tail are {len(data)} bytes, "
            f"max {max_len}"
        )
    data += b"\x00" * (max_len - len(data))

    # Split pointer table: low array, gap, high array.
    lo = bytearray()
    hi = bytearray()
    # Addresses are needed for verification only.
    addresses = []
    addr = info["data"] + 0x8000
    for rec in records:
        addresses.append(addr)
        addr += len(rec.data)
    rec_addr = {id(rec): a for rec, a in zip(records, addresses)}
    for i in range(count):
        a = rec_addr[id(by_index[i])]
        lo.append(a & 0xFF)
        hi.append((a >> 8) & 0xFF)
    gap = bank_bytes(bank)[info["lo"] + count:info["hi"]]
    table = bytes(lo) + gap + bytes(hi)
    return table, bytes(data)


def build_includes(bank: int, records: list[DtxRecord], table: bytes, data: bytes) -> None:
    info = BANK_INFO[bank]
    count = info["count"]
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # Table include uses assembler low/high operators so label movement is
    # resolved automatically.
    tlines = [
        f"; generated by tools/text.py from bank{bank:02d}_messages.dtx",
        f"b{bank:02d}_msg_table_lo:",
    ]
    labels = [f"b{bank:02d}_msg_{i:03d}" for i in range(count)]
    for i in range(0, count, 16):
        tlines.append("    .db " + ", ".join("<" + x for x in labels[i:i+16]))
    gap = bank_bytes(bank)[info["lo"] + count:info["hi"]]
    tlines.append(f"b{bank:02d}_msg_table_gap:")
    for i in range(0, len(gap), 16):
        tlines.append("    .db " + ",".join(f"${x:02X}" for x in gap[i:i+16]))
    tlines.append(f"b{bank:02d}_msg_table_hi:")
    for i in range(0, count, 16):
        tlines.append("    .db " + ", ".join(">" + x for x in labels[i:i+16]))
    tlines.append("")
    (BUILD_DIR / f"bank{bank:02d}_table.inc").write_text("\n".join(tlines), encoding="utf-8")

    # Data include: labels + exact bytes + original tail + padding.
    dlines = [f"; generated by tools/text.py from bank{bank:02d}_messages.dtx"]
    used = 0
    for rec in records:
        for label in rec.labels:
            dlines.append(f"{label}:")
        for i in range(0, len(rec.data), 16):
            dlines.append("    .db " + ",".join(f"${x:02X}" for x in rec.data[i:i+16]))
        used += len(rec.data)
    tail = data[used:]
    dlines.append(f"b{bank:02d}_text_tail:")
    for i in range(0, len(tail), 16):
        dlines.append("    .db " + ",".join(f"${x:02X}" for x in tail[i:i+16]))
    (BUILD_DIR / f"bank{bank:02d}_data.inc").write_text("\n".join(dlines) + "\n", encoding="utf-8")
    print(f"built {BUILD_DIR / f'bank{bank:02d}_table.inc'} and data include")


def write_index_symbols() -> None:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["; generated by tools/text.py -- message-table index constants"]
    for bank in (10, 11):
        for i in range(BANK_INFO[bank]["count"]):
            value = i if bank == 10 else 0x0200 + i
            lines.append(f"b{bank:02d}_msg_index_{i:03d} = ${value:04X}")
    (BUILD_DIR / "index_symbols.inc").write_text("\n".join(lines) + "\n", encoding="utf-8")


def build() -> int:
    for bank in (10, 11):
        records = parse_dtx(dtx_name(bank))
        table, data = compile_bank(bank, records)
        build_includes(bank, records, table, data)
    write_index_symbols()
    return 0


def verify() -> int:
    ok = True
    for bank in (10, 11):
        records = parse_dtx(dtx_name(bank))
        table, data = compile_bank(bank, records)
        info = BANK_INFO[bank]
        orig = bank_bytes(bank)
        want_table = orig[:info["data"]]
        want_data = orig[info["data"]:]
        if table != want_table:
            first = next((i for i in range(min(len(table), len(want_table))) if table[i] != want_table[i]), None)
            print(f"FAIL bank {bank}: table differs at +0x{first:X}")
            ok = False
        if data != want_data:
            first = next((i for i in range(min(len(data), len(want_data))) if data[i] != want_data[i]), None)
            print(f"FAIL bank {bank}: data differs at +0x{first:X}")
            ok = False
        if table == want_table and data == want_data:
            print(f"ok   bank {bank}")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["export", "build", "verify"])
    args = ap.parse_args()
    if args.command == "export":
        for bank in (10, 11):
            export_bank(bank)
        return 0
    if args.command == "build":
        return build()
    return verify()


if __name__ == "__main__":
    raise SystemExit(main())
