# Editable ROM resources

These files are the graphics/font side of the reconstruction.  The original
ROM uses CHR RAM, so there is no CHR ROM; the game copies tile data from PRG
into CHR RAM at runtime.  The resources below are the **PRG source blocks**
turned into ordinary images.

## Graphics / fonts

| File | Source | Format |
|---|---|---|
| `graphics/bank00_chr.png` | PRG bank 0, `$0000-$3FFF` | 8×8 2bpp tiles || `fonts/kanji_16x16_bank01.png` | PRG bank 1, `$0010-$1A0F` | 16×16 2bpp glyphs |
| `graphics/bank01_chr.png` | PRG bank 1, `$1A10-$3FFF` | 8×8 2bpp tiles |
| `fonts/kanji_16x16_bank02.png` | PRG bank 2, `$0010-$080F` | 16×16 2bpp glyphs |
| `graphics/bank02_chr.png` | PRG bank 2, `$0810-$3FFF` | 8×8 2bpp tiles |
| `graphics/bank03_chr.png` | PRG bank 3 | 8×8 2bpp tiles |
| `graphics/bank04_chr.png` | PRG bank 4 | 8×8 2bpp tiles |
| `graphics/bank05_chr.png` | PRG bank 5 | 8×8 2bpp tiles |
| `graphics/bank09_ui_a.png` | PRG bank 9, `$0000-$39FF` | 8×8 2bpp tiles |
| `fonts/kana_8x8.png` | PRG bank 9, `$3A00-$3DFF` | 8×8 1bpp glyphs |
| `graphics/bank09_ui_b.png` | PRG bank 9, `$3E00-$3FFF` | 8×8 2bpp tiles |

The status-screen 16×16 name glyphs (`劉備`) are in bank 0 at `$8680-$86FF`
and have labels `b00_status_name_000` / `b00_status_name_001` in the assembly.

`screens/` contains reference screenshots (`dialogue.png`,
`field_message.png`, `officer_status.png`) captured from Mesen.  They are
documentation only and are not build inputs.

### 2bpp tile sheets

* 16 tiles per row, 8×8 pixels each.
* Colours are fixed:
  * black `(0,0,0)` = colour 0
  * dark grey `(85,85,85)` = colour 1
  * light grey `(170,170,170)` = colour 2
  * white `(255,255,255)` = colour 3
* A tile is stored in the NES order: 8 bytes plane 0, then 8 bytes plane 1.

### 16×16 kanji sheets

* 16 glyphs per row.
* Each cell is 16×16 pixels.
* The four 8×8 NES tiles inside a glyph are stored **column-major**:
  `TL, BL, TR, BR`.
* Editing a glyph keeps the 64-byte stride; adding/removing glyphs changes
  the ROM layout and is not supported without updating the bank size.

### 1bpp kana font

* 16 glyphs per row, 8×8 pixels each.
* Black = 0, white = 1.
* Each glyph is 8 bytes (one bit per pixel); the game expands it to a 2bpp
  tile by copying the 8 bytes to plane 0 and zeroing plane 1.

## Data / text resources

`data/` holds exact binary blocks for data that is not an image: map data,
tables, and whole-bank fallbacks used by code that embeds tables.

Bank 10/11 messages are no longer edited here.  Their editable source is
`decomp/text/bank10_messages.dtx` / `bank11_messages.dtx`; `tools/text.py`
rebuilds the split pointer table and message bytes.  The `text/*.bin` files in
this directory are the original-bank fallback/verification copies.

## Build / verify

`decomp/build.py` runs `python tools/assets.py build` (PNG -> NES bytes) and
`python tools/text.py build` (DTX -> message bytes and pointer tables), then
assembles the ROM. The final SHA-256 is checked against the original ROM. If a
PNG or DTX is edited, the build output changes intentionally; if it is not
edited, the round trip is byte-identical.

`python tools/assets.py verify` checks every PNG against the original ROM
without assembling.
