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
| 1 | `b14_calc_tactic_points`, `compact_items_actor` | tactic points; the item list compacted |
| 2 | `battle_intro_screen` (`$CED2`, fixed bank; also used by `b14_army_status_screen`) | window, fade, clear the nametables; `copy_to_vram` bank 9: tiles `$00-$0F` (digits, borders; the hack's block writer supplies them) and `$E0-$FE` (bars, S.P); `load_text_graphics` index 8 (palette) |
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

# SITREP / instruction book: kanji without CHR switching (info screen, battle)

Updated 2026-11-11 (second round).  No code yet; work starts after the
compaction.  "Decisions" and "Plan" are the user's; "Verified" is what
the code and the traces say (kanji ROM `5449ff00...`; traces and dumps in
`out/test/cinfo/`: `jt1`/`jt2` map path, `jt4` battle -> info -> battle,
`info_230`, `bi_dump_260/470/600`, `bb_*` (boss and r16c battles),
`bs_dump_410` (battle item subwindow), `glyph_check.txt`).

## Decisions (user)

1. On the battle path the info screen uses the battle pool `$A4-$DF`
   for its plane-0 kanji.  The next battle message overwrites the pool
   anyway.
2. Kanji names for items and tactics: `kanjiwordlist.csv` (repo root;
   cp932, tab-separated: type, kana, kanji; types weapon, armor, helmet,
   tactic, consumable, keyitem).  Items get their kanji only after the
   main text routine is overhauled (the current one would break).
3. A 16x16 kanji is 4 consecutive tiles in 8x16 order: `t` top-left,
   `t+1` bottom-left, `t+2` top-right, `t+3` bottom-right (the original
   name layout, e.g. `10 12 / 11 13`).
4. Move the half-bar tile `$F3` to `$FB` (not `$FC`).  `$FC-$FF` stays a
   whole group: one more kanji in battle.  On the info screen the groups
   `$E0`, `$E4`, `$E8`, `$EC`, `$F0`, `$FC` become fully volatile (6
   kanji); `$F4-$F7` and `$F8-$FB` keep the bars and S.P.
5. Every tactic starts with 2 kanji: the first 2 kanji of each tactic
   line take fixed plane-1 slots.  An officer without tactics: skip.
6. Battle gauge palette: P2 colour 1 = `$0F`, colour 3 = colour 2 (the
   gauge colour), so the gauges show plane 1 only and plane 0 of their
   tiles is free.  The gauge colour changes with the HP tier (late-game
   five-digit HP: light green); see "Gauge colour" below.
7. All window borders move down by one tile, on the info screen and in
   battle, so 16-pixel kanji lines sit on the attribute grid.  Done in the
   coding phase.
8. Battle item subwindow worst case: 23 distinct kanji (the user's count).
9. In battle, `$EF-$F4` and `$F9-$FA` are unused, and `$F5-$F8` appear
   only in the tactic subwindow, never with the items.  Battle shows only
   "SP" (`$F6` `$F7`); M (`$F5`) and the dot (`$F8`) are info-screen only.
   S and P move to plane 1, so plane 0 of all of `$A4-$FF` (23 groups)
   becomes the battle's kanji area.
10. `kanjiwordlist.csv`: めいば is 名馬 (fixed by the user).
11. Every UI glyph of the `$E0-$FE` block goes to plane 1: the bars
    `$F3`/`$F4`, M `$F5`, S `$F6`, P `$F7`, dot `$F8`.  Done in the ROM
    data (the kanji target's copy of the bank-9 block), not by code.  The
    info screen's P2 becomes `0F 0F 17 17` (palette data).  One layout for
    both screens.  This supersedes decision 4 (`$F3` -> `$FB` is dropped):
    plane 0 of all of `$E0-$FF` is then free on the info screen too.
12. "MSP" has not been seen anywhere; only "S.P" on the info screen.
    Deal with MSP if it ever shows up.
13. After this work, the battle and the info screen use no scanline IRQ
    at all (no band page, no split).  The IRQ glitches seen there now are
    expected to go away with it; do not chase them separately.
14. Two-step execution: step A (after the next compaction) decompiles the
    code still held in data blobs; then compact again; step B implements.

## Plan: info screen

- Plane 1 of the font tiles `$10-$7F` = 28 kanji slots (P1 cells,
  16x16 aligned):
  - `$10-$1B`: the officer's name, up to 3 kanji (original engine, `$A9`
    = `$10`).
  - `$1C-$4F`: 13 fixed label kanji 武 力 知 攻 撃 装 度 兵 士 数 備 策 略
    (武力 知力 攻撃 武装度 兵士数 装備 策略; S.P stays).
  - `$50-$7F`: tactic line n (0-5) -> slots `$50+8n` (first kanji) and
    `$54+8n` (second).
- Plane 0 (P0 cells, no alignment needed): equipment names, and 計 of
  the tactics.  Room: the 6 volatile groups in `$E0-$FF` plus the pool
  `$A4-$DF` (15) = 21 kanji.  Worst case need: 9 equipment kanji + 計 =
  10.  On the map path `$A4-$DF` hold leftover map tiles that the screen
  does not show, and the map reloads them on exit, so the same room
  exists there.
- A kanji map (WRAM) so a kanji already in CHR is reused, not rewritten.
- Exits:
  - info -> map: nothing to revert (the map reloads `$80-$FE` and the
    whole font page).
  - info -> battle: rewrite plane 1 of every battle name slot.  Plane 0
    of `$A4-$FF` is the battle's volatile kanji area (decisions 6 and 9);
    the battle restores its involatile command kanji when the panel
    returns.

## Plan: battle screen (user; implemented, see "Step B result: the battle screen")

- The command panel needs 15 fixed (involatile) kanji:
  戦 策 略 防 御 道 具 総 攻 撃 退 却 武 将 残.
- Subwindows (tactics, items) and messages may borrow involatile slots.
  Track which involatile slots were changed; restore them when a
  subwindow closes and when the command panel is shown again after a
  round.  The item subwindow covers the whole command panel; the tactic
  window leaves only 道具 visible.
- "Usable kanji slots may be surprisingly low" (user).
- Kanji area in battle: plane 0 of `$A4-$FF`, 23 groups of 4 tiles
  (decisions 6 and 9): the pool `$A4-$DF`, the gauge tiles `$E0-$EE`
  (their plane 0 hidden by the new P2), and `$EF-$FF`.  It holds the 15
  involatile command kanji, the messages and the subwindows.  The
  revision-18 pool logic (blank check, `$A4-$DF` only) gives way to one
  managed slot table for the whole area.
- S and P in plane 1 of `$F6`/`$F7`; their 16x16 cell must use a palette
  that shows plane 1 and must hold no plane-0 glyph.  The info screen
  uploads the same block, so its "S.P" label (`$F6 $F8 $F7`, row 12,
  columns 10-12) needs a P1 cell too, and the dot then has to be in plane 1
  as well (M likewise, wherever "MSP" is shown).

## Verified

Name kanji (original engine):
- `put_officer_name` (`$D4A1`, formerly `load_party_member_stats`), `loc_D4C9`
  (fixed bank).  Officer record
  (`$F3`, bank 12): byte `$10` = per-kanji bank bits, `$11-$13` = up to 3
  glyph indices (`$FF` ends).  Source bank 1 or 2, `$8000 + index * 32`.
  CHR stream mode 2 (`vram_put_run` with C set reads 8 bytes, so plane 0
  is kept; then 8 bytes go to plane 1).  Destination: bump pointer `$A9`,
  +4 tiles per kanji; the tile numbers also go into `$0300`/`$0318`.
- Battle setup `battle_setup_names` (`$E09B`): `$A9` = `$10`, then every name in order, no
  deduplication (兵士 x3 = 6 slots), no bound check.  Kanji 29 and 30
  would land in plane 1 of the portrait tiles `$80-$87` (the next
  portrait upload overwrites them).
- Info screen: `$A9` = `$10` (bank 14 `$8545`).
- Exit to battle: `b14_battle_officer_info` (bank 14 `$AA1A-$AA60`, the
  battle-side wrapper; it runs the info screen `b14_officer_info_screen`,
  `$8518`).  Afterwards `$A9` = `$10` and the
  names of battle slots 0 and 1 are re-streamed (`put_officer_name_actor` `$D49F`, `put_officer_name` `$D4A1`): 4-6
  kanji, which always cover `$10-$1B`.  The new plan needs every slot
  re-streamed: record (glyph index, bank) per slot when the battle
  allocates, or replay its loop (`$E0A3-$E113`).
- Map path: the map entry runs `$84F8` -> `b14_party_status_update`
  (`$84FE`); the battle wrapper calls `$8518` directly.

CHR tiles `$E0-$FF`:
- `$E0-$EE` plane 1 only (battle HP gauges).  `$EF-$FA` plane 0 only
  (`$F3` half bar, `$F4` full bar, `$F5`-`$F8` "M S P .", others).
  `$FB`, `$FC`, `$FE` blank; `$FD` plane 1 only; `$FF` blank in battle.
- Entering the info screen uploads `$E0-$FE` (bank 9, 496 bytes); leaving
  for the battle does not, and the battle's own tiles are the same data.
  Battle CHR before and after the info screen: all 256 BG tiles equal.
- `$F3` is referenced once, bank 14 `$85CE` `lda #$F3` (bar loop: `$F4`
  per 26 points, `$F3` for a remainder of 13 or more).  `$FB` is not used
  as a tile in code (`lda #$FB` in bank 7 is a palette value).  The move:
  that immediate, and the two patterns in bank 9's `$1E00` block.
- Exit to map reloads `$1800-$1FEF` (tiles `$80-$FE`; bank 4 in the
  town) and the whole font page.  `$FF` is not reloaded.

Gauge colour (bank 14 `b14_battle_gauge_scale`, `$ADB5`; tier pick `$AE10-$AE45`):
- The max HP is compared with 500, 2001, 5001, 10001, 15001 (tables
  `$AE58` high / `$AE5D` low bytes, `sub24_inline_clamped` / `add24_inline`
  with inline arguments); tier X 0-5 picks units per gauge segment (`$AE4C`/`$AE52`:
  10, 40, 100, 200, 300, 400 -> `$76`/`$77`) and the colour (`$AE46`:
  `25 27 38 31 21 2A`; `$2A` green for 15001 and up), stored to `$03EA`
  (P2 colour 2) and `$3D` at `$AE40`.
- The base comes from `load_text_graphics` set 8 (hack bank copy at
  `$BF00`): P2 = `0F 17 0F 17`.  The same set serves the info screen,
  whose bars `$F3`/`$F4` are plane 0 in P2 (brown `$17`).
- The battle -> info exit wrapper saves and restores only `$03EA`
  (`$AA1F` / `$AA53`).
- For decision 6: `$AE40` must also store colour 3 and clear colour 1,
  and the exit wrapper must restore all three.  P2 colour 1/3 is used by
  nothing else in battle (every P2 cell held a gauge tile or blank).

Tactic subwindow title (bank 15 `$EB46`, a `text_init` window template in
`data_E8CA`): `6D 0C 0C 0C | 23 14 32 (のこり) 0A | F6 F7 (SP) | 0A x4 |
0C x5 6E`, 20 tiles.  This のこり is the 残 of the 15 command kanji.  S and
P sit at offsets 8 and 9 from the left corner: their 16x16 cell holds
only S and P when the window's left column is even; the remaining-SP
digits follow (digits have both planes, any palette shows them).  Bank 14
`$976A` holds two more strings, "SP" and "MSP" (`$22` + a 16-bit
position); not yet traced to a screen.

Battle palettes and layout:
- Battle P2 = `0F 17 25 17` in every battle frame sampled (normal, boss,
  r16c).  P2 cells hold only blank and gauge tiles (`$E0-$EE`).  Gauges
  are plane 1 (colour 2 = `$25`); a plane-0 bit would show colour 1 or 3
  (`$17`).  So plane 0 of `$E0-$EE` is visible in battle as it stands.
- Command panel: window columns 10-24, rows 18-27; text columns 12 and
  18; kana rows 20/22/24/26 with dakuten rows 19/21/23/25.  P0 cells.
- Item subwindow: columns 10-29, rows 18-27 (covers the command panel);
  two columns of names (12 and 21), kana rows 20/22/24/26: up to 8 items
  (8 item slots per officer).  Seen with たんけん / けん.
- Tactic subwindow: not seen; the state's party has no strategist
  (軍師がおりません).
- Battle message kanji (hack, revision 18 battle pool): plane 0 of
  `$A4+4k..+3`, used once the hack has read the tiles back blank
  (`WINCOL_POOL_OK`), restored to blank in later NMIs (`KANJI_STALE_HI`).
  The info screen sets `text_graphics_index` 8 = `POOL_SET`.  The new
  design replaces the blank check with the managed slot table.

Band page: font tiles `$00-$7F` exist twice (page 1 and the band page 2,
differences in `KANJI_STALE`).  On battle -> info the hack copied tile
`$18` page 1 -> page 2 (`restore_tile`).  Plane-1 writes are best made
after the hack's pending copies (a copy of a label tile would stay in page
2 after the revert; invisible in P0 band cells).

Word list (`kanjiwordlist.csv`, 83 entries; `glyph_check.txt`):
- 30 tactics, all "XXの計" (2 kanji + の + 計); 43 distinct leading kanji.
- Equipment (19 weapons, 7 armor, 8 helmets): all start with a kanji,
  at most 3 kanji, at most 7 cells wide (fits both info windows).
- Only non-kanji besides の: 守りの煙り (consumable).
- 133 distinct kanji with the labels and commands; 32 are not in the
  current kanji font (`assets/fonts/kanji_index.tsv`):
  棍斧槍矛叉弩蛇槌竜皮胴銅甲鉢帽兜鋼練仙炎熱柔倍洪路還丹招魂煙札簿.
  The font build must add them.

Info screen layout with aligned plane-1 kanji (attribute cells start on
even rows):
- Labels at rows 4-5, 6-7, 8-9, 10-11 (column 10); S.P stays at row 12;
  兵士数 moves from row 15 to rows 14-15.
- 策略 title in the top border at rows 14-15; 6 tactic lines at rows
  16-17 ... 26-27.  The bottom border (now row 27) moves to row 28.
- 装備 title at rows 18-19; equipment lines at rows 20-21, 22-23,
  24-25.  The bottom border (now row 25) moves to row 26.
- Kana in a 16-pixel line go in the lower row (as in the battle
  messages: kanji rows 19-20, kana row 20).

Bank 15 `$E000-$E370` and bank 14 `$A800-$AFFF` are source since step A
(see "Step A result").

WRAM: 141 bytes free at `$7F73-$7FFF` (canvas code installed): the panel
kanji map (about 16 x 2 bytes) plus a battle-name record (28 x 2) fit.

## Step A result (2026-11-11)

Done.  The battle and info-screen code is source now; both builds are
unchanged (original `40f19e17...` byte-identical, kanji `5449ff00...`,
bank15 lint OK).

Capture: 12 runs on the kanji build (`tools/lua/cdl_run.lua`), mapped onto
the original PRG (`tools/map_kanji_cdl.py`: banks 0-14 at the same offsets,
the fixed bank from bank 31, code bits only, only where the bytes equal the
original) and ORed into `out/cdl_combined3.bin` (the new default CDL).
States: the user's slot 1 (battle against 2 盗賊 with a strategist, tactic
window open) and `out/user/m5` `r17_pre_battle_normal` / `_boss`.  Paths:
tactic subwindow, a tactic round (わんかの計), both command windows,
ぶしょう -> info (enemy officer) -> battle, item subwindow, defend, retreat,
all-out attack to victory (exp, gold), map menu ぶしょう -> info (劉備,
tactics and equipment) -> map, battle starts (with a surprise attack).
In battle, ぶしょう can only target enemy slots.

Generator fixes (`tools/trace6502.py`, `tools/decompile.py`):
- inline words: every routine that starts with `fetch_inline_word` takes a
  word after its JSR (`copy_to_vram`, `read_inline_rect`,
  `read_inline_block_3`, the 24-bit `add24_inline` / `sub24_inline_clamped`
  helpers), not only `text_print_inline` / `draw_string`;
- `call_inline_block` blocks are decoded by their own control flow inside
  the 255 copied bytes (several `return_inline_block` exits), each
  `jsr return_inline_block` is followed by its resume word, and the main
  trace continues at the resume addresses; a block's calls into
  `$8000-$BFFF` belong to the bank it maps (no labels, no "called by");
- the 255-byte block copy no longer makes the code after a block "data";
- `dispatch_return_table` (`$C10C`) does not return; the item-menu and
  item-effect tables (`$8748`, `$8988`) are listed;
- bank 14 code may call anywhere in bank 14; fixed-bank routines called
  only from banked code are seeded.

Coverage (code bytes): bank 14 2,311 -> 11,761 (the blobs left, 4.4 KB,
are tables, window and nametable records); bank 15 10,446 -> 12,004;
bank 13 2,557 -> 2,663; bank 8 2,278 -> 2,327; bank 7 796 -> 882.

Renamed (the old names were wrong):

| Address | Old | New |
|---|---|---|
| `$C15B` / `$C15F` | `rng_seed` / `rng_next` | `mul16_by_u8` / `mul16x16_shr8` (+ `mul24x16_shr8` `$C163`) |
| `$C1B3` | `mul16x8_shift` | `div16_by_u8` |
| `$D4A1` | `load_party_member_stats` | `put_officer_name` (kana, or kanji glyphs streamed to `$A9`) |
| `$D5FE` | `load_party_member_record` | `compact_items_actor` |
| `$FA10` / `$FA3E` | `read_inline_offset` / `load_battle_graphics` | `add24_inline` / `sub24_inline_clamped` |
| `$8000` | `b14_game_bank_entry` | `b14_field_cmd_talk` (field menu table `$F1C3`) |
| `$959E` | `b14_field_transition_a` | `b14_army_status_screen` (Select on the map) |
| `$9B73` / `$9B79` | `b14_field_transition_b` / `_body` | `b14_battle_entry` / `b14_battle_run` |
| `$B855` / `$B863` | `b14_find_injured_member` / `b14_calc_party_stat` | `b14_calc_strategist_tactic_pts` / `b14_calc_tactic_points` |
| `$BF09`, `$BF46`, `$BF66` | `b14_battle_setup`, `b14_get_item_category`, `b14_draw_battle_status` | `b14_field_load_area_screen`, `b14_field_get_area_tileset`, `b14_field_play_area_music` |

Labels for step B:

| Label | Address | Role |
|---|---|---|
| `battle_setup_slots` | `$DF04` | battle setup (enemy slots, then the two parts below) |
| `battle_setup_names` | `$E09B` | `$A9` = `$10`; loop `$E0A3-$E113` over the 10 slots: sprite, name (`put_officer_name_actor`), troops |
| `battle_draw_slot_troops` | `$E200` | troop number and gauge (tiles `$E0-$EE`) |
| `put_officer_name` | `$D4A1` | name of officer Y; kanji path `loc_D4C9` when `$AA` != 0 |
| `put_officer_name_actor` / `_target` | `$D49F` / `$D49A` | for `text_actor` / `text_target` |
| `b14_battle_build_lineup` | `$9C87` | calls `battle_setup_slots`, then `$AA` = 0 (`$9CC9`) |
| `b14_battle_start` | `$9B89` | `battle_intro_screen_body` (`$CEDA`: CHR `$E0-$FE`, palette set 8) |
| `b14_battle_command_panel` / `_full` | `$9D92` / `$9D9C` | window `$11` (first command of a round, two columns) or `$12` |
| `b14_battle_item_subwindow` | `$9E2D` | window `$16`, 8 x CALL `b14_wincb_item_list_line` (`$8691`) |
| `b14_battle_tactic_subwindow` | `$9EAB` | window `$17`: title (のこり S P, template `$EB46`), CALL `b14_wincb_tactic_sp_left` (`$968A`), 6 x CALL `b14_text_call_tactic_name` (`$B723`) |
| `b14_battle_open_list_window` | `$A590` | opens `$16` / `$17` and waits |
| `b14_battle_show_actor_portrait` | `$ABD4` | portrait tiles `$80-$A3` (`load_actor_portrait` `$CF96`) |
| `b14_battle_open_msg_window` / `b14_battle_close_msg_window` | `$ABEB` / `$ABFF` | battle message window `$01` / `$15`, blank `$13` / `$14` |
| `b14_battle_officer_info` | `$AA1A` | ぶしょう in battle: `b14_officer_info_screen`, then `$A9` = `$10`, names of slots 0 and 1, `$03EA` restored |
| `b14_officer_info_screen` | `$8518` | the info screen (both paths) |
| `b14_field_officer_info` | `$84F8` | the map path |
| `b14_wincb_stat_value_bar` | `$857B` | stat digits and bars (`lda #$F3` at `$85CE`) |
| `b14_wincb_sp_label` | `$8616` | S . P (`$F6 $F8 $F7`) |
| `b14_battle_gauge_scale` | `$ADB5` | gauge scale and colour; tier pick `$AE10`, `sta $03EA` at `$AE40` |

Facts found on the way:
- The original prints battle-message names in kana: `$AA` is cleared at
  `$9CC9` right after `battle_setup_slots`.  Only `battle_setup_names` and
  `b14_battle_officer_info` stream name kanji (the kanji build's message
  kanji are the hack's).
- The info screen draws window `$1B` with `$AA` = 0 (kana), then sets `$AA`
  and `$A9` = `$10` for window `$08` (kanji name), `$8543-$854B`.
- `b14_army_status_screen` (`$959E`, Select on the map) also shows kanji:
  plane 1 of tiles `$C0-$D7` from bank 1 (`b14_inline_upload_status_kanji`)
  and names through `$A9` = `$10`.  Not covered by the plan yet.
- Palette writes in these paths: only `b14_battle_gauge_scale`
  (`$AE33-$AE45`) and a scripted lightning flash (`$B273-$B28F`).
- Bank 13 `$986A` (step A item 3): part of a picture (rows `$2064-$21C4`)
  drawn at bank 13 `$9677-$96B0` after that screen loads its own tiles
  `$80-$FF` from bank 3.  Its `$EF-$F9` are picture tiles, not the bank-9
  glyphs: decision 11 does not touch it.

## Step B result: the info screen (2026-11-11)

Work order items 1-6 are done; item 7 (the battle screen) is done too (next
section).
The original 256 KiB build is still byte-identical (`40f19e17...`).  The
second round applied the user's layout and behaviour changes (listed
below).

The screen (map path, 劉備; battle path, enemy officers):

| Rows | Columns | Content |
|---|---|---|
| 4-11 | 10-15 | 武力 知力 攻撃 武装度, plane-1 kanji (labels `$1C-$4F`) |
| 4, 6, 8, 10 | 17-19, 21-30 | their values, then the bars (the lines' upper row) |
| 12 | 10-12, 17-19, 21- | S.P (plane 1), value, bar |
| 15-16 | 2-7 | 兵士数 (plane 1); the troop maximum in row 15, columns 8-13 |
| 14-15 | 21-24 | 策略 on the tactic window's top border (row 15; window columns 16-29, bottom row 28) |
| 16-27 | 18-24 | tactic lines: two plane-1 kanji (`$50+8n`, `$54+8n`), の in the lower row, plane-0 計 |
| 18-19 | 7-10 | 装備 on the equipment window's top border (row 19; window columns 2-15, bottom row 26) |
| 20-25 | 4- | equipment names: plane-0 kanji in the pool, の in the lower row |

The window titles sit one column right of an even column.  The border tiles
show in either plane, so the three cells under each title are P1; the
attribute layout is `INFO_ATTR_CELLS` in `kanji_build.py`.

How it works:
- **UI bank 28** (`tools/asm/ui.asm`) holds the renderer, its own copy of
  the 100 UI glyphs, and the item and tactic kanji tables.  The tables and
  glyphs come from `ui_data.inc`, which `kanji_build.build_ui_data`
  generates from `kanjiwordlist.csv`, the game's bank-12 names, the
  こうげき table (bank 14 `$8602`) and `INFO_ATTR_CELLS`.
- **`call_ui`** (fixed bank `$C48D`, in the free gap `$C489-$C49D`) maps
  bank 28 under the lock protocol and calls `$8000` with X = function.
  `call_ui_army` is at `$C489`.
- **The screen stays black until it is complete.**  The driver runs
  `battle_intro_screen`, then the portrait (`status_message`'s string and
  `text_load_page`, without `loc_C139`'s rendering-on), then the name
  windows `$1B` and `$08`.  Then `UIF_INFO_DRAW` uploads the 13 label
  kanji, the tactic kanji and the plane-0 kanji, and writes the rest of the
  layout and the attribute table directly, in busy mode as the game's
  `copy_to_vram` does.  Only then does `screen_fade_in_step` turn rendering
  on.  Windows `$2D`, `$09`, `$0B`, `$0A` and the attribute and dakuten
  strings are no longer called.
- **Busy-mode build** (QoL, after item 8).  The game's steps above wait
  with `wait_vblank`, one queue chunk per frame: the portrait 7 frames,
  the name windows and the name's CHR stream 4, plus single waits.  With
  the screen off that pacing is not needed: `wait_vblank`'s busy path
  (`nmi_busy` set) flushes the queue and the stream at once.
  `UIF_INFO_BUSY` (after `battle_intro_screen`) enters busy mode, and
  `UIF_INFO_DRAW`'s `ppu_end` leaves it.  The black period is 5 frames on
  the battle path (was 15) and 6 on the map path (was 16): what is left is
  `battle_intro_screen`'s own last wait and about 3 frames of work (the
  portrait, the name stream, the UI draw).  `UIF_INFO_BUSY` also sets
  `UI_NOMIR`: the direct stream goes through the block writer, which would
  otherwise mirror the name glyphs to the band page.  The finished screen
  is byte-identical to before (all PPU memory, the 16 KiB of CHR RAM, the
  palette), on both paths and after the return to the map; gates as after
  item 8 (`out/test/stepD_g2`; the battle -> info -> battle path's min SP
  `$0B`, the same as before).
- **Plane-0 kanji** take the pool `$A4-$DF`, one group per distinct kanji.
- **The battle path:**
  - `UIF_BINFO_ENTER` sets the path flag, `text_busy` = 0 and keeps P2
    colours 1-3.
  - `UIF_BINFO_EXIT` (rendering off, busy mode) does three things:
    - It reads each battle slot's name in the battle nametable
      (`data_E17C` / `data_E186`).  When a kanji of a name lies in a
      plane-1 group the screen wrote, it streams that name again with the
      game's `put_officer_name` to the same tiles.  The groups written are
      `$10-$4F`, plus `$50+8n` / `$54+8n` for the tactic lines drawn.  In
      busy mode its `wait_vblank` flushes at once, so no frame is spent.
    - It clears the pool (both planes) and marks it checked and blank, so
      the next battle message uses the pool, not the band page.
    - It restores P2 colours 1-3.
  - This replaces the original's streaming of slots 0 and 1.  No CHR RAM
    beyond the two pattern tables is used.
- **No band-page mirroring in the battle or the info screen:**
  - `UI_NOMIR` is a one-shot flag.  `UIF_INFO_ENTER` sets it before
    `battle_intro_screen`, and so does the battle start
    (`b14_k_battle_start`).  While it is set, the block writer marks the
    tiles stale instead of copying them to the band page.  `pal_copy`
    clears it at the next `load_text_graphics`.
  - With palette set 8 loaded (the battle, the info and army screens),
    `restore_next` and `pick_restore` restore nothing, so a sync ends at
    once.
  - The map path still mirrors the font reload on the way back.
- **The battle tactic subwindow's S P cell** (`$27E4`; item 7 reworked this
  as `UI_SPST`, see the battle screen's result) changes palette exactly
  when a window draws rows 18-19.  The canvas RAM code's `cv_sm`
  (every window row pair goes through it) queues the attribute right after
  the row pair.  The value comes from `UI_SPP`: P1 with the tactic window's
  top row, P0 with the next window's (the command panel's border replaces
  S P in the same frame).
- **Army status screen (Select on the map):** it shows SP and MSP (rows 20
  and 22, columns 23-25): decision 12's MSP.  Since the direct build (QoL
  section, "Army status screen, built directly") the whole screen is P0
  but the portrait, and `UIF_ARMY` writes M S P as plane-0 copies.
- **Decision 11:** the kanji target's copy of the bank-9 block,
  `bank09_ui_b_k.bin`, has `$EF-$FA` in plane 1.  Palette set 8 P2 is
  `0F 0F 17 17`.
- **Decision 6:** the gauge colour goes to P2 colours 2 and 3
  (`b14_k_gauge_colour`).  A fresh battle's P2 is `0F 0F 25 25`.
- **Font (item 1):** the 31 UI kanji missing from the font are appended
  after the message kanji, so no message code moved.  The font now has 864
  glyphs.

RAM: `$7FC0-$7FC7` battery RAM (`UI_PATH`, `UI_P2`, `UI_BUSY`, `UI_NOMIR`,
`UI_TACT`, `UI_SPP`).  The canvas RAM code ends at `$7FB3` (the build checks
it stays below `$7FC0`).  The cv_sm hook is appended at the end of the
image, so every canvas label keeps its address and a save state from an
earlier build still runs.  Such a state keeps its old RAM image, though, so
`tools/mss_canvas.py --keep` is needed for the S P timing.

Bank 14 hand edits (all `.ifdef KANJI_TARGET`, same addresses).  The
decomp regeneration must keep them, as it keeps `SAVE_SLOTS` and
`BATTLE_SHAKE`:

| Where | What |
|---|---|
| `b14_officer_info_screen` `$8518-$857A` | the new driver, padded to `$857B` (with `UIF_INFO_BUSY` after `battle_intro_screen`) |
| `b14_battle_build_lineup` (`jsr battle_setup_slots`) | `jsr b14_k_setup` (QoL: `UIF_BSETUP`) |
| `b14_battle_start` `$9BE3`, `b14_loc_9C47` (`jsr wait_vblank_queued`) | `jsr BS_WAIT` (QoL: the frame's steps without the frame; `fixed_hooks.inc`) |
| `b14_inline_969F` (2), `b14_print_gold` / `_food` / `_exp`, `b14_wincb_print_sp` / `_sp_factor` | `jsr wait_vblank` for `jsr wait_vblank_queued` (QoL; the army status screen's windows, which `UIF_ARMY` replaces now; the three printers also serve other bank-14 screens) |
| `b14_battle_officer_info` `$AA1A-$AA60` | `call_ui` enter/exit, no slot 0/1 streaming; the original wrapper is 71 bytes, not `$AA5E` |
| `b14_battle_start` `$9B89` | `jsr b14_k_battle_start` |
| `b14_battle_tactic_subwindow` `$9EB0` | `jsr b14_k_tactic_window` (item 7 reverted it) |
| `$AE3C` (`b14_loc_AE33` tail) | `jmp b14_k_gauge_colour` |
| `b14_army_status_screen` `$959E-$9648` | the QoL driver: `b14_calc_strategist_tactic_pts`, the fade (`draw_window`, Y = 3), `jsr CALL_UI_ARMY` (the whole screen), one `wait_vblank` to show it, the input loop, `jmp field_return_refresh`; padded to `$9649` (`b14_print_gold`) |
| `$BFD8-$BFFF` | the helpers (with `b14_k_setup`).  This was the MMC1 reset stub and vectors, dead in the MMC3 target.  `b14_data_BFD9` stays as an equate for bank 15's MMC1 register writes |

Bank 9 has one more hand edit: `b09_ui_graphics2` uses the kanji copy.
The other changes are in `hack.asm` (`fn_block_post`, `restore_next`,
`pick_restore`, `pal_copy`) and `canvas_ram.asm` (`cv_sm`).
`decomp/build.py` allows bank 9 to differ; `tools/palette_check.py`
expects set 8's new P2.

Gates (kanji ROM `8f34d763...`):
- **Map → info → map:** CHR (all pages) and palettes equal the previous
  build's after the return.  The band page is written only by the map's
  own font reload on the way back (2,048 bytes); the info screen's upload
  is not mirrored.
- **Battle → info → battle**, then about 25 rounds of messages: 0
  band-page writes and 0 IRQ enables.  Every name is intact.  The
  messages after the screen print their kanji in the pool (攻撃, 人倒).
  - Plane 1 of `$48-$4F` keeps 策略: these tiles lie past the last battle
    name, so they are no name tile, and P0 cells don't show plane 1.
- **S P cell:** P1 from the tactic window's top row.  It turns P0 in the
  same frame as the command panel's border replaces S P (traced frame by
  frame).
- **Stack:** UI-bank min SP `$1F`; `ram_gate` 0 / 0 / 0, min SP `$14`.
- **Standard suite** (`run_gates.sh`; states `out/user/m6`, the m5 states
  with the new canvas image; results in `out/test/stepB_g2`):
  - `band_check` +1: 1,253, 0 mismatches; `garble_run` 0.
  - `garble_state` as before.
  - `vblank_deadline` 0.
  - `taint_check` 0 / 0 once `taint_check.lua`'s hack addresses were
    refreshed: `ltg_mask` moved; run `lua_addrs.py` on every Lua file with
    `@label@` markers.
  - `zp`, `mask`, `palette` 0.
  - `canvas_check` (item path) 0 missing, 0 mismatches, 0 late.
- **Army status screen:** SP / MSP visible.

## Step B result: the battle screen (2026-11-11)

Work order item 7.  The user's details: the fixed kanji fill the kanji area
from the back (道具 in the last two groups, 残 third from the last), every
kanji is in 8x16 order, and the command window erases columns 25-29 when
it is drawn over the tactic or item window.

**Kanji area.**  Plane 0 of the 23 groups `$A4 + 4k` (k = 0-22), tiles in
8x16 order (`t` TL, `t+1` BL, `t+2` TR, `t+3` BR).  The battle's cells are
P0, which shows plane 0 only, so the gauges (`$E0-$EE`) and S, P (`$F6`,
`$F7`) keep their plane 1 underneath.

| Groups | Tiles | Content |
|---|---|---|
| 0-7 | `$A4-$C3` | free: the subwindows' kanji (and the messages' pool) |
| 8-14 | `$C4-$DF` | 総 攻 撃 退 却 武 将: only the first command window (`$11`) shows them; the only fixed kanji the messages' pool reaches |
| 15-19 | `$E0-$F3` | 戦 策 略 防 御 |
| 20 | `$F4-$F7` | 残 (the tactic window's title) |
| 21-22 | `$F8-$FF` | 道 具 |

The order within the groups is `UI_FIXED` in `kanji_build.py`; words read
forwards (策 then 略).

**Windows.**
- Command windows `$11` / `$12`: 戦う 総攻撃 / 策略 退却 / 防御 武将 /
  道具 (`$12`: the left column).  う is the kana tile.
- Tactic window `$17`: the title is 残り SP (残's lower half on the border
  row 18, its upper half in row 17 above the window; り, S, P, the digits
  as before).  Each tactic line is two kanji, の and 計, from column 12 and
  column 21.
- Item window `$16`: the item names from the word list (all item types
  now; `UI_ITEM_TYPES`), kana in the lower row; an item without an entry
  keeps its kana name.
- The four window templates in the fixed bank call the UI bank once per
  line (`$F8 cv_wincb n`: n = 0-3 a command line, `$10` a tactic line,
  `$20` an item line).  `cv_wincb` is in the canvas RAM code; the patches
  are `battle_templates` in `kanji_build.py`.

**Slot table** (WRAM, `UI_SLOT` / `UI_GF`, `ui_battle.asm`):
- `UI_SLOT[k]` is the glyph in group k: `$FF` unknown, `$FE` a message
  kanji that may be on screen (`kanji_overlay` marks the pool slots it
  prints into).
- A window's first line places all its glyphs before any of its rows is
  drawn.  A glyph already in some group is used from there, with no upload
  (the tactic window shares 火 between two tactics, 計 between all, and
  将 of 干将 with the fixed 将).  Otherwise it takes the lowest group that
  may be rewritten: not shown by a window on screen, not used by this
  window, no message kanji.  The command windows always use their own
  groups and restore a fixed kanji that was taken.
- A kanji that has no such group yet is drawn blank, and the line is drawn
  again when the window's last row pair is queued.  At that point the old
  window is gone, so the group is free.  No frame shows a wrong glyph.
  Opening a window over the command window, its kanji beyond the 8 free
  groups (plus 残 under `$11`, plus the six `$11`-only ones under `$12`)
  fill in after the wipe.  Closing it, the command kanji it took fill in
  after the wipe.
- Uploads go through the VRAM queue, one glyph (44 bytes) per NMI.  Two
  per NMI overran vblank by up to two lines.
- Battle start (`UIF_BSTART`, rendering off) and the info screen's battle
  exit write all 15 fixed kanji directly.  After a round the window area is
  blank (window `$14`), so the command window restores the fixed kanji the
  messages took before it is drawn.

**Each window row pair** (canvas `cv_sm` hook, `UIF_SM`):
- `$11` / `$12`: the columns right of the window up to 29 are blanked in
  the same flush (`$11`: 25-29, `$12`: 18-29).  The original left the
  tactic and item windows' text there.
- The row pair 18-19: the tactic window turns its S P cell P1 (`$27E4`
  `$4A`) and the cell of 残's upper half P0 (`$27E3` `$02`; rows 16-17 are
  the gauges' P2), and writes that half in row 17.  The next window
  covering rows 18-19 sets `$0A` / `$0A` and blanks row 17 again.  This
  replaces step B's `UI_SPP`.

**Hack state.**  `UI_BATTLE` is set by `UIF_BSTART` and the battle path's
exit, and cleared by `pal_copy` (the next `load_text_graphics`: the map's,
or the info screen's once its screen is off).  While it is set,
`pool_off` leaves the pool armed: the battle owns `$A4-$FF`, and the
pool's blank check is cancelled at the battle start.

**The S P cell and 計.**  The cell (rows 18-19, columns 18-19) must hold
no plane-0 glyph (decision 9), but the first tactic's 計 ends at column 18
of row 19: its top-right quarter lies in the cell and vanished.  Every
even-aligned cell of row 19 holds tactic text except columns 28-29 (the
border), so the cell cannot move.  The fix uses the plane trick: 計's
top-right tile also gets the glyph in plane 1 (8 bytes, written with the
tactic window's uploads, only when 計 is in groups 0-14, whose plane 1
nothing shows).  Both planes set is colour 3, which is white in P0 as well,
so 計 looks the same everywhere.

**Not done: decision 7 in battle** (window borders one row down).  The
window engine draws a text line's two rows in two different row pairs: a
metarow is the lower row of one line and the upper row of the next.
Moving the windows down one row would need the engine's row mapping
changed for battle windows, and the dialogue line addresses too (`$D170`,
`$D39E`, the overlay's `window_geometry`).  The battle's kanji are plane 0
in P0 cells and need no attribute alignment.  The user (item 8): not
needed; a kanji's upper half next to the border is the expected result.

RAM: `UI_RAM` `$7FC0-$7FFE` (63 bytes, `kanji.inc`).  The canvas RAM code
ends at `$7F93`.

Hand edits for item 7 (bank 14, `.ifdef KANJI_TARGET`):

| Where | What |
|---|---|
| `b14_battle_start` `$9B8F` | `jsr b14_k_fade_in` (screen off, then `UIF_BSTART`) |
| `b14_battle_tactic_subwindow` `$9EB0` | back to the original `jsr b14_battle_open_list_window` (step B's `b14_k_tactic_window` is gone) |
| `$BFD8-$BFFF` | `b14_k_gauge_colour`, `b14_k_battle_start`, `b14_k_fade_in` |

Other changes: `ui_battle.asm` (new, included by `ui.asm`), `hack.asm`
(`pal_copy`, `pool_off`), `kanji_overlay.asm` (pool slot marking),
`canvas_ram.asm` (`cv_sm_hook`, `cv_wincb`), `kanji_build.py` (templates,
`UI_FIXED`, all item types), `bank15_lint.py` (the template ranges),
`kanji_common.py` (`kanjiwordlist.csv` may be UTF-8 and comma-separated,
as the user's spreadsheet now saves it).

Gates (kanji ROM `21ae4e88...`; the original still byte-identical, bank-15
lint OK; results in `out/test/stepC_g6`, states `out/user/m7` = the m6
states with the new canvas image):
- **Standard suite:** `band_check` +1: 1,253, 0 mismatches; `garble_run`
  0; `vblank_deadline` 0 (standard path, bt, nb, bb); `zp`, `mask`,
  `palette` 0; `canvas_check` (item path) as before (152 canvas frames, 0
  missing, 0 unlike, 0 late).
- **`garble_state`:** battle paths bt, nb, bb, lv 0; the town and shop
  paths unchanged (n1 / p1-p4 42 / 85 / 44 / 90 / 123, sv 0).  The gate has
  a battle rule now: while `UI_BATTLE` is set, a cell showing a tile of
  `$A4-$FF` must keep its glyph as long as it keeps the tile (plane 0 in P0
  cells, plane 1 in P1 cells; gauges and portrait not checked), and its
  group must not be blank.  Revision 18's `pool_outside` rule (no pool tile
  outside the message window) no longer holds: the command window shows
  総攻撃 退却 武将 from `$C4-$DF`.
- **Custom battle path** (tactic window, an item window with 21 distinct
  kanji poked into 劉備's items, info screen and back, a round):
  `garble_state` 0.
- **`taint_check`:** 0 / 0.  `UI_RAM` counts as protocol RAM now (the UI
  bank counts as game code there, and the canvas hook and the overlay
  write its state).  Min SP `$0D` / `$12` / `$0D` (step B `$0F` / `$12` /
  `$0F`): the battle start's fixed-kanji upload, with the NMI on top, is
  two bytes deeper.
- **`ram_gate`** (run alone; it fails with an empty log among the parallel
  jobs, as in step B): 0 / 0 / 0, min SP `$14`.
- **PPU write timing** on the custom path (`out/test/stepC/vbtime.lua`):
  the battle frames end their writes by line 253 (step B 252).  The only
  writes in visible lines are the info screen's build with rendering off
  (frames 126-127, as in step B).  Two glyph uploads per NMI overran by up
  to two lines; one per NMI is what the code does.

### Fix (2026-11-12): one frame scrolled wrong at each officer switch

**The user's report:** in battle, moving on from one officer's command to
the next showed one frame with the vertical scroll wrong.

**Cause:**
- The game queues the next command window's first three row pairs in one
  frame: 66 bytes.
- `ui_sm` (`UIF_SM`, the step-B hook after each row pair) blanked columns
  18-29 beside every row pair: 2 runs of 12 cells, 30 bytes a pair.
- That made 156 bytes in one flush.  The game's flush (~15 cycles a byte)
  ran into line 3 of the next frame.  The scroll was written after the
  pre-render line's reload, so that frame showed the background about 160
  pixels off.
- It was there before the upload work (identical on `fff6861`).

**Fix:**
- `UI_BRIGHT` (battle; the info screen's `UI_TACT` byte) keeps the first
  column right of every non-command window drawn since a command window
  last blanked beside itself.
  - A command window blanks only up to that column.
  - At its last row pair it sets `UI_BRIGHT` to its own right edge.
  - Between officers the game draws the blank window `$14` (columns
    10-29), so the blanking is still needed there.
- `cv_sm` (RAM) waits for a flush when more than `SM_QMAX` = 56 bytes are
  queued after a battle row pair.
- The officer switch's flushes are now 104, 52, 104 bytes (before: 156,
  104).  The window is complete one frame later (frame 319 instead of
  318).

**Checks:**
- `r17_pre_battle_normal`, frames 200-860, every frame: no transient
  frame (before: frames 317 and 560 scrolled wrong).
- The largest flush is 112 bytes, at the battle start as before.
- Every other frame is identical to the previous build, except the
  switches' 3-5 frames and the cursor blink one frame later.
- Lowest stack push `$0112`, as before.

## Step B item 8: the reward window (2026-11-11)

The user's request: the window after a won battle (top right: 金 / gold,
兵ろう / food, けいけんち / experience, 8x8 tiles) grows three rows down,
and its words become 16x16 kanji 金, 兵糧, 経験値.  The command window's
kanji are volatile now (it is not shown again).  Kanji already in CHR are
used from there, not uploaded again: 金 and 経験値 are almost always in
the pool from the victory message (msg 062), 兵糧 too when the enemy left
food (msg 061).  Decision 7 is not applied here (the user: a kanji's upper
half next to the border is the expected result).

**Layout** (window $22, columns 18-29, rows 2-12; the original rows 2-9):

| Rows | Content | Drawn by |
|---|---|---|
| 2 | top border | the engine |
| 3-4 | 金 (column 20) | line 0 |
| 5 | gold, 7 digits at columns 21-27 | line 1, top row |
| 6-7 | 兵糧 | line 1 bottom row, line 2 top row |
| 8 | food | line 2, bottom row |
| 9-10 | 経験値 | line 3 |
| 11 | experience | `reward_tail` (UIF_SM) |
| 12 | bottom border | `reward_tail` |

The engine draws windows in row pairs, so its height is even.  The four
lines give rows 2-11 with the bottom border on row 11.  With that last row
pair (same flush) `reward_tail` writes row 11 again (the experience), row
12 (the border), and `$27DC` = `$A2`: rows 12-13 columns 18-19 P0.  The
battle has `$AA` there (P2), and the victory routine clears only the
attributes of columns 20-31 below row 11.

**Template.**  Four lines of `$F8 cv_wincb` are 20 bytes; the original
template has 19.  It lives in bank 14 at `$923C` now (`b14_k_reward_tpl`,
in place of `b14_wincb_exp_line`, which only `$22` called), and
`kanji_build` points `data_EDA1/EDD1 + $22` there (`REWARD_TPL`; bank 14
is mapped while `text_init` reads a template, as its CALLs need).  The
line CALLs have no parameter byte: `ui_wincb` runs with the UI bank mapped
over bank 14, so for `$22` it takes the line from `$54`.

**Kanji** (`wg_reward`, `ui_battle.asm`), for each of 金 兵 糧 経 験 値:
1. a group holding its UI glyph (`UI_SLOT`; 8x16 order);
2. else a pool slot a message left it in: `kanji_overlay` now records the
   text code of each pool slot it prints into (`UI_MC_LO/HI`; `q_glyph`
   and the battle start mark a slot as no message kanji).  The slot keeps
   the message routine's order (TL, TR, BL, BR), and the window draws it
   that way;
3. else an upload into groups 15-22 (the command window's), one per NMI.

A pool slot the window uses is reserved (`UI_PRES`): the messages after
the victory (level-up, prisoners) print into the other slots, until the
next battle start.

**Message pool slots** (`pool_choose`, `KANJI_EC`).  A page used to take
consecutive slots `first .. first+n-1`.  With reserved slots in the middle
the level-up messages found no run long enough, and the fallback (slot 0
on) overwrote 経験値.  Now a page takes any free slots: `KANJI_PMASK`
holds the page's blocked slots, and entry k takes the k-th free one.  If
too few are free, the on-screen lines' slots are given up first, then the
reward window's.  `page_flip` keeps its rule: C set (the page does not fit
beside the lines and the reward window) still means clear the window.
Pages fit beside the lines more often now, so the window scrolls on more
often instead of being cleared (the victory message runs on as four
lines).

**The prisoner window.**  In a random battle with a captured officer the
game opens window `$21` (なかまにいれる / にがす), rows 12-17 columns
20-29, while the reward window is still shown.  Its top border now lies
on the reward window's bottom row: columns 20-29 of row 12 show `$21`'s
top border, so the two boxes share an edge.  The original had two rows
between them.  The message window starts at row 18, so `$21` cannot move
down.  The user keeps it: windows overlaying each other is how the
original's windows behave.

**The prisoner window in kanji** (2026-11-13, the user's report: the
choices were kana).
- Now 仲間に入れる / 逃がす (the original's なかまにいれる / にがす).
- 仲間に入れる is 9 cells and the window had room for 7 after the cursor.
  At the user's call it is two columns wider to the left: columns 18-29,
  text from column 20.  Its top border now covers the reward window's
  whole bottom edge.
- **Template** (fixed bank `$EC24`, `kanji_build` `PRISON_TPL`): one
  metatile further left, width 12, and two `$F8 cv_wincb` lines (`$40`,
  `$41`).
- **Drawing:** `ui_battle.asm` `wg_prison` / `draw_prison_line`.
  - 仲 間 入 逃 are UI glyphs (`ui_prison_g`; the UI set is now 147).
  - They take free groups (`need`).
  - Those among the message pool's slots are reserved (`UI_PRES`), so the
    messages after the choice (「それもよかろう 韓忠が我が軍に加わります」,
    「韓忠を釈放した」) print elsewhere.
  - `redraw_line` knows the window's position (`PR_LINE0`) for a kanji
    that had to wait for the window's end.
- **Palette:** columns 18-19 of rows 14-17 were the battle's P2.  When the
  window opens, `$27DC` = `$22` and `$27E4` = `$02` make them P0.  The
  battle ends after the window; the area beside it is black.
- **Checked** on the user's state 2 (総攻撃, a victory capturing 韓忠): both
  choices, the cursor on either line, the kanji kept through the messages
  after.  The battle `r17_pre_battle_normal` (every frame 197-856) and
  state 2 up to the prompt are identical to the previous build.

RAM: `UI_RAM2` `$7F9E-$7FBF` (34 bytes: `UI_MC_LO`, `UI_MC_HI`, `UI_PRES`,
`KANJI_PMASK`; `kanji.inc`).  The canvas RAM code still ends at `$7F93`
(its image is unchanged, so the converted states stay valid).

Hand edit for item 8 (bank 14, `.ifdef KANJI_TARGET`): `$923C-$9257`
`b14_k_reward_tpl` (the original `b14_wincb_exp_line` in the `.else`).
Fixed bank: `$EDC3`, `$EDF3` (`$22`'s template pointer; `PATCH_SITES`,
`bank15_lint`).

Gates (kanji ROM `b08870ac...`; the original still byte-identical, bank-15
lint OK; results in `out/test/stepD_g1`, states `out/user/m7`):
- Standard suite: `band_check` +1: 1,253, 0 mismatches; `garble_run` 0
  (all six offsets); `vblank_deadline` 0 (standard path, bt, nb, bb);
  `zp`, `mask`, `palette` 0; `canvas_check` (item path) as before (152
  canvas frames, 0 missing, 0 unlike, 0 late).
- `garble_state`: bt, nb, bb, sv 0, and lv (a victory with level-ups:
  the reward window and the messages after it) 0.  Item 7's custom path
  (tactic window, 21-kanji item window, info screen and back) 0.  Town and
  shop paths unchanged (42 / 85 / 44 / 90 / 123).
- Victory paths from `out/test/stepC/nb.mss` (enemy troops poked to 1,
  総攻撃): plain, with level-ups, with food (msg 061: all six kanji from
  the pool, no upload), with a prisoner.  `garble_state` 0 on two of them.
  On item 8's first build (consecutive slots) the same path gave 28 cells
  `battle_glyph_changed`.
- `taint_check` 0 / 0, min SP `$15` / `$0D` / `$0D` (item 7 `$12` /
  `$0D` / `$0D`).  `ram_gate` (alone) 0 / 0 / 0, min SP `$14`.
- PPU write timing (`out/test/stepD/vbtime.lua`): the reward window's
  frames end their writes by line 254 (its last row pair with rows 11-12
  in one flush: 64 bytes).  The victory routine's own clears reach line
  257-259, the same on item 7's build.

## QoL: black screens without frame pacing (2026-11-11)

The user saw the officer names enter plane 1 slot by slot, during the
black screen of a battle start and of the army status screen (Select on
the map).  The game paces those builds through the VRAM queue, one wait
per step, although the screen is off.  A second pass (the user: keep the
same rolls without the roll frames; "2 frames per slot sounds absurd")
replaced the remaining pacing waits by their per-frame steps and sped up
the slot work.

| Screen | Original pacing | First pass | Now |
|---|---|---|---|
| info screen, from battle / from the map | 15 / 16 frames | 5 / 6 | 5 / 6 |
| battle start, normal / boss | 47 / 50 | 29 / 31 | 17 / 19 |
| army status screen | 31 | 21 | 14 (direct build: 3, see below) |

**`wait_vblank` vs `wait_vblank_queued`.**  `wait_vblank` flushes the
queue and the palette/CHR stream at once when `nmi_busy` is set (or the
NMI is off); otherwise it falls into `wait_vblank_queued`, which always
yields one frame (task timer) and leaves the flush to the NMI.  A busy
NMI skips the PPU work but still runs the frame counter, the task timers
and the sound (`nmi_mode` 0).

**What a pacing frame does.**  With the NMI busy and rendering off, a
`wait_vblank_queued` frame lets the busy NMI run and then resumes the main
task (task_scheduler `$C040`): `read_controller`, the RNG step
(`read_input_state` `$FA9D`, a misnomer), `nmi_frame_counter`, the sound
hook if `nmi_mode` is set, `pla / tay / pla / tax / rts`.  Nothing else in
the game state changes (the queue budget is set to 1 by the wait and a
busy NMI leaves it).  **`bs_wait`** (fixed bank `$D67B`): with
`nmi_busy` set, rendering off (`ppu_mask_shadow & $18`) and the main task
running, it sets the budget, pushes X and Y and jumps to `$C040`, so the
same steps run without the frame; otherwise it is the real wait.  Every
roll after such a wait sees the same random number as before.

**Battle start.**  Pacing waits, all `jsr bs_wait` now:
- bank 14 `$9BE3` and `$9C47` (`.ifdef KANJI_TARGET`), around the random
  encounter's lineup roll (`b14_battle_setup_enemy_list`);
- bank 15 `$DF32`, one per enemy slot in `battle_setup_slots` (the troop
  rolls);
- `$E0A3` once per slot in `battle_setup_names`, `$E200` / `$E238` twice
  per shown slot (`battle_draw_slot_troops`).

The first pass made the last three `wait_vblank` (busy: flush at once)
and replayed their RNG steps in `UIF_BSETUP_END`; `bs_wait` does the steps
in place, and `UIF_BSETUP_END` only leaves busy mode.  Bank 14
`b14_k_setup` (`jsr battle_setup_slots` in `b14_battle_build_lineup`)
calls `UIF_BSETUP`: busy mode and `UI_NOMIR` if rendering is off (a
scripted battle's intro event could leave it on, then nothing changes).
`$E10F` (the loop end, X = `$0A` there) is `cpx #$0A / bne loc_E0A3 /
jsr call_ui`, so `UIF_BSETUP_END` (function 10) runs before
`battle_setup_intro`; it acts only if `UIF_BSETUP` started (`UI_BSBUSY`).

**The slot work** (per shown slot: the sprite's 24 tiles through the CHR
stream in 6 steps, the name, the troop count and gauge, two OAM rebuilds)
was about 17,000 instructions, ~58,000 cycles; now ~11,100 instructions,
~37,000 cycles:
- **The troop count's digits.**  `copy_pointer_triplet` (`$D671`, also
  the army screen's gold, food, experience and troop numbers) divided by
  10^6 ... 10 with six `div24_shift` calls, ~12,000 cycles.  `$D671` is a
  stub now (`sty ppu_update_off / stx UI_DECX / ldx #UIF_DEC / jmp
  call_ui`); the UI bank's `ui_dec` subtracts the powers of ten, ~1,900
  cycles with the call, with the same digits and the same end state
  (`$00-$09`, `ppu_update_ptr_lo`, X, Y).  Every caller loads A or Y next.
- **`div24_shift`** (`$C1D2`, the gauge and four bank-14 / bank-15
  callers): a stub too (`stx UI_DECX / sty UI_DECY / ldx #UIF_DIV / jmp
  call_ui`).  `ui_div` runs the same 24 shift-and-subtract steps (the same
  results for every input, divisor 0 and divisors over `$7FFFFF`
  included) and skips the dividend's leading zero bytes while the
  remainder is 0: ~1,250 cycles instead of ~1,930.  Callers load A next.
- **No band copy of the name glyphs.**  The block writer copied every
  name tile written to page 1 to the band page (`restore_tile_main`, 664
  cycles a tile).  The battle shows no band (the user's rule: no band
  copying in battle and on the info screen); `UIF_BSETUP` sets `UI_NOMIR`
  until `UIF_BSETUP_END`, so the tiles are marked stale instead, as for
  the battle start's and the info screen's other uploads.
- **The block writer** (`c343_hook`'s main-thread path, now `blk_main`
  at `$D68F`): `FN_BLOCK_PRE` / `FN_BLOCK_POST` act only on CHR page 1
  and cost ~470 cycles a call for page 0 and the nametables, which skip
  them now.  Page-0 writes of plain tiles (mode 0) of 1-15 tiles go to
  `blk_fast` (`$C1DD`): one 2x unrolled loop, ~14 cycles a byte instead
  of ~23, with the body's end state (`$00-$04`, A, X, Y).  The sprite
  stream's steps (4 tiles) take this path.

Fixed-bank space: `copy_pointer_triplet` with its divisor table
(`$D671-$D6C1`) holds the `UIF_DEC` stub, `bs_wait` and `blk_main`;
`div24_shift` (`$C1D2-$C216`) the `UIF_DIV` stub and `blk_fast`.  Both
regions are checked against the original by hash (`kanji_build.py`
`QOL_REGIONS`) and registered in `bank15_lint.py`.  `UI_DECY` / `UI_DECX`
are `$7F9C` / `$7F9D`, below `UI_RAM2` (the canvas RAM code ends at
`$7F93`).  The stubs' stack is no deeper than the originals' for
`UIF_DEC` (the digits at `$0104-$010A` sit at the bottom of the stack
page) and one byte deeper for `UIF_DIV`.

Verified:
- py65 (`out/test/stepE/dec`): `ui_dec` against the original
  `copy_pointer_triplet` + `div24_shift` machine code, 30,244 numbers
  (edges and random 24-bit), 0 mismatches in `$00-$09`, `$0104-$010A`,
  `ppu_update_ptr_lo`, X, Y; `ui_div` against `div24_shift`, 20,176
  dividend / divisor pairs (with divisor 0 and over `$7FFFFF`), 0
  mismatches; `blk_main` / `blk_fast` against the original body, 4,995
  writes of 1-15 tiles, the same PPU register writes in order and the
  same end state.
- At `battle_setup_intro`, against the build before both passes, normal
  and boss battle: nametables, CHR `$0000-$1FFF`, palette, WRAM (but
  `UI_DECY` / `UI_DECX`), the RNG and `nmi_frame_counter` are identical.
  Different by design: the band page (no copy of the name tiles) and
  `KANJI_STALE`; by timing: the NMI's real-frame counter `$33`, the sound
  engine's state (`$CA`, `$D0-$D5`, `$0700-$077F`), the main task's saved
  stack pointer, stack and hack scratch bytes, and two bytes of the
  `$0600` inline-block copy (it copies past its block, over the patched
  `jsr`).
- After the setup the battle runs on the same random numbers, but some
  later sequences pace by `$33`, so a later roll can land on another RNG
  step for the same frame of input (in the first pass's boss test the
  enemy's first strike happened on the old build only).  As random as
  before.

What is left of the 17 frames: 3 frames of the game's own NMI work before
busy mode starts (the black screen begins, the palette upload), about
2.5 frames of the fixed kanji and status panels before the rolls, about
1.25 frames a shown slot (the sprite's 384 CHR bytes, the name's glyphs,
two OAM rebuilds; `update_oam_sprite` steps each actor's animation
counter per call, so neither rebuild can be skipped), 2 frames of
`battle_setup_intro`'s fade.

**Army status screen.**  It is in busy mode already (the game's own); its
frames came from `wait_vblank_queued` calls, which ignore that.  They call
`wait_vblank` now (bank 14 `.ifdef KANJI_TARGET`): `$95EA`, the member
line's inline block (`b14_inline_969F`, two calls per line), and the
number printers `b14_print_gold` / `_food` / `_exp`,
`b14_wincb_print_sp`, `b14_wincb_print_sp_factor` (the same outside busy
mode).  The second pass's digit routine takes it from 21 to 14 frames.
The finished screen is byte-identical to before.  (The direct build below
replaces all of it.)

Gates (`out/test/stepE_g1`, kanji ROM after the second pass): as after the first pass: garble 0 on the battle, victory, level-up and
save paths (town and shop 42 / 85 / 44 / 90 / 123, unchanged), the custom
item path s1 0, the army screen path 0, canvas 152 / 0 / 0, standard
garble 0, band 1253 / 0, zp / deadline / mask / palette 0; taint 0 reads,
0 writes, min SP bt `$15`, nb `$10`, bb `$10` (was `$0D` / `$0C`: the
name loop no longer flushes inside a wait); `ram_gate` 0 / 0 / 0, min SP
`$14`.  The army screen and the info screen (map path) are byte-identical
to the first pass's (all PPU memory, the 16 KiB of CHR RAM, the palette).

### Army status screen, built directly (2026-11-11)

The user's rework of the army status screen (Select on the map), in two
rounds.  First, after a check of the limits (gold, food and experience
are 24-bit counters, 16,777,215 at most; every printer has 7 digit cells;
the user assumes 6 digits in normal play): every tile the screen mixes
into plane 1 is volatile, so all text goes to plane 0 and every cell is P0,
no band-page backups, and a level window 4 columns wider with kanji
labels.  That round did it with a flag in the block writer (`UI_AP0`) and
a second level window drawn over the game's.  Second round: the labels
one more column left and the numbers one more right (6 digits leave 2
blank cells after 経験値), レベル-05 one column left, the strategist's name
from the tiles the troop list uploaded, and "why so many frames": the
names went up 2, 6, 4 and 2 kanji a frame.

**Why it was slow.**  The uploads are small; the time was the text
engine's work around them and frame waits with the screen black.  Kanji
ROM before the second round, `clean_c.mss`, 239,000 cycles of work and
5 waits, 13 black frames:

| Step | Cycles |
|---|---|
| troop list, window `$0E` (7 lines) | 127,000 |
| of which the line routine copied to `$0600` for every line (`call_inline_block` always copies 255 bytes) | 28,000 |
| of which 12 name kanji through the block writer (about 2,300 each) | 28,000 |
| portrait (`sub_CFA1`: six 96-byte parts queued and flushed one by one) | 31,500 |
| windows `$0F` (strategist), `$2E` (leader's name), `$0D` (level) | 19,000, 11,500, 11,800 |
| 大将 / 軍師 upload (inline block), labels, the second level window | 14,000, 8,200, 8,700 |
| waits with the screen black | 2 in `battle_intro_screen` after the fade, 1 in `screen_fade_in`, 2 more in the show sequence (`screen_fade_out`, `wait_vblank`, `loc_C139`) |

**Now.**  `b14_army_status_screen` (`KANJI_TARGET`; the original target
keeps its code) runs `b14_calc_strategist_tactic_pts`, the fade-out
(`draw_window`, Y = 3: four steps of 3 frames, the last one all black,
shown as before), `UIF_ARMY`, one `wait_vblank` (the NMI sends the palette
and turns rendering on), the input loop and `field_return_refresh`.
`UIF_ARMY` (`ui.asm`), busy mode, rendering off:
- `battle_intro_screen`'s setup without its waits: `input_buttons` `$80`,
  `$AA` + 1, PPUCTRL `$90`, PPUMASK off directly (the palette is black),
  `clear_screen`, palette set 8 (`load_text_graphics`).  The hack's state as
  on the info screen: no band, `load_text_graphics`' pool check dropped,
  the pool unchecked.
- CHR, read from the PRG banks by a RAM routine (`rr_rom`, copied to
  `$0660`; it maps the bank with the game's lock protocol, so an NMI maps
  it back): tiles `$00-$0F` (bank 9 `$BA00`) and `$C0-$D7` (大将 / 軍師,
  bank 1 `$8000`) to plane 0 with plane 1 cleared, the UI block's
  `$F0-$FE` (bank 9 `$BF00`), the six label kanji to `$D8-$EF`, M S P to
  plane 0 of `$F5-$F7`, the leader's portrait (`text_load_page`'s parts and
  colours; with `battle_flags` set, never on the map, the game's mirrored
  loader).
- Names: `$A9` from `$10`, 4 tiles a kanji (upper t, t+2, lower t+1,
  t+3), each actor's name uploaded once (`AR_NT`): the leader (also the
  troop list's first line) and the strategist (also in the troop list)
  reuse their tiles.  A name that would end past `$60` goes to `$A4-$BF`
  (free on this screen), so 7 members with 3-kanji names (21 kanji) fit.
- The nametable: `sub_CFA1`'s portrait string (fixed bank, with its P3
  attributes), 大将 / 軍師, the level window, the troop list's frame,
  markers, names and numbers (`read_stack_arg`'s blanking: zeros before
  the first digit blank, the last digit always shown), the strategist's
  name, S P / M S P and their numbers.
- The text engine's state where the field return reads it: `text_mode`
  `$0F`, `menu_flags`, `text_actor`, `text_target`, the saved rows
  `$0348-$035F` blank.

| | Plane-0 round | Now |
|---|---|---|
| 金 兵糧 経験値 | top-left cell in column 17 | column 16 |
| gold / food / experience | right aligned at column 28 | column 29 (6 digits: 2 blank cells after 経験値; 7: 1) |
| レベル-05, べ's dakuten | columns 21-26, `$2076` | columns 20-25, `$2075` |
| strategist's name | its own upload (`$48-$4F` with the test party) | the troop list's tiles |
| black screen (rendering off) | 13 frames | 3 |
| black, with the fade's all-black step | 17 | 5 |
| `$959E` to the first frame shown | 27 frames | 15 |

The fade-out's last step (all black) is shown 3 frames before the build
starts, as in the original.  Removed with this: `UI_AP0` (`$7F9B` is free
again) and its block-writer and `pal_copy` code, `UIF_ALAB`, the window
`$0D` template patch (`$EA44` is the original again), the `$9716` strings
edit (original), `b14_k_army_enter` / `_exit` / `_p0`.  `UIF_ARMY` costs
80,000 cycles (clean_c): the RAM reader 25,000 (21 calls), names 13,400,
`clear_screen` 10,600, digits 10,600, labels 6,600, the strings 5,500, two
busy NMIs 5,800.

Checked:
- The screen (`out/test/stepD/arm16`, `arm17`): nametable and attributes
  as the plane-0 round's but the level window's moves and the name tiles
  (the troop list's first line uses the leader's `$10-$17`, the
  strategist's name his troop line's tiles); pixel-identical outside the
  level window; palette identical.
- Pokes (`ea17`, `eb17`): 9,999,999 / 999,999 in the counters, level 99,
  troops 999,999 / 99,999, S.P 123 / M.S.P 456, seven members with 3-kanji
  names (the plane-0 round overwrote the title and the window corners; now
  the seventh name sits at `$A4-$AF`), no strategist (no name, S.P 0, as
  before).
- After the return to the map (`ret16`, `rm17`): CHR RAM (16 KiB) and the
  palette identical to the plane-0 round's; the map, and a command window
  opened after it, pixel-identical.  RAM: `$54`, `text_line`,
  `text_actor_id`, `text_target_id` and the line buffers keep the map's
  values (the game left window `$0F`'s; the next `text_init` sets them),
  `$A9` is lower (fewer streams), NPC and sprite-flicker state (`$0700`s,
  `$6080`s) follows the frame count.
- Gates (`out/test/stepE_g4`, the build before the post-fade wait went;
  the army path again on the final build, `stepE_g5`): garble 0 on the
  battle, victory, level-up and save paths (town and shop 42 / 85 / 44 /
  90 / 123, unchanged), the custom item path s1 0, the army screen path
  (in and out twice) 0, canvas 152 / 0 / 0, standard garble 0, band
  1253 / 0, zp / deadline / mask / palette 0; taint 0 reads, 0 writes, min
  SP bt `$15`, nb `$10`, bb `$10` (as before the plane-0 round);
  `ram_gate` 0 / 0 / 0, min SP `$14` (run alone: the parallel sweep's run
  exited -1 with an empty log, as once before).

## Questions for the user

None open.  The user's direction after item 8 (2026-11-11): the code as it
stands is final; no further architecture rework is planned.  All branches
were merged (fast-forward) into `master` and pushed.

## Work order

### Step A: done 2026-11-11 (see "Step A result")

1. Capture a CDL on the original ROM (`tools/lua/cdl_*.lua`,
   `tools/merge_cdl.py`): battle start, command panel, item subwindow,
   tactic subwindow (needs a strategist state), ぶしょう -> info -> back
   in battle and on the map, messages, a battle end.  The existing
   `out/cdl_combined2.bin` never ran this code (0 code bytes in the bank
   14/15 blobs).
2. Turn the executed parts of these blobs into source, the original build
   still byte-identical (`40f19e17...`) and the kanji build unchanged:
   - bank 15 `$E000-$E370` (`data_E000`): battle setup, name allocation
     (`$E060-$E098`, `$E09B` `$A9` = `$10`);
   - bank 14 `$A800-$ABFF`: the battle-side info wrapper `$AA1A-$AA5E`;
   - bank 14 `$AC00-$AFFF`: the gauge colour `$AE10-$AE45` and its tables
     (keep the kanji target's `$ACBF` battle-shake patch and its hash
     check in `kanji_build.py`);
   - whatever else on these paths the CDL shows as code in a blob
     (window templates such as bank 15 `$EB46` stay data).
3. Check bank 13 `$986A` (a tile arrangement using `$EF-$F9`): which
   screen, which CHR.  If it shows the bank-9 block's `$F3-$F8` through
   plane-0 palettes, decision 11 must keep it working.
4. Name the routines, update this file with the new labels, run the
   original-build check and `bank15_lint`, commit.  Then compact.

### Step B: done 2026-11-11 (items 1-6: "Step B result: the info screen"; item 7: "Step B result: the battle screen"; item 8: "Step B item 8: the reward window")

1. Font: add the 32 missing kanji (kanji font build).
2. Path flag (map entry `$84F8` vs battle wrapper `$8518`).
3. CHR block (bank 9 `$1E00`, tiles `$E0-$FE`): bars, M, S, P, dot to
   plane 1 in the ROM data; info P2 `0F 0F 17 17` in the palette data
   (decision 11).  Gauge palette: `$AE40` and the exit wrapper store
   colour 1 = `$0F` and colour 3 = colour 2 (decision 6; the one code
   change here).
4. Info screen renderer (hack bank) in place of the driver's window
   sequence (`$8531-$8578`): fixed label slots, tactic slots, kanji map,
   plane-0 groups, borders one tile down (decision 7).
5. Battle exit: re-stream every battle name slot (plane 1); the pool and
   `$E0-$FF` plane 0 need no clearing (the battle's managed slot table
   restores its involatile kanji when the command panel returns).
6. Gates: battle -> info -> battle: plane 1 of all BG tiles equal (as
   the original), plane 0 of `$A4-$FF` restored where the command panel
   shows it; map -> info -> map; the stack and RAM gates.
7. Battle screen (command panel, subwindows, involatile tracking, the
   23-group slot table): after the info screen.
8. The reward window after a victory (user, added after item 7): three
   rows taller, 金 兵糧 経験値 as 16x16 kanji, kanji in CHR reused.
