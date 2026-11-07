; ======================================================================
; Kanji-target text-engine overlay (ROM-resident, one copy per text bank)
;
; Assembled for $B800 and included identically in banks 18-22.  The fixed
; bank only contains the SUROM switcher, the F8 trampoline and the cell
; check; all state lives in internal RAM $0131-$017F / $01E0-$01EB, and the
; glyph copy runs from a tiny RAM stub so it can switch to a font bank
; without unmapping its own code.
;
; Page records in the text bank:
;   count byte, count * (code_lo, code_hi, tile0, tile1, tile2, tile3)
; The first byte at the metadata pointer is the number of pages.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

.base $B800
.org $B800

; ----------------------------------------------------------------------
; Message entry.  The fixed-bank trampoline has put the text bank in
; KANJI_TEXT_BANK, the text address in KANJI_TEXT_ADDR and the metadata
; address in KANJI_PAGE_PTR.  It mapped the text bank before jumping here.
; ----------------------------------------------------------------------
overlay_entry:
    stx KANJI_BUFX
    lda KANJI_TEXT_ADDR
    sta text_ptr_lo
    lda KANJI_TEXT_ADDR+1
    sta text_ptr_hi
    lda #0
    sta text_col
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1
    ldx #15
@clr:
    sta KANJI_DIRTY,x
    dex
    bpl @clr

    ; Read the page count and point at the first page record.
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    sta KANJI_PAGES_LEFT
    inc $10
    bne @nohi
    inc $11
@nohi:
    lda $10
    sta KANJI_PAGE_PTR
    lda $11
    sta KANJI_PAGE_PTR+1

    ; Install the RAM font-copy stub.
    ldx #0
@stub:
    lda stub_src,x
    sta KANJI_STUB,x
    inx
    cpx #(stub_end-stub_src)
    bne @stub

    ldx KANJI_BUFX
    pla
    pla
    jmp TEXT_LINE_LOOP

; ----------------------------------------------------------------------
; Extended dispatcher for $EC-$F7 (replaces the original $D28E path).
; ----------------------------------------------------------------------
text_dispatch:
    cmp #$EC
    bcc @normal
    cmp #$F8
    bcs @normal
    sec
    sbc #$EC
    tay
    sty KANJI_CODE_HI
    inc text_col
    lda #>TEXT_RETURN
    pha
    lda #<TEXT_RETURN
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
    jmp TEXT_NORMAL_CHAR

dispatch_table:
    .dw KANJI_EC, KANJI_EC, KANJI_EC
    .dw $D334, $D30A, $D2FE, $D2F3, $D2ED, $D2E7, $D2E1, $D2DB, $D2CF

; ----------------------------------------------------------------------
; One kanji escape: find the code in the current page record, upload the
; glyph once, and write the four tile numbers into the text buffers.
; ----------------------------------------------------------------------
KANJI_EC:
    pla
    tax
    stx KANJI_BUFX
    ldy text_col
    lda ($51),y
    inc text_col
    sta KANJI_CODE_LO
    jsr page_find
    bcs @blank

    ; Y points at the entry's code_lo; copy tile0..tile3.
    iny
    iny
    ldx #0
@copy_tiles:
    lda ($10),y
    sta KANJI_TILES,x
    iny
    inx
    cpx #4
    bne @copy_tiles

    ; Upload once per page entry.
    lda KANJI_ENTRY
    and #7
    tax
    lda bitmask,x
    sta KANJI_TMP0
    lda KANJI_ENTRY
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_TMP0
    and KANJI_UPLOADED,y
    bne @write_tiles
    lda KANJI_TMP0
    ora KANJI_UPLOADED,y
    sta KANJI_UPLOADED,y
    jsr upload_glyph

@write_tiles:
    ldx KANJI_BUFX
    lda KANJI_TILES
    sta $0300,x
    lda KANJI_TILES+1
    sta $0301,x
    lda KANJI_TILES+2
    sta $0318,x
    lda KANJI_TILES+3
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
; Search the current page record for KANJI_CODE_LO/HI.
; Carry set when absent; otherwise Y = entry offset and KANJI_ENTRY = index.
; Leaves $10/$11 pointing at the page record.
; ----------------------------------------------------------------------
page_find:
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    sta KANJI_TMP0
    beq @notfound
    lda #0
    sta KANJI_ENTRY
    ldy #1
@loop:
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
    inc KANJI_ENTRY
    dec KANJI_TMP0
    bne @loop
@notfound:
    sec
    rts
@found:
    clc
    rts

; ----------------------------------------------------------------------
; Upload the current code to KANJI_TILES.
; The font is 32 bytes per glyph.  Two 16-byte halves are copied through
; the RAM stub; each half yields a left and a right 8x8 tile.
; ----------------------------------------------------------------------
upload_glyph:
    lda KANJI_CODE_HI
    lsr a
    clc
    adc #16
    sta KANJI_SRC_BANK

    lda KANJI_CODE_LO
    sta $10
    lda KANJI_CODE_HI
    and #1
    sta $11
    asl $10
    rol $11
    asl $10
    rol $11
    asl $10
    rol $11
    asl $10
    rol $11
    asl $10
    rol $11
    lda $11
    clc
    adc #$80
    sta $11

    lda #16
    sta KANJI_SRC_COUNT
    jsr KANJI_STUB

    jsr wait_queue_empty
    ldx vram_queue_write
    lda #0
    sta KANJI_Q
    lda #0
    jsr queue_one_tile
    lda #1
    jsr queue_one_tile

    ; Second half of the glyph.
    lda $10
    clc
    adc #16
    sta $10
    lda $11
    adc #0
    sta $11
    lda #16
    sta KANJI_SRC_COUNT
    jsr KANJI_STUB

    lda #0
    jsr queue_one_tile
    lda #1
    jsr queue_one_tile

    lda #0
    sta $0400,x
    stx vram_queue_write

    ; Mark the four tiles dirty.
    ldx #0
@dirty:
    lda KANJI_TILES,x
    sta KANJI_TMP0
    and #7
    tay
    lda bitmask,y
    sta KANJI_TMP1
    lda KANJI_TMP0
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_TMP1
    ora KANJI_DIRTY,y
    sta KANJI_DIRTY,y
    inx
    cpx #4
    bne @dirty
    rts

; ----------------------------------------------------------------------
; Append one 16-byte tile to the VRAM queue.
; Input: A = source parity (0/1), KANJI_Q = tile index (0-3), X = queue
; write offset.  Output: X advanced, KANJI_Q incremented.
; ----------------------------------------------------------------------
queue_one_tile:
    sta KANJI_TMP2
    ldy KANJI_Q
    lda KANJI_TILES,y
    sta KANJI_TMP0

    lda KANJI_TMP0
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta $0400,x
    inx
    lda KANJI_TMP0
    asl a
    asl a
    asl a
    asl a
    sta $0400,x
    inx
    lda #16
    sta $0400,x
    inx

    lda KANJI_TMP2
    sta KANJI_TMP1
    lda #8
    sta KANJI_TMP3
@plane0:
    ldy KANJI_TMP1
    lda KANJI_GLYPH,y
    sta $0400,x
    inx
    lda KANJI_TMP1
    clc
    adc #2
    sta KANJI_TMP1
    dec KANJI_TMP3
    bne @plane0

    lda #8
    sta KANJI_TMP3
    lda #0
@plane1:
    sta $0400,x
    inx
    dec KANJI_TMP3
    bne @plane1
    inc KANJI_Q
    rts

; ----------------------------------------------------------------------
; Restore one kana tile from bank 9.  Does not wait for queue space; the
; caller either waits first or batches eight tiles per frame.
; A = tile number 0-127.
; ----------------------------------------------------------------------
restore_kana_tile:
    sta KANJI_TMP0
    lda #KANA_FONT_BANK
    sta KANJI_SRC_BANK
    lda KANJI_TMP0
    sta $10
    lda #0
    sta $11
    asl $10
    rol $11
    asl $10
    rol $11
    asl $10
    rol $11
    lda $10
    clc
    adc #<KANA_FONT
    sta $10
    lda $11
    adc #>KANA_FONT
    sta $11
    lda #8
    sta KANJI_SRC_COUNT
    jsr KANJI_STUB

    ldx vram_queue_write
    lda KANJI_TMP0
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta $0400,x
    inx
    lda KANJI_TMP0
    asl a
    asl a
    asl a
    asl a
    sta $0400,x
    inx
    lda #16
    sta $0400,x
    inx
    ldy #0
@data:
    lda KANJI_GLYPH,y
    sta $0400,x
    inx
    iny
    cpy #8
    bne @data
    lda #0
    ldy #8
