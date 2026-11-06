; ======================================================================
; PRG bank 01  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$800F  b01_header: Bank 1 padding/header bytes.
;   $8010-$9A0F  b01_kanji_glyphs: Raw 16x16 kanji glyphs: 104 glyphs, 64 bytes each.
;   $9A10-$BFFF  b01_chr: Character/battle-animation tile graphics.
; ======================================================================

; Region aliases
b01_kanji_glyphs = $8010


b01_header:
; editable source: assets/data/bank01_header.bin (bin)
    .incbin "build/assets/bank01_header.bin", $0000, $0010

b01_kanji_000:
; editable source: assets/fonts/kanji_16x16_bank01.png (glyph16)
    .incbin "build/assets/bank01_kanji.bin", $0000, $0040

b01_kanji_001:
    .incbin "build/assets/bank01_kanji.bin", $0040, $0040

b01_kanji_002:
    .incbin "build/assets/bank01_kanji.bin", $0080, $0040

b01_kanji_003:
    .incbin "build/assets/bank01_kanji.bin", $00C0, $0040

b01_kanji_004:
    .incbin "build/assets/bank01_kanji.bin", $0100, $0040

b01_kanji_005:
    .incbin "build/assets/bank01_kanji.bin", $0140, $0040

b01_kanji_006:
    .incbin "build/assets/bank01_kanji.bin", $0180, $0040

b01_kanji_007:
    .incbin "build/assets/bank01_kanji.bin", $01C0, $0040

b01_kanji_008:
    .incbin "build/assets/bank01_kanji.bin", $0200, $0040

b01_kanji_009:
    .incbin "build/assets/bank01_kanji.bin", $0240, $0040

b01_kanji_010:
    .incbin "build/assets/bank01_kanji.bin", $0280, $0040

b01_kanji_011:
    .incbin "build/assets/bank01_kanji.bin", $02C0, $0040

b01_kanji_012:
    .incbin "build/assets/bank01_kanji.bin", $0300, $0040

b01_kanji_013:
    .incbin "build/assets/bank01_kanji.bin", $0340, $0040

b01_kanji_014:
    .incbin "build/assets/bank01_kanji.bin", $0380, $0040

b01_kanji_015:
    .incbin "build/assets/bank01_kanji.bin", $03C0, $0040

b01_kanji_016:
    .incbin "build/assets/bank01_kanji.bin", $0400, $0040

b01_kanji_017:
    .incbin "build/assets/bank01_kanji.bin", $0440, $0040

b01_kanji_018:
    .incbin "build/assets/bank01_kanji.bin", $0480, $0040

b01_kanji_019:
    .incbin "build/assets/bank01_kanji.bin", $04C0, $0040

b01_kanji_020:
    .incbin "build/assets/bank01_kanji.bin", $0500, $0040

b01_kanji_021:
    .incbin "build/assets/bank01_kanji.bin", $0540, $0040

b01_kanji_022:
    .incbin "build/assets/bank01_kanji.bin", $0580, $0040

b01_kanji_023:
    .incbin "build/assets/bank01_kanji.bin", $05C0, $0040

b01_kanji_024:
    .incbin "build/assets/bank01_kanji.bin", $0600, $0040

b01_kanji_025:
    .incbin "build/assets/bank01_kanji.bin", $0640, $0040

b01_kanji_026:
    .incbin "build/assets/bank01_kanji.bin", $0680, $0040

b01_kanji_027:
    .incbin "build/assets/bank01_kanji.bin", $06C0, $0040

b01_kanji_028:
    .incbin "build/assets/bank01_kanji.bin", $0700, $0040

b01_kanji_029:
    .incbin "build/assets/bank01_kanji.bin", $0740, $0040

b01_kanji_030:
    .incbin "build/assets/bank01_kanji.bin", $0780, $0040

b01_kanji_031:
    .incbin "build/assets/bank01_kanji.bin", $07C0, $0040

b01_kanji_032:
    .incbin "build/assets/bank01_kanji.bin", $0800, $0040

b01_kanji_033:
    .incbin "build/assets/bank01_kanji.bin", $0840, $0040

b01_kanji_034:
    .incbin "build/assets/bank01_kanji.bin", $0880, $0040

b01_kanji_035:
    .incbin "build/assets/bank01_kanji.bin", $08C0, $0040

b01_kanji_036:
    .incbin "build/assets/bank01_kanji.bin", $0900, $0040

b01_kanji_037:
    .incbin "build/assets/bank01_kanji.bin", $0940, $0040

b01_kanji_038:
    .incbin "build/assets/bank01_kanji.bin", $0980, $0040

b01_kanji_039:
    .incbin "build/assets/bank01_kanji.bin", $09C0, $0040

b01_kanji_040:
    .incbin "build/assets/bank01_kanji.bin", $0A00, $0040

b01_kanji_041:
    .incbin "build/assets/bank01_kanji.bin", $0A40, $0040

b01_kanji_042:
    .incbin "build/assets/bank01_kanji.bin", $0A80, $0040

b01_kanji_043:
    .incbin "build/assets/bank01_kanji.bin", $0AC0, $0040

b01_kanji_044:
    .incbin "build/assets/bank01_kanji.bin", $0B00, $0040

b01_kanji_045:
    .incbin "build/assets/bank01_kanji.bin", $0B40, $0040

b01_kanji_046:
    .incbin "build/assets/bank01_kanji.bin", $0B80, $0040

b01_kanji_047:
    .incbin "build/assets/bank01_kanji.bin", $0BC0, $0040

b01_kanji_048:
    .incbin "build/assets/bank01_kanji.bin", $0C00, $0040

b01_kanji_049:
    .incbin "build/assets/bank01_kanji.bin", $0C40, $0040

b01_kanji_050:
    .incbin "build/assets/bank01_kanji.bin", $0C80, $0040

b01_kanji_051:
    .incbin "build/assets/bank01_kanji.bin", $0CC0, $0040

b01_kanji_052:
    .incbin "build/assets/bank01_kanji.bin", $0D00, $0040

b01_kanji_053:
    .incbin "build/assets/bank01_kanji.bin", $0D40, $0040

b01_kanji_054:
    .incbin "build/assets/bank01_kanji.bin", $0D80, $0040

b01_kanji_055:
    .incbin "build/assets/bank01_kanji.bin", $0DC0, $0040

b01_kanji_056:
    .incbin "build/assets/bank01_kanji.bin", $0E00, $0040

b01_kanji_057:
    .incbin "build/assets/bank01_kanji.bin", $0E40, $0040

b01_kanji_058:
    .incbin "build/assets/bank01_kanji.bin", $0E80, $0040

b01_kanji_059:
    .incbin "build/assets/bank01_kanji.bin", $0EC0, $0040

b01_kanji_060:
    .incbin "build/assets/bank01_kanji.bin", $0F00, $0040

b01_kanji_061:
    .incbin "build/assets/bank01_kanji.bin", $0F40, $0040

b01_kanji_062:
    .incbin "build/assets/bank01_kanji.bin", $0F80, $0040

b01_kanji_063:
    .incbin "build/assets/bank01_kanji.bin", $0FC0, $0040

b01_kanji_064:
    .incbin "build/assets/bank01_kanji.bin", $1000, $0040

b01_kanji_065:
    .incbin "build/assets/bank01_kanji.bin", $1040, $0040

b01_kanji_066:
    .incbin "build/assets/bank01_kanji.bin", $1080, $0040

b01_kanji_067:
    .incbin "build/assets/bank01_kanji.bin", $10C0, $0040

b01_kanji_068:
    .incbin "build/assets/bank01_kanji.bin", $1100, $0040

b01_kanji_069:
    .incbin "build/assets/bank01_kanji.bin", $1140, $0040

b01_kanji_070:
    .incbin "build/assets/bank01_kanji.bin", $1180, $0040

b01_kanji_071:
    .incbin "build/assets/bank01_kanji.bin", $11C0, $0040

b01_kanji_072:
    .incbin "build/assets/bank01_kanji.bin", $1200, $0040

b01_kanji_073:
    .incbin "build/assets/bank01_kanji.bin", $1240, $0040

