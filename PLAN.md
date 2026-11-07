# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 6, 2026-11-07, after the revision-5 attempt (commit `1a9abec`).
This revision is a pivot. The evidence in section 1 shows the RAM-resident
runtime cannot ship, so section 2 defines a ROM-resident design that needs
about 100 bytes of internal RAM and no NMI code, and section 3 is the work
list to get there. Earlier revisions are in git history; the renderer, SUROM
expansion, trampolines, font and compiler are kept.

Goal and platforms unchanged: every dialogue line, menu, table string and
screen label in kanji+kana; Mesen and the original EverDrive N8.

---

## 0. Revision-6 execution results (2026-11-07)

Phase 1 is implemented. The runtime is now ROM-resident and uses no battery
RAM, no NMI hooks and no CHR/nametable scans.

| Task | Result |
|---|---|
| 1.1 no battery-RAM use | `tools/lua/sram_watch.lua`: 0 hack writes out of 21,923 SRAM writes over the 6,000-frame run. Bank 13 is byte-identical to the original. |
| 1.2 overlay in text banks | 1,042-byte overlay at `$B800`, identical in banks 18-22; bank 15 gap block is 94 bytes; 7 patch ranges; bank 31 mirrors bank 15. |
| 1.3 state and RAM stub | State at `$0131-$013F`, RAM stub at `$0140-$015F`, glyph half-buffer at `$0160-$016F`, dirty bitmap at `$0170-$017F`, scratch at `$01E0-$01E7`. `tools/lua/iram_watch.lua`: 0 foreign writes to the reserved ranges. |
| 1.4 queue upload/restore | Glyphs are written through the game's `$0400` VRAM queue; one-page dirty bitmap restores kana at exit and before page reuse. `tools/lua/mask_restore.lua`: **0** visible-scanline PPUMASK restores. |
| 1.5 static assignment | Compiler assigns four CHR tiles per kanji from the page's free kana set; page records carry the tile numbers; max 11 entries/page; `min_free_static = 4`; `pages_over_capacity = 0`. |
| 1.6 survey / tags | `scene_borrow.tsv` contains 9 surveyed labels (oath scene = `$42-$5B`, most field/menu messages = none); compiler consumes it and falls back to the 26-tile worst case. Prompt list tags: 63 `menu`, 7 `savename`. |
| 1.7 stack | Minimum SP at NMI entry `$18`, at overlay entry `$28`; both keep the stack below the state at `$0131` (`SP=$31`). |

Verified screenshots on the final build: history prompt (`pp_0900`), history
register prompt (`pp_0900` from `prompt_pages`), name-entry grid (`pp_1600`)
and the field message `b10_msg_129` all render kanji+kana with intact map and
menu tiles. The 6,000-frame survey completes without a hang. The map palette
in the survey differs from the original run because the palette animation is
at a different phase; the nametable and map tile numbers are identical.

Current hashes: original `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
kanji `b1e33ab17ad4b41d4a1c6c34386aec0679b36eed3f7df149f2a71857b447bb4c`.
Remaining work is the Phase 2 QA sweep, per-prompt field-list tags beyond the
current heuristic, and the hardware/N8 pass.

---

## 1. Why the current runtime cannot ship

### 1.1 Battery RAM belongs entirely to the game

The executor found a 2 KiB save copy landing at `$6800`. Tracing the copy
pointer at boot (`tools/lua/slot_ptr_watch2.lua`, original ROM, frames
302-303) shows the game validating three save slots:

| Pointer at slot check | Slot |
|---|---|
| `$6800` | history book 1 |
| `$7000` | history book 2 |
| `$7800` | history book 3 |

The live game state is `$6000-$67FF` (cleared by `fill_ram_block` on a new
game, summed into a checksum at `+6/+7`, signature `5S` at `+8/+9`). The
whole 8 KiB is used. Consequences:

- The RAM overlay at `$7002-$7BA6` sits inside books 2 and 3. Installing it
  destroys a player's saved games there, and registering a book in slot 2
  or 3 overwrites the overlay, whose reinstall then corrupts that slot.
- Every test so far registered slot 1 and never touched slots 2-3, which
  is why nothing was observed.
- No hack state can live in battery RAM. Not scratch, not the kana copy,
  not page records, not the overlay, not the `$7C00` save area.

### 1.2 Internal RAM is nearly full

`tools/lua/iram_audit.lua` over the 6,000-frame run on the original
(title, prompts, name entry, oath scene, field with movement) records every
address read or written in the candidate ranges:

| Range | Untouched bytes |
|---|---|
| `$0100-$01FF` | `$0131-$017F` (79), `$01E0-$01EB` (12), `$010B-$0112` (8), `$0100-$0103` (4) |
| `$03C0-$03FF` | none |
| `$0700-$07FF` | none |

`$0500-$05FF` is per-actor state and `$0600-$06FF` the inline-code buffer
(the disassembly annotates both; the executor's relocation corrupted pages
because of this). `$0180-$01DF` is the text engine's saved-tile buffer, so
the stack is confined to `$01EC-$01FF`, about 20 bytes. `$0131-$017F` is
safe only because the stack cannot reach it without first destroying that
buffer, which the game never does.

Budget for the hack: **79 + 12 bytes of internal RAM, zero battery RAM,
and a stack that tolerates at most a few extra nested calls.**

### 1.3 The scans cannot be made invisible

Even at reduced batches the PPUMASK restore landed on visible scanlines,
and the reduced build broke scene progression. With no RAM for an NMI job
runner the question is moot: the new design performs no PPU reads at all.

---

## 2. ROM-resident design

Everything that was dynamic becomes static knowledge in the ROM, checked by
tooling instead of discovered at runtime.

### 2.1 Where code lives

- **Overlay in the text banks.** The runtime (dispatcher, kanji handler,
  control store, exit restore, page-reuse restore) is assembled once at a
  fixed address ($B800-$BFFF) and included identically in every text bank
  (18-22). It is only ever called while a text bank is mapped, which is true
  at every hooked site inside the text engine.
- **Far-copy stub in internal RAM `$0140-$017F`** (64 bytes), installed
  by the trampoline stub at each message open (copy from the text bank;
  cheap). It switches to a font bank, copies and expands one 32-byte glyph
  straight into VRAM-queue entries, and switches back to the text bank.
  The same stub copies 8-byte kana rows from bank 9 for restores.
- **State in `$0131-$013F` and `$01E0-$01EB`:** page-record pointer,
  text bank, uploaded flags (one bit per page entry, ≤16 entries), two or
  three temporaries. Nothing else.
- **Fixed-bank gap `$C611-$C676`:** SUROM switcher (41 bytes), trampoline
  stub (parses `F8 3A C6 bank addr meta`, installs the RAM stub, sets
  `text_window_x`, maps the bank, jumps to the line loop; ~35 bytes), and a
  redraw stub that re-maps the text bank before calling the overlay. The
  NMI guards, signature check and `cell_check` are removed.
- **No `$0600` far loader, no NMI hooks, no signatures.**

### 2.2 Where tiles come from

- **Compiler-assigned tiles.** Each page record in the text bank lists
  `(code_lo, code_hi, tile0..tile3)`; the runtime never allocates. The
  compiler chooses from the 128 kana tiles minus: permanent reserved set,
  the page's own kana (including table and name insertions), the
  **scene borrow set** for that message, and the **list set** for prompt
  messages. Capacity failures are compiler errors.
- **Scene borrow tags.** The survey showed scenes overwrite kana tiles
  (`$42-$5B` in the oath scene). A scripted playthrough dumps CHR at every
  message open and emits, per message label, the set of kana tiles that do
  not hold their glyph. This file (`decomp/text/kanji_plan/scene_borrow.tsv`)
  is compiler input. Messages not reached by the survey get the worst-case
  26-tile allowance as today.
- **List tags.** Prompts are tagged with the list drawn after them
  (`party`, `item`, `officer`, `menu`, `savename`, `none`), from their
  callers in banks 13/14/15. `savename` reserves the name-entry charset,
  which is hiragana plus a few symbols, so the katakana block is free for
  the two history prompts. This replaces the upper pool and the nametable
  scan.
- **Uploads through the game's VRAM queue** (`$0400`), the same path the
  text engine uses for cells, flushed by the unmodified NMI handler within
  the game's own budget. One kanji is four 16-byte entries (77 bytes); the
  handler waits for queue space with `update_frame` as `text_render_cell`
  does. No new PPU writes happen outside the game's flush.
- **Restore at exit:** every tile listed in the message's page records
  that is not referenced by the `$0180`/`$0300` buffers is rewritten from
  the bank-9 font through the queue. Page-2 reuse keeps the single
  `kana_prepare` site inside the text engine (`$D2BB`); the other seven
  `kana_prepare` sites and the bank-13 post-assembly patches are removed,
  because reservation tags make them unnecessary and they run with the
  wrong bank mapped for a text-bank overlay.
- **Rendering-off rule:** if the PPUMASK shadow shows rendering off at a
  page boundary or at exit, skip the restore (the game is reloading CHR).

### 2.3 Patch inventory after the pivot

| Site | Purpose | Target |
|---|---|---|
| `$C4B7` | SUROM switcher jump | gap |
| `$C611-$C675` | switcher, F8 trampoline, cell check | gap |
| `$D28E` | extended dispatcher | overlay |
| `$D2BB` | page-reuse restore | overlay |
| `$D2C7` | control store (page advance) | overlay |
| `$D1FA` | exit restore | overlay |
| `$DBE7-$DBEA` | cell-buffer tile test | gap (`cell_check`) |

Seven ranges instead of seventeen; bank 31 stays a mirror; no bank-13
patches, no NMI patches and no redraw patch (the original redraw is correct
because glyphs are never restored while a message is open).

### 2.4 What this gives up

- Runtime adaptation to scenes the survey did not reach. Replaced by the
  worst-case allowance plus the QA render of all 872 messages, which asserts
  in Lua that no assigned tile is referenced by the nametable outside the
  window and that every kana tile the page uses still holds its glyph.
- The upper-tile pool. Not needed once `savename` reservation exists.
- Any hope of kanji in dense field lists (party/item names). Decision from
  revision 5 stands: kana inside field lists, kanji everywhere else, unless
  the user asks for the pattern-table split later.

---

## 3. Work list (ordered)

### Phase 1 — Pivot the runtime (blocking)

| # | Task | Exit criterion |
|---|---|---|
| 1.1 | Remove all battery-RAM use from `kanji.inc`, `kanji_overlay.asm`, `kanji_build.py`. Build a variant with `sram_watch.lua` asserting zero hack writes to `$6000-$7FFF`. | Audit clean. Registering books in slots 2 and 3 on the original and the kanji ROM yields identical slot bytes. |
| 1.2 | Assemble the overlay for a fixed text-bank address; include it in every text bank; shrink text per bank accordingly (add bank 20 if needed; the trampoline carries the bank). | Lint: overlay bytes identical across text banks; `pages_over_capacity=0`. |
| 1.3 | RAM far-copy stub at `$0140-$017F`, state at `$0131-$013F`/`$01E0-$01EB`, installed by the trampoline stub in the gap. Remove the `$0600` loader, NMI guards, signature code, the seven extra `kana_prepare` sites and the bank-13 patches. | Patch inventory matches section 2.3; bank 31 mirror; `iram_watch.lua` on the kanji ROM shows no writes outside the reserved ranges and the game's own. |
| 1.4 | Queue-based upload and restore; uploaded flags; exit restore skipping visible tiles; rendering-off rule. | `mask_restore.lua`: 0 visible-scanline frames on the kanji ROM. History prompt, name entry, oath scene, field menu clean. |
| 1.5 | Compiler: static tile assignment from reserved ∪ page ∪ scene-borrow ∪ list sets; page records carry tiles; tag files for scene borrow and lists; errors on unfit pages. | Report shows per-message reservations and zero unfit pages. |
| 1.6 | Survey tool: scripted playthrough that dumps CHR at every message open and writes `scene_borrow.tsv`. Start with the existing input sequences; extend as the playthrough grows. | Oath scene rows list `$42-$5B`; file consumed by the build. |
| 1.7 | Stack check: record minimum SP on the kanji ROM over the survey; the live stack must stay below the state at `$0131`. | Measured and recorded in `STATUS.md`. |

### Phase 2 — Harden

QA renderer: open every message index in Mesen, and for each page assert
(a) no assigned tile is referenced by either nametable outside the window,
(b) every kana tile used by the page holds its glyph, (c) PPUMASK restore
never lands on a visible scanline. Then: outer-bank checklist, `<CALL>` and
`<JUMP>` messages, fourth-line check, EverDrive N8 with saves in all three
slots.

### Phase 3 — Script, tables, menus (unchanged)

### Phase 4 — UI screens (unchanged)

### Phase 5 — Release (unchanged)

---

## 4. Risks

| Risk | Status |
|---|---|
| Save-slot corruption by the current build | Solved in 1.1: no hack write reaches `$6000-$7FFF`; slot 2/3 player save test still pending. |
| Scene-borrow table incomplete | 9 labels surveyed; the 26-tile fallback covers the rest; QA assertions still needed. |
| Stack headroom | Measured: min SP `$18` at NMI, `$28` at overlay entry; state starts at SP `$31`. |
| Internal RAM `$0131-$017F` reached by the stack | Not observed; `iram_watch` shows no foreign writes. |
| Queue capacity waits slow fast text | Same mechanism the game uses; measure typewriter at fastest speed. |

---

## 5. Commands

```powershell
python decomp\build.py                       # original, byte-identical
python decomp\build.py --target kanji        # 512 KiB SUROM target + lint
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua    --name sram_watch
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\iram_watch.lua    --name iram_watch
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua  --name mask_kanji
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\stack_check.lua   --name stack
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua  --name prompt_pages
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua    --name town
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua  --name survey_kanji
```

Survey build:

```powershell
python tools\make_survey_rom.py
python tools\mesen_run.py out\test\survey_noupload.nes tools\lua\scene_borrow_kanji.lua --name borrow
python tools\make_scene_borrow.py
```

Gates: `sram_watch` zero hack writes; `iram_watch` zero foreign writes;
`mask_restore` zero visible-scanline frames; `stack_check` min SP below `$31`;
`pages_over_capacity = 0`. Mesen runs always use a copied ROM name.
