; ======================================================================
; Far-text loader copied to $0600 by call_inline_block.
; Assembled for its runtime address ($0601) so relative branches are right.
;
; The F8 trampoline in banks 10/11 is:
;   F8 3A C6 <text bank> <text addr lo/hi> <meta ptr lo/hi>
; $C63A is the fixed-bank far stub, which maps bank 13 without touching
; current_bank_a.  This block installs the RAM overlay from bank 24 when its
; signature is missing, copies the kana font once, then calls the overlay's
; metadata loader and continues at the fixed-bank text loop.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

.base $0601
.org $0601
kanji_far:
    stx KANJI_BUFX

    ; ------------------------------------------------------------------
    ; Install the $7002 text-engine overlay from bank 24 if the signature
    ; is missing.  Copy the code first, then publish the signature word so
    ; an NMI cannot enter a half-copied overlay.
    ; ------------------------------------------------------------------
    lda KANJI_SIGNATURE
    cmp #KANJI_SIG0
    bne @install
    lda KANJI_SIGNATURE+1
    cmp #KANJI_SIG1
    beq @overlay_ok
@install:
    lda #KANJI_OVERLAY_BANK
    sta current_prg_bank
    pha
    lda ppu_ctrl_shadow
    and #$7F
    sta PPUCTRL
    pla
    jsr $C611
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda #<(KANJI_OVERLAY_SRC + 2)
    sta $10
    lda #>(KANJI_OVERLAY_SRC + 2)
    sta $11
    lda #<(KANJI_OVERLAY)
    sta $12
    lda #>(KANJI_OVERLAY)
    sta $13
    ldx #4                  ; 1024 bytes: code + padding
@page:
    ldy #0
@byte:
    lda ($10),y
    sta ($12),y
    iny
    bne @byte
    inc $11
    inc $13
    dex
    bne @page
    lda #KANJI_SIG0
    sta KANJI_SIGNATURE
    lda #KANJI_SIG1
    sta KANJI_SIGNATURE+1

@overlay_ok:
    ; ------------------------------------------------------------------
    ; One-time 1 KiB copy of the bank-9 kana font into SRAM.
    ; ------------------------------------------------------------------
    lda KANJI_KANA_READY
    cmp #KANA_SIG0
    bne @copy_kana
    lda KANJI_KANA_READY+1
    cmp #KANA_SIG1
    beq @meta
@copy_kana:
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
    lda #KANA_SIG0
    sta KANJI_KANA_READY
    lda #KANA_SIG1
    sta KANJI_KANA_READY+1

@meta:
    jsr RAM_META_LOAD

    lda KANJI_TMP2
    sta $51
    lda KANJI_TMP3
    sta $52
    lda #0
    sta text_col

    ldx KANJI_BUFX
    pla
    pla
    jmp TEXT_LINE_LOOP
