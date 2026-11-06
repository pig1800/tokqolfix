# Current implementation status

This file records the state of the kanji-target work after the 2026-11-07
implementation pass. It is intentionally honest about what is verified and
what is still broken.

## Verified

- `python decomp/build.py` still produces the original 256 KiB ROM:
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- `python decomp/build.py --target kanji` produces a 524,304-byte ROM.
- The kanji ROM boots in Mesen and reaches the title/menu screens.
- The SUROM outer-bank switch (CHR bank 0 bit 4) works; synthetic tests
  confirmed bank 16-31 selection and the bank-31 mirror.
- The extended `$EC-$EE` dispatcher reaches the kanji handler.
- The far-text trampoline, SRAM metadata copy and page-slot lookup work.
- Glyph fetch, 1bpp -> four-tile expansion and NMI CHR upload work (verified
  with Mesen execution traces and CHR dumps).
- The 16x16 glyph bitmaps in the dialogue tile buffers are produced correctly
  (`$0300/$0318` two-cell writes).

## Current blocker

The runtime writes kanji quadrants into kana-font tiles that the current page
does not use. That is valid for text, but the game's window/menu drawing code
does not know those tiles were overwritten. After a dialogue, menu and window
graphics can therefore show kanji fragments (dotted borders / garbage) until
the kana font is reloaded.

The next engineering step is to stop sharing the kana/UI tile range:

1. Prefer the plan's original $1800-$1FFF cache window, or
2. Fully restore the 128-tile kana/window font whenever a non-text screen is
   drawn, or
3. Move the text window to a pattern-table split and keep kana/UI untouched.

Option 2 is the smallest change: add a call to a "restore kana font" routine
from the screen/window drawing paths, using the 1 KiB SRAM font copy that the
far loader already creates.

## Other incomplete work

- Inline bank-15 menu scripts (`$E94D`, `$ED50`) are still kana and have no
  page metadata.
- The 4 over-dense pages from the draft are split automatically by the
  compiler; the resulting script has not been proofread.
- Table strings and runtime names are still kana.
- UI screens from PLAN.md phase 7 are not converted.
- `tools/bank15_lint.py` and the full 872-message screenshot test from
  PLAN.md phase 8 are not implemented yet.

## Commands

```powershell
# Original, byte-identical
python decomp\build.py

# Expanded kanji target
python decomp\build.py --target kanji

# Headless Mesen helper
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\boot_check.lua --name kanji_boot

# Regenerate font + text resources only
python tools\kanji_font.py build
python tools\kanji_text.py build
```

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `DotGothic16-Regular.ttf`

The generated `decomp/build/kanji/*.bin` files are build products and are
ignored by git.
