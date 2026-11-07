# Tenchi o Kurau (Japan) (Rev 1) — analysis and decompilation

Workspace for analyzing and modifying the Famicom game
`Tenchi o Kurau (Japan) (Rev 1).nes`.

## Decompilation

`decomp/` contains a byte-identical ASM reconstruction:

```bat
cd decomp
build.cmd
```

Expected result:

```text
size:   262160 bytes
sha256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367
OK: byte-identical to the original ROM
```

Start with [`decomp/README.md`](decomp/README.md) for the layout, coverage,
regeneration workflow, and glyph/text editing notes.

## Editable text

Dialogue banks 10/11 are extracted to:

- `decomp/text/bank10_messages.dtx`
- `decomp/text/bank11_messages.dtx`

Edit the quoted kana strings and named control tokens (`<NL>`, `<PAGE>`,
`<END>`, word/place/item references, and so on), then run
`python decomp\build.py`.  The dialogue font and the `$80-$EE`
dakuten/handakuten encoding are decoded, so most text is readable kana.
The tool rebuilds the split low/high pointer tables and updates code
references such as `b10_msg_index_036`.  See
[`decomp/text/README.md`](decomp/text/README.md).

## Execution plan

[`PLAN.md`](PLAN.md) is the phased execution plan for the full kanji+kana
conversion (SUROM expansion, font pipeline, renderer, text relocation, script
proofread, UI screens, QA), with per-task exit criteria.

The current implementation state is tracked in [`STATUS.md`](STATUS.md) and
[`CHANGELOG.md`](CHANGELOG.md).  The expanded target is built with:

```bat
python decomp\build.py --target kanji
```

It writes `decomp/build/rom_kanji.nes` (524,304 bytes) and leaves the original
256 KiB target byte-identical.  The revision-6 runtime is ROM-resident in text
banks 18-22, uses no battery RAM and has no NMI PPU work.  Revision 7 fixes
multi-page text; revision 8 restores stale CHR at message open and `<JUMP>`
exit and reserves measured scene tiles per message, so field/shop/menu
contexts no longer show kanji fragments.  See `STATUS.md` for the verified
gates and the remaining Phase-2b/3 work.

## Handoff / expansion plan

[`HANDOFF.md`](HANDOFF.md) is a self-contained planning handoff covering the
verified byte-identical build, the 718-kanji inventory, the SUROM 512 KiB
expansion path, CHR RAM limits, EverDrive N8 constraints, and a phased
implementation plan.  Use it as the source of truth for the next planning
model.

## Current analysis

[`ANALYSIS.md`](ANALYSIS.md) contains the kanji+kana feasibility study:
the dialogue engine, the status-screen 16×16 kanji display, font/CHR budgets,
and the recommended implementation paths.

## Main artifacts

- `decomp/` — routine-oriented assembler source, build/verify script, Mesen labels
- `assets/` — editable PNG tile/font resources plus exact binary data blocks
- `decomp/text/` — editable `.dtx` message scripts and text format notes
- `decomp/FUNCTIONS.md`, `decomp/BANKS.md` — routine index and bank/resource map
- `tools/decompile.py` — CDL-seeded source generator
- `tools/symbols.py` — routine names, comments, hardware/RAM symbols
- `tools/assets.py` — PNG ⇄ NES tile conversion and round-trip verification
- `tools/text.py`, `tools/textdata.py` — extract/compile/verify editable message text
- `tools/ghidra_scripts/SeedExport.java` — Ghidra/REA function export helper
- `out/rea/` — Ghidra function/decompilation exports used for naming
- `tools/cdl_summary.py`, `tools/merge_cdl.py` — CDL inspection/merging
- `tools/cdl_*.lua` — Mesen test-runner CDL capture scripts
- `out/` — screenshots, CHR/PPU/RAM dumps, and CDL captures

## Save-file warning

Mesen keys battery saves by ROM display name. Use a **copied ROM filename**
(e.g. `out/cdlprobe/tokqol_cdl.nes`) for test-runner sessions so the original
`D:\EMU\NES\Saves\Tenchi o Kurau (Japan) (Rev 1).sav` is not overwritten.
