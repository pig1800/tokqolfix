#!/usr/bin/env python3
"""Generate the readable, resource-backed ASM6f reconstruction.

The execution-backed trace comes from trace6502.py (Mesen CDL + recursive
control-flow following).  This module turns that trace into:

  * named routines with header comments and call information,
  * local labels for intra-routine branches,
  * explicit data resources included with INCBIN,
  * label files for Mesen.

Graphics are editable PNG resources under assets/.  build.py converts them
back to the exact NES tile bytes before assembling.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom
from trace6502 import (BASES, DEFAULT_CDL, INLINE_WORD_JSR, KNOWN_ENTRIES, inline_block_flow,
                       load_cdl, trace_bank)
from cpu6502 import decode
from symbols import DOCS, HW_NAMES, INLINE_COMMENTS, NAMES, RAM_NAMES, RAM_RANGES
import textdata

ROOT = Path(__file__).resolve().parent.parent
ROM_PATH = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
OUT_DIR = ROOT / "decomp"
ASSETS = ROOT / "assets"
BUILD_ASSETS = OUT_DIR / "build" / "assets"

# A label at the start of each meaningful data region.  These are descriptive
# anchors, not claims that every byte inside is understood.
REGIONS = [
    (0, 0x0000, 0x4000, "b00_chr", "Character/sprite/background tile bank."),
    (1, 0x0000, 0x0010, "b01_header", "Bank 1 padding/header bytes."),
    (1, 0x0010, 0x1A10, "b01_kanji_glyphs", "Raw 16x16 kanji glyphs: 104 glyphs, 64 bytes each."),
    (1, 0x1A10, 0x4000, "b01_chr", "Character/battle-animation tile graphics."),
    (2, 0x0000, 0x0010, "b02_header", "Bank 2 padding/header bytes."),
    (2, 0x0010, 0x0810, "b02_kanji_glyphs", "Raw 16x16 kanji glyphs: 32 glyphs, 64 bytes each."),
    (2, 0x0810, 0x4000, "b02_chr", "Portrait/title tile graphics."),
    (3, 0x0000, 0x4000, "b03_chr", "Title/portrait tile graphics."),
    (4, 0x0000, 0x4000, "b04_chr", "Portrait tile graphics."),
    (5, 0x0000, 0x4000, "b05_chr", "Map chip tile graphics."),
    (6, 0x0000, 0x4000, "b06_map_data", "Map layout/event data."),
    (7, 0x0000, 0x1400, "b07_map_data", "Map movement/event data and tables."),
    (7, 0x1400, 0x1E82, "b07_event_code", "Map/event script interpreter."),
    (7, 0x1E82, 0x4000, "b07_data", "Map/event data and padding."),
    (8, 0x0000, 0x0A50, "b08_sound_driver", "Music/sound driver code."),
    (8, 0x0A50, 0x4000, "b08_sound_data", "Music/sound data and tables."),
    (9, 0x0000, 0x3A00, "b09_ui_graphics", "2bpp UI/window/portrait tile graphics."),
    (9, 0x3A00, 0x3E00, "b09_kana_font", "1bpp dialogue font: 128 8x8 glyphs."),
    (9, 0x3E00, 0x4000, "b09_ui_graphics2", "2bpp UI/status tile graphics."),
    (10, 0x0000, 0x01E8, "b10_msg_ptr_lo", "Message pointer table, low bytes (488 entries)."),
    (10, 0x01E8, 0x0200, "b10_msg_ptr_gap", "Pointer-table gap/auxiliary bytes."),
    (10, 0x0200, 0x03E8, "b10_msg_ptr_hi", "Message pointer table, high bytes (488 entries)."),
    (10, 0x03E8, 0x4000, "b10_messages", "Editable compressed message bytecode."),
    (11, 0x0000, 0x0180, "b11_msg_ptr_lo", "Message pointer table, low bytes (384 entries)."),
    (11, 0x0180, 0x0200, "b11_msg_ptr_gap", "Pointer-table gap/auxiliary bytes."),
    (11, 0x0200, 0x0380, "b11_msg_ptr_hi", "Message pointer table, high bytes (384 entries)."),
    (11, 0x0380, 0x4000, "b11_messages", "Editable compressed message bytecode."),
    (12, 0x0000, 0x4000, "b12_data_tables", "Enemy/town/item/weapon data tables."),
    (13, 0x0000, 0x0800, "b13_data_tables", "Data tables at the start of bank 13."),
    (13, 0x0800, 0x1010, "b13_code_status", "Officer status/name-entry code."),
    (13, 0x1010, 0x1C10, "b13_data", "Bank 13 data region."),
    (13, 0x1C10, 0x2075, "b13_code_name", "Additional status/name-entry code."),
    (13, 0x2075, 0x3710, "b13_code_aux", "Auxiliary gameplay/menu code."),
    (13, 0x3710, 0x3EA8, "b13_dictionary", "Frequent-word/dictionary table."),
    (13, 0x3EA8, 0x4000, "b13_data_tail", "Bank 13 data tail."),
    (14, 0x0000, 0x4000, "b14_bank", "Gameplay/menu bank: code plus embedded tables."),
    (15, 0x0000, 0x2C00, "b15_code", "Fixed-bank main code and tables."),
    (15, 0x2C00, 0x2E79, "b15_text_data", "Inline text/bytecode data in the fixed bank."),
    (15, 0x2E79, 0x3FFA, "b15_code_high", "Fixed-bank code and tables."),
    (15, 0x3FFA, 0x4000, "b15_vectors", "6502 interrupt vectors."),
]

# Resource that covers each bank's data bytes.  The generator emits INCBIN
# slices from these files.  For banks 0-5/9 the PNG resources are the source
# of truth; the build step regenerates the .bin files under
# decomp/build/assets from the PNGs.
BANK_RESOURCE = {
    0: "bank00_chr",
    1: None,          # split between kanji and chr resources
    2: None,
    3: "bank03_chr",
    4: "bank04_chr",
    5: "bank05_chr",
    6: "bank06_map",
    7: "bank07_data",
    8: "bank08_data",
    9: None,
    10: "bank10_messages",
    11: "bank11_messages",
    12: "bank12_tables",
    13: "bank13_data",
    14: "bank14_data",
    15: "bank15_data",
}

# Split resources: (start, end, resource_id).  The offsets are bank offsets.
RESOURCE_SPLITS = {
    1: [(0x0000, 0x0010, "bank01_header"),
        (0x0010, 0x1A10, "bank01_kanji"),
        (0x1A10, 0x4000, "bank01_gfx")],
    2: [(0x0000, 0x0010, "bank02_header"),
        (0x0010, 0x0810, "bank02_kanji"),
        (0x0810, 0x4000, "bank02_gfx")],
    9: [(0x0000, 0x3A00, "bank09_ui_a"),
        (0x3A00, 0x3E00, "bank09_kana"),
        (0x3E00, 0x4000, "bank09_ui_b")],
}

PERIOD = {
    0: 0x400, 1: 0x400, 2: 0x400, 3: 0x400, 4: 0x400, 5: 0x400,
    6: 0x400, 7: 0x400, 8: 0x400, 9: 0x400, 10: 0x400, 11: 0x400,
    12: 0x400, 13: 0x400, 14: 0x400, 15: 0x400,
}

MEMORY_OPS = {
    "lda", "ldx", "ldy", "sta", "stx", "sty", "bit", "asl", "lsr", "rol", "ror",
    "inc", "dec", "adc", "sbc", "and", "ora", "eor", "cmp", "cpx", "cpy",
}
WRITE_OPS = {"sta", "stx", "sty", "asl", "lsr", "rol", "ror", "inc", "dec"}
BRANCHES = {"bpl", "bmi", "bvc", "bvs", "bcc", "bcs", "bne", "beq"}

# Populated by main(): (bank, start) -> block instructions for the RAM-resident
# inline routines copied by call_inline_block ($C4E4).
INLINE_STARTS: dict[tuple[int, int], list] = {}
# (bank, address) of every instruction inside an inline block: its calls into
# $8000-$BFFF go to the bank the block maps, not to this bank.
BLOCK_INSNS: set[tuple[int, int]] = set()


def banked_from_block(bank: int, addr: int, target: int) -> bool:
    return (bank, addr) in BLOCK_INSNS and 0x8000 <= target < 0xC000


def prefix(bank: int) -> str:
    return "" if bank == 15 else f"b{bank:02d}_"


def sanitize(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", name)


def load_manifest() -> dict:
    path = ASSETS / "manifest.json"
    if not path.exists():
        raise SystemExit(f"missing {path}; run 'python tools/assets.py export' first")
    return json.loads(path.read_text(encoding="utf-8"))


def resource_index(manifest: dict) -> dict:
    return {r["id"]: r for r in manifest["resources"]}


def covering_resource(bank: int, off: int):
    """Return (resource_id, offset_within_resource) for a bank offset."""
    if bank in RESOURCE_SPLITS:
        for start, end, rid in RESOURCE_SPLITS[bank]:
            if start <= off < end:
                return rid, off - start
        return None
    rid = BANK_RESOURCE.get(bank)
    if rid is None:
        return None
    return rid, off


def find_inline_blocks(insn: dict, bank: int) -> dict[int, list]:
    """Decode the block after each call_inline_block ($C4E4) JSR.

    The block is copied to $0600 and executed there.  Its source bytes are
    ordinary bank data until a caller looks for them, so the normal CDL trace
    does not mark them as code.  Follow its control flow inside the 255
    copied bytes; every "jsr return_inline_block" ends a path.
    """
    base = BASES[bank]
    data = Rom(str(ROM_PATH)).bank(bank)
    found = {}
    for addr, i in sorted(insn.items()):
        if not (i.mnemonic == "jsr" and i.mode == "abs" and i.value == 0xC4E4):
            continue
        start = addr + i.size
        block, _ = inline_block_flow(data, start - base, base)
        if block:
            found[start] = sorted(block.items())
    return found


def augment_data_labels(all_labels: dict[int, dict[int, str]], traces: dict) -> None:
    """Add labels in the target bank for cross-bank data references.

    A reference such as ``LDA $A900,Y`` after ``set_bank_b(12)`` becomes
    ``LDA b12_data_A900,Y`` once the target bank's data label exists.
    """
    contexts = {b: compute_bank_context(traces[b][0]) for b in range(16)}
    for bank in range(16):
        insn = traces[bank][0]
        ctx = contexts[bank]
        for addr, ins in sorted(insn.items()):
            if ins.mnemonic not in MEMORY_OPS or ins.mode not in ("abs", "abx", "aby"):
                continue
            v = ins.value
            if not (0x8000 <= v < 0xC000):
                continue
            hb = ctx.get(addr)
            if hb is None or hb == bank:
                continue
            labels = all_labels[hb]
            if v in labels:
                continue
            labels[v] = f"b{hb:02d}_data_{v:04X}"


def build_labels(bank: int, insn: dict, cdl: bytes) -> dict[int, str]:
    """Global labels for a bank."""
    base = BASES[bank]
    labels: dict[int, str] = {}
    used: set[str] = set()

    def add(addr: int, name: str) -> None:
        if not (base <= addr < base + 0x4000):
            return
        name = sanitize(name)
        if addr in labels:
            return
        if name in used:
            i = 2
            while f"{name}_{i}" in used:
                i += 1
            name = f"{name}_{i}"
        labels[addr] = name
        used.add(name)

    # Human names first.
    for (b, a), name in sorted(NAMES.items()):
        if b == bank:
            add(a, name)

    # Inline RAM routines copied by call_inline_block.
    for (b, start) in INLINE_STARTS:
        if b == bank:
            add(start, f"b{bank:02d}_inline_{start:04X}" if bank != 15 else f"inline_{start:04X}")

    # Font glyph labels (before region anchors, so each glyph gets its own name).
    if bank == 1:
        for i in range(104):
            add(base + 0x10 + i * 64, f"b01_kanji_{i:03d}")
    elif bank == 2:
        for i in range(32):
            add(base + 0x10 + i * 64, f"b02_kanji_{i:03d}")
    elif bank == 9:
        for i in range(128):
            add(base + 0x3A00 + i * 8, f"b09_kana_{i:03d}")
    elif bank == 0:
        # Status-screen 16x16 name glyphs (劉備 = 2 glyphs, 8 tiles).
        for i in range(2):
            add(base + 0x0680 + i * 64, f"b00_status_name_{i:03d}")
        add(base + 0x0700, "b00_status_names_end")

    # Region anchors.  If a region starts on a glyph label, the region name
    # becomes an assembler alias emitted later.
    for b, start, end, name, _ in REGIONS:
        if b == bank:
            add(base + start, name)

    # JSR/JMP targets become routine or shared-block labels.
    for addr, ins in sorted(insn.items()):
        if ins.mnemonic == "jsr" and ins.mode == "abs":
            t = ins.value
            if banked_from_block(bank, addr, t):
                continue
            if base <= t < base + 0x4000 and t in insn and t not in labels:
                add(t, f"sub_{t:04X}" if bank == 15 else f"b{bank:02d}_sub_{t:04X}")
            if t in INLINE_WORD_JSR:
                add(addr + ins.size, f"data_{addr + ins.size:04X}" if bank == 15 else f"b{bank:02d}_data_{addr + ins.size:04X}")
            if t == 0xC4FB:
                add(addr + ins.size, f"data_{addr + ins.size:04X}" if bank == 15 else f"b{bank:02d}_data_{addr + ins.size:04X}")
        elif ins.mnemonic == "jmp" and ins.mode == "abs":
            t = ins.value
            if banked_from_block(bank, addr, t):
                continue
            if base <= t < base + 0x4000 and t in insn and t not in labels:
                add(t, f"loc_{t:04X}" if bank == 15 else f"b{bank:02d}_loc_{t:04X}")

    # Branch targets become labels as well (global v1; local names can be
    # introduced later without changing the emitted bytes).
    for addr, ins in sorted(insn.items()):
        if ins.mnemonic in BRANCHES and ins.mode == "rel":
            t = ins.value
            if base <= t < base + 0x4000 and t in insn and t not in labels:
                add(t, f"loc_{t:04X}" if bank == 15 else f"b{bank:02d}_loc_{t:04X}")

    # Absolute data references in this bank.  A reference can point into the
    # middle of an instruction (some tables overlap operands); those become
    # assembler equates rather than labels at an invalid address.
    for addr, ins in sorted(insn.items()):
        if ins.mnemonic in MEMORY_OPS and ins.mode in ("abs", "abx", "aby"):
            t = ins.value
            if base <= t < base + 0x4000:
                add(t, f"data_{t:04X}" if bank == 15 else f"b{bank:02d}_data_{t:04X}")

    # Periodic labels in data areas.
    for b, start, end, name, _ in REGIONS:
        if b != bank:
            continue
        period = PERIOD.get(bank, 0x400)
        for off in range(start + period, end, period):
            addr = base + off
            if addr not in labels and addr not in insn:
                add(addr, f"data_{addr:04X}" if bank == 15 else f"b{bank:02d}_data_{addr:04X}")

    # Label the start of every continuous data run in a code bank.
    covered = set()
    for a, i in insn.items():
        for j in range(i.size):
            covered.add(a + j)
    for off in range(0x4000):
        addr = base + off
        if addr in covered:
            continue
        if off == 0 or (addr - 1) in covered:
            if addr not in labels:
                add(addr, f"data_{addr:04X}" if bank == 15 else f"b{bank:02d}_data_{addr:04X}")

    return labels


def compute_routines(insn: dict, labels: dict[int, str], base: int) -> dict[int, int]:
    """Deprecated placeholder; branch targets are global labels for now."""
    return {addr: addr for addr in insn}


def compute_bank_context(insn: dict) -> dict[int, int | None]:
    """Best-effort PRG bank mapped at $8000 for each instruction.

    The state is propagated through straight-line code and reset at branches.
    It is only used to choose readable labels; numeric operands remain the
    fallback.
    """
    ctx: dict[int, int | None] = {}
    cur: int | None = None
    last_a: int | None = None
    setters = {0xC4B7, 0xC484, 0xC482, 0xC480}
    fixed = {0xC49E: 12, 0xC4A2: 13, 0xC4A6: 14}
    for addr, ins in sorted(insn.items()):
        ctx[addr] = cur
        if ins.mnemonic in BRANCHES:
            cur = None
            last_a = None
            continue
        if ins.mnemonic == "lda" and ins.mode == "imm":
            last_a = ins.value
            continue
        if ins.mnemonic in ("jsr", "jmp") and ins.mode == "abs":
            v = ins.value
            if v in fixed:
                cur = fixed[v]
            elif v in setters and last_a is not None:
                cur = last_a
            elif v == 0xC4AA:
                cur = last_a if last_a is not None else None
            elif 0x8000 <= v < 0xC000:
                # A banked call normally restores the mapping before returning.
                # Keep the current context; cross-bank targets are still
                # resolved by their explicit TARGET_BANK_OVERRIDES.
                pass
            last_a = None
        elif ins.mnemonic in ("rts", "rti", "brk"):
            cur = None
            last_a = None
    return ctx


# Manual target-bank fixes for call sites where the static bank tracker loses
# the mapping across a branch or a helper that restores the bank.
TARGET_BANK_OVERRIDES = {
    (15, 0x8000): 8,
    (15, 0x8003): 8,
    (15, 0x842F): 14,
    (15, 0x867D): 14,
    (15, 0x959E): 14,
    (15, 0x9B73): 14,
    (15, 0x9CC6): 13,
    (15, 0xB496): 14,
    (15, 0xBC79): 14,
    (15, 0xBD77): 14,
    (15, 0xBF46): 14,
}


def effective_bank(bank: int, addr: int, target: int, hints: dict[int, int | None] | None) -> int | None:
    hb = hints.get(addr) if hints else None
    if hb is None:
        hb = TARGET_BANK_OVERRIDES.get((bank, target))
    return hb


def format_operand(ins, bank: int, labels: dict[int, str], routine: int | None,
                   all_labels: dict[int, dict[int, str]] | None = None,
                   hints: dict[int, int | None] | None = None) -> str:
    m, mode, v = ins.mnemonic, ins.mode, ins.value
    if mode in ("imp", "acc"):
        return "a" if mode == "acc" else ""
    if mode == "imm":
        return f"#${v:02X}"
    if mode in ("zp", "zpx", "zpy"):
        name = RAM_NAMES.get(v)
        idx = {"zpx": ",x", "zpy": ",y", "zp": ""}[mode]
        return (name if name else f"${v:02X}") + idx
    if mode in ("abs", "abx", "aby"):
        idx = {"abx": ",x", "aby": ",y", "abs": ""}[mode]
        # JSR/JMP targets.
        if m in ("jsr", "jmp"):
            if 0x8000 <= v < 0xC000 and all_labels and hints:
                hb = effective_bank(bank, ins.addr, v, hints)
                if hb is not None and hb != bank and v in all_labels.get(hb, {}):
                    return all_labels[hb][v] + idx
            if v in labels and (BASES[bank] <= v < BASES[bank] + 0x4000):
                return labels[v] + idx
            if 0xC000 <= v < 0x10000 and all_labels and v in all_labels.get(15, {}):
                return all_labels[15][v] + idx
            if 0x8000 <= v < 0xC000 and all_labels and hints:
                hb = effective_bank(bank, ins.addr, v, hints)
                if hb is not None and v in all_labels.get(hb, {}):
                    return all_labels[hb][v] + idx
            return f"${v:04X}{idx}"
        # Hardware registers.
        if v in HW_NAMES:
            return HW_NAMES[v] + idx
        # Named RAM/table addresses.
        if v in RAM_NAMES:
            return RAM_NAMES[v] + idx
        if 0x8000 <= v < 0xC000 and all_labels and hints:
            hb = effective_bank(bank, ins.addr, v, hints)
            if hb is not None and hb != bank and v in all_labels.get(hb, {}):
                return all_labels[hb][v] + idx
        if v in labels and (BASES[bank] <= v < BASES[bank] + 0x4000):
            return labels[v] + idx
        if 0xC000 <= v < 0x10000 and all_labels and v in all_labels.get(15, {}):
            return all_labels[15][v] + idx
        if 0x8000 <= v < 0xC000 and all_labels and hints:
            hb = effective_bank(bank, ins.addr, v, hints)
            if hb is not None and v in all_labels.get(hb, {}):
                return all_labels[hb][v] + idx
        return (f"a:${v:04X}" if v < 0x100 else f"${v:04X}") + idx
    if mode == "rel":
        if v in labels:
            if routine is not None and v in labels:
                # Local label only when the target is inside the same routine
                # and not itself a global routine/data anchor.
                pass
            return labels[v]
        return f"${v:04X}"
    if mode == "ind":
        return f"(${v:04X})"
    if mode == "izx":
        return f"(${v:02X},x)"
    if mode == "izy":
        return f"(${v:02X}),y"
    raise ValueError((m, mode))


def comment_for_insn(ins, bank: int, labels: dict[int, str], routines: dict[int, int],
                     all_labels: dict[int, dict[int, str]] | None = None,
                     hints: dict[int, int] | None = None) -> list[str]:
    notes = []
    m, mode, v = ins.mnemonic, ins.mode, ins.value
    if mode in ("zp", "zpx", "zpy"):
        if v not in RAM_NAMES:
            for lo, hi, name, desc in RAM_RANGES:
                if lo <= v <= hi:
                    notes.append(desc)
                    break
    elif mode in ("abs", "abx", "aby"):
        if v in HW_NAMES or v in RAM_NAMES:
            # The symbol already conveys the meaning; do not repeat it.
            pass
        elif m in MEMORY_OPS:
            for lo, hi, name, desc in RAM_RANGES:
                if lo <= v <= hi:
                    notes.append(desc)
                    break
            else:
                if 0x2000 <= v <= 0x3FFF:
                    notes.append("PPU register mirror")
    if m in ("jsr", "jmp") and mode == "abs":
        if bank == 15 and 0x8000 <= v < 0xC000:
            notes.append("banked call target (bank must be selected first)")
        elif 0x8000 <= v < 0xC000 and hints:
            hb = effective_bank(bank, ins.addr, v, hints)
            if hb is not None:
                target = all_labels.get(hb, {}).get(v) if all_labels else None
                notes.append(f"bank {hb:02d}" + (f": {target}" if target else " target"))
    if m in ("jsr", "jmp") and mode == "abs" and v == 0xC4E4:
        notes.append("copies the following block to $0600 and executes it there")
    if m == "jsr" and mode == "abs" and v in INLINE_WORD_JSR:
        notes.append("inline pointer/data follows the JSR")
    return notes


def emit_header(bank: int, stats: dict, manifest: dict) -> list[str]:
    base = BASES[bank]
    lines = ["; " + "=" * 70]
    lines.append(f"; PRG bank {bank:02d}  CPU ${base:04X}-${base + 0x3FFF:04X}")
    lines.append("; " + "=" * 70)
    lines.append(f"; traced code: {stats['insns']} instructions / {stats['bytes']} bytes; "
                 f"CDL code bytes: {stats['cdl']}")
    for note in stats.get("notes", []):
        lines.append(f"; {note}")
    lines.append(";")
    lines.append("; Data resources (editable PNGs under assets/, rebuilt by build.py):")
    for b, start, end, name, comment in REGIONS:
        if b != bank:
            continue
        lines.append(f";   ${base + start:04X}-${base + end - 1:04X}  {name}: {comment}")
    lines.append("; " + "=" * 70)
    lines.append("")
    return lines


def emit_bank(bank: int, insn: dict, cdl: bytes, manifest: dict,
              all_labels: dict[int, dict[int, str]],
              text_refs: dict[tuple[int, int], textdata.InlineRef]) -> str:
    base = BASES[bank]
    data = Rom(str(ROM_PATH)).bank(bank)
    labels = all_labels[bank]
    routines = compute_routines(insn, labels, base)
    resources = resource_index(manifest)
    hints = compute_bank_context(insn)
    inline_comments = INLINE_COMMENTS

    header = emit_header(bank, {
        "insns": len(insn),
        "bytes": sum(i.size for i in insn.values()),
        "cdl": sum(1 for v in cdl[bank * 0x4000:(bank + 1) * 0x4000] if v & 1),
        "notes": [],
    }, manifest)

    # Text banks are generated from the editable .dtx files, not from a
    # monolithic binary blob.
    if bank in (10, 11):
        header.append(f'.include "build/text/bank{bank:02d}_table.inc"')
        header.append(f'.include "build/text/bank{bank:02d}_data.inc"')
        header.append("")
        return "\n".join(header)

    # Reverse call graph for comments.
    callers: dict[int, list[int]] = defaultdict(list)
    for a, i in insn.items():
        if i.mnemonic == "jsr" and i.mode == "abs" and not banked_from_block(bank, a, i.value):
            callers[i.value].append(a)

    lines = header

    # Some tables deliberately overlap instruction operands.  ASM6f cannot
    # place a label in the middle of an instruction, so emit those aliases as
    # assembler equates.
    interior = set()
    for a, i in insn.items():
        for j in range(1, i.size):
            interior.add(a + j)
    aliases = [(a, n) for a, n in sorted(labels.items()) if a in interior]
    if aliases:
        lines.append("; Overlapping data aliases (tables referenced inside instructions)")
        for a, n in aliases:
            lines.append(f"{n} = ${a:04X}")
        lines.append("")

    # Region names that share an address with a glyph/periodic label are
    # emitted as aliases so both names remain usable in the debugger.
    region_aliases = []
    for b, start, end, name, _ in REGIONS:
        if b != bank:
            continue
        addr = base + start
        if labels.get(addr) != name and name not in labels.values():
            region_aliases.append((addr, name))
    if region_aliases:
        lines.append("; Region aliases")
        for addr, name in region_aliases:
            lines.append(f"{name} = ${addr:04X}")
        lines.append("")

    # Emit one address at a time, grouping data runs.
    off = 0
    while off < 0x4000:
        addr = base + off
        if bank == 15 and off == 0x3FFA:
            lines.append("; ----------------------------------------------------------------------")
            lines.append("; 6502 interrupt vectors")
            lines.append("; ----------------------------------------------------------------------")
            lines.append("b15_vectors:")
            lines.append("    .dw nmi_handler, reset_vector, nmi_handler    ; NMI, RESET, IRQ")
            lines.append("")
            off = 0x4000
            continue

        if addr in insn:
            # Labels for routine/global anchors.
            if addr in labels:
                name = labels[addr]
                if addr in NAMES or name.startswith("b") and ("kanji" in name or "kana" in name):
                    lines.append("")
                # Header block for documented routines.
                doc = DOCS.get((bank, addr)) if bank in (7, 8, 13, 14, 15) else None
                inline = (bank, addr) in INLINE_STARTS
                if doc or addr in callers or inline:
                    lines.append("; " + "-" * 70)
                    lines.append(f"; {name}")
                    if inline:
                        lines.append(";   Inline RAM routine copied to $0600 by call_inline_block.")
                        lines.append(";   It executes with another PRG bank mapped and returns")
                        lines.append(";   through return_inline_block ($C4FB).")
                    if doc:
                        for s in doc.get("summary", []):
                            lines.append(f";   {s}")
                        if doc.get("inputs"):
                            lines.append(f";   inputs:  {doc['inputs']}")
                        if doc.get("outputs"):
                            lines.append(f";   outputs: {doc['outputs']}")
                        for s in doc.get("notes", []):
                            lines.append(f";   {s}")
                    if addr in callers:
                        cs = ", ".join(f"${a:04X}" for a in sorted(callers[addr])[:12])
                        more = "" if len(callers[addr]) <= 12 else f" (+{len(callers[addr]) - 12} more)"
                        lines.append(f";   called by: {cs}{more}")
                    lines.append("; " + "-" * 70)
                lines.append(f"{name}:")

            # Local labels are not used yet; every branch target is a global
            # loc_XXXX symbol so operands are unambiguous.

            ins = insn[addr]
            op = format_operand(ins, bank, labels, routines.get(addr), all_labels, hints)
            notes = comment_for_insn(ins, bank, labels, routines, all_labels, hints)
            if (bank, addr) in INLINE_COMMENTS:
                notes.insert(0, INLINE_COMMENTS[(bank, addr)])
            text = f"    {ins.mnemonic}" + (f" {op}" if op else "")
            if notes:
                text = f"{text:<32}; {'; '.join(notes)}"
            lines.append(text)
            off += ins.size
            continue

        # Data run.  Stop before the next instruction or at the end.
        run_start = off
        while off < 0x4000 and (base + off) not in insn:
            off += 1
            if bank == 15 and base + off == 0x3FFA:
                break
        run_end = off
        emit_data_run(lines, bank, data, labels, run_start, run_end, resources, text_refs)

    return "\n".join(lines) + "\n"


def emit_data_run(lines: list[str], bank: int, data: bytes, labels: dict[int, str],
                  start: int, end: int, resources: dict,
                  text_refs: dict[tuple[int, int], textdata.InlineRef]) -> None:
    """Emit a data run, split at labels and resource boundaries."""
    base = BASES[bank]
    pos = start
    while pos < end:
        addr = base + pos
        # Inline message indices are references, not opaque binary bytes.
        ref = text_refs.get((bank, addr))
        if ref is not None and pos + 2 <= end:
            if addr in labels:
                lines.append("")
                lines.append(f"{labels[addr]}:")
            lines.append(f"    .dw {ref.index_symbol}    ; text index ${ref.word:04X} -> {ref.message_label}")
            pos += 2
            continue
        # Split at the next labeled address.
        nxt = pos + 1
        while nxt < end and (base + nxt) not in labels:
            nxt += 1
        # Also split at resource boundaries and at a maximum chunk size.
        rid, roff = covering_resource(bank, pos) or (None, None)
        max_end = nxt
        if rid is not None:
            # Find end of this resource segment.
            if bank in RESOURCE_SPLITS:
                for s, e, r in RESOURCE_SPLITS[bank]:
                    if s <= pos < e:
                        max_end = min(max_end, e)
                        break
            else:
                max_end = min(max_end, 0x4000)
            max_end = min(max_end, pos + 0x400)
        else:
            max_end = min(max_end, pos + 0x40)

        if addr in labels:
            lines.append("")
            lines.append(f"{labels[addr]}:")
        length = max_end - pos
        if rid is not None:
            res = resources.get(rid)
            if res and roff == 0:
                lines.append(f"; editable source: assets/{res['path']} ({res['kind']})")
            lines.append(f'    .incbin "build/assets/{rid}.bin", ${roff:04X}, ${length:04X}')
        else:
            chunk = data[pos:max_end]
            for i in range(0, len(chunk), 16):
                hexs = ",".join(f"${b:02X}" for b in chunk[i:i + 16])
                lines.append(f"    .db {hexs}")
        pos = max_end
    if end - start > 0x40:
        lines.append("")


def write_main(stats: dict) -> None:
    lines = [
        "; " + "=" * 70,
        "; Tenchi o Kurau (Japan) (Rev 1) -- readable disassembly/reconstruction",
        "; " + "=" * 70,
        "; Target SHA-256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367",
        "; Build: python decomp/build.py",
        ";",
        "; The ROM is split into 16 PRG banks.  Code is emitted for paths proven",
        "; by Mesen CDL or direct control flow.  Graphics, text, and large data",
        "; blocks live under assets/ and are included with INCBIN; editing the",
        "; PNG resources changes the corresponding bytes without touching code.",
        ";",
        "; Bank coverage:",
    ]
    for bank in range(16):
        s = stats[bank]
        lines.append(f";   bank {bank:02d}: {s['insns']:5d} insns, {s['bytes']:5d} bytes code, "
                     f"{s['cdl']:5d} CDL code bytes")
    lines += [
        "; " + "=" * 70,
        "; iNES/NES 2.0 header: PRG 16x16K, CHR 0, mapper 1 (MMC1),",
        "; horizontal mirroring, battery PRG RAM, 8K CHR RAM, NTSC.",
        "; " + "=" * 70,
        "",
        '.db "NES",$1A',
        ".db $10,$00,$12,$08,$00,$00,$70,$07,$00,$00,$00,$01",
        "",
        '.include "include/hardware.inc"',
        '.include "include/ram.inc"',
        '.include "build/text/index_symbols.inc"',
        "",
    ]
    for bank in range(16):
        lines.append(f"; ---------------- bank {bank:02d} ----------------")
        lines.append(f".base ${BASES[bank]:04X}")
        lines.append(f'.include "banks/bank{bank:02d}.asm"')
        lines.append("")
    (OUT_DIR / "main.asm").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_support() -> None:
    inc = OUT_DIR / "include"
    inc.mkdir(parents=True, exist_ok=True)
    hw = ["; Hardware register symbols (used by the generated assembly)."]
    for addr, name in sorted(HW_NAMES.items()):
        hw.append(f"{name:<20} = ${addr:04X}")
    (inc / "hardware.inc").write_text("\n".join(hw) + "\n", encoding="utf-8")

    ram = ["; Named zero-page/RAM symbols.  Addresses not listed stay numeric."]
    for addr, name in sorted(RAM_NAMES.items()):
        ram.append(f"{name:<22} = ${addr:04X}")
    (inc / "ram.inc").write_text("\n".join(ram) + "\n", encoding="utf-8")


def write_labels(all_labels: dict[int, dict[int, str]]) -> None:
    mlb, txt = [], []
    for bank in range(16):
        base = BASES[bank]
        for addr, name in sorted(all_labels[bank].items()):
            prg_off = bank * 0x4000 + (addr - base)
            mlb.append(f"P:{prg_off:X}:{name}:bank {bank:02d}")
            txt.append(f"bank {bank:02d}  ${addr:04X}  {name}")
    (OUT_DIR / "labels.mlb").write_text("\n".join(mlb) + "\n", encoding="utf-8")
    (OUT_DIR / "labels.txt").write_text("\n".join(txt) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdl", nargs="*", default=[str(DEFAULT_CDL)])
    ap.add_argument("--out", default=str(OUT_DIR))
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    r = Rom(str(ROM_PATH))
    cdl = load_cdl(args.cdl)
    out_dir = Path(args.out)
    (out_dir / "banks").mkdir(parents=True, exist_ok=True)
    write_support()
    manifest = load_manifest()

    traces = {b: trace_bank(r, b, cdl) for b in range(16)}

    # Recover the RAM-resident inline routines whose source bytes were not
    # marked as code by CDL.  Only insert a block when it does not overlap an
    # already-traced instruction, so existing control flow is never rewritten.
    for bank in range(16):
        insn = traces[bank][0]
        for start, block in find_inline_blocks(insn, bank).items():
            INLINE_STARTS[(bank, start)] = block
            # Part of a block may already be traced (CDL-backed code inside
            # it); insert the rest only when every instruction boundary agrees.
            covered = {}
            for a, i in insn.items():
                for j in range(i.size):
                    covered[a + j] = a
            if any(a in covered and (covered[a] != a or insn[a].size != i.size)
                   for a, i in block):
                continue
            for a, i in block:
                insn.setdefault(a, i)
                BLOCK_INSNS.add((bank, a))

    all_labels = {}
    for bank in range(16):
        insn, bad, code_bytes, data_only = traces[bank]
        all_labels[bank] = build_labels(bank, insn, cdl)
    augment_data_labels(all_labels, traces)

    # Message-stream labels for the Mesen symbol file.
    for bank, addr_map in textdata.message_labels().items():
        for addr, name in addr_map.items():
            all_labels[bank][addr] = name

    text_refs = textdata.inline_refs(traces)
    print(f"text references: {len(text_refs)} inline message indices")

    stats = {}
    for bank in range(16):
        insn, bad, code_bytes, data_only = traces[bank]
        text = emit_bank(bank, insn, cdl, manifest, all_labels, text_refs)
        (out_dir / "banks" / f"bank{bank:02d}.asm").write_text(text, encoding="utf-8")
        stats[bank] = {
            "insns": len(insn),
            "bytes": sum(i.size for i in insn.values()),
            "cdl": sum(1 for v in cdl[bank * 0x4000:(bank + 1) * 0x4000] if v & 1),
        }
        print(f"bank {bank:02d}: {stats[bank]['insns']:5d} insns, "
              f"{stats[bank]['bytes']:5d} bytes code, {len(all_labels[bank]):4d} labels")

    write_labels(all_labels)
    write_main(stats)
    print(f"wrote {out_dir}")

    if not args.no_build:
        import subprocess
        rc = subprocess.call([sys.executable, str(out_dir / "build.py")])
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
