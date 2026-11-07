# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 4, 2026-11-07, after the revision-3 pass (commits `a3f8b8d`,
`b5ac5f1`; evidence in `SITREP.md`). Earlier revisions are in git history.
Section 1: milestone. Section 2: font change made in this iteration.
Section 3: findings and decisions. Section 4: revised design deltas.
Section 5: ordered work list. Later phases unchanged at the end.

Goal and platforms unchanged: every dialogue line, menu, table string and
screen label in kanji+kana; Mesen and the original EverDrive N8.

---

## 1. Milestone reached

- Runtime CHR cache works end to end: CHR scan builds the resident-kana
  bitmap, nametable scan builds the on-screen bitmap, the allocator takes
  four distinct free tiles per kanji, restore is lazy and demand-driven.
- The history prompt renders as one page with the choice menu above it;
  the name-entry grid, field command menu and field map are clean
  afterwards. No hang or NMI re-entry across 6,000 frames.
- Upper-half allocation removes the save-slot/kanji collision: the prompt
  and the runtime slot line are both clean at `ktown_1100`/`ktown_1240`.
- Bank 31 mirrors bank 15; 17 registered patch sites; SRAM audit clean.
- The scene survey confirmed the model from revision 3: the oath scene
  borrows kana `$42-$5B` (26 tiles), a field transition briefly borrows
  `$00-$17`; worst case 26 is the compiler allowance.

---

## 2. Font replaced (done in this iteration)

DotGothic16 rasterised with 2-pixel strokes at 16 px (歴, 書, 軍 were
visibly heavy). It is replaced by **JF-Dot-Shinonome16.ttf**:

- At size 16 with the `lt` anchor it rasterises to pure 0/255 pixels for
  all 718 inventory glyphs, so the threshold never widens a stroke.
- Glyphs fill the full 16×16 cell. The game's own 104 bank-1 name glyphs
  also use every column and row, so no offset is applied.
- `tools/kanji_common.py` now points at the new TTF; `kanji_font.py`
  documents the choice; `STATUS.md` source-of-truth updated.
- Rebuilt: original target still byte-identical; kanji target after the
  revision-4 runtime work is
  `862d7f377d11050e3eb0f4b4118b6267140cf4d3705bbb913f596bd47d78d6bb`.
- In-game check: `out/test/pp_0900.png` shows `どの歴史書を登録しますか?`
  with single-pixel strokes; `out/test/ktown_1100.png` and
  `out/test/ktown_1240.png` show the history prompt with the save-slot line
  and choice menu both clean.

Phase 3.4 (retouch) shrinks to a comparison of the name kanji against the
original 136 glyphs; Shinonome's style already matches the era.

---

## 3. Findings and decisions

### F13. The save-slot collision is one instance of a general class

Any kana drawn by the game *after* a prompt opens and *outside* the text
engine's page (save-slot names, party-member lists, item lists, officer
lists) can need a tile the prompt's kanji borrowed. `kana_prepare` then
restores the tile and the prompt shows a kana fragment. Save-slot names are
player-typed, so no reservation can bound them. Two mechanisms are needed,
both decided:

1. **Upper-tile allocation for prompts.** The upper half holds the game's
   menu/name-font graphics at the history screen, so it is not blank.
   Evidence `ktown_1100_chr.bin`: 124 of 128 tiles `$80-$FF` are
   non-zero. The allocator therefore uses upper tiles that are
   **unreferenced** by either nametable or by OAM, not only blank ones.
   The pool opens only when the whole upper half is unreferenced, so map
   and portrait screens keep it closed. Borrowed tiles restore to zero at
   message exit; the game reloads CHR on screen changes. Cost: the only
   bit-7 test on the cell buffer in bank 15 is `text_render_cell` at
   `$DBEA-$DBEE` (`lda $0300,y / bpl`). Patch in place: `jsr cell_check`
   over the load, change `bpl` (`$10`) to `bcc` (`$90`); `cell_check` =
   `lda $0300,y / cmp #$FA / rts` (6 bytes) at `$C64F`, inside the
   `$C611` gap. Controls `$FA-$FF` keep working. State: 16-byte upper
   free bitmap (`$68B0-$68BF`), 16-byte upper dirty bitmap
   (`$6910-$691F`), 32-byte screen/visible bitmap (`$68F0-$690F`).
2. **Reservation unions for field prompts.** Where the upper pool is
   closed (map, portraits), prompt pages fall back to lower kana. A
   compiler union of `menu ∪ party_name ∪ item_name` was attempted in
   this pass but could not fit even after 20 page splits, so it is not
   enabled. This remains open for field-prompt screens; the runtime does
   not yet log blank-slot allocations per message.

The executor's option "convert the slot menu to the kanji drawer" is still
right for phase 4 but does not close the class; "decode the save name" and
"kana relocation" are rejected (fragile; reverted once already).

### F14. The nametable scan covers one nametable; the field uses two

`$2000-$23FF` and `$2400-$27FF` are distinct and both can be on screen while
the map scrolls. The scan now covers 2 KiB at 128 bytes per frame (16 frames).
It alternates with the CHR scan so one NMI never pays for both. Field map
screens show upper tile indices in both nametables, confirming the need for
the second half.

