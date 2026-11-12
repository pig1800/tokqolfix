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

; ZP_PTR = ui_glyphs + 32 * A (inline: the battle start's stack is deep).
.macro M_GPTR
    ldx #0
    stx ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    clc
    adc #<ui_glyphs
    sta ZP_PTR
    lda ZP_PTR+1
    adc #>ui_glyphs
    sta ZP_PTR+1
.endm

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
    M_GPTR                      ; (inline: the battle start's stack is
    ldy #0                      ; deep, and the NMI comes on top)
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
    ldx #8
@b:
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    dex
    bne @b
    inc ZP_T
    cpy #32
    bne @tile
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
    sta UI_PEND
    sta UI_WIN
    sta B_MODE
    sta B_Q
    sta UI_PRES
    sta UI_PRES+1
    ldx #POOL_SLOTS-1
    lda #$FF
@mc:
    sta UI_MC_HI,x              ; no message kanji known in the pool
    dex
    bpl @mc
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


; ZP_PTR = ui_glyphs + 32 * A.
glyph_ptr:
    ldx #0
    stx ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    clc
    adc #<ui_glyphs
    sta ZP_PTR
    lda ZP_PTR+1
    adc #>ui_glyphs
    sta ZP_PTR+1
    rts

; ----------------------------------------------------------------------
; Glyph A to plane 0 of group X through the VRAM queue (rendering on):
; four 8-byte entries, 44 bytes, then a flush (WAIT_VBLANK): one glyph per
; NMI (two overran vblank by up to two lines).  UI_SLOT[X] = A.
; ----------------------------------------------------------------------
q_glyph:
    sta UI_SLOT,x
    pha
    cpx #POOL_SLOTS
    bcs @nopool
    lda #$FF
    sta UI_MC_HI,x              ; (no message kanji there any more)
@nopool:
    txa
    asl a
    asl a
    adc #$A4
    sta ZP_T
    pla
    jsr glyph_ptr
    ldy #0
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
    iny
    tya
    and #7
    bne @b
    inc ZP_T
    cpy #32
    bne @tile
    lda #0
    sta $0400,x
    stx vram_queue_write
    inc B_Q
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
grp_safe:
    lda UI_GF,x
    and #GF_NREF
    bne @no
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
    jsr glyph_ptr
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
    ldy #16                     ; the TR quarter's 8 rows
@kb:
    lda (ZP_PTR),y
    sta $0400,x
    inx
    iny
    cpy #24
    bne @kb
    lda #0
    sta $0400,x
    stx vram_queue_write
    lda #1
    sta B_Q
    jmp q_flush
@krts:
    rts

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
; take free groups (need); those among the messages' pool slots are kept
; from the messages after the choice (UI_PRES), as the reward window's.
; Columns 18-19 of rows 14-17 are the battle's P2: P0 while it is open
; (the battle ends after it; rows 12-13 there are P0 already).
; ----------------------------------------------------------------------
wg_prison:
    lda #0
    sta ZP_K
@k:
    ldy ZP_K
    lda ui_prison_g,y
    jsr need
    ldy ZP_K
    lda ui_prison_g,y
    sta ZP_G
    ldx #NGROUPS-1              ; its group (none yet: drawn blank, placed
@f:                             ; at the window's end)
    lda UI_SLOT,x
    cmp ZP_G
    bne @n
    lda UI_GF,x
    and #GF_NREF
    bne @res
@n:
    dex
    bpl @f
    bmi @next
@res:
    cpx #POOL_SLOTS
    bcs @next
    txa                         ; a pool slot: the messages keep off it
    lsr a
    lsr a
    lsr a
    tay
    txa
    and #7
    tax
    lda bit_of,x
    ora UI_PRES,y
    sta UI_PRES,y
@next:
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
; A kanji already in CHR is used from there: a group with its UI glyph
; (8x16 order), or a pool slot a message left it in (UI_MC_LO/HI; the
; message routine's order TL, TR, BL, BR), whose slot the later messages
; then leave alone (UI_PRES).  The rest go to groups 15-22: the command
; window does not come back after a victory.
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
    lda #0
    sta ZP_K
@k:
    ldy ZP_K
    lda ui_reward_g,y
    sta ZP_G
    ldx #NGROUPS-1              ; a group with its UI glyph
@find:
    lda UI_SLOT,x
    cmp ZP_G
    beq @have
    dex
    bpl @find
    ldx #POOL_SLOTS-1           ; a pool slot with it from a message
@pool:
    lda UI_MC_LO,x
    cmp ui_reward_clo,y
    bne @pnext
    lda UI_MC_HI,x
    cmp ui_reward_chi,y
    beq @have
@pnext:
    dex
    bpl @pool
    ldx #15                     ; else a command group
@alloc:
    lda UI_GF,x
    and #GF_NREF
    beq @up
    inx
    cpx #NGROUPS
    bne @alloc
    beq @next                   ; (8 groups for 6 kanji: not reached)
@up:
    jsr set_nref
    lda ZP_G
    jsr q_glyph
    jmp @next
@have:
    jsr set_nref
    cpx #POOL_SLOTS
    bcs @next
    txa                         ; a pool slot: the messages keep off it
    lsr a
    lsr a
    lsr a
    tay
    txa
    and #7
    tax
    lda bit_of,x
    ora UI_PRES,y
    sta UI_PRES,y
@next:
    inc ZP_K
    lda ZP_K
    cmp #RW_N
    bne @k
    rts
bit_of:
    .db $80, $40, $20, $10, $08, $04, $02, $01

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

; Half ZP_J (0 upper, 1 lower) of reward kanji ZP_K at (ZP_A),y; Y += 2.
; This window's group for it (GF_NREF), else blank (not reached).
rw_half:
    sty ZP_X
    ldy ZP_K
    lda ui_reward_g,y
    sta ZP_G
    ldx #NGROUPS-1
@find:
    lda UI_SLOT,x
    cmp ZP_G
    bne @no
    lda UI_GF,x
    and #GF_NREF
    bne @col
@no:
    dex
    bpl @find
    ldx #POOL_SLOTS-1
@pool:
    lda UI_MC_LO,x
    cmp ui_reward_clo,y
    bne @pn
    lda UI_MC_HI,x
    cmp ui_reward_chi,y
    bne @pn
    lda UI_GF,x
    and #GF_NREF
    bne @row
@pn:
    dex
    bpl @pool
    ldy ZP_X
    lda #T_BLANK
    sta (ZP_A),y
    iny
    sta (ZP_A),y
    iny
    rts
@col:                           ; 8x16 order: upper t, t+2; lower t+1, t+3
    txa
    asl a
    asl a
    adc #$A4
    ldy ZP_J
    beq @c0
    adc #1
@c0:
    ldy ZP_X
    sta (ZP_A),y
    iny
    adc #2
    sta (ZP_A),y
    iny
    rts
@row:                           ; the message's order: upper t, t+1; lower
    txa                         ; t+2, t+3
    asl a
    asl a
    adc #$A4
    ldy ZP_J
    beq @r0
    adc #2
@r0:
    ldy ZP_X
    sta (ZP_A),y
    iny
    adc #1
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
