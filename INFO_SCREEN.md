# Character info screen: text rendering (survey, 2026-11-11)

The full-screen officer info screen: ぶしょう, then an officer.  It shows
the portrait, the name in kana and in kanji, and the stats (ぶりょく,
ちりょく, こうげき, ぶそうど, S.P, へいしすう) with bars.  It has a
そうび window and a さくりゃく window.  Measured on the kanji ROM
`5449ff00...` from the map path (`out/test/item1/clean.mss`, a town state
with the menus closed).  The tracer is `tools/lua/screen_trace.lua`; its
output and the dumps are in `out/test/cinfo/`.

## Code path

Bank 14 runs it.  The officers menu reaches `$84A2`, then
`b14_party_status_update` (`$84FE`):

| Step | Code | What it does |
|---|---|---|
| 1 | `b14_calc_party_stat`, `load_party_member_record` | the officer's data |
| 2 | `battle_intro_screen` (`$CED2`, fixed bank; also used by `b14_field_transition_a`) | window, fade, clear the nametables; `copy_to_vram` bank 9: tiles `$00-$0F` (digits, borders; the hack's block writer supplies them) and `$E0-$FE` (bars, S.P); `load_text_graphics` index 8 (palette) |
| 3 | `status_message` -> `text_load_page` | the portrait, tiles `$80-$A3`, through the VRAM queue (6 frames x 96 bytes) |
| 4 | `draw_string` (inline) | the portrait's nametable block |
| 5 | `text_init` `$1B` | name in kana |
| 6 | `text_init` `$08` | name in kanji: bank 1 glyphs through the CHR stream (`flush_palette` -> `write_vram_block` mode 2: read 8 bytes, write 8 bytes, so only plane 1 changes) into tiles `$10-$17` |
| 7 | `text_init` `$2D`, `$09` | stat labels, values, bars (`$F4` per 26 points, `$F3` for a half) |
| 8 | `draw_string` (inline) | へいしすう |
| 9 | `text_init` `$0B` | そうび window: item names from bank 12 (`draw_item_name`) |
| 10 | `text_init` `$0A` | さくりゃく window: strategy names from bank 12 (`draw_string_from_pointer`) |
| 11 | `jmp loc_D44C` | input loop |

Every nametable write goes through the general text engine (`text_init`,
the window line loop, `scroll_map`) and the VRAM queue: the same code the
map windows and the battle use.  The canvas hooks are passed through
here (not map mode).  What is specific to this screen is the bank-14
driver (steps 5-10: which windows, in which order) and the name stream.

## CHR layout (same as the battle screen)

- Font page `$1000-$17FF` (tiles `$00-$7F`): digits and borders (both
  planes set), kana in plane 0.  The info screen leaves the kana as the
  map left them.
- Scene page `$1800-$1FFF` (tiles `$80-$FF`): portrait `$80-$A3`; bars and
  S.P in `$E0-$FE`; `$A4-$DF` still holds the map's tiles.
- Palettes: P0 `0F 20 0F 20` shows plane 0, P1 `0F 0F 20 20` shows
  plane 1, P2 bars, P3 portrait.  The original game's kanji: name glyphs
  go into plane 1 of kana tiles and their 16x16 cells get P1.  On the info
  screen that is `$10-$17` (one name).  On the battle screen it is
  `$10-$4F` (16 kanji: the party and enemy names).
- No CHR register write while the screen is up (no split).

## Room for kanji without any CHR switch

On this screen:
- Plane 1 of font tiles `$18-$7F` is free: 104 quarter-glyphs (26 16x16
  kanji).  Each must sit on a 16x16 attribute cell with P1, so it starts
  on an even tile row and column.
- Scene tiles `$A4-$F2`, `$F5` and `$F9-$FF` are not shown: 87 tiles.
  With the same two-plane trick that is 174 quarter-glyphs (43 kanji).
  Plane-0 glyphs in P0 cells need no 16x16 alignment.
- The screen itself shows 89 distinct tiles.

The text on screen starts on even columns (labels column 10, windows
columns 4 and 18, name column 2), and lines are two tiles apart, so 16x16
kanji line up with the attribute grid.  Mixing 8-pixel kana and 16-pixel
kanji on one line breaks that alignment for plane-1 glyphs.

On exit (B) the game reloads the whole font page (the hack's font) and
the map's tile set (bank 4), so on the map path anything written into the
BG pattern tables while the screen is up is gone on return.  Not checked:
whether the screen can be opened from a battle, and what that exit
reloads.

# SITREP (2026-11-11): kanji on the info screen without CHR switching

Work starts after the compaction of 2026-11-11.  The plan below is the
user's; "Cross-reference" is what the code and the traces say about it
(kanji ROM `5449ff00...`, traces in `out/test/cinfo/`: `jt1`/`jt2` map
path, `jt4` battle path, dumps `info_230`, `bi_dump_260/470/600`, `bb_*`).

## Plan (user)

- Plane 1 of the font tiles `$10-$7F` gives 28 kanji slots (4 tiles each,
  shown through P1 cells, 16x16 aligned):
  - `$10-$1B`: the officer's name, up to 3 kanji, left to the original
    engine (`$A9` = `$10`).
  - `$1C-$4F`: the 13 fixed label kanji 武 力 知 攻 撃 装 度 兵 士 数 備
    策 略 (武力 知力 攻撃 武装度 兵士数 装備 策略; S.P stays).
  - `$50-$7F`: the first 2 kanji of each tactic line (every tactic starts
    with 2 kanji; at most 6 lines x 2 = 12 slots, fixed per line).  An
    officer without tactics: skip.
- Every other panel kanji goes to plane 0 of free scene tiles, in P0
  cells: equipment names (they may start with a single kanji) and the
  rest of each tactic (e.g. 計 after の).  Worst case per the user: 13
  distinct kanji in the 策略 panel, 9 in the 装備 panel.
- A kanji map in WRAM: reuse a kanji already in CHR instead of writing
  every occurrence.
- Two paths:
  - map -> info: overwrite `$E0-$EE` freely, no plane merge (the map
    reloads its tiles on exit).
  - battle -> info: on exit, rewrite plane 1 of every battle name kanji.
- Move the half-bar tile `$F3` to `$FC` to free one more 4-tile group.

## Cross-reference

Confirmed:
- Name kanji: `load_party_member_stats` `loc_D4C9` (fixed bank).  The
  officer record (`$F3`, bank 12): byte `$10` = per-kanji bank bits,
  `$11-$13` = up to 3 glyph indices (`$FF` ends).  Source: bank 1 or 2,
  `$8000 + index * 32`.  CHR stream (`flush_palette` ->
  `write_vram_block`) mode 2: `vram_put_run` with C set reads 8 bytes
  (plane 0 kept), then 8 bytes are written to plane 1.  Destination:
  bump pointer `$A9`, +4 tiles per kanji; it also writes the tile numbers
  into the line buffers `$0300`/`$0318`.
- The info screen sets `$A9` = `$10` (bank 14 `$8545`).
- Entering the info screen uploads `$E0-$FE` (bank 9, 496 bytes;
  `battle_intro_screen`).  Leaving it for the battle does not.  The
  content is the battle's own, so the upload is redundant on the battle
  path.  Battle CHR before the info screen and after it: all 256 BG tiles
  equal.
- `$E0-$EE` hold only plane 1.  `$EF-$FA` hold only plane 0.  `$FB`,
  `$FC`, `$FE` are blank; `$FD` is plane 1 only; `$FF` varies.  The info
  screen shows `$F3 $F4 $F6 $F7 $F8` from this block.  The battles show
  `$E0 $E1 $E2 $E8 $EA $EC $EE` (HP gauges).
- `$F3` is referenced once: bank 14 `$85CE` `lda #$F3` (the half bar;
  full bar `$F4` per 26 points).  `$FC` is not used as a tile in code.  The
  move = that immediate plus the two patterns in bank 9's `$1E00` block.

Corrections and new facts:
- **28 vs 30 name kanji: the original has no guard.**  Battle setup
  `$E09B` `lda #$10 / sta $A9`, then every name is streamed in order, no
  deduplication (兵士 x3 took 6 slots).  Kanji 29 and 30 would land on
  `$80-$87`: plane 1 of the portrait tiles.  The next portrait upload
  (full 2bpp) overwrites them, so those names would show portrait data.
- **Exit to battle**: bank 14 `$AA1A-$AA5E` (called from the battle; it
  runs the info screen through `$8518`).  Afterwards it sets `$A9` =
  `$10` and re-streams the names of battle slots 0 and 1 (`$D49F`,
  `$D4A1`), 4-6 kanji, which always cover `$10-$1B`.  So the original
  re-streams the first two party names, not "as many as the info officer
  had".  For the plan, every allocated slot must be re-streamed: record
  (glyph index, bank) per slot when the battle allocates, or replay the
  battle's allocation loop (`$E060-$E098`).
- **Exit to map** reloads `$1800-$1FEF` (tiles `$80-$FE`, bank 4 in the
  town, 2,032 bytes) and the whole font page `$00-$7F` (the hack's font
  writer).  `$FF` is not reloaded.
- **`$E0-$EE` plane 0 is not free on the battle path.**  The battle
  draws its gauges `$E0-$EE` with P2 = `0F 17 25 17`.  Plane 1 alone gives
  colour 2 (`$25`); a plane-0 bit turns a pixel into colour 1 or 3 (`$17`).
  Kanji written into plane 0 there must be cleared on the way back to the
  battle (zero 8 bytes per tile, or rerun the bank-9 `$1E00` upload,
  rendering off).
- **`$A4-$DF` on the battle path is the hack's battle pool** (revision 18,
  `POOL_FIRST`..`POOL_LAST`, 15 slots): battle-message kanji in plane 0,
  used once the hack has read the tiles back blank (`WINCOL_POOL_OK`), and
  restored to blank in later NMIs (`KANJI_STALE_HI`).  The battle never
  shows them otherwise (normal battle: 56 of 60 blank; a boss message
  used `$A4-$B7`).  The info screen sets `text_graphics_index` 8
  (= `POOL_SET`), so the hack treats it as the battle set.  If the info
  renderer uses `$A4-$DF` on the battle path, it must start after the
  hack's pending pool restores, and zero the tiles on exit.
- **Plane-0 room on the battle path without the pool**: `$E0-$FE` minus
  the 5 tiles the info screen shows = 26 tiles (27 with `$FF`), i.e. 6
  kanji.  That covers it only if the worst case (9 equipment kanji + 計 =
  10) shrinks through the kanji map.  The `$F3`->`$FC` move gains a group
  only if each kanji must use 4 consecutive tiles; if the renderer writes
  its own nametable cells, any 4 free tiles do.
- **Band page bookkeeping**: font tiles `$00-$7F` exist twice (page 1,
  and page 2 = the band page; `KANJI_STALE` marks the differences).  On
  the battle -> info entry the hack copied tile `$18` page 1 -> page 2
  (`restore_tile`).  A copy made while the info screen's plane-1 labels
  are in page 1 would leave them in page 2 after the revert.  That is
  invisible in the band (kana cells use P0, which ignores plane 1), but
  writes are best made after the hack's pending restores.
- **Not in the decomp as code**: bank 15 `$E000-$E370` (`data_E000`, the
  battle name setup) and bank 14 `$A800-$ABFF` (the battle-side wrapper
  at `$AA1A`).  Patching them needs disassembly first or hash-checked
  byte patches, as for the four-screen regions.
- **Window geometry**: 装備 has 3 interior lines (rows 20/22/24),
  策略 6 (rows 16-26); all text starts on even columns (labels 10,
  windows 4 and 18, name 2).  The two window titles sit in the top border
  rows (14 and 18, even).  へいしすう is on row 15 (odd): 兵士数 as 16x16
  needs rows 14-15.
- **Name lists**: `decomp/text/kanji_plan/item_table_kanji.txt` is an
  unreviewed machine plan (丹剣 for たんけん, 麦野の剣 for ばくやのけん);
  the tactic names (bank 12, `draw_string_from_pointer`) have no kanji
  list in the repo.  The user's counts (13 / 9, every tactic starts with
  2 kanji, items may have 1) are not yet checked against a reviewed list.
- **WRAM**: 141 bytes free at `$7F73-$7FFF` (canvas code installed).
  Enough for a panel kanji map (about 16 entries x 2 bytes) plus a
  battle-name record (28 x 2).

## Open questions for the user

1. Use the battle pool `$A4-$DF` on the battle path (with the pool
   coordination above), or stay inside `$E0-$FF`?
2. The source of truth for the item and tactic kanji names.
3. Does a 4-tile kanji have to be 4 consecutive tiles (then `$F3`->`$FC`
   matters)?

## Work order (after compaction)

1. Disassemble bank 15 `$E000-$E370` and bank 14 `$A800-$ABFF` (or
   hash-check the bytes to patch).
2. Path flag: the map entry runs `$84F8`/`$84FE`; the battle wrapper
   calls `$8518` directly.
3. Renderer for the info screen (hack bank), replacing the driver's
   window sequence (`$8531-$8578`): fixed label slots, tactic slots, the
   panel kanji map, plane-0 allocation.
4. Battle exit: re-stream all battle name slots (plane 1), clear what was
   written to `$E0-$EE` plane 0 (and the pool, if used).
5. Gates: battle -> info -> battle CHR equal (all 256 BG tiles, as the
   original); map -> info -> map; the stack/RAM gates.
