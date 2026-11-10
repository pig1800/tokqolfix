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
  - info -> battle: rewrite plane 1 of every battle name slot; clear what
    was written to the pool and to `$E0-$EE` plane 0 (see question 1).

## Plan: battle screen (user, in progress)

- The command panel needs 15 fixed (involatile) kanji:
  戦 策 略 防 御 道 具 総 攻 撃 退 却 武 将 残.
- Subwindows (tactics, items) and messages may borrow involatile slots.
  Track which involatile slots were changed; restore them when a
  subwindow closes and when the command panel is shown again after a
  round.  The item subwindow covers the whole command panel; the tactic
  window leaves only 道具 visible.
- "Usable kanji slots may be surprisingly low" (user).

## Verified

Name kanji (original engine):
- `load_party_member_stats` `loc_D4C9` (fixed bank).  Officer record
  (`$F3`, bank 12): byte `$10` = per-kanji bank bits, `$11-$13` = up to 3
  glyph indices (`$FF` ends).  Source bank 1 or 2, `$8000 + index * 32`.
  CHR stream mode 2 (`vram_put_run` with C set reads 8 bytes, so plane 0
  is kept; then 8 bytes go to plane 1).  Destination: bump pointer `$A9`,
  +4 tiles per kanji; the tile numbers also go into `$0300`/`$0318`.
- Battle setup `$E09B`: `$A9` = `$10`, then every name in order, no
  deduplication (兵士 x3 = 6 slots), no bound check.  Kanji 29 and 30
  would land in plane 1 of the portrait tiles `$80-$87` (the next
  portrait upload overwrites them).
- Info screen: `$A9` = `$10` (bank 14 `$8545`).
- Exit to battle: bank 14 `$AA1A-$AA5E` (the battle-side wrapper; it runs
  the info screen through `$8518`).  Afterwards `$A9` = `$10` and the
  names of battle slots 0 and 1 are re-streamed (`$D49F`, `$D4A1`): 4-6
  kanji, which always cover `$10-$1B`.  The new plan needs every slot
  re-streamed: record (glyph index, bank) per slot when the battle
  allocates, or replay its loop (`$E060-$E098`).
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

Not in the decomp as code: bank 15 `$E000-$E370` (`data_E000`, the
battle name setup) and bank 14 `$A800-$ABFF` (the wrapper at `$AA1A`).
Disassemble first, or hash-check the bytes to patch.

WRAM: 141 bytes free at `$7F73-$7FFF` (canvas code installed): the panel
kanji map (about 16 x 2 bytes) plus a battle-name record (28 x 2) fit.

## Questions for the user

1. Battle P2: change it from `0F 17 25 17` to `0F 0F 25 25`?  The gauges
   look the same, and plane 0 of `$E0-$EE` becomes invisible in battle:
   free for kanji with nothing to revert, in battle and after the info
   screen.  Otherwise plane 0 of those tiles must be cleared on every
   return to the battle, and the battle itself cannot use them.
2. The info screen's 策略 and 装備 windows grow by one row each (bottom
   borders to rows 28 and 26) so the aligned title and lines fit.  OK?
3. Battle item subwindow worst case: 8 items x 3 kanji = 24 distinct
   kanji.  Battle room is the pool (15) plus the `$E0-$FF` groups (at
   most 8, the gauge groups only with question 1).  That is 23, before
   the kanji map's reuse.
4. Word list: めいば -> 名簿 (名馬?); 竜 in 青竜刀 / 土竜の剣 / 青竜の鎧 /
   飛竜の兜 but 龍 in 水龍の計 - intended?

## Work order (after compaction)

1. Disassemble bank 15 `$E000-$E370` and bank 14 `$A800-$ABFF` (or
   hash-check the bytes to patch).
2. Font: add the 32 missing kanji (kanji font build).
3. Path flag (map entry `$84F8` vs battle wrapper `$8518`).
4. Info screen renderer (hack bank) in place of the driver's window
   sequence (`$8531-$8578`): fixed label slots, tactic slots, kanji map,
   plane-0 groups, the window geometry above, `$F3` -> `$FB`.
5. Battle exit: re-stream every battle name slot (plane 1); clear the
   pool and (without question 1) `$E0-$EE` plane 0.
6. Gates: battle -> info -> battle CHR equal (256 BG tiles, as the
   original); map -> info -> map; the stack and RAM gates.
7. Battle screen (command panel, subwindows, involatile tracking): after
   the info screen.
