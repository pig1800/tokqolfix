# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 9, 2026-11-08, after the revision-8 execution (commit `de9ef58`)
and the user's play test. This revision is an architecture pivot on the CHR
side, prompted by the user: give the dialogue window its own 4 KiB CHR page
and switch to it mid-frame, so the hack never writes the scene's pattern
table again. Section 1: why. Section 2: feasibility, measured. Section 3:
the design. Section 4: work list. Section 5: what remains for the user.
Target remains emulator-only (Mesen), with the hardware caveat in 3.6.

---

## 0. Revision-9 execution results (2026-11-08)

Implemented on the final build:

| Item | Result |
|---|---|
| Header / MMC1 | 16 KiB CHR RAM, 4 KiB CHR mode, CHR reg 1 = page 1 at reset |
| Fixed bank | $C611-$C676: SUROM switcher + NMI lock, far head, enter overlay, fixed CHR-reg-1 writer, NMI band stub, reset hook (102 bytes) |
| Trampoline | $BF00 in banks 10/11; reads the five inline operands and installs the RAM band routines |
| Band page | CHR page 2: 128 kana tiles copied from bank 9, six tiles per vblank (22 frames at the first message); kanji cache in the compiler-assigned low kana tiles |
| Mid-frame switch | NMI entry flushes kanji to band; scene page restored before the visible frame; band selected at scanlines 144-146; field `bandwrites` log shows 144-146 |
| Scene page | The hack no longer writes page 1; the field comparison against the old revision-8 build shows only the old build's kanji uploads removed |
| Overlay | Dirty bitmap, restore, kana-prepare and `<JUMP>` restore machinery removed; `exit_clear`/jump hooks clear the band flag and restore the scene page |
| Compiler | Reverted to the proven low-tile per-page assignment (message kana + frame reservations); 760 messages, 1,190 pages, max 10/page, oath 9 pages |
| Gates | original byte-identical; kanji `c8f61a09...`; lint 13 ranges; `sram_watch` 0/5,491; `iram_watch` 0/15,948; `mask_restore` 0; stack SP `$18`/`$28` |
| Visual | History prompt, name entry, oath pages 1-3 and four-line pages clean |

Not yet green:

1. **Field message frames.** The game and the hack share the `$0400`
   queue. During a message the NMI flushes it with the band page selected,
   so field CHR updates can land in the band page (blank frame tiles).
   A split `$0500` hack queue with a deferred game flush was prototyped
   but destabilised the message flow; it needs a larger fixed-bank gap
   (or an overlay-resident NMI helper) and is not in this build.
2. **Field QA state.** `tools/lua/town_menu.mss` is still the revision-8
   state; the new engine must regenerate it on the new ROM. The field
   harness is therefore not a valid gate for this build yet.
3. **Band-switch gate / scene-page equality.** The manual `bandwrites`
   log shows scanlines 144-146, but neither gate is automated in
   `tools/qa_*.py`.
4. **Oath length.** The low-tile assignment restores correctness but the
   oath is 9 short pages, not the 3 projected for the 32-glyph cache.
   The 32-glyph static cache conflicts with the engine's line-scroll
   redraw; the compiler was reverted to the proven assignment.

The original scene-page bug (garbled name input / previous page) is
removed by construction: the hack never writes CHR page 1. The field
frame-tile issue is in the shared queue, not the scene page.

---

## 1. Why pivot now

The executor's revision-8 gates are green (field QA 872/872, per-page QA
1,356 pages, zero battery-RAM writes, zero visible-scanline restores), and
the user still sees garbled name input and a page that garbles the previous
one. The harness and the player disagree because the current design is a
pile of case-specific protections over one shared 4 KiB table: per-page
reservations, scene-borrow surveys, screen-tile surveys, prompt tags,
dirty bitmaps, lazy restore, exit restore, `<JUMP>` restore, open-time
restore. Each pass added one more and shrank capacity (the oath is now nine
short pages). Any path the surveys did not walk is unprotected, and the
player walks such paths. Correctness by construction is worth more than
another survey.

---

## 2. Feasibility, measured on Mesen

Probe: `out/test/chr16_probe2.nes` = current kanji ROM with three changes.

| Change | Bytes |
|---|---|
| NES 2.0 header byte 11 = `$08` (CHR RAM 16 KiB) | 1 |
| `mmc1_init` control `$0E` → `$1E` (4 KiB CHR mode) | 1 per fixed-bank copy |
| reset's second CHR loop `lda #$00` → `lda #$01` at `$F022` (register 1 = page 1) | 1 per fixed-bank copy |

Result (`tools/lua/probe_c16e.lua` vs `probe_basetr.lua`, fresh save
names): frames 900, 1100, 1240, 1720, 1960 and 2300 are pixel-identical to
the current build through the history prompts, name entry and the oath
scene with kanji. Mapper state confirms 4 KiB mode, `$1000` backed by
physical page 1, and the SUROM outer bit still carried in CHR register 0.
Lessons for the executor: Lua writes to mapper registers do not take
effect, so probes must patch ROM; and a reused Mesen ROM name reuses its
battery save and changes the flow.

---

## 3. Design: a private CHR page for the text band

### 3.1 Pages

| Physical 4 KiB page | Role |
|---|---|
| 0 | sprites, as today (`$0000`) |
| 1 | scene BG, as today (`$1000`): kana font, portraits, map chips, menus |
| 2 | **band page**: kana font copy in `$00-$7F`, kanji cache in `$80-$FF` |
| 3 | spare |

CHR register 0 = `0 | outer`; CHR register 1 = `1 | outer` normally, `2 |
outer` during the band scanlines of frames where a message is open. The
hack never writes page 1. Name entry, menus, lists, maps, portraits are
untouched by construction, which removes both play-test bugs and every
restore and reservation mechanism.

### 3.2 Mid-frame switch

The dialogue window occupies rows 18-27 (scanlines 144-223). In the NMI,
after the game's PPU work and `ppu_nmi_on`, if a message is open: delay to
scanline ~146 and write CHR register 1 = `2 | outer`. At the next NMI
entry write register 1 = `1 | outer` before any PPU work, so the top of
the frame and all queue flushes see the scene page; then flush kanji
uploads with register 1 = band page before restoring the scene page.
Order inside NMI: entry → reg1 = band → OAM DMA, queue flush, palette →
reg1 = scene → scroll, mask, `ppu_nmi_on` → delay → reg1 = band → sound.

Tolerance: row 18 is the window's top border, drawn from frame tiles in
the kana region, which are identical in pages 1 and 2, so a switch landing
anywhere inside that row is invisible. Jitter budget is one row. The
queue-flush length varies by up to ~2k cycles, so the delay is computed
from the bytes flushed (or the flush is capped during messages). Calibrate
with a Lua script that logs the PPU scanline at the register write; gate:
every write within scanlines 144-151 across the oath scene, field messages
and the fastest text speed.

If `nmi_mode` is non-zero (the game's own split screens), do not switch;
the compiler marks messages that can appear there, if any, as kana-only.

CPU: the delay burns ~17k cycles per frame while a message is open. The
main thread only runs the typewriter then; the sound driver runs after the
switch, once per frame as before.

### 3.3 Band page content

- Filled once per power-on at the first message: 128 kana tiles from bank 9
  through the VRAM queue (~11 frames), then never touched by the game.
- Kanji cache: 32 glyphs. Consecutive pages use alternating halves (16
  glyphs each), so lines left visible from the previous page keep their
  glyphs. Current maximum is 10-11 per page.
- Uploads: four 16-byte queue entries per glyph, flushed by the unmodified
  handler while register 1 = band page.

### 3.4 Code and RAM budget

Fixed-bank gap (`$C611-$C676`, 102 bytes):

| Item | Bytes |
|---|---|
| SUROM switcher writing CHR reg 0 = outer, reg 1 = (page byte + 1) \| outer, PRG = bank & `$0F`; preserves X/Y via a temp at `$01E8` | ~58 |
| Trampoline head: `lda text_window_x; jsr set_bank_b; jmp $BF00` | 8 |
| NMI entry stub: if message open, `jsr` RAM scene/band page routine | ~10 |
| Band stub replacing `jsr ppu_nmi_on` at `$EEDD`: `jsr ppu_nmi_on`, if open `jmp` RAM delay routine | ~10 |

`cell_check` and the `$DBE7/$DBEA` patch are removed. The trampoline body
moves to `$BF00` in banks 10 and 11 (identical copies; both banks are
pointer tables plus 8-byte stubs with ample room).

Internal RAM (`$0131-$017F`, `$01E0-$01EB`, all audited free): state
(~12 bytes), font-copy stub (32), band delay + page routines (~24), page
byte, message-open flag, switcher temp.

Overlay (text banks, `$B800+`): dispatcher, kanji handler, control store
(page advance, uploaded-flag reset), band fill. Removed: dirty bitmap,
`kana_prepare`, `restore_exit`, `jump_exit_13/14`, open-time restore,
redraw re-upload, all reservation inputs.

Patch inventory after the pivot: `$C4B7`, `$C611-$C676`, `$D28E`, `$D2C7`,
`$EE7F`, `$EEDD`, plus the two 1-byte reset/init changes. Bank 31 stays a
mirror.

### 3.5 Compiler

Static tile assignment from the band's 128 kanji tiles with alternating
halves per page. Delete scene-borrow, screen-tile, prompt-tag and
cross-page reservation logic. Re-page the script at the restored capacity
(the oath returns to three pages).

### 3.6 Hardware caveat

No MMC1 board has 16 KiB CHR RAM; SUROM has 8. Emulators follow the NES 2.0
CHR-RAM field (Mesen verified; FCEUX to check). EverDrive N8 support is
unknown and must be tested when hardware exists; the fallback is a mapper
port (MMC3 with CHR RAM and its scanline IRQ, which also removes the delay
loop). The user accepted emulator-first.

---

## 4. Work list (ordered)

### Phase 1 — Cartridge and switch (blocking)

| # | Task | Exit criterion |
|---|---|---|
| 1.1 | Header, control, reset immediates; dual-register switcher with the page byte; `cell_check` removed. | Full run frame-identical to the current build (the probe result, now from the build). |
| 1.2 | Trampoline body at `$BF00` in banks 10/11; gap head; lint updated. | All 872 messages open (reuse `qa_sweep`). |
| 1.3 | NMI entry and band stubs; RAM delay routine; message-open flag set by the trampoline and cleared at every interpreter exit (`$D1F3`, `<JUMP>` path). | `tools/lua/band_switch.lua`: register-1 write scanline within 144-151 for every frame of the oath scene and a field message at every text speed. |
| 1.4 | Band fill and kanji uploads with register 1 = band during flush; remove the restore machinery. | Oath scene and field messages render; `scene page CHR == original` at every sampled frame (new gate). |
| 1.5 | Compiler: band assignment, alternating halves, reservation code deleted, script re-paged. | `pages_over_capacity=0`; oath = 3 pages. |

### Phase 2 — Gates

- `scene_page_check.lua`: at every sampled frame of the survey, physical
  page 1 (`$1000-$1FFF` while register 1 = 1) equals the original ROM's
  CHR at the same frame. This single assertion replaces the kana-intact,
  frame-tile and outside-window checks.
- `band_switch.lua` scanline gate; `mask_restore` 0; `sram_watch` 0;
  `iram_watch` only reserved ranges; stack check.
- QA sweep in both contexts for legibility (screenshots), now without
  context-dependent failures by construction.
- FCEUX run of the survey for 16 KiB CHR RAM support.
- Random-RAM power-on; no PRG-register bit-4 writes; slot 2/3 proof.

### Phase 3 — Script, tables, menus; Phase 4 — UI; Phase 5 — release

Unchanged, except that kanji outside the band (menus, status labels) now
needs a per-screen decision: screens without scene graphics can map the
band page for the whole frame; others keep kana.

---

## 5. What remains for the user

1. **Save states of the two bugs you saw.** In Mesen, at the garbled name
   input and at the garbled previous page, save a state and drop the
   `.mss` files in `out/user/`. They become regression cases; the pivot
   should make them disappear, and the executor must prove it on your
   states, not only on the harness paths.
2. **Hardware caveat accepted?** 16 KiB CHR RAM on MMC1 is emulator-only
   until tested on an N8; the fallback is a mapper port. Say so if that is
   not acceptable, before phase 1 starts.
3. Proofreading when phase 3 starts; hardware pass when an N8 exists.
4. Do not distribute the current build.

---

## 6. Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\probe_c16e.lua --name probe   # reference probe script
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua    --name sram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua  --name mask
python tools\qa_sweep.py --workers 4
```

Always use a fresh `--name` per ROM variant: Mesen keys the battery save by
ROM name, and a reused name replays the previous run's saves.
