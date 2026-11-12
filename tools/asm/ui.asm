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
    .dw ui_bsetup-1, ui_bsetup_end-1, ui_dec-1, ui_div-1

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
; UIF_ARMY: the army status screen (Select on the map), built whole while
; it is black (bank 14 b14_army_status_screen, after battle_intro_screen's
; fade-out; INFO_SCREEN.md "Army status screen, built directly").  The
; game built it with battle_intro_screen's setup (two frame waits after
; the fade), four text-engine windows (every row queued and flushed, every
; name kanji a block-writer stream, the troop list's line routine copied
; to RAM for each line), its portrait loader (six queued parts) and three
; more frame waits to show it: 13 black frames.  Here, busy mode with
; rendering off throughout, everything written directly:
; - battle_intro_screen's setup: input_buttons, $AA, PPUCTRL, the
;   nametable and the sprites cleared (clear_screen), palette set 8 (the
;   NMI that shows the screen sends it).  Its CHR: tiles $00-$0F (bank 9
;   $BA00, plane-1 glyphs) to plane 0, plane 1 cleared; the UI block's
;   $F0-$FE (bank 9 $BF00; $E0-$EF get the labels);
; - 大将 / 軍師 ($C0-$D7, bank 1 $8000) to plane 0, the six label kanji
;   to $D8-$EF, M S P to plane 0 of $F5-$F7 (planes 1 cleared);
; - the leader's portrait: text_load_page's six parts and colours, read
;   directly; sub_CFA1's string around it (fixed bank);
; - every name once ($A9 from $10, 4 tiles a kanji, $A4-$BF once $10-$5F
;   are full): the leader's, the troop list's, the strategist's; an actor
;   shown before reuses its tiles (the leader and the strategist are in
;   the troop list);
; - the numbers with read_stack_arg's blanking.
; Every cell is P0 (plane 0 only) but the portrait's.  The level window is
; 4 columns wider than the game's (columns 15-30): 金 兵糧 経験値 from
; column 16, numbers right aligned at column 29 (6 digits leave 2 blank
; cells after 経験値), レベル- and the level from column 20.
; The text engine's state is left as its last window left it where the
; field return reads it (text_mode, menu_flags, text_actor, text_target,
; the saved rows); the hack's as for the info screen (no band, the pool
; check posted by load_text_graphics dropped, the pool unchecked).
; ======================================================================
ALAB_TILE   = $D8               ; 6 label kanji, 4 tiles each
AR_NT       = $0600             ; 16: an actor's first name tile (0: not yet)
AR_NK       = $0610             ; 16: its kanji
AR_BUF      = $0620             ; 10: the officer record's bytes $0A-$13
AR_RECA     = $062A             ; the actor whose record AR_BUF holds
RR_CODE     = $0660             ; the RAM reader (rr_rom, up to $06FF)
CLEAR_SCREEN = $C43C
LOAD_TEXT_GRAPHICS = $C5A6
TEXT_LOAD_PAGE = $CFA9
FIND_PARTY_MEMBER = $D636
PORTRAIT_STR = $CFA6            ; sub_CFA1's draw_string pointer
PORTRAIT_DST = $D107            ; text_load_page's CHR address by loop_counter
PORTRAIT_COL = $D0FD            ; its third colour by the record's low nibble

ui_army:
    lda #$80
    sta input_buttons
    inc $AA
    lda #$90
    sta ppu_ctrl_shadow
    jsr ppu_begin               ; busy; PPUCTRL $90 (NMI on, +1)
    lda ppu_mask_shadow
    and #$E7
    sta ppu_mask_shadow
    sta PPUMASK                 ; off now: the fade left the palette black
    jsr CLEAR_SCREEN            ; nametable blank, attributes 0, sprites off
    lda #$08
    sta text_graphics_index
    jsr LOAD_TEXT_GRAPHICS      ; palette set 8 to $03E0
    jsr ppu_setup
    lda #0                      ; the hack's state for a screen without a
    sta KANJI_BAND              ; band (as ui_info_draw)
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
    ldx #0
@rr:
    lda rr_rom,x
    sta RR_CODE,x
    inx
    cpx #rr_end-rr_rom
    bne @rr
    ; battle_intro_screen's tiles, 大将 / 軍師
    lda #0
    sta ZP_I
@chr:
    ldy ZP_I
    lda ar_chr,y                ; PPU address high, 0: end
    beq @labels
    sta PPUADDR
    lda ar_chr+1,y
    sta PPUADDR
    lda ar_chr+3,y
    sta ZP_PTR
    lda ar_chr+4,y
    sta ZP_PTR+1
    lda ar_chr+5,y
    sta ZP_N
    ldx ar_chr+6,y              ; mode
    lda ar_chr+2,y              ; bank
    jsr RR_CODE
    lda ZP_I
    clc
    adc #7
    sta ZP_I
    bne @chr
@labels:
    ; 金 兵 糧 経 験 値: plane 0 of $D8-$EF (8x16 order)
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
    ; names from $10, none uploaded yet
    lda #$10
    sta $A9
    ldx #15
    lda #0
@nc:
    sta AR_NT,x
    dex
    bpl @nc
    ; the leader's portrait
    jsr FIND_PARTY_MEMBER       ; party_slot: the leader (actor)
    lda #$FF
    sta AR_RECA
    lda party_slot
    sta text_actor
    jsr ar_rec
    lda battle_flags
    beq @portrait
    jsr ar_game_portrait        ; (never on the map: the game's mirrored path)
    jmp @pstr
@portrait:
    lda loop_counter
    asl a
    tax
    lda PORTRAIT_DST,x
    sta ZP_A+1
    lda PORTRAIT_DST+1,x
    sta ZP_A
    lda #0
    sta ZP_I
@part:
    lda ZP_A+1
    sta PPUADDR
    lda ZP_A
    sta PPUADDR
    ldy ZP_I
    lda AR_BUF,y                ; part: bit 7 bank 3 (else 2), $8800 + 96 n
    and #$7F
    sta ZP_T
    lda #0
    sta ZP_PTR+1
    lda ZP_T
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1                ; 32 n
    sta ZP_PTR
    asl a
    sta ZP_J
    lda ZP_PTR+1
    rol a
    sta ZP_K                    ; 64 n
    lda ZP_PTR
    clc
    adc ZP_J
    sta ZP_PTR
    lda ZP_PTR+1
    adc ZP_K
    adc #$88
    sta ZP_PTR+1
    lda #96
    sta ZP_N
    lda AR_BUF,y
    asl a                       ; C = bit 7
    lda #2
    adc #0
    ldx #1                      ; copy
    jsr RR_CODE
    lda ZP_A
    clc
    adc #$60
    sta ZP_A
    bcc @pn
    inc ZP_A+1
@pn:
    inc ZP_I
    lda ZP_I
    cmp #6
    bne @part
    lda AR_BUF+6                ; record $10: the colours
    and #$0F
    beq @black
    tax
    lda #$37
    sta $03ED
    lda #$26
    sta $03EE
    lda PORTRAIT_COL,x
    sta $03EF
    bne @pal
@black:
    lda #$0F
    sta $03ED
    sta $03EE
    sta $03EF
@pal:
    lda #1
    sta vram_dma_pending
@pstr:
    lda PORTRAIT_STR
    sta ZP_PTR
    lda PORTRAIT_STR+1
    sta ZP_PTR+1
    jsr ar_str                  ; the portrait's cells and P3
    lda #<ar_layout
    sta ZP_PTR
    lda #>ar_layout
    sta ZP_PTR+1
    jsr ar_str                  ; 大将 軍師, the frames, the labels
    ; the leader's name (window $2E): row 8, column 9
    lda #$09
    sta ZP_A
    lda #$21
    sta ZP_A+1
    lda party_slot
    jsr ar_name
    ; the level (row 4, columns 24-25)
    lda #$20
    sta PPUADDR
    lda #$98
    sta PPUADDR
    ldx #$FF
    lda $6073
    sec
@l10:
    inx
    sbc #10
    bcs @l10
    adc #10
    stx PPUDATA
    sta PPUDATA
    ; gold, food, experience: rows 6, 8, 10, 7 cells to column 29
    lda #0
    sta ZP_I
@gfe:
    ldy ZP_I
    ldx ar_gfe_var,y
    lda $6070,x
    sta RW_NUM
    lda $6071,x
    sta RW_NUM+1
    lda $6072,x
    sta RW_NUM+2
    jsr ar_dig
    ldy ZP_I
    lda ar_gfe_hi,y
    sta PPUADDR
    lda ar_gfe_lo,y
    sta PPUADDR
    ldx #7
    jsr ar_emit
    inc ZP_I
    lda ZP_I
    cmp #3
    bne @gfe
    ; the troop list (window $0E): line n, rows 13+2n / 14+2n
    lda #0
    sta ZP_I
@line:
    ldx ZP_I
    lda $6090,x                 ; party order: the actor, negative: none
    bpl @member
    jmp @next
@member:
    sta ZP_V
    lda ar_line_lo,x            ; the name's top-left cell, column 2
    sta ZP_A
    lda ar_line_hi,x
    sta ZP_A+1
    lda ZP_V
    jsr ar_name
    lda ZP_A                    ; the lower row, column 1: the marker
    clc
    adc #31
    tay
    lda ZP_A+1
    adc #0
    sta PPUADDR
    sty PPUADDR
    ldx ZP_V
    lda $609C,x                 ; state bits
    bmi @b7
    lda #$0E
    bne @mark
@b7:
    and #$40
    beq @plain
    lda #$0F
    bne @mark
@plain:
    lda #T_BLANK
@mark:
    sta PPUDATA
    lda ZP_A                    ; column 8: troops (6 cells) / maximum (5)
    clc
    adc #38
    tay
    lda ZP_A+1
    adc #0
    sta PPUADDR
    sty PPUADDR
    lda ZP_V
    asl a
    asl a
    tax
    lda $60D0,x
    sta RW_NUM
    lda $60D1,x
    sta RW_NUM+1
    lda $60D2,x
    sta RW_NUM+2
    jsr ar_dig
    ldx #6
    jsr ar_emit
    lda #$7C                    ; /
    sta PPUDATA
    lda ZP_V
    asl a
    asl a
    tax
    lda $6160,x
    sta RW_NUM
    lda $6161,x
    sta RW_NUM+1
    lda $6162,x
    sta RW_NUM+2
    jsr ar_dig
    ldx #5
    jsr ar_emit
@next:
    inc ZP_I
    lda ZP_I
    cmp #7
    beq @strat
    jmp @line
@strat:
    ; the strategist (window $0F): the member with state $C0
    ldx #6
@sf:
    lda $609C,x
    cmp #$C0
    beq @sfound
    dex
    bpl @sf
@sfound:
    stx text_target
    txa
    bmi @sp
    lda #$38                    ; row 17, column 24
    sta ZP_A
    lda #$22
    sta ZP_A+1
    txa
    jsr ar_name
@sp:
    lda #$22                    ; S.P: row 20, columns 27-29
    sta PPUADDR
    lda #$9B
    sta PPUADDR
    ldx #3
@sp3:
    lda $61FB-1,x
    sta RW_NUM-1,x
    dex
    bne @sp3
    jsr ar_dig
    ldx #3
    jsr ar_emit
    lda #$22                    ; M.S.P: row 22
    sta PPUADDR
    lda #$DB
    sta PPUADDR
    ldx #3
@msp3:
    lda $61F8-1,x
    sta RW_NUM-1,x
    dex
    bne @msp3
    jsr ar_dig
    ldx #3
    jsr ar_emit
    ; the text engine's state after window $0F
    lda #$0F
    sta text_mode
    lda text_busy
    bne @busy
    lda #1
    sta menu_flags
@busy:
    ldy #$17
    lda #T_BLANK
@saved:
    sta $0348,y
    dey
    bpl @saved
    jsr ppu_end                 ; not busy: the next NMI is a normal one
    lda ppu_mask_shadow
    ora #$18
    sta ppu_mask_shadow         ; rendering on with it
    rts

; The leader's portrait through the game's loader (battle_flags set: its
; mirrored path), as ui_binfo_exit calls put_officer_name.
ar_game_portrait:
    lda current_bank_a          ; text_load_page ends in set_bank_current
    pha
    lda #UI_BANK
    sta current_bank_a
    lda ZP_G
    jsr TEXT_LOAD_PAGE
    pla
    sta current_bank_a
    sta current_bank_b
    jmp ppu_setup

; A = actor: the officer record's bytes $0A-$13 to AR_BUF (bank 12: the
; record's address at $A800 / $A900 + officer), ZP_G = the officer.
ar_rec:
    sta AR_RECA
    tax
    lda $60A8,x
    sta ZP_G
    sta ZP_PTR
    lda #$A8
    sta ZP_PTR+1
    ldx #2                      ; record
    lda #12
    jmp RR_CODE

; A = actor, ZP_A = the name's top-left cell: its kanji in two rows (upper
; t, t+2, lower t+1, t+3 a kanji, as put_officer_name).  The glyphs are
; uploaded the first time only (record $11-$13, $FF ends; record $10 bit 7
; down: kanji n in bank NAME_FONT_BANK + 1, else NAME_FONT_BANK, at $8000 +
; 32 glyph; the kanji target's records all use the name font): plane 0,
; plane 1 cleared, from $A9 on.
ar_name:
    sta ZP_X
    tax
    lda AR_NT,x
    beq @new
    jmp @show
@new:
    lda ZP_X
    cmp AR_RECA
    beq @have                   ; (the leader's, read for the portrait)
    jsr ar_rec
@have:
    ldy #0
@count:
    lda AR_BUF+7,y
    cmp #$FF
    beq @counted
    iny
    cpy #3
    bne @count
@counted:
    ldx ZP_X
    tya
    sta AR_NK,x
    asl a
    asl a
    adc $A9
    cmp #$61
    bcc @fits                   ; it ends at $60 at most
    lda $A9
    cmp #$A4
    bcs @fits                   ; (in $A4-$BF already)
    lda #$A4                    ; then $A4-$BF (free on this screen)
    sta $A9
@fits:
    lda $A9
    sta AR_NT,x
    lda AR_BUF+6
    sta ZP_C                    ; bank bits
    lda AR_NK,x
    sta ZP_K
    lda #0
    sta ZP_J
@glyph:
    ldy ZP_J
    cpy ZP_K
    beq @show
    lda $A9
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta PPUADDR
    lda $A9
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
    lda AR_BUF+7,y
    lsr a
    lsr a
    lsr a
    ora #$80
    sta ZP_PTR+1
    lda AR_BUF+7,y
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ZP_PTR
    lda #4
    sta ZP_N
    asl ZP_C
    lda #NAME_FONT_BANK
    adc #0
    ldx #0                      ; plane 0, plane 1 cleared
    jsr RR_CODE
    lda $A9
    clc
    adc #4
    sta $A9
    inc ZP_J
    jmp @glyph
@show:
    ldx ZP_X
    lda AR_NK,x
    beq @rts
    sta ZP_N
    lda AR_NT,x
    sta ZP_T
    lda ZP_A+1
    sta PPUADDR
    lda ZP_A
    sta PPUADDR
    lda ZP_T
    ldx ZP_N
@top:
    sta PPUDATA
    clc
    adc #2
    sta PPUDATA
    adc #2
    dex
    bne @top
    lda ZP_A
    clc
    adc #32
    tay
    lda ZP_A+1
    adc #0
    sta PPUADDR
    sty PPUADDR
    lda ZP_T
    clc
    adc #1
    ldx ZP_N
@bottom:
    sta PPUDATA
    adc #2
    sta PPUDATA
    adc #2
    dex
    bne @bottom
@rts:
    rts

; RW_DIG = the 24-bit number RW_NUM as 7 decimal digits (no blanking).
ar_dig:
    ldy #0
@digit:
    ldx #0
@sub:
    lda RW_NUM
    sec
    sbc pow7_lo,y
    sta ZP_J
    lda RW_NUM+1
    sbc pow7_mid,y
    sta ZP_K
    lda RW_NUM+2
    sbc pow7_hi,y
    bcc @emit
    sta RW_NUM+2
    lda ZP_K
    sta RW_NUM+1
    lda ZP_J
    sta RW_NUM
    inx
    bne @sub
@emit:
    txa
    sta RW_DIG,y
    iny
    cpy #6
    bne @digit
    lda RW_NUM
    sta RW_DIG+6
    rts

; The last X digits of RW_DIG to PPUDATA as read_stack_arg prints them:
; zeros before the first other digit blank, the last digit always shown.
ar_emit:
    stx ZP_K
    lda #7
    sec
    sbc ZP_K
    tay
    lda #0
    sta ZP_K                    ; a digit was shown
@cell:
    lda RW_DIG,y
    bne @show
    cpy #6
    beq @put
    ldx ZP_K
    bne @put
    lda #T_BLANK
    bne @put
@show:
    sta ZP_K
@put:
    sta PPUDATA
    iny
    cpy #7
    bne @cell
    rts

; A draw_string-format string at (ZP_PTR): address high ($FF ends), low,
; count (bit 7: down a column, bit 6: one tile repeated), tiles.
ar_str:
    ldy #0
    lda (ZP_PTR),y
    cmp #$FF
    beq @end
    sta PPUADDR
    iny
    lda (ZP_PTR),y
    sta PPUADDR
    iny
    lda (ZP_PTR),y
    iny
    sta ZP_C
    and #$3F
    tax
    lda ppu_ctrl_shadow
    and #$FB
    bit ZP_C
    bpl @across
    ora #$04
@across:
    sta PPUCTRL
    bvc @list
    lda (ZP_PTR),y
    iny
@run:
    sta PPUDATA
    dex
    bne @run
    beq @next
@list:
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    dex
    bne @list
@next:
    tya
    clc
    adc ZP_PTR
    sta ZP_PTR
    bcc ar_str
    inc ZP_PTR+1
    bcs ar_str
@end:
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL
    rts

; The RAM reader, copied to RR_CODE (relocatable: branches only).  A = the
; 16 KiB bank (game lock protocol: an NMI maps it back), X = 0: ZP_N tiles
; of 8 bytes from (ZP_PTR) to plane 0, 8 zeros after each (plane 1);
; 1: ZP_N bytes to PPUDATA (a multiple of 4; 0 = 256); 2: the record of
; officer ZP_PTR - $A800 (its address at (ZP_PTR) and 256 bytes on): its
; bytes $0A-$13 to AR_BUF.  Maps the UI bank again.
rr_rom:
    jsr SET_BANK_LOCK
    ldy #0
    dex
    bmi @tile
    beq @copy
    lda (ZP_PTR),y              ; the record
    pha
    inc ZP_PTR+1
    lda (ZP_PTR),y
    sta ZP_PTR+1
    pla
    sta ZP_PTR
    ldy #$0A
@rec:
    lda (ZP_PTR),y
    sta AR_BUF-$0A,y
    iny
    cpy #$14
    bne @rec
    beq @back
@tile:
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda #0
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    dec ZP_N
    bne @tile
    beq @back
@copy:
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    lda (ZP_PTR),y
    sta PPUDATA
    iny
    cpy ZP_N
    bne @copy
@back:
    lda #UI_BANK
    jmp SET_BANK_LOCK
rr_end:
.if rr_end - rr_rom > $100 - <RR_CODE
    .error "rr_rom does not fit the $0600 page"
.endif

; PPU address high (0 ends), low, bank, source low, high, count, mode
ar_chr:
    .db $10,$00, 9, $00,$BA, 16, 0      ; $00-$0F: plane-1 glyphs to plane 0
    .db $1F,$00, 9, $00,$BF, 240, 1     ; $F0-$FE: the UI block's rest
    .db $1C,$00, 1, $00,$80, 24, 0      ; $C0-$D7: 大将 軍師
    .db 0

; gold $6076, food $6079, experience $6070: rows 6, 8, 10, columns 23-29
ar_gfe_var:
    .db 6, 9, 0
ar_gfe_hi:
    .db $20, $21, $21
ar_gfe_lo:
    .db $D7, $17, $57

; the troop list's name cells: row 13 + 2n, column 2
ar_line_lo:
    .db <($21A2+0*64), <($21A2+1*64), <($21A2+2*64), <($21A2+3*64)
    .db <($21A2+4*64), <($21A2+5*64), <($21A2+6*64)
ar_line_hi:
    .db >($21A2+0*64), >($21A2+1*64), >($21A2+2*64), >($21A2+3*64)
    .db >($21A2+4*64), >($21A2+5*64), >($21A2+6*64)

; The fixed cells (ar_str format).
ALT = ALAB_TILE
ar_layout:
    .db $20,$89,4, $C0,$C2,$C4,$C6                      ; 大将 (rows 4-5)
    .db $20,$A9,4, $C1,$C3,$C5,$C7
    .db $21,$B8,4, $D0,$D2,$D4,$D6                      ; 軍師 (rows 13-14)
    .db $21,$D8,4, $D1,$D3,$D5,$D7
    ; the level window, rows 4-11, columns 15-30
    .db $20,$75,1, $72                                  ; べ's dakuten (row 3)
    .db $20,$8F,1, $6D
    .db $20,$90,$44, $0C
    .db $20,$94,4, $65,$60,$64,$79                      ; レベル- (the level: 24-25)
    .db $20,$9A,$44, $0C
    .db $20,$9E,1, $6E
    .db $20,$AF,$C6, $7D                                ; the sides, rows 5-10
    .db $20,$BE,$C6, $7E
    .db $20,$B0,2, ALT+0,ALT+2                          ; 金
    .db $20,$D0,2, ALT+1,ALT+3
    .db $20,$F0,4, ALT+4,ALT+6,ALT+8,ALT+10             ; 兵糧
    .db $21,$10,4, ALT+5,ALT+7,ALT+9,ALT+11
    .db $21,$30,6, ALT+12,ALT+14,ALT+16,ALT+18,ALT+20,ALT+22  ; 経験値
    .db $21,$50,6, ALT+13,ALT+15,ALT+17,ALT+19,ALT+21,ALT+23
    .db $21,$6F,1, $0B
    .db $21,$70,$4E, $0D
    .db $21,$7E,1, $6F
    ; the troop list's window, rows 12-27, columns 0-21
    .db $21,$80,1, $6D
    .db $21,$81,$54, $0C
    .db $21,$95,1, $6E
    .db $21,$A0,$CE, $7D
    .db $21,$B5,$CE, $7E
    .db $23,$60,1, $0B
    .db $23,$61,$54, $0D
    .db $23,$75,1, $6F
    ; S P, M S P (rows 20, 22)
    .db $22,$97,2, $F6,$F7
    .db $22,$D7,3, $F5,$F6,$F7
    .db $FF

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
