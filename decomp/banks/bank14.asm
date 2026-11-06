; ======================================================================
; PRG bank 14  CPU $8000-$BFFF
; ======================================================================
; traced code: 1106 instructions / 2311 bytes; CDL code bytes: 1004
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$BFFF  b14_bank: Gameplay/menu bank: code plus embedded tables.
; ======================================================================

; Overlapping data aliases (tables referenced inside instructions)
b14_loc_BDA9 = $BDA9

; Region aliases
b14_bank = $8000

; ----------------------------------------------------------------------
; b14_game_bank_entry
;   Entry point for the gameplay/menu bank, called from the fixed bank.
; ----------------------------------------------------------------------
b14_game_bank_entry:
    jsr reset_text_engine
    lda game_mode
    jsr draw_status_panel
    lda #$03
    sta ppu_update_ptr_lo
    ldx #$00
    lda game_mode
    cpy #$16
    bne b14_loc_801A
    jsr find_next_actor
    jmp b14_menu_dispatch
b14_loc_801A:
    jsr set_cursor_from_table
    jsr find_next_actor_from_x
; ----------------------------------------------------------------------
; b14_menu_dispatch
;   Menu/command dispatch for the current game mode.
; ----------------------------------------------------------------------
b14_menu_dispatch:
    lda $0500,x                 ; Per-actor state flags.
    and #$02
    bne b14_loc_802F
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_802A:
    .dw b10_msg_index_001    ; text index $0001 -> b10_msg_001
    jmp wait_then_game_main
b14_loc_802F:
    ldx ppu_update_ptr_lo
    stx sound_temp
    lda $0500,x                 ; Per-actor state flags.
    and #$04
    bne b14_loc_8057
    lda game_mode
    eor #$01
    sta $0530,x                 ; Per-actor palette/facing.
    cmp #$02
    bne b14_loc_804F
    lda $0500,x                 ; Per-actor state flags.
    ora #$40
    sta $0500,x                 ; Per-actor state flags.
    bne b14_loc_8057
b14_loc_804F:
    lda $0500,x                 ; Per-actor state flags.
    and #$BF
    sta $0500,x                 ; Per-actor state flags.
b14_loc_8057:
    lda $05E0,x                 ; Per-actor level.
    sta ppu_addr_lo
    lda $05D0,x                 ; Per-actor status bits.
    and #$30
    lsr a
    lsr a
    lsr a
    lsr a
    sta ppu_addr_hi
    lda $05D0,x                 ; Per-actor status bits.
    and #$40
    beq b14_loc_8095
    ldx party_index
    lda #$FF
    sta ppu_update_ptr_lo
; ----------------------------------------------------------------------
; b14_menu_input
;   Menu cursor/input update.
; ----------------------------------------------------------------------
b14_menu_input:
    ror $6780,x
    ror $6700,x
    inc ppu_update_ptr_lo
    lda ppu_update_ptr_lo
    php
    cmp sound_temp
    bne b14_loc_8087
    plp
    php
    sec
    php
b14_loc_8087:
    cmp #$10
    beq b14_loc_808F
    plp
    jmp b14_menu_input
b14_loc_808F:
    plp
    plp
    bcc b14_loc_8095
    inc ppu_addr_lo
b14_loc_8095:
    jsr text_show_message       ; dynamic message index in $14/$15; text_show_message resolves it.
    jmp wait_then_game_main

b14_data_809B:
    .incbin "build/assets/bank14_data.bin", $009B, $0065

b14_data_8100:
    .incbin "build/assets/bank14_data.bin", $0100, $0100

b14_data_8200:
    .incbin "build/assets/bank14_data.bin", $0200, $00B0

b14_data_82B0:
    .incbin "build/assets/bank14_data.bin", $02B0, $0056

    ldx #$04
    jsr text_init
    jsr text_wait
    lda text_menu_index
    bne b14_loc_8315
    jmp b14_status_screen
b14_loc_8315:
    ldx #$03
    jsr text_init
    jsr text_wait
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    sta text_actor
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_836F
    and #$40
    bne b14_loc_8357
    lda $61A8,x                 ; Party member derived stats.
    cmp $619C,x                 ; Party member derived stats.
    bcc b14_loc_837A
    ldy #$06
b14_loc_8339:
    lda $609C,y                 ; Party member state bits.
    and #$BF
    sta $609C,y                 ; Party member state bits.
    dey
    bpl b14_loc_8339
    lda $609C,x                 ; Party member state bits.
    ora #$40
    sta $609C,x                 ; Party member state bits.
    jsr b14_close_menu
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8352:
    .dw b10_msg_index_021    ; text index $0015 -> b10_msg_021
    jmp wait_then_game_main
b14_loc_8357:
    lda $609C,x                 ; Party member state bits.
    and #$BF
    sta $609C,x                 ; Party member state bits.
    lda #$00
    sta $61FB                   ; Party calculation temporaries.
    jsr b14_close_menu
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_836A:
    .dw b10_msg_index_022    ; text index $0016 -> b10_msg_022
    jmp wait_then_game_main
b14_loc_836F:
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8375:
    .dw b10_msg_index_023    ; text index $0017 -> b10_msg_023
    jmp wait_then_game_main
