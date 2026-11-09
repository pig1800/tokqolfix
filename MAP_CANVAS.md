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
is in `out/test/canvas/`.  The decision is pending.  Implementation goes on a
new branch.

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

The code can normalise A12, but the CPU cannot see the frame parity.  Frames
that queue more than 40 bytes, which includes the window-open frames, arm
late and land between -4 and +6.

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
