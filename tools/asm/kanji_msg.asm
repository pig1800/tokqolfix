; ======================================================================
; The message engine: the kanji half of the game's text engine (revision
; 11 as the ROM-resident overlay; 2026-11-14 out of the text banks, the
; user's order), in hack bank 23's lower half, included by hack.asm.
;
; While a message prints the current bank is MSG_BANK (kanji.inc): this
; code at R6, the message's text chunk at R7 ($A000-$BFFF).  The fixed
; bank's text engine calls it on every character ($D28E: text_dispatch)
; and every line control ($D2C7: ctrl_store); the F8 trampoline enters at
; msg_entry (MSG_ENTRY).  The engine never touches the PPU or a mapper
; register.  It posts requests (KANJI_REQ) that the NMI serves in vblank,
; or that the hack code serves directly when rendering is off, and waits
; frame by frame through the fixed-bank WAIT_TEXT helper, which maps the
; message bank again.
;
; Since 2026-11-14 there is no band page (the user's order): map mode, the
; boot screens and the opening oath put their own kanji tiles (TXR_ON), the
; battle set's pool takes the rest, and any other message stops the CPU in
; band_trap.
;
; No metadata (2026-11-14): a page's kanji table, REG_LO/HI 0-15 in
; first-appearance order, is built as the page prints (map mode: page_find
; adds each new kanji) or scanned from the text before the page starts
; (the pool, which must know the page's slots in advance: scan_table).
; KANJI_PAGE_N = the table's entries | the page's runtime officer names <<
; 5 (3 pool slots each).
;
; KANJI_TEXT_ADDR is free after entry: it is the main-thread scratch
; KANJI_M0/M1.  The page-start flag is bit 7 of KANJI_PAGES_LEFT.
; ======================================================================

TEXT_MSG_LOOP = $D160       ; text_show_message line loop (sets the line address)
PAGE_FLAG = $80                 ; in KANJI_PAGES_LEFT: page start pending
                                ; (bit 6: PAGE_POOL, kanji.inc)
SCAN_TABLE = $80                ; KANJI_SCAN: the scan fills the table

; ----------------------------------------------------------------------
; Message entry.  The trampoline has stored the text chunk, the text
; address and the victory flag, and mapped the message bank.  The stack
; holds the F8 handler's TEXT_RETURN above text_clear_line's return.
; ----------------------------------------------------------------------
msg_entry:
    stx KANJI_BUFX
    ; Drop the F8 handler's TEXT_RETURN now: the engine leaves through
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
    ; know.  Clear the window first (as after a page flip); the message
    ; then starts on the top line of a clean window.  The line the engine
    ; was building is dropped with its text_clear_line frame (so the scroll
    ; runs at the engine's usual stack depth) and the line loop restarts.
    ; Battle pool (revision 20): when the lines above are pool kanji or
    ; kana and this message's first page fits in pool slots none of them
    ; shows, the window scrolls on as in the original.
    lda text_line
    beq @fresh
    jsr pool_decide
    bcc @clear
    ldy #0
    jsr scan_table              ; the first page's slots
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

; The message's setup.  Map mode (the text renderer), the boot screens and
; the opening oath (their fixed sets): TXR_ON non-zero, the screen's own
; tiles, no pool, no requests.  Otherwise the battle pool, or the band
; page, which is gone: band_trap.  (KANJI_BAND stays 0: a save state from
; an earlier build may hold 1.)
message_setup:
    lda #0
    sta KANJI_BAND
    lda TXR_ON
    bne @setup
    jsr pool_decide             ; C set: the battle pool
    bcs @setup
    jmp band_trap
@setup:
    lda KANJI_PAGES_LEFT        ; the stub's victory flag (b10_msg_059 / 061
    and #MSG_WIN                ; / 062): in a battle, the battle is won (the
    beq @count                  ; pool gets tiles $80-$A3, UIF_PCHOOSE)
    lda UI_BATTLE
    beq @count
    ora #UI_WON
    sta UI_BATTLE
@count:
    lda #0
    sta KANJI_PAGES_LEFT
    sta KANJI_PAGE_N            ; the first page's table: empty (map mode
                                ; fills it as the page prints)
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

    lda #0
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1
    lda TXR_ON                  ; map mode, the boot screens, the oath:
    bne @done                   ; their own tiles
    lda #PAGE_POOL              ; the pool: flag the message, scan its
    sta KANJI_PAGES_LEFT        ; first page and choose its slots beside
    ldy #0                      ; the lines still on screen
    jsr scan_table
    jsr pool_choose
    sta KANJI_UPLOADED+1
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

; ----------------------------------------------------------------------
; First character of a new page.  The pool: this page's slots (scan_table
; built its table at the page break) beside the lines still on screen
; (after a clear: from 0).  Map mode: the page's table starts empty.  The
; boot screens and the oath: nothing (their tiles are fixed).
; ----------------------------------------------------------------------
page_start:
    lda KANJI_PAGES_LEFT
    and #<~PAGE_FLAG
    sta KANJI_PAGES_LEFT
    lda TXR_ON
    beq @pool
    lda #0
    sta KANJI_PAGE_N
    rts
@pool:
    lda KANJI_PAGE_N
    jsr pool_need
    jmp pool_choose

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
    .dw KANJI_CT, $D2FE, $D2F3, KITEM, KNAME, KNAME, KNAME, KNAME

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
    jsr page_find               ; KANJI_M2 = its entry in the page's table
    bcs @blank_r
    bit TXR_ON
    bpl @notxr
    ; Map mode (TEXT_RENDERER.md): the renderer's codes, $80 + 2e (left
    ; half) and $81 + 2e (right), in both rows; e = the entry, whose glyph
    ; REG_LO/HI keeps.  The renderer uploads the glyph when it draws them.
    lda KANJI_M2
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
    bvs @write_tiles            ; in a slot already
    lda #REQ_UPLOAD
    jsr post_wait
@write_tiles:
    jmp put_tiles

@blank_r:                       ; the page's table is full (the compiler
    ldx KANJI_BUFX              ; allows MAX_PAGE_KANJI): blank
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
; and given its own tiles.  A = its text chunk (an 8 KiB bank), X/Y = its
; text address (tools/band_trap.py names it).
band_trap:
    ldx text_ptr_lo
    ldy text_ptr_hi
    lda KANJI_TEXT_CHUNK
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
    lda KANJI_PAGE_N
    sta TXR_TX                  ; the page's entry count byte
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
; The item's name in battle messages (2026-11-17, the user's report: 「…は
; …を使った」 showed it in kana).  $F3 in a pool message puts item
; text_command (& $7F, as $D5A3) in kanji: its kanji from the page's
; reserved entries like a runtime officer name's (scan_page counts it as
; one name, two for a 4-kanji item), its kana as cells.  The string:
; ki_lo/hi (msg_items.inc: a kana byte, or $EC + store bank and pos; $FF
; ends), ki_n its kanji.  No kanji form, or too few entries left: the
; original's kana.  Map mode (the renderer puts item names) and outside
; the pool: the original handler.
; ----------------------------------------------------------------------
KITEM:                          ; $F3
    bit TXR_ON
    bmi @o
    bit KANJI_PAGES_LEFT
    bvs @pool
@o:
    jmp $D2ED
