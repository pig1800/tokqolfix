# Tenchi o Kurau (Japan) (Rev 1): decompilation and kanji edition

A byte-identical assembler reconstruction of the Famicom game
`Tenchi o Kurau (Japan) (Rev 1).nes`, and a 512 KiB MMC3 build of it that
shows the game's text in kanji.

The ROM is not in this repository, nor is any data taken from it.  Put
your own copy (sha256 `40f19e17...`, below) at the repo root under that
name, then extract the game's graphics and data blocks once:

```sh
python tools/assets.py export
```

## Builds

```sh
python decomp/build.py                  # the original, 256 KiB
python decomp/build.py --target kanji   # the kanji edition, 512 KiB
```

The original build must stay byte-identical:

```text
size:   262160 bytes
sha256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367
OK: byte-identical to the original ROM
```

The kanji edition is `decomp/build/rom_kanji.nes` (524,304 bytes: mapper
4, NES 2.0, 16 KiB CHR RAM, four-screen nametables, battery RAM).  Its
build also lints the fixed bank (`tools/bank15_lint.py`) and regenerates
`MEMORY_MAP.md`.  It needs Python 3 with Pillow and fontTools.

## Documents

- [`STATUS.md`](STATUS.md): the kanji edition as built.  It covers the
  layout, the runtime, how to edit the text, the tools, the tests and
  the known limits.
- [`TEXT_RENDERER.md`](TEXT_RENDERER.md): the design log of the kanji
  runtime (the map renderer, the kanji store, the boot screens, the oath,
  the message engine, the RAM code's move), newest last.
- [`MEMORY_MAP.md`](MEMORY_MAP.md): every PRG region of the current build,
  generated.
- [`decomp/README.md`](decomp/README.md): the reconstruction (layout,
  regeneration from the CDL, glyph and text editing).
- [`decomp/text/README.md`](decomp/text/README.md): the message format and
  tokens.
- [`assets/README.md`](assets/README.md): the exported graphics.

## Text

- The kanji edition's text is in `decomp/text/kanji_plan/bank10_messages_kanji_r14.dtx`
  and `bank11_messages_kanji_r14.dtx`.  Edit those and run the kanji build.
- The original game's kana text is in `decomp/text/bank10_messages.dtx`
  and `bank11_messages.dtx`.  Edit those and run the original build.

## Save-file warning

Mesen keys battery saves by ROM file name.  Run tests on a copied ROM name
(`tools/mesen_run.py` does this) so the game's own
`Saves\Tenchi o Kurau (Japan) (Rev 1).sav` is never touched.
