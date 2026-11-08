# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 10, 2026-11-08, after the revision-9 execution (commit `daba749`,
kanji ROM `c8f61a09...`) and the user's play test. The user saw three things:
a moving garbage line ("horizontal interrupt broken"), the history prompt
turning to garbage right after it finished, and a crash after the oath. All
three reproduce on the harness and are root-caused in section 0. Revision 10
keeps the private CHR page but replaces its mechanics: no RAM-resident code,
the band page is a shadow of the scene page instead of a kana-font copy, the
mid-frame switch is synced by a sprite-0 hit instead of a cycle count, the
hack no longer shares the `$0400` queue, and the hack's NMI code lives in a
PRG bank mapped by the NMI with the game's own bank-lock protocol. Section 1
lists the measured facts the design rests on, section 2 the design, section
3 the work list, section 4 what remains for the user. Target is still
emulator-only (Mesen); hardware caveat in 2.9.

---

## 0. Revision-9 play test, reproduced and root-caused

All evidence is from the current kanji ROM on the standard 4,000-6,000 frame
input path (`tools/lua/rev9_diag.lua`, `rev9_freeze.lua`, `rev9_input.lua`,
`rev9_nmioff.lua`; outputs in `out/test/rev9diag/`), and from the original
ROM for the comparisons (`out/test/ramsurvey/`).

| Symptom | Measured cause | Evidence |
|---|---|---|
| Garbage line that moves | The CHR-register-1 fifth write lands at scanlines 143-156, not 144-151. Histogram over 811 band frames: 144 x573, 145 x157, 154 x36, 156 x19, 147 x13, 143 x9, 146 x3, 155 x1. 8% of frames switch inside the text rows or the scene row, so part of a scanline is drawn from the other page. The delay is a fixed cycle count that starts after a variable amount of NMI work (queue flush length, palette upload). | `diag.txt` switch histogram |
| Game's own splits broken | The band delay (about 17k cycles) runs before the game's split-screen loops at `loc_EF38`/`loc_EF94`, which execute whenever `nmi_mode` is non-zero (intro scroll in bank 7, officer scene in bank 13). The band stub has no `nmi_mode` check. The harness path never had both at once; the user's path does. | `bank15.asm` NMI listing; `surom_b15.asm` `band_stub` |
| Prompt garbled after it finished | `exit_clear` clears `KANJI_BAND_ON` and writes CHR reg 1 = page 1 when the *message* ends, but the *window* stays on screen with its kanji positions now showing page-1 kana. | `f0900.png` (band on, correct) vs `f0940.png` (band off, garbage) |
| Crash after the oath | `cell_check`/`cell_check_x` were installed at `$01EC-$01F7`, which is the main stack (`$01EC-$01FF`; the original audit shows the stack reaching `$01EC`). 72,734 stack writes hit that range in 4,000 frames. At frame 2,480 the renderer executed `jsr $01EC` with the bytes `B9 00 03 C9 96 87` (should end `FA 60`), ran stack garbage, never returned; NMI task timers stopped, game frozen on oath line 2. The original reaches `text_show_message` #5 at frame 3,290; the kanji build never does. `iram_watch` did not cover `$01EC-$01F7`, which is why the gate was green. | `nmioff.txt` line `f=2480 exec 01EC bytes=...`; `freeze.txt`; `input_k.txt` vs `input_o.txt` |

Three further findings that change the design:

- **There is no free RAM page.** `$0400-$06FF` is all used by the game except
  the single byte `$0600`; `$0601-$0634` is game RAM-resident code. The
  revision-9 `$0500` hack-queue prototype wrote over live game RAM, which is
  why it "destabilised the message flow". Free internal RAM remains exactly
  `$0131-$017F`, `$01E0-$01EB`, `$010B-$0112`, `$0100-$0103`
  (`ram_exec_survey.lua`, `survey.txt`).
