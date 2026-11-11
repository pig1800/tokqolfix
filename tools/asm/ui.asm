; ======================================================================
; UI bank (step B, INFO_SCREEN.md): bank-switch-free kanji on the officer
; info screen.  PRG bank UI_BANK, assembled for $8000; the fixed bank's
; call_ui maps it (game lock protocol) and calls $8000 with X = function.
;
; The info screen (b14_officer_info_screen) stays black while it is built:
; the game draws the portrait and the two name windows, then UIF_INFO_DRAW
; uploads the kanji and writes everything else with direct PPU access
; (nmi_busy set, as the game's own copy_to_vram), and only then is
; rendering turned on.  No CHR register is switched while the screen is
; shown and no scanline IRQ runs (decision 13).
;
; CHR (decisions 3, 5, 11; tile order t, t+1, t+2, t+3 = TL, BL, TR, BR):
;   plane 1 of $10-$1B  the name (the original engine, $A9 = $10)
;   plane 1 of $1C-$4F  13 label kanji, slot k at $1C + 4k
;   plane 1 of $50-$7F  tactic line n: first kanji $50 + 8n, second $54 + 8n
;   plane 0 of $A4-$DF  15 groups: the equipment kanji and 計 (P0 cells),
;                       one group per distinct kanji
;   $E0-$FE             the bank-9 block, every glyph in plane 1 (bars, S.P)
; Battle path (UIF_BINFO_ENTER / _EXIT around the screen): on the way back
; every battle name whose plane-1 tiles the screen used is streamed again
; (the game's put_officer_name), the pool is blanked and marked usable, and
; the battle screen's fixed kanji are written again (ui_battle.asm).
; Nothing here touches CHR RAM beyond the two pattern tables.
;
; The battle screen itself (step B item 7: command window, tactic and item
; windows, the slot table of the 23 plane-0 groups $A4-$FF) is in
; ui_battle.asm.
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

T_BLANK     = $0A
T_NO        = $23           ; の
T_DAK       = $72           ; ゛
T_HANDAK    = $73           ; ゜
T_FULL      = $F4           ; bar, 26 points
T_HALF      = $F3           ; bar, 13 points
PUT_OFFICER_NAME = $D4A1      ; fixed bank (step A name)
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
    .dw ui_info_enter-1, ui_bstart-1, ui_wincb-1, ui_sm-1, ui_info_busy-1
    .dw ui_bsetup-1, ui_bsetup_end-1, ui_dec-1, ui_div-1, ui_alab-1

; ======================================================================
; UIF_INFO_ENTER: the info screen, before battle_intro_screen.  Its block
; write of tiles $00-$0F is not mirrored to the band page (the battle and
; the info screen show no band); pal_copy clears the flag again.
; ======================================================================
ui_info_enter:
    lda #1
    sta UI_NOMIR
    rts

; ======================================================================
; UIF_INFO_BUSY: the info screen after battle_intro_screen (rendering off).
; Busy mode until UIF_INFO_DRAW's end: the game's own steps (the portrait,
; the two name windows, the name's CHR stream) wait with wait_vblank, whose
; busy path flushes the queue and the stream at once instead of one chunk
; per frame (15 black frames before, see INFO_SCREEN.md).  Those direct
; flushes go through the block writer: no mirror to the band page (pal_copy
; in battle_intro_screen cleared UI_NOMIR; the next pal_copy clears it).
; ======================================================================
ui_info_busy:
    lda #1
    sta UI_NOMIR
    jmp ppu_begin

; ======================================================================
; UIF_BSETUP: battle_setup_slots is next (bank 14 b14_k_setup).  It rolls
; the enemy slots, then draws every slot (sprite, name, troops), paced by
; queue waits ($DF32, $E0A3, $E200, $E238): about 4 frames a slot.  The
; screen is off and the NMI busy there (always so far; a scripted battle's
; intro event could leave the screen on), and those waits are the fixed
; bank's bs_wait now, which steps the RNG in place of the frame.  Here:
; busy mode for the CHR writes, and no band-page copy of the name glyphs
; (the battle shows no band; the block writer marks the tiles stale).
; UIF_BSETUP_END undoes both when the slot loop ends.
; ======================================================================
ui_bsetup:
    lda ppu_mask_shadow
    and #$18
    bne @rts                    ; shown: as the original
    lda #1
    sta UI_BSBUSY
    sta UI_NOMIR
    jmp ppu_begin
@rts:
    rts

; UIF_BSETUP_END: bank 15 $E10F, after the last slot, before
; battle_setup_intro (its fade and messages need the NMI's PPU work).
ui_bsetup_end:
    lda UI_BSBUSY
    beq @rts
    lda #0
    sta UI_BSBUSY
    sta UI_NOMIR
    jmp ppu_end
@rts:
    rts

; ======================================================================
; UIF_DEC: copy_pointer_triplet ($D671, now a stub: sty ppu_update_off /
; stx UI_DECX / ldx #UIF_DEC / jmp call_ui).  The original divides $03-$05
; by 1,000,000 ... 10 with div24_shift (24 shift steps each, about 11,500
; cycles a number); the quotients go to $0104-$0109 (the first can exceed
; 9: 16,777,215 / 1,000,000 = 16), the last remainder to $010A.  Here the
; powers of ten are subtracted (at most 16 + 5 * 9 subtractions, about
; 1,600 cycles), with the same end state: $00-$02 the last quotient,
; $03-$05 the last remainder, $06-$08 the last divisor (10), $09 = 0
; (div24_shift's counter), ppu_update_ptr_lo = 6, X and Y as given (A and
; the flags are call_ui's; every caller loads A or Y next).  No call and
; no push: the digits sit at the bottom of the stack page.
; ======================================================================
ui_dec:
    ldy #0                      ; digit
@digit:
    ldx #0                      ; quotient
@try:
    lda $03                     ; $06/$07 = trial low / middle bytes
    sec
    sbc dec_lo,y
    sta $06
    lda $04
    sbc dec_mid,y
    sta $07
    lda $05
    sbc dec_hi,y
    bcc @store
    sta $05
    lda $07
    sta $04
    lda $06
    sta $03
    inx
    bne @try                    ; (always: at most 16)
@store:
    txa
    sta $0104,y
    iny
    cpy #6
    bne @digit
    stx $00
    sty ppu_update_ptr_lo
    lda #0
    sta $01
    sta $02
    sta $07
    sta $08
    sta $09
    lda #10
    sta $06
    lda $03
    sta $010A
    ldx UI_DECX
    ldy ppu_update_off
    rts
; ======================================================================
; UIF_DIV: div24_shift ($C1D2, now a stub: stx UI_DECX / sty UI_DECY /
; ldx #UIF_DIV / jmp call_ui).  $00-$02 / $06-$08: the quotient in
; $00-$02, the remainder in $03-$05, $09 = 0, X and Y as given.  The same
; 24 shift-and-subtract steps as the original, so the same results for
; every input (divisor 0: quotient $FFFFFF, remainder the dividend;
; divisors over $7FFFFF: the remainder's bit 24 is dropped as there).
; With a divisor above 0 and the remainder still 0, a zero top byte of the
; dividend makes the next 8 steps leave the remainder 0 and shift 8 zero
; quotient bits in: done as one byte move.  No call and no push.
; ======================================================================
ui_div:
    lda #0
    sta $03
    sta $04
    sta $05
    ldy #24
    lda $06
    ora $07
    ora $08
    beq @step                   ; divisor 0: every step
@skip:
    lda $02
    bne @step
    lda $01                     ; 8 steps: remainder 0, quotient << 8
    sta $02
    lda $00
    sta $01
    lda #0
    sta $00
    tya
    sec
    sbc #8
    tay
    bne @skip
    beq @done                   ; (dividend 0)
@step:
    asl $00
    rol $01
    rol $02
    rol $03
    rol $04
    rol $05
    lda $03
    sec
    sbc $06
    tax
    lda $04
    sbc $07
    sta $09
    lda $05
    sbc $08
    bcc @next
    sta $05
    lda $09
    sta $04
    stx $03
    inc $00
@next:
    dey
    bne @step
@done:
    sty $09
    ldx UI_DECX
    ldy UI_DECY
    rts

; 1,000,000 / 100,000 / 10,000 / 1,000 / 100 / 10 (data_D6B0's divisors)
dec_lo:
    .db $40, $A0, $10, $E8, $64, $0A
dec_mid:
    .db $42, $86, $27, $03, $00, $00
dec_hi:
    .db $0F, $01, $00, $00, $00, $00

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
; ppu_bg_sprites_off).  Busy mode throughout:
; - every battle slot whose name (read from the battle nametable at the
;   slot's position, data_E17C / data_E186) has a kanji in a plane-1 group
;   this screen used is streamed again by put_officer_name to the same
;   tiles ($A9 = its first tile).  In busy mode its wait_vblank flushes at
;   once, so the stream costs no frame.  The block writer does not mirror
;   it (UI_NOMIR);
; - plane 0 and 1 of the pool $A4-$DF are cleared: no message is shown
;   now, the pool is marked checked and blank, so the next battle message
;   uses it (not the band page); then the 15 fixed command kanji go back to
;   groups 8-22 and the slot table is reset (battle_state_direct);
; - the P2 colours 1-3 come back (decision 6).
; ======================================================================
ui_binfo_exit:
    jsr ppu_begin
    lda #1
    sta UI_NOMIR
    lda current_bank_a          ; put_officer_name ends in set_bank_current,
    pha                         ; which maps current_bank_a
    lda #UI_BANK
    sta current_bank_a
    lda #0
    sta ZP_I                    ; slot
@slot:
    jsr slot_name_dirty         ; C set: stream it, Y = actor, ZP_T = tile
    bcc @next
    lda ZP_T
    sta $A9
    lda #1
    sta $AA
    ldx #0
    jsr PUT_OFFICER_NAME
@next:
    inc ZP_I
    lda ZP_I
    cmp #10
    bne @slot
    pla
    sta current_bank_a
    sta current_bank_b
    lda #0
    sta UI_NOMIR
    ; the pool: 60 tiles, both planes
    lda #$1A
    sta PPUADDR
    lda #$40
    sta PPUADDR
    ldx #60
    lda #0
@pool:
    ldy #16
@pool16:
    sta PPUDATA
    dey
    bne @pool16
    dex
    bne @pool
    jsr battle_state_direct     ; the fixed kanji, the slot table, the pool
    jsr ppu_end
    ldx #2
@p2:
    lda UI_P2,x
    sta $03E9,x
    dex
    bpl @p2
    lda #0
    sta UI_PATH
    rts

; Battle slot ZP_I: C set when its name must be streamed again; then Y =
; its actor and ZP_T = the name's first tile.  The name's kanji k sits at
; column 2k of the slot's position (top row t, t+2).
slot_name_dirty:
    ldx ZP_I
    cpx #5
    bcs @enemy
    ldy $6097,x                 ; party slots: the party order
    bmi @no
    bpl @actor
@enemy:
    txa                         ; enemy slots 5-9: actors 7-11
    clc
    adc #2
    tay
@actor:
    lda $609C,y                 ; present (as battle_setup_names asks)
    bpl @no
    lda ppu_ctrl_shadow         ; +1 (a queued vertical run may have left +32)
    and #$FB
    sta PPUCTRL
    lda PPUSTATUS
    lda $E17C,x                 ; data_E17C / data_E186: the name's address
    sta PPUADDR
    lda $E186,x
    sta PPUADDR
    lda PPUDATA                 ; (read buffer)
    lda PPUDATA
    sta ZP_T                    ; first tile
    sta ZP_J                    ; tile expected for kanji k
    ldx #3
@kanji:
    lda ZP_J
    cmp #$10
    bcc @no                     ; not a plane-1 name tile
    cmp #$80
    bcs @no
    jsr group_dirty
    bcs @yes
    dex
    beq @no
    lda PPUDATA                 ; skip the right half
    lda PPUDATA
    sec
    sbc ZP_J
    cmp #4                      ; the next kanji: tile + 4
    bne @no
    lda ZP_J
    clc
    adc #4
    sta ZP_J
    jmp @kanji
@yes:
    sec
    rts
@no:
    clc
    rts

; A = a plane-1 tile $10-$7F: C set when this screen wrote its group.
; Groups $10-$4F (the name, the labels) always; tactic line n's groups
; $50 + 8n and $54 + 8n when the line was drawn (UI_TACT bit n).
group_dirty:
    cmp #$50
    bcc @yes
    sec
    sbc #$50
    lsr a
    lsr a
    lsr a                       ; line n
    sty ZP_K
    tay
    lda tact_bit,y
    ldy ZP_K
    and UI_TACT
    beq @no
@yes:
    sec
    rts
@no:
    clc
    rts
tact_bit:
    .db $01, $02, $04, $08, $10, $20

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
    ; The level window's labels 金 兵 糧 経 験 値: plane 0, tiles $D8-$EF
    ; (8x16 order), over the bars of the UI block (not shown here).
    lda #0
    sta ZP_N
@lab:
    lda ZP_N
    asl a
    asl a
    adc #ALAB_TILE
    tax
    ldy ZP_N
    lda ui_reward_g,y
    clc                         ; plane 0, plane 1 cleared
    jsr put_glyph
    inc ZP_N
    lda ZP_N
    cmp #6
    bne @lab
    ; M S P ($F5-$F7): plane 1 in the kanji target's UI block (decision
    ; 11); plane 0 here, plane 1 cleared.
    lda #$1F
    sta PPUADDR
    lda #$50
    sta PPUADDR
    ldy #0
@smp:
    ldx #8
@p0:
    lda ui_army_smp,y
    sta PPUDATA
    iny
    dex
    bne @p0
    ldx #8
    lda #0
@p1:
    sta PPUDATA
    dex
    bne @p1
    cpy #24
    bne @smp
    lda #1                      ; the names' streams: no band copy and
    sta UI_NOMIR                ; plane 0 (battle_intro_screen's pal_copy
    lda #AP0_ON                 ; cleared both)
    sta UI_AP0
    jmp ppu_end

; ======================================================================
; UIF_ALAB: the army status screen's last string (bank 14, in place of
; draw_string $9753).  The level window again, 4 columns wider (rows
; 4-11, columns 15-30; window $0D drew columns 18-29 with empty lines and
; the level digits went to columns 25-26, kept): the kanji labels with
; their top-left cell where the kana labels were, 3 columns left; the
; numbers right aligned at column 28, one right (6 digits leave a blank
; cell after 金 and 兵糧, none after 経験値; a 7th digit lands in column
; 22).  Then べ's dakuten, S P and M S P.  Busy mode: the queue is flushed
; first (window $0F's rows hold the S P cells).
; ======================================================================
ALAB_TILE   = $D8               ; 6 label kanji, 4 tiles each
ui_alab:
    jsr WAIT_VBLANK
    jsr ppu_begin
    ldy #0
@seg:
    lda ui_alab_str,y           ; address high, 0: end
    beq @num
    sta PPUADDR
    iny
    lda ui_alab_str,y
    sta PPUADDR
    iny
    ldx ui_alab_str,y           ; count
    iny
@tile:
    lda ui_alab_str,y
    sta PPUDATA
    iny
    dex
    bne @tile
    beq @seg
@num:
    lda #0
    sta ZP_I
@line:
    ldy ZP_I
    ldx alab_var,y              ; offset from $6070
    jsr num7                    ; RW_DIG: 7 digit tiles, leading zeros blank
    ldy #0
@lead:
    lda RW_DIG,y
    cmp #T_BLANK
    bne @first
    iny
    cpy #6
    bne @lead                   ; (the last digit is always a digit)
@first:
    sty ZP_N
    ldx ZP_I
    lda alab_hi,x
    sta PPUADDR
    tya
    clc
    adc alab_lo,x
    sta PPUADDR
    ldy ZP_N
@digit:
    lda RW_DIG,y
    sta PPUDATA
    iny
    cpy #7
    bne @digit
    inc ZP_I
    lda ZP_I
    cmp #3
    bne @line
    jmp ppu_end

; address high, low, count, tiles; 0 ends.  Rows 4-11 from column 15.
ALT = ALAB_TILE
ui_alab_str:
    .db $20,$76,1, $72                                  ; べ's dakuten (row 3)
    .db $20,$8F,10, $6D,$0C,$0C,$0C,$0C,$0C,$65,$60,$64,$79   ; row 4: レベル-
    .db $20,$9B,4, $0C,$0C,$0C,$6E                      ; (the level digits: 25-26)
    .db $20,$AF,16, $7D,$0A,ALT+0,ALT+2,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$7E   ; 金
    .db $20,$CF,16, $7D,$0A,ALT+1,ALT+3,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$7E
    .db $20,$EF,16, $7D,$0A,ALT+4,ALT+6,ALT+8,ALT+10,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$7E  ; 兵糧
    .db $21,$0F,16, $7D,$0A,ALT+5,ALT+7,ALT+9,ALT+11,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$7E
    .db $21,$2F,16, $7D,$0A,ALT+12,ALT+14,ALT+16,ALT+18,ALT+20,ALT+22,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$7E  ; 経験値
    .db $21,$4F,16, $7D,$0A,ALT+13,ALT+15,ALT+17,ALT+19,ALT+21,ALT+23,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$7E
    .db $21,$6F,16, $0B,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$6F  ; row 11
    .db $22,$97,2, $F6,$F7                              ; S P
    .db $22,$D7,3, $F5,$F6,$F7                          ; M S P
    .db 0
; gold row 6, food row 8, experience row 10; the 7 digit cells from
; column 22
alab_var:
    .db 6, 9, 0
alab_hi:
    .db $20, $21, $21
alab_lo:
    .db $D6, $16, $56

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
; (already busy: the PPU state only)
ppu_setup:
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
    lda nmi_busy                ; busy since UIF_INFO_BUSY: ppu_end ends it
    beq @begin
    jsr ppu_setup
    jmp @busy
@begin:
    jsr ppu_begin               ; (a save state from an earlier build)
@busy:
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
    jsr draw_troops
    lda #0
    sta UI_NG
    sta UI_TACT
    jsr draw_tactics
    jsr draw_equipment
    jmp ppu_end

; ----------------------------------------------------------------------
; The five stat lines (b14_wincb_stat_value_bar's values): 3 digits at
; columns 17-19 (the kanji lines' upper row), a blank, then from column 21
; a bar of $F4 per 26 points and $F3 for a remainder of 13 or more.
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

; Digits at column 17 of rows 4, 6, 8, 10 (the kanji lines' upper rows)
; and 12 (S.P).
stat_lo:
    .db $91, $D1, $11, $51, $91
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

; ----------------------------------------------------------------------
; 兵士数 (rows 15-16, columns 2-7) and text_actor's 24-bit troop maximum
; ($6160 + 4 * actor, low byte first) as 6 digits, leading zeros blank, in
; row 15 from column 8.  Drawn after the name windows: the kanji name's
; window clears rows 14-15 at columns 2-9 (its second line).
; ----------------------------------------------------------------------
draw_troops:
    lda #<troop_runs
    sta ZP_PTR
    lda #>troop_runs
    sta ZP_PTR+1
    jsr write_runs
    jsr troops_digits
    lda #$21
    sta PPUADDR
    lda #$E8
    sta PPUADDR
    ldx #0
@w:
    lda LBUF_B,x
    sta PPUDATA
    inx
    cpx #6
    bne @w
    rts
troop_runs:
    .db $21,$E2,6, $38,$3A,$3C,$3E,$40,$42  ; 兵士数 rows 15-16
    .db $22,$02,6, $39,$3B,$3D,$3F,$41,$43
    .db $FF

; LBUF_B[0..6) = the troop maximum's 6 digits.
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
    ldx ZP_I                    ; this line's plane-1 groups are used
    lda tact_bit,x
    ora UI_TACT
    sta UI_TACT
    ldy ZP_G
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
; The windows' lines are two rows and their bottom borders one row lower
; than the original's (decision 7); the top borders are at rows 15 / 19,
; under the lower half of the 16x16 titles.
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
    ; さくりゃく window: columns 16-29, top border row 15, bottom row 28;
    ; 策略 at rows 14-15, columns 21-24 (on the border)
    .db $21,$D5,4, $48,$4A,$4C,$4E
    .db $21,$F0,14, $6D,$0C,$0C,$0C,$0C,$49,$4B,$4D,$4F,$0C,$0C,$0C,$0C,$6E
    .db $22,$10,$CC, $7D                    ; column 16, rows 16-27
    .db $22,$1D,$CC, $7E                    ; column 29, rows 16-27
    .db $23,$90,1, $0B
    .db $23,$91,$4C, $0D
    .db $23,$9D,1, $6F
    ; そうび window: columns 2-15, top border row 19, bottom row 26;
    ; 装備 at rows 18-19, columns 7-10 (on the border)
    .db $22,$47,4, $30,$32,$44,$46
    .db $22,$62,14, $6D,$0C,$0C,$0C,$0C,$31,$33,$45,$47,$0C,$0C,$0C,$0C,$6E
    .db $22,$82,$C6, $7D                    ; column 2, rows 20-25
    .db $22,$8F,$C6, $7E                    ; column 15, rows 20-25
    .db $23,$42,1, $0B
    .db $23,$43,$4C, $0D
    .db $23,$4F,1, $6F
    .db $FF

.include "ui_battle.asm"

.include "../../decomp/build/kanji/ui_data.inc"
