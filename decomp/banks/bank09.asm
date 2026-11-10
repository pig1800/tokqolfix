; ======================================================================
; PRG bank 09  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$B9FF  b09_ui_graphics: 2bpp UI/window/portrait tile graphics.
;   $BA00-$BDFF  b09_kana_font: 1bpp dialogue font: 128 8x8 glyphs.
;   $BE00-$BFFF  b09_ui_graphics2: 2bpp UI/status tile graphics.
; ======================================================================

; Region aliases
b09_kana_font = $BA00


b09_ui_graphics:
; editable source: assets/graphics/bank09_ui_a.png (chr2)
    .incbin "build/assets/bank09_ui_a.bin", $0000, $0400

b09_data_8400:
    .incbin "build/assets/bank09_ui_a.bin", $0400, $0400

b09_data_8800:
    .incbin "build/assets/bank09_ui_a.bin", $0800, $0400

b09_data_8C00:
    .incbin "build/assets/bank09_ui_a.bin", $0C00, $0400

b09_data_9000:
    .incbin "build/assets/bank09_ui_a.bin", $1000, $0400

b09_data_9400:
    .incbin "build/assets/bank09_ui_a.bin", $1400, $0400

b09_data_9800:
    .incbin "build/assets/bank09_ui_a.bin", $1800, $0400

b09_data_9C00:
    .incbin "build/assets/bank09_ui_a.bin", $1C00, $0400

b09_data_A000:
    .incbin "build/assets/bank09_ui_a.bin", $2000, $0400

b09_data_A400:
    .incbin "build/assets/bank09_ui_a.bin", $2400, $0400

b09_data_A800:
    .incbin "build/assets/bank09_ui_a.bin", $2800, $0400

b09_data_AC00:
    .incbin "build/assets/bank09_ui_a.bin", $2C00, $0400

b09_data_B000:
    .incbin "build/assets/bank09_ui_a.bin", $3000, $0400

b09_data_B400:
    .incbin "build/assets/bank09_ui_a.bin", $3400, $0400

b09_data_B800:
    .incbin "build/assets/bank09_ui_a.bin", $3800, $0200

b09_kana_000:
; editable source: assets/fonts/kana_8x8.png (font1)
    .incbin "build/assets/bank09_kana.bin", $0000, $0008

b09_kana_001:
    .incbin "build/assets/bank09_kana.bin", $0008, $0008

b09_kana_002:
    .incbin "build/assets/bank09_kana.bin", $0010, $0008

b09_kana_003:
    .incbin "build/assets/bank09_kana.bin", $0018, $0008

b09_kana_004:
    .incbin "build/assets/bank09_kana.bin", $0020, $0008

b09_kana_005:
    .incbin "build/assets/bank09_kana.bin", $0028, $0008

b09_kana_006:
    .incbin "build/assets/bank09_kana.bin", $0030, $0008

b09_kana_007:
    .incbin "build/assets/bank09_kana.bin", $0038, $0008

b09_kana_008:
    .incbin "build/assets/bank09_kana.bin", $0040, $0008

b09_kana_009:
    .incbin "build/assets/bank09_kana.bin", $0048, $0008

b09_kana_010:
    .incbin "build/assets/bank09_kana.bin", $0050, $0008

b09_kana_011:
    .incbin "build/assets/bank09_kana.bin", $0058, $0008

b09_kana_012:
    .incbin "build/assets/bank09_kana.bin", $0060, $0008

b09_kana_013:
    .incbin "build/assets/bank09_kana.bin", $0068, $0008

b09_kana_014:
    .incbin "build/assets/bank09_kana.bin", $0070, $0008

b09_kana_015:
    .incbin "build/assets/bank09_kana.bin", $0078, $0008

b09_kana_016:
    .incbin "build/assets/bank09_kana.bin", $0080, $0008

b09_kana_017:
    .incbin "build/assets/bank09_kana.bin", $0088, $0008

b09_kana_018:
    .incbin "build/assets/bank09_kana.bin", $0090, $0008

b09_kana_019:
    .incbin "build/assets/bank09_kana.bin", $0098, $0008

b09_kana_020:
    .incbin "build/assets/bank09_kana.bin", $00A0, $0008

b09_kana_021:
    .incbin "build/assets/bank09_kana.bin", $00A8, $0008

b09_kana_022:
    .incbin "build/assets/bank09_kana.bin", $00B0, $0008

b09_kana_023:
    .incbin "build/assets/bank09_kana.bin", $00B8, $0008

b09_kana_024:
    .incbin "build/assets/bank09_kana.bin", $00C0, $0008

b09_kana_025:
    .incbin "build/assets/bank09_kana.bin", $00C8, $0008

b09_kana_026:
    .incbin "build/assets/bank09_kana.bin", $00D0, $0008

b09_kana_027:
    .incbin "build/assets/bank09_kana.bin", $00D8, $0008

b09_kana_028:
    .incbin "build/assets/bank09_kana.bin", $00E0, $0008

b09_kana_029:
    .incbin "build/assets/bank09_kana.bin", $00E8, $0008

