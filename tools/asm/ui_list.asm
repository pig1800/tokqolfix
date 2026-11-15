; ======================================================================
; The officers' reserve list (2026-11-15, the user's QoL request;
; TEXT_RENDERER.md "The reserve list by pages"), included by ui.asm.
;
; Window $20 lists the officers in reserve for 能力, 加える and 解雇 (bank
; 14 b14_k_list).  The original showed 8 a page and an entry その他 that
; went on to the next page (and round to the first), and closed the window
; after the last name of a short page.  Now:
;   - the window has 8 lines always (rows 3-18 on screen; bank 14's line
;     CALL b14_k_list_line), then a row for the arrows (19) and the bottom
;     frame (20), one row higher than the その他 line's frame was, so the
;     officer window's 加える below shows whole;
;   - Left / Right flip the page (no wrap); a flip writes the 8 lines'
;     rows again through text_draw_line (the renderer uploads the names'
;     kanji), not the whole window;
;   - sprite arrows (tile $04 of the sprite table at $0000, free in map
;     mode; the left one mirrored) at columns 21 and 28 of row 19 when a
;     page lies that way, and the page between them ("2／5", the font's
;     digits and ／ at columns 23-25; "12／16" at 22-26 from 10 pages) when
;     there is more than one.
; The list holds 125 (LS_RESERVE, kanji.inc; 2026-11-15): 16 pages.
; The page is party_scan ($6E), as the original's.  The window engine
; ends a window on an odd row, so it draws the frame at row 19 and
; UIF_LROWS writes rows 19-20 right after (one frame later).
; ======================================================================

LS_TILE      = $04          ; the arrow's tile in the sprite table
LS_ARROW_Y   = 19*8-1       ; OAM Y: screen row 19
LS_LEFT_X    = 21*8         ; screen column 21
LS_RIGHT_X   = 28*8         ; screen column 28
LS_LINES     = 8
LS_NUM       = 3            ; the page number's first cell in the row (column 23)
T_SLASH      = $7C          ; ／ (the font's digits are $00-$09)
LS_COUNT     = $54          ; the window's lines: the cursor's range (text_scroll)
LS_PAGES     = (LS_CAP + LS_LINES - 1) / LS_LINES   ; 16 (LS_RESERVE, LS_CAP: kanji.inc)
LS_STATUS    = $6300        ; an officer record's state ($E0: the original's mark)
LS_TPL       = $16          ; the window's template pointer (text_init)
PON_RECORD   = $D4A5        ; put_officer_name with Y = the record (after its lookup)
F_WAIT_VBLANK = $C09F
F_HIDE_SPRITES = $C452
F_SET_BANK_CUR = $C47E
F_SOUND_ADD  = $C4D5
F_UPDATE_OAM = $C7C1
F_RESTORE_TILES = $CF76     ; text_restore_tiles: the rows, text_line and the cursor saved
F_ADD_X      = $D7B1        ; cursor_add_x_signed (the metarow)
F_ADD_Y      = $D7D1        ; cursor_add_y_signed (the metacolumn)
F_TO_PPU     = $D7E9        ; cursor_to_ppu: ppu_addr_lo/hi_shadow
F_DRAW_LINE  = $DC93        ; text_draw_line (the renderer translates at its end)
F_ANIM_TILE  = $DD67        ; draw_text_window: update_frame's tile animation

; ----------------------------------------------------------------------
; UIF_LSTART: page 0, the page count (a page exists when its first entry
; does), the arrow tile queued (PPU $0040: the queue's high byte $40, as
; $00 ends the queue; the PPU ignores bits 14-15).
; ----------------------------------------------------------------------
ui_lstart:
    lda #0
    sta party_scan
    tax
@page:
    txa
    asl a
    asl a
    asl a
    tay
    lda LS_RESERVE,y
    beq @end
    inx
    cpx #LS_PAGES
    bne @page
@end:
    txa
    bne @n
    lda #1                      ; (none: the callers check first)
@n:
    sta LS_NP
    ldx vram_queue_write        ; (a ring: every byte through inx)
    ldy #0
@tile:
    lda ls_arrow,y
    sta $0400,x
    inx
    iny
    cpy #3+16
    bne @tile
    lda #0
    sta $0400,x
    stx vram_queue_write
    rts

; The queue entry: PPU $0040 (tile $04), 16 bytes: the right arrow in
; colour 1 (sprite palette 0: white), planes 0 and 1.
ls_arrow:
    .db $40, LS_TILE*16, 16
    .db $00, $20, $30, $38, $3C, $38, $30, $20
    .db $00, $00, $00, $00, $00, $00, $00, $00

; ----------------------------------------------------------------------
; UIF_LROWS (window $20 just drawn, 8 lines): row 19 empty between the
; borders, row 20 the bottom frame (the engine's own codes), the cursor's
; range.
; ----------------------------------------------------------------------
ui_lrows:
    jsr ls_banks
    jsr ls_row19                ; row 19 (buffer row 1 left empty)
    ldy LS_W                    ; buffer row 1: the frame, $0B $0D .. $6F
    dey
    lda #$6F
    sta $0318,y
    lda #$0D
@bar:
    dey
    beq @corner
    sta $0318,y
    bne @bar                    ; (always)
@corner:
    lda #$0B
    sta $0318
    lda #LS_LINES+1             ; row 20: metarow 9's upper row
    jsr ls_addr
    lda #1
    jsr ls_draw
    jmp ls_done

; ----------------------------------------------------------------------
; UIF_LFRAME: the list's frame, update_frame with the arrows put after
; the actors' sprites.
; ----------------------------------------------------------------------
ui_lframe:
    jsr ls_banks
    jsr ls_frame
    jmp ls_unbank

; ----------------------------------------------------------------------
; UIF_LFLIP: Left / Right (controller_state): the page before or after,
; if there is one; then the page number with line 0, and the other lines
; two a frame (as the window opens).
; ----------------------------------------------------------------------
ui_lflip:
    ldx party_scan
    lda controller_state
    and #$02                    ; Left
    beq @right
    txa
    beq @rts                    ; the first page
    dex
    bpl @go                     ; (always)
@right:
    inx
    cpx LS_NP
    bcs @rts                    ; the last page
@go:
    stx party_scan
    lda #$09                    ; the cursor's sound
    jsr F_SOUND_ADD
    jsr ls_banks
    jsr ls_row19
    lda #0
    sta LS_L
@line:
    lda LS_L
    jsr ls_line
    inc LS_L
    lda LS_L
    cmp #LS_LINES
    beq @done
    lsr a
    bcc @line                   ; (another line this frame)
    jsr ls_frame
    jmp @line
@done:
    jmp ls_done
@rts:
    rts

; ----------------------------------------------------------------------
; UIF_LPICK: the officer picked, as the original's end: $60AF = the
; record, $4A = 7, X = its entry in the list (call_ui keeps X).
; ----------------------------------------------------------------------
ui_lpick:
    lda #7
    sta text_actor
    lda party_scan
    asl a
    asl a
    asl a
    adc text_menu_index
    tax
    lda LS_RESERVE,x
    sta $60AF
    rts

; ----------------------------------------------------------------------
; Banks for the game's routines called here: put_officer_name ends in
; set_bank_current (current_bank_a), and a yield resumes in
; current_bank_b.  Both are this bank until ls_unbank.  The window's width
; (text_speed_count, from text_init) is kept for the rows drawn.
ls_banks:
    lda current_bank_a
    sta LS_BA
    lda current_bank_b
    sta LS_BB
    lda #UI_BANK
    sta current_bank_a
    sta current_bank_b
    lda text_speed_count
    sta LS_W
    rts

; After drawing: the cursor's range, the dialogue's rows and the cursor
; back (text_restore_tiles, as the original's redraw did), the width.
ls_done:
    jsr ls_count
    jsr F_RESTORE_TILES
    lda LS_W
    sta text_speed_count
ls_unbank:
    lda LS_BA
    sta current_bank_a
    lda LS_BB
    sta current_bank_b
    rts

; LS_COUNT = the page's officers (the cursor wraps within them), the
; cursor kept within them.
ls_count:
    lda party_scan
    asl a
    asl a
    asl a
    tay
    ldx #0
@c:
    lda LS_RESERVE,y
    beq @e
    iny
    inx
    cpx #LS_LINES
    bne @c
@e:
    stx LS_COUNT
    cpx text_menu_index
    beq @last
    bcs @rts
@last:
    dex
    stx text_menu_index
@rts:
    rts

; update_frame with the arrows: the tile animation every 16 frames, the
; actors' sprites, the rest hidden, the arrows, the frame.
ls_frame:
    lda input_buttons
    bne @wait
    lda frame_counter
    and #$0F
    bne @oam
    jsr F_ANIM_TILE
@oam:
    jsr F_UPDATE_OAM
    jsr F_HIDE_SPRITES
    jsr ls_arrows
@wait:
    jmp F_WAIT_VBLANK

; The arrows into the OAM shadow after the actors (oam_write_index):
; left on every page but the first (mirrored), right on every page but
; the last.
ls_arrows:
    ldx oam_write_index
    lda party_scan
    beq @right
    lda #LS_LEFT_X
    ldy #$40
    jsr @put
@right:
    ldy party_scan
    iny
    cpy LS_NP
    bcs @rts
    lda #LS_RIGHT_X
    ldy #$00
@put:
    cpx #0                      ; (the shadow full: no room)
    beq @rts
    sta $0203,x
    tya
    sta $0202,x
    lda #LS_TILE
    sta $0201,x
    lda #LS_ARROW_Y
    sta $0200,x
    inx
    inx
    inx
    inx
@rts:
    rts

; Line A of the page (0-7) into buffer rows 0-1 (the name after the
; border and the cursor's cell, as b14_k_list_line), then its two rows:
; the upper is metarow A's lower row, the lower metarow A+1's upper row.
ls_line:
    sta LS_K
    jsr ls_clear
    lda party_scan
    asl a
    asl a
    asl a
    adc LS_K
    tay
    lda LS_RESERVE,y
    beq @draw
    tay
    ldx #2
    lda LS_STATUS,y
    cmp #$E0
    bne @name
    lda #$0E                    ; (the original's mark)
    sta $0318,x
    inx
@name:
    jsr PON_RECORD
@draw:
    lda LS_K
    jsr ls_addr
    jsr ls_lower
    lda #0
    jsr ls_draw
    lda LS_K
    clc
    adc #1
    jsr ls_addr
    lda #1
    ; (falls through)

; Buffer row A (text_line) through text_draw_line at ppu_addr_lo/hi_shadow,
; the window's width.
ls_draw:
    sta text_line
    lda LS_W
    sta text_speed_count
    jmp F_DRAW_LINE

; Row 19 (metarow 8's lower row) from buffer row 0: the window's empty
; row, and with more than one page the page number between the arrows:
; "2／5" in cells LS_NUM to LS_NUM+2, from 10 pages "12／16" (" 2／16")
; one cell on and one wider.  Buffer row 1 is left the empty row.
ls_row19:
    jsr ls_clear
    lda LS_NP
    cmp #2
    bcc @draw
    ldx #LS_NUM+2               ; the pages' last digit
    cmp #10
    bcc @one
    inx
@one:
    jsr ls_num                  ; the pages
    lda #T_SLASH
    sta $0300,x
    dex
    lda party_scan
    clc
    adc #1
    jsr ls_num                  ; this page
@draw:
    lda #LS_LINES
    jsr ls_addr
    jsr ls_lower
    lda #0
    jmp ls_draw

; A (1-99) into buffer row 0, its last digit at cell X (the font's digits
; $00-$09); X = the cell before it.
ls_num:
    ldy #0
@t:
    cmp #10
    bcc @u
    sbc #10
    iny
    bne @t                      ; (always)
@u:
    sta $0300,x
    dex
    tya
    beq @rts
    sta $0300,x
    dex
@rts:
    rts

; Buffer rows 0 and 1: an empty line of the window ($7D, $0A .., $7E).
ls_clear:
    ldy LS_W
    dey
    lda #$7E
    sta $0300,y
    sta $0318,y
    lda #$0A
@b:
    dey
    beq @l
    sta $0300,y
    sta $0318,y
    bne @b                      ; (always)
@l:
    lda #$7D
    sta $0300
    sta $0318
    rts

; ppu_addr_lo/hi_shadow = the window's metarow A (0: the top frame's),
; its left column: the cursor as text_init sets it (text_x .. text_y2,
; the template's offsets), A metarows down.
ls_addr:
    sta LS_J
    ldx text_x
    ldy text_y
    lda input_buttons
    bpl @a
    ldx #7
    ldy #0
@a:
    stx cursor_x
    sty cursor_y
    ldx #8
    lda text_busy
    beq @b
    iny
@b:
    lda input_buttons
    bmi @c
    ldx text_x2
    ldy text_y2
@c:
    stx cursor_x2
    sty cursor_y2
    ldy #0
    lda (LS_TPL),y
    clc
    adc LS_J
    jsr F_ADD_X
    ldy #1
    lda (LS_TPL),y
    tax
    lda input_buttons
    and #$02
    beq @d
    inx
@d:
    txa
    jsr F_ADD_Y
    jmp F_TO_PPU

; The metarow's lower row (its upper row is even: bit 5 clear).
ls_lower:
    lda ppu_addr_lo_shadow
    ora #$20
    sta ppu_addr_lo_shadow
    rts
