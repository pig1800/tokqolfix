; ======================================================================
; Kanji-target text-engine overlay (revision 10, ROM-resident)
;
; Assembled for $B800 and included identically in text banks 18-22.
; At message open the overlay copies CHR page 1 to page 2 and uploads
; every glyph the message uses, all with NMI disabled.  The NMI then
; only switches to page 2 at the window border.  No hack-bank code runs
; on the task stack, which is only a few bytes deep.
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
; Message entry.  The trampoline has put the text bank in
; KANJI_TEXT_BANK, the text address in KANJI_TEXT_ADDR and the metadata
; address in KANJI_PAGE_PTR, and mapped this bank.
; ----------------------------------------------------------------------
overlay_entry:
    stx KANJI_BUFX

    ; The text engine runs on a small task stack.  Do the CHR work on the
    ; main stack: while a task runs, the scheduler's stack frames are dead.
    lda #0
    sta KANJI_SAVED_SP
    tsx
    cpx #$31
    bcs @nostack
    stx KANJI_SAVED_SP
    ldx #$FF
    txs
@nostack:

    lda #0
    ldx #15
@clear_a:
    sta KANJI_A_BITS,x
    dex
    bpl @clear_a

    jsr full_sync

    lda #1
    sta KANJI_MSG_OPEN

    lda KANJI_TEXT_ADDR
    sta text_ptr_lo
    lda KANJI_TEXT_ADDR+1
    sta text_ptr_hi
    lda #0
    sta text_col

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

    jsr preupload

    ldx KANJI_SAVED_SP
    beq @norestore
    txs
@norestore:
    ldx KANJI_BUFX
    pla
    pla
    jmp TEXT_LINE_LOOP

; ----------------------------------------------------------------------
; Copy all 128 page-1 tiles to page 2 (NMI off, CHR reg 1 = page 2),
; write the sprite-0 pattern, then restore page 1 and NMI.
; ----------------------------------------------------------------------
full_sync:
    jsr PPU_NMI_OFF
    lda #0
    sta KANJI_BAND_ON
    lda #0
    sta KANJI_SHADOW_CUR
@loop:
    ; Read the tile from page 1.
    lda #1
    jsr write_reg1_locked
    lda KANJI_SHADOW_CUR
    asl a
    asl a
    asl a
    asl a
    sta KANJI_OVL0
    lda KANJI_SHADOW_CUR
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta KANJI_OVL1
    sta PPUADDR
    lda KANJI_OVL0
    sta PPUADDR
    lda PPUDATA
    ldx #0
@read:
    lda PPUDATA
    sta KANJI_GLYPH_BUF,x
    inx
    cpx #16
    bne @read

    ; Write it to page 2.
    lda #2
    jsr write_reg1_locked
    lda KANJI_OVL1
    sta PPUADDR
    lda KANJI_OVL0
    sta PPUADDR
    ldx #0
@write:
    lda KANJI_GLYPH_BUF,x
    sta PPUDATA
    inx
    cpx #16
    bne @write
    inc KANJI_SHADOW_CUR
    lda KANJI_SHADOW_CUR
    cmp #128
    bne @loop

    ; Sprite-0 pattern: page-0 tile $FF, opaque rows 1-2.
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

    lda #1
    jsr write_reg1_locked
    lda #1
    sta KANJI_BAND_ON
    jsr PPU_NMI_ON
    rts

; ----------------------------------------------------------------------
; Upload every page-record glyph to CHR page 2 with NMI disabled.
; Sets the active-kanji bitmap for every assigned tile.
; ----------------------------------------------------------------------
preupload:
    jsr PPU_NMI_OFF
    lda #2
    jsr write_reg1_locked
    lda KANJI_PAGES_LEFT
    sta KANJI_OVL2
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
@page:
    ldy #0
    lda ($10),y
    sta KANJI_OVL3
    inc $10
    bne @p2
    inc $11
@p2:
    lda KANJI_OVL3
    beq @next_page
@entry:
    ldy #0
    lda ($10),y
    sta KANJI_CODE_LO
    iny
    lda ($10),y
    sta KANJI_CODE_HI
    iny
    ldx #0
@tiles:
    lda ($10),y
    sta KANJI_TILES,x
    iny
    inx
    cpx #4
    bne @tiles
    lda $10
    clc
    adc #6
    sta $10
    bcc @adv
    inc $11
@adv:
    lda #0
    sta KANJI_OVL1
@abits:
    ldy KANJI_OVL1
    lda KANJI_TILES,y
    sta KANJI_OVL0
    lsr a
    lsr a
    lsr a
    tay
    lda KANJI_OVL0
    and #7
    tax
    lda bitmask,x
    ora KANJI_A_BITS,y
    sta KANJI_A_BITS,y
    inc KANJI_OVL1
    lda KANJI_OVL1
    cmp #4
    bne @abits

    jsr load_and_upload
    dec KANJI_OVL3
    bne @entry
@next_page:
    dec KANJI_OVL2
    bne @page
    lda #1
    jsr write_reg1_locked
    jsr PPU_NMI_ON
    rts

; ----------------------------------------------------------------------
; Load the glyph named by KANJI_CODE_LO/HI from bank 23/24 and upload
; the four tiles in KANJI_TILES to CHR page 2.  Inline bank mapping keeps
; the task-stack depth at four bytes.
; ----------------------------------------------------------------------
load_and_upload:
    lda KANJI_CODE_HI
    cmp #1
    bcc @bank23
    bne @bank24
    lda KANJI_CODE_LO
    cmp #$67
    bcs @bank24
