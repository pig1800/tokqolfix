; ======================================================================
; PRG bank 14  CPU $8000-$BFFF
; ======================================================================
; traced code: 5366 instructions / 11761 bytes; CDL code bytes: 5173
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$BFFF  b14_bank: Gameplay/menu bank: code plus embedded tables.
; ======================================================================

; Overlapping data aliases (tables referenced inside instructions)
b14_data_8100 = $8100
b14_data_82B0 = $82B0
b14_data_82E0 = $82E0
b14_data_82E1 = $82E1
b14_data_8800 = $8800
b14_data_8880 = $8880
b14_data_8C00 = $8C00
b14_data_9800 = $9800
b14_data_9A33 = $9A33
b14_data_A100 = $A100
b14_data_A800 = $A800
b14_data_A802 = $A802
b14_data_AC00 = $AC00
b14_data_B800 = $B800
b14_data_BE98 = $BE98

; Region aliases
b14_bank = $8000

; ----------------------------------------------------------------------
; b14_field_cmd_talk
;   Field menu はなす (talk), entry 0 of the fixed-bank table at $F1C3;
;   msg 001 when nobody is there.
; ----------------------------------------------------------------------
b14_field_cmd_talk:
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
; ----------------------------------------------------------------------
; b14_field_cmd_search
;   Field menu しらべる (search), entry 1 of the $F1C3 table.
; ----------------------------------------------------------------------
b14_field_cmd_search:
    ldx #$00
    stx party_scan2
    stx $0100
    inx
    jsr text_init
    jsr text_reset_cursor
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_80AC:
    .dw b10_msg_index_002    ; text index $0002 -> b10_msg_002
    jsr b14_sub_8147
    jsr b14_sub_80B7
    jmp wait_then_game_main
; ----------------------------------------------------------------------
; b14_sub_80B7
;   called by: $80B1
; ----------------------------------------------------------------------
b14_sub_80B7:
    lda party_scan2
    beq b14_loc_80E6
    ldx #$02
    jsr text_window_restore_ask
    bcc b14_loc_80E7
b14_loc_80C2:
    lda party_scan
    sta text_command
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_80C9:
    .dw b10_msg_index_029    ; text index $001D -> b10_msg_029
    lda $0100
    bne b14_loc_80DA
    ldy $0101
    lda #$00
    sta $6680,y
    beq b14_loc_80E6
b14_loc_80DA:
    cmp #$FF
    beq b14_loc_80E6
    ldy party_index
    eor $6600,y
    sta $6600,y
b14_loc_80E6:
    rts
b14_loc_80E7:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_80EA:
    .dw b10_msg_index_030    ; text index $001E -> b10_msg_030
    ldx #$03
    jsr text_window_restore_wait
    bcs b14_loc_80C2
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    sta text_actor
b14_loc_80FA:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_80FD:
    .dw b10_msg_index_031    ; text index $001F -> b10_msg_031
    ldx #$06
    jsr text_window_restore_wait
    bcs b14_loc_80E7
    lda text_actor
    asl a
    asl a
    asl a
    adc text_menu_index
    tax
    lda $6100,x                 ; Party member stats.
    and #$7F
    sta text_command
    cmp #$28
    bcs b14_loc_8121
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_811C:
    .dw b10_msg_index_018    ; text index $0012 -> b10_msg_018
    jmp b14_loc_80FA
b14_loc_8121:
    lda #$00
    sta $6100,x                 ; Party member stats.
    sta party_scan2
    jsr compact_items_actor
    txa
    ora #$07
    tax
    lda party_scan
    sta $6100,x                 ; Party member stats.
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_8141
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_813E:
    .dw b10_msg_index_032    ; text index $0020 -> b10_msg_032
    rts
b14_loc_8141:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8144:
    .dw b10_msg_index_033    ; text index $0021 -> b10_msg_033
    rts
; ----------------------------------------------------------------------
; b14_sub_8147
;   called by: $80AE
; ----------------------------------------------------------------------
b14_sub_8147:
    jsr text_draw_char
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_814D
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_814D:
    jsr set_bank_12
    ldy party_index
    lda #$80
    sta ppu_update_len
    lda $6600,y
    sta ppu_update_off
    lda b12_data_8800,y
    sta ppu_update_ptr_lo
    lda b12_data_8880,y
    sta ppu_update_ptr_hi
    ldy #$00
b14_loc_8167:
    lda ($F3),y
    iny
    cmp text_x
    bne b14_loc_8185
    lda ($F3),y
    iny
    cmp text_y
    bne b14_loc_8186
    lda ($F3),y
    iny
    cmp text_x2
    bne b14_loc_8187
    lda ($F3),y
    iny
    cmp text_y2
    bne b14_loc_8188
    beq b14_loc_8193
b14_loc_8185:
    iny
b14_loc_8186:
    iny
b14_loc_8187:
    iny
b14_loc_8188:
    iny
    asl ppu_update_off
    lsr ppu_update_len
    cpy #$28
    bne b14_loc_8167
    beq b14_loc_81B4
b14_loc_8193:
    asl ppu_update_off
    bcs b14_loc_81E9
    lda ($F3),y
    sta party_scan
    ldy party_index
    lda $6600,y
    ora ppu_update_len
    sta $6600,y
    lda ppu_update_len
    sta $0100
    jsr update_frame
    jsr sub_CE7A
    ldy #$00
    beq b14_loc_81EB
b14_loc_81B4:
    ldx #$3F
b14_loc_81B6:
    lda b14_data_A000,x
    cmp text_x
    bne b14_loc_81E6
    lda b14_data_A040,x
    cmp text_y
    bne b14_loc_81E6
    lda b14_data_A080,x
    cmp text_x2
    bne b14_loc_81E6
    lda b14_data_A0C0,x
    cmp text_y2
    bne b14_loc_81E6
    lda $6680,x
    bne b14_loc_81E9
    inc $6680,x
    lda b14_data_A100,x
    sta party_scan
    stx $0101
    ldy #$01
    bne b14_loc_81EB
b14_loc_81E6:
    dex
    bpl b14_loc_81B6
b14_loc_81E9:
    ldy #$02
b14_loc_81EB:
    beq b14_loc_81FB
    dey
    beq b14_loc_822E
    jsr return_inline_block

b14_data_81F3:
    .incbin "build/assets/bank14_data.bin", $01F3, $0002
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_81F8:
    .dw b10_msg_index_003    ; text index $0003 -> b10_msg_003
    rts
b14_loc_81FB:
    jsr return_inline_block

b14_data_81FE:
    .incbin "build/assets/bank14_data.bin", $01FE, $0002
b14_data_8200:
    lda #$11
    jsr sound_queue_add
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8208:
    .dw b10_msg_index_004    ; text index $0004 -> b10_msg_004
    jsr text_draw_char
    lda party_scan
    bne b14_loc_8217
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8214:
    .dw b10_msg_index_005    ; text index $0005 -> b10_msg_005
    rts
b14_loc_8217:
    cmp #$50
    beq b14_loc_8223
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_821E:
    .dw b10_msg_index_006    ; text index $0006 -> b10_msg_006
    jmp b14_loc_8255
b14_loc_8223:
    jsr b14_sub_8268
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8229:
    .dw b11_msg_index_078    ; text index $024E -> b11_msg_078
    jmp b14_loc_8255
b14_loc_822E:
    jsr return_inline_block

b14_data_8231:
    .incbin "build/assets/bank14_data.bin", $0231, $0002
    lda party_scan
    bpl b14_loc_8250
    dec $6680,x
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_823D
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_823D:
    jsr set_bank_13
    lda #$0C
    jsr b13_check_name_tile     ; bank 13: b13_check_name_tile
    jsr return_inline_block

b14_data_8248:
    .incbin "build/assets/bank14_data.bin", $0248, $0002
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_824D:
    .dw b11_msg_index_268    ; text index $030C -> b11_msg_268
    rts
b14_loc_8250:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8253:
    .dw b10_msg_index_007    ; text index $0007 -> b10_msg_007
b14_loc_8255:
    lda party_scan2
    beq b14_loc_8261
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_825F:
    .dw b10_msg_index_008    ; text index $0008 -> b10_msg_008
b14_loc_8261:
    rts

b14_data_8262:
    .incbin "build/assets/bank14_data.bin", $0262, $0006
; ----------------------------------------------------------------------
; b14_sub_8268
;   called by: $8223
; ----------------------------------------------------------------------
b14_sub_8268:
    ldy #$00
    sty ppu_update_ptr_lo
    lda party_scan
    cmp #$10
    bcc b14_loc_82AA
    cmp #$17
    bcc b14_loc_8297
b14_loc_8276:
    lda $6090,y                 ; Party member order (actor ids).
    bmi b14_loc_82A7
    asl a
    asl a
    asl a
    tay
    lda #$08
    sta ppu_update_ptr_hi
b14_loc_8283:
    lda $6100,y                 ; Party member stats.
    beq b14_loc_82A1
    iny
    dec ppu_update_ptr_hi
    bne b14_loc_8283
    inc ppu_update_ptr_lo
    ldy ppu_update_ptr_lo
    cpy #$07
    bne b14_loc_8276
    beq b14_loc_82A7
b14_loc_8297:
    ldy #$38
b14_loc_8299:
    lda $6100,y                 ; Party member stats.
    beq b14_loc_82A1
    iny
    bne b14_loc_8299
b14_loc_82A1:
    lda party_scan
    sta $6100,y                 ; Party member stats.
    rts
b14_loc_82A7:
    inc party_scan2
    rts
b14_loc_82AA:
    pla
    pla
    jsr load_item_data_6e
    lda party_scan
    asl a
    adc party_scan
    tay
    lda b14_data_82DF,y
    sta ptr0_lo
    lda b14_data_82E0,y
    sta ptr0_hi
    lda b14_data_82E1,y
    sta ptr1_lo
    jsr sub_D6C2
    lda party_scan
    cmp #$07
    bcs b14_loc_82D5
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_82D0:
    .incbin "build/assets/bank14_data.bin", $02D0, $0002
    jmp b14_loc_82DA
b14_loc_82D5:
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_82D8:
    .incbin "build/assets/bank14_data.bin", $02D8, $0002
b14_loc_82DA:
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_82DD:
    .incbin "build/assets/bank14_data.bin", $02DD, $0002
b14_data_82DF:
    jmp put_number_bottom

b14_data_82E2:
    .incbin "build/assets/bank14_data.bin", $02E2, $0024
; ----------------------------------------------------------------------
; b14_field_cmd_formation
;   Field menu たいれつ (formation), entry 2: window 4 (ならび / ぐんし); ぐんし
;   sets or clears the strategist bit $40 (msgs 021/022/023/471).
; ----------------------------------------------------------------------
b14_field_cmd_formation:
    ldx #$04
    jsr text_init
    jsr text_wait
    lda text_menu_index
    bne b14_loc_8315
    jmp b14_formation_reorder
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
; b14_formation_reorder
;   The ならび reorder screen: members are picked one by one; B undoes a
;   pick ($846C).
; ----------------------------------------------------------------------
b14_formation_reorder:
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
;   called by: $8429, $8C9B, $A587
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
; ----------------------------------------------------------------------
; b14_field_cmd_officers
;   Field menu ぶしょう (officers), entry 3: officer list (window 3), then
;   the info screen ($84F8).
; ----------------------------------------------------------------------
b14_field_cmd_officers:
    ldx #$03
    jsr text_init
    jsr text_wait
    jmp b14_field_officer_info
; ----------------------------------------------------------------------
; b14_wincb_party_list_line
;   Window CALL (F8) in templates 3, 5 and $0C; runs the inline block
;   at $84AD.
; ----------------------------------------------------------------------
b14_wincb_party_list_line:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_party_list_line
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 12): one officer-list line: ＊ ($0E, not
;   present) or ★ ($0F, strategist), then the name (put_officer_name).
; ----------------------------------------------------------------------
b14_inline_party_list_line:
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
    jsr put_officer_name
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
; ----------------------------------------------------------------------
; b14_field_officer_info
;   Map path into the info screen (b14_party_status_update, then
;   b14_officer_info_screen), back to the field through
;   field_return_refresh.
; ----------------------------------------------------------------------
b14_field_officer_info:
    jsr b14_party_status_update
    jmp field_return_refresh
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
    jsr b14_calc_tactic_points
    ldx text_actor
    lda $61A8,x                 ; Party member derived stats.
    cmp $619C,x                 ; Party member derived stats.
    bcs b14_officer_info_screen
    lda #$00
    sta $61FB                   ; Party calculation temporaries.
; ----------------------------------------------------------------------
; b14_officer_info_screen
;   The officer info screen (both paths; the battle calls it from
;   b14_battle_officer_info): portrait, name (window $1B kana, window
;   $08 kanji with $A9 = $10), stats, equipment and tactics windows.
;   called by: $AA27
; ----------------------------------------------------------------------
b14_officer_info_screen:
.ifdef KANJI_TARGET
    ; Step B (INFO_SCREEN.md): the screen stays black until it is complete.
    ; The game loads the portrait (status_message without its
    ; rendering-on) and draws the two name windows; the UI bank draws the
    ; rest (kanji labels, values and bars, the equipment and tactic windows
    ; with kanji, 兵士数, the attributes); then rendering is turned on.
    ; Windows $2D, $09, $0B, $0A and the attribute and dakuten strings are
    ; not used.  UIF_INFO_ENTER: battle_intro_screen's block write is not
    ; mirrored to the band page.
    jsr compact_items_actor
    ldx #UIF_INFO_ENTER
    jsr CALL_UI
    jsr battle_intro_screen
    ldx #UIF_INFO_BUSY          ; busy until UIF_INFO_DRAW ends: the waits
    jsr CALL_UI                 ; below flush at once (no frame each)
    jsr draw_string             ; status_message's string
    .dw $D0BC                   ; (its inline word at $CF94)
    ldy text_actor              ; load_actor_portrait, without loc_C139
    lda $60A8,y                 ; Party member class/officer id.
    jsr text_load_page
    jsr wait_vblank
    lda #$A1
    sta input_buttons
    dec $AA
    ldx #$1B
    jsr text_init
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bmi b14_k_info_kanji_name
    jsr draw_string             ; inline pointer/data follows the JSR
    .dw $85F3                   ; (the original's b14_data_853E)
    jsr wait_vblank
b14_k_info_kanji_name:
    inc $AA
    lda #$10
    sta $A9
    ldx #$08
    jsr text_init
    ldx #UIF_INFO_DRAW          ; everything else, still black
    jsr CALL_UI
    jsr screen_fade_in_step     ; rendering on
    jsr wait_vblank
    lda #$80                    ; as the original leaves it
    sta input_buttons
    jmp loc_D44C
    .pad $857B
.else
    jsr compact_items_actor
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
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_853E:
    .incbin "build/assets/bank14_data.bin", $053E, $0002
    jsr wait_vblank
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
.endif
; ----------------------------------------------------------------------
; b14_wincb_stat_value_bar
;   Window 9 CALL: one stat (ぶりょく $619C, ちりょく $61A8, こうげき, ぶそうど $60B4,
;   S.P $61FB) as 3 digits, then a bar of $F4 per 26 points plus $F3
;   for a remainder of 13 or more.
; ----------------------------------------------------------------------
b14_wincb_stat_value_bar:
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
    iny
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
; ----------------------------------------------------------------------
; b14_wincb_sp_label
;   Window 9 CALL: the S . P tiles $F6 $F8 $F7.
; ----------------------------------------------------------------------
b14_wincb_sp_label:
    lda #$F6
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    lda #$F8
    sta $0319,x                 ; Bottom 8x8 tiles for the four text lines.
    lda #$F7
    sta $031A,x                 ; Bottom 8x8 tiles for the four text lines.
    ldx #$35
    rts
; ----------------------------------------------------------------------
; b14_wincb_troop_max
;   Window $2D (へいしすう) CALL: text_actor's 24-bit troop maximum $6160
;   as 6 digits.
; ----------------------------------------------------------------------
b14_wincb_troop_max:
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
; ----------------------------------------------------------------------
; b14_wincb_equipped_line
;   Window $0B (そうび) CALL; runs the inline block at $8640.
; ----------------------------------------------------------------------
b14_wincb_equipped_line:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_equipped_line
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 12): the next equipped item (bit 7) of
;   text_actor from slot $70, drawn with load_item_data.
; ----------------------------------------------------------------------
b14_inline_equipped_line:
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
;   called by: $9B96
; ----------------------------------------------------------------------
b14_delay_frames:
    ldx #$06
b14_loc_867F:
    jsr load_party_hp
    dex
    bpl b14_loc_867F
    rts
; ----------------------------------------------------------------------
; b14_field_cmd_items
;   Field menu どうぐ (items), entry 4: officer list (window 3), then
;   b14_field_item_menu.
; ----------------------------------------------------------------------
b14_field_cmd_items:
    ldx #$03
    jsr text_init
    jsr text_wait
    jmp b14_field_item_menu
; ----------------------------------------------------------------------
; b14_wincb_item_list_line
;   Window CALL for window 6 (field item list) and window $16 (battle
;   item subwindow, 8 calls); runs the inline block at $8694.
; ----------------------------------------------------------------------
b14_wincb_item_list_line:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_item_list_line
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 12): one item slot of text_actor
;   (load_item_data); field index $54 with ＊ for equipped items,
;   battle index battle_anim; then rewinds text_col.
; ----------------------------------------------------------------------
b14_inline_item_list_line:
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
; ----------------------------------------------------------------------
; b14_field_item_menu
;   Item menu of the chosen officer: msg 009 without items, else the
;   list (window 6) and つかう/わたす/そうび/すてる (window 7, table $8748).
; ----------------------------------------------------------------------
b14_field_item_menu:
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    sta text_actor
    jsr b14_check_party_slot
    bne b14_loc_871D
    jsr reset_text_engine
    jsr text_reset_cursor
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8718:
    .dw b10_msg_index_009    ; text index $0009 -> b10_msg_009
    jmp wait_then_game_main
b14_loc_871D:
    jsr compact_items_actor
    ldx #$06
    jsr text_init
    jsr text_wait
    lda text_menu_index
    sta $70
    lda text_actor
    asl a
    asl a
    asl a
    adc text_menu_index
    tax
    lda $6100,x                 ; Party member stats.
    and #$7F
    sta text_command
    ldx #$07
    jsr text_init
    jsr text_wait
    lda text_menu_index
    jsr dispatch_return_table

b14_data_8748:
    .incbin "build/assets/bank14_data.bin", $0748, $0008
; ----------------------------------------------------------------------
; b14_item_menu_use
;   Item menu つかう (use).
; ----------------------------------------------------------------------
b14_item_menu_use:
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bmi b14_loc_8762
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_875D:
    .dw b10_msg_index_012    ; text index $000C -> b10_msg_012
    jmp wait_then_game_main
b14_loc_8762:
    lda text_command
    cmp #$38
    bcc b14_loc_8773
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_876E:
    .dw b10_msg_index_035    ; text index $0023 -> b10_msg_035
    jmp wait_then_game_main
b14_loc_8773:
    cmp #$28
    beq b14_loc_879B
    sec
    sbc #$18
    bcc b14_loc_8793
    tax
    lda b14_data_8958,x
    beq b14_loc_8793
    bmi b14_loc_8793
    ldx #$0C
    jsr text_init
    jsr text_wait
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    sta text_target
b14_loc_8793:
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8799:
    .dw b10_msg_index_010    ; text index $000A -> b10_msg_010
b14_loc_879B:
    jsr b14_item_effect_dispatch
    bcs b14_loc_87A8
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_87A6:
    .dw b10_msg_index_011    ; text index $000B -> b10_msg_011
b14_loc_87A8:
    jmp wait_then_game_main
; ----------------------------------------------------------------------
; b14_item_menu_give
;   Item menu わたす (give).
; ----------------------------------------------------------------------
b14_item_menu_give:
    ldx #$0C
    jsr text_init
    jsr text_wait
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    sta text_target
    jsr reset_text_engine
    lda text_target
    asl a
    asl a
    asl a
    tax
b14_loc_87C3:
    lda $6100,x                 ; Party member stats.
    beq b14_loc_87DC
    inx
    txa
    and #$07
    bne b14_loc_87C3
    lda text_actor
    cmp text_target
    beq b14_loc_87DC
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_87D7:
    .dw b10_msg_index_013    ; text index $000D -> b10_msg_013
    jmp wait_then_game_main
b14_loc_87DC:
    lda text_actor
    cmp text_target
    bne b14_loc_87E3
    dex
b14_loc_87E3:
    stx party_scan
    lda text_actor
    asl a
    asl a
    asl a
    adc $70
    tax
    lda #$00
    sta $6100,x                 ; Party member stats.
    jsr compact_items_actor
    ldx party_scan
    lda text_command
    sta $6100,x                 ; Party member stats.
    jsr b14_sub_8D74
    lda text_actor
    cmp text_target
    beq b14_loc_883A
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_8823
    ldx text_target
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_881B
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8816:
    .dw b10_msg_index_014    ; text index $000E -> b10_msg_014
    jmp wait_then_game_main
b14_loc_881B:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_881E:
    .dw b10_msg_index_024    ; text index $0018 -> b10_msg_024
    jmp wait_then_game_main
b14_loc_8823:
    ldx text_target
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_8832
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_882D:
    .dw b10_msg_index_025    ; text index $0019 -> b10_msg_025
    jmp wait_then_game_main
b14_loc_8832:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8835:
    .dw b10_msg_index_026    ; text index $001A -> b10_msg_026
    jmp wait_then_game_main
b14_loc_883A:
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_8849
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8844:
    .dw b10_msg_index_020    ; text index $0014 -> b10_msg_020
    jmp wait_then_game_main
b14_loc_8849:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_884C:
    .dw b10_msg_index_027    ; text index $001B -> b10_msg_027
    jmp wait_then_game_main
; ----------------------------------------------------------------------
; b14_item_menu_equip
;   Item menu そうび (equip).
; ----------------------------------------------------------------------
b14_item_menu_equip:
    lda text_actor
    asl a
    asl a
    asl a
    adc $70
    sta ppu_update_off
    tax
    lda $6100,x                 ; Party member stats.
    bmi b14_loc_886F
    cmp #$40
    bcs b14_loc_8893
b14_loc_8864:
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_886A:
    .dw b10_msg_index_015    ; text index $000F -> b10_msg_015
    jmp wait_then_game_main
b14_loc_886F:
    cmp #$C0
    bcc b14_loc_8864
    and #$7F
    sta $6100,x                 ; Party member stats.
    jsr b14_sub_8D74
    lda #$02
    sta input_buttons
    ldx #$06
    jsr text_init
    lda #$00
    sta input_buttons
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_888E:
    .dw b10_msg_index_017    ; text index $0011 -> b10_msg_017
    jmp wait_then_game_main
b14_loc_8893:
    sta ppu_update_len
    lda ppu_update_off
    and #$F8
    tax
    lda #$08
    sta ppu_update_ptr_lo
    lda ppu_update_len
    cmp #$66
    bcs b14_loc_88D4
    cmp #$58
    bcs b14_loc_88BC
b14_loc_88A8:
    lda $6100,x                 ; Party member stats.
    and #$7F
    cmp #$58
    bcs b14_loc_88B4
    sta $6100,x                 ; Party member stats.
b14_loc_88B4:
    inx
    dec ppu_update_ptr_lo
    bne b14_loc_88A8
    jmp b14_loc_88E5
b14_loc_88BC:
    lda $6100,x                 ; Party member stats.
    and #$7F
    cmp #$58
    bcc b14_loc_88CC
    cmp #$66
    bcs b14_loc_88CC
    sta $6100,x                 ; Party member stats.
b14_loc_88CC:
    inx
    dec ppu_update_ptr_lo
    bne b14_loc_88BC
    jmp b14_loc_88E5
b14_loc_88D4:
    lda $6100,x                 ; Party member stats.
    and #$7F
    cmp #$66
    bcc b14_loc_88E0
    sta $6100,x                 ; Party member stats.
b14_loc_88E0:
    inx
    dec ppu_update_ptr_lo
    bne b14_loc_88D4
b14_loc_88E5:
    ldx ppu_update_off
    lda $6100,x                 ; Party member stats.
    ora #$80
    sta $6100,x                 ; Party member stats.
    jsr b14_sub_8D74
    lda #$02
    sta input_buttons
    ldx #$06
    jsr text_init
    lda #$00
    sta input_buttons
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8905:
    .dw b10_msg_index_016    ; text index $0010 -> b10_msg_016
    jmp wait_then_game_main
