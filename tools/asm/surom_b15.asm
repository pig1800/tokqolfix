; ======================================================================
; Patched fixed-bank support code for the kanji target.
;
; Lives in the audited 102-byte unused gap $C611-$C676 of bank 15.  The
; layout is registered in tools/bank15_lint.py:
;
;   $C611-$C639  SUROM write_prg_bank replacement (41 bytes)
;   $C63A-$C641  far-loader stub (8 bytes)
;   $C642-$C64E  overlay signature check (13 bytes)
;   $C64F-$C659  NMI-palette guard (11 bytes)
;
; The guard stub exists because NMI can fire before the RAM overlay has been
; installed (fresh cartridge / random SRAM).  CHR work now runs only from the
; palette hook, after the NMI handler has read PPUSTATUS and disabled
; rendering, so the old pre-handler upload stub is gone.
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
; Far-loader stub.  The bank 10/11 trampoline is F8 3A C6, so the text
; engine takes the "high byte >= $80" path (set_bank_current) and does not
; clobber current_bank_a.  This stub maps bank 13 and enters the RAM copy
; of the far loader at $8317.
; ----------------------------------------------------------------------
far_stub:
    lda #$0D
    jsr SET_BANK_B
    jmp $8317

; ----------------------------------------------------------------------
; Return with Z=1 when the RAM overlay signature is valid, Z=0 otherwise.
; ----------------------------------------------------------------------
check_sig:
    lda KANJI_SIGNATURE
    cmp #KANJI_SIG0
    bne @no
    lda KANJI_SIGNATURE+1
    cmp #KANJI_SIG1
@no:
    rts

; ----------------------------------------------------------------------
; NMI entry guard.  Replaces "lda nmi_busy / bne $EEE0" at $EE7F.  Runs the
; bounded CHR job runner immediately with rendering disabled, then lets the
; original handler decide whether to do the full frame work.  Running here
; (rather than only from the palette hook) means a main-thread glyph upload
; cannot stall on a frame whose nmi_update_budget happens to be zero.
; ----------------------------------------------------------------------
nmi_entry_guard:
    jsr check_sig
    bne @orig
    jmp RAM_NMI_ENTRY
@orig:
    lda nmi_busy
    bne @busy
    jmp $EE83
@busy:
    jmp $EEE0

; ----------------------------------------------------------------------
; NMI palette guard.  Replaces "jsr flush_palette" at $EECB.  The CHR jobs
; normally ran at the top of the handler; this is a fallback for any NMI
; path that reaches the palette hook without the entry guard.
; ----------------------------------------------------------------------
nmi_palette_guard:
    jsr check_sig
    bne @orig
    jmp RAM_NMI_HOOK
@orig:
    jmp FLUSH_PALETTE
