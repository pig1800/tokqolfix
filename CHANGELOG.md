# Changelog

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
