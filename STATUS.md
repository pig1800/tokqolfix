# The kanji edition as built (2026-11-14)

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
- Font: every kanji is JF-Dot-Izumi16's own 16-pixel bitmap (its 16 ppem
  strike, `JF-Dot-Izumi16.ttf`; never the outlines).  The 15x15 box is
  anchored bottom right.  璝, which the font lacks, is composed from its
  bitmaps.

## Layout (16 KiB banks)

| Bank | Content |
|---|---|
| 0-8, 12 | the original game |
| 9 | original; the UI glyphs `$EF-$FA` moved to plane 1 (the info screen's kanji) |
| 10, 11 | the game's message tables; each kanji message is a 6-byte `$F8` far stub (JUMP-only messages 3 bytes); the old text space is free |
| 13 | original, patched: the boot screens (fixed kanji set, the speed message, two save records), the attract entry |
| 14 | original, patched: hooks for the battle, info and army screens, the battle shake, the reward window's template |
| 15 | free (JAM bytes: nothing maps it) |
| 16-17 | kanji store: 1,004 of 1,024 glyphs, 256 per 8 KiB bank (banks 32-35) |
| 18-19 | text: 758 unique messages in four 8 KiB chunks (banks 36-39), read at R7 |
| 23 | hack bank: the message engine (`kanji_msg.asm`), the battle pool's uploads, the palette tables |
| 24 | title screen and attract mode (`attract.asm`) |
| 26 | map text renderer (`txr.asm`) |
| 28 | UI bank (`ui.asm`, `ui_battle.asm`) |
| 31 | fixed bank: bank 15 with registered patches, and the runtime at `$FC00` (`fixed_rt.asm`) |
| 20-22, 25, 27, 29, 30 | free |

188.1 KiB free in all.

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
  - Each page holds the fixed set (frame and cursor tiles `$00-$0B`, blank
    `$7F`), then kanji in 4-tile groups from `$0C` up, and kana from the
    top down.
  - Glyphs upload in the NMI, before the game's own NMI work: 3 kanji or 7
    kana a frame.  When a part runs out of tiles, a read-back garbage
    collector frees the ones no longer shown.
  - The map UI's words, and item, tactic and place names, show in kanji
    (`TXF_PUT`).  Officer names show in kanji in map mode, in battle and on
    the info and army screens (`pon_kanji`, the UI bank's name table).
  - Map windows never scroll: where the original would scroll, the page
    breaks (`<NLNI>`, `<PAGENI>`).
- **Battle.**  The kanji slot table manages 32 slots of 4 tiles in the
  scene page (`$80 + 4s`, 8x16 order).
  - Before the win, messages use slots 9-23; slots 0-8 hold the portrait.
    The command windows' 15 fixed kanji live there too.
  - From the win, slots 0-5 hold the reward window's 金兵糧経験値 and 6-31
    the messages'.
  - A kanji already in a slot is used from it.
  - The battle window scrolls as in the original.
  - The UI bank draws the command, item and tactic windows (one UI-bank
    call per template line, `cv_wincb`), the reward window (`$22`) and
    the prisoner window (`$21`).
- **UI bank.**  The officer info screen and the army status screen show
  kanji without switching CHR banks: in plane 1 of the font tiles (labels,
  names) and in plane 0 of free scene tiles.  Each screen is built while
  black and shown once complete, without the original's frame pacing.
  The battle setup replays the RNG steps of the frames it skips, so every
  roll is the original's.
- **Boot screens** (main menu, history books, name entry): one fixed set
  of 25 kanji at upper tiles `$80-$E3`, uploaded once at the boot entry
  (`TXF_MENUSET`).  The message speed prompt (b11_msg_147) shows before
  the speed window.
- **The opening oath:** a fixed split.  The IRQ at line 130 switches R1 to
  CHR `$3800`, which holds the oath's 20 kanji.
- **Title and attract mode** (bank 24): each screen has its own tile set,
  and the portraits are 8x16 sprites.  The title's logo intro (its five
  rows closing up) moves every frame (60 fps; the original stepped every
  4 frames).  The NMI computes the strip positions (`title_fx`), and
  scanline IRQs (`title_irq`, fixed bank) make the mid-frame writes in
  hblank.  Bank 13's steps, Start checks and RNG are unchanged.
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
| `$7800-$78FF` | the map's attribute shadow (`MAP_ATTR`, four-screen) |
| `$7900-$7948` | the title intro's IRQ events (`TFX_*`) |
| `$7949-$7BF4` | free (cleared at reset) |
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
- In map mode, each new kanji of a page waits for its glyph upload, so
  kanji print a little slower than kana.
- Level-up battle (seen before 2026-11-14, not fixed): on the page
  「は<CALL:D565=さくりゃく>を覚えた」, 計 shows only its 言 half and 覚
  is blank.  The call's kanji tail and the page's kanji meet in the same
  pool slots.
