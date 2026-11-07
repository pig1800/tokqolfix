# Current implementation status

Status after the revision-7 page-handling pass (2026-11-07). The runtime is
still the revision-6 ROM-resident design; this pass fixed multi-page text and
added the first message-warp QA sweep.

## Verified on the current build

- Original 256 KiB ROM: byte-identical,
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Kanji 512 KiB SUROM ROM:
  `54fc79b849c69f984b257c62a55c3487ce5ec8596f2d253b01eea2d77f178d33`.
- `bank15_lint`: 7 ranges, bank 31 == bank 15.
- `sram_watch`: 0 hack writes out of 20,683 game battery-RAM writes.
- `iram_watch`: 0 foreign writes to `$0131-$017F` / `$01E0-$01E7`.
- `mask_restore`: 0 visible-scanline PPUMASK restores.
- `stack_check`: min SP `$18` at NMI, `$28` at overlay entry; state starts at
  SP `$31`.
- History prompt (`pp_0900`), name-entry grid (`pp_1600`), field command menu
  and the 6,000-frame survey are clean.
- Oath message pages 1-3 render cleanly; the bottom border row stays `$0D`.
  `out/test/oath_zoom.png` is redone from the settled page 3.
- Four-line page b10_msg_130 page 1 has a kanji on line 4; the bottom border
  is intact (`out/test/fourline_zoom.png`).

## Revision-7 root causes and fixes

### 1. `page_find` was one byte late

`page_find` left `Y` on `code_hi` instead of `code_lo`, so `KANJI_EC` copied
tile bytes starting one byte late: it read the next entry's first tile and
the following entry's `code_lo`.  `$0D` (a permanently reserved border tile)
therefore entered page records, and glyphs were drawn from mixed quadrants.
Fixed with `dey` at `@found`.

### 2. Cross-page visible lines

A page break does not clear the window; up to three lines from earlier pages
remain visible while the next page draws.  Reusing their CHR tiles mixed two
glyphs, and drawing the next page's kana restored kana over the old kanji.
The compiler now reserves, for every page:

- the tiles of the last three visible lines from earlier pages;
- the kana tiles of this page and the next two pages.

The first is a backward carry (`assign_pages_with_reserved`), the second is
`page_future_used`.  Both are needed; either alone still produces mixtures.

### 3. Restore policy and NMI budget

`restore_exit` still skips tiles referenced by `$0180`/`$0300`, because the
history/name-entry screen uses a different kana font and a bank-9 restore
there garbles the prompt.  The restore queue is batched four tiles per frame;
eight tiles pushed `mask_restore` to 4 visible-scanline frames.

## QA sweep

`tools/qa_sweep.py` patches the history-prompt inline index at bank 13
`$8B58/$8BDA/$8C38`, truncates the message at its first page break, runs one
Mesen instance per index and checks page 1:

- page record valid, tiles 0-127;
- no page tile in the nametable outside the window box;
- kana inside the window equals the bank-9 glyph;
- frame tiles `$0B/$0D/$6D-$6F/$7D/$7E` keep their CHR bytes.

Full run (872 indices, 4 workers, 780 s):

| Category | Count |
|---|---:|
| Page 1 clean | 772 |
| Empty message records | 89 |
| Context-dependent failures (shop/battle/name font menus) | 11 |

The 89 empty records are unused message-table entries.  The 11 remaining
failures are not a zero-failure gate: the history-prompt warp renders the
message in the history menu's font/menu context, so shop/battle/name-entry
fonts cannot be compared to bank 9.  The real oath/four-line scenes are the
page-handling gate.  A neutral QA entry point is still needed for 2.5.

## Architecture (unchanged from revision 6)

- Overlay: 1,043 bytes at `$B800`, identical in text banks 18-22.
- Fixed-bank gap: 94 bytes at `$C611-$C66E`; `F8 3A C6` trampoline.
- Patch ranges: `$C4B7`, `$C611-$C675`, `$D1FA`, `$D28E`, `$D2BB`, `$D2C7`,
  `$DBE7-$DBEA`.  No battery-RAM state, no NMI code, no PPU scans.
- Internal RAM: `$0131-$013F` state, `$0140-$015F` RAM stub, `$0160-$016F`
  glyph/kana buffer, `$0170-$017F` dirty bitmap, `$01E0-$01E7` scratch.
- Page record: `count, count*(code_lo,code_hi,t0..t3)`.
- Compiler: static tile assignment, max 10 entries/page, `min_free_static`
  and `pages_over_capacity` reported; current build is 0 unfit pages.
- `scene_borrow.tsv`: 9 surveyed labels; oath scene = `$42-$5B`.
- Prompt list tags: 63 `menu`, 7 `savename` (exact 65-tile name-entry set).

## Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua    --name sram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\iram_watch.lua    --name iram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua  --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\stack_check.lua   --name stack
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua  --name prompt
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua    --name town
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua  --name survey
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\oath_settled.lua  --name oath
python tools\qa_sweep.py --workers 4
```

## Remaining work

1. **Neutral QA harness for 2.5.** The history-prompt warp is not neutral
   (menu/font context). Add a dedicated QA entry point that opens a message
   in a blank window, or capture each page in its real scene. Then rerun all
   872 indices with zero hard failures.
2. **Per-page QA beyond page 1.** The current `qa_sweep` truncates at the
   first page break. Extend it to page N by patching the stub text address
   and metadata, or add a page-start table to the compiler.
3. **Prompt list tags.** 63 `menu`, 0 `party`, 0 `item`. Walk the
   `text_print_inline` callers that precede party/item lists and add tags.
4. **Scene-borrow coverage.** Extend the playthrough and regenerate
   `scene_borrow.tsv`; the QA kana assertion is the backstop.
5. **Save-slot proof.** Register a book in slots 2/3 on both ROMs and compare
   `$6800-$7FFF`.
6. **Emulator-only compatibility checks.** Random RAM/CHR power-on, no PRG
   register bit-4 writes, second emulator; then hardware when an N8 exists.
7. **Phase 3 content conversion** (inline scripts, WORD/PLACE/ITEM tables,
   name records) and Phase 4 UI screens.

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/scene_borrow.tsv`
- `JF-Dot-Shinonome16.ttf`

Generated `decomp/build/kanji/*.bin` and `out/qa/*` are build/QA products.
