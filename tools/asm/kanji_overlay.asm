; ======================================================================
; Kanji-target text-engine overlay (revision 9, ROM-resident)
;
; Assembled for $B800 and included identically in text banks 18-22.
; The band page (CHR page 2) holds the kana font in $00-$7F and a
; 32-glyph kanji cache in $80-$FF.  Consecutive pages alternate the two
; 64-tile halves so lines left visible from the previous page keep their
; glyphs.  The scene page (page 1) is never written by this code.
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
; Message entry.  The trampoline has put the text bank in KANJI_TEXT_BANK,
; the text address in KANJI_TEXT_ADDR and the metadata address in
; KANJI_PAGE_PTR.  It mapped the text bank before jumping here.
; ----------------------------------------------------------------------
overlay_entry:
    stx KANJI_BUFX
    ldx #0
@stub:
    lda stub_src,x
    sta KANJI_STUB,x
    inx
    cpx #(stub_end-stub_src)
    bne @stub

    ; Consume the text address before reusing $0132/$0133 for the band queue.
    lda KANJI_TEXT_ADDR
    sta text_ptr_lo
    lda KANJI_TEXT_ADDR+1
    sta text_ptr_hi
    lda #0
    sta vram_queue_read
    sta vram_queue_write

    ; First message after power-on: the band page has not been filled.
    ; The game's boot RAM clear leaves KANJI_BAND_READY zero.

    ; Map the text band page (CHR page 2) and enable the NMI mid-frame
    ; switch.  The trampoline has already mapped this text bank.
    inc KANJI_NMI_LOCK
    lda #2
    jsr overlay_write_chr1
    dec KANJI_NMI_LOCK

    lda KANJI_BAND_READY
    bne @band_ready
    jsr fill_band
@band_ready:
    lda #1
    sta KANJI_BAND_ON
    lda #0
    sta text_col
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1

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

    ldx KANJI_BUFX
    pla
    pla
    jmp TEXT_LINE_LOOP

; ----------------------------------------------------------------------
; Copy the 128 kana rows from bank 9 into CHR page 2.  Twelve tiles per
; frame through the $0400 queue (228 bytes plus terminator).  Descending
; order puts the window frame tiles ($6D-$7F) in the first chunks.
; ----------------------------------------------------------------------
fill_band:
    lda #0
    sta KANJI_BAND_READY
    jsr wait_queue_empty
    lda #0
    sta vram_queue_read
    sta vram_queue_write
    lda #127
    sta KANJI_TMP0
@chunk:
    lda #0
    sta vram_queue_read
    sta vram_queue_write
    ldx #0
    ldy #6
    sty KANJI_TMP1
@tile:
    lda KANJI_TMP0
    jsr copy_kana_row
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

    lda KANJI_TMP0
    beq @last_tile
    dec KANJI_TMP0
    dec KANJI_TMP1
    bne @tile
    beq @flush
@last_tile:
    lda #$FF
    sta KANJI_TMP0
@flush:
    lda #0
    sta $0400,x
    stx vram_queue_write
    jsr wait_queue_empty
    lda KANJI_TMP0
    bpl @chunk
    lda #1
    sta KANJI_BAND_READY
    rts

; A = kana tile 0-127.  Copy its 8 font bytes from bank 9 to KANJI_GLYPH.
copy_kana_row:
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
    rts

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
    dey                 ; Y must point at the entry's code_lo
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

; ----------------------------------------------------------------------
; Text-engine exits: leave the band page for the NMI to unmap at the next
; vblank (the visible frame is about to be redrawn by the game).
; ----------------------------------------------------------------------
exit_clear:
    lda #0
    sta KANJI_BAND_ON
    lda #1
    jsr overlay_write_chr1
    jmp SET_BANK_CURRENT

jump_exit_13:
    lda #0
    sta KANJI_BAND_ON
    lda #1
    jsr overlay_write_chr1
    jmp SET_BANK_13

jump_exit_14:
    lda #0
    sta KANJI_BAND_ON
    lda #1
    jsr overlay_write_chr1
    jmp SET_BANK_14

; ----------------------------------------------------------------------
; Write A to MMC1 CHR register 1 (five serial writes).  This copy lives in
; the text bank because the band stub and the copied RAM routines run while
; the overlay is mapped.
; ----------------------------------------------------------------------
overlay_write_chr1:
    ldx #5
@write:
    sta MMC1_CHR_BANK1
    lsr a
    dex
    bne @write
    rts

; ----------------------------------------------------------------------
; text_redraw_lines high-tile hook.  Replaces the original
; "lda $0319,x / bpl / lda #$0A" sequence:
;   - low tile < $80: copy it to $0301,x (original behaviour);
;   - kanji tile $80-$F9: leave the existing $0301,x untouched;
;   - control $FA-$FF: write a blank tile.
; ----------------------------------------------------------------------
redraw_high:
    lda $0319,x
    cmp #$FA
    bcs @blank
    cmp #$80
    bcs @skip
    sta $0301,x
    jmp $D42A
@blank:
    lda #$0A
    sta $0301,x
@skip:
    jmp $D42A

; ----------------------------------------------------------------------
; Cell-buffer tile test for text_render_cell.  Replaces the original
; "lda $0300,y / bpl" pair: tiles $00-$F9 are tile numbers, $FA-$FF stay
; control codes.  Carry is set for $FA-$FF so the patched caller uses bcc.
; ----------------------------------------------------------------------
cell_check:
    lda $0300,y
    cmp #$FA
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
    cpy #16
    bne @copy
    lda KANJI_TEXT_BANK
    jmp SET_BANK_B
stub_end:
