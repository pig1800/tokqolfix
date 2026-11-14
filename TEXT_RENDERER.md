# Map-mode text renderer: assessment (2026-11-12)

The user's scheme for the last big overhaul: one dedicated renderer for
every text cell in map mode.  It drops the band page, the dialogue canvas
and the compile-time kana borrowing.  This document is the assessment
before any build source changes: measured facts, how the scheme maps onto
the game, open questions.  Probes: `tools/lua/txr_rows.lua`,
`txr_vblank.lua` and `txr_producers.lua`.  Runs: `out/test/txr/`, kanji ROM
`e1dadf97` (7dfd2ad), states `out/user/m7`.

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

**Why the line before (2026-11-14, the user's question).**  The game
fetches BG from `$1000` and sprites from `$0000`.  So A12 rises once a
line at the next line's first BG fetch, about dot 325, not at dot 260
(`mmc3_clock_trace.lua`; MAP_CANVAS.md "IRQ landing").  An IRQ for the
boundary line itself would run inside that line's visible part.  Each
stage therefore takes the clock at the end of the line two before the part
(line 70 for part 2, which starts at line 72).  The handler's own path
plus the `TXR_D` loop then runs through line 71 and writes R0 in its
hblank.  The write is not cycle-exact.  The IRQ waits for the instruction
it interrupts (0-6 cycles), which gives an 18-dot spread inside the 64-dot
hblank: 9 dots spare before dot 257, 35 after.

Re-measured on the kanji-store build (`1191ee64`): standard path from
power-on, 6,000 frames, and the menu cycle (`u3b_c`), 4,230 frames.
- `tools/lua/map_parts_timing.lua`: 7,883 sequences, all ok.  Every write
  is in line 71, 119 or 167 at dots 266-285.  No skips (`nmi_busy` /
  `KANJI_MAINCHR`), and no line-72 writes; the earlier run had heavy
  frames landing late.
- `tools/lua/map_parts_audit.lua`: every R0 write is logged and each map
  frame is checked line by line.  Across 7,882 frames, every visible line
  was fetched from its part's page, with 0 torn lines.

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

## Decisions (user, 2026-11-12)

1. The first bank has 111 free tiles.  The user's 47 counted a kanji as
   2 tiles.
2. In `$2000`, `$2800` and `$3000`, kana start at `$7E` and go down.
   `$7F` is blank in every bank.
3. The band page for non-map scenes moves to `$3800` (`CHR_BAND_LO` 14).
4. Kanji names in map menus come later, after this engine
   (`namekanjilist.csv`).
5. Dialogue scrolling comes later.  The kanji crossing part 2 and part
   3 needs its own study.  Until then the current flip to a fresh
   window at each wait stays.

## Implementation design

### Pages and tiles

| Part | Rows | R0 (1 KiB bank) | Kana from | Pinned |
|---|---|---|---|---|
| 1 | 0-8 | 4 (`$1000`) | `$7A` | `$00-$0B` fixed, `$7B-$7E` コマンド, `$7F` blank |
| 2 | 9-14 | 8 (`$2000`) | `$7E` | `$00-$0B`, `$7F` |
| 3 | 15-20 | 10 (`$2800`) | `$7E` | `$00-$0B`, `$7F` |
| 4 | 21-29 | 12 (`$3000`) | `$7E` | `$00-$0B`, `$7F` |

- **The fixed set.**  The old codes `$6D $0B $6E $6F $0C $0D $7D $7E $0E
  $0F $70 $71` become new `$00-$0B`, and the old `$0A` (blank) becomes
  `$7F`.  These tiles are the same in every page, so a fixed code needs
  no part.
- **Pinned in part 1.**  The old `$4B $24 $68 $6B` (コマンド) are pinned at
  `$7B-$7E`.
- **Glyph bytes.**  Every text tile is 1bpp: plane 0 only, plane 1 stays
  zero.
  - **Kana:** 8 bytes from bank 9 `$BA00 + 8 * code`.
  - **Kanji:** code = glyph-bank index * 512 + local.  The bank is 23 +
    (code high byte >> 1); high-byte bit 0 selects the `+256` half.  Byte
    j is at `$8C00 + half + j * 359 + (local & $FF)`.  Bytes 0-7 are the
    top-left tile, 8-15 the top-right, 16-23 the bottom-left and 24-31
    the bottom-right.
  - **Kanji tile order in a page:** 8x16, so t is the top-left, t+1 the
    bottom-left, t+2 the top-right and t+3 the bottom-right.  Groups are
    4-aligned from `$0C`.

### Kanji in the line buffers

- **Codes.**  The overlay writes logical codes into `$0300`/`$0318`: `$80
  + 2e` for the left half and `$81 + 2e` for the right half.  e is the
  entry index in the page record, and `REG_LO/HI[e]` = the glyph code.
  The engine's line-end markers (`$FA-$FF`, control bytes stored in the
  top row) are unchanged.
- **Top or bottom.**  In map mode a text line's top row is an odd screen
  row, and NT row parity equals screen row parity (`scroll_y` is a
  multiple of 16).  So the row parity tells top from bottom.

### Hooks

| Site | Change |
|---|---|
| `load_battle_palette` `$DE8D` (the map's font load, from `screen_refresh` and at boot) | map init: page 1 lower = fixed set + コマンド, rest zero; allocator reset; `TXR_ON` = 1 |
| `set_ppu_scroll` `$C2AB` (already `jmp cv_fill`; every `clear_screen`, the start of every non-map screen) | with `TXR_ON`: the font back into page 1 (128 tiles, rendering off), `TXR_ON` = 0 |
| `text_draw_line` end `$DD03` | with `TXR_ON`: translate the entries from `vram_queue_write` to X before the commit |
| `text_render_cell` `$DBCA` | with `TXR_ON`: the renderer's own cell loop (a kanji's two columns in one flush; waits as the original) |
| `text_draw_cursor` `$CD0B` (the tile store) | fixed-code map (▶ `$70` to `$0A`, blank `$0A` to `$7F`, ▼ `$71` to `$0B`) |
| `flush_vram_queue` end `$D9EA` | NMI glyph uploads from the staging queue, within the vblank budget |
| overlay `KANJI_EC` and the page logic | with `TXR_ON`: logical codes, `REG[e]`; no band and no tile plan |
| IRQ (`cv_irq`, `cv_nmi`, `irq_arm0`) | with `TXR_ON`: stage 0 at the pre-render clock, then R0 = 8 / 10 / 12 in the hblank of lines 71 / 119 / 167 (reload N = 70, then latch 47 twice); the NMI selects R0 = 4 |
| canvas (`cv_ti`, `cv_ctp`, `cv_split`, `cv_flanks`, `cv_emit`) | removed; `cv_sm`'s step-B battle hook stays |

### Translation and allocation (bank 26, main thread)

- **Per entry.**  NT address to screen row (`ntrow` - `top`, mod 60;
  `top` = `ppu_ctrl` bit 1 * 30 + `scroll_y` / 8), then the part.  Each
  byte is looked up:
  - below `$80`: fixed set, else kana;
  - `$80-$F9`: kanji half;
  - `$FA` and up: unchanged.
- **Misses.**  A miss allocates a tile and stages the glyph.  The entry
  is committed only after the NMI has uploaded the staged tiles (waits
  with `wait_vblank_queued`; direct writes in busy or rendering-off
  frames).
- **Lookups.**  Kana: one tile per part from the top down, a per-part
  map.  Kanji: a per-part list (glyph to group).
- **Full page:** read the part's visible rows back from VRAM (after the
  queue is flushed), keep the tiles still shown, and free the rest.

### RAM

- **Code.**  The canvas-only code goes.  What stays in RAM is the IRQ,
  the NMI arm and stream step, the fill and font restore, the uploader,
  the stubs into bank 26, and the bank reader.
- **Tables** (about 800 bytes): kana maps, kanji lists, group bitmaps,
  `REG`, the staging queue.  They fill the rest of `$7900-$7F9B`, plus
  `$0780-$07FF`.

### Order

1. Pages, init, restore and the IRQ split.  Canvas off.  Kana and
   frames through the hooks.
2. Kanji through the overlay, no half-kanji.
3. Canvas code removed, gates (glyph truth, IRQ lines, deadline, taint,
   RAM).

## Progress (2026-11-12, first working build)

Commits `64da4ae` and the follow-up.  The original build is still
byte-identical, and `bank15_lint` passes.

**In place:**
- **Bank 26 (`txr.asm`, about 2.4 KiB).**
  - The map init (`$DE8D`).
  - The font restore (in the nametable fill, i.e. `clear_screen`).
  - The per-part allocator: kana map, kanji groups, tile bitmap.
  - Staging.
  - The translation of `text_draw_line`'s entries and the
    `text_render_cell` loop (a kanji's two columns in one step).
  - The fill.
  - The split's NMI arm and the glyph uploader, which the NMI maps at
    `$8000`.
- **RAM image (757 bytes, `$7900-$7BF4`).**  The IRQ stages, the stream
  step, the stubs and the bank reader.
  - The renderer never waits itself.  Its calls return a status, and the
    stub waits at the original routine's stack depth.  A first version
    that waited inside bank 26 overflowed the text task's stack
    (`$0100-$0130`) and crashed.
  - In rendering-off frames the glyphs are written directly, with the
    NMI held off.
- **Tables.**  `$7BF5-$7F9B`, plus `$0780-$07F3`.
- **Overlay.**  In map mode it writes the kanji codes and `REG_LO/HI` and
  posts no requests.  The hack's NMI is skipped in map mode.
- **Band page.**  Now at CHR `$3800` (`wr_reg1` maps page 2 to R0 14).
- **Canvas.**  Removed: the `$CA59` patch, `cursor_to_ppu`'s tail and
  `redraw_start`'s redirect are back to the original.  `redraw_start` now
  frees every part's glyphs.

**Measured** (battery-save boot, town, `out/test/txr/`):

| Check | Result |
|---|---|
| IRQ page switches | 2,436, every one in line 71, 119 or 167 at dots 266-282 (hblank).  An IRQ armed before `clear_screen` once switched 14 lines early on the title; fixed (leaving map mode and rendering-off map frames turn the IRQ off). |
| Command window | the finished window pixel-identical to the previous build (`7dfd2ad`); complete at frame 922 against 919, drawn over 8 frames (row by row, each row waiting for its new glyphs) where the previous build showed it at once |
| Kanji message 「早くお行きなさい 玄徳」 | every kanji whole on its first frame (no half kanji) |
| Officer list, item window and sub-window, info screen round trip | the same pictures as the previous build once drawn; the info screen (font restored by `clear_screen`) pixel-identical |

**Not done yet:**
1. **Speed.**  Upload a row's glyphs in the same NMI as its entry (the
   uploader before the game's flush, a lag frame only when they do not
   fit), so windows open at the original pace.
2. **Full pages.**  Freeing slots when a page is full (the VRAM read-back
   GC).  Today slots come back only at the full redraw that closes the
   map's windows.  A cell that finds no slot is drawn blank and counted in
   `TXR_FULL` (`$078F`).
3. **Gates.**  `band_check`, `canvas_check` and parts of `garble_state`
   assume the band or the canvas.  Save states from earlier builds hold
   the old RAM image and no renderer state, so they need a converter.
   Still to run: stack depth (`taint_check`), battle entry and exit, the
   persuasion stream, the deadline gate.

### Second round (2026-11-12, after the user's review)

The user's answers:
- Battle, the info screen and the army screen keep their own (approved)
  code; the renderer is map mode only.
- 3 frames slower to open a menu is fine (the 外星科技 translation needs
  about 15).
- Tile freeing is not needed: only the shop's buying returns to a previous
  menu; every other cancel closes the whole menu.
- Save states: the user makes fresh ones on request; no converter.

Fixes:
- **Title glitch.**  The boot's font load (from the reset path, RAM
  `$061F`) went through the same hook as the map setup.  The logo showed
  the renderer's tiles, and the band page (now CHR `$3800`) never got its
  copy of the font, so the title's history window lost its kana and
  frame.  The hook is now `screen_refresh`'s `jsr load_battle_palette`
  (`$CF22`).  At boot only pages 2-4 are set up, at the first map setup.
- **Opening logo.**  The glyph uploader sat on the NMI's flush call
  (`$EE9E`), 26 cycles before the game's raster loops.  It moved to
  `cv_nmi` (`ef08_gate`, normal frames only): 6 tiles, minus one per 8
  bytes flushed.  With uploads the arm ends by line 256.8.
- **Stack.**  The font restore read bank 9 through the bank switcher,
  inside `clear_screen`: 11 bytes deeper than the original fill (lowest
  push `$0110`).  Bank 26 now carries a copy of the font (the build's
  asset), so kana reads and the restore need no bank switch.  Lowest push
  `$0116` (the previous build: `$0117`) on the boot, town, menus, info
  screen and army screen path.

Checks (battery-save boot, `out/test/txr`):

| Check | Result |
|---|---|
| Boot, logo, title menu, history window (frames 11-650) | pixel-identical to `7dfd2ad` |
| Town fade-in | 1 frame earlier (the map setup writes less than the font copy) |
| Army screen round trip | identical |
| Map page switches | 5,169, all in lines 71, 119, 167 |

### Third round (2026-11-12): the user's states

States `out/user/txr/s1`-`s4` (Mesen slots 1-4, the user's; the RAM
image installed with `tools/mss_canvas.py --keep` into `k1`-`k4`).

| Path | Result |
|---|---|
| s1 random battle, s2 boss battle (saved on the black screen before them) | battle text drawn by the battle's own code (the font back in page 1); after the victory the map setup runs again and the map menu and messages are right |
| s3 shop: buying, back to the previous menu, buying again | right (武器屋 何 他 入用; the gold window straddles parts 2 and 3) |
| s4 record office, saving | right; ▼ at the page wait (fixed: `$71` was not translated) |
| New game, story scenes (frames 20-2340) | pixel-identical to `7dfd2ad` |
| New game, the first town's long speech | **bug**: some kanji blank in parts 3 and 4 |

The bug: a dialogue that flips through many pages in one window keeps
every earlier page's kana and kanji allocated, and parts 3 and 4 fill up.
Freeing is needed after all, but only when a part is full.

The fix is a read-back GC, run only on an allocation failure:
1. Upload the staged tiles.
2. Read the part's visible rows back from VRAM, one row per NMI.
3. Keep the tiles still shown, plus the cells of the current entry
   already translated.
4. Free every other kana tile and kanji group, then retry.

The GC is in (`txr.asm`: `gc_step`, `row_read`, `row_addr`).  On an
allocation failure:
1. The staged tiles go up.
2. The part's visible rows are read back, one row a frame through the
   NMI (all at once with rendering off).
3. The tiles shown, and the tiles of the line being translated, are kept.
4. Every other kana tile and kanji group of the part is freed, and the
   cell is retried once.  A second failure draws it blank (`TXR_FULL`).

| Check (build with the GC) | Result |
|---|---|
| New game, the first town's speech | every kanji drawn (武器 用意 立 虐 救 were blank before) |
| Shop, record office (`k3`, `k4`, RAM image reinstalled) | pixel-identical to the build before the GC (the GC never ran there); `TXR_FULL` 0 |
| Boot, logo, title, history (frames 11-650) | pixel-identical to `7dfd2ad` |
| Stack | lowest push `$0116` |
| Map page switches, new-game path | 10,965.  28 one line late (72, 120, 168): four frames at each page flip, whose window redraw floods the queue past the force limit, as with the band before. |

States saved by one build hold that build's RAM image.  After every
change to `canvas_ram.asm`, reinstall it with `tools/mss_canvas.py
<state> <out> --keep`.

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

## Kanji UI (2026-11-12)

The user's request after play-testing: every map-mode UI text in kanji,
officer names excepted.  Also, the gold window's 金 / 兵糧 become 16x16
kanji beside the numbers.

### How

- **One hook.**  The window templates (`text_input`, `$CC02`) and the
  item, tactic and place names (`draw_string_from_pointer`, `$D5C0`) put
  every cell through `text_put_tile`.  Both calls now go to `txr_tp`, 11
  bytes in the fixed bank's last free space (`$C6C7`).
  - Outside map mode it jumps to `text_put_tile`, so battle, the title and
    the scenes are unchanged.
  - In map mode it goes through `txr_tpm` (RAM, 11 bytes) to the renderer's
    `TXF_PUT`.
- **Substitution, not new data.**  The ROM's kana strings stay as they
  are.  `TXF_PUT` recognises a known kana word, puts its kanji form, and
  skips the rest of the word's bytes.
  - Template words: by window (`text_mode`) and byte offset (`text_col`).
  - Item names: by record pointer at byte 2.
  - Tactic and place names: by record pointer at byte 0.
  - The tables are `txr_ui.inc`, generated by `kanji_build.py
    build_txr_ui`:
    - template words from `kanji_common.MAP_UI_WORDS`;
    - items and tactics from `kanjiwordlist.csv`;
    - places from the glossary (`decomp/text/kanji_r14/glossary.tsv`).
