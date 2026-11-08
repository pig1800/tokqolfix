; ======================================================================
; Hack bank code (revision 10), identical in PRG banks 23 and 24.
;
; Assembled for $8000.  The first $800 bytes are code; glyph data starts
; at KANJI_GLYPH_BASE ($8800), 359 glyphs per bank.
;
; The fixed bank enters at hack_entry through call_hack.  All NMI work
; runs here with the hack bank mapped; the fixed bank is always available
; at $C000-$FFFF (bank 15/31 mirror).
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

.base $8000
.org $8000

hack_entry:
    lda KANJI_FN
    asl a
    tay
    lda fn_table,y
    sta KANJI_TMP0
    lda fn_table+1,y
    sta KANJI_TMP1
    jmp (KANJI_TMP0)

fn_table:
    .dw fn_entry
    .dw fn_band
    .dw fn_scene
    .dw fn_sync
    .dw fn_reset
    .dw fn_glyph
    .dw fn_page2
    .dw fn_page1

; ----------------------------------------------------------------------
; NMI entry: OAM slot 0, DMA, CHR page 1, bookkeeping, glyph or resync,
; sprite-0 pattern.
; ----------------------------------------------------------------------
fn_entry:
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL

    ; OAM slot 0: the sprite-0 line, or offscreen when the band is off.
    lda KANJI_BAND_ON
    beq @oam_hidden
    lda ppu_mask_shadow
    and #$18
    beq @oam_hidden
    lda #143
    sta $0200
    lda #$FF
    sta $0201
    lda #$20
    sta $0202
    lda #16
    sta $0203
    jmp @dma
@oam_hidden:
    lda #$F8
    sta $0200
    lda #0
    sta $0201
    sta $0202
    sta $0203
@dma:
    lda #2
    sta OAMDMA

    ; The visible top of this frame must come from CHR page 1.
    lda #1
    jsr write_chr1_nmi

    ; A block write after the message closed means the screen is being
    ; redrawn: drop the band and release the kanji slots.
    lda KANJI_PAGE1_DIRTY
    beq @no_block
    lda #0
    sta KANJI_PAGE1_DIRTY
    lda KANJI_MSG_OPEN
    bne @no_block
    lda KANJI_BAND_ON
    beq @no_block
    jsr clear_a
    lda #0
    sta KANJI_BAND_ON
@no_block:
    ; Rendering off releases the band.
    lda ppu_mask_shadow
    and #$18
    bne @done
    lda KANJI_BAND_ON
    beq @done
    jsr clear_a
    lda #0
    sta KANJI_BAND_ON
@done:
    rts

; ----------------------------------------------------------------------
; Band switch: wait for sprite 0 at the window's top border, then select
; CHR page 2.  Bounded by a cycle count for the missing-hit case.
; ----------------------------------------------------------------------
fn_band:
    lda nmi_mode
    bne @done
    lda KANJI_BAND_ON
    beq @done
    lda ppu_mask_shadow
    and #$18
    beq @done
    ldx #0
    ldy #7
@poll:
    bit PPUSTATUS
    bvs @hit
    dex
    bne @poll
    dey
    bne @poll
    lda #2
    sta KANJI_BAND_EXIT
    jmp @switch
@hit:
    lda #1
    sta KANJI_BAND_EXIT
@switch:
    lda #2
    jsr write_chr1_nmi
@done:
    lda #0
    sta KANJI_IN_NMI
    rts

; ----------------------------------------------------------------------
; Block-writer hook: select CHR page 1 and mark the shadow dirty.
; ----------------------------------------------------------------------
fn_scene:
@retry:
    lda #1
    sta bank_switch_lock
    lda #1
    ldx #5
@w:
    sta MMC1_CHR_BANK1
    lsr a
    dex
    bne @w
    lda bank_switch_lock
    beq @retry
    lda #0
    sta bank_switch_lock
    lda #1
    sta KANJI_PAGE1_DIRTY
    rts

; ----------------------------------------------------------------------
; Full shadow sync, main thread with NMI disabled.  Copies all 128 page-1
; tiles to page 2 and leaves the band enabled.
; ----------------------------------------------------------------------
fn_sync:
    lda ppu_ctrl_shadow
    pha
    jsr PPU_NMI_OFF
    lda #0
    sta KANJI_BAND_ON
    sta KANJI_SHADOW_CUR
    lda #2
    jsr write_chr1_nmi
@loop:
    jsr copy_tile_shadow
    inc KANJI_SHADOW_CUR
    lda KANJI_SHADOW_CUR
    cmp #128
    bne @loop
    jsr write_sprite_tile
    lda #1
    jsr write_chr1_nmi
    lda #0
    sta KANJI_PAGE1_DIRTY
    lda #1
    sta KANJI_BAND_ON
    pla
    sta ppu_ctrl_shadow
    sta PPUCTRL
    rts

; ----------------------------------------------------------------------
; Upload one glyph to CHR page 2.  Main thread, NMI off; KANJI_CODE_LO/HI
; hold the glyph index (0-717) and KANJI_TILES the four page-2 tiles.
; ----------------------------------------------------------------------
fn_glyph:
    lda KANJI_CODE_HI
    cmp #1
    bcc @bank23
    bne @bank24
    lda KANJI_CODE_LO
    cmp #$67
    bcs @bank24
@bank23:
    lda #23
    jsr SET_BANK_LOCK
    lda KANJI_CODE_LO
    sta $12
    lda KANJI_CODE_HI
    sta $13
    jmp @addr
@bank24:
    lda #24
    jsr SET_BANK_LOCK
    lda KANJI_CODE_LO
    sec
    sbc #$67
    sta $12
    lda KANJI_CODE_HI
    sbc #1
    sta $13
@addr:
    asl $12
    rol $13
    asl $12
    rol $13
    asl $12
    rol $13
    asl $12
    rol $13
    asl $12
    rol $13
    lda $13
    clc
    adc #$88
    sta $13

    lda #0
    sta KANJI_TMP2
@tile:
    ldy KANJI_TMP2
    lda KANJI_TILES,y
    asl a
    asl a
    asl a
    asl a
    sta KANJI_TMP3
    lda KANJI_TILES,y
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$20
    sta PPUADDR
    lda KANJI_TMP3
    sta PPUADDR

    ; buffer offset = (tile & 2) * 8 + (tile & 1)
    lda KANJI_TMP2
    and #2
    asl a
    asl a
    asl a
    sta KANJI_TMP3
    lda KANJI_TMP2
    and #1
    ora KANJI_TMP3
    sta KANJI_TMP3

    ldy KANJI_TMP3
    ldx #8
@plane:
    lda ($12),y
    sta PPUDATA
    tya
    clc
    adc #2
    tay
    dex
    bne @plane
    lda #0
    ldx #8
@zero:
    sta PPUDATA
    dex
    bne @zero

    inc KANJI_TMP2
    lda KANJI_TMP2
    cmp #4
    bne @tile
    rts

fn_page2:
    lda #2
    jmp write_chr1_nmi

fn_page1:
    lda #1
    jmp write_chr1_nmi

; ----------------------------------------------------------------------
; Reset: clear every hack byte.  Returns A=0, X=$F0 for the game's RAM
; clear loop.
; ----------------------------------------------------------------------
fn_reset:
    lda #0
    ldx #0
@clear:
    sta KANJI_TEXT_BANK,x
    inx
    cpx #$4F
    bne @clear
    ldx #0
@scratch:
    sta $0100,x
    inx
    cpx #16
    bne @scratch
    lda #0
    ldx #$F0
    rts

; ----------------------------------------------------------------------
; Copy CHR page-1 tile KANJI_SHADOW_CUR to page 2.
; Uses KANJI_GLYPH_BUF as a 16-byte scratch buffer.
; ----------------------------------------------------------------------
copy_tile_shadow:
    lda KANJI_SHADOW_CUR
    asl a
    asl a
    asl a
    asl a
    sta KANJI_TMP0
    lda KANJI_SHADOW_CUR
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta KANJI_TMP1
    sta PPUADDR
    lda KANJI_TMP0
    sta PPUADDR
    lda PPUDATA
    ldx #0
@read:
    lda PPUDATA
    sta KANJI_GLYPH_BUF,x
    inx
    cpx #16
    bne @read
    lda KANJI_TMP1
    clc
    adc #$10
    sta PPUADDR
    lda KANJI_TMP0
    sta PPUADDR
    ldx #0
@write:
    lda KANJI_GLYPH_BUF,x
    sta PPUDATA
    inx
    cpx #16
    bne @write
    rts

; ----------------------------------------------------------------------
; Sprite-0 pattern in CHR page 0, tile $FF: opaque rows 1-2 only.
; ----------------------------------------------------------------------
write_sprite_tile:
    lda #$0F
    sta PPUADDR
    lda #$F0
    sta PPUADDR
    lda #0
    sta PPUDATA
    lda #$FF
    sta PPUDATA
    sta PPUDATA
    lda #0
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    ldx #8
@zero:
    sta PPUDATA
    dex
    bne @zero
    rts

; ----------------------------------------------------------------------
; CHR register 1, five serial writes.  Called from the NMI only.
; ----------------------------------------------------------------------
write_chr1_nmi:
    ldx #5
@w:
    sta MMC1_CHR_BANK1
    lsr a
    dex
    bne @w
    rts

clear_a:
    lda #0
    ldx #15
@l:
    sta KANJI_A_BITS,x
    dex
    bpl @l
    rts

bitmask:
    .db $80, $40, $20, $10, $08, $04, $02, $01

; The glyph area starts here; kanji_build.py pads the code to 2 KiB.
.org $8800
