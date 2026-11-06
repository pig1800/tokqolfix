# Handoff: ROM expansion and kanji dialogue planning

This document is a self-contained handoff for a planning/implementation model.
It records the current verified state, the decisions already made, the measured
glyph budget, and the unresolved engineering questions around expanding the ROM
and adding mixed kanji+kana dialogue.

The target is **emulator and EverDrive N8**, not original cartridge hardware.

---

## 1. Non-negotiable invariants

1. The current 256 KiB build must remain byte-identical:

   ```text
   size:   262160 bytes
   sha256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367
   ```

2. The original source tree must keep building that exact ROM. Expanded/hacked
   builds must be a separate target with their own expected size/hash. Do not
   overwrite the byte-exact target with an expanded build.

3. The editable `.dtx` text files must keep round-tripping the original message
   bytes until the kanji text format is actually implemented.

4. The kanji planning draft is **not** a final script. It is a machine-assisted
   transcription for glyph budgeting and needs proofreading.

5. Do not assume the status-screen 16×16 kanji renderer can be reused as-is.
   Its PPU/pattern-table split is still not fully traced.

---

## 2. Current verified state

### Build

- ROM: `Tenchi o Kurau (Japan) (Rev 1).nes`
- Size: `262160` bytes (`16`-byte header + `262144` bytes PRG)
- SHA-256:
  `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`
- Build command:

  ```powershell
  python decomp\build.py
  ```

- The build runs asset build, text build, ASM6f, then SHA-256 verification.

### Text

- `python tools\text.py verify` passes both banks.
- `decomp/text/bank10_messages.dtx`: 488 table entries, 460 unique streams.
- `decomp/text/bank11_messages.dtx`: 384 table entries, 305 unique streams.
- All message controls are decoded; no unexplained raw `<XX>` tokens remain in
  the actual message data.

### Assets

- 14 editable PNG resources under `assets/`.
- `python tools\assets.py verify` round-trips cleanly.

### Decompilation

- Routine-oriented source under `decomp/banks/`.
- 271 named/documented routines; index in `decomp/FUNCTIONS.md`.
- `python tools\decompile.py --no-build` regenerates source and still builds
  the byte-identical ROM.

### Kanji planning

- Corrected kanji draft and glyph inventory under `decomp/text/kanji_plan/`.
- Headline: **718 unique kanji**, **3,177 kanji occurrences** in 20,544 visible
  message characters.
- Full report: `decomp/text/kanji_plan/REPORT.md`.

---

## 3. Repository map

| Path | Purpose |
|---|---|
| `decomp/main.asm` | Top-level ASM6f source |
| `decomp/banks/bank00.asm` … `bank15.asm` | PRG bank sources |
| `decomp/banks/*.base` | Bank base/geometry metadata |
| `decomp/build.py` | Full build + verification |
| `decomp/BANKS.md` | Bank/resource map |
| `decomp/FUNCTIONS.md` | Generated routine index |
| `decomp/text/bank10_messages.dtx` | Editable bank 10 dialogue |
| `decomp/text/bank11_messages.dtx` | Editable bank 11 dialogue |
| `decomp/text/README.md` | DTX syntax, controls, font mapping, space limits |
| `tools/textdata.py` | Font table, codec, control tokens, table annotations |
| `tools/text.py` | Export/build/verify DTX and pointer tables |
| `tools/assets.py` | PNG ⇄ NES tile conversion |
| `decomp/text/kanji_plan/` | Kanji planning draft and glyph budget |
| `ANALYSIS.md` | Earlier kanji feasibility study |

### Kanji plan files

| File | Purpose |
|---|---|
| `decomp/text/kanji_plan/all_dialogue_kanji.dtx` | Both banks in one file |
| `decomp/text/kanji_plan/bank10_messages_kanji_fixed.dtx` | Corrected bank 10 draft |
| `decomp/text/kanji_plan/bank11_messages_kanji_fixed.dtx` | Corrected bank 11 draft |
| `decomp/text/kanji_plan/kanji_inventory.csv` | Every kanji, frequency, first context |
| `decomp/text/kanji_plan/kanji_top300.txt` | 300 most frequent kanji |
| `decomp/text/kanji_plan/word_table_kanji.txt` | `$F0` dictionary, converted |
| `decomp/text/kanji_plan/place_table_kanji.txt` | `$EF` place table, converted |
| `decomp/text/kanji_plan/item_table_kanji.txt` | `$F1` item table, converted |
| `decomp/text/kanji_plan/REPORT.md` | Glyph budget and coverage curve |