- **A kana-font copy is not enough for the band page.** The window is not
  full-width. In the town the map's bricks are visible right of the window
  on scanlines 144-175 (`town_o_4425.png`), and the blank tile `$FE` (upper
  half) fills the rest of those rows in the oath and the town. Any tile the
  scene shows on scanlines 144-223 must be identical in the band page.
- **The field-frame problem was the shared queue.** With the band page
  selected during the NMI flush, every game CHR write made while a message
  is open (the cursor tile `$FF` every 16 frames, the oath's `$42-$5B`
  overwrite, field transitions) went to page 2 and never reached page 1.

Executor claims checked: "CHR write scanline 144-146" is contradicted
(143-156); `mask_restore` 0 still holds; `stack_check` `$18/$28` is a task
stack value and is fine; `iram_watch` 0 was true but the watched range
excluded the stack, where the RAM code was.

---

## 1. Facts the revision-10 design relies on (measured)

| Fact | Value | Source |
|---|---|---|
| OAM slot 0 | Never used by the game: `$0200-$0203` = `F8 00 00 00` in all 400 samples | `dmc_oam_survey.lua`, `dmc_oam.txt` |
| Sprite tile indices never referenced by visible sprites on the path | includes `$FF` (full list in the file) | `chr_writers.lua`, `chr_writers.txt` |
| DMC | Unused: 1 write to `$4010-$4013` (reset), 0 enables. No DMA cycle stealing; timed loops are stable | same |
| PPUMASK shadow | `$1E` in play (BG+sprites, no clipping), `$06` during fades | same |
| CHR writers | Only two: the block writer `loc_C343` (`$C3C2`/`$C3D7` loops; 8,848 bytes to page 1, 2,816 to page 0, 2,304 more via `$C3D7`) and the queue flush `$D9E4` (1,664). Nothing else writes PPUDATA with a CHR address | same |
| Game bank-lock protocol | `set_bank_lock` sets `bank_switch_lock`, writes, re-does if the NMI cleared it; `restore_bank_after_nmi` resets the MMC1 shift register and clears the lock if it finds it set. This is the game's own guard for the sound bank switch and the hack must use the same two routines for every mapper write | `bank15.asm` 934-1001 |
| Task stacks | Four tasks with private stacks. Text-engine task stack bottoms at `$0113` on the original (min SP `$1B` at NMI), `$0119` on revision 9. `$01EC-$01FF` (main) and `$0104-$0130` (tasks) are stack | `iram_audit.txt`, `stack_check.txt` |
| Fixed-bank space | Gap `$C611-$C676` (102). Candidates never read or executed on the path: `$FFE0-$FFEF` (16), `$E6B3-$E6C3` (17). Dead in the kanji target: `write_prg_bank` body `$C4BA-$C4CA` (17), because `$C4B7` jumps away | `fixed_reads.lua`, `fixed_reads.txt` |
| Window geometry | Top border on screen row 18 (scanline 144) in the history prompt, oath and town; width varies (town x 8-176, oath 16-176) | screenshots |
| Cursor tile | `draw_text_window` writes tile `$FF` (`$1FF0`) through the queue every 16 frames while a window is open | `bank15.asm` 4529 |
| Border tile line row | To be read from bank 9 tiles `$6D-$6F` by the executor (needed for the sprite-0 row) | task 3.5 |

---

## 2. Design (revision 10)

### 2.1 Pages and registers (unchanged from revision 9)

Page 0 sprites, page 1 scene, page 2 band, page 3 spare. CHR reg 0 carries
only the outer PRG bit (the switcher). CHR reg 1 = `1|outer` from NMI entry
until the band line, `2|outer` from the band line to the next NMI. **The main
thread never writes CHR reg 1**; the hack's block-writer hook (2.4) restores
page 1 before any main-thread CHR write in case the NMI left page 2 selected
and the game then disabled NMI.

