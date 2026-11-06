#!/usr/bin/env python3
"""Apply known corrections to the machine-generated kanji planning text.

The kana-kanji model is a first-pass draft.  This script fixes the game's
proper names, a set of recurring homophone errors, and a few damaged lines.
It writes a separate `_fixed.dtx`; the original draft is kept for comparison.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "decomp" / "text" / "kanji_plan"

# Longest keys first.  These are applied to the visible string only.
REPLACEMENTS = {
    # Proper names / factions
    "董賢": "鄧賢",
    "柴舟兵": "崔州平",
    "柴州兵": "崔州平",
    "長征兵": "張世平",
    "調整兵": "張世平",
    "漢中郡": "韓忠軍",
    "漢中軍": "韓忠軍",
    "丁半": "趙範",
    "鄭玄": "丁原",
    "義の国": "魏の国",
    "義の": "魏の",
    "義に": "魏に",
    "義と": "魏と",
    "義軍": "魏軍",
    "五の国": "呉の国",
    "五の": "呉の",
    "御の国": "呉の国",
    "御の": "呉の",
    "御軍": "呉軍",
    # Recurring homophone / segmentation errors
    "私太刀": "私",
    "あなた太刀": "あなたたち",
    "わたし太刀": "わたしたち",
    "俺達": "俺たち",
    "兵老": "兵糧",
    "凸線": "突然",
    "中間": "仲間",
    "間諜": "漢",
    "五軍": "呉軍",
    "ゴのぐん": "呉の軍",
    "此家": "この家",
    "為なら": "ためなら",
    "云って": "言って",
    "桃李": "通り",
    "掲揚": "桂陽",
    "秦の": "真の",
    "子竜": "子龍",
    "黄巾賊目": "黄巾賊め",
    "ぎでは": "魏では",
    "何等": "何処",
    "軍二": "軍に",
    "様二": "様に",
    "所二": "所に",
    "城二": "城に",
    "国二": "国に",
    "人二": "人に",
    "目二": "目に",
    "手二": "手に",
    "身二": "身に",
    "世二": "世に",
    "後二": "後に",
    "前二": "前に",
    "中二": "中に",
    "上二": "上に",
    "下二": "下に",
    "私野": "私の",
    "妻野": "妻の",
    "人野": "人の",
    "城野": "城の",
    "国野": "国の",
    "軍野": "軍の",
    "心野": "心の",
    "目野": "目の",
    "手野": "手の",
    "身野": "身の",
    "世野": "世の",
    "後野": "後の",
    "前野": "前の",
    "中野": "中の",
    "上野": "上の",
    "下野": "下の",
    "様友": "様と",
    "人友": "人と",
    "軍友": "軍と",
    "国友": "国と",
    "私友": "私と",
    "彼友": "彼と",
    # Place names (also fixes the annotations)
    "タイコウザン": "太行山",
    "テツモンキョウ": "鉄門峡",
    "シスイカン": "泗水関",
    "コロウカン": "虎牢関",
    "ヨウシュウ": "揚州",
    "ケイヨウ": "桂陽",
    "ワイナン": "淮南",
    "ナンヨウ": "南洋",
    "ジョシュウ": "徐州",
    "セイシュウ": "青州",
    "ケイシュウ": "荊州",
    "チョウサ": "長沙",
    "レイリョウ": "零陵",
    "ブリョウ": "武陵",
    "セイト": "成都",
    "フスイ": "涪水",
    "メンチクカン": "綿竹関",
    "ハンヨウ": "漢陽",
    "ケンアン": "建安",
    "カイケイ": "会稽",
    "ケンギョウ": "建業",
    "コウリョウ": "広陵",
    "ガッヒ": "合肥",
    "ジョナン": "汝南",
    "チンリュウ": "陳留",
    "ボッカイ": "渤海",
    "キシュウ": "冀州",
    "コウソウ": "広宗",
    "ロウソウソン": "楼桑村",
}

# Lines the model damaged badly.  Values are the whole corrected string.
OVERRIDES = {
    # bank 10
    "b10_msg_049": "<NAME_F5>が　突然現れた<END>",
    "b10_msg_055": "<CALL:D549>を<NL2><CALL:D6F3=すうじ>人　倒した<END_NOWAIT>",
    "b10_msg_056": "<NAME_F4>の兵が<NL2><CALL:D6F3=すうじ>人　倒された<END_NOWAIT>",
    "b10_msg_126": (
        "「生まれし　月日は異なれど<NL>願わくば　同年<NL>同月　同日に　至仙！"
        "<PAGE>閻魔大王よ<NL>ご照覧あれ！<PAGE>この地界に逆らいし者あれば"
        "<NL>たちどころに　地獄へ<NL>おとされんことを！<END>"
    ),
    "b10_msg_153": (
        "「ふむ！<WORD:31=リュウビどの>と申されるか<NL>なにっ　<WORD:3C=ぎゆうぐん>をもって"
        "<NL><WORD:30=こうきんぞく>を　<WORD:4E=たいじ>して<PAGE>くれるというのか？"
        "<NL>おう！<WORD:53=あなた>のような若者が<NL>現われるのを待っておりましたぞ"
        "<PAGE><WORD:59=わしは>このとおり　<WORD:2D=びょうしょう>のみ"
        "<NL><WORD:31=リュウビどの>が　<WORD:30=こうきんぞく>を　<NL><WORD:4E=たいじ>した"
        "　あかつきには<WORD:45=このしろ>を<PAGE><WORD:53=あなた>に　ゆずりたいとさえ"
        "<NL>思っている<WAIT>"
    ),
    "b10_msg_171": (
        "「ふん！　こう見えても　俺様も<NL><WORD:30=こうきんぞく>の　<NAME_F7>だ"
        "<NL>そう簡単に　<WORD:45=このしろ>を<PAGE>明け渡すわけには　いかねえ！"
        "<NL><WORD:3A=やろうども>　掛かれ！<NL2><JUMP:233A>"
    ),
    "b10_msg_239": (
        "<WORD:3D=ぎゃくぞく>　<NAME:BB>は<NL>５４年の生涯を<NL>おった"
        "<WORD:79=そうです><END>"
    ),
    "b10_msg_246": (
        "「<WORD:55=きでん>が　<WORD:0F=リュウビぐん>の<NL><NAME_F6>どので　ござるか"
        "　<WORD:59=わしは><NL><WORD:3C=ぎゆうぐん>の　総大将を<PAGE>務める　<NAME_F7>"
        "<WORD:7A=というもの>だ<NL><WORD:5A=みやこ><PLACE:71=洛陽>もご覧のとおりの"
        "<NL>有様だ<PAGE>これでは　<NAME:BB>追撃はおろか<NL><WORD:33=しょくりょう>の"
        "　補給もできぬ<PAGE>ひとまず　<WORD:68=渤海>に帰り<NL>兵を　立て直そうと思う"
        "<NL>では　また会おう！<NL2><JUMP:250B>"
    ),
    "b10_msg_279": (
        "「<NAME_F7><WORD:7A=というもの>です<NL>火薬を触らせると<NL>千人力---"
        "<PAGE><WORD:21=わたし>を<WORD:57=なかま>に<NL><WORD:06=くわえてください>"
        "<NL2><JUMP:1CE9>"
    ),
    "b10_msg_302": (
        "「何だ貴様ら！！<NL>今頃のこのこやってきやがって<NL>貴様らが　<PLACE:75=虎牢関>で"
        "　ぐずぐず<PAGE>している間に　<NAME:C4>の野郎が<NL>現われて　ご覧のとおりの"
        "<NL>有様だ　くそっ！<PAGE><NAME:BB>に<NAME:C4>がついていたんじゃ"
        "<NL>とても　勝ち目はねえ<NL>おれは　国に帰らせてもらうぜ！<PAGE>---そうだ"
        "　田舎者！<NL>おれの顔を　よく覚えておけ！<NL><WORD:33=しょくりょう>長官の"
        "<PAGE><NAME:1B>さまだ<NL>命があったら　また会おうぜ！<NL2><JUMP:24F1><END>"
    ),
    "b10_msg_303": (
        "「<WORD:1D=ここは>　<PLACE:6E=エンじょう><NL>この城の民は　<NAME:1B>の"
        "<NL>悪政に喘いで　<WORD:0D=おりました><END>"
    ),
    "b10_msg_310": (
        "「<WORD:21=わたし>の妻も　戻って<NL>参り<WORD:97=ました><NL>"
        "<WORD:50=こころ>から　感謝いたします<END>"
    ),
    "b10_msg_385": (
        "「<WORD:21=わたし>たちは　皆<NL><WORD:0E=リュウビさま>に　忠誠を"
        "<NL>誓<WORD:5C=います><END>"
    ),
    "b10_msg_386": (
        "「<WORD:4B=ごてん>の財宝は<NL>皆　<WORD:21=わたし>たちから<NL>"
        "巻き上げたものです<END>"
    ),
    "b10_msg_398": (
        "「<NAME_F6><WORD:12=しょうぐん>ですね<NL><NAME_F7>と<WORD:71=もうすものです>"
        "<NL>兄　亮が　何処の<WORD:29=いおり>で<PAGE>待っております"
        "<NL><WORD:70=いっこくもはやく>会って<NL>話を聞いてやって<WORD:3F=ください><END>"
    ),
    "b10_msg_401": (
        "「<NAME_F6><WORD:12=しょうぐん>！！<NL><WORD:02=ありがとうございました>"
        "<NL><WORD:98=これで>　<WORD:78=荊州>４郡に　秦の<PAGE><WORD:27=へいわ>が"
        "　訪れます<NL><WORD:98=これで>　<WORD:21=わたし>たちも　<WORD:78=荊州>を"
        "<NL>後にする事もできます<PAGE>どうでしょう<NL><WORD:21=わたし>は　多少"
        "　兵法を<NL><WORD:50=こころ>得ております<PAGE><WORD:07=へいのはしにでも>"
        "　<WORD:48=くわえて><NL>頂けませんでしょうか？<NL2><JUMP:1CE9>"
    ),
    "b10_msg_408": (
        "「<WORD:21=わたし>の<WORD:6F=となりにいるのが><NL>湾です"
        "<NL>あっ　前にも逢いましたっけ？<END>"
    ),
    "b10_msg_410": (
        "「<PLACE:64=桂陽城>の<WORD:15=たいしゅ><NL>趙範には気をつけ"
        "<WORD:3F=ください><END>"
    ),
    "b10_msg_412": (
        "「しっ！騙されてはいけません<NL>くれぐれも油断されぬように<END>"
    ),
    "b10_msg_414": (
        "「懲りずに来たか　<NAME_F6>！<NL>何者だ　かかれ<NL2><JUMP:2B55><END>"
    ),
    "b10_msg_422": (
        "「<PLACE:63=零陵城>には<NL><NAME:C5>という<NL>豪傑が　いる"
        "<WORD:79=そうです><END>"
    ),
    "b10_msg_425": (
        "「<WORD:49=ぶしょう>を　集めていると聞き<NL>馳せ参じ<WORD:97=ました>"
        "<PAGE><WORD:21=わたし>のクイズに<NL>正解すれば<NL><WORD:53=あなた>の軍に"
        "加わりましょう<PAGE>ヒマラヤ---と十回<NL>言って<WORD:3F=ください>"
        "<NL2><JUMP:2DEB>"
    ),
    "b10_msg_446": (
        "「ふあわああ----っ！！<NL><WORD:53=あなた>は　<NAME_F6><WORD:12=しょうぐん>！"
        "<NL>これは　失礼いたしました<PAGE>話は　<NAME:D6>から聞き<WORD:97=ました>"
        "<NL><WORD:26=しかし>　<WORD:21=わたし>には　<WORD:19=おとうと>の<NL>均が"
        "　おります<PAGE>--------<PAGE>--------<PAGE>--------<PAGE>--------<PAGE>"
        "わかり<WORD:97=ました><NL><WORD:21=わたし>のような　若輩ものを<NL>何度も"
        "　訪ねて<PAGE>下さったというのに<NL>断るわけには　いきません<NL>是非とも"
        "　<WORD:57=なかま>に<PAGE><WORD:48=くわえて><WORD:73=くださいませ><WAIT>"
        "孔明が　<WORD:57=なかま>に加わった！！<WAIT>"
    ),
    "b10_msg_448": (
        "「先程は　どうも---<PAGE>実は　ここへ来る　途中<NL>友人の　<NAME:51>に"
        "<NL>会い<WORD:97=ました><PAGE>彼の<WORD:A2=はなし>では　今　<WORD:54=ショク>は"
        "<PAGE>国内では　<WORD:80=はんらん>軍が<NL>国外では　韓忠軍が<PAGE>暴れており"
        "　とても　太守<NL>一人では　押さえきれ<WORD:A3=ません><PAGE>そこで　同族でもある"
        "<NL><WORD:0E=リュウビさま>に　力を貸して<NL>いただきたいと　いうことなのです"
        "<PAGE>ところで<NL>わたくしだけ　城に残るわけには<NL>いき<WORD:A3=ません>"
        "<PAGE><WORD:8A=どうか>　<WORD:67=たいれつ>に<NL><WORD:06=くわえてください>ませ"
        "<NL2><JUMP:2D55>"
    ),
    "b10_msg_462": (
        "「<WORD:21=わたし>は　武術の　<WORD:50=こころ>えが<NL>あります"
        "<PAGE><WORD:07=へいのはしにでも>　<WORD:48=くわえて><NL>"
        "いただけませんでしょうか？<NL2><JUMP:1CE9>"
    ),
    # bank 11
    "b11_msg_007": "「最後の虎が　韓忠軍に<NL>いるそうじゃ！<END>",
    "b11_msg_019": (
        "「<WORD:59=わしは>　２０年も<NL><WORD:89=けんを>　<WORD:8C=つくっ>ておる"
        "<PAGE><WORD:26=しかし>　いまだに<NL>納得のいくものを<NL>"
        "<WORD:8C=つくっ>たことがない<PAGE><WORD:8E=おぬし>に頼みがある"
        "<NL>剛鉄山に眠る<ITEM:1D=てつ>を探し<NL>わしに　最強の<WORD:89=けんを>"
        "<PAGE>作らせてくれんじゃろうか？<END>"
    ),
    "b11_msg_031": (
        "「むむ---<NL>不吉だ！<PAGE>敵勢明らかならず<NL>正座　生還<NL>みな　乱れる"
        "<PAGE>乱世は　まだ　続くぞ<END>"
    ),
    "b11_msg_041": (
        "「た　大変で<WORD:5E=ございます><NL>急に　<WORD:9D=ゴのぐん>勢が攻め込んで"
        "<NL>参り<WORD:97=ました><PAGE><NAME:A9>さまも　<NAME:AA>さまも"
        "<NL>ご自分の城を守るのが<NL>精一杯で<PAGE><WORD:9D=ゴのぐん>を追い返すことなど"
        "<NL>とても　<WORD:5F=できません><PAGE>なにとぞ　援軍を<NL>お出しくださいませ<END>"
    ),
    "b11_msg_043": (
        "「おお　<NAME_F6><NL>よくぞ　来てくれた<PAGE><WORD:9D=ゴのぐん>に襲われ"
        "　<WORD:45=このしろ>も<NL>危ないところであった<PAGE>できれば　一緒に"
        "<WORD:17=たたかい>たいが<NL><WORD:78=荊州>を　任された身では<NL>そうもいかぬ"
        "<PAGE>どうであろう　わしに代わって<NL><WORD:51=むすこ>を　連れて行っては"
        "<NL>くれぬか？<END>"
    ),
    "b11_msg_045": (
        "「桂陽の　城のことも気になる<NL><WORD:9C=だいしきゅう>　行ってやってくれ<END>"
    ),
    "b11_msg_050": (
        "「<WORD:1B=ここから>　<WORD:1F=みなみ>には　行けませんぞ"
        "<NL><PLACE:59=ハンヨウ>湖から　<WORD:A9=みずがあふれ><NL>川ができたので"
        "<PAGE>渡れませんのじゃ<END>"
    ),
    "b11_msg_055": (
        "「<PLACE:59=ハンヨウ>山を　特別な<NL><WORD:B1=ばくやく>を　使って"
        "<NL>爆破すれば<PAGE>その土砂で　きっと水を<NL><WORD:B0=せきとめ>られるはずじゃ"
        "<PAGE><WORD:B1=ばくやく>は　青白く<WORD:B8=ひかる><NL><WORD:AF=しょうせき>と"
        "<PAGE><WORD:AA=１０００ねん>以上　<WORD:AE=いきている><NL>"
        "<WORD:A8=ろうぼくのえだ><PAGE>それと　わしの<WORD:BC=もって>いる"
        "<NL>硫黄を　調合すればよい<PAGE>とりあえず　<WORD:A8=ろうぼくのえだ>と"
        "<NL><WORD:AF=しょうせき>を　<WORD:BC=もって>くれば<NL>それでよい<END>"
    ),
    "b11_msg_078": (
        "「<WORD:BA=キラリ>と　<WORD:B8=ひかる>ものがいる<NL>凍りつくほど　冷たい"
        "<WORD:B9=ひかり>だ<PAGE><WORD:B7=まもの>が　あらわれた<PAGE>ーーーーかと"
        "思うほどだった<NL>そこには　１本の<WORD:B9=ひかり><NL>かがやく　剣が"
        "　横たわっていた<PAGE>どうやら　この<WORD:B9=ひかり>は"
        "<NL>剣から　発せられているようだ！<PAGE><NAME:AD>は　剣を　手に入れた<END>"
    ),
    "b11_msg_096": (
        "「<NAME_F6>よ！<NL>よく　ここまできた！<PAGE>魏とわが軍は"
        "<NL>不可侵条約を結び<PAGE>ともに　<WORD:54=ショク>を滅ぼし"
        "<NL>天下の実権を<PAGE>握るはずであったが<NL>こうなれば　討死も覚悟"
        "<NL>せねば　なるまい<PAGE>ものども　かかれ！<END>"
    ),
    "b11_msg_098": (
        "「兄　<NAME:56>を　暗殺<NL>したのは　わしだ---<PAGE>今思えば　皆　魏の"
        "<NAME:71>に<NL>だまされて　やったこと<PAGE><WORD:AC=あにじゃには>"
        "　悪いことをしたと<NL>思っている<NL><WORD:AC=あにじゃには>　冥土で--ぐふっ"
        "<WAIT><NAME:57>は　息を　ひきとった<WAIT>三代続いた　呉の国の"
        "<NL2>歴史も　今　閉じようと<NL2>している----<NL2><JUMP:3385>"
    ),
    "b11_msg_101": (
        "　<NAME_F6><WAIT>「わが君<NL>ご決心を　促したいことが<NL>"
        "<WORD:5E=ございます><PAGE><WORD:3D=ぎゃくぞく>　<NAME:71>が"
        "　<WORD:22=ミカド>の<NL><WORD:BD=くらい>を奪った今<NL>"
        "<WORD:0E=リュウビさま>　自ら<PAGE><WORD:C3=コウテイ>の<WORD:BD=くらい>につき"
        "<NL>祖廟の礼を　慰め<PAGE>また　もって　万民を<NL>安んずべきと　考えます"
        "<PAGE><NAME:A8><NL2>「その<WORD:A2=はなし>をするな！<PAGE><NAME:D5><WAIT>"
        "「<WORD:26=しかし>　漢の<WORD:22=ミカド>の血を引く<NL>わが君が　進んで"
        "　正統を<NL>つぐべきです<PAGE><NAME:A8><NL2>「だまれ！！<PAGE>そちたちは"
        "　世を　末代まで<NL>不忠不義の人と<NL>呼ばせたいのか！<END>"
    ),
    "b11_msg_102": (
        "　<NAME_F6><NL2>「<NAME:71>　<NAME:57>と　わが君とは<NL>同じでは"
        "　ございませぬ<PAGE>官爵を奪った　<WORD:3D=ぎゃくぞく><NL><NAME:71>を"
        "誰が　懲らしめます<PAGE><NAME:D5><NL2>「このまま　黙っていては"
        "<NL>魏の<NAME:71>　呉の<NAME:57>の即位を<PAGE>正統なものとして"
        "<NL>認めたことになります<PAGE><NAME_F6><NL2>「今まで　数々の"
        "　<WORD:3D=ぎゃくぞく>が<NL><WORD:C3=コウテイ>の<WORD:BD=くらい>を"
        "　狙うことを<PAGE>阻止せんと　戦ってきたことが<NL>無意味と　なります<END>"
    ),
    "b11_msg_103": (
        "　<NAME:A8><NL2>「よくわかった！<NL>余は　小さなことに<PAGE>こだわりすぎた"
        "ようじゃ！<NL><NAME:71>と<NAME:57>の　<WORD:BE=そくい>は<NL>認めぬと"
        "　<WORD:BF=てんか>に知らしめるため<PAGE>余は　<WORD:C3=コウテイ>を"
        "　名のろう！！<WAIT>かくして---<NL2>建安　２６年　４月<WAIT>大霊台が"
        "　築かれ<NL2>文武官の　見守る中で<NL2><NAME:A8>は　玉璽を　受け<WAIT>ここに"
        "　<WORD:54=ショク>の<WORD:C3=コウテイ>を<NL2><WORD:BF=てんか>に"
        "　宣言した<END>"
    ),
    "b11_msg_109": (
        "「うぬが　<WORD:0F=リュウビぐん>の<NL><NAME_F6>か！<PAGE>よくもわが"
        "<WORD:19=おとうと><NL><NAME:1B>を---<PAGE><WORD:19=おとうと>の　かたきだ"
        "<NL>血祭に　あげろ！<END>"
    ),
    "b11_msg_118": (
        "「<NAME:71>は　各所の<WORD:28=とりで>に<NL>宋一族を置き　"
        "<WORD:0F=リュウビぐん>を<NL>待ち構えて<WORD:7B=おります><PAGE>"
        "気をつけて<WORD:73=くださいませ><END>"
    ),
    "b11_msg_125": (
        "「<WORD:0E=リュウビさま>大変で<WORD:5E=ございます><NL>実は---かくかく"
        "　しかじか<PAGE>何！呉の<NAME:57><NL>魏の<NAME:71>ともに"
        "<WORD:22=ミカド>を<NL>名のったというのか<PAGE><WORD:D9=カンチョウ>の"
        "<WORD:22=ミカド>の位を<NL>剥奪したということは<PAGE>事実上　"
        "<WORD:2C=カンオウチョウ>の<NL>崩壊を<NL>意味するではないか---<WAIT><JUMP:30AE>"
    ),
    "b11_msg_139": (
        "「おお　<NAME_F6>か　よく戻った<NL>たった今　キンと名乗る<NL>少年が"
        "　あらわれ<PAGE>兄が　帰ったので　至急<NL>来てくれるよう言っておったぞ！"
        "<NL>さあ　行くがよい　<NAME_F6>！<NL2><JUMP:2E95>"
    ),
    "b11_msg_142": (
        "「<WORD:D1=ぶじであったか！><NL><NAME_F6><WORD:12=しょうぐん>よ！"
        "<PAGE>呉の<NAME:57>が　魏の<NAME:71>と<NL>手を組み"
        "<NL><WORD:78=荊州>に　手を伸ばしている<PAGE>これ以上　<WORD:A5=たみを>"
        "<NL>苦しめては　いかん<PAGE>まずは　呉の<NAME:57>を"
        "<NL><WORD:CC=うってくれ><END>"
    ),
    "b11_msg_147": "文字の速さを決めてください<END>",
    "b11_msg_148": "どの歴史書を登録しますか？<END>",
    "b11_msg_151": "どの歴史書をコピーしますか？<END>",
    "b11_msg_152": "どの歴史書にコピーしますか？<END>",
    "b11_msg_163": (
        "「<WORD:78=荊州>　平定<NL>よくやってくれた<NL>民も　安心　するだろう"
        "<PAGE>しかし　渤海の<NAME:26>を<NL>討つのを　忘れては　おらぬか<NL2>"
    ),
    "b11_msg_172": (
        "「<WORD:12=しょうぐん><NL>鍵を買ってほしいとのこと<NL>これ　本当に"
        "　役に立つよ<PAGE>１つ　金　４０００<NL>でいいよ<NL2><JUMP:27A4>"
    ),
    "b11_msg_181": (
        "「おらも　<WORD:1E=いくさ>に<WORD:1E=いくさ>---<NL>ってなもんや"
        "三度笠---<NL>とくらあ！<END>"
    ),
    "b11_msg_185": (
        "「<NAME_F6>よ<NL><NAME:A8>は<WORD:D5=ショクカン>の<NL>"
        "<WORD:C3=コウテイ>を　名のったそうじゃのう<PAGE><WORD:DD=そのむかし>"
        "　<PLACE:7F=楼桑村>で<NL>むしろを売っていた<NL>若僧が"
        "　<WORD:22=ミカド>を名のり<PAGE>さらに　魏に攻め入るとは"
        "<NL>不届き千万<PAGE>まあ　いずれ<WORD:D5=ショクカン>を<NL>叩くつもり"
        "であったから<NL>ちょうどよいわ<PAGE>今　この場で<WORD:54=ショク>軍の"
        "<NL>息の根を　止めてくれる！<END>"
    ),
    "b11_msg_202": (
        "「うっ　<WORD:1D=ここは>どこだ<NL>そうか　<WORD:EF=われわれ>は"
        "<NL><NAME:88>の<WORD:DE=クーデター>を<PAGE>まのあたりにし----"
        "<NL><WORD:FD=そのご>----<NL>落雷にうたれた<PAGE><WORD:26=しかし>"
        "　<WORD:FD=そのご>の記憶がない<PAGE><WORD:0E=リュウビさま>なら"
        "<NL>なにか　知っているはずだ<END>"
    ),
    "b11_msg_244": (
        "「これでもう　兵士として<NL>徴兵されることはないんだ--"
        "<NL>あー青春だなあー<END>"
    ),
    "b11_msg_283": (
        "「この城を取り戻したからといって<NL>３代続いた　われらの呉が"
        "<NL>破れたわけではない<PAGE><WORD:2C=カンオウチョウ>の　"
        "<WORD:E6=ふっこう>など<NL>させるものか！<NL2><JUMP:3169>"
    ),
}


def apply_replacements(s: str) -> str:
    for old in sorted(REPLACEMENTS, key=len, reverse=True):
        s = s.replace(old, REPLACEMENTS[old])
    # "任" after a runtime number is the counter 人.
    s = re.sub(r"(<CALL:[^>]+>)任", r"\1人", s)
    return s


def main() -> int:
    for bank in (10, 11):
        data = json.loads(
            (PLAN / f"bank{bank:02d}_messages_kanji.json").read_text(encoding="utf-8")
        )
        lines = [
            f"# Tenchi o Kurau dialogue bank {bank:02d} -- corrected kanji plan",
            "#",
            "# Machine draft corrected for the game's proper names and known",
            "# homophone errors.  For glyph-budget assessment only; not assembled.",
            "",
        ]
        out_records = []
        for rec in data:
            label = rec["labels"][0]
            text = OVERRIDES.get(label, apply_replacements(rec["kanji"]))
            out_records.append(
                {"labels": rec["labels"], "source": rec["source"], "kanji": text}
            )
            for lab in rec["labels"]:
                lines.append(f"{lab}:")
            lines.append(f'    "{text}"')
            lines.append("")
        (PLAN / f"bank{bank:02d}_messages_kanji_fixed.dtx").write_text(
            "\n".join(lines), encoding="utf-8"
        )
        (PLAN / f"bank{bank:02d}_messages_kanji_fixed.json").write_text(
            json.dumps(out_records, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"wrote bank{bank:02d}_messages_kanji_fixed.dtx")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