The raw model output (`bank10_messages_kanji.dtx`, etc.) is kept for
comparison. The `_fixed` files are the corrected draft.

---

## 4. ROM and mapper facts

### Header

Exact 16-byte header:

```text
4E 45 53 1A 10 00 12 08 00 00 70 07 00 00 00 01
```

Decoded:

| Field | Value |
|---|---|
| Mapper | `1` / MMC1 |
| PRG | `16` × 16 KiB = `256 KiB` |
| CHR | `0` CHR ROM; `8 KiB` CHR RAM |
| Flags 6 | `$12` = battery-backed PRG RAM; the header's mirroring bit is 0, but MMC1 init writes control `$0E`, which selects vertical mirroring |
| Flags 7 | `$08` = NES 2.0 header |
| PRG NVRAM | `8 KiB` battery-backed |
| CHR RAM | `8 KiB` |

Board behavior is effectively **SNROM**: MMC1, 8 KiB CHR RAM, 8 KiB battery
PRG RAM.

### CPU/PPU memory windows

| Window | Contents |
|---|---|
| `$0000-$07FF` | 2 KiB internal CPU RAM (fixed) |
| `$6000-$7FFF` | 8 KiB cartridge PRG RAM (battery) |
| `$8000-$BFFF` | 16 KiB switchable PRG bank |
| `$C000-$FFFF` | 16 KiB fixed PRG bank (bank 15) |
| PPU `$0000-$1FFF` | 8 KiB CHR RAM window |

### Bank roles

| Bank | Role |
|---:|---|
| 00 | Character/sprite/background tiles |
| 01 | 16×16 kanji + character graphics |
| 02 | 16×16 kanji + portrait/title graphics |
| 03 | Title/portrait graphics |
| 04 | Portrait graphics |
| 05 | Map chip graphics |
| 06 | Map layout/event data |
| 07 | Party/list screen and event code |
| 08 | Sound driver + music data |
| 09 | UI graphics + 1bpp kana font |
| 10 | Message pointer table + dialogue |
| 11 | Message pointer table + dialogue |
| 12 | Enemy/town/item/weapon tables |
| 13 | Officer status/name-entry code + dictionary |
| 14 | Gameplay/menu code + embedded tables |
| 15 | Fixed bank: main loop, text engine, NMI, bank switching |

### MMC1 bank-switch code

Fixed bank `decomp/banks/bank15.asm`:

- `set_bank_a`, `set_bank_b`, `set_bank_current`
- `set_bank_lock`
- `write_prg_bank` at ~`$C4B7` (CPU address)
- `mmc1_reset`, `mmc1_init`
- `restore_bank_after_nmi`

`write_prg_bank` currently serializes **five bits** into the MMC1 PRG bank
register:

```asm
write_prg_bank:
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    rts
```

This is safe only for bank numbers `0-15`. On MMC1B, bit 4 of the PRG bank
register is **PRG RAM disable**. Bank numbers 16-31 would disable the save RAM
and not select the upper ROM half.

---

## 5. Text pipeline facts

### Message banks

| Bank | Low table | Gap | High table | Data | Entries | Unique streams |
|---:|---|---|---|---|---:|---:|
| 10 | `$8000-$81E7` | `$81E8-$81FF` | `$8200-$83E7` | `$83E8-$BFFF` | 488 | 460 |
| 11 | `$8000-$817F` | `$8180-$81FF` | `$8200-$837F` | `$8380-$BFFF` | 384 | 305 |

Text-engine index:

- `< $200` → bank 10, index as-is
- `>= $200` → bank 11, index minus `$200`

The engine reads the low byte at `$8000+index`, the high byte at
`$8200+index`, and forms the message address.

### Message controls

| Token | Byte | Meaning |
|---|---:|---|
| `<NL>` | `$FA` | newline with automatic indent |
| `<NL2>` | `$FB` | newline without indent |
| `<PAGE>` | `$FC` | page break / player wait |
| `<WAIT>` | `$FD` | wait without new page |
| `<END_NOWAIT>` | `$FE` | end without waiting |
| `<END>` | `$FF` | end |
| `<WORD:xx>` | `$F0 xx` | dictionary entry |
| `<PLACE:xx>` | `$EF xx` | place entry |
| `<ITEM:xx>` | `$F1 xx` | item entry |
| `<NAME:xx>` | `$F2 xx` | party-slot name |
| `<NAME_F3>`…`<NAME_F7>` | `$F3-$F7` | runtime names |
| `<CALL:xxxx>` | `$F8 lo hi` | call print helper |
| `<JUMP:xxxx>` | `$F9 lo hi` | jump to script |

### Font

- Dialogue font: 128 8×8 1bpp glyphs, `assets/fonts/kana_8x8.png`.
- Source data in bank 9 at CPU `$BA00-$BDFF`:
  128 glyphs × 8 bytes = 1 KiB.
- Loader expands each 1bpp glyph to a 2bpp NES tile by copying the 8 bytes to
  plane 0 and zeroing plane 1.
- 16×16 kanji on the status screen use 2×2 BG tiles, column-major
  `TL, BL, TR, BR`.

### Space

- Bank 10: no spare bytes after messages + tail. Equal-length/shrink edits only.
- Bank 11: leading tail padding can absorb small growth.
- A mixed kanji text format will add about 3,177 bytes across the two banks
  (one extra byte per kanji occurrence), and bank 10 is already full.

---

## 6. Kanji budget findings

### Counts

From the corrected planning draft (literal message text only, tokens excluded):

| Measure | Count |
|---|---:|
| Visible characters | 20,544 |
| Kanji occurrences | 3,177 |
| Unique kanji | **718** |
| Kanji appearing at least twice | 450 |
| Kanji appearing at least three times | 324 |
| Kanji appearing at least five times | 199 |
| Hiragana used | 70 |
| Katakana used | 28 |
| Other symbols/spaces | 15 |

### Coverage curve

| Glyph set | Kanji occurrences covered | Coverage |
|---:|---:|---:|
| 100 | 1,596 | 50% |
| 200 | 2,229 | 70% |
| 286 | 2,543 | 80% |
| 300 | 2,585 | 81% |
| 426 | 2,861 | 90% |
| 450 | 2,909 | 92% |
| 500 | 2,959 | 93% |
| 560 | 3,019 | 95% |
| 718 | 3,177 | 100% |

### Storage cost

- 16×16 kanji = 4 × 8×8 tiles = **64 bytes** of CHR data.
- 1bpp source glyph = **32 bytes** (the current kana font is 1bpp and expanded
  at load time). 2bpp source = 64 bytes.

| Glyphs | 8×8 tiles | 2bpp source | 1bpp source |
|---:|---:|---:|---:|
| 100 | 400 | 6.25 KiB | 3.13 KiB |
| 300 | 1,200 | 18.75 KiB | 9.38 KiB |
| 450 | 1,800 | 28.13 KiB | 14.06 KiB |
| 500 | 2,000 | 31.25 KiB | 15.63 KiB |
| 560 | 2,240 | 35.00 KiB | 17.50 KiB |
| 718 | 2,872 | 44.88 KiB | 22.44 KiB |

### CHR RAM limit

CHR RAM is 8 KiB:

```text
8 KiB / 64 bytes per 16x16 glyph = 128 glyphs
```

Even if all CHR RAM were used for kanji, at most **128 16×16 glyphs** can be
resident at once. A 300+ glyph font must be **paged/streamed per scene or text
page**. This is expected to be workable because a single scene/text page uses
far fewer than 128 distinct kanji.

### Existing 136 glyphs

The status-screen graphics contain **136 16×16 kanji glyphs** (104 + 32).
Their kanji identities are not yet mapped. Some will overlap the dialogue
inventory (names, common words), but do not assume all 136 are reusable.

### Table/menu additions

The headline 718 count is **literal message text only**. It excludes:

- `$F0` dictionary (252 non-empty entries)
- `$EF` place table (82 non-empty entries)
- `$F1` item table (126 non-empty entries)
- main/command/speed menu labels
- runtime names inserted by `<NAME:xx>` / `<NAME_F3>`–`<NAME_F7>`
- status-screen and battle labels outside the message banks

The converted table files are a first pass and still contain model errors
(for example item names like `七星等`, `下約`, `銅銭丹`, `漢将の剣`). A rough
allowance is **+80 to +150 additional unique kanji** for tables and menus.

### Planning caveat

The draft was generated with a local kana-kanji model and then corrected for
known proper names and recurring homophones. It is useful for sizing, but:

- rare/archaic lines still need proofreading;
- some names and item/place terms are wrong;
- some words were left in kana, which may undercount a fully kanji-heavy text;
- some model-invented rare kanji may overcount.

Treat 718 as an upper-bound inventory and 300–560 as practical font-set sizes.

### Corrected readings

| Reading | Kanji |
|---|---|
| リュウビ | 劉備 |
| カンウ | 関羽 |
| チョウヒ | 張飛 |
| ソウソウ | 曹操 |
| ソンケン / ソンサク / ソンジュン | 孫権 / 孫策 / 孫堅 |
| トウケン | 鄧賢 |
| ゲントク | 玄徳 |
| チョウセイヘイ | 張世平 |
| サイシュウヘイ | 崔州平 |
| ソウジン / ソウユウ | 宋仁 / 宋勇 |
| カンチュウ | 韓忠 |
| テイゲン | 丁原 |
| チョウハン | 趙範 |
| キン | 均（諸葛均） |
| リョウ | 亮（諸葛亮） |
| シリュウ | 子龍 |
| スイキョウ | 水鏡 |
| フクリュウ / ホウスウ | 伏龍 / 鳳雛 |
| タンフク | 単福 |
| モウコウイ | 孟公威 |
| ゴ / ギ / ショク / カン | 呉 / 魏 / 蜀 / 漢 |

Known corrected place names:

`楼桑村`, `徐州`, `青州`, `太行山`, `鉄門峡`, `泗水関`, `洛陽`, `長安`,
`荊州`, `長沙`, `桂陽`, `零陵`, `武陵`, `成都`, `涪水`, `綿竹関`,
`漢陽`, `建安`, `会稽`, `建業`, `広陵`, `合肥`, `汝南`, `陳留`, `渤海`,
`冀州`, `虎牢関`, `揚州`, `淮南`, `南洋`, `宛`.

---

## 7. ROM expansion analysis

### Why the current ROM cannot simply grow

MMC1’s normal PRG bank register only addresses 16 × 16 KiB = 256 KiB. The
current ROM uses all 16 banks. A rough scan for long `$00`/`$FF` runs found
only about **8.6 KiB** of potentially free PRG space across banks, which is not
enough for a 23–45 KiB kanji font plus text growth.

### Recommended target: SUROM 512 KiB

MMC1 can reach 512 KiB by reusing **CHR bank 0 bit 4** as an outer PRG bank
bit (SUROM/SXROM behavior). This is the least invasive expansion because it
keeps the MMC1 register interface and the existing 8 KiB CHR RAM / 8 KiB
battery PRG RAM.

Target:

```text
Mapper 1 / SUROM
512 KiB PRG (32 x 16 KiB)
8 KiB CHR RAM
8 KiB battery PRG RAM
```

Benefits:

- 256 KiB of new PRG space.
- Enough for the full 718-kanji set at 1bpp (~23 KiB), text growth, tables,
  loader, and code.
- Supported by Mesen/FCEUX/Nestopia and the original EverDrive N8, whose PRG
  limit is 512 KiB.
- Keeps battery save RAM and the existing save format.

### Critical code work

1. **Duplicate the fixed bank.**
   In SUROM the outer bank bit applies to the whole 256 KiB, including
   `$C000-$FFFF`. Current fixed bank is bank 15. Copy it to bank 31 so the
   NMI/reset code is identical when outer bank 1 is selected. Put new code/data
   in banks 16–30 and keep 15/31 identical.

2. **Fix `write_prg_bank`.**
   Mask the bank number to 4 bits for the PRG register, and write the outer
   bank bit through CHR bank 0:

   ```text
   bank 0-15  -> outer 0, low 4 bits to PRG register
   bank 16-31 -> outer 1, low 4 bits to PRG register
   ```

   Do not let bit 4 reach the PRG register; on MMC1B it disables PRG RAM.

3. **Audit bank-number assumptions.**
   Bank numbers 0–31 fit in a byte, but any code/table that assumes 0–15,
   masks with `$0F`, or reserves 16+ must be updated.

4. **NMI safety.**
   The duplicated fixed bank makes an outer-bank switch survivable, but still
   switch inside the existing bank-switch lock or with NMI disabled. Ensure
   the NMI handler does not write CHR bank 0 for unrelated reasons.

