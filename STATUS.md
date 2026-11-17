# The kanji edition as built (2026-11-15)

The reference for the current build: layout, runtime, text editing, tools,
tests and limits.  The reasons behind each part, and the measurements, are
in `TEXT_RENDERER.md` (design log, newest last); every PRG region by address
is in `MEMORY_MAP.md`.

## Builds

- Original 256 KiB ROM: byte-identical,
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Kanji edition: `python decomp/build.py --target kanji` writes
  `decomp/build/rom_kanji.nes`.
  - Hardware: 512 KiB PRG, MMC3 (mapper 4, NES 2.0), 16 KiB CHR RAM, 8 KiB
    battery PRG RAM, four-screen nametables.
  - The build lints the fixed bank and regenerates `MEMORY_MAP.md`, whose
    header gives the current sha256.
- Release patch: `python -I tools/make_bps.py` writes
  `out/release/tokqolfix.bps` (BPS, from the original ROM to
  `rom_kanji.nes`), applies it again and compares (2026-11-18).  The patch
  is a release asset, never committed.
- Font: every kanji is JF-Dot-Izumi16's own 16-pixel bitmap (its 16 ppem
  strike, `JF-Dot-Izumi16.ttf`; never the outlines).  The 15x15 box is
  anchored bottom right.  璝, which the font lacks, is composed from its
  bitmaps.

## Layout (16 KiB banks)