@kana:
    ldx KANJI_BUFX
    jmp $D5A3                   ; (the original's body: item text_command)
@pool:
    pla
    tax
    stx KANJI_BUFX
    lda text_command
    and #$7F
    sta TXR_TA                  ; the item (kept while post_wait yields)
    tax
    lda ki_n,x
    beq @kana
    sta KANJI_M0
    lda KANJI_PAGE_N            ; the reserved entries: n .. n + 3 * names
    and #$1F
    sta KANJI_M1
    clc
    adc KANJI_UPLOADED          ; the first not taken (the names' kanji
    sta TXR_NE                  ; the page placed)
    adc KANJI_M0                ; (C clear) after this name's
    sta KANJI_M0
    lda KANJI_PAGE_N
    and #$60
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    sta KANJI_M2                ; names (C clear)
    asl a
    adc KANJI_M2
    adc KANJI_M1                ; the reserved entries' end
    cmp KANJI_M0
    bcc @kana                   ; too few left
    lda #0
    sta TXR_NJ                  ; the string's byte
@el:
    ldx TXR_TA
    lda ki_lo,x
    sta ppu_update_ptr_lo
    lda ki_hi,x
    sta ppu_update_ptr_hi
    ldy TXR_NJ
    lda (ppu_update_ptr_lo),y
    cmp #$FF
    beq @end
    iny
    cmp #$EC
    bcs @k
    sty TXR_NJ
    ldx KANJI_BUFX
    jsr TEXT_PUT_TILE           ; a kana cell (X + 1)
    stx KANJI_BUFX
    jmp @el
@k:
    sbc #$EC                    ; (C set) the store bank
    sta KANJI_CODE_HI
    lda (ppu_update_ptr_lo),y
    sta KANJI_CODE_LO
    iny
    sty TXR_NJ
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
    jmp @el
@end:
    ldx KANJI_BUFX
    rts

; scan_page's $F3: a 4-kanji item takes two names' reserved entries.
ki_scan:
    lda text_command
    and #$7F
    tax
    lda ki_n,x
    cmp #4
    bcc @r
    inc KANJI_M2
@r:
    rts

; ----------------------------------------------------------------------
; KANJI_CODE_LO/HI in the page's table (REG_LO/HI 0 .. KANJI_PAGE_N & $1F):
; KANJI_M2 = its entry, C clear; a new kanji is added (map mode: the page's
; kanji in first-appearance order; the pool: scan_table has added them all
; already).  C set: the table is full (MAX_PAGE_KANJI).  A, Y lost.
; ----------------------------------------------------------------------
page_find:
    lda KANJI_PAGE_N
    and #$1F
    sta KANJI_M1                ; entries
    ldy #0
@loop:
    cpy KANJI_M1
    beq @add
    lda REG_LO,y
    cmp KANJI_CODE_LO
    bne @next
    lda REG_HI,y
    cmp KANJI_CODE_HI
    beq @found
@next:
    iny
    bne @loop                   ; (always)
@add:
    cpy #MAX_PAGE_KANJI
    bcs @rts
    lda KANJI_CODE_LO
    sta REG_LO,y
    lda KANJI_CODE_HI
    sta REG_HI,y
    inc KANJI_PAGE_N
@found:
    sty KANJI_M2
    clc
@rts:
    rts

; ----------------------------------------------------------------------
; The page at ($51),Y (its first byte), up to its page break, the end or
; a jump: C set when it has content (a cell, a kanji, an inserted word or
; name, a call, a jump), A = the pool slots it needs (pool_need of
; KANJI_PAGE_N).
; scan_table also builds its table: REG_LO/HI 0-15 = its kanji in
; first-appearance order (both variants of a pick, as the compiler counts
; them), KANJI_PAGE_N = the entries | its runtime officer names << 5
; ($F4-$F7, the tactic pick and $F3's item, KITEM; at most 3).
; scan_content only looks (map mode at a page break: the table still
; serves the line being drawn).
; The text codes as the compiler's page_from_bytes reads them.  X, Y lost.
; ----------------------------------------------------------------------
scan_table:
    lda #SCAN_TABLE
    sta KANJI_SCAN
    lda #0
    sta KANJI_PAGE_N
    beq scan_page               ; (always)
scan_content:
    lda #0
    sta KANJI_SCAN
scan_page:
    lda #0
    sta KANJI_M2                ; names
@next:
    lda ($51),y
    cmp #$EC
    bcc @cell                   ; a kana cell
    cmp #$F0
    bcc @kanji                  ; $EC-$EF pos: a kanji
    beq @pick                   ; $F0 ctl ...: a kanji pick
    cmp #$F3
    bcc @ins2                   ; $F1 / $F2 n: an inserted word
    beq @item                   ; $F3: the item's name (KITEM)
    cmp #$F8
    bcc @name                   ; $F4-$F7: a runtime officer name
    beq @call                   ; $F8 lo hi: a call (it returns)
    cmp #$FA
    bcc @jump                   ; $F9: a jump (the message goes on in code)
    cmp #$FC
    bcs @end                    ; $FC / $FD: the page break; $FE / $FF: the end
    iny                         ; $FA / $FB: a line break
    bne @next
    beq @end
@jump:                          ; content (the compiler's page has the jump's
    lda KANJI_SCAN              ; operand cells; what the code shows next
    ora #1                      ; goes on from this window), then the end
    sta KANJI_SCAN
    bne @end                    ; (always)
@call:
    iny
@ins2:
    iny
@cell:
    iny
@content:
    lda KANJI_SCAN
    ora #1
    sta KANJI_SCAN
    tya
    bne @next
    beq @end
@item:
    jsr ki_scan                 ; a name's entries; a 4-kanji item two
@name:
    inc KANJI_M2
    bne @cell                   ; (always)
@pick:
    iny
    lda ($51),y                 ; $FB: the tactic's name (reserved entries
    cmp #$FB                    ; like a name); $FF id lenA: 4 bytes, the
    bne @pick3                  ; others 3
    inc KANJI_M2
@pick3:
    cmp #$FF
    bne @pick2
    iny
@pick2:
    iny
    iny
    bne @next
    beq @end
@kanji:
    sec
    sbc #$EC
    sta KANJI_M1                ; code high: the store bank
    iny
    lda ($51),y
    sta KANJI_M0                ; code low: pos
    iny
    bit KANJI_SCAN
    bpl @content
    ldx KANJI_PAGE_N            ; (bits 5-6 are 0 while scanning)
    beq @add
@find:
    dex
    lda REG_LO,x
    cmp KANJI_M0
    bne @nf
    lda REG_HI,x
    cmp KANJI_M1
    beq @content                ; on the page already
@nf:
    txa
    bne @find
    ldx KANJI_PAGE_N
@add:
    cpx #MAX_PAGE_KANJI
    bcs @content
    lda KANJI_M0
    sta REG_LO,x
    lda KANJI_M1
    sta REG_HI,x
    inc KANJI_PAGE_N
    bne @content                ; (always)
@end:
    bit KANJI_SCAN
    bpl @look                   ; scan_content: the table stays
    lda KANJI_M2                ; names, at most 3, to bits 5-6
    cmp #4
    bcc @n3
    lda #3
@n3:
    asl a
    asl a
    asl a
    asl a
    asl a
    ora KANJI_PAGE_N
    sta KANJI_PAGE_N
    jsr pool_need
@look:
    lsr KANJI_SCAN              ; C = content
    rts

; ----------------------------------------------------------------------
; Control store (replaces STA $0300,X at $D2C7).  A page break, $FC <PAGE>
; or $FD <PAGENI> (the same but for the next line's indent, which the
; engine does), starts the next page, the text after it: page_flip clears
; the window after the wait (PAGE_FLAG), unless the next page has no
; content (a page break right before the end: the window stays).  The
; pool: when the next page fits beside the lines on screen, its slots are
; set up here and the engine scrolls on (no page flip).  X kept.
; ----------------------------------------------------------------------
ctrl_store:
    sta $0300,x
    cmp #$FC
    beq @page
    cmp #$FD
    beq @page
    rts
@page:
    txa
    pha
    ldy text_col                ; the page break's offset: the next page
    iny                         ; starts after it
    bit KANJI_PAGES_LEFT
    bvs @pool
    jsr scan_content            ; map mode, the fixed sets: the table still
    bcc @clear                  ; serves the line being drawn
@flag:
    lda KANJI_PAGES_LEFT
    ora #PAGE_FLAG
    sta KANJI_PAGES_LEFT
@clear:
    lda #0
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1
    pla
    tax
    rts
@pool:
    jsr scan_table              ; the next page's table and slots
    bcc @clear
    jsr pool_choose             ; C clear: it fits beside the lines on
    bcs @flag                   ; screen (A = 0)
    sta KANJI_UPLOADED
    sta KANJI_UPLOADED+1
    pla
    tax
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

; the boot screens' fixed set (fix_put)
.include "../../decomp/build/kanji/boot_fix.inc"
; the item names (KITEM)
.include "../../decomp/build/kanji/msg_items.inc"

msg_end:                        ; (the build reports the engine's size)
