# Tenchi o Kurau (Japan) (Rev 1) — readable reconstruction

This directory contains a byte-identical, routine-oriented reconstruction of

`Tenchi o Kurau (Japan) (Rev 1).nes`

Target:

```text
size:   262160 bytes
sha256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367
```

The build is verified against the original ROM after every assembly:

```text
built:  decomp/build/rom.nes
sha256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367
OK: byte-identical to the original ROM
```

## Quick start

Requirements: Windows, Python 3 with Pillow, and the bundled ASM6f assembler.

```bat
cd decomp
build.cmd
```

or:

```powershell
python decomp\build.py
```

`build.py` first converts the editable PNG resources under `assets/` back to
NES tile bytes, compiles the `.dtx` message scripts under `decomp/text/` into
message/pointer-table includes, then assembles `main.asm` with ASM6f and
compares the result with the original ROM.  If a PNG or DTX has been edited,
the output intentionally changes; if nothing was edited, the round trip is
exact.

Options:

```text
python decomp\build.py --listing      write decomp/main.lst
python decomp\build.py --allow-diff   build even if the ROM differs
python decomp\build.py --skip-assets  use existing build/assets binaries
python decomp\build.py --skip-text    use existing build/text includes
```

## Source layout

```text
decomp/
  main.asm                 iNES/NES 2.0 header + 16 bank includes
  banks/bank00.asm         PRG bank 0  ($8000-$BFFF)
  ...
  banks/bank15.asm         PRG bank 15 ($C000-$FFFF, fixed)
  include/hardware.inc     PPU/APU/IO register symbols
  include/ram.inc          named zero-page/RAM symbols
  text/                    editable message scripts (.dtx) + format notes
  FUNCTIONS.md             generated routine index with addresses/callers
  BANKS.md                 bank/resource map
  labels.mlb               Mesen symbol file
  labels.txt               human-readable symbol list
  build.py                 asset build + assemble + byte-for-byte verify
  build.cmd / build.ps1    Windows wrappers
  build/                   generated ROM and binary assets
```

Each `banks/bankNN.asm` emits exactly 16 KB.  `main.asm` resets the logical
address with `.base` before each bank, so the includes are concatenated in ROM
order while labels use the correct CPU addresses.

## What “readable” means here

- Every JSR target has a descriptive working name and a header comment with a
  summary and caller list.  Names describe observed behavior and the call
  graph; they are not original source symbols.
- Hardware and RAM operands use symbols (`PPUCTRL`, `text_col`, `vram_queue`,
  …) instead of raw addresses where the meaning is known.
- Bank-select helpers make cross-bank calls readable:
  `jsr set_bank_14` / `jsr b14_init_battle_party` rather than a bare `$842F`.
- Command-line addresses are not repeated on every instruction; the generated
  listing and `labels.mlb` provide them.
- Internal branch targets remain `loc_XXXX` labels.  These are not separate
  routines.
- Data and code are separate.  Graphics, text, tables, and large data blocks
  live in `assets/` and are included with `INCBIN`.

## Resources

Editable graphics are under `../assets/`:

- `fonts/kana_8x8.png` — 128-glyph 1bpp dialogue font (bank 9 `$BA00-$BDFF`).
- `fonts/kanji_16x16_bank01.png` — 104 16×16 2bpp glyphs (bank 1).
- `fonts/kanji_16x16_bank02.png` — 32 16×16 2bpp glyphs (bank 2).
- `graphics/bank00_chr.png … bank05_chr.png` — raw 2bpp character/map tiles.
- `graphics/bank09_ui_a.png`, `bank09_ui_b.png` — 2bpp UI/status tiles.
- `data/`, `text/` — exact binary blocks for map data, messages, and tables.

`assets/README.md` documents the image formats and color mapping.  The
manifest `assets/manifest.json` records each resource's source bank, offset,
length, and original SHA-256.

## Code/data policy and coverage

Code is emitted for instructions proven by a Mesen CDL execution map or
reachable from those instructions by direct control flow.  The tracer also
recovers the RAM-resident inline routines copied by `call_inline_block`
(`$C4E4`), which CDL alone cannot see as PRG code.  Everything else is kept as
labeled data and included from the resource files.

