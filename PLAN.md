# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 7.1, 2026-11-07, after the revision-6 execution (commit `a14ab1c`).
Section 1: what the pivot achieved, re-verified. Section 2: the regression
that blocks "done". Section 3: work list. Section 4: decisions already made
and what remains for the user. Earlier revisions are in git history; the
design in revision 6 stands.

**Target for this phase: emulator only (Mesen).** The user has no EverDrive
N8 at present. The hack must stay N8-compatible by construction (SUROM
512 KiB, standard MMC1 behaviour, no emulator-only tricks), but no task is
gated on hardware. Hardware verification is a later phase, done when an N8
is available, after every emulator gate is green.

---

## 0. Revision-7 execution results (2026-11-07)

The blocking multi-page regression is fixed and verified.

### Root cause

`page_find` left `Y` on the entry's **code_hi** byte instead of code_lo, so
`KANJI_EC` copied tile bytes one byte late: every glyph read the next entry's
first tile plus the following entry's code_lo.  That produced the mixed
glyphs and put `$0D` (a permanently reserved border tile) into page records.
Fixed with `dey` at `@found`.

The remaining visual mixing was cross-page: the window keeps up to three
lines from earlier pages visible while the next page draws.  The compiler now
reserves, for each page:

- **backward**: the tiles of the last three visible lines of earlier pages;
- **forward**: the kana tiles of this page and the next two pages.

This keeps previous kanji in CHR and keeps the new page's kana from restoring
over them.  `restore_exit` still skips visible tiles (the history/name-entry
screen uses a different kana font, so restoring bank-9 kana there would
garble the prompt); the restore queue batch is four tiles per frame to keep
`mask_restore` at 0.

### Verified

| Check | Result |
|---|---|
| Oath message pages 1-3 | clean; `oath_zoom.png` redone from the settled page 3 |
| Border row | `$0D` intact through pages 1-3 |
| Four-line page (b10_msg_130 page 1) | kanji on line 4, bottom border intact; no compiler rule needed |
| `mask_restore` | 0 visible-scanline frames |
| `sram_watch` | 0 hack writes of 20,683 game writes |
| `iram_watch` | 0 foreign writes to the reserved ranges |
| `stack_check` | min SP `$18` at NMI, `$28` at overlay entry |
| History prompt / name entry / field survey | clean |
| QA warp sweep | 872 indices: 772 page-1 clean; 89 empty records; 11 context-dependent (menus/font pages outside the neutral text window) |

The 89 empty records are unused message-table entries with no text.  The 11
remaining sweep failures are **not** a zero-failure gate: the history-prompt
warp renders arbitrary messages in the history menu's font/context (shop and
battle menus, name-entry font), so their kana cannot be compared to bank 9.
The sweep tool is `tools/qa_sweep.py`; a neutral warp/QA harness is still
needed for the plan's 2.5 gate.  The real oath and four-line scenes are
verified separately above.

Current hashes: original `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
kanji `54fc79b849c69f984b257c62a55c3487ce5ec8596f2d253b01eea2d77f178d33`.

---

## 1. Revision 6 achieved its architecture goals (re-verified)

Rebuilt and re-run on the committed tree:

| Gate | Result |
|---|---|
| Original target | byte-identical |
| `bank15_lint` | 7 ranges, bank 31 == bank 15 |
| `sram_watch` | 0 hack writes out of 21,923 battery-RAM writes |
| `mask_restore` | 0 PPUMASK restores on a visible scanline |
| Internal RAM | only `$0131-$017F` and `$01E0-$01E7`, both audited free |
| Compiler | 1,151 pages, max 11 entries, `pages_over_capacity=0`, overlay 2,048 bytes in banks 18-22 |

The runtime is ROM-resident, uses no battery RAM, no NMI code, no PPU
reads. The history prompts, name entry, field command menu and map are
clean. These are the properties that every earlier design lacked, and they
are now structural rather than tested-for.

---

## 2. Regression: multi-page messages are broken

`out/test/survey_1920.png` (the oath scene, second page of `b10_msg_126`;
zoom in `out/test/oath_zoom.png`) shows:

- several kanji drawn as mixtures of two glyphs (願, 月, 日, 大, 魔, 覧);
- one kana with dakuten damaged (ば);
- the entire bottom border row of the window replaced by a kanji quadrant.

The bottom border tile `$0D` is in the permanent reserved set, so the
compiler cannot have assigned it. The runtime therefore wrote a glyph
quadrant to a tile number it did not get from a valid record. The pattern
fits a page-advance fault: after `<PAGE>` the page pointer or entry index
lands at the wrong offset, tile numbers are read from the wrong bytes, and
the uploaded bitmap is stale. Every screenshot the executor verified was a
single-page message, which is why "done" was reported.

Repro: `tools/lua/state_ppu_dump.lua` loads the oath save state directly;
advance one page and dump. No title-to-scene replay needed.

---

## 3. Work list (ordered)

### Phase 2a — Fix and prove page handling (blocking)

| # | Task | Exit criterion |
|---|---|---|
| 2.1 | **Done.** Debug the page advance: `page_find` Y was one byte late; compiler now reserves the last three visible lines and the next two pages' kana. | Oath pages 1-3 clean; border `$0D`; `oath_zoom.png` redone. |
| 2.2 | **Done.** Four-line check on b10_msg_130 page 1: kanji on line 4, bottom border intact; no compiler rule or window shift needed. | `out/test/fourline_zoom.png`. |
| 2.3 | **Done.** Multi-page and four-line scripts added: `oath_settled.lua`, `oath_page3.lua`, `qa_sweep.py`. | Scripts in `tools/lua`, listed in `STATUS.md`. |

### Phase 2b — QA sweep (the gate for everything after)

| # | Task | Exit criterion |
|---|---|---|
| 2.4 | **Done, with a caveat.** `make_survey_rom.py`-style warp generator in `tools/qa_sweep.py` patches bank 13 `$8B58/$8BDA/$8C38`; it also truncates the message at its first page break to keep page 1 stable. | One ROM per index generated on demand. |
| 2.5 | **Partial.** Sweep ran all 872 indices: 772 clean page 1, 89 empty records, 11 context-dependent failures (shop/battle/name font menus). The history-prompt warp is not a neutral context; a dedicated QA entry point is needed for the zero-failure gate. | `out/qa/report.json`; neutral harness still open. |
| 2.6 | Prompt list tags: the report shows 0 `party` and 0 `item`. Walk the `text_print_inline` callers in banks 13/14/15 that precede a party/item list and tag those prompts; drop `menu` where no menu follows. | Tag table in `kanji_text.py` with a caller address per entry. |
| 2.7 | Scene-borrow coverage: extend the scripted playthrough as far as inputs allow and regenerate `scene_borrow.tsv`; the QA sweep's kana-intact assertion is the backstop for unsurveyed scenes. | Labels covered ≥ all event-scene messages reached by the playthrough. |
| 2.8 | Save-slot proof: register a book in slot 2 and in slot 3 on both ROMs with the same inputs; compare `$6800-$7FFF` dumps. | Byte-identical. |

### Phase 2c — Hardware-compatibility checks that can run in the emulator

No N8 is available, so the hardware pass is deferred (section 4). What the
emulator can still prove, and must:

| # | Task | Exit criterion |
|---|---|---|
| 2.9 | Power-on with random RAM and random CHR RAM (Mesen "randomize RAM" and "random power-on state"), both ROMs: boot, both history prompts, oath scene, field message. The hack keeps no state across power-on, so this should be a formality; prove it. | Clean on 3 seeds. |
| 2.10 | MMC1 behaviour the N8 implements faithfully: the kanji ROM must never write bit 4 of the PRG register (PRG-RAM disable on MMC1B) and must set the CHR-bank outer bit only through the switcher. Add a Mesen write-callback script on `$E000-$FFFF`/`$A000-$BFFF` register writes that logs any 5-bit value with bit 4 set reaching the PRG register. | Zero occurrences over the survey run. |
| 2.11 | Run the full QA sweep (2.5) and the survey under Mesen's "NTSC, accurate PPU" default and once under FCEUX or Nestopia if installed, for a second mapper implementation. | Same results; any difference is investigated, not averaged. |

The later hardware phase (when an N8 exists): boot, prompts, oath scene,
field message, save in all three slots, power-cycle, load.

### Phase 3 — Script, tables, menus (unchanged)

Proofread both `_fixed.dtx` files; move inline bank-15/13 menu and oath
strings into indexed messages; convert WORD/PLACE/ITEM tables and name
records; regenerate inventory and font. Decision pending on kana in field
lists (section 4).

### Phase 4 — UI screens, Phase 5 — release (unchanged)

---

## 4. Decisions made, and what remains for the user

Decided for this phase (the executor acts on these without asking):

1. **Emulator-only target.** Mesen is the reference. Compatibility with the
   EverDrive N8 is preserved by design rules (2.10) and verified later on
   hardware. No task waits on an N8.
2. **Kana inside field lists.** Party and item list entries drawn on the map
   stay in kana; dialogue, prompts, menus and every other label use kanji.
   This is the default for phase 3 table conversion. It can be revisited
   with a pattern-table split later; nothing in phase 3 forecloses that.

Still for the user, later:

3. **Proofreading.** Phase 3 needs a reader of Japanese to check the
   machine draft, especially archaic lines (`b10_msg_126` oath,
   `b11_msg_031` divination) and names. The executor should not be the
   sole judge of the Japanese; decide who does this when phase 3 starts.
4. **Hardware pass** when an N8 is available, after all emulator gates are
   green.
5. The build is safe for saves, but the full-message QA gate is still open;
   do not distribute until the Phase-2 sweep has a neutral harness and zero
   failures.

---

## 5. Commands

```powershell
python decomp\build.py                       # original, byte-identical
python decomp\build.py --target kanji        # 512 KiB SUROM target + lint
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua    --name sram_watch
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\iram_watch.lua    --name iram_watch
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua  --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\stack_check.lua   --name stack
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua  --name survey
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\oath_settled.lua  --name oath
python tools\qa_sweep.py --workers 4
```

Gates: `sram_watch` zero hack writes, `iram_watch` zero foreign writes,
`mask_restore` zero visible-scanline frames, lint 7 ranges. The QA sweep is
still context-dependent (see section 0); the real oath/four-line scenes are
the page-handling gate. Mesen runs always use a copied ROM name.