5. **Header/build.**
   - PRG banks: `0x20` (32)
   - CHR banks: `0x00` (8 KiB CHR RAM)
   - Mapper: 1
   - NES 2.0 submapper 1 (SUROM) is optional; 512 KiB PRG + 8 KiB CHR RAM is
     normally auto-detected.
   - ROM size becomes `16 + 524288 = 524304` bytes.
   - Keep the 256 KiB target as a separate build/verification target.

### RAM: what can and cannot expand

| Memory | Limit | Expand? |
|---|---|---|
| CPU internal RAM | 2 KiB at `$0000-$07FF` | No; zero page and stack are fixed |
| Cartridge PRG RAM | 8 KiB window at `$6000-$7FFF` | Yes; current 8 KiB is enough for buffers; SXROM can bank 32 KiB |
| CHR RAM | 8 KiB visible window | No visible expansion; PPU sees only 8 KiB |

CHR RAM does **not** need to grow. Store the kanji font in PRG and stream the
needed glyphs into the existing 8 KiB CHR window, just as the game already
streams kana/graphics. A scene/text page should need fewer than 128 distinct
kanji.

If more CPU-side buffer is ever needed, SXROM-style 32 KiB PRG RAM is possible
using the same CHR bank bits, but it is not required for this project.

### Emulator/EverDrive constraints

- **Original EverDrive N8:** maximum 512 KiB PRG / 512 KiB CHR. A 1 MiB ROM
  will not boot. Target 512 KiB.
- **EverDrive N8 Pro:** more headroom, but custom mappers still require mapper
  support.
- **Custom mapper:** works only in a modified emulator, not on EverDrive.
- **SUROM 512 KiB:** standard MMC1 configuration; supported by common
  emulators and N8.
- **Save RAM:** keep 8 KiB battery PRG RAM and the existing save layout.

### Alternative if >512 KiB is required

Use MMC3 (512 KiB PRG, 8 KiB CHR RAM, CHR banking) or MMC5 (1 MiB PRG,
64 KiB PRG RAM, more CHR flexibility). Both require rewriting the bank-switch
layer, bank numbers, and possibly CHR loading. N8 original cannot exceed
512 KiB, so this is only for emulator/N8 Pro. It is **not** needed for the
current 718-kanji budget.

---

## 8. Recommended implementation phases

### Phase 0 — Freeze and test the original

- Keep the 256 KiB build/verification intact.
- Add/retain tests:
  - `python tools\text.py verify`
  - `python tools\assets.py verify`
  - `python decomp\build.py`
- Record the original SHA-256 in a separate target.

### Phase 1 — 512 KiB SUROM skeleton

- Add 16 new 16 KiB banks (16–31).
- Duplicate bank 15 into bank 31.
- Update header to 32 PRG banks.
- Add outer-bank switching to `write_prg_bank`.
- Boot test on Mesen and N8 with no gameplay changes.
- Verify reset, NMI, bank switching, save RAM, and audio still work.

### Phase 2 — Font storage and streaming

- Store kanji glyphs in banks 16–30 (1bpp preferred; 32 bytes/glyph).
- Add a loader that expands selected glyphs to 2bpp and writes 4 tiles into a
  free CHR slot.
- Test rendering in a scratch CHR slot and a debug screen.
- Do not alter dialogue text yet.

### Phase 3 — Kanji text opcode and renderer

- Add a kanji escape/opcode to the text format.
- Use a 16-bit index or a bank-local glyph index.
- Implement a 2×2 BG glyph draw path for dialogue.
- Start with a small 128-glyph resident cache and one scene.
- Handle line 4 / bottom border layout.

### Phase 4 — Text bank expansion/relocation

- Bank 10 is full; relocate or split messages into new banks.
- Update the split pointer tables and text-engine bank selection.
- Keep the original text bank layout buildable separately.
- Re-run DTX round-trip tests.

### Phase 5 — Script and table conversion

- Proofread the kanji dialogue draft.
- Convert `$F0` dictionary, `$EF` place, `$F1` item tables into editable
  resources.
- Convert menu/UI labels and runtime names.
- Decide whether proper names stay katakana or become kanji; this changes the
  glyph count.

### Phase 6 — Full test

- Mesen and N8 playthrough.
- Save compatibility.
- Check status/battle/menu paths and glyph-cache eviction.
- Check the fourth dialogue line and bottom border.
- Record new expected size/hash.

---

## 9. Open questions for the planning model

1. Should the target be original EverDrive N8 (512 KiB cap) or N8 Pro
   (larger)? This decides whether 512 KiB SUROM is the hard ceiling.
2. Should proper names be kanji or stay katakana? This changes the font set by
   roughly 100–200 glyphs.
3. What coverage target is acceptable: 300 glyphs (81%), 450 (92%), 560 (95%),
   or 718 (100%)?
4. Is a 16×16 1bpp source font acceptable, or is 2bpp needed for style/color?
5. What is the per-scene maximum distinct kanji count? This determines the
   CHR cache size and eviction policy.
6. Should the fixed bank be duplicated (simple, +16 KiB) or should a trampoline
   be used (smaller, more complex)?
7. What is the text encoding: escape byte + 16-bit index, high-bit marker, or
   bank-local glyph index?
8. How should the text banks be split after expansion? Keep bank 10/11 and add
   overflow banks, or repack all messages?
9. Can the 136 existing 16×16 glyphs be identified and reused? Their identities
   are not mapped yet.
10. Is the status-screen PPU/pattern-table split reusable for dialogue, or does
    dialogue need a separate 2×2 BG path?

---

## 10. Known unresolved technical issues

- **Status-screen PPU split:** The status screen shows 16×16 BG kanji and 8×8
  kana stats from apparently conflicting CHR tile numbers. The exact
  raster/pattern-table split is not fully traced.
- **136 glyph identities:** The existing 16×16 kanji set is not mapped to
  Unicode/kanji.
- **Bank-number audit:** Any code that stores bank numbers in nibbles, tables,
  or assumptions must be found before adding banks 16–31.
- **NMI during outer-bank switch:** Needs a tested lock/trampoline strategy.
- **Text bank 10 full:** Any text growth requires relocation/repacking.
- **Kanji draft proofreading:** Archaic lines, rare verbs, and table/item names
  remain uncertain.
- **Table conversion noise:** `place_table_kanji.txt` and
  `item_table_kanji.txt` include garbage/duplicate entries from table ranges
  that are not all valid place/item entries. Filter to used ranges before
  counting.
- **Build system:** `decomp/build.py` and `main.asm` currently assume 16 banks;
  they need a 32-bank mode and a separate original-build target.

---

## 11. Verification checklist

For the original target:

```powershell
python tools\text.py verify
python tools\assets.py verify
python decomp\build.py
```

Expected:

```text
size:   262160 bytes
sha256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367
OK: byte-identical to the original ROM
```

For the expanded target (to be defined):

- New expected size (512 KiB PRG + 16-byte header = 524304 bytes unless a
  different layout is chosen).
- New SHA-256.
- Boot test on Mesen.
- Boot test on EverDrive N8.
- Save RAM persists across power cycle.
- Audio, NMI, controller, and bank switching still work.
- Dialogue text renders correctly with kanji and kana.
- No CHR corruption when glyph cache pages are swapped.

---

## 12. Useful commands

```powershell
# Original build + hash verification
python decomp\build.py

# Regenerate decompiled bank sources without rebuilding
python tools\decompile.py --no-build

# Text round-trip verification
python tools\text.py verify

# Re-export editable DTX from the original ROM
python tools\text.py export

# Asset round-trip verification
python tools\assets.py verify

# Regenerate UI/menu reference strings
python tools\export_ui.py

# Regenerate the kanji planning draft
python tools\make_kanji_plan.py
python tools\fix_kanji_plan.py
python tools\convert_tables.py
```

The kanji plan generator requires `transformers`, `torch`, and a one-time
download of `subdiox/genmai-310M`.

---

## 13. Planning prompt

Use this document as the source of truth. The planning model should produce a
concrete implementation plan that:

1. Preserves the original 256 KiB byte-identical build.
2. Expands to 512 KiB SUROM without breaking N8 compatibility.
3. Duplicates/handles the fixed bank and outer-bank switching safely.
4. Streams a 300–560 glyph 16×16 kanji font into the existing 8 KiB CHR RAM.
5. Adds a kanji text opcode/renderer and relocates text only after the font
   path works.
6. Keeps 8 KiB battery PRG RAM and the existing save format.
7. Includes test checkpoints on Mesen and EverDrive N8.

The plan should call out exact files/functions to change, the order of changes,
and how to verify each phase without losing the original build.