Current coverage:

| Bank | CPU window | Role | Code bytes |
|---:|---|---|---:|
| 7 | `$8000-$BFFF` | party/list screen and event code | 882 |
| 8 | `$8000-$BFFF` | sound driver + music data | 2,327 |
| 13 | `$8000-$BFFF` | officer status / name entry + dictionary | 2,663 |
| 14 | `$8000-$BFFF` | field menus, info screen, battle engine + tables | 11,761 |
| 15 | `$C000-$FFFF` | fixed bank: main loop, text engine, NMI, bank switching | 12,004 |

Banks 0-6 and 9-12 are graphics/text/table banks and are represented as
resources.  Execution-backed coverage is concentrated in the five code banks;
unexecuted routines reached only through indirect pointers remain data until a
CDL run or a manual seed covers them.

## Regenerating the structural source

`tools/decompile.py` regenerates the bank skeleton from the ROM plus the CDL
map:

```powershell
python tools\assets.py export       # ROM -> assets/*.png + manifest (once)
python tools\decompile.py --no-build
python tools\gen_docs.py            # FUNCTIONS.md / BANKS.md
python decomp\build.py
```

Human-maintained names and comments live in `tools/symbols.py`; the CDL input
is `out/cdl_combined3.bin` (`out/cdl_combined.bin` plus the step-A battle /
info-screen capture of 2026-11-11, see below).  Editing the generated `.asm` files directly is
fine for experiments, but a regeneration overwrites those edits.  Permanent
naming/comment changes should go into `tools/symbols.py` (or be made after the
last regeneration).

**Hand edits a regeneration must keep.**  The kanji edition's changes to
the game banks are hand edits that `decompile.py` does not produce:
- every `.ifdef KANJI_TARGET` / `.ifndef KANJI_TARGET` block (2026-11-15:
  bank 9 one, banks 10 and 11 one each, bank 13 eighteen, bank 14
  twenty-four);
- `SAVE_SLOTS` in bank 13 (2 in the kanji edition, 3 in the original).

Regenerate into a scratch copy and merge the result with `git diff`, never
over these files.  The fixed bank (bank 15) has no hand edits:
`tools/kanji_build.py` patches its copy, bank 31.  asm6f evaluates `.if`
even inside a skipped `.ifdef`, so a label used there must exist in both
builds.

## CDL capture

Mesen's Code/Data Logger records which PRG bytes were executed or read.  The
Lua harnesses in `tools/` dump that map:

- `tools/cdl_dump.lua` — boot/title coverage (300 frames)
- `tools/cdl_capture_status.lua` — mid-game menu/town route
- `tools/cdl_from_state.lua` — mid-dialogue save state, advances text
- `tools/cdl_summary.py` — per-bank coverage summary
- `tools/merge_cdl.py` — bitwise-OR several CDL maps

Example merge:

```powershell
python tools\merge_cdl.py out\cdl_original.bin out\cdl_status\cdl.bin -o out\cdl_combined.bin
```

Step A (2026-11-11) captured the battle and info-screen paths on the kanji
build, where the user's save states are: `tools/lua/cdl_run.lua` (load a
state, play an input path, dump the 512 KiB PRG CDL) and
`tools/map_kanji_cdl.py` (map it onto the original PRG: banks 0-14 at the same
offsets, the fixed bank from bank 31; only the code bits, only where the bytes
equal the original).  `out/cdl_combined3.bin` = `cdl_combined.bin` OR the
mapped capture.

The tracer also knows the game's inline-argument calls: every routine that
starts with `fetch_inline_word` takes a word after its JSR (`INLINE_WORD_JSR`),
`dispatch_return_table` (`$C10C`) is followed by a jump table and does not
return (`DISPATCH_TABLES` lists tables the CDL does not size), and a
`call_inline_block` block is decoded by its own control flow inside the 255
copied bytes, each `jsr return_inline_block` being followed by its resume word.

For Mesen tests, use a copied ROM filename (for example
`out/cdlprobe/tokqol_cdl.nes`).  Mesen keys battery saves by ROM name, so this
keeps the original `Saves\Tenchi o Kurau (Japan) (Rev 1).sav` untouched.

