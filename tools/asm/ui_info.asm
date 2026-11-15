; ======================================================================
; The info screen's Left / Right (2026-11-15, the user's request;
; TEXT_RENDERER.md "The info screen's page flip"), included by ui.asm
; after ui_data.inc (ui_info_lo.asm: the parts that map other banks).
;
; Left / Right show the officer before / after: on the map path the party
; order ($6090-$6096, every member the ぶしょう list shows), on the battle
; path the enemy slots 5-9 (actors 7-11) that are still alive ($609C bit
; 7), round in both.  A flip plays the cursor's sound ($09, as the reserve
; list's pages) and does what opening the screen for that officer does
; (compact_items_actor; on the map b14_party_status_update's S.P), then
; writes only what changes:
;   - a page is an image of the 254 cells that depend on the officer (the
;     names, the five stat lines, 兵士数's digits, the six tactic lines,
;     the three equipment lines; IMG) and its glyphs;
;   - the glyphs are cached: a tactic kanji may sit in plane 1 of any of
;     27 groups ($A4-$DC, then $50-$7C), an equipment kanji or 計 in plane
;     0 of any of 22 ($A4-$F8); a glyph already in a group is not sent
;     again, a new one goes to a group the shown page does not use, so
;     nothing on screen changes until the image is written (a group the
;     shown page uses is taken only when no other is left, and then is
;     sent in the image's own window);
;   - the name's kanji go to plane 1 of $10-$1B as the screen's entry puts
;     them (in the image's window: the shown name never changes before);
;   - the portrait's six parts (rows of 6 tiles, $80-$A3) are sent when
;     they differ from the shown ones, with the colours (P3); a portrait
;     with colour 0 shows black, its parts are not sent.
; The data go in "windows": the vblank and the top 32 lines (black on this
; screen) with rendering off, from the vblank flag (NMI off, the flag
; polled) to line 31's hblank, where rendering comes back on for line 32
; (v = $0080: row 4, fine Y 0; the background only for that frame).
; Every step's cycles are fixed, so each window ends with a delay to the
; same point (IS_TARGET cycles after the poll).  Glyph windows first, then
; the image's (with the colours when no part changed), then the
; portrait's (its parts are read from the ROM just before it).  Each
; window's frame runs its NMI work (busy mode: the timers and the sound)
; right after rendering is on.  The preparation runs in busy mode with the
; NMI on (about 22,000 cycles: the first window comes in the vblank of the
; frame that saw the button); the OAM shadow ($0200, every sprite hidden
; on this screen) is its scratch and is hidden again at the end.
; ======================================================================

UPDATE_FRAME   = $C0D5
SOUND_ADD      = $C4D5
COMPACT_ITEMS  = $D5FE          ; compact_items_actor (text_actor)
MUL16_BY_U8    = $C15B
NMI_HANDLER    = $EE79

F_SHOWN     = 1                 ; slot flags: the shown page uses it
F_NEED      = 2                 ;   the new page uses it
F_PEND      = 4                 ;   its glyph is to be sent

; The image (IMG, $0600): rows of cells, each a run on screen (is_commit).
IM_NAME     = IMG+0             ; rows 10-13, columns 1-7 (kana and marks, kanji, ＊)
IM_STAT     = IMG+28            ; rows 4, 6, 8, 10, 12, columns 17-30
IM_TROOP    = IMG+98            ; row 15, columns 8-13
IM_TACT     = IMG+104           ; line n: row 16 + 2n then 17 + 2n, columns 18-24
IM_EQUIP    = IMG+188           ; line k: row 20 + 2k then 21 + 2k, columns 4-14
IMG_N       = 254

; Cycles (from the jsr to the rts's end) of the timed steps: is_window's
; comments have the rest.
IS_C_PART   = 834               ; pt_0 .. pt_5
IS_C_PT0    = 103               ; is_portrait without its parts (one part: + 833)
IS_C_NT     = 2380              ; is_commit
IS_TARGET   = 6004              ; is_window: the poll's exit to the PPUMASK write

; Window capacities in glyphs (is_window: 31 + steps + a delay of 32 or more)
IS_CAP_E    = (IS_TARGET-88)/410        ; glyphs only
IS_CAP_C    = (IS_TARGET-2467)/410      ; with the image
IS_CAP_PC   = (IS_TARGET-2569)/410      ; with the image and the colours
IS_CAP_P6   = (IS_TARGET-190-833*6)     ; (the portrait's window: 6 parts fit)
.if IS_CAP_P6 < 0
    .error "a portrait of 6 parts does not fit in a window"
.endif

; ======================================================================
; UIF_INFO_WAIT: the screen's wait (the original's loc_D44C: A or B ends
; it), with Left / Right.
; ======================================================================
ui_info_wait:
    jsr UPDATE_FRAME
    lda controller_state
    and #$C0
    bne @rts
    lda controller_state
    and #$03
    beq ui_info_wait
    jsr is_flip
    jmp ui_info_wait
@rts:
    rts

; ----------------------------------------------------------------------
; A flip (controller_state: Left $02 / Right $01).  The portrait's parts
; are read after the image's window (the next window, the last, sends
; them): the preparation before the first window stays short enough for
; the vblank of the frame that saw the button.
; ----------------------------------------------------------------------
is_flip:
    jsr is_next
    bcs @rts                    ; nobody else
    pha
    lda #$09                    ; the cursor's sound
    jsr SOUND_ADD
    jsr ppu_begin               ; busy: the NMIs leave the PPU and the OAM shadow
    lda ppu_ctrl_shadow
    and #$FB
    sta IS_CTL                  ; (is_unmap7: the NMI on again)
    pla
    sta text_actor
    jsr COMPACT_ITEMS           ; as the screen's entry does
    lda UI_PATH
    bne @battle
    jsr is_sp
@battle:
    lda #0
    sta IS_INIT
    jsr is_build
    jsr is_plan
    lda ppu_ctrl_shadow
    and #$7B                    ; NMI off, +1
    sta PPUCTRL
    sta IS_CTL                  ; (is_unmap7: it stays off)
    lda #0
    sta IS_W
@win:
    ldx IS_W
    lda WIN_PT,x
    beq @go
    lda WIN_CM,x
    bne @go
    jsr is_parts                ; the portrait's window: its parts now
    ldx IS_W
@go:
    jsr is_window
    inc IS_W
    lda IS_W
    cmp WIN_N
    bne @win
    jsr is_oam
    jmp ppu_end                 ; NMI on (line 32 or so: the flag is clear), busy off
@rts:
    rts

; The changed parts (NPART bit p) into IS_PB + 96 p.
is_parts:
    ldx #0
@p:
    lda NPART
    and part_bit,x
    beq @next
    stx ZP_I
    lda pb_lo,x
    sta ZP_A
    lda pb_hi,x
    sta ZP_A+1
    lda IS_PART,x
    jsr is_prd
    ldx ZP_I
@next:
    inx
    cpx #6
    bne @p
    rts

; ----------------------------------------------------------------------
; is_next: A = the officer before / after text_actor, C clear; C set:
; none.
; ----------------------------------------------------------------------
is_next:
    lda UI_PATH
    bne @enemy
    ldx #6                      ; the map: the party order
@find:
    lda $6090,x
    cmp text_actor
    beq @at
    dex
    bpl @find
    sec
    rts
@at:
    ldy #6
@step:
    jsr @move
    cpx #7
    bcc @in
    ldx #0
@in:
    lda $6090,x
    bpl @got
    dey
    bne @step
    sec
    rts
@enemy:
    ldx text_actor              ; the battle: actors 7-11 alive
    ldy #4
@estep:
    jsr @move
    cpx #12
    bcc @e1
    ldx #7
@e1:
    cpx #7
    bcs @e2
    ldx #11
@e2:
    lda $609C,x
    bmi @egot
    dey
    bne @estep
    sec
    rts
@egot:
    txa
@got:
    clc
    rts
; X one back (Left) or on (Right); the map's -1 wraps to 6 through 255
@move:
    lda controller_state
    and #$02
    beq @on
    dex
    bpl @mrts
    ldx #6
@mrts:
    rts
@on:
    inx
    rts

; ----------------------------------------------------------------------
; is_sp: the map's S.P for text_actor, as b14_party_status_update
; (b14_calc_tactic_points, 0 when 知力 < 武力).
; ----------------------------------------------------------------------
is_sp:
    ldx text_actor
    lda #0
    sta ptr0_hi
    sta ptr1_lo
    lda $61A8,x
    sta ptr0_lo
    lda $61F8
    sta ppu_addr_hi
    jsr MUL16_BY_U8
    lda ptr0_hi
    sec
    sbc $61FE
    bcs @s
    lda #0
@s:
    sta ZP_T
    ldx text_actor
    lda $61A8,x
    cmp $619C,x
    lda ZP_T
    bcs @set
    lda #0
@set:
    sta $61FB
    rts

; ======================================================================
; The first page (ui_info_draw, rendering off, busy): the cache emptied,
; the page built and written whole.
; ======================================================================
is_first:
    lda #$FF
    ldx #IS_NMB+2-IS_P1G
@c:
    sta IS_P1G,x
    dex
    bpl @c
    lda #0
    ldx #IS_SH0+2-IS_DIRTY
@z:
    sta IS_DIRTY,x              ; (IS_DIRTY, IS_SH1, IS_SH0)
    dex
    bpl @z
    lda ppu_ctrl_shadow
    and #$FB
    sta IS_CTL
    lda #1
    sta IS_INIT
    jsr is_build
    jsr is_items
    jsr sh_store
    ldx #0
@g:
    cpx GI_N
    beq @nt
    lda GI_H,x
    sta ZP_GH
    lda GI_L,x
    sta ZP_GL
    lda GI_B,x
    sta ZP_GB
    ldy GI_P,x
    stx ZP_GI
    jsr is_gl
    ldx ZP_GI
    inx
    bne @g
@nt:
    jsr is_commit
    jmp is_oam

; The OAM shadow hidden again (every byte $F8: Y below the screen).
is_oam:
    lda #$F8
    ldx #0
@o:
    sta $0200,x
    inx
    bne @o
    rts

; ======================================================================
; is_build: text_actor's page: the record, the image, the glyphs' slots
; (those the shown page uses kept: IS_SH1 / IS_SH0), the portrait.
; ======================================================================
is_build:
    ldx text_actor
    lda $60A8,x
    sta IS_OFF
    jsr is_rec
    lda #T_BLANK
    ldx #IMG_N
@b:
    sta IMG-1,x
    dex
    bne @b
    jsr im_name
    jsr im_stats
    jsr im_troops
    ; the slot flags: F_SHOWN from the bits (FL0 follows FL1, IS_SH0
    ; follows IS_SH1: one pass, a byte of bits a slot group of 8)
    ldy #0
    ldx #0
@f8:
    lda #$01
    sta ZP_J
@f:
    lda sh_src,x
    and ZP_J
    beq @s
    lda #F_SHOWN
@s:
    sta FL1,y
    iny
    cpy #P1_N+P0_N
    beq @fe
    cpy #P1_N
    beq @fx                     ; (plane 0's bits start a byte)
    asl ZP_J
    bcc @f
    inx
    bne @f8                     ; (always)
@fx:
    ldx #4
    bne @f8                     ; (always)
@fe:
    jsr is_collect              ; the page's glyphs: VL_*, their slots if cached
    jsr is_assign               ; the others: slots
    jsr im_glyphs
    jmp is_port

; IS_SH1 (4 bytes) and IS_SH0 (3): slot 8b + k is bit k ($01 << k) of
; byte b; IS_SH0 follows IS_SH1.
sh_src = IS_SH1
.if IS_SH0 != IS_SH1+4
    .error "is_build / sh_store: IS_SH0 must follow IS_SH1"
.endif

; ----------------------------------------------------------------------
; The names: the kana (record $14-$19) in row 11 from column 2, the marks
; above (as the game's text engine draws them); the kanji (the name
; table) in rows 12-13 from column 2, glyph k at $10 + 4k (the screen's
; entry puts them there, $A9 = $10); ＊ at row 13, column 1 for a member
; whose $609C bit 7 is clear (the screen's entry draws it).
; ----------------------------------------------------------------------
im_name:
    ldx #0
@k:
    lda IS_REC+10,x
    cmp #$FE
    bcs @kanji
    stx ZP_I
    jsr kana_cell
    ldx ZP_I
    sta IM_NAME+8,x
    tya
    sta IM_NAME+1,x
    inx
    cpx #6
    bne @k
@kanji:
    lda #0
    sta NM_N
    lda IS_OFF
    cmp #UI_NAME_RECORDS
    bcs @star
    ldy #0
@j:
    sty ZP_I
    ldx IS_OFF
    jsr nm_code
    cpy #$FF
    beq @star
    ldx ZP_I
    sta NMP_T,x
    tya
    ora #STORE_8K
    sta NMB_T,x
    inc NM_N
    txa
    asl a
    tay                         ; column 2 + 2k
    asl a
    adc #$10                    ; (C clear) the glyph's first tile
    sta IM_NAME+15,y
    adc #1
    sta IM_NAME+22,y
    adc #1
    sta IM_NAME+16,y
    adc #1
    sta IM_NAME+23,y
    ldy ZP_I
    iny
    cpy #3
    bne @j
@star:
    ldx text_actor
    lda $609C,x
    bmi @rts
    lda #$0E
    sta IM_NAME+21
@rts:
    rts

; A = a kana's game code: A = its cell, Y = the cell above (its voicing
; mark or blank), as the text engine (ui.asm buf_kana's rule).
kana_cell:
    ldy #T_BLANK
    cmp #$80
    bcc @r
    and #$7F
    ldy #T_DAK
    cmp #$62
    bcc @r
    sbc #$0A
    ldy #T_HANDAK
@r:
    rts

; ----------------------------------------------------------------------
; The five stat lines (b14_wincb_stat_value_bar's values): 3 digits at
; columns 17-19, a blank, then from column 21 a bar of $F4 per 26 points
; and $F3 for a remainder of 13 or more.
; ----------------------------------------------------------------------
im_stats:
    lda #0
    sta ZP_I
@s:
    lda ZP_I
    jsr stat_value
    sta ZP_V
    ldx ZP_I
    lda st_ofs,x
    tax
    lda ZP_V
    jsr im_num3
    inx                         ; column 20
    lda ZP_V
@bar:
    cmp #26
    bcc @rem
    sbc #26
    tay
    lda #T_FULL
    sta IMG,x
    inx
    tya
    jmp @bar
@rem:
    cmp #13
    bcc @end
    lda #T_HALF
    sta IMG,x
@end:
    inc ZP_I
    lda ZP_I
    cmp #5
    bne @s
    rts
st_ofs:
    .db IM_STAT-IMG, IM_STAT-IMG+14, IM_STAT-IMG+28, IM_STAT-IMG+42, IM_STAT-IMG+56

; A = 0-255: three digits to IMG + X on (X += 3), leading zeros blank.
im_num3:
    ldy #0
@h:
    cmp #100
    bcc @hd
    sbc #100
    iny
    bne @h
@hd:
    sta ZP_K
    lda #0
    sta ZP_J                    ; a digit was shown
    tya
    jsr @digit
    lda ZP_K
    ldy #0
@t:
    cmp #10
    bcc @td
    sbc #10
    iny
    bne @t
@td:
    sta ZP_K
    tya
    jsr @digit
    lda ZP_K
    sta IMG,x
    inx
    rts
@digit:
    ora ZP_J
    beq @blank
    sta ZP_J
    tya
    sta IMG,x
    inx
    rts
@blank:
    lda #T_BLANK
    sta IMG,x
    inx
    rts

; 兵士数's digits: text_actor's 24-bit troop maximum ($6160 + 4 * actor)
; as 6 digits, leading zeros blank.
im_troops:
    lda text_actor
    asl a
    asl a
    tax
    lda $6160,x
    sta ZP_V
    lda $6161,x
    sta ZP_V+1
    lda $6162,x
    sta ZP_V+2
    lda #0
    sta ZP_J
    ldx #IM_TROOP-IMG
    ldy #0
@digit:
    lda #0
    sta ZP_K
@sub:
    lda ZP_V
    sec
    sbc pow_lo,y
    sta ZP_PTR
    lda ZP_V+1
    sbc pow_mid,y
    sta ZP_PTR+1
    lda ZP_V+2
    sbc pow_hi,y
    bcc @emit
    sta ZP_V+2
    lda ZP_PTR+1
    sta ZP_V+1
    lda ZP_PTR
    sta ZP_V
    inc ZP_K
    bne @sub
@emit:
    lda ZP_K
    ora ZP_J
    bne @show
    lda #T_BLANK
    bne @put
@show:
    sta ZP_J
    lda ZP_K
@put:
    sta IMG,x
    inx
    iny
    cpy #5
    bne @digit
    lda ZP_V
    sta IMG,x
    rts

; ----------------------------------------------------------------------
; The glyph passes.  is_collect: text_actor's glyphs in the order the
; image takes them (VL_G: 計 when a tactic line shows, each line's two
; kanji, the equipment's kanji; VL_P: the pool, 1 plane 1), each one's
; slot when the cache has it (F_NEED set), else $FF (VL_S).  is_assign:
; a slot for each of those (one for a glyph that comes twice).
; ----------------------------------------------------------------------
is_collect:
    lda text_actor
    sta ZP_K
    lda #0
    sta VL_N
    sta ZP_I                    ; 計: a line shows?
@any:
    jsr tact_of
    bcc @kei
    inc ZP_I
    lda ZP_I
    cmp #6
    bne @any
    beq @tact                   ; (none)
@kei:
    lda #UI_G_KEI
    ldx #0
    jsr vl_add
@tact:
    lda #0
    sta ZP_I
@t:
    jsr tact_of
    bcs @tn
    lda ZP_T
    ldx #1
    jsr vl_add
    lda ZP_C
    ldx #1
    jsr vl_add
@tn:
    inc ZP_I
    lda ZP_I
    cmp #6
    bne @t
    jsr eq_first
@item:
    bcs @rts
@tok:
    jsr eq_tok                  ; C set: the item's end; V set: kana
    bcs @inext
    bvs @tok
    ldx #0
    jsr vl_add
    jmp @tok
@inext:
    jsr eq_next
    jmp @item
@rts:
    rts

; Glyph A of pool X into the list, with its slot if cached.
vl_add:
    ldy VL_N
    sta VL_G,y
    sta ZP_G
    txa
    sta VL_P,y
    jsr is_pool
    jsr is_find
    lda #$FF
    bcs @miss
    lda (BP_F),y
    ora #F_NEED
    sta (BP_F),y
    tya
@miss:
    ldy VL_N
    sta VL_S,y
    inc VL_N
    rts

is_assign:
    ldy #0
@v:
    cpy VL_N
    beq @rts
    lda VL_S,y
    cmp #$FF
    bne @next
    sty ZP_X
    lda VL_P,y
    tax
    jsr is_pool
    ldy ZP_X
    lda VL_G,y
    sta ZP_G
    jsr is_find                 ; (given a slot a moment ago: it came twice)
    bcc @set
    jsr is_alloc
    lda ZP_G
    sta (BP_C),y
    lda (BP_F),y
    ora #F_NEED|F_PEND
    sta (BP_F),y
@set:
    tya
    ldy ZP_X
    sta VL_S,y
@next:
    iny
    bne @v
@rts:
    rts

; X = pool (0 plane 0, 1 plane 1): select it.
is_pool:
    txa
    beq @p0
    jmp is_p1
@p0:
    jmp is_p0

; Line ZP_I (0-5) of actor ZP_K: C clear and ZP_T / ZP_C = its two kanji
; (UI glyphs), or C set: none (the screen's rule: tactic $65A0[6 * actor
; + n], 0 none, no kanji pair none, no list past 127).
tact_of:
    lda ZP_K
    asl a
    sta ZP_T
    asl a
    adc ZP_T                    ; 6 * actor
    clc
    adc ZP_I
    bmi @no
    tay
    lda $65A0,y
    beq @no
    tay
    lda ui_tactic_g1,y
    cmp #$FF
    beq @no
    sta ZP_T
    lda ui_tactic_g2,y
    sta ZP_C
    clc
    rts
@no:
    sec
    rts

; The equipment of actor ZP_K: the first 3 of its 8 slots ($6100 + 8 *
; actor) with bit 7 (equipped).  eq_first / eq_next: C clear and ZP_PTR =
; the item's name (ui_item: UI glyphs, $FE kana, $FF end), IS_TOK = 0;
; C set: no more.  eq_tok: the next token: C set: the end; V set: a kana
; (A its code); else A = a kanji's UI glyph.
eq_first:
    lda #0
    sta IS_EQN                  ; items so far
    sta IS_EQS                  ; next slot
eq_scan:
    lda IS_EQN
    cmp #3
    bcs @none
@s:
    lda IS_EQS
    cmp #8
    bcs @none
    inc IS_EQS
    lda ZP_K
    asl a
    asl a
    asl a
    adc IS_EQS
    tay
    lda $6100-1,y
    bpl @s
    and #$7F
    tay
    lda ui_item_lo,y
    sta ZP_PTR
    lda ui_item_hi,y
    sta ZP_PTR+1
    lda #0
    sta IS_TOK
    clc
    rts
@none:
    sec
    rts
eq_next:
    inc IS_EQN
    jmp eq_scan
eq_tok:
    ldy IS_TOK
    lda (ZP_PTR),y
    cmp #$FF
    beq @end
    iny
    cmp #$FE
    bne @kanji
    lda (ZP_PTR),y
    iny
    sty IS_TOK
    bit is_v40                  ; V set
    clc
    rts
@kanji:
    sty IS_TOK
    clv
    clc
    rts
@end:
    sec
    rts
is_v40:
    .db $40

; The pools: is_p1 (plane 1, the tactics), is_p0 (plane 0, equipment, 計).
is_p1:
    lda #<FL1
    sta BP_F
    lda #>FL1
    sta BP_F+1
    lda #<IS_P1G
    sta BP_C
    lda #>IS_P1G
    sta BP_C+1
    lda #P1_N
    sta BP_N
    rts
is_p0:
    lda #<FL0
    sta BP_F
    lda #>FL0
    sta BP_F+1
    lda #<IS_P0G
    sta BP_C
    lda #>IS_P0G
    sta BP_C+1
    lda #P0_N
    sta BP_N
    rts

; ZP_G's slot in the pool: C clear, Y = the slot; C set: none.
is_find:
    lda ZP_G
    ldy BP_N
    cpy #P1_N
    bne @p0
    dey
@f1:
    cmp IS_P1G,y
    beq @hit
    dey
    bpl @f1
    sec
    rts
@p0:
    dey
@f0:
    cmp IS_P0G,y
    beq @hit
    dey
    bpl @f0
    sec
    rts
@hit:
    clc
    rts

; Y = a slot for a new glyph: one never used, else one neither page uses,
; else one only the shown page uses (sent in the image's window).  One
; pass; ZP_N, ZP_T lost.
is_alloc:
    lda #$FF
    sta ZP_N                    ; the first that neither page uses
    sta ZP_T                    ; the first that only the shown page uses
    ldy #0
@a:
    lda (BP_F),y
    and #F_NEED|F_SHOWN
    bne @used
    lda (BP_C),y
    cmp #$FF
    beq @rts                    ; never used: this one
    lda ZP_N
    bpl @n
    sty ZP_N
    bmi @n                      ; (always: Y < 128)
@used:
    and #F_NEED
    bne @n
    lda ZP_T
    bpl @n
    sty ZP_T
@n:
    iny
    cpy BP_N
    bne @a
    ldy ZP_N
    bpl @rts
    ldy ZP_T                    ; (one there is: 13 of 22 at most)
@rts:
    rts

; Tile of slot Y: plane 1: $A4 + 4i (i < 15), $50 + 4(i - 15); plane 0:
; $A4 + 4j.  A = the tile; C clear.
p1_tile:
    tya
    asl a
    asl a
    cpy #15
    bcs @lo
    adc #$A4                    ; (C clear)
    rts
@lo:
    clc
    adc #$14
    rts
p0_tile:
    tya
    asl a
    asl a
    adc #$A4                    ; (C clear)
    rts

; ----------------------------------------------------------------------
; im_glyphs: the tactic lines and the equipment lines into the image,
; the glyphs' slots from VL_S in is_collect's order.
; ----------------------------------------------------------------------
im_glyphs:
    lda text_actor
    sta ZP_K
    lda #0
    sta IS_VI                   ; the list's next
    sta ZP_I
@any:
    jsr tact_of                 ; 計 first when a line shows
    bcc @kei
    inc ZP_I
    lda ZP_I
    cmp #6
    bne @any
    beq @eq
@kei:
    jsr vl_tile
    sta ZP_N
    lda #0
    sta ZP_I
@t:
    jsr tact_of
    bcs @tn
    ldx ZP_I
    lda tl_ofs,x
    sta IS_EQX
    jsr vl_tile
    ldx IS_EQX
    ldy #0
    jsr im_kanji
    jsr vl_tile
    ldx IS_EQX
    ldy #2
    jsr im_kanji
    lda #T_NO
    sta IM_TACT+11,x
    lda ZP_N
    ldy #5
    jsr im_kanji
@tn:
    inc ZP_I
    lda ZP_I
    cmp #6
    bne @t
@eq:
    jsr eq_first
@item:
    bcs @rts
    ldx IS_EQN
    lda el_ofs,x
    sta IS_EQX                  ; the line's top-row cell
    lda #0
    sta IS_EQC                  ; column 0-10
@tok:
    jsr eq_tok
    bcs @inext
    bvs @kana
    jsr vl_tile                 ; (taken even with no room: the list's order)
    ldx IS_EQC
    cpx #10
    bcs @tok                    ; (no room: 11 columns)
    pha
    lda IS_EQX
    clc
    adc IS_EQC
    tax
    pla
    sta IMG,x
    adc #1
    sta IMG+11,x
    adc #1
    sta IMG+1,x
    adc #1
    sta IMG+12,x
    inc IS_EQC
    inc IS_EQC
    jmp @tok
@kana:
    ldx IS_EQC
    cpx #11
    bcs @tok
    jsr kana_cell
    pha
    lda IS_EQX
    clc
    adc IS_EQC
    tax
    pla
    sta IMG+11,x
    tya
    sta IMG,x
    inc IS_EQC
    jmp @tok
@inext:
    jsr eq_next
    jmp @item
@rts:
    rts
tl_ofs:
    .db 0, 14, 28, 42, 56, 70
el_ofs:
    .db IM_EQUIP-IMG, IM_EQUIP-IMG+22, IM_EQUIP-IMG+44

; The list's next glyph: A = its tile (C clear).  X lost, Y kept.
vl_tile:
    sty ZP_J
    ldx IS_VI
    inc IS_VI
    ldy VL_S,x
    lda VL_P,x
    beq @p0
    jsr p1_tile
    ldy ZP_J
    rts
@p0:
    jsr p0_tile
    ldy ZP_J
    rts

; Tile A's 16x16 cells at IM_TACT + X + Y (top row) and + 7 (bottom).
im_kanji:
    sty ZP_J
    pha
    txa
    clc
    adc ZP_J
    tay
    pla
    sta IM_TACT,y
    adc #1                      ; (C clear)
    sta IM_TACT+7,y
    adc #1
    sta IM_TACT+1,y
    adc #1
    sta IM_TACT+8,y
    rts

; ----------------------------------------------------------------------
; is_port: the portrait.  The first page: the screen's entry loaded it
; (text_load_page): its parts and colour noted.  A flip: the parts that
; differ from the shown ones (NPART bit p; is_parts reads them before
; their window), the colours into $03ED-$03EF; IS_PTF set when they must
; be sent.  Colour 0 shows the portrait black (P3 all $0F): no part then.
; ----------------------------------------------------------------------
is_port:
    lda #0
    sta NPART
    sta NPN
    sta IS_PTF
    lda IS_REC+6
    and #$0F
    sta IS_CI
    lda IS_INIT
    beq @flip
    ldx #5
@i:
    lda IS_REC,x
    sta IS_PART,x
    dex
    bpl @i
    lda IS_CI
    sta IS_COL
    rts
@flip:
    lda IS_CI
    beq @col
    ldx #0
@p:
    lda IS_REC,x
    cmp IS_PART,x
    beq @same
    sta IS_PART,x
    lda NPART
    ora part_bit,x
    sta NPART
    inc NPN
@same:
    inx
    cpx #6
    bne @p
@col:
    ldx IS_CI
    beq @black
    lda #$37
    sta $03ED
    lda #$26
    sta $03EE
    lda PORTRAIT_COL,x
    sta $03EF
    bne @cmp
@black:
    lda #$0F
    sta $03ED
    sta $03EE
    sta $03EF
@cmp:
    lda NPART
    bne @send
    lda IS_CI
    cmp IS_COL
    beq @rts
@send:
    lda IS_CI
    sta IS_COL
    inc IS_PTF
@rts:
    rts
pb_lo:
    .db <(IS_PB+0), <(IS_PB+96), <(IS_PB+192), <(IS_PB+288), <(IS_PB+384), <(IS_PB+480)
pb_hi:
    .db >(IS_PB+0), >(IS_PB+96), >(IS_PB+192), >(IS_PB+288), >(IS_PB+384), >(IS_PB+480)
part_bit:
    .db $01, $02, $04, $08, $10, $20

; ======================================================================
; is_items: the glyphs to send, as items (GI_*): those for a slot the
; shown page does not use, then those for one it uses, then the name's
; changed kanji.  N_MAND = the last two kinds (the image's window takes
; them).  A plane-1 slot of $50-$7C sent marks it in IS_DIRTY (the battle
; exit streams a battle name there again).
; ======================================================================
is_items:
    lda #0
    sta GI_N
    lda #F_PEND
    jsr @kind
    lda GI_N
    sta ZP_X                    ; (the safe ones)
    lda #F_PEND|F_SHOWN
    jsr @kind
    ; the name's kanji (plane 1 of $10 + 4k), when they differ
    ldy #0
@nm:
    cpy NM_N
    beq @nmend
    lda NMB_T,y
    cmp IS_NMB,y
    bne @nmnew
    lda NMP_T,y
    cmp IS_NMP,y
    beq @nmnext
@nmnew:
    ldx GI_N
    lda NMB_T,y
    sta IS_NMB,y
    sta GI_B,x
    lda NMP_T,y
    sta IS_NMP,y
    sta GI_P,x
    lda #$11
    sta GI_H,x
    tya
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a                       ; 64 k
    ora #$08                    ; plane 1 of $10 + 4k: $1108 + 64k
    sta GI_L,x
    inc GI_N
@nmnext:
    iny
    bne @nm
@nmend:
    lda GI_N
    sec
    sbc ZP_X
    sta N_MAND
    rts
; every slot whose flags & (F_PEND | F_SHOWN) = A: P1 then P0
@kind:
    sta ZP_C
    ldy #0
@k1:
    lda FL1,y
    and #F_PEND|F_SHOWN
    cmp ZP_C
    bne @n1
    jsr p1_tile
    sec                         ; plane 1
    ldx IS_P1G,y
    jsr @add
    cpy #15
    bcc @n1
    tya
    sbc #15                     ; (C set) $50 + 4j: IS_DIRTY bit j
    tax
    cpx #8
    bcs @d1
    lda bit_tab,x
    ora IS_DIRTY
    sta IS_DIRTY
    bne @n1
@d1:
    lda bit_tab-8,x
    ora IS_DIRTY+1
    sta IS_DIRTY+1
@n1:
    iny
    cpy #P1_N
    bne @k1
    ldy #0
@k0:
    lda FL0,y
    and #F_PEND|F_SHOWN
    cmp ZP_C
    bne @n0
    jsr p0_tile
    clc                         ; plane 0
    ldx IS_P0G,y
    jsr @add
@n0:
    iny
    cpy #P0_N
    bne @k0
    rts
; tile A (C: plane 1), UI glyph X: an item.  Y kept.
@add:
    sty ZP_J
    php
    pha
    ldy GI_N
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta GI_H,y
    pla
    asl a
    asl a
    asl a
    asl a
    plp
    bcc @p0
    ora #$08
@p0:
    sta GI_L,y
    lda ui_gcode_lo,x
    sta GI_P,y
    lda ui_gcode_hi,x
    ora #STORE_8K
    sta GI_B,y
    inc GI_N
    ldy ZP_J
    rts

; ======================================================================
; is_plan: the windows.  The image's window takes the items' end (the
; name's kanji and the glyphs for slots the shown page uses: N_MAND) and
; as many others as fit, and the colours when no part changed; the
; portrait's window (its parts, read by is_flip just before) comes last;
; the other glyphs fill the windows before, from the back.
; ======================================================================
is_plan:
    jsr is_items
    jsr sh_store
    lda #0
    sta IS_PC                   ; the colours alone, in the image's window
    lda IS_PTF
    beq @cap
    lda NPN
    bne @cap
    inc IS_PC
@cap:
    lda #IS_CAP_C
    ldx IS_PC
    beq @c0
    lda #IS_CAP_PC
@c0:
    cmp GI_N
    bcc @c
    lda GI_N
@c:
    sta IS_CL                   ; the image's window's glyphs
    lda GI_N
    sec
    sbc IS_CL
    sta IS_R                    ; left for the windows before
    lda #0
    sta WIN_N
    sta IS_GS                   ; the next item
    lda IS_R
    beq @lw
    ; the first window takes what is over a multiple of IS_CAP_E
@m:
    cmp #IS_CAP_E+1
    bcc @first
    sbc #IS_CAP_E
    bne @m                      ; (always: A > IS_CAP_E)
@first:
    jsr @plain
@more:
    lda IS_R
    beq @lw
    lda #IS_CAP_E
    jsr @plain
    jmp @more
@lw:
    lda IS_CL
    ldx IS_PC
    ldy #1                      ; the image
    jsr @win
    lda IS_PTF
    beq @rts
    lda NPN
    beq @rts
    lda #0
    ldx #1                      ; the portrait
    ldy #0
    jmp @win
@rts:
    rts
; a window of A glyphs only (IS_R -= A)
@plain:
    pha
    eor #$FF
    sec
    adc IS_R
    sta IS_R
    pla
    ldx #0
    ldy #0
; a window of A glyphs, X = portrait, Y = image: its delay
@win:
    stx IS_WP
    sty IS_WC
    ldx WIN_N
    sta ZP_N
    lda IS_WP
    sta WIN_PT,x
    lda IS_WC
    sta WIN_CM,x
    lda IS_GS
    sta WIN_GS,x
    clc
    adc ZP_N
    sta WIN_GE,x
    sta IS_GS
    ; D = IS_TARGET - 31 - portrait - glyphs - image
    lda #<(IS_TARGET-31)
    sta ZP_V
    lda #>(IS_TARGET-31)
    sta ZP_V+1
    lda IS_WP
    beq @np
    lda #<(2+IS_C_PT0)
    jsr @sub
    lda IS_WC
    bne @gl                     ; (the image's window: the colours alone)
    ldy NPN
    beq @gl
@pp:
    lda #<(IS_C_PART-1)
    ldx #>(IS_C_PART-1)
    jsr @subx
    dey
    bne @pp
    beq @gl
@np:
    lda #3
    jsr @sub
@gl:
    ldy ZP_N
    bne @gn
    lda #21
    jsr @sub
    jmp @im
@gn:
    lda #19
    jsr @sub
@gg:
    lda #<410
    ldx #>410
    jsr @subx
    dey
    bne @gg
@im:
    lda IS_WC
    beq @ni
    lda #<(2+IS_C_NT)
    ldx #>(2+IS_C_NT)
    jsr @subx
    jmp @dl
@ni:
    lda #3
    jsr @sub
@dl:
    ; is_delay: 256 DH + 25 + 5 Q + R, Q >= 1, R = 2-6: with E = D - 32,
    ; DH = E >> 8, Q = 1 + (E & $FF) / 5, R = 2 + (E & $FF) mod 5
    lda #32
    jsr @sub
    ldx WIN_N
    lda ZP_V+1
    sta WIN_DH,x
    lda ZP_V
    ldy #1
@q:
    cmp #5
    bcc @qr
    sbc #5
    iny
    bne @q
@qr:
    sty ZP_J
    tay
    lda rv_tab,y
    sta WIN_RV,x
    lda ZP_J
    sta WIN_DQ,x
    inc WIN_N
    rts
@sub:
    ldx #0
@subx:
    sta ZP_T
    lda ZP_V
    sec
    sbc ZP_T
    sta ZP_V
    txa
    eor #$FF
    adc ZP_V+1                  ; (C: the borrow) high - X
    sta ZP_V+1
    rts

; IS_SH1 / IS_SH0 = the slots this page uses (F_NEED): the next flip's
; shown page.
sh_store:
    lda #0
    ldx #6
@z:
    sta IS_SH1,x                ; (IS_SH1, IS_SH0)
    dex
    bpl @z
    ldy #0
    ldx #0
@b8:
    lda #$01
    sta ZP_J
@b:
    lda FL1,y                   ; (FL0 follows)
    and #F_NEED
    beq @n
    lda sh_src,x
    ora ZP_J
    sta sh_src,x
@n:
    iny
    cpy #P1_N+P0_N
    beq @rts
    cpy #P1_N
    beq @bx
    asl ZP_J
    bcc @b
    inx
    bne @b8                     ; (always)
@bx:
    ldx #4
    bne @b8                     ; (always)
@rts:
    rts

rv_tab:
    .db <is_r2, <is_r3, <is_r4, <is_r5, <is_r6

; ======================================================================
; is_window: window X.  Before: rendering on, the NMI off.  The vblank
; flag polled; rendering off for the vblank and lines 0-31 (black: the
; screen's rows 0-3 are blank, the backdrop $0F); the portrait (the
; colours first, in the vblank proper), the glyphs, the image; a delay;
; rendering on in line 31's hblank with v at row 4 ($0080); then the frame's NMI
; work (busy: no PPU).  Cycles from the poll's exit to the PPUMASK write
; (its last cycle): 31 + (portrait: 2 + IS_C_PT0 + 833 n, else 3) +
; is_glyphs (21, or 410 n + 19) + (image: 2 + IS_C_NT, else 3) + the
; delay = IS_TARGET.
; ======================================================================
.if ($ & $FF) + 130 > $100   ; (is_window: no page crossed, its cycles fixed)
    .pad ($ & $FF00) + $100
.endif
is_window:
    lda WIN_DH,x
    sta ZP_DH
    lda WIN_DQ,x
    sta ZP_DQ
    lda WIN_RV,x
    sta ZP_RV
    lda #>is_r2
    sta ZP_RV+1
    lda WIN_GS,x
    sta ZP_GI
    lda WIN_GE,x
    sta ZP_GE
    lda WIN_PT,x
    sta ZP_PT
    lda WIN_CM,x
    sta ZP_CM
    lda ppu_mask_shadow         ; the background only for this frame: the OAM
    and #$EF                    ; got no DMA (the NMI's) and the shadow is
    sta ZP_MK                   ; scratch; the next real NMI writes the mask
    sei
    bit PPUSTATUS               ; (the flag cleared: the next vblank's start)
@sync:
    bit PPUSTATUS
    bpl @sync
@t0:
    lda #0                      ; 2  line 241
    sta PPUMASK                 ; 4
    lda ZP_PT                   ; 3
    beq @np                     ; 2 / 3
@b1:
    jsr is_portrait
@np:
    jsr is_glyphs
    lda ZP_CM                   ; 3
    beq @nc                     ; 2 / 3
@b2:
    jsr is_commit
@nc:
    jsr is_delay
    lda #$00                    ; 2  (v's bits 12-14 are fine Y: $0080
    sta PPUADDR                 ; 4  fetches from $2080, fine Y 0; $2080
    lda #$80                    ; 2  would be fine Y 2)
    sta PPUADDR                 ; 4  v = row 4, column 0, fine Y 0
    lda ZP_MK                   ; 3
    sta PPUMASK                 ; 4  line 31, dots 257-320
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL               ; t: scroll 0 at the next frame's start
    lda ppu_ctrl_shadow
    and #$7F                    ; (the NMI still off)
    sta PPUCTRL
    cli
    lda #>@back                 ; the frame's NMI, as if it came now
    pha
    lda #<@back
    pha
    php
    sei
    jmp NMI_HANDLER
@back:
    rts
.if >@sync != >@t0 || >@b1 != >@np || >@b2 != >@nc
    .error "is_window's timed branches cross a page"
.endif

; The portrait: P3's colours, then the parts in NPART.
.if ($ & $FF) + 80 > $100   ; (is_portrait: no page crossed, its cycles fixed)
    .pad ($ & $FF00) + $100
.endif
is_portrait:                    ; 6
    lda #$3F                    ; 2
    sta PPUADDR                 ; 4
    lda #$0D                    ; 2
    sta PPUADDR                 ; 4
    lda $03ED                   ; 4
    sta PPUDATA                 ; 4
    lda $03EE                   ; 4
    sta PPUDATA                 ; 4
    lda $03EF                   ; 4
    sta PPUDATA                 ; 4
    lda NPART                   ; 4
    sta ZP_PM                   ; 3  (49)
    lsr ZP_PM                   ; 5 a part: 5 + (2 + IS_C_PART, else 3)
    bcc @1
    jsr pt_0
@1:
    lsr ZP_PM
    bcc @2
    jsr pt_1
@2:
    lsr ZP_PM
    bcc @3
    jsr pt_2
@3:
    lsr ZP_PM
    bcc @4
    jsr pt_3
@4:
    lsr ZP_PM
    bcc @5
    jsr pt_4
@5:
    lsr ZP_PM
    bcc @6
    jsr pt_5
@6:
    rts                         ; 6: 103 + 833 n
is_portrait_end:
.if >is_portrait != >is_portrait_end
    .error "is_portrait's branches cross a page"
.endif

; Part p: 96 bytes from IS_PB + 96 p to CHR $1800 + 96 p (tiles $80 +
; 6p); 32 a chunk: chunk c is IS_PB + 32 c, page $79 / $7A / $7B.
.macro IS_PT addr, c0, c1, c2
    lda #>addr
    sta PPUADDR
    lda #<addr
    sta PPUADDR
    ldx #<(IS_PB+32*c0)
    jsr is_cp79+IS_CPN*((IS_PB+32*c0)/256-$79)
    ldx #<(IS_PB+32*c1)
    jsr is_cp79+IS_CPN*((IS_PB+32*c1)/256-$79)
    ldx #<(IS_PB+32*c2)
    jsr is_cp79+IS_CPN*((IS_PB+32*c2)/256-$79)
    rts
.endm
pt_0:
    IS_PT $1800, 0, 1, 2
pt_1:
    IS_PT $1860, 3, 4, 5
pt_2:
    IS_PT $18C0, 6, 7, 8
pt_3:
    IS_PT $1920, 9, 10, 11
pt_4:
    IS_PT $1980, 12, 13, 14
pt_5:
    IS_PT $19E0, 15, 16, 17
; 32 bytes from page $79 / $7A / $7B + X (no page crossed: X + 31 < 256);
; the three are IS_CPN bytes long (pt_0-pt_5 call them by address)
IS_CPN      = 32*6+1
is_cp79:
IS_CK = $7900
.rept 32
    lda IS_CK,x
    sta PPUDATA
IS_CK = IS_CK + 1
.endr
    rts
is_cp7A:
IS_CK = $7A00
.rept 32
    lda IS_CK,x
    sta PPUDATA
IS_CK = IS_CK + 1
.endr
    rts
is_cp7B:
IS_CK = $7B00
.rept 32
    lda IS_CK,x
    sta PPUDATA
IS_CK = IS_CK + 1
.endr
    rts
.if IS_PB != $79A0
    .error "pt_0-pt_5 assume IS_PB = $79A0 (chunks in pages $79-$7B)"
.endif
.if is_cp7A-is_cp79 != IS_CPN || is_cp7B-is_cp7A != IS_CPN
    .error "is_cp79 / 7A / 7B: not IS_CPN bytes each"
.endif

; Glyph items ZP_GI .. ZP_GE - 1 (is_gl each).
.if ($ & $FF) + 40 > $100   ; (is_glyphs: no page crossed, its cycles fixed)
    .pad ($ & $FF00) + $100
.endif
is_glyphs:                      ; 6
    ldx ZP_GI                   ; 3
    cpx ZP_GE                   ; 3
    beq @done                   ; 2 / 3
@g:
    lda GI_H,x                  ; 4
    sta ZP_GH                   ; 3
    lda GI_L,x                  ; 4
    sta ZP_GL                   ; 3
    lda GI_B,x                  ; 4
    sta ZP_GB                   ; 3
    ldy GI_P,x                  ; 4
    stx ZP_GI                   ; 3
    jsr is_gl                   ; IS_C_GL
    ldx ZP_GI                   ; 3
    inx                         ; 2
    cpx ZP_GE                   ; 3
    bne @g                      ; 3 / 2
@done:
    rts                         ; 6: 21, or 410 n + 19
is_glyphs_end:
.if >is_glyphs != >is_glyphs_end
    .error "is_glyphs' branches cross a page"
.endif
.if IS_C_GL != 371
    .error "is_plan counts 410 cycles a glyph (IS_C_GL 371)"
.endif

; The image (IS_C_NT cycles).
.macro IS_ADDR addr
    lda #>addr
    sta PPUADDR
    lda #<addr
    sta PPUADDR
.endm
is_commit:
    IS_ADDR $2141          ; the names: rows 10-13, columns 1-7
IS_K = 0
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2161
IS_K = 7
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2181
IS_K = 14
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $21A1
IS_K = 21
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2091        ; the stats: rows 4-12, columns 17-30
IS_K = 28
.rept 14
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $20D1
IS_K = 42
.rept 14
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2111
IS_K = 56
.rept 14
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2151
IS_K = 70
.rept 14
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2191
IS_K = 84
.rept 14
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $21E8         ; 兵士数: row 15, columns 8-13
IS_K = 98
.rept 6
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2212        ; the tactics: rows 16-27, columns 18-24
IS_K = 104
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2232
IS_K = 111
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2252
IS_K = 118
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2272
IS_K = 125
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2292
IS_K = 132
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $22B2
IS_K = 139
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $22D2
IS_K = 146
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $22F2
IS_K = 153
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2312
IS_K = 160
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2332
IS_K = 167
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2352
IS_K = 174
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2372
IS_K = 181
.rept 7
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2284       ; the equipment: rows 20-25, columns 4-14
IS_K = 188
.rept 11
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $22A4
IS_K = 199
.rept 11
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $22C4
IS_K = 210
.rept 11
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $22E4
IS_K = 221
.rept 11
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2304
IS_K = 232
.rept 11
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    IS_ADDR $2324
IS_K = 243
.rept 11
    lda IMG+IS_K
    sta PPUDATA
IS_K = IS_K + 1
.endr
    rts
.if IS_K != IMG_N
    .error "is_commit: the runs do not cover the image"
.endif

; is_delay: 256 ZP_DH + 25 + 5 ZP_DQ + R cycles from the jsr to the
; rts's end (ZP_DQ = 1-52, R = 2-6: the routine at ZP_RV).
.if ($ & $FF) + 48 > $100   ; (is_delay: no page crossed, its cycles fixed)
    .pad ($ & $FF00) + $100
.endif
is_delay:                       ; 6
    lda ZP_DH                   ; 3
    beq @lo                     ; 2 / 3
@blk:
    ldx #48                     ; 2
@b1:
    dex                         ; 2
    bne @b1                     ; 3 / 2: 239
    nop                         ; 2
    nop                         ; 2
    cmp ZP_DH                   ; 3
    dec ZP_DH                   ; 5
    bne @blk                    ; 3 / 2: 256 a block, 255 the last
    nop                         ; 2
@lo:
    ldx ZP_DQ                   ; 3
@l1:
    dex                         ; 2
    bne @l1                     ; 3 / 2: 5 Q - 1
    jmp (ZP_RV)                 ; 5
is_r2:
    nop
    rts
is_r3:
    cmp ZP_DH
    rts
is_r4:
    nop
    nop
    rts
is_r5:
    nop
    cmp ZP_DH
    rts
is_r6:
    cmp ZP_DH
    cmp ZP_DH
    rts
is_delay_end:
.if >is_delay != >is_delay_end
    .error "is_delay crosses a page (its branches and ZP_RV's page)"
.endif
