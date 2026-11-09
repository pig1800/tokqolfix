# Current implementation status

Revision 21, 2026-11-09 (branch `rev10-wip`, uncommitted working tree).
Implemented by the planner after the revision-10 and revision-11 play
tests; see CHANGELOG for what each revision fixed.

## Builds

- Original 256 KiB ROM: byte-identical,
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Kanji 512 KiB MMC3 ROM (mapper 4, NES 2.0, 16 KiB CHR RAM, CHR mode 1;
  revision 21): `92eb006ab4a3fa3ee616ea10527ca275cb447f9c07e6661f199b54446f0f10c7`.
- Fixed-bank hooks in audited regions plus the rewritten reset setup
  (`$F004-$F039`), the dead MMC1 routines (`$C460-$C47D`, `$C489-$C49D`,
  `$C4AD-$C4B9`) and the IRQ vector.  The largest region is `$C5A6-$C6D1`: the game's
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
  Town walking, no message: NMI ~3,370 cycles per frame (original
  ~3,110; measured on SUROM).  While a message is shown the band costs
  the scanline IRQ (~90 cycles) instead of the sprite-0 wait
  (15,000-19,000 cycles per frame up to revision 21a).
- **Mapper (revision 21).**  MMC3, PRG mode 0: every 16 KiB game bank is
  two 8 KiB halves (R6/R7), bank 31 is the fixed bank.  `set_bank_lock`
  and `restore_bank_after_nmi` keep their addresses and jump to
  `main_prg` / `nmi_prg`.  `$EB` (the MMC1 lock, used only by those
  routines) is the bank-select shadow `MMC3_SEL`: the main thread stores
  it before every `$8000` write, interrupt code writes `$8000` directly
  and leaves with `$8000 = MMC3_SEL | $80` (the NMI's last
  `restore_bank_after_nmi` does it).  The reset writes every MMC3 register
  from `$E000-$FFFF` before using `$C000-$DFFF`, then `cli`.
- **Pages.** CHR page 0 sprites (R2-R5), page 1 scene, page 2 band.  Only
  BG tiles `$00-$7F` switch (R0, 2 KiB); `$80-$FF` always show the scene
  page (R1), so they are never copied or stale (revision 21).  Page 2's
  lower half equals page 1's except for kanji slots.  Every game CHR write is mirrored:
  block writes are copied page 1 -> page 2 right after they happen (main
  thread, rendering off); queue writes are marked stale and restored in
  vblank; kanji slots released by a message are restored the same way.
- **Band switch (revision 21b).**  The MMC3 scanline IRQ selects page 2
  (R0) in the window's top border row, so page 2 covers the window and
  everything below it; the NMI selects page 1 again for the next frame.
  The NMI arms the counter after the frame's last PPU access (it also
  counts the A12 rises of vblank VRAM traffic): latch T + 2, T = the
  border row's first line (`KANJI_WIN_ROW * 8 - scroll_y`, modulo 240,
  16-208), computed for the frame about to be drawn.  Frames whose game
  queue flushed at most 40 bytes reach the arm before the pre-render
  line's clock; heavier frames and CHR-animation frames keep the IRQ's
  own re-arm for the same line one frame later (vblank CHR/palette
  writes can only make it early, onto the map above the window).  The
  IRQ does nothing while no band is shown or in busy mode (the main
  thread's CHR writes clock the counter too); busy, split and
  rendering-off frames disable it.  In Mesen the counter takes one more
  clock at line 0 on every other frame and one more when vblank ends with
  the PPU address below `$1000`: the switch lands in border lines 0-2,
  heavy frames up to 4 lines early, late arms up to +6.
- **Battle pool (revision 18).**  The battle tile set leaves tiles
  `$A4-$DF` of the scene page blank and never shows them.  When graphics
  set 8 (battle) is loaded, the hack reads them back; all blank arms the
  pool, and any game write into them disarms it.  A message printed then,
  with no page over 15 kanji, puts its kanji there (entry k of a page in
  `$A4+4k..+3`, plane 0, scene page): no band, no IRQ.
  The engine's row renderer draws `$A4-$DF` as tiles (`render_ctl`).
  Everywhere else, and for a page over 15 kanji, the band page as below.
  Revision 20: the battle window scrolls as in the original.  A page takes
  the lowest run of slots no pool tile in the window's lines shows (the
  first slot in `KANJI_UPLOADED+1` bits 0-3, at most 12 kanji a page); a
  page that does not fit clears the window first.  The engine's scroll
  copy keeps cells below `$FA` (`$D416`).
- **Fixed-bank tables.** `$E6A9-$E6D0` (battle damage factors) and every
  other byte outside the registered ranges are the original's (revision
  16c); `$0100/$0101` are game RAM, the overlay's scratch is at
  `$0132/$0133` and `$0102/$0103`.
- **No cycles before the game's split code.**  Hooks sit after the
  `nmi_mode` branch (`$EF0B`, normal frames only) and in the epilogue
  (`$EF31`, after every split loop).
- **VRAM work only in vblank.**  One unit (a glyph tile, two when the queue
  is idle; one tile restore; the window probe) in light
  frames (no CHR animation, <= 8 queued bytes); bulk while rendering is
  off.  Bookkeeping runs after the frame's last PPU access.  Measured from
  the hook entry, the latest light-frame entry (scanline 254.7) plus the
  costliest unit ends before the pre-render line.
- **NMI block write** (flush_palette's CHR-animation step, the only block
  write in the NMI): the fixed-bank hook selects page 1 directly
  (`chr1_scene`, one R0 write) and the NMI hook marks the 4 tiles stale
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
| `bank15_lint` | 19 ranges, bank 31 == bank 15, mapper 4; build fails if hook code leaves its gaps |
| Opening logo (raster split) | frames 11-301 pixel-identical to the original, every frame compared (3-frame boot offset; 6 before revision 21) |
| Visible garble (`garble_check.lua`, 6 input timings) | 0 frames (revision 11: 16-460 frames per run) |
| Partner shop from the play-test state (`garble_state.lua`, 5 paths) | only the state's own garbled menu until each path redraws it (42-123 frames; revision 20: 49-130; revision 15b: 206-329 per path) |
| Save at the record office, fade out/in (`garble_state.lua`) | 0 frames (revision 16: 40) |
| Hack VRAM/OAM access vs vblank end (`vblank_deadline.lua`, standard path and three battle states) | 0 after the pre-render line; costliest unit 733 cycles from entry (revision 20: 776) |
| Game's scroll/mask restore (`anim_timing.lua`) | by scanline 259, same histogram as revision 20 (the current path has no CHR-animation step; revision 11: 268) |
| Hack PPU access while rendering (`r11_diag.lua`) | 0 |
| Band switch scanline (`band_check.lua`) | 3,596 IRQ switches: border lines 0-2 in 3,453, +3/+6 in 61, 1-4 lines early in 82 (heavy frames) |
| Band page vs scene page for shown tiles | 0 mismatching cells |
| Kana written over an active kanji tile | 0 |
| `ram_gate.lua` | 0 battery-RAM writes by the hack; 0 game writes to hack state; min SP `$16` |
| Stack at battle entry (`taint_check.lua`, normal and boss) | min SP `$0F` (revision 20: `$0D`; revision 17: `$0B`; original `$1C`) |
| `mask_restore` | 0 |
| Message timeline | messages start at 608/888/1589/2363/3297 (original 607/888/1589/2359/3290; revision 20: 607/888/1593/2367/3302) |
| `zp_check.lua` | `$10/$11` unchanged at every overlay exit (836 checks; the town's RNG differs by build) |
| Battles from three states (`garble_state.lua`: play-test, before a normal and a boss battle) and a forced level-up (`SHOP_POKE`), converted states (`out/user/m3/`) | 0 frames, window closes, shake steps and scrolling included (revision 17: 15 frames in 7 closes) |
| Battles from three states (`taint_check.lua`) | 0 game reads of hack-changed RAM, 0 game writes to hack state |
| Battle round from the play-test state (`taint_check.lua`, revision 16c) | 0 game reads of hack-changed RAM, 0 game writes to hack state; damage 26/22/4/9/3/7 (revision 16b: every hit killed) |
| Menu kana under kanji (compiler) | 0 conflicts |

## Known limits

- Boot is 6 frames longer and every scene load copies its CHR to the band
  page (about 470 cycles per tile).
- Kanji print a little slower than kana: each new kanji of a page waits
  for its glyph upload (2-4 frames).  The first history prompt finishes at
  frame 639 against 626 in the original.
- The band switch follows the IRQ arm: in frames whose game queue flushed
  more than 40 bytes (window drawn or erased) it comes 1-4 lines early,
  onto the map above the window, where the band page shows the scene's
  tiles; a kanji or stale tile shown there would show from page 2 for
  that frame.  The IRQ timing is Mesen's (see Band switch).
- Outside battle, each wait inside a kanji message flips to a fresh window
  (the original scrolls line by line); a message that continues a window
  also starts on a cleared window.  In battle the window scrolls; it is
  cleared only when the next page's kanji do not fit beside the ones on
  screen (not seen on the tested paths).
- Battle pool limits: a battle page with more than 12 kanji uses the band
  page, whose window closes can garble 1-3 frames (none such page exists
  yet).  The pool is verified on four battle runs only; a battle that
  shows tiles `$A4-$DF` would be reported by `pool_outside`.
- The band page is not told about CHR the game writes with direct `$2007`
  loops (the battle-entry dissolve); such tiles are not shown on the band
  page in the tested scenes.
- Runtime names (`<NAME_F3>`..`<NAME_F7>`: acting officer, item) print in
  kana from the game's tables; fixed names in the text are kanji.  The two
  fixed kana tails game code adds to a name in messages are kanji
  (`$D549` の兵, `$D565` の計; revision 19); menus stay kana.
- 16 KiB CHR RAM: the MMC3 CHR-RAM boards (TGROM/TNROM) have 8 KiB.  The
  band's 2 KiB cannot live in the sprite page: the game shows sprite tiles
  `$80-$CF` (history screen, battle) and writes sprite CHR `$0800-$0FFF`.
  Emulator-only (NES 2.0 CHR-RAM size) until a board with more CHR RAM.
- Save states of the SUROM builds need `tools/mss_to_mmc3.py`; battery
  saves (`.sav`) work unchanged.

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
# states: SUROM states converted by tools/mss_to_mmc3.py into out/user/m3/
#   (r16c_rom_kanji_1, r17_pre_battle_normal, r17_pre_battle_boss, r16b_rom_kanji_1, shop_k_rom_kanji_1)
python -I tools\mss_to_mmc3.py <SUROM state.mss> <MMC3 state.mss>
# all gates: sh tools/run_gates.sh (GDIR=<out/test subdir> TAG=<name suffix>)
# vblank deadline from a save state: DL_STATE=<.mss> DL_PATH=... DL_FRAMES=2500 DL_OUT=<file>
python tools\palette_check.py
python tools\lua_addrs.py tools\lua\band_check.lua tools\lua\vblank_deadline.lua tools\lua\zp_check.lua tools\lua\band_timing.lua
```

Outputs go to `out/test/r11/` and `out/test/r12/`.  Use a fresh `--name` per
ROM variant.  Run `lua_addrs.py` after any change to `hack.asm` (it
refreshes the hack addresses the gates hook).

## Source of truth

- Text: `decomp/text/kanji_plan/bank10_messages_kanji_r14.dtx` and
  `bank11_messages_kanji_r14.dtx`.  Edit them and run
  `python decomp\build.py --target kanji` (about 10 seconds; the build
  reports lines over the window width and forced page splits).  They were
  generated once by `tools/kanji_layout.py` from
  `decomp/text/kanji_r14/batch_*.txt`, which now refuses to overwrite them
  without `--force`.  The older `*_kanji_fixed.dtx` drafts are used only
  when the r14 files are absent.
- `JF-Dot-Shinonome16.ttf` (fallbacks: `DotGothic16-Regular.ttf`, MS Gothic)
