# Changelog

## 2026-11-07 — revision-2 pass: RAM overlay, renderer fixes, first kanji page

Baseline: `26999aa`.

### Fixed-bank layout

- Removed the bank-31 `$E000` overlay; bank 31 is now a byte-identical copy
  of patched bank 15. `tools/bank15_lint.py` enforces that equality and the
  registered patch ranges.
- The text-engine overlay is installed into battery PRG RAM at
  `$7002-$73FF` from bank 24. A two-byte `KO` signature at `$7000` gates the
  fixed-bank hooks; a random-SRAM boot re-installs it.
- The `$C611` gap now holds: the 41-byte SUROM switcher, the `$C63A` far
  stub, a signature check, and signature-guarded NMI entry/palette stubs.
- Removed the caller-bank clobber: trampolines are `F8 3A C6`, the far stub
  maps bank 13 through `set_bank_b`, and `current_bank_a` survives a message.

### Text engine fixes

- `$F8-$FF` now take the original `$D2B7` path; the dispatcher no longer
  jumps through an out-of-range table entry on newline/end controls.
- Fixed the page-record field offset (tile0 is read at entry+3, not +4).
- Fixed the four-tile buffer order: TL/TR in `$0300`, BL/BR in `$0318`.
- Fixed 1bpp->2bpp expansion: each quadrant now gets a 16-byte tile slot
  (DST 0/16/32/48 instead of 0/8/16/24).
- Fixed `kana_prepare` clobbering the caller's X/Y and the buffer offset
  being destroyed by NMI (`KANJI_BUFX` now holds it).
- Page metadata is capped at 255 bytes; `KANJI_META` stays in `$6E00-$6FFF`.

### Text compiler

- Per-page reservations now use the exact table strings for
  `<WORD>/<PLACE>/<ITEM>`, the exact name record for `<NAME:xx>`, bounded
  unions for the dynamic name insertions (`<NAME_F3>` item names and
  `<NAME_F4>-<NAME_F7>` party names), plus frame/cursor/digit tiles.
- Menu scripts are not reserved per page; `restore` is expected to handle
  them. The report records reserved counts and minimum free tiles.
- Over-dense pages without a line boundary are split at a token boundary with
  a forced `<NL2><PAGE>`.

### Verified

- Original 256 KiB target remains byte-identical.
- A converted message renders legibly: `どの歴史書を登録しますか?`
  (screenshots under `out/test/`).
- Deterministic random `$6800-$7FFF` still installs the overlay and renders.
- A 6000-frame save-RAM write watchpoint shows no base-game writes to
  `$6800-$7FFF`.

### Still open

- Town/field map CHR is overwritten by the kanji cache; restoring from the
  kana font is wrong for map tiles. A lazy CHR save/restore layer is the next
  blocking step (see `STATUS.md`).
- An NMI-based save/restore prototype was attempted and reverted: CHR access
  inside the NMI handler caused NMI re-entry/stack growth on the outdoor map.
- Visible-line redraws do not re-upload kanji after tile reuse.
- Inline scripts, tables, runtime names and UI screens remain unconverted.

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
