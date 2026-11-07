# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 5, 2026-11-07, after the revision-4 pass (commit `b967d80`;
evidence in `STATUS.md` and the `SITREP.md` addendum). Earlier revisions
are in git history. Section 1: milestone. Section 2: findings from this
review, with the new measurement. Section 3: design deltas. Section 4:
ordered work list. Later phases unchanged at the end.

Goal and platforms unchanged: every dialogue line, menu, table string and
screen label in kanji+kana; Mesen and the original EverDrive N8.

---

## 0. Revision-5 execution results (2026-11-07)

This plan was executed and three of its premises failed:

- **F19 is wrong.** The upper range `$80-$9F` is referenced on the history
  and name-entry screens (window border, menu font, name font). Opening the
  pool from `game_mode`/`text_mode` alone garbles the screen. The
  revision-4 nametable gate must stay.
- **The SRAM audit was incomplete.** Bank 13 copies a 2 KiB save slot over
  `$6800-$6FFF` (indirect `PC $9F6B-$9F7E`, "5S" at `$6008`). Long-lived
  state there is wiped by the save menu. The upper save area at `$7C00`
  survives; internal RAM `$0500-$07FF` is free after boot but a relocation
  attempt caused page-record corruption and was reverted.
- **Batch tuning is not a straight line.** 4 CHR tiles / 64 nametable bytes
  still produced visible-scanline restores (36/11) and broke the survey
  (green screen). Revision-4 batches were restored; the black band remains.

The code is back to the verified revision-4 runtime plus two capacity
checks (page ≤13 slots, metadata ≤256) and a 256-byte metadata copy.
Current hashes: original `40f19e…a8367`, kanji `cf2db9…6a445f`.
Details and next steps are in `STATUS.md`. Sections 1-5 below are retained
as the revision-5 plan of record; where they conflict with `STATUS.md`, the
status file and this section win.

---

## 1. Milestone reached

- Upper-half allocation closes the save-slot collision: the history prompt,
  its slot line and the speed menu are all clean (`ktown_1100`, `ktown_1240`).
- Tiles `$00-$F9` render in the cell buffer; `$FA-$FF` stay controls
  (`cell_check` at `$C64F`, 17 lint ranges, bank 31 still a mirror).
- Nametable scan covers both nametables; OAM sprite tiles are considered.
- Font is JF-Dot-Shinonome16 with single-pixel strokes, verified in game.
- 6,000-frame survey: no hang, no NMI re-entry, map and menus clean.
- `tools/lua/nmi_budget.lua` exists and measured handler cycles.

---

## 2. Findings

### F18. The scan frames blank the top of the picture — must fix

`nmi_budget.lua` measured cycles from NMI entry to `rti`. That metric is
misleading: the original handler also runs its sound driver after
re-enabling the PPU, so its `rti` is routinely mid-frame (original max
10,132 cycles) and nothing is wrong with that. What matters is when the
handler restores PPUMASK (`$EEDA`), because the overlay writes PPUMASK 0
before its jobs and the picture is blank until the restore.

`tools/lua/mask_restore.lua` (added this iteration) logs the PPU scanline
at the `$EEDA` store over the title-to-field run:

| ROM | Frames restoring PPUMASK on a visible scanline (0-239) | Scanlines seen |
|---|---:|---|
| Original | 0 (restore at 248-249) | — |
| Kanji | **73** | 37 and 86, alternating |

So every scan frame renders the top 37 or 86 scanlines black. The history
screen is black there anyway, which is why the surveys and the executor's
screenshots showed nothing. On the field map it is a black band over the
top third of the screen, flickering for the ~32 frames of every message
open. Scanline 86 also means the scan loop costs roughly 40 cycles per byte
read; the loop itself is slow, not just the batch size.

Budget rule from the original: PPU work must end by scanline ~249, which
leaves about 1,300 cycles after OAM DMA, queue flush and palette. Jobs get
at most ~1,000 cycles per frame.

### F19. The nametable scan is the wrong tool for its purpose

It exists to keep kanji off tiles that are visible outside the window and
to decide whether the upper pool is open. Both can be answered without
reading 2 KiB from the PPU every message:

- Upper pool open/closed is a property of the screen mode, not the view.
  The game keeps mode bytes (`game_mode $87`, `text_mode $50`,
  `nmi_mode $F0`); the history/menu screens and the field/event screens
  have distinct values (observed `$1E/$26/$28/$29` for `text_mode`). A
  small static table plus the OAM shadow at `$0200` (RAM, no PPU reads)
  decides the pool. A missed mode shows up as corruption in one screen and
  is found by the survey.
- Lower tiles referenced outside the window are the reserved icons
  (金/兵, already reserved) and runtime lists, which are handled by
  per-message reservation (F20). The oath scene's portrait tiles are
  excluded by the CHR scan, not the nametable scan.

Drop the nametable scan. If a scene later proves to draw kana outside the
window, add that scene to the reservation rule rather than reviving the scan.

### F20. Field prompts: reserve per list, not the union

The union `menu ∪ party_name ∪ item_name` (~100 tiles) cannot fit, as the
executor found. But a given prompt is followed by one list, not all three.
Tag each prompt message with the list that follows it (`party`, `item`,
`officer`, `menu`, `none`) by reading its caller in banks 13/14/15; there
are a few dozen prompts. Reserving one set (57-62 tiles) leaves roughly
20 free tiles, enough for the one to three kanji a prompt uses. Prompts
that still cannot fit are reported by the compiler, not blanked.

### F21. Upper tiles must be saved, not zeroed

The history screen's upper half holds the menu/name font (124 of 128 tiles
non-blank). Restoring borrowed upper tiles to zero destroys that font in
CHR and only works because the following screens happen to reload CHR.
That is a latent corruption. Save the 16 bytes of each borrowed upper tile
before the first upload and restore the saved bytes at exit. Cap upper
borrowing at 8 kanji (32 tiles, 512 bytes of save area). SRAM has room:
the overlay ends at `$7BA6`, so `$7C00-$7DFF` is free for the save area.

### F22. Conditional CHR rescan is still pending

With the nametable scan gone, the CHR scan is the only per-message cost.
Rescan only when the overlay's NMI entry has seen rendering off, or a
VRAM-queue entry below `$2000`, since the last scan. Most messages then
open with no scan at all; the first message after a scene change pays one.

---

## 3. Design deltas (revision 4 remains in force otherwise)

| Area | Change |
|---|---|
| NMI jobs | Hard budget ~1,000 cycles per frame; unrolled tile read loop; verify with `mask_restore.lua`: scanline at `$EEDA` must never be 0-239 on either ROM. |
| Scans | Nametable scan removed. CHR scan kept, conditional on the change signal, 4 tiles per frame worst case. |
| Upper pool | Opened by screen-mode table + OAM shadow; borrowed tiles saved before upload and restored from the save area; cap 8 kanji. |
| Reservation | Per-prompt list tag replaces the union; compiler errors on prompts that cannot fit. |
| Harness | `mask_restore.lua` runs in every pass alongside `prompt_pages`, `town_kanji`, `scene_survey`; its "visible-scanline" count must be 0. |

---

## 4. Work list for the next pass (ordered)

### Phase 1 — PPU budget and pools (blocking)

| # | Task | Exit criterion |
|---|---|---|
| 1.1 | Remove the nametable scan; implement the screen-mode table and OAM-shadow check for the upper pool. Record the mode values per screen in `kanji.inc`. | `prompt_pages`, `town_kanji`, `scene_survey` unchanged in result; message open no longer waits on a nametable scan. |
| 1.2 | Rewrite the CHR scan loop (unrolled 16-byte read + compare), 4 tiles per frame; make it conditional (F22). | `mask_restore.lua`: 0 visible-scanline frames on the kanji ROM over the title-to-field run and over a field message. |
| 1.3 | Upper-tile save/restore with the 8-kanji cap (F21). | After the history prompt, dump CHR `$1800-$1FFF` and compare with the pre-message dump: identical. |
| 1.4 | Prompt list tags in the compiler (F20): tag file keyed by message label; reserve the tagged set; report unfit prompts. | Report lists tags and zero unfit prompts, or the unfit ones are re-paged by hand. |
| 1.5 | Field prompt test: script a field message followed by a party list and by an item list; capture before and after. | Prompt kanji and list kana both clean. |
| 1.6 | Redraw test (carried over): a page over four lines under the command menu. | Kanji intact after the menu closes. |

### Phase 2 — Harden (unchanged)

Outer-bank checklist; all `<CALL>`/`<JUMP>` messages; fourth-line check;
EverDrive N8 boot, dialogue, save, power-cycle, load; `mask_restore` on
hardware is not possible, so the Mesen result is the gate.

### Phase 3 — Script, tables, menus (unchanged; largest remaining work)

Proofread both `_fixed.dtx` files; move inline bank-15/13 menu and oath
strings into indexed messages; convert WORD/PLACE/ITEM tables and name
records; compare name kanji against the original 136 glyphs.

Open decision for phase 3, flagged now: kanji names inside field lists
(party and item lists, 7 names × 2 kanji = 56 tiles) exceed what the lower
pool can hold on a map screen. Options are to keep list entries in kana on
the field, or to render the window band from pattern table `$0000` with a
mid-frame switch, which the game's NMI already does for other modes. The
first is cheap; the second is a new subsystem. Recommendation: kana in
field lists, kanji everywhere else, unless the user wants the split.

### Phase 4 — UI screens (unchanged)

### Phase 5 — QA and release (unchanged)

---

## 5. Risks (updated)

| Risk | Status |
|---|---|
| Black band on field message open (F18) | Open; 1.1-1.2 close it. |
| Upper-tile zeroing corrupts fonts (F21) | Open; 1.3. |
| Field prompts over lists (F20) | Open; 1.4-1.5. |
| Screen-mode table misses a mode | Found by survey; add mode. |
| Kanji names in field lists | Decision needed before phase 3 tables. |

---

## 6. Commands

```powershell
python decomp\build.py                       # original, byte-identical
python decomp\build.py --target kanji        # 512 KiB SUROM target + lint
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua  --name mask_kanji
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua  --name prompt_pages
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua    --name ktown
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua  --name survey_kanji
```

`mask_restore.lua` writes `out/test/mask_restore.txt`; the line
`frames with visible-scanline mask restore` must read 0. Mesen runs always
use a copied ROM name.