- **Line codes.**  UI kanji use REG entries 16-31 (codes `$A0-$BF`).  A
  message page's entries stay 0-15, so a menu never disturbs a message's
  kanji.  An entry is reused only when no row buffer (`$0300-$035F`) and
  no saved row (`$0180-$01DF`) holds its codes.  Equal glyphs share one
  entry.
- **Labels** (`TXF_LABEL`, called by bank 14): the gold window's 金 and
  兵糧, and window `$20`'s その他.

### Converted

| Where | Kana | Kanji |
|---|---|---|
| command window `$00` | はなす しらべる たいれつ ぶしょう どうぐ | 話す 調べる 隊列 武将 道具 |
| formation `$04` | ならび ぐんし | 並び 軍師 |
| item menu `$07` | つかう わたす そうび すてる | 使う 渡す 装備 捨てる |
| shop `$1C` | かいにきた うりにきた | 買いに来た 売りに来た |
| officers `$1F` | のうりょく くわえる はずす かいこ | 能力 加える 外す 解雇 |
| record office `$24` | きろく よぶ | 記録 呼ぶ |
| list `$20` | そのた | その他 |
| gold window `$18` | 金 兵ろう (8x8) | 金 兵糧 (16x16) |
| item names (64 records) | e.g. こん たんけん かわのどうあて | 棍 短剣 皮の胴当 |
| tactic names (in messages) | e.g. れんかのけい | 練火の計 |
| place names (the 神行の札 list) | e.g. ジョシュウじょう | 徐州城 |

Item names are kanji wherever map mode prints them: lists, shops and
runtime names in messages (「リュウビは短剣をカンウに渡した」).

Added to `kanjiwordlist.csv` (items missing from it):
- 皇帝玉璽, 皇帝の璽, 皇帝信璽, 天子信璽, 天子の璽, 天子行璽, 伝国の璽,
  黄色い玉 (keyitem, so the battle's item window shows them too);
- 金 and 兵糧 (other).

Still kana:
- そうこうのふだ: no kanji chosen.
- Window `$19`'s title 兵ろう / 金: it is in the top border row.  A 16x16
  kanji there would need its top half on an even row, against the
  renderer's row-parity rule.
- Not map mode, so unchanged:
  - the title's menus (げーむをはじめる…), the speed menu `$29`, the name
    entry grid;
  - (the battle's prisoner window `$21`: kanji since 2026-11-13,
    INFO_SCREEN.md "The prisoner window").

### Window geometry

- A template's first byte is the row offset and the second the column
  offset, both in metatiles, so windows start on even columns.
- The map redraw that closes windows covers screen columns 2-29 only.  A
  window reaching column 30 leaves cells behind (seen in a test: the
  gold window's last digit and border stayed after it closed).
- **Gold window `$18`.**  It was columns 20-29, with 8x8 金 / 兵ろう at
  column 22 in the top row and 7 digits ending at column 28.  It is now
  columns 18-29, width 12.
  - 金 and 兵糧 in 16x16 at column 19, right after the left border, their
    bottom row the number's.
  - The number right-aligned at column 28, in 6 cells (23-28).  Up to 5
    digits leave a cell after 兵糧.
- **Draw order.**  The shop's buy list (bank 14 `$8E24`) drew the gold
  window first and the item list over its top-left corner (rows 12-13,
  columns 18-19, where 金 now starts).  It now draws the list first, then
  the gold window over it (`b14_k_goldover`).  Then it restores the list's
  cursor state (`$16/$17` the template pointer, `$54` the line count,
  `text_mode`) and waits on the list as before.
- **Why not the user's first layout** (border at 19, label at 20, number
  to 29, border at 30).  Column 30 is outside the map redraw, and 19 is
  not an even start.  The user then chose between this draw-order change
  and an odd-column window plus clearing column 30.  The draw order is
  the smaller change.
- **Buy / sell `$1C`.**  It was columns 22-29, width 8.  It is now 20-29,
  width 10, for 買いに来た (7 cells).

### Checks

| Check | Result |
|---|---|
| New-game path, frames 20-4200 (story, first town speech) | pixel-identical to the previous build |
| Command window | kanji; complete 3 frames later than the previous build (4 tiles per kanji to upload) |
| Shop (`u3`: the user's slot 3, RAM image reinstalled) | item list, gold window, buying, back, buying again: right; no cells left after closing |
| Record office (`u4`) | 記録 / 呼ぶ, the save |
| Item menu, give | 使う 渡す 装備 捨てる; 「リュウビは短剣をカンウに渡した」 |
| Formation | 並び 軍師 |
| Stack (task pushes, IRQ left out) | lowest `$0111` on these paths, as the previous build's deepest (`$0111`, record office); the IRQ adds 5 |
| `TXR_FULL` | 0 |
| RAM image | 755 of 757 bytes |
| Original 256 KiB build | byte-identical |

### Fifth round (2026-11-12): the user's crash and half-drawn windows

**Crash** (the user: open menus again and again, 隊列 and cancel; slot 1
held the crashed state, with the CPU halted at $0000).
- **Reproduced.**  From slot 3 a loop of 隊列 / 並び / cancel crashed at
  frame 1849, with execution in page 1 (`$0102`).
- **Cause: the game's `return_inline_block` (`$C4FB`).**  It runs `tsx /
  pla / pla` and only then reads its return address from the freed bytes
  (`lda $0101,x` / `lda $0102,x`).
  - An interrupt between the pops and the reads pushes over those bytes.
    The routine then jumps to garbage.
  - In the original only the NMI could do that.  The map's split fires
    the IRQ 4 times a frame, and the trace shows an IRQ at `$C4FF`, between
    the two pops.
- **Fix.**  The same 13 bytes, with the reads first: `tsx / lda $0101,x /
  sta $F3 / lda $0102,x / sta $F4 / pla / pla`.  A scan of banks 0-15 found
  no other code that reads stack bytes after popping them.
- **Result.**  The same loop ran 20,000 frames without a crash; the
  previous build crashes at frame 1849.

**Half-drawn windows** (the user: the border and text appear before the
attributes).
- **Cause.**  `scroll_map` queues a row pair, then `draw_map_object`
  queues the pair's attributes.  When the second row waited for glyph
  uploads, the NMI flushed the first row alone.  It showed for a frame or
  more with the map's palette (orange in the shop).
- **Fix (`dl_hold`).**  While a `text_draw_line` entry waits for uploads,
  what is queued before it is held back: a 0 at `vram_queue_read` stops
  the flush.  `txr_dlc` puts the byte back.  So the pair and its
  attributes are flushed in the same NMI.  There is no hold while a GC
  reads rows back, because the rows must be on screen then.
- **Result.**  When the command window opens, no row shows the wrong
  palette, and the window is complete 1 frame earlier (the uploader gets
  the whole vblank while the queue is held).

**Checks:**
- New-game path, frames 20-4200: pixel-identical to the previous build.
- Later frames differ only in how far a window has drawn.
- Shop, record office, give: right; `TXR_FULL` 0.
- Stack: lowest task push `$010D` on the shop path, the same as the build
  before the kanji UI.

### Sixth round (2026-11-12): the gold window over the buy list

The user's choice:
- either the item list drawn first with the gold window over it, and 金 /
  兵糧 one tile left;
- or the right border one tile right with the numbers one tile right, and
  the left border one tile right.

**Assessment.**  The first is the smaller change.
- It is one bank-14 routine and a 10-byte patch at `$8E24`.
- The second needs two new mechanisms:
  - a window on an odd column (template positions and attributes are on
    the 2-column grid);
  - clearing column 30 when windows close (the map redraw never writes
    it).

**Done.**  The first, with 金 / 兵糧 at column 19.
- Shop path: the list, then the gold window over its corner, then the
  wait on the list.  The cursor, buying, buying again and cancel are
  right.
- 5 digits leave one cell after 兵糧.
- The 糧 fix-up in column 23 is gone: the number's 6 cells (23-28) no
  longer reach the label.
- Stack: lowest task push `$010D`, as before.
- The original 256 KiB build is byte-identical.

## Boot menus in kanji (2026-11-12)

The user's request: the last UI left in kana before the officer names.
That is the game's boot menu, including the message-speed choice.

**How (first version, replaced the same day by the fixed set below).**
The boot menus are plain text windows on black, so the map renderer ran
there too.
- **Turning it on.**  At the boot screens that show menus, bank 13's
  `jsr loc_C139` after `ppu_init` becomes `jsr txr_menu` (RAM).
  - `TXF_MENU` fills the screen with the renderer's blank `$7F` again
    (clear_screen's `$0A` is the renderer's ▶), then runs the map setup.
  - The screens: the main menu (`$8AC8`), starting (`$8B49`), registering
    (`$8BCB`), deleting (`$8C29`) and copying (`$8C81`).
  - The next clear_screen gives the font back, as when leaving map mode.
  - The officer-status and name-entry screens of the register flow stay
    on the font (their `loc_C139` is unchanged).
- **The main menu's lines.**  Bank 13 `$9023` (`text_put_tile` for the
  strings at `$90E9`) goes through `txr_tp`.  The renderer substitutes
  them by string pointer (`ui_r1`, `kanji_common.BOOT_MENU`):
  - げーむをはじめる → ゲームを始める
  - れきししょをとうろくする → 歴史書を登録する (13 cells: the window's full width)
  - れきししょをけす → 歴史書を消す
  - れきししょのこぴー → 歴史書のコピー
- **Speed window `$29`.**  はやい / ふつう / おそい become 速い / 普通 /
  遅い.  The window grows from 6 to 7 columns for 普通.
- **Messages.**  The two copy prompts' こぴー became コピー (r14 dtx), as in
  the menu.

**Fixes found on the way:**
- **Raw upper-page tiles.**  The history book list writes its L
  (`$EB`, the bank-9 UI block in the upper page) as a raw cell, and the
  renderer read every code `$80-$F9` as a kanji half.  The kanji codes
  are `$80-$BF` (REG 0-31), so `xlate` now passes `$C0-$FF` through.
- **Label clash, again.**  The new RAM label `txr_boot` became `TXR_BOOT`
  in `canvas_ram.inc`, the same name as the renderer's flag.  The renderer
  wrote its flag into the stub's code, and the second boot screen
  crashed.  The label is now `txr_menu`.  `kanji_build` also fails the
  build if any `canvas_ram.inc` name shadows a `kanji.inc` symbol.
- **RAM.**  `txr_cur` no longer moves its return address around: the
  site is now `pla / jsr txr_cur`.  That freed 16 bytes for the stub.  The
  RAM image is 746 of 757 bytes.

**Checks:**
- Battery boot: main menu, start (book list, prompt, speed), then the town.
- Register, delete (with yes/no) and copy flows: right.
- New-game path, frames 1100-4200:
  - the same screens as the previous build, shifted by at most 2 frames;
  - the only new screens are the speed window's (kanji) and one black
    transition frame.
- The original 256 KiB build is byte-identical.

**Still kana:** the name-entry grid's commands もどる / すすめ / おわる
(register flow), and the grid itself (the kana keyboard).

### Boot screens: a fixed tileset (2026-11-12)

The user's direction: the title menu and the name entry have no
arbitrary text, so they use a fixed tileset, not the renderer.

**The fixed set.**  17 kanji (20 since 2026-11-14, the user's set: "The
boot screens' messages on the fixed set"), from `kanji_build.build_txr_ui`:
- the boot menu (`BOOT_MENU`): 始 歴 史 書 登 録 消;
- the name-entry title (`NAME_TITLE`): 名 前 入;
- the speed window `$29`: 速 普 通 遅;
- the name entry `$26`: 戻 進 終.

They take upper-page tiles `$80-$C3`, at t, t+1, t+2, t+3 = TL, BL, TR,
BR.  The boot screens' battle set there is never shown on them.  The UI
block's L at `$EB` is kept.

**Turning it on.**  At the boot screens' `jsr loc_C139` after `ppu_init`
(rendering off), `txr_menu` calls `TXF_MENU`.
- The sites: the main menu, start, register, delete, copy, and the name
  entry (`$8BF3`).
- `TXF_MENU` writes the set into CHR (from the glyph banks) and sets
  `TXR_ON` = `$40`.
- It marks the battle pool checked and unusable (`KANJI_WIN_COL`), so
  the messages use the band page as before the pool existed.
- The font stays in page 1, and the renderer stays off.  clear_screen
  ends the mode (`txr_fill` clears `TXR_ON`).

**`TXR_ON` bits.**
- Bit 7: the map renderer.
- Bit 6: the UI words in kanji (map mode `$C0`, the boot screens `$40`).
- Every renderer test is on bit 7.  The `text_put_tile` gate (`txr_tp`)
  tests bit 6 (`bvs`).
- In `put_str` a kanji is the fixed set's four tiles when bit 7 is clear
  (`ui_fx`), and a REG code otherwise.

**Name entry.**
- もどる / すすめる / おわる become 戻る / 進める / 終わる.
- The title なまえを　いれてください becomes 名前を入れてください: a new
  `draw_string` block (`boot_title.inc`, rows 2-3 from column 9).  It sits
  in bank 13's filler at `$8D20`, which no code or CDL ever read.  The
  inline pointer at `$9126` points to it.

**Removed.**  The renderer on the boot screens (the `$7F` refill, the
map setup there).  The renderer's `$C0` passthrough stays.

**Checks:**
- Battery boot: the main menu, start (list, prompt, 速い 普通 遅い), the
  town.
- Register: the name entry with the kanji title and commands, name
  input.
- Delete and copy (messages on the band page, yes/no): right.
- New-game path: the story and town screens are the previous build's,
  shifted by at most 2 frames.  The new screens are the speed window's
  and one black transition frame.
- Map menus: still in kanji.
- The original 256 KiB build is byte-identical.

States saved by an earlier build hold `TXR_ON` = `$80`.  Their map UI
words stay in kana until the next map setup (a building entered or left,
a battle).

## Officer names in kanji (2026-11-12)

The user's request: every officer name in kanji, from `namekanjilist.csv`
(repo root, "Kana,Name").  They also warned that ソウジン is two officers
(宋仁 and 曹仁).

**One name per officer record.**  The game keys its names by officer
record (bank 12, pointers `$A800` / `$A900` + id, records `$00-$D8`).
`kanji_common.officer_names()` gives each record its kanji:
- a kana the list gives one form for: that form;
- a kana it gives two forms for: `NAME_PICK` by record id;
- names the list lacks: `NAME_EXTRA`.

Both tables follow the original game's own name glyphs (record bytes
`$10-$13`, banks 1 / 2), read glyph by glyph.  The build fails on two
names that give one original glyph two kanji, or one kanji two glyphs.
The twin glyphs `NAME_GLYPH_TWINS` (蒋/蔣, 苞) are allowed.

| Kana | Records | Kanji |
|---|---|---|
| ソウジン | `$0A` / `$72` | 宋仁 / 曹仁 |
| チョウホウ | `$0D` / `$AD` | 張宝 / 張苞 |
| チョウリョウ | `$0E` / `$83` | 張梁 / 張遼 |
| エンショウ | `$26` / `$27` | 袁紹 / 袁尚 |
| チョウコウ | `$2F` / `$68` | 張郃 / 張紘 |
| ソウコウ | `$73` / `$74` | 曹洪 / 曹昂 |
| ソンカン | `$59` / `$9E` | 孫桓 / 孫乾 (the list has 孫桓 only) |
| チョウショウ | `$51` / `$67` | 張松 / 張昭 (the list has 張昭 only) |

From the original glyphs (not in the list): 海賊 山賊 盗賊 兵士 残党 郭汜
陳琳 孫策 曹操 関索 伊籍 劉禅 荀攸.  Record `$B3` (１０マメ) is not an officer;
it stays kana.

Where the list differs from the original glyphs, the list wins: コウメイ
孔明 (the original 諸葛亮), 麋竺 (糜竺), 潘璋 (藩璋), 厳畯 (厳峻).

The dialogue's 宋仁 / 宋勇 pick (`KANJI_CALLS`) tests officer id `$0A`,
which is 宋仁 in the original glyphs too: it needed no change.

**Glyphs.**  The name kanji join the font's inventory after the UI kanji
(982 glyphs, banks 23-25).  The primary font lacks 璝 (it draws a
placeholder), and its fallbacks draw 傕 彧 昱 汜 玠 褚 詡 邕 郃 鄧 闞 顗 騭 龐
poorly.  These 15 use the original game's own glyph
(`NAME_GLYPH_ORIGINAL`).  That includes the dialogue's 鄧.

**Map mode** (menus and messages): `put_officer_name`'s
`jsr text_put_tile` (`$D4C0`) goes through `txr_tp`, like the item names.
- `txr_put` sees bank 12 and Y = `$14` (the record's kana), and looks the
  record pointer up in `ui_rn`.
- It puts the name's string and skips the rest of the kana.
- The strings use `$ED n` = name glyph n (`nm_gc`).  The UI glyphs and the
  name glyphs together are more than 256.
- Map mode only (`TXR_ON` bit 7).

**Battle messages** (the pool):
- The overlay's dispatcher sends `$F4-$F7` to `KNAME`.
- In a pool message outside map mode, it gets the name's codes from the
  renderer bank (`TXF_NAME`, by record id, `ui_ri`).
- The compiler reserves 3 pool entries per runtime name on a page.  They
  are stored in bits 5-6 of the page record's entry count, and
  `pool_need` adds them wherever the pool's slots are counted.
- A name's kanji take the next reserved entries not yet taken
  (`KANJI_UPLOADED`).  Each is uploaded and placed as `KANJI_EC` places a
  page kanji.
- If the reserved entries cannot hold a name, it is put in kana
  (`put_officer_name` after its lookup, `$D4A5`).
- The troop line's name helper (`<CALL:D549>`, compiled as `$D49A`) is
  now `$F4`: the same routine (`put_officer_name_target`), but through the
  overlay.
- The loop keeps its state in `TXR_NM` (`TXR_NJ`, `TXR_NE`), not in
  `KANJI_M0-M2`: the block writer uses those while `post_wait` yields.
- The overlay is 2026 of 2048 bytes.

**The original name engine** (`put_officer_name` with `$AA` set: battle
screen, info screen, army screen):
- `build_name_font` writes the name kanji to bank 17 (`NAME_FONT_BANK`),
  in the original format: 32 bytes each, TL, BL, TR, BR.
- It rewrites every named record's `$11-$13` to that font, and clears
  `$10` bits 7-5 (the glyph banks).  Bits 3-0 of `$10` are the portrait
  colour and are kept.
- `bank12_names.bin` replaces bank 12 `$A900-$BFFF` in the kanji target.
  `build.py` now allows bank 12 to differ.
- The fixed bank's `lda #1` at `$D4D0` becomes `lda #NAME_FONT_BANK`.
- The UI bank's army screen (`ar_name`) reads that bank too.
- Bank 17 held only a stale glyph table from an old layout.
- The info screen's kana reading above the name stays.

**Checks:**
- Officer list (ぶしょう), shop buyer list, the 渡す message: 劉備は短剣を関羽に渡した.
- Officer list with six 3-kanji names (17 distinct kanji, more than the UI's
  16 REG entries): right.
- Battle: names on the screen, 兵士が現れた, 張飛の攻撃, 兵士を１０人倒した,
  兵士の攻撃 / 劉備の兵が５人倒された (two names on one page).
- Info screen from the map and from battle and back: names right, with
  their portrait colours.
- Army screen: names, 大将, 軍師.
- Lowest stack on the battle path `$0112`, the same as the previous build.
- The original build is byte-identical.

Not checked on screen: the victory / capture messages, the boss battle,
`$F6` / `$F7` in battle messages.

## MS Gothic bitmaps (2026-11-12)

The user's direction: JF-Dot-Shinonome16 lacks too many kanji.  Every
glyph now comes from MS Gothic (`C:/Windows/Fonts/msgothic.ttc`), using
its embedded bitmaps only, never rendered from the outlines.  The game's
own kanji move to it too.

- **Source:** `kanji_common.glyph_bytes` reads the EBDT strike at 16 ppem.
  Its kanji are 16 x 16 cells, ascender 14, bit-aligned format 5.
- **Where it applies:** everything that takes its glyphs from
  `glyph_bytes`:
  - the message / renderer font in banks 23-25;
  - the UI bank's copy;
  - the boot screens' fixed set;
  - the name font in bank 17.
- **Not changed:** the kanji codes, so no text or table moves.
- **Kanji with no 16 ppem bitmap:** 15 of the 982, all JIS X 0212 / 0213.
  - Composed from parts of MS Gothic bitmaps (`GLYPH_COMPOSE`: donor
    columns and rows placed in the cell):
    - 鄱 = 翻 + 部
    - 邢 = 刑 + 部
    - 涪 = 河 + 倍
    - 瓚 = 理 + 讃
    - 詡 = 語 + 翔
    - 傕 = 何 + 確
    - 郃 = 鴿 + 部
    - 璝 = 理 + 潰
    - 褚 = 補 + 緒
    - 玠 = 理 + 价
    - 雒 = 路 (各, 2 columns dropped) + 雄
    - 龐 = 店's 广 + 寵's 龍 (2 columns dropped)
  - The original game's name glyph (`NAME_GLYPH_ORIGINAL`): 闞 騭 邕.  Their
    composites (門 around a squeezed 敢, 陟 squeezed over 馬, 巛 over a
    squeezed 邑) were not legible.
- **The game's own kanji:**
  - Names: the name font (bank 17) is MS Gothic.
  - The army screen's 大将 / 軍師: the original read the first six
    glyphs of bank 1 (大 将 劉 備 軍 師).  The UI bank now reads the same
    six from the name font at `NAME_FONT_LABELS` (`$9F40`).
  - Nothing else reads the original name font in the kanji target.
  - The map's shop signs (武 etc.) are map tiles drawn as pictures, not
    font glyphs; they are unchanged.
- **The contact sheet** (`assets/fonts/kanji_16x16_ext.png`) leaves out
  the 3 original glyphs (red boxes); the ROM's data stays out of git.

**Checks:**
- The officer list, the 渡す message.
- The info screen and the army screen (大将, 軍師, names).
- Battle names and messages.
- The original build is byte-identical.

## Izumi16 bitmaps (2026-11-12, replaces "MS Gothic bitmaps")

The user checked the 15 kanji MS Gothic lacks against jiskan16 and Izumi16,
and chose Izumi16 for every glyph.

**Source:** `JF-Dot-Izumi16.ttf` (repo root), its embedded bitmap strike at
16 ppem; never the outlines.
- Licence: its authors declare the 出水 bitmap font series equivalent to
  public domain.  The published patch carries no MS Gothic data.
- **Placement:** Izumi16 draws kanji in a 15 x 15 box at columns 1-15,
  rows 0-14.  `font_rows` anchors that box bottom right: the same
  columns, one row down (the user, 2026-11-12; first they were moved one
  column left, then kept as drawn).  So a kanji has a free column on its
  left and a free row above.  The build fails if one would leave the
  cell.

**Coverage:** 981 of the 982 kanji.  璝 is not in the font.  It is composed
from Izumi16's 理 (王: columns 1-5, rows 1-14) and 潰 (貴: two columns
narrower, from column 7) (`GLYPH_COMPOSE`).  A free column stays between
them; column 0 and row 0 stay blank.  The first version (貴 from column 4) merged 王's
top stroke into 貴's (fixed after the user's check).

