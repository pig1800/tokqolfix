; ======================================================================
; F8 trampoline body (revision 10; 2026-11-14 the text chunks), identical
; in PRG banks 10 and 11.
;
; The fixed-bank far head has mapped the bank holding the message stub and
; jumped to $BF00.  The stub (kanji_text.py) is
;   F8 <far_head> <text chunk | bit 7: a victory message> <text addr>
; Read the three operands, make the message bank (MSG_BANK: the message
; engine at R6, the text chunk at R7; mmc3_b15.asm main_prg) the engine's
; message bank and map it with the game's lock protocol, whose rts enters
; the message engine (the hack bank's MSG_ENTRY).  No RAM code, no
; CHR-register write, no queue use.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

.base $BF00
.org $BF00

trampoline:                     ; (X: the engine's line-buffer index, kept)
    ldy text_col
    lda ($51),y
    and #$3F
    sta KANJI_TEXT_CHUNK
    lda ($51),y
    and #$80                    ; the victory flag -> MSG_WIN, until the
    lsr a                       ; message's setup (the rest of the byte:
    lsr a                       ; no page pending, not the pool)
    sta KANJI_PAGES_LEFT
    iny
    lda ($51),y
    sta KANJI_TEXT_ADDR
    iny
    lda ($51),y
    sta KANJI_TEXT_ADDR+1

    ; The engine's later message-bank references map the message bank.
    lda #MSG_BANK
    sta text_window_x

    ; Push MSG_ENTRY - 1 so SET_BANK_LOCK's rts enters the message engine.
    lda #>(MSG_ENTRY-1)
    pha
    lda #<(MSG_ENTRY-1)
    pha
    lda #MSG_BANK
    jmp SET_BANK_LOCK
