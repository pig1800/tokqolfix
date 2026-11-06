; SUROM write_prg_bank replacement for the kanji target.
; Assembled at $C611, inside a 102-byte unused gap in bank 15's data table.
; Bank 15 patches $C4B7 with JMP $C611; the bank-31 copy inherits the same
; bytes, so fixed-bank code can switch the outer bit from either half.
.include "../../decomp/include/hardware.inc"

.base $C611
.org $C611
surom_write_prg_bank_b15:
    pha
    tya
    pha
    txa
    pha
    tsx
    lda $0103,x
    tay
    and #$10
    ldx #5
@chr:
    sta MMC1_CHR_BANK0
    lsr a
    dex
    bne @chr
    tya
    and #$0F
    ldx #5
@prg:
    sta MMC1_PRG_BANK
    lsr a
    dex
    bne @prg
    pla
    tax
    pla
    tay
    pla
    lda #0
    rts
