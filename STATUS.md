# Current implementation status

Status after the revision-5 execution attempt (2026-11-07), following
`PLAN.md` revision 5. The plan's three blocking assumptions did not survive
contact with the ROM; the code is back to the verified revision-4 runtime
with two small compiler/runtime capacity changes. This file records exactly
what was measured, what was reverted, and what the next pass should do.

## Verified

- `python decomp/build.py` still produces the original 256 KiB ROM:
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- `python decomp/build.py --target kanji` produces the 524,304-byte SUROM ROM
  (current SHA-256 `cf2db99fee82206ce5425f60a6093f5c6f177ae10f9ca6c973f92d2ffd6a445f`).
- Bank 31 is byte-identical to patched bank 15; `tools/bank15_lint.py`
  passes with 17 registered patch ranges.
- The overlay is 2,981 bytes; the far loader copies 3,072 bytes from bank 24.
- History prompts are clean: `out/test/pp_0900.png` shows
  `どの歴史書を登録しますか?`; `out/test/ktown_1100.png` shows
  `どの歴史書を始めますか?` with the slot line and speed menu.
- The 6,000-frame `scene_survey.lua` run is healthy;
  `out/test/survey_6000.png` shows the field command menu
  (はなす / しらべる / たいねつ / ふじょう / どうぐ) and intact map tiles.
- `mask_restore.lua` now exists and measures the real user-visible event:
  the scanline of the PPUMASK restore at `$EEDA`, not the `rti` cycle count.
  On the current build it reports 73 frames restoring on a visible scanline
  (scanlines 37/86) over the 2,100-frame title-to-field run.

## Findings from the revision-5 attempt

### 1. F19 was wrong: upper tiles are referenced on menu screens

`PLAN.md` revision 5 proposed opening the upper pool from `game_mode` and
`text_mode` alone. That corrupts the screen. On the history and name-entry
screens the upper range `$80-$9F` is used for the window border, the menu
font and the name font. Opening the pool by mode produced garbled prompts
and a dotted border (`pp_0900` before the revert). The revision-4 rule
("the whole upper half must be unreferenced by both nametables and OAM")
is required. The nametable scan is therefore not removable.

### 2. The game copies save data over $6800-$6FFF

This is the most important discovery of the pass. A static audit said the
game's highest reference was `$6780`, but bank 13 contains an indirect
2 KiB copy (`PC $9F6B-$9F7E`, destination pointer `$10/$11`). It writes the
"5S" signature at `$6008/$6009` and copies a save slot to `$6800-$6FFF`.
Consequences:

- `KANJI_KANA_READY`, the kana font copy, the page records and all scratch
  in `$6800-$6FFF` are wiped whenever the save menu loads a slot.
- The far loader recovers (it recopies kana and reloads metadata), which is
  why revision 4 worked despite this.
- Any long-lived state in that range is not safe across save-menu screens.
  The upper save area was moved to `$7C00` and survives.

Moving long-lived state to internal RAM `$0500-$07FF` was implemented and
tested. A 6,000-frame audit of the original ROM shows those addresses are
cleared at boot and never touched afterwards. However, the relocated build
corrupted the runtime page record (wrong code_hi bytes and mixed upper/lower
tile numbers) and garbled prompts. The relocation was reverted without
isolating the exact fault; treat this as the top open investigation.

### 3. Upper save/restore could not be stabilised

Three forms were tried: per-glyph save before upload, whole-range copy at
message open, and a copy/restore state machine with a validity marker.
All of them eventually restored stale or glyph data into visible tiles
because the game's own save-data copies and CHR reloads interleave with the
message lifecycle. The revision-4 policy (borrow only unreferenced upper
tiles, zero them at exit) is back in place; it is visually correct on the
tested screens. F21 remains open.

### 4. NMI batch tuning has a hard floor

With `mask_restore.lua`:

- Revision-4 batches (8 CHR tiles, 128 nametable bytes): visible restores
  at scanline 37/86 during scan frames.
- Reduced batches (4 CHR tiles, 64 nametable bytes): visible restores still
  appear (scanline 36/11), and the 6,000-frame survey turned solid green
  (scene progression broke). The reduction was reverted.
- The 4-tile/64-byte change was likely starving `scan_wait` or the scene
  loader, not just changing timing; it needs bisecting, not guessing.

The black band on scan frames is therefore still present on this build.
It is most visible on the field map; the history screen is black there.

## Compiler/runtime changes kept

- `tools/kanji_text.py` rejects pages needing more than 13 slots and
  messages whose metadata exceeds 256 bytes.
- `meta_load` copies 256 bytes of metadata instead of 512; the build report
  shows `max_meta_bytes: 221`, so this is safe.

## Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua  --name mask_kanji
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua  --name prompt_pages
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua    --name ktown
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua  --name survey_kanji
python tools\mesen_run.py "Tenchi o Kurau (Japan) (Rev 1).nes" tools\lua\ram_audit.lua --name ram_audit
```

Outputs land in `out/test/`. Mesen runs always use a copied ROM name.

## Next steps (revised by evidence)

1. **Fix the internal-RAM relocation.** Reapply `$0500-$07FF` for the page
   record and bitmaps only, then bisect the page corruption with the
   `internal_dump.lua` probe. This is needed before any save-menu-heavy
   screen can be trusted.
2. **Keep the nametable gate.** Restore the plan from revision 4 for the
   upper pool; do not open it by mode.
3. **Measure the scan cost per byte.** 128 nametable bytes cost ~30 cycles
   each in the current loop; unroll `mark_screen_tile` or move the scan to
   a frame with no queue flush. The 4/64 experiment must be repeated with
   a longer `scan_wait` timeout and a survey check before judging it.
4. Only after 1-3: per-prompt list reservations (F20), redraw test, and
   content conversion.

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `JF-Dot-Shinonome16.ttf`

Generated `decomp/build/kanji/*.bin` files are build products (ignored).
