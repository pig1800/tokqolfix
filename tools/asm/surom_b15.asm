; ======================================================================
; Patched fixed-bank support code for the kanji target.
;
; Lives in the audited unused gap $C611-$C676 of bank 15:
;
;   $C611-$C639  SUROM write_prg_bank replacement (41 bytes)
;   $C63A-$C668  F8 trampoline + cell check
;
; There is no NMI code and no signature check: the text-engine overlay is
; ROM-resident in every text bank and all hack state is in internal RAM.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

.base $C611
.org $C611

; ----------------------------------------------------------------------
; SUROM write_prg_bank.  A = low 4 PRG bits plus outer bit 4; also writes
; the outer bit through CHR bank 0 before the low four PRG bits.
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

; ----------------------------------------------------------------------
; F8 trampoline.  The message stub in bank 10/11 is
;   F8 3A C6 <text bank> <text addr lo/hi> <meta addr lo/hi>
; The engine has already advanced text_col by three; read the five inline
; bytes, map the text bank, and enter the overlay at $B800.
; ----------------------------------------------------------------------
.org $C63A
far_stub:
    ; The inline operands live in the bank-10/11 message stub.  The engine
    ; mapped current_bank_a (which is not necessarily the message bank), so
    ; map text_window_x (10 or 11) before reading them.
    lda text_window_x
    jsr SET_BANK_B
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
    lda KANJI_TEXT_BANK
    sta text_window_x
    jsr SET_BANK_B
    jmp RAM_OVERLAY_ENTRY

; ----------------------------------------------------------------------
; Cell-buffer tile test for text_render_cell.  Replaces the original
; "lda $0300,y / bpl" pair: tiles $00-$F9 are tile numbers, $FA-$FF stay
; control codes.  Carry is set for $FA-$FF so the patched caller uses bcc.
; ----------------------------------------------------------------------
cell_check:
    lda $0300,y
    cmp #$FA
    rts