| Bank | Content |
|---|---|
| 0-8, 12 | the original game; the original officer-name glyphs in banks 1 (`$8010-$9A0F`) and 2 (`$8010-$880F`) are unread and freeable (2026-11-17) |
| 9 | original; the UI glyphs `$EF-$FA` moved to plane 1 (the info screen's kanji) |
| 10, 11 | the game's message tables; each kanji message is a 6-byte `$F8` far stub (JUMP-only messages 3 bytes); the old text space is free |
| 13 | original, patched: the boot screens (fixed kanji set, the speed message, two save records), the attract entry |
| 14 | original, patched: hooks for the battle, info and army screens, the battle shake, the reward window's template, the reserve list |
| 15 | free (JAM bytes: nothing maps it) |
| 16-17 | kanji store: 1,007 of 1,024 glyphs, 256 per 8 KiB bank (banks 32-35) |
| 18-19 | text: 758 unique messages in four 8 KiB chunks (banks 36-39), read at R7 |
| 23 | hack bank: the message engine (`kanji_msg.asm`), the battle pool's uploads, the palette tables |
| 24 | title screen and attract mode (`attract.asm`) |
| 26 | map text renderer (`txr.asm`) |
| 28 | UI bank (`ui.asm`, `ui_battle.asm`, `ui_list.asm`, `ui_info.asm`, `ui_info_lo.asm`) |
| 31 | fixed bank: bank 15 with registered patches, and the runtime at `$FC00` (`fixed_rt.asm`) |
| 20-22, 25, 27, 29, 30 | free |

189.5 KiB free in all, 8.5 KiB of it the old name glyphs in banks 1-2 (the
UI bank has 0.6 KiB left, the fixed bank 0.4 KiB).

## Runtime

- **Bank switching.**  MMC3 PRG mode 0.  Every 16 KiB game bank is two
  8 KiB halves (R6/R7); bank 31 is fixed at `$C000-$FFFF`.
  - The game's `set_bank_lock` and `restore_bank_after_nmi` keep their
    addresses and jump to `main_prg` / `nmi_prg`.
  - `MMC3_SEL` (`$EB`) shadows the bank-select register for the main
    thread; interrupt code restores it.
  - `PRG_R7X` lets main-thread code borrow R7 for an 8 KiB bank (a store
    bank or a text chunk); the NMI's restore keeps it.
  - While a message prints, the current bank is `MSG_BANK` (`$97`): R6 =
    the hack bank's lower half, R7 = the message's text chunk.
  - `main_prg` takes 63 cycles and 36 bytes, as the original's switch
    did; the RNG depends on that timing.
- **The fixed bank** keeps every original routine at its address (save
  states hold return addresses).  Changes are allowed only inside the
  ranges `tools/bank15_lint.py` registers.  The runtime at `$FC00` is the
  code that must run with any bank mapped: the IRQ's part switches, the
  NMI's stream step and the renderer's stubs.  No code runs from RAM.
- **Messages.**  A kanji message's entry in banks 10/11 is a stub:
  `F8 <far_head> <chunk | $80 victory> <text address>`.  The trampoline
  enters the message engine at `MSG_ENTRY` (`$800F`, bank 23).
  - Kanji are `$EC-$EF` + pos in the text (store bank + position).
  - A page holds at most 16 kanji.  Its kanji table (`REG_LO/HI` 0-15) is
    built at run time; there is no metadata.
- **Map mode** (the map renderer, bank 26, `TXR_ON` bit 7) draws every
  text cell.
  - The screen has four parts (rows 0-8, 9-14, 15-20, 21-29), shown
    through R0 pages 4, 8, 10 and 12.  The IRQ switches pages at lines 71,
    119 and 167.
  - The map scrolls through four nametables: PPUCTRL bit 1 is the camera's
    vertical half, which the original never set.  Every other screen's
    fill (`txr_fill`) clears it, so a screen drawn at `$2000` shows
    `$2000` (2026-11-17: the ending's last two screens were black).
  - Each page holds the fixed set (frame and cursor tiles `$00-$0B`, blank
    `$7F`), then kanji in 4-tile groups from `$0C` up, and kana from the
    top down.
  - Glyphs upload in the NMI, before the game's own NMI work: 3 kanji or 7
    kana a frame.  When a part runs out of tiles, a read-back garbage
    collector frees the ones no longer shown.
  - The map UI's words, and item, tactic and place names, show in kanji
    (`TXF_PUT`).  Officer names show in kanji in map mode, in battle and on
    the info and army screens (`pon_kanji`, the UI bank's name table).
  - The gold window `$18` (shops): 金 / 糧 with 7 digits at columns 22-28
    (up to 9,999,999, as the original; 2026-11-17: they were 金 / 兵糧
    with 6 digits).
  - Map windows never scroll: where the original would scroll, the page
    breaks (`<NLNI>`, `<PAGENI>`).
- **Battle.**  The kanji slot table manages 32 slots of 4 tiles in the
  scene page (`$80 + 4s`, 8x16 order), plane 0.
  - The 15 fixed command kanji are in plane 1 of slots 9-23 (`$A4-$DF`,
    free in the battle set), the command window's う in plane 1 of `$FB`
    (2026-11-17).  The command windows' kanji cells are P1, every other
    window's P0, set with each row pair (`attr_pair`).  So no other
    window's kanji ever takes theirs, and the item and tactic windows'
    kanji show as their rows are drawn.
  - Before the win, messages use slots 9-31; slots 0-8 hold the portrait.
    The item, tactic and prisoner windows use the same plane-0 groups.
  - From the win, slots 0-5 hold the reward window's 金兵糧経験値 and 6-31
    the messages'.
  - A kanji already in a slot is used from it.  On the battle screen the
    message uploads write plane 0 only.
  - Runtime names in messages show in kanji from entries the page
    reserves: officers (`$F4-$F7`), the tactic, and since 2026-11-17 the
    item (`$F3`, 「劉封は短剣を使った」, `KITEM`).
  - The battle window scrolls as in the original.  The scroll blanks
    line ends (`$FA-$FF`) but keeps the tiles of slots 30-31, which
    share those values (`redraw_hi`).
  - The UI bank draws the command, item and tactic windows (one UI-bank
    call per template line, `cv_wincb`), the reward window (`$22`) and
    the prisoner window (`$21`).
  - The tactic window's rows are one below the engine's (`tw_line`,
    2026-11-16): its title's 残 sits in rows 18-19, P0 like the battle's
    own, so rows 16-17 (the last officer's gauge) keep their palette.
    Rows 18 and 27 show the command window's frames, as before it
    opened; the cursor is one row lower too (`cur_st`).
- **UI bank.**  The officer info screen and the army status screen show
  kanji without switching CHR banks: in plane 1 of the font tiles (labels,
  names) and in plane 0 of free scene tiles.  Each screen is built while
  black and shown once complete, without the original's frame pacing.
  The battle setup replays the RNG steps of the frames it skips, so every
  roll is the original's.
- **The info screen's Left / Right** (`ui_info.asm`): the officer before
  / after, with the cursor's sound: from ぶしょう the party order, from the
  town office's 能力 the reserve list (each officer set up as 能力 does,
  `ui_rsetup` in the fixed bank), in battle the enemies still alive.  A flip re-sends only the kanji that changed
  (a cache of 27 plane-1 and 22 plane-0 groups; a new kanji goes to a
  group the shown page does not use), then writes the officer's 254 cells
  at once.  The data go in "windows": the vblank and the black lines
  0-31 with rendering off, cycle-counted to line 31's hblank, where
  rendering comes back on; each window's frame runs its NMI work itself.
  The text changes 2 frames after the button is read, the portrait 1
  frame later (TEXT_RENDERER.md "The info screen's page flip").
- **Boot screens** (main menu, history books, name entry): one fixed set
  of 25 kanji at upper tiles `$80-$E3`, uploaded once at the boot entry
  (`TXF_MENUSET`).  The message speed prompt (b11_msg_147) shows before
  the speed window.
- **The opening oath:** a fixed split.  The IRQ at line 130 switches R1 to
  CHR `$3800`, which holds the oath's 20 kanji.
- **The reserve list** (window `$20`: 能力, 加える, 解雇; bank 14
  `b14_k_list`, UI bank `ui_list.asm`): 8 officers a page in a window of
  8 lines (screen rows 3-18), an arrow row (19) and the bottom frame
  (20), so the officer window's 加える below stays whole.  Left / Right
  flip pages without a wrap (no その他 entry).  A flip writes the 8 lines'
  rows only (the names' kanji upload as usual).  Sprite arrows (tile `$04`
  of the sprite table, the left one mirrored) at columns 21 and 28 of row
  19 show where another page lies, and the page number between them
  (「2／5」, columns 23-25; 「12／16」, columns 22-26, from 10 pages) when
  there is more than one.
- **The reserve list holds 125** (2026-11-15; the original's 64): the
  game has 132 officers to recruit, 7 of them in the party.  The list is
  at `$6410-$648C` (`LS_RESERVE`, kanji.inc), in the saved state's page
  `$64`, which nothing else uses (checked: TEXT_RENDERER.md "The reserve
  list holds 125"), so the save records keep it.  Every site of the
  original's list is patched: the join (talks and prisoners, bank 13),
  加える, 外す, 解雇 and the packing (bank 14), the event that takes
  officer `$BC` away, the list (16 pages) and the info screen's flips.
  The game does not read `$6030-$606F` any more: a battery save or a
  Mesen state from before needs `python -I tools/reserve_move.py <in>
  <out>` (the user's main save and the test states are converted; the
  user's own older states are given up).  When 125 are in reserve, a join says 「劉備軍はこれ以上仲間を持つことができない」
  and 外す 「これ以上武将の入る場所がございません」, as the original did
  at 64.
- **Title and attract mode** (bank 24): each screen has its own tile set,
  and the portraits are 8x16 sprites.  The title's logo intro (its five
  rows closing up) moves every frame (60 fps; the original stepped every
  4 frames).  The NMI computes the strip positions (`title_fx`), and
  scanline IRQs (`title_irq`, fixed bank) make the mid-frame writes in
  hblank.  Bank 13's steps, Start checks and RNG are unchanged.
- **Doors keep the music** (2026-11-17): entering or leaving a location
  through a door, the music goes on when the next area plays the same one
  (a town of tileset 1 and its houses, for example); the door's sound
  plays over it on the noise channel.  A different music still stops at
  the door and starts in the new area (`door_music`, fixed bank `$EF4D`).
- **The ending's last screen** (CAPCOM, さいごまで あそんでくれて どうも
  ありがとう; 2026-11-17): Start fades it out and resets the game to the
  title and its logo intro (bank 13 `b13_k_flag`, at the ending's story
  flag `$10`).  The reset path sets the stack first now, so the console's
  Reset no longer crashes while a task runs (it did, for example during
  a battle's start).
- **Anything else.**  A message printed with neither the map renderer nor
  the battle pool hits `band_trap`, a JAM, in place of the old band page.
  At the JAM, A = its text chunk and X/Y = its text address;
  `python -I tools/band_trap.py A=.. X=.. Y=..` names the message.  Each
  screen reported this way gets its own fixed kanji, as the boot screens
  and the oath did.

## RAM

| Range | Use |
|---|---|
| `$0102-$0103`, `$0131-$017F` | the message engine's and the battle pool's state |
| `$0780-$07FF` | the map renderer's state (`TXR_*`; `REG_LO/HI` at `$07A0-$07DF`) |
| `$6000-$77FF` | the game's (two save records in the kanji edition) |
| `$6410-$648C` | in it: the reserve list (125, `LS_RESERVE`; `$648D-$648F` stay 0); `$6030-$606F`, the original's list, stays 0 |
| `$7800-$78FF` | the map's attribute shadow (`MAP_ATTR`, four-screen) |
| `$7900-$794C` | the title intro's IRQ events (`TFX_*`) |
| `$794D-$7953` | the reserve list (`LS_*`) |
| `$7954-$799A` | the info screen's glyph cache (`IS_*`) |
| `$79A0-$7BDF` | the info screen's portrait buffer (`IS_PB`) |
| `$799B-$799F`, `$7BE0-$7BF4` | free (cleared at reset) |
| `$7BF5-$7F9B` | the renderer's tables and buffers (in battle: the kanji slot table) |
| `$7F9C-$7FFF` | the UI bank's state, `PRG_R7X` |

`hack_init` clears `$0103-$017F`, `$0780-$07FF` and `$7900-$7FFF` at reset.

## Editing the text

- Edit `decomp/text/kanji_plan/bank10_messages_kanji_r14.dtx` and
  `bank11_messages_kanji_r14.dtx`, then run
  `python decomp/build.py --target kanji` (about 10 seconds).
  - The build reports lines wider than their window and pages it had to
    split.
  - It fails if the text outgrows its four chunks or the store's 1,024
    glyphs.
- `python -I tools/scroll_scan.py` lists messages that would scroll in map
  mode, i.e. a 4th line between page breaks.  It should report 0.
- The compiler adds a `<NLNI>` where a line would pass 18 cells (a kanji
  2, a kana 1).  `<NAME:xx>` is officer xx's fixed name, not the party's
  (it counts its kanji name's width, so `<NAME:AD>` and 張苞 lay out the
  same).  The runtime names `<NAME_F3>`-`<NAME_F7>` count 8.
- `.` is the font's mid-height dot (tile `$78`), the one the game uses
  in ellipses (`...`); it was written `-` until 2026-11-17 (both dtx
  sets, `tools/textdata.py`).
- The name and word kanji come from three files:
  - `kanjiwordlist.csv`: item and tactic words (cp932);
  - `namekanjilist.csv`: officer names;
  - `decomp/text/kanji_r14/glossary.tsv`: place names.
- Boot-screen text must keep its kanji within the fixed set; the build
  checks this.  New attract-mode text goes in `tools/attract_text.py`.

## Tools

| Tool | Use |
|---|---|
| `decomp/build.py` | both builds; runs `assets.py`, `text.py`, `kanji_build.py`, `bank15_lint.py`, `memory_map.py` |
| `tools/kanji_build.py` | the kanji edition's banks; with `kanji_text.py` (text compiler), `kanji_common.py`, `kanji_font.py`, `attract_build.py`, `attract_text.py` |
| `tools/scroll_scan.py`, `tools/band_trap.py` | text checks; naming a trapped message |
| `tools/make_bps.py` | the release patch (BPS), checked by applying it |
| `tools/reserve_move.py` | moves the reserve list of a battery save or Mesen state (original or pre-2026-11-15) to `$6410` |
| `tools/mesen_run.py` | runs a Lua script in Mesen's test runner on a copied ROM name |
| `tools/lua_addrs.py` | refreshes the `-- @label@` addresses in Lua scripts from the listings; run it after a change to `hack.asm` or the fixed bank |
| `tools/mss_to_mmc3.py`, `tools/mss_4screen.py`, `tools/mss_canvas.py` | convert save states of older builds (SUROM, two-screen, before the renderer) |
| `tools/lua/zp_check.lua`, `ram_gate.lua`, `taint_check.lua`, `mask_restore.lua`, `anim_timing.lua` | gates: zero page kept at message exits, RAM ownership, stack, the game's mask/scroll restore |
| `tools/lua/map_parts_*.lua`, `txr_*.lua`, `mmc3_clock_trace.lua`, `screen_trace.lua` | probes for the map renderer's IRQ lines, uploads and rows; a screen's code path |
| `tools/decompile.py`, `gen_docs.py`, `symbols.py`, the CDL tools | regenerating the reconstruction (`decomp/README.md`) |

## Testing

- The regression check is a pixel comparison against the previous build.
  The paths are: the greeting, the menu cycle, the officer switch, the
  level-up and capture battles, the title, the standard path, the oath and
  the five boot flows (about 3,200 screenshots).
  - The harness is local (`out/test/opt/suite.sh`, `suite_cmp.py`) and not
    in the repo; `out/` is ignored.
  - The copy flow's frame 800 differs between builds by a scanline of
    menu border.
- Main-thread cycle changes can move a lag frame, and with it the NPCs and
  the RNG.  Keep hot paths and boot-time code cycle-neutral, and measure
  (Mesen's `cpu.cycleCount`) when in doubt.
- Save states made on an older build may hold return addresses into code
  that moved.  Convert copies of them; never edit the originals.

## Known limits

- 16 KiB CHR RAM and four-screen nametables (NES 2.0).  The MMC3 CHR-RAM
  boards have 8 KiB, so this runs in emulators, or on a board with more
  CHR RAM.
- Screens that have no fixed kanji yet stop at `band_trap` (above).
- A text edit that adds or drops a kanji shifts the store's codes, which
  follow frequency.  A save state made before such a rebuild then shows
  wrong kanji in map windows for glyphs it had in CHR, until a screen
  change resets the renderer (seen 2026-11-15: 程遠志 as 程粛志).
- In map mode, each new kanji of a page waits for its glyph upload, so
  kanji print a little slower than kana.
- Info screen flips: a page whose new kanji need more than the image's
  window (8 glyphs) takes glyph windows first, one frame each (the first
  visit to a strategist: 15 glyphs, one frame more).  The vblank poll
  misses a vblank now and then (a read on the flag's own dot); that window
  comes a frame later.  Two pages with 11 or more distinct equipment kanji
  each can leave a new kanji only a group the shown page uses; it is sent
  just before the image, in the same window, unless that window is full.
