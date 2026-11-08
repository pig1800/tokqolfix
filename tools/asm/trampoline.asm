; ======================================================================
; F8 trampoline body (revision 10), identical in PRG banks 10 and 11.
;
; The fixed-bank far head has mapped the bank holding the message stub and
; jumped to $BF00.  Read the five inline operands, map the text bank with
; the game's lock protocol (the pushed return lands at $B800), and enter
; the overlay.  No RAM code, no CHR-register write, no queue use.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

.base $BF00
.org $BF00

trampoline:
    ldy text_col
    lda ($51),y
    sta KANJI_TEXT_BANK
    iny
    lda ($51),y
    sta KANJI_TEXT_ADDR
    iny
    lda ($51),y
    sta KANJI_TEXT_ADDR+1
    iny
    lda ($51),y
    sta KANJI_PAGE_PTR
    iny
    lda ($51),y
    sta KANJI_PAGE_PTR+1

    ; The engine's later stub-bank references must use the text bank.
    lda KANJI_TEXT_BANK
    sta text_window_x

    ; Push $B7FF so SET_BANK_LOCK's rts enters the overlay at $B800.
    lda #$B7
    pha
    lda #$FF
    pha
    lda KANJI_TEXT_BANK
    jmp SET_BANK_LOCK
