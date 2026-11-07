# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 2, 2026-11-07, after the first implementation pass (commit
`26999aa`). Revision 1 is in git history. Sections 1-3 record what the pass
delivered and what the review found; section 4 is the revised design;
section 5 is the ordered work list. Later phases (script, UI, QA) are
unchanged in substance and kept at the end.

Goal and platforms are unchanged: every dialogue line, menu, table string
and screen label in kanji+kana; Mesen and the original EverDrive N8
(512 KiB PRG ceiling).

---

## 1. What the implementation pass delivered

Verified by reading the sources and rebuilding:

- `python decomp\build.py` still yields the original SHA-256.
- `python decomp\build.py --target kanji` yields a 524,304-byte SUROM ROM
  (mapper 1, submapper 1) that boots to the title and main menu in Mesen.
- SUROM outer-bank switch: `write_prg_bank` at `$C4B7` jumps to a 41-byte
  5-bit switcher at `$C611` (inside a 102-byte gap) in both bank 15 and 31.
- Font pipeline: 718-glyph inventory, DotGothic16 rendered to 1bpp 32-byte
  glyphs in banks 16-17, `assets/fonts/kanji_index.tsv`, contact sheet.
- Text compiler `tools/kanji_text.py`: reflow to 18 cells, page split, 2-byte
  kanji codes `$EC/$ED/$EE nn`, converted streams in banks 18-19, per-page
  slot records in banks 22-23, 8-byte trampolines in banks 10/11.
- Far loader (bank 13 `$8317`, runs from `$0600`): copies the kana font and
  the page records to SRAM, switches to the text bank with outer bit 1.
- Fixed-bank overlay (bank 31 `$E000`): extended dispatcher, kanji handler,
  glyph expand, NMI CHR upload, lazy kana restore, control-store hook.
- Harness: `tools/mesen_run.py`, `tools/lua/boot_check.lua`,
  `tools/bank15_lint.py` (bank 15 only).

Not yet achieved: a screenshot of a real message page with kanji. The three
`out/dialogue/kanji_screen*.png` captures show an empty window; rendering
was verified only through traces and buffer dumps.

---

## 2. Review findings (ordered by severity)

### F1. The bank-31 overlay destroys live code — must fix

`tools/kanji_build.py` writes the 472-byte overlay over bank 31 `$E000-$E1D7`
on the assumption that the `$E000` block (881 bytes) is unused data. It is
unexecuted **code** that the CDL runs never reached. Evidence:

- The block disassembles cleanly (`rts / ldy $F1 / cpy #8 / bcs …`).
- Bank 14 calls into it 15 times: `jsr $E200` (x5), `jsr $E300` (x6),
  `jsr $E323` (x3), `jsr $E369` (x2), `jsr $E28D`; bank 15 jumps into it from
  `$DF40` and `$DF58`.

The overlay covers `$E000-$E1D7`; `$E200+` survives, but anything in
`$E000-$E1D7` that is reached while the outer bit is 1 (any time a message is
open) executes garbage. The lint does not check bank 31, so this was invisible.

### F2. Every message now clobbers the caller's bank — must fix

The trampoline is `F8 17 03 …`. In `text_clear_line` a `$F8` call with a high
byte below `$80` runs `lda #$0D / jsr set_bank_a`, which overwrites
`current_bank_a` with 13. At `<END>` the engine does `jmp set_bank_current`
and maps bank 13. Five message callers live in bank 14; they return into
bank 13 bytes. The original only used this path for name-print helpers that
are called from bank 13 contexts. The boot test cannot see this; a field or
menu message will.

Fix (8 bytes, in the `$C611` gap): trampoline target `F8 3A C6`, and at
`$C63A`: `lda #$0D / jsr set_bank_b / jmp $8317`. A high byte `≥ $80` takes
the `set_bank_current` path, which leaves `current_bank_a` alone, and
`set_bank_b` only touches `current_bank_b`/`current_prg_bank`.

### F3. The CHR blocker — the strategy is right, the restore is incomplete

Kanji quadrants are written into kana-font tiles the page does not use. After
the message, window/menu code sees kanji fragments. The executor proposed
switching to the `$1800-$1FFF` window from plan revision 1. **That window
does not exist in practice.** Measured today with the harness:

| Screen | Tiles `$80-$FF` referenced by the nametable |
|---|---:|
| Oath scene (3 portraits, save state `_11.mss`) | 128 of 128 |
| Town message over the map (`out/test/town_1720`) | 128 of 128 |
| Intro scene captured at frame 1240 | 1 (`$EB`) |

Portraits in event scenes are BG, and map chips fill the upper half in town.
Borrowing unused kana tiles is the only context-independent option, so the
current design stays. What is missing is the restore discipline:

1. Restore every dirty tile at message exit (`$D1F9 jmp set_bank_current`
   is the hook) and keep the lazy per-tile restore for page 2 reuse.
2. Enlarge the reserved set so nothing drawn *while* the message is open can
   collide: frame/cursor/space/digits (already), the yes/no, formation and
   command-menu kana, and every tile that any runtime name insertion
   (`<NAME_F3>`–`<NAME_F7>`, `<NAME:xx>`, bank 13 name helpers) can produce.
3. Treat the first byte of `KANJI_KANA_READY` as a signature word, not a
   non-zero flag: a fresh cartridge has random SRAM.

### F4. `kana_prepare`/dirty tracking must survive font reloads

When the game reloads the 1bpp font from bank 9 (`load_text_graphics` and
screen loaders), the dirty bitmap is stale. Clearing it there is optional
(restoring kana over kana is harmless), but if the kanji target ever changes
the resident font layout the bitmap must be reset. Note only.

### F5. NMI vblank budget — measure

`chr_upload` writes 64 bytes via PPUDATA at NMI entry, before OAM DMA, the
VRAM queue flush and the palette. Worst case is a frame with a glyph upload,
a full queue flush and a palette update. Needs a cycle measurement in Mesen;
if it overflows vblank, upload at most two tiles per frame.

### F6. Tests exist only for boot

`boot_check.lua` cannot reach the text engine. The save state
`D:\EMU\NES\SaveStates\Tenchi o Kurau (Japan) (Rev 1)_11.mss` loads the
oath scene; `tools/lua/state_ppu_dump.lua` (added today) loads it and dumps
PPU memory, zero page and screenshots. `tools/lua/town_ppu_dump.lua` replays
the title → new game → town input sequence and dumps at a town message.
Both work against the original ROM; the kanji ROM needs the same runs.

### F7. Lint gap

`bank15_lint.py` checks bank 15 only. Bank 31 must be checked too: it must
equal bank 15 except for registered sites. With the fix in section 4 the two
banks become identical, which makes the lint trivial.

---

## 3. Measurements that changed decisions

