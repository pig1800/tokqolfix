; ======================================================================
; PRG bank 00  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$BFFF  b00_chr: Character/sprite/background tile bank.
; ======================================================================


b00_chr:
; editable source: assets/graphics/bank00_chr.png (chr2)
    .incbin "build/assets/bank00_chr.bin", $0000, $0400

b00_data_8400:
    .incbin "build/assets/bank00_chr.bin", $0400, $0280

b00_status_name_000:
    .incbin "build/assets/bank00_chr.bin", $0680, $0040

b00_status_name_001:
    .incbin "build/assets/bank00_chr.bin", $06C0, $0040

b00_status_names_end:
    .incbin "build/assets/bank00_chr.bin", $0700, $0100

b00_data_8800:
    .incbin "build/assets/bank00_chr.bin", $0800, $0400

b00_data_8C00:
    .incbin "build/assets/bank00_chr.bin", $0C00, $0400

b00_data_9000:
    .incbin "build/assets/bank00_chr.bin", $1000, $0400

b00_data_9400:
    .incbin "build/assets/bank00_chr.bin", $1400, $0400

b00_data_9800:
    .incbin "build/assets/bank00_chr.bin", $1800, $0400

b00_data_9C00:
    .incbin "build/assets/bank00_chr.bin", $1C00, $0400

b00_data_A000:
    .incbin "build/assets/bank00_chr.bin", $2000, $0400

b00_data_A400:
    .incbin "build/assets/bank00_chr.bin", $2400, $0400

b00_data_A800:
    .incbin "build/assets/bank00_chr.bin", $2800, $0400

b00_data_AC00:
    .incbin "build/assets/bank00_chr.bin", $2C00, $0400

b00_data_B000:
    .incbin "build/assets/bank00_chr.bin", $3000, $0400

b00_data_B400:
    .incbin "build/assets/bank00_chr.bin", $3400, $0400

b00_data_B800:
    .incbin "build/assets/bank00_chr.bin", $3800, $0400

b00_data_BC00:
    .incbin "build/assets/bank00_chr.bin", $3C00, $0400

