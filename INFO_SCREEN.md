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
