#!/bin/sh
# Every gate on decomp/build/rom_kanji.nes (revision 21, MMC3), as background
# Mesen jobs; results in out/test/$GDIR (default r21g), Mesen names get the
# suffix $TAG.  States: the SUROM play-test states converted by
# tools/mss_to_mmc3.py into out/user/m3/.  When every log ends with "exit=",
# summarise as in STATUS.md (garble_k_0.txt per gs_* dir, dead_*.txt,
# taint_*.txt, out/test/r11 and r12 for the standard-path gates).
cd /d/EMU/NES/tokqolfix
U=D:/EMU/NES/tokqolfix/out/user/m3; O=D:/EMU/NES/tokqolfix/out/test/${GDIR:-r21g}; R=decomp/build/rom_kanji.nes
T=${TAG:-21}
B="w,w,w,w,w$(printf ',a,w%.0s' $(seq 1 14))$(printf ',w%.0s' $(seq 1 25))"
B2="w,w,w,w,w,w,w$(printf ',a,w%.0s' $(seq 1 30))$(printf ',w%.0s' $(seq 1 20))"
L="w,w,w,w,w,w,w$(printf ',a,w%.0s' $(seq 1 70))"
LP="60EC=01,60F0=01,60F4=01,6070=00,6071=20"
P="a,w,a,w,w,w,w,w,w,a,w,w,w,w,w,a,w,w,w,w,w,w,a,w,w,w,w,w,w,w,w,w,a$(printf ',w%.0s' $(seq 1 20))"
gs() { mkdir -p $O/gs_$1; (SHOP_STATE=$2 SHOP_PATH="$3" SHOP_OUT=$O/gs_$1 SHOP_TAG=k SHOP_POKE="$4" SHOP_POKE_AT=300 python -I tools/mesen_run.py $R tools/lua/garble_state.lua --name gs${T}_$1 --timeout 1200 > $O/final_gs_$1.log 2>&1 &) ; }
gs bt $U/r16c_rom_kanji_1.mss "$B"; gs nb $U/r17_pre_battle_normal.mss "$B2"; gs bb $U/r17_pre_battle_boss.mss "$B2"; gs sv $U/r16b_rom_kanji_1.mss "$P"
gs lv $U/r17_pre_battle_normal.mss "$L" "$LP"
gs n1 $U/shop_k_rom_kanji_1.mss "b,w,w,a,w,w,a,w,a,w,w,w,w,w,up,a,w,w,w,w,b,w,w,w"; gs p1 $U/shop_k_rom_kanji_1.mss "up,a,w,w,w,w"; gs p2 $U/shop_k_rom_kanji_1.mss "a,w,w,w,a,w,w,w"; gs p3 $U/shop_k_rom_kanji_1.mss "down,a,w,w,w,a,w,w,w"; gs p4 $U/shop_k_rom_kanji_1.mss "down,down,a,w,w,w,a,w,w,w"
dl() { (DL_STATE=$2 DL_PATH="$3" DL_FRAMES=2500 DL_OUT=$O/dead_$1.txt python -I tools/mesen_run.py $R tools/lua/vblank_deadline.lua --name dl${T}$1 --timeout 1200 > $O/final_dl_$1.log 2>&1 &) ; }
dl bt $U/r16c_rom_kanji_1.mss "$B"; dl nb $U/r17_pre_battle_normal.mss "$B2"; dl bb $U/r17_pre_battle_boss.mss "$B2"
tn() { (SHOP_STATE=$2 SHOP_PATH="$3" TAINT_FRAMES=2500 TAINT_OUT=$O/taint_$1.txt python -I tools/mesen_run.py $R tools/lua/taint_check.lua --name tn${T}$1 --timeout 1200 > $O/final_tn_$1.log 2>&1 &) ; }
tn bt $U/r16c_rom_kanji_1.mss "$B"; tn nb $U/r17_pre_battle_normal.mss "$B2"; tn bb $U/r17_pre_battle_boss.mss "$B2"
for g in band_check:band ram_gate:ram mask_restore:mask anim_timing:anim zp_check:zp vblank_deadline:dead; do n=${g%%:*}; m=${g##*:}$T; (python -I tools/mesen_run.py $R tools/lua/$n.lua --name $m --timeout 1500 > $O/std_$m.log 2>&1 &); done
(python -I tools/garble_run.py $R --offsets 0,5,11,19,29,40 > $O/garble_std.log 2>&1; python -I tools/palette_check.py > $O/palette.log 2>&1; echo done > $O/seq.done) > /dev/null 2>&1 &
