# Map-mode text renderer: assessment (2026-11-12)

The user's scheme for the last big overhaul: one dedicated renderer for
every text cell in map mode.  It drops the band page, the dialogue canvas
and the compile-time kana borrowing.  This document is the assessment
before any build source changes: measured facts, how the scheme maps onto
the game, open questions.  Probes: `tools/lua/txr_rows.lua`,
`txr_vblank.lua` and `txr_producers.lua`.  Runs: `out/test/txr/`, kanji ROM
`e1dadf97` (a1cf5e6), states `out/user/m7`.

## The scheme as given

- **Renderer bank.**  A new, dedicated PRG bank.  When it's done, the
  canvas RAM code in battery RAM is freed for the renderer.
- **Setup.**  No full 8x8 font upload, only the fixed set.  New tiles
  `$00-$0B` are the old `$6D $0B $6E $6F $0C $0D $7D $7E $0E $0F $70 $71`:
  the frame corners, the top and bottom edges, the left and right edges,
  ＊, ★, ▶ and ▼.  `$7F` is blank (the old `$0A`).
- **At boot**, the fixed set goes to CHR `$2000`, `$2800` and `$3000`.
- **At map-mode setup**, the fixed set goes to the first bank (`$1000`),
  plus コマンド at `$7B-$7E`: the old `$4B $24 $68 $6B`, where `$6B` is the
  one-tile ド.
- **Allocation.**  Kanji take tiles from `$0C` up, in 8x16 order (t and
  t+1 are the left column, t+2 and t+3 the right).  Kana take tiles from
  the top down: `$7A` in the first bank.  Glyphs already uploaded to a bank
  are reused.
- **Screen parts.**  Four parts, each shown through its own page:

  | Part | Tile rows | Scanlines | Page |
  |---|---|---|---|
  | 1 | 0-8 | 0-71 | `$1000` |
  | 2 | 9-14 | 72-119 | `$2000` |
  | 3 | 15-20 | 120-167 | `$2800` |
  | 4 | 21-29 | 168-239 | `$3000` |

  Three HIRQs switch the page and do nothing else.
- **Uploads.**  Every glyph a text update needs is uploaded before its
  cells show.  If that misses the NMI window, lag frames follow.  No
  half-kanji.

## Measured facts

### CHR in map mode

The font page (`$1000-$17FF`, tiles `$00-$7F`) holds only the 128 font
tiles in map mode.  Measured in the village, the overworld, the town
shop, the record office and the pre-battle map: the only tiles that
differ from the bank-9 font are kanji slots.

With every window closed, no visible map cell uses a tile below `$80`.
The map is entirely in R1 (`$1800-$1FFF`), so switching R0 per part never
touches the map.  Off-screen columns keep `$0A` and stale window cells
from earlier screens, but the map writers replace them before they
scroll into view.

So the first bank has **111** free tiles, `$0C-$7A`: 128 minus 12 fixed,
1 blank and 4 for コマンド.  `$2000`, `$2800` and `$3000` have **115** each,
`$0C-$7E`.

CHR `$2800-$3FFF` is unused today.  `$2000-$27FF` is the band page (R0
bank 8), which the overlay still uses for kanji in non-map scenes: the
history intro, the oath scene and the other fixed-window screens.

### Where windows sit

`txr_rows.lua` covered talk, search, formation, officer and item paths in
4 states, 20 runs.  In every one:
- each window's top corner is on an even screen row (2, 6, 18);
- each bottom corner is on an odd row (7, 13, 15, 17, 19, 23, 27);
- `scroll_y` is a multiple of 16 at every map-mode text write.

So every 2-row text line starts on an odd row.  The part boundaries are
at rows 9, 15 and 21, also odd, so no line or kanji is ever split
between two parts.

Windows seen: the command window at rows 2-13 (part 1, rows 2-8, then
part 2), sub-windows at rows 2-7, 6-15 and 6-17, and the dialogue and
side menus at rows 18-27 (part 3, rows 18-20, then part 4).

### Who writes text cells

`txr_producers.lua` traced, for every map-mode nametable byte below
`$80`, the PC that queued it:

| Producer | What |
|---|---|
| `text_draw_line` (`$DCDC`) | whole window rows |
| `text_render_cell` (`$DBF2` top, `$DC32` bottom) | typewriter cells |
| `text_draw_cursor` (`$CD0B`) | ▶ and its blank |
| `cv_emit` (canvas, RAM) | dialogue rows in the canvas; `scroll_map`'s window rows in the original |

Nothing else wrote one on these paths.  So the tile translation (old
font code to tile in the part's page) needs four hooks, and the hack
already hooks two of them (`cv_sm`, `text_render_cell`).

### Vblank left for uploads

`txr_vblank.lua` recorded, per map-mode NMI, the scanline where the game's
queue flush ends.  The NMI turns rendering off at entry and restores the
mask at `$EEDA`.

| Bytes flushed | Flush ends (scanline) | Frames |
|---|---|---|
| 0 | 246.2-246.3 | idle |
| 1-16 | 246.7-247.2 | typewriter cells, cursor |
| 17-48 | 248.7-250.8 | |
| 49 and more | 253.1-259.3 | window rows |

Uploads after the flush have to end by about line 259.  That leaves the
scroll and mask writes and the IRQ arm before the pre-render line.

- **Typewriter frames:** about 12 lines (~1,350 cycles).
- **Plane-0 tile cost:** a PPUADDR pair plus 8 unrolled bytes, about 80
  cycles.  Plane 1 can stay zero, because every text tile is 1bpp.
- **Capacity:** about 16 tiles (4 kanji) per typewriter frame.
- **Window-row frames:** almost nothing.  A window whose rows need new
  glyphs uploads them first, so it opens with lag frames.

### IRQ

The exact-line arm from map-canvas step 1 is still in place:
- stage 0 at the pre-render clock;
- the switch in the hblank of the line after the clock.

It gives exactly +1 on both frame parities, except in frames that flush
104 or more bytes.  Those are full map redraws, with no text on screen,
and land one line late.

Three chained stages give the R0 writes in the hblank of lines 71, 119
and 167.  Each IRQ waits about 90 cycles for hblank, so about 300 cycles
per frame, only while text is on screen below row 9.

### Space

- **PRG.**  Bank 26 is empty (16 KiB).  Bank 27 holds only the 1.7 KiB RAM
  image, at `$A000`.
- **Battery RAM.**  The canvas RAM code is `$7900-$7F92`, 1,683 bytes.
  Its state is in `$0780-$07FF`.

Not all of the RAM code is canvas:

| Code | Size | Fate |
|---|---|---|
| `cv_irq`, `cv_nmi` | 149 + 302 | become the 3-split; only the IRQ entry (~60 bytes) must stay in RAM or the fixed bank |
| `cv_fill` | 97 | four-screen battle fill; can move to a bank |
| `cv_stream` | 240 | persuasion stream timing; can move to a bank |
| `cv_sm_hook`, `cv_wincb` | 32 | battle UI hooks from step B; can move to a bank |
| `cv_split`, `cv_band`, `cv_ctp`, `cv_ti`, `cv_sm`, `cv_flanks`, `cv_emit` | ~860 | the canvas; removed |

About 1,600 bytes become free.

## How the scheme maps onto the game

- **Translation per row.**  The four producers write old font codes into
  the queue.  The hook knows each entry's screen row, and therefore its
  part.  It maps every code to that page's tile, allocates and uploads on
  a miss, and holds the nametable entry back until the glyph is in CHR.
  - Lines that move between parts are translated again for the new page.
    The dialogue scrolling from row 21 to row 19 moves from part 4 to
    part 3.
  - Cursor moves and blanks (`$70`/`$0A` become `$0A`/`$7F`) go through
    the same hook.
- **Kanji in the line buffers.**  The engine's line buffers hold one byte
  per cell, and map tiles never pass through them.  So codes `$80-$FF` can
  stand for kanji: a small register table (glyph id) times 4 quadrants.
  The overlay writes those codes in place of today's band-page tile
  numbers.  The text compiler then needs no per-page tile plan for
  map-mode pages.
- **Reuse.**  Per page there are two lookups:
  - a kana map (old code to tile, 128 bytes);
  - a short kanji list (glyph id to tile, about 28 entries).
- **Freeing.**  Slots of closed windows must come back.  Two options:
  - **(a) Readback (recommended).**  When a page is full, read the part's
    rows back from VRAM: 6-9 rows of 32 cells, 2-3 vblanks.  Keep only
    the tiles still shown.  It is rare, and it needs no shadow or extra
    hooks.
  - **(b) Shadow.**  A 960-byte screen shadow in the freed RAM.  It needs
    the map writers hooked too, so it knows when map rows cover text.
- **Uploads.**  The main thread decodes glyphs from the font banks (1bpp
  kana in bank 9, kanji in banks 23-25) into a staging buffer in the
  freed RAM.  The NMI copies plane 0 after the game's flush, up to the
  line-259 budget, and carries the rest to the next frame.  A text update
  waits until its glyphs are all in.
- **What goes away in map mode:**
  - the band, and the band-page mirroring of every game CHR write;
  - the canvas (windows draw into the visible half again, as in the
    original);
  - the per-page kana borrowing and the stale-tile restore.

  The four-screen ring and the write-ahead rows stay; they fix map edges,
  not text.
- **Non-map screens.**  Battle (pool and UI bank), the info and army
  screens are untouched.  The fixed-window scenes keep the overlay and the
  band.

## Open questions for the user

1. **Budget.**  You give the first bank 47 free tiles.  I count 111
   (`$0C-$7A`): the map uses no tile below `$80`, so all 128 are text,
   minus 17.  Is 64 of your count reserved for something I'm missing (a
   1 KiB bank? portraits?), or does the brutal case have 111 to work with?
2. **"Kana from `$FE`" in the other banks.**  `$2000`, `$2800` and `$3000`
   are 2 KiB pages, tiles `$00-$7F`.  I read this as `$7E` (blank at
   `$7F`).  Correct?
3. **The band page in non-map scenes.**  The overlay still puts kanji in
   `$2000` for the history, oath and other fixed-window scenes, and that
   would overwrite part 2's fixed set.  Options:
   - **(a) Recommended:** move the band to `$3800`, which is free, so the
     boot-time sets are never touched;
   - **(b)** write the fixed set to `$2000` again at each map entry.
4. **Menus.**  Officer, item and place names in map menus are kana today.
   Does this overhaul cover the messages only, or kanji names in menus
   too?  Your brutal-case count probably decides it.
5. **Dialogue scrolling.**  The current build clears the window at each
   wait in a kanji message.  The original scrolls line by line.  The new
   renderer can scroll as the original: a line moving into part 3 is
   re-uploaded into `$2800`.  Should it?

## Work order (after the answers)

1. **Pages and IRQ.**
   - The boot-time fixed set in `$2000`, `$2800` and `$3000`.
   - The band moved, if 3a.
   - Map-mode setup of the first bank.
   - The 3-stage split in place of the canvas and band splits in map
     mode.
   - The canvas removed (windows in the visible half).
2. **Translation.**  The four producer hooks, the allocator and
   uploader in bank 26, the readback GC.  Kana and frames only, no kanji
   yet.
3. **Kanji.**  Overlay codes `$80-$FF`, the compiler without map-mode
   tile plans, scrolling (if 5).
4. **Clean-up.**  The RAM code shrunk to the IRQ entry, the rest moved to
   bank 26, `$7900-$7F92` handed to the renderer.
5. **Gates.**  `band_check`, `canvas_check` and parts of `garble_state`
   assume the band or the canvas.  They will be replaced by:
   - a glyph-truth check: every shown text cell, read through its part's
     page, equals the glyph it should be;
   - a no-half-kanji check;
   - IRQ landing lines;
   - the existing deadline, taint, RAM and zero-page gates.
