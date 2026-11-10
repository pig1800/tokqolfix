; ======================================================================
; PRG bank 07  CPU $8000-$BFFF
; ======================================================================
; traced code: 381 instructions / 882 bytes; CDL code bytes: 312
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$93FF  b07_map_data: Map movement/event data and tables.
;   $9400-$9E81  b07_event_code: Map/event script interpreter.
;   $9E82-$BFFF  b07_data: Map/event data and padding.
; ======================================================================

; Region aliases
b07_event_code = $9400


b07_map_data:
; editable source: assets/data/bank07.bin (bin)
    .incbin "build/assets/bank07_data.bin", $0000, $0100

b07_data_8100:
    .incbin "build/assets/bank07_data.bin", $0100, $0100

b07_data_8200:
    .incbin "build/assets/bank07_data.bin", $0200, $00B0

b07_data_82B0:
    .incbin "build/assets/bank07_data.bin", $02B0, $0150

b07_data_8400:
    .incbin "build/assets/bank07_data.bin", $0400, $0400

b07_data_8800:
    .incbin "build/assets/bank07_data.bin", $0800, $0400

b07_data_8C00:
    .incbin "build/assets/bank07_data.bin", $0C00, $0400

b07_data_9000:
    .incbin "build/assets/bank07_data.bin", $1000, $0400

; ----------------------------------------------------------------------
; b07_entry
;   Bank 7 entry point (thunk to the party screen setup).
; ----------------------------------------------------------------------
b07_entry:
    jmp b07_party_screen_setup
; ----------------------------------------------------------------------
; b07_enter_party_screen
;   Front-end part of the party screen: draw the title, wait, and
;   call the list-drawing routine.
; ----------------------------------------------------------------------
b07_enter_party_screen:
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_9406:
    .incbin "build/assets/bank07_data.bin", $1406, $0002
    lda #$3C
    jsr b07_delay_frames
    lda #$07
    sta map_x
    ldy #$00
    sty map_y
    jsr b07_wait_and_draw
    lda #$78
    jsr b07_delay_frames
    ldy #$0A
    jsr draw_window
    lda #$B4
    jsr b07_delay_frames
    lda #$00
    sta map_x2
    sta map_y2
; ----------------------------------------------------------------------
; b07_run
;   Bank 7 main runner/dispatch.
; ----------------------------------------------------------------------
b07_run:
    jsr screen_fade_in
    lda #$20
    ldx #$0A
    ldy #$AA
    jsr set_ppu_scroll
    ldx #$00
    stx loop_counter
b07_loc_943D:
    ldy map_y2
    lda b07_data_975B,y
    inc map_y2
    stx loop_counter
    stx battle_flags
    jsr text_load_page
    inc loop_counter
    ldx loop_counter
    cpx #$02
    bne b07_loc_943D
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_9456:
    .incbin "build/assets/bank07_data.bin", $1456, $0002
    jsr wait_vblank
    lda map_x2
    cmp #$02
    beq b07_loc_947F
    cmp #$04
    beq b07_loc_947F
    ldy map_y2
    inc map_y2
    lda b07_data_975B,y
    ldx #$02
    stx loop_counter
    ldy #$00
    sty battle_flags
    jsr text_load_page
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_947A:
    .incbin "build/assets/bank07_data.bin", $147A, $0002
    jsr wait_vblank
b07_loc_947F:
    lda #$00
    sta $A5
    jsr load_text_graphics
    jsr screen_fade_out
    inc nmi_mode
    lda #$F8
    sta $7C
b07_loc_948F:
    lda $7C
    sta $6401
    jsr one_minus_a
    sta $6400
    lda #$00
    sta $6403
    lda #$01
    sta $6402
    lda #$01
    jsr b07_delay_frames
    lda $7C
    sec
    sbc #$08
    sta $7C
    bne b07_loc_948F
    dec nmi_mode
    lda #$28
    jsr b07_delay_frames
    ldy map_x2
    lda b07_data_9756,y
    sta map_x
    jsr b07_wait_and_draw
    lda #$96
    jsr b07_delay_frames
    lda #$96
    jsr b07_delay_frames
    ldy #$0A
    jsr draw_window
    inc map_x2
    lda map_x2
    cmp #$05
    beq b07_loc_94DD
    jmp b07_run
b07_loc_94DD:
    jsr screen_fade_in
    lda #$20
    ldx #$0A
    ldy #$AA
    jsr set_ppu_scroll
    jsr screen_fade_out
    lda #$96
    jsr b07_delay_frames
    lda #$96
    jsr b07_delay_frames
    lda #$06
    sta map_x
    jsr b07_wait_and_draw
    lda #$96
    jsr b07_delay_frames
    lda #$96
    jsr b07_delay_frames
    ldy #$0A
    jsr draw_window
    lda #$96
    jsr b07_delay_frames
    lda #$96
    jsr b07_delay_frames
b07_loc_9516:
    lda #$00
    sta loop_counter
    sta battle_flags
    jmp enter_status_screen
; ----------------------------------------------------------------------
; b07_wait_and_draw
;   Wait/draw loop used by the party screen.
;   called by: $9415, $94C0, $94FA
; ----------------------------------------------------------------------
b07_wait_and_draw:
    lda #$28
    jsr b07_delay_frames
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b07_inline_9527
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b07_inline_9527:
    ldy map_y
    lda b07_data_9570,y
    sta $0616                   ; Text window tile buffer.
    iny
    lda b07_data_9570,y
    sta $0617                   ; Text window tile buffer.
    iny
    sty map_y
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_953C:
    .incbin "build/assets/bank07_data.bin", $153C, $0002
    jsr load_text_graphics
    lda #$FB
    sta $A5
    ldy #$05
    jsr draw_text_window_small
    jsr return_inline_block

b07_data_954D:
    .incbin "build/assets/bank07_data.bin", $154D, $0002
    lda #$28
    jsr b07_delay_frames
    dec map_x
    bne b07_wait_and_draw
    rts
; ----------------------------------------------------------------------
; b07_delay_frames
;   Delay for A frames while servicing the screen.
;   called by: $940A, $941A, $9424, $94A6, $94B6, $94C5, $94CA, $94EE, $94F3, $94FF, $9504, $950E (+3 more)
; ----------------------------------------------------------------------
b07_delay_frames:
    sta party_scan
b07_loc_955B:
    jsr wait_vblank
    lda controller_prev
    and #$10
    bne b07_loc_9569
    dec party_scan
    bne b07_loc_955B
    rts
b07_loc_9569:
    ldx #$2E
    txs
    jmp b07_loc_9516

b07_data_956F:
    .incbin "build/assets/bank07_data.bin", $156F, $0001

b07_data_9570:
    .incbin "build/assets/bank07_data.bin", $1570, $01E6

b07_data_9756:
    .incbin "build/assets/bank07_data.bin", $1756, $0005

b07_data_975B:
    .incbin "build/assets/bank07_data.bin", $175B, $00A5

b07_data_9800:
    .incbin "build/assets/bank07_data.bin", $1800, $0400

b07_data_9C00:
    .incbin "build/assets/bank07_data.bin", $1C00, $005F

; ----------------------------------------------------------------------
; b07_party_screen_setup
;   Party/list screen setup: window, graphics, and bank switches.
; ----------------------------------------------------------------------
b07_party_screen_setup:
    ldy #$05
    jsr draw_window
    jsr screen_fade_in
    lda #$2D
    jsr sound_queue_add
    lda #$00
    sta text_graphics_index
    jsr load_text_graphics
    lda #$08
    sta $6010
    lda $6719
    ora #$01
    sta $6719
    lda #$80
    sta $63D5
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b07_inline_9C88
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b07_inline_9C88:
    jsr set_bank_13
    lda #$10
    jsr b13_data_9CBE           ; bank 13: b13_data_9CBE
    jsr return_inline_block

b07_data_9C93:
    .incbin "build/assets/bank07_data.bin", $1C93, $0002
    ldx #$00
    stx ppu_update_len
    lda #$A8
    sta ppu_update_off
b07_loc_9C9D:
    lda ppu_update_len
    sta $6090,x                 ; Party member order (actor ids).
    lda ppu_update_off
    sta $60A8,x                 ; Party member class/officer id.
    lda #$80
    sta $609C,x                 ; Party member state bits.
    inc ppu_update_len
    inc ppu_update_off
    inx
    cpx #$03
    bne b07_loc_9C9D
    ldx #$00
    stx $0510                   ; Per-actor state flags.
    stx $0520                   ; Per-actor state flags.
    inx
; ----------------------------------------------------------------------
; b07_party_list_draw
;   Draw the party/list screen entries.
; ----------------------------------------------------------------------
b07_party_list_draw:
    stx $0511                   ; Per-actor state flags.
    stx $0521                   ; Per-actor state flags.
    inx
    stx $0512                   ; Per-actor state flags.
    stx $0522                   ; Per-actor state flags.
    lda #$00
    sta text_menu_index
    sta text_menu_sub
    jsr draw_text_window
    jsr wait_vblank
; ----------------------------------------------------------------------
; b07_party_list_input
;   Party/list screen input/menu handling.
; ----------------------------------------------------------------------
b07_party_list_input:
    jsr b07_party_member_setup
    inc text_menu_index
    lda text_menu_index
    cmp #$08
    beq b07_loc_9CE8
    jsr b07_party_list_page
    jmp b07_party_list_input
b07_loc_9CE8:
    jsr b07_screen_fade_in
    lda #$00
    sta scroll_y
    sta scroll_x
    lda #$09
    sta text_graphics_index
    jsr load_text_graphics
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_9CFB:
    .incbin "build/assets/bank07_data.bin", $1CFB, $0002
    jsr screen_fade_out
    ldy #$0A
    jsr draw_text_window_small
    ldx #$C8
    jsr wait_frames
    ldx #$C8
    jsr wait_frames
    ldy #$0A
    jsr draw_window
    jsr b07_screen_fade_in
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b07_inline_9D1A
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b07_inline_9D1A:
    lda #$04
    jsr set_bank_a
    lda #$00
    ldx #$40
    ldy #$18
    jsr copy_to_vram            ; inline pointer/data follows the JSR

b07_data_9D28:
    .incbin "build/assets/bank07_data.bin", $1D28, $0002
    jsr return_inline_block

b07_data_9D2D:
    .incbin "build/assets/bank07_data.bin", $1D2D, $0002
    lda #$0F
    sta $03EC                   ; Small VRAM upload buffer.
    lda #$30
    sta $03ED                   ; Small VRAM upload buffer.
    lda #$10
    sta $03EE                   ; Small VRAM upload buffer.
    lda #$00
    sta $03EF                   ; Small VRAM upload buffer.
    sta vram_dma_pending
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_9D48:
    .incbin "build/assets/bank07_data.bin", $1D48, $0002
    jsr screen_fade_out
    ldy #$0A
    jsr draw_text_window_small
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b07_inline_9D55
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b07_inline_9D55:
    jsr set_bank_13
    lda #$10
    jsr b13_check_name_tile     ; bank 13: b13_check_name_tile
    jsr return_inline_block

b07_data_9D60:
    .incbin "build/assets/bank07_data.bin", $1D60, $0002
b07_loc_9D62:
    jsr wait_vblank
    jmp b07_loc_9D62            ; bank 13 target
; ----------------------------------------------------------------------
; b07_screen_fade_in
;   Fade the screen in before the list is drawn.
;   called by: $9CE8, $9D14
; ----------------------------------------------------------------------
b07_screen_fade_in:
    jsr screen_fade_in
    lda #$20
    ldx #$0A
    ldy #$55
    jmp set_ppu_scroll
; ----------------------------------------------------------------------
; b07_party_list_page
;   Draw one page of the party/list screen.
;   called by: $9CE2
; ----------------------------------------------------------------------
b07_party_list_page:
    jsr screen_fade_in
    lda #$00
    sta scroll_y
    sta scroll_x
    lda #$90
    sta PPUCTRL
    sta ppu_ctrl_shadow
    lda #$20
    ldx #$0A
    ldy #$55
    jsr set_ppu_scroll
    lda text_menu_index
    asl a
    pha
    tax
    lda b13_data_9F34,x
    ldx #$00
    stx loop_counter
    stx battle_flags
    jsr text_load_page
    ldy text_menu_index
    dey
    lda b13_data_9F44,y
    bne b07_loc_9DAF
    pla
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_9DAA:
    .incbin "build/assets/bank07_data.bin", $1DAA, $0002
    jmp b07_loc_9DC2
b07_loc_9DAF:
    pla
    tax
    lda b07_data_9F35,x
    ldx #$01
    stx loop_counter
    stx battle_flags
    jsr text_load_page
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_9DC0:
    .incbin "build/assets/bank07_data.bin", $1DC0, $0002
b07_loc_9DC2:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b07_inline_9DC5
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b07_inline_9DC5:
    ldy text_menu_sub
    lda b07_data_9F4C,y
    sta $0616                   ; Text window tile buffer.
    iny
    lda b07_data_9F4C,y
    sta $0617                   ; Text window tile buffer.
    iny
    sty text_menu_sub
    jsr draw_string             ; inline pointer/data follows the JSR

b07_data_9DDA:
    .incbin "build/assets/bank07_data.bin", $1DDA, $0002
    jsr return_inline_block

b07_data_9DDF:
    .incbin "build/assets/bank07_data.bin", $1DDF, $0002
    jsr screen_fade_out
    lda #$09
    sta text_graphics_index
    jsr load_text_graphics
    ldy #$0A
    jsr draw_text_window_small
    ldx #$96
    jsr wait_frames
    ldx #$96
    jsr wait_frames
    ldy #$0A
    jsr draw_window
    rts
; ----------------------------------------------------------------------
; b07_party_member_setup
;   Load a party member's actor/stats and prepare the battle-party arrays.
;   called by: $9CD7
; ----------------------------------------------------------------------
b07_party_member_setup:
    lda #$00
    sta $90
    lda #$0A
    sta $91
    lda text_menu_index
    asl a
    sta ppu_update_len
    asl a
    clc
    adc ppu_update_len
    tax
    ldy #$00
b07_loc_9E14:
    lda b07_data_A1BF,x
    sta text_x,y
    inx
    iny
    cpy #$04
    bne b07_loc_9E14
    lda #$80
    sta $0500                   ; Per-actor state flags.
    sta $0501                   ; Per-actor state flags.
    sta $0502                   ; Per-actor state flags.
    sta $0550                   ; Per-actor animation frame.
    lda #$00
    sta class_index
    lda b07_data_A1BF,x
    sta game_mode
    inx
    lda b07_data_A1BF,x
    sta level
    beq b07_loc_9E4D
    inc class_index
    cmp #$05
    bne b07_loc_9E4B
    inc class_index
    lda #$7F
    bne b07_loc_9E4D
b07_loc_9E4B:
    lda #$19
b07_loc_9E4D:
    sta party_index
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b07_inline_9E52
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b07_inline_9E52:
    jsr set_bank_14
    jsr b14_init_battle_party   ; bank 14: b14_init_battle_party
    jsr init_party_status
    jsr b14_field_load_area_screen; bank 14: b14_field_load_area_screen
    jsr return_inline_block

b07_data_9E61:
    .incbin "build/assets/bank07_data.bin", $1E61, $0002
    ldx #$FF
b07_loc_9E65:
    txa
    pha
    jsr update_frame
    pla
    tax
    dex
    bne b07_loc_9E65
    ldy #$05
    jsr draw_window
    ldx #$0F
b07_loc_9E76:
    lda #$00
    sta $0500,x                 ; Per-actor state flags.
    dex
    bpl b07_loc_9E76
    jsr clear_oam_shadow
    rts

b07_data:
    .incbin "build/assets/bank07_data.bin", $1E82, $00B2

b07_data_9F34:
    .incbin "build/assets/bank07_data.bin", $1F34, $0001

b07_data_9F35:
    .incbin "build/assets/bank07_data.bin", $1F35, $000F

b07_data_9F44:
    .incbin "build/assets/bank07_data.bin", $1F44, $0008

b07_data_9F4C:
    .incbin "build/assets/bank07_data.bin", $1F4C, $0273

b07_data_A1BF:
    .incbin "build/assets/bank07_data.bin", $21BF, $00C3

b07_data_A282:
    .incbin "build/assets/bank07_data.bin", $2282, $0400

b07_data_A682:
    .incbin "build/assets/bank07_data.bin", $2682, $0400

b07_data_AA82:
    .incbin "build/assets/bank07_data.bin", $2A82, $0400

b07_data_AE82:
    .incbin "build/assets/bank07_data.bin", $2E82, $0400

b07_data_B282:
    .incbin "build/assets/bank07_data.bin", $3282, $0400

b07_data_B682:
    .incbin "build/assets/bank07_data.bin", $3682, $0400

b07_data_BA82:
    .incbin "build/assets/bank07_data.bin", $3A82, $0400

b07_data_BE82:
    .incbin "build/assets/bank07_data.bin", $3E82, $017E

