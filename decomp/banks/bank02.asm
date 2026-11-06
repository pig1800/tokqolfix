; ======================================================================
; PRG bank 02  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$800F  b02_header: Bank 2 padding/header bytes.
;   $8010-$880F  b02_kanji_glyphs: Raw 16x16 kanji glyphs: 32 glyphs, 64 bytes each.
;   $8810-$BFFF  b02_chr: Portrait/title tile graphics.
; ======================================================================

; Region aliases
b02_kanji_glyphs = $8010


b02_header:
; editable source: assets/data/bank02_header.bin (bin)
    .incbin "build/assets/bank02_header.bin", $0000, $0010

b02_kanji_000:
; editable source: assets/fonts/kanji_16x16_bank02.png (glyph16)
    .incbin "build/assets/bank02_kanji.bin", $0000, $0040

b02_kanji_001:
    .incbin "build/assets/bank02_kanji.bin", $0040, $0040

b02_kanji_002:
    .incbin "build/assets/bank02_kanji.bin", $0080, $0040

b02_kanji_003:
    .incbin "build/assets/bank02_kanji.bin", $00C0, $0040

b02_kanji_004:
    .incbin "build/assets/bank02_kanji.bin", $0100, $0040

b02_kanji_005:
    .incbin "build/assets/bank02_kanji.bin", $0140, $0040

b02_kanji_006:
    .incbin "build/assets/bank02_kanji.bin", $0180, $0040

b02_kanji_007:
    .incbin "build/assets/bank02_kanji.bin", $01C0, $0040

b02_kanji_008:
    .incbin "build/assets/bank02_kanji.bin", $0200, $0040

b02_kanji_009:
    .incbin "build/assets/bank02_kanji.bin", $0240, $0040

b02_kanji_010:
    .incbin "build/assets/bank02_kanji.bin", $0280, $0040

b02_kanji_011:
    .incbin "build/assets/bank02_kanji.bin", $02C0, $0040

b02_kanji_012:
    .incbin "build/assets/bank02_kanji.bin", $0300, $0040

b02_kanji_013:
    .incbin "build/assets/bank02_kanji.bin", $0340, $0040

b02_kanji_014:
    .incbin "build/assets/bank02_kanji.bin", $0380, $0040

b02_kanji_015:
    .incbin "build/assets/bank02_kanji.bin", $03C0, $0040

b02_kanji_016:
    .incbin "build/assets/bank02_kanji.bin", $0400, $0040

b02_kanji_017:
    .incbin "build/assets/bank02_kanji.bin", $0440, $0040

b02_kanji_018:
    .incbin "build/assets/bank02_kanji.bin", $0480, $0040

b02_kanji_019:
    .incbin "build/assets/bank02_kanji.bin", $04C0, $0040

b02_kanji_020:
    .incbin "build/assets/bank02_kanji.bin", $0500, $0040

b02_kanji_021:
    .incbin "build/assets/bank02_kanji.bin", $0540, $0040

b02_kanji_022:
    .incbin "build/assets/bank02_kanji.bin", $0580, $0040

b02_kanji_023:
    .incbin "build/assets/bank02_kanji.bin", $05C0, $0040

b02_kanji_024:
    .incbin "build/assets/bank02_kanji.bin", $0600, $0040

b02_kanji_025:
    .incbin "build/assets/bank02_kanji.bin", $0640, $0040

b02_kanji_026:
    .incbin "build/assets/bank02_kanji.bin", $0680, $0040

b02_kanji_027:
    .incbin "build/assets/bank02_kanji.bin", $06C0, $0040

b02_kanji_028:
    .incbin "build/assets/bank02_kanji.bin", $0700, $0040

b02_kanji_029:
    .incbin "build/assets/bank02_kanji.bin", $0740, $0040

b02_kanji_030:
    .incbin "build/assets/bank02_kanji.bin", $0780, $0040

b02_kanji_031:
    .incbin "build/assets/bank02_kanji.bin", $07C0, $0040

b02_chr:
; editable source: assets/graphics/bank02_chr.png (chr2)
    .incbin "build/assets/bank02_gfx.bin", $0000, $0400

b02_data_8C10:
    .incbin "build/assets/bank02_gfx.bin", $0400, $0400

b02_data_9010:
    .incbin "build/assets/bank02_gfx.bin", $0800, $0400

b02_data_9410:
    .incbin "build/assets/bank02_gfx.bin", $0C00, $0400

b02_data_9810:
    .incbin "build/assets/bank02_gfx.bin", $1000, $0400

b02_data_9C10:
    .incbin "build/assets/bank02_gfx.bin", $1400, $0400

b02_data_A010:
    .incbin "build/assets/bank02_gfx.bin", $1800, $0400

b02_data_A410:
    .incbin "build/assets/bank02_gfx.bin", $1C00, $0400

b02_data_A810:
    .incbin "build/assets/bank02_gfx.bin", $2000, $0400

b02_data_AC10:
    .incbin "build/assets/bank02_gfx.bin", $2400, $0400

b02_data_B010:
    .incbin "build/assets/bank02_gfx.bin", $2800, $0400

b02_data_B410:
    .incbin "build/assets/bank02_gfx.bin", $2C00, $0400

b02_data_B810:
    .incbin "build/assets/bank02_gfx.bin", $3000, $0400

b02_data_BC10:
    .incbin "build/assets/bank02_gfx.bin", $3400, $03F0

