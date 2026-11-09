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

**Not done: buffer rows.**  Writing the vertical row one block ahead (like
the horizontal columns) keeps 17 metarows live.  The game's attribute
shadow (`$0780-$07FF`, 128 bytes) covers a 30-row ring; with 17 live rows
two pairs of rows share shadow bytes, so a 256-byte shadow is needed.
Internal RAM has no free 128 bytes (`$0700-$077F` is the sound engine's,
`$0100-$01FF` the task stacks, text rows and hack state), and WRAM
`$6000-$67FF` is the game state that save/load copy whole to the slots at
`$6800/$7000/$7800`; its unused-looking gaps are entries of 256-entry
tables (`$6400`, `$6600`, `$6700/$6780`).  So vertical steps keep the
original timing (the entering row is written in frames 4-6 of the step).

**Tools**: `tools/mss_4screen.py` converts two-screen MMC3 states (into
`out/user/m4/`); `tools/run_gates.sh` takes `GSTATES=`; the gates compute
screen addresses on the 60-row ring (`$177 & $1F`, bit 6 = lower half).
`tools/ref_scan.py` lists absolute references into address ranges across
the 16 original banks.
