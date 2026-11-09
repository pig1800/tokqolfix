; ======================================================================
; Patched fixed-bank support code for the kanji target (revision 11).
;
; Audited gaps of bank 15 (mirrored to bank 31):
;
;   $C5A6-$C6D1  load_text_graphics (its palette tables moved to the hack
;                bank), SUROM write_prg_bank, call_hack/map_hack,
;                block-writer hook
;   $C4BA-$C4CA  NMI hook at loc_EF08 (dead original write_prg_bank body)
;   $D291-$D2B6  NMI epilogue hook at loc_EF31 (dead original $EF-$F7
;                dispatcher, replaced by the overlay's text_dispatch)
;   $F00C-$F039  reset CHR/RAM setup, rewritten
;   $FFE0-$FFEF  block-writer original entry, overlay frame wait
;
; Nothing here runs before the game's own split-screen code: the NMI work
; is attached after the nmi_mode branch ($EF0B, normal frames only) and in
; the epilogue ($EF31, after every split loop has finished).
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

; ----------------------------------------------------------------------
.base $C5A6
; ----------------------------------------------------------------------

; load_text_graphics (original entry $C5A6, called by $CF13 / $CF47),
; rewritten in place: the palette tables it reads (data_C5EF, data_C6B2,
; data_C6C2) now live in hack bank 23 at KANJI_PAL_DATA, so it maps that
; bank (game lock protocol) around the copy.  Otherwise byte-for-byte the
; original logic; X is preserved, Y ends as the original's.  The table
; space ($C5EF-$C6D1) holds the code below.
load_text_graphics:
    txa
    pha
    lda current_prg_bank
    pha
    lda #KANJI_HACK_BANK
    jsr SET_BANK_LOCK
    jmp HACK_PAL_COPY           ; the table copy (Y as the original's);
ltg_copied:                     ; a jump there and back: no extra stack depth
    pla
    jsr SET_BANK_LOCK           ; preserves X and Y
    lda $A5
    beq @done
    ldy #$00
@mask:
    lsr a
    bcs @black
    iny
    iny
    iny
    iny
    cpy #$20
    bne @mask
    beq @done
@black:
    ldx #$04
@black4:
    pha
    lda #$0F
    sta $03E0,y
    pla
    iny
    dex
    bne @black4
    beq @mask
@done:
    sty vram_dma_pending
    lda #$00
    sta $A5
    pla
    tax
    rts

; SUROM write_prg_bank.  A = bank (bit 4 = outer 256 KiB half).  CHR
; register 0 carries the outer bit (its low bits keep sprite page 0), the
; PRG register the low four bits (bit 4 clear: PRG RAM stays enabled).
; The outer register is written only when the half changes (revision 15):
; $BFFF of the bank mapped now tells the half, from the hardware itself
; (every game bank 0-15 has $EE there, every hack/text bank 16-30 has
; $00; kanji_build.py checks this), so an NMI that switched banks in
; between cannot leave a stale copy behind.  X and Y are untouched and at
; most one stack byte is used: an NMI can interrupt a main-thread switch
; and nest a second one.  Returns A = 0.
surom_write_prg_bank:
    cmp #$10
    bcs @hi
    bit OUTER_MARK              ; N = 1: a game bank is mapped (outer 0)
    bpl @lo_outer
@prg:
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    rts
@lo_outer:
    pha
    lda #$00
    beq @outer
@hi:
    bit OUTER_MARK
    bpl @hi_prg                 ; upper half already mapped
    pha
    lda #$10
@outer:
    sta MMC1_CHR_BANK0
    sta MMC1_CHR_BANK0
    sta MMC1_CHR_BANK0
    sta MMC1_CHR_BANK0
    lsr a
    lsr a
    lsr a
    lsr a
    sta MMC1_CHR_BANK0
    pla
@hi_prg:
    and #$0F
    bpl @prg                    ; always

; NMI epilogue gate (jumped to from $EF31 in place of "pla / tay / pla").
; The hack's epilogue work is the band split and the split-mode reset;
; with neither, the frame skips the hack bank (and its two bank
; switches) entirely.
ef31_gate:
    lda nmi_busy
    bne @skip
    lda nmi_mode
    ora KANJI_BAND
    beq @skip
    jmp ef31_hook
@skip:
    pla
    tay
    pla
    jmp $EF34

; NMI hook gate at loc_EF08 (normal frames, jumped to from $EF0B).  With no
; band shown, no request pending, no VRAM queue traffic and no CHR
; animation step, the hack has nothing to track or do: skip the hack bank
; and run only the game's own sound-bank switch.  (KANJI_BAND = 0 implies
; FLAG_PAGE2 = 0: the NMI that clears the band also clears the flag; the
; game keeps OAM slot 0 hidden, so sprite 0 needs no write either.)
ef08_gate:
    lda KANJI_BAND
    ora KANJI_REQ
    bne @go
    lda $39
    cmp KANJI_LAST39
    bne @go
    lda vram_queue_read
    cmp KANJI_QPOS
    bne @go
    jmp ef08_tail
@go:
    jmp ef08_hook

; call_hack: A = function number.  Map hack bank 23, run its $8000
; dispatcher, then map the bank that was current.  Falls into map_hack.
call_hack:
    sta KANJI_FN
    lda current_prg_bank
    pha
    lda #KANJI_HACK_BANK
    jsr map_hack
    jsr $8000
    pla
; map_hack: A = bank.  Main thread (busy mode or NMI disabled): the game's
; set_bank_lock.  NMI: restore_bank_after_nmi.  Clobbers X.
map_hack:
    ldx nmi_busy
    bne @main
    ldx ppu_ctrl_shadow
    bpl @main
    jmp RESTORE_BANK_AFTER_NMI
@main:
    jmp SET_BANK_LOCK

; Kanji page flip (patched over $D1C8 "jsr text_draw_char", the wait after a
; <PAGE>).  After the player's button press, when the overlay has the next
; page of a kanji message pending, clear the window and restart at the top
; line: a page never shares the window (or its CHR tiles) with the one
; before it.  The original keeps scrolling line by line.
page_flip:
    jsr TEXT_DRAW_CHAR          ; prompt and wait, as the original
    bit KANJI_PAGES_LEFT        ; bit 7: the overlay has a page pending
    bpl window_done
; Blank the four text lines (8 tile rows at $0300), draw them with one pass
; of the engine's scroll (it maps the text bank again), top line next.
window_clear:
    ldx #8
@blank:
    txa
    pha
    jsr TEXT_REDRAW_LINES       ; rows move up one, the last row turns blank
    pla
    tax
    dex
    bne @blank
    ldx #$A8                    ; left border of all 8 rows (the shifter
@border:                        ; rewrites only the cells and right border)
    lda #$7D
    sta $0300,x
    txa
    sec
    sbc #$18
    tax
    bcs @border
    jsr scroll_text
    lda #0
    sta text_line
