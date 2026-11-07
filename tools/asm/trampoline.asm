.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"
.include "../../decomp/build/kanji/trampoline_hooks.inc"

.base $BF00
.org $BF00

; ----------------------------------------------------------------------
; F8 trampoline body, one identical copy in banks 10 and 11.
;
; The fixed-bank far head has mapped text_window_x (10 or 11) and jumped
; here.  Read the five inline operands, install the RAM band routines,
; map the text bank, switch CHR register 1 to the band page, and enter
; the overlay at $B800.
; ----------------------------------------------------------------------
trampoline:
    txa
    pha
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

    ldx #0
@copy_ram:
    lda band_ram_src,x
    sta KANJI_BAND_RAM,x
    inx
    cpx #(band_ram_end-band_ram_src)
    bne @copy_ram
    ldx #0
@copy_wait:
    lda band_wait_src,x
    sta KANJI_BAND_WAIT,x
    inx
    cpx #(band_wait_end-band_wait_src)
    bne @copy_wait
    ldx #0
@copy_cell:
    lda cell_check_src,x
    sta KANJI_CELL_CHECK,x
    inx
    cpx #(cell_check_end-cell_check_src)
    bne @copy_cell
    ldx #0
@copy_cellx:
    lda cell_check_x_src,x
    sta KANJI_CELL_CHECK_X,x
    inx
    cpx #(cell_check_x_end-cell_check_x_src)
    bne @copy_cellx

    ; Restore X, then pass the text bank to the fixed-bank enter_text.
    pla
    tax
    lda KANJI_TEXT_BANK
    sta text_window_x
    jmp ENTER_TEXT

; Source for the 8-byte RAM trampoline at KANJI_BAND_RAM ($0158):
; switch to the scene page, then run the calibrated wait and switch to
; the band page.
band_ram_src:
    lda #1
    jsr WRITE_CHR1
    jmp KANJI_BAND_WAIT
band_ram_end:

; Source for the 14-byte delay loop at KANJI_BAND_WAIT ($0170).
; Calibrated so the CHR-register write lands on the window's top border
; row (scanlines 144-151).  X/Y and the immediate constants are tuned by
; tools/lua/band_switch.lua.
band_wait_src:
    ldx #0
    ldy #14
@wait:
    dex
    bne @wait
    dey
    bne @wait
    lda #2
    jmp WRITE_CHR1
band_wait_end:

; Source for the 6-byte renderer control test at KANJI_CELL_CHECK ($01EC).
cell_check_src:
    lda $0300,y
    cmp #$FA
    rts
cell_check_end:
cell_check_x_src:
    lda $0319,x
    cmp #$FA
    rts
cell_check_x_end:
