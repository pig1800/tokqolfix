# Current implementation status

Status after the revision-9 CHR-page pivot (2026-11-08).  The hack now runs
with 16 KiB CHR RAM in 4 KiB mode: page 0 sprites, page 1 scene, page 2 a
private text band.  The scene page is never written by the hack.  This is
a work-in-progress; the field-context queue split is not finished.

## Final build

- Original 256 KiB ROM: byte-identical,
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- Kanji 512 KiB SUROM ROM:
  `c8f61a090b33169f7ead8fccb11c8bcc0d6aae245110401017c0f55858907980`.
- Overlay: 969 bytes at `$B800`, identical in text banks 18-22; fixed-bank
  hooks 102 bytes at `$C611`.
- `bank15_lint`: 13 registered ranges, bank 31 == bank 15.
- Compiler: 760 messages, 1,190 pages, max 10 entries/page, text in banks
  18-21; `pages_over_capacity=0`.

## Gates on the final build

| Gate | Result |
|---|---|
| Original target | byte-identical |
| `bank15_lint` | 13 ranges, bank 31 == bank 15 |
| `sram_watch` | 0 hack writes among 5,491 battery-RAM writes |
| `iram_watch` | 0 foreign writes among 15,948 reserved-range writes |
| `mask_restore` | 0 PPUMASK restores on a visible scanline |
| `stack_check` | min SP `$18` at NMI, `$28` at overlay entry |
| History prompt / name entry | clean screenshots |
| Oath pages 1-3 | clean screenshots (9 pages total) |
| Four-line page | clean |

## Revision-9 design

- Header byte 11 = `$08` (16 KiB CHR RAM); `mmc1_init` control `$1E`;
  reset CHR register 1 = page 1.
- CHR page 2 is the text band: kana font in `$00-$7F`, kanji in the
  compiler-assigned low kana tiles.  The band page is filled from bank 9,
  six tiles per vblank, at the first message.
- NMI entry flushes the shared VRAM queue; the band stub selects the scene
  page for the visible top, delays to scanlines 144-146, selects the band
  page for the window, and restores the scene page.  The CHR write
  scanline was measured at 144-146.
- The overlay no longer has a dirty bitmap, kana restore, `<JUMP>` restore
  or reservation machinery.  `exit_clear`/jump hooks clear the band flag
  and restore the scene page.
- The compiler uses the proven revision-8 low-tile assignment (message
  kana + frame reservations) because the 32-glyph static cache conflicts
  with the engine's line-scroll redraw.  The oath is 9 short pages.

## Remaining work (blocking release)

1. **Field frame tiles.** The game and hack share the `$0400` queue; while
   a message is open the NMI flushes it with the band page selected, so
   field CHR updates can blank band-page frame tiles.  The split `$0500`
   hack queue was prototyped but destabilised the message flow.  It needs
   a larger fixed-bank gap or an overlay-resident NMI helper.
2. **Field QA state.** `tools/lua/town_menu.mss` is still the revision-8
   state.  Regenerate it on the new ROM (`tools/lua/town_menu_save.lua`)
   and re-run `qa_field.py`.
3. **Automated gates.** `band_switch.lua` (scanline 144-151) and
   `scene_page_check.lua` (page 1 equals the original at sampled frames)
   are not yet scripts; the manual `bandwrites` log and the field CHR
   comparison are the evidence so far.
4. **Phase 2b.** Party/item prompt tags, save slots 2/3, random-RAM
   power-on, no PRG-register bit-4 writes, second emulator.
5. **Phase 3/4.** Script/tables/menus and UI screens; proofreading.
6. **Hardware.** EverDrive N8 pass when hardware exists.  16 KiB CHR RAM
   on MMC1 is emulator-only until tested.

## Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua   --name sram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\iram_watch.lua   --name iram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\stack_check.lua  --name stack
```

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `JF-Dot-Shinonome16.ttf`

Generated `decomp/build/kanji/*.bin`, `out/qa/*` and `out/test/*` are build/QA
products.
