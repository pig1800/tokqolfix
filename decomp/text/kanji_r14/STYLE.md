# Kanji re-conversion brief (Tenchi o Kurau / 天地を喰らう, NES, 1989)

You convert the game's all-kana dialogue into natural kanji-kana mixed
Japanese for an adult reader.  A program does all line wrapping and
paging afterwards; you supply the text, punctuation and phrase boundaries.

## Setting and tone

Capcom's Three Kingdoms RPG (based on 本宮ひろ志's manga).  The hero party
is 劉備 (玄徳), 関羽 (雲長), 張飛 (翼徳); the story runs from the 黄巾の乱 to
the Three Kingdoms era.  Keep every speaker's register: archaic and
martial speech (〜じゃ、〜ぬ、〜ござる、〜おる、〜せい), rough soldiers,
polite townsfolk.  Do not add, drop or reinterpret content; keep jokes,
exclamations and stammers ("むむ---") as they are.

## Kanji usage (adult, not children's books)

- Write words the way an adult historical novel or newspaper would
  (常用漢字 and standard 送り仮名).  Examples: 討伐, 義勇軍, 太守, 丞相,
  軍師, 兵糧, 謀反, 降伏, 申し上げる, 参る, 恐れながら, 何卒, 既に, 必ず,
  僅か, 暫く, 宜しい.
- Proper nouns (people, places, weapons, items, titles) always in kanji,
  exactly as in `glossary.tsv`.  Officer names use the person's name
  (関羽), courtesy names where the kana uses them (ゲントク → 玄徳).
  Rare characters are fine for proper nouns (鄧, 瓚, 禰, 琰 ...).
- Keep in kana what adult Japanese normally keeps in kana: particles,
  auxiliary verbs and auxiliary uses (〜ている, 〜てください, 〜てしまう,
  〜ておる), formal nouns (こと, もの, ところ, とき, ため when abstract),
  conjunctions (しかし, そして, だが, では), interjections (おお, むむ,
  ははは), sentence-final particles.
- Use the iteration mark 々 as adult text does: 我々, 数々, 日々, 人々,
  様々, 時々, 早々に, 元々, 益々 (never write the kanji twice, e.g. 日日).
  Words newspapers keep in kana stay in kana: なかなか, まだまだ,
  くれぐれも, みすみす, and all onomatopoeia (のこのこ, ぐずぐず).
- Do not force obscure kanji onto common words (no 其, 此, 迄, 而, 也);
  use the usual modern form.

## Punctuation and spacing

- Use 、 where a reader needs a pause and 。 at the end of each sentence;
  keep ！ and ？ as in the original.  The game font has no 、 or 。: the
  program turns 、 into a one-cell space and drops 。 at line ends, so
  punctuate naturally but not excessively.
- Write **no spaces at all**.  The original kana text separates words with
  spaces; kanji text does not need them.
- Dialogue starts with 「 exactly where the original has 「.  Never write
  」 (the font has no closing bracket; the game never closes quotes).
- The dash "---" (three hyphens) stays as in the original.

## Phrase boundaries: `|`

Put `|` between phrase units (文節) wherever a line may break.  The wrapper
breaks only at `|`, after 、。！？, or at a forced `/`.  Example:

    「玄徳よ、|お聞きなさい。|今|この世は|黄巾賊が|はびこり、|民を|苦しめております。

Keep compounds and names together (`黄巾賊|討伐の|義勇軍を`).

## Waits: `▼` and forced breaks: `/`

- `▼` = the player presses a button before text continues.  Put `▼` only
  at the end of a sentence (after 。！？ or ---), never in the middle of a
  phrase.  The original's ▼ positions show its pacing; with kanji the text
  is shorter, so merge where a wait split a sentence (original
  "このよのみだれを　たださねば▼なりませぬ" becomes
  "この世の|乱れを|正さねば|なりませぬ。").  You do not count lines: the
  program adds a wait at the best sentence/clause boundary whenever more
  than three lines would pass without one.
- `/` forces a line break.  Use it only for deliberate layout (verse such
  as the oath, lists).  Otherwise never break lines yourself.

## Tokens (must survive unchanged, same order)

`<NAME_F3>`..`<NAME_F7>` (names inserted at run time, printed in kana),
`<CALL:xxxx=...>`, `<JUMP:xxxx>`, `<WAIT>`, `<END>`, `<END_NOWAIT>`.
Copy them byte for byte, including any `=annotation`.  `<WAIT>` ends a
quote before narration; keep it where it is.

## Characters

Only these may appear outside tokens (plus `|`, `/`, `▼`, `、`, `。`):

- hiragana: あいうえおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろわをんゔ
- katakana (this subset only; the font lacks ニヌノヘヲ and small ァィゥェォャ): アイウエオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナネハバパヒビピフブプホボポマミムメモヤュユョヨラリルレロワンヴー
- digits ０１２３４５６７８９, symbols 「 ！ ？ ー - ＊ ★ ／
- any kanji and the iteration mark 々 (each becomes a 16x16 glyph)

## Format

Input and output are blocks:

    @b10_msg_002
    <NAME_F6>は|辺りを|見回した。<END>

Copy each `@...` line unchanged, then exactly one line of converted text.
Keep every block, in order, even trivial ones.  Run the checker on your
file and fix every error it reports:

    python -I tools/reconv_check.py decomp/text/kanji_r14/batch_NN.txt