| Measurement | Result | Decision |
|---|---|---|
| Upper 128 BG tiles during event scenes and town messages | fully used | No fixed kanji window; borrow unused kana tiles per page (executor's design) |
| `$E000` block in bank 15 | live code called from bank 14 | Overlay cannot live there; relocate (section 4) |
| Free bytes in `$C611` gap after the switcher | 61 | Enough for the trampoline stub and two guarded NMI hooks, not for the overlay |
| Converted text size | fits banks 18-19 | Keep two data banks; trampolines are not needed for capacity |
| Max distinct kanji per page after compiler split | 11 | Borrow-tile capacity is sufficient; page splits need proofreading |

---

## 4. Revised design

Changes against revision 1 and against the current implementation are marked.

1. **SUROM 512 KiB, bank 31 mirrors bank 15** — unchanged. *Changed:* bank 31
   must be byte-identical to patched bank 15. All text-engine patches are
   applied to both banks, so the engine works from either half (this also
   covers `<CALL>` helpers that drop the outer bit mid-message).
2. **Overlay location** — *changed.* The overlay code moves out of bank 31
   into battery RAM at `$7000-$73FF` (code executes from PRG RAM on MMC1 and
   on the N8). It is installed by the far loader on the first message after
   power-on and re-installed whenever a 2-byte signature at `$7000` is wrong.
   Fixed-bank hooks that can fire before installation (the two NMI hooks) go
   through 12-byte guard stubs in the `$C611` gap that test the signature
   first. Alternative if PRG-RAM execution is rejected: free ≥512 bytes in
   bank 15 by relocating a proven-dead block; nothing proven dead is known.
3. **Trampolines and far loader** — kept (they carry the page-record pointer
   cleanly). *Changed:* trampoline target becomes the fixed-bank stub at
   `$C63A` (F2). *Optional later simplification:* retarget
   `text_show_message`'s `lda #$0A` to `#$12` so banks 18/19 hold the tables
   directly and the per-message 255-byte RAM copy disappears; page records
   would then need a third pointer table. Not required for correctness.
4. **CHR strategy** — borrow unused kana tiles per page, restore at page
   reuse and at message exit, reserved set enlarged (F3). The `$1800-$1FFF`
   window idea from revision 1 is withdrawn.
5. **Encoding, font, cache policy, invariants** — unchanged
   (`$EC/$ED/$EE nn`, 1bpp 32-byte glyphs, compiler-enforced limits,
   byte-identical original target).
6. **SRAM map** (to be confirmed by the save-slot audit, task 1.6):
   `$6800-$68FF` scratch, `$6A00-$6DFF` kana font copy, `$6E00-$75FF` page
   records, `$7000-$73FF` overlay. *The page-record copy and the overlay
   overlap today; move records to `$7400-$7BFF` or cap them.*

---

## 5. Work list for the next pass (ordered)

Each item has an exit criterion. Items 1.1-1.4 are blocking; nothing else
should be started until a message page with kanji is on screen.

### Phase 1 — Unblock rendering

| # | Task | Exit criterion |
|---|---|---|
| 1.1 | Move the overlay to PRG RAM: assemble `kanji_fixed.asm` at `$7000` with a signature word; far loader installs it when the signature is missing; NMI hooks become signature-guarded stubs in the `$C611` gap; remove the `$E000` overwrite from `kanji_build.py`. | `bank31.bin == bank15.bin` byte for byte; lint extended to assert it; kanji ROM boots and plays through the title. |
| 1.2 | Fix the caller-bank clobber: trampoline `F8 3A C6`, stub at `$C63A`. Register the gap layout (`$C611` switcher, `$C63A` stub, `$C642+` NMI guards) in `bank15_lint.py`. | A bank-14 caller (field `はなす` or search message) returns cleanly in Mesen. |
| 1.3 | Restore-at-exit: hook `$D1F9` to a routine that restores every dirty tile from the SRAM kana copy before `set_bank_current`. Keep `kana_prepare`. | Open a message with kanji, close it, open the command menu and yes/no: no fragments. Automated: compare the kana region of CHR before and after the message. |
| 1.4 | Reserved-tile set: compute in `kanji_text.py` the union of frame/cursor/digits, menu-script kana, and all tiles reachable from runtime name insertions; fail compilation if any page cannot fit its kanji after reservation, splitting pages as today. | `kanji_text_report.json` lists reserved count and max slots; no page over capacity. |
| 1.5 | First screenshot milestone: run `state_ppu_dump.lua` and `town_ppu_dump.lua` against `rom_kanji.nes`; commit the PNGs under `out/test/` and reference them in `STATUS.md`. | Two screenshots with legible kanji, one event scene and one town message. |
| 1.6 | SRAM audit: trace the save/copy/delete code paths (`b13_*`, name entry) with a write watchpoint on `$6800-$7FFF` across new game, save, copy, delete, load. Fix the overlap between page records and overlay (section 4.6). | Written map in `kanji.inc`; watchpoint silent. |
| 1.7 | `KANJI_KANA_READY` and the overlay use signatures; a power-on with random SRAM (Mesen "random RAM" option) still renders. | Pass with randomised RAM. |

### Phase 2 — Harden

| # | Task | Exit criterion |
|---|---|---|
| 2.1 | NMI budget: measure the worst frame (glyph upload + queue flush + palette) with Mesen's event viewer; if it exceeds vblank, upload two tiles per frame. | No top-of-frame glitches in a 20-kanji page at the fastest text speed. |
| 2.2 | Outer-bank safety review: list every fixed-bank path that can run with the outer bit set (text loop, `update_frame`, `wait_frames`, sound queue, `set_bank_*`, NMI entry/exit) and confirm they only touch bank 15/31-identical bytes and 5-bit bank numbers. | Checklist in `STATUS.md`. |
| 2.3 | Bank-14 `<CALL>` helpers and `<JUMP>` scripts during a message: run every message that contains `<CALL>`/`<JUMP>` from the harness and check return. | All 30 such records pass. |
| 2.4 | Fourth-line check: a page with kanji on line 4; confirm the border row. | Screenshot; fix in `draw_text_window` if needed. |
| 2.5 | Hardware: EverDrive N8 boot, dialogue, save, power-cycle, load. | Pass. |

### Phase 3 — Script, tables, menus (unchanged from revision 1, re-ordered)

| # | Task |
|---|---|
| 3.1 | Proofread both `_fixed.dtx` files message by message, including the four compiler-split pages; log orthography decisions. |
| 3.2 | Move the bank-15 inline menu scripts (`$E94D`, `$E978`, `$E98C`, `$ED50`, `$ED60`) and the bank-13 main-menu strings into indexed messages so they get kanji and page records; this also frees ~90 bytes in bank 15. |
| 3.3 | Convert WORD/PLACE/ITEM tables and officer-name records to the kanji encoding via a `tools/tables.py` resource; route `draw_item_name`/`load_party_member_stats` through the extended dispatcher. Names drawn by those paths must use reserved tiles or be rendered through the page allocator. |
| 3.4 | Regenerate the inventory from the final script and tables; rebuild the font; retouch the top-60 and name glyphs against the original 劉備 style. |

### Phase 4 — UI screens (unchanged from revision 1)

Per screen, by row pitch: officer status labels, battle headers/messages,
officer list, party/formation, item and shop windows, name-entry labels.
Status-screen labels depend on tracing its pattern-table split first.

### Phase 5 — QA and release (unchanged)

Scripted render of all 872 messages with screenshot diff; Mesen and N8
playthrough with saves; stress pages; record hash; produce a BPS patch.

---

## 6. Risks (updated)

| Risk | Status |
|---|---|
| Overlay over live code (F1) | Open; blocks everything. |
| Caller-bank clobber (F2) | Open; 8-byte fix. |
| Kanji fragments in UI (F3) | Open; restore-at-exit + reserved set. |
| SRAM corruption on fresh cart | Mitigate with signatures (1.7). |
| NMI overrun | Measure (2.1). |
| Page-record/overlay SRAM overlap | Fix in 1.6. |
| Font style mismatch | Phase 3.4. |

---

## 7. Commands

```powershell
python decomp\build.py                       # original, byte-identical
python decomp\build.py --target kanji        # 512 KiB SUROM target
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\state_ppu_dump.lua --name kanji_state
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_ppu_dump.lua  --name kanji_town
python tools\bank15_lint.py --rom decomp\build\rom_kanji.nes
```

Outputs land in `out/test/` (`state_*.png`, `*_ppu.bin`, `*_zp.bin`). Mesen
runs always use a copied ROM name so the real battery save is untouched.

---

## 8. Progress after revision 2 (2026-11-07)

| Task | Status |
|---|---|
| 1.1 RAM overlay, bank 31 == bank 15, guarded NMI hooks | done; lint enforces equality |
| 1.2 caller-bank fix (`F8 3A C6`, `$C63A` stub) | done |
| 1.3 restore-at-exit | **open**; `$D1FA` hook is disabled because restoring erased a still-visible prompt. Map tiles also need their original CHR, not kana. |
| 1.4 reserved-tile set | done for static/table/name insertions; report records reserved counts |
| 1.5 first kanji screenshot | done: `out/test/kanji_prompt_640.png`, `kanji_prompt_900.png` |
| 1.6 SRAM audit | static map in `kanji.inc`; 6000-frame write watchpoint silent outside the RAM loader/overlay |
| 1.7 signatures / random RAM | done: deterministic random `$6800-$7FFF` boots and renders |
| 2.x hardening | not started |
| 3.x script/tables/menus | not started |

Next blocking work: lazy CHR save/restore for overwritten tiles (including map
tiles), re-upload on visible-line redraws, then the remaining phase-3 script
and table conversion.

