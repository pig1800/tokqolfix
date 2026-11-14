# To-do: debloat (ROM space), 2026-11-13

State after the kanji store (`69f99c7`, TEXT_RENDERER.md "The kanji store").
Nothing below is done.  Each item waits for the user's go-ahead; the user
has issues to patch first.

## Free now (banks 16-31, 81.4 KiB since the attract mode, 2026-11-14)

| Where | KiB | Note |
|---|---|---|
| Bank 25 | 16 | the old font copy's bank, blank |
| Bank 24 | 11.8 | after the title screen and attract mode (4.2, 2026-11-14) |
| Bank 23 | 12.3 | 4.3 after the hack code (lower half), the upper half 8 |
| Bank 29 | 14 | only an overlay copy; the text builder's reserve (its 3% margin) |
| Bank 27 | 15.3 | lower half 8 (the old map copy's), upper half 7.3 after the RAM image |
| Bank 28 (UI) | 6.5 | |
| Bank 26 (map renderer) | 4.3 | |
| Text banks 18-22, 30 | 1.3 | the gaps at the banks' ends |
| Kanji store (bank 35) | 0.7 | 21 glyph slots, kept for new kanji (the attract mode took 21) |

## Candidates (measured)

### 1. The band page's parts of the message metadata: 38.9 KiB

- Each message's metadata holds:
  - the page count and a 16-byte kana bitmap;
  - for each page: a keep list, a clean list, the kanji count (with the
    names count), and 6 bytes for each kanji (code lo, hi, 4 band-page tiles).
- 751 messages, 1,151 pages and 6,019 kanji entries: 53,758 bytes (52.5 KiB).
- Only the band page reads the bitmap, the keep and clean lists, and the tile
  bytes: 39,818 bytes.
  - Map mode reads only the page count, the codes and the names count.
  - So does battle.
- **Needed first:** the list of messages that can show on a band-page screen,
  i.e. outside map mode and battle (the boot screens, the name entry,
  anything else).  Those keep their plans; the rest drop them.
- **Measured so far** (2026-11-14, `tools/lua/band_use.lua`):
  - Three battles (r4/s2, r5/s2, `r17_c`) and the menu cycle never turn the
    band on.
  - The standard path from power-on turns it on 3 times, all from the
    overlay's `message_setup`:
    - the boot screens' record prompts (どの歴史書を登録しますか,
      どの歴史書を始めますか; `TXR_ON` = `$40`, set 8);
    - the opening oath scene (生まれし月日は異なれど…; `TXR_ON` = 0,
      set 10).
  - That gives 1,249 band switches in total.  Other band screens (endings,
    events) are not covered by these paths.
  - **Since 2026-11-14** the boot screens' record prompts use the boot
    screens' fixed set (TEXT_RENDERER.md "The boot screens' messages on the
    fixed set"): the standard path turns the band on once, for the oath
    scene (729 switches).  Still on the band at boot: the record check's
    b11_msg_145 (残念ですが…消えています, a damaged record only; `TXR_ON` =
    0, set 8).
- **Risk:** a message shown on a band screen that the list misses would
  show no kanji, or the wrong ones.

### 2. The rest of the metadata: 13.6 KiB

- That is the page count, the per-page kanji codes and the names count.
- Since the store, every code is in the text itself (`$EC+bank, pos`).
- Map mode and battle could count a page's kanji by scanning the page's
  text at the page start: the pool's page check (`pool_need`), and the map
  renderer's entry index (`REG` entries 0-15).
- **Depends on 1** (band-screen messages keep their plans).
- **Cost:** the scan runs at each page start, and the overlay is
  1717 / 2048 bytes.

### 3. The original message text left in banks 10 / 11: 20.7 KiB

- Bank 10 `$9243-$BDD2`: 11,152 bytes.
- Bank 11 `$8CC6-$B3EF`: 10,026 bytes.
- The pointer tables point at the stubs (8 bytes a message; JUMP-only
  messages keep their 3 bytes), so the old text behind them is not used.
- **Measured** (`out/test/opt/romprobe.lua`, Mesen CDL): 0 bytes read on
  five paths. Over the same runs, the stub area and bank 31 were read.
  - menu cycle (`u3b_c`, 4,200 frames);
  - level-up battle (r4/s2, 2,400);
  - capture victory (r5/s2, 1,700);
  - officer-switch battle (`r17_c`, 857);
  - standard path from power-on (6,000).
- **Needed first:** a search of banks 13-15 for direct addresses into these
  ranges (event code), beyond the paths traced.
- **Limit:** usable only while bank 10 or 11 is mapped (at message starts),
  so for data or code that runs there.

### 4. Bank 15: 16 KiB

- It is the original fixed bank, kept at its place; bank 31 holds the same
  patched bytes.  In MMC3 PRG mode 0, `$C000-$FFFF` is bank 31.
- `build.py` allows bank 15 to differ, and `bank15_lint.py` requires
  bank 15 == bank 31: both need changing.
- **Measured:** 0 bytes of it read on the same five paths.  One byte
  (`$3FFFF`) was read in the runs that load a state: Mesen's power-on
  before the load, not seen from power-on itself.
- **Needed first:** a check that nothing maps bank 15 at `$8000` (no
  `set_bank` with 15 in banks 13/14/15).  The build-time readers
  (`kanji_text.menu_stream_tiles`, `bank15_lint`) read the original ROM
  file, not the built bank.

### 5. The overlay copies: 12 of 14 KiB

- There are 2 KiB at `$B800` in each text bank (18-22, 29, 30): 7 copies.
- One copy would live in its own 8 KiB bank at R7 beside the text bank at R6.
- **Blocker:** the overlay runs across the text task's waits (`wait_text`).
  `PRG_R7X` is one global, so another task's bank switch, followed by an
  NMI, would give that task the overlay's R7.  A per-task R7 (saved and
  restored with the task) would be needed.

## Smaller ones (not measured in detail)

- **The map renderer's own kana font copy** (bank 26, for the NMI's kana
  records): a copy of bank 9's kana.
- **The map renderer's UI strings:** they keep 1-byte indexes into code
  tables (`ui_gc`, `nm_gc`, the fixed set's `ui_fx`).  Direct `$EC+bank,
  pos` codes would drop the tables but need a code-to-tile lookup for the
  boot screens' fixed set.

## Verification for any of these

- Pixel compare against the previous build on the regression set
  (`out/test/opt/regress.sh`) and the battle, info and army paths (TEXT_RENDERER.md
  "The kanji store", "Checked").
- `romprobe.lua` for regions that should stay unread.
- The original build stays byte-identical.
