; ======================================================================
; Kanji target text-engine overlay
;
; Assembled for $7002 and installed into battery-backed PRG RAM by the far
; loader (tools/asm/kanji_far.asm).  The signature word at $7000 tells the
; fixed-bank guard stubs whether the overlay is valid.  Bank 31 is a
; byte-identical copy of patched bank 15, so the overlay may run with either
; outer bank selected.
;
; Page records are compact:
;   count, 16-byte used-kana/reserved bitmap, count * (code_lo, code_hi)
; At page start the overlay scans CHR (NMI job) for tiles that still hold the
; kana glyph and allocates four resident, text-unused tiles per kanji.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

.base $7002
.org $7002

; ----------------------------------------------------------------------
; Extended dispatcher for $EC-$F7.  Entered from the text engine with
; A = byte, X = tile-buffer offset.  Pushes TEXT_RETURN and X, then
; dispatches through a 12-entry jump table.
;
; $F8-$FF must keep the original $D2B7 path (newline/end controls and the
; $F9 tile).  $EC-$EE are kanji escapes; $EF-$F7 are the original handlers.
; ----------------------------------------------------------------------
text_dispatch:
    cmp #$EC
    bcc @normal
    cmp #$F8
    bcs @normal
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

dispatch_table:
    .dw KANJI_EC, KANJI_EC, KANJI_EC
    .dw $D334, $D30A, $D2FE, $D2F3, $D2ED, $D2E7, $D2E1, $D2DB, $D2CF

; ----------------------------------------------------------------------
; Kanji glyph handler.  The runtime page at KANJI_PAGE is:
;   count, then count * (code_lo, code_hi, tile0, tile1, tile2, tile3)
; ----------------------------------------------------------------------
KANJI_EC:
    pla
    tax
    stx KANJI_BUFX
    ldy text_col
    lda ($51),y
    inc text_col
    sta KANJI_CODE_LO
    lda KANJI_ESCAPE
    sta KANJI_CODE_HI

    jsr page_find
    bcs @blank
    iny
    iny
    lda KANJI_PAGE,y         ; tile0 (blank marker = $0A)
    cmp #$0A
    beq @blank
    lda KANJI_PAGE,y
    sta KANJI_CHR_TILES
    lda KANJI_PAGE+1,y
    sta KANJI_CHR_TILES+1
    lda KANJI_PAGE+2,y
    sta KANJI_CHR_TILES+2
    lda KANJI_PAGE+3,y
    sta KANJI_CHR_TILES+3
    jsr upload_glyph
@write_tiles:
    ldx KANJI_BUFX
    lda KANJI_CHR_TILES
    sta $0300,x
    lda KANJI_CHR_TILES+1
    sta $0301,x
    lda KANJI_CHR_TILES+2
    sta $0318,x
    lda KANJI_CHR_TILES+3
    sta $0319,x
    inx
    inx
    rts
@blank:
    lda #$0A
    sta $0300,x
    sta $0318,x
    sta $0301,x
    sta $0319,x
    inx
    inx
    rts

; ----------------------------------------------------------------------
; Search the runtime page for KANJI_CODE_LO/HI.
; Carry set when absent; otherwise Y = offset of code_lo.
; ----------------------------------------------------------------------
page_find:
    lda KANJI_PAGE
    beq @notfound
    sta KANJI_TMP0
    ldy #1
@loop:
    lda KANJI_PAGE,y
    cmp KANJI_CODE_LO
    bne @next
    lda KANJI_PAGE+1,y
    cmp KANJI_CODE_HI
    beq @found
@next:
    tya
    clc
    adc #6
    tay
    dec KANJI_TMP0
    bne @loop
@notfound:
    sec
    rts
@found:
    clc
    rts

; ----------------------------------------------------------------------
; Load one compact page record from KANJI_META and allocate four resident,
; text-unused CHR tiles per kanji.  Advances KANJI_META_PTR.
; ----------------------------------------------------------------------
page_alloc:
    lda KANJI_META_PTR
    sta $10
    lda KANJI_META_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    sta KANJI_PAGE
    bne @has_codes
    jmp @no_codes
@has_codes:
    iny
    ldx #0
