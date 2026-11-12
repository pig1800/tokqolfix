; ======================================================================
; Kanji-target text-engine overlay (revision 11, ROM-resident)
;
; Assembled for $B800 and included identically in text banks 18-22.
; The overlay never touches the PPU or a mapper register.  It posts
; requests (KANJI_REQ) that the NMI serves in vblank, or that the hack
; bank serves directly when rendering is off, and waits frame by frame
; through the fixed-bank WAIT_TEXT helper, which maps this bank again.
;
; Message metadata in the text bank:
;   page count, 16-byte bitmap of every lower tile the message shows as
;   kana/frame, then count * page record:
;     nkeep, keep tiles      kanji tiles of earlier lines still on screen
;     nclean, clean tiles    kana tiles an earlier page used as kanji
;     entries, entries * (code_lo, code_hi, tile0, tile1, tile2, tile3)
;                            (entries bits 0-4; bits 5-6: the page's runtime
;                            officer names, 3 pool slots reserved for each)
;
; KANJI_TEXT_ADDR is free after entry: it is the main-thread scratch
; KANJI_M0/M1.  The page-start flag is bit 7 of KANJI_PAGES_LEFT.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

TEXT_MSG_LOOP = $D160       ; text_show_message line loop (sets the line address)
META_KANA  = 1              ; offset of the kana bitmap in the metadata
META_PAGES = 17             ; offset of the first page record
PAGE_FLAG = $80                 ; in KANJI_PAGES_LEFT: page start pending
                                ; (bit 6: PAGE_POOL, kanji.inc)

.base $B800
.org $B800

; ----------------------------------------------------------------------
; Message entry.  The trampoline has stored the text bank, the text
; address and the metadata address, and mapped this bank.  The stack
; holds the F8 handler's TEXT_RETURN above text_clear_line's return.
; ----------------------------------------------------------------------
overlay_entry:
    stx KANJI_BUFX
    ; Drop the F8 handler's TEXT_RETURN now: the overlay leaves through
    ; TEXT_LINE_LOOP or TEXT_MSG_LOOP, and every wait below then runs two
    ; bytes shallower on the text task's small stack.
    pla
    pla
    lda KANJI_TEXT_ADDR
    sta text_ptr_lo
    lda KANJI_TEXT_ADDR+1
    sta text_ptr_hi
    lda #0
    sta text_col

    jsr window_geometry

    ; A message that continues a window (text_line > 0) would share the
    ; band page with the previous message's lines, whose tiles the compiler
    ; cannot know.  Clear the window first (as after a page flip); the
    ; message then starts on the top line of a clean window.  The line the engine was building is dropped
    ; with its text_clear_line frame (so the scroll runs at the engine's
    ; usual stack depth) and the line loop restarts.
    ; Battle pool (revision 20): when the lines above are pool kanji or
    ; kana and this message's first page fits in pool slots none of them
    ; shows, the window scrolls on as in the original.
    lda text_line
    beq @fresh
    lda KANJI_BAND
    bne @clear                  ; the lines above are on the band page
    jsr pool_decide
    bcc @clear
    lda #META_PAGES
    jsr record_n
    jsr pool_choose
    bcc @fresh
@clear:
    pla
    pla
    jsr WINDOW_CLEAR            ; blank window, top line (fixed bank)
    jsr message_setup
    jmp TEXT_MSG_LOOP
@fresh:
    jsr message_setup
    ldx KANJI_BUFX
    jmp TEXT_LINE_LOOP

; Release the previous kanji, enable the band, read the metadata and clean
; this message's kana tiles on the band page.  No request is pending here,
; so the overlay owns KANJI_A.
message_setup:
    bit TXR_ON                  ; map mode: the text renderer owns the
    bmi @txr                    ; tiles (no band, no pool, no requests)
    jsr pool_decide             ; C set: the battle pool
    bcc @band
    jsr release_all
    lda #0                      ; no band page, no sprite 0
    sta KANJI_BAND
    beq @meta
@band:
    ; While no band was shown the NMI only recorded stale tiles: bring
    ; page 2 up to date first.  The previous message's kanji are still
    ; active here, so they are left for clean_kana and the band's own
    ; restores, exactly as before.
    lda #REQ_SYNC
    jsr post_wait
    jsr release_all
    lda #1                      ; (the page count stored below clears PAGE_FLAG)
    sta KANJI_BAND
@meta:

    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    sta KANJI_PAGES_LEFT
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10

    bit TXR_ON
    bmi @cleaned
    lda KANJI_BAND
    bne @clean_band
    lda KANJI_PAGES_LEFT        ; pool: flag the message, no band page to clean
    ora #PAGE_POOL
    sta KANJI_PAGES_LEFT
    bne @cleaned
@clean_band:
    jsr clean_kana
@cleaned:

    lda KANJI_PAGE_PTR
    clc
    adc #META_PAGES
    sta KANJI_PAGE_PTR
    bcc @nohi
    inc KANJI_PAGE_PTR+1
@nohi:
    lda #0
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1
    bit KANJI_PAGES_LEFT
    bvc @done
    jsr record_n                ; pool: the first page's slots (A = 0: the
    jsr pool_choose             ; record at KANJI_PAGE_PTR) beside the
    sta KANJI_UPLOADED+1        ; lines still on screen
@done:
    rts
@txr:
    lda #0
    sta KANJI_BAND
    beq @meta

