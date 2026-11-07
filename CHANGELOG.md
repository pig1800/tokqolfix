# Changelog

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
