; ======================================================================
; Map-canvas step 3: the dialogue canvas, RAM code.
;
; Assembled for CV_RAM ($7900, battery RAM of the third save record, which
; the kanji target no longer offers).  kanji_build.py stores the image in
; PRG bank CV_BANK at $A000; hack_init copies it at reset.  It runs from
; RAM because it calls the game's map lookups (draw_map_area maps banks 9
; and 12/13 over $8000-$BFFF) and must stay mapped across them.
;
; A text window whose rows reach the band (screen rows 18-27: metarows
; 9-13 below the camera's top) in map mode is drawn into the other
; vertical half: the address EOR $0800, the same in-half rows.  Its first
; band metarow must be the band's top (the dialogue window's is); each new
; metarow gets the map's tiles beside the window (the game's own metatile
; lookup) and the map's palettes (the attribute shadow mirrored into the
; canvas half).  The NMI shows CV_ROWS tile rows of it from line 144: an
; IRQ in line 143 points the PPU at the canvas, another one line above the
; canvas's end points it back at the map.  The visible half is never
; written while the canvas is up, so the full redraw that closes the
; window only shrinks the canvas from the bottom as it passes.
;
; Entry points (fixed-bank patches and the hack bank):
;   cv_irq    IRQ, KANJI_IRQ_ST != 0 (stage 0 and the canvas stages)
;   cv_ctp    cursor_to_ppu's tail
;   cv_ti     text_init, each window metarow ("jsr cursor_to_ppu /
;             jsr tile_address")
;   cv_sm     text_init's "jsr scroll_map" (both sites)
;   cv_nmi    NMI, normal frames, after the game's flush
;   cv_split  irq_arm0, canvas frames: the split's PPU addresses
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

CURSOR_TO_PPU     = $D7E9
TILE_ADDRESS      = $D953
SCROLL_MAP        = $DB87
DRAW_MAP_AREA     = $D83E
DRAW_MAP_OBJECT   = $DAF2
CURSOR_ADD_Y_S    = $D7D1       ; cursor_add_y_signed
MAP_TILE_PAGES    = $F6C9       ; data_F6C9: metatile tile table pages by class
ROW_TOP           = $DBC6       ; scroll_map's text_line for row 0, by text_line
ROW_BOTTOM        = $DBC8       ;   and for row 1
LINE_OFFSET       = $DD0B       ; text_draw_line's row-buffer offset by text_line
ROW_BUFFER        = $0300
QUEUE             = $0400

; IRQ delays (calibrated: the second $2006 write lands at dots 257-320).
CV_D1             = 1
CV_D2             = 5

.base CV_RAM
.org CV_RAM

; ----------------------------------------------------------------------
; IRQ (A pushed by irq_handler), KANJI_IRQ_ST != 0.
;   1 / 2   stage 0, in line 0: reload for line KANJI_IRQ_N; the band
;           stage (ST 0) or canvas stage 1 (ST $80) comes there
;   $80     canvas stage 1, in line 143: the canvas from line 144
;   $81     canvas stage 2: the map again below the canvas
; ----------------------------------------------------------------------
cv_irq:
    lda KANJI_IRQ_ST
    bmi cv_stage
    lda KANJI_IRQ_N
    sta MMC3_IRQ_LATCH
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_OFF
    sta MMC3_IRQ_ON
    lsr KANJI_IRQ_ST            ; 1 -> 0 (band), 2 -> 1
    beq @band
    lda #$80
    sta KANJI_IRQ_ST
    jsr cv_split                ; the canvas's addresses, long before line 142
@band:
    pla
    rti

cv_stage:
    txa
    pha
    lda KANJI_IRQ_ST
    lsr a
    bcs cv_stage2
    sta MMC3_IRQ_OFF            ; acknowledge
    lda CV_LATCH
    sta MMC3_IRQ_LATCH
    sta MMC3_IRQ_RELOAD         ; reloads at this line's clock
    sta MMC3_IRQ_ON
    inc KANJI_IRQ_ST            ; $81: stage 2 next
    lda nmi_busy
    bne cv_out
    ldx #CV_D1
@w1:
    dex
    bne @w1
    bit PPUSTATUS
    lda CV_V1H
    sta PPUADDR
    lda CV_V1L
cv_w1:                          ; (label for the timing probe)
    sta PPUADDR                 ; hblank of line 143: the canvas from line 144
    ; Kanji band (BG tiles $00-$7F): from the window's top border row,
    ; whose tiles are the same on both pages.
    lda KANJI_BAND
    beq cv_out
    lda #MMC3_R0
    sta MMC3_SELECT
    lda #CHR_BAND_LO
    sta MMC3_DATA
    lda KANJI_NFLAGS
    ora #FLAG_HIT|FLAG_PAGE2
    sta KANJI_NFLAGS
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
cv_out:
    pla
    tax
    pla
    rti

cv_stage2:
    sta MMC3_IRQ_OFF            ; acknowledge; off until the next arm
    lda nmi_busy
    bne cv_out
    ldx #CV_D2
@w2:
    dex
    bne @w2
    bit PPUSTATUS
    lda CV_V2H
    sta PPUADDR
    lda CV_V2L
cv_w2:                          ; (label for the timing probe)
    sta PPUADDR                 ; the map again from the next line
    jmp cv_out
cv_irq_end:

; ----------------------------------------------------------------------
; NMI, normal frames (ef08_gate: after the game's PPU work and its
; nmi_mode branch, so the game's own split loops keep their timing).
; CV_ROWS takes CV_PEND: growing once the queue is empty (the rows were
; queued before CV_PEND grew), shrinking once the flush passed the closing
; redraw's row.  In a long frame (the hack's NMI does no PPU work after
; this) the PPU-address force (v = $1000: A12 high when vblank ends, the
; pre-render line's first BG fetch is no MMC3 clock; t restored) and a
; canvas's arm come here at once: stage 0 at the pre-render line's clock,
; stage 1 (KANJI_IRQ_ST 2 -> $80) at line 142's clock; a dialogue
; window's frames push the hack's NMI past vblank.  In a light frame
; irq_arm0 does both after the hack's own PPU work, as for the band.
; Stage 0's handler computes the split's addresses (cv_split).
; Fixed-position screens (title, battle, scenes) have no canvas.  A only.
; ----------------------------------------------------------------------
cv_nmi:
    lda nmi_busy
    beq cvn_live
    rts                         ; the main thread owns the PPU
cvn_live:
    lda input_buttons
    bpl cvn_class
    lda #0
    sta CV_REDIR
    sta CV_PEND
cvn_class:
    ; A long frame (nmi_ef08 arms first thing, no hack unit or replay
    ; follows): the force and the canvas's arm come first, before the
    ; bookkeeping below.  A light frame: irq_arm0 does both after the
    ; hack's own PPU work.
    lda ppu_mask_shadow
    and #$18
    beq cvn_pend                ; rendering off
    lda vram_queue_read
    sec
    sbc KANJI_QPOS              ; bytes the game flushed this frame
    cmp #REPLAY_MAX+1
    bcs cvn_long
    lda $39
    cmp KANJI_LAST39
    beq cvn_pend
    lda #0                      ; (a CHR-animation step: a short flush)
cvn_long:
    cmp #CV_FORCE_MAX+1
    bcs cvn_arm                 ; the game's NMI ran late: no PPU access
cv_force:                       ; (label for the gates)
    lda PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
cv_force_end:
cvn_arm:
    lda CV_ROWS
    ora CV_PEND
    beq cvn_pend                ; no canvas shown or coming
    lda #0
    sta MMC3_IRQ_LATCH
cv_reload:                      ; (label for the gates)
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_OFF            ; acknowledge anything pending
    sta MMC3_IRQ_ON
    lda #2
    sta KANJI_IRQ_ST
    lda #CV_TOP*8-2
    sta KANJI_IRQ_N
    lda #$80
    sta CV_ARMED                ; (stage 0 waits for the cli below)
cvn_pend:
    lda CV_PEND
    cmp CV_ROWS
    beq cvn_done
    bcs cvn_grow
    ; Shrinking (the closing redraw): once the flush has passed the queue
    ; position cv_ctp saw, i.e. with the redrawn row's map entries, as the
    ; original's window row vanished.
    lda vram_queue_read
    cmp CV_Q
    beq cvn_done
    lda CV_PEND
    sta CV_ROWS
    bne cvn_done
    sta KANJI_BAND              ; closed: the kanji band goes with it
    sta CV_SROWS                ; (the next canvas computes its split)
    beq cvn_done
cvn_grow:
    ; Growing: once the queue is empty (the rows were queued before
    ; CV_PEND grew).
    lda vram_queue_read
    cmp vram_queue_write
    bne cvn_done
    lda CV_PEND
    sta CV_ROWS
cvn_done:
    bit CV_ARMED
    bpl cvn_rts
    lda #0
    sta CV_ARMED
    lda CV_ROWS
    beq cvn_cancel
    cli                         ; stage 0 may preempt the rest of the NMI
    rts
cvn_cancel:                     ; no canvas rows this frame after all
    sta MMC3_IRQ_OFF
    sta KANJI_IRQ_ST
cvn_rts:
    rts

; ----------------------------------------------------------------------
; IRQ stage 0 of a canvas frame (line 0, or late in the NMI it preempts):
; the two $2006 pairs and the stage-2 latch (stage 1 comes at line 142's
; clock).  Scratch CV_I0-CV_I2 (not the NMI's: it may be preempted); A only.
; ----------------------------------------------------------------------
cv_split:
    lda CV_ROWS
    cmp CV_SROWS
    bne @new
    rts                         ; (the camera rests while the canvas is up)
@new:
    sta CV_SROWS
    lda ppu_ctrl_shadow
    and #$03
    asl a
    asl a
    sta CV_I0                ; the camera's table bits ($08 lower, $04 right)
    lda scroll_y
    lsr a
    lsr a
    lsr a
    clc
    adc #CV_TOP
    cmp #30
    bcc @h1
    sbc #30
    sta CV_I2
    lda CV_I0
    eor #$08
    sta CV_I0
    lda CV_I2
@h1:
    sta CV_I2                ; the band top's in-half row
    lsr a
    lsr a
    lsr a
    ora CV_I0
    eor #$08                    ; the canvas: the other vertical half
    sta CV_V1H
    lda scroll_x
    lsr a
    lsr a
    lsr a
    sta CV_I1                ; coarse X
    lda CV_I2
    asl a
    asl a
    asl a
    asl a
    asl a
    ora CV_I1
    sta CV_V1L
    lda CV_I2
    clc
    adc CV_ROWS
    cmp #30
    bcc @h2
    sbc #30
    sta CV_I2
    lda CV_I0
    eor #$08
    sta CV_I0
    lda CV_I2
@h2:
    sta CV_I2
    lsr a
    lsr a
    lsr a
    ora CV_I0
    sta CV_V2H
    lda CV_I2
    asl a
    asl a
    asl a
    asl a
    asl a
    ora CV_I1
    sta CV_V2L
    lda CV_ROWS
    asl a
    asl a
    asl a
    sec
    sbc #1
    sta CV_LATCH
    rts

; ----------------------------------------------------------------------
; A = the band index (0-4) of the cursor's metarow, C clear; C set when
; it is outside the band.  Main thread; CV_S, CV_T0.
; ----------------------------------------------------------------------
cv_band:
    lda cursor_y
    lsr a
    lda cursor_x
    bcc @u
    adc #14                     ; +15: the lower vertical half
@u:
    sta CV_S                    ; the cursor's metarow on the 30-metarow ring
    lda ppu_ctrl_shadow
    and #$02
    beq @c
    lda #15
@c:
    sta CV_T0
    lda scroll_y
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc CV_T0                   ; the camera's top metarow
    eor #$FF
    sec
    adc CV_S                    ; cursor - camera
    bcs @p
    adc #30
@p:
    sec
    sbc #CV_TOP/2
    cmp #5
    rts

; ----------------------------------------------------------------------
; cursor_to_ppu's tail (A = the address low byte for $68, $69 stored).
; While the canvas takes writes, a band metarow's address moves to the
; canvas.  While it closes, a map row redrawn in the band ends the canvas
; above it.
; ----------------------------------------------------------------------
cv_ctp:
    sta ppu_addr_lo_shadow
    bit CV_REDIR                ; (bit 7 only: redraw_start shifts it out)
    bmi @go
    lda CV_PEND
    beq @rts
@go:
    jsr cv_band
    bcs @rts
    bit CV_REDIR
    bpl @shrink
    lda ppu_addr_hi_shadow
    eor #$08
    sta ppu_addr_hi_shadow
@rts:
    rts
@shrink:
    asl a
    cmp CV_PEND
    bcs @rts
    sta CV_PEND
    lda vram_queue_write        ; the row's map entries come after this
    sta CV_Q
    rts

; ----------------------------------------------------------------------
; text_init, each window metarow, in place of "jsr cursor_to_ppu / jsr
; tile_address".  Returns X = the attribute-shadow index for the window's
; palette bits and attribute writes: the canvas half's for a canvas row.
; ----------------------------------------------------------------------
cv_ti:
    lda #$FF
    sta CV_CUR
    lda input_buttons
    bmi @plain                  ; fixed-position windows: not the map
    jsr cv_band
    bcs @plain
    bit CV_REDIR
    bmi @on
    tax
    bne @plain                  ; the canvas starts at the band's top metarow
    ldx CV_PEND
    bne @plain                  ; (still closing)
    lda #$80
    sta CV_REDIR
    stx CV_MROWS
    txa
@on:
    sta CV_CUR
    jsr CURSOR_TO_PPU           ; moved into the canvas by cv_ctp
    jsr TILE_ADDRESS            ; X = the visible half's shadow index
    ; This metarow's quadrant pair of its attribute row (16 bytes), visible
    ; half -> canvas half; the canvas's other pair stays (the metarow next
    ; to it can be a live buffer row of the map).
    txa
    pha
    lda cursor_x
    lsr a
    lda #$0F
    bcc @m
    lda #$F0
@m:
    sta CV_T0
    txa
    and #$F0
    tax
    lda #16
    sta CV_S
@cp:
    txa
    eor #$80
    tay
    lda MAP_ATTR,x
    eor MAP_ATTR,y
    and CV_T0
    eor MAP_ATTR,y
    sta MAP_ATTR,y
    inx
    dec CV_S
    bne @cp
    pla
    eor #$80
    tax
    stx CV_BC
    rts
@plain:
    jsr CURSOR_TO_PPU
    jmp TILE_ADDRESS

; ----------------------------------------------------------------------
; text_init's "jsr scroll_map".  A new canvas metarow is queued whole: two
; 32-cell rows (the map beside the window, the window's cells from the row
; buffer) and the screen row's attribute bytes, in as few entries as the
; nametable edge allows (the window frames carry the most VRAM traffic of
; the dialogue).  A canvas metarow already set up gets scroll_map's own
; window rows and attribute bytes (moved into the canvas).  The canvas
; shows it from the next frame on.
; ----------------------------------------------------------------------
cv_sm:
    ldx CV_CUR
    bmi @plain
    cpx CV_MROWS
    bcc @old
    bne @plain                  ; a gap below the canvas: not shown
    lda input_buttons
    bne @plain                  ; (map windows have none)
    jsr cv_flanks
    inc CV_MROWS
    jmp @shown
@old:
    jsr SCROLL_MAP
@shown:
    lda CV_CUR
    asl a
    adc #2
    cmp CV_PEND
    bcc @rts
    sta CV_PEND
@rts:
    rts
@plain:
    jmp SCROLL_MAP

; ----------------------------------------------------------------------
; A new canvas metarow, in place of scroll_map: the tiles of every
; metatile not wholly under the window (draw_map_area, as the game's row
; drawing) and the window's cells (scroll_map's row-buffer rows) make two
; 32-cell rows; then the screen row's attribute bytes (the window's
; palette bits are already in the canvas shadow).  Cursor = the window's
; metarow and left metacol, text_speed_count = its width, text_line its
; row-buffer pair, CV_BC its attribute index, $68/$69 its first row's
; canvas address (cv_ti).
; ----------------------------------------------------------------------
cv_flanks:
    ldx #3
@sv:
    lda cursor_x,x
    sta CV_SAVE,x
    dex
    bpl @sv
    lda current_bank_b
    sta CV_SAVE+4
    lda current_prg_bank
    sta CV_SAVE+5
    lda tile_id_base
    sta CV_SAVE+6
    ; geometry
    lda ppu_ctrl_shadow
    lsr a                       ; C = the camera's right table
    lda scroll_x
    ror a
    lsr a
    lsr a
    lsr a
    sta CV_M0                   ; table << 4 | scroll_x >> 4
    asl a
    and #$3F
    sta CV_C0                   ; screen column 0's nametable column
    lda cursor_y2
    lsr a
    lda cursor_x2
    bcc @l
    ora #$10
@l:
    sec
    sbc CV_M0
    and #$1F
    sta CV_WL
    lda text_speed_count
    lsr a
    clc
    adc CV_WL
    sta CV_WR
    lda ppu_addr_hi_shadow
    and #$FB
    sta CV_HB
    lda ppu_addr_lo_shadow
    and #$E0
    sta CV_LB
    ; the metatiles, from screen metacol 0
    lda #0
    sec
    sbc CV_WL
    jsr CURSOR_ADD_Y_S
    ldx #0
@mt:
    cpx CV_WL
    bcc @look
    cpx CV_WR
    bcc @next
