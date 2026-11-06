#!/usr/bin/env python3
"""6502 tracer seeded by Mesen's execution-backed CDL map.

This module follows direct branches/calls from CDL code and known entry points.
It also contains the older linear emitter used during the first reconstruction
pass; the current readable source generator is tools/decompile.py.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rom import Rom
from cpu6502 import decode, successors, BRANCHES

ROOT = Path(__file__).resolve().parent.parent

# JSR targets that consume a 2-byte inline pointer following the call.
INLINE_WORD_JSR = {0xC25A, 0xD10D, 0xDD14}

# Plausible code ranges for switchable banks.  A JSR/JMP target outside these
# ranges is only followed when Mesen CDL marked it as executed.  This prevents
# a banked call such as ``JSR $842F`` (bank 14 mapped) from tracing bank 7's
# unrelated data at the same CPU address.
TRACE_RANGES = {
    7: [(0x1400, 0x1F00)],
    8: [(0x0000, 0x0A00)],
    13: [(0x0800, 0x2200)],
    14: [(0x0000, 0x1C00), (0x340E, 0x4000)],
}
ROM_PATH = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
DEFAULT_CDL = ROOT / "out" / "cdl_combined.bin"
OUT_DIR = ROOT / "decomp"
ASM6F = ROOT / "tools" / "toolchain" / "asm6f" / "asm6f_64.exe"

BASES = [0x8000] * 15 + [0xC000]

# Execution-backed entry points discovered in Mesen, plus vector entries.
KNOWN_ENTRIES = {
    7: [0x9400, 0x9403],
    8: [0x8000, 0x8003],
    13: [0x8800, 0x8D0, 0x98E7, 0x9C00, 0x9CC6, 0x9F63, 0xA075, 0xA0F3],
    14: [0x8000, 0x842F, 0x867D, 0x959E, 0x9B73, 0xB40E, 0xB487, 0xBC79, 0xBD77, 0xBF09, 0xBF46],
    15: [0xFFD8, 0xEE79, 0xC06E, 0xC08F,
         0xC106, 0xC3EE, 0xC4CF, 0xCC19, 0xCED2, 0xCF91,
         0xD43C, 0xD4A1, 0xD567, 0xD5A5, 0xD5FE, 0xD652, 0xD661,
         0xD671, 0xDDDA, 0xDE07, 0xE371, 0xE711,
         0xF0BB, 0xF0D7, 0xF0DF, 0xF999, 0xF99C, 0xFA10],
}

# Human names for important addresses.  Anything here is emitted as a label
# even if the address is currently classified as data.
KNOWN_LABELS = {
    7: {
        0x9400: "b07_entry",
    },
    8: {
        0x8000: "sound_update",
        0x8003: "sound_play",
        0x8129: "sound_stop",
        0x812D: "sound_pause",
    },
    13: {
        0x8800: "b13_8800",
        0x88D0: "b13_88D0",
    },
    14: {
        0x8000: "b14_entry",
        0xB40E: "b14_B40E",
        0xB487: "b14_B487",
    },
    15: {
        0xFFD8: "reset",
        0xEE79: "nmi_irq",
        0xEFC9: "reset_init",
        0xC000: "main_loop",
        0xC06E: "sub_C06E",
        0xC08F: "sub_C08F",
        0xC0F2: "ppu_nmi_off",
        0xC0FC: "ppu_nmi_on",
        0xC439: "ppu_init",
        0xC460: "mmc1_reset_bank14",
        0xC468: "mmc1_control_write",
        0xC47E: "set_bank_from_a",
        0xC484: "set_bank_lock",
        0xC4A2: "set_bank_13",
        0xC4A6: "set_bank_14",
        0xC4AA: "set_bank_safe",
        0xC4B7: "set_prg_bank",
        0xD10D: "text_print_inline",
        0xD11B: "text_reset",
        0xD124: "text_show",
        0xD160: "text_loop",
        0xD1A5: "text_next_char",
        0xD1A8: "text_draw_cell",
        0xD1FD: "text_set_pointer",
        0xD229: "text_clear_line",
        0xD376: "text_wrap_line",
        0xD456: "text_advance",
        0xD9A1: "vram_queue_flush",
        0xDBCA: "text_render_cell",
    },
}

BANK_NOTES = {
    7: [
        "Map/event code and tables.  Code region begins around $9400.",
    ],
    8: [
        "Music/sound driver (NSF-like).  Mapped at $8000 temporarily by NMI.",
        "Entry points: $8000 = update/tick, $8003 = play command.",
    ],
    13: [
        "Mixed data/code bank.  Code regions are executed through the $8000 window.",
        "Contains menu/status/gameplay helpers and the large table near $B700.",
    ],
    14: [
        "Main gameplay/menu bank, mapped at $8000 for most game logic.",
        "Entry $8000 is called by the fixed bank; many routines are reached via",
        "the $C4A6 bank-select helper.",
    ],
    15: [
        "Fixed PRG bank ($C000-$FFFF).  Main loop, task scheduler, text engine,",
        "VRAM queue, NMI, reset, bank switching and shared helpers live here.",
        "The 16 KB window at $8000 is banked; direct JSRs into $8000-$BFFF are",
        "bank-dependent and are left numeric in this source.",
    ],
}

DETAILED_COMMENTS = {
    0xD9A1: [
        "Flush the $0400 VRAM update queue.",
        "Queue format: $00 terminates; otherwise PPUADDR hi, PPUADDR lo,",
        "length (bit 7 toggles PPUCTRL bit 2), then 'length' data bytes.",
    ],
    0xDBCA: [
        "Render one 8x16 dialogue cell.",
        "Inputs: $56 = line, $0300,Y = top tile, $0318,Y = bottom tile,",
        "$68/$69 = current PPU address.  Output: VRAM queue entries.",
        "The two nametable rows per cell give the 16-pixel line pitch that",
        "makes 16x16 kanji feasible; a wide glyph needs 2x2 tiles and +2 columns.",
    ],
    0xD160: [
        "Dialogue bytecode VM.",
        "Controls seen here: $F9 = switch bank and continue at a 16-bit pointer;",
        "$FC/$FD = text timing/flag controls; $FE = end/wait handling;",
        "$FF = message terminator.  Bytes < $80 are direct 8x8 font tiles.",
    ],
    0xD1A8: [
        "Render the current cell and advance the cursor.",
        "$0300/$0318 hold the top/bottom 8x8 tiles for the current line;",
        "$53 is the column and $56 the line.  A 16x16 kanji needs two",
        "adjacent columns and both tile rows.",
    ],
    0xD229: [
        "Initialize one text line in the $0300/$0318 tile buffers.",
        "The line index in $56 selects the destination offset.",
    ],
    0xD376: [
        "Line-wrap / bottom-line handling when the text cursor reaches line 4.",
    ],
    0xD456: [
        "Advance the text cursor or scroll state after a cell/control code.",
    ],
}

ROUTINE_COMMENTS = {
    0xFFD8: "Reset vector. Resets the MMC1 shift register then jumps to init.",
    0xEE79: "NMI/IRQ handler. PPU updates, music tick, scroll/register restore.",
    0xEFC9: "Reset initialization: wait for PPU, clear RAM, set MMC1, start main loop.",
    0xC000: "Main loop / cooperative task scheduler.",
    0xC4B7: "Write A to the MMC1 PRG bank register ($FFF9), five serial bits.",
    0xC4A2: "Switch the 16 KB window at $8000 to PRG bank 13.",
    0xC4A6: "Switch the 16 KB window at $8000 to PRG bank 14.",
    0xC4AA: "Bank switch used by NMI; restores a pending bank if needed.",
    0xD10D: "Print inline text bytes following the JSR.",
    0xD124: "Set up a text window/message and enter the text VM.",
    0xD160: "Text VM main loop: fetch compressed bytecode, emit cells, handle controls.",
    0xD1A8: "Render the current 8x16 text cell through the VRAM queue.",
    0xD1FD: "Set text cursor from the current window parameters.",
    0xD229: "Clear/initialize one text line in the tile buffers.",
    0xD376: "Handle text line wrapping.",
    0xD9A1: "Flush the $0400 VRAM update queue to the PPU.",
    0xDBCA: "Build VRAM-queue entries for one 8x16 text cell (top/bottom tile).",
}

# Routine/detail comments are keyed by (bank, CPU address) because $8000-$BFFF
# is reused by every switchable bank.
ROUTINE_COMMENTS = {(15, addr): text for addr, text in ROUTINE_COMMENTS.items() if addr >= 0xC000}
ROUTINE_COMMENTS.update({
    (7, 0x9400): "Bank 7 entry point (map/event logic).",
    (8, 0x8000): "Sound driver tick/update entry.",
    (8, 0x8003): "Sound driver command entry (A = sound id).",
    (13, 0x8800): "Bank 13 entry point (shared menu/status code).",
    (14, 0x8000): "Gameplay/menu bank entry, called by the fixed bank.",
    (14, 0xB40E): "Code following the $B400 table; party/status helper.",
    (14, 0xB48D): "Initialize seven party/unit slots.",
    (15, 0xC06E): "Task continuation reached through task state.",
    (15, 0xC08F): "Task continuation reached through task state.",
})
DETAILED_COMMENTS = {(15, addr): text for addr, text in DETAILED_COMMENTS.items()}

# (bank, start_offset, end_offset, label, comment)
REGIONS = [
    (0, 0x0000, 0x4000, "b00_character_graphics", "Character/tile graphics bank."),
    (1, 0x0010, 0x1A10, "b01_kanji_glyphs", "Raw 16x16 kanji glyphs: 104 glyphs, 64 bytes each."),
    (1, 0x1A10, 0x3E10, "b01_character_graphics", "Character/tile graphics."),
    (1, 0x3E10, 0x4000, "b01_battle_animation_graphics", "Battle animation graphics."),
    (2, 0x0010, 0x0810, "b02_kanji_glyphs", "Raw 16x16 kanji glyphs: 32 glyphs, 64 bytes each."),
    (2, 0x0810, 0x3810, "b02_face_graphics", "Portrait/face graphics."),
    (2, 0x3810, 0x4000, "b02_title_graphics_a", "Title graphics (first part)."),
    (3, 0x0000, 0x0810, "b03_title_graphics_b", "Title graphics (second part)."),
    (3, 0x0810, 0x4000, "b03_face_graphics", "Portrait/face graphics."),
    (4, 0x0000, 0x4000, "b04_face_graphics", "Portrait/face graphics."),
    (5, 0x0000, 0x4000, "b05_map_graphics", "Map chip graphics."),
    (6, 0x0000, 0x4000, "b06_map_data", "Map data."),
    (7, 0x0000, 0x1400, "b07_map_data", "Map movement/event data and tables."),
    (7, 0x1400, 0x1E82, "b07_code", "Bank 7 program code."),
    (7, 0x1E82, 0x4000, "b07_unused", "Unused/padding."),
    (8, 0x0000, 0x0A50, "b08_sound_driver", "Music/sound driver code."),
    (8, 0x0A50, 0x4000, "b08_sound_data", "Music/sound data and tables."),
    (9, 0x3A10, 0x4000, "b09_font_source", "Compressed kana/UI font source (PRG $27A10-$2800F, approx.)."),
    (9, 0x0000, 0x4000, "b09_graphics", "Kana/UI graphics and related data."),
    (10, 0x0000, 0x03F0, "b10_message_meta", "Message metadata/address area (approx.)."),
    (10, 0x03F0, 0x4000, "b10_messages", "Message bytecode (approx. start)."),
    (11, 0x0010, 0x0390, "b11_message_table", "Message address table (approx.)."),
    (11, 0x0390, 0x4000, "b11_messages", "Message bytecode (approx. start)."),
    (12, 0x0000, 0x4000, "b12_data_tables", "Enemy/town/item/weapon data tables."),
    (13, 0x0000, 0x0800, "b13_data_tables", "Data tables at the start of bank 13."),
    (13, 0x0800, 0x1010, "b13_code_8800", "Bank 13 code region 1."),
    (13, 0x1010, 0x1C10, "b13_data_9000", "Bank 13 data region."),
    (13, 0x1C10, 0x1FEA, "b13_code_9C10", "Bank 13 code region 2."),
    (13, 0x1FEA, 0x2075, "b13_data_9FEA", "Bank 13 data region."),
    (13, 0x2075, 0x3710, "b13_code_A075", "Bank 13 code region 3."),
    (13, 0x3710, 0x3EA8, "b13_dictionary", "Frequent-word/dictionary table (approx.)."),
    (13, 0x3EA8, 0x4000, "b13_data_tail", "Bank 13 data tail."),
    (14, 0x0000, 0x4000, "b14_bank", "Gameplay/menu bank (code plus embedded tables)."),
    (15, 0x2C00, 0x2E79, "b15_text_data", "Text/bytecode data in the fixed bank (approx. $EC00-$EE78)."),
    (15, 0x0000, 0x4000, "b15_fixed_bank", "Fixed PRG bank: main code and tables."),
]

# Periodic labels keep large data blobs navigable and make glyph edits easy.
PERIOD = {
    0: 0x40, 1: 0x40, 2: 0x40, 3: 0x40, 4: 0x40, 5: 0x40, 6: 0x40,
    7: 0x100, 8: 0x100, 9: 0x40, 10: 0x100, 11: 0x100, 12: 0x100,
    13: 0x100, 14: 0x100, 15: 0x100,
}

HW_NAMES = {
    0x2000: "PPUCTRL", 0x2001: "PPUMASK", 0x2002: "PPUSTATUS",
    0x2003: "OAMADDR", 0x2004: "OAMDATA", 0x2005: "PPUSCROLL",
    0x2006: "PPUADDR", 0x2007: "PPUDATA",
    0x4014: "OAMDMA", 0x4015: "APUSTATUS", 0x4016: "JOY1", 0x4017: "JOY2/APUFRAME",
    0xFFF9: "MMC1 PRG bank", 0x9FFE: "MMC1 control",
}

RAM_NAMES = {
    0x33: "frame/tick counter",
    0x40: "vram_queue_write_pos",
    0x41: "vram_queue_read_pos",
    0x43: "current_bank_a",
    0x44: "current_bank_b",
    0x46: "text_window_x?",
    0x4F: "text_speed?",
    0x51: "text_ptr_lo", 0x52: "text_ptr_hi",
    0x53: "text_col", 0x55: "text_state", 0x56: "text_line",
    0x58: "input_buttons",
    0x5F: "text_flags",
    0x60: "text_x", 0x61: "text_y", 0x62: "text_x2", 0x63: "text_y2",
    0x68: "text_ppu_addr_lo", 0x69: "text_ppu_addr_hi", 0x6A: "text_ppu_ctrl",
    0x73: "text_busy", 0x87: "game_mode", 0x92: "loop_counter",
    0xA0: "frame_counter",
    0xEA: "bank_sound_lock", 0xEB: "bank_switch_pending", 0xEC: "nmi_busy",
    0xED: "current_prg_bank",
    0xF0: "nmi_mode", 0xF1: "ppu_update_len", 0xF2: "ppu_update_off",
    0xF3: "ppu_update_ptr_lo", 0xF4: "ppu_update_ptr_hi",
    0xF5: "controller_state",
    0xFC: "scroll_y", 0xFD: "scroll_x", 0xFE: "ppu_mask_shadow", 0xFF: "ppu_ctrl_shadow",
}


def load_cdl(paths):
    if not paths:
        return b"\x00" * len(Rom().prg)
    out = bytearray(len(Rom().prg))
    for p in paths:
        path = Path(p)
        if not path.exists():
            print(f"warning: CDL not found: {p} (continuing with an empty map)")
            continue
        data = path.read_bytes()
        if len(data) == 262153:  # Mesen CDLv2 header
            data = data[9:]
        assert len(data) == len(out), (p, len(data), len(out))
        for i, v in enumerate(data):
            out[i] |= v
    return bytes(out)


def trace_bank(r, bank, cdl, debug=False):
    base = BASES[bank]
    data = r.bank(bank)
    cdl_bank = cdl[bank * 0x4000:(bank + 1) * 0x4000]
    code_bytes = {i for i, v in enumerate(cdl_bank) if v & 1}
    data_only = {i for i, v in enumerate(cdl_bank) if (v & 2) and not (v & 1)}
    insn = {}
    bad = set()
    work = []

    for a in KNOWN_ENTRIES.get(bank, []):
        work.append(a)
    for i, v in enumerate(cdl_bank):
        if v & 0x0C:
            work.append(base + i)

    def ok(off, size):
        return (off >= 0 and off + size <= len(data)
                and not any((off + j) in data_only for j in range(size)))

    def run_work():
        while work:
            a = work.pop()
            if a in insn or a in bad:
                continue
            off = a - base
            ins = decode(data, off, base) if 0 <= off < len(data) else None
            if ins is None or not ok(off, ins.size):
                bad.add(a)
                continue
            insn[a] = ins
            if ins.mnemonic == "jsr" and ins.value in INLINE_WORD_JSR:
                # The two bytes after the call are an inline pointer, not code.
                off = a - base
                for j in range(1, 3):
                    data_only.add(off + j)
            for s in successors(ins):
                if ins.mnemonic == "jsr" and s == ins.next_addr and ins.value in INLINE_WORD_JSR:
                    s += 2
                if not (base <= s < base + len(data)):
                    continue
                # Do not follow a banked call/JMP into a switchable bank's
                # unrelated data.  CDL-executed bytes are always accepted.
                if ins.mnemonic in ("jsr", "jmp") and ins.mode == "abs" and s == ins.value and bank != 15:
                    off = s - base
                    if not (cdl_bank[off] & 1) and not any(lo <= off < hi for lo, hi in TRACE_RANGES.get(bank, [])):
                        continue
                work.append(s)

    run_work()

    # Fill executed code runs that were not reached by the entry-point trace.
    changed = True
    while changed:
        changed = False
        covered = set()
        for a, ins in insn.items():
            for j in range(ins.size):
                covered.add(a + j - base)
        i = 0
        starts = []
        while i < len(data):
            if i in code_bytes and i not in covered:
                starts.append(i)
                while i < len(data) and i in code_bytes and i not in covered:
                    i += 1
            else:
                i += 1
        for off in starts:
            before = len(insn)
            work.append(base + off)
            run_work()
            if len(insn) != before:
                changed = True

    return insn, bad, code_bytes, data_only


def auto_name(bank, addr, kind):
    if bank == 15:
        return f"{kind}_{addr:04X}"
    return f"b{bank:02d}_{kind}_{addr:04X}"


def is_inside_instruction(insn, addr):
    for start, ins in insn.items():
        if start < addr < start + ins.size:
            return True
    return False


def build_labels(r, cdl, traces):
    labels = {b: {} for b in range(16)}
    label_owner = {}

    def add(bank, addr, name, force=False):
        base = BASES[bank]
        if not (base <= addr < base + 0x4000):
            return False
        if addr in labels[bank]:
            if force:
                old = labels[bank][addr]
                # keep both by aliasing the old name to the new one later
                labels[bank][addr] = name
                label_owner.pop(old, None)
                label_owner[name] = (bank, addr)
                return True
            return False
        if name in label_owner and label_owner[name] != (bank, addr):
            return False
        labels[bank][addr] = name
        label_owner[name] = (bank, addr)
        return True

    # Known names first.
    for bank, table in KNOWN_LABELS.items():
        for addr, name in table.items():
            add(bank, addr, name, force=True)

    # One label per raw 16x16 kanji glyph (64 bytes, column-major tile order).
    # Give these priority over the generic periodic/region labels.
    for bank, (start, count) in {1: (0x10, 104), 2: (0x10, 32)}.items():
        for i in range(count):
            add(bank, BASES[bank] + start + i * 64, f"b{bank:02d}_kanji_{i:03d}", force=True)

    # Region starts and periodic data labels.
    for bank, start, end, name, _ in REGIONS:
        add(bank, BASES[bank] + start, name, force=False)
        period = PERIOD[bank]
        for off in range(start + period, end, period):
            addr = BASES[bank] + off
            if addr not in labels[bank]:
                add(bank, addr, f"b{bank:02d}_d_{addr:04X}")

    # Collect code targets.
    for bank, (insn, bad, code_bytes, data_only) in traces.items():
        base = BASES[bank]
        for addr, ins in insn.items():
            m, mode = ins.mnemonic, ins.mode
            if m in ("jsr", "jmp") and mode == "abs":
                t = ins.value
                # A switchable-bank call target is only safe to label when it
                # is also traced in this same bank.  Otherwise the current
                # bank at run time may be a different 16 KB bank.
                if base <= t < base + 0x4000 and t in insn:
                    add(bank, t, auto_name(bank, t, "sub"))
                elif 0xC000 <= t < 0x10000 and t in traces[15][0]:
                    add(15, t, auto_name(15, t, "sub"))
            elif m in BRANCHES:
                t = ins.value
                if base <= t < base + 0x4000:
                    add(bank, t, auto_name(bank, t, "loc"))

        # CDL sub entry points are function starts.
        cdl_bank = cdl[bank * 0x4000:(bank + 1) * 0x4000]
        for i, v in enumerate(cdl_bank):
            if v & 0x08 and (base + i) in insn:
                add(bank, base + i, auto_name(bank, base + i, "sub"))

    # Drop labels that land inside a traced instruction (except its first byte).
    for bank, (insn, bad, code_bytes, data_only) in traces.items():
        for addr in list(labels[bank]):
            if is_inside_instruction(insn, addr):
                name = labels[bank].pop(addr)
                label_owner.pop(name, None)

    return labels


def hw_comment(value):
    if value in HW_NAMES:
        return HW_NAMES[value]
    if 0x2000 <= value <= 0x3FFF:
        return "PPU register mirror"
    if 0x4000 <= value <= 0x401F:
        return "APU/IO register"
    if 0x8000 <= value <= 0xFFFF:
        return "MMC1 register area"
    return ""


def ram_comment(value):
    return RAM_NAMES.get(value, "")


def format_insn(ins, bank, label_maps):
    m, mode, v = ins.mnemonic, ins.mode, ins.value
    idx = ""
    if mode in ("imp", "acc"):
        op = "a" if mode == "acc" else ""
    elif mode == "imm":
        op = f"#${v:02X}"
    elif mode in ("zp", "zpx", "zpy"):
        idx = {"zpx": ",x", "zpy": ",y", "zp": ""}[mode]
        op = f"${v:02X}{idx}"
    elif mode in ("abs", "abx", "aby"):
        idx = {"abx": ",x", "aby": ",y", "abs": ""}[mode]
        t = v
        lbl = None
        if m in ("jsr", "jmp"):
            if 0xC000 <= t < 0x10000:
                lbl = label_maps[15].get(t)
            elif BASES[bank] <= t < BASES[bank] + 0x4000:
                lbl = label_maps[bank].get(t)
        if lbl:
            op = lbl + idx
        else:
            op = f"${t:04X}{idx}"
            if t < 0x100:
                op = f"a:${t:04X}{idx}"
    elif mode == "ind":
        op = f"(${v:04X})"
    elif mode == "izx":
        op = f"(${v:02X},x)"
    elif mode == "izy":
        op = f"(${v:02X}),y"
    elif mode == "rel":
        lbl = label_maps[bank].get(v)
        op = lbl if lbl else f"${v:04X}"
    else:
        raise ValueError((m, mode))
    return (m + (" " + op if op else "")).strip()


MEMORY_OPS = {
    "lda", "ldx", "ldy", "sta", "stx", "sty", "bit", "asl", "lsr", "rol", "ror",
    "inc", "dec", "adc", "sbc", "and", "ora", "eor", "cmp", "cpx", "cpy",
}


def insn_comment(ins, bank, label_maps):
    m, mode, v = ins.mnemonic, ins.mode, ins.value
    notes = []
    if mode in ("zp", "zpx", "zpy"):
        c = ram_comment(v)
        if c:
            notes.append(c)
    elif mode in ("abs", "abx", "aby") and m in MEMORY_OPS:
        c = hw_comment(v)
        if c:
            notes.append(c)
        elif v < 0x800:
            c = ram_comment(v)
            if c:
                notes.append(c)
    if m in ("jsr", "jmp") and mode == "abs" and 0x8000 <= v < 0xC000 and bank == 15:
        notes.append("banked target (currently mapped bank)")
    return ("  " + "; ".join(notes)) if notes else ""


def emit_bank(r, bank, insn, label_maps, cdl):
    base = BASES[bank]
    data = r.bank(bank)
    labels = label_maps[bank]
    lines = []
    traced_bytes = sum(i.size for i in insn.values())
    cdl_code = sum(1 for v in cdl[bank * 0x4000:(bank + 1) * 0x4000] if v & 1)
    lines.append(f"; ----------------------------------------------------------------------")
    lines.append(f"; PRG bank {bank:02d}  CPU ${base:04X}-${base + 0x3FFF:04X}")
    lines.append(f"; traced code: {len(insn)} instructions / {traced_bytes} bytes; CDL code bytes: {cdl_code}")
    for note in BANK_NOTES.get(bank, []):
        lines.append(f"; {note}")
    for b, start, end, name, comment in REGIONS:
        if b == bank:
            lines.append(f";   ${base + start:04X}-${base + end - 1:04X}  {name}: {comment}")
    lines.append(f"; ----------------------------------------------------------------------")
    lines.append("")

    label_at = {}
    for addr, name in labels.items():
        label_at.setdefault(addr, []).append(name)
    for v in label_at.values():
        v.sort(key=lambda s: (len(s), s))

    region_comments = {base + start: comment for b, start, end, name, comment in REGIONS if b == bank}

    def labels_for(addr):
        return label_at.get(addr, [])

    def emit_labels(addr):
        for name in labels_for(addr):
            lines.append(f"{name}:")
        key = (bank, addr)
        if key in ROUTINE_COMMENTS:
            lines.append(f"; {ROUTINE_COMMENTS[key]}")
        for comment in DETAILED_COMMENTS.get(key, []):
            lines.append(f"; {comment}")
        if addr in region_comments:
            lines.append(f"; {region_comments[addr]}")

    off = 0
    data_start = None

    def flush_data(end_off):
        nonlocal data_start
        if data_start is None or data_start >= end_off:
            data_start = None
            return
        a = base + data_start
        b = base + end_off
        if end_off - data_start >= 0x80:
            lines.append(f"; data ${a:04X}-${b - 1:04X} ({end_off - data_start} bytes)")
        pos = data_start
        while pos < end_off:
            chunk = data[pos:min(pos + 16, end_off)]
            hexs = ",".join(f"${x:02X}" for x in chunk)
            lines.append(f"    .db {hexs}    ; ${base + pos:04X}")
            pos += len(chunk)
        lines.append("")
        data_start = None

    while off < 0x4000:
        if bank == 15 and off == 0x3FFA:
            flush_data(off)
            lines.append("; 6502 interrupt vectors")
            lines.append("    .dw nmi_irq, reset, nmi_irq    ; $FFFA NMI, $FFFC RESET, $FFFE IRQ")
            lines.append("")
            off = 0x4000
            continue
        addr = base + off
        if addr in insn:
            flush_data(off)
            emit_labels(addr)
            ins = insn[addr]
            text = format_insn(ins, bank, label_maps)
            comment = insn_comment(ins, bank, label_maps)
            line = f"    {text:<30}; ${addr:04X}"
            if comment:
                line += comment
            lines.append(line)
            off += ins.size
        else:
            if labels_for(addr):
                flush_data(off)
                data_start = off
                emit_labels(addr)
            elif data_start is None:
                data_start = off
            off += 1
    flush_data(0x4000)
    return "\n".join(lines) + "\n"


def write_support_files(out_dir):
    inc = out_dir / "include"
    inc.mkdir(parents=True, exist_ok=True)
    (inc / "hardware.inc").write_text(
        "; Hardware register names (comments only; the code uses raw addresses)\n"
        "PPUCTRL   = $2000\n"
        "PPUMASK   = $2001\n"
        "PPUSTATUS = $2002\n"
        "OAMADDR   = $2003\n"
        "OAMDATA   = $2004\n"
        "PPUSCROLL = $2005\n"
        "PPUADDR   = $2006\n"
        "PPUDATA   = $2007\n"
        "OAMDMA    = $4014\n"
        "APUSTATUS = $4015\n"
        "JOY1      = $4016\n"
        "JOY2      = $4017\n",
        encoding="utf-8",
    )
    (inc / "ram.inc").write_text(
        "; Selected RAM variables documented during analysis.\n"
        "ppu_ctrl_shadow   = $00FF\n"
        "ppu_mask_shadow   = $00FE\n"
        "scroll_y          = $00FC\n"
        "scroll_x          = $00FD\n"
        "vram_queue        = $0400\n"
        "vram_queue_write  = $0040\n"
        "vram_queue_read   = $0041\n"
        "text_tile_row0    = $0300\n"
        "text_tile_row1    = $0318\n"
        "text_ptr_lo       = $0051\n"
        "text_ptr_hi       = $0052\n"
        "text_col          = $0053\n"
        "text_line         = $0056\n"
        "current_prg_bank  = $00ED\n"
        "bank_switch_lock  = $00EB\n",
        encoding="utf-8",
    )


def write_labels(out_dir, labels):
    mlb = []
    txt = []
    for bank in range(16):
        base = BASES[bank]
        for addr, name in sorted(labels[bank].items()):
            prg_off = bank * 0x4000 + (addr - base)
            mlb.append(f"P:{prg_off:X}:{name}:bank {bank:02d}")
            txt.append(f"bank {bank:02d}  ${addr:04X}  {name}")
    (out_dir / "labels.mlb").write_text("\n".join(mlb) + "\n", encoding="utf-8")
    (out_dir / "labels.txt").write_text("\n".join(txt) + "\n", encoding="utf-8")


def write_main(out_dir, bank_stats):
    header = [
        "; ======================================================================",
        "; Tenchi o Kurau (Japan) (Rev 1) -- disassembly/reconstruction",
        "; ======================================================================",
        "; Target SHA-256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367",
        "; Build: python build.py",
        ";",
        "; The source is intentionally a loose reconstruction.  Code is emitted",
        "; only for paths proven by Mesen CDL or reachable by direct control flow;",
        "; everything else is kept as labelled data.  This keeps the build",
        "; byte-identical while making later text/glyph work practical.",
        ";",
        "; Bank coverage:",
    ]
    for b, (n, nbytes, cdlbytes) in bank_stats.items():
        header.append(f";   bank {b:02d}: {n:5d} insns, {nbytes:5d} bytes code, {cdlbytes:5d} CDL code bytes")
    header += [
        "; ======================================================================",
        "; iNES/NES 2.0 header:",
        ";   PRG = 16 x 16 KB, CHR = 0, mapper 1 (MMC1), horizontal mirroring,",
        ";   battery-backed 8 KB PRG RAM, 8 KB CHR RAM, NTSC.",
        "; ======================================================================",
        "",
        '.db "NES",$1A',
        ".db $10,$00,$12,$08,$00,$00,$70,$07,$00,$00,$00,$01",
        "",
        '.include "include/hardware.inc"',
        '.include "include/ram.inc"',
        "",
    ]
    lines = header
    for bank in range(16):
        lines.append(f"; ---------------- bank {bank:02d} ----------------")
        lines.append(f".base ${BASES[bank]:04X}")
        lines.append(f'.include "banks/bank{bank:02d}.asm"')
        lines.append("")
    (out_dir / "main.asm").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdl", nargs="*", default=[str(DEFAULT_CDL)])
    ap.add_argument("--out", default=str(OUT_DIR))
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    r = Rom(str(ROM_PATH))
    cdl = load_cdl(args.cdl)
    out_dir = Path(args.out)
    (out_dir / "banks").mkdir(parents=True, exist_ok=True)
    write_support_files(out_dir)

    traces = {}
    for bank in range(16):
        traces[bank] = trace_bank(r, bank, cdl)
    labels = build_labels(r, cdl, traces)
    write_labels(out_dir, labels)

    bank_stats = {}
    for bank in range(16):
        insn, bad, code_bytes, data_only = traces[bank]
        text = emit_bank(r, bank, insn, labels, cdl)
        (out_dir / "banks" / f"bank{bank:02d}.asm").write_text(text, encoding="utf-8")
        bank_stats[bank] = (len(insn), sum(i.size for i in insn.values()),
                            sum(1 for v in cdl[bank * 0x4000:(bank + 1) * 0x4000] if v & 1))

    write_main(out_dir, bank_stats)

    # A short build/verification report.
    if not args.no_build:
        build_py = out_dir / "build.py"
        if build_py.exists():
            subprocess.run([sys.executable, str(build_py)], check=False)
        else:
            print("build.py not found; source generated only.")

    print(f"generated {out_dir}")
    for b in range(16):
        n, nb, cb = bank_stats[b]
        print(f"  bank {b:02d}: {n:5d} insns, {nb:5d} code bytes, {cb:5d} CDL code bytes")
    print("CDL inputs:", ", ".join(args.cdl))


if __name__ == "__main__":
    main()