window_done:
    rts

; Block-writer hook (patched over loc_C343 "lda PPUSTATUS").  Main thread
; (rendering off): FN_BLOCK_PRE (CHR page 1, save parameters), the
; original body, FN_BLOCK_POST (copy the written tiles to the band page).
; NMI: the only block write there is flush_palette's CHR-animation step,
; which already ends near the bottom of vblank; select the scene page with
; a few register writes (no bank switching) and let the NMI hook mark the
; tiles stale afterwards (it sees $39 move).
c343_hook:
    lda nmi_busy
    bne @main
    lda ppu_ctrl_shadow
    bpl @main
    jsr chr1_scene
    jmp c343_plain
@main:
    lda #FN_BLOCK_PRE
    jsr call_hack
    jsr c343_plain
    lda #FN_BLOCK_POST
    jmp call_hack

; CHR register 1 = page 1 (scene) under the game's bank-switch protocol:
; reset the MMC1 shift register and clear bank_switch_lock, so a
; main-thread switch that this interrupted starts over (as after
; restore_bank_after_nmi).  Returns A = 0; X and Y untouched.  (Revision
; 16c: moved here from $E6B3-$E6C3, which is part of two battle tables.)
chr1_scene:
    inc MMC1_RESET_ADDR
    lda #1
    sta MMC1_CHR_BANK1
    lsr a
    sta bank_switch_lock
    sta MMC1_CHR_BANK1
    sta MMC1_CHR_BANK1
    sta MMC1_CHR_BANK1
    sta MMC1_CHR_BANK1
    rts