b01_kanji_074:
    .incbin "build/assets/bank01_kanji.bin", $1280, $0040

b01_kanji_075:
    .incbin "build/assets/bank01_kanji.bin", $12C0, $0040

b01_kanji_076:
    .incbin "build/assets/bank01_kanji.bin", $1300, $0040

b01_kanji_077:
    .incbin "build/assets/bank01_kanji.bin", $1340, $0040

b01_kanji_078:
    .incbin "build/assets/bank01_kanji.bin", $1380, $0040

b01_kanji_079:
    .incbin "build/assets/bank01_kanji.bin", $13C0, $0040

b01_kanji_080:
    .incbin "build/assets/bank01_kanji.bin", $1400, $0040

b01_kanji_081:
    .incbin "build/assets/bank01_kanji.bin", $1440, $0040

b01_kanji_082:
    .incbin "build/assets/bank01_kanji.bin", $1480, $0040

b01_kanji_083:
    .incbin "build/assets/bank01_kanji.bin", $14C0, $0040

b01_kanji_084:
    .incbin "build/assets/bank01_kanji.bin", $1500, $0040

b01_kanji_085:
    .incbin "build/assets/bank01_kanji.bin", $1540, $0040

b01_kanji_086:
    .incbin "build/assets/bank01_kanji.bin", $1580, $0040

b01_kanji_087:
    .incbin "build/assets/bank01_kanji.bin", $15C0, $0040

b01_kanji_088:
    .incbin "build/assets/bank01_kanji.bin", $1600, $0040

b01_kanji_089:
    .incbin "build/assets/bank01_kanji.bin", $1640, $0040

b01_kanji_090:
    .incbin "build/assets/bank01_kanji.bin", $1680, $0040

b01_kanji_091:
    .incbin "build/assets/bank01_kanji.bin", $16C0, $0040

b01_kanji_092:
    .incbin "build/assets/bank01_kanji.bin", $1700, $0040

b01_kanji_093:
    .incbin "build/assets/bank01_kanji.bin", $1740, $0040

b01_kanji_094:
    .incbin "build/assets/bank01_kanji.bin", $1780, $0040

b01_kanji_095:
    .incbin "build/assets/bank01_kanji.bin", $17C0, $0040

b01_kanji_096:
    .incbin "build/assets/bank01_kanji.bin", $1800, $0040

b01_kanji_097:
    .incbin "build/assets/bank01_kanji.bin", $1840, $0040

b01_kanji_098:
    .incbin "build/assets/bank01_kanji.bin", $1880, $0040

b01_kanji_099:
    .incbin "build/assets/bank01_kanji.bin", $18C0, $0040

b01_kanji_100:
    .incbin "build/assets/bank01_kanji.bin", $1900, $0040

b01_kanji_101:
    .incbin "build/assets/bank01_kanji.bin", $1940, $0040

b01_kanji_102:
    .incbin "build/assets/bank01_kanji.bin", $1980, $0040

b01_kanji_103:
    .incbin "build/assets/bank01_kanji.bin", $19C0, $0040

b01_chr:
; editable source: assets/graphics/bank01_chr.png (chr2)
    .incbin "build/assets/bank01_gfx.bin", $0000, $0400

b01_data_9E10:
    .incbin "build/assets/bank01_gfx.bin", $0400, $0400

b01_data_A210:
    .incbin "build/assets/bank01_gfx.bin", $0800, $0400

b01_data_A610:
    .incbin "build/assets/bank01_gfx.bin", $0C00, $0400

b01_data_AA10:
    .incbin "build/assets/bank01_gfx.bin", $1000, $0400

b01_data_AE10:
    .incbin "build/assets/bank01_gfx.bin", $1400, $0400

b01_data_B210:
    .incbin "build/assets/bank01_gfx.bin", $1800, $0400

b01_data_B610:
    .incbin "build/assets/bank01_gfx.bin", $1C00, $0400

b01_data_BA10:
    .incbin "build/assets/bank01_gfx.bin", $2000, $0400

b01_data_BE10:
    .incbin "build/assets/bank01_gfx.bin", $2400, $01F0

