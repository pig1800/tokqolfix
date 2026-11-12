; ======================================================================
; PRG bank 12  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$BFFF  b12_data_tables: Enemy/town/item/weapon data tables.
; ======================================================================


b12_data_tables:
; editable source: assets/data/bank12_tables.bin (bin)
    .incbin "build/assets/bank12_tables.bin", $0000, $0400

b12_data_8400:
    .incbin "build/assets/bank12_tables.bin", $0400, $0400

b12_data_8800:
    .incbin "build/assets/bank12_tables.bin", $0800, $0080

b12_data_8880:
    .incbin "build/assets/bank12_tables.bin", $0880, $0380

b12_data_8C00:
    .incbin "build/assets/bank12_tables.bin", $0C00, $0400

b12_data_9000:
    .incbin "build/assets/bank12_tables.bin", $1000, $0400

b12_data_9400:
    .incbin "build/assets/bank12_tables.bin", $1400, $0400

b12_data_9800:
    .incbin "build/assets/bank12_tables.bin", $1800, $0400

b12_data_9C00:
    .incbin "build/assets/bank12_tables.bin", $1C00, $0400

b12_data_A000:
    .incbin "build/assets/bank12_tables.bin", $2000, $03C8

b12_data_A3C8:
    .incbin "build/assets/bank12_tables.bin", $23C8, $0038

b12_data_A400:
    .incbin "build/assets/bank12_tables.bin", $2400, $0038

b12_data_A438:
    .incbin "build/assets/bank12_tables.bin", $2438, $02C8

b12_data_A700:
    .incbin "build/assets/bank12_tables.bin", $2700, $0020

b12_data_A720:
    .incbin "build/assets/bank12_tables.bin", $2720, $00E0

b12_data_A800:
    .incbin "build/assets/bank12_tables.bin", $2800, $0100

b12_data_A900:
; The kanji target: the officer records' name glyph bytes point into the
; name font (tools/kanji_build.py build_name_font).
.ifdef KANJI_TARGET
    .incbin "build/kanji/bank12_names.bin", $0000, $0300
.else
    .incbin "build/assets/bank12_tables.bin", $2900, $0300
.endif

b12_data_AC00:
.ifdef KANJI_TARGET
    .incbin "build/kanji/bank12_names.bin", $0300, $0400
.else
    .incbin "build/assets/bank12_tables.bin", $2C00, $0400
.endif

b12_data_B000:
.ifdef KANJI_TARGET
    .incbin "build/kanji/bank12_names.bin", $0700, $0400
.else
    .incbin "build/assets/bank12_tables.bin", $3000, $0400
.endif

b12_data_B400:
.ifdef KANJI_TARGET
    .incbin "build/kanji/bank12_names.bin", $0B00, $0182
.else
    .incbin "build/assets/bank12_tables.bin", $3400, $0182
.endif

b12_data_B582:
.ifdef KANJI_TARGET
    .incbin "build/kanji/bank12_names.bin", $0C82, $027E
.else
    .incbin "build/assets/bank12_tables.bin", $3582, $027E
.endif

b12_data_B800:
.ifdef KANJI_TARGET
    .incbin "build/kanji/bank12_names.bin", $0F00, $0400
.else
    .incbin "build/assets/bank12_tables.bin", $3800, $0400
.endif

b12_data_BC00:
.ifdef KANJI_TARGET
    .incbin "build/kanji/bank12_names.bin", $1300, $0400
.else
    .incbin "build/assets/bank12_tables.bin", $3C00, $0400
.endif

