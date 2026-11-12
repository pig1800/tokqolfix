; ======================================================================
; Map-mode text renderer (TEXT_RENDERER.md, 2026-11-12).  PRG bank
; TXR_BANK, assembled for $8000.  txr_call (RAM, canvas_ram.asm) maps it
; with the game's lock protocol and calls $8000 with X = function; $10/$11
; are saved around the call.  Main thread only.
;
; Screen parts: rows 0-8, 9-14, 15-20, 21-29 show BG tiles $00-$7F from
; the pages R0 = 4, 8, 10, 12 (CHR $1000, $2000, $2800, $3000); the IRQ
; switches R0 in the hblank of lines 71, 119 and 167.  Every page holds the
; fixed set (old codes $6D $0B $6E $6F $0C $0D $7D $7E $0E $0F $70 $71) at
; tiles $00-$0B and a blank $7F; page 1 holds コマンド at $7B-$7E.  The
; rest is allocated per part: kanji in 4-tile groups from $0C up (t, t+1,
; t+2, t+3 = top-left, bottom-left, top-right, bottom-right), kana single
; tiles from the top down.  Text tiles are 1bpp: plane 0, plane 1 zero.
;
; The game's text cells hold old font codes ($00-$7F) and, from the
; overlay, kanji halves $80 + 2e (left) / $81 + 2e (right), e = the page
; entry (REG_LO/HI[e] = glyph code); $FA-$FF are line-end codes.  A row's
; screen row gives its part, its parity the kanji half's row (text lines
; start on odd rows in map mode).  Glyphs a row needs are uploaded (the NMI
; after the game's flush, TXR_UQ) before the row's entry is committed.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/canvas_ram.inc"

PTR             = $10           ; (saved by txr_call)
UPDATE_FRAME    = $C0D5
SOUND_QUEUE_ADD = $C4D5
CELL_ROWS       = $DC8F         ; text_render_cell's row-buffer offsets by text_line
FONT_BANK       = 9
FONT_SRC        = $BA00
GLYPH_TAB       = $8C00
GSTRIDE         = 359
BLANK           = $7F

.base $8000
.org $8000
    jmp txr_dispatch            ; $8000: main thread (txr_call)
    jmp nmi_cv                  ; $8003: NMI entries, this bank's first 8 KiB
    jmp nmi_live                ; $8006:   mapped at $8000 by the RAM's
    nop                         ; ($8009: free)
    nop
    nop
txr_dispatch:                   ; (Y kept: TXF_PUT and TXF_LABEL keep it)
    lda txr_fnh,x
    pha
    lda txr_fnl,x
    pha
    rts
txr_fnl:
    .db <(txr_mapinit-1), <(txr_restore-1), <(txr_dl-1), <(txr_rc-1), <(txr_reset-1)
    .db <(txr_dlc-1), <(txr_rcc-1), <(txr_fill-1), <(txr_put-1), <(txr_label-1)
txr_fnh:
    .db >(txr_mapinit-1), >(txr_restore-1), >(txr_dl-1), >(txr_rc-1), >(txr_reset-1)
    .db >(txr_dlc-1), >(txr_rcc-1), >(txr_fill-1), >(txr_put-1), >(txr_label-1)

; ======================================================================
; NMI code (mapped at $8000-$9FFF by the RAM stubs; any bank may be in
; $A000-$BFFF).  Keep it in this bank's first 8 KiB.
; ======================================================================
; ----------------------------------------------------------------------
; NMI, normal frames (ef08_gate: after the game's PPU work and its
; nmi_mode branch), or cv_stream after the stream step.
; Map mode (TXR_ON): R0 = page 1, the PPU-address force (v = $1000: A12
; high when vblank ends, no MMC3 clock at the pre-render line's first BG
; fetch; t restored) unless the game's flush ran long or the uploader left
; v in the pattern table, then the arm: stage 0 at the pre-render line's
; clock, the parts from line 71's clock (KANJI_IRQ_ST 2).  Nothing of the
; hack's NMI follows in map mode (ef08_gate skips it).
; Elsewhere the band, as before: forced and armed here in long frames,
; by irq_arm0 after the hack's own PPU work in light ones.  A, X.
; ----------------------------------------------------------------------
nmi_cv:
    lda nmi_busy
    ora CV_STRM
    beq nmi_live
    lda #0
    sta CV_STRM                 ; (cv_stream ran it in this NMI, or busy)
    rts
nmi_live:
    bit TXR_ON
    bmi cvn_map
    jmp cvn_band_path
cvn_map:
    lda #MMC3_R0
    sta MMC3_SELECT
    lda #CHR_SCENE_LO
    sta MMC3_DATA
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
    lda $39
    sta KANJI_LAST39
    lda vram_queue_read
    sec
    sbc KANJI_QPOS              ; bytes the game flushed this frame
    tax
    lda vram_queue_read
    sta KANJI_QPOS
    lda ppu_mask_shadow
    and #$18
    beq cvn_off                 ; rendering off: no split, none pending
    bit CV_STRM
    bvs cvn_arm                 ; cv_stream forced already (no uploads after it)
    lda TXR_RBQ
    beq @noread
    cpx #48
    bcs @noup                   ; a long flush: the read waits a frame
    stx TXR_Q0
    jsr row_read                ; the GC's row (no uploads this frame)
    ldx TXR_Q0
    jmp @noup
@noread:
    lda TXR_UQN
    beq @noup
    jsr nmi_up                  ; staged glyphs (X = bytes flushed)
@noup:
    cpx #CV_FORCE_MAX+1
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
    lda #0
    sta MMC3_IRQ_LATCH
cv_reload:                      ; (label for the gates)
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_OFF            ; acknowledge anything pending
    sta MMC3_IRQ_ON
    lda #2
    sta KANJI_IRQ_ST
    lda #TXR_N0
    sta KANJI_IRQ_N
    lda KANJI_NFLAGS
    ora #FLAG_ARMED
    sta KANJI_NFLAGS
    lda #0
    sta TXR_UPF
    cli                         ; stage 0 may preempt the rest of the NMI
cvn_rts:
    rts
cvn_off:
    sta MMC3_IRQ_OFF
    sta KANJI_IRQ_ST            ; (A = 0)
    rts
cvn_band_path:
    lda ppu_mask_shadow
    and #$18
    beq cvn_rts                 ; rendering off
    lda vram_queue_read
    sec
    sbc KANJI_QPOS              ; bytes the game flushed this frame
    cmp #CV_FORCE_MAX+1
    bcs cvn_barm                ; the game's NMI ran late: no PPU access
    bit CV_STRM
    bvc cvn_nstrm
    jmp cvn_sarm                ; after the stream step: forced, reloaded
cvn_nstrm:
    cmp #REPLAY_MAX+1
    bcs cvn_need                ; a long frame
    lda $39
    cmp KANJI_LAST39
    beq cvn_rts                 ; a light frame: irq_arm0
cvn_need:
    lda KANJI_BAND
    beq cvn_rts                 ; no split this frame: no PPU access
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
cvn_barm:
    lda KANJI_BAND
    beq cvn_rts                 ; no split this frame
    ; The band alone: armed here, right after the force, as irq_arm0
    ; would after the hack NMI's entry; FLAG_ARMED makes that a no-op.
    lda #0
    sta MMC3_IRQ_LATCH
cv_breload:                     ; (label for the gates)
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_OFF
    sta MMC3_IRQ_ON
    lda KANJI_NFLAGS
    ora #FLAG_ARMED
    sta KANJI_NFLAGS
    jmp cvn_band
; After the stream step (cv_stream forced v and reloaded the counter when
; the band comes): the stage settings; no band: the IRQ off again.
cvn_sarm:
    lda KANJI_BAND
    beq cvb_cancel
cvn_band:                       ; (the band's stage settings)
    lda #1
    sta KANJI_IRQ_ST            ; stage 0, then the band stage
    lda KANJI_WIN_ROW
    asl a
    asl a
    asl a
    sec
    sbc scroll_y
    bcs cvb_row
    sbc #15                     ; borrow: wrap modulo 240
cvb_row:
    cmp #16
    bcc cvb_cancel
    cmp #209
    bcs cvb_cancel
    sta KANJI_IRQ_N
    cmp #ARM_CLI_MIN
    bcc cvb_rts                 ; near the top: stage 0 waits for the NMI's end
    cli
cvb_rts:
    rts
cvb_cancel:
    lda #0
    sta KANJI_IRQ_ST
    sta MMC3_IRQ_OFF
    rts

; The staged glyph tiles after the game's flush (txr_flush, RAM, saved
; the read index in TXR_Q0): 8 tiles after an empty flush, one fewer per 8
; bytes flushed, none with a palette or CHR-stream step pending (they
; follow in this NMI).  R0 = page 1 again after.
nmi_up:
    ; After the game's NMI work (ef08_gate, normal frames only: no cycle
    ; before the game's raster loops), rendering on, vblank: 6 tiles after
    ; an empty flush, one fewer per 8 bytes flushed (the palette may have
    ; gone up too); the rest next frame.  X = bytes flushed, kept.
    stx TXR_Q0
    txa
    cmp #48
    bcs @rts
    lsr a
    lsr a
    lsr a
    eor #$FF
    sec
    adc #6
    sta TXR_I                   ; tiles this NMI (1-6)
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL                 ; +1 increments
    lda #MMC3_R0
    sta MMC3_SELECT
    bit PPUSTATUS
    ldx TXR_UQR
@rec:
    lda TXR_UQ,x
    sta MMC3_DATA
    lda TXR_UQ+1,x
    sta PPUADDR
    lda TXR_UQ+2,x
    sta PPUADDR
    lda TXR_UQ+3,x
    sta PPUDATA
    lda TXR_UQ+4,x
    sta PPUDATA
    lda TXR_UQ+5,x
    sta PPUDATA
    lda TXR_UQ+6,x
    sta PPUDATA
    lda TXR_UQ+7,x
    sta PPUDATA
    lda TXR_UQ+8,x
    sta PPUDATA
    lda TXR_UQ+9,x
    sta PPUDATA
    lda TXR_UQ+10,x
    sta PPUDATA
    txa
    clc
    adc #11
    tax
    dec TXR_UQN
    beq @done
    dec TXR_I
    bne @rec
@done:
    stx TXR_UQR
    lda #CHR_SCENE_LO
    sta MMC3_DATA
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
@rts:
    ldx TXR_Q0
    rts
; The GC's row read (NMI after the game's flush, or the main thread with
; the NMI held off): TXR_N1 cells from TXR_A1H/L and TXR_N2 from
; TXR_A2H/L into TXR_GBUF.
row_read:
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL                 ; +1 increments
    ldy #0
    bit PPUSTATUS
    lda TXR_A1H
    sta PPUADDR
    lda TXR_A1L
    sta PPUADDR
    lda PPUDATA                 ; (the read buffer's old byte)
    ldx TXR_N1
@a:
    lda PPUDATA
    sta TXR_GBUF,y
    iny
    dex
    bne @a
    ldx TXR_N2
    beq @done
    bit PPUSTATUS
    lda TXR_A2H
    sta PPUADDR
    lda TXR_A2L
    sta PPUADDR
    lda PPUDATA
@b:
    lda PPUDATA
    sta TXR_GBUF,y
    iny
    dex
    bne @b
@done:
    lda #0
    sta TXR_RBQ
    rts
nmi_code_end:
.if nmi_code_end > $A000
.error "the renderer's NMI code must stay in the bank's first 8 KiB"
.endif

; Part p's R0 value, group-table base, bitmap base, kana-map base (lo/hi).
part_r0:    .db CHR_SCENE_LO, 8, 10, 12
part_g:     .db 0, TXR_NG, TXR_NG*2, TXR_NG*3
part_b:     .db 0, 16, 32, 48
part_kml:   .db <TXR_KM, <(TXR_KM+$80), <(TXR_KM+$100), <(TXR_KM+$180)
part_kmh:   .db >TXR_KM, >(TXR_KM+$80), >(TXR_KM+$100), >(TXR_KM+$180)
bitmask:    .db $80, $40, $20, $10, $08, $04, $02, $01

; New tiles $00-$0B: the old font codes they show.
fix_src:    .db $6D, $0B, $6E, $6F, $0C, $0D, $7D, $7E, $0E, $0F, $70, $71
; コマンド in page 1, tiles $7B-$7E.
cmd_src:    .db $4B, $24, $68, $6B

; ======================================================================
; Page and allocator setup
; ======================================================================

; The map setup (screen_refresh, in place of its font load), rendering
; off: page 1 lower = the fixed set, コマンド, everything else blank; pages
; 2-4 the first time after reset (nothing else uses them).  Every part's
; glyphs free.  Map mode from here.
txr_mapinit:
    jsr busy_on
    bit TXR_BOOT
    bmi @p1
    lda #8
    jsr page_init
    lda #10
    jsr page_init
    lda #12
    jsr page_init
    lda #$80
    sta TXR_BOOT
@p1:
    lda #CHR_SCENE_LO
    jsr page_init
    ldx #0                      ; コマンド
@cmd:
    stx TXR_G
    lda cmd_src,x
    jsr read_kana
    lda TXR_G
    clc
    adc #$7B
    jsr write_gbuf
    ldx TXR_G
    inx
    cpx #4
    bne @cmd
    jsr busy_off
    jsr txr_reset
    lda #$80
    sta TXR_ON
    rts

; R0 = A, every tile of the page: the fixed set at $00-$0B, the rest blank.
page_init:
    jsr set_r0
    bit PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #0
    sta PPUADDR
    tax                         ; the 2 KiB blank first
@z:
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    dex
    bne @z
    ldx #0
@f:
    stx TXR_G
    lda fix_src,x
    jsr read_kana
    lda TXR_G
    jsr write_gbuf
    ldx TXR_G
    inx
    cpx #12
    bne @f
    rts

; clear_screen (cv_fill, before the fill), rendering off: the font back
; into page 1 lower, as the game loads it.  Not map mode any more.
txr_restore:
    jsr busy_on
    lda #CHR_SCENE_LO
    jsr set_r0
    lda #0
    jsr tile_addr
    lda #<font_copy
    sta PTR
    lda #>font_copy
    sta PTR+1
    ldx #128                    ; tiles
@tile:
    ldy #0
@d:
    lda (PTR),y
    sta PPUDATA
    iny
    cpy #8
    bne @d
    lda #0
    ldy #8
@z:
    sta PPUDATA
    dey
    bne @z
    lda PTR
    clc
    adc #8
    sta PTR
    bcc @n
    inc PTR+1
@n:
    dex
    bne @tile
    jsr busy_off
    lda #0
    sta TXR_ON
    sta MMC3_IRQ_OFF            ; no map split pending any more
    sta KANJI_IRQ_ST
    rts

; Every part's glyphs free: kana maps empty, groups free, the bitmaps
; holding only the pinned tiles; page 1's コマンド kana pinned.
txr_reset:
    lda #0
    tax
@km:
    sta TXR_KM,x
    sta TXR_KM+$100,x
    inx
    bne @km
    lda #$FF
    ldx #TXR_NG*4-1
@g:
    sta TXR_GHI,x
    dex
    bpl @g
    ldx #63
@b:
    lda #0
    sta TXR_TBM,x
    dex
    bpl @b
    ldx #48
@pin:
    lda #$FF                    ; tiles $00-$07, $08-$0B: fixed
    sta TXR_TBM,x
    lda #$F0
    sta TXR_TBM+1,x
    lda #$01                    ; $7F blank
    sta TXR_TBM+15,x
    txa
    sec
    sbc #16
    tax
    bpl @pin
    lda #$1F                    ; page 1: $7B-$7F
    sta TXR_TBM+15
    ldx #3
@cmd:
    lda cmd_src,x
    tay
    txa
    clc
    adc #$7B
    sta TXR_KM,y
    dex
    bpl @cmd
    lda #0
    sta TXR_UQN
    sta TXR_FULL
    sta TXR_SKIP
    rts

; ----------------------------------------------------------------------
; The nametable fill set_ppu_scroll ($C2AB; RAM cv_fill stores A/X/Y in
; $00-$02 and calls this): A = table ($20 / $24), X = tile, Y = attribute
; byte; rendering off.  Both twins (four-screen), unrolled.  Leaving map
; mode (clear_screen starts every other screen): the font back first.
; ----------------------------------------------------------------------
txr_fill:
    bit TXR_ON                  ; leaving map mode: the font back first
    bpl @go                     ; (TEXT_RENDERER.md)
    jsr txr_restore
@go:
    lda $00
    ldy #1                      ; two tables (no subroutine: the original
    ora #$08                    ; is flat, the stack stays as deep): the
cvf_table:                      ; lower twin first
    bit PPUSTATUS
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda $01
    ldx #64                     ; 64 x 16 bytes
cvf_loop:
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    dex
    beq cvf_tdone
    cpx #4
    bne cvf_loop
    lda $02                     ; the last 64: the attribute bytes
    jmp cvf_loop
cvf_tdone:
    lda $00                     ; then the table
    dey
    bpl cvf_table
    rts

; ======================================================================
; PPU helpers (rendering off, busy: the main thread owns the PPU)
; ======================================================================

; The NMI leaves the PPU alone (busy) and the hack NMI leaves R0 alone.
busy_on:
    inc nmi_busy
    lda #1
    sta KANJI_MAINCHR
    lda ppu_ctrl_shadow         ; +1 increments (a vertical queue entry may
    and #$FB                    ; have left +32)
    sta PPUCTRL
    rts
busy_off:
    lda #CHR_SCENE_LO
    jsr set_r0
    lda #0
    sta KANJI_MAINCHR
    dec nmi_busy
    rts

; R0 = A under the bank-select shadow (main thread).
set_r0:
    pha
    lda #MMC3_R0
    sta MMC3_SEL
    sta MMC3_SELECT
    pla
    sta MMC3_DATA
    rts

; PPU address = plane 0 of tile A (pattern table $1000).
tile_addr:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    bit PPUSTATUS
    sta PPUADDR
    pla
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
    rts

; Tile A of the R0 page = TXR_GBUF[0-7] in plane 0, plane 1 zero.
write_gbuf:
    jsr tile_addr
    ldx #0
@d:
    lda TXR_GBUF,x
    sta PPUDATA
    inx
    cpx #8
    bne @d
    lda #0
@z:
    sta PPUDATA
    dex
    bne @z
    rts

; TXR_GBUF[0-7] = the old font's glyph A (1bpp; this bank's copy of the
; bank-9 font, so no bank switch: the stack stays shallow).
read_kana:
    ldx #0
    stx PTR+1
    asl a
    rol PTR+1
    asl a
    rol PTR+1
    asl a
    rol PTR+1
    sta PTR
    lda PTR+1
    clc
    adc #>font_copy
    sta PTR+1
    ldy #7
@c:
    lda (PTR),y
    sta TXR_GBUF,y
    dey
    bpl @c
    rts

; TXR_GBUF[0-31] = kanji glyph TXR_K (code = bank index * 512 + local:
; high byte bit 0 = the +256 half, the rest the glyph bank 23 + n).
read_kanji:
    lda TXR_K+1
    and #1
    clc
    adc #>GLYPH_TAB
    sta TXR_RS+1
    lda TXR_K
    sta TXR_RS
    lda #<GSTRIDE
    sta TXR_RST
    lda #>GSTRIDE
    sta TXR_RST+1
    lda #0
    sta TXR_RO
    lda #32
    sta TXR_RN
    lda TXR_K+1
    lsr a
    clc
    adc #KANJI_HACK_BANK
    jmp TXR_RR

; ======================================================================
; Staging: TXR_SN records built in TXR_UQ, then published (TXR_UQN) for
; the NMI uploader.  With rendering off (or busy) they are written
; directly, the NMI held off.  The renderer never waits itself: a
; function that needs the NMI returns TXR_ST = 1 and the RAM stub waits
; at the original routine's stack depth, then calls the continuation.
; ======================================================================

; C clear: room for A more records (written directly first when rendering
; is off).  C set: no room, the batch is published (TXR_ST = 1).
stage_room:
    clc
    adc TXR_SN
    cmp #TXR_UQMAX+1
    bcc @ok
    jsr stage_out
    lda TXR_SN                  ; 0 after a direct write
    bne @wait
@ok:
    clc
    rts
@wait:
    sec
    rts

; The batch out: written now (rendering off or busy: TXR_SN = 0 after),
; or published for the NMI (TXR_ST = 1, TXR_SN kept until the stub's
; continuation clears it).
stage_out:
    lda TXR_SN
    beq @rts
    lda nmi_busy
    bne @direct
    lda ppu_mask_shadow
    and #$18
    beq @direct
    lda #0
    sta TXR_UQR
    lda TXR_SN
    sta TXR_UQN
    lda #1
    sta TXR_ST
@rts:
    rts
@direct:
    jsr busy_on
    ldx #0
@rec:
    lda TXR_UQ,x
    jsr set_r0
    bit PPUSTATUS
    lda TXR_UQ+1,x
    sta PPUADDR
    lda TXR_UQ+2,x
    sta PPUADDR
    ldy #8
@d:
    lda TXR_UQ+3,x
    sta PPUDATA
    inx
    dey
    bne @d
    inx
    inx
    inx
    dec TXR_SN
    bne @rec
    jmp busy_off

; Record TXR_SN = tile TXR_T of part TXR_P, bytes TXR_GBUF+Y .. +7.
stage_tile:
    sty TXR_I
    lda TXR_SN
    asl a                       ; x 11
    sta TXR_J
    asl a
    asl a
    adc TXR_J
    adc TXR_SN
    tax
    ldy TXR_P
    lda part_r0,y
    sta TXR_UQ,x
    lda TXR_T
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta TXR_UQ+1,x
    lda TXR_T
    asl a
    asl a
    asl a
    asl a
    sta TXR_UQ+2,x
    ldy TXR_I
    lda #8
    sta TXR_J
@b:
    lda TXR_GBUF,y
    sta TXR_UQ+3,x
    iny
    inx
    dec TXR_J
    bne @b
    inc TXR_SN
    rts

; ======================================================================
; Translation
; ======================================================================

; Part and parity of the nametable address A (high) / X (low) on the
; 60-row ring: TXR_P = 0-3 by screen row, TXR_PAR = 0 for an odd row (a
; text line's top row).
addr_part:
    sta TXR_I
    and #$08                    ; lower vertical half: +30 rows
    beq @u
    lda #30
@u:
    sta TXR_J
    lda TXR_I
    and #$03
    asl a
    asl a
    asl a
    sta TXR_I                   ; (hi & 3) * 8
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    ora TXR_I                   ; row 0-29 in its half
    tax
    and #1
    eor #1
    sta TXR_PAR
    txa
    clc
    adc TXR_J                   ; ring row 0-59
    sta TXR_I
    lda ppu_ctrl_shadow         ; the camera's top ring row
    and #$02
    beq @t
    lda #30
@t:
    sta TXR_J
    lda scroll_y
    lsr a
    lsr a
    lsr a
    clc
    adc TXR_J
    sta TXR_J
    lda TXR_I
    sec
    sbc TXR_J
    bcs @pos
    adc #60
@pos:
    ldx #0
    cmp #9
    bcc @p
    inx
    cmp #15
    bcc @p
    inx
    cmp #21
    bcc @p
    inx
@p:
    stx TXR_P
    rts

; C clear: A = the tile for cell byte A in part TXR_P (row parity
; TXR_PAR); a glyph new in this part is allocated and staged.  Bytes
; $FA-$FF unchanged.  C set: no staging room (nothing allocated; retry
; after the batch is in, TXR_ST = 1).
xlate:
    cmp #$FA
    bcs @keep
    sta TXR_B
    cmp #$80
    bcs @kanji
    tay
    lda fix_map,y
    bpl @ok                     ; the fixed set and the blank
    ; Kana: this part's tile, or a new one from the top down.
    ldx TXR_P
    lda part_kml,x
    sta PTR
    lda part_kmh,x
    sta PTR+1
    ldy TXR_B
    lda (PTR),y
    bne @ok
    lda #1
    jsr stage_room
    bcs @rts
    jsr alloc_kana
    bcs @full
    sta TXR_T
    ldy TXR_B
    sta (PTR),y
    lda TXR_B
    jsr read_kana
    ldy #0
    jsr stage_tile
    lda TXR_T
@ok:
    clc
@rts:
    rts
@keep:
    clc
    rts
@full:
    lda TXR_GCF
    bne @blank                  ; the GC ran for this line already
    jsr stage_out               ; what is staged goes up first
    lda TXR_P
    ora #$80
    sta TXR_GCS                 ; the continuation runs the GC first
    lda #0
    sta TXR_GCR
    lda #1
    sta TXR_ST
    sec
    rts
@blank:
    inc TXR_FULL
    lda #BLANK
    clc
    rts
@kanji:
    and #$7F
    lsr a
    tax
    lda REG_LO,x
    sta TXR_K
    lda REG_HI,x
    sta TXR_K+1
    jsr find_group
    bcc @have
    lda #4
    jsr stage_room
    bcs @rts
    jsr alloc_group
    bcs @full
    jsr read_kanji
    lda TXR_G
    asl a
    asl a
    adc #$0C
    sta TXR_T
    ldy #0                      ; top-left
    jsr stage_tile
    inc TXR_T
    ldy #16                     ; bottom-left
    jsr stage_tile
    inc TXR_T
    ldy #8                      ; top-right
    jsr stage_tile
    inc TXR_T
    ldy #24                     ; bottom-right
    jsr stage_tile
@have:
    lda TXR_G                   ; t + 2 * right half + bottom row
    asl a
    asl a
    adc #$0C
    sta TXR_T
    lda TXR_B
    and #1
    asl a
    ora TXR_PAR
    ora TXR_T
    clc
    rts

; C clear: TXR_G = the group of part TXR_P holding glyph TXR_K.
find_group:
    ldx TXR_P
    lda part_g,x
    tax
    ldy #0
@l:
    lda TXR_GHI,x
    cmp TXR_K+1
    bne @n
    lda TXR_GLO,x
    cmp TXR_K
    beq @f
@n:
    inx
    iny
    cpy #TXR_NG
    bne @l
    sec
    rts
@f:
    sty TXR_G
    clc
    rts

; C clear: TXR_G = a free group of part TXR_P (4 tiles free), now TXR_K's.
alloc_group:
    ldx TXR_P
    lda part_g,x
    sta TXR_I
    lda #0
    sta TXR_G
@l:
    ldx TXR_I
    lda TXR_GHI,x
    cmp #$FF
    bne @n
    jsr group_bits              ; X = bitmap byte, A = the group's 4 bits
    and TXR_TBM,x
    beq @take
@n:
    inc TXR_I
    inc TXR_G
    lda TXR_G
    cmp #TXR_NG
    bne @l
    sec
    rts
@take:
    jsr group_bits
    ora TXR_TBM,x
    sta TXR_TBM,x
    ldx TXR_I
    lda TXR_K
    sta TXR_GLO,x
    lda TXR_K+1
    sta TXR_GHI,x
    clc
    rts

; Group TXR_G of part TXR_P: X = its bitmap byte, A = its 4 bits.  Tiles
; $0C + 4g: byte (3 + g) >> 1, the low nibble for even g.
group_bits:
    lda TXR_G
    clc
    adc #3
    lsr a
    php
    ldx TXR_P
    clc
    adc part_b,x
    tax
    plp
    lda #$0F
    bcs @r
    lda #$F0
@r:
    rts

; C clear: A = a free tile of part TXR_P for a kana, from $7E down to $0C;
; marked used.
alloc_kana:
    ldx TXR_P
    lda part_b,x
    clc
    adc #15
    tax                         ; bitmap byte of tiles $78-$7F
    lda #$7F
    sta TXR_T
@byte:
    lda TXR_TBM,x
    cmp #$FF
    beq @next8
    ldy #7                      ; bit 7 - (tile & 7)
@bit:
    lda bitmask,y
    and TXR_TBM,x
    beq @take
    dec TXR_T
    dey
    bpl @bit
    bmi @nexttile
@next8:
    lda TXR_T
    sec
    sbc #8
    sta TXR_T
@nexttile:
    dex
    txa
    ldy TXR_P
    sec
    sbc part_b,y
    cmp #1                      ; down to byte 1 (tiles $08-$0F: $0C-$0F)
    bcs @byte
    sec
    rts
@take:
    lda TXR_T
    cmp #$0C
    bcc @no
    lda bitmask,y
    ora TXR_TBM,x
    sta TXR_TBM,x
    lda TXR_T
    clc
    rts
@no:
    sec
    rts

; ======================================================================
; GC (a part is full): read the part's visible rows back from VRAM, one
; row a frame (the NMI) or all at once (rendering off), keep the tiles
; shown and the ones this line already uses, free every other kana tile
; and kanji group, then the line goes on (the failed cell retried).
; C set: wait (TXR_ST = 1), then call again; C clear: done.
; ======================================================================
part_row:   .db 0, 9, 15, 21
part_rows:  .db 9, 6, 6, 9

gc_step:
    lda TXR_RBQ
    beq @go
    jmp gc_wait
@go:
    lda TXR_GCS
    and #3
    sta TXR_P
    lda TXR_GCR
    bne gc_got
    ; Start: the bitmap holds the tiles this line already uses (EB's bytes
    ; before TXR_E, the cell's tiles; conservative) and page 1's pins.
    ldx #15
    lda #0
@clr:
    sta TXR_MARK,x
    dex
    bpl @clr
    ldx TXR_E
    beq @cell
@eb:
    dex
    lda TXR_EB,x
    jsr mark_tile
    cpx #0
    bne @eb
@cell:
    lda TXR_CT
    jsr mark_tile
    lda TXR_CT+1
    jsr mark_tile
    lda TXR_CB
    jsr mark_tile
    lda TXR_CB+1
    jsr mark_tile
    lda TXR_MARK+15
    ora #$1E                    ; $7B-$7E (pinned in page 1)
    sta TXR_MARK+15
    ldx TXR_P
    lda part_rows,x
    sta TXR_GN
    jmp gc_req
gc_got:
    ldx #31                     ; the row read: mark its tiles
@m:
    lda TXR_GBUF,x
    jsr mark_tile
    dex
    bpl @m
    lda TXR_GCR
    cmp TXR_GN
    bcs gc_free
gc_req:
    jsr row_addr
    inc TXR_GCR
    lda #1
    sta TXR_RBQ
    lda nmi_busy
    bne @direct
    lda ppu_mask_shadow
    and #$18
    bne gc_wait
@direct:
    jsr busy_on
    jsr row_read
    jsr busy_off
    jmp gc_got
gc_wait:
    lda #1
    sta TXR_ST
    sec
    rts
gc_free:
    ; Kana: a tile no row shows is free again.
    ldx TXR_P
    lda part_kml,x
    sta PTR
    lda part_kmh,x
    sta PTR+1
    ldy #127
@k:
    lda (PTR),y
    beq @kn
    jsr is_marked
    bne @kn
    lda (PTR),y
    jsr tbm_clear
    lda #0
    sta (PTR),y
@kn:
    dey
    bpl @k
    ; Kanji groups: one whose four tiles no row shows is free again.
    lda #0
    sta TXR_G
@g:
    ldx TXR_P
    lda part_g,x
    clc
    adc TXR_G
    tay
    lda TXR_GHI,y
    cmp #$FF
    beq @gn
    lda TXR_G                   ; (3 + g) >> 1, the nibble
    clc
    adc #3
    lsr a
    tax
    lda #$0F
    bcs @nib
    lda #$F0
@nib:
    and TXR_MARK,x
    bne @gn
    lda #$FF
    sta TXR_GHI,y
    jsr group_bits              ; X = the part's bitmap byte, A = nibble
    eor #$FF
    and TXR_TBM,x
    sta TXR_TBM,x
@gn:
    inc TXR_G
    lda TXR_G
    cmp #TXR_NG
    bne @g
    lda #0
    sta TXR_GCS
    sta TXR_GCR
    lda #1
    sta TXR_GCF
    clc
    rts

; A = a tile: set in TXR_MARK when below $7F (X, Y kept).
mark_tile:
    cmp #$7F
    bcs @r
    stx TXR_J
    pha
    and #7
    tax
    lda bitmask,x
    sta TXR_I
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda TXR_I
    ora TXR_MARK,x
    sta TXR_MARK,x
    ldx TXR_J
@r:
    rts

; A = a tile: Z clear when it is in TXR_MARK (Y kept).
is_marked:
    pha
    and #7
    tax
    lda bitmask,x
    sta TXR_I
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda TXR_MARK,x
    and TXR_I
    rts

; A = a tile of part TXR_P: its bit in TXR_TBM cleared (Y kept).
tbm_clear:
    pha
    and #7
    tax
    lda bitmask,x
    eor #$FF
    sta TXR_I
    pla
    lsr a
    lsr a
    lsr a
    ldx TXR_P
    clc
    adc part_b,x
    tax
    lda TXR_I
    and TXR_TBM,x
    sta TXR_TBM,x
    rts

; The nametable addresses of screen row part_row[P] + TXR_GCR: 32 cells
; from the camera's left column, up to two segments (the ring's two
; horizontal tables).
row_addr:
    ldx TXR_P
    lda part_row,x
    clc
    adc TXR_GCR
    sta TXR_I                   ; screen row
    lda ppu_ctrl_shadow
    and #$02
    beq @t
    lda #30
@t:
    sta TXR_J
    lda scroll_y
    lsr a
    lsr a
    lsr a
    clc
    adc TXR_J
    clc
    adc TXR_I                   ; ring row
    cmp #60
    bcc @r60
    sbc #60
@r60:
    ldx #$20                    ; upper half
    cmp #30
    bcc @h
    sbc #30
    ldx #$28                    ; lower half
@h:
    stx TXR_A1H
    sta TXR_I                   ; row in the half
    lsr a
    lsr a
    lsr a
    ora TXR_A1H
    sta TXR_A1H                 ; + row >> 3
    sta TXR_A2H
    lda TXR_I
    asl a
    asl a
    asl a
    asl a
    asl a
    sta TXR_A1L                 ; (row & 7) << 5
    sta TXR_A2L
    lda scroll_x                ; first column on the 64-column ring
    lsr a
    lsr a
    lsr a
    sta TXR_I                   ; column 0-31
    lda ppu_ctrl_shadow
    and #$01
    beq @x
    lda TXR_A1H
    ora #$04
    sta TXR_A1H                 ; the right table first
    bne @x2
@x:
    lda TXR_A2H
    ora #$04
    sta TXR_A2H                 ; the right table second
@x2:
    lda TXR_A1L
    ora TXR_I
    sta TXR_A1L
    lda #32
    sec
    sbc TXR_I
    sta TXR_N1
    lda TXR_I
    sta TXR_N2
    rts

; ======================================================================
; text_draw_line's entries (queue $40 .. TXR_QX).  They leave the queue
; (other tasks may queue while glyphs upload: the stub's waits yield),
; are translated in TXR_EB, then queued again at the queue's end; TXR_QX
; = the new end (the stub writes the terminator and commits).
; TXF_DL starts, TXF_DLC continues after a wait (TXR_ST = 1 returned).
; ======================================================================
txr_dl:
    ldx vram_queue_write
    ldy #0
@out:
    cpx TXR_QX
    beq @outd
    lda $0400,x
    sta TXR_EB,y
    inx
    iny
    cpy #48
    bne @out
@outd:
    sty TXR_EL
    ldx vram_queue_write
    lda #0
    sta $0400,x                 ; the queue ends before them again
    sta TXR_SN
    sta TXR_E
    sta TXR_EN
    sta TXR_GCF
    beq dl_go
txr_dlc:
    lda #0
    sta TXR_SN                  ; (the NMI has the batch in CHR)
    bit TXR_GCS
    bpl dl_go
    jsr gc_step
    bcc dl_go
    rts                         ; (TXR_ST = 1: a row read or uploads)
dl_go:
    lda #0
    sta TXR_ST
@loop:
    ldx TXR_E
    cpx TXR_EL
    bcs @done
    lda TXR_EN
    bne @cell
    lda TXR_EB,x                ; an entry's header
    pha
    lda TXR_EB+1,x
    tax
    pla
    jsr addr_part
    ldx TXR_E
    lda TXR_EB+2,x
    and #$7F
    sta TXR_EN
    inx
    inx
    inx
    stx TXR_E
    jmp @loop
@cell:
    lda TXR_EB,x
    jsr xlate
    bcs @wait
    ldx TXR_E
    sta TXR_EB,x
    inx
    stx TXR_E
    dec TXR_EN
    jmp @loop
@wait:
    rts
@done:
    jsr stage_out
    lda TXR_ST
    bne @wait                   ; the last batch first (TXF_DLC: queued)
    ldx vram_queue_write
    ldy #0
@in:
    cpy TXR_EL
    beq @ind
    lda TXR_EB,y
    sta $0400,x
    inx
    iny
    bne @in
@ind:
    stx TXR_QX
    rts

; ======================================================================
; text_render_cell in map mode (the original at $DBCA), one step a call:
; a cell, or a kanji's two columns (no half kanji), translated and
; queued.  TXR_ST: 0 = the line ended (TXR_RET = its end byte), 1 = wait
; for the uploads then TXF_RCC, 2 = queued: the stub pauses TXR_WC cells
; from row-buffer index TXR_Y (as the original), then TXF_RCC.
; ======================================================================
txr_rc:
    ldx text_line
    lda CELL_ROWS,x
    sta ptr1_hi
    lda #0
    sta TXR_SN
    sta TXR_GCF
    beq rc_step
txr_rcc:
    lda #0
    sta TXR_SN
    bit TXR_GCS
    bpl rc_step
    jsr gc_step
    bcc rc_step
    rts
rc_step:
    lda #0
    sta TXR_ST
    ldy ptr1_hi
    sty TXR_Y
    lda $0300,y
    cmp #$FA
    bcc @cell
    sta TXR_RET                 ; the line's end
    ldx vram_queue_write
    lda #0
    sta $0400,x
    rts
@cell:
    ldx #1
    cmp #$80
    bcc @n1
    lsr a                       ; a kanji's left half (even): both columns
    bcs @n1
    inx
@n1:
    stx TXR_N
    lda ppu_addr_hi_shadow      ; the cell's part (its top row)
    ldx ppu_addr_lo_shadow
    jsr addr_part
    ldy TXR_Y
    lda $0300,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CT
    inc TXR_PAR                 ; (0: the top row) the bottom row
    ldy TXR_Y
    lda $0318,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CB
    lda TXR_N
    cmp #2
    bne @tr
    dec TXR_PAR
    ldy TXR_Y
    lda $0301,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CT+1
    inc TXR_PAR
    ldy TXR_Y
    lda $0319,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CB+1
@tr:
    jsr stage_out
    lda TXR_ST
    bne @rts                    ; uploads first (the cells are retried)
    lda #0
    sta TXR_G
@q:
    ldx TXR_G
    lda TXR_CT,x
    sta TXR_T
    lda TXR_CB,x
    sta TXR_B
    jsr queue_cell
    inc TXR_G
    lda TXR_G
    cmp TXR_N
    bne @q
    ldx vram_queue_write
    lda #0
    sta $0400,x
    lda #0
    sta TXR_GCF                 ; (the next cell may run the GC again)
    lda TXR_N
    sta TXR_WC
    clc
    adc ptr1_hi
    sta ptr1_hi
    lda #2
    sta TXR_ST
@rts:
    rts
@wait:
    rts                         ; (stage_room published: TXR_ST = 1)

; Two queue entries: TXR_T at ($69, $68), TXR_B one row below (the
; four-screen wrap of $DC0E), then the cursor one cell right (the next
; table at column 32).  Committed (vram_queue_write).
queue_cell:
    ldx vram_queue_write
    lda ppu_addr_hi_shadow
    sta $0400,x
    inx
    lda ppu_addr_lo_shadow
    sta $0400,x
    inx
    lda #1
    sta $0400,x
    inx
    lda TXR_T
    sta $0400,x
    inx
    lda ppu_addr_hi_shadow
    sta TXR_I
    lda ppu_addr_lo_shadow
    clc
    adc #$20
    sta TXR_J
    bcc @c
    inc TXR_I
@c:
    cmp #$C0
    bcc @ok
    lda TXR_I
    and #$03
    cmp #$03
    bne @ok
    lda TXR_I                   ; below row 29: row 0 of the other half
    eor #$0B
    sta TXR_I
    lda TXR_J
    and #$1F
    sta TXR_J
@ok:
    lda TXR_I
    sta $0400,x
    inx
    lda TXR_J
    sta $0400,x
    inx
    lda #1
    sta $0400,x
    inx
    lda TXR_B
    sta $0400,x
    inx
    lda #0
    sta $0400,x                 ; the terminator before the commit
    stx vram_queue_write
    inc ppu_addr_lo_shadow
    lda ppu_addr_lo_shadow
    and #$1F
    bne @rts
    lda ppu_addr_hi_shadow
    eor #$04
    sta ppu_addr_hi_shadow
    lda ppu_addr_lo_shadow
    and #$E0
    sec
    sbc #$20
    sta ppu_addr_lo_shadow
@rts:
    rts

; Old font code -> new tile for the fixed set and the blank; bit 7 set:
; a kana (this part's own tile).
fix_map:
    .db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, BLANK, $01, $04, $05, $08, $09
    .dsb $60-$10, $FF
    .db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $02, $03
    .db $0A, $0B, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $06, $07, $FF

; ======================================================================
; Kanji UI (TEXT_RENDERER.md "Kanji UI"): the map's menus in kanji.
; text_put_tile's calls in the window templates (text_input $CC02, bank
; 14 mapped) and in draw_string_from_pointer ($D5C0, bank 12: item names
; from Y = 2, tactic and place names from Y = 0) come here in map mode
; (txr_tp in the fixed bank, txr_tpm in RAM).  A known kana word is put in
; its kanji form (txr_ui.inc, generated by kanji_build.py) and the rest of
; its bytes are skipped; any other byte is put as the game puts it.  The
; ROM's kana stay as they are: battle, the title and the scenes (no map
; mode) show them as before.
; Kanji take the line codes $A0-$BF: REG entries 16-31, a message page's
; are 0-15.  An entry is taken again only when no row buffer ($0300-$035F)
; and no saved row ($0180-$01DF) holds its codes.
; ======================================================================
UI_E0           = 16            ; the first REG entry of the map UI

; TXF_PUT: TXR_TA = the byte, TXR_TX = the row-buffer index, Y = the
; source index (kept).  X = the row-buffer index after the cell(s).
txr_put:
    sty TXR_TY
    lda TXR_SB
    cmp #12
    beq @b12
    cmp #14
    bne @plain
    lda TXR_SKIP                ; a template (window text_mode, text_col Y)
    bne @skip
    jsr ui_tpl
    bcc @str
    bcs @plain
@b12:
    cpy #0
    bne @b12n
    sty TXR_SKIP                ; Y = 0: a tactic or a place name starts
    ldx #UI_N0-1
    jsr ui_r0
    bcc @str
    bcs @plain
@b12n:
    lda TXR_SKIP
    bne @skip
    cpy #2
    bne @plain
    ldx #UI_N2-1                ; Y = 2: an item name starts
    jsr ui_r2
    bcs @plain
@str:
    ldx TXR_TX
    jmp put_str                 ; (Y back from TXR_TY there)
@skip:
    dec TXR_SKIP                ; a byte of a word put in kanji
    ldx TXR_TX
    ldy TXR_TY
    rts
@plain:
    lda TXR_TA
    ldx TXR_TX
    jsr TEXT_PUT_TILE
    ldy TXR_TY
    rts

; Template text_mode's word at text_col TXR_TY: C clear, PTR = its string,
; TXR_SKIP = the bytes to skip.  C set: none.
ui_tpl:
    ldx text_mode
    cpx #UI_NWIN
    bcs @no
    lda ui_win_lo,x
    sta PTR
    lda ui_win_hi,x
    sta PTR+1
    ora PTR
    beq @no
    ldy #0
@w:
    lda (PTR),y
    cmp #$FF
    beq @no
    cmp TXR_TY
    beq @f
    iny
    iny
    iny
    iny
    bne @w
@f:
    iny
    lda (PTR),y
    sta TXR_SKIP
    iny
    lda (PTR),y
    tax
    iny
    lda (PTR),y
    sta PTR+1
    stx PTR
    clc
    rts
@no:
    sec
    rts

; The record at ($F3) among the tactic and place names (ui_r0, X = count
; - 1) or the item names (ui_r2): C clear, PTR = its string, TXR_SKIP set.
ui_r0:
    lda ui_r0_lo,x
    cmp ppu_update_ptr_lo
    bne @n
    lda ui_r0_hi,x
    cmp ppu_update_ptr_hi
    beq @f
@n:
    dex
    bpl ui_r0
    sec
    rts
@f:
    lda ui_r0_sk,x
    sta TXR_SKIP
    lda ui_r0_sl,x
    sta PTR
    lda ui_r0_sh,x
    sta PTR+1
    clc
    rts
ui_r2:
    lda ui_r2_lo,x
    cmp ppu_update_ptr_lo
    bne @n
    lda ui_r2_hi,x
    cmp ppu_update_ptr_hi
    beq @f
@n:
    dex
    bpl ui_r2
    sec
    rts
@f:
    lda ui_r2_sk,x
    sta TXR_SKIP
    lda ui_r2_sl,x
    sta PTR
    lda ui_r2_sh,x
    sta PTR+1
    clc
    rts

; TXF_LABEL (bank 14: the gold window's 金 and 兵糧, the list's その他):
; TXR_TA = the label, TXR_TX = the row-buffer index.  The label from index
; + ui_lb_off; X = index + ui_lb_adv.  Y kept.
txr_label:
    sty TXR_TY
    ldy TXR_TA
    lda TXR_TX
    clc
    adc ui_lb_adv,y
    sta TXR_LA
    lda TXR_TX
    clc
    adc ui_lb_off,y
    tax
    lda ui_lb_lo,y
    sta PTR
    lda ui_lb_hi,y
    sta PTR+1
    jsr put_str
    ldx TXR_LA
    ldy TXR_TY
    rts

; The string at PTR into the row buffers from index X: a kana byte as
; text_put_tile puts it, $EC n UI kanji n (both rows, two cells), $FF
; ends.  X = the index after it, Y = TXR_TY.  (Shallow: it runs inside
; the text task's small stack, from a message's item name too.)
put_str:
    ldy #0
@l:
    lda (PTR),y
    cmp #$FF
    beq @r
    iny
    cmp #$EC
    beq @k
    jsr TEXT_PUT_TILE           ; (Y kept)
    jmp @l
@k:
    lda (PTR),y
    iny
    sty TXR_TA
    stx TXR_PX
    tay
    lda ui_gc_lo,y
    sta TXR_K
    lda ui_gc_hi,y
    sta TXR_K+1
    jsr ui_reg
    ldx TXR_PX
    sta $0300,x                 ; left half, both rows (the row's parity
    sta $0318,x                 ; picks the top or the bottom tile)
    ora #1
    sta $0301,x
    sta $0319,x
    inx
    inx
    ldy TXR_TA
    jmp @l
@r:
    ldy TXR_TY
    rts

; A = the line code ($A0 + 2k) of glyph TXR_K in REG entry 16 + k: the
; entry that has it, else the next one (round robin) no row holds.
ui_reg:
    ldx #15
@f:
    lda REG_LO+UI_E0,x
    cmp TXR_K
    bne @n
    lda REG_HI+UI_E0,x
    cmp TXR_K+1
    beq @got
@n:
    dex
    bpl @f
    lda #0                      ; the entries the rows hold: TXR_I (0-7),
    sta TXR_I                   ; TXR_J (8-15)
    sta TXR_J
    ldy #$5F
@s:
    lda $0300,y
    sec
    sbc #$80+UI_E0*2
    cmp #$20
    bcs @s2
    lsr a
    tax
    jsr ui_mark
@s2:
    lda $0180,y
    sec
    sbc #$80+UI_E0*2
    cmp #$20
    bcs @s3
    lsr a
    tax
    jsr ui_mark
@s3:
    dey
    bpl @s
    ldy #16
@p:
    lda TXR_UR
    clc
    adc #1
    and #15
    sta TXR_UR
    tax
    cpx #8
    bcs @hi
    lda bitmask,x
    and TXR_I
    beq @take
    bne @pn
@hi:
    lda bitmask-8,x
    and TXR_J
    beq @take
@pn:
    dey
    bne @p
    ldx TXR_UR                  ; (all 16 held: the next one anyway)
@take:
    lda TXR_K
    sta REG_LO+UI_E0,x
    lda TXR_K+1
    sta REG_HI+UI_E0,x
@got:
    txa
    asl a
    ora #$80+UI_E0*2
    rts

; X = a UI entry 0-15 a row holds: its bit in TXR_I / TXR_J.  Y kept.
ui_mark:
    cpx #8
    bcs @hi
    lda bitmask,x
    ora TXR_I
    sta TXR_I
@r:
    rts
@hi:
    lda bitmask-8,x
    ora TXR_J
    sta TXR_J
    rts

    .include "../../decomp/build/kanji/txr_ui.inc"

; The bank-9 font (1bpp, 128 glyphs), the build's asset (identical to
; bank 9 $BA00): kana glyphs and the font restore without a bank switch.
    .align 256
font_copy:
    .incbin "../../decomp/build/assets/bank09_kana.bin"
