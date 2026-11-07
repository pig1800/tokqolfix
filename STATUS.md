# Current implementation status

Status after the revision-4 pass (2026-11-07), following `PLAN.md` revision 4
plus the font change to JF-Dot-Shinonome16. This file records what is
verified, what is still broken, and the next engineering step.

## Verified

- `python decomp/build.py` still produces the original 256 KiB ROM:
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`.
- `python decomp/build.py --target kanji` produces the 524,304-byte SUROM ROM
  (current SHA-256 `862d7f377d11050e3eb0f4b4118b6267140cf4d3705bbb913f596bd47d78d6bb`).
- Bank 31 is byte-identical to patched bank 15; `tools/bank15_lint.py`
  enforces this and 17 registered patch ranges.
- The font is built from `JF-Dot-Shinonome16.ttf`; at size 16 it rasterises
  to pure 0/255 pixels for all 718 inventory glyphs, so strokes stay one pixel.
- The overlay is 2,981 bytes at `$7002-$7BA6`; the far loader copies 3,072
  bytes from bank 24. The fixed-bank hook block is 97 bytes and the far block
  is 181 bytes.
- The NMI entry reads `PPUSTATUS` before any CHR work, then runs a bounded
  job runner (upload, CHR scan, nametable scan, upper/lower restore) and jumps
  back into the original handler. A 6,000-frame scene run shows no hang and no
  NMI re-entry.
- Page records are compact: `count`, a 16-byte used-tile bitmap, then
  `count * (code_lo, code_hi)`. At page start the overlay allocates four
  distinct tiles per kanji, trying unreferenced upper tiles `$80-$F9` first,
  then resident, text-unused, non-visible lower kana tiles.
- The upper pool is opened only when neither nametable and no OAM sprite
  references an upper tile. It is not required that upper CHR be blank:
  the game's upper half holds menu/name-font graphics at the history screen.
  Tiles borrowed there are restored to zero at message exit, and the pool is
  closed on map/portrait screens so those keep their CHR.
- The history prompts render as one page with the menu still open:
  `どの歴史書を登録しますか?` (`out/test/pp_0900.png`) and
  `どの歴史書を始めますか?` with the slot line `1 <けず L64` and the
  はやい / ふつう / おそい menu (`out/test/ktown_1100.png`,
  `out/test/ktown_1240.png`). The previous save-slot/kanji collision is gone.
- The name-entry grid after selection is clean
  (`out/test/pp_1100.png`).
- The field command menu is clean after the message-exit restore: はなす /
  しらべる / たいねつ / ふじょう / どうぐ (`out/test/survey_6000.png`).
- The field map tiles are intact through frame 6,000
  (`out/test/survey_4320.png`, `out/test/survey_6000.png`).
- `text_redraw_lines` is routed through a hook that re-uploads page glyphs
  whose CHR tiles were restored.
- `kana_prepare` is installed at the six bank-15 `jsr text_put_tile` sites and
  the two bank-13 name-list sites; kana draws restore a stolen tile on demand.
- The lower CHR scan and the 2 KiB nametable scan (`$2000-$27FF`, 128 bytes
  per frame) now alternate frames, so one NMI never pays for both. The CHR
  scan reads eight tiles per frame; a message open takes about 32 frames.
- NMI duration measured in Mesen over a 2,100-frame title-to-town run:
  baseline original auto max 10,132 cycles / average 2,786; kanji ROM max
  15,833 cycles / average 3,430. The longest handlers are scan frames; they
  run with rendering disabled and the main thread is waiting, so no visible
  glitch appeared in the 6,000-frame survey.
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

### 1. Redraw re-upload is installed but not scripted-tested

The hook at `$D388` re-uploads page entries whose tiles were restored. No
current test message reliably scrolls four dialogue lines, so this path has
not been exercised by a screenshot test yet.

### 2. Unconverted inline scripts and tables

The intro/oath lines, several town/event lines, word/place/item tables and
runtime names still render kana because they are inline bank-15/bank-13
scripts or table records, not indexed messages. These are PLAN.md phase 3
tasks.

### 3. Field prompts still fall back to lower kana tiles

On map/portrait screens the upper pool is closed, so prompt kanji use lower
tiles. Menus drawn after the prompt can still collide with those tiles. A
compiler union of `menu ∪ party_name ∪ item_name` was tried but could not fit
even after 20 page splits, so it is not enabled. The remaining options are:
make the specific prompt screens kanji-aware, decode their runtime names, or
find a cheaper reservation subset per screen.

### 4. Upper-pool safety needs wider coverage

Borrowing unreferenced upper tiles is safe on the tested history screens and
restores them to zero at exit, but it assumes the game reloads CHR when the
screen changes. Every new scene that opens a message over a black/menu
background should be checked with a screenshot and a CHR dump. Map and
portrait screens already keep the pool closed via the nametable/OAM scan.

### 5. NMI peak still exceeds one vblank

The longest scan handler is about 15.8k CPU cycles against a 2.27k vblank.
Rendering is disabled for the jobs and the main thread waits during the scan,
so this mostly costs time rather than corrupting the picture. If hardware
shows a partial frame or audio hitch at message open, cut the scan further or
move the nametable scan to a slower background job.

## Commands

```powershell
# Original, byte-identical
python decomp\build.py

# Expanded kanji target + fixed-bank lint
python decomp\build.py --target kanji

# Headless Mesen checks
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\boot_check.lua --name kanji_boot
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua --name prompt_pages
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua --name ktown
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua --name survey_kanji
python tools\mesen_run.py "Tenchi o Kurau (Japan) (Rev 1).nes" tools\lua\scene_survey.lua --name survey_orig
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\nmi_budget.lua --name nmi_budget
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua --name kanji_sram_watch
```

Outputs land in `out/test/`. Mesen runs always use a copied ROM name.

## Source of truth

- `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx`
- `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx`
- `JF-Dot-Shinonome16.ttf` (replaced DotGothic16 on 2026-11-07: DotGothic
  rendered 2-pixel strokes at 16 px)

The generated `decomp/build/kanji/*.bin` files are build products and are
ignored by git.
