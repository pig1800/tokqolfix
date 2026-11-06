# Editable message text

The two dialogue banks are edited through these files:

- `bank10_messages.dtx` — 488 table entries (460 unique streams)
- `bank11_messages.dtx` — 384 table entries (305 unique streams)

After editing, run:

```powershell
python tools\text.py build
```

or simply `python decomp\build.py`, which runs the text build before assembling.

## Font mapping

The dialogue font is the 128-tile 8×8 sheet in `assets/fonts/kana_8x8.png`.
Its reading order is:

```text
０１２３４５６７８９　<LB><TOP><BOT>＊★
かきくけこさしすせそたちつてとな
にぬねのマメモユヨまみむめもやゆ
よらりるれろわをんゃゅょっあいう
えおアイウエオカキクケコサシスセ
ソタチツテトナネハヒフミホはひふ
へほラリルレロワンュョド金<LT><RT><RB>
▶▼゛゜ヤム「ッ-ー！？／<L><R>兵
```

Bytes `$80-$EE` do not select another font page.  They draw the base tile
`byte & $7F` plus a dakuten mark (`$72`) or handakuten mark (`$73`) in the
upper half of the cell:

- `$90-$9E` → がぎぐげござじずぜぞだぢづでど
- `$B0-$BF` → ゔ and the voiced kana in the `$30` row
- `$C4`, `$C7-$CF` → ヴ, ガギグゲゴ, ザジズゼゾ
- `$D0-$DF` → ゾダヂヅデド, バビブベボ, ばびぶべぼ
- `$E0-$E1` → べぼ
- `$E2-$E6` → パピプペポ (where the base glyph exists)
- `$E7-$EB` → ぱぴぷぺぽ

This is why the extracted text is mostly readable kana rather than one
`<XX>` token per high byte.

## Format

Each block is one or more labels followed by one or more quoted strings:

```text
# b10_msg_000  $83E8  len=14  refs=0,1
b10_msg_000:
b10_msg_001:
    "そちらには　だれもいません<END>"
```

- Multiple labels before the string are aliases for the same message stream.
  The exported files use one label per table entry; duplicate table pointers
  therefore share the same bytes.
- Literal kana/digits are mapped to the game's 8×8 tile codes.
- `　` (U+3000) is the game's space tile.  ASCII spaces are accepted too.
- `""` denotes an empty stream.

## Named tokens

| Token | Byte(s) | Meaning |
|---|---:|---|
| `<NL>` | `$FA` | new line, with the automatic indent |
| `<NL2>` | `$FB` | new line, without the indent |
| `<PAGE>` | `$FC` | page break / wait for the player |
| `<WAIT>` | `$FD` | wait for the player without a new page |
| `<END>` | `$FF` | end of message |
| `<END_NOWAIT>` | `$FE` | end without waiting |
| `<NAME_F3>` … `<NAME_F7>` | `$F3-$F7` | insert a runtime name |
| `<NAME:xx>` | `$F2 xx` | insert the name of party slot `xx` |
| `<WORD:xx=...>` | `$F0 xx` | dictionary word `xx` |
| `<PLACE:xx=...>` | `$EF xx` | place-name entry `xx` |
| `<ITEM:xx=...>` | `$F1 xx` | item-name entry `xx` |
| `<CALL:xxxx>` | `$F8 lo hi` | call the print helper at `xxxx` |
| `<JUMP:xxxx>` | `$F9 lo hi` | jump to the script at `xxxx` |
| `<FRAME_LB>` etc. | `$0B-$0D`, `$6D-$6F`, `$7D-$7E` | frame/tab tiles |
| `<XX>` | one byte | raw byte, no interpretation |
| `<XX:char>` | one byte | alternate byte for a character with two codes |

Text after `=` in a `WORD`, `PLACE`, `ITEM`, or `CALL` token is only an
annotation for readers.  The compiler ignores it and emits the original
reference bytes.  For example:

```text
"「もしや　<WORD:53=あなた>は<WORD:0E=リュウビさま>では？ ..."
```

## Word tables

The annotations are decoded from the original ROM tables:

- `WORD` — bank 13, split table `$B700/$B800`, strings from `$B900`
- `PLACE` — bank 12, split table `$A100/$A140`
- `ITEM` — bank 12, split table `$A3C8/$A438` (the first two bytes of each
  entry are a header and are not drawn)

The original table bytes are not modified by the message compiler.  Editing
the words themselves is a separate resource task.

## Code references

Inline message indices in code are emitted as references:

```asm
jsr text_print_inline
.dw b10_msg_index_036    ; message index -> b10_msg_036
```

`b10_msg_index_036` is a constant (`$0024`) generated in
`build/text/index_symbols.inc`; `b10_msg_036` is the message label in the
generated data include.

## Kanji planning transcription

`kanji_plan/` contains a kanji/kana version of both dialogue banks for
**glyph-budget planning only**.  It is machine-assisted and corrected for the
game's known proper names; it is not part of the build.

- `kanji_plan/REPORT.md` — glyph counts, coverage curve, CHR/text-space math
- `kanji_plan/bank10_messages_kanji_fixed.dtx`
- `kanji_plan/bank11_messages_kanji_fixed.dtx`
- `kanji_plan/kanji_inventory.csv` — every kanji, frequency, first context
- `kanji_plan/kanji_top300.txt` — the 300 most frequent kanji

Headline result: the corrected draft uses **718 unique kanji** in 3,177
occurrences.  The top 300 kanji cover about 81% of occurrences; 450 cover
about 92%; 560 cover about 95%.  A 16x16 kanji costs 64 bytes, so 300 kanji
need 18.75 KiB of pattern data, 450 need 28.13 KiB, and 718 need 44.88 KiB.
CHR RAM is only 8 KiB (128 glyphs at 64 bytes each), so any set above 128
must be paged per scene.

Regenerate the draft with:

```powershell
python tools\make_kanji_plan.py
python tools\fix_kanji_plan.py
python tools\convert_tables.py
```

The model download is a one-time cost (`subdiox/genmai-310M`, transformers +
torch).

## UI strings outside the message banks

`ui_strings.txt` is a reference extraction of the main-menu and command-menu
labels in banks 13/15:

```text
げーむをはじめる / れきししょをとうろくする / ...
コマンド / はなす / しらべる / たいれつ / ぶしょう / どうぐ
ならび / ぐんし / はい / いいえ
はやい / ふつう / おそい
```

These labels are inline in menu scripts, so they are not part of the editable
message build yet.  Regenerate the reference with:

```powershell
python tools\export_ui.py
```

The prompt strings ("どのれきししょをはじめますか？" etc.) are already in
`bank11_messages.dtx`.

## Space

Bank 10 currently has no spare bytes after messages + tail.  Equal-length and
shrinking edits work; growth requires freeing space or repacking.  Bank 11 has
leading tail padding that the compiler consumes when text grows, so small
additions there work automatically.

## Known mapping limitations

- A few high codes are still raw `<XX>` tokens when the base tile has no
  valid dakuten/handakuten form (for example `$E5` is ミ + ゜ and is not a
  normal kana).
- The only character with two valid tile codes found so far is ド (`$6B`
  direct and `$D5` composed).  The exporter keeps one canonical form and
  emits the other as `<D5:ド>` so both round-trip exactly.
- `<CALL:xxxx>` and `<JUMP:xxxx>` are script references.  Their targets are
  code in banks 13/14; the text they print is runtime-dependent unless it has
  an explicit annotation.
