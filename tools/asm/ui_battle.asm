; ======================================================================
; Battle screen (step B item 7, INFO_SCREEN.md "Step B result: the battle
; screen").  Included by ui.asm.
;
; Kanji area: plane 0 of the 23 groups $A4 + 4k (k = 0-22), tiles in 8x16
; order (t TL, t+1 BL, t+2 TR, t+3 BR).  P0 cells show plane 0 only, so
; the gauges ($E0-$EE) and S, P ($F6, $F7) keep their plane 1.
;   groups 0-7    free: the subwindows' kanji (and the messages' pool)
;   groups 8-22   the 15 fixed command kanji, filled from the back
;                 (ui_fixed_g): 道具 in 21-22, 残 in 20, then 御 防 略 策
;                 戦, then the first command window's 将 武 却 退 撃 攻 総
;                 (8-14: the only fixed ones the messages' pool $A4-$DF
;                 reaches)
; UI_SLOT[k] = the glyph in group k ($FF unknown, $FE a message kanji that
; may be on screen).  UI_GF[k]: GF_REF = a window on screen shows it,
; GF_NREF = the window being drawn uses it.  A group on screen, or with a
; message kanji, is never rewritten: the new window draws that kanji blank
; and fills it in once its last row pair is drawn (the old window is gone
; then; UI_PEND = its lines).  Subwindows take the lowest free group; the
; command windows use their fixed groups and restore the ones that were
; taken.
;
; Window templates (fixed bank, patched by kanji_build): "$F8 cv_wincb n"
; per line; n = 0-3 command window line, $10 tactic line, $20 item line,
; $40-$41 the prisoner window's lines ($21: 仲間に入れる / 逃がす).
; The reward window $22 (bank 14's template): "$F8 cv_wincb", line $54.
; The canvas code's cv_sm hook calls UIF_SM after every row pair.
; ======================================================================
B_TOP       = $08           ; 2: row-buffer pointer, top row
B_BOT       = $0A           ; 2: row-buffer pointer, bottom row
B_MODE      = UI_BMODE
B_LINE      = UI_BLINE
B_Q         = UI_BQ
B_E         = UI_BE
GF_REF      = $01
GF_NREF     = $02

TEXT_PUT    = $D340         ; text_put_tile (fixed bank)
SP_OWNER_X6 = $DEBC         ; battle_sp_owner_x6 (fixed bank): Y = 6 * owner
NGROUPS     = 23
G_FIXED     = 8             ; group of ui_fixed_g[0]
F_ZAN       = 12            ; ui_fixed_g index of 残 (group 20)
F_DOU       = 13            ;   道 (group 21); 具 = 14 (group 22)
WIN_LINE0   = $266C         ; line 0's top row (19), column 12, nametable 1
PR_LINE0    = $25B4         ; window $21's line 0: top row 13, column 20
ZAN_TOP     = $262E         ; row 17, columns 14-15: 残's top half
ZAN_TILE    = $F4           ; group 20's first tile


; ----------------------------------------------------------------------
; UIF_BSTART: b14_battle_start after battle_intro_screen_body (rendering
; off): the 15 fixed kanji, the slot table, the pool.
; ----------------------------------------------------------------------
ui_bstart:
    jsr ppu_begin
    jsr battle_state_direct
    jmp ppu_end

; Busy mode: the fixed kanji to plane 0 of groups 8-22 (plane 1 kept), the
; state reset and the hooks on.
battle_state_direct:
    jsr battle_state_reset
    ldx #0
@fix:
    stx ZP_I
    txa
    asl a
    asl a
    adc #$C4                    ; group 8 + X
    sta ZP_T
    lda ui_fixed_g,x
    sta UI_SLOT+G_FIXED,x
    tay                         ; the slot table: its code (the store)
    lda ui_gcode_lo,y
    sta SL_LO+9+G_FIXED,x
    sta ZP_N                    ; (its pos)
    lda ui_gcode_hi,y
    sta SL_HI+9+G_FIXED,x
    M_STMAP                     ; (inline: the battle start's stack is
    ldy ZP_N                    ; deep, and the NMI comes on top)
@tile:
    lda ZP_T
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta PPUADDR
    lda ZP_T
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
@b:
    lda (ZP_PTR),y
    sta PPUDATA
    inc ZP_PTR+1
    lda ZP_PTR+1
    and #7
    bne @b
    inc ZP_T
    lda ZP_PTR+1
    cmp #ST_END
    bne @tile
    M_STUNMAP
    ldx ZP_I
    inx
    cpx #15
    bne @fix
    rts

; The slot table unknown, no window, no pending pool check, the pool
; handed over (the hack leaves the tiles to this code while UI_BATTLE is
; set: pool_off), the hooks on.
battle_state_reset:
    ldx #NGROUPS-1
@slot:
    lda #$FF
    sta UI_SLOT,x
    lda #0
    sta UI_GF,x
    dex
    bpl @slot
    sta UI_SPST
    sta UI_SHOWCHK
    sta UI_PEND
    sta UI_WIN
    sta B_MODE
    sta B_Q
    jsr sl_clear
    lda KANJI_CODE_HI           ; load_text_graphics posted a pool check
    cmp #POOL_CHECK_CODE
    bne @nocheck
    lda KANJI_REQ
    cmp #REQ_UPLOAD
    bne @nocheck
    lda #REQ_NONE
    sta KANJI_REQ
@nocheck:
    lda KANJI_WIN_COL
    ora #WINCOL_POOL_OK|WINCOL_CHECKED
    sta KANJI_WIN_COL
    lda #1
    sta UI_BATTLE
    rts


; UI glyph number A: its store bank at R7 (M_STMAP; the caller unmaps),
; Y = its pos.  X lost.
glyph_map:
    tay
    lda ui_gcode_lo,y
    pha
    lda ui_gcode_hi,y
    M_STMAP
    pla
    tay
    rts

; ----------------------------------------------------------------------
; Glyph A to plane 0 of group X through the VRAM queue (rendering on):
; four 8-byte entries, 44 bytes, then a flush (WAIT_VBLANK): one glyph per
; NMI (two overran vblank by up to two lines).  UI_SLOT[X] = A; the slot
; table notes the glyph's text code (slot X + 9; messages may use it).
; ----------------------------------------------------------------------
q_glyph:
    sta UI_SLOT,x
    pha
    tay
    lda ui_gcode_lo,y
    sta SL_LO+9,x
    lda ui_gcode_hi,y
    sta SL_HI+9,x
    lda SL_CLK
    sta SL_AGE+9,x
    txa
    asl a
    asl a
    adc #$A4
    sta ZP_T
    pla
    jsr q_tiles
    inc B_Q
    jmp q_flush

; Glyph A to plane 0 of tiles ZP_T..ZP_T+3 through the VRAM queue (44
; bytes, no flush), from the kanji store.
q_tiles:
    jsr glyph_map               ; Y = pos
    ldx vram_queue_write
@tile:
    lda ZP_T
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta $0400,x
    inx
    lda ZP_T
    asl a
    asl a
    asl a
    asl a
    sta $0400,x
    inx
    lda #8
    sta $0400,x
    inx
@b:
    lda (ZP_PTR),y
    sta $0400,x
    inx
    inc ZP_PTR+1
    lda ZP_PTR+1
    and #7
    bne @b
    inc ZP_T
    lda ZP_PTR+1
    cmp #ST_END
    bne @tile
    lda #0
    sta $0400,x
    stx vram_queue_write
    M_STUNMAP
    rts
.if $ > STORE_TAB
    .error "kanji store code past $9FFF (the store bank is mapped at R7)"
.endif
q_flush:
    lda B_Q
    beq @rts
    lda #0
    sta B_Q
    jmp WAIT_VBLANK
@rts:
    rts

; C set when group X may be rewritten now.  Window start (B_MODE 0): not
; used by this window, not shown by a window on screen, no message kanji.
; Window end (B_MODE 1, the old window is gone): not used by this window.
; Never one the message may show while the reward or prisoner window opens
; beside the message window (grp_shown).
grp_safe:
    lda UI_GF,x
    and #GF_NREF
    bne @no
    jsr grp_shown               ; a message line shows it (window $21 / $22
    bcs @no                     ; beside the message window, win_begin)
    lda B_MODE
    bne @yes
    lda UI_GF,x
    and #GF_REF
    bne @no
    lda UI_SLOT,x
    cmp #$FE
    beq @no
@yes:
    sec
    rts
@no:
    clc
    rts

set_nref:
    lda UI_GF,x
    ora #GF_NREF
    sta UI_GF,x
    rts

; ----------------------------------------------------------------------
; Glyph A for this window: a group that holds it, else the lowest group
; that may be rewritten (uploaded now), else none yet (drawn blank and
; filled in at the window's end).
; ----------------------------------------------------------------------
need:
    cmp #$FF
    beq @rts                    ; (no kanji)
    sta ZP_G
    ldx #NGROUPS-1
@find:
    lda UI_SLOT,x
    cmp ZP_G
    beq @have
    dex
    bpl @find
    ldx #0
@alloc:
    jsr grp_safe
    bcs @got
    inx
    cpx #NGROUPS
    bne @alloc
@rts:
    rts
@got:
    jsr set_nref
    lda ZP_G
    jmp q_glyph
@have:
    jmp set_nref

; Fixed kanji A (ui_fixed_g index) in its own group, restored when that
; may be rewritten (always at the window's end).
need_fixed:
    clc
    adc #G_FIXED
    tax
    jsr set_nref
    lda ui_fixed_g-G_FIXED,x
    cmp UI_SLOT,x
    beq @rts
    sta ZP_G
    lda B_MODE
    bne @put
    lda UI_GF,x
    and #GF_REF
    bne @rts
    lda UI_SLOT,x
    cmp #$FE
    beq @rts
@put:
    lda ZP_G
    jmp q_glyph
@rts:
    rts

; ----------------------------------------------------------------------
; Every glyph of window UI_WIN (need / need_fixed).
; ----------------------------------------------------------------------
win_glyphs:
    lda UI_WIN
    cmp #$16
    bne @not16
    jmp wg_items
@not16:
    cmp #$22
    bne @not22
    jmp wg_reward
@not22:
    cmp #$21
    bne @not21
    jmp wg_prison
@not21:
    cmp #$17
    bne @panel
    jmp wg_tactics
@panel:                         ; command window $11 / $12: its lines
    lda #0
    sta ZP_K
@line:
    ldx ZP_K
    lda panel_line,x
    sta ZP_A
    lda panel_line+4,x
    sta ZP_A+1
    ldy #0
@ent:
    lda (ZP_A),y
    iny
    cmp #$FF
    beq @next
    cmp #$FE
    bne @nokana
    iny                         ; (a kana)
    bne @ent
@nokana:
    cmp #$FD
    bne @kanji
    lda UI_WIN
    cmp #$11
    beq @ent                    ; the right column: window $11 only
    bne @next
@kanji:
    sty ZP_J
    jsr need_fixed
    ldy ZP_J
    jmp @ent
@next:
    inc ZP_K
    lda ZP_K
    cmp #4
    bne @line
    rts

wg_tactics:
    lda #F_ZAN                  ; the title's 残
    jsr need_fixed
    lda #F_DOU                  ; 道具: the command window's, still shown
    jsr need_fixed
    lda #F_DOU+1
    jsr need_fixed
    lda #0
    sta ZP_K
@ent:
    lda ZP_K
    jsr tactic_of
    beq @done
    ldy ZP_N
    lda ui_tactic_g1,y
    jsr need
    ldy ZP_N
    lda ui_tactic_g2,y
    jsr need
    lda #UI_G_KEI
    jsr need
    inc ZP_K
    lda ZP_K
    cmp #6
    bne @ent
@done:
; 計's top-right tile in plane 1 as well: the first tactic's 計 ends at
; column 18 of row 19, inside the S P cell (P1 while this window is open,
; S and P are plane 1).  Both planes set is colour 3, white in P0 too.
; Only in groups 0-14, whose plane 1 nothing shows.
    ldx #NGROUPS-1
@kei:
    lda UI_SLOT,x
    cmp #UI_G_KEI
    bne @knext
    lda UI_GF,x
    and #GF_NREF
    bne @kfound
@knext:
    dex
    bpl @kei
    rts
@kfound:
    cpx #15
    bcs @krts
    txa
    asl a
    asl a
    adc #$A6                    ; the group's third tile (TR)
    sta ZP_T
    lda #UI_G_KEI
    jsr glyph_map               ; Y = pos
    lda #>STORE_TAB+16          ; the TR tile's 8 rows (8x16 order)
    sta ZP_PTR+1
    ldx vram_queue_write
    lda ZP_T
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta $0400,x
    inx
    lda ZP_T
    asl a
    asl a
    asl a
    asl a
    ora #8                      ; plane 1
    sta $0400,x
    inx
    lda #8
    sta $0400,x
    inx
@kb:
    lda (ZP_PTR),y
    sta $0400,x
    inx
    inc ZP_PTR+1
    lda ZP_PTR+1
    cmp #>STORE_TAB+24
    bne @kb
    lda #0
    sta $0400,x
    stx vram_queue_write
    M_STUNMAP
    lda #1
    sta B_Q
    jmp q_flush
@krts:
    rts
.if $ > STORE_TAB
    .error "kanji store code past $9FFF (the store bank is mapped at R7)"
.endif

wg_items:
    lda #0
    sta ZP_K
@ent:
    lda ZP_K
    jsr item_of
    beq @done
    lda #0
    sta ZP_J
@tok:
    ldy ZP_J
    lda (ZP_A),y
    cmp #$FF
    beq @next
    inc ZP_J
    cmp #$FE
    bne @k
    inc ZP_J                    ; (a kana)
    bne @tok
@k:
    jsr need
    jmp @tok
@next:
    inc ZP_K
    lda ZP_K
    cmp #8
    bne @ent
@done:
    rts

; A = entry 0-5 of the S.P owner's tactic list: ZP_N = the tactic (Z set:
; none).
tactic_of:
    sta ZP_N
    jsr SP_OWNER_X6
    tya
    bmi @none
    clc
    adc ZP_N
    tay
    lda $65A0,y
    sta ZP_N
    rts
@none:
    lda #0
    sta ZP_N
    rts

; A = entry 0-7 of text_actor's items: ZP_N = the item (Z set: none),
; ZP_A = its name string.
item_of:
    sta ZP_N
    lda text_actor
    asl a
    asl a
    asl a
    adc ZP_N
    tay
    lda $6100,y
    and #$7F
    sta ZP_N
    beq @rts
    tay
    lda ui_item_lo,y
    sta ZP_A
    lda ui_item_hi,y
    sta ZP_A+1
    lda ZP_N
@rts:
    rts

; ----------------------------------------------------------------------
; UIF_WINCB: a battle window line (template "$F8 cv_wincb n"; X in UI_X).
; The window's first line also starts the window: its glyphs are placed
; and uploaded before any of its rows is drawn.
; ----------------------------------------------------------------------
ui_wincb:
    lda text_mode
    cmp #$22
    bne @param
    lda $54                     ; the reward window: its template is in
    ora #$30                    ; bank 14 (not mapped now), line = $54
    bne @kind
@param:
    ldy text_col
    lda ($16),y                 ; n
    inc text_col
@kind:
    sta ZP_C
    lda UI_BATTLE
    bne @live
    jsr battle_state_reset      ; (a save state from an earlier build)
@live:
    lda $54
    bne @draw
    jsr win_begin
@draw:
    lda #$00
    sta B_TOP
    lda #$18
    sta B_BOT
    lda #$03
    sta B_TOP+1
    sta B_BOT+1
    lda $54
    sta B_LINE
    ldy UI_X
    lda ZP_C
    cmp #$10
    beq @tactic
    bcc @panel
    cmp #$40
    bcs @prison
    cmp #$30
    bcs @reward
    lda battle_anim
    jsr draw_item_pair
    jmp @out
@panel:
    jsr draw_panel_line
    jmp @out
@tactic:
    lda battle_anim
    jsr draw_tactic_pair
    jmp @out
@reward:
    jsr draw_reward_line
    jmp @out
@prison:
    jsr draw_prison_line
@out:
    sty UI_X
    ldx UI_X
    rts

win_begin:
    lda vram_queue_write        ; (our entries come first in their flush)
    cmp vram_queue_read
    beq @empty
    jsr WAIT_VBLANK
@empty:
    lda text_mode
    sta UI_WIN
    ldx #0
    cmp #$21                    ; the prisoner and reward windows open beside
    beq @beside                 ; the message window: its kanji stay (UI_PML,
    cmp #$22                    ; grp_shown); other windows cover it
    bne @pml
@beside:
    inx
@pml:
    stx UI_SHOWCHK
    ldx #NGROUPS-1
@nref:
    lda UI_GF,x
    and #GF_REF
    sta UI_GF,x
    dex
    bpl @nref
    lda #0
    sta UI_PEND
    sta B_MODE
    sta B_Q
    jsr win_glyphs
    jmp q_flush

; ----------------------------------------------------------------------
; Line drawing into the row buffers (B_TOP / B_BOT), Y = index (column -
; the window's left column; +$30 in the second buffer pair).  Y returns
; past the line.
; ----------------------------------------------------------------------
; Command window line ZP_C (0-3): its words (panel_line); the right column
; (window $11) at 6 cells after the line's start (column 18).
draw_panel_line:
    sty ZP_X
    ldx ZP_C
    lda panel_line,x
    sta ZP_A
    lda panel_line+4,x
    sta ZP_A+1
    lda #0
    sta ZP_J
@ent:
    ldy ZP_J
    inc ZP_J
    lda (ZP_A),y
    ldy ZP_X
    cmp #$FF
    beq @done
    cmp #$FE
    bne @nokana
    ldy ZP_J
    inc ZP_J
    lda (ZP_A),y
    ldy ZP_X
    jsr put_kana
    sty ZP_X
    jmp @ent
@nokana:
    cmp #$FD
    bne @kanji
    lda UI_WIN
    cmp #$11
    bne @done
    lda ZP_X
    and #$30
    ora #8
    sta ZP_X
    jmp @ent
@kanji:
    clc
    adc #G_FIXED
    tax
    lda ui_fixed_g-G_FIXED,x
    cmp UI_SLOT,x
    bne @blank
    jsr put_group
    sty ZP_X
    jmp @ent
@blank:
    jsr put_blank
    sty ZP_X
    jmp @ent
@done:
    rts

; Tactic entries A and A+1 (one line): the first at Y, the second at
; column 21.  No tactic: nothing (and no count, as the original).
draw_tactic_pair:
    sta ZP_K
    jsr @one
    bcc @rts
    tya
    and #$30
    ora #$0B
    tay
    inc ZP_K
@one:
    sty ZP_X
    lda ZP_K
    jsr tactic_of
    ldy ZP_X
    lda ZP_N
    beq @none
    lda B_MODE
    bne @nocount                ; (drawn again at the window's end)
    inc battle_anim
@nocount:
    ldx ZP_N
    lda ui_tactic_g1,x
    jsr put_glyph_cell
    ldx ZP_N
    lda ui_tactic_g2,x
    jsr put_glyph_cell
    lda #T_NO
    jsr put_kana
    lda #UI_G_KEI
    jsr put_glyph_cell
    sec
    rts
@none:
    clc
@rts:
    rts

; Item entries A and A+1 likewise.
draw_item_pair:
    sta ZP_K
    jsr @one
    bcc @rts
    tya
    and #$30
    ora #$0B
    tay
    inc ZP_K
@one:
    sty ZP_X
    lda ZP_K
    jsr item_of
    ldy ZP_X
    lda ZP_N
    beq @none
    lda B_MODE
    bne @nocount
    inc battle_anim
@nocount:
    lda #0
    sta ZP_J
@tok:
    sty ZP_X
    ldy ZP_J
    lda (ZP_A),y
    iny
    sty ZP_J
    ldy ZP_X
    cmp #$FF
    beq @end
    cmp #$FE
    bne @k
    ldy ZP_J
    lda (ZP_A),y
    iny
    sty ZP_J
    ldy ZP_X
    jsr put_kana
    jmp @tok
@k:
    jsr put_glyph_cell
    jmp @tok
@end:
    sec
    rts
@none:
    clc
@rts:
    rts

; Glyph A at Y: this window's group that holds it, else blank.
put_glyph_cell:
    cmp #$FF
    beq put_blank
    sta ZP_G
    ldx #NGROUPS-1
@find:
    lda UI_SLOT,x
    cmp ZP_G
    bne @no
    lda UI_GF,x
    and #GF_NREF
    bne put_group
@no:
    dex
    bpl @find
; A blank 16x16 cell at Y; the line is drawn again at the window's end.
put_blank:
    lda #T_BLANK
    sta (B_TOP),y
    sta (B_BOT),y
    iny
    sta (B_TOP),y
    sta (B_BOT),y
    iny
    ldx B_LINE
    lda line_bit,x
    ora UI_PEND
    sta UI_PEND
    rts
; Group X's tiles at Y (8x16 order).
put_group:
    txa
    asl a
    asl a
    adc #$A4
    sta (B_TOP),y
    adc #1
    sta (B_BOT),y
    iny
    adc #1
    sta (B_TOP),y
    adc #1
    sta (B_BOT),y
    iny
    rts
line_bit:
    .db $01, $02, $04, $08

; Kana game code A at Y: lower row, the voicing mark above it (as the
; game's text_put_tile).
put_kana:
    cmp #$80
    bcc @plain
    and #$7F
    cmp #$62
    bcc @dak
    sbc #$0A                    ; (C set)
    pha
    lda #T_HANDAK
    bne @mark
@dak:
    pha
    lda #T_DAK
@mark:
    sta (B_TOP),y
    pla
@plain:
    sta (B_BOT),y
    iny
    rts

; Command window lines: ui_fixed_g index (the kanji in its group), $FE
; kana, $FD the right column (window $11 only), $FF end.
panel_line:
    .db <pl0, <pl1, <pl2, <pl3
    .db >pl0, >pl1, >pl2, >pl3
pl0: .db 7, $FE,$3F, $FD, 0, 1, 2, $FF  ; 戦う   総攻撃
pl1: .db 8, 9, $FD, 3, 4, $FF           ; 策略   退却
pl2: .db 10, 11, $FD, 5, 6, $FF         ; 防御   武将
pl3: .db 13, 14, $FF                    ; 道具

; ----------------------------------------------------------------------
; UIF_SM: a battle window row pair was queued (canvas cv_sm; the ppu_addr
; shadow is its second row at the window's left column).
; - Command windows: the columns right of the window blank, in the same
;   flush (the messages, the tactic and item windows are wider; the
;   original left their text there).  Only up to the rightmost column
;   another window covered since the last blanking (UI_BRIGHT): between
;   two officers' command windows nothing is there, and blanking it
;   anyway (30 bytes a row pair) made the flush overrun vblank (a frame
;   with the screen scrolled wrong).  cv_sm waits for a flush when the
;   queue is long (SM_QMAX).
; - The row pair 18-19: the tactic window's S P / 残 cells (UI_SPST).
; - The window's last row pair (UI_SMRET = $82): the window's end.
; ----------------------------------------------------------------------
ui_sm:
    lda ppu_addr_lo_shadow
    and #$1F
    clc
    adc text_speed_count
    sta B_E                     ; the first column right of the window
    lda text_mode
    cmp #$11
    beq @erase
    cmp #$12
    beq @erase
    lda B_E                     ; another window: it covers the columns
    cmp UI_BRIGHT               ; beside a command window up to B_E
    bcc @noerase
    sta UI_BRIGHT
    bcs @noerase
@erase:
    lda UI_BRIGHT
    cmp #31
    bcc @cap
    lda #30
@cap:
    sec
    sbc B_E                     ; columns to blank (up to 29)
    beq @noerase
    bcc @noerase
    sta ZP_N
    lda ppu_addr_lo_shadow
    and #$E0
    sec
    sbc #$20
    ora B_E
    sta ZP_T                    ; first row
    ldx vram_queue_write
    jsr sm_blank_run
    lda ZP_T
    ora #$20
    sta ZP_T                    ; second row
    jsr sm_blank_run
    lda #0
    sta $0400,x
    stx vram_queue_write
@noerase:
    lda ppu_addr_hi_shadow
    cmp #$26
    bne @nosp
    lda ppu_addr_lo_shadow
    and #$E0
    cmp #$60
    bne @nosp
    ldy #0
    lda text_mode
    cmp #$17
    bne @want
    iny
@want:
    cpy UI_SPST
    beq @nosp
    sty UI_SPST
    ldy #0
    lda UI_SPST
    beq @sp0
    ldy #10
@sp0:
    lda #10
    sta B_E
    ldx vram_queue_write
@sp:
    lda sp_off,y
    sta $0400,x
    inx
    iny
    dec B_E
    bne @sp
    lda #0
    sta $0400,x
    stx vram_queue_write
@nosp:
    lda UI_SMRET
    cmp #$82
    bne @rts
    lda text_mode               ; a command window's end: beside it is
    cmp #$11                    ; blank now
    beq @clean
    cmp #$12
    bne @noclean
@clean:
    lda ppu_addr_lo_shadow
    and #$1F
    clc
    adc text_speed_count
    sta UI_BRIGHT
@noclean:
    lda text_mode
    cmp #$22
    bne @end
    jsr reward_tail             ; (the same flush as the row pair)
@end:
    jmp win_end
@rts:
    rts

; A row of ZP_N blanks at ppu_addr_hi_shadow:ZP_T, queued at X.
sm_blank_run:
    lda ppu_addr_hi_shadow
    sta $0400,x
    inx
    lda ZP_T
    sta $0400,x
    inx
    lda ZP_N
    sta $0400,x
    inx
    tay
    lda #T_BLANK
@b:
    sta $0400,x
    inx
    dey
    bne @b
    rts

; $27E3 (rows 16-19, columns 12-15) and $27E4 (columns 16-19): the battle's
; own $0A / $0A; open: rows 16-17 columns 14-15 P0 (残's top half), rows
; 18-19 columns 18-19 P1 (S P).  Row 17 columns 14-15: blank / 残's top.
sp_off:
    .db $27,$E3,2, $0A,$0A
    .db >ZAN_TOP,<ZAN_TOP,2, T_BLANK,T_BLANK
sp_on:
    .db $27,$E3,2, $02,$4A
    .db >ZAN_TOP,<ZAN_TOP,2, ZAN_TILE,ZAN_TILE+2

; The window's last row pair is queued, so the old window is gone, and so
; are the message kanji.  A window of ours: its groups are the ones shown
; now; its kanji drawn blank get their group and their lines are drawn
; again.  Another window (message, blank): ours are covered.
win_end:
    ldx #NGROUPS-1
@msg:
    lda UI_SLOT,x
    cmp #$FE
    bne @keep
    lda #$FF
    sta UI_SLOT,x
@keep:
    dex
    bpl @msg
    lda UI_WIN
    cmp text_mode
    beq @ours
    ldx #NGROUPS-1
    lda #0
@clr:
    sta UI_GF,x
    dex
    bpl @clr
    sta UI_WIN
    rts
@ours:
    jsr nref_to_ref
    lda UI_PEND
    beq @done
    lda #1
    sta B_MODE
    sta B_Q
    jsr q_flush                 ; (the last row pair goes in its own flush)
    jsr win_glyphs
    jsr q_flush
    lda #0
    sta B_LINE
@line:
    ldx B_LINE
    lda line_bit,x
    and UI_PEND
    beq @next
    jsr redraw_line
@next:
    inc B_LINE
    lda B_LINE
    cmp #4
    bne @line
    jsr nref_to_ref
@done:
    lda #0
    sta UI_PEND
    sta UI_WIN
    sta B_MODE
    rts

; GF_REF = GF_NREF for every group.
nref_to_ref:
    ldx #NGROUPS-1
@g:
    lda UI_GF,x
    and #GF_NREF
    beq @set
    lda #GF_NREF|GF_REF
@set:
    sta UI_GF,x
    dex
    bpl @g
    rts

; Line B_LINE again (its kanji now in CHR), from column 12 to the window's
; last inner column, both rows, then a flush.
redraw_line:
    ldx #31
    lda #T_BLANK
@fill:
    sta LBUF_T,x
    sta LBUF_B,x
    dex
    bpl @fill
    lda #<LBUF_T
    sta B_TOP
    lda #>LBUF_T
    sta B_TOP+1
    lda #<LBUF_B
    sta B_BOT
    lda #>LBUF_B
    sta B_BOT+1
    ldy #2                      ; column 12 (window $21: 20)
    lda UI_WIN
    cmp #$21
    beq @prison
    cmp #$16
    beq @item
    cmp #$17
    beq @tactic
    lda B_LINE
    sta ZP_C
    jsr draw_panel_line
    jmp @queue
@tactic:
    lda B_LINE
    asl a
    jsr draw_tactic_pair
    jmp @queue
@item:
    lda B_LINE
    asl a
    jsr draw_item_pair
@queue:
    lda text_speed_count        ; columns 12 .. left + width - 2
    sec
    sbc #3
    sta ZP_N
    lda B_LINE
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a                       ; $40 * line
    clc
    adc #<WIN_LINE0
    sta ZP_T
    lda #>WIN_LINE0
    adc #0
    sta ZP_C
    jmp @put
@prison:
    lda B_LINE
    sta ZP_C
    jsr draw_prison_line
    lda #9                      ; columns 20-28
    sta ZP_N
    lda B_LINE
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc #<PR_LINE0
    sta ZP_T
    lda #>PR_LINE0
    adc #0
    sta ZP_C
@put:
    ldx vram_queue_write
    jsr @head
    ldy #2
@t:
    lda LBUF_T,y
    sta $0400,x
    inx
    iny
    dec ZP_J
    bne @t
    lda ZP_T
    clc
    adc #$20
    sta ZP_T
    lda ZP_C
    adc #0
    sta ZP_C
    jsr @head
    ldy #2
@b:
    lda LBUF_B,y
    sta $0400,x
    inx
    iny
    dec ZP_J
    bne @b
    lda #0
    sta $0400,x
    stx vram_queue_write
    jmp WAIT_VBLANK
@head:
    lda ZP_C
    sta $0400,x
    inx
    lda ZP_T
    sta $0400,x
    inx
    lda ZP_N
    sta $0400,x
    sta ZP_J
    inx
    rts

; ----------------------------------------------------------------------
; Window $21: a captured officer (the victory, after the reward window):
; 仲間に入れる / 逃がす (the original's なかまにいれる / にがす).  At the user's
; call (2026-11-12) two columns wider to the left than the original:
; columns 18-29, rows 12-17, text from column 20 (index 2).  Its kanji
; take free groups (need; never one the message window may show); the
; messages keep off them while the window is shown (GF_REF).
; Columns 18-19 of rows 14-17 are the battle's P2: P0 while it is open
; (the battle ends after it; rows 12-13 there are P0 already).
; ----------------------------------------------------------------------
wg_prison:
    lda #0
    sta ZP_K
@k:
    ldy ZP_K                    ; (the messages keep off its groups while it
    lda ui_prison_g,y           ; is shown: GF_REF, ui_pchoose)
    jsr need
    inc ZP_K
    lda ZP_K
    cmp #PR_N
    bne @k
    ldx vram_queue_write
    ldy #0
@a:
    lda pr_attr,y
    sta $0400,x
    inx
    iny
    cpy #8
    bne @a
    lda #0
    sta $0400,x
    stx vram_queue_write
    lda #1
    sta B_Q
    rts
; $27DC (rows 12-15, columns 16-19): the reward window's $A2, now with
; rows 14-15 columns 18-19 P0; $27E4 (rows 16-19, columns 16-19): the
; battle's $0A, with rows 16-17 columns 18-19 P0.
pr_attr:
    .db $27,$DC,1,$22, $27,$E4,1,$02
PR_N        = 4             ; ui_prison_g: 仲 間 入 逃

; Line ZP_C & 1 of window $21 at Y: ui_prison_g index, $FE kana, $FF end.
draw_prison_line:
    lda ZP_C
    and #1
    tax
    lda pr_line_lo,x
    sta ZP_A
    lda pr_line_hi,x
    sta ZP_A+1
    lda #0
    sta ZP_J
@tok:
    sty ZP_X
    ldy ZP_J
    inc ZP_J
    lda (ZP_A),y
    ldy ZP_X
    cmp #$FF
    beq @done
    cmp #$FE
    bne @kanji
    ldy ZP_J
    inc ZP_J
    lda (ZP_A),y
    ldy ZP_X
    jsr put_kana
    jmp @tok
@kanji:
    tax
    lda ui_prison_g,x
    jsr put_glyph_cell
    jmp @tok
@done:
    rts
pr_line_lo: .db <pr_l0, <pr_l1
pr_line_hi: .db >pr_l0, >pr_l1
pr_l0:      .db 0, 1, $FE,$20, 2, $FE,$34, $FE,$33, $FF    ; 仲間に入れる
pr_l1:      .db 3, $FE,$90, $FE,$17, $FF                    ; 逃がす

; ----------------------------------------------------------------------
; Reward window $22 (victory: gold, food, experience; step B item 8).  The
; original's eight rows (2-9, columns 18-29) grow by three: 16x16 kanji,
; each word with its number in the row below.  The template (bank 14
; $923C, data_EDA1/EDD1 patched by kanji_build) has four lines, rows 3-10;
; its last row pair also writes rows 11 and 12 (reward_tail).
;   rows 3-4    金            line 0
;   row 5       gold          line 1, top row
;   rows 6-7    兵糧          line 1 bottom row, line 2 top row
;   row 8       food          line 2, bottom row
;   rows 9-10   経験値        line 3
;   row 11      experience    reward_tail
;   row 12      border        reward_tail
; Kanji from column 20 (index 2), 7 digits at columns 21-27 (index 3-9).
; Since 2026-11-13 the six kanji have fixed slots 0-5 (tiles $80-$97, the
; portrait's, free from the win): the first victory message loads them
; (UIF_RWLOAD); if it did not, the window's start does.
; ----------------------------------------------------------------------
RW_BASE     = ZP_C          ; the row pair's base ($00 / $30), after the line
RW_DIG      = $0650         ; 7: digit tiles (the $0600 page, within a call)
RW_NUM      = $0657         ; 3: the number
RW_GOLD     = $06           ; offsets from $6070: gold $6076, food $6079,
RW_FOOD     = $09           ; experience $6070
RW_EXP      = $00
RW_N        = 6             ; ui_reward_g: 金 兵 糧 経 験 値
RW_ROW12_AT = $27DC         ; rows 12-15, columns 16-19: the battle's $AA (P2)
RW_ROW12_V  = $A2           ;   with rows 12-13 columns 18-19 P0
T_LSIDE     = $7D
T_RSIDE     = $7E
T_BL        = $0B
T_BOT       = $0D
T_BR        = $6F

wg_reward:
    lda UI_BATTLE
    and #UI_RWLOAD
    bne @rts
    lda #0                      ; not loaded yet: here, one per NMI
    sta ZP_K
@k:
    ldx ZP_K
    jsr rw_slot_glyph
    inc B_Q
    jsr q_flush
    inc ZP_K
    lda ZP_K
    cmp #RW_N
    bne @k
    lda UI_BATTLE
    ora #UI_WON|UI_RWLOAD
    sta UI_BATTLE
@rts:
    rts

; Line ZP_C & 3 of the reward window, Y = UI_X (the pair's base in bits
; 4-5).  Y returns at index 10.
draw_reward_line:
    lda ZP_C
    and #3
    tax
    tya
    and #$30
    sta RW_BASE
    txa
    beq @l0
    cmp #2
    beq @l2
    bcs @l3
    ldx #RW_GOLD                ; line 1: gold, 兵糧's upper half
    jsr rw_top_num
    lda #1
    ldx #2
    ldy #0
    jsr rw_bot_word
    jmp @out
@l0:
    lda #0                      ; line 0: 金
    ldx #1
    jsr rw_both
    jmp @out
@l2:
    lda #1                      ; line 2: 兵糧's lower half, food
    ldx #2
    ldy #1
    jsr rw_top_word
    ldx #RW_FOOD
    jsr rw_bot_num
    jmp @out
@l3:
    lda #3                      ; line 3: 経験値
    ldx #3
    jsr rw_both
@out:
    lda RW_BASE
    ora #10
    tay
    rts

; Words: X kanji from reward kanji A at index 2, half Y (0 upper, 1
; lower), in the top / bottom row; rw_both: the upper half in the top row,
; the lower in the bottom row.
rw_both:
    stx ZP_T
    pha
    ldy #0
    jsr rw_top_word
    pla
    ldx ZP_T
    ldy #1
rw_bot_word:
    pha
    lda B_BOT
    sta ZP_A
    lda B_BOT+1
    bne rw_word                 ; (always: $03)
rw_top_word:
    pha
    lda B_TOP
    sta ZP_A
    lda B_TOP+1
rw_word:
    sta ZP_A+1
    sty ZP_J
    stx ZP_N
    pla
    sta ZP_K
    lda RW_BASE
    ora #2
    tay
@k:
    jsr rw_half
    inc ZP_K
    dec ZP_N
    bne @k
    rts

; Numbers: the 24-bit number at $6070 + X, 7 digits at index 3.
rw_bot_num:
    lda B_BOT
    sta ZP_A
    lda B_BOT+1
    bne rw_num                  ; (always: $03)
rw_top_num:
    lda B_TOP
    sta ZP_A
    lda B_TOP+1
rw_num:
    sta ZP_A+1
    jsr num7
    lda RW_BASE
    ora #3
    tay
    ldx #0
@d:
    lda RW_DIG,x
    sta (ZP_A),y
    iny
    inx
    cpx #7
    bne @d
    rts

; Half ZP_J (0 upper, 1 lower) of reward kanji ZP_K at (ZP_A),y; Y += 2:
; its slot RW_SLOT + ZP_K, 8x16 order (upper t, t+2; lower t+1, t+3).
rw_half:
    sty ZP_X
    lda ZP_K
    clc
    adc #RW_SLOT
    asl a
    asl a
    ora #$80
    ldy ZP_J
    beq @c0
    ora #1
@c0:
    ldy ZP_X
    sta (ZP_A),y
    iny
    clc
    adc #2
    sta (ZP_A),y
    iny
    rts

; RW_DIG = the 24-bit number at $6070 + X as 7 digit tiles, leading zeros
; blank (as the original's read_stack_arg).
num7:
    lda $6070,x
    sta RW_NUM
    lda $6071,x
    sta RW_NUM+1
    lda $6072,x
    sta RW_NUM+2
    ldy #0
    sty ZP_N                    ; a digit was shown
@digit:
    ldx #0
@sub:
    lda RW_NUM
    sec
    sbc pow7_lo,y
    sta ZP_PTR
    lda RW_NUM+1
    sbc pow7_mid,y
    sta ZP_PTR+1
    lda RW_NUM+2
    sbc pow7_hi,y
    bcc @emit
    sta RW_NUM+2
    lda ZP_PTR+1
    sta RW_NUM+1
    lda ZP_PTR
    sta RW_NUM
    inx
    bne @sub
@emit:
    txa
    ora ZP_N
    bne @show
    lda #T_BLANK
    bne @put
@show:
    sta ZP_N
    txa
@put:
    sta RW_DIG,y
    iny
    cpy #6
    bne @digit
    lda RW_NUM
    sta RW_DIG+6
    rts
pow7_lo:                        ; 1000000, 100000, 10000, 1000, 100, 10
    .db $40, $A0, $10, $E8, $64, $0A
pow7_mid:
    .db $42, $86, $27, $03, $00, $00
pow7_hi:
    .db $0F, $01, $00, $00, $00, $00

; The window's last row pair (rows 10-11) is queued: row 11 again with the
; experience, row 12 the bottom border, and row 12's cells at columns
; 18-19 P0, in the same flush.  The ppu_addr shadow is row 11 at the
; window's left column.
reward_tail:
    ldx #RW_EXP
    jsr num7
    ldx vram_queue_write
    lda ppu_addr_hi_shadow
    sta $0400,x
    inx
    lda ppu_addr_lo_shadow
    sta $0400,x
    inx
    lda #12
    sta $0400,x
    inx
    lda #T_LSIDE
    sta $0400,x
    inx
    lda #T_BLANK
    sta $0400,x
    inx
    sta $0400,x
    inx
    ldy #0
@d:
    lda RW_DIG,y
    sta $0400,x
    inx
    iny
    cpy #7
    bne @d
    lda #T_BLANK
    sta $0400,x
    inx
    lda #T_RSIDE
    sta $0400,x
    inx
    lda ppu_addr_lo_shadow      ; row 12
    clc
    adc #$20
    sta ZP_T
    lda ppu_addr_hi_shadow
    adc #0
    sta $0400,x
    inx
    lda ZP_T
    sta $0400,x
    inx
    lda #12
    sta $0400,x
    inx
    lda #T_BL
    sta $0400,x
    inx
    ldy #10
    lda #T_BOT
@b:
    sta $0400,x
    inx
    dey
    bne @b
    lda #T_BR
    sta $0400,x
    inx
    lda #>RW_ROW12_AT
    sta $0400,x
    inx
    lda #<RW_ROW12_AT
    sta $0400,x
    inx
    lda #1
    sta $0400,x
    inx
    lda #RW_ROW12_V
    sta $0400,x
    inx
    lda #0
    sta $0400,x
    stx vram_queue_write
    rts

; ======================================================================
; The battle messages' kanji slots (2026-11-13, the user's design; the
; message engine calls these through call_ui).  Slot s = tiles $80 + 4s (kanji.inc
; SL_*): before the win 9-23 (the command kanji 17-23 last), from the win
; 6-31 (0-5: the reward window's).  The slot table knows the kanji in each
; slot (messages' and the UI's own uploads), so a kanji already in a slot
; is not uploaded again.  No zero page here: the text engine's state is
; live around these calls.
; ======================================================================

; ----------------------------------------------------------------------
; UIF_PCHOOSE: a page needing up to KANJI_M2 slots (its kanji, 3 per
; runtime name; kanji already in a slot need none, but count).  V clear:
; enough of this phase's slots are free beside the lines still on screen
; and the windows (the window scrolls on); V set: the caller clears the
; window (the lines no longer count).
; ----------------------------------------------------------------------
ui_pchoose:
    jsr sl_check
    inc SL_CLK                  ; a new page (the slots' age)
    jsr scan_lines
    ldy #0                      ; the phase's base mask: before the win
    lda UI_BATTLE
    bpl @b
    ldy #4                      ; from the win
@b:
    sty UI_PS2
    jsr pc_base
    jsr pc_or_lines
    jsr pc_or_gf
    jsr pc_count
    bcs @fits
    ldy UI_PS2                  ; fallback: the window is cleared
    jsr pc_base
    jsr pc_or_gf
    jsr pc_set
    ldx #3
    lda #0
@clr:
    sta UI_PML,x
    dex
    bpl @clr
    bit pc_v40                  ; V set: fallback
    rts
@fits:
    jsr pc_set
    clv
    rts
pc_v40:
    .db $40

; UI_PMT = base mask Y: 0 before the win (slots 9-23), 4 from it (6-31).
pc_base:
    ldx #0
@b:
    lda pc_masks,y
    sta UI_PMT,x
    iny
    inx
    cpx #4
    bne @b
    rts
pc_masks:
    .db $FF, $80, $00, $FF
    .db $FC, $00, $00, $00

pc_or_lines:
    ldx #3
@l:
    lda UI_PML,x
    ora UI_PMT,x
    sta UI_PMT,x
    dex
    bpl @l
    rts

; UI_PMT += every battle-screen group a window on screen shows or the window
; being drawn uses (the prisoner window beside the message, mostly).
pc_or_gf:
    lda UI_BATTLE
    beq @rts
    ldx #NGROUPS-1
@g:
    lda UI_GF,x
    and #GF_REF|GF_NREF
    beq @n
    stx UI_PS0
    lda pt_byte+9,x
    tay
    lda pt_bit+9,x
    ora UI_PMT,y
    sta UI_PMT,y
    ldx UI_PS0
@n:
    dex
    bpl @g
@rts:
    rts

; C set when UI_PMT leaves at least KANJI_M2 slots free.
pc_count:
    lda #0
    sta UI_PS1
    ldx #3
@byte:
    lda UI_PMT,x
    and #$0F
    tay
    lda pc_z4,y
    clc
    adc UI_PS1
    sta UI_PS1
    lda UI_PMT,x
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda pc_z4,y
    clc
    adc UI_PS1
    sta UI_PS1
    dex
    bpl @byte
    lda UI_PS1
    cmp KANJI_M2
    rts
pc_z4:                          ; clear bits of a nibble
    .db 4,3,3,2,3,2,2,1,3,2,2,1,2,1,1,0

; KANJI_PMASK = UI_PMT.
pc_set:
    ldx #3
@s:
    lda UI_PMT,x
    sta KANJI_PMASK,x
    dex
    bpl @s
    rts

; UI_PML = the slots of every kanji in the message window's lines, read
; from the bottom rows (a kanji's bottom tiles t+1, t+3 name its slot; no
; line end is there): all four lines at text_line 0 (a new window: the
; last window's lines may still be shown) and from 3 on, else lines 0 to
; text_line; per row the window's 20 cells (frame and 18 text cells; bytes
; 20-23 are never shown, and other code's row buffers leave tiles there).
; A, X, Y clobbered.
scan_lines:
    ldx #3
    lda #0
@z:
    sta UI_PML,x
    dex
    bpl @z
    ldx text_line
    cpx #4
    bcc @lines
    ldx #3
@lines:
    lda pc_scan_lines,x
    sta UI_PS1                  ; lines to read
    ldx #$18                    ; line 0's bottom row
@line:
    lda #20
    sta UI_PS2
@cell:
    lda $0300,x
    bpl @cnext                  ; (kana and frame tiles: fast)
    lsr a                       ; tile $80-$FF -> slot 0-31
    lsr a
    and #$1F
    tay
    lda pt_bit,y
    sta UI_PS0
    lda pt_byte,y
    tay
    lda UI_PS0
    ora UI_PML,y
    sta UI_PML,y
@cnext:
    inx
    dec UI_PS2
    bne @cell
    txa
    clc
    adc #$30-20                 ; the next line's bottom row
    tax
    dec UI_PS1
    bne @line
    rts
pc_scan_lines:                  ; by text_line (0 and 3 up: all four)
    .db 4, 2, 3, 4

; C set when the window being drawn opens beside the message window
; (UI_SHOWCHK) and the message may show group X (UI_PML: the lines at the
; last pool_choose and every slot placed since).  X kept, A and Y
; clobbered.
grp_shown:
    lda UI_SHOWCHK
    beq @no
    lda pt_byte+9,x
    tay
    lda UI_PML,y
    and pt_bit+9,x
    beq @no
    sec
    rts
@no:
    clc
    rts

; The slot table empty (no kanji known in any slot), marked this build's.
sl_check:
    lda UI_SLV
    cmp #SL_MAGIC
    beq sl_rts
sl_clear:
    ldx #31
    lda #$FF
@c:
    sta SL_HI,x
    dex
    bpl @c
    lda #SL_MAGIC
    sta UI_SLV
sl_rts:
    rts

; Slot s: its mask byte and bit.
pt_byte:
    .db 0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1, 2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3
pt_bit:
    .db $80,$40,$20,$10,$08,$04,$02,$01, $80,$40,$20,$10,$08,$04,$02,$01
    .db $80,$40,$20,$10,$08,$04,$02,$01, $80,$40,$20,$10,$08,$04,$02,$01

; ----------------------------------------------------------------------
; UIF_PTILES: the kanji KANJI_CODE_LO/HI on this page -> KANJI_TILES: the
; slot holding it already (V set: no upload), else the free slot unused
; longest (V clear: upload it; the slot table and, for a battle-screen
; group, UI_SLOT $FE note it).  Tiles t..t+3 in 8x16 order (t TL, t+1 BL,
; t+2 TR, t+3 BR; KANJI_TILES is in the glyph's order: t, t+2, t+1, t+3).
; The slot counts as shown from now on (UI_PML, KANJI_PMASK).
; ----------------------------------------------------------------------
ui_ptiles:
    jsr sl_check
    ldx #31
@find:
    lda SL_LO,x
    cmp KANJI_CODE_LO
    bne @fn
    lda SL_HI,x
    cmp KANJI_CODE_HI
    beq @hit
@fn:
    dex
    bpl @find
    lda UI_BATTLE
    bmi @won
    lda #9                      ; before the win: slots 9-16, then the
    ldy #16                     ; command kanji's 17-23
    jsr lru_slot
    bcc @new
    lda #17
    ldy #23
    jsr lru_slot
    bcc @new
    ldx #9                      ; (none free: not reached, pool_choose made
    bne @new                    ; room)
@won:
    lda #6
    ldy #31
    jsr lru_slot
    bcc @new
    ldx #6
@new:
    lda KANJI_CODE_LO
    sta SL_LO,x
    lda KANJI_CODE_HI
    sta SL_HI,x
    cpx #9
    bcc @nogrp
    lda #$FE                    ; a battle-screen group: a message kanji,
    sta UI_SLOT-9,x             ; maybe shown
@nogrp:
    lda #0
    beq @mark
@hit:
    lda #$40
@mark:
    sta UI_PS2
    lda SL_CLK
    sta SL_AGE,x
    ldy pt_byte,x
    lda pt_bit,x
    ora UI_PML,y
    sta UI_PML,y
    lda pt_bit,x
    ora KANJI_PMASK,y
    sta KANJI_PMASK,y
    txa
    asl a
    asl a
    ora #$80
    sta KANJI_TILES             ; TL t
    ora #1
    sta KANJI_TILES+2           ; BL t+1
    and #$FC
    ora #2
    sta KANJI_TILES+1           ; TR t+2
    ora #1
    sta KANJI_TILES+3           ; BR t+3
    bit UI_PS2                  ; V: in its slot already
    rts

; A = first slot, Y = last: X = the slot of A-Y the page may take
; (KANJI_PMASK clear) that was used longest ago (an empty one at once), C
; clear; C set: none.
lru_slot:
    sta UI_PS0
    sty UI_PS1
    lda #$FF
    sta UI_PS2                  ; the best so far: none
    lda #0
    sta KANJI_M0                ; its age
@l:
    ldx UI_PS0
    ldy pt_byte,x
    lda KANJI_PMASK,y
    and pt_bit,x
    bne @n
    lda SL_HI,x
    cmp #$FF
    beq @empty
    lda SL_CLK
    sec
    sbc SL_AGE,x
    cmp KANJI_M0
    bcc @n
    beq @n
    sta KANJI_M0
    stx UI_PS2
@n:
    inc UI_PS0
    lda UI_PS1
    cmp UI_PS0
    bcs @l
    ldx UI_PS2
    cpx #$FF                    ; C set: none
    rts
@empty:
    clc
    rts

; ----------------------------------------------------------------------
; UIF_RWLOAD (the first victory message, kanji_msg message_setup): the
; reward kanji KANJI_M2 (ui_reward_g) to slot RW_SLOT + KANJI_M2 through
; the VRAM queue; the message engine waits a frame after each (the NMI flushes
; it).  The slot table notes its text code.  ZP_PTR and ZP_T are the game's
; here: kept.
; ----------------------------------------------------------------------
ui_rwload:
    jsr sl_check
    lda ZP_PTR
    pha
    lda ZP_PTR+1
    pha
    lda ZP_T
    pha
    ldx KANJI_M2
    jsr rw_slot_glyph
    pla
    sta ZP_T
    pla
    sta ZP_PTR+1
    pla
    sta ZP_PTR
    rts

; Reward kanji X to its slot: the slot table, then the four tiles queued.
rw_slot_glyph:
    lda ui_reward_g,x
    pha
    tay
    lda ui_gcode_lo,y
    sta SL_LO+RW_SLOT,x
    lda ui_gcode_hi,y
    sta SL_HI+RW_SLOT,x
    lda SL_CLK
    sta SL_AGE+RW_SLOT,x
    txa
    clc
    adc #RW_SLOT
    asl a
    asl a
    ora #$80
    sta ZP_T
    pla
    jmp q_tiles
