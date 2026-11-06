# Tenchi o Kurau (Japan) (Rev 1) — kanji + kana text feasibility

Target: `Tenchi o Kurau (Japan) (Rev 1).nes`
SHA-256: `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`
File size: 262,160 bytes

## TL;DR

- The game **does** have a kanji name display: on the officer status screen the name is drawn as a **16×16 BG glyph** (2×2 tiles), with the katakana reading above it.
- The dialogue engine is a separate **8×16 cell** text renderer using a **128-tile kana font** in CHR RAM `$1000-$17FF`.
- The kanji name display technique is reusable in principle, but the status-screen routine itself is screen-specific. It is not a generic inline “print kanji” function.
- The dialogue box already has a 16-pixel line pitch, so a 16×16 kanji fits vertically on the first three lines. The fourth line sits directly on the bottom border and would need layout work.
- The raw kanji graphics blocks contain **136 16×16 glyphs** (104 + 32). That is a name/UI set, **not nearly enough** for a full kanji+kana dialogue conversion. Even the 272 symbols reported by TCRF would be short.
- BG CHR is almost completely full during dialogue (only 1 blank tile in the `$1000` table). There is free space in the sprite table, but sprites are already used for the portrait and are limited to 64.
- The text bytecode is compressed and uses almost every high code (`$80-$FF`); only four high codes are unused (`$A1`, `$C1`, `$C2`, `$DA`). Adding a kanji opcode is possible but tight.
- Recommendation: start with a **limited kanji mode** (common words/names) using a new opcode and a 2×2 wide-character path; a **full conversion** needs a new font bank, a glyph cache, text-data conversion, and probably ROM expansion.
- Measured from the actual dialogue: the corrected kanji planning draft in
  `decomp/text/kanji_plan/` uses **718 unique kanji** in 3,177 occurrences.
  The top 300 cover about 81% of occurrences, 450 about 92%, and 560 about
  95%.  At 64 bytes per 16×16 glyph that is 18.75 KiB / 28.13 KiB / 35 KiB
  of pattern data.  CHR RAM is 8 KiB, so only 128 16×16 glyphs can be
  resident at once; any larger set must be paged per scene.  See
  `decomp/text/kanji_plan/REPORT.md` for the full budget.

## 1. ROM / mapper facts

Parsed from the iNES/NES 2.0 header and confirmed by running the ROM in Mesen 2.2.1:

| Item | Value |
|---|---|
| PRG ROM | 256 KB (16 × 16 KB banks) |
| CHR ROM | 0 KB |
| CHR RAM | 8 KB (512 tiles) |
| PRG RAM / battery | 8 KB battery-backed |
| Mapper | 1 (MMC1) |
| Mirroring | Horizontal |
| Reset vector | `$FFD8` (fixed bank 15) |

The game uses CHR RAM, so all text/graphics tiles are uploaded from PRG at runtime.

## 2. Dialogue text engine

### 2.1 Text window layout

At a normal dialogue frame the nametable contains:

- Window border rows `$12-$1B`, columns 6-25.
- Text rows: `$14`, `$16`, `$18`, `$1A`.
- Each text character occupies an **8×16 cell**: an 8×8 glyph on the text row plus a second row used for descenders/shadow (tile `$72`) or left blank.
- Effective text area: about 18 columns × 4 lines.

The renderer at `$DBCA` writes two nametable rows per character:
- `$0300,Y` = top tile
- `$0318,Y` = bottom tile
- It emits a VRAM-queue command for each row.

So the line pitch is already 16 pixels. A 16×16 kanji can occupy two nametable rows without increasing line spacing. This is the strongest argument that mixed kanji+kana is visually possible.

Caveat: the fourth line is at `$1A/$1B`, and `$1B` is the bottom border. A 16×16 kanji on line 4 would overwrite the border. Lines 1-3 are safe; line 4 needs either an 8×8 glyph, a taller window, or a border shift.

### 2.2 Kana font and PPU setup

During dialogue:

- `PPUCTRL` shadow (`$FF`) = `$90`: BG pattern table `$1000`, sprite pattern table `$0000`.
- The kana font occupies CHR `$1000-$17FF` (128 tiles, 8×8).
- `$1800-$1FFF` contains UI/window graphics.
- Portraits are sprites using `$0000`.

The kana font is stored **uncompressed as 1bpp glyph data** at PRG bank 9
CPU `$BA00-$BDFF` (128 glyphs × 8 bytes).  The loader expands each 8-byte
glyph into a normal NES 2bpp tile by copying the 8 bytes to plane 0 and
zeroing plane 1.  A direct search for 16-byte 2bpp tiles therefore fails, but
the 8-byte glyphs match exactly.  The editable resource is
`assets/fonts/kana_8x8.png`.

### 2.3 Text data

The script is in PRG banks 10 and 11.  Each bank has a **split pointer
table** (low bytes, a gap, then high bytes) followed by message streams:

| Region | CPU range | Contents |
|---|---|---|
| Bank 10 low table | `$8000-$81E7` | 488 low bytes |
| Bank 10 gap | `$81E8-$81FF` | auxiliary/padding |
| Bank 10 high table | `$8200-$83E7` | 488 high bytes |
| Bank 10 messages | `$83E8-$BFFF` | message bytecode |
| Bank 11 low table | `$8000-$817F` | 384 low bytes |
| Bank 11 gap | `$8180-$81FF` | auxiliary/padding |
| Bank 11 high table | `$8200-$837F` | 384 high bytes |
| Bank 11 messages | `$8380-$BFFF` | message bytecode |

The text engine at `$D124` receives a 16-bit **table index** in the inline
word after `JSR $D10D`:

- index `< $200` -> bank 10 entry `index` (0-487)
- index `>= $200` -> bank 11 entry `index - $200` (0-383)

It reads the low byte from `$8000+index` and the high byte from
`$8200+index`, forming the message-stream address.  Code now references these
as `b10_msg_index_036` / `b11_msg_index_145` symbols.

The table has 488 + 384 entries but only 460 + 305 unique stream addresses;
duplicate entries are aliases.  A stream commonly ends with `$FF`, but some
entries are control-flow fragments that jump elsewhere, so the pointer table
boundaries are authoritative rather than `$FF` scanning.

Message bytes:

- `$00-$7F` are direct 8×8 font tile codes (kana/punctuation/digits).
- `$80-$EE` are **dakuten/handakuten combinations**: the low seven bits are
  the base tile and the upper half of the cell is replaced by the dakuten
  (`$72`) or handakuten (`$73`) tile.  For example `$90` = が, `$9A` = だ,
  `$DD` = ば, `$D5` = ド, `$E2-$E6` = パピプペポ, `$E7-$EB` = ぱぴぷぺぽ.
  This is why most high bytes decode to readable kana rather than opaque
  tokens.
- `$EF-$F7` are control/name insertions (place, word, item, party-slot and
  runtime names).  `$EF`, `$F0`, `$F1`, and `$F2` consume one inline byte.
- `$F8` and `$F9` consume a two-byte code pointer (call/jump).
- `$FA-$FF` are line/page/wait/end controls.

The editable sources are `decomp/text/bank10_messages.dtx` and
`bank11_messages.dtx`.  Kana/digits are emitted as Unicode, high bytes are
composed into voiced kana, and the word/place/item controls are annotated
with their decoded text:

```text
<WORD:0E=リュウビさま>  <PLACE:7D=セイシュウじょう>  <ITEM:2C=めいば>
<NL> <PAGE> <END>  <NAME_F6>  <CALL:21D0=ソウジン>
```

Every byte is still lossless: the compiler rebuilds both the streams and the
split pointer table, and unmodified `.dtx` files reproduce the original ROM
byte-for-byte.

Example decoded message (`$8CBC`, table index 126):

```
76 3F 29 34 16 0A 1C 11 5E 5D 14 1E 1F 34 9E FA 22 90 36 12 DD ...
「うまれし つきひはことなれど ...
```

The exact high-code/dictionary expansion is not fully decoded; those bytes
remain tokens in the editable text rather than being guessed.

So the text is not plain kana: it is a compressed stream with dictionary references and modifiers. Any conversion has to work with that stream, not just replace bytes 1:1.

## 3. Kanji name display on the officer status screen

Verified in Mesen by navigating to the officer status screen (Liu Bei):

- The screen shows:
  - katakana reading `リュウビ` in 8×8 text,
  - kanji name `劉備` in 16×16,
  - stats in 8×8 text.
- `OAM` contains no visible sprites over the name area, so the kanji is **BG**, not sprites.
- The nametable uses a 2×2 tile block at rows `$0C/$0D`, columns 2-5:

```
row $0C: 10 12 14 16
row $0D: 11 13 15 17
```

- At the captured frame, CHR `$1000` tiles `$10-$17` contain the two 16×16 glyphs `劉` and `備`. Tile order is column-major: `TL, BL, TR, BR`.
- This creates an apparent conflict: the same tile numbers `$16/$17` are also used for `し/す` in the stats text. The status screen therefore must be using a **raster split / alternate pattern-table mapping** (or a transient CHR state) to show the kanji and the kana stats from different tables. The exact split still needs tracing.
- What is certain: the name is BG, 16×16, and written as a 2×2 tile block. The “load 4 tiles into a CHR slot + write 2×2 nametable” technique is valid, but the status screen’s PPU table switching is screen-specific and must not be copied blindly.

This is the reusable mechanism:

1. Pick 8 consecutive CHR tiles (2 glyphs) or 4 tiles (1 glyph).
2. Copy/expand the 16×16 glyph into those tiles.
3. Write the 2×2 tile numbers into the nametable.
4. Optionally draw the katakana reading separately.

### 3.1 Where the name glyphs come from

The status-screen `劉備` tiles are **raw 2bpp data in PRG bank 0**, not in the
bank 1/2 kanji blocks.  The eight CHR tiles used for the two 16×16 glyphs
match bank 0 CPU `$8680-$86FF` exactly:

```
CHR $1010-$1017  ->  PRG bank 0 $8680-$86FF  (128 bytes, 8 tiles)
```

The earlier “unknown/compressed” note was caused by searching the bank 1/2
name-font blocks instead of the UI graphics bank.  The name display technique
is therefore straightforward: copy four consecutive tiles per glyph into a
CHR slot and write a 2×2 nametable block.

This does not change the display conclusion, but it means:

- The status-screen name glyphs are directly editable in
  `assets/graphics/bank00_chr.png`.
- The bank 1/2 blocks are a separate 136-glyph name/common-kanji set.
- The status screen still uses a screen-specific CHR slot/nametable position;
  it is not a generic dialogue “print kanji” routine.

The raw blocks at bank 1 `$8010-$9A0F` and bank 2 `$8010-$880F` remain the
best starting point for a font extension.

## 4. Glyph budget

Measured raw kanji blocks (separate from the bank 0 status-name tiles):

| Block | File offset | Size | Glyph size | Glyph count |
|---|---:|---:|---:|---:|
| Name/common kanji 1 | `0x4010-0x5A10` | `0x1A00` | 64 bytes | 104 |
| Name/common kanji 2 | `0x8010-0x8810` | `0x0800` | 64 bytes | 32 |
| **Total** | | | | **136** |

All 136 are non-blank. They are mostly officer-name and UI kanji (the first block visually resembles the Shu generals `劉備/関羽/張飛/趙雲`). They are **not** a general-purpose dialogue font.

TCRF claims 272 Chinese symbols in the Japanese version. Our measurement of the two raw 16×16 blocks gives 136 glyphs. Possible explanations:

- TCRF counted 8×8 tiles (272 tiles = 68 glyphs), or
- there is another compressed name font elsewhere, or
- the count includes both used and unused/duplicate glyphs.

Either way, 136-272 glyphs is far below what a normal RPG script needs (typically several hundred distinct kanji). A full kanji+kana conversion would need a new/expanded font.

## 5. CHR budget during dialogue

Measured at a stable dialogue frame:

- BG table `$1000-$1FFF`: only **1 completely blank tile** (`$80`).
- Sprite table `$0000-$0FFF`: **176 blank tiles** (`$00-$0F`, `$58-$7F`, `$88-$FF`).

Why this matters:

- Dialogue text is BG `$1000`; the BG table is almost full.
- The status-screen trick overwrites kana tiles `$10-$17` with kanji. In dialogue those tiles are `かきくけこさしす`, which are common. You cannot overwrite them globally.
- You could repurpose the katakana half of the kana table if the dialogue does not use katakana, but names/dictionary entries do use katakana.
- The free sprite tiles could hold kanji, but each 16×16 glyph needs 4 tiles and 4 sprites. A line with many kanji would hit the 64-sprite limit, and the portrait already uses sprites.

Feasible CHR strategies:

1. **Kanji cache in the kana table** — allocate 8-12 rarely used kana tiles as a 2-3 glyph scratch area; reload per message. Simplest, limited.
2. **Sprite kanji** — use free sprite tiles; needs sprite multiplexing and a strict per-line kanji limit.
3. **BG pattern-table switch** — copy kana to `$0000` (plenty of free tiles) and use `$0000` for the dialogue band, freeing `$1000` for kanji. Requires mid-frame PPUCTRL switching and moving/redrawing the portrait; larger engine change.
4. **Reduce/relocate UI graphics** — free tiles from `$1800-$1FFF` by replacing window graphics with compressed/procedural borders. Moderate work.

## 6. Is the status-screen routine reusable?

**Display technique: yes.**
The 2×2 BG block + 4-tile CHR upload is exactly what a dialogue kanji needs. The 16-pixel line pitch already matches.

**Exact routine: no, not as-is.**
It is tied to the status screen:
- fixed CHR slot `$10-$17`,
- fixed nametable position,
- status-screen-specific CHR reloading/restoring,
- no cursor/line-wrap/double-width handling,
- no dialogue-box clipping.

To reuse it in dialogue you need a generalized helper:

```
draw_kanji_16x16(glyph_index, screen_x, screen_y, chr_slot)
  - load 4 tiles from font bank/cache into chr_slot
  - write 2x2 nametable block at (x,y)
  - return new cursor x + 2
```

The dialogue renderer then needs:
- a new opcode (one of `$A1/$C1/$C2/$DA`) followed by a glyph index,
- a “wide character” branch that writes 4 tiles and advances the cursor by 2 columns,
- line-wrap logic that accounts for double-width cells,
- handling for the fourth line (border conflict),
- a glyph cache that loads only the kanji used in the current message.

## 7. Recommended implementation paths

### Path A — limited kanji mode (recommended first step)

Scope: convert a curated set of common words/names to kanji using the existing 136-glyph set.

- Add a `KANJI <index>` opcode using one unused high code.
- Implement `draw_kanji_16x16` using a small scratch slot in the kana table (e.g., tiles `$70-$77`, which are punctuation/rare kana) or free sprite tiles.
- Convert only high-value words: officer names, place names, `王`, `軍`, `城`, `兵`, `金`, `食`, etc.
- Keep the fourth line kana-only, or expand the box by one row.
- No ROM expansion, no new font. Text edits are limited and reversible.

This proves the pipeline and gives an immediate readability improvement without a full script rewrite.

### Path B — full kanji+kana conversion

Scope: all dialogue.

- Build a new 16×16 kanji font with the required glyphs (likely 500-1000).
- Add a font bank and a glyph cache. The cache loads 4 tiles per distinct kanji per message and evicts/reloads as needed.
- Convert the text data from kana bytecode to mixed bytecode, preserving dictionary references and pointer tables.
- Update the text editor/compressor; message lengths and address tables will change.
- Solve the CHR budget: either move kana to `$0000` during dialogue, free UI tiles, or use a hybrid BG/sprite scheme.
- PRG space: a scan of the 256 KB PRG found only about **6.9 KB** of long (≥256-byte) zero runs, with the largest run 1,536 bytes. A 500-glyph 16×16 font needs ~32 KB (plus a glyph cache/index), so a full conversion likely needs **ROM expansion to 512 KB** (MMC1 supports it) and new bank switching, or heavy repurposing of existing data.

This is a multi-week ROM-hacking project, not a small patch.

### Path C — 8×8 kanji font (not recommended)

An 8×8 kanji font would fit the current one-tile-per-character renderer with minimal engine changes, but:
- 8×8 kanji are barely legible,
- you still need hundreds of glyphs and CHR space,
- it would look inconsistent with the existing 16×16 name kanji.

## 8. Concrete next steps

1. The status-screen name-glyph source is identified (bank 0 `$8680-$86FF`);
   the remaining work is to generalise the screen-specific 2×2 draw into a
   dialogue helper.
2. The dialogue pointer tables and message streams are extracted into
   `decomp/text/*.dtx`, with generated pointer tables and code index
   references.  The remaining text work is decoding the high control/dictionary
   codes so those tokens can also be edited as words.
3. Dump and label the 136 raw bank 1/2 glyphs with kanji identities; build a
   glyph index → kanji table.  This is needed for any opcode mapping.
3. Implement a test harness: patch one dialogue message to include a `KANJI`
   opcode and display one existing glyph (e.g., `劉`) in the first line. This
   validates the renderer/CHR approach.
4. Decide the CHR strategy (scratch kana tiles vs. sprite kanji vs.
   pattern-table switch).
5. Only then convert a small word list. Measure text-length/pointer-table
   impact.
6. For full conversion, budget a new font + script conversion + ROM expansion.

## 9. Analysis artifacts

Created in this workspace:

- `tools/rom.py` — iNES parser/bank helpers
- `tools/disasm.py` — 6502 linear disassembler (py65)
- `tools/find.py` — byte-pattern search
- `tools/tiles.py` — 8×8 tile contact sheets
- `tools/glyphs16.py` — 16×16 glyph renderer (column/row order)
- `tools/labeled_tiles.py` — labeled CHR tile sheets
- `tools/*.lua` — Mesen test-runner scripts for input sequences, state dumps, CHR/nametable/OAM capture

Key output images:

- `out/dialogue/chr.png`, `out/dialogue/font1000.png` — dialogue kana font
- `out/kanji_oam/name_1000.png` — status-screen `劉備` glyph tiles
- `out/kanji_oam/s_6300.png` — officer status screen
- `out/kanji_4010.png`, `out/font_8010_glyphs.png` — raw kanji blocks
- `out/g16_4010_col.png` — 104 16×16 glyphs from `0x4010`

## 10. Important note about the Mesen save file

During testing, Mesen’s test runner loaded the ROM and auto-saved SRAM on exit. This overwrote:

`D:\EMU\NES\Saves\Tenchi o Kurau (Japan) (Rev 1).sav`

The original save had 342 non-zero bytes; it is now a nearly empty 22-byte save. No backup was made. If you have an external backup or a Mesen save-state, restore it. For future tests, copy the ROM to a different filename (so Mesen uses a separate `.sav`) or back up the `Saves` folder first.

`D:\EMU\NES\settings.json` was temporarily modified to allow Lua file I/O and has been restored from the backup taken before the change.

## 11. Decompilation / build environment

A byte-identical, routine-oriented reconstruction lives in `decomp/`:

- Toolchain: ASM6f v1.6 f03 (`tools/toolchain/asm6f/asm6f_64.exe`).
- Build: `decomp\build.cmd` or `python decomp\build.py`.
- Verified SHA-256: `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Source: `main.asm` + 16 bank files, one 16 KB bank per PRG bank.
- Code/data separation is execution-backed: instructions reached by Mesen CDL
  or direct control flow are disassembled; the RAM-resident inline routines
  copied by `call_inline_block` (`$C4E4`) are decoded into named blocks.
- Routine names and comments live in `tools/symbols.py`; the generated index is
  `decomp/FUNCTIONS.md`.
- Graphics and fonts are editable PNGs under `assets/`; `tools/assets.py`
  converts them back to exact NES tile bytes and verifies the round trip.
- Message banks 10/11 are editable `.dtx` text under `decomp/text/`;
  `tools/text.py` rebuilds the split pointer tables and message bytes and
  verifies the round trip.
- Bank 1/2 kanji have per-glyph labels (`b01_kanji_000` … `b01_kanji_103`,
  `b02_kanji_000` … `b02_kanji_031`, 64 bytes each); bank 9 kana has
  `b09_kana_000` … `b09_kana_127` (8 bytes each).
- `decomp/labels.mlb` and `decomp/labels.txt` contain the generated symbols for
  the Mesen debugger.
- Static cross-checking used Ghidra 12.1.4 via the REA CLI and direct headless
  exports; see `tools/ghidra_scripts/SeedExport.java` and `out/rea/`.
- CDL tooling: `tools/cdl_summary.py`, `tools/merge_cdl.py`,
  `tools/cdl_dump.lua`, `tools/cdl_capture_status.lua`, and
  `tools/cdl_from_state.lua`.

Current execution-backed coverage is concentrated in banks 7, 8, 13, 14, and
15. Unexecuted switchable-bank code and indirect-jump-only routines remain data
until a CDL run or a manual seed covers them. The reconstruction is a strong
base for text/glyph work, not yet a complete whole-ROM decompilation.

The save state `D:\EMU\NES\SaveStates\Tenchi o Kurau (Japan) (Rev 1)_11.mss`
contains a mid-dialogue scene. It can be loaded by the test-runner Lua harness
and is useful for capturing text-engine execution without replaying the intro.
