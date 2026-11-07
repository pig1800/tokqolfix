# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 3, 2026-11-07, after the revision-2 pass (commits `3be259e`,
`0be4f8a`). Earlier revisions are in git history. Section 1 records the
milestone, section 2 the review findings with evidence, section 3 the
corrected CHR model, section 4 the revised design, section 5 the ordered
work list. Script, UI and QA phases are unchanged and kept at the end.

Goal and platforms are unchanged: every dialogue line, menu, table string
and screen label in kanji+kana; Mesen and the original EverDrive N8.

---

## 1. Milestone reached

- `どの歴史書を登録しますか?` renders with legible 16×16 kanji inside the
  dialogue window (`out/test/kanji_prompt_900.png`). The full chain works:
  SUROM switch, far trampoline, RAM overlay, page records, 1bpp expansion,
  NMI upload, two-cell rendering.
- Bank 31 is byte-identical to patched bank 15 and the lint enforces it.
- The caller-bank clobber (revision-2 F2) is fixed (`F8 3A C6`).
- Random-SRAM power-on still installs the overlay and renders.
- A 6000-frame watchpoint shows the base game never writes `$6800-$7FFF`.
- The compiler now reserves exact table/name tiles per page and caps page
  records at 255 bytes.

---

## 2. Review findings

### F8. The CHR blocker is misdiagnosed — it is not the town map

`STATUS.md` says the field/town nametable references almost every tile in
`$00-$7F` plus all of `$80-$FF`. The executor's "town" captures at frames
1720/1960 (`otown_*`) are the **oath scene** with three portraits; the
title → new game input sequence does not reach town by then. Measured on
the original ROM at those frames:

| Item | Value |
|---|---|
| PPUCTRL / nmi_mode | `$90` / 0 — one BG pattern table, no split |
| Tiles `$80-$FF` referenced | 128 (portrait graphics) |
| Tiles `$00-$7F` referenced | 56–58: window text, frame/dakuten tiles, and the whole block `$42-$5B` |
| Kana tiles intact in `$1000-$17FF` | **102 of 128** |

The game itself overwrites 26 kana tiles (`$42-$5B`, the katakana block the
scene does not need) with portrait graphics. So `$1000-$17FF` is a pool the
game already shares between kana and scene graphics, per scene, by hand.
The compiler's "tiles the page does not use" set includes those 26, so the
kanji cache stomped on portrait tiles and the restore then wrote kana over
portrait graphics. Nothing about the town map is known yet; no town capture
exists. The fix is **never to borrow a tile that does not currently hold
its kana glyph**, which makes the restore source always the kana copy and
removes the need for a CHR save buffer.

### F9. The kanji ROM hangs after the name-entry screen

`ktown_1100/1240/1720/1960_cpu.txt` all show `PC=$73D0` (inside the RAM
overlay) with the stack pointer wandering (`$4D`, `$EE`, `$6E`), and the
screen is black with PPUMASK `$06`. The original reaches name entry and the
oath scene at those frames. Whether these captures come from the reverted
prototype or the current build is not recorded; the next pass must re-run
`town_kanji.lua` on a clean build first. The name-entry screenshot at frame
900 (`ktown_0900.png`) also shows kanji fragments in the kana grid, which
is the restore problem from F8/F3 in a screen drawn outside the text
engine.

### F10. The reverted prototype failed on NMI discipline, not on the idea

The trace (`nmi_bal.txt`) shows repeated NMI entries within one frame with
the stack sinking. That is NMI re-entry: the hook ran a wait loop or a job
longer than a frame inside the handler. Rules for any NMI-side CHR work:

1. Never spin on a flag inside the NMI handler.
2. Bound the work per frame (N tiles), keep a job queue in SRAM, and let
   main-thread code wait with the existing `update_frame` loops.
3. Run the hook after the handler's `lda PPUSTATUS` has cleared the vblank
   flag, and before `ppu_nmi_on`.
4. When PPUMASK has rendering off (screen transitions, PPUMASK `$06`), the
   job runner may drain the whole queue; PPU access is unrestricted then.

### F11. Restore-at-exit was removed for a real reason

The history prompt ends with the window still on screen while the choice
menu is open, so restoring at message exit erased visible kanji. Restore
must therefore be lazy and tied to *demand* for a tile, plus a full restore
at the one safe point: rendering off. Details in section 4.

### F12. Reservation must cover concurrent menus

Prompts that leave the window up (`<END_NOWAIT>`, `<WAIT>`) can be overlaid
by the yes/no, choice and command menus. Those menu kana must not be
borrowed by such pages. The compiler already computes `menu_stream_tiles`
(76 tiles); it must reserve that set only for those messages, not globally.

---

## 3. CHR model (corrected)

- `$0000-$0FFF`: sprites (portraits in event scenes, characters on maps).
- `$1000-$17FF`: kana font, 128 tiles. **Scenes may overwrite any of these
  with graphics**; the oath scene takes `$42-$5B`.
- `$1800-$1FFF`: scene graphics (portraits, map chips); never free.
- A tile is borrowable for the kanji cache only if, at message open, its
  16 bytes equal the kana glyph (plane 0 = font, plane 1 = 0), it is not
  used by the page's text or runtime insertions, and it is not reserved.
- Permanently reserved: frame, cursor, space, digits, dakuten marks
  (already), plus `$6C` 金 and `$7F` 兵, which the field map uses as icons.
- Unknowns to measure (task 1.3): how many kana tiles each scene takes
  over, and the town/field map context. The compiler's capacity check must
  assume the worst measured scene.

---

## 4. Revised design

Unchanged: SUROM 512 KiB, bank 31 = bank 15, RAM overlay with signature,
`F8 3A C6` trampolines, `$EC/$ED/$EE` codes, 1bpp font, page records.

Changed:

1. **Runtime free-tile discovery.** At message open the far loader queues
   a CHR scan job: read each candidate tile in `$00-$7F` back through
   PPUDATA and compare with the SRAM kana copy. Result: a 16-byte
   `KANA_RESIDENT` bitmap. Candidate order is "least likely to be needed"
   so the scan can stop once enough free tiles exist for the page.
   Budget: 8-16 tiles per frame inside the NMI job runner; a full scan is
   8-16 frames, a candidates-only scan is 3-5. Write-tracking (hooking the
   seven PPUDATA writers) was considered and rejected: it needs six more
   bank-15 patch sites and the `$C611` gap has about 20 bytes left.
2. **Runtime slot allocation.** Page records carry the distinct kanji codes
   and the page's used-kana bitmap; tile numbers are assigned at runtime
   from `KANA_RESIDENT ∧ ¬used ∧ ¬reserved`, four tiles per kanji, not
   necessarily consecutive (the handler already takes four independent
   tile numbers). Uploaded flags move to an SRAM table keyed by slot.
3. **Restore policy.** Borrowed tiles always held kana, so restore = kana
   copy. Restore happens (a) per tile, on demand, in a `text_put_tile`
   entry hook so every kana draw through the engine self-heals;
   (b) all dirty tiles whenever the NMI sees rendering off; (c) all dirty
   tiles at the next message open before the scan. No restore at exit.
4. **Reservation rule.** Messages ending in `<END_NOWAIT>` or `<WAIT>`
   additionally reserve the menu kana set. Global reserved set gains
   `$6C`/`$7F`.
5. **Redraw.** `text_redraw_lines` gets a hook that re-uploads page entries
   whose tiles were restored since upload (flag cleared by the per-tile
   restore). With rule 4 this only triggers after rendering-off
   transitions, where the game redraws the window anyway.
6. **NMI job runner** replaces the single-flag upload: a small queue in
   SRAM of jobs (upload 16-byte tile, scan tile, restore tile), processed
   up to a per-frame budget, drained fully when rendering is off.
   Obeys F10 rules 1-3.
7. **Capacity check in the compiler** uses the measured worst-case scene
   borrowing from task 1.3 and splits pages as today.

---

## 5. Work list for the next pass (ordered)

### Phase 1 — Stabilise and measure (blocking)