**Removed:** the MS Gothic composites and the original game's name glyphs
(闞 騭 邕 are Izumi16's now).  No glyph comes from the ROM any more.  The
contact sheet shows every glyph.

**Unchanged:** the kanji codes, the name font layout (bank 17, with the
army screen's 大将 / 軍師 at `NAME_FONT_LABELS`).

**Checks:**
- The officer list, the 渡す message.
- The info screen and the army screen.
- Battle names and messages.
- A party list of 歩騭 龐統 闞沢 諸葛謹 蔡邕 劉璝.
- The original build is byte-identical.

## Upload speed (2026-11-12): assessment

The user's question: build the upload list outside vblank and use the
tightest possible code in vblank.  How many cycles does that save, and
does it remove a lag frame per screen update?

The list is already built outside vblank.  The main thread stages each
tile as an 11-byte record (R0 value, PPU address, 8 bytes) in `TXR_UQ`.
The NMI only copies the records.

Probe: `tools/lua/txr_upload.lua`, classified with `tools/txr_frames.py`.
Runs: `out/test/opt/` (`cw1`, `cw3`), state `out/user/txr/u3b` with the
RAM image installed.

### Upload frame, measured

Scanline.fraction, with an empty game queue:

| Step | Line |
|---|---|
| NMI | 241.0 |
| OAM DMA and the game's flush end | 246.2 |
| mask restored | 246.9 |
| `ef08_gate` (after the task timers) | 248.2 |
| `nmi_up` | 249.4 |
| first pattern byte | 250.1 |
| last pattern byte, 4 tiles / 5 tiles | 253.6 / 254.6 |
| split armed, 4 tiles / 5 tiles | 254.4 / 255.4 |

- **Copy loop:** 114 cycles per tile.
- **Renderer overhead before the first byte:** 1.9 lines (216 cycles).
- **Deadline:** the force has to end by pre-render dot ~262
  (`CV_FORCE_MAX`), so uploads could run until about line 260.5.  About
  6 lines (~680 cycles) of every upload frame go unused.

### Where the frames go

The vblank budget does not set the pace.  Two other things do:

1. **The batch cap.**  `TXR_UQMAX` = 5 tiles, one batch per NMI.  A
   kanji is 4 tiles, so usually one kanji per frame.
2. **Cells after their glyphs.**  An entry goes into the queue only after
   the NMI that uploaded its glyphs, and it is flushed in the NMI after
   that.  So every update that needs a new glyph costs one extra frame:
   - a kana with a new glyph: 2 frames (the original pace is 1);
   - a kanji with a new glyph: 3 frames (the original pace is 2, one per
     column).

Frame classes (U = upload only, F = cells flushed, B = both, P = publish
only, . = nothing):

| Update | Frames | Sequence |
|---|---|---|
| Shop arrival and greeting, typed (`cw1` 13-80) | 68: 28 U, 6 P, 32 F | `FFFFFUFUFUFUFUFUFFUFUFF.PUFPUFPUFPUFUFF.PUFPUFUFUFUFUFFUFUFUFUUUFUUU` |
| Command window, glyphs freed at the last close (`cw3` 64-77) | 14 from the first publish, 38 tiles | `PUUUUUUFUUUUBF` |

- The command window uploads its glyphs again at every open.
  `redraw_start` (the full redraw that closes the map's windows) frees
  every part's glyphs.  The second open in `cw2` uploaded 14 tiles over 4
  frames.

### Options

**D. A tighter copy loop alone.**
- Cost per tile:
  - now: 114 cycles;
  - records grouped by part, without the per-tile R0 write and counters:
    ~93;
  - a kanji's 4 tiles as one record (shared address high byte): ~82.
- Saving: 20-30 cycles per tile, about 150 cycles per 5-tile batch.
- **0 frames by itself:** a 5-tile batch already ends by line 255.4.
- Generated code (`lda #imm` / `sta PPUDATA`, ~60 cycles per tile) needs
  ~50 bytes of RAM per tile.  That is not available.

**B. Batches sized by vblank time, not 5 tiles.**
- Tiles per frame, from line 250.1 to 260.5:
  - about 10 with today's loop;
  - 12-14 with D.
- Estimated command window (cold): 14 frames down to ~7.
  - Its two glyph groups (20 and 16 tiles) take 2 frames each, instead
    of 6 and 4.
  - D does not change that count: 20 tiles still need 2 frames.
- RAM: the staging area grows from 55 bytes to 130-154.  The renderer's
  battery RAM (`$7BF5-$7F9B`) and the RAM image are full.  Possible
  sources:
  - a smaller kana map (`TXR_KM`: 512 bytes, 4 parts x 128 codes; about
    17 codes per part are never kana);
  - kana staged by code, with bank 26's font copy (`$A500`) moved below
    `$A000` so the NMI can read it.

**C. Glyphs and cells in the same NMI.**
- The main thread queues the entry together with its batch and holds it,
  as `dl_hold` does.
- The NMI uploads the batch.  When the batch is complete and the held
  bytes fit in the time left, it puts the held byte back and flushes the
  entry itself.  Otherwise it releases the entry in a later NMI, as today.
- Effect: one frame less for every update that needs glyphs.
  - Typed text runs at the original pace: estimated 28 of the 68 frames
    above.
  - One character's tiles (at most 4) end by line 253.6, so they always
    fit.
- RAM: a few bytes.

**E. Glyphs kept when windows close.**
- `redraw_start` would stop freeing; the read-back GC frees only when a
  part is full.
- Effect: a reopened window or a repeated word needs no uploads.  The
  command window would open at the original pace after its first open.
- Cost: the GC runs more often.  It reads one row per NMI, so a pause is
  6-9 frames when a part fills.  Reading 2-3 rows per NMI would shorten
  it.

The user's choice: all of them, in the order C, E, B + D.

### C done: glyphs and cells in one NMI

- **Main thread** (`txr.asm` `rc_step`):
  - A step with new glyphs queues its cells at once.
  - The cells' first byte is held back (a 0 there stops the game's flush;
    the byte is saved in `TXR_HB` with bit 7 set, the range in
    `TXR_HI`..`TXR_HE`).
  - Then the batch is published, and the step returns the pause as usual.
  - The hold comes before the batch, so an NMI between them has nothing
    to release.
- **Rendering off or busy:** the glyphs are written at once
  (`stage_direct`), and nothing is held.
- **NMI** (`nmi_up`), when the batch is complete:
  - it puts the byte back;
  - it flushes the cells itself (`rel_flush`) when two tiles' worth of
    budget is left and nothing queued before them is waiting;
  - otherwise the game's next flush draws them.
- **Waiting.**  `TXF_RCC` returns "wait" until the batch, its cells and
  any GC row read are done.  The RAM stub then just waits a frame and
  calls it again (the RAM image is 7 bytes smaller: 739).
- **Safety.**  `txr_reset` never leaves cells held.
- **Not changed: text_draw_line.**  Its hold also covers the attributes
  that `draw_map_object` queues after the line returns.  Releasing it in
  the NMI would draw rows before their attributes, so the main thread
  still releases it.

Checks (runs in `out/test/opt`; `c0` and `c1` are the shop greeting on the
previous and the new build, each with its own RAM image):

| Check | Result |
|---|---|
| Shop arrival and greeting, frames 1-100 | 20 U frames merged into B frames; the greeting and the list are complete 20 frames sooner |
| Settled screens (frames 120, 199) | identical except the cursor's blink phase (the cursor blinks normally) |
| New-game path from power-on, frames 1-4300 (`std0`, `std1`) | U frames 248 -> 115, B 18 -> 147; the GC runs at the same points (parts 3 and 2); `TXR_FULL` 0; the speech pages (幾 武器 用意 ...) identical |
| A kanji's frame (4 tiles + 4 cells) | uploads end at line 253.6, cells 256.2, split armed 256.9 |
| Lowest stack push (shop path) | `$010C` (previous build `$010A`), the same fixed-bank routine |
| Original build | byte-identical |

### E done: glyphs kept when windows close

- **At a close** (`redraw_start`, `TXF_RESET` -> `txr_close`):
  - no part shows text any more;
  - a part keeps its glyphs (kana map, kanji groups, tiles), so a window
    opened again finds them and uploads nothing;
  - a part with fewer than `KEEP_MIN` = 48 free tiles (12 kanji) is freed
    there instead.  That costs nothing at that moment and spares a
    read-back GC (a frame per row, 7-10 frames) in the next window.
- **Unchanged:**
  - the map setup still frees every part (page 1 held the font or another
    screen's tiles);
  - the GC still frees what no row shows when a part fills within a
    window.
- `txr_reset` is now a loop over `part_reset`; `part_free` counts a
  part's free tiles.

Checks (`out/test/opt`):

| Check | Result |
|---|---|
| Command window opened, closed, opened (`e_k1` C only, `e_k2` C + E) | the second open uploads nothing and draws in consecutive frames (`F..FFFF`); before, `PUBUUUUUFUUUU` |
| Menu cycle x4 from `u3b`: talk (shop list), officers, items, formation (4,233 frames) | tiles uploaded: 1,437 (C only), 204 (E without the close-time free), 512 (E); U + P frames 441 / 59 / 165.  Every window the same picture as with C only (cursor blink and NPC sprites aside) |
| Part 1 made full (every group taken, nothing shown; pokes) before the close | freed at the close: the next command window opens with no GC (12 frames; with the GC ~22) |
| The same, made full after the close | GC part 0 (~10 frames), then the window right; the same pictures as without the close-time free |
| New-game path from power-on (`std3`) | identical to C only at every 20th frame from 2000 to 4300; the GC at the same points; `TXR_FULL` 0 |
| Lowest stack push (menu cycle) | `$010C`, the same fixed-bank routine as before |
| Original build | byte-identical |

### B + D done: bigger batches, glyphs read in the NMI

**Staging (main thread).**
- The 55 bytes of `TXR_UQ` hold references, not glyph bytes:
  - a kana is `R0, tile, code` (3 bytes);
  - a kanji is `R0 | $80, tile t, glyph code lo, hi` (4 bytes).
- So one batch holds up to 13 kanji (it held 1 before).
- The main thread no longer copies glyphs into the buffer.
- `TXR_SN` / `TXR_UQN` now count bytes.
- **Rendering off or busy** (`is_direct`): `stage_kana` / `stage_kanji`
  write the glyph at once, with the same routines as the map setup and
  the boot menus.  Normal play never takes this path; a test forced it
  (below).

**NMI** (`nmi_up`).  As many records as a budget allows (`UP_*`, units of
16 cycles, in `kanji.inc`): `UP_UNITS` = 67, one unit less per byte the
game flushed.

| Item | Charge | Measured |
|---|---|---|
| kana (`up_kana`) | 11 | ~161 cycles |
| kanji (`mk_run`) | 31 | ~400-500 cycles (page crossings, a bank switch) |
| a run of kanji: the call and exit | 3 | |
| released cells (C) | 14 | |

- **Kana** (`txr.asm` `up_kana`): read from bank 26's font copy, which
  moved to `$8400`, in the half the NMI maps.  Unrolled per 256-byte page
  of the font.
- **Kanji** (`hack.asm` `mk_run`, `$B900` in every hack bank = `HACK_MKUP`):
  - read straight from the glyph tables, all 4 tiles unrolled;
  - two variants: the low half and the +256 half;
  - it runs from `$A000-$BFFF` and maps R6 and R7 to each glyph's bank;
    R7 changes under its own feet, which works because the code is
    identical in banks 23-25;
  - it maps R6 back to the renderer bank before returning;
  - the game's NMI end restores both halves.
- The second hack segment now ends at `$BEFB` (palette tables at
  `$BF00`).

**Per frame**, uploads start about line 250.8 (kana) or 251.4 (kanji):

| Frame | Last upload write | Force | Arm |
|---|---|---|---|
| 2 kanji | 258.6 | | 259.8 |
| 6 kana (injected batch) | 259.5 | 260.4 | 260.8 |
| 1 kanji + 3 kana (injected batch) | 259.4 | 260.4 | 260.7 |

The IRQ reload is still about 0.8 lines before the pre-render line's
clock.  The game's own long-flush frames end the force near line 261.8.

**Results** (`out/test/opt`, each build with its own RAM image):

| Update | Before (9fd2e34) | C | C + E | C + E + B + D |
|---|---|---|---|---|
| Shop greeting and item list, from `u3b` (last upload frame) | 100 | 79 | 79 | 74 |
| Command window, first open (frames from the first publish to complete) | 14 | 14 | 11 | 8 |
| Command window, opened again | (not run; as C) | 13 | 0 uploads (the game's row pace) | 0 uploads |
| Menu cycle x4, 4,233 frames: U + P frames | | 441 | 165 | 117 |
| New-game path, frames 1-4300: U frames | 248 | 115 | 115 | 113 |

**Checks:**
- Same pictures as C + E: shop, command window, menu cycle, GC test,
  new-game path every 20th frame from 2000 to 4300.  The only
  differences are the cursor blink and NPC sprites.
- A battle from `r17_pre_battle_normal`: identical every 30th frame
  (frames 30-1470).  The hack banks' second segment moved.
- **Forced screen-off test.**  The mask shadow `$FE` was set to 0 before
  opening the command window and restored after.  The glyphs were
  written directly (8 times), and the windows are the same picture as a
  normal run.
- GC with a part made full: right.  `TXR_FULL` 0 everywhere.
- Lowest stack push `$010C`.
- Original build byte-identical.

**Limits:**
- About 2 kanji (8 tiles), or 6 kana, or 1 kanji + 3 kana per frame.
  The fixed cost before the first upload (OAM DMA, the game's flush and
  task timers, the split's setup) leaves about 9 lines.
- A cold window with many new kanji still takes a frame per 2 kanji.

### Round 2 (2026-11-12): assessment of the user's "unpack every glyph" idea

**The proposal:**
- unpack the glyphs stored compressed in the original data;
- add a plane-1 copy of the kanji to save bit shifting;
- keep an uncompressed copy of the kana;
- the user also noted that officer names are probably not needed, since
  we use our own glyphs now.

**Findings.**  No glyph is compressed, and no path shifts glyph bits.
- Kanji: the glyph tables in banks 23-25, raw rows, planar by byte index.
- Kana: the bank-9 font at `$BA00`, raw 8 bytes per tile.  Bank 26
  carries an identical copy at `$8400`.
- Names: bank 17's name font, raw 32 bytes per glyph.
- UI screens: bank 28's UI kanji, raw 32 bytes per glyph.
- Every byte goes from ROM to `PPUDATA` with one load and one store.
- Plane 1 is the same bytes at the tile address + 8.  The shifts in the
  code turn tile numbers into PPU addresses.
- So a plane-1 set or a 2bpp copy would hold the same bytes and save
  nothing.
- Officer names: no original name glyph is used since `320050a` (all
  Izumi16).  Bank 17 is our glyphs, laid out for the original name
  routine that the battle, info and army screens still use.

**Where the cycles go** (map mode, upload frames):

| Part | Lines / cycles |
|---|---|
| the game's NMI work (OAM DMA, its flush, palette, task timers), 241.0 -> 248.2 | 7.2 lines, fixed |
| our path to the first upload write, 248.3 -> 250.8 (kana) / 251.4 (kanji) | 2.5-3.1 lines |
| a kana | ~161 cycles: 64 copying, ~45 address and font-page arithmetic, the rest budget and record bookkeeping |
| a kanji | ~400-500 cycles: 256 copying, ~40 address and bank arithmetic |

**Options** (estimates):
1. **Precomputed records.**  The main thread stores the PPU address and
   the font offset or glyph bank: kana 5 bytes, kanji 5 bytes.  Kana
   ~120 cycles, kanji ~390.
2. **A leaner NMI path** before the first write: ~300 cycles -> ~120.
- 1 + 2 together: uploads start about line 249.7.  Per frame:
  - kanji: 3 instead of 2 (just fits by the line-260 rule);
  - kana: about 9 instead of 6.

### Round 2 done: precomputed records

**The user's choice:** options 1 + 2 of the round-2 assessment.

**Records** are 5 bytes, built by the main thread (`rec_head`):
- kana: `R0, PPU hi, lo, the glyph's offset in its 256-byte font page,
  the page`;
- kanji: `R0 | $80, PPU hi, lo of tile t, the glyph's column, its bank's
  R6 value | $80 for the +256 half`.
- So the NMI does no tile-to-address, code-to-offset or bank arithmetic.

**Caches in the NMI:**
- R0 is written only when a record's page differs (`KANJI_T1`).
- The glyph bank only when it changes (`KANJI_T0`).

**Measured** (injected batches, `out/test/opt/inj9_*`):

| | Before | Now |
|---|---|---|
| kana | ~188 cycles | ~157 cycles |
| kanji with a bank switch | ~500 cycles | ~420 cycles |
| 6 kana: last write | line 259.5 | line 258.0 |
| 2 kanji: last write | line 258.6 | line 257.6 |

- Charges: `UP_KANA` 10, `UP_KANJI` 27 (`UP_UNITS` 67, `UP_KRUN` 3).
- A frame now holds 2 kanji + 1 kana (before: 2 kanji), 6 kana, or
  1 kanji + 3 kana.
- The hack bank's second segment ends at `$BEEA`.

**Unchanged:** the frame counts of the tested screens (shop, command
window, menu cycle, new-game path).  They are kanji-bound, and a third
kanji does not fit:
- 3 kanji need ~1,100-1,160 cycles from the first write (line 251.1);
- about 1,000 cycles are left before line 260.
- The fixed path before the first write is the game's NMI work (to line
  248.2) plus ~2.8 lines of ours.  Trimming ours further gains well under
  a line.

**Checks:**
- Pictures identical to the previous build: shop, command window,
  menu cycle, GC, forced screen-off (8 direct writes), the new-game path
  (every 20th frame) and a battle (every frame 200-859).
- Latest upload write on the new-game path: line 257.95 (before 258.52).
- Lowest stack push `$010A` (the same fixed-bank routine).
- Original build byte-identical.

### Round 3 (2026-11-12): assessment, a third kanji per frame

**The question (the user's):** can the original game's NMI give up about
100 more cycles, so that a third kanji fits in a frame?  MMC3 8 KiB
banking may be used freely in our own code.

**What a third kanji needs.**  Measured with an instruction trace of
2-kanji frames (no game flush; `out/test/opt/ntrace.lua`, `ntr.txt`):
- The second kanji's last write is at cycle ~1,890 after the NMI (line
  257.7).
- A third would end at ~2,330 (line 261.6).
- `v = $1000` (the force) comes ~124 cycles after the last upload write
  and must land before line 261.0 (cycle ~2,263).
- So a third kanji is ~190 cycles short at zero margin.
- Today's worst case (1 kana + 2 kanji, the second started with exactly
  `UP_KANJI` left) keeps ~60 cycles before line 261.  Keeping that
  margin means saving ~250 cycles.  100 is not enough.

**The game's NMI, NMI -> `$EF08`** (808 cycles, measured):

| Part | Cycles | Needed before our uploads? |
|---|---|---|
| entry, pushes, PPUCTRL, PPUMASK off, OAMADDR | 48 | yes |
| OAM DMA | 517 | in vblank, but its place in it doesn't matter |
| the game's queue flush (empty) | 32, +~15 a byte | yes |
| palette check, `flush_palette` | 24 | yes (PPU work) |
| scroll, PPUMASK on, `ppu_nmi_on` (`$EECE-$EEDF`) | 45 | no, in map mode: the force rewrites PPUCTRL and the scroll; PPUMASK only needs to be on before line 261 |
| frame counter, the task timers, the `nmi_mode` branch (`$EEE0-$EF07`) | 142 | no: no PPU access |

- **Deferrable: 187 cycles.**  A gate at `$EECE` would skip to `$EF08`
  in map mode (not busy, `nmi_mode` 0, `TXR_ON`).  The map path then
  does the skipped work after the uploads.  The gate costs ~15 cycles
  and needs ~20 bytes of fixed bank (`$C489-$C49D` has 21 free).
- **Net: ~170 cycles.**
- When the force is skipped (`CV_FORCE_MAX`: a long flush), the map
  path must write the scroll, PPUCTRL and PPUMASK itself, at once.
- Busy NMIs already jump to `$EEE0`; they keep the timers in place.

**Our path, `$EF08` -> first glyph byte** (326 cycles, measured):

| Part | Cycles | Lean |
|---|---|---|
| fixed-bank gate, RAM stub, R6, `nmi_cv`, `nmi_live` | 62 | ~30: the gate maps bank 26 and jumps in |
| `cvn_map` up to `nmi_up` | 78 | ~40: R0, `KANJI_LAST39` and `KANJI_QPOS` written after the uploads |
| `nmi_up` setup and budget, up to `mk_run` | 89 | ~40: one budget decision from the main thread's per-record costs |
| `mk_run` budget, glyph bank, R0, address | 97 | ~85 |

- **Saves ~135 before the first write, and ~12 per later kanji: ~160
  for 3 kanji.**
- **The tail:** the last write -> force is 110 cycles of bookkeeping (the
  R0 restore, the held cells, the queue index).  Doing the force and
  arm first moves the upload deadline ~80 cycles later.

**8 KiB banking: a page-aligned glyph copy for the NMI.**
- 256 glyphs per 8 KiB bank, row r of glyph c at `$A000 + r * 256 + c`,
  mapped with R7 only.  The uploader stays in bank 26's NMI half: no
  copy of `mk_run` in each glyph bank, no call, no R6 switch.
- **Per kanji:**
  - the R7-only switch: 12;
  - no +256 branch: 7;
  - no page crossings: 6-16 measured, 32 at worst;
  - the call: ~18.
  - **That is ~40-50 a kanji, ~130 for 3**, and a constant kanji time,
    so the charge can be exact.
- **Cost:** 32 KiB in four 8 KiB banks (982 glyphs).
  - Banks 17b and 27a are empty.
  - Two more need small moves: the 751-byte RAM image in 27b and 563
    bytes in 29a.
  - The glyph tables in banks 23-25 stay for the main thread and the
    other screens.

**Totals:**

| Levers | Saved | A third kanji |
|---|---|---|
| the game's NMI only | ~170 | no (needs ~190) |
| + our path | ~330 | yes, ~130 to spare (today: ~60) |
| + the tail | (+80 deadline) | ~210 to spare |
| + the 8 KiB glyph copy | ~460 | ~340 to spare: 3 kanji + 1 kana |

- A fourth kanji needs ~370 more: not reachable with these.

**A bigger, separate lever: skipping the OAM DMA (517 cycles).**
- The game rewrites the sprite buffer every 1-3 frames (`$C459`,
  `$C950-$C95F`; 87-111 bytes).
- Measured while a window drew: 0 bytes changed in nearly every frame
  (frames 1-120 of the greeting).
- With a dirty flag (the writers patched to compare before they store),
  the NMI could skip the DMA when nothing changed.  OAMADDR would then
  not be written either.  On hardware, OAM keeps its contents while
  rendering is on every frame.
- That would give room for about a fourth kanji in those frames.
- More invasive: it patches two game routines and changes when sprites
  are sent.


### Round 3 done: the uploads before the game's deferrable NMI work

**The user's choice:** the recommended levers (the game's NMI, our path,
the tail).  Measured worst cases showed they were not enough for a
guaranteed third kanji (below), so the 8 KiB glyph copy went in too.

**The game's NMI** (`mmc3_b15.asm` `nmi_gate`, patched over `$EED0`
"sta PPUSCROLL").
- Map mode (`TXR_ON` bit 7), not busy: R6 = bank 26, `jmp $8009`
  (`txr.asm` `nmi_map`).
- `nmi_map`:
  1. the uploads (`nmi_up`) or the GC's row read;
  2. the force (`v = $1000`) with the original's PPUCTRL (`ppu_nmi_on`),
     scroll and PPUMASK;
  3. R0 = page 1 and the arm;
  4. the bookkeeping (`KANJI_LAST39`, `KANJI_QPOS`);
  5. the frame counter and the task timers (the original's
     `$EEE0-$EEFE`, copied);
  6. `$EF08`'s push and `ef08_tail`.
- **Other paths:**
  - a long flush (`CV_FORCE_MAX`) or rendering off: the original's
    writes at once, no force;
  - `cv_stream` already ran: its force stands, the original's writes
    follow;
  - `nmi_mode` not 0 (not seen in map mode): R6 back through `NMI_PRG`,
    then the original path at `$EED3`.
- **Elsewhere:** the original.  Busy NMIs still reach `ef08_gate`.
- `ef08_gate` shrank to make room: its band checks moved into bank 26
  (`nmi_cvg`, carry = work for the hack NMI).

**The glyph copy** (`kanji_build.py` `build_glyph_copy`; `kanji.inc`
`GCOPY_*`).
- Glyph i (inventory order) is column `i & $FF` of copy bank `i >> 8`.
- Byte b of a glyph is at `$A000 + 256 b + column`, so no read crosses a
  page.
- Copy banks are 8 KiB, mapped with R7 alone:
  - 32 and 33 (bank 16, unused before; the build dir held a stale file);
  - 35 (bank 17's upper half);
  - 54 (bank 27's lower half).
- `stage_kanji` turns the glyph code into the copy's column and R7 value.
- `up_kanji` (bank 26, the NMI half) replaces the hack banks' `mk_run`,
  which is gone.

**Charges:** `UP_UNITS` 85, `UP_KANA` 11, `UP_KANJI` 27, each a record's
worst case.
- A kana with an R0 switch: ~171 cycles.
- A kanji with a copy-bank and an R0 switch: 426 cycles (before: up to
  481 with page crossings).
- Without the copy, the worst kanji left three over the deadline: the
  force at line 261.6.

**Measured** (instruction traces; the user's states converted, below):

| | Before | Now |
|---|---|---|
| nmi_up entry (no game flush) | line 249.4 | line 247.3 |
| first kanji byte | line 251.1 | line 249.0 |
| 2 kanji: last byte | line 257.7 | line 255.6 |
| last byte -> force | 110 cycles | 81 cycles |
| per frame | 2 kanji + 1 kana | 3 kanji (game flush up to 4 bytes), or 7 kana |

- **Worst cases** (game flush 4 bytes, injected):
  - 3 kanji, each with a copy-bank and an R0 switch: `v = $1000` at line
    259.88 (126 cycles before line 261), IRQ reload at line 260.5;
  - 7 kana alternating R0: `v = $1000` at line 259.13.
- **Pictures identical to the previous build:**
  - the greeting and shop;
  - the menu cycle (16 shots);
  - the new-game path (211 shots);
  - a battle (every frame 197-856);
  - window reopen, the GC run, a forced screen-off (direct writes).
- **Frame counts:** the tested screens are mostly paced by the main
  thread.
  - Greeting: last upload frame 71 -> 70, one 3-kanji frame.
  - Menu cycle: 122 -> 116 upload frames.
  - New-game path: the same frames; the latest upload write at line
    256.75 (before 257.95).
- **Also unchanged:**
  - `TXR_FULL` 0;
  - one GC in the GC run;
  - lowest stack push `$010C` (menu cycle; before `$010A`), `$0118`
    (new-game path; before `$0117`);
  - the original build byte-identical.

**Old save states:**
- A state saved while an IRQ had interrupted the NMI's tail returns into
  bank 26's old layout and crashes (the user's `u3b.mss` did).
- The tests ran from copies converted on the previous build:
  `out/test/opt/convstate.lua` saves at an NMI entry with the main
  thread in the fixed bank.
- States the user saves on this build are fine.

### Round 4 (2026-11-12): assessment, skipping the OAM DMA in upload frames

**The proposal (the user's):** a frame that lags because of tile uploads
needs no OAM DMA (517 cycles).  The NMI can predict such a frame from the
tiles waiting to go up.

**Findings** (`out/test/opt/oamup.lua` on the round-3 build: the greeting,
the menu cycle, the new-game path; 34 + 116 + 137 upload frames).
- **The main thread does not stop while it waits.**
  - `wait_vblank` gives the text task a one-frame timer and returns to
    `main_loop`, whose scheduler runs the other ready tasks.
  - So the sprite buffer is still rebuilt every 1-3 frames
    (`update_oam`, `clear_oam_shadow`).
- **It changed in 3, 89 and 146 frames of the three runs, never in an
  upload frame.**  Sprites happen to stay still while windows draw, but
  nothing guarantees it (NPCs, the map task).
- **No upload frame was budget-limited after round 3.**
  - At most 3 records (15 bytes) were waiting at any NMI.
  - None was left over after the uploads.
  - The main thread publishes a row's or a cell's new glyphs and waits.
    In these screens a batch never held more than one NMI uploads.
- **So the 517 cycles would save no frame on the tested screens.**  They
  would only help a batch of 4 or more kanji: a row drawn whole with 4+
  glyphs not yet in CHR.

**If wanted later** (a screen with such rows):
- **Decide at the NMI's start**, before `$EE93`:
  - the staged batch's total charge (a running sum kept by the staging
    code, 1 byte) against `UP_UNITS` less the game's queue length;
  - and the sprite buffer unchanged since the last DMA.
- **Unchanged:** a dirty flag set by the game's sprite routines (patched
  to compare before they store).  Without it, a skipped frame shows the
  sprites one frame late.
- **Skip OAMADDR too:** on the 2C02, writing OAMADDR can corrupt OAM, and
  the DMA normally repairs it.  OAM keeps its contents while rendering is
  on every frame.
- **Space:** the fixed bank has none left.  The `$EE8B-$EE97` rewrite
  needs a few bytes more than it frees, so a fixed-bank routine would
  have to move out.
- **Gain:** one more kanji (4 a frame) or ~3 more kana, in those frames
  only.

### Fixes after round 3 (2026-11-12, the user's states 1 and 2)

**Tactic names in battle messages were kana** (state 2: 総攻撃, the
level-up's 「麋竺 はじょうないの計を覚えた」; also 「れんかの計を使った」 when a
tactic is used).
- `<CALL:D565>` puts the tactic's kana from bank 12 and the kana tail
  のけい; the compiler's `$EE $FC 2 計` turned the tail into 計.  Only map
  mode substitutes the name (`txr_tp`).
- **Now:**
  - the compiler emits `$EE $FB lenA`, variant A (の計), `$EE $FE lenB`,
    variant B (the old bytes), and counts the tactic as a runtime name of
    the page (3 reserved pool entries);
  - in a pool message outside map mode the overlay's `kanji_ctl` puts the
    name's kanji as `KNAME` puts an officer's (`kn_put`, shared), then
    variant A;
  - in map mode, on the band page, or when the reserved entries cannot
    hold it: variant B.
- `TXF_NAME` (`txr_name`) now takes the name's code: 16-22 for
  `$F4-$F7` (the officer selection moved there from the overlay, which
  needed the bytes) and 24 for the tactic (`text_command`; tables `tn_*`
  from the word list's 「XXの計」, 31 of 32 tactics, all 2 kanji).
- The overlay is 2044 of 2048 bytes.
- **Result:** 「麋竺 は城内の計を覚えた」, 「練火の計を使った」; the kanji type
  half by half like officer names.

**CHR splits 1-2 lines early with A held** (state 1, the save man).
- Holding A speeds the text up.  When the dialogue scrolls, the game
  flushes 104 bytes in one NMI: one more than `CV_FORCE_MAX` (103).
- So `nmi_map` skipped the force (`v = $1000`) and armed the IRQ at once,
  at line 260.7.  With v still at a nametable address, A12 rises at the
  pre-render line's first background fetch: an extra MMC3 clock.  Stage
  0 ran at line 261 instead of line 0, and the splits came at 69 / 117 /
  165 (or 70 / 118 / 166) instead of 71 / 119 / 167.
- **The build before round 3 misplaced these frames too:** its later arm
  came after the pre-render line's real clock, so the splits fell one line
  late (72 / 120 / 168).
- **Fix:** `nmi_map` has its own limit, `CV_MAP_FORCE_MAX` (its timing
  is ~2 lines earlier).  It is 104 since the title fix below.
  - The 104-byte scroll is now forced.
  - The IRQ reload lands before the pre-render line's real clock
    (261.95).
- **Checked:** every frame of state 1 with A held (30 frames, 120 frames,
  three short holds): splits at 71 / 119 / 167.  The largest map-mode
  flush in the test runs is otherwise 93 bytes.
- **Above the limit** (not seen in map mode): no force, as before.  The
  arm can then still precede the pre-render line.
- **Regression:** the pictures are identical to the previous build for
  the greeting, the menu cycle, a battle (frames 197-856) and the new-game
  path.

**Title screen glitch** (the user's report, after round 3).
- The title (`nmi_mode` `$80`, `TXR_ON` 0) and bank 7's effect
  (`nmi_mode` 1) split the screen in the NMI with delay loops counted
  from the NMI's start (`$EF38`, `$EF94`).
- Round 3's `nmi_gate` added 13 cycles before them: the title's
  `$2000` / `$2006` writes moved ~39 dots, some into the next line.
- **Fix:** `nmi_gate`'s non-map path is the original `$EED0-$EEDF` with
  `ppu_nmi_on` inlined.  With the jump and the `TXR_ON` test, that is
  exactly the original's 42 cycles to `$EEE0`.
  - Measured on the title (frames 13-141 from power-on): the split writes
    land on the same dots as the build before round 3 (the usual ±2-4
    cycles of NMI latency).
  - The screenshots are identical.
- **Space:** `ef08_gate` is gone.
  - `$EF0B` jumps to the RAM's `cv_nmi`.
  - Bank 26's `nmi_cvg` picks `nmi_map` (map mode, not busy: from
    `nmi_gate`), else `EF08_HOOK` / `EF08_TAIL`.
  - 2 padding bytes keep every later fixed-bank routine at its address,
    and the RAM image is unchanged.  So save states made on the previous
    builds still load (the user's states 1 and 2 checked).
- **Map path cost:** ~30 cycles more to the first upload.
  - The worst 3-kanji batch puts `v = $1000` at line 260.08 (104 cycles
    to spare).
  - The dialogue scroll's 104-byte flush starts the force at line 260.52.
  - Hence `CV_MAP_FORCE_MAX` 104: a 104-byte flush in one entry starts it
    at ~261.07, the latest that keeps its scroll writes and the arm in
    time.
- **Rule** (the fixed bank's own header says it): nothing may change the
  cycle count of the game's NMI before its split loops.

### Fix (2026-11-13): messages that are only a JUMP

**The user's state 1:** talking to the bridge guard in the cave printed
「ﾌわの1」 and waited.
- `b11_msg_105` is `<JUMP:23B6>`: event code in bank 13 (here 「何者だ
  よそ者は帰れ」).
- The engine tests `$F9` only at a line's start (`$D160`).  Behind its far
  stub, the overlay resumes the message inside the line loop (`$D250`),
  so the jump's bytes were printed as text.
- A jump after text is fine: the compiler puts it after a line break.
- **Fix** (`kanji_text.py`): the 11 messages that begin with `$F9` keep
  their original 3 bytes in bank 10 / 11 in place of the far stub.
  - The engine runs the jump as the original does.
  - The messages: `b10_msg_441`; `b11_msg_033`, `047`, `089`, `105`,
    `122`, `140`, `274`/`275`, `280`, `284`, `331`.
- **Checked:** the guard now answers.  The greeting and shop (a jump
  after text), the menu cycle and the new-game path are identical to the
  previous build.

### Questions (2026-11-13): clear instead of scroll in the battle win; scroll in map mode

**1. Does a full CHR pool force a clear in the battle win?  Yes.**
- **The pool:** tiles `$A4-$DF`, 15 slots of 4 tiles (one kanji each).
  Groups 0-7 are the subwindows' (reward, prisoner, item, tactic) and the
  messages'; groups 8-14 are command kanji the pool may overwrite while no
  command window is up.
- **The rule** (`pool_choose`, asked by `overlay_entry` for a message that
  continues a window, and by `ctrl_store` at a page start):
  - Wanted `n` = the page's distinct kanji, +3 for each runtime name.
  - Blocked = every pool slot used in the window's lines (all four lines at
    `text_line` 0 and at 3, else lines 0..`text_line`) + `UI_PRES` (the
    reward and prisoner windows' kanji).
  - Free >= `n`: the message takes its slots and the engine scrolls on, as
    the original.
  - Free < `n` (C set, a "fallback"): the window is cleared (blank, top
    line) and the page takes slots beside the windows' only.
- **Measured** (`out/test/opt/poolprobe.lua`, the victory over 韓忠, state
  r5/s2):

  | frame | message | blocked (windows) | free | wanted | result |
  |---|---|---|---|---|---|
  | 1288 | 2nd, `text_line` 2 | 7 (0) | 8 | 6 | scroll on |
  | 1391 | 3rd, `text_line` 3 | 8 (4) | 7 | 7 | scroll on (exact fit) |
  | 1501 | 4th, after the capture choice | 14 (8) | 1 | 4 | **clear** |

- **The prisoner window caused the third.**  Its 4 kanji (仲間入逃,
  `wg_prison`) take pool slots while it is up: the reserved slots went from
  4 (reward window) to 8.  Without them the same message would have had 5
  free slots (4 wanted).
- **Other causes of a clear in battle** (rare): a page with more than 12
  kanji (`POOL_PAGE_MAX`) or a failed pool check goes to the band page;
  lines on the band page always clear.
- **If fewer clears are wanted:**
  - A message's kanji that already sit in a window's slot (金 兵 糧 経 験 値
    appear in the win messages themselves) could reuse that slot: up to 6
    slots back.  The overlay is 2044 of 2048 bytes, so the code would live
    in bank 26.
  - A bigger pool has no room: all 23 groups are assigned (15 fixed
    command kanji, 8 for the subwindows).

**2. Where did the scroll in map mode come from?  The game's own, never
switched off.**
- `text_scroll_up` (`$D376`) is called from three places:
  - `$D1BA`: after a line ended by `<NL>` / `<NL2>` / `<PAGE>` / `<WAIT>`
    when the window holds 4 lines (the 4th line).  For `<PAGE>` it scrolls
    first and waits after.
  - `$D1DE`: at the end of a message (`<END>`) with 4 lines in the window.
    The original scrolls one line so that a message that continues the
    window has a free line.  The kanji build clears the window for the next
    message in map mode, so the scroll gains nothing here.
  - `$D2AC` (`scroll_text`, the page flip's `window_clear`): scrolls blank
    rows; it looks like a quick wipe (3 frames), not a scroll.
- **What the kanji build replaced:** the scroll at a `<PAGE>` wait (a flip
  to a fresh window) and the continuation of a window (`@clear`).  The 4th
  line and the end of a message were left as the original.
- **Which messages** (`out/test/opt/scrollscan.py`: the compiled messages
  run through the engine's line rules): 19 of 765.
  - End of message with 4 lines (11): `b10_msg_139` 153 166 203 347 349;
    `b11_msg_037` 044 137 163 273.
  - A 4th line inside the message (12): `b10_msg_153` 203 325 399 463;
    `b11_msg_044` 098 101 161 250 266 273.
  - Story ones among them: 張世平's gold, 馬良, 水鏡先生's letter, 孫権's
    last words, 孔明 urging 劉備's enthronement, 呂布's death, 徐庶's
    mother's letter, the 荊州 orders.  The other 746 never put 4 lines in
    the window before a flip (lines counted across `<WAIT>`s, which do not
    clear).
- **Checked** by running each message in map mode (`mkmsg.py` / `injrun.sh`
  overwrite the far pointer of the save man's first message in state r4/s1
  with the message's; `poolprobe.lua` logs the calls): every one of the 18
  that can run without its event context calls `text_scroll_up` from `$D1BD`
  (4th line) or `$D1E1` (end), where the scan said.  `b11_msg_266` stops
  after its third wait when injected (probably its second officer name,
  which needs the event); its 4-line page is predicted only.  Seven
  messages with a 3-line window (`b10_msg_032` 238 372; `b11_msg_010` 062
  135 219) never call it.
- **Why it is slow:** 11-12 frames in map mode, 6-7 in battle (the same
  engine code, no renderer).
  - Each step flushes a window row (104 bytes) and the line that moves from
    part 4 into part 3 (row 21 to 19) needs its kanji in the other part's
    page: 13 tiles in the measured example, two upload frames.
  - The engine moves half a line per step, so the kanji show half-shifted
    in between (also in battle and the original).
- **Options** offered: A, no scroll in map mode (an end-of-message skip
  and the compiler turning a `<WAIT>` into a `<PAGE>`); B, keep the scroll
  and upload first; C, leave it.  The user chose a runtime form of A, below.

### Done (2026-11-13): in map mode a page break where the engine would scroll

**The user:** "in map mode only, treat now-to-scroll as page break".

- **After every line** (`$D1B4`: `cmp #$01 / bcc` in place of `cmp #$04 /
  bne`, then `jsr map_lines` at `$D1BA`, fixed bank):
  - `text_line` 4: the original scroll (outside map mode; in map mode
    only for text the look-ahead cannot read).
  - Map mode, after the 3rd line or a `<WAIT>`: bank 26's `TXF_LOOK` (by
    `txr_call`; the answer in the V flag, which `txr_call` keeps) reads the
    next `4 - text_line` lines from the overlay's text bank (`txr_rr`,
    32-byte pieces).  If the last of them would end with `<NL>` / `<NL2>` /
    `<PAGE>` / `<WAIT>` (the engine would scroll there) and none before it
    is a `<PAGE>` or a later `<WAIT>`, the line just ended becomes a page
    break: `PAGE_FLAG` (`page_flip` clears the window after the wait; in
    map mode `page_start` only clears the flag again), and a 3rd line ended
    by `<NL>` / `<NL2>` waits as at a `<WAIT>` (its control on the stack
    becomes `$FD`).
- **Why a line earlier than the scroll:** a break with 4 lines up puts the
  ▼ on the 4th line's text (tried: 「桂陽の城▼ことも気になる」, and the cell
  stays blank after the press).  The window never holds 4 lines with more
  to come, so the ▼ sits on an empty line as at any page, and the break
  is an existing `<WAIT>` whenever there is one.
- **The end of a message with 4 lines** (`$D1DE`, `map_end4`): no scroll in
  map mode.  The 4 lines stay; the caller waits for the button (no ▼ there)
  and the next message starts on a cleared window (`overlay_entry`'s
  `@clear`).  A wait and a clear at that point would add a press on a blank
  window.
- **Space:** `sub_CE7A` (an event's map change) moved to the UI bank
  (`UIF_ROWEV`) to free its fixed-bank bytes.  No other routine moved; the
  RAM image is unchanged.
- **Checked** (the 19 messages injected into the save man's talk, first
  pass compared with the previous build):
  - no `text_scroll_up` from `$D1BD` / `$D1E1` in map mode;
  - the same number of waits (A presses) in every message;
  - a clear where each scroll was;
  - the ▼ on an empty line at the breaks (`b11_msg_044`, `b10_msg_463`,
    `b11_msg_250`).
  - `b11_msg_266` now runs to its end; on the previous build its first
    pass stopped two waits early, around its 4-line scroll.
  - The 7 control messages: identical.
  - Battle (the capture state's victory): the same pool decisions and the
    same 4 engine scrolls.
  - The room-transfer wipe: identical pictures and queue sizes.
  - `sub_CE7A`, forced at the room transfer: identical PPU writes and
    nametables.
  - The greeting, the menu cycle, a battle, the title and the new-game path
    are identical to the previous build.

**The scan (2026-11-14): `tools/scroll_scan.py`.**  The user wants the
scrolls fixed in the text itself, so this run-time code can go.
- It lists every message whose text puts a 4th line in the window.  It
  uses the compiler's own layout (`kanji_text.fit_tokens`, now a module
  function: the build is byte-identical), then the engine's line rule.
- It shows the four lines, where the break goes, and the edit (usually a
  `<WAIT>` made a `<PAGE>`).  It marks the breaks the compiler added
  (auto).
- After an inner scroll it goes on as if that break were made, so each
  entry is a cause of its own.
- First run: 20 causes in 19 of 765 messages, the same 19 as the
  2026-11-13 scan.
- When it lists none, `TXF_LOOK`, `map_lines` and `map_end4` have nothing
  left to do and can be removed.

### Done (2026-11-13): the battle messages' kanji after a win, and a last-resort collection

The user's order: once the battle is won, tiles `$80-$A3` are free for
9 more kanji; if even that is not enough, count what is on screen and
cannot be purged, treat every other kanji tile as free and upload there.
The window is cleared only when even that fails.  The battle-only pool
code moved out of the overlay into the UI bank (bank 28, through
`call_ui`); the overlay keeps two stubs.

- **Slots** (`kanji.inc`, `ui_battle.asm` `ui_pchoose` / `ui_ptiles`), 4
  tiles each in 8x16 order:

  | slots | tiles | when |
  |---|---|---|
  | 0-14 | `$A4-$DF` (groups 0-14) | always, as before |
  | 16-24 | `$80-$A3` | once the battle is won |
  | 25-30 | `$E0-$F7` (groups 15-20) | the collection, when the rest is full |

  Groups 21-22 (`$F8-$FF`) stay out: their top tiles would be the text
  engine's line-end codes `$F8-$FF` (`render_ctl` now draws `$80-$F7`).
- **The win:** `b10_msg_059` 「…との戦いに勝った」 and the rewards
  `b10_msg_061` / `062` carry bit 5 of the metadata's page count
  (`META_WIN`, `kanji_text.py` `WIN_LABELS`).  When one starts in a
  battle, `message_setup` sets `UI_BATTLE` bit 7 (`UI_WON`); the battle
  start clears it.  `$80-$A3` are the battle portrait's 36 tiles; measured
  in a portrait battle (state r4/s2, enemies poked to 1 troop) no
  portrait is shown when 059 starts (the last one closes before it) and
  nothing writes `$80-$A3` after it.  The scripted battles' victory face
  (`b14_battle_victory_event`) comes before 059 in the code; it was not
  played.
- **The tries** (`ui_pchoose`):
  1. Slots 0-14 (and 16-24 once won), minus the kanji in the window's
     lines and `UI_PRES` (the reward and prisoner windows).
  2. The collection: also slots 25-30, minus every group a window on
     screen shows or the window being drawn uses (`GF_REF`, `GF_NREF`).
  3. The fallback, as before: the window is cleared.
  The lines are now read only in each row's 20 window cells: bytes 20-23
  are never shown, and the battle windows' row buffers (the same
  `$0300-$03BF`) left gauge and command tiles there, which used to block
  slots.
- **After the collection:** a group 15-20 taken by a message is marked
  `$FE` in `UI_SLOT`; the command window puts its kanji back when it opens
  (`need_fixed`, one per NMI: up to 6 frames later than usual, only
  before the win).  The glyph upload keeps plane 1 of `$E0-$F7` (HP gauges,
  S P; `hack.asm` `plane1_blank`).
- **The reward and prisoner windows** open beside the message window.
  They now keep off every slot the message may show (`UI_PML`: the lines
  at the last page start plus every slot placed since; `grp_shown` in
  `grp_safe` and in the reward window's group search).  The reward window
  takes groups 15-22, then a free pool group (reserved in `UI_PRES`), and
  overwrites only when nothing else is left.
- **Measured:**
  - The capture victory (r5/s2): the 4th message (「二君に仕える気はない」)
    now scrolls on with slots 14, 16-18 (it was cleared: 1 free of 4).
    Identical to the previous build up to there.
  - The portrait battle's forced win: 「関羽は兵士数が 191になった」 scrolls
    on instead of clearing.
  - The collection, forced (`UI_PRES` poked to block the whole pool):
    `b10_msg_061` took groups 15-18; the gauges stayed; the reward window
    then used groups 20-22 and pool groups 0-2, and the message stayed
    intact.
  - Greeting, menu cycle, the officer-switch battle, the title and the
    standard path: identical to the previous build.
- **Limits:** before the win 15 slots, plus up to 6 from the collection;
  after it 24, plus up to 6.  At `text_line` 0 all four lines still count
  as shown, including leftovers of other windows in them.  (A page over
  12 slots used the band page until the next change.)
- **Space:** the overlay is 1790 of 2048 bytes; the UI bank 12839 of 16384.

### Assessment (2026-11-13): the user's by-code tracking for the battle box

The user's scheme: a 4-line ring buffer of the box's text (36 bytes a
line); preload 金兵糧経験値 at the win and lock them; move old on-screen
金/兵 to the locked copies; all 32 groups `$80-$FF`; no band page and no
12-kanji limit in battle.

- **What the current code tracks:** the engine already keeps the box's
  4 lines as tiles (`$0300-$03BF`, top and bottom tile of every cell,
  scrolled with the box): `ui_pchoose` reads them (20 window cells a row).
  It knows which slots are on screen, not which kanji a slot holds, so
  every page uploads all its kanji again.
- **Measured** (`poolprobe2.lua`, k28): the r4/s2 battle, 20 messages:
  85 kanji uploads, 20 distinct; 65 were glyphs uploaded earlier in the
  same battle.  Each upload waits about 2 frames (half a glyph per light
  frame), so about 130 frames of waiting.  The capture victory (r5/s2): 23
  uploads, 2 repeats.
- **A text ring buffer** (144 bytes) would duplicate the engine's lines;
  a slot -> code table (32 entries, 64 bytes) gives the same answer from
  the tiles.  Free RAM in battle: the map renderer's staging buffers
  `TXR_UQ` (55) and `TXR_EB` (48) are used by the map renderer only.  The
  engine's lines also serve as row buffers when battle windows draw, so a
  fresh window starts with leftovers; the code table lets those be
  ignored (a slot counts only if it holds a message kanji).
- **Preload at the win:** the end animation (`b14_battle_end_anim`, 120
  frames) comes before the rewards: time for the 6 uploads with the
  existing NMI path.  Six kanji need `$80-$97` (24 tiles).  The extra 8
  black lines at the top would need rendering off until line 8, timed by
  counting cycles from the NMI (the MMC3 counter does not run while
  rendering is off), next to the battle's IRQ arm: not needed.  Moving
  old 金/兵 copies to the locked ones frees at most 2 slots until they
  scroll off.
- **32 groups:** before the win `$80-$A3` is the portrait (23 groups);
  groups 8-22 are the command kanji, borrowed between rounds and put back
  when the command window opens.  Groups 21-22 (`$F8-$FF`): their top
  tiles are the line-end codes; telling them apart by the bottom tile
  needs about 8 more fixed-bank bytes (the bank is full).  Plane 1 to keep
  in `$E0-$FF`: `$E0-$E6` and `$F6-$F7` (groups at `$E0`, `$E4`, `$F4`);
  the upload already skips plane 1 for all of `$E0-$F7`.
- **Band page / limit:** the largest battle page needs 13 slots
  (`b10_msg_463`); `KANJI_UPLOADED` holds 16.  Outside battle and map
  mode (boot screens, name entry) the band page is the only kanji path.

### Done (2026-11-13): no band page and no page limit in battle

- `pool_decide`: on the battle screen (`UI_BATTLE`) every message uses the
  pool; the per-page walk against `POOL_PAGE_MAX` (12) is gone.
- Pool pages track nothing per entry any more: `ui_ptiles` returns V set
  when this page placed the entry already (its slot is in `UI_PML`), and
  `KANJI_EC` uploads only on V clear.  The names' reserved entries are
  counted (`KANJI_UPLOADED` byte 0, `kn_put`; `TXF_NAME` adds the count)
  instead of a 16-bit bitmap.  A fallback clears `UI_PML` (the window is
  cleared: every slot placed after it is new).
- Checked: `b10_msg_349` (15 kanji on one page) injected in place of the
  win message: the previous build put it on the band page, this one in
  pool slots 0-14 (fits exactly), shown sooner.  The capture victory, the
  level-up battle, the forced collection and the regression set are
  identical to the previous build.
- Left: the compiler still splits a page above 16 kanji
  (`MAX_PAGE_ENTRIES`), because every message still carries band-page
  tile plans; no battle page comes near it (the largest needs 15).

### Done (2026-11-13): the line ends and tiles `$F8-$FF`

The text engine ends a line at a top-row byte with bit 7 set (`render_ctl`
draws `$80-$F7`); the line ends it stores are `$FA-$FF`, which a kanji's
top tiles in `$F8-$FF` would match.  `render_ctl` now compares the top
tile with the cell's bottom tile: a kanji's bottom tile is the next one
(8x16 order: t over t+1, t+2 over t+3), a line end's bottom cell is the
cleared blank.  15 bytes in the block that had 16 (`irq_tail` moved one
byte; only fixed-bank jumps reach it).  No fixed-bank bytes had to be
freed.

- Checked with a test build that put pool slot 14 at tiles `$F8-$FB`
  (UI_PRES poked so that slot 14 is used): 劉 of 「劉備軍は韓忠との」
  showed correctly and every line ended where it should.  (The test build
  also showed the reward window's 糧 overwritten: its group 21 was the
  test's slot 14; the real slot table will know both.)  The regression set
  and the capture victory are identical to the previous build.
- So all 32 groups can hold kanji after the win: 6 for the reward window,
  26 for messages (the slot table, next step).

### Done (2026-11-13): the battle's kanji slot table

The user's design (assessment above), replacing the pool slots, the
collection and the reward window's group search:

- **Slots:** slot s = tiles `$80` + 4s, s = 0-31, 8x16 order (the battle
  screen's group k is slot k + 9).
  - Before the win: 9-23; the command kanji's 17-23 (将武却退撃攻総) only
    when 9-16 have no free slot.  0-8 (the portrait) and 24-31 are never
    taken.
  - From the win (`b10_msg_059` / `061` / `062`): 0-5 are the reward
    window's 金兵糧経験値, loaded at the first victory message (one a
    frame, 6 frames; `UIF_RWLOAD`), 6-31 the messages'.
- **Slot table** (`SL_LO` / `SL_HI` / `SL_AGE`, 97 bytes in the map
  renderer's staging buffers, unused in battle): the text code of the
  kanji in each slot.  The UI's own uploads note theirs too (`q_glyph`, the
  fixed command kanji at the battle start: `ui_gcode_lo/hi`), so a message
  uses 攻撃 from the command window's slots.
- **A kanji** (`ui_ptiles`): in a slot already -> that slot, no upload;
  else the free slot used longest ago (pages, `SL_CLK`).  Free = this
  phase's and not shown: the lines' kanji (bottom rows of the 4 lines),
  the battle windows on screen (`GF_REF`, the prisoner window), the slots
  placed on this page.
- **A page** (`ui_pchoose`): fits when this phase's free slots are at least
  its kanji plus 3 per runtime name (kanji already in a slot count too);
  else the window is cleared, as before.
- **The reward window** draws from slots 0-5; the prisoner window takes
  free groups as before (never one the message may show).
- **Save states** made in a battle by an earlier build: `UI_SLV` is not
  `SL_MAGIC` there, so the table starts empty (those kanji are uploaded
  again once).  Without that check a state from before this change showed
  道 for 軍.
- **Measured:**
  - Level-up battle (r4/s2, 2400 frames): 37 uploads, 53 kanji used from
    their slots, no clears (85 uploads before).  One LRU over 9-23 instead
    of "17-23 last" gave 33 uploads but 5 command-kanji restores: about the
    same cost, so "last" stays.
  - Capture victory (r5/s2): 17 uploads + the 6 reward kanji; 経験値 and
    金 of the reward message came from slots 0-5.
  - Portrait battle's forced win, the injected 15-kanji page: right.
  - Greeting, menu cycle, officer-switch battle, title, standard path:
    identical to the previous build.

## The kanji store (2026-11-13): one copy, bank + pos

The user's order: every kanji once, in four consecutive 8 KiB banks of
256 glyphs, located by bank + pos; the text's kanji code carries the bank
and pos directly (high bits mark a kanji, 10 bits bank + pos, no
conversion); every kanji path (messages, the battle's officer names, the
info screen, the army screen) reads it; the band page's font copy goes.

**Layout** (`kanji.inc` `STORE_*`, `kanji_build.py` `build_store`):
- 8 KiB banks 32-35 = the 16 KiB banks 16 and 17.  Glyph code c = its
  number in `kanji_common.inventory()`: bank `c >> 8`, pos `c & $FF`.
  982 glyphs: banks 0-2 full, bank 3 holds 214, its last 42 pos blank.
- Inside a bank, byte b of glyph pos is at `$A000 + 256 b + pos` (with the
  bank at R7): `ldx pos` / `lda $A000+256*b,x`, one indexed load a byte, no
  pointer arithmetic and no page crossing.  That is the layout the map
  renderer's NMI copy already had (it is what lets the NMI upload 3 kanji a
  frame); 32 consecutive bytes a glyph would cost 3 more cycles a byte
  there, ~300 cycles a frame at 3 kanji.
- b = 8 k + row, tile k in 8x16 order (TL, BL, TR, BR), the battle
  screen's groups and the original game's name font; read in order, a
  glyph comes out as the 4 tiles t..t+3 of a battle group.

**Text encoding:** a kanji is `$EC + bank, pos` (`%111011bb pppppppp`:
the top 6 bits mark it, the low 10 are bank and pos), two bytes for every
kanji; the overlay's `text_dispatch` already puts `byte - $EC` in
`KANJI_CODE_HI`.  The 3-byte `$EE hi lo` is gone (text 31,849 -> 30,973
bytes).  The kanji controls moved from `$EE $FB-$FF` to `$F0 $FB-$FF`.
`$EF` (a place name) and `$F0` (a word) were the original's insertions:
0 uses in the compiled text, none in the window templates; the compiler
now refuses `<PLACE:>` / `<WORD:>`.

**8 KiB switching for our main-thread code.**  Every NMI restored both
PRG halves from `current_prg_bank`, so main-thread code could not keep an
8 KiB bank at R7 across an NMI.  `nmi_prg` (the restore's body, moved to
`$D4C9`) now keeps R7 = `PRG_R7X` when that holds a store bank (32-35);
the NMI's own maps (the hack bank, the sound bank) use `nmi_prg_pair`.
Main-thread code: set `PRG_R7X`, map R7, read, clear `PRG_R7X`, map R7
back; nothing that may switch banks or yield in between.  `PRG_R7X` is in
battery RAM (`UI_RAM2+16`): `hack_init` clears it at reset, and the NMI
ignores any value outside 32-35, so a save state from an earlier build
(whose battery RAM had `$40`, `$02`, `$01` there in the user's states)
runs.  Cost: 6 cycles a restore when clear.

**The readers:**
- Battle pool and band page (`hack.asm` `glyph_upload`): R7 = the store
  bank, 8 unrolled loads a tile (`UPLOAD_TILE k, s`: KANJI_TILES keeps its
  TL, TR, BL, BR order; s is the store's tile).  The hack code is in bank
  23's lower 8 KiB now (the palette tables at `$9F00`); it was copied into
  banks 23-25 beside 359-glyph tables, and a code meant a divide by 359.
  Costliest NMI unit 702 cycles from entry (733 before).
- Map renderer: the NMI uploader's R7 value is `STORE_8K | bank`, its
  column the pos (the code as it is); `read_kanji` (rendering off) reads 32
  bytes through the RAM reader from the 16 KiB bank `STORE_16K + bank >> 1`.
- UI bank (`M_STMAP` / `M_STUNMAP`, routines kept in `$8000-$9FFF`, checked
  by the assembler): `q_tiles` (battle windows, the reward window),
  `put_code` / `put_glyph` (info screen, army screen), the battle start's
  fixed command kanji.  A UI glyph number indexes `ui_gcode_lo/hi`, its
  store code.  The UI's own 147 glyphs (4.6 KiB) are gone.
- Officer names in the original name engine (`put_officer_name` with `$AA`
  set: the battle screen, the info screen): its kanji path (`$D4C9-$D548`,
  the address arithmetic for the original's name font) is `pon_kanji` now.
  Per kanji it calls `UIF_NAMEG` (the UI bank's name table by record,
  `ui_nm_lo0-2` / `ui_nm_hi0-2`), which queues the glyph to plane 1 of
  `$A9..$A9+3`, then waits a frame as the original did, so the frame count
  is the same.  The army screen's names (`ar_name`) and 大将 / 軍師 use the
  same table and the store.  Bank 12 is the original's again (its records'
  glyph bytes are no longer read), and the 8 KiB name font is gone.
- Free 21 bytes at `$D534-$D548`, 22 in the `$C5A6` region.

**Checked** (`out/test/opt`, the previous build k31 against this one, k32):
- Every glyph of the store equals the old NMI copy's and the old hack
  copy's (982), the 147 UI glyphs equal the old UI copy, the 445 name kanji
  equal the old name font, 大将 / 軍師 too.
- Pixel-identical screens: greeting, menu cycle, officer-switch battle,
  title, standard path (570 shots), level-up battle (116), capture victory
  (161), the info screen from the map (29) and from a battle and back
  (81), the army screen opened twice (50).
- R7 traffic (`r7probe.lua`): store banks 0-3 by the NMI in map mode and in
  battle, 0, 1 and 3 by the main thread (UI); `PRG_R7X` 0 at the end, the
  r5/s2 state's stale `$02` cleared.
- `vblank_deadline` (standard path): 0 hack PPU accesses after the
  pre-render line, 0 late scroll restores.
- The original build is byte-identical.

## The title screen and the attract mode (2026-11-14)

The user's spec (`titlekanji.txt`, kept out of git as theirs; the text is
`tools/attract_text.py`).  The title's ©もとみやきかく／しゅうえいしゃ and
every line of the attract mode (the intro over the logo, the five
portrait screens, the text screen) in kanji.  Portraits are sprites.

**Code and data.**  Bank 24 (`tools/asm/attract.asm`, data from
`tools/attract_build.py`: `attract_lo.inc`, `attract_hi.inc`), 4.3 KiB of
it used:
- `$8000` the attract mode.  The fixed bank's `enter_party_screen` maps
  bank 24 and jumps there in place of bank 7's `b07_enter_party_screen`
  (3 bytes, `$F0D8`, `$F0DD`).  Bank 7 is the original.  The port keeps
  every step and frame count of bank 7's code: phrases, delays, fades, the
  slide, Start (only in the delays, as the original's `b07_delay_frames`)
  and the end in `enter_status_screen`.
- `$8003` the title's tile set and nametable.  The title's inline block
  (bank 13 `b13_inline_881A`) calls it in place of the letters' copy and
  `load_battle_palette`.  The block's `draw_string` gets only the
  original's attribute records (`ATT_TITLE_ATTR`).
- `$8006` Start on the title: `b13_loc_88BC`'s jump goes to
  `b13_k_restore` in bank 13's filler.  That puts the font (bank 9) and the
  letters (bank 2) back on the scene page for the boot screens, as the
  original's title load left them.
- The kanji: 21 new ones joined the store (`kanji_common.ui_kanji`
  appends `attract_text`, so no earlier code moved); the store holds 1,003
  of 1,024.  黄忠 uses 黄 (U+9EC4), as the game's officer name (the user's
  choice; the file had 黃).

**Tile sets** (the user's rules): every screen has its own BG set,
uploaded while it is black.
- Kanji from tile `$00` (4 tiles each, 8x16 order, from the store through
  `PRG_R7X`), then every 8x8 glyph the screen needs: the game's font (bank
  9 `$BA00`, 1bpp) and the title's letters (bank 2 `$BE00`).  Tile `$FF`
  is written blank and the nametables are filled with it.
- The title keeps the logo at `$80-$DF`; its 8x8 glyphs continue at `$E0`.
- The intro uses the title's set (no transition).
- Banks 2, 3 and 9 are read by RAM routines (`RR_COPY`, `RR_PART`, copied
  to `$0660`) that map them with `set_bank_b`, the game's NMI-safe switch.

| Set | Kanji | 8x8 | Last tile | Free |
|---|---|---|---|---|
| Title + intro | 25 | 49 | `$F4` | 10 |
| Portrait screen 1 | 45 | 15 | `$C2` | 60 |
| Portrait screen 2 | 41 | 13 | `$B0` | 78 |
| Portrait screen 3 | 35 | 13 | `$98` | 102 |
| Portrait screen 4 | 39 | 15 | `$AA` | 84 |
| Portrait screen 5 | 25 | 8 | `$6B` | 147 |
| Text screen | 28 | 33 | `$90` | 110 |

**Lines.**  A kanji is two columns, every other glyph one, and U+3000 is
one blank column, as the original's spaces.
- A line's kanji bottom row is the original line's row, and dakuten go on
  the row above, as the game's font draws them.  So a line covers rows
  r-1 and r: the original line plus its dakuten row, one attribute row.
- Each phrase keeps the original phrase's attribute records, so it fades
  in through BG palette 2 on its own attribute row as before.
- The build follows the attribute state from each screen's start.  When
  a line is drawn its cells must be palette 2, and the lines drawn before
  it must not be.  A line the original leaves in palette 1 gets one record
  for its own quadrants.
  - Only the intro's last line (row 25, ヒストリー ロールプレイング ゲーム
    である) needs it: the original's oversight, so that line popped in
    unfaded.  It fades now (the user's fix, 2026-11-14): `$23F1`, 6 bytes.
- Columns: intro 5, bands 1 and 3 column 9, band 2 column 2 (checked to
  end before its portrait at column 24), as the original.  The text
  screen starts at column 4 (the user's hard indent, 2026-11-14; the
  original's column 3) with the user's leading blanks.
- The build fails if a line would leave its rows or columns.
- The longest phrase is 55 queue bytes.

**Portraits as 8x16 sprites** (the user's choice over the mid-frame OAM
DMA scheme):
- 18 sprites a portrait, 54 at most, 6 on a line, so the NMI's own OAM DMA
  shows them all; no scanline IRQ, no mid-frame `$2001` or DMA.
  `PPUCTRL` bit 5 is set on these screens only and cleared when the
  attract ends (Start included).
- The parts (bank 12's records, 6 parts of 6 tiles from banks 2/3) go to
  the sprite page in top/bottom pairs, tile `36 p + 12 (R >> 1) + 2 c + (R & 1)`.
- Band 2's portrait is the H-flip, in place of the original's
  bit-reversed copy.
- All 13 attract portraits use colour `$20`.  Sprite palette 0 is BG
  palette 3 after each `load_text_graphics`, so the fades treat it as the
  original's portrait palette.  The fades get `$A4` set, so they leave the
  OAM shadow alone.
- The slide: x = 16 + offset for bands 1 and 3, 192 - offset for band 2,
  offset `$F8` down to 0 in steps of 8, a column hidden while it is past
  the screen's edge.

**The band page.**  The boot screens' record prompts show the font
through the band (page 2), and the original's title load put it there
through the block writer's mirror.  `att_title_set` writes it to page 2
directly.  The title and the attract never touch page 2 otherwise.

**Checked** (`out/test/opt/att`):
- Event timeline (fades, screen on/off, the title) against the original:
  the same sequence and frame counts.  The black phases are 3-5 frames
  where the original took 6-7; the text screen takes 3 where it took 1
  (it uploads its set now).  The title comes 1 frame later than the
  original (the page-2 font) and 2 earlier than the previous build.
- All five slides are pixel-identical to the original's BG-split slides,
  45 frames each.
- No PPU write while rendering is on, other than `screen_fade_in`'s
  `PPUCTRL` write, which the original makes too.  The original's mid-frame
  writes are its split loops.
- Start during the intro, a slide, a phrase and the text screen leads to
  the title.  Start during a fade is ignored, as in the original (checked
  on both).  Then Start leads to the boot screens with the font.
- Standard path against the previous build: CHR RAM is identical at frame
  6200 (both pages), and every boot-screen frame from 300 to 1700 has an
  identical frame within 2.  The path runs one frame later after Start on
  the title: the restore takes ~0.94 frame, and there are ~2.5K cycles
  of slack before the next frame there.
- Attract with the portraits loaded, Start, Start, into the game: the
  same screens as the standard path; the sprites are the game's again.
- Only banks 13a, 15b/31b, the store's last bank and bank 24 differ from
  the previous build.  The original build is byte-identical.

## The boot screens' messages on the fixed set (2026-11-14)

The user's direction: the whole boot menu uses one fixed kanji set,
始歴史書登録消名前入戻進終速普通遅本当宜, at `$80-$DF`.  That range is
volatile on the boot screens, so the set has room and leaves the letters
(`$E0-$FB`, the record list's level) alone.  No band, no tricks.

**The set.**  `kanji_common.BOOT_FIXED`, in the user's order: 20 kanji,
tiles `$80-$CF` (t, t+1, t+2, t+3 = TL, BL, TR, BR as before).  It adds
本 当 宜 to the 17 of 2026-11-12, and 戻進終 now come before 速普通遅.
`build_txr_ui` fails the build if any kanji of the boot menu, the boot
windows' words, the name-entry title or the boot messages is outside it,
or if the set passes `$DF`.

**The messages.**  The boot screens (`TXR_ON` = `$40`) print six:
b11_msg_146 (どの歴史書を始めますか), 148 (登録), 149 (消し), 150
(本当に宜しいですか), 151 and 152 (コピー) (`kanji_common.BOOT_MESSAGES`;
bank 13's only `text_print_inline` sites between `$8B43` and `$8CEF`).
Until now they used the band page (the pool tiles hold the set).  Now:
- `message_setup`: `TXR_ON` non-zero (map mode or the boot screens):
  no band, no pool, no `REQ_SYNC`, nothing to clean.  `page_start` is the
  same.
- `KANJI_EC`: with `TXR_ON` = `$40`, `fix_put` finds the code in the
  overlay's copy of the set (`boot_fix.inc`, 20 code pairs) and writes the
  tiles `$80 + 4k`.  No metadata lookup, no upload.  A kanji outside the
  set would be blank cells (the build allows none).
- The overlay is 1830 / 2048 bytes.  The fixed bank changes only in
  `ctrl_store`'s address (`$D2C8`).

**Not on the set (first commit, fixed below):**
- b11_msg_145 (残念ですが／歴史書Nは／消えています): the record check
  before the menu (`$8A55` loop, `loc_C139`, `TXR_ON` = 0, set 8).  It is
  shown only for a damaged record, and it used the band.  Its 残念
  are outside the set.
- b11_msg_147 (文字の速さを決めてください): nothing in the ROM prints it
  (no inline index `$0293` in banks 0-15; the speed window shows no
  message).

**Checked** (`out/test/opt/boot`, against the previous build):
- Start, delete (with はい/いいえ), register (to the name entry) and copy
  flows, from copies of `rom_kanji.sav` (two records, and one after the
  delete):
  - no band and 2 IRQ enables on each (the previous build: 284-940);
  - every prompt is pixel-identical once printed, and prints sooner
    without the waits: どの歴史書を消しますか 9 frames, 本当に宜しいですか 7;
  - the only unmatched shots are text still printing.
- Standard path from power-on (6,200 frames): 568 of 591 shots identical
  at the same frame; the rest are text printing earlier, including the
  oath scene's first page (fewer band-page tiles to restore).  The GC
  starts at the same frames.  `band_use.lua`: the band turns on once (the
  oath scene, 729 switches; before: 3 times).
- A damaged record (scratch save): b11_msg_145 on the band as before,
  41 of 41 shots identical.
- The regression set (greeting, menu cycle, officer-switch battle, title,
  standard path from frame 2000): pixel-identical.
- The original build is byte-identical.

### The whole boot menu on the set (2026-11-14, second round)

The user's answer: add 残念 and 文字決 (VRAM is enough; no band anywhere
in the boot menu).  The speed message is the original's oversight: after
a history book is chosen, show it first, then the speed window; when the
speed window is cancelled, show どの歴史書を始めますか again.

**The set: 25 kanji, tiles `$80-$E3`.**  The user's 20, then 残念文字決.
- `$80-$DF` holds 24.  The 25th (決) takes `$E0-$E3`, the letters A-D.
  No boot screen shows those: only L (`$EB`, the record list's level).
  The title's PRESS START, TM, ©, ® and CAPCOM 1989 are drawn before the
  boot screens.
- `FIX_LIMIT` is `$E4`.
- The game gets A-D back before it shows them: CHR RAM is byte-identical
  to the previous build in the map (from a record) and during the oath
  scene and the town (a new game).
- The set upload (`txr_menuinit`, each boot screen, rendering off) took
  68,583 CPU cycles (2.3 frames), 54,888 for 20 kanji: +0.46 frame a
  screen.  Since the third round it runs once (below).

**The record check** (bank 13 `b13_k_check`, the damaged-record path
only): `ppu_init`, then `TXR_MENU` (the set, `TXR_ON` = `$40`), then
b11_msg_145 as before.  A boot with sound records does not pay for it.
(Third round: only the flags, below.)

**The speed message** (`b13_k_speed`, in place of `ldx #$29` / `jsr
text_init` at `$8B71`): `input_buttons` = `$84`, window `$1E`,
b11_msg_147, then the speed window `$29`.  This is the same sequence as
the delete flow's b11_msg_150 before its yes/no window.  Cancel still
goes to `$8B43`: the start screen is rebuilt with どの歴史書を始めますか
and the book list, as the original did.  Both routines are reached by
`jmp` and return by `jmp`, so the stack depth is the original's.  They sit
in bank 13's filler after `b13_k_restore`.
- **Layout:** the speed window (rows 12-19, columns 22-28) covered the
  message window's top-right corner: its top border and the first text
  line's top row at those columns.  The message's cells there (さい) are
  plain kana with blank top rows, so the text was whole.  The original
  never showed the two together.  (Third round: the window moved up.)

**Checked** (`out/test/opt/boot`, against the first commit's build):
- Start flow from `rom_kanji.sav`: book, message and speed window,
  cancel, どの歴史書を始めますか and the list again, book, speed, the map
  (the same frame as before).
- Damaged record: b11_msg_145 on the set, pixel-identical once printed,
  8 frames sooner.  No band (2 IRQ enables; 178 before).
- Delete, register and copy: no band; 60-70 of 61-71 shots identical at
  the same frame.  The rest: a cursor blink, and a window caught mid-draw
  (the longer upload).
- Standard path from power-on: the band turns on once (the oath scene).
  The screens differ only where the message now shows before the speed
  window.  The oath starts at the same frame.
- The regression set: pixel-identical.  The original build is
  byte-identical.

### The set loaded once; the speed window up (2026-11-14, third round)

The user's questions: the set should already be in VRAM, so why load it
on each screen?  And move the speed window 2 tiles up: the third record
used to push it down, and it is gone.

**One upload.**
- Until now `TXR_MENU` wrote the whole set into CHR on every boot screen.
  That took 2.3 frames with the screen black, though the set was still
  there from the previous screen.
- At the record check the set was not in VRAM yet.  The record check runs
  before the main menu, right after `b13_loc_8A23` loads graphics set 8
  (the battle set) over `$80-$FF`.
- Measured (`out/test/opt/boot/setkeep.lua`): from one upload to the next,
  0 of the set's 100 tiles changed, and nothing else wrote PPU
  `$1800-$1E3F`.  The flows: register (the status menu and the name entry
  included), the menu, start with the speed window cancelled, delete,
  copy, and a damaged record.
- `b13_loc_8A23` is the only way into the boot screens (Start on the
  title, through `b13_k_restore`).

The changes:
- `TXF_MENUSET` (13, `txr_menuset`): the upload, called once by bank 13
  `b13_k_set` in place of the `wait_vblank` after set 8.
  - It runs at frames 300-302 of the standard path (68,551 cycles).
  - `PPUMASK` is `$06` at its start and end (rendering off), and no
    `PPUMASK` write turns rendering on during it.
- `TXF_MENU` (each screen's `TXR_MENU`): only `TXR_ON` = `$40` and the
  pool marked unusable.
- `b13_k_check` (the damaged record): `TXF_MENU` through `TXR_CALL`, no
  `ppu_init`, then b11_msg_145.
- The later boot screens build about 2 frames sooner.  `TXR_ON` no longer
  stays 0 for a whole frame between screens, and the menu after the name
  entry comes 2 frames earlier.

**The speed window** `$29`: its row byte (template byte 0, in metatiles)
goes from `$FF` to `$FE` (`kanji_build.MAP_UI_ROWS`; lint range
`$ED4C-$ED4E`).  It now spans rows 10-17, between the record list (rows
4-9 with two records) and the message window (from row 18).  The original
placed it at row 12, below the 3-record list's last row (11).

**Checked** (`out/test/opt/boot`, against the second round's build):
- Start with cancel, delete, register through the finished name entry,
  copy, and a damaged record: no band, kanji right on every screen.  The
  speed window is clear of the message window.  The other screens match,
  sooner.
- Standard path from power-on: the band once (the oath scene, frame 1590
  in both).  CHR RAM is identical in the oath scene (frames 1650, 1700).
  - The menus and the oath start match.  After the oath the game runs
    on a shifted frame-counter phase.
  - The frame counter `$33` and the RNG (`$AC-$AF`) step once a frame.
    They first differ at frame 303, after the one upload.  The previous
    builds lost those steps on every boot screen's upload instead.
  - So the oath's later pages print a frame earlier, and 7 CHR bytes
    differ at frame 6200.
  - With a player at the menus the RNG state at the start of play
    depends on the player's timing anyway.
- The regression set: greeting, menu cycle, the battle and the title
  pixel-identical.  The standard path from frame 2000 differs as above
  (the new game's RNG).  The original build is byte-identical.

## The opening oath: a fixed split, no band (2026-11-14)

The user's direction: for the opening oath (b10_msg_128), instead of the
message-driven band, a fixed split at line 128 (the screen is black
around it, so no wait code).  Below it, a fixed kanji page at CHR `$3800`
replaces `$1800` (BG tiles `$80-$FF`), holding the 20 kanji
生月日異願同年死閻魔大王照覧誓逆者地獄落.  Every other 8x8 tile the
window needs is intact in page `$1000`.  No dynamic allocation.

**Checked first:**
- The oath's kana and frame tiles (`$12-$7A`) avoid the scene's borrowed
  font tiles (`$42-$5B`, its portraits).  So page `$1000` has all of them,
  as the user said.
- The scene's pattern writes all happen with rendering off (frames
  1579-1582: the portraits into `$1800-$1FFF` and `$1420-$15BF`).  Once it
  shows, the only pattern writes were the band's uploads and restores.

**How:**
- **The set:** `kanji_common.OATH_FIXED`, in the user's order.  The build
  fails if the oath shows a kanji outside it, or if it passes 32 kanji
  (R1's page).
- **Setup** (bank 13 `b13_k_oath`, in place of the `wait_vblank` after the
  portraits; rendering off): `TXF_OATH` writes the kanji to CHR
  `$3800 + 64k` (tiles 4k..4k+3 there, TL, BL, TR, BR), with R0 =
  `CHR_BAND_LO` for the writes.  Then `TXR_ON` = `TXR_SPLIT` (`$20`).
- **The split:**
  - Each NMI with rendering on (bank 26 `cvn_split`, first in
    `cvn_band_path`): R1 = `CHR_SCENE_HI` for the top, then the IRQ armed
    for line `SPLIT_LINE`.  Stage 0 reloads the counter in line 0.  There
    is no PPU-address force; `FLAG_ARMED` makes the hack NMI's arm a
    no-op.
  - The fixed bank's `irq_split` (on `irq_band`'s no-band branch, in
    `load_text_graphics`' gap, `$C6B6-$C6CC`): R1 = `CHR_BAND_LO`.
- **The message:** with `TXR_ON` = `$20` the overlay uses no band, no
  pool and no requests (`message_setup`, `page_start`).  `KANJI_EC` puts
  a kanji as its set's tiles `$80 + 4k` (`fix_put`, now over a set's
  entry range: the boot set, then the oath's, in `boot_fix.inc`).  Pages
  flip to a clear window, as on the band.
- **Teardown** (`b13_k_oathend`, in place of the scene's last `jmp
  ppu_bg_sprites_off`):
  - rendering off as before;
  - `TXF_OATHEND`: `TXR_ON` 0 first (a pending IRQ then switches
    nothing), the IRQ off, R1 = the scene page, no band kanji active;
  - the hack's block-write mirror (`FN_BLOCK_POST`) copies band-page
    tiles `$00-$4F` (the CHR the kanji took) from page 1.  A later band
    screen (history, events, endings: not on the measured paths) finds
    the font there.  (Removed with the band page, below: CHR `$3800`
    keeps the oath's kanji.)

**The line.**  The IRQ for line 128 landed in lines 127-129.  Row 15
(lines 120-127) still holds the portraits' bottom tiles (codes `$80+`):
black on the scene page, not on `$3800`.  A switch in line 127 showed a
row of dots under the right portrait.  `SPLIT_LINE` is 130: the switch
lands in lines 129-131 (735 of 735 frames on the standard path).  That is
inside rows 16-17 (lines 128-143), which show nothing on either page, and
13 lines above the window's border (line 144).

**Checked** (`out/test/opt/boot`, against the previous build):
- Standard path:
  - The band is never on (before: once, 729 switches).
  - R1 back to the scene page in vblank (lines 249-255) every frame.
  - No pattern write while the scene shows.
- Screens:
  - 418 of 421 oath shots match a shot of the previous run.  The text
    prints sooner without the uploads.
  - The other three: the window drawn a frame later at the start, and the
    town's first message 2 frames later.
- Costs, rendering off:
  - setup 54,870 cycles (frames 1583-1584);
  - teardown 58,975 (frames 2321-2323).
- The band page after the teardown:
  - all 128 tiles equal page 1;
  - against before the oath, only `$42-$5B` differ (the scene's borrowed
    tiles, which the band page mirrors as before).
- The scene now turns the NMI on ~2 frames later (the setup comes first).
  So the scheduler's RNG step (`read_input_state`, once a frame with the
  NMI on) and `$33` run 2 steps behind for frame-locked input.  With a
  player the RNG at any later point depends on when they press A anyway.
- The regression set: greeting, menu cycle, the battle and the title
  pixel-identical.  The standard path from frame 2000 differs as above.
  The original build is byte-identical.

## The band page removed (2026-11-14)

The user's order: no font copy into CHR `$3800` any more; the
message-driven band does not exist.  Its code is replaced by a small trap
that stops the game where such a band would have been turned on.  The
user plays the whole game, and each screen found gets its own tiles (as
the boot screens and the oath did).  On the measured paths no message uses
the band any more.

**The trap** (`kanji_overlay.asm` `band_trap`).  `message_setup` with
`TXR_ON` = 0 and no battle pool (`pool_decide`) used to turn the band on.
It now loads A = the message's text bank and X/Y = its text address, then
runs a JAM (`$02`): the CPU stops.  In Mesen's debugger, read A, X and Y,
then:

    python tools/band_trap.py A=12 X=57 Y=9C

That prints the label (`message_map.json`) and the text.  Checked by
forcing the oath onto the old path (`TXR_ON` cleared before its message):
the CPU stops at `$BB88` with A = `$12`, X/Y = `$57`/`$9C`, which is
b10_msg_126-128's text.

**Removed:**
- **Overlay:** the band branch of `message_setup` (`REQ_SYNC`, the active
  set), `clean_kana`, the keep / clean lists of `page_start`, `KANJI_EC`'s
  per-entry band tiles and uploads, `entry_bit`, `release_all`, and
  `overlay_entry`'s band test.  Pool pages and the fixed sets are as
  before.  1,907 -> 1,566 bytes.
- **Hack bank** (`hack.asm`, 2,056 -> 828 lines, 3,530 -> 1,465 bytes):
  - stale tracking (`queue_scan`'s marks, `mark_range`, `mark_stale`,
    `KANJI_STALE`), the restores (`restore_next`, `restore_tile`,
    `pick_restore`, `advance_hi`), the queue replay, the window probe and
    `nt_check` / `nt_rescan`;
  - page-2 selection (`wr_reg1`, `set_page`, `scene_page_now`,
    `FLAG_PAGE2`) and the band IRQ arm (`irq_arm0`);
  - `mark_upload`, the epilogue's band reset (`nmi_ef31` is an `rts`);
  - the block writer's mirror: `fn_block_post` only disarms the pool when
    the game writes its tiles.
- **What the hack bank still does:** the battle pool's uploads and check
  (`REQ_UPLOAD`..`REQ_MARK`; light, bulk and main-thread units, as
  before), and the pool guard on the game's queue CHR entries and CHR
  animation (`pool_scan`, `anim_check`).  A band request still in a save
  state from an earlier build is dropped.
- **Bank 26:** the band's force and arm in `cvn_band_path` (only the
  oath's split is left there), and the band test in `nmi_cvg`.
- **Fixed bank:** `irq_band`'s R0 switch: stage 0 of the IRQ is the oath's
  `irq_split` alone.
- **Attract bank:** `att_title_set`'s font copy into page 2 (`att_r0`).
- **The oath's teardown:** the copy back into `$3800`.
- **Unchanged:** the RAM image (byte-identical: old save states load), and
  the compiler's metadata (its band parts are just not read:
  DEBLOAT_TODO 1).

**Checked** (`out/test/opt`, against the previous build):
- Greeting, menu cycle, officer-switch battle (330 shots), title,
  level-up battle (158) and capture victory (111): pixel-identical.
- Boot flows (start with cancel, delete, register through the name entry,
  copy, a damaged record): every shot but two transition frames also in
  the previous run; no band.
- Oath: every shot in the previous run; the split in lines 129-131.
- The standard path differs after the oath only by timing: the teardown
  is 2 frames shorter, and screen loads no longer copy to page 2.
- The original build is byte-identical.

## Page breaks by design: `<NLNI>`, `<PAGENI>` (2026-11-14)

The user: rename `<NL2>` to `<NLNI>` and `<WAIT>` to `<PAGENI>`.  Make
them behave by their design instead of a patch that depends on context.

**The engine** (bank 15 `$D1A5-$D1CB`, `$D2C3`), read from the code:

| Code | Name | Waits | Next line |
|---|---|---|---|
| `$FA` | `<NL>` | no | indented one cell (`inc $5F`) |
| `$FB` | `<NLNI>` (was `<NL2>`) | no | column 0 |
| `$FC` | `<PAGE>` | yes | indented one cell |
| `$FD` | `<PAGENI>` (was `<WAIT>`) | yes | column 0 |

- `$5F` is consumed by the next line, even an empty one, and never
  carries over into the next message.
- In the original game neither page code clears the window: both wait,
  and the lines scroll at a 4th line.  So `<WAIT>` was always a page break
  without the indent.

**The kanji build until now:**
- `<PAGE>` cleared the window; `<WAIT>` did not.
- Lines piled up across waits.  In 19 messages a 4th line came: the
  engine's scroll, slow in map mode.
- The 2026-11-13 run-time patch (`map_lines`, `map_end4`, bank 26's
  `TXF_LOOK`) looked ahead and turned a line into a page break there.
- Also, the band-era page splits (`split_failing_page`) turned any line
  break into an indented `<PAGE>`, `<NL2>` included.  b11_msg_098's
  三代続いた呉の国の came out indented.

**Now:**
- **Both page codes are page breaks:**
  - the compiler splits page records at both (`split_pages`,
    `page_from_bytes`);
  - the overlay's `ctrl_store` advances the record and sets the page flag
    at `$FD` as at `$FC`;
  - `page_flip` clears the window after the wait.
  - The engine itself handles the indent.
  - In battle a page may still share the window when its kanji fit the
    pool (the original's scroll), for both.
- **A page split keeps the break's kind:** `<NL>` becomes `<PAGE>`,
  `<NLNI>` becomes `<PAGENI>`.  With the smaller page records, no split is
  needed any more (`split_pages` 6 -> 0); the mid-line fallback is counted
  (`fallback_splits`, 0).
- **Removed:** `map_lines` and `map_end4` (`$D1B7`, `$D1BA` and `$D1DE`
  hold the original bytes again; lint 76 -> 73 ranges), and `TXF_LOOK`
  (`TXF_MENUSET` / `_OATH` / `_OATHEND` are now 12-14).  The RAM image is
  unchanged.
- **Renamed everywhere:** the dtx sources (the original's too: its build is
  byte-identical), the r14 batches and the glossary, the tools, and
  decomp/text/README.md.  Older sections here keep the old names.
- `tools/scroll_scan.py` uses the new rule: 0 of 765 messages scroll.

**Checked** (against the previous build):
- The 19 messages that scrolled, injected into the save man's talk
  (converted state `s1_c.mss`): no scroll from the 4th line (`$D1BA`) or
  the end (`$D1DE`); a clear at each page break.
- After a `<PAGENI>` the next line starts at column 0 (b11_msg_044's
  「桂陽の…, b11_msg_098's 孫権は… and 三代…).  After a `<PAGE>` it is
  indented (今思えば…).
- Pixel-identical: greeting, menu cycle, officer-switch, level-up and
  capture battles, title, the standard path from frame 2000, and the oath.
- Boot flows: identical but for the copy flow's frame 800 (the menu
  border one scanline apart, as in every comparison).
- The original build is byte-identical.

## The message engine out of the text banks; no metadata (2026-11-14)

The user: the overlay should be gone from the text banks entirely, its
code merged into the new code banks, and every unnecessary band-era
metadata removed; without both, the text should fit 32 KiB, four
consecutive 8 KiB banks, a message never crossing a bank border.

**The layout:**
- **Text:** four 8 KiB chunks, the 8 KiB banks 36-39 (16 KiB banks 18-19,
  right after the kanji store), always read at R7 (`$A000-$BFFF`).
  `kanji_text.py` packs the 758 unique messages first-fit by decreasing
  size: 30,918 bytes, chunks 36-38 full to the byte, 1,850 bytes free in 39.
  Banks 20 and 21 are free.
- **The message engine** (`tools/asm/kanji_msg.asm`, the old overlay):
  1,471 bytes in hack bank 23's lower half, included by `hack.asm`; entry
  `MSG_ENTRY` (`$800F`, the jump table), the fixed bank's hooks at `$D28E`
  / `$D2C7` point into it.  The overlay was 1,540 bytes in a 2 KiB slot in
  each of four text banks.
- **The message bank** `MSG_BANK` = `$97` (`$80 | 23`, a number no bank
  has): while a message prints it is the current bank.
  - `main_prg` maps it as R6 = 46 (the hack bank's lower half: `2 * $97`
    without bit 8) and R7 = `KANJI_TEXT_CHUNK`.
  - So every "map the message bank again" goes through unchanged: the
    engine's `set_bank_b(text_window_x)` and `set_bank_current`, and the
    hack's `WAIT_TEXT`, `scroll_text`, `call_ui`, `call_hack`, `txr_call`.
  - `PRG_R7X` (the kanji store's R7 protocol) follows: `main_prg` clears it
    first for every bank, and sets it to the chunk just before R7 gets it,
    so an NMI anywhere restores what the main thread has.  `nmi_prg`'s R7
    range now covers 32-39 (store and text: the same instructions).
  - `main_prg` keeps its 63 cycles for every other bank (the original's
    timing: a 4-cycle change once moved a lag frame) and its 36 bytes (the
    routines after it keep their addresses); its end (`main_tail`, 24
    bytes) went into the gap at `$C6AC`.
- **Why not PRG mode 1** (`$C000` = R6, the user's first idea): the
  engine is entered from bank 62 code, both interrupt vectors reach bank
  62 within a few instructions, and mode 1 puts bank 62 at `$8000`, so the
  text could only live at `$A000` anyway.  Then R6 is free in mode 0.
- **The stub** (banks 10/11): `F8 <far_head> <chunk | $80 victory> <text
  addr>`, 6 bytes (was 8: no metadata pointer).  The trampoline stores the
  chunk, the victory flag (`MSG_WIN` in `KANJI_PAGES_LEFT` until the
  message's setup) and the address, keeping X (the engine's line-buffer
  index).
- **No metadata** (13.6 KiB before): a page's kanji table (`REG_LO/HI`
  0-15, first-appearance order, `KANJI_PAGE_N` = entries | names << 5) is
  built at run time.
  - Map mode: `page_find` adds each new kanji as the page prints.
  - The battle pool, which must know a page's slots before it starts:
    `scan_table` reads the page's text ahead (at the message's setup, at a
    page break, and for the window-continuing check at the entry), with
    the compiler's rules (both variants of a pick, names `$F4-$F7` and the
    tactic pick).
  - At a page break, `scan_content` decides the flip: a page with content
    (a cell, a kanji, an insertion, a call or a jump) flips the window
    after the wait; a page break right before the end does not (8
    messages), as the old page count did.  A jump counts: the old records
    gave the page after 「…<PAGE>」 before b10_msg_129's jump a record, so
    the window flipped there and the next message's first line kept the
    `<PAGE>`'s indent.
- **The compiler** (`kanji_text.py`, 1,417 -> 690 lines): the band-era tile
  planner is gone (reserved kana, scene borrow, menu contexts, tile
  assignment, relaxed retries).  `fit_tokens` splits a page only when it
  has more kanji than the table (16; at most 15 now, no split).  The ROM is
  byte-identical with and without the planner.

**Space:** 167.0 -> 186.8 KiB free (MEMORY_MAP.md); stubs 3,651 -> 2,739
bytes (bank 10) and 2,374 -> 1,788 (bank 11).

**Checked** (against the build before):
- Pixel-identical on 13 tests, 3,197 screenshots: greeting, menu cycle,
  officer-switch, level-up and capture battles (victory, reward window,
  capture prompt), title, the standard path from frame 2000, the oath and
  the five boot flows.  The one difference is the copy flow's frame 800,
  the menu border one scanline apart (it differs between earlier builds
  too).
- The RAM image and the original build are byte-identical.
- Seen on the way, the same in both builds: in the level-up battle the
  「は<CALL:D565=さくりゃく>を覚えた」 page shows 計 as its 言 half and 覚
  blank (frame 1700 of the r4/s2 run): the call's kanji tail and the
  page's kanji meet in the pool's slots.  Not fixed here.
