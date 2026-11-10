; ======================================================================
; UI bank (step B, INFO_SCREEN.md): bank-switch-free kanji on the officer
; info screen.  PRG bank UI_BANK, assembled for $8000; the fixed bank's
; call_ui maps it (game lock protocol) and calls $8000 with X = function.
;
; The info screen (b14_officer_info_screen) calls UIF_INFO_DRAW right after
; battle_intro_screen, while rendering is still off: this bank uploads the
; kanji and writes the whole layout with direct PPU access (nmi_busy set,
; as the game's own copy_to_vram), then the game draws the portrait and the
; two name windows.  No CHR register is switched while the screen is shown
; and no scanline IRQ runs (decision 13).
;
; CHR (decisions 3, 5, 11; tile order t, t+1, t+2, t+3 = TL, BL, TR, BR):
;   plane 1 of $10-$1B  the name (the original engine, $A9 = $10)
;   plane 1 of $1C-$4F  13 label kanji, slot k at $1C + 4k
;   plane 1 of $50-$7F  tactic line n: first kanji $50 + 8n, second $54 + 8n
;   plane 0 of $A4-$DF  15 groups: the equipment kanji and 計 (P0 cells),
;                       one group per distinct kanji
;   $E0-$FE             the bank-9 block, every glyph in plane 1 (bars, S.P)
; The battle path (UIF_BINFO_ENTER / _EXIT around the screen) saves plane 1
; of $1C-$7F and plane 0 of $A4-$DF to spare CHR RAM first and puts them
; back afterwards, so every battle name and the pool are as they were.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

; Zero-page scratch: the game's per-call temporaries $00-$0F.  The UI
; functions run on the main thread between game calls and never yield.
ZP_PTR      = $00           ; 2: glyph / string / table pointer
ZP_T        = $02           ; tile
ZP_C        = $03           ; bit 7: restore (chr_copy) / plane 1 (put_glyph)
ZP_N        = $04           ; count
ZP_G        = $05           ; glyph / tactic id
ZP_A        = $06           ; 2: PPU address (line top row, spare CHR)
ZP_V        = $08           ; 3: number
ZP_I        = $0B           ; line / stat index
ZP_J        = $0C
ZP_K        = $0D
ZP_X        = $0E           ; line buffer length

; RAM scratch (call_inline_block's $0600 page: free between game calls)
LBUF_T      = $0600         ; line buffer, top row
LBUF_B      = $0620         ; line buffer, bottom row
UI_NG       = $0640         ; plane-0 groups used on this screen
UI_GMAP     = $0641         ; 15: glyph in each plane-0 group
CBUF        = $0650         ; 8: CHR copy buffer

T_BLANK     = $0A
T_NO        = $23           ; の
T_DAK       = $72           ; ゛
T_HANDAK    = $73           ; ゜
T_FULL      = $F4           ; bar, 26 points
T_HALF      = $F3           ; bar, 13 points
LABEL_TILE  = $1C
TACT_TILE   = $50
POOL_GROUPS = 15

.base $8000
.org $8000
    jmp ui_dispatch

ui_dispatch:
    txa
    asl a
    tay
    lda ui_fns+1,y
    pha
    lda ui_fns,y
    pha
    rts
ui_fns:
    .dw ui_info_draw-1, ui_binfo_enter-1, ui_binfo_exit-1, ui_army-1
    .dw ui_info_late-1

; ======================================================================
; UIF_BINFO_ENTER: the battle wrapper, before the info screen (rendering
; on).  Battle path flag, text_busy = 0 (the wrapper's own store), the
; battle's P2 colours 1-3 (decision 6: the exit puts all three back).
; ======================================================================
ui_binfo_enter:
    lda #1
    sta UI_PATH
    lda #0
    sta text_busy
    ldx #2
@p2:
    lda $03E9,x
    sta UI_P2,x
    dex
    bpl @p2
    rts

; ======================================================================
; UIF_BINFO_EXIT: the battle wrapper, after the info screen (rendering off:
; ppu_bg_sprites_off).  The battle's CHR and P2 colours back; the pool is
; unchecked (the next battle message checks it again).
; ======================================================================
ui_binfo_exit:
    lda UI_PATH
    beq @p2x
    jsr ppu_begin
    sec
    jsr chr_save_restore
    jsr ppu_end
@p2x:
    ldx #2
@p2:
    lda UI_P2,x
    sta $03E9,x
    dex
    bpl @p2
    lda #0
    sta UI_PATH
    ; fall through
pool_unchecked:
    lda KANJI_WIN_COL
    and #<~(WINCOL_POOL_OK|WINCOL_CHECKED)
    sta KANJI_WIN_COL
    rts

; ======================================================================
; UIF_ARMY: the army status screen (Select on the map), in place of its
; "jsr wait_vblank" after the attribute string (busy mode, rendering off).
; Flush the queue as that call did, then set the cells of SP (row 20) and
; MSP (row 22), columns 22-25, to P1: S, P and M are plane 1 (decision 11).
; ======================================================================
ui_army:
    jsr WAIT_VBLANK             ; busy mode: flushes the queue directly
    jsr ppu_begin
    lda #$23
    sta PPUADDR
    lda #$ED
    sta PPUADDR
    lda #$44                    ; $23ED: rows 20-23, columns 22-23
    sta PPUDATA
    lda #$11                    ; $23EE: rows 20-23, columns 24-25
    sta PPUDATA
    jmp ppu_end

; ======================================================================
; Direct PPU access on the main thread: busy mode (the NMI leaves the PPU
; alone, as for the game's copy_to_vram), no IRQ, the scene page for BG
; tiles $00-$7F, +1 increment.
; ======================================================================
ppu_begin:
    lda nmi_busy
    sta UI_BUSY
    lda #1
    sta nmi_busy
    sta MMC3_IRQ_OFF
    lda #MMC3_R0
    sta MMC3_SEL
    sta MMC3_SELECT
    lda #CHR_SCENE_LO
    sta MMC3_DATA
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL
    lda PPUSTATUS
    rts

ppu_end:
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda UI_BUSY
    sta nmi_busy
    rts

; A = select ($80 | register), X = 1 KiB CHR bank (main-thread protocol).
set_chr:
    sta MMC3_SEL
    sta MMC3_SELECT
    stx MMC3_DATA
    rts

; ======================================================================
; The battle's CHR around the info screen: C clear = save, C set =
; restore.  Plane 1 of $1C-$7F (the battle names beyond the info screen's
; own name) <-> spare $0000-$031F, plane 0 of $A4-$DF (the pool) <-> spare
; $0400-$05DF, with sprite banks R2/R3 = CHR_SPARE/+1 meanwhile.
; ======================================================================
chr_save_restore:
    ror ZP_C
    lda #$82
    ldx #CHR_SPARE
    jsr set_chr
    lda #$83
    ldx #CHR_SPARE+1
    jsr set_chr
    lda #$1C
    ldx #$00
    ldy #100
    jsr @region8
    lda #$A4
    ldx #$04
    ldy #60
    jsr @region0
    lda #$82
    ldx #0
    jsr set_chr
    lda #$83
    ldx #1
    jmp set_chr
@region8:
    pha
    lda #8
    bne @region
@region0:
    pha
    lda #0
@region:
    sta ZP_K                    ; plane offset
    pla
    sta ZP_T
    stx ZP_A+1
    lda #0
    sta ZP_A
    sty ZP_N
@tile:
    jsr tile_addr               ; ZP_PTR = CHR address of ZP_T, plane ZP_K
    bit ZP_C
    bmi @back
    ldx ZP_PTR+1
    ldy ZP_PTR
    jsr read8
    ldx ZP_A+1
    ldy ZP_A
    jsr write8
    jmp @next
@back:
    ldx ZP_A+1
    ldy ZP_A
    jsr read8
    ldx ZP_PTR+1
    ldy ZP_PTR
    jsr write8
@next:
    lda ZP_A
    clc
    adc #8
    sta ZP_A
    bcc @nc
    inc ZP_A+1
@nc:
    inc ZP_T
    dec ZP_N
    bne @tile
    rts

; ZP_PTR = $1000 + 16 * ZP_T + ZP_K
tile_addr:
    lda ZP_T
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta ZP_PTR+1
    lda ZP_T
    asl a
    asl a
    asl a
    asl a
    ora ZP_K
    sta ZP_PTR
    rts

; X:Y = PPU address: 8 bytes to CBUF / from CBUF.
read8:
    stx PPUADDR
    sty PPUADDR
    lda PPUDATA                 ; the read buffer's stale byte
    ldx #0
@r:
    lda PPUDATA
    sta CBUF,x
    inx
    cpx #8
    bne @r
    rts
write8:
    stx PPUADDR
    sty PPUADDR
    ldx #0
@w:
    lda CBUF,x
    sta PPUDATA
    inx
    cpx #8
    bne @w
    rts

; ======================================================================
; Glyph A to tiles X..X+3.  C set: plane 1 only (plane 0, the kana, is
; kept).  C clear: plane 0, and plane 1 cleared.
; ======================================================================
put_glyph:
    ror ZP_C
    stx ZP_T
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
    ldy #0
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
    bit ZP_C
    bpl @p0
    ora #8
@p0:
    sta PPUADDR
    ldx #8
@b:
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    dex
    bne @b
    bit ZP_C
    bmi @next
    lda #0
    ldx #8
@z:
    sta PPUDATA
    dex
    bne @z
@next:
    inc ZP_T
    cpy #32
    bne @tile
    rts

; ======================================================================
; A = glyph: its plane-0 group on this screen (uploaded on first use).
; Returns A = the group's first tile.  Groups $A4, $A8, ... $DC.
; ======================================================================
pool_glyph:
    sta ZP_G
    ldx #0
@find:
    cpx UI_NG
    beq @new
    lda UI_GMAP,x
    cmp ZP_G
    beq @have
    inx
    bne @find
@new:
    cpx #POOL_GROUPS
    bcs @full
    lda ZP_G
    sta UI_GMAP,x
    inc UI_NG
    txa
    pha
    asl a
    asl a
    adc #$A4
    tax
    lda ZP_G
    clc
    jsr put_glyph
    pla
    tax
@have:
    txa
    asl a
    asl a
    adc #$A4
    rts
@full:
    lda #$FF                    ; no room (cannot happen: at most 10)
    rts

; ======================================================================
; Static runs: hi, lo, ctl (bits 0-5 count, bit 6 one byte repeated, bit 7
; vertical), data; $FF ends.  ZP_PTR = the runs.
; ======================================================================
write_runs:
    ldy #0
@run:
    lda (ZP_PTR),y
    cmp #$FF
    beq @done
    sta PPUADDR
    iny
    lda (ZP_PTR),y
    sta PPUADDR
    iny
    lda (ZP_PTR),y
    iny
    sta ZP_C
    and #$3F
    sta ZP_N
    lda ppu_ctrl_shadow
    and #$FB
    bit ZP_C
    bpl @inc1
    ora #$04
@inc1:
    sta PPUCTRL
    bit ZP_C
    bvs @fill
@copy:
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    dec ZP_N
    bne @copy
    beq @run
@fill:
    lda (ZP_PTR),y
    iny
@rep:
    sta PPUDATA
    dec ZP_N
    bne @rep
    beq @run
@done:
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL
    rts

; Write the line buffers: LBUF_T[0..ZP_X) at ZP_A, LBUF_B below it.
write_line:
    lda ZP_A+1
    sta PPUADDR
    lda ZP_A
    sta PPUADDR
    ldx #0
@t:
    cpx ZP_X
    beq @bot
    lda LBUF_T,x
    sta PPUDATA
    inx
    bne @t
@bot:
    lda ZP_A
    clc
    adc #$20
    tay
    lda ZP_A+1
    adc #0
    sta PPUADDR
    sty PPUADDR
    ldx #0
@b:
    cpx ZP_X
    beq @done
    lda LBUF_B,x
    sta PPUDATA
    inx
    bne @b
@done:
    rts

; Line buffers: put kanji group A (16x16, tiles A..A+3) at ZP_X.
buf_kanji:
    ldx ZP_X
    sta LBUF_T,x
    clc
    adc #1
    sta LBUF_B,x
    adc #1
    sta LBUF_T+1,x
    adc #1
    sta LBUF_B+1,x
    inx
    inx
    stx ZP_X
    rts

; Line buffers: kana game code A at ZP_X (in the lower row, its voicing
; mark above it, as the game's text engine draws it).
buf_kana:
    ldx ZP_X
    ldy #T_BLANK
    cmp #$80
    bcc @plain
    and #$7F
    ldy #T_DAK
    cmp #$62
    bcc @plain
    sbc #$0A
    ldy #T_HANDAK
@plain:
    sta LBUF_B,x
    tya
    sta LBUF_T,x
    inc ZP_X
    rts

; ======================================================================
; UIF_INFO_DRAW: the info screen after battle_intro_screen (rendering
; off).  Everything but the portrait and the two name windows.
; ======================================================================
ui_info_draw:
    jsr ppu_begin
    ; The hack's state for a screen without a band: no band, no pending
    ; pool check (load_text_graphics posted one for set 8), the pool
    ; unchecked (this screen writes it).
    lda #0
    sta KANJI_BAND
    lda KANJI_CODE_HI
    cmp #POOL_CHECK_CODE
    bne @nocheck
    lda KANJI_REQ
    cmp #REQ_UPLOAD
    bne @nocheck
    lda #REQ_NONE
    sta KANJI_REQ
@nocheck:
    jsr pool_unchecked
    lda UI_PATH
    beq @nosave
    clc
    jsr chr_save_restore        ; the battle's CHR to the spare page
@nosave:
    ; the 13 label kanji, plane 1 of $1C-$4F
    lda #0
    sta ZP_I
@label:
    lda ZP_I
    asl a
    asl a
    adc #LABEL_TILE
    tax
    lda ZP_I
    sec
    jsr put_glyph
    inc ZP_I
    lda ZP_I
    cmp #13
    bne @label
    ; the static layout and the attributes
    lda #<info_runs
    sta ZP_PTR
    lda #>info_runs
    sta ZP_PTR+1
    jsr write_runs
    lda #$23
    sta PPUADDR
    lda #$C0
    sta PPUADDR
    ldx #0
@attr:
    lda ui_info_attr,x
    sta PPUDATA
    inx
    cpx #64
    bne @attr
    jsr draw_stats
    lda #0
    sta UI_NG
    jsr draw_tactics
    jsr draw_equipment
    jmp ppu_end

; ----------------------------------------------------------------------
; The five stat lines (b14_wincb_stat_value_bar's values): 3 digits at
; column 16 of the line's lower row, a blank, then a bar of $F4 per 26
; points and $F3 for a remainder of 13 or more.
; ----------------------------------------------------------------------
draw_stats:
    lda #0
    sta ZP_I
@stat:
    lda ZP_I
    jsr stat_value
    sta ZP_V
    lda #0
    sta ZP_X
    lda ZP_V
    jsr buf_num3
    ldx ZP_X
    lda #T_BLANK
    sta LBUF_B,x
    inx
    lda ZP_V
@bar:
    cmp #26
    bcc @rem
    sbc #26
    pha
    lda #T_FULL
    sta LBUF_B,x
    inx
    pla
    jmp @bar
@rem:
    cmp #13
    bcc @end
    lda #T_HALF
    sta LBUF_B,x
    inx
@end:
    stx ZP_X
    ldx ZP_I
    lda stat_hi,x
    sta PPUADDR
    lda stat_lo,x
    sta PPUADDR
    ldx #0
@w:
    lda LBUF_B,x
    sta PPUDATA
    inx
    cpx ZP_X
    bne @w
    inc ZP_I
    lda ZP_I
    cmp #5
    bne @stat
    rts

; Digits at column 16 of rows 5, 7, 9, 11 (the kanji lines' lower rows)
; and 12 (S.P).
stat_lo:
    .db $B0, $F0, $30, $70, $90
stat_hi:
    .db $20, $20, $21, $21, $21

; A = stat 0-4: ぶりょく, ちりょく, こうげき, ぶそうど, S.P of text_actor.
stat_value:
    ldx text_actor
    cmp #1
    bcc @s0
    beq @s1
    cmp #3
    bcc @s2
    beq @s3
    ldy #0                      ; S.P: $61FB (the party), $61FC (actors 7+)
    cpx #7
    bcc @sp
    iny
@sp:
    lda $61FB,y
    rts
@s0:
    lda $619C,x
    rts
@s1:
    lda $61A8,x
    rts
@s2:
    ldy $60C0,x
    lda ui_atk_table,y
    rts
@s3:
    lda $60B4,x
    rts

; A = 0-255: three digits into LBUF_B at ZP_X, leading zeros blank.
buf_num3:
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
    ldx ZP_X
    sta LBUF_B,x
    inc ZP_X
    rts
@digit:
    ldx ZP_X
    ora ZP_J
    beq @blank
    sta ZP_J
    tya
    sta LBUF_B,x
    inc ZP_X
    rts
@blank:
    lda #T_BLANK
    sta LBUF_B,x
    inc ZP_X
    rts

; ======================================================================
; UIF_INFO_LATE: after the name windows (rendering on).  The kanji name's
; window clears rows 14-15 at columns 2-9 (its second line), so 兵士数 and
; the troop maximum are queued here, as the original's window $2D came
; after it: rows 14-15, columns 2-7, the digits in row 15 from column 8.
; ======================================================================
ui_info_late:
    jsr troops_digits
    ldx vram_queue_write
    ldy #0
@hdr:
    lda late_runs,y
    sta $0400,x
    inx
    iny
    cpy #9                      ; $21C2, 6 tiles: the top row
    bne @hdr
@hdr2:
    lda late_runs,y
    sta $0400,x
    inx
    iny
    cpy #18                     ; $21E2, 12 tiles: the bottom row ...
    bne @hdr2
    ldy #0
@dig:
    lda LBUF_B,y                ; ... and the 6 digits
    sta $0400,x
    inx
    iny
    cpy #6
    bne @dig
    lda #0
    sta $0400,x
    stx vram_queue_write
    rts
late_runs:
    .db $21,$C2,6,  $38,$3A,$3C,$3E,$40,$42
    .db $21,$E2,12, $39,$3B,$3D,$3F,$41,$43

; ----------------------------------------------------------------------
; へいしすう: text_actor's 24-bit troop maximum ($6160 + 4 * actor, low
; byte first) as 6 digits, leading zeros blank, into LBUF_B[0..6).
; ----------------------------------------------------------------------
troops_digits:
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
    sta ZP_X
    sta ZP_J                    ; a digit was shown
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
    ldx ZP_X
    lda ZP_K
    ora ZP_J
    bne @show
    lda #T_BLANK
    bne @put
@show:
    sta ZP_J
    lda ZP_K
@put:
    sta LBUF_B,x
    inc ZP_X
    iny
    cpy #5
    bne @digit
    ldx ZP_X
    lda ZP_V
    sta LBUF_B,x
    rts

pow_lo:                         ; 100000, 10000, 1000, 100, 10
    .db $A0, $10, $E8, $64, $0A
pow_mid:
    .db $86, $27, $03, $00, $00
pow_hi:
    .db $01, $00, $00, $00, $00

; ----------------------------------------------------------------------
; さくりゃく: line n (0-5) shows tactic $65A0[6 * actor + n] (0: none) as
; its two plane-1 kanji ($50 + 8n, $54 + 8n), の and the plane-0 計, at
; rows 16 + 2n / 17 + 2n from column 18.
; ----------------------------------------------------------------------
draw_tactics:
    lda text_actor
    asl a
    sta ZP_J
    asl a
    adc ZP_J
    sta ZP_J                    ; 6 * actor
    lda #0
    sta ZP_I
@line:
    lda ZP_J
    clc
    adc ZP_I
    bmi @next                   ; (the original's other list; no actor here)
    tay
    lda $65A0,y
    beq @next
    sta ZP_G
    tay
    lda ui_tactic_g1,y
    cmp #$FF
    beq @next
    ; plane-1 kanji
    lda ZP_I
    asl a
    asl a
    asl a
    adc #TACT_TILE
    tax
    lda ui_tactic_g1,y
    sec
    jsr put_glyph
    lda ZP_I
    asl a
    asl a
    asl a
    adc #TACT_TILE+4
    tax
    ldy ZP_G
    lda ui_tactic_g2,y
    sec
    jsr put_glyph
    ; the line
    lda #0
    sta ZP_X
    lda ZP_I
    asl a
    asl a
    asl a
    adc #TACT_TILE
    pha
    jsr buf_kanji
    pla
    adc #4
    jsr buf_kanji
    lda #T_NO
    jsr buf_kana
    lda #UI_G_KEI
    jsr pool_glyph
    jsr buf_kanji
    ldx ZP_I
    lda tact_lo,x
    sta ZP_A
    lda tact_hi,x
    sta ZP_A+1
    jsr write_line
@next:
    inc ZP_I
    lda ZP_I
    cmp #6
    bne @line
    rts

; Row 16 + 2n, column 18.
tact_lo:
    .db $12, $52, $92, $D2, $12, $52
tact_hi:
    .db $22, $22, $22, $22, $23, $23

; ----------------------------------------------------------------------
; そうび: line k (0-2) shows the k-th equipped item (bit 7) of the actor's
; 8 slots ($6100 + 8 * actor): its kanji name (plane-0 groups), kana in the
; lower row, at rows 20 + 2k / 21 + 2k from column 4.
; ----------------------------------------------------------------------
draw_equipment:
    lda #0
    sta ZP_I                    ; line
    sta ZP_K                    ; slot
@scan:
    lda ZP_K
    cmp #8
    bcs @done
    lda text_actor
    asl a
    asl a
    asl a
    adc ZP_K
    tay
    inc ZP_K
    lda $6100,y
    bpl @scan
    and #$7F
    tay
    lda ui_item_lo,y
    sta ZP_A
    lda ui_item_hi,y
    sta ZP_A+1
    lda #0
    sta ZP_X
    sta ZP_N                    ; string index
@tok:
    ldy ZP_N
    lda (ZP_A),y
    cmp #$FF
    beq @line
    inc ZP_N
    cmp #$FE
    bne @kanji
    iny
    inc ZP_N
    lda (ZP_A),y
    jsr buf_kana
    jmp @tok
@kanji:
    jsr pool_glyph
    jsr buf_kanji
    jmp @tok
@line:
    ldx ZP_I
    lda equip_lo,x
    sta ZP_A
    lda equip_hi,x
    sta ZP_A+1
    jsr write_line
    inc ZP_I
    lda ZP_I
    cmp #3
    bcc @scan
@done:
    rts

; Row 20 + 2k, column 4.
equip_lo:
    .db $84, $C4, $04
equip_hi:
    .db $22, $22, $23

; ----------------------------------------------------------------------
; The static layout (nametable 0).  Label kanji k: top t, t+2, bottom
; t+1, t+3 with t = $1C + 4k (武 力 知 攻 撃 装 度 兵 士 数 備 策 略).
; The windows sit one tile lower than the original's (decision 7): the
; titles are 16x16 kanji on the top border, every line two rows.
; ----------------------------------------------------------------------
info_runs:
    .db $20,$8A,4, $1C,$1E,$20,$22          ; 武力   rows 4-5
    .db $20,$AA,4, $1D,$1F,$21,$23
    .db $20,$CA,4, $24,$26,$20,$22          ; 知力   rows 6-7
    .db $20,$EA,4, $25,$27,$21,$23
    .db $21,$0A,4, $28,$2A,$2C,$2E          ; 攻撃   rows 8-9
    .db $21,$2A,4, $29,$2B,$2D,$2F
    .db $21,$4A,6, $1C,$1E,$30,$32,$34,$36  ; 武装度 rows 10-11
    .db $21,$6A,6, $1D,$1F,$31,$33,$35,$37
    .db $21,$8A,3, $F6,$F8,$F7              ; S.P    row 12
    ; (兵士数, rows 14-15: queued by ui_info_late after the name windows)
    ; さくりゃく window: columns 16-29, rows 14-28, 策略 at columns 20-23
    .db $21,$D0,14, $6D,$0C,$0C,$0C,$48,$4A,$4C,$4E,$0C,$0C,$0C,$0C,$0C,$6E
    .db $21,$F0,14, $7D,$0A,$0A,$0A,$49,$4B,$4D,$4F,$0A,$0A,$0A,$0A,$0A,$7E
    .db $22,$10,$CC, $7D                    ; column 16, rows 16-27
    .db $22,$1D,$CC, $7E                    ; column 29, rows 16-27
    .db $23,$90,1, $0B
    .db $23,$91,$4C, $0D
    .db $23,$9D,1, $6F
    ; そうび window: columns 2-15, rows 18-26, 装備 at columns 6-9
    .db $22,$42,14, $6D,$0C,$0C,$0C,$30,$32,$44,$46,$0C,$0C,$0C,$0C,$0C,$6E
    .db $22,$62,14, $7D,$0A,$0A,$0A,$31,$33,$45,$47,$0A,$0A,$0A,$0A,$0A,$7E
    .db $22,$82,$C6, $7D                    ; column 2, rows 20-25
    .db $22,$8F,$C6, $7E                    ; column 15, rows 20-25
    .db $23,$42,1, $0B
    .db $23,$43,$4C, $0D
    .db $23,$4F,1, $6F
    .db $FF

.include "../../decomp/build/kanji/ui_data.inc"
