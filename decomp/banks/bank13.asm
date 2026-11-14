; ======================================================================
; PRG bank 13  CPU $8000-$BFFF
; ======================================================================
; traced code: 1229 instructions / 2663 bytes; CDL code bytes: 1778
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$87FF  b13_data_tables: Data tables at the start of bank 13.
;   $8800-$900F  b13_code_status: Officer status/name-entry code.
;   $9010-$9C0F  b13_data: Bank 13 data region.
;   $9C10-$A074  b13_code_name: Additional status/name-entry code.
;   $A075-$B70F  b13_code_aux: Auxiliary gameplay/menu code.
;   $B710-$BEA7  b13_dictionary: Frequent-word/dictionary table.
;   $BEA8-$BFFF  b13_data_tail: Bank 13 data tail.
; ======================================================================

; Save records.  The kanji target keeps two (map-canvas step 2): the
; third record's 2 KiB of battery RAM ($7800-$7FFF) holds map engine RAM.
.ifdef KANJI_TARGET
SAVE_SLOTS = 2
.else
SAVE_SLOTS = 3
.endif

; Overlapping data aliases (tables referenced inside instructions)
b13_data_A0E1 = $A0E1

; Region aliases
b13_code_status = $8800
b13_code_aux = $A075


b13_data_tables:
; editable source: assets/data/bank13.bin (bin)
    .incbin "build/assets/bank13_data.bin", $0000, $0400

b13_data_8400:
    .incbin "build/assets/bank13_data.bin", $0400, $0400

; ----------------------------------------------------------------------
; b13_load_status_screen
;   Load the officer status screen and its graphics.
; ----------------------------------------------------------------------
b13_load_status_screen:
    jsr ppu_init
    lda #$00
    sta $7C
    ldx #$03
    ldy #$05
    jsr fill_ram_block
    lda #$24
    ldx #$0A
    ldy #$00
    jsr set_ppu_scroll
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b13_inline_881A
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b13_inline_881A:
    lda #$02
    jsr set_bank_b
    lda #$00
    ldx #$80
    ldy #$18
    jsr copy_to_vram            ; inline pointer/data follows the JSR

b13_data_8828:
    .incbin "build/assets/bank13_data.bin", $0828, $0002
.ifdef KANJI_TARGET
    ; The title in kanji (tools/asm/attract.asm, 2026-11-14): its own tile
    ; set and nametable from bank ATT_BANK in place of the letters and the
    ; font (b13_k_restore puts those back when Start leaves the title).
    lda #ATT_BANK
    jsr set_bank_b
    jsr ATT_TITLE_SET
    nop
    nop
    nop
    nop
    nop
    nop
.else
    lda #$04
    ldx #$20
    ldy #$1E
    jsr copy_to_vram            ; inline pointer/data follows the JSR

b13_data_8833:
    .incbin "build/assets/bank13_data.bin", $0833, $0002
    jsr load_battle_palette
.endif
    jsr return_inline_block

b13_data_883B:
    .incbin "build/assets/bank13_data.bin", $083B, $0002
    jsr draw_string             ; inline pointer/data follows the JSR

b13_data_8840:
.ifdef KANJI_TARGET
    .dw ATT_TITLE_ATTR          ; (the block's attribute records: ATT_TITLE_SET drew the rest)
.else
    .incbin "build/assets/bank13_data.bin", $0840, $0002
.endif
    jsr wait_vblank
    lda #$09
    sta text_graphics_index
    lda #$FE
    sta $A5
    jsr load_text_graphics
    lda #$22
    jsr sound_queue_add
    jsr ppu_nmi_on
    jsr wait_vblank
    lda #$3D
    sta $00
    lda #$0A
    sta $02
    lda #$1F
    sta $04
    lda #$80
    sta nmi_mode
    jsr b13_load_officer_palette; bank 02 target
    jsr loc_C139
b13_loc_8871:
    ldx #$04
b13_loc_8873:
    lda controller_state
    and #$10
    beq b13_loc_8882
    jsr load_text_graphics
    lda #$00
    sta nmi_mode
    beq b13_loc_88AA
b13_loc_8882:
    jsr wait_vblank
    dex
    bne b13_loc_8873
    dec $04
    jsr b13_load_officer_palette
    lda $04
    bpl b13_loc_8871
    lda #$00
    sta nmi_mode
    lda #$0E
    sta $A5
    ldy #$0A
    jsr draw_text_window_small
    jsr load_text_graphics
    lda #$01
    sta $A5
    ldy #$0A
    jsr draw_text_window_small
b13_loc_88AA:
    lda #$21
    sta party_scan
    ldx #$3C
b13_loc_88B0:
    dex
    bne b13_loc_88BC
    ldx #$3C
    dec party_scan
    bne b13_loc_88BC
    jmp enter_party_screen
b13_loc_88BC:
    jsr wait_vblank
    lda controller_state
    and #$10
    beq b13_loc_88B0
    lda #$20
    jsr sound_queue_add_once
    jsr ppu_init
.ifdef KANJI_TARGET
    jmp b13_k_restore           ; (the font and the letters back first)
.else
    jmp b13_loc_8A23
.endif
; ----------------------------------------------------------------------
; b13_load_officer_palette
;   Load the palette for the current officer.
;   called by: $886B, $888A
; ----------------------------------------------------------------------
b13_load_officer_palette:
    lda $04
    asl a
    adc $04
    tax
    lda b13_data_89C3,x
    lsr a
    lsr a
    lsr a
    lsr a
    sta $6400
    lda b13_data_89C3,x
    and #$0F
    sta $6401
    lda b13_data_89C4,x
    lsr a
    lsr a
    lsr a
    lsr a
    sta $6402
    lda b13_data_89C4,x
    and #$0F
    sta $6403
    lda b13_data_89C5,x
    lsr a
    lsr a
    lsr a
    lsr a
    sta $6404
    rts

b13_data_8905:
    .incbin "build/assets/bank13_data.bin", $0905, $00BE

b13_data_89C3:
    .incbin "build/assets/bank13_data.bin", $09C3, $0001

b13_data_89C4:
    .incbin "build/assets/bank13_data.bin", $09C4, $0001

b13_data_89C5:
    .incbin "build/assets/bank13_data.bin", $09C5, $005E

b13_loc_8A23:
    lda #$00
    sta text_graphics_index
    jsr load_text_graphics
    jsr wait_vblank
    lda #$08
    sta text_graphics_index
    jsr load_text_graphics
.ifdef KANJI_TARGET
    jsr b13_k_set               ; (then the boot screens' fixed set, once)
.else
    jsr wait_vblank
.endif
    ldx #$00
    stx text_palette
    stx $0D
    stx $0E
    lda #$FF
    sta $6090                   ; Party member order (actor ids).
    sta $6091                   ; Party member order (actor ids).
    sta $6092                   ; Party member order (actor ids).
    sta $6093                   ; Party member order (actor ids).
b13_loc_8A4D:
    sta $60A8,x                 ; Party member class/officer id.
    inx
    cpx #$08
    bne b13_loc_8A4D
b13_loc_8A55:
    jsr ppu_init
    jsr loc_C139
    jsr b13_init_name_entry
    ldy #$08
    lda ($10),y
    cmp #$35
    bne b13_loc_8A9B
    iny
    lda ($10),y
    cmp #$53
    bne b13_loc_8A9B
    jsr b13_copy_name_tiles
    ldy #$06
    lda ($10),y
    cmp ppu_update_ptr_lo
    bne b13_loc_8A7F
    iny
    lda ($10),y
    cmp ppu_update_ptr_hi
    beq b13_loc_8A9B
b13_loc_8A7F:
    ldy #$08
    lda #$00
    sta ($10),y
    iny
    sta ($10),y
.ifdef KANJI_TARGET
    jmp b13_k_check             ; (the boot screens' fixed set first)
    nop
b13_k_check_ret:
.else
    lda #$84
    sta input_buttons
.endif
    ldx #$1E
    jsr text_init
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_8A94:
    .dw b11_msg_index_145    ; text index $0291 -> b11_msg_145
    ldx #$30
    jsr wait_frames
b13_loc_8A9B:
    inc text_palette
    lda text_palette
    cmp #SAVE_SLOTS
    bne b13_loc_8A55
b13_loc_8AA3:
    lda #SAVE_SLOTS-1
    sta text_palette
    lda #$00
    sta $0F
b13_loc_8AAB:
    jsr b13_init_name_entry
    ldy #$08
    lda ($10),y
    cmp #$35
    bne b13_loc_8AC0
    iny
    lda ($10),y
    cmp #$53
    bne b13_loc_8AC0
    sec
    bcs b13_loc_8AC1
b13_loc_8AC0:
    clc
b13_loc_8AC1:
    rol $0F
    dec text_palette
    bpl b13_loc_8AAB
    jsr ppu_init
.ifdef KANJI_TARGET
    jsr TXR_MENU                ; the boot menus in kanji (the renderer's pages)
.else
    jsr loc_C139
.endif
    lda $0F
    sta ppu_update_off
    ldx #$00
    ldy #$04
    stx ppu_update_len
b13_loc_8AD7:
    lda ppu_update_len
    cmp #SAVE_SLOTS
    beq b13_loc_8AF1
    lsr ppu_update_off
    bcc b13_loc_8AE8
    sta $60A8,x                 ; Party member class/officer id.
    inx
    jmp b13_loc_8AEC
b13_loc_8AE8:
    sta $60A8,y                 ; Party member class/officer id.
    iny
b13_loc_8AEC:
    inc ppu_update_len
    jmp b13_loc_8AD7
b13_loc_8AF1:
    lda #$FF
    sta $60A8,x                 ; Party member class/officer id.
    sta $60A8,y                 ; Party member class/officer id.
    lda $0F
    bne b13_loc_8B04
    ldy #$01
    sty $6090                   ; Party member order (actor ids).
    bne b13_loc_8B1F
b13_loc_8B04:
    cmp #(1 << SAVE_SLOTS) - 1   ; every record in use: no new game
    bne b13_loc_8B14
    lda #$00
    sta $6090                   ; Party member order (actor ids).
    ldy #$02
    sty $6091                   ; Party member order (actor ids).
    bne b13_loc_8B1F
b13_loc_8B14:
    ldy #$00
b13_loc_8B16:
    tya
    sta $6090,y                 ; Party member order (actor ids).
    iny
    cpy #$04
    bne b13_loc_8B16
b13_loc_8B1F:
    lda #$FF
    sta $6090,y                 ; Party member order (actor ids).
    lda #$80
    sta input_buttons
    ldx #$27
    jsr text_init
    jsr text_wait_loop
    jsr wait_vblank
    ldx text_menu_index
    lda $6090,x                 ; Party member order (actor ids).
    jsr dispatch_return_table

b13_data_8B3B:
    .incbin "build/assets/bank13_data.bin", $0B3B, $0008
b13_loc_8B43:
    jsr wait_vblank
    jsr ppu_init
.ifdef KANJI_TARGET
    jsr TXR_MENU                ; the boot menus in kanji (the renderer's pages)
.else
    jsr loc_C139
.endif
    lda #$84
    sta input_buttons
    ldx #$1E
    jsr text_init
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_8B58:
    .dw b11_msg_index_146    ; text index $0292 -> b11_msg_146
    ldx #$28
    jsr text_init
    jsr text_wait_loop
    bcc b13_loc_8B6A
    jsr wait_vblank
    jmp b13_loc_8AA3
b13_loc_8B6A:
    ldx text_menu_index
    lda $60A8,x                 ; Party member class/officer id.
    sta text_palette
.ifdef KANJI_TARGET
    jmp b13_k_speed             ; (文字の速さを決めてください first)
    nop
    nop
b13_k_speed_ret:
.else
    ldx #$29
    jsr text_init
.endif
    lda #$01
    sta text_menu_index
    jsr loc_CDB6
    bcs b13_loc_8B43
    lda text_menu_index
    beq b13_loc_8B8D
    cmp #$01
    bne b13_loc_8B8B
    lda #$02
    bne b13_loc_8B8D
b13_loc_8B8B:
    lda #$04
b13_loc_8B8D:
    sta text_speed
    jsr wait_vblank
    jsr ppu_init
    jsr b13_init_name_entry
    jsr b13_copy_name_tiles
    ldy #$73
    lda ($10),y
    bne b13_loc_8BA4
    jmp b13_loc_8CEF
b13_loc_8BA4:
    lda #$00
    sta $00
    lda #$60
    sta $01
    lda #$00
    sta ppu_update_len
b13_loc_8BB0:
    ldy #$00
b13_loc_8BB2:
    lda ($10),y
    sta ($00),y
    iny
    bne b13_loc_8BB2
    inc ptr0_hi
    inc $01
    inc ppu_update_len
    lda ppu_update_len
    cmp #$08
    bne b13_loc_8BB0
    jmp b13_loc_9FAB
    jsr ppu_init
.ifdef KANJI_TARGET
    jsr TXR_MENU                ; the boot menus in kanji (the renderer's pages)
.else
    jsr loc_C139
.endif
    lda #$84
    sta input_buttons
    ldx #$1E
    jsr text_init
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_8BDA:
    .dw b11_msg_index_148    ; text index $0294 -> b11_msg_148
    lda #$80
    sta input_buttons
    ldx #$2B
    jsr text_init
    jsr text_wait_loop
    bcc b13_loc_8BF0
    jsr wait_vblank
    jmp b13_loc_8AA3
b13_loc_8BF0:
    jsr ppu_init
.ifdef KANJI_TARGET
    jsr TXR_MENU                ; (the name entry: the boot screens' fixed kanji set)
.else
    jsr loc_C139
.endif
    ldx text_menu_index
    lda $60AC,x                 ; Party member class/officer id.
    sta text_palette
    tay
b13_loc_8BFE:
    ror $0F
    dey
    bpl b13_loc_8BFE
    ldy text_palette
    sec
b13_loc_8C06:
    rol $0F
    dey
    bpl b13_loc_8C06
    lda #$00
    ldx #$60
    ldy #$67
    jsr fill_ram_block
    jsr b13_officer_status_menu
    jsr b13_name_entry_screen
    jsr ppu_init
    jsr loc_C139
    jmp b13_loc_8AA3
b13_loc_8C23:
    jsr wait_vblank
    jsr ppu_init
.ifdef KANJI_TARGET
    jsr TXR_MENU                ; the boot menus in kanji (the renderer's pages)
.else
    jsr loc_C139
.endif
    lda #$84
    sta input_buttons
    ldx #$1E
    jsr text_init
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_8C38:
    .dw b11_msg_index_149    ; text index $0295 -> b11_msg_149
    ldx #$28
    jsr text_init
    jsr text_wait_loop
    bcc b13_loc_8C4A
    jsr wait_vblank
    jmp b13_loc_8AA3
b13_loc_8C4A:
    ldx text_menu_index
    lda $60A8,x                 ; Party member class/officer id.
    sta text_palette
    lda #$84
    sta input_buttons
    ldx #$1E
    jsr text_init
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_8C5D:
    .dw b11_msg_index_150    ; text index $0296 -> b11_msg_150
    ldx #$2A
    jsr text_init
    jsr text_wait_ask
    bcs b13_loc_8C23
    jsr b13_init_name_entry
    ldy #$08
    lda #$00
    sta ($10),y
    iny
    sta ($10),y
    jsr wait_vblank
    jmp b13_loc_8AA3

b13_data_8C7B:
.ifdef KANJI_TARGET
    .incbin "build/assets/bank13_data.bin", $0C7B, $0006
    jsr TXR_MENU                ; ($8C81, copying: the boot menus in kanji)
    .incbin "build/assets/bank13_data.bin", $0C84, $006B
.else
    .incbin "build/assets/bank13_data.bin", $0C7B, $0074
.endif

b13_loc_8CEF:
    jmp b13_loc_9587
; ----------------------------------------------------------------------
; b13_copy_name_tiles
;   Copy/decompress the 16x16 name tiles.
;   called by: $8A6D, $8B98
; ----------------------------------------------------------------------
b13_copy_name_tiles:
    lda #$00
    sta ppu_update_ptr_lo
    sta ppu_update_ptr_hi
    ldy #$08
    sty ppu_update_off
b13_loc_8CFC:
    lda ($10),y
    sta ($00),y
    clc
    adc ppu_update_ptr_lo
    sta ppu_update_ptr_lo
    lda ppu_update_ptr_hi
    adc #$00
    sta ppu_update_ptr_hi
    iny
    bne b13_loc_8CFC
    inc $01
    inc ptr0_hi
    dec ppu_update_off
    bne b13_loc_8CFC
    lda ptr0_hi
    sec
    sbc #$08
    sta ptr0_hi
    rts

b13_data_8D1E:
.ifdef KANJI_TARGET
    ; $8D20-$8FFF is the ROM's filler (never read): the name-entry title in
    ; kanji, a draw_string block generated by kanji_build.py.
    .incbin "build/assets/bank13_data.bin", $0D1E, $0002
    .include "build/kanji/boot_title.inc"
; Start on the title (2026-11-14): the title showed its own tile set (bank
; ATT_BANK); the font and the letters back on the scene page as the
; original's title load wrote them, for the boot screens (attract.asm
; att_restore: a direct copy, not the block writer's mirror, which the
; title's att_title_set did for the band page).
b13_k_restore:
    jsr call_inline_block
    lda #ATT_BANK
    jsr set_bank_b
    jsr ATT_RESTORE
    jsr return_inline_block
    .dw b13_loc_8A23-1
; The boot entry (2026-11-14): the boot screens' fixed set into CHR, once,
; after graphics set 8 (which writes those tiles).  Nothing writes them
; again while the boot screens last; each screen's TXR_MENU sets the flags.
b13_k_set:
    jsr wait_vblank
    ldx #TXF_MENUSET
    jmp TXR_CALL
; A damaged record (2026-11-14, the user's "no band in the whole boot
; menu"): the record check's flags (TXR_ON = $40) before b11_msg_145
; (残念ですが…消えています), so its kanji are the set's tiles.
b13_k_check:
    ldx #TXF_MENU
    jsr TXR_CALL
    lda #$84
    sta input_buttons
    jmp b13_k_check_ret
; Starting a history book (2026-11-14, the user's fix of the original's
; oversight): b11_msg_147 (文字の速さを決めてください), which nothing printed,
; before the speed window.  Cancelling the speed window goes back to the
; start screen as before ($8B43: the book list and b11_msg_146 again).
b13_k_speed:
    lda #$84
    sta input_buttons
    ldx #$1E
    jsr text_init
    jsr text_print_inline       ; inline pointer/data follows the JSR
    .dw b11_msg_index_147    ; text index $0293 -> b11_msg_147
    ldx #$29
    jsr text_init
    jmp b13_k_speed_ret
; The opening oath (2026-11-14, the user's fixed split): after the
; portraits (rendering off) its kanji go into CHR $3800 and TXR_ON =
; TXR_SPLIT: R1 shows them below line SPLIT_LINE, b10_msg_128 puts them as
; fixed tiles; no band, no uploads.
b13_k_oath:
    ldx #TXF_OATH
    jsr TXR_CALL
    jmp wait_vblank
; Its end (the NMI off): rendering off as the original, then the split off.
b13_k_oathend:
    jsr ppu_bg_sprites_off
    ldx #TXF_OATHEND
    jmp TXR_CALL
b13_k_end:
    .incbin "build/assets/bank13_data.bin", $0D20 + (b13_k_end - boot_title_block), $02E0 - (b13_k_end - boot_title_block)
.else
    .incbin "build/assets/bank13_data.bin", $0D1E, $02E2
.endif

b13_data_9000:
    .incbin "build/assets/bank13_data.bin", $1000, $0009

    ldy $54
    lda $6090,y                 ; Party member order (actor ids).
    asl a
    tay
b13_data:
    lda b13_data_90E9,y
    sta ptr0_lo
    lda b13_data_90EA,y
    sta ptr0_hi
    ldy #$00
b13_loc_901C:
    lda ($10),y
    cmp #$FF
    beq b13_loc_9029
    iny
.ifdef KANJI_TARGET
    jsr TXR_TP                  ; (the boot menu's lines in kanji)
.else
    jsr text_put_tile
.endif
    jmp b13_loc_901C
b13_loc_9029:
    lda text_col
    sec
    sbc #$04
    sta text_col
    ldy $54
    lda $6091,y                 ; Party member order (actor ids).
    bmi b13_loc_903B
    cpy #$04
    bne b13_loc_903F
b13_loc_903B:
    lda #$08
    sta text_col
b13_loc_903F:
    rts
    ldy $54
    lda $60A8,y                 ; Party member class/officer id.
    sta text_palette
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inc $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    jsr b13_init_name_entry
    lda #$0A
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    ldy #$0C
b13_loc_9059:
    lda ($10),y
    jsr text_put_tile
    iny
    cpy #$10
    bne b13_loc_9059
    lda #$0A
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    lda #$EB
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    lda #$00
    sta ppu_addr_lo
    sta ptr1_hi
    ldy #$73
    lda ($10),y
    sta ptr1_lo
    jsr read_inline_block_3     ; inline pointer/data follows the JSR

b13_data_907E:
    .incbin "build/assets/bank13_data.bin", $107E, $0002
    lda $0109
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    lda $010A
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    ldy $54
    lda $60A9,y                 ; Party member class/officer id.
    bmi b13_loc_909B
    lda text_col
    sec
    sbc #$04
    bne b13_loc_909D
b13_loc_909B:
    lda #$08
b13_loc_909D:
    sta text_col
    rts
    ldy $54
    lda $60AC,y                 ; Party member class/officer id.
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inc $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    lda #$05
    sta ppu_update_len
b13_loc_90B0:
    lda #$0A
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    dec ppu_update_len
    bne b13_loc_90B0
    lda $60AD,y                 ; Party member class/officer id.
    bmi b13_loc_90C7
    lda text_col
    sec
    sbc #$04
    jmp b13_loc_90C9
b13_loc_90C7:
    lda #$08
b13_loc_90C9:
    sta text_col
    rts

b13_data_90CC:
    .incbin "build/assets/bank13_data.bin", $10CC, $001D

b13_data_90E9:
    .incbin "build/assets/bank13_data.bin", $10E9, $0001

b13_data_90EA:
    .incbin "build/assets/bank13_data.bin", $10EA, $0030

; ----------------------------------------------------------------------
; b13_officer_status_menu
;   Officer status menu main loop.
;   called by: $8C14
; ----------------------------------------------------------------------
b13_officer_status_menu:
    lda #$81
    sta input_buttons
    ldx #$26
    jsr text_init
    jsr draw_string             ; inline pointer/data follows the JSR

b13_data_9126:
.ifdef KANJI_TARGET
    .dw boot_title_block            ; (the kanji title, $8D20)
.else
    .incbin "build/assets/bank13_data.bin", $1126, $0002
.endif
    jsr loc_C139
    jsr b13_init_name_entry
    lda #$0A
    ldy #$0C
b13_loc_9132:
    sta $6000,y
    iny
    cpy #$10
    bne b13_loc_9132
    lda #$00
    sta text_menu_index
    sta text_menu_sub
    sta cursor_blink
    sta copy_src_hi
    sta copy_dst_lo
b13_loc_9146:
    jsr b13_officer_status_input
    lda controller_state
    tax
    and #$10
    bne b13_officer_status_exit
    txa
    and #$C0
    beq b13_loc_916A
    lda #$0A
    jsr sound_queue_add
    jsr b13_draw_officer_portrait
    lda #$00
    sta cursor_blink
    jsr b13_queue_cursor_tile
    jsr b13_queue_name_tile2
    jsr b13_officer_status_draw
b13_loc_916A:
    jsr b13_queue_name_tile
    jsr wait_vblank
    jmp b13_loc_9146
; ----------------------------------------------------------------------
; b13_officer_status_exit
;   Exit the officer status menu.
; ----------------------------------------------------------------------
b13_officer_status_exit:
    jsr b13_queue_portrait_tile
    lda #$10
    sta copy_dst_lo
    jsr b13_queue_name_tile
    jsr ppu_init
    lda #$00
    sta text_menu_index
    sta text_menu_sub
    rts
; ----------------------------------------------------------------------
; b13_officer_status_input
;   Officer status input/cursor update.
;   called by: $9146
; ----------------------------------------------------------------------
b13_officer_status_input:
    lda controller_prev
    and #$0F
    beq b13_loc_9205
    tax
    lda text_scroll_pos
    clc
    adc #$10
    sta text_scroll_pos
    bne b13_loc_9209
    lda #$09
    jsr sound_queue_add
    txa
    pha
    jsr b13_draw_officer_portrait
    jsr b13_queue_portrait_tile
    pla
    tax
    and #$03
    beq b13_loc_91D6
    ldy text_menu_index
    eor #$03
    asl a
    sec
    sbc #$03
    clc
    adc text_menu_sub
    bmi b13_loc_91C7
    cmp #$0A
    bcs b13_loc_91C3
    cmp #$08
    bcc b13_loc_91D1
    cpy #$05
    bcc b13_loc_91D1
b13_loc_91C3:
    lda #$00
    beq b13_loc_91D1
b13_loc_91C7:
    cpy #$05
    bcc b13_loc_91CF
    lda #$07
    bne b13_loc_91D1
b13_loc_91CF:
    lda #$09
b13_loc_91D1:
    sta text_menu_sub
    jmp b13_loc_920F
b13_loc_91D6:
    txa
    ldy text_menu_sub
    and #$0C
    eor #$0C
    lsr a
    sec
    sbc #$03
    clc
    adc text_menu_index
    bmi b13_loc_91F6
    cmp #$0A
    bcs b13_loc_91F2
    cmp #$05
    bcc b13_loc_9200
    cpy #$08
    bcc b13_loc_9200
b13_loc_91F2:
    lda #$00
    beq b13_loc_9200
b13_loc_91F6:
    cpy #$08
    bcc b13_loc_91FE
    lda #$04
    bne b13_loc_9200
b13_loc_91FE:
    lda #$09
b13_loc_9200:
    sta text_menu_index
    jmp b13_loc_920F
b13_loc_9205:
    lda #$F0
    sta text_scroll_pos
b13_loc_9209:
    jsr b13_draw_officer_portrait
    jsr b13_queue_cursor_tile
b13_loc_920F:
    rts
; ----------------------------------------------------------------------
; b13_draw_officer_portrait
;   Draw the officer portrait.
;   called by: $915A, $919E, $9209, $92C8
; ----------------------------------------------------------------------
b13_draw_officer_portrait:
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b13_inline_9213
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b13_inline_9213:
    lda #$0E
    jsr set_bank_b
    lda text_menu_index
    sta ptr0_lo
    lda #$00
    sta ptr0_hi
    sta $17
    sta copy_src_lo
    lda #$40
    sta ppu_addr_hi
    jsr mul16_by_u8
    lda text_menu_sub
    asl a
    sta $16
    jsr add24_inline            ; inline pointer/data follows the JSR

b13_data_9233:
    .incbin "build/assets/bank13_data.bin", $1233, $0002
    lda #$00
    sta ptr1_lo
    lda #$21
    sta ptr0_hi
    lda #$05
    sta ptr0_lo
    jsr add24_inline            ; inline pointer/data follows the JSR

b13_data_9244:
    .incbin "build/assets/bank13_data.bin", $1244, $0002
    jsr return_inline_block

b13_data_9249:
    .incbin "build/assets/bank13_data.bin", $1249, $0002
    rts
; ----------------------------------------------------------------------
; b13_queue_portrait_tile
;   Queue a portrait tile update.
;   called by: $9173, $91A1
; ----------------------------------------------------------------------
b13_queue_portrait_tile:
    lda #$00
    sta cursor_blink
    ldy #$0A
    bne b13_queue_tile
; ----------------------------------------------------------------------
; b13_queue_cursor_tile
;   Queue a cursor tile update.
;   called by: $9161, $920C
; ----------------------------------------------------------------------
b13_queue_cursor_tile:
    lda cursor_blink
    inc cursor_blink
    ldy #$0A
    and #$10
    bne b13_queue_tile
    ldy #$70
; ----------------------------------------------------------------------
; b13_queue_tile
;   Queue one tile update at the current PPU cursor.
;   called by: $9298
; ----------------------------------------------------------------------
b13_queue_tile:
    ldx vram_queue_write
    lda $17
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda $16
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$01
    sta $0400,x                 ; VRAM update command queue.
    inx
    tya
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    rts
; ----------------------------------------------------------------------
; b13_queue_name_tile
;   Queue a name tile update.
;   called by: $916A, $917A
; ----------------------------------------------------------------------
b13_queue_name_tile:
    lda copy_dst_lo
    inc copy_dst_lo
    ldy #$0A
    and #$10
    bne b13_loc_928D
; ----------------------------------------------------------------------
; b13_queue_name_tile2
;   Queue a name tile update (variant).
;   called by: $9164
; ----------------------------------------------------------------------
b13_queue_name_tile2:
    ldy #$79
b13_loc_928D:
    lda #$20
    sta $17
    lda copy_src_hi
    clc
    adc #$CE
    sta $16
    jsr b13_queue_tile
    rts
; ----------------------------------------------------------------------
; b13_officer_status_draw
;   Draw/update the officer status screen.
;   called by: $9167
; ----------------------------------------------------------------------
b13_officer_status_draw:
    ldx text_menu_index
    lda b13_data_934D,x
    sta copy_dst_hi
    lda b13_data_9357,x
    sta cursor_x
    ldy text_menu_sub
    lda ($1B),y
    cmp #$FD
    bne b13_loc_92B7
    lda copy_src_hi
    beq b13_loc_92B6
    dec copy_src_hi
b13_loc_92B6:
    rts
b13_loc_92B7:
    cmp #$FE
    bne b13_loc_92C4
    lda copy_src_hi
    cmp #$03
    beq b13_loc_9330
    inc copy_src_hi
    rts
b13_loc_92C4:
    cmp #$FF
    bne b13_loc_92D0
    jsr b13_draw_officer_portrait
    pla
    pla
    jmp b13_officer_status_exit
b13_loc_92D0:
    pha
    ldx vram_queue_write
    lda #$20
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda copy_src_hi
    tay
    clc
    adc #$AE
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$01
    sta $0400,x                 ; VRAM update command queue.
    inx
    pla
    sta $600C,y
    ldy #$0A
    pha
    asl a
    bcc b13_loc_9300
    ldy #$72
    cmp #$C4
    bcc b13_loc_9300
    pla
    sec
    sbc #$0A
    pha
    ldy #$73
b13_loc_9300:
    pla
    and #$7F
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$20
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda copy_src_hi
    clc
    adc #$8E
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$01
    sta $0400,x                 ; VRAM update command queue.
    inx
    tya
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    lda copy_src_hi
    cmp #$03
    beq b13_loc_9330
    inc copy_src_hi
b13_loc_9330:
    rts

b13_data_9331:
    .incbin "build/assets/bank13_data.bin", $1331, $001C

b13_data_934D:
    .incbin "build/assets/bank13_data.bin", $134D, $000A

b13_data_9357:
    .incbin "build/assets/bank13_data.bin", $1357, $00B9

b13_data_9410:
    .incbin "build/assets/bank13_data.bin", $1410, $0177

b13_loc_9587:
    lda #$80
    ldx #$63
    ldy #$63
    jsr fill_ram_block
    inc $7C
    ldy #$06
b13_loc_9594:
    lda b13_data_96F3,y
    sta $6090,y                 ; Party member order (actor ids).
    dey
    bpl b13_loc_9594
    ldy #$02
b13_loc_959F:
    lda b13_data_96FA,y
    sta $609C,y                 ; Party member state bits.
    dey
    bpl b13_loc_959F
    ldy #$02
b13_loc_95AA:
    lda b13_data_96FD,y
    sta $60A8,y                 ; Party member class/officer id.
    dey
    bpl b13_loc_95AA
    ldy #$10
b13_loc_95B5:
    lda b13_data_9700,y
    sta $6011,y
    dey
    bpl b13_loc_95B5
    ldy #$17
b13_loc_95C0:
    lda b13_data_9711,y
    sta $6100,y                 ; Party member stats.
    dey
    bpl b13_loc_95C0
    lda #$01
    sta $6010
    sta $6505
    sta $6528
    sta $6529
    sta $6543
    sta $6544
    sta $6545
    sta $6546
    sta $6547
    sta $654E
    sta $6073
    lda #$0A
    sta $61F8                   ; Party calculation temporaries.
    lda #$C0
    sta $63A4
    lda #$00
    tax
    tay
b13_loc_95FA:
    lda b13_data_98C7,x
    sta ppu_update_ptr_lo
b13_loc_95FF:
    asl ppu_update_ptr_lo
    bcc b13_loc_9608
    lda #$98
    sta $6300,y
b13_loc_9608:
    iny
    tya
    and #$07
    bne b13_loc_95FF
    inx
    cpx #$20
    bne b13_loc_95FA
    jsr battle_party_init
    lda #$05
    sta party_index
    ldx #$02
b13_loc_961C:
    lda b13_data_9729,x
    sta $0500,x                 ; Per-actor state flags.
    lda b13_data_972C,x
    sta $0510,x                 ; Per-actor state flags.
    lda b13_data_972C,x
    sta $0520,x                 ; Per-actor state flags.
    lda b13_data_972F,x
    sta $0530,x                 ; Per-actor palette/facing.
    lda b13_data_9732,x
    sta $0540,x                 ; Per-actor tile/sprite id.
    lda b13_data_9735,x
    sta $0550,x                 ; Per-actor animation frame.
    dex
    bpl b13_loc_961C
    jsr loc_C139
    lda #$00
    sta menu_flags
    lda #$50
    sta $8C
b13_loc_964E:
    inc $0540                   ; Per-actor tile/sprite id.
    inc $0551                   ; Per-actor animation frame.
    dec $0552                   ; Per-actor animation frame.
    ldx #$02
b13_loc_9659:
    lda $05A0,x                 ; Per-actor animation state.
    clc
    adc #$04
    sta $05A0,x                 ; Per-actor animation state.
    dex
    bpl b13_loc_9659
    jsr loc_C0E2
    jsr loc_C0E2
    dec $8C
    bpl b13_loc_964E
    ldx #$32
    jsr wait_frames
    jsr ppu_init
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b13_inline_967A
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b13_inline_967A:
    lda #$03
    jsr set_bank_b
    lda #$00
    ldx #$80
    ldy #$18
    jsr copy_to_vram            ; inline pointer/data follows the JSR

b13_data_9688:
    .incbin "build/assets/bank13_data.bin", $1688, $0002
    lda #$20
    ldx #$1A
    ldy #$14
    jsr copy_to_vram            ; inline pointer/data follows the JSR

b13_data_9693:
    .incbin "build/assets/bank13_data.bin", $1693, $0002
    lda #$00
    ldx #$08
    ldy #$08
    jsr copy_to_vram            ; inline pointer/data follows the JSR

b13_data_969E:
    .incbin "build/assets/bank13_data.bin", $169E, $0002
    jsr return_inline_block

b13_data_96A3:
    .incbin "build/assets/bank13_data.bin", $16A3, $0002
    jsr draw_string             ; inline pointer/data follows the JSR

b13_data_96A8:
    .incbin "build/assets/bank13_data.bin", $16A8, $0002
    jsr wait_vblank
    jsr draw_string             ; inline pointer/data follows the JSR

b13_data_96B0:
    .incbin "build/assets/bank13_data.bin", $16B0, $0002
    jsr wait_vblank
    jsr draw_string             ; inline pointer/data follows the JSR

b13_data_96B8:
    .incbin "build/assets/bank13_data.bin", $16B8, $0002
    jsr read_inline_rect        ; inline pointer/data follows the JSR

b13_data_96BD:
    .incbin "build/assets/bank13_data.bin", $16BD, $0002
.ifdef KANJI_TARGET
    jsr b13_k_oath              ; (the oath's kanji and its split first)
.else
    jsr wait_vblank
.endif
    jsr ppu_nmi_on
    lda #$0A
    sta text_graphics_index
    jsr load_text_graphics
    jsr wait_vblank
    jsr screen_fade_in_step
    lda #$84
    sta input_buttons
    ldx #$1E
    jsr text_init
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_96DE:
    .dw b10_msg_index_128    ; text index $0080 -> b10_msg_128
    jsr loc_D44C
    lda #$00
    sta text_graphics_index
    jsr load_text_graphics
    jsr wait_vblank
    jsr ppu_nmi_off
.ifdef KANJI_TARGET
    jmp b13_k_oathend           ; (then the split off)
.else
    jmp ppu_bg_sprites_off
.endif

b13_data_96F3:
    .incbin "build/assets/bank13_data.bin", $16F3, $0007

b13_data_96FA:
    .incbin "build/assets/bank13_data.bin", $16FA, $0003

b13_data_96FD:
    .incbin "build/assets/bank13_data.bin", $16FD, $0003

b13_data_9700:
    .incbin "build/assets/bank13_data.bin", $1700, $0011

b13_data_9711:
    .incbin "build/assets/bank13_data.bin", $1711, $0018

b13_data_9729:
    .incbin "build/assets/bank13_data.bin", $1729, $0003

b13_data_972C:
    .incbin "build/assets/bank13_data.bin", $172C, $0003

b13_data_972F:
    .incbin "build/assets/bank13_data.bin", $172F, $0003

b13_data_9732:
    .incbin "build/assets/bank13_data.bin", $1732, $0003

b13_data_9735:
    .incbin "build/assets/bank13_data.bin", $1735, $00DB

b13_data_9810:
    .incbin "build/assets/bank13_data.bin", $1810, $00B7

b13_data_98C7:
    .incbin "build/assets/bank13_data.bin", $18C7, $0020

; ----------------------------------------------------------------------
; b13_fade_out_wait
;   Fade the screen out and wait for the transition.
; ----------------------------------------------------------------------
b13_fade_out_wait:
    lda #$0F
    jsr sound_queue_add
    lda #$0F
b13_loc_98EE:
    pha
    jsr screen_fade_in_step
    jsr update_frame
    jsr ppu_bg_sprites_off_shadow
    jsr update_frame
    pla
    sec
    sbc #$01
    bne b13_loc_98EE
    jsr clear_oam_shadow
    ldy #$00
b13_loc_9906:
    lda #$00
    sta ppu_update_len
b13_loc_990A:
    jsr ppu_bg_sprites_off_shadow
    jsr wait_vblank
    jsr ppu_nmi_off
    lda #$00
    clc
    adc ppu_update_len
    sta cursor_x2
    lda #$18
    sta cursor_y2
    lda #$00
    sta ppu_update_ptr_lo
b13_loc_9922:
    lda cursor_y2
    sta PPUADDR
    lda cursor_x2
    sta PPUADDR
    lda PPUDATA
    lda PPUDATA
    and b13_data_996E,y
    ldx cursor_y2
    stx PPUADDR
    ldx cursor_x2
    stx PPUADDR
    sta PPUDATA
    lda cursor_x2
    clc
    adc #$08
    sta cursor_x2
    lda cursor_y2
    adc #$00
    sta cursor_y2
    dec ppu_update_ptr_lo
    bne b13_loc_9922
    jsr ppu_nmi_on
    jsr screen_fade_in_step
    ldx #$01
    jsr wait_frames
    iny
    inc ppu_update_len
    lda ppu_update_len
    cmp #$08
    bne b13_loc_990A
    cpy #$10
    bne b13_loc_9906
    jmp ppu_bg_sprites_off

b13_data_996E:
    .incbin "build/assets/bank13_data.bin", $196E, $0292

; ----------------------------------------------------------------------
; b13_find_first_party
;   Find the first active party member.
; ----------------------------------------------------------------------
b13_find_first_party:
    lda #$00
    tax
    tay
b13_loc_9C04:
    lda $6090,x                 ; Party member order (actor ids).
    bmi b13_code_name
    inx
    cpx #$07
    bne b13_loc_9C04
    beq b13_loc_9C50
b13_code_name:
    lda $60A8,y                 ; Party member class/officer id.
    beq b13_loc_9C1C
    iny
    cpy #$07
    bne b13_code_name
    beq b13_loc_9C50
b13_loc_9C1C:
    tya
    pha
    sta $6090,x                 ; Party member order (actor ids).
    lda #$80
    sta $609C,y                 ; Party member state bits.
    ldx sound_temp
    lda $05F0,x
    sta $60A8,y                 ; Party member class/officer id.
    tax
    lda #$C0
    sta $6300,x
    jsr battle_party_init
    pla
    asl a
    asl a
    tay
    lda $6160,y                 ; Party member derived stats.
    sta $60D0,y                 ; Party member stats.
    lda $6161,y                 ; Party member derived stats.
    sta $60D1,y                 ; Party member stats.
    lda $6162,y                 ; Party member derived stats.
    sta $60D2,y                 ; Party member stats.
    jmp b13_loc_9C71
b13_loc_9C50:
    ldy #$00
b13_loc_9C52:
    lda $6030,y
    beq b13_loc_9C63
    iny
    cpy #$40
    bne b13_loc_9C52
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_9C5F:
    .dw b10_msg_index_038    ; text index $0026 -> b10_msg_038
    sec
    rts
b13_loc_9C63:
    ldx sound_temp
    lda $05F0,x
    sta $6030,y
    tax
    lda #$C0
    sta $6300,x
b13_loc_9C71:
    ldx sound_temp
    lda #$00
    sta $0500,x                 ; Per-actor state flags.
    clc
    rts
; ----------------------------------------------------------------------
; b13_init_name_entry
;   Initialise the name-entry screen.
;   called by: $8A5B, $8AAB, $8B95, $8C69, $904E, $912B, $9F63
; ----------------------------------------------------------------------
b13_init_name_entry:
    lda #$00
    sta ptr0_lo
    lda #$08
    sta ptr0_hi
    lda text_palette
    clc
    adc #$0D
    sta ppu_addr_hi
    jsr mul16_by_u8
    lda #$00
    sta $00
    lda #$60
    sta $01
    rts

b13_data_9C95:
    .incbin "build/assets/bank13_data.bin", $1C95, $000B
; ----------------------------------------------------------------------
; b13_expand_name_tile
;   Expand one packed name tile.
;   called by: $9CC6, $A0A4, $A0AF
; ----------------------------------------------------------------------
b13_expand_name_tile:
    sta ppu_update_len
    lsr a
    lsr a
    lsr a
    tax
    lda ppu_update_len
    and #$07
    sta ppu_update_len
    tay
    lda $6550,x
b13_loc_9CB0:
    rol a
    dec ppu_update_len
    bpl b13_loc_9CB0
    rts
; ----------------------------------------------------------------------
; b13_pack_name_tile
;   Pack/rotate one name-entry tile into the tile buffer.
;   called by: $9CCA
; ----------------------------------------------------------------------
b13_pack_name_tile:
    ror a
    dey
    bpl b13_pack_name_tile
    sta $6550,x
    rts

b13_data_9CBE:
    .incbin "build/assets/bank13_data.bin", $1CBE, $0008
; ----------------------------------------------------------------------
; b13_check_name_tile
;   Check/expand a packed name tile and set carry on failure.
; ----------------------------------------------------------------------
b13_check_name_tile:
    jsr b13_expand_name_tile
    sec
    jsr b13_pack_name_tile
    rts

b13_data_9CCE:
    .incbin "build/assets/bank13_data.bin", $1CCE, $0266

b13_data_9F34:
    .incbin "build/assets/bank13_data.bin", $1F34, $0010

b13_data_9F44:
    .incbin "build/assets/bank13_data.bin", $1F44, $001F

; ----------------------------------------------------------------------
; b13_name_entry_screen
;   Name-entry screen setup.
;   called by: $8C17
; ----------------------------------------------------------------------
b13_name_entry_screen:
    jsr b13_init_name_entry
    lda #$35
    sta $6008
    lda #$53
    sta $6009
    lda #$00
    sta ppu_update_ptr_lo
    sta ppu_update_ptr_hi
    ldy #$08
    sty ppu_update_off
b13_loc_9F7A:
    lda ($00),y
    sta ($10),y
    clc
    adc ppu_update_ptr_lo
    sta ppu_update_ptr_lo
    lda ppu_update_ptr_hi
    adc #$00
    sta ppu_update_ptr_hi
    iny
    bne b13_loc_9F7A
    inc $01
    inc ptr0_hi
    dec ppu_update_off
    bne b13_loc_9F7A
    lda ptr0_hi
    sec
    sbc #$08
    sta ptr0_hi
    ldy #$06
    lda ppu_update_ptr_lo
    sta ($10),y
    iny
    lda ppu_update_ptr_hi
    sta ($10),y
    lda #$08
    jmp sound_queue_add
; ----------------------------------------------------------------------
; b13_loc_9FAB
;   called by: $A0F9
; ----------------------------------------------------------------------
b13_loc_9FAB:
    lda #$02
    sta $6011
    ldx #$00
    lda $6550
    asl a
    bcc b13_loc_9FCB
    ldy #$08
    lda $607E
b13_loc_9FBD:
    cmp b13_data_A069,y
    beq b13_loc_9FC5
    dey
    bne b13_loc_9FBD
b13_loc_9FC5:
    tya
    asl a
    asl a
    asl a
    asl a
    tax
b13_loc_9FCB:
    ldy #$00
b13_loc_9FCD:
    lda b13_data_9FDA,x
    sta $6012,y
    inx
    iny
    cpy #$10
    bne b13_loc_9FCD
    rts

b13_data_9FDA:
    .incbin "build/assets/bank13_data.bin", $1FDA, $0036

b13_data_A010:
    .incbin "build/assets/bank13_data.bin", $2010, $0059

b13_data_A069:
    .incbin "build/assets/bank13_data.bin", $2069, $000C

; ----------------------------------------------------------------------
; b13_name_entry_input
;   Name-entry cursor/input handler.
; ----------------------------------------------------------------------
b13_name_entry_input:
    cmp #$01
    beq b13_loc_A0DA
    lda $6013
    cmp $607E
    bne b13_loc_A0DA
    cmp $607F
    beq b13_loc_A0CB
    lda $607F
    bne b13_loc_A0BC
    lda #$20
    sta $05D3                   ; Per-actor status bits.
    ldx $6010
    cpx #$04
    beq b13_loc_A0A2
b13_loc_A097:
    lda $6371
    bne b13_loc_A09D
    inx
b13_loc_A09D:
    lda b13_data_A0E1,x
    bne b13_loc_A0C8
b13_loc_A0A2:
    lda #$04
    jsr b13_expand_name_tile
    bcc b13_loc_A0AD
    lda #$A2
    bne b13_loc_A0C8
b13_loc_A0AD:
    lda #$05
    jsr b13_expand_name_tile
    bcs b13_loc_A0B8
    ldx #$04
    bne b13_loc_A097
b13_loc_A0B8:
    lda #$A4
    bne b13_loc_A0C8
b13_loc_A0BC:
    sta $607E
    sta text_command
    lda #$00
    sta $05D3                   ; Per-actor status bits.
    lda #$CF
b13_loc_A0C8:
    sta $05E3                   ; Per-actor level.
b13_loc_A0CB:
    jsr set_bank_13
    lda #$58
    sta screen_brightness
    ldx #$00
    jsr expand_name_tile
    jmp set_bank_14
b13_loc_A0DA:
    lda #$00
    sta $0503                   ; Per-actor state flags.
    jmp set_bank_14

b13_data_A0E2:
    .incbin "build/assets/bank13_data.bin", $20E2, $0011
; ----------------------------------------------------------------------
; b13_officer_status_init
;   Initialise the officer-status/gameplay handoff after name entry.
; ----------------------------------------------------------------------
b13_officer_status_init:
    jsr ppu_bg_sprites_off
    jsr ppu_nmi_off
    jsr b14_data_9FAB           ; bank 14: b14_data_9FAB
    lda $6014
    sta party_index
    ldx #$03
b13_loc_A103:
    lda $6016,x
    sta text_x,x
    dex
    bpl b13_loc_A103
    lda #$02
    sta $6011
    lda #$00
    sta $90
    sta text_busy
    sta battle_flags
    sta game_mode
    sta battle_flags2
    ldx #$06
b13_loc_A11E:
    lda $60A8,x                 ; Party member class/officer id.
    cmp #$D5
    beq b13_loc_A12D
    cmp #$A8
    bcc b13_loc_A14D
    cmp #$AE
    bcs b13_loc_A14D
b13_loc_A12D:
    lda $609C,x                 ; Party member state bits.
    bne b13_loc_A137
    lda #$80
    sta $609C,x                 ; Party member state bits.
b13_loc_A137:
    txa
    asl a
    asl a
    tay
    lda $6160,y                 ; Party member derived stats.
    sta $60D0,y                 ; Party member stats.
    lda $6161,y                 ; Party member derived stats.
    sta $60D1,y                 ; Party member stats.
    lda $6162,y                 ; Party member derived stats.
    sta $60D2,y                 ; Party member stats.
b13_loc_A14D:
    dex
    bpl b13_loc_A11E
    lda #$0D
    sta current_bank_a
    jsr call_inline_block       ; copies the following block to $0600 and executes it there
; ----------------------------------------------------------------------
; b13_inline_A157
;   Inline RAM routine copied to $0600 by call_inline_block.
;   It executes with another PRG bank mapped and returns
;   through return_inline_block ($C4FB).
; ----------------------------------------------------------------------
b13_inline_A157:
    lda #$0E
    jsr set_bank_a
    jsr b14_field_get_area_tileset; bank 14: b14_field_get_area_tileset
    jsr b14_field_play_area_music; bank 14: b14_field_play_area_music
    jsr b14_init_battle_party   ; bank 14: b14_init_battle_party
    jsr init_party_status
    jsr battle_main
    jsr screen_refresh
    jsr return_inline_block

b13_data_A171:
    .incbin "build/assets/bank13_data.bin", $2171, $0002
    jsr find_party_member
    jsr reset_text_engine
    lda party_index
    cmp #$05
    bne b13_loc_A187
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_A182:
    .dw b10_msg_index_211    ; text index $00D3 -> b10_msg_211
    jmp b13_loc_A18C
b13_loc_A187:
    jsr text_print_inline       ; inline pointer/data follows the JSR

b13_data_A18A:
    .dw b10_msg_index_212    ; text index $00D4 -> b10_msg_212
b13_loc_A18C:
    jsr wait_keypress
    jsr text_draw_screen
    jmp set_bank_14
    lda $6705
    and #$F7
    sta $6705
    jmp set_bank_14

b13_data_A1A0:
    .incbin "build/assets/bank13_data.bin", $21A0, $02D5

b13_data_A475:
    .incbin "build/assets/bank13_data.bin", $2475, $0400

b13_data_A875:
    .incbin "build/assets/bank13_data.bin", $2875, $0400

b13_data_AC75:
    .incbin "build/assets/bank13_data.bin", $2C75, $0400

b13_data_B075:
    .incbin "build/assets/bank13_data.bin", $3075, $0400

b13_data_B475:
    .incbin "build/assets/bank13_data.bin", $3475, $028B

b13_data_B700:
    .incbin "build/assets/bank13_data.bin", $3700, $0010

b13_dictionary:
    .incbin "build/assets/bank13_data.bin", $3710, $00F0

b13_data_B800:
    .incbin "build/assets/bank13_data.bin", $3800, $0310

b13_data_BB10:
    .incbin "build/assets/bank13_data.bin", $3B10, $0388

b13_data_BE98:
    .incbin "build/assets/bank13_data.bin", $3E98, $0010

b13_data_tail:
    .incbin "build/assets/bank13_data.bin", $3EA8, $0158

