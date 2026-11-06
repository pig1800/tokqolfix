# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Goal: a playable hack in which every dialogue line, menu, table string, and
screen label is written in normal kanji+kana Japanese instead of kana only.
Target platforms: Mesen and EverDrive N8 (original, 512 KiB PRG ceiling).

This plan builds on `HANDOFF.md` and `ANALYSIS.md`. It adds the measurements
taken on 2026-11-07 (section 1), fixes the design decisions (section 2), and
turns the phases into concrete tasks with exit criteria (section 4).

---

## 1. New measurements that shape the design

| Fact | Value | Consequence |
|---|---|---|
| Max distinct kanji on one text page (draft, 1,154 pages) | **21** | A 24-glyph per-page cache covers every page. 32 glyphs leaves margin. |
| Pages with more than 12 distinct kanji | 2 of 1,154 | Per-page cache reset is cheap; no eviction policy needed. |
| Max visible characters per page | 65 | Fits the 18×4 window; kanji take 2 cells so the compiler must check width. |
| Escape bytes `$EC $ED $EE` in real text | **unused** (0 occurrences) | Three free 2-byte escapes = 768 kanji codes. |
| Control dispatch | `text_clear_line` (`$D229`): bytes `$EF-$F7` go through a 9-entry table at `data_D2A5`; everything below `$EF` goes to `text_put_tile` | The kanji hook is one compare and three new table entries. |
| Cell buffers | `$0300,x` top tile, `$0318,x` bottom tile, 24 cells/line, lines at offsets 1/49/97/145 | A kanji is two cells: (TL,BL) then (TR,BR). `text_render_cell` needs **no change**. |
| CHR during dialogue | `$1000-$17FF` kana (128 tiles), `$1800-$1FFF` 128 tiles of portrait/leftover graphics, map hidden | Candidate cache window: `$1800-$1FFF` = 32 glyphs. Must be confirmed by nametable scan. |
| Fixed bank 15 free runs ≥128 bytes | **none** | Hook code must go into holes created by relocating bank-15 data (5,929 bytes of `incbin` blocks, incl. menu scripts at `$E94D`/`$ED50`). |
| Free runs in other banks | bank 13: 1,257 B at `$8317`; bank 12: 1,254 B; bank 9: 921 B; bank 4: 2,240 B | Small helpers can live in bank 13 without expansion. |
| SRAM references | highest static reference `$6780` of `$6000-$7FFF` | `$6800-$7FFF` is probably free for cache tables and staging. Must be audited against the save loop. |
| MMC1 CHR bank register | never written by the game | SUROM outer-bank bit must be initialised to 0 in `mmc1_init`; bank 31 must mirror bank 15 for reset safety. |
| NMI | maps bank 8 (sound) every frame via `write_prg_bank` | Outer bank 1 may only be mapped with NMI inhibited; copy glyphs to RAM, then release. |

---

## 2. Design decisions (defaults; change only with a reason)

1. **Cartridge target: MMC1 SUROM, 512 KiB PRG, 8 KiB CHR RAM, 8 KiB battery RAM.**
   Banks 16-30 hold the kanji font, relocated text, and new code. Bank 31 is a
   byte copy of bank 15. The original 256 KiB build stays byte-identical.
2. **Proper names in kanji** (劉備, 関羽, 洛陽 …). The status screen already
   shows 劉備 in 16×16, so this matches the original art direction.
3. **Full inventory stored, per-page cache resident.** Store every kanji the
   proofread script needs (budget 900 glyphs, ~28 KiB at 1bpp). Only the
   glyphs used by the current page are uploaded to CHR RAM.
4. **Glyph storage 1bpp, 32 bytes/glyph**, expanded to plane 0 at upload time
   exactly like the kana font, so kanji and kana share the same palette colour.
5. **Text encoding:** `$EC nn`, `$ED nn`, `$EE nn` = kanji code `nn`,
   `nn+256`, `nn+512`. Kana stay 1 byte. Growth ≈ 3.2 KiB for dialogue.
6. **Cache policy:** slot table resets at message start and at `<PAGE>`.
   Slots are assigned in first-use order while the line is decoded. The DTX
   compiler rejects any page with more distinct kanji than slots and any line
   wider than 18 cells. No runtime eviction.
7. **Cache window:** 32 slots in CHR `$1800-$1FFF` during dialogue, if the
   nametable scan in task 2.4 confirms those tiles are unused by the dialogue
   screens. Fallback: 24 slots in `$1A00-$1FFF` plus freeing rarely used kana.
