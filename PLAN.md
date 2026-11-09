# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 14, 2026-11-08.  The revision-10 design (private band page,
sprite-0 switch, hack bank, no RAM code) is implemented and gated by the
planner (revision 11), and revision 12 fixed the revision-11 play-test
report (prompt and oath garbled until the band went live); revision 13
restored the area palettes (white town exterior); revision 14 replaced
the text with an Opus re-conversion laid out by program, with page flips.  `STATUS.md` is the reference for the runtime as built; this file
lists what the executor does next.  Target: emulator (Mesen) first; the
hardware caveat in section 4 stands.  Revision 21 moved the target to
MMC3 and replaced the sprite-0 switch with the MMC3 scanline IRQ.

---

## 1. What changed from the revision-10 WIP (do not reintroduce)

| Revision-10 WIP | Defect | Revision 11 |
|---|---|---|
| `jsr nmi_entry` on the OAM DMA (`$EE93`) | +22 cycles before the game's raster splits: opening logo artifact | NMI hooks only at `$EF0B` (after the `nmi_mode` branch, jumped to) and `$EF31` (epilogue) |
| Overlay full CHR copy and glyph pre-upload with NMI off | VRAM written while rendering: history screen garbled | Overlay never touches the PPU; NMI does one measured unit per light frame |
| Pre-upload of every page's glyphs at message open | Later pages overwrote earlier pages' slots | Upload on demand per page entry |
| `text_dispatch` jumping to the kanji handler | No X push, no code high byte | Revision-8 dispatcher |
| Release of kanji at message end | Prompt turned to garbage while still shown | Slots stay active until the next message or page start |
| Carry rule "next 3 lines" | Kept kanji collided with the next page's kana (oath last page) | Next pages that start while the lines are visible, fully reserved |
| Rev 11: only glyph uploads allowed when the game queued bytes | Sprite-0 tile waited for an idle queue: band off while the first line printed (prompt/oath garbled) | Any unit in light frames, sprite tile first; units re-measured |
| Rev 11/12: hook code in `$C611-$C676` | That range is the area palette table: towns kept the default palette (white exterior) | Tables moved to the hack bank, `load_text_graphics` rewritten in place |
| Rev 11: block-writer hook calls the hack bank twice inside the NMI | CHR-animation NMI overran vblank (scroll restore at scanline 268) | NMI path selects page 1 in the fixed bank; tiles marked from `$39` |

Rules that every change must keep:

1. No added cycle before the game's split-screen code in `nmi_mode != 0`
   frames.  Check: opening frames 11-301 pixel-identical to the original
   (3-frame boot offset since revision 21, every frame compared), split-write dots identical.
2. No hack `$2006/$2007` access while rendering.  Check: `r11_diag.lua`
   reports 0, `vblank_deadline.lua` reports 0 accesses after the pre-render
   line start, and `anim_timing.lua` keeps the game's own scroll/mask
   restore before scanline 261.  Any new or longer unit must be measured
   from the hook entry against the latest light-frame entry (254.7).
3. Page 2 equals page 1 for every tile shown below the window border,
   except active kanji.  Check: `band_check.lua`.
4. No kana written over an active kanji tile.  Check: `band_check.lua`.
5. Stack never below `$010B` (`$0104-$010A` is game scratch).  Check:
   `ram_gate.lua` (now `$0110`) and `taint_check.lua` from the battle-entry
   states (revision 18: an NMI in the game's bank-switch lock window adds
   its lock path on top of hack code; keep hack frames shallow there).
6. Hack state only in `$0131-$017F` and `$0100-$0103`; no battery-RAM
   writes.  Spare bits in use: `KANJI_WIN_COL` bits 6-7, `KANJI_PAGES_LEFT`
   bit 6.  Check: `ram_gate.lua`.
7. No visible garble on any input timing.  Check: `tools/garble_run.py`
   (six offsets at least) reports 0 garbled frames.
8. No fixed-bank byte is reused unless every code reference to it is
   accounted for (decomp sources, pointer tables, indexed tables); read
   coverage on a test path is not proof (revision 13: the "gap" at
   `$C611-$C676` was the area palette table; revision 16c: the "zero
   padding" at `$E6B3-$E6C3` was part of the battle damage tables, read by
   undecoded bank-14 code).  Scan every code bank for jumps and indexed
   reads into a candidate range; zeros are data until proven otherwise.
   The game's RAM is the same: `$0100/$0101` are game variables.  Check:
   `palette_check.py`, `bank15_lint.py`, the hash checks in
   `kanji_build.py`, and `taint_check.lua` from battle and menu states.
9. Text-time code changes no game zero page the original engine leaves
   alone: scripts keep values in the math temps across a message
   (revision 15b: the inn price in `$10-$12`).  The overlay borrows
   `$10/$11` only between waits and puts them back.  Check:
   `zp_check.lua`.
10. Kanji never borrow the kana of a menu that can be on screen with the
    message: menu code keeps its window beside the text window, on the
    band page, while it prints (revision 16: the partner shop).  The
    compiler derives each message's menus from the original code
    (`menu_context_tiles`).  Check: `menu_context_conflicts` in the
    compiler report (the build fails), and `tools/lua/garble_state.lua`
    from a save state in a menu.
11. Everything the band switch depends on must hold for the frame being
    drawn.  The IRQ arm (`irq_arm`) reads `scroll_y` and the window row
    in the NMI of that frame, after the frame's last PPU access and before
    the pre-render line's clock (the MMC3 counter also counts the A12
    rises of vblank VRAM traffic): no PPU access may follow it, and any
    NMI work added before it must keep frames with at most
    `IRQ_ARM_MAX` queued bytes ahead of that clock.  Interrupt code that
    writes `$8000` leaves with `$8000 = MMC3_SEL | $80`; main-thread code
    stores `MMC3_SEL` before every `$8000` write.  Check: `band_check.lua`
    (switch minus band top), `garble_state.lua` from battle and menu
    states, including `kanji_left`.
12. Scene-page tiles the hack writes (the battle pool) must be read back
    unused before use and guarded against every game write path; a game
    path the hack cannot see (direct `$2007` loops) must be followed by a
    graphics-set load, which re-checks.  The engine's row buffer marks its
    end codes with bit 7: any tile at `$80` or above needs `render_ctl`,
    and the scroll copy (`$D416`) keeps cells below `$FA`.  Pool slots are
    chosen from what the window's rows show, never from remembered state.
    Check: `pool_outside` / `pool_*` in the garble gates from battle states.
13. Text that game code prints itself (`lda #imm / jsr text_put_tile`)
    is invisible to the compiler.  The scan of banks 0-15 finds two such
    tails in message helpers (`$D549`, `$D565`), compiled as a troop pick
    and a back-up over the tail.  A new `<CALL:xxxx>` in the text needs the
    same scan of its helper.

---

## 2. Next work for the executor (ordered)

1.9 **Text workflow.**  Edit `decomp/text/kanji_r14/batch_NN.txt` (keep `|` phrase
    marks, `▼` at sentence ends), run `python -I tools/reconv_check.py` on
    the file, then `python -I tools/kanji_layout.py` and the build.  Review
    `out/reconv/layout_report.txt` (waits inside sentences) and the
    compiler's `split_pages` in `kanji_text_report.json`.
2.0 **Gate upkeep.**  After any `hack.asm` change run
    `tools/lua_addrs.py` on the gates that hook hack addresses, then the
    whole gate set (STATUS.md, Commands).  Extend `garble_check.lua`'s
    input path (shops, battles, castle) as coverage grows; it is the gate
    that catches what the user sees.
2.1 **QA harness for the band page.**  `qa_pages.py`, `qa_field.py` and
    `qa_sweep.py` check CHR through PPU memory, which is page 1 now.  Rework
    their tile checks to read CHR RAM page 2 (`emu.memType.nesChrRam`,
    offset `$2000`) for cells below the window border, and add the
    `band_check.lua` checks per warped message.  `message_locations` in
    `qa_sweep.py` already reads the revision-11 metadata.  Regenerate
    `tools/lua/town_menu.mss` with `town_menu_save.lua` on the current ROM.
    Gate: all 872 indices, zero failures.
2.2 **Coverage.**  Save states and scripted paths for: a battle with
    messages, a shop, a castle audience, the officer scene (`nmi_mode =
    $80`, split + palette changes), save slots 2/3, the two relaxed
    messages (`b11_msg_161`, `b11_msg_203`).  Run `band_check.lua` and
    `r11_diag.lua` on each.  Gate: rules 1-6.
2.3 **Power-on robustness.**  Random RAM fills (`$00`, `$FF`, random) at
    power-on; reset during a message.  Gate: rules 1-6, no hang.
2.4 **Second emulator.**  FCEUX or Nestopia with the MMC3 build (NES 2.0
    CHR-RAM size 16 KiB); record whether they honour the size and where
    their MMC3 IRQ lands (`band_check.lua` switch minus band top).
2.5 **IRQ arm in heavy frames.**  Frames with more than `IRQ_ARM_MAX`
    queued bytes keep the IRQ's own re-arm (1-4 lines early on the
    standard path).  If a play-test shows a kanji or stale tile above a
    window while it is drawn or erased, arm those frames from a measured
    estimate of the game's flush time instead.
2.6 **Phase 3/4** content and proofreading as before.

---

## 3. What remains for the user

- Play-test the current build `3610a067...` (`decomp/build/rom_kanji.nes`):
  history select and name entry, the opening logo, the oath and the first
  town.  Save a Mesen state at any glitch into `out/user/`.
- Outside battle, a message that continues an open window starts on a
  cleared window; in battle the window scrolls as in the original.
- The build is MMC3 now: old Mesen states of the SUROM build need
  `python -I tools\mss_to_mmc3.py <old.mss> <new.mss>` (load the new
  file with Mesen's "Load State From File"); the battery save works as is.
- Do not distribute builds yet.

---

## 4. Hardware caveat (revision 21)

The build is MMC3 with 16 KiB CHR RAM (NES 2.0).  Nintendo's MMC3
CHR-RAM boards (TGROM/TNROM) have 8 KiB, and the band's 2 KiB cannot
share the sprite page (the game shows sprite tiles `$80-$CF` and writes
sprite CHR `$0800-$0FFF`).  Emulator-only until a board with more CHR
RAM; the IRQ timing is measured in Mesen only.

---

## 5. Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji
python tools\bank15_lint.py

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\band_check.lua --name band
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\r11_diag.lua   --name diag
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\ram_gate.lua   --name ram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\vblank_deadline.lua --name dead
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\anim_timing.lua --name anim
python tools\garble_run.py decomp\build\rom_kanji.nes --offsets 0,5,11,19,29,40
python tools\palette_check.py
python -I tools\mss_to_mmc3.py <SUROM state.mss> <MMC3 state.mss>
sh tools/run_gates.sh        # every gate, states from out/user/m3 (GDIR=, TAG=)
```

Always use a fresh `--name` per ROM variant: Mesen keys the battery save on
the ROM file name.