| # | Task | Exit criterion |
|---|---|---|
| 1.1 | Clean rebuild; run `town_kanji.lua`, `trace_message.lua` and `boot_long.lua` on the current ROM. Record PC/SP at each dump in `STATUS.md`. If `PC=$73D0`-style hangs persist, bisect: disable the NMI entry hook first, then the palette hook. | No hang through frame 6000; name entry and oath scene reached. |
| 1.2 | Rewrite the NMI-side code as the bounded job runner (design 6) following F10. Remove every wait loop from NMI context. | Trace shows one NMI entry per frame across the oath scene and the outdoor map. |
| 1.3 | Scene survey on the original ROM: extend `boot_long.lua` to dump CHR every 60 frames to frame 6000 and through a real town (fix the input sequence so it actually reaches town; verify with screenshots). Script: count tiles in `$00-$7F` not equal to the kana font, per dump. | Table of max borrowed kana tiles per scene; worst case recorded in `kanji_text.py` as the capacity allowance. |
| 1.4 | Implement the CHR scan job and `KANA_RESIDENT` bitmap (design 1). | In the oath scene the bitmap excludes `$42-$5B`; on the title prompt it includes all 128. |
| 1.5 | Runtime slot allocation (design 2); compiler emits codes + used bitmap instead of tile numbers; capacity check uses the 1.3 allowance. | Oath-scene pages render with no portrait corruption; `kanji_text_report.json` shows zero pages over capacity. |
| 1.6 | Restore policy (design 3): `text_put_tile` entry hook, rendering-off full restore, restore at message open. Register the new patch site in the lint. | After the history prompt, the name-entry grid is clean (`ktown_0900` equivalent). After the oath scene, the command menu is clean. |
| 1.7 | Reservation rule for prompt messages (design 4). | Choice menu over the history prompt shows digits and kanji together, no fragments. |
| 1.8 | Redraw re-upload hook (design 5). | Open the command menu over a kanji message, close it: kanji intact. |

### Phase 2 — Harden (unchanged items renumbered)

| # | Task | Exit criterion |
|---|---|---|
| 2.1 | Vblank budget measurement for the job runner with the VRAM queue busy. | No top-of-frame glitches at the fastest text speed. |
| 2.2 | Outer-bank safety checklist. | In `STATUS.md`. |
| 2.3 | All messages with `<CALL>`/`<JUMP>` run from the harness. | Pass. |
| 2.4 | Fourth-line check. | Screenshot. |
| 2.5 | EverDrive N8: boot, dialogue, save, power-cycle, load. | Pass. |

### Phase 3 — Script, tables, menus (unchanged)

Proofread both `_fixed.dtx` files including compiler-split pages; move the
bank-15/13 inline menu scripts into indexed messages (these are the lines
still in kana in the intro); convert WORD/PLACE/ITEM tables and name
records; regenerate inventory and font, retouch top-60 and name glyphs.

### Phase 4 — UI screens (unchanged)

Per screen by row pitch; status-screen labels after tracing its split.

### Phase 5 — QA and release (unchanged)

Scripted render of all 872 messages; Mesen and N8 playthrough; BPS patch.

---

## 6. Risks (updated)

| Risk | Status |
|---|---|
| Hang inside the overlay (F9) | Open; gate for everything. |
| Scene graphics in the kana region (F8) | Open; design 1-3. |
| NMI re-entry (F10) | Design 6 rules; verify by trace. |
| Scan delay visible at message open | Candidates-only scan; measure. Fallback: write-tracking. |
| Scenes that draw kana outside the window | Only 金/兵 known; survey in 1.3. |
| Town context still unmeasured | Task 1.3 must reach a real town. |

---

## 7. Commands

```powershell
python decomp\build.py                       # original, byte-identical
python decomp\build.py --target kanji        # 512 KiB SUROM target + lint
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua    --name ktown
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\trace_message.lua --name kanji_message
python tools\mesen_run.py "Tenchi o Kurau (Japan) (Rev 1).nes" tools\lua\town_orig.lua --name otown
```

Outputs land in `out/test/`. Mesen runs always use a copied ROM name.

---

## 8. Revision-3 progress (2026-11-07)

Phase 1 is implemented and tested in Mesen:

- 1.1: no hang through frame 6,000 on the kanji ROM; the `$73D0` hang was
  specific to the reverted prototype.
- 1.2: bounded NMI job runner; the entry guard reads `PPUSTATUS` before CHR
  work. A 6,000-frame run shows no NMI re-entry or stack growth.
- 1.3: scene survey complete. Oath scene borrows `$42-$5B` (26 tiles);
  town/field transition borrows `$00-$17` transiently.
- 1.4: CHR scan plus `KANJI_RESIDENT`; the nametable scan additionally fills
  `KANJI_SCREEN`.
- 1.5: runtime four-tile allocation from resident, text-unused, non-visible
  tiles; duplicate-allocation bugs fixed.
- 1.6: on-demand kana restore, message-exit restore of non-visible dirty
  tiles, and rendering-off restore all installed. The name-entry grid is
  clean after the history prompt.
- 1.7: prompt messages reserve the menu kana stream and render on one page.
  Runtime save-slot names remain a known collision (see `STATUS.md`).
- 1.8: redraw re-upload hook installed; no scripted scrolling test yet.

Next: menu-aware allocation or upper-CHR allocation for runtime names, then
the script/table/UI conversion phases.