@used:
    lda ($10),y
    sta KANJI_PAGE_USED,x
    iny
    inx
    cpx #16
    bne @used

    lda KANJI_META_PTR
    clc
    adc #17
    sta KANJI_META_PTR
    sta $10
    lda KANJI_META_PTR+1
    adc #0
    sta KANJI_META_PTR+1
    sta $11

    lda KANJI_PAGE
    sta KANJI_PAGE_I
    ldx #0
    ldy #0
@copy_codes:
    lda ($10),y
    sta KANJI_PAGE+1,x
    iny
    inx
    lda ($10),y
    sta KANJI_PAGE+1,x
    iny
    inx
    inx
    inx
    inx
    inx
    dec KANJI_PAGE_I
    bne @copy_codes

    lda KANJI_PAGE
    asl a
    clc
    adc KANJI_META_PTR
    sta KANJI_META_PTR
    lda KANJI_META_PTR+1
    adc #0
    sta KANJI_META_PTR+1

    lda #0
    sta KANJI_PAGE_I
    sta KANJI_PAGE_SCAN
@entry:
    lda KANJI_PAGE_I
    cmp KANJI_PAGE
    bne @has_entry
    jmp @done
@has_entry:
    sta KANJI_TMP0
    asl a
    clc
    adc KANJI_TMP0
    asl a
    clc
    adc #1
    sta KANJI_PAGE_OFF
    clc
    adc #2
    sta KANJI_PAGE_EPTR
    lda #4
    sta KANJI_PAGE_ALLOC
@alloc:
    lda KANJI_PAGE_SCAN
    cmp #128
    bcs @no_free
    sta KANJI_TMP1
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_TMP1
    and #7
    tax
    lda bitmask,x
    sta KANJI_TMP0
    and KANJI_RESIDENT,y
    beq @next_tile
    lda KANJI_TMP0
    and KANJI_PAGE_USED,y
    bne @next_tile
    lda KANJI_TMP0
    and KANJI_SCREEN,y
    bne @next_tile
    ldx KANJI_PAGE_EPTR
    lda KANJI_TMP1
    sta KANJI_PAGE,x
    inc KANJI_PAGE_EPTR
    lda KANJI_TMP0
    eor #$FF
    and KANJI_PAGE_USED,y
    sta KANJI_PAGE_USED,y
    inc KANJI_PAGE_SCAN
    dec KANJI_PAGE_ALLOC
    beq @alloc_done
    jmp @alloc
@alloc_done:
    jmp @next_entry
@next_tile:
    inc KANJI_PAGE_SCAN
    jmp @alloc
@no_free:
    lda #$0A
    ldx KANJI_PAGE_EPTR
    sta KANJI_PAGE,x
    inc KANJI_PAGE_EPTR
    dec KANJI_PAGE_ALLOC
    bne @no_free
@next_entry:
    inc KANJI_PAGE_I
    jmp @entry
@no_codes:
    lda #0
    sta KANJI_PAGE
@done:
    lda KANJI_PAGES_LEFT
    beq @skip_dec
    dec KANJI_PAGES_LEFT
@skip_dec:
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
    lda #1
    sta KANJI_SRC
    lda #16
    sta KANJI_DST
    jsr expand_tile
    lda #16
    sta KANJI_SRC
    lda #32
    sta KANJI_DST
    jsr expand_tile
    lda #17
    sta KANJI_SRC
    lda #48
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
    lda bitmask,y
    eor #$FF
    and KANJI_RESIDENT,x
    sta KANJI_RESIDENT,x
    inc KANJI_SRC
    dec KANJI_TMP3
    bne @markloop
    lda #1
    sta KANJI_DIRTY_ANY
    rts

; ----------------------------------------------------------------------
; Control store (replaces STA $0300,X).  $FC starts the next text page.
; ----------------------------------------------------------------------
ctrl_store:
    sta $0300,x
    cmp #$FC
    bne @done
    lda KANJI_PAGES_LEFT
    bne @alloc
    lda #0
    sta KANJI_PAGE
    rts
@alloc:
    jsr page_alloc
@done:
    rts

; ----------------------------------------------------------------------
; Restore one kana tile from the SRAM font copy into CHR, waiting for the
; NMI upload slot.  A = tile number (0-127).
; ----------------------------------------------------------------------
restore_tile:
    sta KANJI_BASE
    lda ppu_ctrl_shadow
    bmi @nmi_on
    rts                 ; NMI is off; the screen loader refreshes CHR
@nmi_on:
    lda KANJI_BASE
    sta KANJI_SRC
    lda #0
    sta KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1
    asl KANJI_SRC
    rol KANJI_SRC+1

    lda $12
    pha
    lda $13
    pha
    lda #<KANA_FONT
    clc
    adc KANJI_SRC
    sta $12
    lda #>KANA_FONT
    adc KANJI_SRC+1
    sta $13
    ldy #0
@copy:
    lda ($12),y
    sta KANJI_STAGE,y
    iny
    cpy #8
    bne @copy
    lda #0
@zero:
    sta KANJI_STAGE,y
    iny
    cpy #16
    bne @zero
    pla
    sta $13
    pla
    sta $12

    lda KANJI_BASE
    sta KANJI_CHR_TILES
    lda #1
    sta KANJI_CHR_COUNT
    sta KANJI_CHR_FLAG
@wait:
    lda KANJI_CHR_FLAG
    bne @wait

    lda KANJI_BASE
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_BASE
    and #7
    tax
    lda bitmask,x
    ora KANJI_RESIDENT,y
    sta KANJI_RESIDENT,y
    lda bitmask,x
    eor #$FF
    and KANJI_DIRTY,y
    sta KANJI_DIRTY,y
    rts

; ----------------------------------------------------------------------
; Message-exit restore.  Tiles referenced by the current text buffers stay;
; every other dirty tile is restored so menus and map screens drawn outside
; the text engine see kana again.
; ----------------------------------------------------------------------
restore_exit:
    lda #0
    ldx #0
@clr:
    sta KANJI_VISIBLE,x
    inx
    cpx #16
    bne @clr
    ldx #0
@buf1:
    lda $0180,x
    jsr mark_visible
    inx
    cpx #96
    bne @buf1
    ldx #0
@buf2:
    lda $0300,x
    jsr mark_visible
    inx
    cpx #192
    bne @buf2

    lda #0
    sta KANJI_TMP3
@loop:
    lda KANJI_TMP3
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_TMP3
    and #7
    tax
    lda bitmask,x
    sta KANJI_TMP1
    and KANJI_DIRTY,y
    beq @next
    lda KANJI_TMP1
    and KANJI_VISIBLE,y
    bne @next
    lda KANJI_TMP3
    jsr restore_tile
@next:
    inc KANJI_TMP3
    lda KANJI_TMP3
    cmp #128
    bne @loop
    lda #0
    sta KANJI_DIRTY_ANY
    jmp $C47E           ; set_bank_current

mark_visible:
    cmp #128
    bcs @done
    sta KANJI_TMP0
    lsr a
    lsr a
    lsr a
    sta KANJI_TMP1
    lda KANJI_TMP0
    and #7
    tay
    lda bitmask,y
    ldy KANJI_TMP1
    ora KANJI_VISIBLE,y
    sta KANJI_VISIBLE,y
@done:
    rts

; ----------------------------------------------------------------------
; Restore a kana tile if a kanji or scene graphics overwrote it, then
; continue through the original text_put_tile.
; ----------------------------------------------------------------------
kana_prepare:
    pha                 ; preserve the character code for text_put_tile
    txa
    pha                 ; preserve the caller's buffer offset
    tya
    pha                 ; preserve the caller's loop index
    tsx
    lda $0103,x         ; saved character
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
    and KANJI_RESIDENT,y
    bne @done
    lda KANJI_TMP1
    jsr restore_tile
@done:
    pla
    tay
    pla
    tax
    pla
    jmp $D340           ; text_put_tile

; ----------------------------------------------------------------------
; Scan CHR for tiles that still equal the kana font.  The NMI job reads a
; bounded number of tiles per frame; the main thread waits with the normal
; task yield loop.
; ----------------------------------------------------------------------
scan_start:
    lda nmi_busy
    bne @abort
    lda ppu_ctrl_shadow
    bpl @abort
    lda #0
    ldx #0
@clr:
    sta KANJI_RESIDENT,x
    sta KANJI_SCREEN,x
    inx
    cpx #16
    bne @clr
    sta KANJI_SCAN_POS
    sta KANJI_VRAM_POS
    sta KANJI_VRAM_POS+1
    sta KANJI_SCAN_DONE
    sta KANJI_VRAM_DONE
    lda #1
    sta KANJI_SCAN_ACTIVE
    sta KANJI_VRAM_ACTIVE
    rts
