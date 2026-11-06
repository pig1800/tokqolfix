# Changelog

## 2026-11-07 — kanji-target implementation pass

Baseline: `81d7307` (byte-identical 256 KiB reconstruction).

### Build targets

- Added `python decomp/build.py --target kanji`, producing
  `decomp/build/rom_kanji.nes` (524,304 bytes, 32 x 16 KiB PRG).
- The original target still produces
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Added `decomp/main_kanji.asm`, `decomp/banks/bank16_30.asm`, and a
  byte-level bank-15 patch step that preserves all original bank-15 label
  addresses.

### SUROM / MMC1

- NES 2.0 header now declares mapper 1 submapper 1 (SUROM).
- Bank 15 and bank 31 receive a 41-byte SUROM `write_prg_bank` replacement at
  `$C611` (inside an audited 102-byte unused data gap). `$C4B7` jumps to it.
- The switcher writes the outer bit through CHR bank 0 and the low four PRG
  bits through the PRG bank register.
- Bank 31 is a copy of patched bank 15 with the text-engine patches.

### Fixed-bank overlay (`bank 31 $E000`)

- Extended text dispatcher for `$EC-$EE` plus the original `$EF-$F7` table.
- Kanji cell handler using compiler-generated per-page slot records.
- NMI CHR upload hook and an NMI-entry upload path that also works while
  `nmi_busy` suppresses normal sound/VRAM work.
- Control-store hook and lazy kana restore hook.
- 8x16 `text_put_tile`-compatible rendering path (each 16x16 kanji is written
  as two adjacent native cells).

### Far text loader (bank 13 `$8317`)

- Each message in banks 10/11 is replaced by an 8-byte trampoline:
  `F8 17 03 <target bank> <target addr> <meta ptr>`.
- A 255-byte RAM-resident loader copies the kana font and page-slot metadata
  to SRAM, switches to text banks 18-21 and continues in the fixed bank.

### Font and text pipeline

- Added `tools/kanji_common.py`, `tools/kanji_font.py`, `tools/kanji_text.py`.
- Inventory: 718 kanji from the corrected draft and referenced tables.
- Font: DotGothic16 rendered at 16x16, emitted as 32-byte 1bpp glyphs.
- Text compiler reflows lines to 18 cells, splits over-dense pages, assigns
  four CHR tiles per distinct kanji, and emits:
  - banks 10/11: pointer tables + trampolines,
  - banks 22/23: page-slot metadata,
  - banks 18-21: converted message streams.
- Added `assets/fonts/kanji_index.tsv` and a contact sheet at
  `assets/fonts/kanji_16x16_ext.png`.

### Test harness

- Added `tools/mesen_run.py` (copies ROMs under `out/test` so real saves are
  never touched) and `tools/lua/` helper scripts.
- Verified the 512 KiB target boots and reaches the title/menu in Mesen.
- Verified the SUROM outer-bank switch and bank-31 overlay with synthetic
  test ROMs.

### Known blockers (see `STATUS.md`)

- The current CHR strategy reuses kana tiles; after a dialogue, window/UI
  drawing can see overwritten tiles because the window drawing path does not
  restore kana/window tiles.
- Inline bank-15 menu scripts remain kana and have no page metadata; they are
  not converted yet.
- Full dialogue proofreading and UI-screen conversion are not done.