b09_kana_030:
    .incbin "build/assets/bank09_kana.bin", $00F0, $0008

b09_kana_031:
    .incbin "build/assets/bank09_kana.bin", $00F8, $0008

b09_kana_032:
    .incbin "build/assets/bank09_kana.bin", $0100, $0008

b09_kana_033:
    .incbin "build/assets/bank09_kana.bin", $0108, $0008

b09_kana_034:
    .incbin "build/assets/bank09_kana.bin", $0110, $0008

b09_kana_035:
    .incbin "build/assets/bank09_kana.bin", $0118, $0008

b09_kana_036:
    .incbin "build/assets/bank09_kana.bin", $0120, $0008

b09_kana_037:
    .incbin "build/assets/bank09_kana.bin", $0128, $0008

b09_kana_038:
    .incbin "build/assets/bank09_kana.bin", $0130, $0008

b09_kana_039:
    .incbin "build/assets/bank09_kana.bin", $0138, $0008

b09_kana_040:
    .incbin "build/assets/bank09_kana.bin", $0140, $0008

b09_kana_041:
    .incbin "build/assets/bank09_kana.bin", $0148, $0008

b09_kana_042:
    .incbin "build/assets/bank09_kana.bin", $0150, $0008

b09_kana_043:
    .incbin "build/assets/bank09_kana.bin", $0158, $0008

b09_kana_044:
    .incbin "build/assets/bank09_kana.bin", $0160, $0008

b09_kana_045:
    .incbin "build/assets/bank09_kana.bin", $0168, $0008

b09_kana_046:
    .incbin "build/assets/bank09_kana.bin", $0170, $0008

b09_kana_047:
    .incbin "build/assets/bank09_kana.bin", $0178, $0008

b09_kana_048:
    .incbin "build/assets/bank09_kana.bin", $0180, $0008

b09_kana_049:
    .incbin "build/assets/bank09_kana.bin", $0188, $0008

b09_kana_050:
    .incbin "build/assets/bank09_kana.bin", $0190, $0008

b09_kana_051:
    .incbin "build/assets/bank09_kana.bin", $0198, $0008

b09_kana_052:
    .incbin "build/assets/bank09_kana.bin", $01A0, $0008

b09_kana_053:
    .incbin "build/assets/bank09_kana.bin", $01A8, $0008

b09_kana_054:
    .incbin "build/assets/bank09_kana.bin", $01B0, $0008

b09_kana_055:
    .incbin "build/assets/bank09_kana.bin", $01B8, $0008

b09_kana_056:
    .incbin "build/assets/bank09_kana.bin", $01C0, $0008

b09_kana_057:
    .incbin "build/assets/bank09_kana.bin", $01C8, $0008

b09_kana_058:
    .incbin "build/assets/bank09_kana.bin", $01D0, $0008

b09_kana_059:
    .incbin "build/assets/bank09_kana.bin", $01D8, $0008

b09_kana_060:
    .incbin "build/assets/bank09_kana.bin", $01E0, $0008

b09_kana_061:
    .incbin "build/assets/bank09_kana.bin", $01E8, $0008

b09_kana_062:
    .incbin "build/assets/bank09_kana.bin", $01F0, $0008

b09_kana_063:
    .incbin "build/assets/bank09_kana.bin", $01F8, $0008

b09_kana_064:
    .incbin "build/assets/bank09_kana.bin", $0200, $0008

b09_kana_065:
    .incbin "build/assets/bank09_kana.bin", $0208, $0008

b09_kana_066:
    .incbin "build/assets/bank09_kana.bin", $0210, $0008

b09_kana_067:
    .incbin "build/assets/bank09_kana.bin", $0218, $0008

b09_kana_068:
    .incbin "build/assets/bank09_kana.bin", $0220, $0008

b09_kana_069:
    .incbin "build/assets/bank09_kana.bin", $0228, $0008

b09_kana_070:
    .incbin "build/assets/bank09_kana.bin", $0230, $0008

b09_kana_071:
    .incbin "build/assets/bank09_kana.bin", $0238, $0008

b09_kana_072:
    .incbin "build/assets/bank09_kana.bin", $0240, $0008

b09_kana_073:
    .incbin "build/assets/bank09_kana.bin", $0248, $0008

b09_kana_074:
    .incbin "build/assets/bank09_kana.bin", $0250, $0008

b09_kana_075:
    .incbin "build/assets/bank09_kana.bin", $0258, $0008

b09_kana_076:
    .incbin "build/assets/bank09_kana.bin", $0260, $0008

b09_kana_077:
    .incbin "build/assets/bank09_kana.bin", $0268, $0008

b09_kana_078:
    .incbin "build/assets/bank09_kana.bin", $0270, $0008

b09_kana_079:
    .incbin "build/assets/bank09_kana.bin", $0278, $0008

b09_kana_080:
    .incbin "build/assets/bank09_kana.bin", $0280, $0008

b09_kana_081:
    .incbin "build/assets/bank09_kana.bin", $0288, $0008

b09_kana_082:
    .incbin "build/assets/bank09_kana.bin", $0290, $0008

b09_kana_083:
    .incbin "build/assets/bank09_kana.bin", $0298, $0008

b09_kana_084:
    .incbin "build/assets/bank09_kana.bin", $02A0, $0008

b09_kana_085:
    .incbin "build/assets/bank09_kana.bin", $02A8, $0008

b09_kana_086:
    .incbin "build/assets/bank09_kana.bin", $02B0, $0008

b09_kana_087:
    .incbin "build/assets/bank09_kana.bin", $02B8, $0008

b09_kana_088:
    .incbin "build/assets/bank09_kana.bin", $02C0, $0008

b09_kana_089:
    .incbin "build/assets/bank09_kana.bin", $02C8, $0008

b09_kana_090:
    .incbin "build/assets/bank09_kana.bin", $02D0, $0008

b09_kana_091:
    .incbin "build/assets/bank09_kana.bin", $02D8, $0008

b09_kana_092:
    .incbin "build/assets/bank09_kana.bin", $02E0, $0008

b09_kana_093:
    .incbin "build/assets/bank09_kana.bin", $02E8, $0008

b09_kana_094:
    .incbin "build/assets/bank09_kana.bin", $02F0, $0008

b09_kana_095:
    .incbin "build/assets/bank09_kana.bin", $02F8, $0008

b09_kana_096:
    .incbin "build/assets/bank09_kana.bin", $0300, $0008

b09_kana_097:
    .incbin "build/assets/bank09_kana.bin", $0308, $0008

b09_kana_098:
    .incbin "build/assets/bank09_kana.bin", $0310, $0008

b09_kana_099:
    .incbin "build/assets/bank09_kana.bin", $0318, $0008

b09_kana_100:
    .incbin "build/assets/bank09_kana.bin", $0320, $0008

b09_kana_101:
    .incbin "build/assets/bank09_kana.bin", $0328, $0008

b09_kana_102:
    .incbin "build/assets/bank09_kana.bin", $0330, $0008

b09_kana_103:
    .incbin "build/assets/bank09_kana.bin", $0338, $0008

b09_kana_104:
    .incbin "build/assets/bank09_kana.bin", $0340, $0008

b09_kana_105:
    .incbin "build/assets/bank09_kana.bin", $0348, $0008

b09_kana_106:
    .incbin "build/assets/bank09_kana.bin", $0350, $0008

b09_kana_107:
    .incbin "build/assets/bank09_kana.bin", $0358, $0008

b09_kana_108:
    .incbin "build/assets/bank09_kana.bin", $0360, $0008

b09_kana_109:
    .incbin "build/assets/bank09_kana.bin", $0368, $0008

b09_kana_110:
    .incbin "build/assets/bank09_kana.bin", $0370, $0008

b09_kana_111:
    .incbin "build/assets/bank09_kana.bin", $0378, $0008

b09_kana_112:
    .incbin "build/assets/bank09_kana.bin", $0380, $0008

b09_kana_113:
    .incbin "build/assets/bank09_kana.bin", $0388, $0008

b09_kana_114:
    .incbin "build/assets/bank09_kana.bin", $0390, $0008

b09_kana_115:
    .incbin "build/assets/bank09_kana.bin", $0398, $0008

b09_kana_116:
    .incbin "build/assets/bank09_kana.bin", $03A0, $0008

b09_kana_117:
    .incbin "build/assets/bank09_kana.bin", $03A8, $0008

b09_kana_118:
    .incbin "build/assets/bank09_kana.bin", $03B0, $0008

b09_kana_119:
    .incbin "build/assets/bank09_kana.bin", $03B8, $0008

b09_kana_120:
    .incbin "build/assets/bank09_kana.bin", $03C0, $0008

b09_kana_121:
    .incbin "build/assets/bank09_kana.bin", $03C8, $0008

b09_kana_122:
    .incbin "build/assets/bank09_kana.bin", $03D0, $0008

b09_kana_123:
    .incbin "build/assets/bank09_kana.bin", $03D8, $0008

b09_kana_124:
    .incbin "build/assets/bank09_kana.bin", $03E0, $0008

b09_kana_125:
    .incbin "build/assets/bank09_kana.bin", $03E8, $0008

b09_kana_126:
    .incbin "build/assets/bank09_kana.bin", $03F0, $0008

b09_kana_127:
    .incbin "build/assets/bank09_kana.bin", $03F8, $0008

b09_ui_graphics2:
; editable source: assets/graphics/bank09_ui_b.png (chr2)
.ifdef KANJI_TARGET
    ; Step B, decision 11 (INFO_SCREEN.md): the same block with every UI
    ; glyph ($EF-$FA: bars, M, S, P, dot) moved to plane 1, made by
    ; tools/kanji_build.py from the PNG's build output.
    .incbin "build/kanji/bank09_ui_b_k.bin", $0000, $0200
.else
    .incbin "build/assets/bank09_ui_b.bin", $0000, $0200
.endif

