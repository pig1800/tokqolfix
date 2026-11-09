# Changelog

## 2026-11-09 — revision 21: MMC3; the band switch is a scanline IRQ

Request: move the kanji target to MMC3 (the revision-17 assessment's
option 2: a line interrupt instead of the sprite-0 wait, finer CHR banks).

**21a, the mapper layer** (sprite-0 band kept, every gate against
revision 20):

- Mapper 4 (NES 2.0: 32 x 16 KiB PRG, 16 KiB CHR RAM, 8 KiB battery PRG
  RAM).  PRG mode 0: every 16 KiB game bank is two 8 KiB halves (R6/R7);
  bank 31 is the fixed bank at `$C000-$FFFF`.  The SUROM outer-bank
  register and the `$BFFF` marker are gone.
- The game's MMC1 routines are replaced in place: `set_bank_lock` keeps
  its `sta current_prg_bank` and jumps to `main_prg`,
  `restore_bank_after_nmi` (NMI only) jumps to `nmi_prg`; `mmc1_reset`,
  `mmc1_init` and the rest of both bodies are dead (no other reference in
  any code bank; the two byte patterns that point there are glyph and map
  data).  The reset writes every MMC3 register before it touches
  `$C000-$DFFF` (the power-on PRG mode is unknown).
- Bank-switch protocol: the MMC1 lock byte `$EB` (used only by the
  rewritten routines) is the bank-select shadow `MMC3_SEL`.  The main
  thread stores it before every `$8000` write; interrupt code writes
  `$8000` directly and leaves with `$8000 = MMC3_SEL | $80`.  An interrupt
  between a select and its data write changes nothing, so the retry loops
  are gone.
- CHR mode 1: R0 = BG tiles `$00-$7F` (scene page 1 or band page 2), R1 =
  `$80-$FF` (always the scene page), R2-R5 = sprites.  The band page is
  only 2 KiB now: upper tiles are no longer copied to it or marked stale,
  which also halves the scene-load copies (boot 3 frames longer than the
  original instead of 6).
- `tools/mss_to_mmc3.py` converts Mesen states of the SUROM build: MMC3
  registers and mapping arrays from the MMC1 ones, `$EB` = `$87`, the
  CPU's interrupt-disable flag cleared, OAM slot 0 hidden.  The gates' states are
  in `out/user/m3/`.  The garble gates track R0/R1 data writes per
  scanline; `band_check` compares only tiles `$00-$7F`.

**21b, the scanline IRQ:**

- The MMC3 IRQ switches R0 to the band page in the window's top border
  row (`irq_handler`, fixed bank, IRQ vector `$FFFE`, `cli` at reset; the
  APU frame IRQ is inhibited and there is no DMC).  The NMI arms it after
  the frame's last PPU access (the counter also counts the A12 rises of
  vblank VRAM traffic) for latch T + 2, T = the border row's first line.
  Frames whose game queue flushed at most 40 bytes reach the arm before
  the pre-render line's clock (standard path: at most 32 bytes, latest
  261.3; 48 bytes and more 263.9-278.7); heavier frames keep the IRQ's own
  re-arm for the same line one frame later, which can only come early.
  No switch while no band is shown or in busy mode; the busy-mode NMI,
  split frames and rendering-off frames disable it.
- Gone: the sprite-0 wait in the NMI epilogue (15,000-19,000 cycles per
  band frame), the sprite tile at page-0 `$FF`, sprite placement and the
  vblank `OAMDATA` fix.  OAM slot 0 and `clear_oam_shadow` are the game's
  again (`$C44F` original).  The epilogue runs only in split frames.
- Measured in Mesen: the counter takes one more clock at the start of
  line 0 on every other frame, and one more when vblank ends with the PPU
  address below `$1000`; with latch T + 2 the switch lands in border
  lines 0-2.  `band_check`: switch minus band top -4..+6 (82 of 3,596
  frames outside 0-7: heavy frames 1-4 lines early, late arms up to +6),
  0 mismatching cells.
- Messages start at 608/888/1589/2363/3297 (original 607/888/1589/2359/
  3290; revision 20: 607/888/1593/2367/3302).

Gates: garble 0 (standard path x6, play-test state, normal and boss
battles, forced level-up, save fade); shop paths only the state's own
episode (42/84/43/89/123 frames; revision 20: 49/87/50/92/130); deadline
0 late (costliest unit 733 cycles; was 776); taint 0/0, min SP
`$12`/`$0F`/`$0F`; ram 0, min SP `$16`; zp 0; mask 0; palettes 8/0;
opening frames 11-301 pixel-identical (3-frame boot offset).

## 2026-11-09 — revision 20: battle text scrolls again; officer screen sprites; text source

Play-test report: (1) a line-break improvement for 「強い武将は前…」;
(2) the 武将 (officer) screen showed the field sprites, NPCs included;
(3) at the end of a battle, 「(names)は〜の計を覚えた」 was hard to read:
each message cleared the window, so the officer names printed just before
「は〜の計を覚えた」 vanished at once.  Proposal: scroll in battle as the
original does, and check whether the 15 pool kanji are enough.

- **Text source**: the revision-14 dtx files are the editable source now
  (`decomp/text/kanji_plan/bank1X_messages_kanji_r14.dtx`; edit, then
  `python decomp\build.py --target kanji`, about 10 seconds).
  `kanji_layout.py` refuses to overwrite them without `--force`.
  b10_msg_148 is 「強い武将は前／弱い武将は後ろ／これが隊列の基本です」.
- **Officer screen** (older than revision 17, from revision 16b):
  `clear_oam_shadow` started with `ldx #$00 / beq`; the patch to
  `ldx #$04` left the `beq` untaken, so the clear fell into `hide_sprites`
  (`$C452`), which hides only from sprite `$A1` up.  Now `ldx #$04 / bne`
  (`$C44F-$C450`).  The officer screen is pixel-identical to the original.
- **Measured first**: in battle messages a 4-line window of one message
  holds at most 8 distinct kanji, a line at most 7; the level-up block
  (four messages scrolling) at most 11.  15 slots are enough.
- **Battle scroll**: the engine's window scroll (`text_redraw_lines`)
  blanked every row cell with bit 7 set, the pool's kanji included; it now
  blanks only the line-end codes (`$FA-$FF`, same 17 bytes at `$D416`).
  Pool pages no longer start on a cleared window.  A page takes the lowest
  run of free slots (mod 15) not shown by any pool tile in the window's
  lines (scanned from `$0300` at the page start: lines 0 to `text_line`;
  in a new window all four, which may still be on screen).  The first slot
  is kept in `KANJI_UPLOADED+1` bits 0-3 (pool pages hold at most 12
  kanji, `POOL_PAGE_MAX`).  A message continuing a window, or a `<PAGE>`,
  scrolls on when its page fits, and clears the window as before when it
  does not.  Band (field) messages are unchanged.
- The tiles `$EF-$FF` the play-test found unused at battle end are not
  needed for this.
- Gates: `garble_state.lua` accepts `SHOP_POKE` / `SHOP_POKE_AT` (RAM pokes
  after the state loads; the level-up run sets the enemy armies to 1 and
  experience to 8,192).  The pool `not_uploaded` check now looks at the
  whole 4-tile slot: 上's top-left quadrant is blank by design (the
  revision-19 run of the same level-up reported 305 such frames).
- Results: battles (play-test, normal, boss, forced level-up) 0 garbled
  frames; standard path 0; save fade 0; deadline 0 late; taint 0 / 0.

## 2026-11-09 — revision 19: kana tails printed by game code

Play-test report: after our attack the battle result read
「テイエンシのへいを　2人倒した」; the enemy's attack read 「…の兵が…」.

- **Cause**: `b10_msg_055` prints the target through the game routine
  `$D549`, which draws the name (`$D49A`) and then writes the tiles の/へ/い
  itself (`lda #imm / jsr text_put_tile`) when the target unit
  (`$60A8,[$4B]`) is 8 or up.  Those tiles are code, not message text, so
  the compiler never saw them.  A scan of all 16 original banks for
  `lda #imm` followed by `text_put_tile` finds one other such tail:
  `$D565` (strategy name, then の/け/い unconditionally; three messages:
  覚えた, 使った, 解き放った).  The battle menu draws strategy names
  through `$D567` from its own code; menus stay kana.
- **Troop pick** (`$EE $FD lenA`, `kanji_ctl`): the compiler writes
  `<CALL:D549>` as `<CALL:D49A>` (the name alone) and a pick on the same
  test, variant A 「の兵」, variant B empty (`KANJI_TROOP_CALLS`).
- **Back over a tail** (`$EE $FC n`): the compiler writes `<CALL:D565>` as
  the call, then `$EE $FC 2` (the buffer position goes back two cells,
  over けい) and 計 (`KANJI_SUFFIX_CALLS`).  の計 is as wide as のけい.
- The inventory counts only the kanji of a pick's text (`KANJI_RE`), so
  の stays kana.  兵 and 計 count once more, which reorders the kanji codes;
  `kanji_layout.py` gives the troop call its real width and leaves the
  generated text unchanged.
- Checked in battle: the boss battle shows 「テイエンシの兵を　2人倒した」,
  the normal battle 「ヘイシを　9人倒した」 (unit below 8, as the original).
  The strategy messages, opened in place of the result message with
  `$4D` set: 「ごうかの計を使った」, 「はげきじゅうの計を覚えた」,
  「じょうないの計を使った」 (no party in the saved states has a strategist).
- Gates unchanged from revision 18; `zp_check` counts 1,000 checks
  (revision 18: 1,043): the first town's RNG drifts from frame ~5,700 with
  the reordered kanji codes, so other townspeople speak by frame 9,000.

## 2026-11-09 — revision 18: battle kanji in the scene page's free tiles

Play-test proposal: in battle, tiles `$A4-$DF` of the background page are
blank and never shown, so the kanji can go straight into the page the PPU
shows, with no band, no sprite 0 and no NMI wait.

- **Facts measured first** (three battles: the play-test state, and new
  states just before a normal and a boss battle, `out/user/r17/`): tiles
  `$A4-$DF` are never shown and never written by the game after the battle
  set is loaded; the only CHR the battle writes is the portrait tiles
  `$80-$A3`.  The battle loads graphics set 8 (`text_graphics_index`) in
  `battle_intro_screen` and the area's own set when it ends.  The pool
  tiles are cleared at battle entry by the screen dissolve (`$9942`, direct
  `$2007` writes, not the block writer).  The history-select screen also
  loads set 8 but keeps graphics in those tiles.
- **Pool**: when set 8 is loaded the hack reads the 60 tiles back (posted
  by `pal_copy`; at battle entry rendering is still off, so it finishes in
  one NMI; otherwise 4 tiles per light frame, 533 cycles at most).  All
  blank: the pool is armed (`KANJI_WIN_COL` bit 6; bit 7 = checked since
  the last set load, so a failed check is not repeated).  Any game write
  into the tiles (block writer, queue, CHR animation) disarms it.  A
  message printed while set 8 is loaded and the pool is armed, with no
  page over 15 kanji, is a pool message (`KANJI_PAGES_LEFT` bit 6): entry
  k of a page uses tiles `$A4+4k..+3`, uploaded to the scene page (plane 0;
  plane 1 stays blank), and the band, sprite 0 and the NMI wait stay off.
  Pages start on a cleared window (`FRESH_PAGES`), so slots are reused only
  after a clear.  Other messages, and a page over 15 kanji, use the band.
- **Engine**: `text_render_cell` treated every row-buffer byte with bit 7
  set as the line's end code (its font is all below `$80`), so the first
  pool kanji ended the line and the rest printed on the next line.  Its
  `jmp loc_DC7C` (`$DBED`) now goes to `render_ctl` (`$F02B`, the dead tail
  of the rewritten reset code; no code in banks 0-15 references
  `$F02B-$F039`), which draws `$A4-$DF` as tiles and sends every other
  byte down the original path.  The engine's line scroll still blanks such
  bytes; kanji messages clear the window instead of scrolling.
- **Stack at battle entry** (found by the taint gate, older than this
  revision): the block copy to the band page ran `restore_tile` ->
  `set_page` -> `wr_reg1_main` under the game's bank-switch lock, and an NMI
  in that window takes the game's lock path (`mmc1_reset`) on top: minimum
  SP `$09` (revision 17: `$0B`; game scratch starts at `$010A`; the
  original reaches `$1C` there).  The block writer now uses
  `restore_tile_main` with the CHR-register writes inline (only its return
  address on the stack in the lock window), and `wr_reg1_main` writes the
  register inline: minimum SP `$0D` in both battle entries.
- Gates: `garble_check.lua`/`garble_state.lua` check pool kanji
  (`pool_not_uploaded`, `pool_on_band`, `pool_glyph_changed`, and
  `pool_outside` for a pool tile the game itself shows while the pool is
  armed).  `vblank_deadline.lua` tags `poolchk`.  `taint_check.lua` counts
  the rewritten `load_text_graphics` (`$C5A6-$C5E1`, the original routine's
  writes to `$3D`/`$A5`) as game code and drops the restored `$E6B3-$E6C3`.
- Battle results: 0 garbled frames in all three battles, window closes and
  shake steps included (revision 17: 15 frames in 7 closes); 0 accesses after
  the pre-render line; taint 0 / 0.

## 2026-11-09 — revision 17: sprite 0 follows the frame it is drawn in

Play-test follow-up to revision 16c (one garbled frame per screen-shake
step while 「…の攻撃」 is shown; the frame when a battle window closes).

- **Cause (shake)**: sprite 0, the band's line sensor, goes to the PPU with
  the OAM DMA at the start of each NMI, but its position was computed in
  the previous NMI from that frame's scroll.  The battle shake moves the
  screen 3 px vertically (`scroll_y` 0 <-> 237) from the main thread
  between the two NMIs, so on every step sprite 0 sat 3 lines off the
  border line, the hit never came and the window's kanji showed page 1
  (8 frames on the play-test battle).  Horizontal steps never missed (the
  border line is 19 tiles wide).
- **Fix**: the rule is now that sprite 0 must match the frame being drawn.
  `KANJI_SPRITE_DIRTY` became `KANJI_SPR0`: the vertical scroll sprite 0
  was placed for (0-239), `SPR0_STALE` ($FE, set by the overlay when it
  moves the window) or `SPR0_DIRTY` ($FF, page-0 tile `$FF` overwritten, as
  before).  In every light frame with the band on, `light_unit` compares
  `scroll_y` with it; on a difference `spr0_fix` places sprite 0 again
  (`spr0_place`, the old hook tail, now in the second code segment) and
  writes the four bytes to `OAMDATA` in the same vblank.  The game's NMI
  sets `OAMADDR` to 0 before its DMA and nothing touches OAM after it, so
  the writes land on sprite 0.  That frame uploads one glyph tile instead
  of two.  Light uploads write CHR register 1 directly
  (`upload_unit_nmi`: `KANJI_MAINCHR` is never set in a live NMI), which
  pays for the check: the costliest unit (double upload) is 8 cycles
  shorter than in 16c.
- Battle (`out/user/r16c` state, 2,450 frames, new gate
  `tools/lua/band_timing.lua`): 0 sprite-0 misses (16c: 8),
  15 corrections (shake steps and window moves), each ending by scanline
  252.2.
- **Gates**: `garble_check.lua` and `garble_state.lua` also flag
  `kanji_left`: a cell that showed a kanji still shows it on page 1 after
  the window's corner is gone.  Until now a window erased from the top was
  invisible to them (they find the window by its corner), which hid the
  battle-close frames below.  `vblank_deadline.lua` counts `OAMDATA` writes
  as PPU accesses, tags `spr0fix` units, buckets CHR-animation NMIs
  (`anim`, no units) apart from idle-queue ones, and can run from a save
  state (`DL_STATE`, `DL_PATH`, `DL_FRAMES`, `DL_OUT`).  In the battle the
  only NMIs entered after the pre-render line are CHR-animation steps
  (up to scanline 263.3), which run no unit.
- **Not fixed (known)**: every battle message close garbles 1-3 frames
  (7 closes, 15 frames on the play-test battle; revision 16c reported
  only the last 「…が現れた」).  The game erases the window two rows per
  frame from the top; once the border row is gone the remaining kanji
  rows are drawn from page 1.  Sprite 0 cannot follow there: the erase is
  flushed in a vblank that ends at scanline 260, too late to move it.
  Map windows do not close this way (standard path: 0).

## 2026-11-09 — revision 16c: every hit kills (battle damage table)

Play-test report: every hit to an enemy is a one-hit kill.  Save state
(`out/user/r16c/rom_kanji_1.mss`, battle start) reproduces it: every attack,
ours and the enemies', removed the target's whole troop count.

- **Cause**: the damage formula (bank 14 `$983F`/`$9844`) multiplies by a
  per-unit-type factor read from two fixed-bank tables, low bytes at
  `$E6A9,y` and high bytes at `$E6BD,y` (20 entries each).  The kanji build
  had put `chr1_scene` (17 bytes of hook code) at `$E6B3-$E6C3`, taken for
  "zero padding, never read" by a runtime read survey of the history
  prompts (`tools/fixed_survey.py`), which never runs a battle.  Those
  zeros are the tail of the low table and the head of the high table, so
  the factors became `$EB0C`, `$4C54`, ... instead of `$000C`, `$0054`:
  damage 6,214 instead of 10.  PLAN rule 8 warned that read coverage is no
  proof; the bank-14 code that reads the tables is undecoded data in the
  decomp, so the audit missed the indexed reads.
- **Fix**: `$E6B3-$E6C3` is the original again (both copies, banks 15 and
  31; the lint now checks it).  `chr1_scene` moved into the `$C5A6` hook
  region, made room by moving load_text_graphics' table copy into the hack
  bank (`pal_copy` at `$8009`, jumped to and back so the text task's
  stack is no deeper; the same `$F3/$F4`, `$03E0` and Y effects).  A static scan of banks 12-15 for jumps and indexed reads into
  every other reused fixed-bank range found no real reference.
- Damage after the fix (same state, first round): 26, 22, 4, 9, 3, 7
  soldiers (the original ROM on this state: 10, 6, 10, ...).
- **Also fixed: `$0100/$0101`**.  The overlay's scratch `KANJI_M0/M1`
  (and its dispatcher's jump vector, written for every kanji and control
  code) lived at `$0100/$0101`, which bank-14 item code uses: when the
  inventory is full and a chest item is given up, it stores a flag and the
  chest index there (`$81A7`, `$81DF`), prints 「…は…を諦めた。」 and then
  clears that chest's opened flag (`$80CB-$80D5`).  The scratch now lives in
  `$0132/$0133` (the text address, consumed at message entry); the
  page-start flag moved to bit 7 of `KANJI_PAGES_LEFT`.  `ram_gate.lua`
  flags any hack write to `$0100/$0101`.
- **Gate**: `tools/lua/taint_check.lua` runs from a save state with a
  scripted input path and reports game reads of RAM (`$0000-$07FF`,
  `$6000-$7FFF`) that the hack changed since the game last wrote it, game
  writes to the hack state, and the minimum stack pointer.  Battle round:
  0 / 0, min SP `$14`.
- **Not fixed (known)**: one garbled frame when the last 「…が現れた」 leaves
  at a battle start, and one frame per screen-shake step while 「…の攻撃」 is
  shown.  Both are frames without a sprite-0 hit while the window's kanji
  are still on screen: the battle erases the window from the top (the
  corner goes one flush before the text row, in an NMI that ends past the
  pre-render line), and the hit shake moves the scroll after sprite 0 was
  placed.  Showing the band page for the whole frame was tried and dropped:
  the battle tile set keeps the officer names in bitplane 1 of the same
  lower tiles that carry the kana in bitplane 0, so any kanji slot is a
  piece of a name above the window (7 frames of garbled names instead).

## 2026-11-09 — revision 16b: kanji garbled during screen fades

Play-test report: saving at the record office (この度の戦の成果を 歴史書に記録しても
宜しいでしょうか？ → はい), the kanji were garbled while the screen faded to
black and back.  Also reported: one garbled frame when 「…が現れた」 leaves
the screen at the start of a battle (not reproduced yet; see below).

- **Cause**: the palette fades (`$C51A` fade-in, `$C522` fade-out) call
  `clear_oam_shadow` (`$C44E`) and `update_oam` on every step.  The clear
  hides all 64 sprites, including slot 0, which carries the band's sprite-0
  marker; the game's own sprites start at slot 1 (`update_oam`), so only
  the marker was lost.  Without the sprite-0 hit the NMI epilogue never
  switched to the band page, and the window's kanji showed the scene
  page's kana tiles for the whole fade (20 frames each way here).
- **Fix**: `clear_oam_shadow` starts at slot 1 (`ldx #$04` at `$C44F`, a
  registered fixed-bank patch site).  The NMI already owns slot 0: every
  normal frame it writes the band marker or hides it, and split frames
  hide it.
- **Test**: from the play-test state (`out/user/r16b/rom_kanji_1.mss`),
  the save conversation and its fade: 40 garbled frames before, 0 after
  (`tools/lua/garble_state.lua`).
- The battle intro fades in with the same loop before printing 「…が現れた」.
  The reported single frame at the message's end has not been reproduced
  (no field state yet).

## 2026-11-09 — revision 16: partner-shop menu garbled under kanji messages

Play-test report (save state at the 徐州城 partner shop): the menu
のうりょく / くわえる / はずす / かいこ showed とうりょく / くわえる / はFF / †いこ.

- **Cause**: kanji borrow kana tiles on the band page (CHR page 2), which
  covers the text window and everything below its top border.  The
  compiler kept a message's kanji off menu kana only for messages ending in
  `?`, `<WAIT>` or `<END_NOWAIT>`.  「<NAME_F6>様、ご用件をお申し付けください」
  (b10_msg_086) ends in `<JUMP:92BE>`, whose bank-14 code opens the menu
  ($1F) beside the window, so 様用件申付 sat on か, す, の.  The replies
  that the menu code prints while the menu stays up (誰も登録されていませんよ,
  …殿は隊列から外せないようですが, …) did the same with their own kanji.
- **Menu context** (`tools/kanji_text.py`): the original banks 13-15 are
  scanned for `jsr text_print_inline` + message index (279 sites; most
  menu code is undecoded data in the decomp) and for menu opens (`ldx
  #menu` + `jsr` text_init/its wait variants, `jsr $C99F` yes/no).
  - Printed by bank-14/15 code: the fixed kana of every menu opened in the
    $300 bytes before the call and since the menu routine's JUMP entry.
  - A JUMP into bank 14 or the fixed bank: the menu the target opens first.
  - No menu found: the union of all submenus.
  - Bank-13 event code: はい/いいえ and きろく/よぶ only.
  - `?`/`<WAIT>`/`<END_NOWAIT>` prompts reserve the submenu union without
    the name-entry kana grid (menu $26, only on the history screen).
  The build fails if any kanji lands on its own message's menu kana
  (report `menu_context_conflicts`).
- **Tile order**: kanji take the least exposed free tiles first: tiles no
  menu or name uses, then name-entry-grid kana, then submenu kana, then
  officer/item-name kana (lists drawn by menu code).  Previously tiles were
  taken in ascending order, i.e. the common hiragana first.
- The menu cursor ▶ (`$70`, a background tile) is reserved like ▼.
- `PAGE_TILE_MARGIN` 4 → 0 (a leftover slack; the runtime needs no spare
  tile).  Forced page splits for tile space: 29 → 11.
- **Top-of-screen flicker** found while testing: after a large VRAM flush
  (a window drawn or cleared) the NMI put the scene page back only after
  its queue scan, at scanline 19-33 of the next frame, so the top lines
  showed band-page tiles for 2 frames (コマンド's ド here; the same happened
  before with other kana).  The no-unit and CHR-animation paths now select
  page 1 before the scan when the flush is large (at scanline 260 here;
  1 when the game's own NMI already runs to scanline 0), and `nt_rescan`
  no longer repeats the nametable checks that `queue_scan` already ran
  (about 1,900 cycles on such frames).  Small flushes keep the replay
  timing (scroll restore max scanline 260.328).
- **Test**: `tools/lua/garble_state.lua` runs the visible-garble detector
  from a save state with a scripted input path (`SHOP_STATE`, `SHOP_PATH`,
  `SHOP_OUT`).  From the reported state (`out/user/shop_k/`): greeting,
  cancel, のうりょく, くわえる, はずす (劉備, 関羽), かいこ: 0 garbled frames after
  the first 45 (the state's own CHR, saved on the old build).

## 2026-11-09 — revision 15b: inns refuse to let you stay

Play-test report: at the 徐州城 inn, with 200 gold from 張世平, the innkeeper
said 金が足りないようでは お泊めすることはできません.

- **Cause**: the inn's price helper (`<CALL:91B5>`, bank 14) multiplies the
  town's base price by the party size into the math temps `$10-$12`; after
  the message, the Yes handler (`<JUMP:9159>`, `jsr $FA3E`) compares the
  gold with `$10-$12`.  The original text engine never touches `$10/$11`
  while a message prints.  The kanji overlay used `$10/$11` as its
  page-record pointer (page_find, page_start, clean_kana, ctrl_store,
  message_setup), so any kanji after the price (泊 in お泊まりになりますか,
  since revision 14) turned the price into an address ($9xxx-$Axxx, about
  40,000 gold).  Any script that keeps a value in `$10/$11` across a
  message (shops, other prices) was exposed the same way.
- **Fix**: every overlay use of `$10/$11` saves the game's bytes on the
  stack and puts them back before control returns to the engine and
  before every frame wait (so no wait runs deeper on the text task's
  stack).
- **Gate**: `tools/lua/zp_check.lua` snapshots `$10/$11` at every entry
  from the engine into the overlay and after every frame wait, and
  compares at every exit: 0 changes in 932 checks; the previous overlay
  fails it (47 changes in 1,141 checks).  `tools/lua_addrs.py` now also
  reads the overlay and fixed-bank listings.
- Play test also reports the one-frame line artifact right after file
  selection (before the three heroes appear) is gone since revision 15.

## 2026-11-08 — revision 15: iteration mark 々, text fixes, NMI/bank-switch overhead

Play-test request: add the 々 glyph and use it in the text.

- **Glyph**: 々 (U+3005) is treated as a 16x16 glyph like any kanji
  (`KANJI_RE` in `kanji_common.py`/`kanji_text.py`, width in
  `kanji_layout.py` and `reconv_check.py`).  The compiler no longer
  expands 々 into a repeat of the previous kanji.  JF-Dot-Shinonome16 has
  the glyph, so no fallback font is involved.
- **Text** (`decomp/text/kanji_r14/`): every place adult text uses 々
  was changed: われわれ → 我々 (b10_msg_208, b11_msg_202, b11_msg_329),
  かずかず → 数々 (b11_msg_102), 日日 → 日々 (b11_msg_324), そうそうに →
  早々に (b11_msg_077), もともと → 元々 (b11_msg_189), ますます → 益々
  (b10_msg_433, 老いて益々盛ん).  Kept in kana as newspapers do: なかなか,
  まだまだ, くれぐれも, みすみす and onomatopoeia.  All replacements keep
  the cell width, so line breaks and waits are unchanged.
- **Checker**: 々 is allowed; the same kanji twice in one phrase is an
  error (write 々).  `STYLE.md` documents the rule.
- 830 glyphs (々 at code $00E5).
- **Text fixes** (play test): いくばくかの → 幾ばくかの (b10_msg_130).  ソウジン/ソウユウ
  (b10_msg_141) are printed by the bank-13 helpers $A1D0/$A1D4, which pick
  officer $0A or $0B from the runtime name table so the talked-to brother
  names himself first.  The compiler now emits a kanji pick for those two
  CALLs (`KANJI_CALLS` in `kanji_common.py`): `$EE $FF id lenA`, 宋仁,
  `$EE $FE lenB`, 宋勇; the overlay's `kanji_ctl` makes the helper's test
  (`$0580,[$72]` = id) and skips to one variant, drawn by the normal kanji
  path.  Checked on screen with a test build: $0A → 私は宋仁 隣が宋勇,
  $0B → 私は宋勇 隣が宋仁.
- **Lag with many moving characters** (play test: slowdown with 5+
  characters walking, also with no message).  Measured in the first town
  (`out/test/r15/lag_probe.lua`): the hack added ~1,350 NMI cycles per
  frame and ~40 cycles per bank switch (NPC-update frames make ~40), so
  the tightest frames lost all of their idle time.  Fixes:
  - `surom_write_prg_bank` writes the outer-half register only when the
    half changes, read from the hardware: `$BFFF` has bit 7 set in every
    game bank and clear in banks 16-30 (`bank15_lint.py` checks it);
    `set_bank_lock` calls it directly.  A game-bank switch now costs ~7
    cycles more than the original instead of ~40.
  - `ef08_gate` / `ef31_gate`: with no band, no request, no VRAM queue
    traffic and no CHR-animation step the NMI skips the hack bank (82%
    of walking frames); the epilogue runs only while a band is shown or
    in split mode.
  - Dormant mode: with no band and no request the NMI only records stale
    band-page tiles (no restore, no pick, no page rewrite); a message
    start syncs them first (`REQ_SYNC`, before the previous kanji are
    released, so it restores what the continuous restore used to).
  - `queue_scan` drops the band in the frame the game's VRAM queue
    overwrites the window's top-left corner (`nt_check`), instead of
    waiting for the probe; the epilogue's sprite-0 wait no longer runs
    on after a window closes.
    It runs only after the scroll restore (`nt_rescan` for the no-unit
    path, whose scan may replay a CHR entry before the deadline); a first
    version that checked inside that scan pushed 39 scroll restores past
    the pre-render line and garbled ~38 frames per run (caught by
    `vblank_deadline.lua` and `garble_run.py`).
  - Hack banks gain a second code segment at $B900-$BEFF (after the glyph
    tables), identical in every hack bank.
  Result (no message shown): NMI ~3,370 cycles/frame vs the original's
  ~3,110 (was ~4,450); idle time per frame within a few percent of the
  original in every load class.  While a message is shown the band's
  sprite-0 wait still takes ~15,000-19,000 cycles per frame (the split
  needs the CPU at the window border; MMC1 has no IRQ).

## 2026-11-08 — revision 14: adult kanji re-conversion, rule-based layout, page flips

Play-test request: the DeepSeek conversion was too childish and had awkward
waits; re-convert with Opus subagents for adult readers, wrap by program
(18 cells, indent-aware), use spaces only for 、, move DotGothic16 glyphs
down one pixel and list the fallback glyphs.

- **Re-conversion** (`out/reconv/`): `tools/reconv_prep.py` exports the
  original kana with dictionary words, places, items and fixed officer
  names expanded (so ゲントク becomes 玄徳; only runtime names `<NAME_F3>`..
  `<NAME_F7>` stay kana).  One Opus agent wrote the proper-noun glossary
  (`decomp/text/kanji_r14/glossary.tsv`, 293 entries, sourced; e.g. トウケン = 陶謙, not 鄧賢);
  eight Opus agents converted 765 messages following `STYLE.md`, each
  checked by `tools/reconv_check.py` (tokens, font charset, no spaces,
  waits at sentence ends, phrase marks).
- **Layout by program** (`tools/kanji_layout.py` → `bank1X_messages_kanji_r14.dtx`):
  wraps at the agents' phrase marks, 18 cells, 17 after an indenting
  break (dialogue uses <NL> so lines align after 「); 、 and a mid-line 。
  become one space; waits stay at sentence ends, and one is added only
  when more than three lines would pass (61 of 444 waits fall inside a
  sentence, at a clause where possible).  Records that fell through into
  the next record in the original are joined (8).  Line widths checked
  again by the compiler (0 issues).
- **Page flip** (`page_flip` at `$D1C8`, fixed bank): after a kanji page's
  wait the window is cleared and the next page starts on the top line,
  in about one scroll's time; continued windows use the same clear.  A
  page therefore never shares CHR tiles with the previous page: forced
  page splits for tile shortage fell from 281 to 29, relaxed messages
  from 8 to 0.
- **Capacity**: kanji codes are `bank*512 + local`; 2-byte escapes for codes
  below 512, 3-byte `$EE hi lo` above.  Glyph banks grow from 23 (up to
  30, 2,872 glyphs); text banks grow from 18-22 into 30, 29, ...  This
  text: 828 glyphs (banks 23-25), text in banks 18-22, 29, 30.
- **Font**: DotGothic16 glyphs move down one pixel; every fallback glyph is
  listed in `assets/fonts/kanji_fallback.tsv` (preview
  `assets/fonts/kanji_fallback_preview.png`): DotGothic16 汜 釭; MS Gothic
  鄱 龐 涪 雒 詡 瓚 邢.
- **Palette gate** made timing-independent (`tools/palette_check.py`,
  `tools/lua/palette_loads.lua`): every palette load must equal what the
  original routine makes from the original tables (8 loads, 0 wrong; the
  revision-12 build fails 3 of 10).
- Kanji ROM `30918659c14d6cdf07a35cfb5dc506c77e2ddf0b38499c93c6b453d3a3f1d8d2`; original byte-identical; all gates pass.

## 2026-11-08 — revision 13: town palettes restored (fixed-bank gap was live data)

Play-test report on revision 12: outside the first town the grass and trees
turned white ("like snow").  Root cause, present since the hook gap was
first used: `$C611-$C676`, the largest fixed-bank "gap", is the game's
palette table for areas 1-6 (`data_C5EF`, read only by `load_text_graphics`
through the pointer tables `data_C6B2`/`data_C6C2`).  The gap audit was
read-coverage on the scripted path, which never loaded those palettes.  With
hook code there, `load_text_graphics` read a byte >= $80 first, stopped, and
the area kept the default palette (first town room: brown/green instead of
yellow/blue; town exterior: grey/white instead of green).

- The three palette tables (227 bytes) moved to hack banks 23/24 at `$BF00`
  (pointers relocated by `kanji_build.py`); `load_text_graphics` is
  rewritten in place at `$C5A6` to map bank 23 around the copy (game lock
  protocol, X/Y and outputs as the original).  The routine-plus-table range
  `$C5A6-$C6D1` is now the hook gap; the build checks its original bytes by
  hash.
- Other borrowed regions re-audited against every code reference in the
  decomp sources (not read coverage): `$C4BA-$C4CA`, `$D291-$D2B6`,
  `$E6B3-$E6C3`, `$FFE0-$FFEF`, `$F00C-$F039` have no references; the only
  indexed table around `$E6B3` (`data_E668`) is indexed by `game_mode*2`.
- New gate `tools/palette_check.py`: the order of every stable palette the
  game loads on the standard path plus a walk out of the first town's
  building must equal the original's (37 states).  It fails on the
  revision-12 build at the first town room.
- Test harness: `mesen_run.py` and `garble_run.py` delete the test name's
  battery save before each run (a reused name loaded the previous run's game
  and changed the scripted path); the user's own save names are refused.
- Kanji ROM `76dbd865163e122d02be296c2af972b9d9f144042565fbd8f9216befab478e41`; original byte-identical; all revision-12 gates re-run
  and passing.

## 2026-11-08 — revision 12: band goes live before any kanji is shown; vblank budget re-measured

Play-test report on revision 11: the "どの歴史書…" prompt is garbled, and the
oath is garbled until its first line has printed.  Reproduced, root-caused
and fixed; two further timing defects found by the new gates and fixed.

- **Garbled prompt/oath (reported).**  The text engine queues 4-8 VRAM bytes
  almost every frame while it prints or a cursor blinks, and the NMI only
  allowed glyph uploads in such frames, never the sprite-0 tile.  After a
  scene load (sprite tile invalidated) the band could not switch on until
  the queue went idle, typically at the end of the first line, so the
  window showed the scene page with kana in the kanji slots.  Measured on
  the old build: 16-460 garbled frames per run depending on input timing.
  Now every light frame (no CHR animation, <= 8 queued bytes) may run any
  unit, the sprite tile first, so the band is live before the first glyph
  upload completes.  The band is no longer dropped when rendering is off
  (the window probe decides).  Gate: `garble_check.lua` over 18 input
  timings, 0 garbled frames (it flags kanji drawn from the scene page,
  glyphs not uploaded, band/scene mismatches, released or changed glyphs).
- **Vblank budget.**  Work units re-measured from the hook entry: the queue
  scan, DMA flag, upload marks and the scene-page select moved after the
  frame's last PPU access; glyph uploads are one tile per unit when bytes
  are queued, two when the queue is idle; bank 24 is mapped with a direct
  PRG write in the NMI.  Gate: `vblank_deadline.lua`, last hack VRAM access
  at most scanline 259.6 (pre-render line 261), scroll restore in time.
- **CHR animation overran vblank (pre-existing since revision 11).**  The
  block-writer hook took ~750 cycles (two hack-bank round trips) inside the
  NMI's CHR-animation upload, pushing the game's own scroll/mask restore to
  scanline 268: one frame rendered from a stale VRAM address each animation
  step in town.  The NMI path now only selects the scene page (new
  `chr1_scene`, game lock protocol, ~60 cycles); the tiles are marked stale
  by the NMI hook from the animation pointer.  Gate: `anim_timing.lua`,
  restore at scanline 260 (original 259).  Space came from rewriting the
  reset code's CHR/RAM setup (`$F00C-$F039`), which now clears the hack
  state inline; the old reset hook gap holds `chr1_scene`.
- **Queued CHR writes after a band frame** (the ▾ prompt blink, tile `$FF`)
  landed on the band page only and were then "restored" away.  The NMI now
  replays such an entry on the scene page from the queue ring.
- Stack: NMI marking chain uses scratch instead of pushes; minimum SP `$0F`.
- Text speed: the first history prompt finishes printing at frame 639
  (original 626, revision 11 about 640).
- Kanji ROM `1f3bb530e1c114ab0d8e33472c2f84ea8b39628beb227c1b8cae135465cd7c56`;
  original byte-identical.
- New tools: `tools/garble_run.py` (parallel input-offset runs of
  `garble_check.lua`), `tools/lua_addrs.py` (refresh hack addresses in Lua
  gates from the listing), gates `garble_check.lua`, `vblank_deadline.lua`,
  `anim_timing.lua`.

## 2026-11-08 — revision 11 (implemented by the planner): band page fixed end to end

Play-test reports on revision 10: the opening logo had line artifacts, the
history-select screen garbled as soon as it opened.  Both reproduced and
root-caused, plus four more defects found on the way.

- **Opening artifact.**  The revision-10 hook on the OAM DMA (`$EE93`) added
  22 cycles before the game's own raster-split loops, pushing a `$2006`
  write out of hblank.  All NMI hooks now sit after the `nmi_mode` branch
  (`$EF0B`, jumped to) or in the epilogue (`$EF31`).  Split-write dot
  timing and the logo frames are identical to the original.
- **History-select garble.**  The overlay copied CHR and uploaded glyphs
  with NMI off but rendering on, writing VRAM mid-frame.  The overlay now
  never touches the PPU; all VRAM work runs in the NMI's vblank, one unit
  per light frame (measured: >= 7 scanlines left when the game queued
  <= 8 bytes and no CHR animation ran), or in bulk while rendering is off.
  Cycle-measured: glyph uploads split in two halves, restore candidates
  picked in the epilogue.  Gate: 0 hack PPU accesses while rendering.
- **Band page stays in sync with the scene page**: block writes mirrored
  right after the game's write (`loc_C343` hook, read-back copy), queue
  CHR writes scanned and restored, released kanji slots restored.  Gate:
  0 mismatching shown tiles over 3,324 band frames.
- **Sprite-0 band switch**: sprite 0 on the window's top-border line,
  page 2 selected at the hit; window position computed per message.  All
  switches land on border-row line 1.
- **Continued windows** (a message starting on line 3 after a `<JUMP>`, e.g.
  `b10_msg_129` -> `b10_msg_130`): previous lines scroll out with the
  engine's own scroll before the new message prints.
- **Carry rule.**  The compiler now keeps each page's kanji clear of every
  kana of the next page(s) that start while those lines are on screen, and
  emits per-page keep/clean lists plus a per-message kana bitmap.  Gate:
  0 kana written over an active kanji tile (6 on the old rule: the oath's
  last page read "コ しどこマに").
- **Dispatcher** restored to the revision-8 version (revision 10 jumped to
  the kanji handler without pushing X or setting the code's high byte).
- **Stack**: one-push SUROM switcher, jump-based EF08 hook; deepest stack
  `$0110` (original `$0113`, game scratch at `$0104-$010A`).
- **Font**: 鄧 and 瓚 are missing from JF-Dot-Shinonome16; drawn from
  DotGothic16 and MS Gothic, reported by the font builder.
- Build: `kanji_build.py` fails if fixed-bank hook code leaves its gaps.
- Kanji ROM `8d8ea65eedb6aa00716e6811d341a484b4e5a6e3ab3679143d51a8c7e32cfe7d`;
  original byte-identical; 760 messages, 1,192 pages.
- New gates in `tools/lua/`: `band_check.lua`, `r11_diag.lua`,
  `ram_gate.lua`; surveys `nmi_timing.lua`, `nmi_light.lua`,
  `chr_write_ctx.lua`, `task_stacks.lua`, `window_pos_survey.lua`.


## 2026-11-08 — planning iteration 10: play-test bugs reproduced; shadow page, sprite-0 switch, no RAM code

- Reproduced all three play-test reports on the harness (`tools/lua/rev9_*.lua`,
  `out/test/rev9diag/`): CHR-register-1 switch scanlines measured 143-156
  (8% outside the border row); the band delay precedes the game's own
  `nmi_mode` split loops; the history prompt turns to kana garbage the
  frame the band flag clears (`f0900.png` vs `f0940.png`); the oath freezes
  at frame 2,480 because `cell_check` lived at `$01EC-$01F7` inside the
  main stack and was overwritten (`B9 00 03 C9 96 87`), which `iram_watch`
  did not cover.
- Surveys on the original (`out/test/ramsurvey/`): `$0400-$06FF` is live game
  RAM (`$0601-$0634` is game RAM code), so the revision-9 `$0500` queue was
  on used memory; OAM slot 0 is never used; DMC is unused; all CHR writes
  come from `loc_C343` and the queue flush; the game has its own bank-lock
  redo protocol (`set_bank_lock` / `restore_bank_after_nmi`); the town map
  shares scanlines 144-175 with the dialogue window; fixed-bank bytes
  `$FFE0-$FFEF` and `$E6B3-$E6C3` are never read on the path.
- `PLAN.md` revision 10: band page becomes a shadow copy of the scene page
  (resync on block writes, mirrored queue flush, kanji slots excluded);
  mid-frame switch synced by a sprite-0 hit with a bounded fallback; hack
  NMI code moved to PRG banks 23/24 reached through `call_hack` with the
  game's lock protocol; all RAM-resident code removed; `nmi_mode` frames get
  zero hack cycles; band lifetime tied to active kanji, not message end;
  new gates `shadow_check`, `band_switch`, `bank_lock_check`, exec watch, and
  the three play-test regressions.


## 2026-11-08 — revision-9 CHR-page pivot (work in progress)

- Header byte 11 `$08` (16 KiB CHR RAM), `mmc1_init` control `$1E`
  (4 KiB CHR mode), reset CHR register 1 = page 1.
- Fixed bank `$C611-$C676`: SUROM switcher with an NMI lock, F8 far head,
  fixed-bank `enter_text`, CHR-register-1 writer, NMI band stub, reset
  hook (102 bytes).
- F8 trampoline body at `$BF00` in banks 10/11: reads the five inline
  operands, installs the RAM band routines and enters the overlay.
- CHR page 2 is the private text band: kana font in `$00-$7F`, kanji in
  compiler-assigned low tiles.  Fill is six tiles per vblank (22 frames at
  the first message) so the NMI flush fits vblank (`mask_restore` 0).
- NMI band stub: scene page for the visible top, band page at scanlines
  144-146 for the window, scene page restored for the next frame.  A
  manual `bandwrites` log shows 144-146.
- Dirty bitmap, kana restore, `<JUMP>` restore and scene reservations are
  removed.  `exit_clear`/jump hooks clear the band flag and restore the
  scene page.  The hack never writes CHR page 1.
- Compiler reverted to the proven revision-8 low-tile per-page
  assignment: 760 messages, 1,190 pages, max 10/page, oath 9 pages.
- Final gates: original byte-identical; kanji
  `c8f61a090b33169f7ead8fccb11c8bcc0d6aae245110401017c0f55858907980`;
  lint 13 ranges; `sram_watch` 0/5,491; `iram_watch` 0/15,948;
  `mask_restore` 0; stack SP `$18`/`$28`.
- Remaining: field frame tiles can be blanked because the game and hack
  share the `$0400` queue and the NMI flush selects the band page during
  messages.  A split `$0500` queue was prototyped but destabilised the
  message flow; it needs a larger fixed-bank gap or an overlay-resident
  NMI helper.  The field QA save state is still the revision-8 state and
  must be regenerated on the new ROM.  Automated `band_switch` and
  `scene_page_check` gates are still to be written.

## 2026-11-08 — planning iteration 9: private CHR page for the text band

- User play test: garbled name input; next page garbles the previous page.
  The revision-8 harness is green, so the harness paths and the player's
  paths differ; the per-case protection design cannot close that gap.
- Feasibility probe for the user's suggestion (larger CHR RAM):
  `out/test/chr16_probe2.nes` = kanji ROM + header byte 11 `$08` (16 KiB
  CHR RAM) + `mmc1_init` control `$1E` (4 KiB CHR mode) + reset immediate
  at `$F022` `$00`→`$01` (CHR register 1 = page 1), in banks 15 and 31.
  Frames 900-2300 pixel-identical to the current build (`probe_c16e.lua`
  vs `probe_basetr.lua`); mapper state shows 4 KiB mode, `$1000` on page
  1, outer bit still via register 0. Two pitfalls recorded: Lua writes to
  mapper registers are ignored, and a reused Mesen ROM name reuses its
  battery save and changes the game flow.
- `PLAN.md` revision 9: page 2 becomes a private band page (kana copy +
  32-glyph kanji cache), switched in mid-frame at the window's top border
  row by a timed NMI delay, scene page never written by the hack; all
  restore/reservation machinery removed; new gate "scene page CHR equals
  the original at every sampled frame"; hardware caveat for 16 KiB CHR RAM
  on MMC1.

## 2026-11-07 — revision-8 execution: field context and stale CHR

- Hooked the `<JUMP>` exit at `$D190`/`$D198` (`jump_exit_13`/`jump_exit_14`):
  the overlay restores every dirty tile, then tail-jumps to the original
  `set_bank_13`/`set_bank_14`.  A field replay shows the dirty bitmap going
  from 76 bits to 0 before the target script bank is mapped.
- `overlay_entry` now installs the RAM font-copy stub first and restores any
  dirty tiles left by the previous message before clearing the map.  This
  closes the `<END>`, `<END_NOWAIT>`, `<CALL>`-without-return and
  `text_init` cases: visible kanji are no longer forgotten at the next open.
- The compiler now reserves measured screen tiles.  `tools/qa_sweep.py` and
  `tools/qa_field.py` record every lower tile referenced outside the page's
  text-window box; `tools/make_screen_survey.py` merges both surveys into
  `scene_borrow.tsv` (scene borrow + screen columns).  Unsurveyed messages use
  the measured field fallback (command-menu kana, HUD and the 26-tile
  oath-scene borrow).
- Added the field QA harness: `tools/lua/town_menu.mss` (town, command menu
  open) + `tools/qa_field.py` overrides the next `text_show_message` index and
  captures page 1 with the menu visible.  Added `tools/lua/town_menu_save.lua`
  to regenerate the state.
- D3 resolved: on the history/name-entry screen the original ROM's
  `$1000-$17FF` CHR matches bank 9 in all 128 tiles.  The 20 differing tiles
  on the kanji ROM are exactly the prompt's own kanji slots, not a different
  font.  The remaining shop/menu failures were stale kanji and are closed by
  the open-time restore and screen reservations.
- Added `tools/qa_pages.py`: samples every 5 frames, groups by
  `KANJI_PAGE_PTR`, and asserts every page (page tiles, outside-window
  collisions, kana CHR, frame tiles).
- Added `tools/field_check.py` for the `field_kana_check.lua` menu-box dumps.
- Empty message records now compile to a valid `$FF` stream; the QA ROM
  neutralises `<CALL>` tokens so battle helper messages can be opened.
- Final gates: field QA 872/872, per-page QA 872 indices / 1,356 pages with
  0 failures; `sram_watch` 0/17,314; `iram_watch` 0/29,164;
  `mask_restore` 0; stack SP `$18`/`$28`.  Original
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
  kanji `a90614d88a584d436255c4ee5d7f28b28984acfb758a6cf17d45c296436dccb9`.
- Tradeoff: the larger reservations reduce page capacity; the oath is 9
  short pages.  Correctness was prioritised.

## 2026-11-07 — planning iteration 8: field-context defects

- Re-verified `1b1001f`: original byte-identical; lint 7 ranges; `sram_watch`
  0 hack writes; `mask_restore` 0; oath pages and a four-line page clean.
- Added `tools/lua/field_kana_check.lua` (kanji ROM, survey inputs, CHR and
  nametable dumps every 20 frames through the town). Offline check: for
  each dump, compare every tile `< $80` referenced inside the window and in
  the command-menu box against the bank-9 font.
- D1: after the NPC speech chain 129-131 (each ending in `<JUMP>`), the
  command menu shows kanji quadrants in マ は な し ら べ. Page records
  decoded from the ROM show 129-131 own exactly those tiles and 132 does
  not; `<JUMP>` leaves the interpreter via `jmp ($00F3)` and never reaches
  the `$D1FA` exit restore. 95 messages end with `<JUMP>`.
- D2: the field command menu is visible during talk messages, and nothing
  reserves its kana for non-prompt messages; the sweep ran only on the
  history screen, where no menu exists.
- D3: the eleven "font context" sweep failures are unproven.
- `PLAN.md` revision 8: hook the `<JUMP>` path before the bank switch,
  survey-recorded screen-referenced tiles per message, a field QA harness
  with the menu open, and the history-font diff.

## 2026-11-07 — revision-7 execution: multi-page fix and QA sweep

- Fixed the multi-page corruption: `page_find` left `Y` on `code_hi`, so
  tile bytes were read one byte late and `$0D` entered page records.  `dey`
  at `@found` makes `Y` point at code_lo.
- Added cross-page tile reservations: a page now reserves the last three
  visible lines from earlier pages (backward carry) and the kana tiles of
  itself plus the next two pages (forward).  This keeps previous kanji in CHR
  and prevents the next page's kana from restoring over them.
- Kept `restore_exit`'s visible-tile skip (the history/name-entry screen uses
  a different kana font, so a bank-9 restore there garbles the prompt) and
  reduced the restore batch to four tiles per frame; `mask_restore` is 0.
- Verified oath pages 1-3 (`oath_zoom.png` redone), border `$0D`, and a
  four-line page with a line-4 kanji (`fourline_zoom.png`).
- Added `tools/qa_sweep.py`: patches the history-prompt inline index, runs one
  Mesen instance per index, truncates at page 1, and checks page records,
  window/nametable collisions, kana CHR and frame tiles.  Full 872-index run:
  772 clean, 89 empty records, 11 context-dependent (history menu/font)
  failures; a neutral QA harness is still needed for a zero-failure gate.
- Added `oath_settled.lua`, `oath_page3.lua` and `qa_sweep.py`.
- Final hashes: original
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
  kanji `54fc79b849c69f984b257c62a55c3487ce5ec8596f2d253b01eea2d77f178d33`.

## 2026-11-07 — planning iteration 7.1: emulator-only target

- No EverDrive N8 is available. `PLAN.md` 7.1 makes Mesen the reference,
  defers the hardware pass, and replaces it with emulator-provable
  compatibility checks: random-RAM power-on, no PRG-register bit-4 writes,
  a second emulator run. Field-list kana is decided (kana in map lists).

## 2026-11-07 — planning iteration 7: gates re-verified, multi-page regression

- Re-ran the revision-6 gates on a fresh build of `a14ab1c`: original
  byte-identical; lint 7 ranges; `sram_watch` 0 hack writes of 21,923;
  `mask_restore` 0 visible-scanline restores.
- Found a regression the single-page checks could not see: the oath scene's
  second page (`out/test/survey_1920.png`, zoom `out/test/oath_zoom.png`)
  shows kanji drawn as mixtures of two glyphs, a damaged ば, and the bottom
  border row (`$0D`, permanently reserved) overwritten by a kanji quadrant.
  Consistent with a page-advance fault in the page-record pointer or the
  uploaded bitmap. Repro: `state_ppu_dump.lua` on the oath save state.
- `PLAN.md` revision 7: fix and prove page handling, fourth-line check,
  message-warp QA sweep over all 872 indices with nametable/CHR assertions,
  prompt list tags, slot 2/3 proof, hardware pass; section 4 lists what
  needs the user.

## 2026-11-07 — revision-6 execution: ROM-resident runtime, no battery RAM

- Replaced the battery-RAM/SRAM overlay with a **ROM-resident overlay**:
  1,042 bytes at `$B800`, assembled once and included identically in text
  banks 18-22. The `F8 3A C6` trampoline now maps bank 10/11, reads the five
  inline bytes, maps the text bank and enters `$B800`.
- Removed the `$0600` far loader, bank-24 overlay install, signature check,
  NMI entry/palette guards, `cell_check` signature dependency, all seven extra
  `kana_prepare` sites and the bank-13 patches. Fixed-bank block is 94 bytes;
  the lint now registers 7 patch ranges.
- Moved all hack state to internal RAM: `$0131-$013F` (text/page/entry state),
  `$0140-$015F` (RAM font-copy stub), `$0160-$016F` (glyph/kana buffer),
  `$0170-$017F` (dirty-CHR bitmap), `$01E0-$01E7` (scratch). No hack write
  reaches battery PRG RAM.
- Replaced dynamic CHR allocation with **compiler-assigned tiles**: page
  records now carry `(code_lo, code_hi, t0, t1, t2, t3)`. Uploads and restores
  go through the game's `$0400` VRAM queue; a 16-byte dirty bitmap restores
  kana at exit and before page reuse. `mask_restore.lua` reports 0 visible-
  scanline PPUMASK restores.
- Added `scene_borrow_kanji.lua` (survey build with `upload_glyph` patched to
  RTS, so the scene CHR is never touched), `scene_borrow.tsv` (9 surveyed
  labels; oath scene = `$42-$5B`) and an exact 65-tile name-entry `savename`
  set extracted from the original PPU. Compiler consumes both; max page
  entries 11, `min_free_static = 4`, `pages_over_capacity = 0`.
- Added `sram_watch.lua`, `iram_watch.lua` and `stack_check.lua`. Verified:
  0 hack SRAM writes, 0 foreign internal-RAM writes, min SP `$18` at NMI and
  `$28` at overlay entry; history prompt/name entry and field message
  `b10_msg_129` render correctly; 6,000-frame survey healthy.
- Removed the obsolete `tools/asm/kanji_fixed.asm` and `kanji_far.asm`.
- Final hashes: original
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
  kanji `b1e33ab17ad4b41d4a1c6c34386aec0679b36eed3f7df149f2a71857b447bb4c`.

## 2026-11-07 — planning iteration 6: battery RAM is the game's; pivot

- `tools/lua/slot_ptr_watch2.lua` (original ROM, frames 302-303): the boot
  slot check calls `b13_init_name_entry` with copy pointers `$6800`, `$7000`
  and `$7800`. The three history books occupy all battery RAM above the
  live state at `$6000`. The RAM overlay at `$7002` therefore sits inside
  books 2 and 3; no hack state may live in `$6000-$7FFF`.
- `tools/lua/iram_audit.lua` (original ROM, 6,000 frames): untouched
  internal RAM is `$0131-$017F`, `$01E0-$01EB`, `$010B-$0112`, `$0100-$0103`
  only; `$03C0-$03FF` and `$0700-$07FF` are fully used; the stack is
  confined to about `$01EC-$01FF` by the text tile buffer at `$0180-$01DF`.
- `tools/lua/mask_off_log.lua`: rendering-off windows on the original are
  1-19 frames at scene transitions.
- `PLAN.md` revision 6: ROM-resident overlay in every text bank, 64-byte
  far-copy stub in `$0140-$017F`, compiler-assigned tiles with scene-borrow
  and list tags, uploads through the game's VRAM queue, no NMI code, no
  scans, seven patch ranges.

## 2026-11-07 — revision-5 execution attempt and evidence

- Executed the revision-5 plan and falsified its central premise: the upper
  CHR range is referenced by the history/name-entry screens (window border,
  menu and name fonts). Opening the upper pool from mode bytes alone garbles
  the screen, so the revision-4 nametable gate is restored.
- Found a hidden SRAM conflict: bank 13 copies a 2 KiB save slot over
  `$6800-$6FFF` via an indirect pointer (`PC $9F6B-$9F7E`, "5S" signature at
  `$6008`). This invalidates the earlier "unused above `$6780`" audit.
- Implemented and tested three upper-tile save/restore schemes and an
  internal-RAM relocation of long-lived state; all were reverted because
  they corrupted page records or visible tiles. Findings are recorded in
  `STATUS.md`; the code is back to the verified revision-4 runtime.
- Added diagnostic Lua scripts: `mask_restore.lua`, `upper_restore.lua`,
  `ram_audit.lua`, `sram_clear.lua`, `state_watch.lua`, `first_save.lua`,
  `internal_dump.lua`, `frame_state.lua`.
- Kept two capacity changes: the compiler rejects pages with more than 13
  slots and metadata over 256 bytes; `meta_load` copies 256 bytes instead
  of 512 (measured maximum is 221).
- Rebuilt and verified: original ROM byte-identical; kanji ROM
  `cf2db99fee82206ce5425f60a6093f5c6f177ae10f9ca6c973f92d2ffd6a445f`;
  prompts (`pp_0900`, `ktown_1100`) and the 6,000-frame survey are clean;
  bank-15 lint passes with 17 ranges.

## 2026-11-07 — planning iteration 5: PPUMASK-restore measurement

- Added `tools/lua/mask_restore.lua`: logs the PPU scanline at the NMI
  handler's PPUMASK restore (`$EEDA`), which is when the picture resumes.
  Over the title-to-field run the original ROM never restores on a visible
  scanline; the kanji ROM does so in 73 frames (scanlines 37 and 86,
  alternating), i.e. every scan frame blanks the top of the picture. The
  history screen is black there, so earlier screenshots could not show it.
- Added `tools/lua/open_frames.lua` (per-frame capture around message open).
- `PLAN.md` revision 5: drop the nametable scan, conditional and unrolled
  CHR scan under a ~1,000-cycle budget, save/restore for borrowed upper
  tiles instead of zeroing, per-prompt list reservation tags.

## 2026-11-07 — revision 4: upper-half prompts, 2 KiB nametable scan

- Fixed the history save-slot collision by allocating prompt kanji from the
  upper CHR half when the whole upper half is unreferenced by both
  nametables and by OAM. The history screen's upper CHR is the menu/name
  font, not blank; the allocator therefore treats "unreferenced" rather
  than "all zero" as the safety condition.
- Added `cell_check` at `$C64F` and patched `text_render_cell` at
  `$DBE7/$DBEA` so tile numbers `$00-$F9` render and `$FA-$FF` stay controls.
  Registered both ranges in `bank15_lint.py` (17 ranges).
- Added upper free/dirty bitmaps, 32-byte screen/visible bitmaps, OAM sprite
  tile marking, upper restore-to-zero at exit, and upper-pool reuse at
  message open.
- Extended the nametable scan to `$2000-$27FF` (2 KiB) at 128 bytes/frame and
  alternated it with the CHR scan so one NMI never runs both. Message-open
  scan is about 32 frames.
- Added `tools/lua/nmi_budget.lua`. Measured over a 2,100-frame run:
  original max 10,132 / avg 2,786 cycles; kanji max 15,833 / avg 3,430.
  The split cut the kanji peak from 21,636 cycles.
- Verified `prompt_pages.lua`, `town_kanji.lua` and a 6,000-frame
  `scene_survey.lua` run on the new build. Overlay is 2,981 bytes.
- Kanji ROM SHA-256 `862d7f377d11050e3eb0f4b4118b6267140cf4d3705bbb913f596bd47d78d6bb`;
  original ROM remains byte-identical.

## 2026-11-07 — font switched to JF-Dot-Shinonome16 (planning iteration 4)

- DotGothic16 rendered 2-pixel strokes at 16 px (歴, 書, 軍 visibly heavy).
  `tools/kanji_common.py` now renders from `JF-Dot-Shinonome16.ttf`, which
  rasterises to pure 0/255 pixels at size 16 for all 718 glyphs; no offset
  is applied because the game's own bank-1 name glyphs also fill the cell.
- Regenerated `assets/fonts/kanji_16x16_ext.png` and `kanji_font.bin`.
  Original target still byte-identical; kanji target SHA-256
  `9cd038d459122b4394afa14ae0df589433792dbc12dde1c9b81350efa35c425a`.
- Verified in Mesen: `out/test/pp_0900.png` (history prompt).
- `PLAN.md` revision 4 records the next work list.

## 2026-11-07 — revision-3 pass: runtime cache, live scan, restore policy

Baseline: `0be4f8a` plus the revision-3 `PLAN.md`.

### NMI job runner

- The NMI entry guard now reads `PPUSTATUS` before any CHR work, runs the
  bounded jobs, and jumps into the original handler. This removes the
  vblank-flag re-entry that a pre-handler upload caused.
- The overlay's job runner performs: upload pending glyph/restore tiles,
  scan 8 CHR tiles per frame, scan 64 nametable bytes per frame, and restore
  dirty tiles (four per frame) when the mask shadow says rendering is off.
- The old pre-handler upload stub was replaced; the `$C611` hook block is now
  91 bytes (switcher, far stub, signature check, entry guard, palette guard).

### CHR model

- The overlay now matches 128 CHR tiles against the SRAM kana copy and builds
  `KANJI_RESIDENT`; the same scan also records tiles referenced by the visible
  nametable in `KANJI_SCREEN`.
- The overlay is assembled at `$7002` and copied as 3,072 bytes; the current
  code is 2,247 bytes (`$7002-$78C8`).
- The scene survey on the original ROM confirms the oath scene overwrites
  kana `$42-$5B` (26 tiles) and a town/field transition briefly overwrites
  `$00-$17`. The compiler keeps the 26-tile worst-case allowance for ordinary
  pages.

### Page allocation

- Metadata is now compact per page: count, 16-byte used bitmap, then
  `(code_lo, code_hi)` pairs. The runtime allocates four distinct tiles per
  kanji from `resident ∧ ¬used ∧ ¬screen`.
- Fixed two allocation bugs found by screenshot: the code bytes were read
  from the record start instead of after the used bitmap, and the scan
  position was not advanced after the fourth tile of an entry, so tiles were
  reused.
- Page records are copied with a fixed 512-byte copy; the payload cap is 509
  bytes.

### Restore policy

- Message exit (`$D1FA`) now restores every dirty tile that is not referenced
  by the `$0180` or `$0300` text buffers. Visible prompt kanji survive; menus
  drawn outside the text engine get kana back.
- `kana_prepare` is installed at the six bank-15 `jsr text_put_tile` sites and
  the two bank-13 name-list sites. It restores a stolen kana tile on demand.
- `text_redraw_lines` (`$D388`) is routed through a re-upload hook for tiles
  that were restored after a redraw.

### Compiler

- Prompt messages (`<END_NOWAIT>`, trailing `<WAIT>`, or a trailing question
  mark) reserve the union of the menu kana stream. They also skip the
  oath-scene allowance because the menu reservation is the binding limit.
- The history prompt now fits on one page:
  `どの歴史書を登録しますか?`.
- The report now records `scene_borrow_allowance` and the actual
  `pages_over_capacity` count.

### Tests and tooling

- `tools/lua/scene_survey.lua` dumps screenshots and CHR every 60 frames for
  the original and kanji ROMs; it was used for the 6,000-frame no-hang check
  and the 26-tile borrowing measurement.
- `tools/lua/prompt_pages.lua` advances the history prompt, captures the
  one-page render and the name-entry grid.
- `tools/lua/sram_watch.lua` accepts the larger overlay window
  (`$7002-$7FFF`) and still reports no base-game writes.
- Original ROM remains byte-identical; bank 31 still mirrors bank 15.

### Known issue

- The history slot menu prints a runtime save name after the prompt opens.
  Its kana can overlap the prompt's kanji tiles, so the prompt shows
  `どの歴史書 始 をメロめますか?` while the slot list is visible. The
  nametable scan cannot see a menu that is drawn later. This is recorded in
  `STATUS.md` as the next menu-aware allocation task.

## 2026-11-07 — revision-2 pass: RAM overlay, renderer fixes, first kanji page

Baseline: `26999aa`.

### Fixed-bank layout

- Removed the bank-31 `$E000` overlay; bank 31 is now a byte-identical copy
  of patched bank 15. `tools/bank15_lint.py` enforces that equality and the
  registered patch ranges.
- The text-engine overlay is installed into battery PRG RAM at
  `$7002-$73FF` from bank 24. A two-byte `KO` signature at `$7000` gates the
  fixed-bank hooks; a random-SRAM boot re-installs it.
- The `$C611` gap now holds: the 41-byte SUROM switcher, the `$C63A` far
  stub, a signature check, and signature-guarded NMI entry/palette stubs.
- Removed the caller-bank clobber: trampolines are `F8 3A C6`, the far stub
  maps bank 13 through `set_bank_b`, and `current_bank_a` survives a message.

### Text engine fixes

- `$F8-$FF` now take the original `$D2B7` path; the dispatcher no longer
  jumps through an out-of-range table entry on newline/end controls.
- Fixed the page-record field offset (tile0 is read at entry+3, not +4).
- Fixed the four-tile buffer order: TL/TR in `$0300`, BL/BR in `$0318`.
- Fixed 1bpp->2bpp expansion: each quadrant now gets a 16-byte tile slot
  (DST 0/16/32/48 instead of 0/8/16/24).
- Fixed `kana_prepare` clobbering the caller's X/Y and the buffer offset
  being destroyed by NMI (`KANJI_BUFX` now holds it).
- Page metadata is capped at 255 bytes; `KANJI_META` stays in `$6E00-$6FFF`.

### Text compiler

- Per-page reservations now use the exact table strings for
  `<WORD>/<PLACE>/<ITEM>`, the exact name record for `<NAME:xx>`, bounded
  unions for the dynamic name insertions (`<NAME_F3>` item names and
  `<NAME_F4>-<NAME_F7>` party names), plus frame/cursor/digit tiles.
- Menu scripts are not reserved per page; `restore` is expected to handle
  them. The report records reserved counts and minimum free tiles.
- Over-dense pages without a line boundary are split at a token boundary with
  a forced `<NL2><PAGE>`.

### Verified

- Original 256 KiB target remains byte-identical.
- A converted message renders legibly: `どの歴史書を登録しますか?`
  (screenshots under `out/test/`).
- Deterministic random `$6800-$7FFF` still installs the overlay and renders.
- A 6000-frame save-RAM write watchpoint shows no base-game writes to
  `$6800-$7FFF`.

### Still open

- Town/field map CHR is overwritten by the kanji cache; restoring from the
  kana font is wrong for map tiles. A lazy CHR save/restore layer is the next
  blocking step (see `STATUS.md`).
- An NMI-based save/restore prototype was attempted and reverted: CHR access
  inside the NMI handler caused NMI re-entry/stack growth on the outdoor map.
- Visible-line redraws do not re-upload kanji after tile reuse.
- Inline scripts, tables, runtime names and UI screens remain unconverted.

## 2026-11-07 — kanji-target implementation pass


Baseline: `81d7307` (byte-identical 256 KiB reconstruction).

### Build targets

- Added `python decomp/build.py --target kanji`, producing
  `decomp/build/rom_kanji.nes` (524,304 bytes, 32 x 16 KiB PRG).
- The original target still produces
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Added `decomp/main_kanji.asm`, `decomp/banks/bank16_30.asm`, and a
  byte-level bank-15 patch step that preserves all original bank-15 label
  addresses.

### SUROM / MMC1

- NES 2.0 header now declares mapper 1 submapper 1 (SUROM).
- Bank 15 and bank 31 receive a 41-byte SUROM `write_prg_bank` replacement at
  `$C611` (inside an audited 102-byte unused data gap). `$C4B7` jumps to it.
- The switcher writes the outer bit through CHR bank 0 and the low four PRG
  bits through the PRG bank register.
- Bank 31 is a copy of patched bank 15 with the text-engine patches.

### Fixed-bank overlay (`bank 31 $E000`)

- Extended text dispatcher for `$EC-$EE` plus the original `$EF-$F7` table.
- Kanji cell handler using compiler-generated per-page slot records.
- NMI CHR upload hook and an NMI-entry upload path that also works while
  `nmi_busy` suppresses normal sound/VRAM work.
- Control-store hook and lazy kana restore hook.
- 8x16 `text_put_tile`-compatible rendering path (each 16x16 kanji is written
  as two adjacent native cells).

### Far text loader (bank 13 `$8317`)

- Each message in banks 10/11 is replaced by an 8-byte trampoline:
  `F8 17 03 <target bank> <target addr> <meta ptr>`.
- A 255-byte RAM-resident loader copies the kana font and page-slot metadata
  to SRAM, switches to text banks 18-21 and continues in the fixed bank.

### Font and text pipeline

- Added `tools/kanji_common.py`, `tools/kanji_font.py`, `tools/kanji_text.py`.
- Inventory: 718 kanji from the corrected draft and referenced tables.
- Font: DotGothic16 rendered at 16x16, emitted as 32-byte 1bpp glyphs.
- Text compiler reflows lines to 18 cells, splits over-dense pages, assigns
  four CHR tiles per distinct kanji, and emits:
  - banks 10/11: pointer tables + trampolines,
  - banks 22/23: page-slot metadata,
  - banks 18-21: converted message streams.
- Added `assets/fonts/kanji_index.tsv` and a contact sheet at
  `assets/fonts/kanji_16x16_ext.png`.

### Test harness

- Added `tools/mesen_run.py` (copies ROMs under `out/test` so real saves are
  never touched) and `tools/lua/` helper scripts.
- Verified the 512 KiB target boots and reaches the title/menu in Mesen.
- Verified the SUROM outer-bank switch and bank-31 overlay with synthetic
  test ROMs.

### Known blockers (see `STATUS.md`)

- The current CHR strategy reuses kana tiles; after a dialogue, window/UI
  drawing can see overwritten tiles because the window drawing path does not
  restore kana/window tiles.
- Inline bank-15 menu scripts remain kana and have no page metadata; they are
  not converted yet.
- Full dialogue proofreading and UI-screen conversion are not done.