@abort:
    ldx #0
@all:
    lda #$FF
    sta KANJI_RESIDENT,x
    lda #0
    sta KANJI_SCREEN,x
    inx
    cpx #16
    bne @all
    lda #0
    sta KANJI_SCAN_ACTIVE
    sta KANJI_VRAM_ACTIVE
    sta KANJI_SCAN_DONE
    sta KANJI_VRAM_DONE
    rts

scan_wait:
    lda frame_counter
    sta KANJI_TMP0
    lda #40
    sta KANJI_SCAN_TILE
@loop:
    lda KANJI_SCAN_ACTIVE
    ora KANJI_VRAM_ACTIVE
    beq @done
    lda frame_counter
    cmp KANJI_TMP0
    beq @loop
    sta KANJI_TMP0
    dec KANJI_SCAN_TILE
    bne @loop
    lda #0
    sta KANJI_SCAN_ACTIVE
    sta KANJI_VRAM_ACTIVE
    sta KANJI_SCAN_DONE
    sta KANJI_VRAM_DONE
@done:
    rts

; ----------------------------------------------------------------------
; NMI: scan up to 8 CHR tiles per frame.
; ----------------------------------------------------------------------
scan_job:
    lda KANJI_SCAN_ACTIVE
    ora KANJI_VRAM_ACTIVE
    beq @quick
    lda $12
    pha
    lda $13
    pha
    lda KANJI_SCAN_ACTIVE
    beq @vram
    lda #8
    sta KANJI_NMI4
@loop:
    lda KANJI_SCAN_POS
    cmp #128
    bcs @finish
    jsr scan_one
    inc KANJI_SCAN_POS
    dec KANJI_NMI4
    bne @loop
    jmp @vram
@finish:
    lda #0
    sta KANJI_SCAN_ACTIVE
    sta KANJI_SCAN_DONE
@vram:
    lda KANJI_VRAM_ACTIVE
    beq @exit
    jsr vram_scan
@exit:
    pla
    sta $13
    pla
    sta $12
@quick:
    rts

; ----------------------------------------------------------------------
; NMI: copy up to 64 nametable bytes per frame into KANJI_SCREEN.
; ----------------------------------------------------------------------
vram_scan:
    lda KANJI_VRAM_POS+1
    ora #$20
    sta PPUADDR
    lda KANJI_VRAM_POS
    sta PPUADDR
    lda PPUDATA         ; discard the buffered read
    lda #64
    sta KANJI_NMI4
@byte:
    lda PPUDATA
    jsr mark_screen_tile
    inc KANJI_VRAM_POS
    bne @no_hi
    inc KANJI_VRAM_POS+1
@no_hi:
    lda KANJI_VRAM_POS+1
    cmp #$04
    bcs @finish
    dec KANJI_NMI4
    bne @byte
    rts
@finish:
    lda #0
    sta KANJI_VRAM_ACTIVE
    sta KANJI_VRAM_DONE
    rts

mark_screen_tile:
    cmp #128
    bcs @done
    sta KANJI_NMI0
    lsr a
    lsr a
    lsr a
    sta KANJI_NMI1
    lda KANJI_NMI0
    and #7
    tay
    lda bitmask,y
    ldy KANJI_NMI1
    ora KANJI_SCREEN,y
    sta KANJI_SCREEN,y
@done:
    rts

scan_one:
    lda KANJI_SCAN_POS
    sta KANJI_NMI0
    lda #0
    sta KANJI_NMI1
    asl KANJI_NMI0
    rol KANJI_NMI1
    asl KANJI_NMI0
    rol KANJI_NMI1
    asl KANJI_NMI0
    rol KANJI_NMI1
    asl KANJI_NMI0
    rol KANJI_NMI1
    lda KANJI_NMI1
    ora #$10
    sta PPUADDR
    lda KANJI_NMI0
    sta PPUADDR
    lda PPUDATA         ; discard the buffered read
    ldx #0
@read:
    lda PPUDATA
    sta KANJI_SCAN_BUF,x
    inx
    cpx #16
    bne @read

    lda KANJI_SCAN_POS
    sta KANJI_NMI0
    lda #0
    sta KANJI_NMI1
    asl KANJI_NMI0
    rol KANJI_NMI1
    asl KANJI_NMI0
    rol KANJI_NMI1
    asl KANJI_NMI0
    rol KANJI_NMI1
    lda KANJI_NMI0
    clc
    adc #<KANA_FONT
    sta $12
    lda KANJI_NMI1
    adc #>KANA_FONT
    sta $13
    ldy #0
@cmp:
    lda KANJI_SCAN_BUF,y
    cmp ($12),y
    bne @exit
    iny
    cpy #8
    bne @cmp
@zero:
    lda KANJI_SCAN_BUF,y
    bne @exit
    iny
    cpy #16
    bne @zero
    lda KANJI_SCAN_POS
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_SCAN_POS
    and #7
    tax
    lda bitmask,x
    ora KANJI_RESIDENT,y
    sta KANJI_RESIDENT,y
@exit:
    rts

; ----------------------------------------------------------------------
; NMI: when rendering is off, restore up to four dirty tiles per frame.
; ----------------------------------------------------------------------
restore_job:
    lda KANJI_DIRTY_ANY
    beq @done
    lda ppu_mask_shadow
    and #$18
    bne @done
    lda #0
    sta KANJI_NMI2
@loop:
    lda KANJI_NMI2
    cmp #4
    beq @done
    lda KANJI_RESTORE_POS
    cmp #128
    bcs @reset
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_RESTORE_POS
    and #7
    tax
    lda bitmask,x
    and KANJI_DIRTY,y
    beq @next
    lda KANJI_RESTORE_POS
    jsr nmi_restore_tile
    inc KANJI_NMI2
@next:
    inc KANJI_RESTORE_POS
    jmp @loop
@reset:
    lda #0
    sta KANJI_RESTORE_POS
    sta KANJI_DIRTY_ANY
@done:
    rts

nmi_restore_tile:
    sta KANJI_NMI0
    lda $12
    pha
    lda $13
    pha
    lda KANJI_NMI0
    sta KANJI_NMI1
    lda #0
    sta KANJI_NMI4
    asl KANJI_NMI1
    rol KANJI_NMI4
    asl KANJI_NMI1
    rol KANJI_NMI4
    asl KANJI_NMI1
    rol KANJI_NMI4
    lda KANJI_NMI1
    clc
    adc #<KANA_FONT
    sta $12
    lda KANJI_NMI4
    adc #>KANA_FONT
    sta $13
    ldy #0
@copy:
    lda ($12),y
    sta KANJI_SCAN_BUF,y
    iny
    cpy #8
    bne @copy
    lda #0
@zero:
    sta KANJI_SCAN_BUF,y
    iny
    cpy #16
    bne @zero

    lda KANJI_NMI0
    sta KANJI_NMI1
    lda #0
    sta KANJI_NMI4
    asl KANJI_NMI1
    rol KANJI_NMI4
    asl KANJI_NMI1
    rol KANJI_NMI4
    asl KANJI_NMI1
    rol KANJI_NMI4
    asl KANJI_NMI1
    rol KANJI_NMI4
    lda KANJI_NMI4
    ora #$10
    sta PPUADDR
    lda KANJI_NMI1
    sta PPUADDR
    ldx #0
@write:
    lda KANJI_SCAN_BUF,x
    sta PPUDATA
    inx
    cpx #16
    bne @write

    lda KANJI_NMI0
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_NMI0
    and #7
    tax
    lda bitmask,x
    ora KANJI_RESIDENT,y
    sta KANJI_RESIDENT,y
    lda bitmask,x
    eor #$FF
    and KANJI_DIRTY,y
    sta KANJI_DIRTY,y
    pla
    sta $13
    pla
    sta $12
    rts

; ----------------------------------------------------------------------
; Re-upload page glyphs whose CHR tiles were restored since the last draw.
; Called after text_redraw_lines.
; ----------------------------------------------------------------------
redraw_hook:
    jsr TEXT_REDRAW_LINES
    lda KANJI_PAGE
    beq @done
    sta KANJI_PAGE_I
    lda #1
    sta KANJI_PAGE_OFF
@entry:
    lda #0
    sta KANJI_TMP2
    lda KANJI_PAGE_OFF
    clc
    adc #2
    sta KANJI_TMP3
    ldx #0
@check:
    ldy KANJI_TMP3
    lda KANJI_PAGE,y      ; tile0..tile3
    jsr resident_test
    beq @check_next
    inc KANJI_TMP2