@bank23:
    lda #23
    sta KANJI_OVL0
    lda KANJI_CODE_LO
    sta KANJI_OVL1
    lda KANJI_CODE_HI
    sta KANJI_OVL2
    jmp @map
@bank24:
    lda #24
    sta KANJI_OVL0
    lda KANJI_CODE_LO
    sec
    sbc #$67
    sta KANJI_OVL1
    lda KANJI_CODE_HI
    sbc #1
    sta KANJI_OVL2
@map:
    lda #1
    sta bank_switch_lock
@retry_map:
    lda KANJI_OVL0
    and #$10
    ldx #5
@c0:
    sta MMC1_CHR_BANK0
    lsr a
    dex
    bne @c0
    lda KANJI_OVL0
    and #$0F
    ldx #5
@p0:
    sta MMC1_PRG_BANK
    lsr a
    dex
    bne @p0
    lda bank_switch_lock
    beq @retry_map
    lda #0
    sta bank_switch_lock

    lda KANJI_OVL1
    sta $12
    lda KANJI_OVL2
    sta $13
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
    ldy #0
@copy:
    lda ($12),y
    sta KANJI_GLYPH_BUF,y
    iny
    cpy #32
    bne @copy

    ; Map the text bank back.
    lda #1
    sta bank_switch_lock
@retry_back:
    lda KANJI_TEXT_BANK
    and #$10
    ldx #5
@c1:
    sta MMC1_CHR_BANK0
    lsr a
    dex
    bne @c1
    lda KANJI_TEXT_BANK
    and #$0F
    ldx #5
@p1:
    sta MMC1_PRG_BANK
    lsr a
    dex
    bne @p1
    lda bank_switch_lock
    beq @retry_back
    lda #0
    sta bank_switch_lock

    ; Upload the four tiles from KANJI_GLYPH_BUF.
    lda #0
    sta KANJI_OVL0
@tile:
    ldy KANJI_OVL0
    lda KANJI_TILES,y
    asl a
    asl a
    asl a
    asl a
    sta KANJI_OVL1
    lda KANJI_TILES,y
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta PPUADDR
    lda KANJI_OVL1
    sta PPUADDR

    lda KANJI_OVL0
    and #2
    asl a
    asl a
    asl a
    sta KANJI_OVL2
    lda KANJI_OVL0
    and #1
    ora KANJI_OVL2
    sta KANJI_OVL2
    ldy KANJI_OVL2
    ldx #8
@plane:
    lda KANJI_GLYPH_BUF,y
    sta PPUDATA
    tya
    clc
    adc #2
    tay
    dex
    bne @plane
    lda #0
    ldx #8
@z:
    sta PPUDATA
    dex
    bne @z
    inc KANJI_OVL0
    lda KANJI_OVL0
    cmp #4
    bne @tile
    rts

; ----------------------------------------------------------------------
; A = 1 or 2; write MMC1 CHR register 1 under the bank-switch lock.
; ----------------------------------------------------------------------
write_reg1_locked:
    sta KANJI_REG1_TMP
@retry:
    lda #1
    sta bank_switch_lock
    lda KANJI_REG1_TMP
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
    rts

; ----------------------------------------------------------------------
; Extended dispatcher for $EC-$F7 (replaces the original $D28E path).
; ----------------------------------------------------------------------
text_dispatch:
    cmp #$EF
    bcc @low
    cmp #$F8
    bcs @normal
    sec
    sbc #$EF
    tay
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
    sta KANJI_OVL0
    lda dispatch_table+1,y
    sta KANJI_OVL1
    jmp (KANJI_OVL0)
@low:
    cmp #$EC
    bcs KANJI_EC
@normal:
    jmp TEXT_NORMAL_CHAR

dispatch_table:
    .dw $D334, $D30A, $D2FE, $D2F3, $D2ED, $D2E7, $D2E1, $D2DB, $D2CF

; ----------------------------------------------------------------------
; One kanji escape: find the code in the current page record and write
; the four tile numbers into the text buffers.
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
; ----------------------------------------------------------------------
page_find:
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    sta KANJI_OVL0
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
    dec KANJI_OVL0
    bne @loop
@notfound:
    sec
    rts
@found:
    dey
    clc
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
    sta KANJI_OVL0
    asl a
    clc
    adc KANJI_OVL0
    clc
    adc #1
    clc
    adc KANJI_PAGE_PTR
    sta KANJI_PAGE_PTR
    lda KANJI_PAGE_PTR+1
    adc #0
    sta KANJI_PAGE_PTR+1
    rts
@no_next:
    lda #0
    sta KANJI_PAGES_LEFT
@done:
    rts

; ----------------------------------------------------------------------
; Text-engine exits: the message stream is closed but the window stays
; on screen, so the band and the kanji set survive until the screen is
; redrawn.
; ----------------------------------------------------------------------
exit_clear:
    lda #0
    sta KANJI_MSG_OPEN
    jmp SET_BANK_CURRENT

jump_exit_13:
    lda #0
    sta KANJI_MSG_OPEN
    jmp SET_BANK_13

jump_exit_14:
    lda #0
    sta KANJI_MSG_OPEN
    jmp SET_BANK_14

bitmask:
    .db $80, $40, $20, $10, $08, $04, $02, $01
