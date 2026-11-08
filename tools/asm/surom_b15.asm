; ======================================================================
; Patched fixed-bank support code for the kanji target (revision 10).
;
; The dispatchers live in four audited gaps:
;
;   $C611-$C676  SUROM write_prg_bank, F8 far head, call_hack, NMI entry
;   $C4BA-$C4CA  block-writer hook (dead original write_prg_bank body)
;   $E6B3-$E6C3  reset hook (zero table padding, never read on the path)
;   $FFE0-$FFEF  band hook (zero padding before the vectors)
;
; There is no CHR-register write, no RAM code, no NMI lock and no queue
; hook here.  The actual work lives in hack banks 23/24, reached through
; call_hack with the game's own bank-lock protocol.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

.base $C000
.base $C611

; ----------------------------------------------------------------------
; SUROM write_prg_bank.  A = low 4 PRG bits plus outer bit 4; writes the
; outer bit through CHR bank 0, then the low four PRG bits.  X and Y are
; preserved because the game's set_bank_lock calls this from every bank.
; ----------------------------------------------------------------------
surom_write_prg_bank:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda $0103,x          ; saved A
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
    tay
    pla
    tax
    pla
    lda #0
    rts

; ----------------------------------------------------------------------
; F8 far head.  The message stub in banks 10/11 is
;   F8 <far_head> <text bank> <text addr> <meta addr>
; Map the bank holding the message stub and run the trampoline at $BF00.
; ----------------------------------------------------------------------
far_head:
    lda text_window_x
    jsr SET_BANK_B
    jmp $BF00

; ----------------------------------------------------------------------
; call_hack.  A = function number.  Map hack bank 23, call $8000, then
; restore the bank that was current.  The entry/exit mapper uses the
; game's lock protocol: set_bank_lock on the main thread, and
; restore_bank_after_nmi inside the NMI.
; ----------------------------------------------------------------------
call_hack:
    sta KANJI_FN
    lda current_prg_bank
    pha
    lda #23
    jsr map_hack
    jsr $8000
    pla
    jmp map_hack

map_hack:
    ldx KANJI_IN_NMI
    bne @nmi
    jmp SET_BANK_LOCK
@nmi:
    jmp RESTORE_BANK_AFTER_NMI

; ----------------------------------------------------------------------
; NMI entry, called where the original writes OAMDMA.  In split-screen
; frames (nmi_mode != 0) run the original DMA and nothing else.  In
; normal frames enter FN_ENTRY in the hack bank with IN_NMI set.
; ----------------------------------------------------------------------
nmi_entry:
    lda nmi_mode
    bne @plain
    lda #1
    sta KANJI_IN_NMI
    lda #CALL_HACK_FN_ENTRY
    jmp call_hack
@plain:
    lda #2
    sta OAMDMA
    rts

.base $C4BA

; ----------------------------------------------------------------------
; Block-writer hook.  Select CHR page 1 before the game writes CHR and
; record that the scene page changed.  Split-screen frames keep the
; original path with no added mapper work.
; ----------------------------------------------------------------------
c343_hook:
    lda nmi_mode
    bne @plain
    lda #CALL_HACK_FN_SCENE
    jsr call_hack
@plain:
    lda PPUSTATUS
    jmp $C346

.base $E6B3

; ----------------------------------------------------------------------
; Reset hook.  The game's reset code has bank 14 mapped but has just
; cleared current_prg_bank to zero, so restore that value before
; call_hack saves it.  IN_NMI is cleared so the main-thread mapper is
; selected even with random power-on RAM.
; ----------------------------------------------------------------------
reset_hook:
    lda #0
    sta KANJI_IN_NMI
    lda #$0E
    sta current_prg_bank
    lda #CALL_HACK_FN_RESET
    jmp call_hack

.base $FFE0

; ----------------------------------------------------------------------
; NMI exit.  Replaces the first three bytes of the handler epilogue
; (pla / tay / pla) at $EF31.  The sound and task code have already run,
; so the sprite-0 poll now ends the handler and returns immediately:
; the next vblank is far away and cannot nest.
; ----------------------------------------------------------------------
exit_stub:
    lda #CALL_HACK_FN_BAND
    jsr call_hack
    pla
    tay
    pla
    jmp $EF34