### F15. Message-open cost can be cut without new patches

The CHR scan only needs to rerun when CHR may have changed. Both change
paths are observable from inside the NMI overlay entry: rendering was off
since the last scan (bulk loads happen then), or a VRAM-queue entry since
the last scan targeted an address below `$2000`. Keep the resident bitmap
across messages otherwise. The nametable scan stays per message.

### F16. NMI budget is measurable in the harness

`tools/lua/nmi_budget.lua` hooks `$EE7F` and `$EF31` and subtracts
`getCpuState().cycleCount` to measure handler duration. `getState().ppu.scanline`
returned -1 inside the exec callback, so the implemented check uses CPU
cycles instead. Baseline original max 10,132 / average 2,786; kanji ROM max
15,833 / average 3,430. The peak is the scan handler, which runs with
rendering off while the main thread waits. Splitting the two scans cut the
peak from 21,636 cycles.

### F17. Overlay headroom

The overlay is now 2,981 bytes of the 3,070-byte limit; 89 bytes remain.
The 4 KiB copy caused BRK/NMI storms and was not bisected. If more is ever
needed, bisect the 4 KiB failure (copy duration vs the `$7C02-$7FFF`
zeroing) rather than guessing.

---

## 4. Design deltas (revision 3 remains in force otherwise)

| Area | Change |
|---|---|
| Cell buffer | Tiles `$00-$F9` allowed; `$FA-$FF` remain controls (F13.1). |
| Allocator | Order: unreferenced upper tiles when the whole upper half is idle, then resident+unused+unreferenced lower kana tiles. |
| Restore | Upper tiles restore to zero; kana tiles to the kana copy. Both lazy, plus rendering-off drain and message-open restore. |
| Compiler | Prompt pages reserve menu kana (current behaviour). The party/item union remains an open field-prompt item. |
| Scans | CHR 128 tiles and nametables 2 KiB, alternating frames (F14, F16). |
| Harness | `nmi_budget.lua` records max/average handler cycles. Blank-slot logging is still open. |
| Font | JF-Dot-Shinonome16, no offset (section 2). |

---

## 5. Work list for the next pass (ordered)

### Phase 1 — Close the collision class and verify budgets

| # | Task | Status / exit criterion |
|---|---|---|
| 1.1 | Rebuild with the new font; re-run `prompt_pages.lua`, `town_kanji.lua`, `scene_survey.lua`. | Done. Prompt, name entry, field menu and 6,000-frame survey clean. |
| 1.2 | Upper-tile support: `cell_check` at `$DBE7`, upper free/dirty bitmaps, OAM/nametable gate, restore-to-zero, lint registration. | Done. History prompt allocates `$80-$93`; `ktown_1100` / `ktown_1240` show prompt, slot line and menu clean. |
| 1.3 | Prompt reservation unions and blank-slot logging. | Open. Full union did not fit after 20 splits; field prompts still fall back to lower. |
| 1.4 | Nametable scan over `$2000-$27FF` at 128 B/frame. | Done. 6,000-frame field survey intact. |
| 1.5 | NMI budget recording and the busiest case. | Done as `nmi_budget.lua` (cycles). Max 15,833 vs baseline 10,132 after splitting scans. |
| 1.6 | Conditional CHR rescan (F15). | Open. |
| 1.7 | Redraw test with a scrolling four-line page. | Open; no scripted case yet. |

### Phase 2 — Harden (unchanged)

Outer-bank checklist; all `<CALL>`/`<JUMP>` messages; fourth-line check;
EverDrive N8 boot, dialogue, save, power-cycle, load.

### Phase 3 — Script, tables, menus (unchanged, now the largest remaining work)

Proofread both `_fixed.dtx` files including compiler-split pages; move the
bank-15/13 inline menu and oath strings into indexed messages; convert
WORD/PLACE/ITEM tables and name records; regenerate inventory and font;
compare name kanji against the original 136 glyphs.

### Phase 4 — UI screens (unchanged)

Per screen by row pitch, including the history slot menu as a kanji-aware
drawer; status-screen labels after tracing its split.

### Phase 5 — QA and release (unchanged)

Scripted render of all 872 messages; Mesen and N8 playthrough; BPS patch.

---

## 6. Risks (updated)

| Risk | Status |
|---|---|
| Dynamic kana lists over prompts (F13) | Upper-half history/menu case fixed; field prompts that fall back to lower remain (1.3). |
| Upper pool overwrites unreferenced graphics | Open; verify each new scene with a screenshot and CHR dump. |
| NMI overrun with scans active | Measured max 15,833 cycles; split from 21,636. Re-measure on hardware. |
| Overlay headroom | 89 bytes; bisect before growing. |
| Font style of name kanji | Compare in phase 3. |

---

## 7. Commands

```powershell
python decomp\build.py                       # original, byte-identical
python decomp\build.py --target kanji        # 512 KiB SUROM target + lint
python tools\kanji_font.py build             # regenerate font from JF-Dot-Shinonome16
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua --name prompt_pages
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua    --name ktown
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua  --name survey_kanji
```

Outputs land in `out/test/`. Mesen runs always use a copied ROM name.
