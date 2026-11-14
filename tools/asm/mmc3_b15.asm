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
;   $C460-$C47D  dead mmc1_reset / mmc1_init: render_ctl, IRQ tail
;   $C489-$C49D  dead rest of set_bank_lock: free
;   $C4AD-$C4B9  dead rest of restore_bank_after_nmi: chr1_scene
;   $C4BA-$C4CA  NMI hook at loc_EF08 (dead original write_prg_bank body)
;   $EED0-$EED2  NMI: jmp nmi_gate (map mode: the uploads before $EED0-$EF0A;
;                elsewhere the original's cycles exactly)
;   $D291-$D2B6  NMI epilogue hook at loc_EF31 (dead original $EF-$F7
;                dispatcher, replaced by the message engine's text_dispatch)
;   $F004-$F039  reset mapper/RAM setup, rewritten
;   $FFE0-$FFEF  block-writer original entry, the message engine's frame wait
;   $FAD5-$FBC1  the dead developer debug overlay: free
;   $FBC3-$FFD7  its dead hex font and tiles: the runtime at $FC00
;                (fixed_rt.asm: IRQ, NMI stream, renderer stubs; RAM code
;                until 2026-11-14)
;   $D671-$D6C1  copy_pointer_triplet and its divisor table (QoL: the
;                digits come from the UI bank; stubs in the space)
;   $C1D2-$C216  div24_shift (QoL: the UI bank divides; the block
;                writer's fast copy in the space)
;
; MMC3 bank-switch protocol (revision 21).  MMC3_SEL ($EB, the game's MMC1
; bank_switch_lock, which only the rewritten switch routines used) holds the
; last value the main thread wrote to the bank-select register $8000.  The
; main thread stores it there before every $8000 write; interrupt code
; writes $8000 directly and leaves with $8000 = MMC3_SEL | $80
; (restore_bank_after_nmi does it last in every NMI that touched the
; mapper).  So an NMI between a main-thread select and its data write
; changes nothing: the data lands in the register the main thread chose.
; The scanline IRQ (revision 21b) follows the same rule.
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
    pla                         ; (the palette mask loop runs in the hack
    jsr SET_BANK_LOCK           ; bank since map-canvas step 1); preserves
    pla                         ; X and Y
    tax
    rts

; set_bank_lock body (jumped to from $C486, after "sta current_prg_bank";
; A = the 16 KiB bank).  Main thread: $8000-$9FFF = R6 = 2 * bank,
; $A000-$BFFF = R7 = 2 * bank + 1, MMC3_SEL stored before each select.
; The message bank (MSG_BANK, bit 7 set, kanji.inc): R6 = the hack bank's
; lower half (2 * MSG_BANK without bit 8; the MMC3 keeps 6 bits anyway),
; R7 = KANJI_TEXT_CHUNK.  PRG_R7X follows, each time before the R7 write
; that it describes: 0 first (an NMI from there on restores both halves of
; the new bank), the chunk just before R7 gets it (main_tail).  X and Y
; untouched, no stack.  Returns as the original: A = 0, Z set, N clear, C =
; bit 3 of the bank (the original's banks 0-15; set for 8-31), V
; unchanged.  Cycles: 63 to the rts's end for every bank but MSG_BANK, as
; before the message bank (the original game's timing: every bank switch
; runs through here).  36 bytes, as before: the routines after it keep
; their addresses (a save state's stack may hold them).
main_prg:
    lda #0                      ; 2
    sta PRG_R7X                 ; 4
    lda #MMC3_R6                ; 2
    sta MMC3_SEL                ; 3
    sta MMC3_SELECT             ; 4
    lda current_prg_bank        ; 3
    asl a                       ; 2
    sta MMC3_DATA               ; 4
    lda #MMC3_R7                ; 2
    sta MMC3_SEL                ; 3
    sta MMC3_SELECT             ; 4
    lda current_prg_bank        ; 3
    asl a                       ; 2  C = MSG_BANK
    nop                         ; 2
    nop                         ; 2
    jmp main_tail               ; 3  (+18 there)
    .dsb 3, $EA                 ; (free: main_prg's 36 bytes)

; (restore_bank_after_nmi's body, nmi_prg, is at $D4C9 since the kanji
; store: it keeps the main thread's 8 KiB bank at R7.)

; NMI epilogue gate (jumped to from $EF31 in place of "pla / tay / pla").
; The hack's epilogue work is the split-mode reset (the band switch is the
; scanline IRQ's since revision 21b); normal frames skip the hack bank
; (and its two bank switches) entirely.
ef31_gate:
    lda nmi_busy
    bne @skip
    lda nmi_mode
    beq @skip
    jmp ef31_hook
@skip:
    pla
    tay
    pla
    jmp $EF34

; NMI, not busy, after the game's flush, palette DMA and CHR-stream step:
; jumped to from $EED0 in place of "sta PPUSCROLL" ($EECE's "lda scroll_x"
; ran: A = scroll_x).  Map mode (TXR_ON bit 7): the renderer bank's
; nmi_map (through fixed_rt.asm cv_nmi and nmi_cvg) uploads first and runs
; the original's $EED0-$EF0A (the scroll, PPUMASK, ppu_nmi_on, the frame
; counter and task timers: no PPU work that must come first) after the
; uploads (TEXT_RENDERER.md "Upload speed", round 3).  Elsewhere the
; original $EED0-$EEDF with ppu_nmi_on inlined: with the jump here and the
; test, exactly its 42 cycles to $EEE0 (the title's split loops at $EF38
; and $EF94 count cycles from the NMI).
nmi_gate:
    bit TXR_ON                  ; 4
    bmi @map                    ; 2 (not taken)
    sta PPUSCROLL               ; 4
    lda scroll_y                ; 3
    sta PPUSCROLL               ; 4
    lda ppu_mask_shadow         ; 3
    sta PPUMASK                 ; 4
    lda ppu_ctrl_shadow         ; 3  ppu_nmi_on
    ora #$80                    ; 2
    sta ppu_ctrl_shadow         ; 3
    sta PPUCTRL                 ; 4
    jmp $EEE0                   ; 3  (+ the jump here: 42, as $EED0-$EEDF)
@map:
    jmp cv_nmi                  ; (fixed_rt.asm at $FC00)
    .db $EA, $EA                ; (the routines below keep their addresses)

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
; <PAGE>).  After the player's button press, when the message engine has the next
; page of a kanji message pending, clear the window and restart at the top
; line: a page never shares the window (or its CHR tiles) with the one
; before it.  The original keeps scrolling line by line.
page_flip:
    jsr TEXT_DRAW_CHAR          ; prompt and wait, as the original
    bit KANJI_PAGES_LEFT        ; bit 7: the message engine has a page pending
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
; tiles stale afterwards (it sees $39 move).  cv_stream (fixed_rt.asm) runs the
; step and forces the PPU address for a split right after it (the game's
; NMI goes on into the pre-render line before ef08_gate).
c343_hook:
    lda nmi_busy
    bne @main
    lda ppu_ctrl_shadow
    bpl @main
    jsr chr1_scene
    jmp cv_stream               ; the step, then a split's address force
@main:
    jmp blk_main                ; (QoL: page 0 and the nametables skip the
                                ; hack calls; $D671 block below)

; MMC3 scanline IRQ (the vector at $FFFE, IRQs enabled at reset).  Two
; per frame since map-canvas step 1.  Stage 0 (KANJI_IRQ_ST = 1 or 2)
; comes at the pre-render line's clock (irq_arm0 in the hack bank) and
; runs in line 0: it reloads the counter for line KANJI_IRQ_N.  It and the
; map's part switches (KANJI_IRQ_ST bit 7) run in fixed_rt.asm (cv_irq,
; $FC00).  Stage KANJI_IRQ_ST = 0: the opening oath's split
; (irq_split); the band page's switch is gone (2026-11-14).  $8000 goes
; back to MMC3_SEL, as after every NMI.  A and the stack only.
irq_handler:
    pha
    lda KANJI_IRQ_ST
    beq irq_split
    jmp cv_irq
irq_off:
    jmp irq_off_tail

; Battle shake (bank 14 $ACBF, four-screen): A = the scroll_y offset ($00
; or $ED, the screen shifted 3 lines down), Y = the shake step.  With 4
; nametables a negative offset would wrap from row 29 into the lower
; half; PPUCTRL bit 1 makes the wrap land in row 0 of the battle screen
; (the 3 lines above come from the lower half, in the overscan).  The
; shake always ends on step 3 (offset 0), which clears the bit again.
battle_shake:
    sta scroll_y
    cmp #$01
    lda ppu_ctrl_shadow
    and #$FD
    bcc @set
    ora #$02
@set:
    sta ppu_ctrl_shadow
    lda $AD7B,y                 ; scroll_x offset, as the original
    sta scroll_x
    rts
battle_shake_end:               ; (game code for the RAM gates)

; UI kanji (TEXT_RENDERER.md "Kanji UI"): text_put_tile's calls in
; text_input ($CC02, the window templates), in draw_string_from_pointer
; ($D5C0, item, tactic and place names) and in the boot menu's lines (bank
; 13).  With TXR_ON bit 6 (map mode, the boot screens) the renderer bank
; puts the byte, or a known kana word's kanji form (TXF_PUT, through txr_tpm).
txr_tp:
    bit TXR_ON
    bvs @m
    jmp TEXT_PUT_TILE
@m:
    jmp txr_tpm

; The opening oath's fixed split (TXR_ON = TXR_SPLIT; armed for line
; SPLIT_LINE by the renderer bank's cvn_split): R1 = CHR $3800, its kanji
; at tiles $80+ for the rest of the frame.  The screen is black there.
irq_split:
    lda TXR_ON
    cmp #TXR_SPLIT
    bne irq_off
    lda #MMC3_R1
    sta MMC3_SELECT
    lda #CHR_BAND_LO
    sta MMC3_DATA
    sta MMC3_IRQ_OFF            ; acknowledge; off until the next arm
    jmp irq_tail

; main_prg's end (C = MSG_BANK, A = 2 * the bank, R7 selected).
main_tail:
    bcs @msg                    ; 2
    ora #1                      ; 2
    sta MMC3_DATA               ; 4
    cmp #$11                    ; 2  C = bit 3 of banks 0-15
    lda #0                      ; 2
    rts                         ; 6
@msg:
    lda KANJI_TEXT_CHUNK
    sta PRG_R7X                 ; (first: an NMI from here on restores it)
    sta MMC3_DATA
    lda #0
    rts
.if $ > $C6D2
    .error "txr_tp / irq_split / main_tail: past load_text_graphics' gap ($C6D1)"
.endif

; ----------------------------------------------------------------------
.base $C460
; ----------------------------------------------------------------------

; text_render_cell, patched at $DBED (its "jmp loc_DC7C"): a row-buffer
; byte with bit 7 set ends the line in the original, whose tiles are all
; below $80 and whose line ends are the text codes $FA-$FF.  The battle
; messages' kanji tiles (the pool $A4-$DF since revision 18; $80-$A3 after
; a win and groups 15-20 $E0-$F7 since 2026-11-13, ui_pchoose) are drawn
; like any tile: $80-$F7 are tiles.  $F8-$FF: a kanji's top tile when the
; cell's bottom tile is the next one (8x16 order: t over t+1, t+2 over
; t+3; the slots at $F8-$FF), else a line end (its bottom cell is blank).
render_ctl:
    cmp #$F8
    bcc @tile
    cmp $0318,y                 ; the cell's bottom tile
    bcc @tile                   ; top < bottom: a kanji (bottom = top + 1)
    jmp $DC7C                   ; end of line, as the original
@tile:
    jmp $DBEF                   ; queue the cell (top tile in A)

; IRQ tail: $8000 back to the main thread's select.
irq_tail:
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
    pla
    rti
irq_off_tail:
    sta MMC3_IRQ_OFF            ; acknowledge, no IRQ until the NMI arms it
    pla
    rti

; ----------------------------------------------------------------------
.base $C489
; ----------------------------------------------------------------------
; ($C489-$C49D: free since map-canvas step 3; IRQ stage 0 is cv_irq.)
; call_ui (step B): X = UI function.  Map the UI bank (main thread, the
; game's lock protocol), run its $8000 dispatcher, map the bank that was
; current.  Bank 14 calls it (the info screen, its battle wrapper, the army
; status screen).  A is lost; X and Y are the UI function's.
call_ui_army:
    ldx #UIF_ARMY               ; (not zero: the branch is always taken)
    bne call_ui
call_ui:
    lda current_prg_bank
    pha
    lda #UI_BANK
    jsr SET_BANK_LOCK
    jsr $8000
    pla
    jmp SET_BANK_LOCK

; ----------------------------------------------------------------------
.base $C2AB
; ----------------------------------------------------------------------
; The nametable fill set_ppu_scroll: both vertical twins (cv_fill).
    jmp cv_fill                 ; set_ppu_scroll's "sta $00 / stx $01"

; ----------------------------------------------------------------------
.base $C4AD
; ----------------------------------------------------------------------

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
    jsr nmi_prg_pair
    jsr $8003
ef08_tail:
    lda #$08                    ; the sound bank: both halves (never the
    jsr nmi_prg_pair            ; main thread's 8 KiB bank at R7)
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
;   F8 <far_head> <text chunk | MSG_WIN flag in bit 7> <text addr>
far_head:
    lda text_window_x
    jsr SET_BANK_B
    jmp $BF00

; Message-engine helper: scroll the text window up one line with the
; engine's own routine (it waits frames), then map the message bank again.
scroll_text:
    jsr $D376                   ; text_scroll_up
    lda #MSG_BANK
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
    cli                         ; the MMC3 IRQ is the only IRQ source (APU
    lda #0                      ; frame IRQ inhibited at $EFFF, no DMC)
    ldx #$F0
    jmp $F03A

; The reset vector's "jmp reset_init" comes here first (map-canvas step 3):
; every MMC3 register and hack_init (clear the hack state and battery RAM
; $7900-$7FFF) before reset_init's PPU warm-up, whose three vblank waits
; absorb the clear (after them the RAM image's copy, until 2026-11-14,
; cost the game a frame).  NMIs and IRQs are off; the stack is the
; power-on one until reset_init's txs.
early_reset:
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
    jsr HACK_INIT
    jmp $EFC9                   ; reset_init

; R0-R7: scene BG halves, sprite page 0, the hack bank (hack_init; the
; game's code from $F03A on maps its banks before it uses them).
mmc3_init:
    .db CHR_SCENE_LO, CHR_SCENE_HI, 0, 1, 2, 3, KANJI_HACK_BANK*2, KANJI_HACK_BANK*2+1

; ----------------------------------------------------------------------
.base $FFE0; ----------------------------------------------------------------------
.base $FFE0
; ----------------------------------------------------------------------

; The original block-writer entry.
c343_plain:
    lda PPUSTATUS
    jmp $C346

; Message-engine frame wait: yield one frame, then map the message bank
; again (other tasks may have switched banks while this one was suspended).
wait_text:
    jsr WAIT_VBLANK
    lda #MSG_BANK
    jmp SET_BANK_LOCK

;----------------------------------------------------------------------
.base $D671
; ----------------------------------------------------------------------
; QoL (battle setup and the army screen).  copy_pointer_triplet ($D671,
; entered from read_pointer_triplet above it and called directly) wrote
; the decimal digits of $03-$05 with six div24_shift calls, ~11,500 cycles
; a number.  UIF_DEC does the same by subtracting the powers of ten,
; ~1,700 cycles with the call, and leaves the same results and end state
; (ui.asm ui_dec).  Its 81 bytes (with the divisor table) hold the stub and
; the two routines after it.  The stack is no deeper than with
; div24_shift (call_ui's bank byte and return address, nothing in
; ui_dec): $0104-$010A, the digits, sit at the bottom of the stack page.
cpt_stub:
    sty ppu_update_off          ; (the original's first instruction)
    stx UI_DECX
    ldx #UIF_DEC
    jmp call_ui

; bs_wait: wait_vblank_queued for the battle start's pacing waits (bank 14
; $9BE3 / $9C47 around the encounter roll, bank 15 $DF32 in the enemy
; slots' roll, $E0A3 / $E200 / $E238 in the name loop).  With the NMI busy
; and rendering off, such a frame only lets the busy NMI run (frame
; counter, task timers, sound: no PPU work) and then resumes the main
; task: controller, RNG step (read_input_state), nmi_frame_counter, the
; sound hook if nmi_mode is set.  Without the frame, the same steps run
; here, from the scheduler's own resume code ($C040, which pulls Y and X
; and returns), so every roll sees the same random numbers.  The queue
; budget is set as the real wait sets it (a busy NMI leaves it).  Shown
; screen, NMI not busy or another task: the real wait.
bs_wait:
    lda nmi_busy
    beq @wait
    lda ppu_mask_shadow
    and #$18
    bne @wait
    lda task_slot_index
    bne @wait
    lda #1
    sta nmi_update_budget
    txa
    pha
    tya
    pha
    jmp TASK_RESUME
@wait:
    jmp WAIT_VBLANK_QUEUED

; blk_main: c343_hook's main-thread path.  FN_BLOCK_PRE / FN_BLOCK_POST
; only act on CHR page 1 ($1000-$1FFF: select it, copy or mark the band
; page); for page 0 and the nametables they cost ~470 cycles a call for
; nothing (the battle setup's sprite stream: 48 such calls).
; Page-0 writes of plain tiles (mode 0: 16 bytes a tile from ($00)) of
; 1-15 tiles go to blk_fast (the sprite stream: 4 tiles a step).
blk_main:
    lda $03
    cmp #$20
    bcs @plain                  ; nametables, palette
    cmp #$10
    bcs @page1
    lda $04
    and #$0F
    bne @plain                  ; fills, plane-only and read-back modes
    ldx $02
    dex
    cpx #15
    bcs @plain                  ; 0 (= 256) or 16 and more tiles
    jmp blk_fast
@plain:
    jmp c343_plain
@page1:
    lda #FN_BLOCK_PRE
    jsr call_hack
    jsr c343_plain
    lda #FN_BLOCK_POST
    jmp call_hack
blk_main_end:

; ----------------------------------------------------------------------
.base $C1D2
; ----------------------------------------------------------------------
; QoL: div24_shift ($00-$02 / $06-$08: quotient $00-$02, remainder
; $03-$05, $09 = 0, X and Y kept) shifts 24 times, ~1,900 cycles.  The UI
; bank's ui_div runs the same steps (the same results for every input,
; divisor 0 and divisors over $7FFFFF included) and skips the dividend's
; leading zero bytes.  Callers load A again after it (A and the flags are
; call_ui's).  The stack is one byte deeper than the original's (X and Y
; pushed there; call_ui's bank byte and return address here).
div_stub:
    stx UI_DECX
    sty UI_DECY
    ldx #UIF_DIV
    jmp call_ui

; blk_fast (from blk_main): the game's body for mode 0, page 0, 1-15
; tiles, in one 2x unrolled loop: ~14 cycles a byte instead of ~23 (the
; body calls a routine per 8 bytes and tests the read flag per byte).
; End state as the body's: $00/$01 past the tiles, $02 = $03 = 0, X = Y = 0,
; A = $01.
blk_fast:
    bit PPUSTATUS
    lda $03
    sta PPUADDR
    lda $04
    sta PPUADDR
    lda $02
    asl a
    asl a
    asl a
    asl a
    sta $03                     ; the end index (16-240)
    ldy #0
@copy:
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    cpy $03
    bne @copy
    tya
    clc
    adc $00
    sta $00
    lda #0
    tax
    tay
    stx $02
    stx $03
    adc $01
    sta $01
    rts
blk_fast_end:

; ======================================================================
; Map-canvas step 2: four-screen nametables (TR1ROM/TVROM-style, header
; flag 6 bit 3).  The map's 30-row ring becomes a 60-row ring: world
; metarow m = 15 * screen + row sits in the vertical nametable (screen & 1)
; ($2000/$2400 or $2800/$2C00), and PPUCTRL bit 1 follows the camera's
; top screen.  Vertical steps write the row one block beyond the camera's
; destination, as the horizontal steps write their column: 17 x 18
; metatiles are live (the visible 15 x 16 and one buffer row / column on
; each side), and the rest of the ring is free for the dialogue canvas.
; The attribute shadow covers all four tables: 256 bytes at MAP_ATTR
; ($7800, the third save record's RAM), index = lower half << 7 |
; attribute row << 4 | right table << 3 | attribute column.  Each block
; below replaces the original routine's bytes in place (the build checks
; them).
; ======================================================================

UPDATE_PARTY_SPRITES = $F421
WALK_DY              = $E660            ; data_E660: scroll_y step per direction/speed
ppu_update_off_      = $F2
ppu_update_len_      = $F1
ptr_lo_              = $F3
ptr_hi_              = $F4

; ----------------------------------------------------------------------
.base $D7E9
; ----------------------------------------------------------------------

; cursor_to_ppu: nametable address of the cursor's metatile.
;   hi = $20 | (cursor_y & 1) << 3 | (cursor_y2 & 1) << 2 | cursor_x >> 2
;   lo = (cursor_x & 3) << 6 | cursor_x2 << 1
; Leaves $F3 = cursor_x2 * 2 and $F4 = cursor_x >> 2 as the original.
cursor_to_ppu:
    lda cursor_x2
    asl a
    sta ptr_lo_
    lda cursor_x
    lsr a
    lsr a
    sta ptr_hi_
    jsr nt_bits
    asl a
    asl a
    ora ptr_hi_
    ora #$20
    sta ppu_addr_hi_shadow
    lda cursor_x
    ror a
    ror a
    ror a
    and #$C0
    ora ptr_lo_
    sta ppu_addr_lo_shadow
    rts

; A = (cursor_y & 1) << 1 | (cursor_y2 & 1): the cursor's nametable.
nt_bits:
    lda cursor_y2
    lsr a
    lda cursor_y
    rol a
    and #$03
    rts
cursor_to_ppu_end:

; ----------------------------------------------------------------------
.base $D815
; ----------------------------------------------------------------------

; set_scroll_from_cursor (original entry): the camera's top-left metatile
; is 7 rows above and 8 columns left of the player; PPUCTRL bits 0-1 =
; its nametable.
set_scroll_from_cursor:
    lda #$F9
    jsr $D7A9                   ; cursor_add_x
    lda cursor_x
    asl a
    asl a
    asl a
    asl a
    sta scroll_y
    lda #$F8
    jsr $D7C9                   ; cursor_add_y
    lda cursor_x2
    asl a
    asl a
    asl a
    asl a
    sta scroll_x
    jsr nt_bits
    eor ppu_ctrl_shadow
    and #$03
    eor ppu_ctrl_shadow
    sta ppu_ctrl_shadow
    rts
set_scroll_end:

; ----------------------------------------------------------------------
.base $F3A3
; ----------------------------------------------------------------------

; Walking scroll, after "jsr update_party_sprites" at $F3A0.  X = direction
; * 2 + speed, Y = $F3 = $FF / $FE as the original.  Crossing the 240-line
; wrap toggles PPUCTRL bit 1 (the camera enters the other vertical half);
; $F0 -> $00 going down, $FF/$FE -> $EF/$EE going up.  The horizontal part
; ($F3CB-$F3EE) is the original's.
walk_scroll:
    lda battle_flags2
    lsr a
    lsr a                       ; C = speed bit
    lda game_mode
    rol a                       ; direction * 2 + speed, C = 0
    tax
    and #$01
    eor #$FF
    tay
    sty ptr_lo_
    lda WALK_DY,x
    adc scroll_y                ; C = 0
    cmp #$F0
    bcc @store
    and #$0F
    beq @toggle                 ; $F0: down into the next screen, row 0
    ora #$E0                    ; $FF/$FE: up into the screen above
@toggle:
    pha
    lda ppu_ctrl_shadow
    eor #$02
    sta ppu_ctrl_shadow
    pla
@store:
    sta scroll_y
walk_scroll_end:

; ----------------------------------------------------------------------
.base $DAB9
; ----------------------------------------------------------------------

; draw_tile_run, vertical run past row 29: continue at row 0 of the other
; vertical half (the original wrapped to row 0 of the same table).  The
; new run starts at row 0, so its length is min(30, remaining).
column_wrap:
    lda ptr_hi_
    eor #$0B                    ; hi & 3 = 3 here: (hi & $FC) EOR $08
    sta $0400,x
    sta ptr_hi_
    inx
    lda ptr_lo_
    and #$1F
    sta $0400,x
    sta ptr_lo_
    inx
    lda #$00
    sta ppu_update_off_
    lda #$1E
    cmp ppu_update_len_
    bcc @len
    lda ppu_update_len_
@len:
    ora #$80
    sta $0400,x
    inx
    jmp $DA94                   ; the run's copy loop
column_wrap_end:

; draw_map_object, columns: the next attribute row (in the bytes
; column_wrap freed; 8-bit wrap through the 16 attribute rows).
dmo_col_next:
    lda battle_cursor
    clc
    adc #$10
    sta battle_cursor
    dec ptr_hi_
    bne dmo_entry
    beq dmo_done
dmo_col_next_end:

; ----------------------------------------------------------------------
.base $DAF2
; ----------------------------------------------------------------------

; draw_map_object (the map attribute writer, called by draw_party_footer
; and the window code): queues tile_id_base attribute bytes of the shadow
; from index battle_cursor, each into its own table (index bit 3: right
; table, bit 7: lower half).  Rows (tile_attr bit 7 clear) run along the
; shadow row, wrapping in its 16 bytes; columns run down, wrapping through
; all 16 attribute rows of the 60-row ring.  The original's rts at $DB7E
; (a branch target of scroll_map) stays.
draw_map_object:
    lda tile_id_base
    sta ptr_hi_
    ldx vram_queue_write
dmo_entry:
    lda battle_cursor
    and #$08
    lsr a
    ora #$23
    bit battle_cursor
    bpl @upper
    ora #$08
@upper:
    sta $0400,x
    inx
    lda battle_cursor
    lsr a
    and #$38
    sta ptr_lo_
    lda battle_cursor
    and #$07
    ora ptr_lo_
    ora #$C0
    sta $0400,x
    inx
    ldy tile_attr
    bmi @column
    and #$07
    eor #$07                    ; 7 - column
    cmp ptr_hi_
    bcs @count                  ; the rest of the count fits in this table's row
    adc #$01                    ; 8 - column (C = 0)
    bne @run
@count:
    lda ptr_hi_
    bne @run
@column:
    lda #$01                    ; column entries are one byte each
@run:
    sta $0400,x
    inx
@byte:
    ldy battle_cursor
    lda MAP_ATTR,y
    sta $0400,x
    inx
    lda tile_attr
    bmi dmo_col_next
    dec ptr_hi_
    beq dmo_done
    inc battle_cursor
    lda battle_cursor
    and #$0F
    bne @same_row
    lda battle_cursor
    sec
    sbc #$10
    sta battle_cursor
@same_row:
    and #$07
    bne @byte
    beq dmo_entry
dmo_done:
    lda #$00
    sta $0400,x
    stx vram_queue_write
    rts

; data_D979 (tile_address's attribute-table bank pointers), moved here:
; tile_address needs its bytes.
attr_table_hi:
    .db $8C, $99, $A6

; Full map redraws (text_draw_screen, render_map_column) draw 17 rows: the
; camera's 15 and a buffer row above and below.  They walk "up" from one
; screen below; this starts them 17 rows below the player (an up step
; draws 8 rows above its position).  Returns A = 17 rows.
redraw_start:
    jsr txr_rd                  ; the map renderer's window close (TEXT_RENDERER.md)
    inc text_y
    lda #$02
    jsr $D7A9                   ; cursor_add_x: cursor = text + 2 rows
    lda cursor_x
    sta text_x
    lda cursor_y
    sta text_y
    lda #$11
    rts
draw_map_object_end:

; ----------------------------------------------------------------------
.base $D953
; ----------------------------------------------------------------------

; tile_address: the shadow index of the cursor's metatile,
;   X = (cursor_y & 1) << 7 | (cursor_x >> 1) << 4 | (cursor_y2 & 1) << 3
;       | cursor_x2 >> 1
; and $14/$15 = its attribute table, as the original.  Y is kept.
tile_address:
    lda #$00
    sta ppu_addr_lo
    ldx class_index
    lda attr_table_hi,x
    sta ppu_addr_hi
    lda cursor_y
    lsr a
    lda cursor_x
    bcc @upper
    ora #$10
@upper:
    and #$FE
    asl a
    asl a
    asl a
    sta ptr_lo_
    lda cursor_y2
    lsr a
    lda cursor_x2
    bcc @left
    ora #$10
@left:
    lsr a
    ora ptr_lo_
    tax
    rts
tile_address_end:

; ----------------------------------------------------------------------
; The attribute shadow's readers and writers outside this file: the
; window code at $CAA2 and draw_party_status at $F5E7 ($0780,x -> MAP_ATTR,x).
.base $CAA3
    .dw MAP_ATTR
.base $CAA8
    .dw MAP_ATTR
.base $F5E8
    .dw MAP_ATTR
.base $F5EF
    .dw MAP_ATTR

; Row and column tables of the walking / redraw tasks (indexed by
; game_mode: up, down, left, right).
.base $F697
    .db $0A                     ; draw_party_footer: 10 attribute rows per column
.base $F6A1
    .db $F8, $08, $F8, $F8      ; first metarow: 8 above / below (was 7)
.base $F6BD
    .db $24, $24, $22, $22      ; run length: columns 34 tiles (was 30)
.base $F6C5
    .db $00, $24, $22, $22      ; second run's buffer offset
.base $F6D4
    .db $23, $01, $22, $00      ; column tiles in the row buffer
    .db $23, $01, $22, $00
.base $F6DC
    .db $12, $12, $11, $11      ; metatiles: columns 17 (was 15)

; text_draw_screen and render_map_column: 17 rows (redraw_start).
.base $CDDF
    lda game_mode
    pha
    lda #$00
    sta game_mode
    jsr redraw_start
    nop
.base $D97C
    lda #$00
    sta game_mode
    jsr redraw_start
    nop

; sub_CE2D (bank 14's room transfer with $90 bit 4, its only caller at
; $BDF8): the new room wiped in from the right over the shown one (the
; scroll stays), one metatile column a frame, 18 columns.  The original's
; runs (30 tiles from buffer offsets 0 and $1E) with the 17-metatile
; columns above drew the right half two metarows low (the user's state,
; 2026-11-13); 34-tile runs would make the queue 120 bytes a frame, and
; the NMI would end past the pre-render line.  Now the UI bank moves the
; text position one row down first (UIF_WIPE: draw_party_status starts at
; the camera's top row), the loop is the original's with the right
; column at $22: the camera's 15 rows and the attribute column (10 rows
; from the top row), 112 queue bytes and the original's main-thread work
; a frame.  Then UIF_WIPE_ROWS draws the buffer rows (8 above and below
; the camera's middle) as walking steps do, one frame each, and puts the
; text position back.  tile_attr is set once a column (draw_tile_run and
; the footer only read it).
.base $CE2D
sub_CE2D_stub:
    lda game_mode
    pha
    ldx #UIF_WIPE
    jsr call_ui                 ; 18 columns right, one row down, game_mode 2
    lda #$12
@col:
    pha
    jsr $C0CE                   ; wait_frame_tick
    jsr $F662                   ; draw_party_header: one column left
    jsr $F572                   ; draw_party_status: the column, from the top row
    jsr $F55C                   ; draw_party_window
    inc ppu_addr_lo_shadow
    lda #$80
    sta tile_attr
    ldy #$22                    ; the right tile column (was $1E)
    ldx #$1E
    jsr $D9ED                   ; draw_tile_run
    jsr $F690                   ; draw_party_footer
    dec ppu_addr_lo_shadow
    ldy #$00
    ldx #$1E
    jsr $D9ED
    jsr $C09F                   ; wait_vblank
    pla
    sec
    sbc #$01
    bne @col
    pla
    sta game_mode
    ldx #UIF_WIPE_ROWS
    jmp call_ui                 ; the buffer rows; the text position back
; UIF_WIPE_ROWS' trampolines: the game's bank-switching routines and the
; yields with bank 14 mapped (as under the original), the UI bank again
; on return.
wipe_status:
    jsr $F572                   ; draw_party_status (ends with set_bank_b 14)
    jsr $F55C                   ; draw_party_window
    jmp wipe_ui
wipe_cols_end:
.if wipe_cols_end > $CE7A
    .error "sub_CE2D's loop and wipe_status outgrew $CE2D-$CE79"
.endif

; sub_CE7A (bank 14 $81AE, an event's map change: the player's metarow
; redrawn, 10 metatiles from 9 columns left): the UI bank's UIF_ROWEV
; (2026-11-13; until 2026-11-14 its fixed-bank space also held the map-mode
; look-ahead page breaks, gone since <PAGENI> is a page break).
; draw_party_status starts 8 rows above now (was 7): the text position
; goes one row further first and comes back one more.
.base $CE7A
sub_CE7A_stub:
    ldx #UIF_ROWEV
    jmp call_ui
WIPE_BANK14 = $0E
wipe_tick:
    lda #WIPE_BANK14
    jsr SET_BANK_LOCK
    jsr $C0CE                   ; wait_frame_tick
    jmp wipe_ui
wipe_wait:
    lda #WIPE_BANK14
    jsr SET_BANK_LOCK
    jsr $C09F                   ; wait_vblank
wipe_ui:
    lda #UI_BANK
    jmp SET_BANK_LOCK

wipe_rows_end:
.if wipe_rows_end > $CED2
    .error "sub_CE7A's stub and the trampolines outgrew $CE7A-$CED1"
.endif
.if wipe_status != WIPE_STATUS || wipe_wait != WIPE_WAIT || wipe_tick != WIPE_TICK
    .error "the wipe trampolines moved: kanji.inc WIPE_STATUS / WIPE_WAIT / WIPE_TICK"
.endif

; ----------------------------------------------------------------------
; text_init's "jsr scroll_map" ($CB1B, $CB80): step B's battle row hook
; (cv_sm).
.base $CB1B
    jsr cv_sm
.base $CB80
    jsr cv_sm

.base $FFDC
    jmp early_reset             ; reset vector: "jmp reset_init"

; ----------------------------------------------------------------------
.base $DC0E
; ----------------------------------------------------------------------

; text_render_cell, the bottom tile of a cell below row 29: row 0 of the
; other vertical half (the original wrapped to row 0 of the same table).
; Here hi & 3 = 3, so hi EOR $0B = (hi & $FC) EOR $08.  Same 12 bytes.
cell_wrap:
    lda ptr_hi_
    eor #$0B
    sta ptr_hi_
    lda ptr_lo_
    and #$1F
    sta ptr_lo_
cell_wrap_end:

; ----------------------------------------------------------------------
.base $D4C9
; ----------------------------------------------------------------------
; put_officer_name's kanji path ($AA set; Y = the officer record, X = the
; line-buffer index), rewritten for the kanji store (2026-11-13): each
; kanji of the record's name (the UI bank's name table: UIF_NAMEG puts it
; in plane 1 of tiles $A9..$A9+3 through the VRAM queue), one a frame as
; the original (whose NMI CHR-animation step read the original's name
; font), and its four cells into the line buffers (top t, t+2; bottom t+1,
; t+3).  The record bytes $10-$13 (the original's glyph banks and numbers)
; are no longer read: bank 12 is the original's.
pon_kanji:
    sty NG_REC
    lda #0
    sta NG_K
@g:
    stx NG_X
    ldx #UIF_NAMEG
    jsr call_ui                 ; V set: no kanji NG_K (V survives the
    bvs @end                    ; bank switch back)
    jsr WAIT_VBLANK             ; the NMI flushes it (busy: flushed now)
    ldx NG_X
    lda $A9
    clc
    sta $0300,x                 ; top row
    adc #1
    sta $0318,x                 ; bottom row
    inx
    adc #1
    sta $0300,x
    adc #1
    sta $0318,x
    adc #1
    inx
    sta $A9
    inc NG_K
    bne @g                      ; (always)
@end:
    ldx NG_X
    jmp SET_BANK_CURRENT

; restore_bank_after_nmi's body (jumped to from $C4AA; A = the bank, the
; main thread's at the NMI's last restore).  NMI only: MMC3_SEL stays the
; main thread's, and $8000 gets it back last.  Clobbers X (every caller
; reloads it).  R7 = PRG_R7X when the main thread has an 8 KiB bank there
; (a kanji store bank: kanji.inc), else the bank's upper half.
nmi_prg:
    ldx PRG_R7X
    bne nmi_r7x
; The NMI's own maps (the hack bank, the sound bank): both halves of A.
nmi_prg_pair:
    asl a
    tax
    lda #MMC3_R6
    sta MMC3_SELECT
    stx MMC3_DATA
    inx
nmi_r7:
    lda #MMC3_R7
    sta MMC3_SELECT
    stx MMC3_DATA
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
    rts
nmi_r7x:
    cpx #STORE_8K               ; a kanji store bank or a text chunk, else a
    bcc nmi_prg_pair            ; stale byte (a state saved by an earlier
    cpx #TEXT_8K+TEXT_CHUNKS    ; build, whose battery RAM had other data
    bcs nmi_prg_pair            ; there): both halves
    asl a                       ; (MSG_BANK: the hack bank's lower half)
    pha
    lda #MMC3_R6
    sta MMC3_SELECT
    pla
    sta MMC3_DATA
    bne nmi_r7                  ; (always: 2 * a bank with PRG_R7X set is
                                ; never 0 mod 256; X = PRG_R7X)
.if $ > $D549
    .error "pon_kanji and nmi_prg outgrew put_officer_name's kanji path ($D4C9-$D548)"
.endif


; ----------------------------------------------------------------------
; The developer debug overlay ($FAD5-$FBC1: RAM $60-$63 and $47 as hex
; sprites when $A6 != 0) and its screens' 1bpp hex font and tiles
; ($FBC3-$FFD7), dead: no caller, pointer or read on any path (the survey
; of 2026-11-14, TEXT_RENDERER.md "The RAM code in bank 31").  $FAD4
; (read_input_state's rts) and $FBC2 (nop_return2) stay.  Free but for
; the runtime at $FC00.
; ----------------------------------------------------------------------
.base $FAD5
.if $ > $FBC2
    .error "the dead debug overlay's space is $FAD5-$FBC1"
.endif
.base $FBC3
.if $ > $FC00
    .error "the runtime starts at $FC00"
.endif
.base $FC00
.include "fixed_rt.asm"
.if $ > $FFD8
    .error "the runtime outgrew the dead tiles ($FBC3-$FFD7)"
.endif
; The RAM image's layout, one page up from $7900 (the branches' pages, the
; IRQ's dot timing): its labels at their old offsets.
.if cv_irq != $FC00 || cv_stage != $FC20 || cv_w1 != $FC4D || txr_lat != $FC6D
    .error "fixed_rt.asm: the IRQ code moved within its page"
.endif
.if cv_stream != $FC75 || cvs_copy != $FC9F || cv_sforce != $FD24 || cv_nmi != $FD64
    .error "fixed_rt.asm: the NMI code moved within its page"
.endif
.if cv_fill != $FD7B || cv_sm != $FD8D || cv_wincb != $FDAE || txr_call != $FDB6
    .error "fixed_rt.asm: the stubs moved"
.endif
.if txr_rr_gap != $FDDE || txr_dlx != $FE15 || txr_rcx != $FE41 || txr_menu != $FEE7 || rt_end != $FEEF
    .error "fixed_rt.asm: the stubs moved"
.endif
