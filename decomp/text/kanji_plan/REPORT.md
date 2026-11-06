# Kanji glyph budget for the dialogue

This folder is a **planning transcription**, not a build input.  The kana
dialogue from `decomp/text/bank10_messages.dtx` and
`bank11_messages.dtx` was converted to a kanji/kana version with a local
kana-kanji model, then corrected for the game's known proper names and
several recurring homophone errors.

The purpose is to answer one question:

> If the dialogue is rewritten with kanji, how many 16x16 glyphs have to be
> drawn, stored, and made resident in CHR RAM?

## Files

| File | Contents |
|---|---|
| `all_dialogue_kanji.dtx` | Both banks in one file, corrected kanji draft |
| `bank10_messages_kanji_fixed.dtx` | Bank 10 dialogue, corrected kanji draft |
| `bank11_messages_kanji_fixed.dtx` | Bank 11 dialogue, corrected kanji draft |
| `bank10_messages_kanji.dtx` | Raw model output, before corrections |
| `bank11_messages_kanji.dtx` | Raw model output, before corrections |
| `kanji_inventory.csv` | Every kanji in the corrected draft, with frequency and first context |
| `kanji_top300.txt` | The 300 most frequent kanji, one per line |
| `word_table_kanji.txt` | `$F0` dictionary table, converted (reference) |
| `place_table_kanji.txt` | `$EF` place table, converted (reference) |
| `item_table_kanji.txt` | `$F1` item table, converted (reference) |
| `tables_kanji.json` | Machine-readable table conversion |

The `.dtx` files keep the original labels and control tokens.  They are for
reading and counting only; they do not compile to the original message
bytes.

## What was counted

Only the **literal message text** is included in the headline counts:

- 765 unique message records (460 in bank 10, 305 in bank 11)
- 20,544 visible characters (tokens such as `<NAME_F6>` and `<PAGE>` are
  excluded, because they are not drawn as text)
- 3,177 kanji occurrences

Text inserted through `<WORD>`, `<PLACE>`, `<ITEM>`, and runtime names is
**not** included in the headline count.  Those strings live in separate
tables and add more glyphs.  The table conversions in this folder are a
first pass; see “What is still missing” below.

## Headline counts

| Measure | Count |
|---|---:|
| Unique kanji in the corrected draft | **718** |
| Kanji occurring at least twice | 450 |
| Kanji occurring at least three times | 324 |
| Kanji occurring at least five times | 199 |
| Hiragana used | 70 |
| Katakana used | 28 |
| Spaces, punctuation, digits, brackets | 15 |

The 718 figure is an upper-bound planning number: it includes proper-name
kanji, rare words, and some machine-draft choices.  Many of them occur only
once.  A production script would normally consolidate or kana-ize some of
those.

## Coverage curve

If the font only contains the N most frequent kanji, this is how much of the
dialogue's kanji usage it covers:

| Glyphs | Kanji occurrences covered | Coverage |
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

A practical budget can therefore be chosen by coverage:

- **300 glyphs** — about 81% of kanji occurrences; rare words stay kana.
- **450 glyphs** — about 92%; includes most common names and place words.
- **560 glyphs** — about 95%; only rare names and archaic words are missing.
- **718 glyphs** — everything in this draft, including one-off names.

## Storage cost

A 16x16 kanji is four 8x8 NES tiles.  Each 8x8 tile is 16 bytes, so one
kanji is **64 bytes** of pattern data.

| Glyphs | 8x8 tiles | Bytes | KiB |
|---:|---:|---:|---:|
| 100 | 400 | 6,400 | 6.25 |
| 300 | 1,200 | 19,200 | 18.75 |
| 450 | 1,800 | 28,800 | 28.13 |
| 500 | 2,000 | 32,000 | 31.25 |
| 560 | 2,240 | 35,840 | 35.00 |
| 718 | 2,872 | 45,952 | 44.88 |

For comparison, the current 128-tile 8x8 dialogue font is 2,048 bytes.
A 300-kanji set is **9.4 times** the current dialogue font; the full 718
set is **22.4 times** it.

## CHR RAM is the real limit

The NES has 8 KiB of CHR RAM in this cartridge (the ROM has no CHR ROM).
At 64 bytes per 16x16 glyph:

```text
8 KiB / 64 bytes = 128 glyphs
```

Even if the entire CHR RAM were used for kanji, at most **128 16x16 glyphs**
can be resident at once.  A 300- or 500-glyph font therefore cannot be a
single resident font.  It has to be **paged or streamed**:

- keep the 128 8x8 kana tiles resident;
- load the kanji needed by the current scene/text page into a small CHR
  window;
- swap glyphs when the scene changes or when a new message page is shown.

This is workable because a single scene or text page normally uses far
fewer than 128 distinct kanji.  It is not workable as one flat font.

## Text encoding cost

The current messages use one byte per character.  A kanji-aware format needs
either a 16-bit code for every character or a mixed format:

```text
1 byte  : kana, punctuation, digits
2 bytes : kanji (escape byte + 16-bit index, or a high-bit code)
```

With 3,177 kanji occurrences in this draft, a mixed format adds about
**3,177 bytes** across the two message banks:

| Format | Message bytes | Growth |
|---|---:|---:|
| Current | 27,227 | — |
| Mixed 1-byte kana + 2-byte kanji | ~30,404 | +11.7% |
| All characters 2 bytes | ~54,454 | +100% |

Bank 10 is already full; bank 11 has only a small tail margin.  A mixed
format is strongly preferable to a uniform 16-bit format.  Even +3.2 KiB
requires repacking or ROM expansion in bank 10.

## Recommended budget

1. **Start with 300 kanji** (18.75 KiB of pattern data, 81% coverage).
   Keep rare words and one-off names in kana.  This is the smallest set that
   still makes the dialogue read as normal Japanese.
2. **Add about 150 name/place glyphs** if proper names are written in kanji.
   A 450-glyph set covers about 92% and costs 28.13 KiB.
3. **Reserve 560 glyphs** only if the ROM/CHR budget can afford 35 KiB and
   the loader can page them; 95% coverage is a comfortable production target.
4. **Do not plan for 718 resident glyphs.**  Treat 718 as the full inventory,
   not the resident set.  Stream per scene.
5. Keep the existing 128 8x8 kana tiles.  Do not redraw kana as 16x16; that
   would quadruple the kana cost for no readability gain.
6. Use a mixed text encoding.  A uniform 16-bit encoding doubles the message
   banks and is not realistic without major expansion.
7. The status-screen already has **136 16x16 kanji glyphs**.  Some of them
   are name kanji that also appear in this inventory, so they can offset part
   of the name set.  The exact overlap still needs the 136 glyph identities
   mapped; do not assume all 136 are reusable for dialogue.

## Proper names used in the correction

The draft uses these readings, confirmed against the game's character and
place data:

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

## What is still missing

The headline 718 count is **message text only**.  A complete budget also
needs:

- the `$F0` dictionary table (252 non-empty entries);
- the `$EF` place table (82 non-empty entries);
- the `$F1` item table (126 non-empty entries);
- the main/command/speed menu labels;
- runtime character names inserted by `<NAME:xx>` and `<NAME_F3>`–`<NAME_F7>`;
- status-screen labels and battle messages that are drawn outside the
  message banks.

The table conversions in this folder are a first pass and still contain
model errors (for example item names such as `七星等`, `下約`, `銅銭丹`,
`漢将の剣`).  They should be proofread before their kanji are added to the
budget.  A rough allowance is **+80 to +150 additional unique kanji** for
the tables and menus, mostly item/place names.

The dialogue draft itself also needs a proofreading pass for archaic lines:
the incantation around `b10_msg_126`, the divination line in `b11_msg_031`,
and a handful of rare verbs.  Those do not change the order of magnitude of
the budget.

## Bottom line

- **Minimum practical set:** ~300 kanji, ~1,200 tiles, ~18.75 KiB.
- **With names:** ~450 kanji, ~1,800 tiles, ~28.1 KiB.
- **Comfortable coverage:** ~560 kanji, ~2,240 tiles, ~35 KiB.
- **Full draft inventory:** 718 kanji, ~2,872 tiles, ~44.9 KiB.
- **Resident limit:** 128 glyphs in 8 KiB CHR RAM, so the font must be paged
  per scene regardless of which set is chosen.