@check_next:
    inc KANJI_TMP3
    inx
    cpx #4
    bne @check
    lda KANJI_TMP2
    beq @skip
    ldy KANJI_PAGE_OFF
    lda KANJI_PAGE,y      ; code_lo
    sta KANJI_CODE_LO
    lda KANJI_PAGE+1,y    ; code_hi
    sta KANJI_CODE_HI
    lda KANJI_PAGE+2,y
    sta KANJI_CHR_TILES
    lda KANJI_PAGE+3,y
    sta KANJI_CHR_TILES+1
    lda KANJI_PAGE+4,y
    sta KANJI_CHR_TILES+2
    lda KANJI_PAGE+5,y
    sta KANJI_CHR_TILES+3
    jsr upload_glyph
@skip:
    lda KANJI_PAGE_OFF
    clc
    adc #6
    sta KANJI_PAGE_OFF
    dec KANJI_PAGE_I
    bne @entry
@done:
    rts

; A = tile; Z=1 when the tile currently holds kana.
resident_test:
    sta KANJI_TMP1
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_TMP1
    and #7
    tax
    lda bitmask,x
    and KANJI_RESIDENT,y
    rts

; ----------------------------------------------------------------------
; A = 10-31.  Switch PRG bank/outer bit with NMI inhibited.  Used by the
; RAM far loader before the first text bank is mapped.
; ----------------------------------------------------------------------
bank_switch_outer:
    sta current_prg_bank
    pha
    lda ppu_ctrl_shadow
    and #$7F
    sta PPUCTRL
    pla
    jsr $C611           ; SUROM switcher in the fixed-bank gap
    lda ppu_ctrl_shadow
    sta PPUCTRL
    rts

; ----------------------------------------------------------------------
; Load the per-message page records.  The trampoline at ($51) in bank
; 10/11 supplies the text bank, text address and metadata pointer.
; Returns with KANJI_TMP2/TMP3 = text data address and the text bank
; mapped at $8000.
; ----------------------------------------------------------------------
meta_load:
    lda text_window_x
    jsr SET_BANK_B
    ldy #3
    lda ($51),y
    sta KANJI_TEXT_BANK
    iny
    lda ($51),y
    sta KANJI_TMP2
    iny
    lda ($51),y
    sta KANJI_TMP3
    iny
    lda ($51),y
    sta $10
    iny
    lda ($51),y
    sta $11

    ; Metadata lives in bank 22 (low text bank) or 23 (high text bank).
    lda text_window_x
    sec
    sbc #10
    clc
    adc #22
    jsr bank_switch_outer

    ldy #0
    lda ($10),y
    sta KANJI_PAGES_LEFT
    lda $10
    clc
    adc #3
    sta $10
    lda $11
    adc #0
    sta $11

    lda #<KANJI_META
    sta $12
    lda #>KANJI_META
    sta $13
    ldx #2              ; 512 bytes
@page:
    ldy #0
@byte:
    lda ($10),y
    sta ($12),y
    iny
    bne @byte
    inc $11
    inc $13
    dex
    bne @page

    lda #<KANJI_META
    sta KANJI_META_PTR
    lda #>KANJI_META
    sta KANJI_META_PTR+1
    lda KANJI_TEXT_BANK
    sta text_window_x
    jsr SET_BANK_B
    jsr page_alloc
    rts

; ----------------------------------------------------------------------
; NMI hook: upload pending kanji/kana CHR data, run the CHR scan, restore
; dirty tiles when rendering is off.  nmi_entry_guard calls this at the top
; of every NMI with rendering disabled; the later palette hook only runs the
; jobs if the guard has not already done so.
; ----------------------------------------------------------------------
nmi_entry_ram:
    lda nmi_busy
    bne @busy
    lda PPUSTATUS       ; clear the vblank flag before the CHR jobs
    lda #1
    sta KANJI_NMI_DONE
    lda #0
    sta PPUMASK
    jsr nmi_jobs
    jmp $EE83
@busy:
    jmp $EEE0

nmi_jobs:
    jsr chr_upload
    jsr scan_job
    jsr restore_job
    rts

nmi_hook:
    lda KANJI_NMI_DONE
    bne @skip
    jsr nmi_jobs
@skip:
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
