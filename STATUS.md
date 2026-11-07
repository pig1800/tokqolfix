# Current implementation status

Status after the revision-3 pass (2026-11-07), following `PLAN.md`.
This file records what is verified, what is still broken, and the next
engineering step.

## Verified

- `python decomp/build.py` still produces the original 256 KiB ROM:
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- `python decomp/build.py --target kanji` produces the 524,304-byte SUROM ROM
  (current SHA-256 `ce583c7f72066119b794f3001b817e7923c71addc810ecd9e07da1cd1059c82f`).
- Bank 31 is byte-identical to patched bank 15; `tools/bank15_lint.py`
  enforces this and 15 registered patch ranges.
- The overlay is 2,247 bytes at `$7002-$78C8`; the far loader copies 3,072
  bytes from bank 24. The fixed-bank hook block is 91 bytes and the far block
  is 181 bytes.
- The NMI entry now reads `PPUSTATUS` before any CHR work, then runs a bounded
  job runner (upload, CHR scan, nametable scan, dirty restore) and jumps back
  into the original handler. A 6,000-frame scene run shows no NMI re-entry and
  no stack growth.
- Page records are compact: `count`, a 16-byte used-tile bitmap, then
  `count * (code_lo, code_hi)`. The overlay scans CHR for resident kana and
  the visible nametable for tiles already on screen, then allocates four
  distinct resident, text-unused, non-visible tiles per kanji. Duplicate tile
  allocation was found and fixed.
- The history-selection prompt now renders as one page:
  `どの歴史書を登録しますか?` with the 1-3 menu above it
  (`out/test/pp_0900.png`). The name-entry grid after selection is clean
  (`out/test/pp_1100.png`, `out/test/pp_1800.png`).
- The field command menu is clean after the message-exit restore: はなす /
  しらべる / たいねつ / ふじょう / どうぐ (`out/test/survey_6000.png`).
- The field map tiles are intact through frame 6,000
  (`out/test/survey_4320.png`).
- `text_redraw_lines` is routed through a hook that re-uploads page glyphs
  whose CHR tiles were restored.
- `kana_prepare` is installed at the six bank-15 `jsr text_put_tile` sites and
  the two bank-13 name-list sites; kana draws restore a stolen tile on demand.
- Scene survey on the original ROM (60-frame CHR dumps to 6,000):
  the oath scene overwrites exactly kana `$42-$5B` (26 tiles); a town/field
  transition briefly overwrites `$00-$17` (23 tiles) and restores them. The
  worst measured borrowing is 26 tiles, recorded as
  `SCENE_BORROW_ALLOWANCE` in `tools/kanji_text.py`.
- A write watchpoint over `$6800-$7FFF` for 6,000 frames shows every write
  comes from the RAM far loader (`$0600-$06FF`) or the RAM overlay
  (`$7002-$7FFF`).
- `python decomp/build.py --target kanji` still passes the original-bank
  checks: only banks 10, 11, 13 and 15 differ from the base game.

## Current blockers

### 1. Runtime save-slot names still collide with prompt kanji

The history slot menu displays a save-slot name and `L64`. The name is drawn
from save data and may use any kana tile. The prompt's kanji allocation cannot
see that name before the menu is drawn, so the menu overwrites one or more
kanji tiles. `out/test/ktown_1100.png` shows the prompt as
`どの歴史書 始 をメロめますか?` and the slot line as `1 くわO L64` while the
choice menu is open.

The nametable scan cannot fix this because the slot menu is drawn *after* the
prompt opens. Options for phase 3/4:

1. Convert the slot menu to the kanji-aware drawer and give it its own
   reserved slots (preferred).
2. Allocate prompt kanji from the upper 128 CHR tiles when they are blank,
   keeping all lower kana tiles untouched for runtime names. This needs a
   32-byte resident/blank/dirty map and a restore-to-zero path for upper
   tiles.
3. Decode the displayed save-slot name at message open and reserve its exact
   tiles. This is fragile but small.

### 2. Redraw re-upload is installed but not scripted-tested

The hook at `$D388` re-uploads page entries whose tiles are resident again.
No current test message scrolls the four dialogue lines, so this path has not
been exercised by a screenshot test yet.

### 3. Unconverted inline scripts and tables

The intro/oath lines, several town/event lines, word/place/item tables and
runtime names still render kana because they are inline bank-15/bank-13
scripts or table records, not indexed messages. These are PLAN.md phase 3
tasks.

### 4. Scan cost at message open

The CHR scan (8 tiles/frame) and the 1 KiB nametable scan (64 bytes/frame)
run together, so a message open pays roughly 16 frames before text starts.
The current screenshots show no visible glitch; measure on hardware before
tightening or caching the result per scene.

## Commands

```powershell
# Original, byte-identical
python decomp\build.py

# Expanded kanji target + fixed-bank lint
python decomp\build.py --target kanji

# Headless Mesen checks
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\boot_check.lua --name kanji_boot
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua --name prompt_pages
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua --name survey_kanji
python tools\mesen_run.py "Tenchi o Kurau (Japan) (Rev 1).nes" tools\lua\scene_survey.lua --name survey_orig
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua --name kanji_sram_watch
```

Outputs land in `out/test/`. Mesen runs always use a copied ROM name.

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `DotGothic16-Regular.ttf`

The generated `decomp/build/kanji/*.bin` files are build products and are
ignored by git.