@look:
    stx CV_S
    jsr DRAW_MAP_AREA           ; Y = the metatile; bank 9 mapped
    lda #0
    sta ppu_addr_lo
    ldx class_index
    lda MAP_TILE_PAGES,x
    sta ppu_addr_hi
    lda CV_S
    asl a
    tax
    lda (ppu_addr_lo),y
    sta CV_FLANK,x
    inc ppu_addr_hi
    lda (ppu_addr_lo),y
    sta CV_FLANK+1,x
    inc ppu_addr_hi
    lda (ppu_addr_lo),y
    sta CV_FLANK+32,x
    inc ppu_addr_hi
    lda (ppu_addr_lo),y
    sta CV_FLANK+33,x
    ldx CV_S
@next:
    lda #1
    jsr CURSOR_ADD_Y_S
    inx
    cpx #16
    bne @mt
    ldx #3
@rs:
    lda CV_SAVE,x
    sta cursor_x,x
    dex
    bpl @rs
    lda CV_SAVE+4
    sta current_bank_b
    lda CV_SAVE+5
    jsr SET_BANK_LOCK
    ; the window's cells: row 0 from scroll_map's top line, row 1 from its
    ; bottom line (text_draw_line's buffer offsets)
    ldx text_line
    lda ROW_TOP,x
    tax
    ldy LINE_OFFSET,x
    lda CV_WL
    asl a
    tax
    jsr cv_wincells
    ldx text_line
    lda ROW_BOTTOM,x
    tax
    ldy LINE_OFFSET,x
    lda CV_WL
    asl a
    ora #$20
    tax
    jsr cv_wincells
    ; both rows, whole
    lda #0
    sta CV_R
@row:
    lda #0
    sta CV_C
    lda #32
    sta CV_N
    jsr cv_emit
    lda CV_R
    eor #1
    sta CV_R
    bne @row
    lda ppu_addr_lo_shadow      ; (as scroll_map leaves it: the second row)
    ora #$20
    sta ppu_addr_lo_shadow
    ; the screen row's attribute bytes, the window's run among them
    lda #0
    sta tile_attr
    lda CV_M0
    lsr a
    sta CV_T0                   ; the screen's first byte (bit 3: table)
    lda CV_BC
    and #$F0
    ora CV_T0
    sta battle_cursor
    lda CV_M0
    and #$01
    ora #$08                    ; 8 bytes, 9 when the screen starts mid-byte
    sta tile_id_base
    jsr DRAW_MAP_OBJECT
    lda CV_SAVE+6
    sta tile_id_base
    rts

; text_speed_count cells from the row buffer at Y into CV_FLANK at X.
cv_wincells:
    lda text_speed_count
    sta CV_K
@c:
    lda ROW_BUFFER,y
    sta CV_FLANK,x
    inx
    iny
    dec CV_K
    bne @c
    rts

; CV_R = tile row 0/1, CV_C = first screen column, CV_N = cells: one run
; of CV_FLANK into the canvas row, split at the nametable's edge.
cv_emit:
    lda CV_N
    bne @go
    rts
@go:
    ldx vram_queue_write
@ent:
    lda CV_C
    clc
    adc CV_C0
    and #$3F
    sta CV_K                    ; nametable column 0-63
    and #$20
    lsr a
    lsr a
    lsr a
    ora CV_HB
    sta QUEUE,x
    inx
    lda CV_R
    lsr a
    lda CV_K
    and #$1F
    ora CV_LB
    bcc @r0
    ora #$20
@r0:
    sta QUEUE,x
    inx
    lda CV_K
    and #$1F
    eor #$1F
    clc
    adc #1                      ; room left in this table's row
    cmp CV_N
    bcc @k
    lda CV_N
@k:
    sta CV_K
    sta QUEUE,x
    inx
    lda CV_R
    lsr a
    lda CV_C
    bcc @b
    ora #$20
@b:
    tay
    lda CV_K
    sta CV_T0
@d:
    lda CV_FLANK,y
    sta QUEUE,x
    inx
    iny
    dec CV_T0
    bne @d
    lda CV_C
    clc
    adc CV_K
    sta CV_C
    lda CV_N
    sec
    sbc CV_K
    sta CV_N
    bne @ent
    lda #0
    sta QUEUE,x
    stx vram_queue_write
    rts

cv_ram_end:
