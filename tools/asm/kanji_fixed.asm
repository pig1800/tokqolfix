; ======================================================================
; Kanji target fixed-bank overlay (assembled for $E000, lives in bank 31)
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

.base $E000

; ----------------------------------------------------------------------
; Extended dispatcher for $EC-$F7.  Entered from the text engine with
; A = byte, X = tile-buffer offset.  Pushes TEXT_RETURN and X, then
; dispatches through a 12-entry jump table.
; ----------------------------------------------------------------------
text_dispatch:
    cmp #$EC
    bcc @normal
    sec
    sbc #$EC
    tay
    sty KANJI_ESCAPE
    inc text_col
    lda #$D2
    pha
    lda #$85
    pha
    txa
    pha
    tya
    asl a
    tay
    lda dispatch_table,y
    sta $EE
    lda dispatch_table+1,y
    sta $EF
    jmp ($00EE)
@normal:
    jmp $D2B7

.org $E030
dispatch_table:
    .dw KANJI_EC, KANJI_EC, KANJI_EC
    .dw $D334, $D30A, $D2FE, $D2F3, $D2ED, $D2E7, $D2E1, $D2DB, $D2CF

; ----------------------------------------------------------------------
; Kanji glyph handler.  Page records are:
;   count, then count * (code_lo, code_hi, tile0, tile1, tile2, tile3)
; bit 7 of tile0 is the runtime "already uploaded" flag.
; ----------------------------------------------------------------------
KANJI_EC:
    pla
    tax
    stx KANJI_TMP0
    ldy text_col
    lda ($51),y
    inc text_col
    sta KANJI_CODE_LO
    lda KANJI_ESCAPE
    sta KANJI_CODE_HI

    lda KANJI_META_PTR
    sta $10
    lda KANJI_META_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    sta KANJI_COUNT
    ldy #1
@search:
    lda KANJI_COUNT
    beq @blank
    lda ($10),y
    cmp KANJI_CODE_LO
    bne @next
    iny
    lda ($10),y
    cmp KANJI_CODE_HI
    beq @found
    dey
@next:
    tya
    clc
    adc #6
    tay
    dec KANJI_COUNT
    bne @search
@blank:
    lda #$0A
    sta $0300,x
    sta $0318,x
    sta $0301,x
    sta $0319,x
    inx
    inx
    rts

@found:
    iny
    iny
    lda ($10),y         ; tile0 + uploaded flag
    bmi @already
    ora #$80
    sta ($10),y
    lda #1
    sta KANJI_TMP2
    bne @load_tiles
@already:
    lda #0
    sta KANJI_TMP2
@load_tiles:
    lda ($10),y
    and #$7F
    sta KANJI_CHR_TILES
    iny
    lda ($10),y
    sta KANJI_CHR_TILES+1
    iny
    lda ($10),y
    sta KANJI_CHR_TILES+2
    iny
    lda ($10),y
    sta KANJI_CHR_TILES+3
    lda KANJI_TMP2
    beq @write_tiles
    jsr upload_glyph
@write_tiles:
    ldx KANJI_TMP0
    lda KANJI_CHR_TILES
    sta $0300,x
    lda KANJI_CHR_TILES+1
    sta $0318,x
    lda KANJI_CHR_TILES+2
    sta $0301,x
    lda KANJI_CHR_TILES+3
    sta $0319,x
    inx
    inx
    rts

; ----------------------------------------------------------------------
; Upload one glyph to the four tile numbers in KANJI_CHR_TILES.
; ----------------------------------------------------------------------
upload_glyph:
    lda KANJI_CODE_HI
    and #1
    sta KANJI_TMP1
    lda KANJI_CODE_HI
    lsr a
    clc
    adc #16
    sta KANJI_TMP2
    lda KANJI_CODE_LO
    sta KANJI_SRC
    lda KANJI_TMP1
    sta KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    lda KANJI_SRC+1
    clc
    adc #$80
    sta $11
    lda KANJI_SRC
    sta $10
    lda KANJI_TMP2
    jsr SET_BANK_B
    ldy #0
    ldx #32
@copy:
    lda ($10),y
    sta KANJI_GLYPH,y
    iny
    dex
    bne @copy
    lda KANJI_TEXT_BANK
    jsr SET_BANK_B

    lda #0
    sta KANJI_SRC
    lda #0
    sta KANJI_DST
    jsr expand_tile
    lda #16
    sta KANJI_SRC
    lda #8
    sta KANJI_DST
    jsr expand_tile
    lda #1
    sta KANJI_SRC
    lda #16
    sta KANJI_DST
    jsr expand_tile
    lda #17
    sta KANJI_SRC
    lda #24
    sta KANJI_DST
    jsr expand_tile

    lda #4
    sta KANJI_CHR_COUNT
    lda #1
    sta KANJI_CHR_FLAG
@wait:
    lda KANJI_CHR_FLAG
    bne @wait

    lda #4
    sta KANJI_TMP3
    lda #0
    sta KANJI_SRC
@markloop:
    ldx KANJI_SRC
    ldy KANJI_CHR_TILES,x
    tya
    lsr a
    lsr a
    lsr a
    sta KANJI_TMP2
    tya
    and #7
    tay
    lda bitmask,y
    ldx KANJI_TMP2
    ora KANJI_DIRTY,x
    sta KANJI_DIRTY,x
    inc KANJI_SRC
    dec KANJI_TMP3
    bne @markloop
    rts

; ----------------------------------------------------------------------
; Control store (replaces STA $0300,X).  $FC advances the page record.
; ----------------------------------------------------------------------
ctrl_store:
    sta $0300,x
    cmp #$FC
    bne @done
    lda KANJI_META_PTR
    sta $10
    lda KANJI_META_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    asl a
    sta KANJI_TMP0
    asl a
    clc
    adc KANJI_TMP0      ; count * 6
    clc
    adc #1
    sta KANJI_TMP0
    lda $10
    clc
    adc KANJI_TMP0
    sta KANJI_META_PTR
    lda $11
    adc #0
    sta KANJI_META_PTR+1
@done:
    rts

; ----------------------------------------------------------------------
; Restore a kana tile from the SRAM font copy if a kanji overwrote it.
; ----------------------------------------------------------------------
kana_prepare:
    sta KANJI_TMP0
    cmp #$80
    bcc @plain
    and #$7F
    cmp #$62
    bcc @have
    sec
    sbc #$0A
@have:
    tax
    jmp @check
@plain:
    tax
@check:
    stx KANJI_TMP1
    txa
    lsr a
    lsr a
    lsr a
    tay
    txa
    and #7
    tax
    lda bitmask,x
    and KANJI_DIRTY,y
    beq @done
    lda bitmask,x
    eor #$FF
    and KANJI_DIRTY,y
    sta KANJI_DIRTY,y

    lda KANJI_TMP1
    sta KANJI_SRC
    lda #0
    sta KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    ldx KANJI_SRC
    ldy #0
@copy:
    lda KANA_FONT,x
    sta KANJI_STAGE,y
    inx
    iny
    cpy #8
    bne @copy
    lda #0
@zero:
    sta KANJI_STAGE,y
    iny
    cpy #16
    bne @zero

    lda KANJI_TMP1
    sta KANJI_CHR_TILES
    lda #1
    sta KANJI_CHR_COUNT
    sta KANJI_CHR_FLAG
@wait:
    lda KANJI_CHR_FLAG
    bne @wait
@done:
    lda KANJI_TMP0
    jmp TEXT_PUT_TILE

; ----------------------------------------------------------------------
; NMI hook: upload pending kanji/kana CHR data, then the normal palette.
; ----------------------------------------------------------------------
nmi_hook:
    jsr chr_upload
    jmp FLUSH_PALETTE

chr_upload:
    lda KANJI_CHR_FLAG
    beq @done
    lda #0
    sta KANJI_SRC
    sta KANJI_TMP2
@tileloop:
    ldx KANJI_TMP2
    cpx KANJI_CHR_COUNT
    beq @finish
    lda KANJI_CHR_TILES,x
    sta KANJI_TMP0
    lda #0
    sta KANJI_TMP1
    asl KANJI_TMP0
    rol KANJI_TMP1
    asl KANJI_TMP0
    rol KANJI_TMP1
    asl KANJI_TMP0
    rol KANJI_TMP1
    asl KANJI_TMP0
    rol KANJI_TMP1
    lda KANJI_TMP1
    clc
    adc #$10
    sta PPUADDR
    lda KANJI_TMP0
    sta PPUADDR
    ldx #16
@bytes:
    ldy KANJI_SRC
    lda KANJI_STAGE,y
    sta PPUDATA
    inc KANJI_SRC
    dex
    bne @bytes
    inc KANJI_TMP2
    bne @tileloop
@finish:
    lda #0
    sta KANJI_CHR_FLAG
@done:
    rts

; ----------------------------------------------------------------------
; Expand one 8-row 1bpp slice into a 2bpp tile (plane0 + zero plane1).
; ----------------------------------------------------------------------
expand_tile:
    lda #8
    sta KANJI_COUNT
@loop8:
    ldx KANJI_SRC
    lda KANJI_GLYPH,x
    ldx KANJI_DST
    sta KANJI_STAGE,x
    inc KANJI_DST
    lda KANJI_SRC
    clc
    adc #2
    sta KANJI_SRC
    dec KANJI_COUNT
    bne @loop8
    lda #8
    sta KANJI_COUNT
    lda #0
@loopz:
    ldx KANJI_DST
    sta KANJI_STAGE,x
    inc KANJI_DST
    dec KANJI_COUNT
    bne @loopz
    rts

bitmask:
    .db $80,$40,$20,$10,$08,$04,$02,$01
; ----------------------------------------------------------------------
; SUROM bank switch used only by the bank-31 fixed-bank copy.  Preserves
; X/Y and writes the outer bit through CHR bank 0 before the low four PRG
; bank bits.  The bank-15 copy keeps the original 16-bank routine.
; ----------------------------------------------------------------------
surom_write_prg_bank:
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
; NMI entry used in the bank-31 fixed-bank copy.  Upload pending CHR data
; even when nmi_busy suppresses the normal sound/VRAM work.
; ----------------------------------------------------------------------
nmi_entry:
    jsr chr_upload
    lda nmi_busy
    bne @skip
    jmp $EE83
@skip:
    jmp $EEE0
