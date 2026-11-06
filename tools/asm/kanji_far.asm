; ======================================================================
; Far-text loader copied to $0600 by call_inline_block.
; Assembled for its runtime address ($0601) so relative branches are right.
;
; The F8 trampoline in banks 10/11 is:
;   F8 17 03 <target bank> <target addr lo/hi> <meta ptr lo/hi>
; This block reads those bytes, copies the page-slot metadata to SRAM,
; switches to the target text bank (outer SUROM bank 1) and continues at
; the fixed-bank text loop.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

.base $0601
.org $0601
kanji_far:
    stx KANJI_BUFX
    lda KANJI_KANA_READY
    bne @meta

    ; One-time 1 KiB copy of the bank-9 kana font into SRAM.
    lda #9
    jsr SET_BANK_B
    lda #$00
    sta $10
    lda #$BA
    sta $11
    lda #<KANA_FONT
    sta $12
    lda #>KANA_FONT
    sta $13
    lda #4
    sta KANJI_COUNT
    ldy #0
@outer:
@inner:
    lda ($10),y
    sta ($12),y
    iny
    bne @inner
    inc $11
    inc $13
    dec KANJI_COUNT
    bne @outer
    inc KANJI_KANA_READY

@meta:
    lda text_window_x
    jsr SET_BANK_B

    ldy #3
    lda ($51),y
    sta KANJI_TEXT_BANK
    iny
    lda ($51),y
    sta KANJI_TMP2
    iny
    lda ($51),y
    sta KANJI_TMP3
    iny
    lda ($51),y
    sta $10
    iny
    lda ($51),y
    sta $11

    ; Metadata lives in bank 22 (low text bank) or 23 (high text bank).
    lda text_window_x
    sec
    sbc #10
    clc
    adc #22
    jsr @switch_outer

    ldy #1
    lda ($10),y
    sta KANJI_TMP0
    iny
    lda ($10),y
    sta KANJI_TMP1
    lda $10
    clc
    adc #3
    sta $10
    lda $11
    adc #0
    sta $11

    lda #<KANJI_META
    sta $12
    lda #>KANJI_META
    sta $13
@copy:
    lda KANJI_TMP0
    ora KANJI_TMP1
    beq @done
    ldy #0
    lda ($10),y
    sta ($12),y
    inc $10
    bne @src_ok
    inc $11
@src_ok:
    inc $12
    bne @dst_ok
    inc $13
@dst_ok:
    lda KANJI_TMP0
    bne @dec
    dec KANJI_TMP1
@dec:
    dec KANJI_TMP0
    jmp @copy

@done:
    lda #<KANJI_META
    sta KANJI_META_PTR
    lda #>KANJI_META
    sta KANJI_META_PTR+1
    lda KANJI_TMP2
    sta $51
    lda KANJI_TMP3
    sta $52
    lda #0
    sta text_col

    ; The fixed bank is now bank 31, whose write_prg_bank knows SUROM.
    lda KANJI_TEXT_BANK
    sta text_window_x
    jsr SET_BANK_B

    ldx KANJI_BUFX
    pla
    pla
    jmp TEXT_LINE_LOOP

; ----------------------------------------------------------------------
; A = outer bank 16-31.  Performs the first MMC1 switch from RAM while NMI
; is inhibited.  Later switches go through the bank-31 write_prg_bank.
; ----------------------------------------------------------------------
@switch_outer:
    pha
    lda ppu_ctrl_shadow
    and #$7F
    sta PPUCTRL
    pla
    sta current_prg_bank
    pha
    and #$10
    ldx #5
@chr:
    sta MMC1_CHR_BANK0
    lsr a
    dex
    bne @chr
    pla
    and #$0F
    ldx #5
@prg:
    sta MMC1_PRG_BANK
    lsr a
    dex
    bne @prg
    lda ppu_ctrl_shadow
    sta PPUCTRL
    rts
