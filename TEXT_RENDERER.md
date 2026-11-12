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

Commits `a2c501a` and the follow-up.  The original build is still
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
| Command window | the finished window pixel-identical to the previous build (`a1cf5e6`); complete at frame 922 against 919, drawn over 8 frames (row by row, each row waiting for its new glyphs) where the previous build showed it at once |
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
| Boot, logo, title menu, history window (frames 11-650) | pixel-identical to `a1cf5e6` |
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
| New game, story scenes (frames 20-2340) | pixel-identical to `a1cf5e6` |
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
| Boot, logo, title, history (frames 11-650) | pixel-identical to `a1cf5e6` |
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
  - the battle's prisoner window `$21`.

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

**The fixed set.**  17 kanji, from `kanji_build.build_txr_ui`:
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