; ----------------------------------------------------------------------
; Window geometry from the engine's current line cell address
; (ppu_addr shadow = corner + $21 + text_line * $40, rows wrap at 30).
; Four-screen (map-canvas step 2): KANJI_WIN_ROW bit 6 = the corner's
; vertical half (the line's, flipped when the rows wrap above row 0).
; ----------------------------------------------------------------------
window_geometry:
    lda ppu_addr_hi_shadow
    and #$03
    asl a
    asl a
    asl a
    sta KANJI_M0
    lda ppu_addr_lo_shadow
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    ora KANJI_M0                ; cell row 0-29
    ldy #$00
    sec
    sbc #1
    sec
    sbc text_line
    sec
    sbc text_line
    bpl @row_ok
    clc
    adc #30
    ldy #WINROW_LOWER           ; wrapped: the other vertical half
@row_ok:
    sta KANJI_WIN_ROW
    sty KANJI_M0
    lda ppu_addr_hi_shadow
    and #$08
    asl a
    asl a
    asl a                       ; WINROW_LOWER when the line is in $2800/$2C00
    eor KANJI_M0
    ora KANJI_WIN_ROW
    sta KANJI_WIN_ROW
    lda ppu_addr_hi_shadow
    and #$04
    asl a
    asl a
    asl a                       ; $20 for nametable 1
    sta KANJI_M0
    lda ppu_addr_lo_shadow
    and #$1F
    sec
    sbc #1
    bpl @col_ok
    and #$1F
    tay
    lda KANJI_M0
    eor #$20
    sta KANJI_M0
    tya
@col_ok:
    ora KANJI_M0
    sta KANJI_M0
    lda KANJI_WIN_COL
    and #WINCOL_POOL_OK|WINCOL_CHECKED
    ora KANJI_M0
    sta KANJI_WIN_COL           ; the NMI arms the IRQ for it
    rts

; ----------------------------------------------------------------------
; Post request A and wait until it is served.  The NMI serves requests in
; vblank; with rendering off (busy mode or NMI disabled) the hack bank
; serves them at once.  Gives up after 120 frames.  Clobbers A, X, Y.
; ----------------------------------------------------------------------
post_wait:
    sta KANJI_REQ
    ldy #0
@wait:
    lda KANJI_REQ
    beq @done
    lda nmi_busy
    bne @direct
    lda ppu_ctrl_shadow
    bmi @yield
@direct:
    tya
    pha
    lda #FN_SERVICE
    jsr CALL_HACK
    pla
    tay
    jmp @wait
@yield:
    jsr WAIT_TEXT
    iny
    cpy #120
    bcc @wait
    lda #0
    sta KANJI_REQ
@done:
    rts

; ----------------------------------------------------------------------
; Restore every band-page tile this message shows as kana/frame and that
; still holds an old kanji.  The bitmap is at metadata + 1.
; ----------------------------------------------------------------------
clean_kana:
    lda #48                     ; at most 48 restores
    pha
@scan:
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #META_KANA
    ldx #0
@byte:
    lda KANJI_A,x
    eor #$FF
    and KANJI_STALE,x
    and ($10),y
    bne @found
    iny
    inx
    cpx #16
    bne @byte
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    pla
    rts
@found:
    ldy #0
@bit:
    asl a
    bcs @got
    iny
    bne @bit
@got:
    sty KANJI_M0
    txa
    asl a
    asl a
    asl a
    ora KANJI_M0
    sta KANJI_TILES
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    lda #REQ_RESTORE
    jsr post_wait
    pla
    sec
    sbc #1
    pha
    bne @scan
    pla
    rts

; ----------------------------------------------------------------------
; Battle pool or band page for this message: C set for the pool.  Pool
; when the battle graphics set is loaded, the pool tiles were read back
; blank (checked here if pal_copy could not post the check), and no page
; of the message has more than POOL_PAGE_MAX kanji.  KANJI_PAGE_PTR = the
; message's metadata.
; ----------------------------------------------------------------------
pool_decide:
    lda text_graphics_index
    cmp #POOL_SET
    beq @set8
    clc
    rts
@set8:
    lda KANJI_WIN_COL
    bmi @checked
    ldy #120                    ; let a pending request (pal_copy's check) end
@idle:
    lda KANJI_REQ
    beq @start
    tya
    pha
    jsr WAIT_TEXT
    pla
    tay
    dey
    bne @idle
    clc                         ; still busy: band page
    rts
@start:
    lda KANJI_WIN_COL
    bmi @checked                ; pal_copy's check ended meanwhile
    lda #POOL_FIRST
    sta KANJI_TILES
    lda #0
    sta KANJI_TILES+1
    lda #POOL_CHECK_CODE
    sta KANJI_CODE_HI
    lda #REQ_UPLOAD
    jsr post_wait
@checked:
    lda KANJI_WIN_COL
    and #WINCOL_POOL_OK
    beq @no
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #0
    lda ($10),y                 ; page count
    sta KANJI_M0
    lda $10
    clc
    adc #META_PAGES
    sta $10
    bcc @page
    inc $11
@page:
    lda KANJI_M0
    beq @fits
    jsr entries_offset          ; Y = offset of the entry count
    lda ($10),y
    pha
    jsr pool_need               ; the page's entries and reserved names
    cmp #POOL_PAGE_MAX+1
    pla
    bcs @band
    and #$1F
    sty KANJI_M2                ; next record = $10 + Y + 1 + 6 * entries
    asl a
    sta KANJI_M1
    asl a
    clc
    adc KANJI_M1
    sec
    adc KANJI_M2
    clc
    adc $10
    sta $10
    bcc @nohi
    inc $11
@nohi:
    dec KANJI_M0
    jmp @page
@fits:
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    sec
    rts
@band:
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
@no:
    clc
    rts

release_all:
    lda #0
    ldx #15
@l:
    sta KANJI_A,x
    dex
    bpl @l
    rts

; $10/$11 = page record -> Y = offset of its entry count.
entries_offset:
    ldy #0
    lda ($10),y                 ; nkeep
    sec
    adc #0                      ; skip nkeep byte + keep tiles
    tay
    lda ($10),y                 ; nclean
    sec
    adc #0
    sta KANJI_M1
    tya
    clc
    adc KANJI_M1
    tay
    rts

; ----------------------------------------------------------------------
; First character of a new page: keep only the kanji still on screen,
; then restore this page's kana tiles that an earlier page used.
; ----------------------------------------------------------------------
page_start:
    lda KANJI_PAGES_LEFT
    and #<~PAGE_FLAG
    sta KANJI_PAGES_LEFT
    bit TXR_ON
    bpl @band
    rts                         ; map mode: nothing on any band page
@band:
    jsr release_all
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    ldy #0
    lda ($10),y
    beq @clean
    sta KANJI_M1
@keep:
    iny
    lda ($10),y
    and #$7F
    pha
    lsr a
    lsr a
    lsr a
    tax
    pla
    and #7
    sty KANJI_M2
    tay
    lda bitmask,y
    ldy KANJI_M2
    ora KANJI_A,x
    sta KANJI_A,x
    dec KANJI_M1
    bne @keep
@clean:
    iny                         ; Y = nclean offset
    bit KANJI_PAGES_LEFT
    bvs @pool_end               ; pool: nothing on the band page to clean
    lda ($10),y
    beq @done
    sta KANJI_M1
@next:
    iny
    lda ($10),y
    sty KANJI_M2
    and #$7F
    sta KANJI_TILES
    pha
    lsr a
    lsr a
    lsr a
    tax
    pla
    and #7
    tay
    lda bitmask,y
    and KANJI_STALE,x
    beq @skip
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    lda KANJI_M1
    pha
    lda KANJI_M2
    pha
    lda #REQ_RESTORE
    jsr post_wait
    pla
    sta KANJI_M2
    pla
    sta KANJI_M1
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    lda KANJI_PAGE_PTR          ; reload: other tasks may have run
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
@skip:
    ldy KANJI_M2
    dec KANJI_M1
    bne @next
@done:
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    rts
@pool_end:
    jsr entries_offset          ; pool: this page's slots beside the lines
    lda ($10),y                 ; still on screen (after a clear: from 0)
    jsr pool_need
    jsr pool_choose
    sta KANJI_M0
    lda KANJI_UPLOADED+1
    and #$F0
    ora KANJI_M0
    sta KANJI_UPLOADED+1
    jmp @done

; ----------------------------------------------------------------------
; Extended dispatcher for $EC-$F7 (replaces the original $D28E path).
; Every character except $F8 passes here, so the page-start work runs
; before the first character of a new page is buffered.
; ----------------------------------------------------------------------
text_dispatch:
    bit KANJI_PAGES_LEFT        ; N = PAGE_FLAG (A, X, Y kept)
    bpl @go
    stx KANJI_BUFX
    jsr page_start
    ldx KANJI_BUFX
    ldy text_col
    lda ($51),y
@go:
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
    sta KANJI_M0
    lda dispatch_table+1,y
    sta KANJI_M1
    jmp (KANJI_M0)
@normal:
    jmp TEXT_NORMAL_CHAR

dispatch_table:
    .dw KANJI_EC, KANJI_EC, KANJI_EE
    .dw $D334, $D30A, $D2FE, $D2F3, $D2ED, KNAME, KNAME, KNAME, KNAME

; ----------------------------------------------------------------------
; Three-byte kanji escape $EE hi lo (codes 512 and up): the high byte
; follows the escape; then as KANJI_EC.
; ----------------------------------------------------------------------
KANJI_EE:
    ldy text_col
    lda ($51),y
    inc text_col
    cmp #$FC
    bcs kanji_ctl
    sta KANJI_CODE_HI
    jmp KANJI_EC

; ----------------------------------------------------------------------
; Kanji-pick controls (revision 15; code high bytes are 0-15, so $FC-$FF
; are free):
;   $EE $FF id lenA   the bank-13 name helpers $A1D0/$A1D4 as text: if
;                     the talked-to actor ($0580,[$72]) is officer id, the
;                     lenA bytes that follow are shown (they end with the
;                     skip below), else the variant after them
;   $EE $FD lenA      troop pick (revision 19): the tail of $D549 as
;                     text.  The message calls the name helper $D49A,
;                     then this: if the target unit ($60A8,[$4B]) is 8 or
;                     up, the lenA bytes that follow are shown (they end
;                     with the skip below), else they are skipped
;   $EE $FE n         skip n bytes
;   $EE $FC n         back n cells (revision 19): follows a call whose
;                     fixed kana tail ($D565: のけい) has a kanji form of
;                     the same width; the kanji after it overwrite the
;                     tail's last n cells
; Both variants are plain kanji escapes, drawn by the normal path; this
; draws nothing.  $F1 and $AA are set as the original helper sets them.
; ----------------------------------------------------------------------
kanji_ctl:
    iny                         ; Y = first operand
    sta KANJI_M0                ; control byte
    pla
    tax                         ; buffer position (pushed by text_dispatch)
    lda KANJI_M0
    cmp #$FE
    beq @skip
    bcc @low                    ; $FC, $FD
    stx KANJI_BUFX
    lda ($51),y                 ; officer id
    sta $F1
    iny                         ; Y = lenA
    ldx $72
    lda $0580,x
    ldx #0
    stx $AA
    cmp $F1
    beq @take_a
    lda ($51),y                 ; skip variant A
    jmp @advance
@low:
    lsr a                       ; C = 1: $FD troop, C = 0: $FC back
    bcc @back
    stx KANJI_BUFX
    ldx $4B                     ; as $D549: ldy $4B / lda $60A8,y / cmp #8
    lda $60A8,x
    cmp #8
    bcs @take_a
    lda ($51),y                 ; skip variant A
    jmp @advance
@take_a:
    lda #0
@advance:
    sty KANJI_M0
    sec
    adc KANJI_M0                ; text_col = Y + 1 + A
    sta text_col
    ldx KANJI_BUFX
    rts
@skip:
    lda ($51),y                 ; n
    sty KANJI_M0
    sec
    adc KANJI_M0
    sta text_col
    rts
@back:
    txa
    sec
    sbc ($51),y                 ; X - n
    tax
    iny
    sty text_col
    rts

; ----------------------------------------------------------------------
; One kanji escape: find the code in the current page record, have the
; glyph uploaded once per page, and write the four tiles into the text
; buffers.
; ----------------------------------------------------------------------
KANJI_EC:
    pla
    tax
    stx KANJI_BUFX
    ldy text_col
    lda ($51),y
    inc text_col
    sta KANJI_CODE_LO
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    jsr page_find
    bcc @found
    jmp @blank_r
@found:
    bit TXR_ON
    bpl @notxr
    ; Map mode (TEXT_RENDERER.md): the renderer's codes, $80 + 2e (left
    ; half) and $81 + 2e (right), in both rows; e = the entry, whose glyph
    ; REG_LO/HI keeps.  The renderer uploads the glyph when it draws them.
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    ldy KANJI_M2
    lda KANJI_CODE_LO
    sta REG_LO,y
    lda KANJI_CODE_HI
    sta REG_HI,y
    tya
    asl a
    ora #$80
    ldx KANJI_BUFX
    sta $0300,x
    sta $0318,x
    ora #1
    sta $0301,x
    sta $0319,x
    inx
    inx
    rts
@notxr:
    bit KANJI_PAGES_LEFT
    bvc @record
    jsr pool_tiles              ; pool: entry k -> the k-th free slot
    jmp @tiles_done
@record:
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
@tiles_done:
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10

    jsr entry_bit               ; entry index KANJI_M2
    sta KANJI_M0
    and KANJI_UPLOADED,x
    bne @write_tiles
    lda KANJI_M0
    ora KANJI_UPLOADED,x
    sta KANJI_UPLOADED,x
    lda #REQ_UPLOAD
    jsr post_wait
@write_tiles:
    jmp put_tiles

@blank_r:
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    ldx KANJI_BUFX
    lda #$0A
    sta $0300,x
    sta $0318,x
    sta $0301,x
    sta $0319,x
    inx
    inx
    rts

; Pool entry KANJI_M2 -> KANJI_TILES: the k-th slot this page's
; KANJI_PMASK leaves free (pool_choose leaves the page's entries free),
; tiles $A4 + 4 * slot ..+3.  The battle screen's slot table (UI bank)
; marks it a message kanji, maybe shown, with its code (the reward window
; uses a kanji a message left in the pool).
pool_tiles:
    ldy KANJI_M2
    ldx #0
@walk:
    lda slot_lo,x
    and KANJI_PMASK
    bne @blocked
    lda slot_hi,x
    and KANJI_PMASK+1
    bne @blocked
    dey
    bmi @slot
@blocked:
    inx
    cpx #POOL_SLOTS
    bne @walk
    ldx #0
    beq @walk
@slot:
    lda #$FE
    sta UI_SLOT,x
    lda KANJI_CODE_LO
    sta UI_MC_LO,x
    lda KANJI_CODE_HI
    sta UI_MC_HI,x
    txa
    asl a
    asl a                       ; C clear (slot < 64)
    adc #POOL_FIRST
    ldx #0
@pool4:
    sta KANJI_TILES,x
    clc
    adc #1
    inx
    cpx #4
    bne @pool4
    rts

; KANJI_TILES into the text buffers at KANJI_BUFX (two cells); X after them.
put_tiles:
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

; Entry KANJI_M2 -> A = its bit, X = its byte in KANJI_UPLOADED.
entry_bit:
    lda KANJI_M2
    and #7
    tax
    lda bitmask,x
    pha
    lda KANJI_M2
    lsr a
    lsr a
    lsr a
    tax
    pla
    rts

; An entry count byte -> A = the pool slots its page needs: the entries
; (bits 0-4) and 3 per runtime officer name (bits 5-6).  X clobbered.
pool_need:
    pha
    and #$1F
    tax
    pla
    and #$60
    beq @n
@l:
    inx
    inx
    inx
    sec
    sbc #$20
    bne @l
@n:
    txa
    rts

; ----------------------------------------------------------------------
; Officer names in battle messages (2026-11-12).  $F4-$F7 in a pool
; message put the name in kanji.  The compiler reserves 3 pool entries per
; runtime name of a page (the count byte's bits 5-6) after the page's
; kanji; a name's kanji take the next free reserved entries (KANJI_UPLOADED
; marks them), uploaded and placed as KANJI_EC places a page kanji.  The
; renderer bank (TXF_NAME) gives the codes and the first free entry.  Map mode (the renderer
; puts its own names) and the band page: the original handlers.  A name
; the reserved entries cannot hold: kana.
; ----------------------------------------------------------------------
KNAME:                          ; $F4-$F7 (Y = 2 * (code - $EC): 16-22)
    bit TXR_ON
    bmi @o
    bit KANJI_PAGES_LEFT
    bvs @pool
@o:
    lda kn_orig-16,y
    sta KANJI_M0
    lda kn_orig-15,y
    sta KANJI_M1
    jmp (KANJI_M0)
@pool:
    cpy #22
    beq @f7
    cpy #18
    bne @f6
    ldx text_actor              ; $F5: text_actor's
    bcs @x
@f6:
    cpy #20
    bne @t
    ldx party_slot              ; $F6: party_slot's, else text_target's
    bpl @x
@t:
    ldx text_target             ; $F4: text_target's (none if negative)
    bpl @x
    pla
    tax
    rts
@f7:
    ldx $72                     ; $F7: the record of $05F0,[$72]
    lda $05F0,x
    bcs kn_rec
@x:
    lda $60A8,x                 ; the officer's record
kn_rec:
    sta TXR_TA
    pla
    sta KANJI_BUFX
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    jsr entries_offset
    lda ($10),y
    sta TXR_TX                  ; the page's entry count byte
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    ldx #TXF_NAME
    jsr TXR_CALL                ; TXR_NM: kanji (0: kana), codes; TXR_NE: entry
    lda TXR_NM
    beq @kana
    lda #0                      ; (KANJI_M0-M2 are the block writer's while
    sta TXR_NJ                  ; post_wait yields: the loop's state is here)
@k:
    ldx TXR_NJ
    lda TXR_NM+1,x
    sta KANJI_CODE_LO
    lda TXR_NM+4,x
    sta KANJI_CODE_HI
    lda TXR_NE
    sta KANJI_M2
    jsr entry_bit
    ora KANJI_UPLOADED,x
    sta KANJI_UPLOADED,x
    jsr pool_tiles
    lda #REQ_UPLOAD
    jsr post_wait
    jsr put_tiles
    stx KANJI_BUFX
    inc TXR_NE
    inc TXR_NJ
    lda TXR_NJ
    cmp TXR_NM
    bne @k
    rts
@kana:
    ldy TXR_TA                  ; put_officer_name after its record lookup
    ldx KANJI_BUFX
    jmp $D4A5

kn_orig:
    .dw $D2E7, $D2E1, $D2DB, $D2CF

; ----------------------------------------------------------------------
; Search the current page record for KANJI_CODE_LO/HI.  Carry set when
; absent; otherwise Y = entry offset (code_lo), KANJI_M2 = entry index,
; $10/$11 = page record.
; ----------------------------------------------------------------------
page_find:
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    jsr entries_offset
    lda ($10),y
    and #$1F                    ; (bits 5-6: reserved names)
    sta KANJI_M1
    beq @notfound
    lda #0
    sta KANJI_M2
    iny
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
    inc KANJI_M2
    dec KANJI_M1
    bne @loop
@notfound:
    sec
    rts
@found:
    dey
    clc
    rts

; ----------------------------------------------------------------------
; Control store (replaces STA $0300,X at $D2C7).  $FC advances to the next
; page record.
; ----------------------------------------------------------------------
ctrl_store:
    sta $0300,x
    cmp #$FC
    beq @page
    rts
@page:
    lda KANJI_PAGES_LEFT
    and #<~(PAGE_FLAG|PAGE_POOL)
    cmp #2
    bcc @no_next
    lda KANJI_PAGES_LEFT
    sbc #1                      ; C set: pages left - 1, bits 6-7 kept
    sta KANJI_PAGES_LEFT
    txa
    pha
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    lda KANJI_PAGE_PTR
    sta $10
    lda KANJI_PAGE_PTR+1
    sta $11
    jsr entries_offset
    sty KANJI_M2
    lda ($10),y
    and #$1F
    asl a
    sta KANJI_M1
    asl a
    clc
    adc KANJI_M1                ; 6 * entries
    sec
    adc KANJI_M2                ; + entries offset + 1
    clc
    adc KANJI_PAGE_PTR
    sta KANJI_PAGE_PTR
    lda KANJI_PAGE_PTR+1
    adc #0
    sta KANJI_PAGE_PTR+1
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    pla
    tax
    bit KANJI_PAGES_LEFT
    bvc @flag                   ; band: the next page starts on a clear window
    txa                         ; pool: when the next page fits beside the
    pha                         ; lines on screen, set it up here and let
    lda #0                      ; the engine scroll on (no page flip)
    jsr record_n
    jsr pool_choose
    tay
    pla
    tax
    bcs @flag
    lda #0
    sta KANJI_UPLOADED
    sty KANJI_UPLOADED+1        ; the page's first slot
    rts
@flag:
    lda KANJI_PAGES_LEFT
    ora #PAGE_FLAG
    sta KANJI_PAGES_LEFT
    jmp @clear
@no_next:
    lda KANJI_PAGES_LEFT        ; count 0, the pending and pool flags as they were
    and #PAGE_FLAG|PAGE_POOL
    sta KANJI_PAGES_LEFT
    lda #<empty_record
    sta KANJI_PAGE_PTR
    lda #>empty_record
    sta KANJI_PAGE_PTR+1
@clear:
    lda #0
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1
@done:
    rts

empty_record:
    .db 0, 0, 0

; ----------------------------------------------------------------------
; A = the pool slots of the page record at KANJI_PAGE_PTR + A: its entries
; and reserved names (pool_need; the game's $10/$11 kept; X, Y clobbered).
; ----------------------------------------------------------------------
record_n:
    clc
    adc KANJI_PAGE_PTR
    tax
    lda KANJI_PAGE_PTR+1
    adc #0
    tay
    lda $10                     ; the game's $10/$11 (math temps)
    pha
    lda $11
    pha
    stx $10
    sty $11
    jsr entries_offset
    lda ($10),y
    jsr pool_need
    tax
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    txa
    rts

; ----------------------------------------------------------------------
; Battle pool slots for a page of A entries (revision 20; step B item 8).
; The window scrolls on, so the page's slots must avoid every pool tile
; still in the text lines of this window ($0300 + $30 per line, lines 0 to
; text_line: the lines below hold rows of earlier windows; at text_line 0
; all four, the last window may still be on screen), and while UI_BATTLE is
; set the reward window's (UI_PRES).  KANJI_PMASK = the blocked slots:
; entry k takes the k-th free slot (KANJI_EC).  C clear: n slots are free
; beside both.  C set: fewer; KANJI_PMASK then gives up the lines' slots,
; and if that is not enough the reward window's too (the callers that
; cleared the window use it; page_flip clears the window instead).  A = 0
; (the old first-slot nibble of KANJI_UPLOADED+1).
; KANJI_M0/M1 = the blocked slots being tried (bit per slot), KANJI_M2 = n.
; ----------------------------------------------------------------------
pool_choose:
    sta KANJI_M2                ; n
    lda #0
    sta KANJI_M0
    sta KANJI_M1
    sta KANJI_PMASK
    sta KANJI_PMASK+1
    ldx text_line
    cpx #4
    bcc @lines
    ldx #3
@lines:
    lda scan_len,x
    tax
@scan:
    lda $02FF,x
    sec
    sbc #POOL_FIRST
    cmp #POOL_SLOTS*4
    bcs @next
    lsr a
    lsr a                       ; slot 0-14
    cmp #8
    and #7
    tay
    lda bitmask,y
    bcs @hi
    ora KANJI_M0
    sta KANJI_M0
    bcc @next
@hi:
    ora KANJI_M1
    sta KANJI_M1
@next:
    dex
    bne @scan
    lda UI_BATTLE               ; KANJI_PMASK = the reward window's slots
    beq @try
    lda UI_PRES
    sta KANJI_PMASK
    ora KANJI_M0
    sta KANJI_M0
    lda UI_PRES+1
    sta KANJI_PMASK+1
    ora KANJI_M1
    sta KANJI_M1
    lda #0                      ; (first try)
    pha
@try:
    ldy #0                      ; free slots
    ldx #POOL_SLOTS-1
@count:
    lda slot_lo,x
    and KANJI_M0
    bne @cnext
    lda slot_hi,x
    and KANJI_M1
    bne @cnext
    iny
@cnext:
    dex
    bpl @count
    cpy KANJI_M2
    bcs @fits
    pla
    lda #1                      ; (a fallback)
    pha
    lda KANJI_M0                ; too few: without the lines' slots, then
    cmp KANJI_PMASK             ; without the reward window's
    bne @nolines
    lda KANJI_M1
    cmp KANJI_PMASK+1
    bne @nolines
    lda #0
    sta KANJI_M0
    sta KANJI_M1
    beq @fits                   ; (all 15 free)
@nolines:
    lda KANJI_PMASK
    sta KANJI_M0
    lda KANJI_PMASK+1
    sta KANJI_M1
    jmp @try
@fits:
    lda KANJI_M0
    sta KANJI_PMASK
    lda KANJI_M1
    sta KANJI_PMASK+1
    pla
    cmp #1                      ; C set: a fallback
    lda #0
    rts

; Slot bit in KANJI_M0 (slots 0-7) and KANJI_M1 (slots 8-14).
slot_lo:
    .db $80, $40, $20, $10, $08, $04, $02, $01, 0, 0, 0, 0, 0, 0, 0
slot_hi:
    .db 0, 0, 0, 0, 0, 0, 0, 0, $80, $40, $20, $10, $08, $04, $02

scan_len:                       ; text_line 0: a new window, whose rows still
    .db $C0, $60, $90, $C0      ; hold the last window's lines (maybe shown)


bitmask:
    .db $80, $40, $20, $10, $08, $04, $02, $01