@zero:
    sta $0400,x
    inx
    dey
    bne @zero
    sta $0400,x
    stx vram_queue_write

    lda KANJI_TMP0
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_TMP0
    and #7
    tax
    lda bitmask,x
    eor #$FF
    and KANJI_DIRTY,y
    sta KANJI_DIRTY,y
    rts

; ----------------------------------------------------------------------
; Restore a kana tile before text_put_tile draws it, if a previous page
; borrowed that CHR tile for a kanji.  Replaces the original $D2BB call.
; ----------------------------------------------------------------------
kana_prepare:
    pha
    txa
    pha
    tya
    pha
    tsx
    lda $0103,x
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
    jsr wait_queue_empty
    lda KANJI_TMP1
    jsr restore_kana_tile
@done:
    pla
    tay
    pla
    tax
    pla
    jmp TEXT_PUT_TILE

; ----------------------------------------------------------------------
; Message-exit restore.  Every dirty tile not referenced by the saved or
; current text buffers gets its kana glyph back.  Clears the dirty map.
; ----------------------------------------------------------------------
restore_exit:
    lda #0
    sta KANJI_TMP3
    sta KANJI_TMP2
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
    and KANJI_DIRTY,y
    beq @next
    lda KANJI_TMP3
    jsr tile_is_visible
    bne @next
    lda KANJI_TMP2
    bne @queue
    jsr wait_queue_empty
@queue:
    lda KANJI_TMP3
    jsr restore_kana_tile
    inc KANJI_TMP2
    lda KANJI_TMP2
    cmp #8
    bcc @next
    lda #0
    sta KANJI_TMP2
@next:
    inc KANJI_TMP3
    lda KANJI_TMP3
    cmp #128
    bne @loop
    jsr wait_queue_empty
    jmp SET_BANK_CURRENT

; A = tile.  Returns A=1 when the tile is referenced by either text buffer.
tile_is_visible:
    sta KANJI_TMP0
    ldx #0
@buf1:
    lda $0180,x
    cmp KANJI_TMP0
    beq @yes
    inx
    cpx #96
    bne @buf1
    ldx #0
@buf2:
    lda $0300,x
    cmp KANJI_TMP0
    beq @yes
    inx
    cpx #96
    bne @buf2
    lda #0
    rts
@yes:
    lda #1
    rts

; ----------------------------------------------------------------------
; Control store (replaces STA $0300,X).  $FC advances to the next page.
; ----------------------------------------------------------------------
ctrl_store:
    sta $0300,x
    cmp #$FC
    bne @done
    lda KANJI_PAGES_LEFT
    cmp #2
    bcc @no_next
    dec KANJI_PAGES_LEFT

    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    asl a
    sta KANJI_TMP1
    asl a
    clc
    adc KANJI_TMP1
    clc
    adc #1
    clc
    adc KANJI_PAGE_PTR
    sta KANJI_PAGE_PTR
    lda KANJI_PAGE_PTR+1
    adc #0
    sta KANJI_PAGE_PTR+1
    jsr clear_uploaded
    rts
@no_next:
    lda #0
    sta KANJI_PAGES_LEFT
    lda #<empty_record
    sta KANJI_PAGE_PTR
    lda #>empty_record
    sta KANJI_PAGE_PTR+1
    jsr clear_uploaded
@done:
    rts

clear_uploaded:
    lda #0
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1
    rts

; ----------------------------------------------------------------------
; Wait until the game's NMI has drained the VRAM queue.
; ----------------------------------------------------------------------
wait_queue_empty:
    lda vram_queue_read
    cmp vram_queue_write
    beq @done
    jsr WAIT_VBLANK
    jmp wait_queue_empty
@done:
    rts

empty_record:
    .db 0

bitmask:
    .db $80,$40,$20,$10,$08,$04,$02,$01

; ----------------------------------------------------------------------
; RAM font-copy stub.  Installed at KANJI_STUB ($0140) at message open.
; Copies KANJI_SRC_COUNT bytes from $10/$11 in KANJI_SRC_BANK to
; KANJI_GLYPH, then maps the text bank again.
; ----------------------------------------------------------------------
stub_src:
    lda KANJI_SRC_BANK
    jsr SET_BANK_B
    ldy #0
@copy:
    lda ($10),y
    sta KANJI_GLYPH,y
    iny
    cpy KANJI_SRC_COUNT
    bne @copy
    lda KANJI_TEXT_BANK
    jmp SET_BANK_B
stub_end:
