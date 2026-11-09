; ======================================================================
; Patched fixed-bank support code for the kanji target (revision 11;
; MMC3 since revision 21).
;
; Audited gaps of bank 15 (bank 31, the fixed bank at $C000-$FFFF, is a
; copy):
;
;   $C5A6-$C6D1  load_text_graphics (its palette tables moved to the hack
;                bank), the MMC3 bank switches, call_hack/map_hack,
;                block-writer hook
;   $C460-$C47D  dead mmc1_reset / mmc1_init: render_ctl, chr1_scene
;   $C4BA-$C4CA  NMI hook at loc_EF08 (dead original write_prg_bank body)
;   $D291-$D2B6  NMI epilogue hook at loc_EF31 (dead original $EF-$F7
;                dispatcher, replaced by the overlay's text_dispatch)
;   $F004-$F039  reset mapper/RAM setup, rewritten
;   $FFE0-$FFEF  block-writer original entry, overlay frame wait
;
; MMC3 bank-switch protocol (revision 21).  MMC3_SEL ($EB, the game's MMC1
; bank_switch_lock, which only the rewritten switch routines used) holds the
; last value the main thread wrote to the bank-select register $8000.  The
; main thread stores it there before every $8000 write; interrupt code
; writes $8000 directly and leaves with $8000 = MMC3_SEL | $80
; (restore_bank_after_nmi does it last in every NMI that touched the
; mapper).  So an NMI between a main-thread select and its data write
; changes nothing: the data lands in the register the main thread chose.
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

; set_bank_lock body (jumped to from $C486, after "sta current_prg_bank";
; A = the 16 KiB bank).  Main thread: $8000-$9FFF = R6 = 2 * bank,
; $A000-$BFFF = R7 = 2 * bank + 1, MMC3_SEL stored before each select.
; X and Y untouched, one stack byte.  Returns as the original: A = 0,
; Z set, N clear, C = bit 3 of the bank, V unchanged.
main_prg:
    asl a
    pha
    lda #MMC3_R6
    sta MMC3_SEL
    sta MMC3_SELECT
    pla
    sta MMC3_DATA
    pha
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    pla
    ora #1
    sta MMC3_DATA
    lda current_prg_bank
    lsr a
    lsr a
    lsr a
    lsr a
    lda #0
    rts

; restore_bank_after_nmi body (jumped to from $C4AA; A = bank).  NMI only:
; MMC3_SEL stays the main thread's, and $8000 gets it back last.  Clobbers
; X (every caller reloads it).
nmi_prg:
    asl a
    tax
    lda #MMC3_R6
    sta MMC3_SELECT
    stx MMC3_DATA
    inx
    lda #MMC3_R7
    sta MMC3_SELECT
    stx MMC3_DATA
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
    rts

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

; ----------------------------------------------------------------------
.base $C460
; ----------------------------------------------------------------------

; text_render_cell, patched at $DBED (its "jmp loc_DC7C"): a row-buffer
; byte with bit 7 set ends the line in the original, whose tiles are all
; below $80.  The battle pool's kanji tiles $A4-$DF (revision 18) are drawn
; like any tile; every other byte keeps the original path.
render_ctl:
    cmp #POOL_FIRST
    bcc @ctl
    cmp #POOL_LAST+1
    bcs @ctl
    jmp $DBEF                   ; queue the cell (top tile in A)
@ctl:
    jmp $DC7C                   ; end of line, as the original

; BG tiles $00-$7F = the scene page (R0).  NMI only (c343_hook): $8000 is
; given back by the restore_bank_after_nmi that ends every such NMI.
; X and Y untouched.
chr1_scene:
    lda #MMC3_R0
    sta MMC3_SELECT
    lda #CHR_SCENE_LO
    sta MMC3_DATA
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
.base $F004
; ----------------------------------------------------------------------

; Reset (in place of "lda #$0E / jsr write_prg_bank / jsr mmc1_init"):
; every MMC3 register, then clear the hack state $0103-$017F, then the
; game's own RAM clear at $F03A with A = 0, X = $F0 as before.  The first
; $8000 write sets PRG mode 0, so $C000-$DFFF is the fixed bank from then
; on (the MMC3 powers up in an unknown mode; this code is in $E000-$FFFF).
; CHR mode 1: BG $1000-$17FF = R0 (2 KiB, tiles $00-$7F: scene or band
; page), $1800-$1FFF = R1 (scene, never switched), sprites = R2-R5.
; The RAM clear zeroes MMC3_SEL; restores OR in the mode bit.
reset_mmc3:
    ldx #7
@reg:
    txa
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
    lda mmc3_init,x
    sta MMC3_DATA
    dex
    bpl @reg
    inx
    stx MMC3_MIRROR             ; vertical, as the original's MMC1 control
    stx MMC3_IRQ_OFF
    lda #$80
    sta MMC3_WRAM               ; battery RAM enabled, writable
    txa
    ldx #$7C
@clear:
    sta KANJI_MAINCHR,x
    dex
    bpl @clear
    ldx #$F0
    jmp $F03A

; R0-R7: scene BG halves, sprite page 0, bank 14 (as the original reset).
mmc3_init:
    .db CHR_SCENE_LO, CHR_SCENE_HI, 0, 1, 2, 3, 28, 29

; ----------------------------------------------------------------------
.base $FFE0; ----------------------------------------------------------------------
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
