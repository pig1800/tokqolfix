; ======================================================================
; RAM code (battery RAM at CV_RAM, $7900; the third save record's, which
; the kanji target no longer offers).  kanji_build.py stores the image in
; PRG bank CV_BANK at $A000; hack_init copies it at reset.  It must end
; below TXR_TABLES (the map renderer's tables).
;
; Map-canvas step 3's dialogue canvas is gone (TEXT_RENDERER.md,
; 2026-11-12): map windows draw into the visible nametable again and the
; map text renderer (txr.asm, bank TXR_BANK) owns every text tile.  What
; stays here must run with any bank mapped:
;   cv_irq    IRQ, KANJI_IRQ_ST != 0: stage 0, the map's part switches
;   cv_nmi    NMI, normal frames (ef08_gate): the split's force and arm
;   cv_stream NMI, the game's CHR-stream step (c343_hook)
;   cv_fill   set_ppu_scroll (clear_screen): both twins; the font back
;   cv_sm     text_init's "jsr scroll_map": step B's battle hook
;   cv_wincb  the battle templates' line CALL (step B)
;   txr_*     the renderer's stubs, waits, bank reader and NMI uploader
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

SCROLL_MAP        = $DB87
LOC_C139          = $C139       ; NMI on, a frame, rendering on (the game's)
CALL_UI_C         = $C48D       ; call_ui (mmc3_b15.asm; checked by kanji_build.py)
C343_PLAIN        = $FFE0       ; c343_plain (mmc3_b15.asm; checked by kanji_build.py)
FLUSH_VRAM_QUEUE  = $D9A1
UPDATE_FRAME      = $C0D5
SOUND_QUEUE_ADD   = $C4D5
SET_BANK_CURRENT  = $C47E
CELL_ROWS         = $DC8F       ; text_render_cell's row-buffer offsets
RENDER_CELL_LOOP  = $DBD1       ; text_render_cell after its first three instructions
TXR_NMI_CV        = $8003       ; txr.asm: nmi_cv, nmi_live (the bank's first
TXR_NMI_LIVE      = $8006       ; 8 KiB, mapped at $8000 by txr_map6 in the NMI)

; IRQ delay (calibrated: the R0 data write lands in dots 257-320).
TXR_D             = 1

.base CV_RAM
.org CV_RAM

; ----------------------------------------------------------------------
; IRQ (A pushed by irq_handler), KANJI_IRQ_ST != 0.
;   1 / 2   stage 0, in line 0: reload for line KANJI_IRQ_N; then the band
;           stage (ST 0, fixed bank) or the map's parts (ST $80)
;   $80-$82 the map's parts 2, 3, 4: R0 = 8, 10, 12 in the hblank of lines
;           71, 119, 167, the counter reloaded for the next one
;   $83     line 240: R0 = page 1 again for the vblank
; No switch while the main thread owns the PPU or the CHR registers.
; ----------------------------------------------------------------------
cv_irq:
    lda KANJI_IRQ_ST
    bmi cv_stage
    lda KANJI_IRQ_N
    sta MMC3_IRQ_LATCH
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_OFF
    sta MMC3_IRQ_ON
    lsr KANJI_IRQ_ST            ; 1 -> 0 (band), 2 -> 1 (map parts)
    beq @band
    lda #$80
    sta KANJI_IRQ_ST
@band:
    pla
    rti

cv_stage:
    txa
    pha
    sta MMC3_IRQ_OFF            ; acknowledge
    lda nmi_busy
    ora KANJI_MAINCHR
    bne cv_quit
    ldx KANJI_IRQ_ST
    lda txr_lat-$80,x
    beq cv_last
    sta MMC3_IRQ_LATCH
    sta MMC3_IRQ_RELOAD         ; reloads at this line's clock
    sta MMC3_IRQ_ON
    inc KANJI_IRQ_ST
    lda #MMC3_R0
    sta MMC3_SELECT
    lda txr_r0v-$80,x
    ldx #TXR_D
@w:
    dex
    bne @w
cv_w1:                          ; (label for the timing probe)
    sta MMC3_DATA               ; hblank: the next part's page
    jmp cv_out
cv_last:
    lda #MMC3_R0
    sta MMC3_SELECT
    lda #CHR_SCENE_LO
    sta MMC3_DATA               ; line 240: page 1 for the vblank
cv_quit:
    lda #0
    sta KANJI_IRQ_ST
cv_out:
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
    pla
    tax
    pla
    rti
txr_lat:
    .db 47, 47, 72, 0
txr_r0v:
    .db 8, 10, 12, CHR_SCENE_LO
cv_irq_end:

; ----------------------------------------------------------------------
; NMI, the game's CHR-stream step (flush_palette: 4 tiles per frame from
; ($39), c343_hook's NMI path with the scene page selected).  The step
; ends near the bottom of vblank, and the game's NMI goes on (scroll,
; task timers) into the pre-render line or line 0 before ef08_gate: too
; late there for a split's PPU-address force and for the reload before
; the pre-render line's clock.  The game's PPUMASK store comes after it
; too (the pre-render line's copies need rendering on by dot 257), so
; the step's plain copy runs here, faster.  In map mode both come here, right after
; the game's last PPU data write (t restored at once: the game's own
; scroll writes may land after the pre-render line's copies now), then
; cv_nmi's bookkeeping and the split's stage settings, with IRQs enabled
; at its end; FLAG_ARMED makes the hack's irq_arm0 a no-op in this NMI.
; ef08_gate's call returns at once (CV_STRM bit 7).
; ----------------------------------------------------------------------
cv_stream:
    lda nmi_mode
    beq cvs_map
    jmp C343_PLAIN              ; title / scenes: the game's body, as before
cvs_map:
    lda $04
    and #$0F
    bne cvs_plain               ; (read-back / fill modes: the game's body)
    ldx $02
    beq cvs_plain
    cpx #16
    bcc cvs_fast
cvs_plain:
    jsr C343_PLAIN              ; the step (write_vram_block's body)
    jmp cvs_split
cvs_fast:
    ; Mode 0 (plain tiles), as the game's body but in one loop: $02 tiles
    ; of 16 bytes from ($00) to PPU $0304; ~650 cycles less for the
    ; stream's 4 tiles, so the step ends ~6 lines earlier.
    lda PPUSTATUS
    lda $03
    sta PPUADDR
    lda $04
    sta PPUADDR
    ldy #0
cvs_copy:
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    lda ($00),y
    sta PPUDATA
    iny
    dex
    bne cvs_copy
    tya                         ; the body's exit state: the pointer past
    clc                         ; the data, count and fill byte 0, X = Y = 0
    adc $00
    sta $00
    bcc cvs_c1
    inc $01
cvs_c1:
    lda #0
    sta $02
    sta $03
    tay
    tax
cv_scopy_end:                   ; (cv_stream-cv_scopy_end: game code for the RAM gates)
cvs_split:
    lda ppu_mask_shadow
    and #$18
    beq cvs_body                ; rendering off: no split
    bit TXR_ON
    bmi cvs_force               ; the map's parts
    lda KANJI_BAND
    beq cvs_body                ; no split this frame
cvs_force:
cv_sforce:                      ; (label for the gates)
    lda PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #$00
    sta PPUADDR                 ; v = $1000
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
cv_sforce_end:                  ; (label for the gates)
    lda #0
    sta MMC3_IRQ_LATCH
cv_sreload:                     ; (label for the gates)
    sta MMC3_IRQ_RELOAD         ; stage 0 at the pre-render line's clock
    sta MMC3_IRQ_OFF
    sta MMC3_IRQ_ON
    lda KANJI_NFLAGS
    ora #FLAG_ARMED
    sta KANJI_NFLAGS
cvs_body:
    lda #$40
    sta CV_STRM                 ; bit 6: cv_nmi called from here
    jsr cvn_live
    lda #$80
    sta CV_STRM                 ; bit 7: cv_nmi done in this NMI
cvs_rts:
    rts

; ----------------------------------------------------------------------
; NMI, normal frames (ef08_gate) and cv_stream: the split's force and arm
; run from the text renderer's bank (txr.asm nmi_cv / nmi_live), mapped
; at $8000-$9FFF here; the NMI's last restore_bank_after_nmi maps the
; current bank back.
; ----------------------------------------------------------------------
cv_nmi:
    jsr txr_map6
    jmp TXR_NMI_CV
cvn_live:
    jsr txr_map6
    jmp TXR_NMI_LIVE
txr_map6:
    lda #MMC3_R6
    sta MMC3_SELECT
    lda #TXR_BANK*2
    sta MMC3_DATA
    rts

; ----------------------------------------------------------------------
; The nametable fill set_ppu_scroll ($C2AB, patched "jmp cv_fill"): A =
; table ($20 / $24), X = tile, Y = attribute byte; rendering off.  On the
; original's two mirrored tables the fill also filled the lower twin ($28
; / $2C); with four screens the twin kept the previous screen's map, which
; the battle shake (scroll_y $ED: row 29 of the lower half in the top 3
; lines) brought into view.  Both tables here, unrolled: ~9.4k cycles,
; a little under the original's one table (~9.8k), so the screens set up
; at the original's pace.  The original's exit state ($00-$02 = A/X/Y,
; A = $C0, X = tile, Y = attribute).  Game code for the RAM gates.
; ----------------------------------------------------------------------
cv_fill:
    sta $00
    stx $01
    sty $02
    ldx #TXF_FILL               ; (leaving map mode: the font back first)
    jsr txr_call
    ldy $02
    lda #$C0
    ldx $01
    rts
cv_fill_end:                    ; (label for the RAM gates)

; ----------------------------------------------------------------------
; text_init's "jsr scroll_map" ($CB1B, $CB80): the game's row drawing,
; then step B's battle hook (UIF_SM after every row pair, UI_SMRET =
; the return address low byte: $1D a line, $82 the window's last pair).
; ----------------------------------------------------------------------
cv_sm:
    jsr SCROLL_MAP
    lda UI_BATTLE
    beq @rts
    tsx
    lda $0101,x
    sta UI_SMRET
    ldx #UIF_SM
    jsr CALL_UI_C
    lda vram_queue_write        ; a long queue (the blanking beside a
    sec                         ; command window): flushed now, so the
    sbc vram_queue_read         ; next row pair cannot push the NMI's
    cmp #SM_QMAX+1              ; flush past vblank
    bcc @rts
    jmp WAIT_VBLANK
@rts:
    rts

; Battle window templates ($11, $12, $16, $17; kanji_build patches them):
; "$F8 cv_wincb n" calls the UI bank for line kind n with the row-buffer
; index X (returned in X).
cv_wincb:
    stx UI_X
    ldx #UIF_WINCB
    jmp CALL_UI_C

; ======================================================================
; Map text renderer stubs (txr.asm in bank TXR_BANK)
; ======================================================================

; X = function: map the renderer bank (lock protocol), run it, map the
; bank that was current.  $10/$11 kept.  A, X, Y lost.  Nothing on the
; stack: the text task's stack is small (TEXT_RENDERER.md); every wait is
; the stubs' own, at the original routine's depth.
txr_call:
    lda $10
    sta TXR_S10
    lda $11
    sta TXR_S11
    lda current_prg_bank
    sta TXR_SB
    lda #TXR_BANK
    jsr SET_BANK_LOCK
    jsr $8000
    lda TXR_SB
    jsr SET_BANK_LOCK
    lda TXR_S10
    sta $10
    lda TXR_S11
    sta $11
    rts

; TXR_GBUF[TXR_RO..] = TXR_RN bytes of 16 KiB bank A from TXR_RS, every
; TXR_RST bytes; then the renderer bank again.  Main thread.
txr_rr:
    jsr SET_BANK_LOCK
    lda TXR_RS
    sta txr_rr_src+1
    lda TXR_RS+1
    sta txr_rr_src+2
    ldx TXR_RO
    ldy TXR_RN
txr_rr_src:
    lda $FFFF
    sta TXR_GBUF,x
    inx
    lda txr_rr_src+1
    clc
    adc TXR_RST
    sta txr_rr_src+1
    lda txr_rr_src+2
    adc TXR_RST+1
    sta txr_rr_src+2
    dey
    bne txr_rr_src
    lda #TXR_BANK
    jmp SET_BANK_LOCK

; text_draw_line's end ($DD03, X = the queue's end): in map mode the
; renderer translates the line's entries first.
txr_dlx:
    bit TXR_ON
    bpl @c
    stx TXR_QX
    ldx #TXF_DL
@call:
    jsr txr_call
    lda TXR_ST
    beq @done
@w:
    jsr WAIT_VBLANK             ; the NMI uploads the batch (or reads a row)
    lda TXR_UQN
    ora TXR_RBQ
    bne @w
    ldx #TXF_DLC
    bne @call
@done:
    ldx TXR_QX
@c:
    lda #0
    sta $0400,x
    stx vram_queue_write
    rts

; text_render_cell ($DBCA): the renderer's own loop in map mode.
txr_rcx:
    bit TXR_ON
    bmi @m
    ldx text_line               ; the original's first three instructions
    lda CELL_ROWS,x
    sta ptr1_hi
    jmp RENDER_CELL_LOOP
@m:
    ldx #TXF_RC
@call:
    jsr txr_call
    lda TXR_ST
    beq @end
    lsr a                       ; 1: a frame for the NMI (TXF_RCC checks
    bcc @pause                  ; the batch, its cells, the GC's row read)
    jsr WAIT_VBLANK
    jmp @cont
@pause:                         ; the original's per-cell pause, per cell
    lda input_buttons
    and #$10
    bne @cont
@cell:
    lda frame_counter
    lsr a
    bcs @ns
    lda #$07
    jsr SOUND_QUEUE_ADD
@ns:
    lda text_speed
    ldx TXR_Y
    ldy $0318,x
    cpy #$0A
    bne @f
    clc
    adc #2
@f:
    pha
    jsr UPDATE_FRAME
    pla
    sec
    sbc #1
    bpl @f
    inc TXR_Y
    dec TXR_WC
    bne @cell
@cont:
    ldx #TXF_RCC
    bne @call
@end:
    lda input_buttons
    and #$10
    beq @r
    jsr WAIT_VBLANK
@r:
    lda TXR_RET
    rts

; text_draw_cursor's tile store ($CD07, "pla / sta $0400,x" patched to
; "pla / jsr txr_cur"; also text_put_char's ▼ and blank): A = the tile.  In
; map mode ▶ ($70), ▼ ($71) and the blank ($0A) are the fixed set's $0A,
; $0B and $7F.
txr_cur:
    bit TXR_ON
    bpl @st
    cmp #$0A
    beq @b
    cmp #$70
    bcc @st
    cmp #$72
    bcs @st
    sbc #$65                    ; (C clear: - $66) $70 -> $0A, $71 -> $0B
    bne @st
@b:
    lda #$7F
@st:
    sta $0400,x
    rts

; screen_refresh's "jsr load_battle_palette" ($CF22, the map setup): the
; renderer's page setup in place of the font load.  (The boot's font load,
; from the reset path, stays the game's: the title and the scenes use the
; font, and the band page gets its copy.)
txr_mi:
    ldx #TXF_MAPINIT
    jmp txr_call

; redraw_start's first instruction: the full redraw that closes every map
; window (TXF_RESET: the glyphs stay; txr.asm txr_close).  X and Y kept.
txr_rd:
    bit TXR_ON
    bpl @r
    stx TXR_RX
    sty TXR_RY
    ldx #TXF_RESET
    jsr txr_call
    ldx TXR_RX
    ldy TXR_RY
@r:
    rts

; text_put_tile's calls in the window templates ($CC02) and in the item,
; tactic and place names ($D5C0), in map mode (txr_tp, fixed bank): the
; renderer's TXF_PUT puts the byte, or a kana word's kanji form.  A = the
; byte, X = the row-buffer index, Y kept; X after the cell(s).
txr_tpm:
    sta TXR_TA
    stx TXR_TX
    ldx #TXF_PUT
    jmp txr_call

; The boot screens (bank 13: the main menu, starting, registering, deleting
; and copying a history book, the name entry), in place of their "jsr
; loc_C139" after ppu_init (rendering off): the fixed kanji set into the
; upper page (TXF_MENU); then the original.  The next clear_screen ends it.
txr_menu:
    ldx #TXF_MENU
    jsr txr_call
    jmp LOC_C139

cv_ram_end:
