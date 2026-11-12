# Map-mode kanji canvas: assessment (2026-11-09)

The user's scheme was assessed before any code was written.  It has five
parts:
- a 4-screen ROM;
- a dialogue canvas in off-screen nametable space;
- kanji in a private 2 KiB page shown through R1 (tiles `$80-$FF`);
- the map tiles in the flanking columns remapped into that page from `$FE`
  down;
- two scanline IRQs per frame.

Every figure below was measured on the build of 2026-11-09.  The probes are
`tools/lua/canvas_survey.lua` and `tools/lua/irq_precision.lua`; their output
is in `out/test/canvas/`.  Implementation goes on a new branch.

## User direction (2026-11-09, second round)

- Go 4-screen.  Patch the vertical scroll engine so that it works like the
  horizontal one: a 60-row ring, with two buffer rows written after each
  move.  The canvas then sits at +30 rows (address EOR `$0800`), clear of
  both buffers, so no tile recovery is needed.  The 2-screen alternative
  would have to re-render the two horizontal buffer blocks after each window.
- The splits must be exact (see "IRQ landing").
- Scope the dialogue panel path first, with less code, fewer cycles and less
  memory.  Menus come later; the user is investigating them.

The vertical engine touches these places in bank 15:
- the walking code's wrap at 240 (`$F3B2-$F3C9`);
- `cursor_add_x` (15-row wrap);
- `set_scroll_from_cursor`;
- `tile_address`;
- `scroll_map` (row writes);
- the NMI's scroll write and the PPUCTRL vertical-nametable bit.

Our own row code (`KANJI_WIN_ROW`, the IRQ arm modulo 240) changes too.

## Measured facts

### Mirroring

The game uses vertical mirroring:
- the original MMC1 control is `$0E`;
- our MMC3 reset writes `$A000 = 0`.

So the map is 64x30 tiles: `$2000` and `$2400` sit side by side, and Y wraps
at 240 inside one table.  Over three runs (standard path, overworld, village)
there were 0 writes to `$2800-$2FFF`.

A 4-screen board breaks every map screen with `scroll_y` other than 0.  At the
wrap, the PPU moves on to `$2800`/`$2C00`, which nothing writes.  The measured
`scroll_y` values were `$A0`, `$D0`, `$20`, `$50` and `$60`.

To use 4-screen anyway, one of these is needed:
- every nametable write mirrored to +`$800`, which doubles the vblank nametable
  traffic;
- a third raster split at the wrap line in every map frame.

"TxSROM" is mapper 118, where CHR A17 drives the nametable select.  It is not a
4-screen board.  The MMC3 4-screen boards are TR1ROM and TVROM: mapper 4 with
header flag 6 bit 3.

### Free nametable space already exists

The other horizontal half is free (visible address EOR `$0400`):
- **Same rows, same hscroll.**  The canvas needs no change to the vertical
  scroll.
- **Horizontal scrolling.**  When the camera moves sideways, the game writes
  only the two columns entering view, each a full 30-row column
  (`2480v26 2400v4`).
- **Vertical scrolling.**  Row writes cover 36 cells.
- **While stationary.**  Nothing touches the off-screen columns, so canvas
  leftovers are overwritten before they can scroll into view.

### The split itself

A `$2000` write that only toggles the nametable-X bit takes effect at the next
scanline, because the PPU copies t's horizontal bits to v at dot 257.  The
write may come anywhere in the previous line.  It needs no `$2006`/`$2005`
sequence, and fine X and Y are untouched.

R1, however, switches mid-line.  Its write has to land in hblank (dots 257-320
of the line before) to avoid one garbled line.  That costs a delay of about 90
cycles in the IRQ handler.

### Window geometry in map mode

- **Position.**  The window is at screen rows 18-27 and columns 2-21 in every
  map scene seen (town, village, overworld).
- **Scroll alignment.**  `scroll_x` and `scroll_y` are always multiples of 16,
  so attribute quadrants align.  When `scroll_x` is 16 mod 32, the attribute
  bytes at the half boundary are shared with visible columns and need a
  read-modify-write.
- **Tiles.**  The window frame, kana and menus use tiles below `$80`.  Map
  tiles are `$80` and up.
- **Drawing pace.**  The window opens 2 rows per frame over 5 frames (20
  cells per row plus 6 attribute bytes per row pair) and is erased by a
  2-rows-per-frame redraw.

### Budget

**Kanji.**  At most 16 kanji occurrences on any page, counted from the r14
dtx.  That is 64 tiles, `$80-$BF`.

**Flank tiles** (unique tiles `$80` and up in columns 0-1 and 22-31, rows
18-27):

| Scene | Unique tiles |
|---|---|
| Town | 11 |
| Village | 10 |
| Overworld forest | 3 |

`$C0-$FE` holds 63.

### Water

Tile `$FF` is the only animated BG tile seen in map mode:
- it is an ordinary VRAM-queue entry from `flush_vram_queue` (`$D9E4`), 16
  bytes at `$1FF0`;
- it is written every 16 frames in the village.

Because R1 shows the scene page in vblank, the kanji page's copy of `$FF` must
be replayed from the queue.

### Menus beside the window

The partner shop draws a submenu at columns 22-31, rows 18-27, while its
message is shown.  Any nametable write into the band rows while the canvas is
on must therefore reach the canvas, not only the dialogue routine's writes.
When such a menu closes, the map it uncovers may need tiles that were not
captured at setup.

### IRQ landing (Mesen, 3,418 IRQs armed in vblank)

The landing line is fully determined by two inputs:
- the PPU address A12 at the arm (`a12`);
- the PPU frame parity (`par`, 0 or 1).

It lands at T + `a12` + (1 - `par`), with zero spread within each class:

| | `par` = 0 | `par` = 1 |
|---|---|---|
| `a12` = 0 | +1 | +0 |
| `a12` = 1 | +2 | +1 |

`tools/lua/mmc3_clock_trace.lua` follows the counter clock by clock.  It shows
one clock per line at about dot 325, plus two extra clocks:

- **Pre-render line, dot 5, when vblank ends with A12 low.**  This is the
  first BG fetch from `$1000` after a long low.  The code can control it by
  leaving the PPU address at a fixed value.
- **Line 0, dot 5, on every other frame.**  The game draws BG from `$1000` and
  sprites from `$0000`, the reverse of the usual MMC3 setup.  The A12 low time
  across the frame start is borderline, and the shorter pre-render line on odd
  frames tips it.  With sprites at `$1000` and BG at `$0000`, A12 rises once a
  line at dot 260 and never at the frame start.

There is a separate problem with the arm position.  Our NMI arms after its
own bookkeeping.  In frames where the game queues more than 40 bytes (window
drawing), that bookkeeping ends between lines 263.9 and 278.7, which is past
the pre-render clock.  Those frames therefore fall back to the IRQ's own
re-arm.

Both problems are in our code, not the MMC3.  Exact splits need two fixes:
- arm right after the game's last PPU write;
- remove the frame-start clock, either by rendering with sprites at `$1000`
  in canvas frames or by tracking frame parity.

## Options

### A. As specified, with 4-screen

Not recommended.  It needs mirrored nametable writes or a wrap split in every
map frame, on top of everything below.

### B. Off-screen half, exact splits

The canvas goes in the off-screen horizontal half, and the splits follow the
specification:
- the first at line 143;
- the second tracks the rows drawn while the window opens.

This needs exact-line IRQs.  That means arming before the vblank flush and
resolving the frame parity, for example with a sprite-0 hit as in revisions
up to 21a.  Without that, the split is one line wrong on alternate frames,
and up to 6 lines wrong in the open and close frames.

### C. Off-screen half, tolerant splits (recommended)

The split is shown only while the window is complete:
- it enters inside the top border row and leaves inside the bottom border row;
- the border rows are drawn identically in both halves;
- text goes only to the canvas;
- the window opens and closes as in the original, in the visible nametable.

An IRQ landing anywhere in a border row is invisible, as with today's band
switch.  The current arm is reused, with a second IRQ chained from the first.

### Common to B and C

- Capture every band-row write into the canvas: menus, prompts, and map
  restores under menus.
- Copy flank tiles into the kanji page.  Through `$2007` in vblank that costs
  about 200 cycles per tile; copying from the graphics set's PRG source is
  faster.
- Replay the `$FF` water tile.
- Read-modify-write the shared attribute bytes.
- Screens other than the map (history, oath, officer scenes) keep the current
  R0 band unless they are moved too.  Battle keeps the pool.  The history
  screen shows no tile `$80` or above in its band rows, so it could use the
  canvas directly.

## Progress (branch `map-canvas`)

### Step 1: exact IRQ (2026-11-09)

The two-stage arm:

1. **`irq_arm0`** (hack bank) runs right after the frame's last PPU access.
   - It sets v = `$1000` and restores t, so A12 is high when vblank ends.
   - It reloads the counter with 0.
   - It enables IRQs, so stage 0 can interrupt a long NMI tail.
2. **Stage 0** comes at the pre-render line's clock (dot ~325).  Its handler
   runs in line 0, after the odd-frame clock at dot 5, and reloads the
   counter for line T.
3. **Stage 1** comes at the clock of line T and switches in line T + 1.

Frames that flush more than 27 bytes, or that step the CHR animation, arm
first thing in `nmi_ef08`, because no unit or replay follows.  The others arm
after their unit or replay.

Space: `load_text_graphics`' palette mask loop moved into the hack bank
(`pal_copy`, `ltg_mask`), which freed 46 fixed-bank bytes.

**Results** (switch line minus T):

| Path | Switches | Exactly +1 |
|---|---|---|
| Standard | 3,605 | 3,577 |
| Shop | 647 | 639 |
| Village | 446 | 446 |
| Overworld | 448 | 448 |

All are exact on both frame parities, in light, CHR-animation and
window-drawing frames.  The exceptions (28 standard, 8 shop) are frames whose
game queue held 104 or more bytes (full-screen redraws).  There the game's
NMI ends at line 259.6, `irq_arm0` skips the address force (no PPU access
during rendering), and the switch comes one line later.

Before this step:
- light frames landed 0 to 2 lines after T, depending on parity and A12;
- heavy frames landed between -4 and +6.

**Gates:**

| Gate | Result |
|---|---|
| `vblank_deadline` (standard, battle, shop) | 0 hack accesses after the pre-render line start; the address force ends by pre-render dot 152 (allowed up to 180, because the PPU reloads v from t at dots 257 and 280-304) |
| `band_check` | +1: 3,575, +2: 28; 0 page-2 mismatches; 0 kana over kanji |
| `garble_run` (6 offsets) | 0 frames |
| `ram_gate` | 0 / 0 / 0; min SP `$17` |
| `taint_check` (normal battle, boss battle, play-test battle) | 0 / 0; min SP `$0F` / `$0F` / `$12` |

The probes are `tools/lua/irq_precision.lua` (environment variables
`IP_STATE`, `IP_PATH`, `IP_FRAMES`, `IP_OUT`) and
`tools/lua/vblank_deadline.lua`, which now reports the address force on its
own line.

### Step 2: four-screen nametables (2026-11-10)

The kanji ROM now has four-screen nametables (NES 2.0 flag 6 bit 3, as
TR1ROM / TVROM; Mesen gives `$2000-$2FFF` 4 KiB, unmirrored).  The map is a
64 x 60 ring: world metarow `15 * screen + row` sits in the vertical half
`screen & 1`, and PPUCTRL bit 1 follows the camera's top screen.  The other
vertical half (address EOR `$0800`) is free for the canvas: walking writes
only the visible rows and the entering row.

**Fixed-bank rewrites** (in place, original bytes checked by hash in
`kanji_build.py`, `FOURSCREEN_REGIONS`):

| Routine | Change |
|---|---|
| `cursor_to_ppu` `$D7E9` | address bit 11 = `cursor_y & 1` (shared `nt_bits`) |
| `set_scroll_from_cursor` `$D815` | PPUCTRL bits 0-1 from the camera's top-left metatile |
| walking scroll `$F3A3-$F3CA` | crossing the 240-line wrap toggles PPUCTRL bit 1 |
| `draw_tile_run` column wrap `$DAB9` | a column past row 29 goes on at row 0 of the other half |
| `draw_map_object` `$DAF2` | rows: into the drawn row's half; columns: both halves |
| `text_render_cell` `$DC0E` | a text cell's bottom tile below row 29: row 0 of the other half |
| battle shake (bank 14 `$ACBF` -> `battle_shake`) | PPUCTRL bit 1 while the screen is shifted up 3 lines |

The overlay's `window_geometry` stores the window corner's vertical half in
`KANJI_WIN_ROW` bit 6 (`WINROW_LOWER`); `probe_window`, the queue tracker
and `irq_arm0` work unchanged with it (`row >> 3 | $20` and `row * 8`).

**What the comparison found** (two-screen build vs four-screen build, same
input, `tools/lua/screen_digest.lua` + `tools/sd_compare.py`):

1. Text lines start at odd rows (corner + 1).  A window whose corner is at
   row 28 puts the first line's bottom tiles past row 29; the engine wrapped
   them to row 0 of the same table.  Kanji messages lost their bottom
   halves (and the band probe lost the window) until `text_render_cell` and
   `window_geometry` knew the other half.
2. The battle shake sets `scroll_y = $ED`: with four tables that wraps into
   the lower half.
3. Writing every attribute row to both halves slowed the full map redraw
   after a dialogue by up to 6 frames (the original's main thread already
   ends at line 228-240 there).  Rows now go to their own half only;
   columns (one per horizontal step) to both.

**Result**: the NTSC picture (lines 8-231) is pixel-identical on every path
(standard boot path, village, overworld with screen crossings, town, shop,
partner shop, normal and boss battles).  The only differences are in the
overscan lines during vertical steps and the battle shake, where the
four-screen build shows the right rows.  Drawing pace: identical (one
frame once in the standard path).

**Gates** (kanji ROM `ce4709c7...`; the original 256 KiB build is still
`40f19e17...`; states converted into `out/user/m4/`):

| Gate | Result |
|---|---|
| A/B picture, 9 paths | identical in lines 8-231; drawing pace equal |
| `band_check` | +1: 3,576, +2: 28; 0 page-2 mismatches; 0 kana over kanji |
| `garble_run` (6 offsets) | 0 frames |
| `garble_state` battle, boss, play-test battle, lv, sv | 0 frames |
| `garble_state` partner shop n1, p1-p4 | the save state's opening episode only (42-123 frames), identical on the two-screen build with the committed gate |
| `vblank_deadline` std, bt, nb, bb | 0 |
| `ram_gate` | 0 / 0 / 0, min SP `$17` |
| `taint_check` bt, nb, bb | 0 / 0, min SP `$12` / `$0F` / `$0F` |
| `zp_check`, `mask_restore`, `palette_check` | 0, 0, 0 wrong |
| `anim_timing` | scroll restore by line 259 |

The window and screen gates now address the 60-row ring; on a two-screen
build `garble_state` would report false "active_outside" cells (its window
and screen addresses fall in different mirrors), so they are for this
branch's builds only.

**Write-ahead rows (2026-11-10, second round).**  The kanji target keeps
two save records (user's call); the third record's 2 KiB of battery RAM
(`$7800-$7FFF`) is map engine RAM.  Bank 13's title menus loop over
`SAVE_SLOTS` records (2 in the kanji target, 3 in the original build):
with both records in use the menu offers continue and erase, with one it
offers continue, new, erase and copy (new: record 2 only), with none only
new (records 1 and 2).

- The attribute shadow is 256 bytes at `MAP_ATTR` (`$7800`): index =
  lower half << 7 | attribute row << 4 | right table << 3 | attribute
  column (`tile_address`, rewritten in place).  `draw_map_object` writes
  every byte to its own table in one pass; columns run through all 16
  attribute rows.  `$0780-$07FF` (the old shadow) is free internal RAM.
- Vertical steps write the row one block beyond the destination (8 rows
  above / below the player instead of 7), as the horizontal steps write
  their column.  Columns are 17 metatiles (34 tiles, 10 attribute rows),
  so the buffer rows stay valid after horizontal steps.
- Full redraws draw 17 rows (`redraw_start`): `render_map_column`
  (rendering off) costs nothing; `text_draw_screen`, the redraw after a
  dialogue, takes 17 frames instead of 15.
- **The two other redraws (fix, 2026-11-13; the user's state: an indoor
  room transfer).**
  - `sub_CE2D` is bank 14's room transfer with `$90` bit 4 ($BDF8): the new
    room is wiped in from the right over the shown one, one metatile column
    a frame, 18 columns, with the scroll unchanged.
  - Its runs were the original's 30 tiles from buffer offsets 0 and `$1E`.
    With 17-metatile columns the right tile column came out two metarows
    low: every other tile column was shifted.
  - 34-tile runs would make the queue 120 bytes a frame (112 before). The
    game's flush then ends at line 260.9 and the NMI turns rendering on
    after the pre-render line's vertical copy, so those frames show the
    picture shifted (tried: `k22t`).
  - **Now:**
    - The UI bank (`UIF_WIPE`) first moves the text position one row down,
      so `draw_party_status` starts at the camera's top row.
    - The loop is the original's, with the right column at `$22`: the
      camera's 15 rows and the attribute column (10 rows from the top row).
      That is 112 bytes and the original's main-thread work a frame. An
      earlier version did the loop in the UI bank, and its bank switches
      cost 3-8 lines a column and 4 lag frames.
    - Then `UIF_WIPE_ROWS` draws the two buffer rows as walking steps do
      (109 bytes, one frame each) and puts the text position back.
      `draw_party_status`/`window` and the waits go through fixed-bank
      trampolines with bank 14 mapped, as under the original.
  - The transfer ends 3 frames later than before (the user's state: frame
    33, was 30).
  - The final nametables equal a 34-tile wipe's, apart from 5 attribute
    bytes of the row below the bottom buffer row. That row is outside the
    live 17; this build writes the new room's attributes there.
  - `sub_CE7A` (bank 14 $81AE: an event's map change redraws the player's
    metarow, 10 metatiles) drew the row above: it now moves the text
    position 9 rows and back 8 (was 8 and 7). It is compacted in place to
    hold the wipe's second trampoline.

`tools/lua/edge_check.lua` follows every map cell on screen during a step
(all 240 lines) and compares it with the same world cell at rest before
and after the step:

| Build | Overworld (screen crossings) | Village | Town |
|---|---|---|---|
| original two-screen | 6,722 overscan + 802 picture cells wrong | 512 + 22 | - |
| step 2 (original timing) | 2,139 + 458 | - | - |
| write-ahead | 0 + 0 | 0 + 0 | 0 + 0 |

A/B against the step-2 build from the user's battery save (record 1,
town walks, a dialogue): identical picture apart from the step-2 build's
one-frame flashes during vertical steps; the redraw after the dialogue 2
frames later.  Gates as above (band_check +1: 3,592 / +2: 28, 0 mismatches;
garble_run 0; deadline 0; taint 0; ram_gate 0 / 0 / 0 with min SP `$16`;
zp, mask, palette 0).  Converted save states have no valid buffer rows
until the next full redraw (map change); play from the battery save is
right from the start.

The build's "first 256 KiB stays original" check now allows banks 13 and
14, and `bank15_lint.py` reads the rewritten ranges from `kanji_build.py`
(the step-2 commit `a5afe81` failed that check on bank 14 unnoticed: the
ROM was written, the lint was not run).

**Tools**: `tools/mss_4screen.py` converts two-screen MMC3 states (into
`out/user/m4/`); `tools/run_gates.sh` takes `GSTATES=`; the gates compute
screen addresses on the 60-row ring (`$177 & $1F`, bit 6 = lower half).
`tools/ref_scan.py` lists absolute references into address ranges across
the 16 original banks.

### Step 3a: the dialogue canvas, kanji still on the band (2026-11-10)

A text window whose rows reach the band (screen rows 18-27, metarows 9-13
below the camera's top) in map mode is drawn into the other vertical half
(address EOR `$0800`: the same in-half rows), and a split shows it from
line 144.  The visible half keeps the map: nothing writes it while the
canvas is up, so the window closes without any tile recovery.  Kanji stay
on the old band page (R0, switched by the canvas's first IRQ); step 3b
moves them into the canvas page (R1).

**What decides "canvas"**: a `text_init` window row at the band's top
metarow in map mode (`input_buttons` bit 7 clear: player-relative
windows; the title, battle and scenes place windows at fixed positions)
turns the redirect on; from then on every band-row address `cursor_to_ppu`
computes (window rows, text cells, prompts, the line scroll, side menus
opened beside the message) goes to the canvas.  The command menu at rows
2-13 stays in the visible half.  `redraw_start` (the redraw that closes
every dialogue) turns the redirect off; each map row it redraws in the
band ends the canvas above that row, so the window still vanishes
bottom-up as in the original.

**Each new canvas metarow** (in place of `scroll_map`) is queued whole:
two 32-cell rows (the window's cells from the row buffer, the map beside
it from the game's own metatile lookup `draw_map_area`) and the screen
row's attribute bytes.  The window's palette bits go to the canvas half's
attribute shadow (index EOR `$80`); the visible half's pair of quadrants
for that metarow is mirrored into the canvas half first, the other pair
kept (the canvas metarow next to it can be a live buffer row).  Pace: the
window opens one metarow per frame, as the original.

**The split** (`cv_irq`): stage 0 (line 0) reloads the counter for line
142; stage 1 (line 143) writes `$2006` = the canvas's row 18 (fine Y 0)
in hblank (dots 257-320) and reloads for the canvas's end; stage 2 writes
`$2006` = the map row below it.  Stage 0 also computes the two addresses
when the canvas's height changed.  The height (`CV_ROWS`) follows the
main thread's `CV_PEND` in the NMI: growing once the queue is empty,
shrinking once the flush passed the closing redraw's row.

**Arm timing.**  The window frames carry 76-90 queued bytes (55 in the
original); the hack's NMI then ran past vblank and the stages landed 1-2
lines off.  The PPU-address force (v = `$1000`) and, in long frames (over
27 bytes or a CHR-animation step: no hack unit follows), the canvas's arm
now come in `cv_nmi`, called first thing in the normal-frame NMI path
(`ef08_gate`, after the game's `nmi_mode` branch, so the title's own
raster splits keep their timing); light frames arm after the hack's own
PPU work, as the band did.  Over 103 bytes no force (it would end past
the pre-render line's dot 256); the counter reload still comes first.
The replay of CHR entries the game flushed while the band page was
selected now skips tiles `$80-$FF` (R1 is always the scene page), which
removes the town's 16-frame tile replay from band and canvas frames.

**Code**: the canvas code runs from battery RAM at `$7900` (the third
save record's, 1,148 bytes; `canvas_ram.asm`, stored in PRG bank 27 at
`$A000`, copied by `hack_init` from the reset vector before
`reset_init`'s PPU warm-up, which absorbs the copy).  It must stay mapped
while it calls `draw_map_area`, which maps banks 9/12/13 over
`$8000-$BFFF`.  State in internal RAM `$0780-$07FF` (the old attribute
shadow).  Fixed-bank patches: `$CA59` (`jsr cv_ti`), `$CB1B`/`$CB80`
(`jsr cv_sm`), `cursor_to_ppu`'s end (`jmp cv_ctp`), `irq_handler`
(`jmp cv_irq`), `ef08_gate` (`jsr cv_nmi`), `redraw_start` (`lsr
CV_REDIR`), the reset vector's `jmp` (`early_reset`); `irq_stage0`
(`$C489-$C49D`) is free.  The build now rejects fixed-bank blocks that
overlap (a 3-byte `jmp` in `cursor_to_ppu` once ran one byte into
`set_scroll_from_cursor`).

**Results** (`tools/lua/canvas_check.lua`: per canvas frame, the stages'
second `$2006` write line and dot, and every canvas cell with a map tile
against the visible half's cell, tile and palette):

| Path | Canvas frames | Splits off | Map cells | Unlike the map |
|---|---|---|---|---|
| town, battery save, two dialogues | 215 | 0 | 24,360 | 0 |
| village (`u_rom_kanji_1`) | 106 | 0 | 12,000 | 0 |
| overworld (`u_rom_kanji_11`) | 152 | 0 | 16,704 | 0 |
| `r16b` | 76 | 0 | 8,352 | 0 |
| shop (`shop_k`, n1) | 493 | 0 | 23,112 | 0 |
| standard gate path (6,000 frames) | 2,423 | 0 | 284,736 | 0 |

No window tile shows in the visible half's band rows on any path; every
`cv_nmi` force ends by pre-render dot 236 and every canvas counter
reload comes before the pre-render clock.

**Gates** (kanji ROM `e545608b...`; original still `40f19e17...`; states
`out/user/m5/`):

| Gate | Result |
|---|---|
| `canvas_check` (above) | 0 off, 0 missing, 0 flank mismatches |
| A/B against step 2b, battery save | boot and dialogue pixel-identical; the close 1 frame later |
| `band_check` (non-canvas band frames) | +1: 1,246, +2: 8; 0 page-2 mismatches; 0 kana over kanji |
| `garble_run` (6 offsets) | 0 episodes |
| `garble_state` bb, bt, nb, lv, sv | 0 frames |
| `garble_state` partner shop n1, p1-p4 | 42 / 85 / 44 / 90 / 123: the state's opening episode, as step 2b (42 / 85 / 43 / 90 / 123) |
| `vblank_deadline` standard, bt, nb, bb | 0 |
| `taint_check` bb, bt, nb | 0 / 0, min SP `$0F` / `$12` / `$0F` |
| `ram_gate` | 0 / 0 / 0, min SP `$14` (the RAM code is hack code; `$7800-$7FFF` and `$0780-$07FF` are hack RAM) |
| `zp_check`, `mask_restore`, `palette_check` | 0, 0, 0 wrong |

A/B against step 2b from the battery save (town walk, a dialogue, more
walking): the boot and the whole dialogue are pixel-identical; the
closing redraw shows the same pictures 1-2 frames later (its rows end 2
lines before vblank in the original, and the splits cost ~4 lines of CPU
per frame), and everything after is shifted by those frames.

States for this build: `python -I tools/mss_canvas.py <m4 state> <out>`
installs the build's RAM code and clears the canvas state (`out/user/m5/`;
redo after every build: the RAM code moves).

### Step 3a play-test fixes (2026-11-10)

Three glitches from the user's play-test, reproduced from their save
states (`rom_kanji_1`: a battle, `rom_kanji_2`: before the はい that
persuades an officer to join):

1. **Battle: the picture one line up for a frame** (when a message box
   goes).  `cv_nmi` forced the PPU address (v = `$1000`) in every long
   frame, canvas or not.  Battle NMIs run longer than the map's for the
   same flush size; the force's second `$2006` write landed at pre-render
   dots 281-313, during or after the vertical copy, and the frame started
   from v = `$1000`: fine Y 1.  Step 2b forced only with the band shown.
   Now the force comes only when a split follows (`CV_ROWS | CV_PEND |
   KANJI_BAND`); battles and scenes never force.
2. **Battle shake: the old map in the top 3 lines.**  The battle clears
   `$2000` and `$2400` with the game's fill (`set_ppu_scroll`, `$C2AB`);
   on the original's mirrored VRAM that also cleared `$2800`/`$2C00`.
   With four screens the twins kept the map, and the shake's `scroll_y =
   $ED` shows the lower twin's row 29 in the top 3 lines.  The fill now
   writes both twins (`cv_fill`, RAM), unrolled: both tables take ~9.4k
   cycles against the original's ~9.8k for one, so screens still set up
   at the original's pace (the A/B boot is frame-identical; a plain
   second fill made it one frame late).
3. **Persuasion: a few frames of a scrolled picture.**  The officer
   joining streams sprite tiles (`flush_palette`: 4 tiles per frame,
   `($39)` to `$0100+`).  The game's step ends at line 260 and its NMI
   goes on (scroll, PPUMASK, task timers) to `ef08_gate` in line 0, so
   `cv_nmi`'s force wrote `$2006` in lines 0-1, mid-picture.  The force
   now comes from `cv_stream`, the step's tail (`c343_hook`'s NMI path
   jumps there), right after the game's last PPU data write, followed by
   the counter reload and `cv_nmi`'s bookkeeping with IRQs enabled, so
   stage 0 still comes at the pre-render clock; `ef08_gate`'s call then
   returns at once.  That work would push the game's PPUMASK store (it
   turns rendering back on after the step) past pre-render dot 257 and
   lose the frame's vertical copy, so in map mode `cv_stream` also runs
   the step's plain-tile copy itself in one unrolled loop: ~650 cycles
   less, and rendering is back on in line 257 instead of 260 (pre-render
   dot 139 in the worst frame before).  Other stream modes, and every
   non-map NMI (the title's cycle-timed raster), keep the game's routine.

Also: the band alone (no canvas) is now armed by `cv_nmi` / `cv_stream`
right after the force in long and stream frames (as `irq_arm0` would,
which `FLAG_ARMED` then makes a no-op); after 92-byte flushes the hack
NMI's arm came past the pre-render clock (switches 2-3 lines into the
border row).  The map-mode check (`input_buttons` bit 7) moved after the
arm, so after a flush of more than `CV_FORCE_MAX` bytes the canvas
reloads at pre-render dot ~269 (step 3a: ~287; the clock is at ~325).

**Code**: RAM code 1,639 bytes, 7 pages (`$7900-$7FFF`, the rest of the
freed save record; the reset copy is still absorbed by the PPU warm-up);
fixed bank: `$C2AB` `jmp cv_fill`, `c343_hook`'s NMI path `jmp
cv_stream`; `$C489-$C49D` stays free.  `tools/mss_canvas.py --keep`
installs the RAM code into a canvas build's state without clearing the
canvas state (a state saved with a canvas up).

**Gates** (kanji ROM `cc0afb33...`; original still `40f19e17...`; states
`out/user/m5/` regenerated; the user's two states with `--keep`):

| Gate | Result |
|---|---|
| user's battle state, 3,300 frames of fighting | no 1-line jumps, no hack PPU write in the picture |
| battle from `r17_pre_battle_normal` | `$2800`/`$2C00` blank after the setup; 48 shake frames, the top 3 lines blank |
| user's persuasion state | splits in lines 143/223 on every frame; the stream frames' only change is the cursor |
| `canvas_check` std, town, village, overworld, r16b, shop n1, persuasion | 0 off, 0 missing, 0 flank mismatches; no force or reload late (persuasion: 18 stream-path forces) |
| A/B against step 3a, battery save, 3,400 frames | picture identical (lines 8-231); the twins differ while rendering is off (town load, frames 626-648) |
| `band_check` | +1: 1,254 (step 3a: +1: 1,246, +2: 8); 0 mismatches; 0 kana over kanji |
| `garble_run` (6 offsets) | 0 episodes |
| `garble_state` bb, bt, nb, lv, sv | 0 frames |
| `garble_state` partner shop n1, p1-p4 | 42 / 85 / 44 / 90 / 123 (the state's opening episode, as before) |
| `vblank_deadline` standard, bt, nb, bb | 0 |
| `taint_check` bb, bt, nb | 0 / 0, min SP `$0F` / `$12` / `$0F` (the RAM fill and the stream copy are game code for the gates) |
| `ram_gate` | 0 / 0 / 0, min SP `$14` |
| `zp_check`, `mask_restore`, `palette_check` | 0, 0, 0 wrong |

A state saved by an earlier build carries that build's RAM code in its
battery RAM: convert it (`tools/mss_canvas.py <in> <out> --keep`) before
loading it on this build.

### Item-menu sub-window fix (2026-11-11)

**Report**: menu, どうぐ, a character, an item: the sub-window (つかう / わたす /
そうび / すてる) did not appear; the screen showed stale canvas rows and junk
columns that depended on old nametable contents.

**Cause**: a queue overrun.  A new canvas metarow (`cv_sm` -> `cv_flanks`)
queues 91 bytes: two 32-cell rows and the attribute run.  The original's
window rows for the same line are 20-60 bytes.  The game's text loop yields
after every line only for windows 13 or more cells wide (`loc_CB24`);
narrower windows draw two or three lines per yield.  The sub-window drew
three metarows between flushes, 277 bytes in the 256-byte queue at `$0400`.
The write position lapped the read position, the next flush parsed data
as entries (a 10-byte write at `$320A`, a 96-byte one at `$3000`), and the
window's rows never arrived.  The dialogue is 13 or more cells wide, so it
never hit this.

**Fix**: `cv_sm` checks the queue before a new metarow.  With `CV_QWAIT`
(32) or more bytes already queued it calls `wait_vblank` first, the game's
own yield, as at `loc_CB3B`.  So there is one metarow per flush, as in the
dialogue.  A narrow window in the canvas now opens one line per frame
instead of two or three.  On the item path the queue peaks at 95 bytes;
each flush is 91-95 bytes.  The wait runs at SP `$2C` (the menu task's
stack, `$0100-$0130`); the path's minimum SP is `$16`, as before.

**Gates** (kanji ROM `5449ff00...`; original still `40f19e17...`; states in
`out/user/m5/` regenerated): `canvas_check` on std, town, village,
overworld, r16b, shop n1 and persuasion, plus the item path (both
sub-windows, from a state with the menus closed): 0 splits off, 0 missing,
0 flank mismatches, no force or reload late.  A/B against `cc0afb33` over
3,400 frames of boot, town and dialogue: picture identical (the dialogue
never waits).  `band_check` +1: 1,254; `garble_run` 0; `garble_state` bb,
bt, nb, lv, sv 0, shop n1 and p1-p4 42 / 85 / 44 / 90 / 123 (as before);
`vblank_deadline` 0; `taint_check` 0 / 0, min SP `$0F` / `$12` / `$0F`;
`ram_gate` 0 / 0 / 0, min SP `$14` (rerun alone; it crashes when too many
Mesen instances run at once); `zp_check`, `mask_restore`,
`palette_check` 0.

## User direction (2026-11-11): one text renderer, not per-window splits

The user inspected the whole game.  Menu boxes, menu sub-boxes, dialogues,
selections, and the ration and cold-box windows all overlap and mix on
screen.  So the scheme of one scanline split per window (the band, the
dialogue canvas) is to be dropped.  What's needed is one unified text
rendering routine that every kind of box goes through.  A raster split may
still be needed, but only because the kanji on screen can outgrow the font
buffer (CHR space), not as the way windows are drawn.  Step 3b as planned
(a kanji page for the canvas) is on hold.  The user has other work queued
first.