b14_loc_837A:
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8380:
    .dw b10_msg_index_471    ; text index $01D7 -> b10_msg_471
    jmp wait_then_game_main
; ----------------------------------------------------------------------
; b14_close_menu
;   Close the current menu and restore the text engine.
;   called by: $834C, $8364
; ----------------------------------------------------------------------
b14_close_menu:
    lda #$02
    sta input_buttons
    ldx #$03
    jsr text_init
    lda #$00
    sta input_buttons
    jmp reset_text_engine
; ----------------------------------------------------------------------
; b14_status_screen
;   Officer status screen setup.
; ----------------------------------------------------------------------
b14_status_screen:
    ldx #$00
    stx party_scan
b14_loc_8399:
    lda $6090,x                 ; Party member order (actor ids).
    sta $0360,x                 ; Saved text tile rows for window redraw.
    bmi b14_loc_83A6
    inx
    cpx #$07
    bne b14_loc_8399
b14_loc_83A6:
    stx $71
    ldx #$0F
    lda #$FF
b14_loc_83AC:
    sta $0370,x
    dex
    bpl b14_loc_83AC
; ----------------------------------------------------------------------
; b14_status_update
;   Officer status screen per-frame update.
; ----------------------------------------------------------------------
b14_status_update:
    ldx #$00
b14_loc_83B4:
    lda $0370,x
    sta $6090,x                 ; Party member order (actor ids).
    inx
    cpx $71
    bne b14_loc_83B4
    ldx #$05
    jsr text_init
    ldx #$00
b14_loc_83C6:
    lda $0360,x                 ; Saved text tile rows for window redraw.
    sta $6090,x                 ; Party member order (actor ids).
    inx
    cpx $71
    bne b14_loc_83C6
    ldx #$03
    jsr text_init
    lda $54
    sec
    sbc party_scan
    sta $54
    lda party_scan
    cmp $71
    beq b14_loc_8413
    jsr text_wait_loop
    bcc b14_loc_83EB
    jmp b14_battle_party_loop
b14_loc_83EB:
    jsr text_draw_cursor
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    ldy party_scan
    sta $0370,y
    txa
    sta $0378,y
    inc party_scan
b14_loc_83FE:
    cpx #$06
    beq b14_loc_840B
    lda $0361,x                 ; Saved text tile rows for window redraw.
    sta $0360,x                 ; Saved text tile rows for window redraw.
    inx
    bne b14_loc_83FE
b14_loc_840B:
    lda #$FF
    sta $0360,x                 ; Saved text tile rows for window redraw.
    jmp b14_status_update
b14_loc_8413:
    ldx #$00
b14_loc_8415:
    lda $0370,x
    sta $6090,x                 ; Party member order (actor ids).
    inx
    cpx $71
    bne b14_loc_8415
b14_loc_8420:
    jsr update_frame
    lda controller_state
    and #$C0
    beq b14_loc_8420
    jsr b14_init_battle_party
    jmp b14_loc_8498
; ----------------------------------------------------------------------
; b14_init_battle_party
;   Initialise the battle party arrays.
;   called by: $8429
; ----------------------------------------------------------------------
b14_init_battle_party:
    ldx #$10
    stx screen_brightness
    ldx #$FF
    stx party_scan2
    inx
    stx party_scan
    ldx #$02
b14_loc_843C:
    asl $0500,x                 ; Per-actor state flags.
    lsr $0500,x                 ; Per-actor state flags.
    dex
    bpl b14_loc_843C
b14_loc_8445:
    inc party_scan2
    ldx party_scan2
    cpx #$07
    beq b14_loc_846B
    ldy $6090,x                 ; Party member order (actor ids).
    bmi b14_loc_846B
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_8445
    ldx party_scan
    asl $0500,x                 ; Per-actor state flags.
    sec
    ror $0500,x                 ; Per-actor state flags.
    jsr update_party_portrait
    inc party_scan
    lda party_scan
    cmp #$03
    bne b14_loc_8445
b14_loc_846B:
    rts
; ----------------------------------------------------------------------
; b14_battle_party_loop
;   Battle party initialisation loop.
; ----------------------------------------------------------------------
b14_battle_party_loop:
    dec party_scan
    ldx party_scan
    bmi b14_loc_8498
    ldy $0378,x
    cpy #$06
    beq b14_loc_848A
    ldy #$05
b14_loc_847B:
    lda $0360,y                 ; Saved text tile rows for window redraw.
    sta $0361,y                 ; Saved text tile rows for window redraw.
    tya
    cmp $0378,x
    beq b14_loc_848A
    dey
    bpl b14_loc_847B
b14_loc_848A:
    lda $0370,x
    sta $0360,y                 ; Saved text tile rows for window redraw.
    lda #$FF
    sta $0370,x
    jmp b14_status_update
b14_loc_8498:
    lda #$00
    sta $71
    jmp game_main
    ldx #$03
    jsr text_init
    jsr text_wait
    jmp b14_loc_84F8
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_84AD
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_84AD:
    jsr set_bank_12
    ldy $54
    lda $6090,y                 ; Party member order (actor ids).
    bmi b14_loc_84D1
    tay
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_84C1
    lda #$0E
    bne b14_loc_84C7
b14_loc_84C1:
    and #$40
    beq b14_loc_84CB
    lda #$0F
b14_loc_84C7:
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
b14_loc_84CB:
    lda $60A8,y                 ; Party member class/officer id.
    jsr load_party_member_stats
b14_loc_84D1:
    ldy $54
    cpy #$06
    beq b14_loc_84F2
    lda text_col
    sec
    sbc #$04
    sta text_col
    ldy $54
    lda $6091,y                 ; Party member order (actor ids).
    bpl b14_loc_84F2
    ldy $71
    beq b14_loc_84EE
    dey
    cpy $54
    bne b14_loc_84F2
b14_loc_84EE:
    lda #$08
    sta text_col
b14_loc_84F2:
    jsr return_inline_block

b14_data_84F5:
    .incbin "build/assets/bank14_data.bin", $04F5, $0002
    rts
b14_loc_84F8:
    jsr b14_party_status_update

b14_data_84FB:
    .incbin "build/assets/bank14_data.bin", $04FB, $0003
; ----------------------------------------------------------------------
; b14_party_status_update
;   Update the party status panel.
;   called by: $84F8
; ----------------------------------------------------------------------
b14_party_status_update:
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    sta text_actor
    tax
    jsr b14_calc_party_stat
    ldx text_actor
    lda $61A8,x                 ; Party member derived stats.
    cmp $619C,x                 ; Party member derived stats.
    bcs b14_loc_8518

b14_data_8513:
    .incbin "build/assets/bank14_data.bin", $0513, $0005
b14_loc_8518:
    jsr load_party_member_record
    jsr battle_intro_screen
    jsr status_message
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_8524:
    .incbin "build/assets/bank14_data.bin", $0524, $0002
    jsr wait_vblank
    lda #$A1
    sta input_buttons
    dec $AA
    ldx #$1B
    jsr text_init
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bmi b14_loc_8543

b14_data_853B:
    .incbin "build/assets/bank14_data.bin", $053B, $0008
b14_loc_8543:
    inc $AA
    lda #$10
    sta $A9
    ldx #$08
    jsr text_init
    ldx #$2D
    jsr text_init
    lda #$00
    sta party_scan
    lda #$81
    sta input_buttons
    ldx #$09
    jsr text_init
    dec input_buttons
    lda #$00
    sta $70
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_8569:
    .incbin "build/assets/bank14_data.bin", $0569, $0002
    jsr wait_vblank
    ldx #$0B
    jsr text_init
    ldx #$0A
    jsr text_init
    jmp loc_D44C
    ldy party_scan
    lda b14_data_85F8,y
    sta copy_src_lo
    lda b14_data_85FD,y
    sta copy_src_hi
    ldy text_actor
    lda $54
    cmp #$02
    bne b14_loc_8596
    lda $60C0,y
    tay
    jmp b14_loc_85A3
b14_loc_8596:
    cmp #$04
    bne b14_loc_85A3
    ldy #$00
    lda text_actor
    cmp #$07
    bcc b14_loc_85A3

b14_data_85A2:
    .incbin "build/assets/bank14_data.bin", $05A2, $0001
b14_loc_85A3:
    inc party_scan
    lda ($18),y
    sta $03
    lda #$00
    sta $04
    sta $05
    jsr copy_pointer_triplet
    lda #$02
    jsr read_stack_arg
    inx
    inx
    lda ($18),y
    pha
    sec
b14_loc_85BD:
    pla
    sbc #$1A
    bcc b14_loc_85CC
    pha
    lda #$F4
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    sec
    bcs b14_loc_85BD
b14_loc_85CC:
    adc #$0D
    bcc b14_loc_85D6
    lda #$F3
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
b14_loc_85D6:
    rts

b14_data_85D7:
    .incbin "build/assets/bank14_data.bin", $05D7, $0021

b14_data_85F8:
    .incbin "build/assets/bank14_data.bin", $05F8, $0005

b14_data_85FD:
    .incbin "build/assets/bank14_data.bin", $05FD, $0019
    lda #$F6
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    lda #$F8
    sta $0319,x                 ; Bottom 8x8 tiles for the four text lines.
    lda #$F7
    sta $031A,x                 ; Bottom 8x8 tiles for the four text lines.
    ldx #$35
    rts
    lda text_actor
    asl a
    asl a
    tay
    lda #$60
    sta $00
    lda #$61
    sta $01
    jsr read_pointer_triplet
    lda #$05
    jmp read_stack_arg
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_8640
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_8640:
    jsr set_bank_12
    lda text_actor
    asl a
    asl a
    asl a
    adc $70
    tay
    lda $54
    cmp #$02
    beq b14_loc_8658
    lda text_col
    sec
    sbc #$04
    sta text_col
b14_loc_8658:
    lda $70
    cmp #$08
    bcs b14_loc_8677
    inc $70
    lda $6100,y                 ; Party member stats.
    bmi b14_loc_8668
    iny
    bne b14_loc_8658
b14_loc_8668:
    tay
    jsr load_item_data
    txa
    and #$30
    bne b14_loc_8675
    ldx #$0B
    bne b14_loc_8677
b14_loc_8675:
    ldx #$3B
b14_loc_8677:
    jsr return_inline_block

b14_data_867A:
    .incbin "build/assets/bank14_data.bin", $067A, $0002
    rts
; ----------------------------------------------------------------------
; b14_delay_frames
;   Delay for a fixed number of frames.
; ----------------------------------------------------------------------
b14_delay_frames:
    ldx #$06
b14_loc_867F:
    jsr load_party_hp
    dex
    bpl b14_loc_867F
    rts
    ldx #$03
    jsr text_init
    jsr text_wait
    jmp b14_loc_8703
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_8694
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_8694:
    jsr set_bank_12
    lda text_actor
    asl a
    asl a
    asl a
    ldy text_busy
    bne b14_loc_86A4
    adc $54
    bpl b14_loc_86A6
b14_loc_86A4:
    adc battle_anim
b14_loc_86A6:
    tay
    lda text_mode
    cmp #$0F
    bne b14_loc_86B3
    lda $54
    cmp #$06
    beq b14_loc_86C3
b14_loc_86B3:
    lda $54
    cmp #$07
    beq b14_loc_86C3
    lda text_busy
    bne b14_loc_86C3
    lda input_buttons
    bpl b14_loc_86C7
    bmi b14_loc_86CC
b14_loc_86C3:
    lda text_col
    bne b14_loc_86D3
b14_loc_86C7:
    lda $6101,y                 ; Party member stats.
    beq b14_loc_86C3
b14_loc_86CC:
    lda text_col
    sec
    sbc #$04
    sta text_col
b14_loc_86D3:
    pha
    lda $6100,y                 ; Party member stats.
    beq b14_loc_86FA
    tay
    bpl b14_loc_86E6
    lda text_busy
    bne b14_loc_86E6
    lda #$0E
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
b14_loc_86E6:
    lda text_busy
    beq b14_loc_86EC
    inc battle_anim
b14_loc_86EC:
    jsr load_item_data
    txa
    and #$30
    bne b14_loc_86F8
    ldx #$0B
    bne b14_loc_86FA
b14_loc_86F8:
    ldx #$3B
b14_loc_86FA:
    pla
    sta text_col
    jsr return_inline_block

b14_data_8700:
    .incbin "build/assets/bank14_data.bin", $0700, $0002
    rts
b14_loc_8703:
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    sta text_actor
    jsr b14_check_party_slot
    bne b14_loc_871D

b14_data_870F:
    .incbin "build/assets/bank14_data.bin", $070F, $000E
b14_loc_871D:
    jsr load_party_member_record
    ldx #$06
    jsr text_init
    jsr text_wait

b14_data_8728:
    .incbin "build/assets/bank14_data.bin", $0728, $00D8

b14_data_8800:
    .incbin "build/assets/bank14_data.bin", $0800, $0148

; ----------------------------------------------------------------------
; b14_check_party_slot
;   Check whether a party slot is empty.
;   called by: $870A
; ----------------------------------------------------------------------
b14_check_party_slot:
    asl a
    asl a
    asl a
    tax
    ldy #$08
b14_loc_894E:
    lda $6100,x                 ; Party member stats.
    bne b14_loc_8957
    inx
    dey
    bne b14_loc_894E
b14_loc_8957:
    rts

b14_data_8958:
    .incbin "build/assets/bank14_data.bin", $0958, $02A8

b14_data_8C00:
    .incbin "build/assets/bank14_data.bin", $0C00, $0400

b14_data_9000:
    .incbin "build/assets/bank14_data.bin", $1000, $0400

b14_data_9400:
    .incbin "build/assets/bank14_data.bin", $1400, $019E

; ----------------------------------------------------------------------
; b14_field_transition_a
;   Field/battle transition: restore the field screen and graphics.
; ----------------------------------------------------------------------
b14_field_transition_a:
    jsr b14_find_injured_member
    jsr battle_intro_screen
    jsr screen_fade_in
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_95AA
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_95AA:
    lda #$01
    jsr set_bank_a
    ldy #$1C
    lda #$08
    ldx #$18
    jsr copy_to_vram
    brk

b14_data_95B9:
    .incbin "build/assets/bank14_data.bin", $15B9, $0247

b14_data_9800:
    .incbin "build/assets/bank14_data.bin", $1800, $0373

; ----------------------------------------------------------------------
; b14_field_transition_b
;   Field/battle transition: return to the field and refresh the party.
; ----------------------------------------------------------------------
b14_field_transition_b:
    jsr b14_field_transition_body
    jmp data_CF19
; ----------------------------------------------------------------------
; b14_field_transition_body
;   Body of the field/battle transition routine.
;   called by: $9B73
; ----------------------------------------------------------------------
b14_field_transition_body:
    inc text_busy
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_9B7E
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_9B7E:
    jsr set_bank_13
    jsr b13_fade_out_wait       ; bank 13: b13_fade_out_wait
    jsr return_inline_block
b14_data_9B87:
    dey

b14_data_9B88:
    .incbin "build/assets/bank14_data.bin", $1B88, $0078

b14_data_9C00:
    .incbin "build/assets/bank14_data.bin", $1C00, $03FE

b14_data_9FFE:
    .incbin "build/assets/bank14_data.bin", $1FFE, $0002

b14_data_A000:
    .incbin "build/assets/bank14_data.bin", $2000, $0400

b14_data_A400:
    .incbin "build/assets/bank14_data.bin", $2400, $01BD

b14_data_A5BD:
    .incbin "build/assets/bank14_data.bin", $25BD, $0101

b14_data_A6BE:
    .incbin "build/assets/bank14_data.bin", $26BE, $0142

b14_data_A800:
    .incbin "build/assets/bank14_data.bin", $2800, $0400

b14_data_AC00:
    .incbin "build/assets/bank14_data.bin", $2C00, $0400

b14_data_B000:
    .incbin "build/assets/bank14_data.bin", $3000, $0400

b14_data_B400:
    .incbin "build/assets/bank14_data.bin", $3400, $000E

; ----------------------------------------------------------------------
; b14_officer_list_screen
;   Officer list/roster screen.
; ----------------------------------------------------------------------
b14_officer_list_screen:
    txa
    pha
    tya
    pha
    lda $639D
    cmp #$98
    bne b14_loc_B426
    lda $6026
    cmp #$05
    bne b14_loc_B426
    lda #$4B
    sta game_submode
    bne b14_loc_B436
b14_loc_B426:
    lda $63B7
    bpl b14_loc_B43B
    lda $6026
    cmp #$06
    bne b14_loc_B43B
    lda #$4F
    sta game_submode
b14_loc_B436:
    pla
    pla
    pla
    pla
    rts
b14_loc_B43B:
    ldx #$1F
    lda #$00
b14_loc_B43F:
    sta $0310,x                 ; Top 8x8 tiles for the four text lines.
    dex
    bpl b14_loc_B43F
    lda #$00
    sta party_scan
    ldy #$E0
b14_loc_B44B:
    lda $6300,y
    and #$10
    beq b14_loc_B472
    tya
    pha
    lda ppu_update_ptr_hi
    pha
    lda #$02
    jsr read_party_stat_byte
    sta ppu_update_ptr_lo
    pla
    sta ppu_update_ptr_hi
    pla
    tay
    lda ppu_update_ptr_lo
    cmp $6026
    bne b14_loc_B472
    ldx party_scan
    inc party_scan
    tya
    sta $0310,x                 ; Top 8x8 tiles for the four text lines.
b14_loc_B472:
    dey
    bne b14_loc_B44B
    jsr read_input_state
    lda rng0
    adc rng1
    adc rng2
    adc rng3
    sta party_scan2
    pla
    tay
    pla
    tax
    rts
; ----------------------------------------------------------------------
; b14_init_party_slots
;   Initialise the seven party slots.
; ----------------------------------------------------------------------
b14_init_party_slots:
    jsr b14_init_party_loop
    jmp b14_copy_active_party
; ----------------------------------------------------------------------
; b14_init_party_loop
;   Loop over the seven party slots.
;   called by: $B487
; ----------------------------------------------------------------------
b14_init_party_loop:
    ldy #$06
b14_loc_B48F:
    jsr b14_party_member_setup
    dey
    bpl b14_loc_B48F
    rts
; ----------------------------------------------------------------------
; b14_copy_active_party
;   Copy active party members into the battle arrays.
; ----------------------------------------------------------------------
b14_copy_active_party:
    ldx #$06
b14_loc_B498:
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_B4A1
    txa
    jsr b14_copy_party_stats
b14_loc_B4A1:
    dex
    bpl b14_loc_B498
    rts
; ----------------------------------------------------------------------
; b14_copy_party_stats
;   Copy one member's stats to the battle array.
;   called by: $B49E
; ----------------------------------------------------------------------
b14_copy_party_stats:
    asl a
    asl a
    tay
    lda $6160,y                 ; Party member derived stats.
    sta $60D0,y                 ; Party member stats.
    lda $6161,y                 ; Party member derived stats.
    sta $60D1,y                 ; Party member stats.
    lda $6162,y                 ; Party member derived stats.
    sta $60D2,y                 ; Party member stats.
    rts

b14_data_B4BB:
    .incbin "build/assets/bank14_data.bin", $34BB, $000A
; ----------------------------------------------------------------------
; b14_party_member_setup
;   Set up one party member's battle record.
;   called by: $B48F
; ----------------------------------------------------------------------
b14_party_member_setup:
    tya
    pha
    lda $6090,y                 ; Party member order (actor ids).
    tay
    asl a
    asl a
    sta copy_src_lo
    lda $60A8,y                 ; Party member class/officer id.
    tay
    lda #$07
    jsr read_party_stat_byte
    bmi b14_loc_B506
    asl a
    sta copy_src_hi
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_B4E0
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_B4E0:
    lda #$0C
    jsr set_bank_b
    lda #$D0
    sta ppu_update_ptr_lo
    lda #$BE
    sta ppu_update_ptr_hi
    ldx copy_src_lo
    ldy copy_src_hi
    lda ($F3),y
    sta $6160,x                 ; Party member derived stats.
    iny
    lda ($F3),y
    sta $6161,x                 ; Party member derived stats.
    lda #$00
    sta $6162,x                 ; Party member derived stats.
    jsr return_inline_block

b14_data_B504:
    .incbin "build/assets/bank14_data.bin", $3504, $0002
b14_loc_B506:
    and #$7F
    tay
    lda #$64
    sta ptr0_lo
    ldx #$01
    stx ppu_addr_hi
    dex
    stx ptr0_hi
    stx ptr1_lo
    stx ppu_update_len
    inc ppu_update_len
    ldx #$04
b14_loc_B51C:
    lda b12_data_B582,x
    cmp ppu_update_len
    beq b14_data_B528
    dex
    bpl b14_loc_B51C
    bmi b14_loc_B529

b14_data_B528:
    .incbin "build/assets/bank14_data.bin", $3528, $0001
b14_loc_B529:
    lda ppu_update_len
    cmp $6073
    beq b14_loc_B555

b14_data_B530:
    .incbin "build/assets/bank14_data.bin", $3530, $0025
b14_loc_B555:
    ldx copy_src_lo
    lda ptr0_lo
    sta $6160,x                 ; Party member derived stats.
    lda ptr0_hi
    sta $6161,x                 ; Party member derived stats.
    lda ptr1_lo
    sta $6162,x                 ; Party member derived stats.
    pla
    tay
    rts

b14_data_B569:
    .incbin "build/assets/bank14_data.bin", $3569, $0019

b14_data_B582:
    .incbin "build/assets/bank14_data.bin", $3582, $01A1

    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_B726
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_B726:
    jsr set_bank_12
    ldy text_busy
    bne b14_loc_B739
    lda text_actor
    asl a
    sta ppu_update_ptr_lo
    asl a
    adc ppu_update_ptr_lo
    adc $54
    bpl b14_loc_B740
b14_loc_B739:
    jsr data_DEBC
    tya
    clc
    adc battle_anim
b14_loc_B740:
    tay
    lda text_mode
    cmp #$0F
    bne b14_loc_B74D
    lda $54
    cmp #$04
    beq b14_loc_B75D
b14_loc_B74D:
    lda $54
    cmp #$05
    beq b14_loc_B75D
    lda text_busy
    bne b14_loc_B75D
    lda input_buttons
    bpl b14_loc_B761
    bmi b14_loc_B766
b14_loc_B75D:
    lda text_col
    bne b14_loc_B76D
b14_loc_B761:
    lda $65A1,y
    beq b14_loc_B75D
b14_loc_B766:
    lda text_col
    sec
    sbc #$04
    sta text_col
b14_loc_B76D:
    pha
    lda $65A0,y
    beq b14_loc_B788
    tay
    lda text_busy
    beq b14_loc_B77A
    inc battle_anim
b14_loc_B77A:
    jsr draw_item_name
    txa
    and #$30
    bne b14_loc_B786
    ldx #$0B
    bne b14_loc_B788
b14_loc_B786:
    ldx #$3B
b14_loc_B788:
    pla
    sta text_col
    jsr return_inline_block

b14_data_B78E:
    .incbin "build/assets/bank14_data.bin", $378E, $0002
    rts
; ----------------------------------------------------------------------
; b14_officer_status_screen
;   Officer status screen and stat display.
; ----------------------------------------------------------------------
b14_officer_status_screen:
    stx cursor_blink
    ldy $60A8,x                 ; Party member class/officer id.
    lda #$01
    jsr read_party_stat_byte
    sta ptr0_lo
    txa
    asl a
    sta ppu_update_ptr_lo
    asl a
    adc ppu_update_ptr_lo
    sta ptr0_hi
    tay
    lda #$06
    sta ppu_update_ptr_lo
    lda #$00
b14_loc_B7AD:
    sta $65A0,y
    iny
    dec ppu_update_ptr_lo
    bne b14_loc_B7AD
    cpx #$07
    bcc b14_loc_B7C7

b14_data_B7B9:
    .incbin "build/assets/bank14_data.bin", $37B9, $000E
b14_loc_B7C7:
    lda $61A8,x                 ; Party member derived stats.
    cmp $619C,x                 ; Party member derived stats.
    bcs b14_loc_B7D2
    jmp b14_loc_B852
b14_loc_B7D2:
    lda $6073
    sta $7F
    lda #$01
    sta ppu_update_ptr_hi
b14_loc_B7DB:
    ldy ppu_update_ptr_hi
    ldx b14_data_B884,y
    lda b14_data_B8F4,x
    cmp ptr0_lo
    beq b14_loc_B7E9
    bcs b14_loc_B81D
b14_loc_B7E9:
    lda b14_data_B8D5,x
    sta ppu_update_ptr_lo
    lda b14_data_B8B6,x
    clc
    adc ptr0_hi
    tay
    ldx $65A0,y
    lda b14_data_B8D5,x
    beq b14_loc_B801

b14_data_B7FD:
    .incbin "build/assets/bank14_data.bin", $37FD, $0003

b14_data_B800:
    .incbin "build/assets/bank14_data.bin", $3800, $0001
b14_loc_B801:
    ldx ppu_update_ptr_hi
    lda b14_data_B884,x
    ldx cursor_blink
    cpx #$07
    bcc b14_loc_B814

b14_data_B80C:
    .incbin "build/assets/bank14_data.bin", $380C, $0008
b14_loc_B814:
    cmp text_command
    sta $65A0,y
    bne b14_loc_B81D
    inc ptr1_lo
b14_loc_B81D:
    inc ppu_update_ptr_hi
    lda ppu_update_ptr_hi
    cmp $7F
    beq b14_loc_B7DB
    bcc b14_loc_B7DB
    lda #$07
    sta ppu_update_ptr_lo
    lda #$06
    sta ppu_update_ptr_hi
    lda ptr0_hi
    tay
    tax
    dex
b14_loc_B834:
    inx
    dec ppu_update_ptr_lo
    beq b14_loc_B848
    lda $65A0,x
    beq b14_loc_B834
    sta $65A0,y
    iny
    dec ppu_update_ptr_hi
    bne b14_loc_B834
    beq b14_loc_B852
b14_loc_B848:
    lda #$00
b14_loc_B84A:
    sta $65A0,y
    iny
    dec ppu_update_ptr_hi
    bne b14_loc_B84A
b14_loc_B852:
    ldx cursor_blink
    rts
; ----------------------------------------------------------------------
; b14_find_injured_member
;   Find a party member with the $C0/injured state bit.
;   called by: $959E
; ----------------------------------------------------------------------
b14_find_injured_member:
    ldx #$06
b14_loc_B857:
    lda $609C,x                 ; Party member state bits.
    cmp #$C0
    beq b14_calc_party_stat
    dex
    bpl b14_loc_B857
    bmi b14_loc_B87E
; ----------------------------------------------------------------------
; b14_calc_party_stat
;   Calculate a party member's derived stat.
;   called by: $8506
; ----------------------------------------------------------------------
b14_calc_party_stat:
    lda #$00
    sta ptr0_hi
    sta ptr1_lo
    lda $61A8,x                 ; Party member derived stats.
    sta ptr0_lo
    lda $61F8                   ; Party calculation temporaries.
    sta ppu_addr_hi
    jsr rng_seed
    lda ptr0_hi
    sec
    sbc $61FE
    bcs b14_loc_B880
b14_loc_B87E:
    lda #$00
b14_loc_B880:
    sta $61FB                   ; Party calculation temporaries.
    rts

b14_data_B884:
    .incbin "build/assets/bank14_data.bin", $3884, $0032

b14_data_B8B6:
    .incbin "build/assets/bank14_data.bin", $38B6, $001F

b14_data_B8D5:
    .incbin "build/assets/bank14_data.bin", $38D5, $001F

b14_data_B8F4:
    .incbin "build/assets/bank14_data.bin", $38F4, $030C

b14_data_BC00:
    .incbin "build/assets/bank14_data.bin", $3C00, $0079

; ----------------------------------------------------------------------
; b14_scan_bank7_table_a
;   Scan a bank 7 table for a matching map/position entry (variant A).
; ----------------------------------------------------------------------
b14_scan_bank7_table_a:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_BC7C
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_BC7C:
    lda #$07
    jsr set_bank_b
    ldx #$00
b14_loc_BC83:
    lda b07_map_data,x
    sta copy_dst_lo
    lda b07_data_8100,x
    sta copy_dst_hi
    ldy #$00
    lda ($1A),y
    and #$3F
    cmp text_x
    bne b14_loc_BCC4
    iny
    lda ($1A),y
    cmp text_y
    bne b14_loc_BCC4
    iny
    lda ($1A),y
    sta cursor_x2
    iny
    lda ($1A),y
    sta cursor_y2
    lda #$02
    sta ppu_update_len
b14_loc_BCAC:
    lda cursor_x2
    cmp text_x2
    bne b14_loc_BCB8
    lda cursor_y2
    cmp text_y2
    beq b14_loc_BCD3
b14_loc_BCB8:
    dec ppu_update_len
    beq b14_loc_BCC4
    lda #$01
    jsr cursor_add_y_signed
    sec
    bcs b14_loc_BCAC
b14_loc_BCC4:
    inx
    cpx #$F0
    bne b14_loc_BC83
    lda #$FF
    sta $86
    jsr return_inline_block
b14_data_BCD0:
    cmp ($BC),y
    rts
b14_loc_BCD3:
    lda party_index
    ldx $6011
    sta $6012,x
    inc $6011
    lda $6011
    asl a
    asl a
    tax
    ldy #$00
b14_loc_BCE6:
    lda text_x,y
    sta $6016,x
    inx
    iny
    cpy #$04
    bne b14_loc_BCE6
    ldy #$08
    lda ($1A),y
    cmp #$21
    bne b14_loc_BD2A
    lda $6572
    beq b14_loc_BD2A
    lda #$1A
    sta text_y
    lda #$0E
    sta text_x
    lda #$0A
    sta text_y2
    lda #$0F
    sta text_x2
    ldx $6011
    lda #$51
    sta $6012,x
    sta party_index
    tax
    lda $6700,x
    ora #$02
    sta $6700,x
    lda #$00
    sta $90
    sta game_mode
    beq b14_loc_BD5D
b14_loc_BD2A:
    ldy #$04
    ldx #$00
b14_loc_BD2E:
    lda ($1A),y
    sta text_x,x
    iny
    inx
    cpx #$04
    bne b14_loc_BD2E
    ldy #$00
    sty $90
    lda ($1A),y
    and #$C0
    clc
    rol a
    rol a
    rol a
    and #$03
    sta game_mode
    ldx $6011
    ldy #$08
    lda ($1A),y
    sta $6012,x
    sta party_index
    tax
    lda $6700,x
    ora #$02
    sta $6700,x
b14_loc_BD5D:
    jsr return_inline_block
b14_data_BD60:
    adc ($BD,x)
    lda #$FF
    jsr sound_queue_add_once
    lda #$10
    jsr sound_queue_add
    ldy #$05
    jsr draw_window
    jsr init_party_status
    jmp b14_loc_BEF3
; ----------------------------------------------------------------------
; b14_scan_bank7_table_b
;   Scan a bank 7 table for a matching map/position entry (variant B).
; ----------------------------------------------------------------------
b14_scan_bank7_table_b:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_BD7A
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_BD7A:
    lda #$07
    jsr set_bank_b
    ldx #$00
b14_loc_BD81:
    stx ppu_update_len
    lda b07_data_8200,x
    sta copy_dst_lo
    lda b07_data_82B0,x
    sta copy_dst_hi
    ldy #$00
b14_loc_BD8F:
    lda ($1A),y
    cmp text_x,y
    bne b14_loc_BD9D
    iny
    cpy #$04
    bne b14_loc_BD8F
    beq b14_loc_BDA9
b14_loc_BD9D:
    ldx ppu_update_len
    inx
    cpx #$B0
    bne b14_loc_BD81
    jsr return_inline_block
b14_data_BDA7:
    rol b14_data_A6BE
    .incbin "build/assets/bank14_data.bin", $3DAA, $0001
    lda $6700,x
    ora #$04
    sta $6700,x
    lda ($1A),y
    sta $90
    and #$0F
    sta text_x
    iny
    lda ($1A),y
    sta text_y
    iny
    lda ($1A),y
    sta text_x2
    iny
    lda ($1A),y
    sta text_y2
    iny
    lda ($1A),y
    sta party_index
    lda $90
    and #$60
    clc
b14_loc_BDD4:
    rol a
    rol a
    rol a
    rol a
    sta game_mode
    jsr return_inline_block
b14_data_BDDD:
    dec b14_data_A5BD,x
    bcc b14_loc_BE0B
    bpl b14_loc_BDD4
    and $A2

b14_data_BDE6:
    .incbin "build/assets/bank14_data.bin", $3DE6, $0025
b14_loc_BE0B:
    ora task_state

b14_data_BE0D:
    .incbin "build/assets/bank14_data.bin", $3E0D, $00E6

b14_loc_BEF3:
    lda #$01
    sta $91
    jsr b14_battle_setup_tail
    pla
    pla
    jmp loc_F3EF
; ----------------------------------------------------------------------
; b14_battle_setup_tail
;   Tail of the battle setup: item category and display refresh.
;   called by: $BEF7
; ----------------------------------------------------------------------
b14_battle_setup_tail:
    jsr b14_get_item_category
    jsr b14_battle_setup
    jsr b14_draw_battle_status
    rts
; ----------------------------------------------------------------------
; b14_battle_setup
;   Set up the battle/field display for the current game mode.
;   called by: $BF02
; ----------------------------------------------------------------------
b14_battle_setup:
    ldx #$02
b14_loc_BF0B:
    lda game_mode
    jsr set_actor_palette
    dex
    bpl b14_loc_BF0B
    jsr set_scroll_from_cursor
    lda $90
    and #$10
    bne b14_loc_BF45
    jsr screen_fade_in
    lda game_mode
    pha
    jsr render_map_column
    pla
    sta game_mode
    jsr draw_battle_panel
    jsr battle_main
    lda level
    sta text_graphics_index
    jsr load_text_graphics
    jsr update_oam
    ldx $91
    jsr wait_frames
    jsr screen_fade_out
    ldy #$05
    jsr draw_text_window_small
b14_loc_BF45:
    rts
; ----------------------------------------------------------------------
; b14_get_item_category
;   Look up an item's category/equipment slot.
;   called by: $BEFF
; ----------------------------------------------------------------------
b14_get_item_category:
    lda #$00
    sta class_index
    lda party_index
    lsr a
    tay
    lda b14_data_BF98,y
    bcs b14_loc_BF57
    lsr a
    lsr a
    lsr a
    lsr a
b14_loc_BF57:
    and #$0F
    sta level
    beq b14_loc_BF65
    inc class_index
    cmp #$04
    bcc b14_loc_BF65
    inc class_index
b14_loc_BF65:
    rts
; ----------------------------------------------------------------------
; b14_draw_battle_status
;   Draw the battle status text/selection fields.
;   called by: $BF05
; ----------------------------------------------------------------------
b14_draw_battle_status:
    lda $6553
    and #$04
    beq b14_loc_BF71
    lda #$21
    bne b14_loc_BF8D
b14_loc_BF71:
    lda party_index
    cmp #$7F
    bne b14_loc_BF7B
    lda #$20
    bne b14_loc_BF8D
b14_loc_BF7B:
    ldx level
    lda b14_data_BF91,x
    cpx #$00
    bne b14_loc_BF8D
    ldy $6010
    cpy #$06
    bcc b14_loc_BF8D
    lda #$28
b14_loc_BF8D:
    jsr sound_queue_add_once
    rts

b14_data_BF91:
    .incbin "build/assets/bank14_data.bin", $3F91, $0007

b14_data_BF98:
    .incbin "build/assets/bank14_data.bin", $3F98, $0041

b14_data_BFD9:
    .incbin "build/assets/bank14_data.bin", $3FD9, $0027