### 2.2 The band page is a shadow of the scene page

Invariant: `page2[t] == page1[t]` for every tile `t` not in the active-kanji
set **A** (the tiles holding the current message's kanji). Three mechanisms:

- **Resync.** The block-writer hook sets `KANJI_PAGE1_DIRTY`. While DIRTY and
  rendering is off (`ppu_mask_shadow & $18 == 0`) each NMI copies 48 tiles
  page 1 to page 2 by PPUDATA read-back (16-byte tile, remember the PPUDATA
  read buffer), driven by a cursor in RAM and skipping tiles in A. With
  rendering on, 2 tiles per vblank. DIRTY clears when the cursor completes a
  pass with no new write; a write during the pass sets it again. Boot and
  every scene load are expected to complete the pass inside their
  rendering-off window; the gate in 3.4 checks it.
- **Mirror.** `flush_vram_queue` is hooked at its entry. The hack's copy of
  the loop writes each entry to page 1 (reg 1 = 1 first) and writes entries
  addressed in `$1000-$1FFF` a second time to page 2 unless the tile is in A.
  Because the hook is at the routine's entry, both the NMI flush and the
  main-thread `wait_vblank` flush are mirrored.
- **Kanji.** Uploaded into page-2 slots by the NMI from the font bank
  (2.6). Released slots go into a RESTORE bitmap and are re-copied from page 1
  by the resync cursor.

Consequence: when A is empty and nothing is pending, page 2 equals page 1
and the band switch is invisible, so the band flag's lifetime is simple:

- set at overlay entry (message open);
- A is released (moved to RESTORE) on `<END>` (the window is about to be
  erased), at the next overlay entry (previous message's A), and whenever the
  NMI sees rendering off. A is **not** released on `<END_NOWAIT>`, `<CALL>`
  or `<JUMP>` exits, so a prompt keeps its kanji until the screen changes or
  the next message opens;
- the band flag clears when A is empty and RESTORE is empty, or when
  rendering is off.

### 2.3 Mid-frame switch synced by sprite 0

- NMI entry (hack code, band on): write OAM slot 0 before the DMA:
  `y = 143 + r`, `tile = $FF`, `attr = $20` (behind background, palette 0),
  `x = 16` (inside the window's top border, clear of the left 8 pixels). `r`
  is the pixel row of the horizontal line inside the top-border tile (from
  bank 9). Also rewrite page-0 tile `$FF` every band frame: plane 0 rows
  `r` and `r+1` = `$FF`, everything else 0. The sprite is opaque only on the
  border line and sits behind it, so it is invisible; the hit fires on
  scanline `144 + r`.
- Band stub at `$EEDD` (hack code): if `nmi_mode == 0`, band on and rendering
  on: poll `bit PPUSTATUS` for bit 6 with a bounded loop whose bound is
  about scanline 150; on hit or bound, write CHR reg 1 = `2|outer`; return.
  The game's sound code then runs as it does now. Log the exit reason
  (hit or bound) in a RAM byte for the gate.
- Next NMI entry: reg 1 = `1|outer` before any PPU work.
- `nmi_mode != 0`: the fixed-bank stubs skip both hack calls and the flush
  hook runs the original loop, so the game's split-screen scenes get zero
  added cycles. The flush hook's plain path sets DIRTY unconditionally so a
  later resync catches any CHR write made there.

### 2.4 Code placement: a hack PRG bank, no RAM code

- **Hack banks 23 and 24** (new; banks 23-30 are unused). Each holds the
  identical hack code at `$8000` (entry, band, reset, flush, scene-page
  helper; target about 400 bytes) followed by glyph data: 718 glyphs x 32
  bytes split across the two banks, so a glyph is always readable from the
  bank whose code is running. The upload request names the bank. (Keeping
  the data in banks 16-17 and putting the code there is equivalent; the only
  rule is that code and the glyph it reads are in the same bank.)
- **`call_hack`** (fixed bank, about 29 bytes): `sta KANJI_FN; lda
  current_prg_bank; pha; lda KANJI_HACK_BANK; jsr map_hack; jsr $8000; pla;
  jmp map_hack`, with `map_hack: lda KANJI_IN_NMI; bne @n; jmp set_bank_lock;
  @n: jmp restore_bank_after_nmi`. The main-thread variant inherits the
  game's lock-and-redo; the NMI variant inherits reset-if-locked. Inside the
  hack bank, every CHR-register sequence issued from the main thread (the
  scene-page helper, the mirror's page switches) sets `bank_switch_lock`,
  writes, and redoes if the lock was cleared; sequences issued from the NMI
  need nothing more because the entry already reset the shift register if a
  main-thread sequence was interrupted.
- **Fixed-bank stubs** (sizes approximate):
  - switcher at `$C611`, as now minus `KANJI_NMI_LOCK` (about 36);
  - `far_head` + `enter_text` unchanged (14), or `enter_text` replaced by
    pushing `$B7FF` and jumping to `set_bank_b` so its `rts` lands at `$B800`;
  - `nmi_entry` (patch `$EE93` `lda #2 / sta OAMDMA` to `jsr nmi_entry / nop
    / nop`): `lda nmi_mode; bne @plain; lda #FN_ENTRY; jmp call_hack; @plain:
    lda #2; sta OAMDMA; rts` (15). `FN_ENTRY` does OAM slot 0, the DMA, reg 1
    = page 1, one upload or two copies, the sprite tile, and sets
    `KANJI_IN_NMI`;
  - `band_stub` (patch `$EEDD`): `jsr ppu_nmi_on; lda nmi_mode; bne @r; lda
    #FN_BAND; jmp call_hack; @r: rts` (13). `FN_BAND` clears `KANJI_IN_NMI`
    at its end;
  - flush hook: `flush_vram_queue: jmp flush_hook` (3 in place) and
    `flush_hook: lda nmi_mode; bne @plain; lda #FN_FLUSH; jmp call_hack;
    @plain: inc KANJI_PAGE1_DIRTY; ldx vram_queue_read; jmp $D9B3` (17);
  - block-writer hook: `loc_C343: jmp c343_hook` (3 in place) and
    `c343_hook: inc KANJI_PAGE1_DIRTY; lda nmi_mode; bne @plain; lda
    #FN_SCENE; jsr call_hack; @plain: lda PPUSTATUS; jmp loc_C343+3` (18).
    `FN_SCENE` writes reg 1 = page 1 under the lock protocol. `call_hack`
    swaps `$8000` while the block writer's source bank is mapped and
    restores it before the body runs, which is why the hook is at the entry;
  - reset hook (patch `$F036`): `lda #FN_RESET; jmp call_hack` (5).
    `FN_RESET` clears all hack state, sets `current_prg_bank` to the bank the
    original has mapped at `$F039` (verify in the trace; expected `$0E`), and
    returns with A = 0, X = `$F0`.
  - Removed: fixed `write_chr1`, both `cell_check` routines, every RAM
    routine, `KANJI_NMI_LOCK`. Patches `$DBE7`, `$DBEA`, `$D420` go back to the
    original bytes; the compiler asserts every assigned tile is below `$80`
    (it already only assigns kana slots) so the original bit-7 control test
    is correct and the line-scroll redraw conflict disappears.
  - Budget: about 147 bytes against 102 + 17 (`$C4BA`) + 16 (`$FFE0`) + 17
    (`$E6B3`) = 152 once task 3.1 confirms the two candidates. If it rejects
    them, trim: `enter_text` via the `rts` trick (-6), drop X/Y preservation
    in the switcher after checking the callers (-8), inline `band_stub`'s
    checks into the hack bank at the cost of about 200 cycles in split
    scenes (not preferred).

### 2.5 RAM (state only)

- `$0131-$013F`: text bank/address, page pointer, code, pages left, entry,
  four tiles, uploaded flags (as now).
- `$0140-$015F`: request block (`REQ_FLAG`, `REQ_BANK`, `REQ_GLYPH` lo/hi,
  `REQ_TILES` x4), resync cursor, `PAGE1_DIRTY`, `IN_NMI`, `FN`, `HACK_BANK`,
  `BAND_ON`, band exit reason, pending counters.
- `$0160-$016F`: RESTORE bitmap (128 tiles).
- `$0170-$017F`: active-kanji bitmap A (128 tiles).
- `$01E0-$01EB`: scratch.
- Nothing in `$01EC-$01FF`, `$0100-$0130`, `$0400-$06FF`. No code in RAM.
  All of it is initialised by `FN_RESET`; random power-on RAM is a gate.

### 2.6 Overlay (text banks 18-22)

- Entry: move the previous message's A into RESTORE, clear A, set `BAND_ON`,
  consume the text address, read the page record (as now). No band fill, no
  RAM stub install, no CHR-register write, no queue use.
- Per kanji: if not yet uploaded, post the request (bank, glyph index, four
  tiles), set the four bits in A, loop on `wait_vblank` until `REQ_FLAG`
  clears (the NMI serves one glyph per frame when the game's queue holds at
  most 32 bytes), then render the tile numbers into `$0300` as now.
- Page change: tiles of the finished page that the new page does not use go
  to RESTORE; `<END>` moves all of A to RESTORE.
- Exits: `exit_clear`/`jump_exit_13/14` keep only the bank handling; they no
  longer touch `BAND_ON` or CHR registers.
- `fill_band`, `copy_kana_row`, the stub source, `overlay_write_chr1` and
  `wait_queue_empty` are deleted.

### 2.7 Vblank budget

Hack work per NMI stays under about 1,000 cycles: two bank-switch pairs
(about 300), OAM slot 0 (12), sprite tile (about 150, band frames only), and
either one glyph (64 PPUDATA writes, about 600) or two tile copies (about
600), never both; the glyph is skipped when the game's queue holds more
than 32 bytes. `mask_restore` must stay 0.

### 2.8 Compiler

Unchanged (revision-8 low-tile per-page assignment with forward and backward
reservations) plus the `< $80` assertion. Capacity work (the oath's nine
pages) is deferred until the gates are green; it is content, not stability.

### 2.9 Hardware caveat (unchanged)

No MMC1 board has 16 KiB CHR RAM. Emulator-only until tried on an N8; the
fallback is a mapper port.

---

## 3. Work list (ordered)

### Phase 1 — stabilise the private page (blocking)

3.1 **Fixed-bank audit.** Extend `tools/lua/fixed_reads.lua` to the QA sweep
    and the town path on the original; confirm `$FFE0-$FFEF` and
    `$E6B3-$E6C3` are never read or executed; register the confirmed ranges
    and `$C4BA-$C4CA` in `bank15_lint`.
3.2 **No RAM code.** Delete `cell_check`, `cell_check_x`, the RAM band and
    stub routines; restore `$DBE7`, `$DBEA`, `$D420`; add the compiler
    assertion. Extend `iram_watch` to `$01EC-$01FF` (zero hack writes) and
    add an exec watch: no execution anywhere in `$0000-$07FF` except the
    game's `$0601-$0634`.
3.3 **Hack bank and call path.** Banks 23/24 with code + glyph data;
    `call_hack`/`map_hack`; the five stubs and `FN_RESET`; the bank-lock
    rules of 2.4. Gate: `bank_lock_check.lua`, every MMC1 write sequence
    (PRG, CHR 0, CHR 1) completes with five writes to one register with no
    other mapper write in between, over the sweep.
3.4 **Shadow page.** DIRTY, resync cursor, block-writer hook, mirrored flush,
    RESTORE/A bitmaps. Gate `shadow_check.lua`: at every sampled band frame,
    `page2[t] == page1[t]` for every `t` not in A that screen rows 18-27
    reference (nametable rows resolved through the scroll registers); pages
    0 and 1 equal the original ROM's CHR at the same point of the standard
    path (align by `text_show_message` count, not frame number; page-0 tile
    `$FF` excluded); boot and each scene load finish the resync before
    rendering turns on (report any frame where DIRTY is set with rendering
    on and the band on).
3.5 **Sprite-0 switch.** OAM slot 0, page-0 tile `$FF`, bounded poll, border
    line row `r` from bank 9. Gate `band_switch.lua`: fifth CHR-1 write
    scanline per band frame, all within 144-151, at least 99% by hit, and
    zero hack cycles in `nmi_mode != 0` frames (the bank-7 intro scroll and
    the bank-13 officer scene frames pixel-identical to the original).
3.6 **Glyph upload through the NMI and the band lifetime of 2.2.** Then the
    three play-test regressions as gates: (i) history prompt: every frame
    from completion until the screen change renders the window identically
    to the completion frame; (ii) the standard 6,000-frame path reaches
    `text_show_message` #5-#9 within 30 frames of the original's 3,290,
    4,415, 4,685, 4,955, 5,226 and the oath advances page by page; (iii) the
    town path opens and closes four dialogues with the map rows outside the
    window pixel-identical to the original.

### Phase 2 — gates on the final build

`bank15_lint`; `sram_watch` 0; `iram_watch` 0 including `$01EC-$01FF`; exec
watch; stack min SP at NMI at least `$13`; `mask_restore` 0; `band_switch`;
`shadow_check`; `bank_lock_check`; CHR writers on the sweep are only `loc_C343`
and the hack flush; OAM slot 0 and sprite tile `$FF` unused by the game on
the sweep; `qa_pages` and `qa_field` regenerated on the new ROM (new
`town_menu.mss` via `town_menu_save.lua`); random-RAM power-on (`$00`, `$FF`,
random fills); no PRG-register bit-4 writes; second emulator (FCEUX with 16
KiB CHR RAM support, or document the limitation); save slots 2/3 round-trip.

### Phase 3 — script, tables, menus; Phase 4 — UI; Phase 5 — release

Unchanged from revision 9. Capacity (fewer oath pages) belongs to phase 3.

---

## 4. What remains for the user

- `out/user/` is still empty. Mesen save states at the moment of each bug
  you see (`.mss`) are the best regression cases; drop them there with a
  one-line note. The harness now reproduces all three reported bugs without
  them, but your states cover paths the input scripts do not.
- The hardware caveat (2.9) stands; say so if emulator-only is not
  acceptable.
- Do not distribute the current build (`c8f61a09...`): it freezes in the
  oath on the harness path.
- Proofreading waits for phase 3; the hardware pass waits for an N8.

---

## 5. Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji
python tools\bank15_lint.py

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\rev9_diag.lua    --name diag
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua   --name sram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\iram_watch.lua   --name iram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\stack_check.lua  --name stack
python tools\mesen_run.py decomp\build\rom.nes       tools\lua\chr_writers.lua  --name chrw
```

Always use a fresh `--name` per ROM variant: Mesen keys the battery save on
the ROM file name and a reused name replays the previous run's save.
Diagnostic scripts added this iteration, all under `tools/lua/`:
`rev9_diag.lua` (switch scanlines, stack writes into `$01EC-$01F7`,
`nmi_mode` conflicts, crash PCs, screenshots), `rev9_freeze.lua`,
`rev9_input.lua`, `rev9_nmioff.lua`, `ram_exec_survey.lua`,
`dmc_oam_survey.lua`, `chr_writers.lua`, `fixed_reads.lua`,
`window_rows_survey.lua`, `town_msg_shots.lua`.