; ----------------------------------------------------------------------
.base $C4BA
; ----------------------------------------------------------------------

; NMI, normal frames, jumped to from $EF0B in place of
; "lda #$08 / jsr restore_bank_after_nmi" (vblank, after the game's PPU
; work).  Runs the hack bank's EF08 entry, maps the sound bank exactly as
; the original did, and returns to $EF10.  A jump, not a call, so the
; bank switches nest no deeper than the original's.
ef08_hook:
    lda #KANJI_HACK_BANK
    jsr RESTORE_BANK_AFTER_NMI
    jsr $8003
ef08_tail:
    lda #$08
    jsr RESTORE_BANK_AFTER_NMI
    jmp $EF10

; ----------------------------------------------------------------------
.base $D291
; ----------------------------------------------------------------------

; NMI epilogue, every frame (jumped to from $EF31 in place of
; "pla / tay / pla").  The sound code and every split loop are done.
ef31_hook:
    lda #KANJI_HACK_BANK
    jsr RESTORE_BANK_AFTER_NMI
    jsr $8006
    lda current_prg_bank
    jsr RESTORE_BANK_AFTER_NMI
    pla
    tay
    pla
    jmp $EF34

; F8 far head: the message stub in banks 10/11 is
;   F8 <far_head> <text bank> <text addr> <meta addr>
far_head:
    lda text_window_x
    jsr SET_BANK_B
    jmp $BF00

; Overlay helper: scroll the text window up one line with the engine's own
; routine (it waits frames), then map the text bank again.
scroll_text:
    jsr $D376                   ; text_scroll_up
    lda KANJI_TEXT_BANK
    jmp SET_BANK_LOCK

; ----------------------------------------------------------------------
.base $F00C
; ----------------------------------------------------------------------

; Reset: CHR register 1 = page 1, CHR register 0 = page 0 (lower outer
; half, as the original), clear the hack state $0103-$017F, then the
; game's own RAM clear at $F03A with A = 0, X = $F0 as before.
reset_chr:
    jsr chr1_scene
    sta MMC1_CHR_BANK0
    sta MMC1_CHR_BANK0
    sta MMC1_CHR_BANK0
    sta MMC1_CHR_BANK0
    sta MMC1_CHR_BANK0
    ldx #$7C
@clear:
    sta KANJI_MAINCHR,x
    dex
    bpl @clear
    ldx #$F0
    jmp $F03A

; text_render_cell, patched at $DBED (its "jmp loc_DC7C"): a row-buffer
; byte with bit 7 set ends the line in the original, whose tiles are all
; below $80.  The battle pool's kanji tiles $A4-$DF (revision 18) are drawn
; like any tile; every other byte keeps the original path.  In the dead
; tail of the rewritten reset code.
render_ctl:
    cmp #POOL_FIRST
    bcc @ctl
    cmp #POOL_LAST+1
    bcs @ctl
    jmp $DBEF                   ; queue the cell (top tile in A)
@ctl:
    jmp $DC7C                   ; end of line, as the original

; ----------------------------------------------------------------------
.base $FFE0
; ----------------------------------------------------------------------

; The original block-writer entry.
c343_plain:
    lda PPUSTATUS
    jmp $C346

; Overlay frame wait: yield one frame, then map the text bank again (other
; tasks may have switched banks while this one was suspended).
wait_text:
    jsr WAIT_VBLANK
    lda KANJI_TEXT_BANK
    jmp SET_BANK_LOCK
