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
▶▼゛゜ヤム「ッ.ー！？／<L><R>兵
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
- `.` is tile `$78`, a small dot at mid height that the game uses in
  ellipses (`「そうか...`).  It was written `-` until 2026-11-17.
- `""` denotes an empty stream.

## Named tokens

| Token | Byte(s) | Meaning |
|---|---:|---|
| `<NL>` | `$FA` | new line, with the automatic indent |
| `<NLNI>` | `$FB` | new line, no indent (was `<NL2>`) |
| `<PAGE>` | `$FC` | page break: wait for the player; the next line indented (as after `<NL>`) |
| `<PAGENI>` | `$FD` | page break: wait for the player; no indent (was `<WAIT>`).  The original game clears the window at neither (its lines scroll); the kanji build starts a new window at both |
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

## The kanji edition's text

The kanji edition reads `kanji_plan/bank10_messages_kanji_r14.dtx` and
`kanji_plan/bank11_messages_kanji_r14.dtx`, edited by hand.  They use the
same records, labels and tokens as the kana files (above), with kanji in
the strings.  `tools/kanji_text.py` compiles them:
- a 6-byte far stub per message in banks 10/11;
- the text into four 8 KiB chunks;
- kanji as store codes.

Edit them and run `python decomp/build.py --target kanji`.  The place
names' kanji come from `kanji_r14/glossary.tsv`; the item and tactic
words' from `../../kanjiwordlist.csv`; the officer names' from
`../../namekanjilist.csv`.  See `../../STATUS.md` "Editing the text".

(They came from revision 14's re-conversion, laid out by program on
2026-11-08.  The batch sources, the older machine drafts and the
glyph-budget planning files were removed on 2026-11-14 and are in the git
history.)

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
