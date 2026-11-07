# Current implementation status

Status after the revision-8 field-context pass (2026-11-08). The runtime is
still the revision-6 ROM-resident design, now with stale-CHR restore on both
message open and `<JUMP>` exit, plus per-message screen-tile reservations.

## Final build

- Original 256 KiB ROM: byte-identical,
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Kanji 512 KiB SUROM ROM:
  `a90614d88a584d436255c4ee5d7f28b28984acfb758a6cf17d45c296436dccb9`.
- Overlay: 1,150 bytes at `$B800`, identical in text banks 18-22; fixed-bank
  hooks 94 bytes at `$C611`.
- `bank15_lint`: 9 registered ranges, bank 31 == bank 15.
- Compiler: 760 messages, 1,190 pages, max 10 entries/page, max 11 pages per
  message, `pages_over_capacity=0`; text in banks 18-21.

## Gates on the final build

| Gate | Result |
|---|---|
| Original target | byte-identical |
| `bank15_lint` | 9 ranges, bank 31 == bank 15 |
| `sram_watch` | 0 hack writes among 17,314 battery-RAM writes |
| `iram_watch` | 0 foreign writes among 29,164 reserved-range writes |
| `mask_restore` | 0 PPUMASK restores on a visible scanline |
| `stack_check` | min SP `$18` at NMI, `$28` at overlay entry |
| Field QA (`qa_field.py`) | 872 indices, 0 failures |
| Per-page QA (`qa_pages.py`) | 872 indices, 1,356 pages, 0 failures |
| History/shop smoke (`qa_sweep.py`) | 867 page-1 clean; 5 short-message timing cases, all clean under `qa_pages` |
| Original history/name-entry CHR | 0 diffs against bank 9 |
| Four-line page | line-4 kanji with bottom border intact (`fourline_zoom.png`) |

The 56 empty message-table records and the four CALL-only battle fragments
are handled by the QA harness: empty records now emit a valid `$FF` stream,
and CALL tokens are neutralised only in the QA ROM.

## Revision-8 root causes and fixes

### D1. `<JUMP>` did not run the exit restore

The interpreter leaves through `jmp ($00F3)` at `$D19B` with the target in
`ppu_update_ptr_lo/hi`.  A field replay showed 76 dirty bits carried into the
next scene; the command menu then displayed kanji fragments.

- Patched `$D190`/`$D198` to `jump_exit_13`/`jump_exit_14` in the overlay.
  Each preserves A/X/Y, restores every dirty tile with the normal four-tile
  batch, then tail-jumps to the original `set_bank_13`/`set_bank_14`.
- `overlay_entry` now installs the RAM font-copy stub first and restores any
  dirty tiles left by the previous message before clearing the map and
  loading the new page.  This also covers `<END>`, `<END_NOWAIT>`,
  `<CALL>`-without-return and `text_init` resets.
- Result: the field replay shows dirty 76 -> 0 before the script bank is
  mapped, and `qa_field` is clean for every index.

### D2. The command menu stays on screen during field messages

The field command menu, HUD and cutscene scenery reference tiles that the
compiler could assign to kanji.  The old prompt tags covered only menus drawn
by the text engine.

- `qa_sweep.py` and `qa_field.py` now record every lower tile referenced
  outside the page's text-window box.  The window is the bounding box of the
  page's own tiles; page tiles that leak into the scene expand it and are
  caught by the field menu-box check.
- `make_screen_survey.py` merges the history/shop survey, the field survey and
  page 1 of the per-page survey into
  `decomp/text/kanji_plan/scene_borrow.tsv` (scene borrow + screen columns).
- `extra_for` reserves the per-label scene tiles minus the message's own kana
  (already in `page.used`), plus the measured field command-menu/HUD floor
  (`FIELD_SCENE_TILES`, 48 tiles).  Unsurveyed records use the 70-tile
  fallback (field floor plus the 26-tile oath-scene borrow).
- Field harness: `tools/lua/town_menu.mss` (town, menu open) plus
  `tools/qa_field.py`, which overrides the next `text_show_message` index and
  captures with the menu visible.  `town_menu_save.lua` regenerates the
  state.

### D3. The "different history font" claim was false

On the original ROM, CHR `$1000-$17FF` at the history prompt, name-entry grid
and 1,600-frame screen matches bank 9 in all 128 tiles.  The 20 differing
tiles on the kanji ROM are exactly the prompt's own kanji slots
(`$0E,$0F,$24-$28,$42-$4E`).  The remaining shop/menu failures were real
stale kanji from earlier messages; the open-time restore and per-message
reservations close them.

### Page splitting tradeoff

The larger scene reservations reduce page capacity.  Pages now hold at most
10 kanji; the oath message is 9 short pages instead of 3.  All text and
borders are clean, but the extra page breaks are a readability cost.  Further
compaction would need a different reservation strategy; correctness was
prioritised.

## Revision-7 work carried forward

- `page_find` off-by-one (`dey` at `@found`).
- Backward carry of the last three visible lines and forward reservation of
  the kana that can be drawn before those lines scroll away.  The forward
  set is now the first three lines of the next two pages, not whole pages.
- `restore_exit` skips tiles still referenced by `$0180`/`$0300`; the restore
  batch is four tiles per frame.

## QA tools

| Tool | Purpose |
|---|---|
| `tools/qa_sweep.py` | Fast history-prompt page-1 warp; screen survey and smoke gate |
| `tools/qa_field.py` | Field context with command menu open; all 872 indices |
| `tools/qa_pages.py` | Samples every 2 frames, groups by `KANJI_PAGE_PTR`, checks every page |
| `tools/make_screen_survey.py` | Merges surveys into `scene_borrow.tsv` |
| `tools/field_check.py` | Offline command-menu CHR check for `field_kana_check.lua` |
| `tools/qa_summary.py` | Compact report summary |

## Remaining work

1. **Phase 2b prompt tags.** 63 `menu`, 7 `savename`, 0 `party`, 0 `item`.
   Walk the `text_print_inline` callers in banks 13/14/15 and tag party/item
   prompts.
2. **Save-slot proof.** Register a book in slots 2 and 3 on both ROMs with
   identical inputs and compare `$6800-$7FFF`.
3. **Emulator-only compatibility checks.** Random RAM/CHR power-on on three
   seeds, no PRG-register bit-4 writes, a second emulator run.
4. **Hardware pass.** When an EverDrive N8 is available.
5. **Phase 3 content conversion.** Inline bank-15/13 scripts, WORD/PLACE/ITEM
   tables, name records; then Phase 4 UI screens and release.
6. **Optional readability work.** Revisit the page-splitting tradeoff if the
   9-page oath is unacceptable.

## Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji

python tools\qa_sweep.py --workers 4
python tools\qa_field.py --workers 4
python tools\qa_pages.py --workers 4
python tools\make_screen_survey.py
python tools\qa_summary.py

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua   --name sram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\iram_watch.lua   --name iram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\stack_check.lua  --name stack
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\field_kana_check.lua --name fk
python tools\field_check.py
```

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/scene_borrow.tsv`
- `JF-Dot-Shinonome16.ttf`

Generated `decomp/build/kanji/*.bin`, `out/qa/*` and `out/test/*` are build/QA
products.
