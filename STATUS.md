# Current implementation status

Status after the revision-6 pivot (2026-11-07). The RAM-resident runtime and
all battery-RAM use are gone. The text engine is ROM-resident in the text
banks and uses only the internal-RAM ranges the original game leaves alone.

## Verified

- `python decomp/build.py` produces the original 256 KiB ROM byte-identical:
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- `python decomp/build.py --target kanji` produces the 524,304-byte SUROM ROM:
  `b1e33ab17ad4b41d4a1c6c34386aec0679b36eed3f7df149f2a71857b447bb4c`.
- Banks 0-14 are byte-identical to the original (bank 13 is no longer patched).
  Bank 31 is byte-identical to patched bank 15. `tools/bank15_lint.py` passes
  with 7 registered patch ranges.
- Overlay: 1,042 bytes at `$B800`, byte-identical in text banks 18-22.
  Fixed-bank gap block: 94 bytes at `$C611-$C66E`.
- `tools/lua/sram_watch.lua`: 0 hack writes to `$6000-$7FFF` over 21,923
  game SRAM writes in the 6,000-frame run.
- `tools/lua/iram_watch.lua`: 0 foreign writes to `$0131-$017F` or
  `$01E0-$01E7` over the same run. Only the overlay (`$B800-$BFFF`), the RAM
  stub (`$0140-$015F`) and the fixed-bank trampoline (`$C63A-$C675`) write
  those ranges.
- `tools/lua/mask_restore.lua`: **0** frames with a visible-scanline PPUMASK
  restore. There is no NMI PPU work in the kanji target.
- `tools/lua/stack_check.lua`: minimum SP is `$18` at NMI entry and `$28` at
  overlay entry; the reserved state starts at `$0131` (SP `$31`), so the live
  stack stays below it.
- Prompt/name-entry screens are clean: `pp_0900` shows
  `どの歴史書を登録しますか?`, `pp_1600` shows the full name-entry grid.
  `ktown_1100` shows `どの歴史書を始めますか?` with the slot and speed menus.
- Field message `b10_msg_129` renders kanji+kana over the map; its nametable
  rows and map tile numbers are identical to the original. The map palette
  differs because the palette animation is at a different phase; this is not
  a tile/nametable change.
- The 6,000-frame `scene_survey.lua` run completes without a hang or NMI
  re-entry.

## Revision-6 architecture

### Code and data

| Range | Contents |
|---|---|
| `$C611-$C639` | SUROM `write_prg_bank` replacement |
| `$C63A-$C65D` | `F8 3A C6` trampoline: maps bank 10/11, reads five inline bytes, maps the text bank, enters `$B800` |
| `$C664-$C669` | `cell_check` for tiles `$00-$F9` |
| banks 18-22 | text data + page records below `$B800`; overlay at `$B800-$BFFF` |
| banks 16-17 | 718-kanji 1bpp font source |
| banks 10/11 | original pointer tables + 8-byte `F8 3A C6` stubs |

Patch ranges (7): `$C4B7`, `$C611-$C675`, `$D1FA`, `$D28E`, `$D2BB`,
`$D2C7`, `$DBE7-$DBEA`. No bank-13 patch, no NMI patch, no signature check,
no `$0600` loader.

### Internal RAM

| Range | Contents |
|---|---|
| `$0131-$013F` | text bank, text address, page pointer, code, page count, entry index, four tiles, uploaded flags |
| `$0140-$015F` | RAM font-copy stub, installed at each message open |
| `$0160-$016F` | one 16-byte half-glyph / 8-byte kana row |
| `$0170-$017F` | 16-byte dirty-CHR bitmap |
| `$01E0-$01E7` | source bank/count, scratch, saved X, upload index |

Battery PRG RAM is never written by the hack.

### Page records

```
message metadata:  pages byte
per page:          count byte, count * (code_lo, code_hi, t0, t1, t2, t3)
```

The trampoline points at the metadata; the overlay keeps a page pointer and
advances it on `$FC`. A 16-bit uploaded bitmap suppresses duplicate glyph
uploads within a page. A 16-byte dirty bitmap tracks every tile holding a
kanji; `kana_prepare` restores a kana tile before page reuse, and
`restore_exit` restores all non-visible dirty tiles at message exit.

### Static tile assignment

- The compiler reserves permanent frame/cursor/digit tiles, the page's own
  kana/table/name insertions, a per-message scene-borrow set and (for prompts)
  the list set.
- `scene_borrow.tsv` is generated from `scene_borrow_kanji.lua` captures and
  consumed by the build. Surveyed labels: 9. The oath scene borrows
  `$42-$5B`; the history prompts, name entry and the tested field messages
  borrow none.
- Unsurveyed messages fall back to the 26-tile worst case.
- Prompt list tags: `menu` (63), `savename` (7, history prompts). The
  `savename` set is the exact 65-tile name-entry charset extracted from the
  original PPU nametables.
- Page entries are capped at 16 (runtime uploaded bitmap); current maximum is
  11. `min_free_static = 4`; `pages_over_capacity = 0`.

## Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua    --name sram_watch
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\iram_watch.lua    --name iram_watch
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua  --name mask
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\stack_check.lua   --name stack
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua  --name prompt
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua    --name town
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua  --name survey
```

Survey capture (optional, for new scenes):

```powershell
python tools\make_survey_rom.py
python tools\mesen_run.py out\test\survey_noupload.nes tools\lua\scene_borrow_kanji.lua --name borrow
python tools\make_scene_borrow.py   # writes decomp/text/kanji_plan/scene_borrow.tsv
```

Outputs land in `out/test/`. Mesen runs always use a copied ROM name.

## Remaining work

1. **Phase 2 QA sweep.** Open every message index, assert no assigned tile is
   referenced by the nametable outside the window, every kana tile used by the
   page still holds its glyph, and PPUMASK restores never land on a visible
   scanline. The first two need a Mesen script that walks the message index and
   a save state/warp mechanism; the third is already 0.
2. **Per-prompt field-list tags.** The current heuristic tags every
   question-ending message `menu`; prompts followed by party/item/officer
   lists should use the smaller specific set. The history prompts already use
   `savename`.
3. **Scene-borrow coverage.** Extend the scripted playthrough so more labels
   have surveyed borrow sets; currently 9 labels are covered and the rest use
   the 26-tile fallback.
4. **Outer-bank / hardware checks.** Run with both SUROM outer bits, the
   EverDrive N8, and saves in all three history books.
5. **Content conversion.** Inline bank-15/13 scripts, WORD/PLACE/ITEM tables
   and name records; then phase 3/4 UI screens and the BPS release.

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/scene_borrow.tsv`
- `JF-Dot-Shinonome16.ttf`

Generated `decomp/build/kanji/*.bin` files are build products (ignored).
