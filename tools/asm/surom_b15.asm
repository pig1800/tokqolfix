; ======================================================================
; Patched fixed-bank support code for the kanji target (revision 9).
;
; Lives in the audited unused gap $C611-$C676 of bank 15:
;
;   SUROM write_prg_bank replacement (CHR reg 0 = outer, PRG = bank)
;   far head: map text_window_x (10/11) and enter the trampoline at $BF00
;   CHR register 1 write helper (5-write MMC1 sequence)
;   NMI band stub ($EEDD): scene page, wait, band page at the window row
;   reset hook: clear the band state on power-on/soft reset
;
; The band delay loop itself lives in internal RAM ($0158/$0170) and is
; installed by the bank-10/11 trampoline.  cell_check moved to the overlay.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

.base $C611
.org $C611

; ----------------------------------------------------------------------
; SUROM write_prg_bank.  A = low 4 PRG bits plus outer bit 4; writes the
; outer bit through CHR bank 0, then the low four PRG bits.  NMI_LOCK
; covers the serial sequence so the NMI band stub never writes CHR reg 1
; in the middle of it.
; ----------------------------------------------------------------------
surom_write_prg_bank_b15:
    pha
    tya
    pha
    txa
    pha
    tsx
    lda $0103,x
    tay
    inc KANJI_NMI_LOCK
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
    dec KANJI_NMI_LOCK
    pla
    tax
    pla
    tay
    pla
    lda #0
    rts

; ----------------------------------------------------------------------
; F8 head.  The message stub in banks 10/11 is
;   F8 <far_head> <text bank> <text addr> <meta addr>
; Map the bank holding the message stub, then run the trampoline body at
; $BF00 (identical in banks 10 and 11).
; ----------------------------------------------------------------------
far_head:
    lda text_window_x
    jsr SET_BANK_B
    jmp $BF00

; ----------------------------------------------------------------------
; Enter the text overlay after the bank-10/11 body has stored the text
; bank.  This routine stays in the fixed bank while SET_BANK_B swaps the
; window, so the jump to $B800 executes from mapped-to-fixed code.
; A = text bank.
; ----------------------------------------------------------------------
enter_text:
    jsr SET_BANK_B
    jmp RAM_OVERLAY_ENTRY

; ----------------------------------------------------------------------
; NMI band stub, reached from the patched $EEDD call.
; Always enables NMI first; while a message is open and no bank switch is
; in flight, run the RAM scene/delay/band routine.  That routine returns
; to $EEE0 through this call's return address.
; ----------------------------------------------------------------------
band_stub:
    jsr PPU_NMI_ON
    lda KANJI_BAND_ON
    beq @done
    lda KANJI_NMI_LOCK
    bne @done
    jmp KANJI_BAND_RAM
@done:
    rts

; ----------------------------------------------------------------------
; Write A to MMC1 CHR register 1 (five serial writes).  The fixed-bank
; copy is used by the RAM band routines so they work while any PRG bank
; (including the font bank) is mapped.
; ----------------------------------------------------------------------
write_chr1:
    ldx #5
@write:
    sta MMC1_CHR_BANK1
    lsr a
    dex
    bne @write
    rts

; ----------------------------------------------------------------------
; Reset hook.  The reset code jumps here with A=0 requested and expects
; A=0, X=$F0 on return.  Clear the band state so a power-on never runs an
; uninitialised RAM routine from the NMI.
; ----------------------------------------------------------------------
reset_extra:
    lda #0
    sta KANJI_BAND_READY
    sta KANJI_BAND_ON
    sta KANJI_NMI_LOCK
    ldx #$F0
    rts

