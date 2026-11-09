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
;   $C489-$C49D  dead rest of set_bank_lock: IRQ middle
;   $C4AD-$C4B9  dead rest of restore_bank_after_nmi: chr1_scene
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
; The scanline IRQ (revision 21b) follows the same rule.
;
; Nothing here runs before the game's own split-screen code: the NMI work
; is attached after the nmi_mode branch ($EF0B, normal frames only) and in
; the epilogue ($EF31, after every split loop has finished).
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/canvas_ram.inc"

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

; NMI hook gate at loc_EF08 (normal frames, jumped to from $EF0B).  With no
; band shown, no request pending, no VRAM queue traffic and no CHR
; animation step, the hack has nothing to track or do: skip the hack bank
; and run only the game's own sound-bank switch.  (KANJI_BAND = 0 implies
; FLAG_PAGE2 = 0: the NMI that clears the band also clears the flag; the
; game keeps OAM slot 0 hidden, so sprite 0 needs no write either.)
ef08_gate:
    jsr CV_NMI                  ; v = $1000, the dialogue canvas's arm
    lda KANJI_BAND
    ora KANJI_REQ
    ora CV_ROWS                 ; a shown canvas is armed every frame
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

; MMC3 scanline IRQ (the vector at $FFFE, IRQs enabled at reset).  Two
; per frame since map-canvas step 1.  Stage 0 (KANJI_IRQ_ST = 1 or 2)
; comes at the pre-render line's clock (irq_arm0 in the hack bank) and
; runs in line 0: it reloads the counter for line KANJI_IRQ_N.  It and the
; dialogue canvas's two stages (KANJI_IRQ_ST bit 7, map-canvas step 3) run
; from RAM (cv_irq).  The band stage (KANJI_IRQ_ST = 0): BG tiles $00-$7F
; switch to the band page, the IRQ is acknowledged and stays off until the
; next arm.  No switch while no band is shown or the main thread owns the
; PPU.  $8000 goes back to MMC3_SEL, as after every NMI.  A and the stack
; only.
irq_handler:
    pha
    lda KANJI_IRQ_ST
    beq irq_band
    jmp CV_IRQ
irq_band:
    lda KANJI_BAND
    beq irq_off
    lda nmi_busy
    bne irq_off
    lda #MMC3_R0
    sta MMC3_SELECT
    lda #CHR_BAND_LO
    sta MMC3_DATA
irq_switched:                   ; (label for the test scripts)
    sta MMC3_IRQ_OFF            ; acknowledge; off until the next arm
    lda KANJI_NFLAGS
    ora #FLAG_HIT|FLAG_PAGE2    ; the next vblank finds page 2 selected
    sta KANJI_NFLAGS
    jmp irq_tail
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

; ($C489-$C49D: free since map-canvas step 3; IRQ stage 0 is cv_irq.)

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
    cli                         ; the MMC3 IRQ is the only IRQ source (APU
    lda #0                      ; frame IRQ inhibited at $EFFF, no DMC)
    ldx #$F0
    jmp $F03A

; The reset vector's "jmp reset_init" comes here first (map-canvas step 3):
; every MMC3 register and hack_init (clear the hack state, install the
; canvas RAM code) before reset_init's PPU warm-up, whose three vblank waits
; absorb the copy (after them it cost the game a frame).  NMIs and IRQs are
; off; the stack is the power-on one until reset_init's txs.
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

; Overlay frame wait: yield one frame, then map the text bank again (other
; tasks may have switched banks while this one was suspended).
wait_text:
    jsr WAIT_VBLANK
    lda KANJI_TEXT_BANK
    jmp SET_BANK_LOCK

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
    jmp CV_CTP                  ; stores $68; the dialogue canvas (map-canvas step 3)

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
    lsr CV_REDIR                ; the dialogue canvas closes as the redraw passes
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

; ----------------------------------------------------------------------
; Map-canvas step 3: text_init's window rows go through the canvas code
; (RAM): "jsr cursor_to_ppu / jsr tile_address" at $CA59 and both
; "jsr scroll_map" ($CB1B, $CB80).
.base $CA59
    jsr CV_TI
    nop
    nop
    nop
.base $CB1B
    jsr CV_SM
.base $CB80
    jsr CV_SM

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