; ----------------------------------------------------------------------
; b14_item_menu_discard
;   Item menu すてる (discard).
; ----------------------------------------------------------------------
b14_item_menu_discard:
    jsr reset_text_engine
    lda text_actor
    asl a
    asl a
    asl a
    adc $70
    tax
    lda $6100,x                 ; Party member stats.
    and #$7F
    cmp #$28
    bcs b14_loc_8926
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8921:
    .dw b10_msg_index_018    ; text index $0012 -> b10_msg_018
    jmp wait_then_game_main
b14_loc_8926:
    lda #$00
    sta $6100,x                 ; Party member stats.
    jsr compact_items_actor
    jsr b14_sub_8D74
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_8940
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_893B:
    .dw b10_msg_index_019    ; text index $0013 -> b10_msg_019
    jmp wait_then_game_main
b14_loc_8940:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8943:
    .dw b10_msg_index_028    ; text index $001C -> b10_msg_028
    jmp wait_then_game_main
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
    .incbin "build/assets/bank14_data.bin", $0958, $0028
; ----------------------------------------------------------------------
; b14_item_effect_dispatch
;   Jump on text_command - $18 through the 40-entry table at $8988
;   (items $18-$3F); from the field ($879B) and battle item use
;   ($A341); C set = something happened.
;   called by: $879B, $A341
; ----------------------------------------------------------------------
b14_item_effect_dispatch:
    lda text_command
    sec
    sbc #$18
    jsr dispatch_return_table

b14_data_8988:
    .incbin "build/assets/bank14_data.bin", $0988, $0050

    lda text_x
    cmp #$05
    bne b14_loc_8A13
    lda text_y
    cmp #$01
    bne b14_loc_8A13
    lda text_x2
    cmp #$0C
    bne b14_loc_8A13
    lda text_y2
    cmp #$13
    bne b14_loc_8A13
    jsr loc_D44C
    jsr text_draw_screen
    inc $657D
    inc $6576
    jsr b14_consume_used_item
    lda #$A8
    sta $05E3                   ; Per-actor level.
    inc $6768
    inc $6598
    lda #$0E
    sta current_bank_a
    pla
    pla
    jmp game_main
b14_loc_8A13:
    clc
    rts
    lda text_busy
    bne b14_loc_8A1B
b14_loc_8A19:
    clc
    rts
b14_loc_8A1B:
    jsr battle_arg_slot_actor
    lda $60A8,y                 ; Party member class/officer id.
    cmp #$BC
    bne b14_loc_8A19
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_8A19
    lda text_actor
    pha
    sty text_actor
    jsr b14_battle_close_msg_window
    inc battle_flags
    jsr load_actor_portrait
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_8A3A:
    .incbin "build/assets/bank14_data.bin", $0A3A, $0002
    jsr loc_C0E2
    jsr reset_text_engine
    lda #$80
    sta input_buttons
    jsr read_input_state
    lda rng0
    bpl b14_loc_8A5B
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8A50:
    .dw b10_msg_index_277    ; text index $0115 -> b10_msg_277
    jsr loc_D44C
    jsr b14_battle_close_enemy_msg_window
    jmp b14_loc_8AF1
b14_loc_8A5B:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8A5E:
    .dw b10_msg_index_297    ; text index $0129 -> b10_msg_297
    jsr text_window_restore_ask
    bcc b14_loc_8A79
b14_loc_8A65:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8A68:
    .dw b10_msg_index_300    ; text index $012C -> b10_msg_300
    pla
    sta text_actor
    jsr b14_battle_actor_step_back
    jsr b14_battle_close_enemy_msg_window
    pla
    pla
    jmp b14_battle_party_loses_round

b14_data_8A78:
    .incbin "build/assets/bank14_data.bin", $0A78, $0001
b14_loc_8A79:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8A7C:
    .dw b10_msg_index_298    ; text index $012A -> b10_msg_298
    jsr text_window_restore_ask
    bcs b14_loc_8A65
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8A86:
    .dw b10_msg_index_299    ; text index $012B -> b10_msg_299
    lda #$04
    sta sound_temp
    ldy text_actor
    lda $60A8,y                 ; Party member class/officer id.
    sta $05F4
    jsr call_b13_9c00
    bcs b14_loc_8AF1
    jsr battle_arg_slot_actor
    lda #$00
    sta $609C,y                 ; Party member state bits.
    tya
    asl a
    asl a
    tay
    lda #$00
    sta $60D0,y                 ; Party member stats.
    sta $60D1,y                 ; Party member stats.
    sta $60D2,y                 ; Party member stats.
    jsr battle_draw_slot_troops
    jsr text_restore_tiles
    ldx $79
    lda $0506,x                 ; Per-actor state flags.
    and #$7F
    sta $0506,x                 ; Per-actor state flags.
    jsr loc_C0E2
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8AC9:
    .dw b10_msg_index_109    ; text index $006D -> b10_msg_109
    jsr text_draw_char
    lda #$C0
    sta $63C0
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8AD6:
    .dw b10_msg_index_266    ; text index $010A -> b10_msg_266
    jsr loc_D44C
    jsr b14_battle_close_enemy_msg_window
    jsr battle_arg_slot_actor
    lda $60A9,y                 ; Party member class/officer id.
    sta $60A8,y                 ; Party member class/officer id.
    lda #$00
    sta battle_flags
    pla
    sta text_actor
    jmp b14_consume_used_item
b14_loc_8AF1:
    pla
    sta text_actor
    sec
    rts
    rts
    lda text_y2
    cmp #$01
    bne b14_loc_8B13
    lda text_x2
    cmp #$07
    bne b14_loc_8B13
    lda text_y
    cmp #$20
    bne b14_loc_8B13
    lda text_x
    cmp #$06
    beq b14_loc_8B15
    cmp #$07
    beq b14_loc_8B15
b14_loc_8B13:
    clc
    rts
b14_loc_8B15:
    jsr b14_consume_used_item
    jsr loc_D44C
    jsr text_draw_screen
    inc $6575
    jsr b14_sub_8B29
    pla
    pla
    jmp game_main
; ----------------------------------------------------------------------
; b14_sub_8B29
;   called by: $8B21
; ----------------------------------------------------------------------
b14_sub_8B29:
    lda #$13
    jsr sound_queue_add
    lda #$00
    sta ptr1_lo
b14_loc_8B32:
    lda ptr1_lo
    lsr a
    bcs b14_loc_8B6C
    lsr a
    bcs b14_loc_8B6C
    and #$03
    tay
    lda b14_data_8B86,y
    jsr one_minus_a
    clc
    adc scroll_y
    sta scroll_y
    lda b14_data_8B8A,y
    jsr one_minus_a
    clc
    adc scroll_x
    sta scroll_x
    ldx #$0F
b14_loc_8B55:
    lda $0540,x                 ; Per-actor tile/sprite id.
    clc
    adc b14_data_8B86,y
    sta $0540,x                 ; Per-actor tile/sprite id.
    lda $0550,x                 ; Per-actor animation frame.
    clc
    adc b14_data_8B8A,y
    sta $0550,x                 ; Per-actor animation frame.
    dex
    bpl b14_loc_8B55
b14_loc_8B6C:
    ldx #$0F
    lda ptr1_lo
    lsr a
    bcs b14_loc_8B75
    ldx #$25
b14_loc_8B75:
    stx $03F0                   ; Small VRAM upload buffer.
    stx vram_dma_pending
    jsr loc_C0E2
    inc ptr1_lo
    lda ptr1_lo
    cmp #$20
    bne b14_loc_8B32
    rts

b14_data_8B86:
    .incbin "build/assets/bank14_data.bin", $0B86, $0004

b14_data_8B8A:
    .incbin "build/assets/bank14_data.bin", $0B8A, $0004
    rts
    lda game_mode
    bne b14_loc_8BB2
    lda text_x
    cmp #$09
    bne b14_loc_8BB2
    lda text_y
    cmp #$20
    bne b14_loc_8BB2
    lda text_x2
    cmp #$07
    bne b14_loc_8BB2
    lda text_y2
    cmp #$08
    bne b14_loc_8BB2
    lda $05F3
    cmp #$D7
    beq b14_loc_8BB5
b14_loc_8BB2:
    clc
    bcc b14_loc_8BC8
b14_loc_8BB5:
    lda #$03
    sta sound_temp
    jsr loc_D44C
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8BBF:
    .dw b11_msg_index_171    ; text index $02AB -> b11_msg_171
    lda text_menu_index
    bne b14_loc_8BC8
    jmp b14_consume_used_item
b14_loc_8BC8:
    rts
    lda text_x
    cmp #$02
    bne b14_loc_8BF2
    lda text_y
    cmp #$1A
    bne b14_loc_8BF2
    lda text_x2
    cmp #$0C
    bne b14_loc_8BF2
    lda text_y2
    cmp #$04
    bne b14_loc_8BF2
    jsr b14_consume_used_item
    lda #$19
    sta party_scan
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8BEE:
    .dw b10_msg_index_006    ; text index $0006 -> b10_msg_006
    sec
    rts
b14_loc_8BF2:
    clc
    rts
    rts
    lda #$00
    sta $7C
    ldx #$23
    jsr text_init
    jsr text_wait
    ldx $7C
    ldx text_menu_index
    stx ppu_update_len
    ldx #$00
b14_loc_8C09:
    lda b14_data_8DE7,x
    tay
    inx
    lda $6700,y
    and #$02
    beq b14_loc_8C09
    dec ppu_update_len
    bpl b14_loc_8C09
    dex
    txa
    pha
    ldy #$05
    jsr draw_window
    jsr text_draw_screen
    ldy #$00
    pla
    asl a
    asl a
    tax
b14_loc_8C2A:
    lda b14_data_8DF4,x
    sta text_x,y
    inx
    iny
    cpy #$04
    bne b14_loc_8C2A
    lda #$01
    sta game_mode
    lda #$00
    sta $90
    sta $6011
    sta party_index
    sta $86
    jsr field_party_sprites_reset
    jsr b14_field_change_area
    jsr b14_consume_used_item
    pla
    pla
    jmp game_main
    rts
    lda #$40
    sta $8B
    lda battle_flags2
    ora #$42
    sta battle_flags2
    jmp b14_consume_used_item
    lda #$40
    sta $8A
    lda battle_flags2
    ora #$04
    sta battle_flags2
    jmp b14_consume_used_item
    rts
    ldx text_target
    lda $609C,x                 ; Party member state bits.
    bmi b14_loc_8CAD
    ora #$80
    sta $609C,x                 ; Party member state bits.
    lda #$0B
    jsr sound_queue_add
    ldx #$3C
    jsr update_frames
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8C88:
    .dw b10_msg_index_040    ; text index $0028 -> b10_msg_040
    lda text_target
    asl a
    asl a
    tay
    lda #$01
    sta ptr0_hi
    lda #$90
    sta ptr0_lo
    lda text_busy
    bne b14_loc_8CA1
    jsr b14_init_battle_party
    jmp b14_heal_target_troops
b14_loc_8CA1:
    ldx $79
    asl $0506,x                 ; Per-actor state flags.
    sec
    ror $0506,x                 ; Per-actor state flags.
    jmp b14_heal_target_troops
b14_loc_8CAD:
    rts
    lda #$00
    sta ptr0_hi
    lda #$64
    sta ptr0_lo
    bne b14_heal_target_troops
    lda #$01
    sta ptr0_hi
    lda #$F4
    sta ptr0_lo
    bne b14_heal_target_troops
    lda #$03
    sta ptr0_hi
    lda #$E8
    sta ptr0_lo
    bne b14_heal_target_troops
    lda #$11
    sta ptr0_hi
    lda #$94
    sta ptr0_lo
; ----------------------------------------------------------------------
; b14_heal_target_troops
;   Add $10-$12 to text_target's troops $60D0, capped at the maximum
;   $6160, then msg 039; also used by tactic type 2 ($BA44).
;   called by: $BA44
; ----------------------------------------------------------------------
b14_heal_target_troops:
    jsr b14_abort_if_target_down
    lda #$00
    sta ptr1_lo
    lda text_target
    asl a
    asl a
    tay
    jsr add24_inline_y          ; inline pointer/data follows the JSR

b14_data_8CE3:
    .incbin "build/assets/bank14_data.bin", $0CE3, $0002
    lda $60D0,y                 ; Party member stats.
    sta ptr0_lo
    lda $60D1,y                 ; Party member stats.
    sta ptr0_hi
    lda $60D2,y                 ; Party member stats.
    sta ptr1_lo
    jsr sub24_inline_clamped_y  ; inline pointer/data follows the JSR

b14_data_8CF7:
    .incbin "build/assets/bank14_data.bin", $0CF7, $0002
    php
    jsr add24_inline_y          ; inline pointer/data follows the JSR

b14_data_8CFD:
    .incbin "build/assets/bank14_data.bin", $0CFD, $0002
    plp
    bcs b14_loc_8D0A
    jsr b14_abort_if_target_down
    lda text_target
    jsr b14_refill_member_troops
b14_loc_8D0A:
    lda text_command
    cmp #$30
    beq b14_loc_8D18
    jsr b14_effect_msg_pause
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_8D16:
    .dw b10_msg_index_039    ; text index $0027 -> b10_msg_039
b14_loc_8D18:
    lda text_busy
    beq b14_loc_8D28
    jsr battle_draw_slot_troops
    lda text_command
    cmp #$30
    bcc b14_loc_8D2B
    jmp b14_consume_used_item
b14_loc_8D28:
    jmp b14_consume_used_item
b14_loc_8D2B:
    rts
    pla
    pla
    jsr b14_consume_used_item
    ldx #$15
    jsr text_init
    ldx party_count
    lda #$00
    sta $61D0,x
    jsr battle_effect_setup
    lda #$FF
    sta $7C
    jmp b14_loc_A1A7
    rts
; ----------------------------------------------------------------------
; b14_consume_used_item
;   Clear item slot $70 of text_actor and recompact the list, then C =
;   1: the shared tail of the item effects.
;   called by: $89FC, $8B15, $8BE1, $8C4B, $8D2E
; ----------------------------------------------------------------------
b14_consume_used_item:
    lda text_actor
    asl a
    asl a
    asl a
    adc $70
    tax
    lda #$00
    sta $6100,x                 ; Party member stats.
    jsr compact_items_actor
    sec
    rts
; ----------------------------------------------------------------------
; b14_effect_msg_pause
;   Pause before an effect message: field waits for A/B, battle waits
;   10 frames, all-out mode none.
;   called by: $8D10
; ----------------------------------------------------------------------
b14_effect_msg_pause:
    lda text_busy
    bmi b14_loc_8D68
    bne b14_loc_8D63
    jmp text_draw_char
b14_loc_8D63:
    ldx #$0A
    jmp wait_frames
b14_loc_8D68:
    rts
; ----------------------------------------------------------------------
; b14_abort_if_target_down
;   If text_target is down (state bit 7 clear), drop the caller's
;   return address and return C = 0 to the caller's caller.
;   called by: $8CD4, $8D02
; ----------------------------------------------------------------------
b14_abort_if_target_down:
    ldx text_target
    lda $609C,x                 ; Party member state bits.
    bmi b14_loc_8D73
    pla
    pla
    clc
b14_loc_8D73:
    rts
; ----------------------------------------------------------------------
; b14_sub_8D74
;   called by: $87FC, $8878, $88EF, $892E
; ----------------------------------------------------------------------
b14_sub_8D74:
    ldx text_actor
    lda #$00
    sta $60B4,x
    sta $60C0,x
    txa
    asl a
    asl a
    asl a
    tay
b14_loc_8D83:
    lda $6100,y                 ; Party member stats.
    bpl b14_loc_8DB1
    and #$7F
    cmp #$58
    bcs b14_loc_8DA1
    cmp #$40
    bcc b14_loc_8DB1
    lda $6100,y                 ; Party member stats.
    bpl b14_loc_8DB1
    and #$7F
    sec
    sbc #$3F
    sta $60C0,x
    bne b14_loc_8DB1
b14_loc_8DA1:
    sec
    sbc #$58
    tax
    lda data_E6D1,x
    clc
    ldx text_actor
    adc $60B4,x
    sta $60B4,x
b14_loc_8DB1:
    iny
    tya
    and #$07
    bne b14_loc_8D83
    rts

b14_data_8DB8:
    .incbin "build/assets/bank14_data.bin", $0DB8, $002F

b14_data_8DE7:
    .incbin "build/assets/bank14_data.bin", $0DE7, $000D

b14_data_8DF4:
    .incbin "build/assets/bank14_data.bin", $0DF4, $020C

b14_data_9000:
    .incbin "build/assets/bank14_data.bin", $1000, $0222

; ----------------------------------------------------------------------
; b14_wincb_gold_line
;   Window $18/$22 CALL: the 金 tile ($6C), then gold ($6076).
; ----------------------------------------------------------------------
b14_wincb_gold_line:
    lda #$6C
    sta $0332                   ; Saved text tile rows for window redraw.
    jmp b14_print_gold
; ----------------------------------------------------------------------
; b14_wincb_food_line
;   Window $18/$22 CALL: 兵ろう ($7F $35 $3F), then food ($6079).
; ----------------------------------------------------------------------
b14_wincb_food_line:
    lda #$7F
    sta $0302                   ; Top 8x8 tiles for the four text lines.
    lda #$35
    sta $0303                   ; Top 8x8 tiles for the four text lines.
    lda #$3F
    sta $0304                   ; Top 8x8 tiles for the four text lines.
    jmp b14_print_food
; ----------------------------------------------------------------------
; b14_wincb_exp_line
;   Window $22 CALL: けいけんち, then experience ($6070).
; ----------------------------------------------------------------------
.ifdef KANJI_TARGET
; Step B item 8: the reward window $22's template (kanji_build points
; data_EDA1/EDD1 + $22 here; REWARD_TPL): four lines of one UI-bank CALL
; each (cv_wincb, ui_battle.asm; no parameter byte: the UI bank, mapped
; over this bank then, takes the line from $54), rows 3-10 at columns
; 18-29; the last row pair adds rows 11-12.  Only $22 called
; b14_wincb_exp_line.
b14_k_reward_tpl:
    .db $FA,$01,$0C                         ; as the original: x -6, y +1, width 12
    .db $FA,$F8,<CV_WINCB,>CV_WINCB         ; 金
    .db $FA,$F8,<CV_WINCB,>CV_WINCB         ; gold, 兵糧 (upper half)
    .db $FA,$F8,<CV_WINCB,>CV_WINCB         ; 兵糧 (lower half), food
    .db $FA,$F8,<CV_WINCB,>CV_WINCB         ; 経験値
    .db $FF
    .dsb 8, $FF
.if b14_k_reward_tpl != $923C
    .error "b14_k_reward_tpl moved: update REWARD_TPL in kanji_build.py"
.endif
.else
b14_k_reward_tpl:                       ; (asm6f evaluates the .if above here too)
b14_wincb_exp_line:
    lda #$13
    sta $0332                   ; Saved text tile rows for window redraw.
    lda #$3E
    sta $0333                   ; Saved text tile rows for window redraw.
    lda #$13
    sta $0334                   ; Saved text tile rows for window redraw.
    lda #$38
    sta $0335                   ; Saved text tile rows for window redraw.
    lda #$1B
    sta $0336                   ; Saved text tile rows for window redraw.
    jmp b14_print_exp
.endif

b14_data_9258:
    .incbin "build/assets/bank14_data.bin", $1258, $01A8

b14_data_9400:
    .incbin "build/assets/bank14_data.bin", $1400, $0179

; ----------------------------------------------------------------------
; b14_sub_9579
;   called by: $AF3D
; ----------------------------------------------------------------------
b14_sub_9579:
    lda #$00
    tax
    tay
b14_loc_957D:
    lda $6030,x
    bne b14_loc_9587
    iny
    cpy #$40
    bcs b14_loc_9593
b14_loc_9587:
    lda $6030,y
    sta $6030,x
    inx
    iny
    cpy #$40
    bcc b14_loc_957D
b14_loc_9593:
    lda #$00
b14_loc_9595:
    sta $6030,x
    inx
    cpx #$40
    bcc b14_loc_9595
    rts
; ----------------------------------------------------------------------
; b14_army_status_screen
;   Select on the map: the leader's portrait and kanji name,
;   gold/food/exp, level, the troop list and the strategist's S.P.
; ----------------------------------------------------------------------
b14_army_status_screen:
    jsr b14_calc_strategist_tactic_pts
    jsr battle_intro_screen
    jsr screen_fade_in
    jsr call_inline_block       ; copies the following block to $0600 and executes it there

; ----------------------------------------------------------------------
; b14_inline_upload_status_kanji
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block: bank 1 mapped, copy_to_vram mode 2 writes plane 1 of
;   BG tiles $C0-$D7 from bank 1 $8000.
; ----------------------------------------------------------------------
b14_inline_upload_status_kanji:
    lda #$01
    jsr set_bank_a
    ldy #$1C
    lda #$08
    ldx #$18
    jsr copy_to_vram            ; inline pointer/data follows the JSR

b14_data_95B8:
    .incbin "build/assets/bank14_data.bin", $15B8, $0002
    jsr return_inline_block

b14_data_95BD:
    .incbin "build/assets/bank14_data.bin", $15BD, $0002
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_95C2:
    .incbin "build/assets/bank14_data.bin", $15C2, $0002
.ifdef KANJI_TARGET
    jsr CALL_UI_ARMY            ; step B: wait_vblank, then SP / MSP cells P1
.else
    jsr wait_vblank
.endif
    lda #$10
    sta $A9
    jsr find_party_member
    ldx party_slot
    stx text_actor
    ldy $60A8,x                 ; Party member class/officer id.
    jsr sub_CFA1
    lda #$A1
    sta input_buttons
    ldx #$2E
    jsr text_init
    lda #$80
    sta input_buttons
    ldx #$0D
    jsr text_init
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: busy (army screen): flushes at once
.else
    jsr wait_vblank_queued
.endif
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_95F0:
    .incbin "build/assets/bank14_data.bin", $15F0, $0002
    ldx vram_queue_write
    dex
    dex
    ldy #$FF
    lda $6073
    sec
b14_loc_95FC:
    iny
    sbc #$0A
    bcs b14_loc_95FC
    sta ppu_update_ptr_lo
    tya
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_update_ptr_lo
    adc #$0A
    sta $0400,x                 ; VRAM update command queue.
    jsr wait_vblank
    ldx #$0E
    jsr text_init
    ldx #$06
b14_loc_9619:
    lda $609C,x                 ; Party member state bits.
    cmp #$C0
    beq b14_loc_9623
    dex
    bpl b14_loc_9619
b14_loc_9623:
    stx text_target
    inc input_buttons
    ldx #$0F
    jsr text_init
    dec input_buttons
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_9631:
    .incbin "build/assets/bank14_data.bin", $1631, $0002
    jsr wait_vblank
    jsr screen_fade_out
    jsr wait_vblank
    jsr loc_C139
b14_loc_963F:
    jsr wait_vblank
    lda controller_state
    beq b14_loc_963F
    jmp field_return_refresh
; ----------------------------------------------------------------------
; b14_print_gold
;   Flush the VRAM queue, then print gold $6076.
; ----------------------------------------------------------------------
b14_print_gold:
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: the same unless busy; then it flushes at once
.else
    jsr wait_vblank_queued
.endif
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_964F:
    .incbin "build/assets/bank14_data.bin", $164F, $0002
    lda #$06
    jmp read_stack_arg
; ----------------------------------------------------------------------
; b14_print_food
;   Flush the VRAM queue, then print food $6079.
; ----------------------------------------------------------------------
b14_print_food:
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: the same unless busy; then it flushes at once
.else
    jsr wait_vblank_queued
.endif
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_965C:
    .incbin "build/assets/bank14_data.bin", $165C, $0002
    lda #$06
    jmp read_stack_arg
; ----------------------------------------------------------------------
; b14_print_exp
;   Flush the VRAM queue, then print experience $6070.
; ----------------------------------------------------------------------
b14_print_exp:
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: the same unless busy; then it flushes at once
.else
    jsr wait_vblank_queued
.endif
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_9669:
    .incbin "build/assets/bank14_data.bin", $1669, $0002
    lda #$06
    jmp read_stack_arg
; ----------------------------------------------------------------------
; b14_wincb_print_sp
;   Window $0F CALL: S.P $61FB as 3 digits.
; ----------------------------------------------------------------------
b14_wincb_print_sp:
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: the same unless busy; then it flushes at once
.else
    jsr wait_vblank_queued
.endif
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_9676:
    .incbin "build/assets/bank14_data.bin", $1676, $0002
    lda #$02
    jmp read_stack_arg
; ----------------------------------------------------------------------
; b14_wincb_print_sp_factor
;   Window $0F CALL: $61F8 (the S.P multiplier of
;   b14_calc_tactic_points) as 3 digits.
; ----------------------------------------------------------------------
b14_wincb_print_sp_factor:
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: the same unless busy; then it flushes at once
.else
    jsr wait_vblank_queued
.endif
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_9683:
    .incbin "build/assets/bank14_data.bin", $1683, $0002
    lda #$02
    jmp read_stack_arg
; ----------------------------------------------------------------------
; b14_wincb_tactic_sp_left
;   Window $17 (battle tactic subwindow title) CALL: the remaining S.P
;   $6210 as 3 digits.
; ----------------------------------------------------------------------
b14_wincb_tactic_sp_left:
    jsr wait_vblank
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_9690:
    .incbin "build/assets/bank14_data.bin", $1690, $0002
    ldx #$0B
    lda #$02
    jsr read_stack_arg
    ldx #$32
    rts
; ----------------------------------------------------------------------
; b14_wincb_army_member_line
;   Window $0E CALL (inline block, bank 12): per party-order entry a
;   ＊/★ marker, the name, then troops $60D0 / maximum $6160.
; ----------------------------------------------------------------------
b14_wincb_army_member_line:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_969F
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_969F:
    jsr set_bank_12
    ldy $54
    lda $6090,y                 ; Party member order (actor ids).
    bmi b14_loc_9703
    tay
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_96B3
    lda #$0E
    bne b14_loc_96BD
b14_loc_96B3:
    and #$40
    beq b14_loc_96BB
    lda #$0F
    bne b14_loc_96BD
b14_loc_96BB:
    lda #$0A
b14_loc_96BD:
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    lda $60A8,y                 ; Party member class/officer id.
    jsr put_officer_name
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: busy (army screen): flushes at once
.else
    jsr wait_vblank_queued
.endif
    txa
    and #$F8
    ora #$08
    tax
    ldy $54
    lda $6090,y                 ; Party member order (actor ids).
    asl a
    asl a
    pha
    tay
    lda #$D0
    sta $00
    lda #$60
    sta $01
    jsr read_pointer_triplet
    lda #$05
    jsr read_stack_arg
    lda #$7C
    jsr text_put_tile
.ifdef KANJI_TARGET
    jsr wait_vblank             ; QoL: busy (army screen): flushes at once
.else
    jsr wait_vblank_queued
.endif
    pla
    tay
    lda #$60
    sta $00
    lda #$61
    sta $01
    jsr read_pointer_triplet
    lda #$04
    jsr read_stack_arg
b14_loc_9703:
    ldy $54
    cpy #$06
    beq b14_loc_9710
    lda text_col
    sec
    sbc #$04
    sta text_col
b14_loc_9710:
    jsr return_inline_block

b14_data_9713:
    .incbin "build/assets/bank14_data.bin", $1713, $0002
    rts

b14_data_9716:
    .incbin "build/assets/bank14_data.bin", $1716, $0065

; ----------------------------------------------------------------------
; b14_battle_calc_damage
;   Damage of the acting slot (tactic power, or ぶりょく x troop factor
;   with class, terrain, defence and defend modifiers and a random
;   spread); subtracted from the target's $60D0; msgs 052/053 on a
;   critical roll.
;   called by: $ACFC
; ----------------------------------------------------------------------
b14_battle_calc_damage:
    ldx party_count
    lda $61D0,x
    cmp #$01
    bne b14_loc_97E9
    lda #$00
    sta $7C
    jsr battle_sp_owner_x6
    sta ppu_update_ptr_lo
    ldx party_count
    ldy $6200,x                 ; Party battle flags.
    sty text_command
    lda b14_data_BB9D,y
    sta ptr0_lo
    lda b14_data_BBBC,y
    sta ptr0_hi
    lda #$00
    sta ptr1_lo
    sta ppu_addr_hi
    jsr b14_battle_actor_max_ability
    sta ppu_addr_lo
    jsr mul16x16_shr8
    lda rng0
    adc rng3
    and #$0F
    tay
    lda b14_data_99BC,y
    sta ppu_addr_lo
    lda b14_data_99CC,y
    sta ppu_addr_hi
    jsr mul16x16_shr8
    ldx battle_flags
    ldy text_command
    lda $6222,x                 ; Party battle flags.
    and #$02
    beq b14_loc_97D2
    lda b14_data_B8B6,y
    beq b14_loc_97E0
    bne b14_loc_97E6
b14_loc_97D2:
    lda $6222,x                 ; Party battle flags.
    and #$04
    beq b14_loc_97E6
    lda b14_data_B8B6,y
    cmp #$01
    bne b14_loc_97E6
b14_loc_97E0:
    lsr ptr1_lo
    ror ptr0_hi
    ror ptr0_lo
b14_loc_97E6:
    jmp b14_loc_98D7
b14_loc_97E9:
    jsr battle_current_actor
    sty ppu_update_len
    lda $619C,y                 ; Party member derived stats.
    sta ptr0_lo
    lda #$00
    sta ptr0_hi
    sta ptr1_lo
    lda ppu_update_len
    asl a
    asl a
    tay
    lda $60D0,y                 ; Party member stats.
    sta $03
    lda $60D1,y                 ; Party member stats.
    sta $04
    lda $60D2,y                 ; Party member stats.
    sta $05
    jsr copy_pointer_triplet
    ldy #$00
b14_loc_9812:
    lda $0104,y
    bne b14_loc_981E
    iny
    cpy #$08
    bne b14_loc_9812
    beq b14_loc_9839
b14_loc_981E:
    sty ppu_update_off
    lda #$07
    sec
    sbc ppu_update_off
    sta ppu_update_off
    tay
    lda #$00
    sta ppu_addr_hi
b14_loc_982C:
    lda ppu_update_off
    clc
    adc ppu_addr_hi
    sta ppu_addr_hi
    dey
    bne b14_loc_982C
    jsr mul16_by_u8
b14_loc_9839:
    ldx ppu_update_len
    lda $60C0,x
    tay
    lda $E6A9,y
    sta ppu_addr_lo
    lda $E6BD,y
    sta ppu_addr_hi
    tya
    asl a
    tay
    lda $619C,x                 ; Party member derived stats.
    cmp $E6E9,y
    bcs b14_loc_9860
    lda $61A8,x                 ; Party member derived stats.
    cmp $E6EA,y
    bcs b14_loc_9860
    lsr ppu_addr_hi
    ror ppu_addr_lo
b14_loc_9860:
    jsr mul24x16_shr8
    lda $7C
    cmp #$F0
    bcc b14_loc_986D
    lda #$33
    bne b14_loc_9879
b14_loc_986D:
    lda rng1
    adc rng2
    sta rng1
    and #$0F
    tax
    lda b14_data_9954,x
b14_loc_9879:
    sta ppu_addr_lo
    lda #$00
    sta ppu_addr_hi
    jsr mul24x16_shr8
    jsr battle_arg_slot_actor
    lda #$FF
    sec
    sbc $60B4,y
    sta ppu_addr_lo
    lda #$00
    sta ppu_addr_hi
    jsr mul24x16_shr8
    lda text_x
    cmp #$0B
    bne b14_loc_98AC
    lda text_y
    cmp #$08
    bne b14_loc_98AC
    lda text_x2
    cmp #$01
    bne b14_loc_98AC
    lda text_y2
    cmp #$09
    beq b14_loc_98D7
b14_loc_98AC:
    lda battle_flags
    bne b14_loc_98D7
    ldy game_submode
    bmi b14_loc_98D7
    lda b14_data_9964,y
    sta ppu_addr_lo
    lda #$00
    sta ppu_addr_hi
    jsr mul24x16_shr8
    lda battle_flags
    eor #$01
    tax
    lda $6222,x                 ; Party battle flags.
    and #$08
    beq b14_loc_98D7
    lda #$01
    sta ppu_addr_hi
    lda #$19
    sta ppu_addr_lo
    jsr mul16x16_shr8
b14_loc_98D7:
    ldy $79
    lda $61D0,y
    bpl b14_loc_98E4
    lsr ptr1_lo
    ror ptr0_hi
    ror ptr0_lo
b14_loc_98E4:
    ldx battle_flags
    lda $6222,x                 ; Party battle flags.
    lsr a
    bcc b14_loc_98F2
    lsr ptr1_lo
    ror ptr0_hi
    ror ptr0_lo
b14_loc_98F2:
    ldy party_count
    lda battle_flags
    eor #$01
    tax
    lda $622E,x                 ; Party battle flags.
    and b14_data_BC43,y
    beq b14_loc_990A
    asl ptr0_lo
    rol ptr0_hi
    rol ptr1_lo
    jmp b14_loc_991A
b14_loc_990A:
    lda $6221                   ; Party battle flags.
    beq b14_loc_991A
    lda #$B3
    sta ppu_addr_lo
    lda #$00
    sta ppu_addr_hi
    jsr mul16x16_shr8
b14_loc_991A:
    lda ptr0_lo
    clc
    adc #$01
    sta ptr0_lo
    lda ptr0_hi
    adc #$00
    sta ptr0_hi
    lda ptr1_lo
    adc #$00
    sta ptr1_lo
    lda text_target
    asl a
    asl a
    tay
    jsr sub24_inline_clamped_y  ; inline pointer/data follows the JSR

b14_data_9935:
    .incbin "build/assets/bank14_data.bin", $1935, $0002
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_993A:
    .incbin "build/assets/bank14_data.bin", $193A, $0002
    lda $7C
    cmp #$F0
    bcc b14_loc_9953
    lda battle_flags
    bne b14_loc_994E
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9949:
    .dw b10_msg_index_052    ; text index $0034 -> b10_msg_052
    jmp b14_loc_9953
b14_loc_994E:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9951:
    .dw b10_msg_index_053    ; text index $0035 -> b10_msg_053
b14_loc_9953:
    rts

b14_data_9954:
    .incbin "build/assets/bank14_data.bin", $1954, $0010

b14_data_9964:
    .incbin "build/assets/bank14_data.bin", $1964, $0058

b14_data_99BC:
    .incbin "build/assets/bank14_data.bin", $19BC, $0010

b14_data_99CC:
    .incbin "build/assets/bank14_data.bin", $19CC, $0010

; ----------------------------------------------------------------------
; b14_msgcb_victory_exp
;   Message CALL (msgs 061/062): experience = enemy totals x area
;   factor, added to $6070 and printed.
; ----------------------------------------------------------------------
b14_msgcb_victory_exp:
    stx ppu_update_len
    ldx $6026
    lda b14_data_9A33,x
    sta ppu_addr_lo
    lda #$00
    sta ppu_addr_hi
    lda #$00
    sta ptr1_lo
    sta cursor_y
    sta cursor_x2
    sta cursor_y2
    ldx #$11
b14_loc_99F6:
    ldy #$01
b14_loc_99F8:
    lda $617C,x                 ; Party member derived stats.
    sta ptr0_lo,y
    dex
    dey
    bpl b14_loc_99F8
    jsr mul16x16_shr8
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_9A08:
    .incbin "build/assets/bank14_data.bin", $1A08, $0002
    dex
    dex
    bpl b14_loc_99F6
    lda cursor_y
    sta ptr0_lo
    lda cursor_x2
    sta ptr0_hi
    lda cursor_y2
    sta ptr1_lo
    lda game_submode
    bmi b14_loc_9A25
    lda #$03
    sta ppu_addr_hi
    jsr mul16_by_u8
b14_loc_9A25:
    ldx ppu_update_len
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_9A2A:
    .incbin "build/assets/bank14_data.bin", $1A2A, $0002
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_9A2F:
    .incbin "build/assets/bank14_data.bin", $1A2F, $0002
    jmp put_number_bottom

b14_data_9A34:
    .incbin "build/assets/bank14_data.bin", $1A34, $0008
; ----------------------------------------------------------------------
; b14_msgcb_victory_gold
;   Message CALL (msgs 061/062): gold reward, added to $6076 and
;   printed.
; ----------------------------------------------------------------------
b14_msgcb_victory_gold:
    lda #$00
    sta cursor_x
    jsr b14_sum_enemy_officer_stats
    lda game_submode
    bpl b14_loc_9A51
    lda #$02
    sta ppu_addr_hi
    jsr mul16_by_u8
    jmp b14_loc_9A58
b14_loc_9A51:
    lda #$04
    sta ppu_addr_hi
    jsr mul16_by_u8
b14_loc_9A58:
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_9A5B:
    .incbin "build/assets/bank14_data.bin", $1A5B, $0002
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_9A60:
    .incbin "build/assets/bank14_data.bin", $1A60, $0002
    jmp put_number_bottom
; ----------------------------------------------------------------------
; b14_msgcb_victory_food
;   Message CALL (msg 061): food reward, added to $6079 and printed.
; ----------------------------------------------------------------------
b14_msgcb_victory_food:
    lda #$01
    sta cursor_x
    jsr b14_sum_enemy_officer_stats
    lda game_submode
    bmi b14_loc_9A77
    lda #$05
    sta ppu_addr_hi
    jsr mul16_by_u8
b14_loc_9A77:
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_9A7A:
    .incbin "build/assets/bank14_data.bin", $1A7A, $0002
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_9A7F:
    .incbin "build/assets/bank14_data.bin", $1A7F, $0002
    jmp put_number_bottom
; ----------------------------------------------------------------------
; b14_sum_enemy_officer_stats
;   Sum over the enemy officers the larger (cursor_x = 0) or smaller
;   (1, then x5) of $61A3/$61AF, scaled by the area table $9AE1.
;   called by: $9A40, $9A69
; ----------------------------------------------------------------------
b14_sum_enemy_officer_stats:
    txa
    pha
    ldx #$00
    stx ptr0_hi
    stx ptr1_lo
    stx cursor_y
    stx cursor_x2
    stx cursor_y2
b14_loc_9A92:
    lda $60AF,x                 ; Party member class/officer id.
    beq b14_loc_9ABB
    lda $61AF,x                 ; Party member derived stats.
    cmp $61A3,x                 ; Party member derived stats.
    bcs b14_loc_9AA8
    ldy cursor_x
    bne b14_loc_9AAF
    lda $61A3,x                 ; Party member derived stats.
    bne b14_loc_9AAF
b14_loc_9AA8:
    ldy cursor_x
    beq b14_loc_9AAF
    lda $61A3,x                 ; Party member derived stats.
b14_loc_9AAF:
    sta ptr0_lo
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_9AB4:
    .incbin "build/assets/bank14_data.bin", $1AB4, $0002
    inx
    cpx #$05
    bne b14_loc_9A92
b14_loc_9ABB:
    lda cursor_y
    sta ptr0_lo
    lda cursor_x2
    sta ptr0_hi
    lda $6026
    asl a
    tax
    lda b14_data_9AE1,x
    sta ppu_addr_hi
    lda b14_data_9AE2,x
    sta ppu_addr_lo
    jsr mul16x16_shr8
    ldy cursor_x
    beq b14_loc_9AE0
    lda #$05
    sta ppu_addr_hi
    jsr mul16_by_u8
b14_loc_9AE0:
    pla
b14_data_9AE1:
    tax
b14_data_9AE2:
    rts

b14_data_9AE3:
    .incbin "build/assets/bank14_data.bin", $1AE3, $0010
; ----------------------------------------------------------------------
; b14_calc_food_use_rate
;   At battle end: total troops of the 7 members -> $607D = total /
;   1000 or $607C = 1000 / total (the field food rate).
;   called by: $A550
; ----------------------------------------------------------------------
b14_calc_food_use_rate:
    ldx #$00
    stx ptr1_hi
    stx ppu_addr_lo
    stx ppu_addr_hi
    inx
    stx $607C
    stx $607D
    lda #$06
    sta $7C
b14_loc_9B06:
    lda $7C
    asl a
    asl a
    tay
    lda $60D0,y                 ; Party member stats.
    sta ptr0_lo
    iny
    lda $60D0,y                 ; Party member stats.
    sta ptr0_hi
    iny
    lda $60D0,y                 ; Party member stats.
    sta ptr1_lo
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_9B1F:
    .incbin "build/assets/bank14_data.bin", $1B1F, $0002
    dec $7C
    bpl b14_loc_9B06
    lda ptr1_hi
    sta $00
    lda ppu_addr_lo
    sta $01
    lda ppu_addr_hi
    sta $02
    lda #$E8
    sta $06
    lda #$03
    sta $07
    lda #$00
    sta $08
    jsr div24_shift
    lda $00
    ora $01
    beq b14_loc_9B4C
    lda $00
    sta $607D
    rts
b14_loc_9B4C:
    lda $03
    sta $06
    lda $04
    sta $07
    lda $05
    sta $08
    lda #$E8
    sta $00
    lda #$03
    sta $01
    lda #$00
    sta $02
    jsr div24_shift
    lda $00
    ldx $01
    beq b14_loc_9B6F
    lda #$FF
b14_loc_9B6F:
    sta $607C
    rts
; ----------------------------------------------------------------------
; b14_battle_entry
;   Battle entry from the fixed bank: b14_battle_run, then
;   field_return_refresh.
; ----------------------------------------------------------------------
b14_battle_entry:
    jsr b14_battle_run
    jmp field_return_refresh
; ----------------------------------------------------------------------
; b14_battle_run
;   text_busy + 1, the encounter transition (inline block), then the
;   battle from b14_battle_start.
;   called by: $9B73
; ----------------------------------------------------------------------
b14_battle_run:
    inc text_busy
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_battle_transition
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block: bank 13 b13_fade_out_wait (encounter sound and
;   flashes, then CHR $1800-$1FFF masked in 16 steps).
; ----------------------------------------------------------------------
b14_inline_battle_transition:
    jsr set_bank_13
    jsr b13_fade_out_wait       ; bank 13: b13_fade_out_wait
    jsr return_inline_block

b14_data_9B87:
    .incbin "build/assets/bank14_data.bin", $1B87, $0002
; ----------------------------------------------------------------------
; b14_battle_start
;   Battle (re)start, also for chained battles:
;   battle_intro_screen_body (battle CHR and palette set 8), scroll,
;   battle flags, attribute layout $A59E.
; ----------------------------------------------------------------------
b14_battle_start:
.ifdef KANJI_TARGET
    jsr b14_k_battle_start      ; step B: no band-page mirror (UI_NOMIR)
.else
    jsr find_party_member
.endif
    jsr battle_intro_screen_body
.ifdef KANJI_TARGET
    jsr b14_k_fade_in           ; step B: + the battle screen's fixed kanji
.else
    jsr screen_fade_in
.endif
    lda #$91
    sta ppu_ctrl_shadow
    jsr b14_delay_frames        ; bank 13 target
    lda #$24
    ldx #$0A
    ldy #$00
    jsr set_ppu_scroll
    jsr b14_battle_clear_actor_tables; bank 13 target
    ldx #$12
    lda #$00
b14_loc_9BA9:
    sta $6220,x                 ; Party battle flags.
    dex
    bpl b14_loc_9BA9
    ldx #$18
    stx $7C
b14_loc_9BB3:
    ldx $7C
    stx game_mode
    jsr draw_status_panel
    cpy #$10
    beq b14_loc_9BC4
    dec $7C
    bpl b14_loc_9BB3
    bmi b14_loc_9BC7
b14_loc_9BC4:
    inc $6220                   ; Party battle flags.
b14_loc_9BC7:
    ldx #$03
b14_loc_9BC9:
    lda $0500,x                 ; Per-actor state flags.
    and #$7F
    sta $0500,x                 ; Per-actor state flags.
    dex
    bpl b14_loc_9BC9
    ldx #$09
    lda #$00
b14_loc_9BD8:
    sta $0556,x                 ; Per-actor animation frame.
    dex
    bpl b14_loc_9BD8
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_9BE1:
    .incbin "build/assets/bank14_data.bin", $1BE1, $0002
    jsr wait_vblank_queued
    ldx text_y
    ldy text_y2
    lda party_index
    bne b14_battle_setup_enemy_list
    stx ppu_update_len
    sty ppu_update_off
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_battle_area_from_map
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 13): the area rank $6026 from the map position.
; ----------------------------------------------------------------------
b14_inline_battle_area_from_map:
    jsr set_bank_13
    lda ppu_update_off
    lsr a
    php
    sta ppu_update_ptr_hi
    lda ppu_update_len
    sec
    sbc #$04
    asl a
    asl a
    sta ppu_update_ptr_lo
    asl a
    clc
    adc ppu_update_ptr_lo
    adc ppu_update_ptr_hi
    tax
    lda b13_data_BE98,x
    plp
    bcs b14_loc_9C18
    lsr a
    lsr a
    lsr a
    lsr a
b14_loc_9C18:
    and #$0F
    sta $6026
    jsr return_inline_block

b14_data_9C20:
    .incbin "build/assets/bank14_data.bin", $1C20, $0002
; ----------------------------------------------------------------------
; b14_battle_setup_enemy_list
;   Random battle: b14_battle_roll_encounter_lineup; scripted: $6E/$6F
;   = bank-12 enemy list $8D60 + submode x 5.
; ----------------------------------------------------------------------
b14_battle_setup_enemy_list:
    lda game_submode
    bpl b14_loc_9C2D
    jsr b14_battle_roll_encounter_lineup
    lda game_submode
    bmi b14_loc_9C47
b14_loc_9C2D:
    sta ptr0_lo
    lda #$00
    sta ptr0_hi
    lda #$05
    sta ppu_addr_hi
    jsr mul16_by_u8
    lda ptr0_lo
    clc
    adc #$60
    sta party_scan
    lda ptr0_hi
    adc #$8D
    sta party_scan2
b14_loc_9C47:
    jsr wait_vblank_queued
    jsr b14_battle_gauge_scale
    lda #$01
    sta battle_flags
    lda game_submode
    bmi b14_battle_build_lineup
    lda #$07
    sta text_actor
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_pick_enemy_leader
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 12): the first present officer of the ($6E)
;   list becomes the enemy leader $60AF.
; ----------------------------------------------------------------------
b14_inline_pick_enemy_leader:
    jsr set_bank_12
    ldy #$FF
b14_loc_9C61:
    iny
    lda ($6E),y
    tax
    lda $6300,x
    beq b14_loc_9C61
    cmp #$99
    bcs b14_loc_9C61
    stx $60AF                   ; Party member class/officer id.
    jsr return_inline_block

b14_data_9C74:
    .incbin "build/assets/bank14_data.bin", $1C74, $0002
    lda #$80
    sta input_buttons
    jsr screen_fade_out
    dec $AA
    jsr b14_battle_intro_event
    inc $AA
    jsr screen_fade_in
; ----------------------------------------------------------------------
; b14_battle_build_lineup
;   Battle slots $6097-$609B: present non-strategist members, then the
;   strategist, $A3 for empty; then battle_setup_slots (names,
;   gauges), $AA = 0, and the surprise roll (msgs 102/103).
; ----------------------------------------------------------------------
b14_battle_build_lineup:
    dec battle_flags
    lda #$90
    sta input_buttons
    ldx #$FF
    stx party_count
    stx $79
b14_loc_9C93:
    cpx #$06
    beq b14_loc_9CA6
    inx
    ldy $6090,x                 ; Party member order (actor ids).
    bmi b14_loc_9C93
    lda $609C,y                 ; Party member state bits.
    cmp #$80
    beq b14_loc_9CB8
    bne b14_loc_9C93
b14_loc_9CA6:
    inc $79
    bne b14_loc_9CB6
    ldy #$06
b14_loc_9CAC:
    lda $609C,y                 ; Party member state bits.
    cmp #$C0
    beq b14_loc_9CB8
    dey
    bpl b14_loc_9CAC
b14_loc_9CB6:
    ldy #$A3
b14_loc_9CB8:
    tya
    inc party_count
    ldy party_count
    sta $6097,y                 ; Party member order (actor ids).
    cpy #$04
    bne b14_loc_9C93
.ifdef KANJI_TARGET
    jsr b14_k_setup             ; QoL: busy mode for the slot setup (screen off)
.else
    jsr battle_setup_slots
.endif
    lda #$00
    sta $AA
    sta $7D
    sta $74
    lda #$0A
    sta $0514                   ; Per-actor state flags.
    lda #$0B
    sta $0515                   ; Per-actor state flags.
    lda #$07
    sta text_actor
    jsr read_input_state
    ldx #$03
    lda game_submode
    bpl b14_loc_9CF4
    dex
    lda $60AF                   ; Party member class/officer id.
    cmp #$08
    bcs b14_loc_9CF4
    dex
    cmp #$04
    bcs b14_loc_9CF4
    dex
b14_loc_9CF4:
    lda game_submode
    cmp #$48
    beq b14_loc_9D16
    cmp #$39
    beq b14_loc_9D16
    cmp #$3D
    beq b14_loc_9D16
    cmp #$4E
    beq b14_loc_9D16
    lda rng0
    adc rng3
    and #$3F
    cmp b14_data_A692,x
    bcc b14_loc_9D2C
    cmp b14_data_A696,x
    bcc b14_loc_9D3D
b14_loc_9D16:
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9D1C:
    .dw b10_msg_index_103    ; text index $0067 -> b10_msg_103
    ldx #$1E
    jsr wait_frames
    jsr b14_battle_close_enemy_msg_window
    jsr b14_battle_clear_commands
    jmp b14_battle_party_loses_round
b14_loc_9D2C:
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9D32:
    .dw b10_msg_index_102    ; text index $0066 -> b10_msg_102
    lda #$01
    sta $74
    ldx #$28
    jsr wait_frames
b14_loc_9D3D:
    jsr b14_battle_close_enemy_msg_window
; ----------------------------------------------------------------------
; b14_battle_round_start
;   Start of a round: tactic points, clear the commands; all-out mode
;   goes straight to execution or ends.
; ----------------------------------------------------------------------
b14_battle_round_start:
    jsr b14_calc_strategist_tactic_pts
    jsr b14_battle_clear_commands
    lda text_busy
    bpl b14_battle_command_phase
    cmp #$C0
    beq b14_loc_9D51
    jmp b14_battle_execute_round
b14_loc_9D51:
    jsr b14_battle_all_out_withdraw
    lda #$01
    sta text_busy
; ----------------------------------------------------------------------
; b14_battle_command_phase
;   Command input: slot 0, command count $7C = 0, clear the S.P
;   reserves $6213-$6217.
; ----------------------------------------------------------------------
b14_battle_command_phase:
    lda #$00
    sta party_count
    sta $7C
    ldx #$04
b14_loc_9D60:
    sta $6213,x                 ; Party battle flags.
    dex
    bpl b14_loc_9D60
; ----------------------------------------------------------------------
; b14_battle_command_slot
;   Command input for one slot: skips slots that are down or held by a
;   tactic, loads the portrait ($CF96) and places it.
; ----------------------------------------------------------------------
b14_battle_command_slot:
    lda #$98
    sta input_buttons
    jsr battle_current_actor
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_9D75
b14_loc_9D72:
    jmp b14_loc_9F39
b14_loc_9D75:
    sty text_actor
    lda $6228                   ; Party battle flags.
    and b14_data_BC43,x
    bne b14_loc_9D72
    lda $622A                   ; Party battle flags.
    and b14_data_BC43,x
    bne b14_loc_9D72
    jsr load_actor_portrait
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_9D8D:
    .incbin "build/assets/bank14_data.bin", $1D8D, $0002
    jsr wait_vblank
; ----------------------------------------------------------------------
; b14_battle_command_panel
;   Step forward; window $11 (the round's first command: two columns)
;   or window $12 (four commands).
; ----------------------------------------------------------------------
b14_battle_command_panel:
    jsr b14_battle_actor_step_forward
    lda $7C
    bne b14_loc_9DE5
    jsr clear_text_state
; ----------------------------------------------------------------------
; b14_battle_command_panel_full
;   Window $11 input: the right column is そうこうげき, たいきゃく or ぶしょう
;   (target select, b14_battle_officer_info, then back here).
; ----------------------------------------------------------------------
b14_battle_command_panel_full:
    lda #$06
    sta battle_anim
    lda #$40
    sta text_busy
    ldx #$11
    jsr text_init
    jsr loc_CDB6
    ldx #$00
    stx battle_anim
    inx
    stx text_busy
    bcc b14_loc_9DB8
    jmp b14_battle_cmd_prev_slot
b14_loc_9DB8:
    lda text_menu_sub
    beq b14_battle_cmd_chosen
    ldy #$00
    sty text_menu_sub
    ldx text_menu_index
    bne b14_loc_9DD1
    jsr b14_battle_actor_step_back
    lda #$80
    sta text_busy
    jsr b14_battle_all_out_advance
    jmp b14_battle_execute_round
b14_loc_9DD1:
    dex
    bne b14_loc_9DD7
    jmp b14_battle_cmd_retreat
b14_loc_9DD7:
    jsr b14_battle_select_enemy_target
    beq b14_loc_9DDF
    jmp b14_battle_cmd_retry
b14_loc_9DDF:
    jsr b14_battle_officer_info
    jmp b14_battle_command_panel_full
b14_loc_9DE5:
    ldx #$00
    stx battle_anim
    ldx #$12
    jsr text_init
    jsr text_wait_loop
    bcc b14_battle_cmd_chosen
    jmp b14_battle_cmd_prev_slot
; ----------------------------------------------------------------------
; b14_battle_cmd_chosen
;   Store the left-column command in $61D0,x (0 fight, 1 tactic, 2
;   defend, 3 item), then target or subwindow.
; ----------------------------------------------------------------------
b14_battle_cmd_chosen:
    ldx party_count
    lda #$00
    sta $6200,x                 ; Party battle flags.
    lda text_menu_index
    sta $61D0,x
    bne b14_loc_9E0F
b14_loc_9E04:
    jsr b14_battle_select_enemy_target
    beq b14_loc_9E0C
    jmp b14_battle_cmd_retry
b14_loc_9E0C:
    jmp b14_battle_cmd_accept
b14_loc_9E0F:
    cmp #$02
    beq b14_loc_9E0C
    cmp #$01
    beq b14_battle_cmd_tactic
    jsr compact_items_actor
    jsr battle_actor_items_x8
    lda $6100,y                 ; Party member stats.
    bne b14_battle_item_subwindow
    jsr b14_battle_open_notice_window
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9E28:
    .dw b10_msg_index_009    ; text index $0009 -> b10_msg_009
    jmp b14_battle_cmd_error_wait
; ----------------------------------------------------------------------
; b14_battle_item_subwindow
;   The item subwindow (window $16): chosen slot in $61DA,x, target
;   type from table $8958.
; ----------------------------------------------------------------------
b14_battle_item_subwindow:
    ldx #$16
    jsr b14_battle_open_list_window
    bcs b14_loc_9EA8
    lda text_menu_index
    asl a
    adc text_menu_sub
    ldx party_count
    sta $61DA,x
    jsr battle_actor_items_x8
    clc
    adc $61DA,x
    tay
    lda $6100,y                 ; Party member stats.
    cmp #$40
    bcs b14_loc_9E0C
    sec
    sbc #$18
    bcc b14_loc_9E0C
    tay
    lda b14_data_8958,y
b14_loc_9E56:
    beq b14_loc_9E0C
    bmi b14_loc_9E04
    jsr b14_battle_select_ally_target
    bne b14_loc_9EA8
    beq b14_loc_9E0C
; ----------------------------------------------------------------------
; b14_battle_cmd_tactic
;   さくりゃく: checks strategist, learned tactics and S.P (msgs
;   469/468/470), then the tactic subwindow.
; ----------------------------------------------------------------------
b14_battle_cmd_tactic:
    jsr b14_battle_calc_free_tactic_pts
    jsr battle_sp_owner_x6
    sta $7E
    tya
    bmi b14_loc_9E7B
    lda $61FB                   ; Party calculation temporaries.
    beq b14_loc_9E92
    lda $6210                   ; Party battle flags.
    beq b14_loc_9E92
    lda $65A0,y
    bne b14_battle_tactic_subwindow
b14_loc_9E7B:
    jsr b14_battle_open_notice_window
    lda $7E
    bmi b14_loc_9E8A
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9E85:
    .dw b10_msg_index_468    ; text index $01D4 -> b10_msg_468
    jmp b14_battle_cmd_error_wait
b14_loc_9E8A:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9E8D:
    .dw b10_msg_index_469    ; text index $01D5 -> b10_msg_469
    jmp b14_battle_cmd_error_wait
b14_loc_9E92:
    jsr b14_battle_open_notice_window
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9E98:
    .dw b10_msg_index_470    ; text index $01D6 -> b10_msg_470
    jmp b14_battle_cmd_error_wait
; ----------------------------------------------------------------------
; b14_battle_tactic_needs_river
;   Msg 123 (no river nearby), then b14_battle_cmd_error_wait.
; ----------------------------------------------------------------------
b14_battle_tactic_needs_river:
    jsr b14_battle_open_notice_window
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9EA3:
    .dw b10_msg_index_123    ; text index $007B -> b10_msg_123
; ----------------------------------------------------------------------
; b14_battle_cmd_error_wait
;   Wait for A/B after a command error message, then
;   b14_battle_cmd_retry.
; ----------------------------------------------------------------------
b14_battle_cmd_error_wait:
    jsr loc_D44C
b14_loc_9EA8:
    jmp b14_battle_cmd_retry
; ----------------------------------------------------------------------
; b14_battle_tactic_subwindow
;   The tactic subwindow (window $17): tactic in $6200,x, river check,
;   cost $BBDB against $6210 reserved in $6213,x, target type $BB40.
; ----------------------------------------------------------------------
b14_battle_tactic_subwindow:
    jsr wait_vblank
    ldx #$17
    jsr b14_battle_open_list_window
    bcs b14_battle_cmd_retry
    lda text_menu_index
    asl a
    adc text_menu_sub
    ldx party_count
    sta $61DA,x
    jsr battle_sp_owner_x6
    clc
    adc $61DA,x
    tay
    lda $65A0,y
    sta $6200,x                 ; Party battle flags.
    tay
    lda b14_data_B8B6,y
    cmp #$01
    beq b14_loc_9ED9
    cpy #$12
    bne b14_loc_9EE1
b14_loc_9ED9:
    lda $6220                   ; Party battle flags.
    bne b14_loc_9EE1
    jmp b14_battle_tactic_needs_river
b14_loc_9EE1:
    lda b14_data_BBDB,y
    cmp $6210                   ; Party battle flags.
    beq b14_loc_9EEB
    bcs b14_loc_9E92
b14_loc_9EEB:
    sta $6213,x                 ; Party battle flags.
    lda b14_data_BB40,y
    jmp b14_loc_9E56
; ----------------------------------------------------------------------
; b14_battle_cmd_retry
;   Command cancelled: step back, clear the slot's S.P reserve, reopen
;   the panel.
; ----------------------------------------------------------------------
b14_battle_cmd_retry:
    jsr b14_battle_actor_step_back
    jsr b14_battle_clear_tactic_reserve
    jmp b14_battle_command_panel
; ----------------------------------------------------------------------
; b14_battle_cmd_prev_slot
;   B on the panel: window $14, step back, previous slot that takes
;   input.
; ----------------------------------------------------------------------
b14_battle_cmd_prev_slot:
    jsr b14_battle_blank_party_msg_window
    jsr b14_battle_actor_step_back
b14_loc_9F03:
    dec party_count
    jsr b14_battle_clear_tactic_reserve
    jsr battle_current_actor
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_9F03
    lda $6228                   ; Party battle flags.
    and b14_data_BC43,x
    bne b14_loc_9F03
    lda $622A                   ; Party battle flags.
    and b14_data_BC43,x
    bne b14_loc_9F03
    dec $7C
    beq b14_loc_9F29
    bmi b14_loc_9F29
    jmp b14_battle_command_slot
b14_loc_9F29:
    jmp b14_battle_command_phase
; ----------------------------------------------------------------------
; b14_battle_cmd_accept
;   Command accepted: sound $0A, window $14, step back, next slot or
;   execution after slot 4.
; ----------------------------------------------------------------------
b14_battle_cmd_accept:
    lda #$0A
    jsr sound_queue_add
    jsr b14_battle_blank_party_msg_window
    jsr b14_battle_actor_step_back
    inc $7C
b14_loc_9F39:
    inc party_count
    ldx party_count
    cpx #$05
    beq b14_loc_9F44
    jmp b14_battle_command_slot
b14_loc_9F44:
    jmp b14_battle_execute_round
; ----------------------------------------------------------------------
; b14_battle_all_out_advance
;   そうこうげき: slots 0-4 fight; all units move from column $40 to $70.
;   called by: $9DCB
; ----------------------------------------------------------------------
b14_battle_all_out_advance:
    ldy #$04
b14_loc_9F49:
    lda #$00
    sta $61D0,y
    dey
    bpl b14_loc_9F49
    ldy #$40
    sty $7C
b14_loc_9F55:
    lda #$09
    sta party_count
b14_loc_9F59:
    ldy $7C
    jsr b14_battle_actor_walk_to_x
    dec party_count
    bpl b14_loc_9F59
    jsr battle_sprite_frame
    inc $7C
    inc $7C
    ldy $7C
    cpy #$72
    bne b14_loc_9F55
    rts
; ----------------------------------------------------------------------
; b14_battle_all_out_withdraw
;   All units move back from $70 to $40.
;   called by: $9D51
; ----------------------------------------------------------------------
b14_battle_all_out_withdraw:
    ldy #$70
    sty $7C
b14_loc_9F74:
    lda #$09
    sta party_count
b14_loc_9F78:
    ldy $7C
    jsr b14_sub_AAB2
    dec party_count
    bpl b14_loc_9F78
    jsr loc_C0E2
    dec $7C
    dec $7C
    ldy $7C
    cpy #$3E
    bne b14_loc_9F74
    ldy #$09
b14_loc_9F90:
    lda $0506,y                 ; Per-actor state flags.
    ora #$04
    sta $0506,y                 ; Per-actor state flags.
    dey
    bpl b14_loc_9F90
    rts
; ----------------------------------------------------------------------
; b14_battle_cmd_retreat
;   たいきゃく: msg 046; success if the enemy was unaware or a roll against
;   $A69A passes, else msg 047.
; ----------------------------------------------------------------------
b14_battle_cmd_retreat:
    jsr b14_battle_actor_step_back
    ldx #$15
    jsr text_init
    lda #$88
    sta input_buttons
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9FAB:
    .dw b10_msg_index_046    ; text index $002E -> b10_msg_046
    ldx #$14
    jsr wait_frames
    jsr read_input_state
    lda $74
    lsr a
    bcs b14_battle_retreat_escape
    ldx #$00
    lda game_submode
    bpl b14_loc_9FD3
    inx
    lda $60AF                   ; Party member class/officer id.
    cmp #$02
    bcc b14_loc_9FD3
    inx
    cmp #$04
    bcc b14_loc_9FD3
    inx
    cmp #$08
    bcc b14_loc_9FD3
    inx
b14_loc_9FD3:
    lda rng1
    adc rng3
    and #$1F
    cmp b14_data_A69A,x
    bcc b14_battle_retreat_escape
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_9FE1:
    .dw b10_msg_index_047    ; text index $002F -> b10_msg_047
    ldx #$14
    jsr wait_frames
; ----------------------------------------------------------------------
; b14_battle_party_loses_round
;   Party slots do nothing ($40), enemies act: after an ambush or a
;   failed retreat.
; ----------------------------------------------------------------------
b14_battle_party_loses_round:
    ldx #$09
    lda #$00
b14_loc_9FEC:
    cpx #$05
    bcs b14_loc_9FF2
    lda #$40
b14_loc_9FF2:
    sta $61D0,x
    dex
    bpl b14_loc_9FEC
    jsr b14_battle_blank_party_msg_window
    jmp b14_battle_execute_round
; ----------------------------------------------------------------------
; b14_battle_retreat_escape
;   Successful retreat: the party units turn around, then
;   b14_battle_flee_to_field.
; ----------------------------------------------------------------------
b14_battle_retreat_escape:
    lda #$98
b14_data_A000:
    sta input_buttons
    ldx #$00
    stx party_count
b14_loc_A006:
    jsr battle_current_actor
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_A03A
    ldx party_count
    lda #$84
    sta $0506,x                 ; Per-actor state flags.
    lda #$01
    sta $0536,x                 ; Per-actor palette/facing.
    lda #$06
    sta ptr1_lo
b14_loc_A01E:
    jsr loc_C0E2
    dec ptr1_lo
    bne b14_loc_A01E
    ldx party_count
    lda #$C4
    sta $0506,x                 ; Per-actor state flags.
    inc $0536,x                 ; Per-actor palette/facing.
    lda #$06
    sta ptr1_lo
b14_loc_A033:
    jsr loc_C0E2
    dec ptr1_lo
    bne b14_loc_A033
b14_loc_A03A:
    inc party_count
    ldx party_count
    cpx #$05
b14_data_A040:
    bne b14_loc_A006
    jmp b14_battle_flee_to_field
; ----------------------------------------------------------------------
; b14_battle_execute_round
;   Execution phase: enemy commands (b14_battle_ai_pick_commands),
;   turn order, clear the portrait, then the turn loop.
; ----------------------------------------------------------------------
b14_battle_execute_round:
    jsr b14_battle_ai_pick_commands
    jsr b14_battle_calc_turn_order
    lda #$00
    sta battle_anim
    sta text_menu_sub
    lda $74
    lsr a
    bcc b14_loc_A066
    lda #$00
    sta $74
    ldx #$05
    lda #$40
b14_loc_A05E:
    sta $61D0,x
    inx
    cpx #$0A
    bne b14_loc_A05E
b14_loc_A066:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_A069:
    .incbin "build/assets/bank14_data.bin", $2069, $0002
    jsr wait_vblank
    lda #$00
    sta $7E
; ----------------------------------------------------------------------
; b14_battle_next_turn
;   Next slot of the turn order $61EE; sets text_actor/text_target;
;   tactic effects ending (msg 319).
; ----------------------------------------------------------------------
b14_battle_next_turn:
    ldy $7E
    ldx $61EE,y                 ; Party calculation temporaries.
    stx party_count
    lda $61D0,x
    and #$40
    bne b14_loc_A092
b14_data_A080:
    lda $61E4,x                 ; Party calculation temporaries.
    sta $79
    jsr battle_arg_slot_actor
    sty text_target
    jsr battle_current_actor
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_A095
b14_loc_A092:
    jmp b14_loc_A2A9
b14_loc_A095:
    sty text_actor
    lda text_busy
    bmi b14_loc_A0CF
    jsr b14_battle_show_actor_portrait
    lda $7D
    beq b14_loc_A0D2
    lda game_submode
    cmp #$46
    bne b14_loc_A0D2
    lda battle_flags
    beq b14_loc_A0D2
    ldy text_actor
    lda $60A8,y                 ; Party member class/officer id.
    cmp #$08
    bcc b14_loc_A0D2
    lda rng3
    sbc rng2
    and #$03
    clc
    adc #$E8
    sta ppu_addr_lo
b14_data_A0C0:
    lda #$02
    sta ppu_addr_hi
    lda #$80
    sta input_buttons
    jsr text_show_message
    lda #$90
    sta input_buttons
b14_loc_A0CF:
    jsr b14_battle_open_msg_window
b14_loc_A0D2:
    ldy battle_flags
    ldx party_count
    lda $622A,y                 ; Party battle flags.
    and b14_data_BC43,x
    beq b14_loc_A121
    lda rng3
    sbc rng2
    and #$07
    cmp #$05
    bcs b14_loc_A107
    lda #$09
    sta $61E4,x                 ; Party calculation temporaries.
    lda rng1
    sbc rng0
    and #$03
    ldy battle_flags
    beq b14_loc_A0FA
    clc
    adc #$05
b14_loc_A0FA:
    sta $61E4,x                 ; Party calculation temporaries.
    lda #$00
    sta $61D0,x
    sta $6200,x                 ; Party battle flags.
    beq b14_battle_turn_dispatch
b14_loc_A107:
    lda $622A,y                 ; Party battle flags.
    and b14_data_BC4D,x
    sta $622A,y                 ; Party battle flags.
    lda #$17
    sta text_command
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A117:
    .dw b11_msg_index_319    ; text index $033F -> b11_msg_319
b14_loc_A119:
    ldx #$4B
    jsr b14_battle_delay_anim_frames
b14_loc_A11E:
    jmp b14_loc_A2A2
b14_loc_A121:
    lda $6228,y                 ; Party battle flags.
    and b14_data_BC43,x
    beq b14_battle_turn_dispatch
    lda rng3
    sbc rng2
    and #$07
    cmp #$05
    bcc b14_loc_A11E
    lda $6228,y                 ; Party battle flags.
    and b14_data_BC4D,x
    sta $6228,y                 ; Party battle flags.
    lda #$16
    sta text_command
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A143:
    .dw b11_msg_index_319    ; text index $033F -> b11_msg_319
    jmp b14_loc_A119
; ----------------------------------------------------------------------
; b14_battle_turn_dispatch
;   Run the slot's command: defend (msg 054), item, tactic, otherwise
;   attack.
; ----------------------------------------------------------------------
b14_battle_turn_dispatch:
    ldx party_count
    lda $61D0,x
    cmp #$02
    bne b14_loc_A163
    lda #$80
    sta $61D0,x
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A159:
    .dw b10_msg_index_054    ; text index $0036 -> b10_msg_054
    ldx #$0A
    jsr wait_frames
    jmp b14_loc_A258
b14_loc_A163:
    cmp #$03
    bne b14_loc_A16A
    jmp b14_battle_use_item
b14_loc_A16A:
    ldx party_count
    lda $61D0,x
    cmp #$01
    bne b14_battle_attack
    jmp b14_battle_exec_tactic
; ----------------------------------------------------------------------
; b14_battle_attack
;   たたかう: msg 050, then the attack roll.
; ----------------------------------------------------------------------
b14_battle_attack:
    lda #$00
    jsr battle_effect_setup
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A17E:
    .dw b10_msg_index_050    ; text index $0032 -> b10_msg_050
; ----------------------------------------------------------------------
; b14_battle_attack_roll
;   Step forward; miss (8/256, msg 051) or attack animation and damage
;   (b14_battle_attack_target).
; ----------------------------------------------------------------------
b14_battle_attack_roll:
    jsr b14_battle_actor_step_forward
    lda rng1
    adc rng2
    sta rng1
    cmp #$08
    bcs b14_loc_A19F
    lda #$06
    jsr sound_queue_add
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A195:
    .dw b10_msg_index_051    ; text index $0033 -> b10_msg_051
b14_loc_A197:
    ldx #$1E
    jsr b14_battle_delay_anim_frames
    jmp b14_battle_after_action
b14_loc_A19F:
    lda rng0
    adc rng1
    sta rng0
    sta $7C
b14_loc_A1A7:
    jsr b14_battle_attack_target
; ----------------------------------------------------------------------
; b14_battle_after_action
;   After an action: defeat or victory checks, extra attacks,
;   multi-target tactics, ambush troops.
; ----------------------------------------------------------------------
b14_battle_after_action:
    lda #$04
    sta $79
b14_loc_A1AE:
    jsr battle_arg_slot_actor
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_A1C1
    dec $79
    bpl b14_loc_A1AE
    lda #$01
    sta battle_flags
    jmp b14_battle_over
b14_loc_A1C1:
    ldy #$04
b14_loc_A1C3:
    lda $60A3,y                 ; Party member state bits.
    bmi b14_loc_A1DB
    dey
    bpl b14_loc_A1C3
    lda #$00
    sta battle_flags
    ldx game_submode
    cpx #$3D
    bne b14_loc_A1D8
    jmp b14_battle_event_3d_betrayal
b14_loc_A1D8:
    jmp b14_battle_over
b14_loc_A1DB:
    jsr battle_current_actor
    lda $61D0,x
    bne b14_loc_A204
    lda #$40
    sta $61D0,x
    tya
    asl a
    asl a
    asl a
    tax
b14_loc_A1ED:
    lda $6100,x                 ; Party member stats.
    cmp #$C7
    beq b14_loc_A1F8
    cmp #$CB
    bne b14_loc_A1FE
b14_loc_A1F8:
    jsr b14_battle_open_msg_window
    jmp b14_battle_attack
b14_loc_A1FE:
    inx
    txa
    and #$07
    bne b14_loc_A1ED
b14_loc_A204:
    ldx party_count
    ldy $6200,x                 ; Party battle flags.
    beq b14_loc_A258
    lda b14_data_BB40,y
    bne b14_loc_A258
    lda b14_data_BB5F,y
    beq b14_loc_A258
    lda $61E4,x                 ; Party calculation temporaries.
    sta $79
b14_loc_A21A:
    ldx party_count
    inc $61E4,x                 ; Party calculation temporaries.
    inc $79
    lda $79
    cmp #$05
    beq b14_loc_A240
    cmp #$0A
    beq b14_loc_A240
    jsr battle_arg_slot_actor
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_A235
    bpl b14_loc_A21A
b14_loc_A235:
    sty text_target
    jsr b14_battle_open_msg_window
    inc $6232                   ; Party battle flags.
    jmp b14_loc_A16A
b14_loc_A240:
    sec
    sbc #$05
    sta $79
    sta $61E4,x                 ; Party calculation temporaries.
    ldy party_count
    lda battle_flags
    eor #$01
    tax
    lda $6230,x                 ; Party battle flags.
    and b14_data_BC4D,y
    sta $6230,x                 ; Party battle flags.
b14_loc_A258:
    lda #$00
    sta $6232                   ; Party battle flags.
    ldy party_count
    lda battle_flags
    eor #$01
    tax
    lda $6230,x                 ; Party battle flags.
    and b14_data_BC43,y
    beq b14_loc_A29B
    lda $6221                   ; Party battle flags.
    bne b14_loc_A298
    inc $6221                   ; Party battle flags.
    lda rng1
    sbc rng3
    and #$03
    bne b14_loc_A285
    lda $6230,x                 ; Party battle flags.
    and b14_data_BC4D,y
    sta $6230,x                 ; Party battle flags.
b14_loc_A285:
    lda $61D0,y
    and #$FC
    sta $61D0,y
    jsr b14_battle_open_msg_window
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A293:
    .dw b11_msg_index_318    ; text index $033E -> b11_msg_318
    jmp b14_battle_attack_roll
b14_loc_A298:
    dec $6221                   ; Party battle flags.
b14_loc_A29B:
    lda text_busy
    bmi b14_loc_A2A2
    jsr b14_battle_actor_step_back
b14_loc_A2A2:
    lda text_busy
    bmi b14_loc_A2A9
    jsr b14_battle_close_msg_window
b14_loc_A2A9:
    inc $7E
    lda $7E
    cmp #$0A
    beq b14_battle_round_end
    jmp b14_battle_next_turn
; ----------------------------------------------------------------------
; b14_battle_round_end
;   End of round: active tactic effects may end (b11 msgs 320-323),
;   then the next round.
; ----------------------------------------------------------------------
b14_battle_round_end:
    jsr wait_vblank_queued
    ldx #$00
    stx party_scan
b14_loc_A2BB:
    lda $6224,x                 ; Party battle flags.
    beq b14_loc_A2F8
    lda #$07
    sta text_actor
    jsr read_input_state
    lda rng1
    sbc rng3
    and #$07
    cmp #$05
    bcc b14_loc_A2F8
    jsr text_reset_cursor
    jsr wait_vblank_queued
    jsr b14_battle_open_party_msg_window
    jsr wait_vblank_queued
    ldx party_scan
    lda #$00
    sta $6224,x                 ; Party battle flags.
    txa
    ora #$40
    sta ppu_addr_lo
    lda #$03
    sta ppu_addr_hi
    jsr text_show_message
    ldx #$4B
    jsr b14_battle_delay_anim_frames
    jsr b14_battle_blank_party_msg_window
b14_loc_A2F8:
    inc party_scan
    ldx party_scan
    cpx #$04
    bne b14_loc_A2BB
    inc $7D
    lda game_submode
    cmp #$48
    beq b14_loc_A30B
    jmp b14_battle_round_start
b14_loc_A30B:
    lda #$00
    sta battle_flags
    beq b14_loc_A35A
; ----------------------------------------------------------------------
; b14_battle_use_item
;   どうぐ in battle: msg 010, then the item effect
;   (b14_item_effect_dispatch) or msg 011.
; ----------------------------------------------------------------------
b14_battle_use_item:
    ldx party_count
    lda $61DA,x
    sta $70
    jsr battle_actor_items_x8
    ldx party_count
    clc
    adc $70
    tay
    lda $6100,y                 ; Party member stats.
    sta text_command
    jsr battle_arg_slot_actor
    sty text_target
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A32E:
    .dw b10_msg_index_010    ; text index $000A -> b10_msg_010
    jsr b14_battle_actor_step_forward
    lda text_command
    cmp #$19
    beq b14_loc_A341
    cmp #$30
    bcc b14_loc_A346
    cmp #$40
    bcs b14_loc_A346
b14_loc_A341:
    jsr b14_item_effect_dispatch
    bcs b14_loc_A34B
b14_loc_A346:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A349:
    .dw b10_msg_index_011    ; text index $000B -> b10_msg_011
b14_loc_A34B:
    ldx #$0A
    jsr wait_frames
    jmp b14_battle_after_action
; ----------------------------------------------------------------------
; b14_battle_over
;   Battle result: attributes, music, msgs 059/060, scripted-battle
;   bookkeeping, chained battles.
; ----------------------------------------------------------------------
b14_battle_over:
    lda text_busy
    bmi b14_loc_A35A
    jsr b14_battle_actor_step_back
b14_loc_A35A:
    lda #$80
    sta input_buttons
    ldx #$01
    stx text_busy
    lda battle_flags
    bne b14_loc_A3AE
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_A369:
    .incbin "build/assets/bank14_data.bin", $2369, $0002
    jsr wait_vblank
    ldx game_submode
    bmi b14_loc_A3A8
    inc $6500,x
    lda #$07
    sta text_actor
    inc battle_flags
    inc menu_flags
    jsr b14_battle_victory_event
    dec menu_flags
    dec battle_flags
    lda game_submode
    cmp #$48
    bne b14_loc_A38D
    jmp b14_battle_return_to_field
b14_loc_A38D:
    cmp #$4D
    bne b14_loc_A398
    lda #$36
    sta game_submode
    jmp b14_battle_start
b14_loc_A398:
    cmp #$46
    bne b14_loc_A3A8
    lda #$00
    sta $6547
    lda #$47
    sta game_submode
    jmp b14_battle_start
b14_loc_A3A8:
    lda #$88
    sta input_buttons
    ldx #$15
b14_loc_A3AE:
    jsr text_init
    lda #$07
    sta text_target
    jsr text_reset_cursor
    lda battle_flags
    bne b14_loc_A3D3
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_A3BF:
    .incbin "build/assets/bank14_data.bin", $23BF, $0002
    lda #$FF
    jsr sound_queue_add
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A3C9:
    .dw b10_msg_index_059    ; text index $003B -> b10_msg_059
    lda #$2F
    jsr sound_queue_add_once
    jmp b14_battle_end_anim
b14_loc_A3D3:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_A3D6:
    .incbin "build/assets/bank14_data.bin", $23D6, $0002
    lda #$30
    jsr sound_queue_add_once
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A3E0:
    .dw b10_msg_index_060    ; text index $003C -> b10_msg_060
; ----------------------------------------------------------------------
; b14_battle_end_anim
;   Both outcomes: reset the actors, 120-frame animation, then defeat
;   (sub_E5C1) or the victory path.
; ----------------------------------------------------------------------
b14_battle_end_anim:
    ldx #$09
    lda #$00
b14_loc_A3E6:
    sta $05A6,x                 ; Per-actor animation state.
    dex
    bpl b14_loc_A3E6
    ldx #$09
b14_loc_A3EE:
    lda $0506,x                 ; Per-actor state flags.
    and #$80
    sta $0506,x                 ; Per-actor state flags.
    lda #$01
    sta $0536,x                 ; Per-actor palette/facing.
    dex
    bpl b14_loc_A3EE
    lda #$78
    sta ptr1_lo
b14_loc_A402:
    ldx #$09
b14_loc_A404:
    lda $05A6,x                 ; Per-actor animation state.
    clc
    adc #$03
    sta $05A6,x                 ; Per-actor animation state.
    dex
    bpl b14_loc_A404
    jsr loc_C0E2
    dec ptr1_lo
    bne b14_loc_A402
    lda battle_flags
    beq b14_battle_victory_rewards
    jmp battle_defeat
; ----------------------------------------------------------------------
; b14_battle_victory_rewards
;   Victory: msg 061/062 (exp, gold, food), level-up check, prisoners
;   in random battles.
; ----------------------------------------------------------------------
b14_battle_victory_rewards:
    lda game_submode
    bmi b14_loc_A42A
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A425:
    .dw b10_msg_index_061    ; text index $003D -> b10_msg_061
    jmp b14_loc_A42F
b14_loc_A42A:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A42D:
    .dw b10_msg_index_062    ; text index $003E -> b10_msg_062
b14_loc_A42F:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_A432:
    .incbin "build/assets/bank14_data.bin", $2432, $0002
    jsr wait_vblank
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_A43A:
    .incbin "build/assets/bank14_data.bin", $243A, $0002
    jsr wait_vblank
    ldx #$22
    jsr text_window_restore
    jsr b14_check_level_up
    lda game_submode
    bmi b14_battle_offer_prisoners
    jmp b14_loc_A549
; ----------------------------------------------------------------------
; b14_battle_offer_prisoners
;   Captured enemy officers (msg 104): recruit or release.
; ----------------------------------------------------------------------
b14_battle_offer_prisoners:
    ldy #$07
    sty $7C
b14_loc_A452:
    ldx $60A8,y                 ; Party member class/officer id.
    cpx #$08
    bcs b14_loc_A45C
b14_loc_A459:
    jmp b14_loc_A53E
b14_loc_A45C:
    sty text_actor
    lda $6300,x
    cmp #$98
    beq b14_loc_A459
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A46B:
    .dw b10_msg_index_104    ; text index $0068 -> b10_msg_104
    ldx #$21
    jsr text_window_restore_wait
    lda text_menu_index
    beq b14_loc_A479
b14_loc_A476:
    jmp b14_battle_release_prisoner
b14_loc_A479:
    bcs b14_loc_A476
    lda rng0
    adc rng2
    sta rng0
    and #$0F
    cmp #$03
    bcs b14_loc_A48F
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A48A:
    .dw b10_msg_index_108    ; text index $006C -> b10_msg_108
    jmp b14_loc_A534
b14_loc_A48F:
    cmp #$06
    bcs b14_loc_A49B
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A496:
    .dw b11_msg_index_160    ; text index $02A0 -> b11_msg_160
    jmp b14_loc_A4E5
b14_loc_A49B:
    cmp #$0C
    bcs b14_loc_A4FE
    lda #$00
    sta ptr0_hi
    ldx $6026
    stx ptr0_lo
    stx ppu_addr_hi
    jsr mul16_by_u8
    lda #$00
    jsr read_actor_record_byte
    sta ppu_addr_hi
    lda #$01
    jsr read_actor_record_byte
    cmp ppu_addr_hi
    bcc b14_loc_A4BF
    sta ppu_addr_hi
b14_loc_A4BF:
    jsr mul16_by_u8
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_A4C5:
    .incbin "build/assets/bank14_data.bin", $24C5, $0002
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A4CA:
    .dw b10_msg_index_106    ; text index $006A -> b10_msg_106
    jsr text_window_restore_ask
    bcs b14_loc_A527
    jsr sub24_inline_clamped    ; inline pointer/data follows the JSR

b14_data_A4D4:
    .incbin "build/assets/bank14_data.bin", $24D4, $0002
    bcs b14_loc_A4E5
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_A4DB:
    .incbin "build/assets/bank14_data.bin", $24DB, $0002
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A4E0:
    .dw b10_msg_index_111    ; text index $006F -> b10_msg_111
    jmp b14_loc_A53E
b14_loc_A4E5:
    lda #$04
    sta sound_temp
    ldy text_actor
    lda $60A8,y                 ; Party member class/officer id.
    sta $05F4
    jsr call_b13_9c00
    bcs b14_loc_A4FB
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A4F9:
    .dw b10_msg_index_109    ; text index $006D -> b10_msg_109
b14_loc_A4FB:
    jmp b14_loc_A53E
b14_loc_A4FE:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A501:
    .dw b10_msg_index_107    ; text index $006B -> b10_msg_107
    jsr text_window_restore_ask
    bcs b14_loc_A527
    ldy #$37
b14_loc_A50A:
    lda $6100,y                 ; Party member stats.
    cmp #$2C
    bne b14_loc_A51C
    lda #$00
    sta $6100,y                 ; Party member stats.
    jsr compact_items_all
    jmp b14_loc_A4E5
b14_loc_A51C:
    dey
    bpl b14_loc_A50A
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A522:
    .dw b10_msg_index_112    ; text index $0070 -> b10_msg_112
    jmp b14_loc_A53E
b14_loc_A527:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A52A:
    .dw b10_msg_index_110    ; text index $006E -> b10_msg_110
    jmp b14_loc_A53E
; ----------------------------------------------------------------------
; b14_battle_release_prisoner
;   Msg 105 (released), then the officer's $6300 status = $90.
; ----------------------------------------------------------------------
b14_battle_release_prisoner:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_A532:
    .dw b10_msg_index_105    ; text index $0069 -> b10_msg_105
b14_loc_A534:
    ldy text_actor
    ldx $60A8,y                 ; Party member class/officer id.
    lda #$90
    sta $6300,x
b14_loc_A53E:
    inc $7C
    ldy $7C
    cpy #$0C
    beq b14_loc_A549
    jmp b14_loc_A452
b14_loc_A549:
    jsr wait_keypress
; ----------------------------------------------------------------------
; b14_battle_return_to_field
;   Common battle exit: food rate, actor tables, PPU off, field party
;   sprites, area music.
;   called by: $BAF0
; ----------------------------------------------------------------------
b14_battle_return_to_field:
    lda #$00
    sta text_busy
    jsr b14_calc_food_use_rate
    ldx #$02
b14_loc_A555:
    asl $0500,x                 ; Per-actor state flags.
    sec
    ror $0500,x                 ; Per-actor state flags.
    dex
    bpl b14_loc_A555
    lda battle_flags
    beq b14_loc_A57B
    lda game_submode
    cmp #$3D
    beq b14_loc_A56D
    cmp #$4E
    bne b14_loc_A57B
b14_loc_A56D:
    pla
    pla
    jsr text_hide
    lda #$00
    sta menu_flags
    sta $71
    jmp loc_F1DD
b14_loc_A57B:
    jsr b14_battle_clear_actor_tables
    jsr ppu_bg_sprites_off_shadow
    jsr wait_vblank
    jsr ppu_nmi_off
    jsr b14_init_battle_party
    jsr battle_main
    jmp b14_field_play_area_music
; ----------------------------------------------------------------------
; b14_battle_open_list_window
;   Open the item ($16) or tactic ($17) subwindow given in X and wait
;   (C = 1 on cancel).
;   called by: $9E2F, $9EB0
; ----------------------------------------------------------------------
b14_battle_open_list_window:
    jsr text_init
    dec battle_anim
    bne b14_loc_A59B
    lda #$01
    sta $54
b14_loc_A59B:
    jmp text_wait_loop

b14_data_A59E:
    .incbin "build/assets/bank14_data.bin", $259E, $00F4

b14_data_A692:
    .incbin "build/assets/bank14_data.bin", $2692, $0004

b14_data_A696:
    .incbin "build/assets/bank14_data.bin", $2696, $0004

b14_data_A69A:
    .incbin "build/assets/bank14_data.bin", $269A, $0057

; ----------------------------------------------------------------------
; b14_battle_ai_pick_commands
;   Enemy (all-out: every) command and target choice for the round.
;   called by: $A045
; ----------------------------------------------------------------------
b14_battle_ai_pick_commands:
    ldx #$05
    lda text_busy
    bpl b14_loc_A6F9
    ldx #$00
b14_loc_A6F9:
    stx party_count
b14_loc_A6FB:
    ldx party_count
    cpx #$05
    bcc b14_loc_A75F
    jsr battle_current_actor
    ldx #$06
    lda $61A8,y                 ; Party member derived stats.
    cmp $619C,y                 ; Party member derived stats.
    bcc b14_loc_A738
b14_loc_A70E:
    cmp b14_data_A852,x
    bcs b14_loc_A716
    dex
    bpl b14_loc_A70E
b14_loc_A716:
    lda $7D
    and #$07
    tay
    lda b14_data_A859,x
    clc
    adc b14_data_A860,y
    bpl b14_loc_A726
    lda #$00
b14_loc_A726:
    sta ppu_update_ptr_lo
    lda rng2
    adc rng3
    and #$1F
    cmp ppu_update_ptr_lo
    bcs b14_loc_A75F
    jsr b14_battle_ai_pick_tactic
    jmp b14_loc_A75F
b14_loc_A738:
    cmp b14_data_A868,x
    bcs b14_loc_A740
    dex
    bpl b14_loc_A738
b14_loc_A740:
    lda $7D
    and #$07
    tay
    lda b14_data_A86F,x
    clc
    adc b14_data_A876,y
    bpl b14_loc_A750
    lda #$00
b14_loc_A750:
    sta ppu_update_ptr_lo
    lda rng2
    adc rng3
    and #$1F
    cmp ppu_update_ptr_lo
    bcs b14_loc_A75F
    jsr b14_battle_ai_pick_tactic
b14_loc_A75F:
    ldx #$FF
    stx ppu_update_ptr_lo
    inx
    lda party_count
    cmp #$05
    bcs b14_loc_A76C
    ldx #$05
b14_loc_A76C:
    stx ppu_update_ptr_hi
b14_loc_A76E:
    txa
    jsr battle_slot_actor
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_A779
    inc ppu_update_ptr_lo
b14_loc_A779:
    inc ppu_update_ptr_hi
    ldx ppu_update_ptr_hi
    cpx #$05
    beq b14_loc_A787
    cpx #$0A
    beq b14_loc_A787
    bne b14_loc_A76E
b14_loc_A787:
    asl ppu_update_ptr_lo
    asl ppu_update_ptr_lo
    asl ppu_update_ptr_lo
    asl ppu_update_ptr_lo
    jsr read_input_state
    lda party_count
    and #$03
    tay
    lda rng0,y
    adc rng1
    sta rng0,y
    and #$0F
    clc
    adc ppu_update_ptr_lo
    tay
    lda ppu_update_ptr_lo
    bne b14_loc_A7AB
    ldy #$10
b14_loc_A7AB:
    lda b14_data_A802,y
    sta ppu_update_ptr_hi
    lda #$00
    ldx party_count
    cpx #$05
    bcs b14_loc_A7BA
    lda #$05
b14_loc_A7BA:
    sta ppu_update_ptr_lo
b14_loc_A7BC:
    lda ppu_update_ptr_lo
    inc ppu_update_ptr_lo
    jsr battle_slot_actor
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_A7BC
    dec ppu_update_ptr_hi
    bpl b14_loc_A7BC
    ldx party_count
    dec ppu_update_ptr_lo
    lda ppu_update_ptr_lo
    sta $61E4,x                 ; Party calculation temporaries.
    cpx #$05
    bcc b14_loc_A806
    ldy $6200,x                 ; Party battle flags.
    lda b14_data_BB40,y
    cmp #$01
    bne b14_loc_A806
    lda rng3
    adc rng1
    and #$01
    beq b14_loc_A7FF
    lda rng0
    adc rng2
    and #$03
    clc
    adc #$05
    jsr battle_slot_actor
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_A7FF
    txa
    bpl b14_loc_A801
b14_loc_A7FF:
    lda party_count
b14_loc_A801:
    ldx party_count
    sta $61E4,x                 ; Party calculation temporaries.
b14_loc_A806:
    inc party_count
    ldx party_count
    cpx #$0A
    beq b14_loc_A811
    jmp b14_loc_A6FB
b14_loc_A811:
    rts

b14_data_A812:
    .incbin "build/assets/bank14_data.bin", $2812, $0040

b14_data_A852:
    .incbin "build/assets/bank14_data.bin", $2852, $0007

b14_data_A859:
    .incbin "build/assets/bank14_data.bin", $2859, $0007

b14_data_A860:
    .incbin "build/assets/bank14_data.bin", $2860, $0008

b14_data_A868:
    .incbin "build/assets/bank14_data.bin", $2868, $0007

b14_data_A86F:
    .incbin "build/assets/bank14_data.bin", $286F, $0007

b14_data_A876:
    .incbin "build/assets/bank14_data.bin", $2876, $0008

b14_data_A87E:
    .incbin "build/assets/bank14_data.bin", $287E, $0030

b14_data_A8AE:
    .incbin "build/assets/bank14_data.bin", $28AE, $0004

; ----------------------------------------------------------------------
; b14_battle_ai_pick_tactic
;   Enemy tactic choice by troop ratio and chance; stores it in
;   $6200,x, command $61D0,x = 1.
;   called by: $A732, $A75C
; ----------------------------------------------------------------------
b14_battle_ai_pick_tactic:
    jsr battle_current_actor
    tya
    asl a
    asl a
    tax
    lda $6160,x                 ; Party member derived stats.
    sta $06
    lda $6161,x                 ; Party member derived stats.
    sta $07
    lda #$00
    sta $08
    lda $60D0,x                 ; Party member stats.
    sta ptr0_lo
    lda $60D1,x                 ; Party member stats.
    sta ptr0_hi
    lda #$10
    sta ppu_addr_hi
    jsr mul16_by_u8
    lda ptr0_lo
    sta $00
    lda ptr0_hi
    sta $01
    lda ptr1_lo
    sta $02
    jsr div24_shift
    lda $00
    cmp #$0B
    bcc b14_loc_A8EF
    lda #$0B
b14_loc_A8EF:
    asl a
    asl a
    tax
    lda rng2
    adc rng3
    sbc rng1
    and #$0F
    sta ppu_update_ptr_lo
b14_loc_A8FC:
    lda ppu_update_ptr_lo
    cmp b14_data_A87E,x
    bcc b14_loc_A909
    inx
    txa
    and #$03
    bne b14_loc_A8FC
b14_loc_A909:
    txa
    and #$03
    tax
    lda b14_data_A8AE,x
    sta ppu_update_ptr_hi
    bne b14_loc_A91B
    ldx $6220                   ; Party battle flags.
    beq b14_loc_A91B
    inc ppu_update_ptr_hi
b14_loc_A91B:
    cmp #$04
    bne b14_loc_A92B
    lda rng1
    adc rng2
    sbc rng0
    and #$01
    beq b14_loc_A92B
    inc ppu_update_ptr_hi
b14_loc_A92B:
    jsr battle_sp_owner_x6
    lda #$06
    sta ppu_update_ptr_lo
b14_loc_A932:
    ldx $65A0,y
    lda b14_data_B8B6,x
    cmp ppu_update_ptr_hi
    beq b14_loc_A943
    iny
    dec ppu_update_ptr_lo
    bne b14_loc_A932
    beq b14_loc_A95E
b14_loc_A943:
    ldx party_count
    lda $65A0,y
    beq b14_loc_A95E
    cmp #$12
    bne b14_loc_A956
    inc $6220                   ; Party battle flags.
    dec $6220                   ; Party battle flags.
    beq b14_loc_A95E
b14_loc_A956:
    sta $6200,x                 ; Party battle flags.
    lda #$01
    sta $61D0,x
b14_loc_A95E:
    rts
; ----------------------------------------------------------------------
; b14_battle_calc_turn_order
;   Randomised speed per slot from $61B4, sorted fastest first into
;   $61EE.
;   called by: $A048
; ----------------------------------------------------------------------
b14_battle_calc_turn_order:
    lda #$09
    sta party_count
b14_loc_A963:
    jsr battle_current_actor
    lda $61B4,y                 ; Party member troops/HP.
    sta ptr0_lo
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_A975
    lda #$40
    sta $61D0,x
b14_loc_A975:
    lda battle_flags
    eor #$01
    tay
    lda $622C,y                 ; Party battle flags.
    and b14_data_BC43,x
    beq b14_loc_A98A
    asl ptr0_lo
    bcc b14_loc_A98A
    lda #$FF
    sta ptr0_lo
b14_loc_A98A:
    lda #$00
    sta ptr0_hi
    jsr read_input_state
    lda rng0
    and #$0F
    tax
    lda party_count
    cmp #$05
    bcs b14_loc_A9A9
    ldy b14_data_A9E6,x
    lda b14_data_A9F6,y
    sta ppu_addr_lo
    lda b14_data_A9FB,y
    bpl b14_loc_A9B4
b14_loc_A9A9:
    ldy b14_data_AA00,x
    lda b14_data_AA10,y
    sta ppu_addr_lo
    lda b14_data_AA15,y
b14_loc_A9B4:
    sta ppu_addr_hi
    jsr mul16x16_shr8
    lda ptr0_lo
    ldy ptr0_hi
    beq b14_loc_A9C1
    lda #$FF
b14_loc_A9C1:
    ldx party_count
    sta $0104,x
    dec party_count
    bpl b14_loc_A963
    ldy #$00
    sty ppu_update_ptr_lo
    ldy #$09
b14_loc_A9D0:
    ldx #$09
b14_loc_A9D2:
    lda $0104,x
    cmp ppu_update_ptr_lo
    bne b14_loc_A9DE
    txa
    sta $61EE,y                 ; Party calculation temporaries.
    dey
b14_loc_A9DE:
    dex
    bpl b14_loc_A9D2
    inc ppu_update_ptr_lo
    bne b14_loc_A9D0
    rts

b14_data_A9E6:
    .incbin "build/assets/bank14_data.bin", $29E6, $0010

b14_data_A9F6:
    .incbin "build/assets/bank14_data.bin", $29F6, $0005

b14_data_A9FB:
    .incbin "build/assets/bank14_data.bin", $29FB, $0005

b14_data_AA00:
    .incbin "build/assets/bank14_data.bin", $2A00, $0010

b14_data_AA10:
    .incbin "build/assets/bank14_data.bin", $2A10, $0005

b14_data_AA15:
    .incbin "build/assets/bank14_data.bin", $2A15, $0005
; ----------------------------------------------------------------------
; b14_battle_officer_info
;   ぶしょう in battle: the info screen (b14_officer_info_screen) for the
;   chosen slot, then $A9 = $10, the names of battle slots 0 and 1
;   re-streamed, the gauge colour $03EA restored, the portrait and window
;   reloaded.
;   called by: $9DDF
; ----------------------------------------------------------------------
b14_battle_officer_info:
.ifdef KANJI_TARGET
    ; Step B: UIF_BINFO_ENTER sets the battle-path flag and text_busy = 0
    ; and keeps the P2 colours 1-3.  UIF_BINFO_EXIT (rendering off) streams
    ; again every battle name the screen wrote over (plane 1), blanks the
    ; pool and puts the three colours back (decision 6); it replaces the
    ; original's streaming of slots 0 and 1.  text_actor = slot 0's actor
    ; and text_menu_sub = 1 as the original leaves them.
    jsr battle_slot_actor
    sty text_actor
    ldx #UIF_BINFO_ENTER
    jsr CALL_UI
    jsr b14_officer_info_screen
    jsr ppu_bg_sprites_off
    ldx #UIF_BINFO_EXIT
    jsr CALL_UI
    inc text_busy
    jsr text_hide
    lda #$91
    sta ppu_ctrl_shadow
    lda #$00
    jsr battle_slot_actor
    sty text_actor
    lda #$01
    sta text_menu_sub
    lda #$00
    sta $AA
    jsr load_actor_portrait
    jsr screen_fade_in_step
    ldy #$03
    jmp draw_text_window_small
    .pad $AA61
.else
    jsr battle_slot_actor
    sty text_actor
    lda $03EA                   ; Small VRAM upload buffer.
    pha
    lda #$00
    sta text_busy
    jsr b14_officer_info_screen
    jsr ppu_bg_sprites_off
    inc text_busy
    jsr text_hide
    lda #$91
    sta ppu_ctrl_shadow
    lda #$10
    sta $A9
    lda #$00
    jsr battle_slot_actor
    sty text_actor
    jsr put_officer_name_actor
    lda #$01
    sta text_menu_sub
    jsr battle_slot_actor
    jsr put_officer_name
    lda #$00
    sta $AA
    pla
    sta $03EA                   ; Small VRAM upload buffer.
    jsr load_actor_portrait
    jsr screen_fade_in_step
    ldy #$03
    jmp draw_text_window_small
.endif
; ----------------------------------------------------------------------
; b14_battle_target_has_troops
;   Z = 1 when target slot $79's troops $60D0-$60D2 are zero; X
;   preserved.
;   called by: $AD13
; ----------------------------------------------------------------------
b14_battle_target_has_troops:
    lda $79
    stx ppu_update_ptr_lo
    jsr battle_slot_actor
    tya
    asl a
    asl a
    tax
    lda $60D0,x                 ; Party member stats.
    ora $60D1,x                 ; Party member stats.
    ora $60D2,x                 ; Party member stats.
    pha
    ldx ppu_update_ptr_lo
    pla
    rts
; ----------------------------------------------------------------------
; b14_battle_clear_actor_tables
;   Zero entries 4-15 of every 16-byte actor array $0500-$05FF.
;   called by: $9BA2, $A57B, $B1F0
; ----------------------------------------------------------------------
b14_battle_clear_actor_tables:
    lda #$05
    sta ppu_update_ptr_hi
    lda #$00
    sta ppu_update_ptr_lo
b14_loc_AA82:
    ldy #$04
b14_loc_AA84:
    lda #$00
    sta ($F3),y
    iny
    cpy #$10
    bne b14_loc_AA84
    lda ppu_update_ptr_lo
    clc
    adc #$10
    sta ppu_update_ptr_lo
    bne b14_loc_AA82
b14_loc_AA96:
    rts
; ----------------------------------------------------------------------
; b14_battle_actor_step_forward
;   Walk the current slot's sprite forward to X = $50 (party) or $A0
;   (enemy).
;   called by: $9D92, $A180, $A330, $B964
; ----------------------------------------------------------------------
b14_battle_actor_step_forward:
    lda text_busy
    bmi b14_loc_AA96
    ldy #$50
; ----------------------------------------------------------------------
; b14_battle_actor_walk_to_x
;   Walk the current slot's sprite 2 px per frame to the X in Y
;   (mirrored for enemies).
;   called by: $9F5B
; ----------------------------------------------------------------------
b14_battle_actor_walk_to_x:
    lda #$02
    ldx party_count
    cpx #$05
    bcc b14_loc_AAC3
    sty ppu_update_ptr_lo
    lda #$F0
    sbc ppu_update_ptr_lo
    tay
    lda #$FE
    bne b14_loc_AAC3
; ----------------------------------------------------------------------
; b14_battle_actor_step_back
;   Walk the current slot's sprite back to X = $40 (party) or $B0
;   (enemy).
;   called by: $8A6D, $9DC4, $9EF4, $9F00, $9F34, $9F9C, $A29F, $A357
; ----------------------------------------------------------------------
b14_battle_actor_step_back:
    ldy #$40
; ----------------------------------------------------------------------
; b14_sub_AAB2
;   called by: $9F7A
; ----------------------------------------------------------------------
b14_sub_AAB2:
    lda #$FE
    ldx party_count
    cpx #$05
    bcc b14_loc_AAC3
    sty ppu_update_ptr_lo
    lda #$F0
    sbc ppu_update_ptr_lo
    tay
    lda #$02
b14_loc_AAC3:
    ldx party_count
    sta ptr1_lo
    stx ptr1_hi
    sty ppu_addr_lo
    lda $0506,x                 ; Per-actor state flags.
    and #$FB
    sta $0506,x                 ; Per-actor state flags.
b14_loc_AAD3:
    ldx ptr1_hi
    lda $0556,x                 ; Per-actor animation frame.
    cmp ppu_addr_lo
    beq b14_loc_AAF4
    clc
    adc ptr1_lo
    sta $0556,x                 ; Per-actor animation frame.
    lda $05A6,x                 ; Per-actor animation state.
    adc #$09
    sta $05A6,x                 ; Per-actor animation state.
    lda text_busy
    bmi b14_loc_AAF1
    jsr loc_C0E2
b14_loc_AAF1:
    jmp b14_loc_AAD3
b14_loc_AAF4:
    lda text_busy
    bmi b14_loc_AB00
    lda $0506,x                 ; Per-actor state flags.
    ora #$04
    sta $0506,x                 ; Per-actor state flags.
b14_loc_AB00:
    rts
; ----------------------------------------------------------------------
; b14_battle_place_target_cursor
;   Show the target cursor sprite at the row from table $AB10.
;   called by: $AB99
; ----------------------------------------------------------------------
b14_battle_place_target_cursor:
    lda $0504                   ; Per-actor state flags.
    ora #$84
    sta $0504                   ; Per-actor state flags.
    lda b14_data_AB10,y
    sta $0544                   ; Per-actor tile/sprite id.
    rts

b14_data_AB10:
    .incbin "build/assets/bank14_data.bin", $2B10, $0005
; ----------------------------------------------------------------------
; b14_battle_select_ally_target
;   Up/down target cursor over the party slots 0-4 (item targets).
;   called by: $9E5A
; ----------------------------------------------------------------------
b14_battle_select_ally_target:
    lda $0504                   ; Per-actor state flags.
    and #$BF
    ldx #$50
    ldy #$00
    beq b14_loc_AB29
; ----------------------------------------------------------------------
; b14_battle_select_enemy_target
;   Up/down target cursor over the live enemy slots 5-9; chosen slot
;   in $61E4,x; Z = 1 on A.
;   called by: $9DD7, $9E04
; ----------------------------------------------------------------------
b14_battle_select_enemy_target:
    lda $0504                   ; Per-actor state flags.
    ora #$40
    ldx #$A0
    ldy #$05
b14_loc_AB29:
    sta $0504                   ; Per-actor state flags.
    stx $05E4                   ; Per-actor level.
    sty $79
    lda #$00
    sta ptr1_lo
b14_loc_AB35:
    jsr b14_battle_cursor_slot_state
    bmi b14_loc_AB3E
    inc ptr1_lo
    bne b14_loc_AB35
b14_loc_AB3E:
    lda controller_prev
    and #$0C
    beq b14_loc_AB84
    tay
    lda ptr1_hi
    clc
    adc #$10
    sta ptr1_hi
    bne b14_loc_AB88
    lda #$09
    jsr sound_queue_add
    tya
    eor #$0C
    lsr a
    sec
    sbc #$03
    sta ppu_update_ptr_hi
b14_loc_AB5C:
    lda ptr1_lo
    clc
    adc ppu_update_ptr_hi
    bpl b14_loc_AB65
    lda #$04
b14_loc_AB65:
    cmp #$05
    bne b14_loc_AB6B
    lda #$00
b14_loc_AB6B:
    sta ptr1_lo
    jsr b14_battle_cursor_slot_state
    bmi b14_loc_AB88
    lda $0554                   ; Per-actor animation frame.
    bmi b14_loc_AB5C
    lda ptr1_lo
    clc
    adc $79
    tax
    lda $6097,x                 ; Party member order (actor ids).
    bmi b14_loc_AB5C
    bpl b14_loc_AB88
b14_loc_AB84:
    lda #$F0
    sta ptr1_hi
b14_loc_AB88:
    jsr b14_battle_cursor_slot_state
    lda $05E4                   ; Per-actor level.
    cpx party_count
    bne b14_loc_AB94
    lda #$60
b14_loc_AB94:
    sta $0554                   ; Per-actor animation frame.
    ldy ptr1_lo
    jsr b14_battle_place_target_cursor
    jsr loc_C0E2
    lda controller_state
    and #$C0
    beq b14_loc_AB3E
    and #$40
    php
    lda $0504                   ; Per-actor state flags.
    and #$7F
    sta $0504                   ; Per-actor state flags.
    ldx party_count
    lda $79
    clc
    adc ptr1_lo
    sta $61E4,x                 ; Party calculation temporaries.
    plp
    rts
; ----------------------------------------------------------------------
; b14_battle_cursor_slot_state
;   State bits of slot $79 + ptr1_lo, X = slot.
;   called by: $AB35, $AB6D, $AB88
; ----------------------------------------------------------------------
b14_battle_cursor_slot_state:
    lda ptr1_lo
    clc
    adc $79
    jsr battle_slot_actor
    lda $609C,y                 ; Party member state bits.
    rts
; ----------------------------------------------------------------------
; b14_battle_open_notice_window
;   Message window $15 for a notice (no items, no strategist, not
;   enough S.P) and event text.
;   called by: $9E22, $9E7B, $9E92, $9E9D, $B1D4
; ----------------------------------------------------------------------
b14_battle_open_notice_window:
    lda #$88
    sta input_buttons
    ldx #$15
    jsr text_init
    jmp text_reset_cursor
; ----------------------------------------------------------------------
; b14_battle_show_actor_portrait
;   Load the acting officer's face (tiles $80-$A3) and place it right
;   (enemy) or left (party), then b14_battle_open_msg_window.
;   called by: $A09B
; ----------------------------------------------------------------------
b14_battle_show_actor_portrait:
    jsr load_actor_portrait
    lda battle_flags
    beq b14_loc_ABE3
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_ABDE:
    .incbin "build/assets/bank14_data.bin", $2BDE, $0002
    jmp b14_loc_ABE8
b14_loc_ABE3:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_ABE6:
    .incbin "build/assets/bank14_data.bin", $2BE6, $0002
b14_loc_ABE8:
    jsr loc_C0E2
; ----------------------------------------------------------------------
; b14_battle_open_msg_window
;   Reset the text cursor; message window $01 (enemy) or $15 (party).
;   called by: $A0CF, $A1F8, $A237, $A28D, $BA76
; ----------------------------------------------------------------------
b14_battle_open_msg_window:
    jsr text_reset_cursor
    ldy #$90
    ldx #$01
    lda battle_flags
    bne b14_loc_ABFA
; ----------------------------------------------------------------------
; b14_battle_open_party_msg_window
;   Message window $15.
;   called by: $A2D7
; ----------------------------------------------------------------------
b14_battle_open_party_msg_window:
    ldy #$98
    ldx #$15
b14_loc_ABFA:
    sty input_buttons
    jmp text_init
; ----------------------------------------------------------------------
; b14_battle_close_msg_window
;   Erase the acting side's face and draw the blank window $14 or $13.
;   called by: $8A2F, $A2A6, $AF6B, $B06D, $B25A, $B2A5, $B2BF
; ----------------------------------------------------------------------
b14_battle_close_msg_window:
    lda battle_flags
    beq b14_loc_AC0C
; ----------------------------------------------------------------------
; b14_battle_close_enemy_msg_window
;   Erase the right face and draw the blank window $13.
;   called by: $8A55, $8A70, $8ADB, $9D23, $9D3D
; ----------------------------------------------------------------------
b14_battle_close_enemy_msg_window:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_AC06:
    .incbin "build/assets/bank14_data.bin", $2C06, $0002
    ldx #$13
    bne b14_loc_AC13
b14_loc_AC0C:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_AC0F:
    .incbin "build/assets/bank14_data.bin", $2C0F, $0002
; ----------------------------------------------------------------------
; b14_battle_blank_party_msg_window
;   Draw the blank window $14 (no face erase).
;   called by: $9EFD, $9F31, $9FF8, $A2F5, $B01F, $B03C
; ----------------------------------------------------------------------
b14_battle_blank_party_msg_window:
    ldx #$14
b14_loc_AC13:
    inc input_buttons
    jsr text_init
    dec input_buttons
    rts
; ----------------------------------------------------------------------
; b14_battle_attack_target
;   Normal attack: retarget past dead slots, flash or shake, damage,
;   kill and wipe-out messages (055-058), troop panel update.
;   called by: $A1A7
; ----------------------------------------------------------------------
b14_battle_attack_target:
    ldy battle_flags
    ldx party_count
    lda $622A,y                 ; Party battle flags.
    and b14_data_BC43,x
    bne b14_loc_AC32
    lda $6200,x                 ; Party battle flags.
    bne b14_loc_AC32
    lda $6226,y                 ; Party battle flags.
    beq b14_loc_AC32
    rts
b14_loc_AC32:
    ldx party_count
    lda $61E4,x                 ; Party calculation temporaries.
    sta $79
    jsr battle_arg_slot_actor
    sty text_target
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_AC49
    jsr b14_battle_next_target_slot
    jmp b14_loc_AC32
b14_loc_AC49:
    ldx party_count
    lda $61D0,x
    cmp #$01
    bne b14_loc_AC56
    lda #$00
    sta $7C
b14_loc_AC56:
    ldy $61E4,x                 ; Party calculation temporaries.
    lda b14_data_AD63,y
    sta $0545                   ; Per-actor tile/sprite id.
    lda b14_data_AD87,y
    ldx text_busy
    bmi b14_loc_AC70
    lda b14_data_AD6D,y
    cpy party_count
    bne b14_loc_AC70
    lda b14_data_AD91,y
b14_loc_AC70:
    sta $0555                   ; Per-actor animation frame.
    lda #$00
    sta ptr1_lo
    ldx $7C
    lda #$00
    ldy battle_flags
    beq b14_loc_AC81
    lda #$02
b14_loc_AC81:
    cpx #$F0
    bcc b14_loc_AC87
    adc #$00
b14_loc_AC87:
    jsr sound_queue_add
b14_loc_AC8A:
    lda ptr1_lo
    lsr a
    bcs b14_loc_ACA1
    ldy $79
    lda $0506,y                 ; Per-actor state flags.
    eor #$80
    sta $0506,y                 ; Per-actor state flags.
    lda $0505                   ; Per-actor state flags.
    eor #$80
    sta $0505                   ; Per-actor state flags.
b14_loc_ACA1:
    lda $05A5                   ; Per-actor animation state.
    adc #$09
    sta $05A5                   ; Per-actor animation state.
    lda battle_flags
    beq b14_loc_ACDF
    lda ptr1_lo
    lsr a
    bcs b14_loc_ACDF
    ldx text_busy
    bmi b14_loc_ACB9
    lsr a
    bcs b14_loc_ACDF
b14_loc_ACB9:
    and #$03
    tay
    lda b14_data_AD77,y
.ifdef KANJI_TARGET
    ; Four-screen nametables (map-canvas step 2): the battle shake's
    ; "sta scroll_y / lda $AD7B,y / sta scroll_x" at $ACBF calls the fixed
    ; bank, which also sets PPUCTRL bit 1 while the screen is shifted up.
    jsr BATTLE_SHAKE
    nop
    nop
    nop
    nop
.else
    sta scroll_y
    lda b14_data_AD7B,y
    sta scroll_x
.endif
    ldx #$0F
b14_loc_ACC8:
    lda $0540,x                 ; Per-actor tile/sprite id.
    clc
    adc b14_data_AD7F,y
    sta $0540,x                 ; Per-actor tile/sprite id.
    lda $0550,x                 ; Per-actor animation frame.
    clc
    adc b14_data_AD83,y
    sta $0550,x                 ; Per-actor animation frame.
    dex
    bpl b14_loc_ACC8
b14_loc_ACDF:
    jsr battle_sprite_frame
    inc ptr1_lo
    lda ptr1_lo
    ldx text_busy
    bmi b14_loc_ACF0
    cmp #$20
    bne b14_loc_AC8A
    beq b14_loc_ACF4
b14_loc_ACF0:
    cmp #$10
    bne b14_loc_AC8A
b14_loc_ACF4:
    lda #$00
    sta $0505                   ; Per-actor state flags.
    jsr battle_sprite_frame
    jsr b14_battle_calc_damage
    lda battle_flags
    bne b14_loc_AD0B
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_AD06:
    .dw b10_msg_index_055    ; text index $0037 -> b10_msg_055
    jmp b14_loc_AD10
b14_loc_AD0B:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_AD0E:
    .dw b10_msg_index_056    ; text index $0038 -> b10_msg_056
b14_loc_AD10:
    jsr battle_draw_slot_troops
    jsr b14_battle_target_has_troops
    bne b14_loc_AD62
    ldx $79
    lda $0506,x                 ; Per-actor state flags.
    and #$7F
    sta $0506,x                 ; Per-actor state flags.
    jsr battle_arg_slot_actor
    lda #$00
    sta $609C,y                 ; Party member state bits.
    lda battle_flags
    bne b14_loc_AD3E
    ldx #$15
    jsr text_init
    jsr text_reset_cursor
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_AD39:
    .dw b10_msg_index_057    ; text index $0039 -> b10_msg_057
    jmp b14_loc_AD62
b14_loc_AD3E:
    lda #$05
    jsr sound_queue_add
    jsr reset_text_engine
    jsr text_reset_cursor
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_AD4C:
    .dw b10_msg_index_058    ; text index $003A -> b10_msg_058
    ldx $79
    lda $6228                   ; Party battle flags.
    and b14_data_BC4D,x
    sta $6228                   ; Party battle flags.
    lda $622A                   ; Party battle flags.
    and b14_data_BC4D,x
    sta $622A                   ; Party battle flags.
b14_loc_AD62:
    rts

b14_data_AD63:
    .incbin "build/assets/bank14_data.bin", $2D63, $000A

b14_data_AD6D:
    .incbin "build/assets/bank14_data.bin", $2D6D, $000A

b14_data_AD77:
    .incbin "build/assets/bank14_data.bin", $2D77, $0004

b14_data_AD7B:
    .incbin "build/assets/bank14_data.bin", $2D7B, $0004

b14_data_AD7F:
    .incbin "build/assets/bank14_data.bin", $2D7F, $0004

b14_data_AD83:
    .incbin "build/assets/bank14_data.bin", $2D83, $0004

b14_data_AD87:
    .incbin "build/assets/bank14_data.bin", $2D87, $000A

b14_data_AD91:
    .incbin "build/assets/bank14_data.bin", $2D91, $000A
; ----------------------------------------------------------------------
; b14_battle_next_target_slot
;   $61E4,x = next slot on the same side (5 -> 0, 10 -> 5).
;   called by: $AC43
; ----------------------------------------------------------------------
b14_battle_next_target_slot:
    ldx party_count
    inc $61E4,x                 ; Party calculation temporaries.
    lda $61E4,x                 ; Party calculation temporaries.
    cmp #$05
    bne b14_loc_ADAB
    lda #$00
    beq b14_loc_ADB1
b14_loc_ADAB:
    cmp #$0A
    bne b14_loc_ADB1
    lda #$05
b14_loc_ADB1:
    sta $61E4,x                 ; Party calculation temporaries.
    rts
; ----------------------------------------------------------------------
; b14_battle_gauge_scale
;   Troop gauge scale: the party's largest maximum troops against
;   500/2001/5001/10001/15001 picks units per segment ($76/$77) and
;   the gauge colour (table $AE46), stored to $03EA (BG palette 2
;   colour 2) and vram_dma_pending.
;   called by: $9C4A
; ----------------------------------------------------------------------
b14_battle_gauge_scale:
    ldx #$00
b14_loc_ADB7:
    lda $6097,x                 ; Party member order (actor ids).
    bpl b14_loc_ADC2
    inx
    cpx #$05
    bne b14_loc_ADB7
    rts
b14_loc_ADC2:
    asl a
    asl a
    tay
    lda $6160,y                 ; Party member derived stats.
    sta ptr1_hi
    lda $6161,y                 ; Party member derived stats.
    sta ppu_addr_lo
    lda $6162,y                 ; Party member derived stats.
    sta ppu_addr_hi
b14_loc_ADD4:
    inx
    cpx #$05
    beq b14_loc_AE10
    lda $6097,x                 ; Party member order (actor ids).
    bmi b14_loc_ADD4
    asl a
    asl a
    tay
    lda $6160,y                 ; Party member derived stats.
    sta ptr0_lo
    lda $6161,y                 ; Party member derived stats.
    sta ptr0_hi
    lda $6162,y                 ; Party member derived stats.
    sta ptr1_lo
    jsr sub24_inline_clamped    ; inline pointer/data follows the JSR

b14_data_ADF3:
    .incbin "build/assets/bank14_data.bin", $2DF3, $0002
    php
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_ADF9:
    .incbin "build/assets/bank14_data.bin", $2DF9, $0002
    plp
    bcs b14_loc_ADD4
    lda $6160,y                 ; Party member derived stats.
    sta ptr1_hi
    lda $6161,y                 ; Party member derived stats.
    sta ppu_addr_lo
    lda $6162,y                 ; Party member derived stats.
    sta ppu_addr_hi
    jmp b14_loc_ADD4
b14_loc_AE10:
    ldx #$00
b14_loc_AE12:
    lda #$00
    sta ptr1_lo
    lda b14_data_AE58,x
    sta ptr0_hi
    lda b14_data_AE5D,x
    sta ptr0_lo
    jsr sub24_inline_clamped    ; inline pointer/data follows the JSR

b14_data_AE23:
    .incbin "build/assets/bank14_data.bin", $2E23, $0002
    php
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_AE29:
    .incbin "build/assets/bank14_data.bin", $2E29, $0002
    plp
    bcc b14_loc_AE33
    inx
    cpx #$05
    bne b14_loc_AE12
b14_loc_AE33:
    lda b14_data_AE4C,x
    sta $76
    lda b14_data_AE52,x
    sta $77
    lda b14_data_AE46,x
.ifdef KANJI_TARGET
    ; Step B, decision 6: P2 colour 3 = colour 2 as well (colour 1 is $0F
    ; in palette set 8), so the gauges show plane 1 only.
    jmp b14_k_gauge_colour
    nop
    nop
    nop
.else
    sta $03EA                   ; Small VRAM upload buffer.
    sta vram_dma_pending
    rts
.endif

b14_data_AE46:
    .incbin "build/assets/bank14_data.bin", $2E46, $0006

b14_data_AE4C:
    .incbin "build/assets/bank14_data.bin", $2E4C, $0006

b14_data_AE52:
    .incbin "build/assets/bank14_data.bin", $2E52, $0006

b14_data_AE58:
    .incbin "build/assets/bank14_data.bin", $2E58, $0005

b14_data_AE5D:
    .incbin "build/assets/bank14_data.bin", $2E5D, $0005
; ----------------------------------------------------------------------
; b14_battle_calc_free_tactic_pts
;   $6210 = tactic points $61FB minus the costs reserved this turn
;   ($6213-$6217).
;   called by: $9E61
; ----------------------------------------------------------------------
b14_battle_calc_free_tactic_pts:
    lda $61FB                   ; Party calculation temporaries.
    sec
    sbc $6213                   ; Party battle flags.
    sbc $6214                   ; Party battle flags.
    sbc $6215                   ; Party battle flags.
    sbc $6216                   ; Party battle flags.
    sbc $6217                   ; Party battle flags.
    sta $6210                   ; Party battle flags.
    rts
; ----------------------------------------------------------------------
; b14_battle_clear_tactic_reserve
;   Clear the current slot's reserved tactic cost $6213,x.
;   called by: $9EF7, $9F05
; ----------------------------------------------------------------------
b14_battle_clear_tactic_reserve:
    ldx party_count
    lda #$00
    sta $6213,x                 ; Party battle flags.
    rts

b14_data_AE81:
    .incbin "build/assets/bank14_data.bin", $2E81, $0006
; ----------------------------------------------------------------------
; b14_battle_actor_max_ability
;   The larger of the acting member's $619C and $61A8.
;   called by: $97A4, $BA3C
; ----------------------------------------------------------------------
b14_battle_actor_max_ability:
    jsr battle_current_actor
    lda $619C,y                 ; Party member derived stats.
    cmp $61A8,y                 ; Party member derived stats.
    bcs b14_loc_AE95
    lda $61A8,y                 ; Party member derived stats.
b14_loc_AE95:
    rts
; ----------------------------------------------------------------------
; b14_battle_clear_commands
;   Clear the command ($61D0) and tactic ($6200) bytes of all 10
;   slots.
;   called by: $9D26, $9D43
; ----------------------------------------------------------------------
b14_battle_clear_commands:
    lda #$00
    ldx #$09
b14_loc_AE9A:
    sta $61D0,x
    sta $6200,x                 ; Party battle flags.
    dex
    bpl b14_loc_AE9A
    rts
; ----------------------------------------------------------------------
; b14_battle_delay_anim_frames
;   Wait X frames running the actor animation (skipped in all-out
;   mode).
;   called by: $A11B, $A199, $A2F2
; ----------------------------------------------------------------------
b14_battle_delay_anim_frames:
    lda text_busy
    bmi b14_loc_AEB3
    txa
b14_loc_AEA9:
    pha
    jsr battle_sprite_frame
    pla
    sec
    sbc #$01
    bne b14_loc_AEA9
b14_loc_AEB3:
    rts
b14_loc_AEB4:
    lda #$57
    jsr text_load_page
    jmp b14_loc_AEDB
; ----------------------------------------------------------------------
; b14_battle_intro_event
;   Scripted battle intro: the leader's face and message, special
;   cases, then the window closes.
;   called by: $9C7F
; ----------------------------------------------------------------------
b14_battle_intro_event:
    ldx game_submode
    cpx #$4D
    beq b14_loc_AEB4
    lda b14_data_AFC7,x
    cmp #$FF
    bne b14_loc_AED5
    lda game_submode
    cmp #$04
    bne b14_loc_AED4
    lda #$02
    sta $677D
b14_loc_AED4:
    rts
b14_loc_AED5:
    asl a
    bcs b14_loc_AEE8
    jsr load_actor_portrait
b14_loc_AEDB:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_AEDE:
    .incbin "build/assets/bank14_data.bin", $2EDE, $0002
    lda #$FF
    jsr sound_queue_add
    jsr wait_vblank
b14_loc_AEE8:
    jsr reset_text_engine
    ldx game_submode
    lda b14_data_AF6F,x
    sta ppu_addr_lo
    lda b14_data_AFC7,x
    and #$7F
    sta ppu_addr_hi
    jsr text_show_message
    ldx game_submode
    cpx #$48
    bne b14_loc_AF5F
    lda $63BC
    and #$40
    beq b14_loc_AF5F
    jsr wait_keypress
    lda #$80
    sta $63C0
    lda #$BC
    jsr text_load_page
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_AF1C:
    .dw b11_msg_index_248    ; text index $02F8 -> b11_msg_248
    ldx #$06
b14_loc_AF20:
    lda $60A8,x                 ; Party member class/officer id.
    cmp #$BC
    beq b14_loc_AF43
    dex
    bpl b14_loc_AF20
    ldx #$3F
b14_loc_AF2C:
    lda $6030,x
    cmp #$BC
    beq b14_loc_AF38
    dex
    bpl b14_loc_AF2C
    bmi b14_loc_AF5F
b14_loc_AF38:
    lda #$00
    sta $6030,x
    jsr b14_sub_9579
    jmp b14_loc_AF5F
b14_loc_AF43:
    txa
    sta ppu_update_len
    pha
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_AF4A
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_AF4A:
    jsr set_bank_13
    jsr $9DFF                   ; bank 13 target
    jsr return_inline_block

b14_data_AF53:
    .incbin "build/assets/bank14_data.bin", $2F53, $0002
    pla
    tax
    lda #$00
    sta $60A8,x                 ; Party member class/officer id.
    sta $609C,x                 ; Party member state bits.
b14_loc_AF5F:
    ldx game_submode
    cpx #$4E
    bne b14_loc_AF68
    jmp b14_battle_lightning_dodge_input
b14_loc_AF68:
    jsr wait_keypress
    jsr b14_battle_close_msg_window
    rts

b14_data_AF6F:
    .incbin "build/assets/bank14_data.bin", $2F6F, $0058

b14_data_AFC7:
    .incbin "build/assets/bank14_data.bin", $2FC7, $0039

b14_data_B000:
    .incbin "build/assets/bank14_data.bin", $3000, $001F

b14_loc_B01F:
    jsr b14_battle_blank_party_msg_window
    lda #$57
    jsr text_load_page
    jmp b14_loc_B045
; ----------------------------------------------------------------------
; b14_battle_victory_event
;   Scripted battle: post-victory face and message, story flags,
;   captured officers' $6300 = $90.
;   called by: $A37D
; ----------------------------------------------------------------------
b14_battle_victory_event:
    ldx game_submode
    cpx #$4D
    beq b14_loc_B01F
    lda b14_data_B149,x
    cmp #$FF
    bne b14_loc_B03A
    jmp b14_loc_B0BD
b14_loc_B03A:
    asl a
    php
    jsr b14_battle_blank_party_msg_window
    plp
    bcs b14_loc_B04D
    jsr load_actor_portrait
b14_loc_B045:
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_B048:
    .incbin "build/assets/bank14_data.bin", $3048, $0002
    jsr wait_vblank
b14_loc_B04D:
    jsr reset_text_engine
    ldx game_submode
    lda b14_data_B0F1,x
    sta ppu_addr_lo
    lda b14_data_B149,x
    and #$7F
    sta ppu_addr_hi
    jsr text_show_message
    jsr wait_keypress
    lda #$F6
    sta $A5
    ldy #$0A
    jsr draw_window
    jsr b14_battle_close_msg_window
    inc vram_dma_pending
    lda game_submode
    cmp #$03
    bcs b14_loc_B093
    lda $6500
    and $6501
    and $6502
    beq b14_loc_B093
    sta $6570
    lda #$00
    sta $6505
    lda #$80
    sta $6310
    sta $63BA
b14_loc_B093:
    lda game_submode
    cmp #$05
    bne b14_loc_B0A7
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_B09C
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b14_inline_B09C:
    jsr set_bank_13
    jsr $A37F                   ; bank 13 target
    jsr return_inline_block

b14_data_B0A5:
    .incbin "build/assets/bank14_data.bin", $30A5, $0002
b14_loc_B0A7:
    lda game_submode
    cmp #$1F
    bne b14_loc_B0B5
    lda #$80
    sta $6341
    sta $6342
b14_loc_B0B5:
    cmp #$48
    beq b14_loc_B0BC
    jmp b14_loc_B0C8
b14_loc_B0BC:
    rts
b14_loc_B0BD:
    lda game_submode
    cmp #$04
    bne b14_loc_B0C8
    lda #$82
    sta $677D
b14_loc_B0C8:
    lda #$04
    sta ppu_update_ptr_lo
b14_loc_B0CC:
    ldx ppu_update_ptr_lo
    lda $60AF,x                 ; Party member class/officer id.
    sta ppu_update_ptr_hi
    lsr a
    lsr a
    lsr a
    tax
    lda ppu_update_ptr_hi
    and #$07
    tay
    lda b14_data_B1A1,x
b14_loc_B0DF:
    asl a
    dey
    bpl b14_loc_B0DF
    bcc b14_loc_B0EC
    ldx ppu_update_ptr_hi
    lda #$90
    sta $6300,x
b14_loc_B0EC:
    dec ppu_update_ptr_lo
    bpl b14_loc_B0CC
    rts

b14_data_B0F1:
    .incbin "build/assets/bank14_data.bin", $30F1, $0058

b14_data_B149:
    .incbin "build/assets/bank14_data.bin", $3149, $0058

b14_data_B1A1:
    .incbin "build/assets/bank14_data.bin", $31A1, $0020

; ----------------------------------------------------------------------
; b14_battle_event_3d_betrayal
;   Scripted battle $3D ending: dialogue (b11 191-200), then the
;   lightning sequence.
; ----------------------------------------------------------------------
b14_battle_event_3d_betrayal:
    lda #$01
    sta text_busy
    jsr loc_C0E2
    lda #$01
    sta $653D
    lda #$00
    sta $654E
    sta battle_flags
    jsr b14_battle_open_notice_window
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B1DA:
    .dw b11_msg_index_191    ; text index $02BF -> b11_msg_191
    jsr text_draw_char
    ldy #$05
    jsr draw_window
    jsr ppu_init
    lda #$24
    ldx #$0A
    ldy #$00
    jsr set_ppu_scroll
    jsr b14_battle_clear_actor_tables
    jsr loc_C139
    jsr b14_event_speaker_right_71
    lda #$25
    jsr sound_queue_add_once
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B201:
    .dw b11_msg_index_192    ; text index $02C0 -> b11_msg_192
    jsr b14_event_speaker_left_88
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B209:
    .dw b11_msg_index_193    ; text index $02C1 -> b11_msg_193
    jsr text_draw_char
    jsr b14_sub_B2DA
    jsr b14_event_speaker_right_71
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B217:
    .dw b11_msg_index_195    ; text index $02C3 -> b11_msg_195
    jsr b14_event_speaker_left_88
    jsr b14_sub_B2DA
    jsr b14_event_speaker_right_71
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B225:
    .dw b11_msg_index_196    ; text index $02C4 -> b11_msg_196
    jsr b14_event_speaker_left_88
    jsr b14_sub_B2DA
    jsr b14_event_speaker_right_71
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B233:
    .dw b11_msg_index_197    ; text index $02C5 -> b11_msg_197
    jsr text_draw_char
    jsr b14_event_speaker_left_88
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B23E:
    .dw b11_msg_index_198    ; text index $02C6 -> b11_msg_198
    jsr text_draw_char
    jsr b14_sub_B2DA
    jsr b14_event_speaker_right_71
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B24C:
    .dw b11_msg_index_199    ; text index $02C7 -> b11_msg_199
    jsr loc_D44C
    lda #$F6
    sta $A5
    ldy #$0A
    jsr draw_window
    jsr b14_battle_close_msg_window
    inc vram_dma_pending
    jsr b14_event_speaker_left_88
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B265:
    .dw b11_msg_index_200    ; text index $02C8 -> b11_msg_200
    jsr loc_D44C
; ----------------------------------------------------------------------
; b14_battle_lightning_strike_loss
;   Palette flash, b11 201, then the battle ends as a loss.
; ----------------------------------------------------------------------
b14_battle_lightning_strike_loss:
    lda #$04
    jsr sound_queue_add
    lda #$14
    sta party_scan
b14_loc_B273:
    lda #$20
    sta $03E2                   ; Small VRAM upload buffer.
    sta $03F0                   ; Small VRAM upload buffer.
    sta vram_dma_pending
    jsr wait_vblank
    lda #$0F
    sta $03E2                   ; Small VRAM upload buffer.
    sta $03F0                   ; Small VRAM upload buffer.
    sta vram_dma_pending
    jsr wait_vblank
    dec party_scan
    bne b14_loc_B273
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B294:
    .dw b11_msg_index_201    ; text index $02C9 -> b11_msg_201
    jsr loc_D44C
    jsr jmp_b13_b3cb
    inc battle_flags
    jmp b14_battle_return_to_field
; ----------------------------------------------------------------------
; b14_event_speaker_right_71
;   Event dialogue: face $71 on the right, message window 1.
;   called by: $B1F6, $B211, $B21F, $B22D, $B246
; ----------------------------------------------------------------------
b14_event_speaker_right_71:
    lda #$00
    sta battle_flags
    jsr b14_battle_close_msg_window
    inc battle_flags
    lda #$71
    jsr text_load_page
    lda #$80
    sta input_buttons
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_B2B6:
    .incbin "build/assets/bank14_data.bin", $32B6, $0002
    jmp reset_text_engine
; ----------------------------------------------------------------------
; b14_event_speaker_left_88
;   Event dialogue: face $88 on the left, message window $15.
;   called by: $B203, $B219, $B227, $B238, $B25F
; ----------------------------------------------------------------------
b14_event_speaker_left_88:
    lda #$01
    sta battle_flags
    jsr b14_battle_close_msg_window
    dec battle_flags
    lda #$88
    jsr text_load_page
    lda #$88
    sta input_buttons
    jsr draw_string             ; inline pointer/data follows the JSR

b14_data_B2D0:
    .incbin "build/assets/bank14_data.bin", $32D0, $0002
    jsr text_reset_cursor
    ldx #$15
    jmp text_init
; ----------------------------------------------------------------------
; b14_sub_B2DA
;   called by: $B20E, $B21C, $B22A, $B243
; ----------------------------------------------------------------------
b14_sub_B2DA:
    lda #$03
    jsr sound_queue_add
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B2E2:
    .dw b11_msg_index_194    ; text index $02C2 -> b11_msg_194
    jmp text_draw_char
; ----------------------------------------------------------------------
; b14_battle_lightning_dodge_input
;   Scripted battle $4E: an 8-press input within about 255 frames;
;   timeout -> the strike.
; ----------------------------------------------------------------------
b14_battle_lightning_dodge_input:
    jsr text_draw_char
    lda #$00
    sta ppu_update_off
    sta ppu_update_len
b14_loc_B2F0:
    jsr wait_vblank
    ldx ppu_update_len
    cpx #$08
    beq b14_loc_B311
    lda controller_state
    beq b14_loc_B308
    cmp b14_data_B31C,x
    beq b14_loc_B306
    lda #$FF
    sta ppu_update_len
b14_loc_B306:
    inc ppu_update_len
b14_loc_B308:
    dec ppu_update_off
    bne b14_loc_B2F0
    pla
    pla
    jmp b14_battle_lightning_strike_loss
b14_loc_B311:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B314:
    .dw b11_msg_index_210    ; text index $02D2 -> b11_msg_210
    jsr wait_keypress
    jmp b14_battle_close_msg_window

b14_data_B31C:
    .incbin "build/assets/bank14_data.bin", $331C, $0008
; ----------------------------------------------------------------------
; b14_battle_roll_encounter_lineup
;   Random encounter: enemy type from the terrain, 2-5 enemies into
;   $0300-$0304, maybe one regional officer.
;   called by: $9C26
; ----------------------------------------------------------------------
b14_battle_roll_encounter_lineup:
    ldx #$04
    lda #$00
b14_loc_B328:
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    dex
    bpl b14_loc_B328
    ldx #$08
    stx $7C
b14_loc_B332:
    ldx $7C
    stx game_mode
    jsr draw_status_panel
    cpy #$10
    beq b14_loc_B357
    cpy #$04
    beq b14_loc_B35B
    cpy #$14
    beq b14_loc_B35B
    dec $7C
    bpl b14_loc_B332
    lda rng3
    sbc rng0
    sta rng3
    and #$01
    clc
    adc #$03
    tay
    bne b14_loc_B35D
b14_loc_B357:
    ldy #$01
    bne b14_loc_B35D
b14_loc_B35B:
    ldy #$02
b14_loc_B35D:
    ldx #$03
    lda $6026
    cmp #$06
    bcc b14_loc_B36A
    ldy #$04
    ldx #$01
b14_loc_B36A:
    sty ppu_update_len
    stx cursor_blink
    lda rng1
    adc rng2
    sta rng1
    and #$0F
    tax
    lda b14_data_B3FE,x
    sta ppu_update_off
    jsr read_input_state
    ldx #$00
    stx ppu_update_ptr_hi
b14_loc_B383:
    lda ppu_update_ptr_hi
    bne b14_loc_B3BE
    txa
    and #$03
    tay
    lda rng0,y
    adc rng3
    sta rng0,y
    and cursor_blink
    bne b14_loc_B3BE
    jsr b14_collect_region_officers
    lda party_scan
    beq b14_loc_B3BE
    ldy #$00
b14_loc_B3A0:
    lda $0310,y                 ; Top 8x8 tiles for the four text lines.
    iny
    cpy party_scan
    bne b14_loc_B3AA
    ldy #$00
b14_loc_B3AA:
    dec party_scan2
    bne b14_loc_B3A0
    tay
    lda #$03
    sta cursor_blink
    lda $6300,y
    and #$EF
    sta $6300,y
    tya
    bne b14_loc_B3C2
b14_loc_B3BE:
    inc ppu_update_ptr_hi
    lda ppu_update_len
b14_loc_B3C2:
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    inx
    cpx ppu_update_off
    bne b14_loc_B383
    ldx #$00
b14_loc_B3CC:
    ldy $0300,x                 ; Top 8x8 tiles for the four text lines.
    cpy #$08
    bcc b14_loc_B3E2
    lda $6300,y
    ora #$10
    sta $6300,y
    inx
    cpx #$05
    bne b14_loc_B3CC
    beq b14_loc_B3F5
b14_loc_B3E2:
    cpx #$00
    beq b14_loc_B3F5
    lda $0300,x                 ; Top 8x8 tiles for the four text lines.
    beq b14_loc_B3F5
    lda #$04
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    inx
    cpx #$05
    bne b14_loc_B3E2
b14_loc_B3F5:
    lda #$00
    sta party_scan
    lda #$03
    sta party_scan2
    rts

b14_data_B3FE:
    .incbin "build/assets/bank14_data.bin", $33FE, $0002

b14_data_B400:
    .incbin "build/assets/bank14_data.bin", $3400, $000E
; ----------------------------------------------------------------------
; b14_collect_region_officers
;   Officers of region $6026 (bit 4 of $6300) into $0310, or switch
;   game_submode to $4B/$4F.
;   called by: $B397
; ----------------------------------------------------------------------
b14_collect_region_officers:
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
    jmp b14_refill_present_troops
; ----------------------------------------------------------------------
; b14_init_party_loop
;   Loop over the seven party slots.
;   called by: $B487, $B5D3
; ----------------------------------------------------------------------
b14_init_party_loop:
    ldy #$06
b14_loc_B48F:
    jsr b14_calc_member_max_troops
    dey
    bpl b14_loc_B48F
    rts
; ----------------------------------------------------------------------
; b14_refill_present_troops
;   Current troops = maximum for each present party member.
; ----------------------------------------------------------------------
b14_refill_present_troops:
    ldx #$06
b14_loc_B498:
    lda $609C,x                 ; Party member state bits.
    bpl b14_loc_B4A1
    txa
    jsr b14_refill_member_troops
b14_loc_B4A1:
    dex
    bpl b14_loc_B498
    rts
; ----------------------------------------------------------------------
; b14_refill_member_troops
;   Member A's current troops $60D0 = maximum $6160.
;   called by: $8D07, $B49E
; ----------------------------------------------------------------------
b14_refill_member_troops:
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

b14_calc_member7_max_troops:
    .incbin "build/assets/bank14_data.bin", $34BB, $000A
; ----------------------------------------------------------------------
; b14_calc_member_max_troops
;   Member Y's maximum troops: fixed table value, or 100 grown per
;   party level by class factors.
;   called by: $B48F
; ----------------------------------------------------------------------
b14_calc_member_max_troops:
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
; b14_inline_fixed_max_troops
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 12): the member's fixed 16-bit maximum troops
;   from the table at $BED0.
; ----------------------------------------------------------------------
b14_inline_fixed_max_troops:
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
b14_loc_B518:
    inc ppu_update_len
    ldx #$04
b14_loc_B51C:
    lda b12_data_B582,x
    cmp ppu_update_len
    beq b14_loc_B528
    dex
    bpl b14_loc_B51C
    bmi b14_loc_B529
b14_loc_B528:
    iny
b14_loc_B529:
    lda ppu_update_len
    cmp $6073
    beq b14_loc_B555
    cmp #$32
    bcs b14_loc_B53F
    lda b14_data_B569,y
    sta ppu_addr_lo
    jsr mul16x16_shr8
    jmp b14_loc_B518
b14_loc_B53F:
    lda ptr0_lo
    clc
    adc #$D0
    sta ptr0_lo
    lda ptr0_hi
    adc #$07
    sta ptr0_hi
    lda ptr1_lo
    adc #$00
    sta ptr1_lo
    jmp b14_loc_B518
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
    .incbin "build/assets/bank14_data.bin", $3582, $0004
; ----------------------------------------------------------------------
; b14_check_level_up
;   Experience against the level table $B687: level-up messages,
;   troops, new tactics, tactic points.
;   called by: $A444
; ----------------------------------------------------------------------
b14_check_level_up:
    ldx $6073
    dex
    stx ptr0_lo
    lda #$00
    sta ptr0_hi
    lda #$03
    sta ppu_addr_hi
    jsr mul16_by_u8
    lda ptr0_lo
    clc
    adc #$87
    sta ppu_update_ptr_lo
    lda ptr0_hi
    adc #$B6
    sta ppu_update_ptr_hi
    ldy #$00
    lda ($F3),y
    sta ptr0_lo
    iny
    lda ($F3),y
    sta ptr0_hi
    iny
    lda ($F3),y
    sta ptr1_lo
    jsr sub24_inline_clamped    ; inline pointer/data follows the JSR

b14_data_B5B7:
    .incbin "build/assets/bank14_data.bin", $35B7, $0002
    php
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_B5BD:
    .incbin "build/assets/bank14_data.bin", $35BD, $0002
    plp
    bcs b14_loc_B5C3
    rts
b14_loc_B5C3:
    inc $6073
    jsr text_draw_char
    lda #$32
    jsr sound_queue_add
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B5D1:
    .dw b10_msg_index_042    ; text index $002A -> b10_msg_042
    jsr b14_init_party_loop
    ldy #$00
    sty $7C
b14_loc_B5DA:
    lda $6090,y                 ; Party member order (actor ids).
    sta text_actor
    tay
    asl a
    asl a
    tax
    lda $60A8,y                 ; Party member class/officer id.
    tay
    lda #$07
    jsr read_party_stat_byte
    bpl b14_loc_B60A
    lda $6160,x                 ; Party member derived stats.
    sta ptr0_lo
    lda $6161,x                 ; Party member derived stats.
    sta ptr0_hi
    lda $6162,x                 ; Party member derived stats.
    sta ptr1_lo
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_B600:
    .incbin "build/assets/bank14_data.bin", $3600, $0002
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B608:
    .dw b10_msg_index_043    ; text index $002B -> b10_msg_043
b14_loc_B60A:
    inc $7C
    ldy $7C
    cpy #$07
    bne b14_loc_B5DA
    ldx $6073
    lda b14_data_B884,x
    beq b14_loc_B674
    sta text_command
    ldy #$00
    sty party_scan
    sty party_scan2
b14_loc_B622:
    lda #$FF
    sta ptr1_lo
    ldx $6090,y                 ; Party member order (actor ids).
    bmi b14_loc_B63E
    jsr b14_build_member_tactic_list
    lda ptr1_lo
    bmi b14_loc_B63E
    stx text_actor
    inc party_scan
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B63C:
    .dw b10_msg_index_044    ; text index $002C -> b10_msg_044
b14_loc_B63E:
    inc party_scan2
    ldy party_scan2
    cpy #$07
    bne b14_loc_B622
    lda party_scan
    beq b14_loc_B674
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B64D:
    .dw b10_msg_index_045    ; text index $002D -> b10_msg_045
    lda #$00
    sta ptr0_hi
    sta ptr1_lo
    jsr read_input_state
    lda rng0
    and #$0F
    tax
    lda b14_data_B677,x
    sta ptr0_lo
    jsr add24_inline            ; inline pointer/data follows the JSR

b14_data_B665:
    .incbin "build/assets/bank14_data.bin", $3665, $0002
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b14_data_B66A:
    .incbin "build/assets/bank14_data.bin", $366A, $0002
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B672:
    .dw b10_msg_index_125    ; text index $007D -> b10_msg_125
b14_loc_B674:
    jmp b14_check_level_up

b14_data_B677:
    .incbin "build/assets/bank14_data.bin", $3677, $00AC

; ----------------------------------------------------------------------
; b14_text_call_tactic_name
;   Window CALL (tactic window $17, 6x; also $EA20): one tactic name
;   of the $65A0 list.
; ----------------------------------------------------------------------
b14_text_call_tactic_name:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_print_tactic_name
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 12): tactic name from $65A0 (two columns in
;   battle), draw_item_name.
; ----------------------------------------------------------------------
b14_inline_print_tactic_name:
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
    jsr battle_sp_owner_x6
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
; b14_build_member_tactic_list
;   Rebuild member X's 6-entry tactic list $65A0 + 6X from the
;   per-level tables.
;   called by: $B62B
; ----------------------------------------------------------------------
b14_build_member_tactic_list:
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
    ldy text_busy
    beq b14_loc_B7C7
    ldy $60A8,x                 ; Party member class/officer id.
    lda #$08
    jsr read_party_stat_byte
    bne b14_loc_B7D5
b14_loc_B7C7:
    lda $61A8,x                 ; Party member derived stats.
    cmp $619C,x                 ; Party member derived stats.
    bcs b14_loc_B7D2
    jmp b14_loc_B852
b14_loc_B7D2:
    lda $6073
b14_loc_B7D5:
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
    cmp ppu_update_ptr_lo
    bcs b14_loc_B81D
b14_loc_B801:
    ldx ppu_update_ptr_hi
    lda b14_data_B884,x
    ldx cursor_blink
    cpx #$07
    bcc b14_loc_B814
    ldx text_busy
    beq b14_loc_B814
    cmp #$1D
    bcs b14_loc_B81D
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
; b14_calc_strategist_tactic_pts
;   Find the strategist (state $C0) among members 0-6 and compute
;   tactic points, else $61FB = 0.
;   called by: $959E, $9D40
; ----------------------------------------------------------------------
b14_calc_strategist_tactic_pts:
    ldx #$06
b14_loc_B857:
    lda $609C,x                 ; Party member state bits.
    cmp #$C0
    beq b14_calc_tactic_points
    dex
    bpl b14_loc_B857
    bmi b14_loc_B87E
; ----------------------------------------------------------------------
; b14_calc_tactic_points
;   $61FB = member X's $61A8 x $61F8 / 256 - spent $61FE, clamped at
;   0.
;   called by: $8506
; ----------------------------------------------------------------------
b14_calc_tactic_points:
    lda #$00
    sta ptr0_hi
    sta ptr1_lo
    lda $61A8,x                 ; Party member derived stats.
    sta ptr0_lo
    lda $61F8                   ; Party calculation temporaries.
    sta ppu_addr_hi
    jsr mul16_by_u8
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
    .incbin "build/assets/bank14_data.bin", $38F4, $001F

; ----------------------------------------------------------------------
; b14_battle_exec_tactic
;   Tactic turn: effect animation, msg 124, S.P cost, success roll
;   (466/467), then damage, heal, status, dispel, kill or retreat.
; ----------------------------------------------------------------------
b14_battle_exec_tactic:
    ldx party_count
    ldy $6200,x                 ; Party battle flags.
    beq b14_loc_B951
    lda b14_data_BB40,y
    bne b14_loc_B951
    lda $6232                   ; Party battle flags.
    bne b14_loc_B951
    lda b14_data_BB5F,y
    beq b14_loc_B931
    bmi b14_loc_B931
    cpx #$05
    bcs b14_loc_B939
    bcc b14_loc_B935
b14_loc_B931:
    cpx #$05
    bcc b14_loc_B939
b14_loc_B935:
    lda #$00
    beq b14_loc_B93B
b14_loc_B939:
    lda #$05
b14_loc_B93B:
    sta $79
b14_loc_B93D:
    jsr battle_arg_slot_actor
    lda $609C,y                 ; Party member state bits.
    bmi b14_loc_B949
    inc $79
    bpl b14_loc_B93D
b14_loc_B949:
    sty text_target
    txa
    ldx party_count
    sta $61E4,x                 ; Party calculation temporaries.
b14_loc_B951:
    ldy party_count
    lda $6200,y                 ; Party battle flags.
    sta text_command
    tay
    lda b14_data_BB7E,y
    jsr battle_effect_setup
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B962:
    .dw b10_msg_index_124    ; text index $007C -> b10_msg_124
    jsr b14_battle_actor_step_forward
    ldy text_command
    ldx battle_flags
    bne b14_loc_B97C
    ldx $6232                   ; Party battle flags.
    bne b14_loc_B97C
    lda $61FE
    clc
    adc b14_data_BBDB,y
    sta $61FE
b14_loc_B97C:
    ldx battle_flags
    cpy #$19
    beq b14_loc_B991
    lda $6224,x                 ; Party battle flags.
    beq b14_loc_B991
    ldx party_count
    lda #$00
    sta $6200,x                 ; Party battle flags.
    jmp b14_battle_after_action
b14_loc_B991:
    ldy text_target
    lda $609C,y                 ; Party member state bits.
    bpl b14_loc_B9E5
    ldy text_command
    lda b14_data_BBFA,y
    bpl b14_loc_B9A2
    jmp b14_loc_BA25
b14_loc_B9A2:
    ldy text_target
    lda $61A8,y                 ; Party member derived stats.
    sta ppu_update_ptr_lo
    ldy text_actor
    lda $61A8,y                 ; Party member derived stats.
    sec
    sbc ppu_update_ptr_lo
    bcc b14_loc_B9C4
    ldy #$03
b14_loc_B9B5:
    cmp b14_data_BC19,y
    bcs b14_loc_B9BD
    dey
    bpl b14_loc_B9B5
b14_loc_B9BD:
    lda b14_data_BC1D,y
    sta ppu_update_ptr_lo
    bpl b14_loc_B9D8
b14_loc_B9C4:
    sec
    sbc #$01
    eor #$FF
    ldy #$03
b14_loc_B9CB:
    cmp b14_data_BC21,y
    bcs b14_loc_B9D3
    dey
    bpl b14_loc_B9CB
b14_loc_B9D3:
    lda b14_data_BC25,y
    sta ppu_update_ptr_lo
b14_loc_B9D8:
    jsr read_input_state
    lda rng1
    adc rng2
    and #$0F
    cmp ppu_update_ptr_lo
    bcc b14_loc_B9F2
b14_loc_B9E5:
    lda #$06
    jsr sound_queue_add
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_B9ED:
    .dw b10_msg_index_467    ; text index $01D3 -> b10_msg_467
    jmp b14_loc_A197
b14_loc_B9F2:
    ldy text_command
    cpy #$1A
    bne b14_loc_BA12
    lda rng0
    adc rng3
    ldy text_actor
    cmp $61A8,y                 ; Party member derived stats.
    bcs b14_loc_B9E5
    ldy text_target
    lda $60A8,y                 ; Party member class/officer id.
    ldy #$07
b14_loc_BA0A:
    cmp b14_data_BC5E,y
    beq b14_loc_B9E5
    dey
    bpl b14_loc_BA0A
b14_loc_BA12:
    lda #$04
    jsr sound_queue_add
    jsr text_print_inline       ; inline pointer/data follows the JSR

b14_data_BA1A:
    .dw b10_msg_index_466    ; text index $01D2 -> b10_msg_466
    ldy text_command
    cpy #$10
    bcs b14_loc_BA4A
    jmp b14_loc_A1A7
b14_loc_BA25:
    lda b14_data_B8B6,y
    cmp #$02
    bne b14_loc_BA4A
    lda b14_data_BC1E,y
    sta ptr0_lo
    lda b14_data_BC23,y
    sta ptr0_hi
    lda #$00
    sta ptr1_lo
    sta ppu_addr_hi
    jsr b14_battle_actor_max_ability
    sta ppu_addr_lo
    jsr mul16x16_shr8
    jsr b14_heal_target_troops
    jmp b14_battle_after_action
b14_loc_BA4A:
    cpy #$16
    bcs b14_loc_BA7C
    lda battle_flags
    eor #$01
    clc
    adc b14_data_BC23,y
    tax
    lda $6220,x                 ; Party battle flags.
    ora b14_data_BC2B,y
    sta $6220,x                 ; Party battle flags.
b14_loc_BA60:
    jsr b14_battle_print_tactic_effect
    lda text_command
    cmp #$1C
    beq b14_loc_BA6C
    jmp b14_battle_after_action
b14_loc_BA6C:
    ldx party_count
    lda #$00
    sta $6221                   ; Party battle flags.
    sta $61D0,x
    jsr b14_battle_open_msg_window
    jmp b14_battle_attack
b14_loc_BA7C:
    cpy #$19
    bne b14_loc_BA9E
    ldx battle_flags
    lda #$00
    sta $6222,x                 ; Party battle flags.
    sta $6224,x                 ; Party battle flags.
    sta $6226,x                 ; Party battle flags.
    sta $6228,x                 ; Party battle flags.
    sta $622A,x                 ; Party battle flags.
    sta $622C,x                 ; Party battle flags.
    sta $622E,x                 ; Party battle flags.
    sta $6230,x                 ; Party battle flags.
    beq b14_loc_BA60
b14_loc_BA9E:
    cpy #$1A
    bne b14_loc_BAC8
    ldy text_target
    lda #$00
    sta $609C,y                 ; Party member state bits.
    tya
    asl a
    asl a
    tax
    lda #$00
    sta $60D0,x                 ; Party member stats.
    sta $60D1,x                 ; Party member stats.
    jsr battle_sprite_frame
    jsr battle_draw_slot_troops
    ldx $79
    lda $0506,x                 ; Per-actor state flags.
    and #$7F
    sta $0506,x                 ; Per-actor state flags.
    jmp b14_loc_BA60
b14_loc_BAC8:
    cpy #$1D
    bcc b14_loc_BAFC
    jsr b14_battle_print_tactic_effect
    lda text_command
    cmp #$1E
    bne b14_battle_flee_to_field
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_tactic_retreat_home
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block for tactic $1E: bank 13 resets the location stack,
;   then the location reloads.
; ----------------------------------------------------------------------
b14_inline_tactic_retreat_home:
    jsr set_bank_13
    jsr b13_loc_9FAB            ; bank 13: b13_loc_9FAB
    jsr set_bank_14
    jsr load_game
    lda #$01
    sta game_mode
    jsr field_party_sprites_reset
    jsr return_inline_block

b14_data_BAEE:
    .incbin "build/assets/bank14_data.bin", $3AEE, $0002
; ----------------------------------------------------------------------
; b14_battle_flee_to_field
;   Leave the battle (b14_battle_return_to_field), refresh, reset the
;   stack, game_mode_switch.
; ----------------------------------------------------------------------
b14_battle_flee_to_field:
    jsr b14_battle_return_to_field; bank 14: b14_battle_return_to_field
    jsr screen_refresh
    ldx #$30
    txs
    jmp game_mode_switch
b14_loc_BAFC:
    cpy #$18
    beq b14_loc_BB04
    cpy #$1B
    bcc b14_loc_BB25
b14_loc_BB04:
    lda battle_flags
    eor #$01
    clc
    adc b14_data_BC3F,y
    tax
    ldy party_count
    lda text_command
    cmp #$1C
    beq b14_loc_BB19
    lda $61E4,y                 ; Party calculation temporaries.
    tay
b14_loc_BB19:
    lda $622C,x                 ; Party battle flags.
    ora b14_data_BC43,y
    sta $622C,x                 ; Party battle flags.
    jmp b14_loc_BA60
b14_loc_BB25:
    lda battle_flags
    eor #$01
    clc
    adc b14_data_BC46,y
    tax
    ldy party_count
    lda $61E4,y                 ; Party calculation temporaries.
    tay
    lda $6228,x                 ; Party battle flags.
    ora b14_data_BC43,y
    sta $6228,x                 ; Party battle flags.
    jmp b14_loc_BA60

b14_data_BB40:
    .incbin "build/assets/bank14_data.bin", $3B40, $001F

b14_data_BB5F:
    .incbin "build/assets/bank14_data.bin", $3B5F, $001F

b14_data_BB7E:
    .incbin "build/assets/bank14_data.bin", $3B7E, $001F

b14_data_BB9D:
    .incbin "build/assets/bank14_data.bin", $3B9D, $001F

b14_data_BBBC:
    .incbin "build/assets/bank14_data.bin", $3BBC, $001F

b14_data_BBDB:
    .incbin "build/assets/bank14_data.bin", $3BDB, $001F

b14_data_BBFA:
    .incbin "build/assets/bank14_data.bin", $3BFA, $0006

b14_data_BC00:
    .incbin "build/assets/bank14_data.bin", $3C00, $0019

b14_data_BC19:
    .incbin "build/assets/bank14_data.bin", $3C19, $0004

b14_data_BC1D:
    .incbin "build/assets/bank14_data.bin", $3C1D, $0001

b14_data_BC1E:
    .incbin "build/assets/bank14_data.bin", $3C1E, $0003

b14_data_BC21:
    .incbin "build/assets/bank14_data.bin", $3C21, $0002

b14_data_BC23:
    .incbin "build/assets/bank14_data.bin", $3C23, $0002

b14_data_BC25:
    .incbin "build/assets/bank14_data.bin", $3C25, $0006

b14_data_BC2B:
    .incbin "build/assets/bank14_data.bin", $3C2B, $0014

b14_data_BC3F:
    .incbin "build/assets/bank14_data.bin", $3C3F, $0004

b14_data_BC43:
    .incbin "build/assets/bank14_data.bin", $3C43, $0003

b14_data_BC46:
    .incbin "build/assets/bank14_data.bin", $3C46, $0007

b14_data_BC4D:
    .incbin "build/assets/bank14_data.bin", $3C4D, $0011

b14_data_BC5E:
    .incbin "build/assets/bank14_data.bin", $3C5E, $0008

; ----------------------------------------------------------------------
; b14_battle_print_tactic_effect
;   Tactic effect message $0320 + 2 x (text_command - $10) + side (b11
;   288-317).
;   called by: $BA60, $BACC
; ----------------------------------------------------------------------
b14_battle_print_tactic_effect:
    lda text_command
    sec
    sbc #$10
    asl a
    adc battle_flags
    adc #$20
    sta ppu_addr_lo
    lda #$03
    sta ppu_addr_hi
    jmp text_show_message
; ----------------------------------------------------------------------
; b14_field_enter_location
;   Entrance check (called from $F2A0).
; ----------------------------------------------------------------------
b14_field_enter_location:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_find_entrance
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 7): scan the entrance records for the current
;   map and position.
; ----------------------------------------------------------------------
b14_inline_find_entrance:
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
    .incbin "build/assets/bank14_data.bin", $3CD0, $0002
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
    .incbin "build/assets/bank14_data.bin", $3D60, $0002
; ----------------------------------------------------------------------
; b14_field_enter_location_done
;   After an entrance match: door sound, window 5, init_party_status,
;   then the area change.
; ----------------------------------------------------------------------
b14_field_enter_location_done:
    lda #$FF
    jsr sound_queue_add_once
    lda #$10
    jsr sound_queue_add
    ldy #$05
    jsr draw_window
    jsr init_party_status
    jmp b14_field_area_change_tail
; ----------------------------------------------------------------------
; b14_field_transfer_or_exit
;   Transfer / exit check (called from $F2AA).
; ----------------------------------------------------------------------
b14_field_transfer_or_exit:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_find_transfer
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 7): scan the transfer records for an exact
;   position match.
; ----------------------------------------------------------------------
b14_inline_find_transfer:
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
    .incbin "build/assets/bank14_data.bin", $3DA7, $0002
b14_loc_BDA9:
    ldx party_index
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
    rol a
    rol a
    rol a
    rol a
    sta game_mode
    jsr return_inline_block

b14_data_BDDD:
    .incbin "build/assets/bank14_data.bin", $3DDD, $0002
; ----------------------------------------------------------------------
; b14_field_transfer_done
;   After a transfer match: redraw, reload the area screen and music,
;   back to the field loop.
; ----------------------------------------------------------------------
b14_field_transfer_done:
    lda $90
    and #$10
    beq b14_loc_BE0A
    ldx #$0C
b14_loc_BDE7:
    lda $0503,x                 ; Per-actor state flags.
    ora #$10
    sta $0503,x                 ; Per-actor state flags.
    dex
    bpl b14_loc_BDE7
    jsr loc_C0E2
    jsr field_party_sprites_reset
    jsr sub_CE2D
    ldx #$0C
b14_loc_BDFD:
    lda $0503,x                 ; Per-actor state flags.
    and #$EF
    sta $0503,x                 ; Per-actor state flags.
    dex
    bpl b14_loc_BDFD
    bmi b14_loc_BE1C
b14_loc_BE0A:
    ldy #$05
    jsr draw_window
    lda $90
    bpl b14_loc_BE19
    jsr field_party_sprites_reset
    jmp b14_loc_BE1C
b14_loc_BE19:
    jsr init_party_status
b14_loc_BE1C:
    lda #$00
    sta $86
    lda #$01
    sta $91
    jsr b14_field_get_area_tileset
    jsr b14_field_load_area_and_music
    pla
    pla
    jmp loc_F3EF
; ----------------------------------------------------------------------
; b14_field_exit_to_prev_location
;   No match: pop the location stack, per-location exit tweaks, then
;   the area change.
; ----------------------------------------------------------------------
b14_field_exit_to_prev_location:
    lda #$FF
    sta $86
    jsr sound_queue_add_once
    lda #$10
    jsr sound_queue_add
    ldy #$05
    jsr draw_window
    ldx party_index
    lda $6700,x
    ora #$04
    sta $6700,x
    lda #$01
    sta game_mode
    lda $6011
    dec $6011
    asl a
    asl a
    tax
    ldy #$00
    sta $90
b14_loc_BE5B:
    lda $6016,x
    sta text_x,y
    inx
    iny
    cpy #$04
    bne b14_loc_BE5B
    ldy party_index
    cpy #$69
    bne b14_loc_BE85
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b14_inline_exit_69_flag_check
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
;   Inline block (bank 13): location $69 exit adjustment.
; ----------------------------------------------------------------------
b14_inline_exit_69_flag_check:
    jsr set_bank_13
    lda #$08
    jsr b13_expand_name_tile    ; bank 13: b13_expand_name_tile
    php
    jsr return_inline_block

b14_data_BE7C:
    .incbin "build/assets/bank14_data.bin", $3E7C, $0002
    plp
    bcs b14_loc_BE85
    inc text_x
    bne b14_loc_BEE6
b14_loc_BE85:
    cpy #$20
    bne b14_loc_BE99
    lda $6010
    cmp #$02
    bcc b14_loc_BE95
    lda $6506
    bne b14_loc_BEE8
b14_loc_BE95:
    dec text_x
    bne b14_loc_BEE6
b14_loc_BE99:
    lda $6010
    cmp #$03
    bcs b14_loc_BEB1
    cpy #$6F
    beq b14_loc_BEAD
    cpy #$21
    bne b14_loc_BEB1
    lda $650A
    bne b14_loc_BEB1
b14_loc_BEAD:
    inc text_x
    bne b14_loc_BEE6
b14_loc_BEB1:
    cpy #$28
    bne b14_loc_BEBE
    lda $6516
    bne b14_loc_BEBE
    inc text_x
    bne b14_loc_BEE6
b14_loc_BEBE:
    cpy #$64
    bne b14_loc_BECB
    lda $651B
    bne b14_loc_BECB
    dec text_x
    bne b14_loc_BEE6
b14_loc_BECB:
    cpy #$33
    bne b14_loc_BED9
    lda $6733
    lsr a
    bcs b14_loc_BED9
    inc text_x2
    bne b14_loc_BEE6
b14_loc_BED9:
    cpy #$5F
    bne b14_loc_BEE8
    lda $6552
    and #$04
    bne b14_loc_BEE8
    dec text_x
b14_loc_BEE6:
    inc $86
b14_loc_BEE8:
    ldx $6011
    lda $6012,x
    sta party_index
    jsr field_party_sprites_reset
; ----------------------------------------------------------------------
; b14_field_area_change_tail
;   $91 = 1, b14_field_change_area, drop the caller's frame, resume
;   the field loop.
; ----------------------------------------------------------------------
b14_field_area_change_tail:
    lda #$01
    sta $91
    jsr b14_field_change_area
    pla
    pla
    jmp loc_F3EF
; ----------------------------------------------------------------------
; b14_field_change_area
;   Area tileset lookup, screen load and music.
;   called by: $8C48, $BEF7
; ----------------------------------------------------------------------
b14_field_change_area:
    jsr b14_field_get_area_tileset
; ----------------------------------------------------------------------
; b14_field_load_area_and_music
;   Load the area screen and start its music.
;   called by: $BE27
; ----------------------------------------------------------------------
b14_field_load_area_and_music:
    jsr b14_field_load_area_screen
    jsr b14_field_play_area_music
    rts
; ----------------------------------------------------------------------
; b14_field_load_area_screen
;   Party facing and scroll, map render, area CHR and palette, fade.
;   called by: $BF02
; ----------------------------------------------------------------------
b14_field_load_area_screen:
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
; b14_field_get_area_tileset
;   level = tileset nibble from $BF98; class_index 0/1/2 by tileset.
;   called by: $BE24, $BEFF
; ----------------------------------------------------------------------
b14_field_get_area_tileset:
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
; b14_field_play_area_music
;   Pick and queue the area music.
;   called by: $BF05
; ----------------------------------------------------------------------
b14_field_play_area_music:
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

.ifdef KANJI_TARGET
b14_data_BF98:
    .incbin "build/assets/bank14_data.bin", $3F98, $0040
    ; $BFD8-$BFFF held the MMC1 reset stub and vectors, dead in the MMC3
    ; kanji target (bank 14 is only ever mapped at $8000): step B helpers.
; b14_k_gauge_colour: the gauge colour A to P2 colours 2 and 3 (decision 6).
b14_k_gauge_colour:
    sta $03EA
    sta $03EB
    sta vram_dma_pending
    rts
; b14_k_fade_in: screen_fade_in (rendering off, busy), then UIF_BSTART:
; the battle screen's 15 fixed command kanji (plane 0 of groups 8-22),
; its slot table and hooks (UI bank, ui_battle.asm).
b14_k_fade_in:
    jsr screen_fade_in
    ldx #UIF_BSTART
    jmp CALL_UI
; b14_k_battle_start: the battle start's block write of tiles $00-$0F
; (battle_intro_screen_body) is not mirrored to the band page; pal_copy
; clears the flag.
b14_k_battle_start:
    lda #1
    sta UI_NOMIR
    jmp find_party_member
; b14_k_setup: UIF_BSETUP (busy mode while the screen is off; bank 15's
; slot loop calls UIF_BSETUP_END at its end), then battle_setup_slots.
b14_k_setup:
    ldx #UIF_BSETUP
    jsr CALL_UI
    jmp battle_setup_slots
    .pad $C000
b14_data_BFD9 = $BFD9           ; (bank 15's MMC1 register writes name it)
.else
b14_data_BF98:
    .incbin "build/assets/bank14_data.bin", $3F98, $0041

b14_data_BFD9:
    .incbin "build/assets/bank14_data.bin", $3FD9, $0027
.endif

