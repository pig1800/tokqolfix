# Current implementation status

Revision 19, 2026-11-09 (branch `rev10-wip`, uncommitted working tree).
Implemented by the planner after the revision-10 and revision-11 play
tests; see CHANGELOG for what each revision fixed.

## Builds

- Original 256 KiB ROM: byte-identical,
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Kanji 512 KiB SUROM ROM (16 KiB CHR RAM, 4 KiB CHR mode):
  `59bf7b5ac8bedd55112cde5a8c6cca79db38588b23fcd44d8453157ace50843a`.
- Fixed-bank hooks in five audited regions plus the rewritten reset setup
  (`$F00C-$F039`).  The largest region is `$C5A6-$C6D1`: the game's
  `load_text_graphics` rewritten in place, its palette tables moved to hack
  banks 23/24 at `$BF00`.  Hack code `$8000-$8BFF` plus a second segment at
  `$B900` (after the glyph tables), identical in every hack bank 23-25;
  overlay at `$B800` in the text banks.
- Text: revision-14 Opus re-conversion (`decomp/text/kanji_r14/`), laid out by
  `tools/kanji_layout.py` into `decomp/text/kanji_plan/bank1X_messages_kanji_r14.dtx`
  (the compiler's source when present); 830 glyphs including 々 (glyph banks 23-25),
  text in banks 18-22, 29, 30; 11 forced page splits, no relaxed messages.
- Kanji tiles: per page, the free kana tiles least exposed to game windows
  (unused by menus/names, then name-entry grid, submenu, officer/item
  names).  A message printed by menu code, or jumping into it, never
  borrows the kana of the menus that code opens (derived from the
  original banks 13-15; build fails on a conflict).
- Font: JF-Dot-Shinonome16; fallbacks listed in
  `assets/fonts/kanji_fallback.tsv` (DotGothic16 glyphs drawn 1 px lower).

## Runtime design

- **Idle cost (revision 15).** With no band, no request, no VRAM queue
  traffic and no CHR-animation step, `ef08_gate` skips the hack bank;
  `ef31_gate` skips the epilogue unless a band is shown or a split mode
  runs.  With no band the NMI only records stale band-page tiles; the next
  message start syncs them (`REQ_SYNC`, 1-8 frames on the test paths).
  Bank switches write the SUROM outer register only when the 256 KiB half
  changes (`$BFFF` marker).  Town walking, no message: NMI ~3,370 cycles
  per frame (original ~3,110).  While a message is shown the band's
  sprite-0 wait costs ~15,000-19,000 cycles per frame.
- **Pages.** CHR page 0 sprites, page 1 scene, page 2 band.  Page 2 equals
  page 1 except for kanji slots.  Every game CHR write is mirrored:
  block writes are copied page 1 -> page 2 right after they happen (main
  thread, rendering off); queue writes are marked stale and restored in
  vblank; kanji slots released by a message are restored the same way.
- **Band switch.** Sprite 0 sits on the window's top-border line; the NMI
  epilogue waits for the hit and selects page 2, so page 2 covers the
  window and everything below it.  The window position is computed per
  message from the engine's line address and the scroll.  The vblank hook
  selects page 1 again for the next frame (before its queue scan when the
  game flushed a large queue, so the top lines never show page 2).  The sprite-0 tile is the first
  unit whenever the band is requested and the tile is not in place, so the
  band is live before any glyph upload of the message completes.  OAM
  slot 0 belongs to the NMI: the game's `clear_oam_shadow` (screen fades)
  starts at slot 1 (revision 16b).
- **Battle pool (revision 18).**  The battle tile set leaves tiles
  `$A4-$DF` of the scene page blank and never shows them.  When graphics
  set 8 (battle) is loaded, the hack reads them back; all blank arms the
  pool, and any game write into them disarms it.  A message printed then,
  with no page over 15 kanji, puts its kanji there (entry k of a page in
  `$A4+4k..+3`, plane 0, scene page): no band, no sprite 0, no NMI wait.
  The engine's row renderer draws `$A4-$DF` as tiles (`render_ctl`).
  Everywhere else, and for a page over 15 kanji, the band page as below.
- **Sprite 0 follows the drawn frame (revision 17).**  The hook tail places
  sprite 0 for the next DMA and records the vertical scroll it used in
  `KANJI_SPR0`; the overlay marks it `SPR0_STALE` when it moves the window.
  If the main thread moved the screen before the next NMI (battle shake),
  that NMI's light unit places sprite 0 again and writes it to `OAMDATA`
  in the same vblank, then uploads one tile.  Heavy and CHR-animation
  frames cannot do this (no vblank left) and keep the DMA'd sprite.
- **Fixed-bank tables.** `$E6A9-$E6D0` (battle damage factors) and every
  other byte outside the registered ranges are the original's (revision
  16c); `$0100/$0101` are game RAM, the overlay's scratch is at
  `$0132/$0133` and `$0102/$0103`.
- **No cycles before the game's split code.**  Hooks sit after the
  `nmi_mode` branch (`$EF0B`, normal frames only) and in the epilogue
  (`$EF31`, after every split loop).
- **VRAM work only in vblank.**  One unit (a glyph tile, two when the queue
  is idle; one tile restore; the window probe; the sprite tile) in light
  frames (no CHR animation, <= 8 queued bytes); bulk while rendering is
  off.  Bookkeeping runs after the frame's last PPU access.  Measured from
  the hook entry, the latest light-frame entry (scanline 254.7) plus the
  costliest unit ends before the pre-render line.
- **NMI block write** (flush_palette's CHR-animation step, the only block
  write in the NMI): the fixed-bank hook selects page 1 directly
  (`chr1_scene`, lock protocol) and the NMI hook marks the 4 tiles stale
  from the animation pointer.  Queued CHR writes that land on page 2 after
  a band frame are replayed on page 1 from the queue ring.
- **Overlay.** Posts requests and waits frame by frame; never touches the
  PPU or a mapper register.  At a page start it keeps only the kanji of
  the three lines still on screen and restores this page's kana tiles that
  an earlier page used.  A message that continues an open window first
  scrolls the previous lines out with the engine's own scroll routine.
- **RAM.** State only in `$0131-$017F` and `$0100-$0103` (cleared at reset
  with `$0104-$0130`); no RAM code.  Pool state lives in spare bits:
  `KANJI_WIN_COL` bits 6-7 (armed, checked), `KANJI_PAGES_LEFT` bit 6
  (pool message).

## Gates on the final build

| Gate | Result |
|---|---|
| Original target | byte-identical |
| Palettes (`palette_check.py`) | every load equals the original routine on the original tables (8 loads incl. the town exterior; revision 12 fails) |
| `bank15_lint` | 16 ranges, bank 31 == bank 15; build fails if hook code leaves its gaps |
| Opening logo (raster split) | frames 2-294 pixel-identical to the original (6-frame boot offset) |
| Visible garble (`garble_check.lua`, 6 input timings) | 0 frames (revision 11: 16-460 frames per run) |
| Partner shop from the play-test state (`garble_state.lua`, 5 paths) | only the state's own garbled menu until each path redraws it (45-129 frames, same as revision 16c; revision 15b: 206-329 per path) |
| Save at the record office, fade out/in (`garble_state.lua`) | 0 frames (revision 16: 40) |
| Hack VRAM/OAM access vs vblank end (`vblank_deadline.lua`, standard path and three battle states) | 0 after the pre-render line; costliest unit 776 cycles from entry (16c: 777); pool check 533; `spr0fix` ends by 252.2 |
| CHR-animation NMIs (`anim_timing.lua`) | game's scroll/mask restore at scanline 260 (original 259; revision 11: 268) |
| Hack PPU access while rendering (`r11_diag.lua`) | 0 |
| Band switch scanline (`band_check.lua`) | 3,792 band frames, all on border-row line 1 |
| Band page vs scene page for shown tiles | 0 mismatching cells |
| Kana written over an active kanji tile | 0 |
| `ram_gate.lua` | 0 battery-RAM writes by the hack; 0 game writes to hack state; min SP `$13` |
| Stack at battle entry (`taint_check.lua`, normal and boss) | min SP `$0D` (revision 17: `$0B`, revision 18 before the fix `$09`; original `$1C`) |
| `mask_restore` | 0 |
| Message timeline | messages start at 607/888/1593/2367/3302 (original 607/888/1589/2359/3290) |
| `zp_check.lua` | `$10/$11` unchanged at every overlay exit (1,000 checks; the town's RNG differs by build) |
| Battles from three states (`garble_state.lua`: play-test, before a normal and a boss battle) | 0 frames, window closes and shake steps included (revision 17: 15 frames in 7 closes) |
| Sprite-0 hits from save states (`band_timing.lua`) | 0 misses: partner shop 600, save fade 2,200 (battles use the pool) |
| Battles from three states (`taint_check.lua`) | 0 game reads of hack-changed RAM, 0 game writes to hack state |
| Battle round from the play-test state (`taint_check.lua`, revision 16c) | 0 game reads of hack-changed RAM, 0 game writes to hack state; damage 26/22/4/9/3/7 (revision 16b: every hit killed) |
| Menu kana under kanji (compiler) | 0 conflicts |

## Known limits

- Boot is 6 frames longer and every scene load copies its CHR to the band
  page (about 470 cycles per tile).
- Kanji print a little slower than kana: each new kanji of a page waits
  for its glyph upload (2-4 frames).  The first history prompt finishes at
  frame 639 against 626 in the original.
- While the band is on, the NMI waits for the sprite-0 hit each frame, so
  the main thread gets about 95 scanlines per frame instead of about 200.
  No slowdown is visible on the tested paths.
- Each wait inside a kanji message flips to a fresh window (the original
  scrolls line by line); a message that continues a window also starts on
  a cleared window.
- Battle pool limits: a battle page with more than 15 kanji uses the band
  page, whose window closes can garble 1-3 frames (none such page exists
  yet).  The engine's line scroll blanks pool tiles; kanji messages clear
  the window instead of scrolling, so it is not reached.  The pool is
  verified on three battles only; a battle that shows tiles `$A4-$DF`
  would be reported by `pool_outside`.
- The band page is not told about CHR the game writes with direct `$2007`
  loops (the battle-entry dissolve); such tiles are not shown on the band
  page in the tested scenes.
- Runtime names (`<NAME_F3>`..`<NAME_F7>`: acting officer, item) print in
  kana from the game's tables; fixed names in the text are kanji.  The two
  fixed kana tails game code adds to a name in messages are kanji
  (`$D549` の兵, `$D565` の計; revision 19); menus stay kana.
- 16 KiB CHR RAM on MMC1 exists on no real board; CHR register 1 is written
  without the outer-bank bit.  Emulator-only until tested on hardware.

## Remaining work

1. Rework `qa_pages.py`/`qa_field.py`/`qa_sweep.py` for the band page (their
   checks read page 1) and regenerate `tools/lua/town_menu.mss`.
2. Coverage beyond the scripted path: battles, shops, castles, the officer
   scene (`nmi_mode = $80`), save slots 2/3, random power-on RAM, a second
   emulator.
3. Eyeball the two relaxed messages.
4. Phase 3/4 content and proofreading; hardware when an N8 exists.

## Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\band_check.lua --name band
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\r11_diag.lua   --name diag
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\ram_gate.lua   --name ram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\vblank_deadline.lua --name dead
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\anim_timing.lua --name anim
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\zp_check.lua   --name zp
python tools\garble_run.py decomp\build\rom_kanji.nes --offsets 0,5,11,19,29,40
# from a save state: SHOP_STATE=<.mss> SHOP_PATH=b,w,a,... SHOP_OUT=<dir>
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\garble_state.lua --name gs
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\taint_check.lua --name tnt
# battle states: out/user/r16c/rom_kanji_1.mss, out/user/r17/pre_battle_normal.mss, pre_battle_boss.mss
# vblank deadline from a save state: DL_STATE=<.mss> DL_PATH=... DL_FRAMES=2500 DL_OUT=<file>
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\band_timing.lua --name bt   # SHOP_STATE/SHOP_PATH, BT_OUT, BT_FRAMES
python tools\palette_check.py
python tools\lua_addrs.py tools\lua\band_check.lua tools\lua\vblank_deadline.lua tools\lua\zp_check.lua tools\lua\band_timing.lua
```

Outputs go to `out/test/r11/` and `out/test/r12/`.  Use a fresh `--name` per
ROM variant.  Run `lua_addrs.py` after any change to `hack.asm` (it
refreshes the hack addresses the gates hook).

## Source of truth

- `decomp/text/kanji_r14/batch_00.txt` .. `batch_07.txt` (with `STYLE.md` and
  `glossary.tsv`); `tools/kanji_layout.py` generates the compiler's
  `bank1X_messages_kanji_r14.dtx` from them.  The older `*_kanji_fixed.dtx`
  drafts are used only when the r14 files are absent.
- `JF-Dot-Shinonome16.ttf` (fallbacks: `DotGothic16-Regular.ttf`, MS Gothic)