## Static analysis

The routine map was cross-checked with Ghidra 12.1.4 (the REA CLI and
headless exports, 2026-11-07; the seed scripts are in the git history).
Ghidra's C output was an analysis aid, not a build input; the assembly is
generated from the 6502 trace.

## Editing glyphs and text

### 16×16 kanji glyphs

Each glyph is 64 bytes: four NES 2bpp tiles in column-major order
(TL, BL, TR, BR).  Edit the PNG sheets; the build converts them back to exact
tile bytes.  Per-glyph labels `b01_kanji_000…103` and `b02_kanji_000…031` are
emitted at the corresponding offsets.

### 1bpp kana font

The dialogue font is 128 8×8 1bpp glyphs at bank 9 `$BA00-$BDFF`.  The game
expands each glyph to a 2bpp tile by copying the 8 bytes to plane 0 and
zeroing plane 1.  Edit `assets/fonts/kana_8x8.png`; labels
`b09_kana_000…127` mark each glyph.

### Dialogue text

Banks 10 and 11 are now extracted into editable text sources:

- `text/bank10_messages.dtx` — 488 table entries / 460 unique message streams
- `text/bank11_messages.dtx` — 384 table entries / 305 unique message streams

Each record has labels such as `b10_msg_000` (and aliases for duplicate table
entries), so the split low/high pointer table is generated from labels:

```asm
b10_msg_table_lo:
    .db <b10_msg_000, <b10_msg_001, ...
...
b10_msg_table_hi:
    .db >b10_msg_000, >b10_msg_001, ...
```

Literal kana map to the game's 8×8 font tiles.  High bytes `$80-$EE` are
dakuten/handakuten combinations of the base tile (for example `$90` = が,
`$D5` = ド), so most dialogue is readable kana rather than raw tokens.  The
remaining controls are named tokens:

```text
<NL> <NLNI> <PAGE> <PAGENI> <END> <END_NOWAIT>
<NAME_F3> ... <NAME_F7>   <NAME:xx>
<WORD:xx=...>  <PLACE:xx=...>  <ITEM:xx=...>
<CALL:xxxx>  <JUMP:xxxx>
```

`WORD`, `PLACE`, and `ITEM` are decoded word/place/item references; the text
after `=` is only a reader annotation and the compiler emits the original
two-byte reference.  See `text/README.md` for the full token table and the
font row order.  Every byte still round-trips exactly.

The kanji edition's text is `text/kanji_plan/bank1X_messages_kanji_r14.dtx`
(`../STATUS.md` "Editing the text").

The split pointer table and message data are regenerated by:

```powershell
python tools\text.py build
```

`decomp/build.py` runs this automatically before assembling.  Changing a
string length moves later messages and updates the pointer table labels
automatically.  Bank 10 is currently full, so growth there needs free space or
repacking; shortening and equal-length edits work directly.  Bank 11 has
leading tail padding the compiler can consume for small additions.

Code that prints an inline message now references the message index:

```asm
jsr text_print_inline
.dw b10_msg_index_036    ; text index $0024 -> b10_msg_036
```

`b10_msg_index_036` is defined in `build/text/index_symbols.inc`; the value is
the table index the text engine expects, while `b10_msg_036` is the actual
message label.  The text bank itself is loaded through the normal bank-switch
helpers.

## Known limitations

- Switchable-bank coverage is execution-backed and therefore incomplete;
  unexecuted indirect-only routines remain data.
- Some routine names are working names from behavior/call-graph analysis and
  may be revised.
- The exact status-screen PPU/pattern-table split is still being documented;
  the name glyphs themselves are now known to come from bank 0 `$8680`.
- The original battery save was overwritten during earlier testing; use a
  copied ROM name for emulator runs.

## Save-file warning

During earlier testing, Mesen's test runner auto-saved SRAM and overwrote the
original `Tenchi o Kurau (Japan) (Rev 1).sav`.  No backup was made.  Use a
copied ROM filename for any further emulator runs, or back up
`D:\EMU\NES\Saves` first.
