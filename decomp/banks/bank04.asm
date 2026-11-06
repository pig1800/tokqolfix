; ======================================================================
; PRG bank 04  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$BFFF  b04_chr: Portrait tile graphics.
; ======================================================================


b04_chr:
; editable source: assets/graphics/bank04_chr.png (chr2)
    .incbin "build/assets/bank04_chr.bin", $0000, $0400

b04_data_8400:
    .incbin "build/assets/bank04_chr.bin", $0400, $0400

b04_data_8800:
    .incbin "build/assets/bank04_chr.bin", $0800, $0400

b04_data_8C00:
    .incbin "build/assets/bank04_chr.bin", $0C00, $0400

b04_data_9000:
    .incbin "build/assets/bank04_chr.bin", $1000, $0400

b04_data_9400:
    .incbin "build/assets/bank04_chr.bin", $1400, $0400

b04_data_9800:
    .incbin "build/assets/bank04_chr.bin", $1800, $0400

b04_data_9C00:
    .incbin "build/assets/bank04_chr.bin", $1C00, $0400

b04_data_A000:
    .incbin "build/assets/bank04_chr.bin", $2000, $0400

b04_data_A400:
    .incbin "build/assets/bank04_chr.bin", $2400, $0400

b04_data_A800:
    .incbin "build/assets/bank04_chr.bin", $2800, $0400

b04_data_AC00:
    .incbin "build/assets/bank04_chr.bin", $2C00, $0400

b04_data_B000:
    .incbin "build/assets/bank04_chr.bin", $3000, $0400

b04_data_B400:
    .incbin "build/assets/bank04_chr.bin", $3400, $0400

b04_data_B800:
    .incbin "build/assets/bank04_chr.bin", $3800, $0400

b04_data_BC00:
    .incbin "build/assets/bank04_chr.bin", $3C00, $0400