8. **Glyph upload path:** glyph bytes are copied from the font bank into a RAM
   staging buffer inside a short NMI-inhibited critical section, then pushed
   through the existing `$0400` VRAM queue (`flush_vram_queue`) so PPU writes
   stay in vblank. One 16×16 glyph = 4 queue entries of 16 bytes.
9. **Fixed-bank rule:** never shift existing bank-15 code. Patch in place and
   put new code only in holes that are created deliberately (section 4,
   phase 2). A diff lint enforces this.
10. **Font source:** a public-domain 16×16 JIS bitmap font (Shinonome 16 or
    jiskan16) as the base for every glyph, then hand-retouch the ~60 most
    frequent kanji and all name kanji to match the existing 136-glyph style.
11. **UI labels** use the same 16×16 glyph pipeline where the screen already
    has a 16-pixel row pitch (dialogue, status labels, menus). Screens with an
    8-pixel pitch keep kana unless a layout change is cheap.
12. **Name entry stays kana input.** Players type kana; only the labels around
    the input grid become kanji.

---

## 3. Invariants and controls

- `python decomp\build.py` must keep producing the original SHA-256.
- The hack is a second target: `python decomp\build.py --target kanji`,
  writing `decomp/build/rom_kanji.nes` (524,304 bytes) with its own recorded
  hash in `decomp/targets.json`.
- `tools/bank15_lint.py` (new) compares bank 15 of the hack with the original
  and fails if any byte outside the registered patch ranges differs.
- Every phase ends with the three existing verifications plus the new
  `tools/text.py verify --target kanji` and a Mesen test-runner script.
- Mesen runs always use a copied ROM name under `out/` so the real `.sav` is
  never touched.

---

## 4. Phases and tasks

Effort is given as calendar-free "focus days". Dependencies are listed where
a task cannot start earlier.

### Phase 0 — Repository and test harness (≈2 days)

| # | Task | Files | Exit criterion |
|---|---|---|---|
| 0.1 | `git init`, commit the current tree, add `.gitignore` for `decomp/build/`, `out/*.bin`, model caches. | repo root | First commit reproduces the byte-identical build. |
| 0.2 | Add a `--target {original,kanji}` switch to `build.py`. `kanji` uses `main_kanji.asm`, a 32-bank header, and a separate expected hash. | `decomp/build.py`, `decomp/main_kanji.asm`, `decomp/targets.json` | `--target original` unchanged; `--target kanji` builds an identical 256 KiB image padded to 512 KiB and boots. |
| 0.3 | Write `tools/bank15_lint.py` with a patch-range registry. | `tools/bank15_lint.py`, `decomp/patches.json` | Lint passes on the padded build with zero patches. |
| 0.4 | Build a Mesen test-runner harness: boot, load the mid-dialogue save state, advance N pages, dump screen/CHR/nametable/OAM, exit without saving. Parameterise the ROM path. | `tools/mesen_run.py`, `tools/lua/*.lua` (consolidate the existing `dump_*.lua`) | One command produces `out/test/<name>/screen.png`, `chr.bin`, `nt.bin`. |
| 0.5 | Record baseline captures of every text-bearing screen: event dialogue, field message, battle message, command menu, main menu, speed menu, officer status, officer list, party/formation screen, item/shop windows, name entry. | `out/baseline/` | A checklist of screens with screenshot, PPUCTRL, and tile usage per pattern table. |

### Phase 1 — 512 KiB SUROM skeleton (≈3 days)

| # | Task | Files / routines | Exit criterion |
|---|---|---|---|
| 1.1 | Add banks 16-31 to `main_kanji.asm`; bank 31 `.include`s the same source as bank 15 so it is a byte copy. | `decomp/main_kanji.asm`, `decomp/banks/bank16..30.asm` (stub), header bytes `$04=$20` | Hack ROM is 524,304 bytes; bytes 0-256 KiB identical to the original. |
| 1.2 | Add `MMC1_CHR_BANK0 = $BFFF` to `hardware.inc`; write 0 to it in `mmc1_init` (5-write serialisation). | `decomp/include/hardware.inc`, `mmc1_init` (`$C468`) | Boots on Mesen with outer bank 0 from any power-on state; `bank15_lint` lists one patch. |
| 1.3 | Add `far_copy_glyph` (new, in a bank-15 hole, see phase 2) or, until the hole exists, in bank 13 `$8317`: inhibit NMI via PPUCTRL, write CHR bank 0 = `$10`, copy N bytes from a bank-16+ address to RAM, write CHR bank 0 = 0, restore PPUCTRL. | new routine | A debug message copies 64 bytes from bank 16 to `$03C0` and shows them in Mesen's memory viewer. |
| 1.4 | Audit every store of a bank number (`current_bank_a/b`, `current_prg_bank`, `set_bank_*`, inline RAM blocks, `nmi_handler`) for 0-15 assumptions. Document in `decomp/BANKS.md`. | `tools/symbols.py` notes | Written list; no code change needed if outer bank is only touched inside `far_copy_glyph`. |
| 1.5 | Hardware test: copy to EverDrive N8, boot, play into a dialogue, save, power-cycle, load. | — | Save persists; audio and NMI unaffected. |

### Phase 2 — Fixed-bank holes, RAM, and CHR window (≈3 days)

| # | Task | Details | Exit criterion |
|---|---|---|---|
| 2.1 | Identify the contents of the large bank-15 `incbin` blocks (`$E000` 881 B, `$E8CA` 822 B, `$FBC3` 694 B, `$EC00` 417 B, `$FE79` 351 B, `$DEBC` 323 B). Classify as unexecuted code, pointer tables, or menu scripts. | `decomp/main.lst`, `out/rea/`, CDL merge | Each block labelled in `tools/symbols.py`. |
| 2.2 | Free ≥512 contiguous bytes in bank 15. Preferred: move the command/speed/yes-no menu scripts (`$E94D`, `$E978`, `$E98C`, `$ED50`, `$ED60`) into the message banks as ordinary indexed messages, since they must be rewritten in kanji anyway. Second choice: move an unexecuted data table to bank 13 behind a bank-switch wrapper. | `text_print_inline` callers, `decomp/patches.json` | Hole registered; original build still byte-identical (holes exist only in the kanji target). |
| 2.3 | RAM audit: confirm `$03C0-$03DF` usage (7 references) and SRAM `$6800-$7FFF` against the save-slot loop. Reserve: 64-byte glyph staging buffer, 32-byte slot table (kanji code per slot, 2 bytes each = 64 B), slot counter, current page flag. | `decomp/include/ram.inc` | Reserved ranges documented and never written by original code during a 10-minute Mesen run with a write watchpoint. |
| 2.4 | Nametable scan: on each dialogue-type screen from 0.5, list every tile index in `$1800-$1FFF` that the nametable or OAM references while a message is open. | Lua script over baseline states | Confirms slot count (32 or 24) and which tiles must be preserved. |

### Phase 3 — Font asset pipeline (≈4 days, parallel with phase 2)

| # | Task | Files | Exit criterion |
|---|---|---|---|
| 3.1 | Freeze the kanji inventory: union of the proofread dialogue draft, converted WORD/PLACE/ITEM tables, menu labels, status/battle labels, and all officer names. Order by frequency; names first within equal counts. | `tools/kanji_inventory.py` → `assets/fonts/kanji_index.tsv` (code, char, count) | Stable code assignment; ≤768 entries, with codes 0-255 holding the most frequent so most text uses `$EC`. |
| 3.2 | Import a public-domain 16×16 font (Shinonome 16 / jiskan16 BDF) and render every inventory glyph to `assets/fonts/kanji_16x16_ext.png` (16 per row, same layout as the existing sheets). | `tools/font_import.py` | Sheet round-trips through `assets.py`; visual contact sheet in `out/font_ext.png`. |
| 3.3 | Identify the 136 existing glyphs (`kanji_16x16_bank01/02.png`) and the two status-name glyphs; map them to Unicode in `kanji_index.tsv` so their art is reused where it matches. | `assets/fonts/kanji_existing_map.tsv` | Every one of the 136 has a Unicode identity or an "unused/unknown" mark. |
| 3.4 | Retouch pass: hand-fix the top-60 kanji and all name kanji in the PNG to match stroke weight of the original 劉備 glyphs. | PNG sheet | Side-by-side sheet reviewed; no glyph touches the 16×16 border on the right/bottom edge (cell gap matches kana). |
| 3.5 | Add `font1_16` kind to `assets.py`: PNG → 32 bytes/glyph 1bpp, emitted as `build/assets/kanji_font.bin` and included in bank 16+ with a per-bank glyph table (`kanji_bank_lo/hi`). | `tools/assets.py`, `assets/manifest.json`, `decomp/banks/bank16.asm` | 900 glyphs = 28.8 KiB in banks 16-17; verify round-trip. |

### Phase 4 — Dialogue kanji renderer and prototype (≈5 days; needs 1.3, 2.2, 2.3, 3.5)

| # | Task | Routine / change | Exit criterion |
|---|---|---|---|
| 4.1 | Patch `text_clear_line`: change `cmp #$EF / bcc` to `cmp #$EC / bcc`, and replace the inline 9-entry dispatch with a `jmp` to a new 12-entry dispatcher in the bank-15 hole (entries for `$EC $ED $EE` + the original nine). | `$D28E-$D2B6`, new `text_dispatch_ext` | `bank15_lint` shows exactly the registered patch. Original messages render unchanged. |
| 4.2 | `kanji_handler`: read index byte, form 10-bit code, look up the slot table; if absent, allocate the next slot, call `far_copy_glyph` for 32 bytes, expand 1bpp → four 16-byte tiles in the staging buffer, enqueue four VRAM entries at `$1800 + slot*64`; then write (TL,BL) and (TR,BR) into `$0300/$0318` and advance X by 2. Wait for queue space with `update_frame` when the queue is nearly full. | new code in bank-15 hole and bank 13/16 | A test message `<K:劉><K:備>は　たたかった` renders in Mesen with correct tiles and no corruption on the next page. |
| 4.3 | Reset the slot table on message open (`text_show_message`, after `set_bank_b`) and at `<PAGE>` (`$FC` path in `text_show_message`/`text_scroll_up`). | small patches | Two consecutive pages each with 20 distinct kanji render correctly. |
| 4.4 | Line-wrap and width: the decoder must not place a kanji in column 18 (would split). Decide: compiler guarantees it (default) and the handler only asserts. | `tools/text.py` lint | Compiler error on any overflowing line in the converted script. |
| 4.5 | Fourth-line check: confirm whether top tiles on line 4 (`$0300+145`) are drawn on the border row. If so, adopt the fix: shift the window down one row for dialogue (`draw_text_window`, `$DD67`) or reserve kanji to lines 1-3. | measurement, then one patch | Screenshot of a 4-line page with kanji on every line. |
| 4.6 | Typewriter timing: measure cycles for one glyph upload; keep the per-cell delay path (`text_render_cell`) unchanged. | Mesen profiler | No visible stall; audio unaffected. |

### Phase 5 — Text banks and compiler (≈4 days; needs 4.x)

| # | Task | Files | Exit criterion |
|---|---|---|---|
| 5.1 | Extend the DTX codec: kanji characters compile to `$EC/$ED/$EE nn` via `kanji_index.tsv`; export decodes them back. Keep the original target compiling the kana files. | `tools/textdata.py`, `tools/text.py` | `text.py verify --target kanji` round-trips a test file. |
| 5.2 | Add lint rules: ≤18 cells per line counting kanji as 2, ≤ slot count distinct kanji per page, no kanji split across lines, all kanji present in the inventory. | `tools/text.py lint` | Lint runs in `build.py --target kanji`. |
| 5.3 | Relocate text: keep the index scheme (`<$200` → bank A, `≥$200` → bank B) but point the engine's bank numbers at new banks 18/19 (`text_window_x` set in `text_show_message`; also `text_clear_line` `$D285` re-map and the `$F8` call path). Banks 10/11 keep original bytes for the original target and become free in the kanji target. | patches to `text_show_message`, `text_clear_line` | Original index values unchanged; all 872 table entries resolve. |
| 5.4 | Move the WORD/PLACE/ITEM tables into editable DTX-style resources with kanji support (`bank 13 $B700/$B800/$B900`, `bank 12 $A100/$A140`, `$A3C8/$A438`). Relocate them to bank 20 if they grow. | `tools/tables.py` (new) | Tables round-trip for the original target; kanji versions compile for the hack. |
| 5.5 | Runtime names: officer name strings printed by `<NAME_F3>`-`<NAME_F7>` and `<NAME:xx>` come from bank 12 records (`load_party_member_stats`, `$D4A0`). Convert those records to the kanji encoding; the handler already goes through `text_put_tile`, so route it through the extended dispatcher. | bank 12 data, small patch | Party names show in kanji in dialogue and headers. |

### Phase 6 — Script conversion and proofreading (≈8-10 days; can start after 3.1, independent of code)

| # | Task | Exit criterion |
|---|---|---|
| 6.1 | Proofread `bank10/11_messages_kanji_fixed.dtx` against the kana original, message by message. Fix model errors (archaic lines around `b10_msg_126`, divination `b11_msg_031`, verbs, homophones). Keep a decisions list for orthography (okurigana, 之/の, 様/さま). | Two reviewers or two passes; every record marked reviewed. |
| 6.2 | Apply the width and page lints; re-break lines where kanji made them narrower or wider; re-page where needed. | Lint clean. |
| 6.3 | Convert the dictionary, place, item tables, and officer names (fix known errors like 七星等 → 七星剣). | Table review sheet complete. |
| 6.4 | Regenerate the inventory (3.1) from the final script and rebuild the font; verify no missing glyphs. | `kanji_index.tsv` frozen, version-tagged. |

### Phase 7 — UI screens (≈5 days; needs phase 4)

| Screen | Where the strings live | Approach |
|---|---|---|
| Command menu, yes/no, formation/strategist, speed | bank 15 inline scripts (moved in 2.2) | Now ordinary messages; kanji via the same renderer. Check the small window (`draw_text_window_small`, `$C51A`) has 16-px pitch. |
| Main menu (4 strings, bank 13 `$90E9`) | bank 13 | Convert to indexed messages or patch the bank 13 printer to call the extended dispatcher; bank 13 has 1,257 free bytes. |
| Officer status labels (ぶりょく/ちりょく/こうげき/そうび/へいしすう/さくりゃく) | bank 13/14 status drawers (`b14_officer_status_screen` `$B791`, `b13_officer_status_draw` `$929C`) | Rows already sit on a 16-px pitch; replace each 4-kana label with a 2-kanji block using a status-screen CHR slot area. Requires the status-screen pattern-table split to be traced first (open item). |
| Battle messages and headers (`draw_party_header` `$F662`, `b14_draw_battle_status` `$BF66`) | bank 14/15 | Route through the dialogue renderer where they use `text_put_tile`; otherwise keep kana and list as exceptions. |
| Officer list, party/formation, item and shop windows | banks 7/14 | Same rule: 16-px pitch → kanji, 8-px pitch → keep kana. |
| Name entry | bank 13 | Labels only. |
| Title screen | graphics | Unchanged. |

Exit criterion: the screen checklist from 0.5 is re-captured and every screen is marked "kanji", "kana by design", or "exception with reason".

### Phase 8 — Full QA and release (≈4 days)

| # | Task | Exit criterion |
|---|---|---|
| 8.1 | Scripted Mesen run that opens every message index (0-871) through a debug hook and screenshots each page; diff against expected text rendered by a Python reference renderer. | Zero mismatches, zero lint errors. |
| 8.2 | Manual playthrough on Mesen, then on EverDrive N8, with saves made and reloaded in each chapter. | No crash, no CHR corruption, saves compatible with the original save file. |
| 8.3 | Stress: longest pages, 21-kanji page, page turns during music, dialogue during battle transitions. | Pass. |
| 8.4 | Record the final hash in `targets.json`, write `RELEASE.md` (what changed, known kana exceptions), produce an IPS/BPS patch from the original ROM. | Patch applies cleanly to the original and yields the recorded hash. |

---

## 5. Order and critical path

```
0.1-0.5 ──► 1.1-1.5 ──► 2.1-2.4 ──► 4.1-4.6 ──► 5.1-5.5 ──► 7 ──► 8
                  └──► 3.1-3.5 ─────────┘           ▲
                                   6.1-6.4 ─────────┘
```

- Phases 3 and 6 are content work and run in parallel with the code phases.
- The first visible milestone is the end of phase 4: one real message page
  rendered with kanji on the expanded ROM. Aim for that before investing in
  the full proofread.
- Total focus effort: roughly 35-40 days, of which 8-10 are proofreading.

---

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| No usable hole in bank 15 | Task 2.2 has two independent strategies; worst case, the kanji handler runs as a RAM-resident block via `call_inline_block` (`$C4E4`), which the game already uses for cross-bank code. |
| `$1800-$1FFF` is partly used during dialogue | Task 2.4 measures it; 24 slots still covers every page in the draft. |
| Outer-bank switch during NMI | Only `far_copy_glyph` touches the outer bit, with NMI inhibited, and bank 31 mirrors bank 15 as a second safety net. |
| Absolute addresses embedded in data (pointer tables, `<CALL:xxxx>` tokens) | Fixed-bank rule 9 plus `bank15_lint`; never shift code. |
| Save-file damage during testing | Harness always runs a copied ROM name; `D:\EMU\NES\Saves` backed up before phase 0. |
| Font style clash | Phase 3.4 retouch; keep the original 136 glyphs where they match. |
| Script quality | Phase 6 is a real proofread, not a model pass; orthography decisions logged. |
| N8 original limit | 512 KiB is the hard ceiling; the plan uses under 300 KiB of new space. |

---

## 7. Decisions still open (defaults in effect)

1. N8 original vs N8 Pro: **default original (512 KiB)**.
2. Slot count 32 vs 24: **decided by task 2.4**.
3. Font base: **Shinonome 16** unless jiskan16 matches the original style better after a contact-sheet comparison.
4. Status-screen labels in kanji: **yes, if the pattern-table split traced in phase 7 allows a stable 16-tile slot area**; otherwise kana by design.
5. Line 4 handling: **decided by task 4.5**.
