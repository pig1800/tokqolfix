# Current implementation status

Status after the revision-2 pass (2026-11-07), following `PLAN.md`.
This file records what is verified, what is still broken, and the next
engineering step.

## Verified

- `python decomp/build.py` still produces the original 256 KiB ROM:
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- `python decomp/build.py --target kanji` produces the 524,304-byte SUROM ROM.
- Bank 31 is now byte-identical to patched bank 15; `tools/bank15_lint.py`
  enforces this and the registered patch ranges.
- The text-engine overlay runs from battery PRG RAM at `$7002-$73FF`. It is
  installed from bank 24 by the far loader when the `$7000` signature is
  wrong; NMI hooks are signature-guarded stubs in the `$C611` gap.
- The far trampoline is `F8 3A C6`, so the text engine takes the
  `set_bank_current` path and no longer clobbers `current_bank_a`.
- The page-record handler, four-tile expansion and NMI CHR upload are fixed:
  tile0..tile3 map to TL/TR/BL/BR, and each quadrant gets its own 2bpp tile.
- A real converted message page renders in Mesen with legible kanji:
  the history-selection prompt reads `どの歴史書を登録しますか?`
  (`out/test/kanji_prompt_640.png`, `out/test/kanji_prompt_900.png`).
- The prompt still renders when `$6800-$7FFF` is filled with deterministic
  random values before boot, so the overlay/kana signatures work on a fresh
  cartridge.
- A write watchpoint on `$6800-$7FFF` across a 6000-frame run shows no writes
  from base-game code; only the RAM far loader (`$0600-$06FF`) and the overlay
  (`$7002-$73FF`) touch that range.
- `kanji_text_report.json` now records `reserved_count`, `max_page_slots`,
  `min_free_after_allocation`, `max_meta_bytes` and the reserved tile list;
  the compiler raises if a message metadata record exceeds 255 bytes.

## Current blockers

### 1. Town map CHR is overwritten by the kanji cache

In the field/town screen the map nametable references almost every tile in
`$00-$7F` as well as all of `$80-$FF`. The compiler allocates kanji slots from
tiles the *text page* does not use, so it still overwrites visible map tiles.
Restoring those tiles from the kana font is wrong: their original contents are
map graphics, not kana.

The next engineering step is a CHR save/restore layer:

1. Lazy-save each 16-byte CHR tile before the first kanji upload writes it
   (from the NMI handler, during vblank) into `$7400-$7BFF`.
2. At message exit, restore saved tiles that are no longer referenced by the
   nametable or the `$0180/$0300` text buffers. Keep tiles that are still
   visible so a prompt remains legible while a choice menu is open.
3. Choose cache slots from tiles not referenced by the nametable at page
   start, so the map is not visibly corrupted *during* the message either.

The `restore_all` routine and the `$D1FA` hook from revision 2 were removed
from the active build because restoring at message exit erased kanji that were
still visible on the history prompt. The routine remains in the overlay for
the next attempt.

### 2. Visible line redraws do not re-upload kanji

`text_save_tiles` copies the tile numbers to `$0180`; a later window redraw
copies them back without invoking the kanji handler. If the CHR tiles were
reused by another page, the redraw shows stale glyphs. The CHR save/restore
layer plus an explicit re-upload on redraw is required.

### 3. Unconverted inline scripts and tables

The intro/oath lines and several town/event lines still render kana because
they are inline bank-15/bank-13 scripts, not indexed messages. Table strings
and runtime names are still kana. These are PLAN.md phase 3 tasks.

## Commands

```powershell
# Original, byte-identical
python decomp\build.py

# Expanded kanji target + fixed-bank lint
python decomp\build.py --target kanji

# Headless Mesen checks
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\boot_check.lua --name kanji_boot
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\trace_message.lua --name kanji_message
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\trace_message_random.lua --name kanji_random
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua --name kanji_sram_watch
```

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `DotGothic16-Regular.ttf`

The generated `decomp/build/kanji/*.bin` files are build products and are
ignored by git.
