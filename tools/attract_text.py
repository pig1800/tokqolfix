"""The title screen and the attract mode in kanji: the user's text
(titlekanji.txt, 2026-11-14).  tools/attract_build.py lays it out.

Every line is drawn with its kanji bottom row on the original line's row
(the original's kana row); a kanji is two columns, every other glyph one
(a dakuten mark goes on the row above, as the game's own font draws it).
U+3000 is one blank column, as the original's spaces.  黄忠 is written with
U+9EC4, as the game's officer name (the user's choice, 2026-11-14; the
file had U+9EC3).
"""

# The title screen (bank 13): the copyright line replaces the original's
# kana line, same row and columns (16 columns either way).
TITLE_COPYRIGHT = "©本宮企画／集英社"

# The intro over the title logo (bank 7 phrases 0-6): rows 13, 15, ..., 25
# from column 5.  It uses the title screen's tile set (no transition).
INTRO = [
    "この物語は",
    "今を去る１８００年の昔",
    "中国を舞台に",
    "繰り広げられた",
    "野望多き男たちの",
    "戦いを描いた",
    "ヒストリー　ロールプレイング　ゲームである",
]

# The five portrait screens (bank 7 phrases 7-45): one entry per band, three
# lines each.  Band 1 rows 5/7/9 from column 9, band 2 rows 13/15/17 from
# column 2 (its portrait is on the right), band 3 rows 21/23/25 from column 9.
PORTRAITS = [
    [
        ["漢朝復興のために挙兵した", "中山靖王　劉勝の子孫", "劉備玄徳"],
        ["兵一万人に相当すると言われ", "文武共に優れた　今も神と", "崇められる　関羽雲長"],
        ["猛将呂布と互角に", "渡り合える　ただ一人の武将", "張飛翼徳"],
    ],
    [
        ["黄巾賊の首領", "太平道の教祖でもある", "張角"],
        ["猛将呂布を味方に付け", "洛陽で我が物顔に振る舞う", "董卓仲穎"],
        ["最強の武将故に", "裏切りの人生を歩む", "呂布奉先"],
    ],
    [
        ["董卓討伐軍の総大将を", "務めたが　呂布に敗れ", "紀州に帰った　袁紹本初"],
        ["一度は帝を名乗ったが", "根本的に統治能力が", "不足していた　袁術公路"],
    ],
    [
        ["曹軍百万の中を", "ただ一騎で駆け抜け", "勇名を馳せた　趙雲子龍"],
        ["諸葛亮をして　張飛と並ぶ", "勇将と言わしめた", "馬超孟起"],
        ["老いて益々盛んな老将", "荊州の虎", "黄忠漢升"],
    ],
    [
        ["中国史上最大の", "天才軍師", "伏龍こと諸葛亮孔明"],
        ["諸葛亮と並び称される", "天才軍師", "鳳雛こと龐統士元"],
    ],
]

# The text screen (bank 7 phrases 46-51): rows 7, 9, ..., 17, drawn from
# column 3 as the original; the leading blanks centre the block.
FINAL = [
    "　膨大な資料により　２００人以上の",
    "　　武将の能力をシミュレートし　中国",
    "　三国志の時代を完全に再現した",
    "　　　　　　カプコン初の本格的",
    "　　ヒストリー　ロールブレイング　ゲーム!",
    "　　　　　ここに堂々完成",
]


def all_text() -> str:
    """Every string above (the kanji store takes their kanji)."""
    parts = [TITLE_COPYRIGHT] + INTRO + FINAL
    for screen in PORTRAITS:
        for band in screen:
            parts += band
    return "".join(parts)
