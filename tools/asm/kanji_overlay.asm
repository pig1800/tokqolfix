; ======================================================================
; Kanji-target text-engine overlay (revision 11, ROM-resident)
;
; Assembled for $B800 and included identically in text banks 18-22.
; The overlay never touches the PPU or a mapper register.  It posts
; requests (KANJI_REQ) that the NMI serves in vblank, or that the hack
; bank serves directly when rendering is off, and waits frame by frame
; through the fixed-bank WAIT_TEXT helper, which maps this bank again.
;
; Since 2026-11-14 there is no band page (the user's order): map mode, the
; boot screens and the opening oath put their own kanji tiles (TXR_ON), the
; battle set's pool takes the rest, and any other message stops the CPU in
; band_trap.  The metadata's band parts (the kana bitmap, keep and clean
; lists, each entry's four tiles) are gone too.
;
; Message metadata in the text bank:
;   page count (bit 5: a victory message), then count * page record:
;     entries, entries * (code_lo, code_hi)
;                            (entries bits 0-4; bits 5-6: the page's runtime
;                            officer names, 3 pool slots reserved for each)
;   (Until 2026-11-14 also the band page's kana bitmap, keep / clean lists
;   and four tiles per entry.)
;
; KANJI_TEXT_ADDR is free after entry: it is the main-thread scratch
; KANJI_M0/M1.  The page-start flag is bit 7 of KANJI_PAGES_LEFT.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

TEXT_MSG_LOOP = $D160       ; text_show_message line loop (sets the line address)
META_PAGES = 1              ; offset of the first page record (after the count)
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

    ; A message that continues a window (text_line > 0) would share its
    ; tiles with the previous message's lines, which the compiler cannot
    ; know.  Clear the window first (as after a page flip); the
    ; message then starts on the top line of a clean window.  The line the engine was building is dropped
    ; with its text_clear_line frame (so the scroll runs at the engine's
    ; usual stack depth) and the line loop restarts.
    ; Battle pool (revision 20): when the lines above are pool kanji or
    ; kana and this message's first page fits in pool slots none of them
    ; shows, the window scrolls on as in the original.
    lda text_line
    beq @fresh
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

; Read the metadata.  Map mode (the text renderer), the boot screens and the
; opening oath (their fixed sets): TXR_ON non-zero, the screen's own tiles,
; no pool, no requests.  Otherwise the battle pool, or the band page, which
; is gone: band_trap.  (KANJI_BAND stays 0: a save state from an earlier
; build may hold 1.)
message_setup:
    lda #0
    sta KANJI_BAND
    lda TXR_ON
    bne @meta
    jsr pool_decide             ; C set: the battle pool
    bcs @meta
    jmp band_trap
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
    cmp #META_WIN               ; a victory message (b10_msg_059 / 061 / 062):
    bcc @count                  ; in a battle, the battle is won (the pool
    and #META_WIN-1             ; gets tiles $80-$A3, UIF_PCHOOSE)
    ldy UI_BATTLE
    beq @count
    pha
    tya
    ora #UI_WON
    sta UI_BATTLE
    pla
@count:
    sta KANJI_PAGES_LEFT
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    lda UI_BATTLE               ; won just now: the reward window's 金兵糧
    and #UI_WON|UI_RWLOAD       ; 経験値 to slots 0-5, one a frame (the UI
    cmp #UI_WON                 ; bank queues it, the NMI flushes it while
    bne @noload                 ; the text task waits)
    lda UI_BATTLE
    ora #UI_RWLOAD
    sta UI_BATTLE
    ldy #0
@load:
    tya
    pha
    sta KANJI_M2
    ldx #UIF_RWLOAD
    jsr CALL_UI
    jsr WAIT_TEXT
    pla
    tay
    iny
    cpy #6
    bne @load
@noload:

    lda TXR_ON                  ; map mode, the boot screens, the oath:
    bne @cleaned                ; their own tiles
    lda KANJI_PAGES_LEFT        ; the pool: flag the message
    ora #PAGE_POOL
    sta KANJI_PAGES_LEFT
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
; The battle pool for this message: C set for the pool (C clear: the band
; it once used, band_trap).  Pool
; on the battle screen (UI_BATTLE: always, any page size, 2026-11-13), and
; elsewhere when the battle graphics set is loaded and the pool tiles were
; read back blank (checked here if pal_copy could not post the check).
; Pool pages track nothing per entry: pool_tiles tells whether an entry is
; on this page's slots already, and KANJI_UPLOADED counts the names'
; kanji (kn_put, TXF_NAME).
; ----------------------------------------------------------------------
pool_decide:
    lda text_graphics_index
    cmp #POOL_SET
    beq @set8
    clc
    rts
@set8:
    lda UI_BATTLE               ; the battle screen: always the pool (no band
    bne @pool                   ; page there, 2026-11-13)
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
    clc                         ; still busy: no pool
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
@pool:
    sec
    rts
@no:
    clc
    rts

; $10/$11 = page record -> Y = offset of its entry count (0: the record
; starts with it since the band page's keep / clean lists went).
entries_offset:
    ldy #0
    rts

; ----------------------------------------------------------------------
; First character of a new page.  The pool: this page's slots beside the
; lines still on screen (after a clear: from 0).  Map mode, the boot screens
; and the oath: nothing (their tiles are fixed or the renderer's).
; ----------------------------------------------------------------------
page_start:
    lda KANJI_PAGES_LEFT
    and #<~PAGE_FLAG
    sta KANJI_PAGES_LEFT
    lda TXR_ON
    beq @pool
    rts
@pool:
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
    jsr pool_need
    jsr pool_choose
    pla                         ; give the game its $10/$11 back
    sta $11
    pla
    sta $10
    rts

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

; $EC-$EF pos: a kanji, store bank 0-3 (text_dispatch set KANJI_CODE_HI
; to it), pos next (KANJI_EC).  $F0: the kanji controls (KANJI_CT).  The
; original's $EF (a place) and $F0 (a word) are not in the compiled text.
dispatch_table:
    .dw KANJI_EC, KANJI_EC, KANJI_EC, KANJI_EC
    .dw KANJI_CT, $D2FE, $D2F3, $D2ED, KNAME, KNAME, KNAME, KNAME

; ----------------------------------------------------------------------
; $F0 ctl: the control byte follows (kanji_ctl).
; ----------------------------------------------------------------------
KANJI_CT:
    ldy text_col
    lda ($51),y
    inc text_col

; ----------------------------------------------------------------------
; Kanji-pick controls (revision 15; $F0 since the kanji store, $EE before):
;   $F0 $FF id lenA   the bank-13 name helpers $A1D0/$A1D4 as text: if
;                     the talked-to actor ($0580,[$72]) is officer id, the
;                     lenA bytes that follow are shown (they end with the
;                     skip below), else the variant after them
;   $F0 $FD lenA      troop pick (revision 19): the tail of $D549 as
;                     text.  The message calls the name helper $D49A,
;                     then this: if the target unit ($60A8,[$4B]) is 8 or
;                     up, the lenA bytes that follow are shown (they end
;                     with the skip below), else they are skipped
;   $F0 $FE n         skip n bytes
;   $F0 $FC n         back n cells (revision 19): follows a call whose
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
    lsr a                       ; C = 1: $FD troop / $FB tactic, C = 0: $FC back
    bcc @back
    cmp #$7E
    bcc @tact                   ; ($FB >> 1)
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
; $F0 $FB lenA (2026-11-12): $D565's tactic name.  In a pool message
; outside map mode its kanji (KNAME's way, reserved entries), then variant
; A (の計); else variant B (the call and its kanji tail, as before).
@tact:
    stx KANJI_BUFX
    bit TXR_ON
    bmi @tb
    bit KANJI_PAGES_LEFT
    bvc @tb
    lda #24
    sta TXR_TA
    jsr kn_put
    beq @tb                     ; kana: variant B
    lda #0
    beq @ta
@tb:
    ldy text_col                ; lenA
    lda ($51),y
@ta:
    ldy text_col
    jmp @advance

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
    bit TXR_ON                  ; the boot screens ($40), the oath
    bmi @meta                   ; (TXR_SPLIT): their fixed sets
    bvs @boot
    lda TXR_ON
    cmp #TXR_SPLIT
    bne @meta
    lda #OV_FIX_N               ; the oath's entries
    ldy #OV_FIX_N+OV_OATH_N-1
    bne @fix
@boot:
    lda #0                      ; the boot set's entries
    ldy #OV_FIX_N-1
@fix:
    jmp fix_put
@meta:
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
    jsr pool_tiles              ; pool: its slot (the slot table); V set:
    pla                         ; in a slot already
    sta $11                     ; (give the game its $10/$11 back; pla and
    pla                         ; sta keep V)
    sta $10
    bvs @write_tiles
    lda #REQ_UPLOAD
    jsr post_wait
    jmp put_tiles
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

; The band page is gone (2026-11-14, the user's order): a message that
; would have shown its kanji there (outside map mode, the battle set's pool,
; the boot screens and the oath) stops the CPU here, to be found in play
; and given its own tiles.  A = its text bank, X/Y = its text address
; (tools/band_trap.py names it).
band_trap:
    ldx text_ptr_lo
    ldy text_ptr_hi
    lda KANJI_TEXT_BANK
    .db $02                     ; JAM: the CPU stops

; The boot screens (TXR_ON = $40) and the opening oath (TXR_SPLIT),
; 2026-11-14: the kanji KANJI_CODE_LO/HI is entry k of the screen's fixed
; set (boot_fix.inc, the user's sets: entries A..Y), whose tiles are
; t = OV_FIX_FIRST + 4k (TL, BL, TR, BR; the boot set in the upper page, the
; oath's in CHR $3800 below the split): its tiles into the text buffers at
; X, X after them.  No upload, no band.  A kanji outside the set (the build
; allows none) is blank.
fix_put:
    sta KANJI_M0                ; the set's first entry
@f:
    lda ov_fix_lo,y
    cmp KANJI_CODE_LO
    bne @n
    lda ov_fix_hi,y
    cmp KANJI_CODE_HI
    beq @got
@n:
    cpy KANJI_M0
    beq @none
    dey
    bpl @f
@none:
    lda #$0A
    sta $0300,x
    sta $0318,x
    sta $0301,x
    sta $0319,x
    bne @adv
@got:
    tya
    sec
    sbc KANJI_M0                ; k
    asl a
    asl a
    adc #OV_FIX_FIRST           ; (C clear: k < 64)
    sta $0300,x                 ; TL
    adc #1
    sta $0318,x                 ; BL
    adc #1
    sta $0301,x                 ; TR
    adc #1
    sta $0319,x                 ; BR
@adv:
    inx
    inx
    rts

; The kanji KANJI_CODE_LO/HI -> KANJI_TILES (the UI bank's ui_ptiles: the
; battle's slot table): the slot holding it already (V set: no upload),
; else a free one (V clear).  Tiles t..t+3 in 8x16 order (t TL, t+1 BL,
; t+2 TR, t+3 BR; KANJI_TILES gets them in the glyph's order, t, t+2, t+1,
; t+3).  KANJI_M2 is kept; A, X, Y clobbered.
pool_tiles:
    ldx #UIF_PTILES
    jmp CALL_UI

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
    sty TXR_TA                  ; the code: the renderer bank finds the record
    pla
    tax
    jsr kn_put
    beq @kana
    rts                         ; put (or no officer: nothing)
@kana:
    ldy TXR_TA                  ; put_officer_name after its record lookup
    ldx KANJI_BUFX
    jmp $D4A5

; TXR_TA = a name's code (TXF_NAME), X = the buffer position: its kanji
; from the reserved entries.  X = the buffer position after; A = TXR_NM
; (Z: kana, put nothing; N: no officer).
kn_put:
    stx KANJI_BUFX
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
    jsr TXR_CALL                ; TXR_NM: kanji (0: kana, $FF: none), codes; TXR_NE: entry
    lda TXR_NM
    beq @end
    bmi @end
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
    inc KANJI_UPLOADED          ; (pool pages: the names' kanji placed)
    jsr pool_tiles              ; V set: in a slot already (no upload)
    bvs @put
    lda #REQ_UPLOAD
    jsr post_wait
@put:
    jsr put_tiles
    stx KANJI_BUFX
    inc TXR_NE
    inc TXR_NJ
    lda TXR_NJ
    cmp TXR_NM
    bne @k
@end:
    ldx KANJI_BUFX
    lda TXR_NM
    rts

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
    adc #2                      ; (code lo, hi)
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
; Control store (replaces STA $0300,X at $D2C7).  A page break, $FC <PAGE>
; or $FD <PAGENI> (the same but for the next line's indent, which the
; engine does), advances to the next page record: page_flip then clears
; the window after the wait.  (Since 2026-11-14 $FD is a page break: the
; compiler splits page records at both.)
; ----------------------------------------------------------------------
ctrl_store:
    sta $0300,x
    cmp #$FC
    beq @page
    cmp #$FD
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
    asl a                       ; 2 * entries
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
    jsr pool_choose             ; (A = 0)
    tay
    pla
    tax
    bcs @flag
    sty KANJI_UPLOADED
    sty KANJI_UPLOADED+1
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
    .db 0                       ; (no entries)

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
; Battle pool slots for a page needing A slots (revision 20; since
; 2026-11-13 the UI bank's ui_pchoose: the lines' slots, the reward and
; prisoner windows', tiles $80-$A3 once the battle is won, then every
; kanji tile no window shows).  KANJI_PMASK = the blocked slots (entry k
; takes the k-th free one, pool_tiles).  C clear: they fit beside the
; lines on screen (the window scrolls on).  C set: fewer; the mask then
; gives up the lines' slots (the callers clear the window).  A = 0 (the
; old first-slot nibble of KANJI_UPLOADED+1).  X, Y clobbered.
; ----------------------------------------------------------------------
pool_choose:
    sta KANJI_M2                ; n
    ldx #UIF_PCHOOSE
    jsr CALL_UI                 ; V: the result (the bank switch keeps it)
    clc
    bvc @fits
    sec
@fits:
    lda #0
    rts

bitmask:
    .db $80, $40, $20, $10, $08, $04, $02, $01

; the boot screens' fixed set (fix_put)
.include "../../decomp/build/kanji/boot_fix.inc"
