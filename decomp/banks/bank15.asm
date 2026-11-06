; ======================================================================
; PRG bank 15  CPU $C000-$FFFF
; ======================================================================
; traced code: 5206 instructions / 10446 bytes; CDL code bytes: 8690
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $C000-$EBFF  b15_code: Fixed-bank main code and tables.
;   $EC00-$EE78  b15_text_data: Inline text/bytecode data in the fixed bank.
;   $EE79-$FFF9  b15_code_high: Fixed-bank code and tables.
;   $FFFA-$FFFF  b15_vectors: 6502 interrupt vectors.
; ======================================================================

; Overlapping data aliases (tables referenced inside instructions)
data_C400 = $C400
data_F279 = $F279
data_F679 = $F679

; Region aliases
b15_code = $C000
b15_code_high = $EE79

; ----------------------------------------------------------------------
; main_loop
;   Cooperative task scheduler and main loop entry.
;   Each 4-byte task slot at $20..$3F has state, timer, and a
;   continuation pointer.  State 0 is idle, 1 is timed, 2 is
;   running, 4 is waiting, and 8 resumes at a pointer.
;   inputs:  none
;   outputs: never returns to the reset vector
; ----------------------------------------------------------------------
main_loop:
    ldx #$FF                    ; Reset the main stack.
    txs
; ----------------------------------------------------------------------
; task_scheduler
;   Scan the four task slots and run the first ready task.
;   Falls back to $C003 when every slot is idle.
; ----------------------------------------------------------------------
task_scheduler:
    ldx #$00                    ; Scan the four 4-byte task slots.
    stx task_scan_index
    ldy #$04                    ; Four slots (Y counts down).
loc_C009:
    lda task_state,x
    cmp #$04                    ; States 0-3 are idle/timed; 4+ is runnable.
    bcs loc_C019
    inx
    inx
    inx
    inx
    dey
    bne loc_C009
    jmp task_scheduler          ; No task ready; keep scanning.
loc_C019:
    lda task_scan_index
    bne task_scheduler
    dey
    tya
    eor #$03
    sta task_slot_index
    ldy task_state,x
    lda #$02
    sta task_state,x
    cpy #$08                    ; State 8 resumes at the saved pointer.
    bne loc_C038
    lda task_ptr_lo,x
    sta task_temp_lo
    lda task_ptr_hi,x
    sta task_temp_hi
    jmp ($0034)                 ; Tail-call the task continuation.
loc_C038:
    lda task_ptr_lo,x
    tax
    txs                         ; Use the task's private stack.
    lda task_slot_index
    bne loc_C059
    jsr read_controller         ; Poll controller 1 once per frame.
    jsr read_input_state        ; Update edge/repeat state.
    inc nmi_frame_counter
    lda nmi_mode
    beq loc_C059
    lda #$08
    jsr set_bank_lock
    jsr sound_update            ; Run the banked per-frame hook.; banked call target (bank must be selected first)
    lda current_bank_b
    jsr set_bank_lock
loc_C059:
    pla
    tay
    pla
    tax
    rts
; ----------------------------------------------------------------------
; task_set_continuation
;   Store a continuation pointer in the current task and mark it ready.
;   called by: $F068
; ----------------------------------------------------------------------
task_set_continuation:
    jsr task_slot_from_a
    lda task_temp_lo
    sta task_ptr_lo,x
    lda task_temp_hi
    sta task_ptr_hi,x
    lda #$08
    sta task_state,x
    rts
; ----------------------------------------------------------------------
; task_clear
;   Clear the current task's state (idle).
; ----------------------------------------------------------------------
task_clear:
    jsr task_slot_from_a
    lda #$00
    sta task_state,x
    rts
loc_C076:
    sta task_temp_lo
    txa
    pha
    tya
    pha
    jsr task_slot_from_current
    lda task_temp_lo
    sta task_timer,x
    lda #$01
    sta task_state,x
    txa
    tay
    tsx
    stx task_ptr_lo,y
    jmp main_loop
; ----------------------------------------------------------------------
; task_end
;   Clear the current task and restart the scheduler.
; ----------------------------------------------------------------------
task_end:
    jsr task_slot_from_current
    lda #$00
    sta task_state,x
    jmp main_loop
; ----------------------------------------------------------------------
; task_slot_from_current
;   Load the current task index into A, then fall through to task_slot_from_a.
;   called by: $C07C, $C08F
; ----------------------------------------------------------------------
task_slot_from_current:
    lda task_slot_index
; ----------------------------------------------------------------------
; task_slot_from_a
;   Convert A (task index) to a 4-byte task-slot offset in X.
;   called by: $C05E, $C06E
; ----------------------------------------------------------------------
task_slot_from_a:
    asl a
    asl a
    tax
    rts
; ----------------------------------------------------------------------
; wait_vblank
;   Wait for the NMI window and flush queued PPU updates.
;   If rendering is off, switch to the scheduler before waiting.
;   This is the standard 'yield' call used by text, menu, and map loops.
;   called by: $C0BC, $C13C, $C14B, $C155, $C57C, $C70E, $CE1E, $CED7, $D035, $D07E, $D527, $DC8A (+4 more)
; ----------------------------------------------------------------------
wait_vblank:
    lda nmi_busy
    bne loc_C0AD
    lda ppu_ctrl_shadow
    bpl loc_C0AD
    lda #$01                    ; Request one NMI transfer.
    sta nmi_update_budget
    bne loc_C076
loc_C0AD:
    txa
    pha
    tya
    pha
    jsr flush_vram_queue        ; Flush the VRAM queue.
    jsr flush_palette           ; Upload the pending palette.
    pla
    tay
    pla
    tax
    rts
; ----------------------------------------------------------------------
; wait_frames
;   Wait for X frames by repeatedly yielding.
;   called by: $D1F0
; ----------------------------------------------------------------------
wait_frames:
    jsr wait_vblank
    dex
    bne wait_frames
    rts

data_C0C3:
    .incbin "build/assets/bank15_data.bin", $00C3, $000B
; ----------------------------------------------------------------------
; wait_frame_tick
;   Frame-paced wait helper.  Only acts when the low nibble of $33 is zero.
;   called by: $CA56, $CDEB, $D38B
; ----------------------------------------------------------------------
wait_frame_tick:
    lda frame_counter
    and #$0F
    beq update_frame
    rts
; ----------------------------------------------------------------------
; update_frame
;   Per-frame input/UI update.
;   Polls the controller, updates sprites, and yields to the scheduler.
;   called by: $CDBE, $D442, $D44C, $D477, $D488, $DC70, $F195, $F1CD, $F1DA
; ----------------------------------------------------------------------
update_frame:
    lda input_buttons
    bne loc_C0E8
    lda frame_counter
    and #$0F
    bne update_frame_no_input
    jsr draw_text_window
loc_C0E2:
    jsr update_oam
    jsr hide_sprites
loc_C0E8:
    jmp wait_vblank
; ----------------------------------------------------------------------
; update_frame_no_input
;   Per-frame update variant that skips controller polling while a button is held.
;   called by: $CB3B, $D3BA, $D3C7, $D3D1
; ----------------------------------------------------------------------
update_frame_no_input:
    lda input_buttons
    beq loc_C0E2
    jmp wait_vblank
; ----------------------------------------------------------------------
; ppu_nmi_off
;   Clear PPUCTRL bit 7 (disable NMI) and write the shadow.
;   called by: $C439, $F0FD
; ----------------------------------------------------------------------
ppu_nmi_off:
    lda ppu_ctrl_shadow
    and #$7F
    sta ppu_ctrl_shadow
    sta PPUCTRL
    rts
; ----------------------------------------------------------------------
; ppu_nmi_on
;   Set PPUCTRL bit 7 (enable NMI) and write the shadow.
;   called by: $C139, $C145, $CF0C, $EEDD, $F075
; ----------------------------------------------------------------------
ppu_nmi_on:
    lda ppu_ctrl_shadow
    ora #$80
    sta ppu_ctrl_shadow
    sta PPUCTRL
    rts
; ----------------------------------------------------------------------
; one_minus_a
;   Return 1 - A (ones-complement helper).
; ----------------------------------------------------------------------
one_minus_a:
    sec
    sbc #$01
    eor #$FF
    rts
; ----------------------------------------------------------------------
; dispatch_return_table
;   Dispatch through a table that follows the JSR return address.
;   A selects the word entry; the return address is advanced past the table.
;   called by: $D2A2, $F1C0, $F547
; ----------------------------------------------------------------------
dispatch_return_table:
    asl a
    tay
    iny
    pla
    sta sound_ptr
    pla
    sta $EF
    lda ($EE),y
    tax
    iny
    lda ($EE),y
    sta $EF
    stx sound_ptr
    jmp ($00EE)
; ----------------------------------------------------------------------
; ppu_bg_sprites_off
;   Disable background and sprite rendering (PPUMASK bits 3-4).
;   called by: $C43C, $F100
; ----------------------------------------------------------------------
ppu_bg_sprites_off:
    lda ppu_mask_shadow
    and #$E7
    sta PPUMASK
loc_C129:
    sta ppu_mask_shadow
    rts

data_C12C:
    .incbin "build/assets/bank15_data.bin", $012C, $0006
; ----------------------------------------------------------------------
; ppu_bg_sprites_off_shadow
;   Disable background/sprite rendering in the shadow only.
;   called by: $C148
; ----------------------------------------------------------------------
ppu_bg_sprites_off_shadow:
    lda ppu_mask_shadow
    and #$E7
    jmp loc_C129
loc_C139:
    jsr ppu_nmi_on
    jsr wait_vblank
; ----------------------------------------------------------------------
; screen_fade_in_step
;   Advance one step of the screen fade-in state machine.
; ----------------------------------------------------------------------
screen_fade_in_step:
    lda ppu_mask_shadow
    ora #$18
    bne loc_C129
; ----------------------------------------------------------------------
; screen_fade_in
;   Enable NMI, restore the mask, yield, and step the fade state.
;   called by: $CEE4, $CF1F
; ----------------------------------------------------------------------
screen_fade_in:
    jsr ppu_nmi_on
    jsr ppu_bg_sprites_off_shadow
    jsr wait_vblank
    inc nmi_busy
    rts
; ----------------------------------------------------------------------
; screen_fade_out
;   Begin a screen fade-out and wait.
;   called by: $CF3A
; ----------------------------------------------------------------------
screen_fade_out:
    lda #$00
    sta nmi_busy
    jsr wait_vblank
    jmp screen_fade_in_step
; ----------------------------------------------------------------------
; rng_seed
;   Seed the 24-bit LFSR from $10/$11/$16.
;   called by: $CFE6
; ----------------------------------------------------------------------
rng_seed:
    lda #$00
    sta ppu_addr_lo
; ----------------------------------------------------------------------
; rng_next
;   Advance the 24-bit LFSR (used for random encounters and battle rolls).
;   called by: $E756
; ----------------------------------------------------------------------
rng_next:
    lda #$00
    sta ptr1_lo
    lda $16
    pha
    lda ptr1_lo
    sta $16
    lda ptr0_hi
    sta ptr1_hi
    lda ptr0_lo
    sta ptr1_lo
    tya
    pha
    lda #$00
    sta ptr0_lo
    sta ptr0_hi
    ldy #$18
loc_C17C:
    asl ptr0_lo
    rol ptr0_hi
    rol ptr1_lo
    rol ptr1_hi
    rol $16
    bcc loc_C199
    lda ptr0_lo
    clc
    adc ppu_addr_lo
    sta ptr0_lo
    lda ptr0_hi
    adc ppu_addr_hi
    sta ptr0_hi
    bcc loc_C199
    inc ptr1_lo
loc_C199:
    dey
    bne loc_C17C
    lda ptr0_hi
    sta ptr0_lo
    lda ptr1_lo
    sta ptr0_hi
    lda ptr1_hi
    sta ptr1_lo
    pla
    tay
    pla
    sta $16
    rts

data_C1AE:
    .incbin "build/assets/bank15_data.bin", $01AE, $0005
; ----------------------------------------------------------------------
; mul16x8_shift
;   Shift/multiply helper used by the RNG and battle math.
;   called by: $E58B
; ----------------------------------------------------------------------
mul16x8_shift:
    tya
    pha
    lda #$00
    sta ptr1_lo
    ldy #$10
loc_C1BB:
    asl ptr0_lo
    rol ptr0_hi
    rol ptr1_lo
    lda ptr1_lo
    sec
    sbc ptr1_hi
    bcc loc_C1CC
    sta ptr1_lo
    inc ptr0_lo
loc_C1CC:
    dey
    bne loc_C1BB
    pla
    tay
    rts
; ----------------------------------------------------------------------
; div24_shift
;   24-bit shift/divide helper.
;   called by: $D698
; ----------------------------------------------------------------------
div24_shift:
    txa
    pha
    tya
    pha
    lda #$00
    sta $03
    sta $04
    sta $05
    ldy #$18
    sty $09
loc_C1E2:
    asl $00
    rol $01
    rol $02
    rol $03
    rol $04
    rol $05
    lda $03
    tax
    sec
    sbc $06
    sta $03
    lda $04
    tay
    sbc $07
    sta $04
    lda $05
    sbc $08
    bcc loc_C20A
    sta $05
    inc $00
    jmp loc_C20E
loc_C20A:
    sty $04
    stx $03
loc_C20E:
    dec $09
    bne loc_C1E2
    pla
    tay
    pla
    tax
    rts

data_C217:
    .incbin "build/assets/bank15_data.bin", $0217, $0043

; ----------------------------------------------------------------------
; fetch_inline_word
;   Fetch the word that follows the caller's JSR.
;   Used by inline text and inline pointer data.
;   outputs: A/X = low/high byte, return address advanced
;   called by: $C340, $C3EE, $D10D, $D656, $DD14, $FA14, $FA1F, $FA42, $FA4D
; ----------------------------------------------------------------------
fetch_inline_word:
    tsx
    lda $0103,x
    sta $05
    lda $0104,x
    sta $06
    ldy #$01
    lda ($05),y
    sta $00
    iny
    lda ($05),y
    sta $01
    clc
    lda #$02
    adc $05
    sta $0103,x
    lda #$00
    adc $06
    sta $0104,x
    rts
; ----------------------------------------------------------------------
; read_controller
;   Poll controller 1 and update $F5/$F7.
;   The previous state is kept for edge detection.
;   called by: $C040
; ----------------------------------------------------------------------
read_controller:
    ldx #$01                    ; Strobe JOY1 and read eight buttons.
    stx JOY1
    dex
    stx JOY1
    ldx #$08
loc_C28B:
    lda JOY1
    lsr a
    rol controller_state
    lsr a
    rol sound_ptr
    dex
    bne loc_C28B
    lda sound_ptr
    ora controller_state
    sta controller_state
    ldx #$00
    lda controller_state,x
    tay
    eor controller_prev,x
    and controller_state,x
    sta controller_state,x
    sty controller_prev,x
    rts
; ----------------------------------------------------------------------
; set_ppu_scroll
;   Set PPU scroll/address registers from A/X/Y.
;   called by: $C445
; ----------------------------------------------------------------------
set_ppu_scroll:
    sta $00                     ; Set PPUADDR to 0 and write scroll.
    stx $01
    sty $02
    lda PPUSTATUS
    lda $00
    sta PPUADDR
    ldy #$00
    sty PPUADDR
    ldx #$04
    ldy #$00
    lda $01
loc_C2C4:
    sta PPUDATA
    dey
    bne loc_C2C4
    dex
    bne loc_C2C4
    ldy $02
    lda $00
    clc
    adc #$03
    sta PPUADDR
    lda #$C0
    sta PPUADDR
    ldx #$40
loc_C2DE:
    sty PPUDATA
    dex
    bne loc_C2DE
    ldx $01
    rts
; ----------------------------------------------------------------------
; fill_ram_block
;   Fill a block of CPU RAM/PPU memory with a constant.
;   called by: $F05B
; ----------------------------------------------------------------------
fill_ram_block:
    pha
    txa
    sty ptr0_hi
    clc
    sbc ptr0_hi
    tax
    pla
    ldy #$00
    sty ptr0_lo
loc_C2F4:
    sta ($10),y
    dey
    bne loc_C2F4
    dec ptr0_hi
    inx
    bne loc_C2F4
    rts
; ----------------------------------------------------------------------
; flush_palette
;   Upload a pending palette block through the VRAM helper.
;   called by: $C0B4, $EECB
; ----------------------------------------------------------------------
flush_palette:
    lda palette_dirty
    beq loc_C330
    lda #$00
    sta palette_dirty
    lda $3A
    sta $01
    lda $39
    sta $00
    clc
    adc #$40
    sta $39
    lda $3A
    adc #$00
    sta $3A
    lda $3B
    ldx #$04
    ldy $3C
    jsr write_vram_block
    lda $3B
    clc
    adc #$40
    sta $3B
    lda $3C
    adc #$00
    sta $3C
loc_C330:
    rts
; ----------------------------------------------------------------------
; write_vram_block
;   Write a block of bytes to PPUDATA from a RAM pointer.
;   called by: $C320, $C70B, $DEB6
; ----------------------------------------------------------------------
write_vram_block:
    sta $04                     ; Set PPUADDR and copy A bytes from ($00).
    stx $02
    sty $03
    jmp loc_C343
; ----------------------------------------------------------------------
; copy_to_vram
;   Copy a block from CPU memory to PPUDATA.
;   called by: $CEF5, $CF00, $DE98
; ----------------------------------------------------------------------
copy_to_vram:
    sta $04
    stx $02
    sty $03
    jsr fetch_inline_word       ; inline pointer/data follows the JSR
loc_C343:
    lda PPUSTATUS
    ldy $03
    sty PPUADDR
    lda $04
    and #$F0
    sta PPUADDR
    lda #$00
    sta $03
    lda $04
    and #$0F
    lsr a
    bcc loc_C35F
    dec $03
loc_C35F:
    lsr a
    bcc loc_C365
    ldx PPUDATA
loc_C365:
    tay
    beq loc_C37D
    dey
    beq loc_C38B
    dey
    beq loc_C397
    dey
loc_C36F:
    jsr vram_put_tile_xor
    ldy #$00
    jsr vram_put_tile_loop
    jsr vram_ptr_add8
    bne loc_C36F
    rts
loc_C37D:
    jsr vram_put_tile_loop
    jsr vram_put_tile_loop
    lda #$10
    jsr vram_ptr_add
    bne loc_C37D
    rts
loc_C38B:
    jsr vram_put_tile_loop
    jsr vram_put_run
    jsr vram_ptr_add8
    bne loc_C38B
    rts
loc_C397:
    sec
    jsr vram_put_run
    clc
    jsr vram_put_tile_loop
    jsr vram_ptr_add8
    bne loc_C397
    rts
; ----------------------------------------------------------------------
; vram_ptr_add8
;   Add 8 to the 16-bit VRAM pointer in $00/$01.
;   called by: $C377, $C391, $C39F
; ----------------------------------------------------------------------
vram_ptr_add8:
    lda #$08
; ----------------------------------------------------------------------
; vram_ptr_add
;   Add A to the 16-bit VRAM pointer in $00/$01.
;   called by: $C385
; ----------------------------------------------------------------------
vram_ptr_add:
    php
    ldy #$00
    clc
    adc $00
    sta $00
    lda #$00
    adc $01
    sta $01
    plp
    dec $02
    rts
; ----------------------------------------------------------------------
; vram_put_tile_loop
;   Write a run of bytes to PPUDATA from the current pointer.
;   called by: $C374, $C37D, $C380, $C38B, $C39C
; ----------------------------------------------------------------------
vram_put_tile_loop:
    ldx #$08
loc_C3BB:
    bcs loc_C3C7
    lda ($00),y
    sta PPUDATA
loc_C3C2:
    iny
    dex
    bne loc_C3BB
    rts
loc_C3C7:
    lda PPUDATA
    sta ($00),y
    bcs loc_C3C2
; ----------------------------------------------------------------------
; vram_put_run
;   Write a run of bytes to PPUDATA with a fixed tile value.
;   called by: $C38E, $C398
; ----------------------------------------------------------------------
vram_put_run:
    lda $03
    ldx #$08
loc_C3D2:
    bcs loc_C3DB
    sta PPUDATA
loc_C3D7:
    dex
    bne loc_C3D2
    rts
loc_C3DB:
    lda PPUDATA
    bcs loc_C3D7
; ----------------------------------------------------------------------
; vram_put_tile_xor
;   Write 8 bytes to PPUDATA XORed with a constant.
;   called by: $C36F
; ----------------------------------------------------------------------
vram_put_tile_xor:
    ldx #$08
loc_C3E2:
    lda $03
    eor ($00),y
    sta PPUDATA
    iny
    dex
    bne loc_C3E2
    rts
; ----------------------------------------------------------------------
; read_inline_rect
;   Read an inline rectangle/table descriptor and copy four bytes to $02-$06.
; ----------------------------------------------------------------------
read_inline_rect:
    jsr fetch_inline_word       ; inline pointer/data follows the JSR
data_C3F1:
    ldy #$00
    lda ($00),y
loc_C3F5:
    sta $02
    iny
    lda ($00),y
    sta $03
    iny
    lda ($00),y
    sta $05
    iny
    lda ($00),y
    sta $06
loc_C406:
    ldx oam_write_index
    lda $03
    sta $0200,x                 ; Sprite shadow copied to OAM by DMA.
    lda $05
    sta $0202,x                 ; Sprite shadow copied to OAM by DMA.
loc_C412:
    lda $06
    sta $0203,x                 ; Sprite shadow copied to OAM by DMA.
    clc
    adc #$08
    sta $06
    iny
    lda ($00),y
    cmp #$FF
    beq loc_C412
    sta $0201,x                 ; Sprite shadow copied to OAM by DMA.
    lda oam_write_index
    clc
    adc #$04
    sta oam_write_index
    dec $02
    bne loc_C406
    iny
    lda ($00),y
    cmp #$FF
    bne loc_C3F5
    rts
; ----------------------------------------------------------------------
; ppu_init
;   Initialise PPU registers, palette, scroll, and OAM shadow.
;   called by: $F07B
; ----------------------------------------------------------------------
ppu_init:
    jsr ppu_nmi_off
; ----------------------------------------------------------------------
; clear_screen
;   Clear the screen and reset PPU state.
;   called by: $CEE7
; ----------------------------------------------------------------------
clear_screen:
    jsr ppu_bg_sprites_off
    lda #$20
    ldx #$0A
    ldy #$00
    jsr set_ppu_scroll
    lda #$00
    sta scroll_y
    sta scroll_x
; ----------------------------------------------------------------------
; clear_oam_shadow
;   Hide all 64 sprites in the OAM shadow.
;   called by: $C576
; ----------------------------------------------------------------------
clear_oam_shadow:
    ldx #$00
    beq loc_C454
; ----------------------------------------------------------------------
; hide_sprites
;   Write $F8 (offscreen Y) to every sprite in the OAM shadow.
;   called by: $C0E5, $F701
; ----------------------------------------------------------------------
hide_sprites:
    ldx oam_write_index
loc_C454:
    lda #$F8
loc_C456:
    sta $0200,x                 ; Sprite shadow copied to OAM by DMA.
    inx
    inx
    inx
    inx
    bne loc_C456
    rts
; ----------------------------------------------------------------------
; mmc1_reset
;   Reset the MMC1 shift register and map bank 14.
;   called by: $C493, $C4AF
; ----------------------------------------------------------------------
mmc1_reset:
    inc data_FFD9
    lda #$0E
    jsr write_prg_bank
; ----------------------------------------------------------------------
; mmc1_init
;   Initialise MMC1 control/PRG registers.
;   called by: $F009
; ----------------------------------------------------------------------
mmc1_init:
    lda #$0E
    sta MMC1_CONTROL
    lsr a
    sta MMC1_CONTROL
    lsr a
    sta MMC1_CONTROL
    lsr a
    sta MMC1_CONTROL
    lsr a
    sta MMC1_CONTROL
    rts
; ----------------------------------------------------------------------
; set_bank_current
;   Map the bank stored in $43 at $8000.
;   called by: $CB8A, $CBF2, $CDDA, $CF05, $CF28, $D032, $D27D, $E386, $E8B3, $F1D3, $F4A9
; ----------------------------------------------------------------------
set_bank_current:
    lda current_bank_a          ; Publish the current bank and map it.
; ----------------------------------------------------------------------
; set_bank_a
;   Map bank A at $8000 and update both current-bank variables.
;   called by: $D275, $F0D9, $F0E1, $F1BB
; ----------------------------------------------------------------------
set_bank_a:
    sta current_bank_a
; ----------------------------------------------------------------------
; set_bank_b
;   Map bank A at $8000; used for temporary data access.
;   called by: $C9C6, $CBDA, $CDB8, $CEEC, $CFAC, $CFEB, $CFFD, $D047, $D139, $D288, $D315, $D4A7 (+24 more)
; ----------------------------------------------------------------------
set_bank_b:
    sta current_bank_b
; ----------------------------------------------------------------------
; set_bank_lock
;   Map bank A at $8000, waiting for a pending NMI bank restore.
;   called by: $C04E, $C056
; ----------------------------------------------------------------------
set_bank_lock:
    sta current_prg_bank        ; Map A and wait for a pending NMI restore.
loc_C486:
    lda #$01
    sta bank_switch_lock
    lda current_prg_bank
    jsr write_prg_bank
    lda bank_switch_lock
    bne loc_C499
    jsr mmc1_reset
    jmp loc_C486
loc_C499:
    lda #$00
    sta bank_switch_lock
    rts
; ----------------------------------------------------------------------
; set_bank_12
;   Map bank 12 at $8000.
; ----------------------------------------------------------------------
set_bank_12:
    lda #$0C
    bne set_bank_a
; ----------------------------------------------------------------------
; set_bank_13
;   Map bank 13 at $8000.
;   called by: $D190, $F088, $F2AD
; ----------------------------------------------------------------------
set_bank_13:
    lda #$0D
    bne set_bank_a
; ----------------------------------------------------------------------
; set_bank_14
;   Map bank 14 at $8000.
;   called by: $D198, $F08E, $F0BB, $F2F1
; ----------------------------------------------------------------------
set_bank_14:
    lda #$0E
    bne set_bank_a
; ----------------------------------------------------------------------
; restore_bank_after_nmi
;   Restore the bank that was active before NMI.
;   called by: $EF0D, $EF2E
; ----------------------------------------------------------------------
restore_bank_after_nmi:
    pha
    lda bank_switch_lock
    beq loc_C4B6
    jsr mmc1_reset
    lda #$00
    sta bank_switch_lock
loc_C4B6:
    pla
; ----------------------------------------------------------------------
; write_prg_bank
;   Serialise A into the MMC1 PRG bank register.
;   called by: $C465, $C48C, $F006
; ----------------------------------------------------------------------
write_prg_bank:
    sta MMC1_PRG_BANK           ; Serialise A into MMC1 over five writes.
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    lsr a
    sta MMC1_PRG_BANK
    rts

data_C4CB:
    .incbin "build/assets/bank15_data.bin", $04CB, $0004
; ----------------------------------------------------------------------
; sound_queue_add_once
;   Queue a sound command only when it differs from the last one.
; ----------------------------------------------------------------------
sound_queue_add_once:
    cmp sound_bank_lock
    beq loc_C4E3
    sta sound_bank_lock
; ----------------------------------------------------------------------
; sound_queue_add
;   Append a sound command to the 8-entry ring buffer at $E8.
;   inputs:  A = command, Y = parameter
;   called by: $CD39, $CDD2, $D47F, $DC60, $F1A8, $F342, $F34E
; ----------------------------------------------------------------------
sound_queue_add:
    stx sound_ptr
    ldx sound_queue_write
    sta $E0,x
    inx
    txa
    and #$07
    sta sound_queue_write
    ldx sound_ptr
loc_C4E3:
    rts
; ----------------------------------------------------------------------
; call_inline_block
;   Copy the 255-byte inline block after the JSR to $0600 and jump to $0601.
;   The block executes from RAM with a different PRG bank mapped; it must end
;   with return_inline_block/JMP C4FB.
;   This is a far-call/inline-code trampoline, not a normal subroutine.
; ----------------------------------------------------------------------
call_inline_block:
    lda current_bank_a
    sta $45
    pla
    sta ppu_update_ptr_lo
    pla
    sta ppu_update_ptr_hi
    ldy #$01
loc_C4F0:
    lda ($F3),y
    sta $0600,y                 ; Text window tile buffer.
    iny
    bne loc_C4F0
    jmp $0601
; ----------------------------------------------------------------------
; return_inline_block
;   Return from a call_inline_block block: restore the caller's bank and
;   resume at the saved bank address.
;   Used by the RAM-resident inline routines.
; ----------------------------------------------------------------------
return_inline_block:
    stx ppu_update_off
    tsx
    pla
    pla
    lda $0101,x
    sta ppu_update_ptr_lo
    lda $0102,x
    sta ppu_update_ptr_hi
    ldy #$02
    lda ($F3),y
    pha
    dey
    lda ($F3),y
    pha
    ldx ppu_update_off
    lda $45
    jmp set_bank_a
; ----------------------------------------------------------------------
; draw_text_window_small
;   Draw a compact text window (status/menu variant).
;   called by: $CF4F
; ----------------------------------------------------------------------
draw_text_window_small:
    txa
    pha
    lda #$30
    ldx #$F0
    bne loc_C527
; ----------------------------------------------------------------------
; draw_window
;   Draw the standard dialogue/menu window frame.
;   called by: $CED4, $E5C9
; ----------------------------------------------------------------------
draw_window:
    txa
    pha
    lda #$10
    tax
loc_C527:
    stx $0B
    sta $0F
    sty $0E
    ldx #$1F
loc_C52F:
    lda $03E0,x                 ; Small VRAM upload buffer.
    sta $03C0,x                 ; Text line shadow buffer.
    dex
    bpl loc_C52F
    bmi loc_C545
loc_C53A:
    ldx #$1F
loc_C53C:
    lda $03C0,x                 ; Text line shadow buffer.
    sta $03E0,x                 ; Small VRAM upload buffer.
    dex
    bpl loc_C53C
loc_C545:
    ldy #$00
    lda $A5
loc_C549:
    ldx #$04
    lsr a
    bcc loc_C558
    iny
    iny
    iny
    iny
loc_C552:
    cpy #$20
    bne loc_C549
    beq loc_C56D
loc_C558:
    pha
    lda $03E0,y                 ; Small VRAM upload buffer.
    sec
    sbc $0F
    bpl loc_C563
    lda #$0F
loc_C563:
    sta $03E0,y                 ; Small VRAM upload buffer.
    pla
    iny
    dex
    bne loc_C558
    beq loc_C552
loc_C56D:
    sty vram_dma_pending
    lda $0E
loc_C571:
    pha
    lda $A4
    bne loc_C57C
    jsr clear_oam_shadow
    jsr update_oam
loc_C57C:
    jsr wait_vblank
    pla
    sec
    sbc #$01
    bne loc_C571
    lda $0F
    clc
    adc $0B
    sta $0F
    bmi loc_C592
    cmp #$50
    bne loc_C53A
loc_C592:
    ldx #$1F
loc_C594:
    lda $03C0,x                 ; Text line shadow buffer.
    sta $03E0,x                 ; Small VRAM upload buffer.
    dex
    bpl loc_C594
    lda #$00
    sta $A4
    sta $A5
    pla
    tax
    rts
; ----------------------------------------------------------------------
; load_text_graphics
;   Load the tile set for the current text/menu page.
;   called by: $CF13, $CF47
; ----------------------------------------------------------------------
load_text_graphics:
    txa
    pha
    ldx text_graphics_index
    lda data_C6B2,x
    sta ppu_update_ptr_lo
    lda data_C6C2,x
    sta ppu_update_ptr_hi
    ldy #$00
    lda ($F3),y
    tax
loc_C5B9:
    iny
    lda ($F3),y
    bmi loc_C5C4
    sta $03E0,x                 ; Small VRAM upload buffer.
    inx
    bne loc_C5B9
loc_C5C4:
    lda $A5
    beq loc_C5E6
    ldy #$00
loc_C5CA:
    lsr a
    bcs loc_C5D7
    iny
    iny
    iny
    iny
    cpy #$20
    bne loc_C5CA
    beq loc_C5E6
loc_C5D7:
    ldx #$04
loc_C5D9:
    pha
    lda #$0F
    sta $03E0,y                 ; Small VRAM upload buffer.
    pla
    iny
    dex
    bne loc_C5D9
    beq loc_C5CA
loc_C5E6:
    sty vram_dma_pending
    lda #$00
    sta $A5
    pla
    tax
    rts

data_C5EF:
    .incbin "build/assets/bank15_data.bin", $05EF, $00C3

data_C6B2:
    .incbin "build/assets/bank15_data.bin", $06B2, $0010

data_C6C2:
    .incbin "build/assets/bank15_data.bin", $06C2, $0010

; ----------------------------------------------------------------------
; draw_portrait
;   Draw a 16x16 portrait/actor tile block.
;   called by: $E868
; ----------------------------------------------------------------------
draw_portrait:
    lda $0500,x                 ; Per-actor state flags.
    ora #$0C
    sta $0500,x                 ; Per-actor state flags.
    asl $05A0,x                 ; Per-actor animation state.
    lsr $05A0,x                 ; Per-actor animation state.
    lda #$00
    sta ppu_update_ptr_lo
    lda $0510,x                 ; Per-actor state flags.
    tay
    lda data_C980,y
    ldx #$03
    sta ppu_update_ptr_hi
loc_C6EF:
    clc
    lsr ppu_update_ptr_hi
    ror ppu_update_ptr_lo
    dex
    bpl loc_C6EF
    lda ppu_update_ptr_lo
    ora #$02
    sta ppu_update_ptr_lo
    lda #$80
    sta $00
    lda #$01
    sta $01
    lda ppu_update_ptr_lo
    ldy ppu_update_ptr_hi
    ldx #$04
    jsr write_vram_block
    jsr wait_vblank
    ldx vram_queue_write
    lda ppu_update_ptr_hi
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_update_ptr_lo
    and #$F0
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$40
    sta $0400,x                 ; VRAM update command queue.
    inx
    stx ppu_update_ptr_lo
    lda #$80
    sta $00
    lda #$01
    sta $01
    ldx #$00
    stx cursor_y2
    stx ppu_update_ptr_hi
loc_C737:
    lda data_C77F,x
    sta cursor_x2
    lda #$10
    sta cursor_y
loc_C740:
    ldx #$07
    ldy cursor_x2
    clc
loc_C745:
    lda ($00),y
    asl a
    sta ($00),y
    rol cursor_y2
    dey
    dex
    bpl loc_C745
    lda cursor_y2
    ldx ppu_update_ptr_lo
    sta $0400,x                 ; VRAM update command queue.
    inc ppu_update_ptr_lo
    dec cursor_y
    lda cursor_y
    beq loc_C76B
    cmp #$08
    bne loc_C740
    tya
    clc
    adc #$10
    sta cursor_x2
    bne loc_C740
loc_C76B:
    inc ppu_update_ptr_hi
    ldx ppu_update_ptr_hi
    cpx #$04
    bne loc_C737
    ldx ppu_update_ptr_lo
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    jmp wait_vblank

data_C77F:
    .incbin "build/assets/bank15_data.bin", $077F, $0004
; ----------------------------------------------------------------------
; set_cursor_from_table
;   Set the text cursor from a two-byte table entry and save it.
;   called by: $F47C
; ----------------------------------------------------------------------
set_cursor_from_table:
    ldy text_x
    sty cursor_x
    ldy text_y
    sty cursor_y
    ldy text_x2
    sty cursor_x2
    ldy text_y2
    sty cursor_y2
; ----------------------------------------------------------------------
; set_cursor_no_save
;   Set the text cursor from a table without saving.
;   called by: $F999
; ----------------------------------------------------------------------
set_cursor_no_save:
    asl a
    tay
    lda data_C7A3,y
    jsr cursor_add_x_signed
    iny
    lda data_C7A3,y
    jsr cursor_add_y_signed
    rts

data_C7A3:
    .incbin "build/assets/bank15_data.bin", $07A3, $0008
; ----------------------------------------------------------------------
; set_actor_palette
;   Set an actor's palette/facing bits.
;   called by: $E81B, $F337, $F375, $F412, $F4B1, $F95C
; ----------------------------------------------------------------------
set_actor_palette:
    and #$03
    sta $0530,x                 ; Per-actor palette/facing.
    cmp #$02
    php
    lda $0500,x                 ; Per-actor state flags.
    and #$BF
    plp
    bne loc_C7BD
    ora #$40
loc_C7BD:
    sta $0500,x                 ; Per-actor state flags.
    rts
; ----------------------------------------------------------------------
; update_oam
;   Rebuild the OAM shadow from the actor arrays.
;   called by: $C0E2, $C579, $F6FE
; ----------------------------------------------------------------------
update_oam:
    lda #$04
    sta oam_write_index
    ldx #$00
    stx sprite_index
    stx copy_src_lo
loc_C7CB:
    lda $0500,x                 ; Per-actor state flags.
    bpl loc_C809
    lsr a
    bcs loc_C809
    stx $6080
    lda $0540,x                 ; Per-actor tile/sprite id.
    and #$F0
    sta ppu_update_ptr_lo
    inx
    stx copy_src_hi
loc_C7E0:
    lda $0500,x                 ; Per-actor state flags.
    bpl loc_C7F9
    lsr a
    bcs loc_C7F9
    lda $0540,x                 ; Per-actor tile/sprite id.
    and #$F0
    cmp ppu_update_ptr_lo
    bne loc_C7F9
    inc sprite_index
    ldy sprite_index
    txa
    sta $6080,y
loc_C7F9:
    inx
    cpx #$10
    bne loc_C7E0
    lda sprite_index
    sec
    sbc #$04
    bpl loc_C811
    lda #$00
    sta sprite_index
loc_C809:
    inc copy_src_lo
    ldx copy_src_lo
    cpx #$0C
    bne loc_C7CB
loc_C811:
    ldx #$00
    stx $A2
loc_C815:
    lda $0500,x                 ; Per-actor state flags.
    bpl loc_C82F
    lsr a
    bcs loc_C82F
    ldy sprite_index
    beq loc_C82C
    txa
loc_C822:
    beq loc_C82C
    cmp $6080,y
    beq loc_C82F
    dey
    bpl loc_C822
loc_C82C:
    jsr update_oam_sprite
loc_C82F:
    inc $A2
    ldx $A2
    cpx #$10
    bne loc_C815
    lda sprite_index
    beq loc_C875
    sta ppu_update_ptr_hi
    ldy $8F
    ldx $6080,y
    cpx #$02
    bne loc_C848
    inc $8F
loc_C848:
    ldy $8F
    ldx $6080,y
    cpx #$FF
    bne loc_C857
    ldy #$00
    sty $8F
    beq loc_C848
loc_C857:
    lda #$FF
    sta $6080,y
    cpx #$00
    beq loc_C863
    jsr update_oam_sprite
loc_C863:
    ldy $8F
    inc $8F
    cpy sprite_index
    bne loc_C86F
    lda #$00
    sta $8F
loc_C86F:
    dec ppu_update_ptr_hi
    bpl loc_C848
    inc $8F
loc_C875:
    rts
; ----------------------------------------------------------------------
; update_oam_sprite
;   Update one actor's OAM entries.
;   called by: $C82C, $C860
; ----------------------------------------------------------------------
update_oam_sprite:
    lda $0500,x                 ; Per-actor state flags.
    and #$10
    beq loc_C87E
    rts
loc_C87E:
    lda $0540,x                 ; Per-actor tile/sprite id.
    sta copy_src_lo
    lda $0550,x                 ; Per-actor animation frame.
    sta copy_dst_hi
    lda $0510,x                 ; Per-actor state flags.
    tay
    lda data_C980,y
    sta copy_src_hi
    ldy $0530,x                 ; Per-actor palette/facing.
    lda data_C98C,y
    clc
    adc copy_src_hi
    sta copy_src_hi
    lda $0500,x                 ; Per-actor state flags.
    and #$04
    bne loc_C8BD
    lda menu_flags
    bne loc_C8BD
    inc $05A0,x                 ; Per-actor animation state.
    lda $05A0,x                 ; Per-actor animation state.
    and #$7F
    cmp #$20
    bcc loc_C8BD
    lda $05A0,x                 ; Per-actor animation state.
    eor #$80
    and #$80
    sta $05A0,x                 ; Per-actor animation state.
loc_C8BD:
    lda $05A0,x                 ; Per-actor animation state.
    bpl loc_C8C8
    lda copy_src_hi
    ora #$04
    sta copy_src_hi
loc_C8C8:
    lda $0500,x                 ; Per-actor state flags.
    lsr a
    bcc loc_C8D1
    jmp loc_C973
loc_C8D1:
    lda $0500,x                 ; Per-actor state flags.
    and #$40
    ora $0520,x                 ; Per-actor state flags.
    sta copy_dst_lo
    lda $05D0,x                 ; Per-actor status bits.
    sta ppu_update_off
    lda #$00
    sta ppu_update_ptr_lo
loc_C8E4:
    ldx oam_write_index
    bne loc_C8EB
    jmp loc_C973
loc_C8EB:
    lda ppu_update_ptr_lo
    asl a
    clc
    adc ppu_update_ptr_lo
    tay
    lda data_C974,y
    clc
    adc copy_src_lo
    sta copy_src_lo
    iny
    lda copy_dst_lo
    and #$40
    beq loc_C902
    iny
loc_C902:
    lda data_C974,y
    clc
    adc copy_dst_hi
    sta copy_dst_hi
    lda ppu_update_off
    and #$0C
    beq loc_C928
    and #$04
    beq loc_C920
    lda copy_src_lo
    and #$F0
    beq loc_C947
    cmp #$20
    bcc loc_C947
    bcs loc_C928
loc_C920:
    lda copy_src_lo
    and #$F0
    cmp #$C0
    bcs loc_C947
loc_C928:
    lda ppu_update_off
    and #$03
    beq loc_C94B
    lsr a
    bcc loc_C93D
    lda copy_dst_hi
    bmi loc_C94B
    and #$F0
    cmp #$30
    bcc loc_C947
    bcs loc_C94B
loc_C93D:
    lda copy_dst_hi
    bpl loc_C94B
    and #$F0
    cmp #$D0
    bcc loc_C94B
loc_C947:
    lda #$F8
    bne loc_C94D
loc_C94B:
    lda copy_src_lo
loc_C94D:
    sta $0200,x                 ; Sprite shadow copied to OAM by DMA.
    lda copy_src_hi
    sta $0201,x                 ; Sprite shadow copied to OAM by DMA.
    lda copy_dst_lo
    sta $0202,x                 ; Sprite shadow copied to OAM by DMA.
    lda copy_dst_hi
    sta $0203,x                 ; Sprite shadow copied to OAM by DMA.
    inc copy_src_hi
    lda oam_write_index
    clc
    adc #$04
    sta oam_write_index
    inc ppu_update_ptr_lo
    lda ppu_update_ptr_lo
    cmp #$04
    beq loc_C973
    jmp loc_C8E4
loc_C973:
    rts

data_C974:
    .incbin "build/assets/bank15_data.bin", $0974, $000C

data_C980:
    .incbin "build/assets/bank15_data.bin", $0980, $000C

data_C98C:
    .incbin "build/assets/bank15_data.bin", $098C, $0024
; ----------------------------------------------------------------------
; reset_text_engine
;   Clear the text engine and reset its cursor.
;   called by: $E5A9, $F110, $F23F, $F286
; ----------------------------------------------------------------------
reset_text_engine:
    ldx #$01
    jsr text_init
    jmp text_reset_cursor
; ----------------------------------------------------------------------
; text_init
;   Initialise text buffers, window tiles, and cursor state.
;   called by: $C9B2, $F1AD
; ----------------------------------------------------------------------
text_init:
    stx text_mode
    ldy #$17
    lda #$0A
loc_C9BE:
    sta $0348,y                 ; Saved text tile rows for window redraw.
    dey
    bpl loc_C9BE
    lda #$0E
    jsr set_bank_b
    lda text_busy
    bne loc_C9D3
    lda #$01
    sta menu_flags
    bne loc_C9D8
loc_C9D3:
    bpl loc_C9D8
    jmp loc_C0E2
loc_C9D8:
    lda data_EDA1,x
    sta $16
    lda data_EDD1,x
    sta $17
    ldx text_x
    ldy text_y
    lda input_buttons
    bpl loc_C9EE
    ldx #$07
    ldy #$00
loc_C9EE:
    stx cursor_x
    sty cursor_y
    ldx #$08
    lda text_busy
    beq loc_C9F9
    iny
loc_C9F9:
    lda input_buttons
    bmi loc_CA01
    ldx text_x2
    ldy text_y2
loc_CA01:
    stx cursor_x2
    sty cursor_y2
    ldy #$00
    sty text_line
    sty $54
    lda ($16),y
    tax
    asl a
    asl a
    asl a
    asl a
    clc
    adc #$6E
    ldy party_index
    bne loc_CA1C
    clc
    adc #$01
loc_CA1C:
    sta text_actor_id
    txa
    jsr cursor_add_x_signed
    ldy #$01
    lda ($16),y
    tax
    asl a
    asl a
    asl a
    asl a
    clc
    adc #$80
    sta text_target_id
    lda input_buttons
    and #$02
    beq loc_CA37
    inx
loc_CA37:
    txa
    jsr cursor_add_y_signed
    ldy #$02
    lda ($16),y
    sta text_speed_count
    iny
    sty text_col
    lda cursor_x2
    and #$01
    sta ppu_update_ptr_lo
    lda text_speed_count
    lsr a
    lsr a
    bcs loc_CA52
    adc ppu_update_ptr_lo
loc_CA52:
    adc #$00
    sta tile_id_base
loc_CA56:
    jsr wait_frame_tick
    jsr cursor_to_ppu
    jsr tile_address
    stx battle_cursor
    lda input_buttons
    bne loc_CABA
    ldx battle_cursor
    ldy #$00
loc_CA69:
    lda cursor_x
    lsr a
    bcs loc_CA72
    lda #$0F
    bne loc_CA74
loc_CA72:
    lda #$F0
loc_CA74:
    sta ppu_update_ptr_lo
    tya
    bne loc_CA86
    lda cursor_x2
    lsr a
    bcc loc_CAA2
    lda ppu_update_ptr_lo
    and #$CC
    sta ppu_update_ptr_lo
    bne loc_CAA2
loc_CA86:
    clc
    adc #$01
    cmp tile_id_base
    bne loc_CAA2
    lda cursor_x2
    and #$01
    sta ppu_update_ptr_hi
    lda text_speed_count
    lsr a
    and #$01
    eor ppu_update_ptr_hi
    beq loc_CAA2
    lda ppu_update_ptr_lo
    and #$33
    sta ppu_update_ptr_lo
loc_CAA2:
    lda $0780,x
    ora ppu_update_ptr_lo
    sta $0780,x
    inx
    txa
    and #$0F
    bne loc_CAB5
    txa
    sec
    sbc #$10
    tax
loc_CAB5:
    iny
    cpy tile_id_base
    bne loc_CA69
loc_CABA:
    ldy text_col
    lda ($16),y
    cmp #$FE
    bcc loc_CAC5
    jmp loc_CB4E
loc_CAC5:
    lda $54
    bne loc_CB06
    ldx #$17
    lda #$0A
loc_CACD:
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    dex
    bpl loc_CACD
    ldx #$00
loc_CAD5:
    ldy text_col
    inc text_col
    lda ($16),y
    cmp #$FA
    bcs loc_CAE5
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    bne loc_CAD5
loc_CAE5:
    bne loc_CAE9
    inc $5F
loc_CAE9:
    txa
    bne loc_CB06
    ldy text_speed_count
    dey
    dey
    lda #$6D
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
loc_CAF6:
    lda #$0C
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    dey
    bne loc_CAF6
    lda #$6E
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    ldx #$01
loc_CB06:
    lda input_buttons
    and #$20
    beq loc_CB14
    lda #$04
    jsr text_input
    jmp loc_CB1B
loc_CB14:
    lda text_line
    eor #$01
    jsr text_input
loc_CB1B:
    jsr scroll_map
    jsr text_find_line
    lda $54
    ldx text_speed_count
    cpx #$0D
    bcs loc_CB3B
    cpx #$09
    bcs loc_CB38
    sec
loc_CB2E:
    sbc #$03
    bcs loc_CB2E
    cmp #$FF
    beq loc_CB3B
    bne loc_CB3E
loc_CB38:
    lsr a
    bcc loc_CB3E
loc_CB3B:
    jsr update_frame_no_input
loc_CB3E:
    lda text_line
    eor #$01
    sta text_line
    inc $54
    lda #$01
    jsr cursor_add_x_signed
    jmp loc_CA56
loc_CB4E:
    ldx text_speed_count
    dex
    dex
    stx ppu_update_ptr_lo
    ldx text_line
    lda data_CB90,x
    tax
    lda input_buttons
    lsr a
    bcc loc_CB6C
    ldy #$18
    lda #$0A
loc_CB63:
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    inx
    dey
    bne loc_CB63
    beq loc_CB80
loc_CB6C:
    lda #$0B
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    lda #$0D
loc_CB73:
    inx
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    dec ppu_update_ptr_lo
    bne loc_CB73
    lda #$6F
    sta $0301,x                 ; Top 8x8 tiles for the four text lines.
loc_CB80:
    jsr scroll_map
    jsr text_find_line
    lda #$00
    sta text_col
    jsr set_bank_current
    jmp update_frame_no_input

data_CB90:
    .incbin "build/assets/bank15_data.bin", $0B90, $0002
; ----------------------------------------------------------------------
; text_input
;   Handle text-menu input and cursor movement.
;   called by: $CB0E, $CB18
; ----------------------------------------------------------------------
text_input:
    tay
    ldx data_CC14,y
    stx ppu_update_ptr_hi
    ldy text_speed_count
    lda input_buttons
    lsr a
    bcc loc_CBB0
    lda #$0A
loc_CBA1:
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    dey
    bne loc_CBA1
    ldx ppu_update_ptr_hi
    jmp loc_CBD1
loc_CBB0:
    dey
    dey
    lda #$7D
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    lda #$0A
loc_CBBC:
    inx
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    dey
    bne loc_CBBC
    lda #$7E
    sta $0301,x                 ; Top 8x8 tiles for the four text lines.
    sta $0319,x                 ; Bottom 8x8 tiles for the four text lines.
    ldx ppu_update_ptr_hi
    inx
loc_CBD1:
    lda $5F
    beq loc_CBD8
    inx
    dec $5F
loc_CBD8:
    lda #$0E
    jsr set_bank_b
    ldy text_col
    lda ($16),y
    cmp #$F8
    bne loc_CBFE
    iny
    lda ($16),y
    sta ppu_update_ptr_lo
    iny
    lda ($16),y
    sta ppu_update_ptr_hi
    iny
    sty text_col
    jsr set_bank_current
    lda #$CB
    pha
    lda #$D7
    pha
    jmp ($00F3)
loc_CBFE:
    cmp #$FA
    bcs loc_CC09
    jsr text_put_tile
    inc text_col
    bne loc_CBD8
loc_CC09:
    bne loc_CC0D
    inc $5F
loc_CC0D:
    cmp #$FD
    bcs loc_CC13
    inc text_col
loc_CC13:
    rts

data_CC14:
    .incbin "build/assets/bank15_data.bin", $0C14, $0005
; ----------------------------------------------------------------------
; read_stack_arg
;   Read a byte from the caller's stack frame.
; ----------------------------------------------------------------------
read_stack_arg:
    sta ppu_update_ptr_lo
    sty ppu_update_off
    lda #$06
    sec
    sbc ppu_update_ptr_lo
    tay
    lda #$00
    sta ppu_update_ptr_hi
loc_CC27:
    lda $0104,y
    bne loc_CC3C
    inc ppu_update_ptr_lo
    dec ppu_update_ptr_lo
    beq loc_CC3E
    inc ppu_update_ptr_hi
    dec ppu_update_ptr_hi
    bne loc_CC3E
    lda #$0A
    bne loc_CC3E
loc_CC3C:
    inc ppu_update_ptr_hi
loc_CC3E:
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    iny
    dec ppu_update_ptr_lo
    bpl loc_CC27
    ldy ppu_update_off
    rts
; ----------------------------------------------------------------------
; text_find_line
;   Find the text line/actor matching the current selection.
;   called by: $CB1E, $CB83
; ----------------------------------------------------------------------
text_find_line:
    ldx #$0F
loc_CC4C:
    lda $0540,x                 ; Per-actor tile/sprite id.
    cmp text_actor_id
    bne loc_CC76
    lda text_target_id
    sta ppu_update_ptr_lo
    lda text_speed_count
    lsr a
    tay
loc_CC5B:
    lda $0550,x                 ; Per-actor animation frame.
    cmp ppu_update_ptr_lo
    beq loc_CC6E
    lda ppu_update_ptr_lo
    clc
    adc #$10
    sta ppu_update_ptr_lo
    dey
    bne loc_CC5B
    beq loc_CC76
loc_CC6E:
    lda $0500,x                 ; Per-actor state flags.
    ora #$10
    sta $0500,x                 ; Per-actor state flags.
loc_CC76:
    dex
    bpl loc_CC4C
    lda text_actor_id
    clc
    adc #$10
    sta text_actor_id
    rts
; ----------------------------------------------------------------------
; text_hide
;   Hide the text cursor and restore the underlying tiles.
;   called by: $CF4A
; ----------------------------------------------------------------------
text_hide:
    ldx #$0F
loc_CC83:
    lda $0500,x                 ; Per-actor state flags.
    and #$EF
    sta $0500,x                 ; Per-actor state flags.
    dex
    bpl loc_CC83
    lda #$00
    sta menu_flags
    jmp set_bank_current
; ----------------------------------------------------------------------
; text_cursor_init
;   Initialise the text cursor position.
;   called by: $CD3E
; ----------------------------------------------------------------------
text_cursor_init:
    lda #$00
    sta cursor_blink
    ldy #$0A
    bne loc_CCA9
loc_CC9D:
    lda cursor_blink
    inc cursor_blink
    ldy #$0A
    and #$10
    bne loc_CCA9
; ----------------------------------------------------------------------
; text_draw_cursor
;   Draw/update the blinking text cursor.
;   called by: $CDD7
; ----------------------------------------------------------------------
text_draw_cursor:
    ldy #$70
loc_CCA9:
    tya
    pha
    ldx text_x
    ldy text_y
    lda input_buttons
    bpl loc_CCB7
    ldx #$07
    ldy #$00
loc_CCB7:
    stx cursor_x
    sty cursor_y
    ldx #$08
    lda text_busy
    beq loc_CCC2
    iny
loc_CCC2:
    lda input_buttons
    bmi loc_CCCA
    ldx text_x2
    ldy text_y2
loc_CCCA:
    stx cursor_x2
    sty cursor_y2
    ldy #$00
    lda ($16),y
    sec
    adc text_menu_index
    jsr cursor_add_x_signed
    ldy #$01
    lda ($16),y
    jsr cursor_add_y_signed
    jsr cursor_to_ppu
    inc ppu_addr_lo_shadow
loc_CCE4:
    ldx vram_queue_write
    lda ppu_addr_hi_shadow
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_addr_lo_shadow
    ldy text_menu_sub
    beq loc_CCFD
    clc
    adc #$09
    ldy text_busy
    cpy #$40
    bne loc_CCFD
    sbc #$03
loc_CCFD:
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$01
    sta $0400,x                 ; VRAM update command queue.
    inx
    pla
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    rts
; ----------------------------------------------------------------------
; clear_text_state
;   Clear the text-menu selection variables.
;   called by: $CDB3, $F1B0
; ----------------------------------------------------------------------
clear_text_state:
    lda #$00
    sta text_menu_index
    sta text_menu_sub
    sta cursor_blink
    sta text_scroll_pos
    rts
; ----------------------------------------------------------------------
; text_scroll
;   Scroll the text window by one row.
;   called by: $CDBB
; ----------------------------------------------------------------------
text_scroll:
    lda controller_prev
    and #$0F
    beq loc_CD87
    tax
    and #$03
    beq loc_CD2E
    lda battle_anim
    beq loc_CD87
loc_CD2E:
    lda text_scroll_pos
    clc
    adc #$10
    sta text_scroll_pos
    bne loc_CD8B
    lda #$09
    jsr sound_queue_add
    txa
    pha
    jsr text_cursor_init
    pla
    tax
    and #$0C
    bne loc_CD52
    txa
    and #$03
    eor #$03
    lsr a
    sta text_menu_sub
    jmp loc_CD8E
loc_CD52:
    eor #$0C
    lsr a
    sec
    sbc #$03
    clc
    adc text_menu_index
    bpl loc_CD6C
    lda battle_anim
    beq loc_CD67
    lsr a
    sta text_menu_index
    jmp loc_CD8E
loc_CD67:
    lda $54
    sec
    sbc #$01
loc_CD6C:
    cmp $54
    bne loc_CD72
    lda #$00
loc_CD72:
    sta text_menu_index
    ldx battle_anim
    beq loc_CD8B
    asl a
    adc text_menu_sub
    cmp battle_anim
    beq loc_CD8B
    bcc loc_CD8B
    lda #$00
    sta text_menu_index
    beq loc_CD8B
loc_CD87:
    lda #$F0
    sta text_scroll_pos
loc_CD8B:
    jmp loc_CC9D
loc_CD8E:
    lda text_menu_index
    asl a
    adc text_menu_sub
    cmp battle_anim
    beq loc_CD8B
    bcc loc_CD8B
    dec text_menu_index
    bpl loc_CD8B
; ----------------------------------------------------------------------
; text_wait
;   Wait for text input and update the cursor.
;   called by: $F1B3
; ----------------------------------------------------------------------
text_wait:
    jsr text_wait_loop
    bcs loc_CDA3
    rts
loc_CDA3:
    pla
    pla
    jmp game_main

data_CDA8:
    .incbin "build/assets/bank15_data.bin", $0DA8, $000B
; ----------------------------------------------------------------------
; text_wait_loop
;   Main text input/wait loop.
;   called by: $CD9D
; ----------------------------------------------------------------------
text_wait_loop:
    jsr clear_text_state
loc_CDB6:
    lda #$0E
    jsr set_bank_b
    jsr text_scroll
    jsr update_frame
    lda controller_state
    and #$80
    bne loc_CDD0
    lda controller_state
    and #$40
    beq loc_CDB6
    sec
    bcs loc_CDD6
loc_CDD0:
    lda #$0A
    jsr sound_queue_add
    clc
loc_CDD6:
    php
    jsr text_draw_cursor
    jsr set_bank_current
    plp
    rts
; ----------------------------------------------------------------------
; text_draw_screen
;   Redraw the current text screen.
;   called by: $E5DC, $F11B, $F1D0, $F24A, $F291, $F2EE
; ----------------------------------------------------------------------
text_draw_screen:
    inc text_y
    lda game_mode
    pha
    lda #$00
    sta game_mode
    lda #$0F
loc_CDEA:
    pha
    jsr wait_frame_tick
    jsr draw_party_header
    jsr draw_party_status
    jsr draw_party_window
    lda ppu_addr_lo_shadow
    clc
    adc #$21
    sta ppu_addr_lo_shadow
    lda #$00
    sta tile_attr
    ldy #$25
    ldx #$1F
    jsr draw_tile_run
    jsr draw_party_footer
    lda ppu_addr_lo_shadow
    clc
    adc #$E0
    sta ppu_addr_lo_shadow
    lda #$00
    sta tile_attr
    ldy #$01
    ldx #$1F
    jsr draw_tile_run
    jsr wait_vblank
    pla
    sec
    sbc #$01
    bne loc_CDEA
    pla
    sta game_mode
    jmp text_hide

data_CE2D:
    .incbin "build/assets/bank15_data.bin", $0E2D, $00A5

; ----------------------------------------------------------------------
; battle_intro_screen
;   Battle introduction screen: window, fade, and clear.
; ----------------------------------------------------------------------
battle_intro_screen:
    ldy #$03
    jsr draw_window
    jsr wait_vblank
    lda #$80
    sta input_buttons
    inc $AA
    lda #$90
    sta ppu_ctrl_shadow
    jsr screen_fade_in
    jsr clear_screen
    lda #$09
    jsr set_bank_b
    ldy #$10
    lda #$08
    ldx #$10
    jsr copy_to_vram

data_CEF8:
    .incbin "build/assets/bank15_data.bin", $0EF8, $0002
    ldy #$1E
    lda #$00
    ldx #$1F
    jsr copy_to_vram

data_CF03:
    .incbin "build/assets/bank15_data.bin", $0F03, $0002
    jsr set_bank_current
    lda #$00
    sta nmi_busy
    jsr ppu_nmi_on
    lda #$08
    sta text_graphics_index
    jsr load_text_graphics
    jmp wait_vblank

data_CF19:
    .incbin "build/assets/bank15_data.bin", $0F19, $0006
; ----------------------------------------------------------------------
; screen_refresh
;   Refresh the whole screen: palette, window, text, sprites.
;   called by: $F106
; ----------------------------------------------------------------------
screen_refresh:
    jsr screen_fade_in
    jsr load_battle_palette
    jsr draw_battle_panel
    jsr set_bank_current
    lda game_mode
    pha
    jsr render_map_column
    pla
    sta game_mode
    jsr set_scroll_from_cursor
    jsr draw_text_window
    jsr screen_fade_out
    lda #$00
    sta input_buttons
    sta $AA
    lda level
    sta text_graphics_index
    jsr load_text_graphics
    jsr text_hide
    ldy #$03
    jsr draw_text_window_small
    lda #$00
    sta menu_flags
    sta $71
    jmp update_frame_no_input
; ----------------------------------------------------------------------
; text_save_tiles
;   Save the current text tile rows for redraw.
;   called by: $D19F, $D1F7
; ----------------------------------------------------------------------
text_save_tiles:
    ldy #$5F
loc_CF5D:
    lda $0300,y                 ; Top 8x8 tiles for the four text lines.
    sta $0180,y
    dey
    bpl loc_CF5D
    lda text_line
    sta text_saved_line
    ldy #$03
loc_CF6C:
    lda cursor_x,y
    sta a:$0039,y
    dey
    bpl loc_CF6C
    rts

data_CF76:
    .incbin "build/assets/bank15_data.bin", $0F76, $001B
; ----------------------------------------------------------------------
; status_message
;   Draw a status message and load the matching text page.
; ----------------------------------------------------------------------
status_message:
    jsr draw_string             ; inline pointer/data follows the JSR

data_CF94:
    .incbin "build/assets/bank15_data.bin", $0F94, $0002
    ldy text_actor
    lda $60A8,y                 ; Party member class/officer id.
    jsr text_load_page
    jmp loc_C139

data_CFA1:
    .incbin "build/assets/bank15_data.bin", $0FA1, $0008
; ----------------------------------------------------------------------
; text_load_page
;   Load a text page/graphics set from bank 12.
;   called by: $CF9B
; ----------------------------------------------------------------------
text_load_page:
    tay
    lda #$0C
    jsr set_bank_b
    lda b12_data_A800,y
    sta ppu_update_ptr_lo
    lda b12_data_A900,y
    sta ppu_update_ptr_hi
    ldy #$0A
    sty ppu_update_off
    lda loop_counter
    asl a
    tax
    lda data_D107,x
    sta cursor_y2
    inx
    lda data_D107,x
    sta cursor_x2
    lda ($F3),y
loc_CFCE:
    lda #$02
    sta ppu_update_len
    lda ($F3),y
    bpl loc_CFDA
    eor #$80
    inc ppu_update_len
loc_CFDA:
    sta ppu_addr_hi
    lda #$00
    sta ptr0_hi
    lda #$60
    sta ptr1_lo
    sta ptr0_lo
    jsr rng_seed
    lda ppu_update_len
    jsr set_bank_b
    lda #$00
    clc
    adc ptr0_lo
    sta cursor_x
    lda #$88
    adc ptr0_hi
    sta cursor_y
    lda ppu_update_len
    jsr set_bank_b
    ldx vram_queue_write
    lda cursor_y2
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda cursor_x2
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$60
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda battle_flags
    beq loc_D01E
    jsr text_draw_page
    jmp loc_D032
loc_D01E:
    ldy #$00
loc_D020:
    lda ($1C),y
    sta $0400,x                 ; VRAM update command queue.
    iny
    inx
    cpy #$60
    bne loc_D020
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
loc_D032:
    jsr set_bank_current
    jsr wait_vblank
    lda cursor_x2
    clc
    adc #$60
    sta cursor_x2
    lda cursor_y2
    adc #$00
    sta cursor_y2
    lda #$0C
    jsr set_bank_b
    inc ppu_update_off
    ldy ppu_update_off
    cpy #$10
    beq loc_D055
    jmp loc_CFCE
loc_D055:
    lda ($F3),y
    and #$0F
    beq loc_D06F
    tax
    lda #$37
    sta $03ED                   ; Small VRAM upload buffer.
    lda #$26
    sta $03EE                   ; Small VRAM upload buffer.
    lda data_D0FD,x
    sta $03EF                   ; Small VRAM upload buffer.
    jmp loc_D07A
loc_D06F:
    lda #$0F
    sta $03ED                   ; Small VRAM upload buffer.
    sta $03EE                   ; Small VRAM upload buffer.
    sta $03EF                   ; Small VRAM upload buffer.
loc_D07A:
    lda #$01
    sta vram_dma_pending
    jsr wait_vblank
    jmp set_bank_current
; ----------------------------------------------------------------------
; text_draw_page
;   Draw the loaded text page.
;   called by: $D018
; ----------------------------------------------------------------------
text_draw_page:
    lda vram_queue_write
    clc
    adc #$53
    tax
    ldy #$00
loc_D08C:
    lda #$08
    sta ppu_update_len
    lda ($1C),y
loc_D092:
    lsr a
    rol copy_dst_hi
    dec ppu_update_len
    bne loc_D092
    lda copy_dst_hi
    sta $0400,x                 ; VRAM update command queue.
    inx
    iny
    tya
    and #$0F
    bne loc_D08C
    txa
    sec
    sbc #$20
    tax
    cpy #$60
    bne loc_D08C
    lda vram_queue_write
    clc
    adc #$63
    sta vram_queue_write
    tax
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    rts

data_D0BC:
    .incbin "build/assets/bank15_data.bin", $10BC, $0041

data_D0FD:
    .incbin "build/assets/bank15_data.bin", $10FD, $000A

data_D107:
    .incbin "build/assets/bank15_data.bin", $1107, $0006

; ----------------------------------------------------------------------
; text_print_inline
;   Print the inline message reference that follows the JSR.
;   The first word is a 16-bit message-table index (< $200: bank 10,
;   >= $200: bank 11 with $200 subtracted), not a direct address.
;   called by: $E5AF, $E5BC, $F113, $F12D, $F242, $F289
; ----------------------------------------------------------------------
text_print_inline:
    jsr fetch_inline_word       ; Fetch the inline word after the JSR.; inline pointer/data follows the JSR
data_D110:
    lda $00
    sta ppu_addr_lo
    lda $01
    sta ppu_addr_hi
    jmp text_show_message
; ----------------------------------------------------------------------
; text_reset_cursor
;   Reset text cursor/line/speed state.
;   called by: $E5AC
; ----------------------------------------------------------------------
text_reset_cursor:
    ldx #$00
    stx text_line
    stx text_speed_count
    stx text_col
loc_D123:
    rts
; ----------------------------------------------------------------------
; text_show_message
;   Open a text window and run the message bytecode interpreter.
;   Input: $14/$15 = 16-bit message-table index.  The split low/high
;   tables in bank 10 or 11 turn it into the actual message address.
; ----------------------------------------------------------------------
text_show_message:
    lda text_busy
    bmi loc_D123
    lda #$0A
    sta text_window_x
    lda ppu_addr_hi
    sec
    sbc #$02
    bcc loc_D137
    sta ppu_addr_hi
    inc text_window_x
loc_D137:
    lda text_window_x
    jsr set_bank_b
    ldy #$00
    lda #$00
    clc
    adc ppu_addr_lo
    sta ppu_update_ptr_lo
    lda #$80
    adc ppu_addr_hi
    sta ppu_update_ptr_hi
    lda ($F3),y
    sta text_ptr_lo
    lda #$00
    clc
    adc ppu_addr_lo
    sta ppu_update_ptr_lo
    lda #$82
    adc ppu_addr_hi
    sta ppu_update_ptr_hi
    lda ($F3),y
    sta text_ptr_hi
loc_D160:
    jsr text_set_cursor         ; Message bytecode fetch/dispatch loop.
    lda #$02
    clc
    adc text_line
    jsr cursor_add_x_signed
    lda #$F9
    jsr cursor_add_y_signed
    jsr cursor_to_ppu
    lda ppu_addr_lo_shadow
    clc
    adc #$21
    sta ppu_addr_lo_shadow
    ldy text_col
    lda ($51),y
    cmp #$F9
    bne loc_D1A5
    iny
    lda ($51),y
    sta ppu_update_ptr_lo
    iny
    lda ($51),y
    bmi loc_D196
    ora #$80
    sta ppu_update_ptr_hi
    jsr set_bank_13
    jmp loc_D19B
loc_D196:
    sta ppu_update_ptr_hi
    jsr set_bank_14
loc_D19B:
    lda #$00
    sta text_col
    jsr text_save_tiles
    jmp ($00F3)
loc_D1A5:
    jsr text_clear_line         ; Clear the line before drawing the next cell.
    jsr text_render_cell
    inc text_col
    inc text_line
    cmp #$FE
    bcs loc_D1CE
    pha
    lda text_line
    cmp #$04
    bne loc_D1BD
    jsr text_scroll_up
loc_D1BD:
    pla
    cmp #$FD
    beq loc_D1C8
    cmp #$FC
    bne loc_D1CB
    inc $5F
loc_D1C8:
    jsr text_draw_char
loc_D1CB:
    jmp loc_D160
loc_D1CE:
    beq loc_D1E1
    lda input_buttons
    and #$10
    bne loc_D1E1
    lda text_line
    cmp #$04
    bne loc_D1E1
    dec text_line
    jsr text_scroll_up
loc_D1E1:
    lda input_buttons
    and #$10
    beq loc_D1F3
    ldx text_speed
    inx
    txa
    asl a
    asl a
    asl a
    asl a
    tax
    jsr wait_frames
loc_D1F3:
    lda #$00
    sta text_col
    jsr text_save_tiles
    jmp set_bank_current
; ----------------------------------------------------------------------
; text_set_cursor
;   Set the PPU cursor address from the text cursor variables.
;   called by: $D160, $D38E, $D456
; ----------------------------------------------------------------------
text_set_cursor:
    ldx text_x
    ldy text_y
    lda input_buttons
    bpl loc_D209
    ldx #$07
    ldy #$00
loc_D209:
    stx cursor_x
    sty cursor_y
    ldx #$08
    lda text_busy
    beq loc_D214
    iny
loc_D214:
    lda input_buttons
    bmi loc_D21C
    ldx text_x2
    ldy text_y2
loc_D21C:
    and #$0C
    beq loc_D224
    lsr a
    adc #$08
    tax
loc_D224:
    stx cursor_x2
    sty cursor_y2
    rts
; ----------------------------------------------------------------------
; text_clear_line
;   Clear one 24-column text line in the tile buffers.
;   called by: $D1A5
; ----------------------------------------------------------------------
text_clear_line:
    ldy text_line
    ldx data_D2CB,y
    stx ppu_update_ptr_hi
    lda #$7D
    sta $02FF,x                 ; Sprite shadow copied to OAM by DMA.
    sta $0317,x                 ; Top 8x8 tiles for the four text lines.
    lda #$7E
    sta $0312,x                 ; Top 8x8 tiles for the four text lines.
    sta $032A,x                 ; Bottom 8x8 tiles for the four text lines.
    ldy #$12
loc_D242:
    lda #$0A
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    dey
    bne loc_D242
    ldx ppu_update_ptr_hi
loc_D250:
    lda $5F
    beq loc_D257
    inx
    dec $5F
loc_D257:
    ldy text_col
    lda ($51),y
    cmp #$F8
    bne loc_D28E
    lda #$D2
    pha
    lda #$85
    pha
    iny
    lda ($51),y
    sta ppu_update_ptr_lo
    iny
    lda ($51),y
    bmi loc_D27B
    ora #$80
    sta ppu_update_ptr_hi
    lda #$0D
    jsr set_bank_a
    jmp loc_D280
loc_D27B:
    sta ppu_update_ptr_hi
    jsr set_bank_current
loc_D280:
    iny
    sty text_col
    jmp ($00F3)
    lda text_window_x
    jsr set_bank_b
    jmp loc_D250
loc_D28E:
    bcs loc_D2B7
    cmp #$EF
    bcc loc_D2B7
    sbc #$EF
    tay
    inc text_col
    lda #$D2
    pha
    lda #$85
    pha
    txa
    pha
    tya
    jsr dispatch_return_table

data_D2A5:
    .incbin "build/assets/bank15_data.bin", $12A5, $0012
loc_D2B7:
    cmp #$FA
    bcs loc_D2C3
    jsr text_put_tile
    inc text_col
    jmp loc_D250
loc_D2C3:
    bne loc_D2C7
    inc $5F
loc_D2C7:
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    rts

data_D2CB:
    .incbin "build/assets/bank15_data.bin", $12CB, $003F
    pla
    tax
    ldy text_col
    lda ($51),y
    tay
    inc text_col
    lda #$0D
    jsr set_bank_b
    lda b13_data_B700,y
    sta ppu_update_ptr_lo
    lda b13_data_B800,y
    sta ppu_update_ptr_hi
    ldy #$00
loc_D324:
    lda ($F3),y
    cmp #$FF
    beq loc_D331
    iny
    jsr text_put_tile
    jmp loc_D324
loc_D331:
    jmp set_bank_current

data_D334:
    .incbin "build/assets/bank15_data.bin", $1334, $000C
; ----------------------------------------------------------------------
; text_put_tile
;   Write the top/bottom tile pair for one character into the tile buffers.
;   called by: $CC02, $D2BB, $D32B, $D4C0, $D57D, $D582, $D5C0
; ----------------------------------------------------------------------
text_put_tile:
    pha
    asl a
    bcc loc_D351
    cmp #$C4
    bcs loc_D34C
    lda #$72
    bcc loc_D34E
loc_D34C:
    lda #$73
loc_D34E:
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
loc_D351:
    pla
    and #$7F
    bcc loc_D358
    sbc #$0A
loc_D358:
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    rts
; ----------------------------------------------------------------------
; text_put_char_shadow
;   Queue the bottom/alternate tile for the current text character.
;   called by: $D482
; ----------------------------------------------------------------------
text_put_char_shadow:
    lda #$00
    sta cursor_blink
    ldy #$0A
    bne loc_D371
; ----------------------------------------------------------------------
; text_put_char_cursor
;   Queue the cursor/underline tile for the current text character.
;   called by: $D474
; ----------------------------------------------------------------------
text_put_char_cursor:
    lda cursor_blink
    inc cursor_blink
    ldy #$0A
    and #$10
    bne loc_D371
; ----------------------------------------------------------------------
; text_put_char
;   Queue the top tile for the current text character.
;   called by: $D46B
; ----------------------------------------------------------------------
text_put_char:
    ldy #$71
loc_D371:
    tya
    pha
    jmp loc_CCE4
; ----------------------------------------------------------------------
; text_scroll_up
;   Scroll the four dialogue lines up by one line.
;   called by: $D1BA, $D1DE
; ----------------------------------------------------------------------
text_scroll_up:
    lda #$02
loc_D378:
    pha
    lda #$08
    sta text_line
    ldy #$13
loc_D37F:
    lda data_D3F1,y
    sta $03C0,y                 ; Text line shadow buffer.
    dey
    bpl loc_D37F
    jsr text_redraw_lines
loc_D38B:
    jsr wait_frame_tick
    jsr text_set_cursor
    ldx text_line
    lda data_D3DF,x
    jsr cursor_add_x_signed
    lda #$F9
    jsr cursor_add_y_signed
    jsr cursor_to_ppu
    lda ppu_addr_lo_shadow
    clc
    ldx text_line
    adc data_D3E8,x
    sta ppu_addr_lo_shadow
    lda #$14
    sta text_speed_count
    jsr text_draw_line
    inc text_line
    lda text_line
    cmp #$09
    bne loc_D3C3
    jsr update_frame_no_input
    lda #$00
    sta text_line
    beq loc_D38B
loc_D3C3:
    cmp #$04
    bne loc_D3CD
    jsr update_frame_no_input
    jmp loc_D38B
loc_D3CD:
    cmp #$08
    bne loc_D38B
    jsr update_frame_no_input
    pla
    sec
    sbc #$01
    bne loc_D378
    lda #$03
    sta text_line
    rts

data_D3DF:
    .incbin "build/assets/bank15_data.bin", $13DF, $0009

data_D3E8:
    .incbin "build/assets/bank15_data.bin", $13E8, $0009

data_D3F1:
    .incbin "build/assets/bank15_data.bin", $13F1, $000F

data_D400:
    .incbin "build/assets/bank15_data.bin", $1400, $0005
; ----------------------------------------------------------------------
; text_redraw_lines
;   Redraw all four text lines from the tile buffers.
;   called by: $D388
; ----------------------------------------------------------------------
text_redraw_lines:
    lda #$00
    sta ppu_update_ptr_hi
loc_D409:
    lda ppu_update_ptr_hi
    asl a
    asl a
    asl a
    sta ppu_update_ptr_lo
    asl a
    adc ppu_update_ptr_lo
    tax
    ldy #$12
loc_D416:
    lda ppu_update_ptr_hi
    cmp #$07
    bne loc_D420
    lda #$0A
    bne loc_D427
loc_D420:
    lda $0319,x                 ; Bottom 8x8 tiles for the four text lines.
    bpl loc_D427
    lda #$0A
loc_D427:
    sta $0301,x                 ; Top 8x8 tiles for the four text lines.
    inx
    dey
    bne loc_D416
    lda #$7E
    sta $0301,x                 ; Top 8x8 tiles for the four text lines.
    inc ppu_update_ptr_hi
    lda ppu_update_ptr_hi
    cmp #$08
    bne loc_D409
    rts
; ----------------------------------------------------------------------
; wait_then_game_main
;   Wait for a keypress, then resume the main gameplay loop.
; ----------------------------------------------------------------------
wait_then_game_main:
    jsr wait_keypress
    jmp game_main
; ----------------------------------------------------------------------
; wait_keypress
;   Wait until a button edge is detected.
;   called by: $D43C, $E5C4, $E5D9, $F118, $F247, $F28E
; ----------------------------------------------------------------------
wait_keypress:
    jsr update_frame
    lda controller_state
    and #$CF
    beq wait_keypress
    rts
loc_D44C:
    jsr update_frame
    lda controller_state
    and #$C0
    beq loc_D44C
    rts
; ----------------------------------------------------------------------
; text_draw_char
;   Render one 8x16 character and advance the text cursor.
;   called by: $D1C8, $E5B9
; ----------------------------------------------------------------------
text_draw_char:
    jsr text_set_cursor
    lda #$03
    clc
    adc text_line
    jsr cursor_add_x_signed
    lda #$FD
    jsr cursor_add_y_signed
    jsr cursor_to_ppu
    inc ppu_addr_lo_shadow
    jsr text_put_char
loc_D46E:
    lda controller_prev
    and #$C0
    bne loc_D47D
    jsr text_put_char_cursor
    jsr update_frame
    jmp loc_D46E
loc_D47D:
    lda #$0A
    jsr sound_queue_add
    jsr text_put_char_shadow
    lda #$0A
loc_D487:
    pha
    jsr update_frame
    pla
    sec
    sbc #$01
    bne loc_D487
    lda #$03
    jmp cursor_add_y_signed

data_D496:
    .incbin "build/assets/bank15_data.bin", $1496, $0009
    ldy text_actor
; ----------------------------------------------------------------------
; load_party_member_stats
;   Load a party member's class/stat record from bank 12.
; ----------------------------------------------------------------------
load_party_member_stats:
    lda $60A8,y                 ; Party member class/officer id.
    tay
    lda #$0C
    jsr set_bank_b
    lda b12_data_A800,y
    sta ppu_update_ptr_lo
    lda b12_data_A900,y
    sta ppu_update_ptr_hi
    lda $AA
    bne loc_D4C9
    ldy #$14
loc_D4BA:
    lda ($F3),y
    cmp #$FE
    bcs loc_D4C6
    jsr text_put_tile
    iny
    bne loc_D4BA
loc_D4C6:
    jmp set_bank_current
loc_D4C9:
    ldy #$10
    lda ($F3),y
    sta ppu_update_len
    iny
loc_D4D0:
    lda #$01
    sta ppu_update_off
    lda #$0C
    jsr set_bank_b
    cpy #$14
    beq loc_D4C6
    lda #$00
    sta $3A
    sta $3C
    lda ($F3),y
    cmp #$FF
    beq loc_D4C6
    asl a
    rol $3A
    asl a
    rol $3A
    asl a
    rol $3A
    asl a
    rol $3A
    asl a
    rol $3A
    sta $39
    lda $3A
    ora #$80
    sta $3A
    lda $A9
    asl a
    rol $3C
    asl a
    rol $3C
    asl a
    rol $3C
    asl a
    rol $3C
    ora #$08
    sta $3B
    lda $3C
    ora #$10
    sta $3C
    asl ppu_update_len
    bcc loc_D51E
    inc ppu_update_off
loc_D51E:
    lda ppu_update_off
    jsr set_bank_b
    lda #$01
    sta palette_dirty
    jsr wait_vblank
    lda $A9
    clc
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    adc #$01
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    inx
    adc #$01
    sta $0300,x                 ; Top 8x8 tiles for the four text lines.
    adc #$01
    sta $0318,x                 ; Bottom 8x8 tiles for the four text lines.
    adc #$01
    inx
    sta $A9
    iny
    jmp loc_D4D0

data_D549:
    .incbin "build/assets/bank15_data.bin", $1549, $001E
; ----------------------------------------------------------------------
; draw_item_name
;   Draw an item/equipment name from the bank 12 text tables.
; ----------------------------------------------------------------------
draw_item_name:
    lda #$0C
    jsr set_bank_b
    lda b12_data_A700,y
    sta ppu_update_ptr_lo
    lda b12_data_A720,y
    sta ppu_update_ptr_hi
    ldy #$00
    jsr draw_string_from_pointer
    lda #$23
    jsr text_put_tile
    lda #$13
    jsr text_put_tile
    lda #$3E
    jmp text_put_tile

data_D58A:
    .incbin "build/assets/bank15_data.bin", $158A, $001B
; ----------------------------------------------------------------------
; load_item_data
;   Load item/equipment data from bank 12.
; ----------------------------------------------------------------------
load_item_data:
    lda #$0C
    jsr set_bank_b
    tya
    and #$7F
    tay
    lda b12_data_A3C8,y
    sta ppu_update_ptr_lo
    lda b12_data_A438,y
    sta ppu_update_ptr_hi
    ldy #$02
; ----------------------------------------------------------------------
; draw_string_from_pointer
;   Draw a FF-terminated string through the current pointer.
;   called by: $D578
; ----------------------------------------------------------------------
draw_string_from_pointer:
    lda ($F3),y
    cmp #$FF
    beq loc_D5C6
    jsr text_put_tile
    iny
    bne draw_string_from_pointer
loc_D5C6:
    jmp set_bank_current

data_D5C9:
    .incbin "build/assets/bank15_data.bin", $15C9, $0035
; ----------------------------------------------------------------------
; load_party_member_record
;   Load a party member record from the $6100 array.
; ----------------------------------------------------------------------
load_party_member_record:
    lda text_actor
    sta ppu_update_off
    lda ppu_update_off
    asl a
    asl a
    asl a
    sta ppu_update_ptr_hi
loc_D609:
    ldy ppu_update_ptr_hi
    lda $6100,y                 ; Party member stats.
    bne loc_D62B
    lda ppu_update_ptr_hi
    sta ppu_update_ptr_lo
loc_D614:
    ldy ppu_update_ptr_lo
    lda $6101,y                 ; Party member stats.
    sta $6100,y                 ; Party member stats.
    inc ppu_update_ptr_lo
    lda ppu_update_ptr_lo
    and #$07
    cmp #$07
    bne loc_D614
    lda #$00
    sta $6101,y                 ; Party member stats.
loc_D62B:
    inc ppu_update_ptr_hi
    lda ppu_update_ptr_hi
    and #$07
    cmp #$07
    bne loc_D609
    rts
; ----------------------------------------------------------------------
; find_party_member
;   Find the first active party member.
;   called by: $F1B6
; ----------------------------------------------------------------------
find_party_member:
    txa
    pha
    ldx #$00
    stx ppu_update_ptr_lo
loc_D63C:
    lda $6090,x                 ; Party member order (actor ids).
    tax
    lda $609C,x                 ; Party member state bits.
    bmi loc_D64D
    inc ppu_update_ptr_lo
    ldx ppu_update_ptr_lo
    cpx #$07
    bne loc_D63C
loc_D64D:
    stx party_slot
    pla
    tax
    rts
; ----------------------------------------------------------------------
; read_inline_block_3
;   Read an inline pointer and copy three bytes from it.
; ----------------------------------------------------------------------
read_inline_block_3:
    stx ppu_update_len
    sty ppu_update_off
    jsr fetch_inline_word       ; inline pointer/data follows the JSR
data_D659:
    ldy ppu_update_off
    ldx ppu_update_len
    sty ppu_update_off
    ldy #$00
; ----------------------------------------------------------------------
; read_pointer_triplet
;   Read three bytes through the current pointer.
; ----------------------------------------------------------------------
read_pointer_triplet:
    lda ($00),y
    sta $03
    iny
    lda ($00),y
    sta $04
    iny
    lda ($00),y
    sta $05
    ldy ppu_update_off
; ----------------------------------------------------------------------
; copy_pointer_triplet
;   Copy a three-byte pointer/triplet.
; ----------------------------------------------------------------------
copy_pointer_triplet:
    sty ppu_update_off
    lda #$00
    sta ppu_update_ptr_lo
loc_D677:
    lda $03
    sta $00
    lda $04
    sta $01
    lda $05
    sta $02
    lda ppu_update_ptr_lo
    asl a
    adc ppu_update_ptr_lo
    tay
    lda data_D6B0,y
    sta $08
    lda data_D6B1,y
    sta $07
    lda data_D6B2,y
    sta $06
    jsr div24_shift
    ldy ppu_update_ptr_lo
    lda $00
    sta $0104,y
    inc ppu_update_ptr_lo
    cpy #$05
    bne loc_D677
    lda $03
    sta $010A
    ldy ppu_update_off
    rts

data_D6B0:
    .incbin "build/assets/bank15_data.bin", $16B0, $0001

data_D6B1:
    .incbin "build/assets/bank15_data.bin", $16B1, $0001

data_D6B2:
    .incbin "build/assets/bank15_data.bin", $16B2, $0061

; ----------------------------------------------------------------------
; set_party_cursor
;   Position the status cursor on a party member.
;   called by: $F95F
; ----------------------------------------------------------------------
set_party_cursor:
    txa
    pha
    lda $0560,x                 ; Per-actor map/world X.
    sta cursor_x
    lda $0570,x                 ; Per-actor map/world Y.
    sta cursor_y
    lda $0580,x                 ; Per-actor screen X.
    sta cursor_x2
    lda $0590,x                 ; Per-actor screen Y.
    sta cursor_y2
    lda $0530,x                 ; Per-actor palette/facing.
    tax
    jsr draw_status_row
    pla
    tax
    rts
; ----------------------------------------------------------------------
; draw_status_panel
;   Draw the officer/status panel for the current game mode.
;   called by: $F315
; ----------------------------------------------------------------------
draw_status_panel:
    lda text_x
    sta cursor_x
    lda text_y
    sta cursor_y
    lda text_x2
    sta cursor_x2
    lda text_y2
    sta cursor_y2
    ldx game_mode
; ----------------------------------------------------------------------
; draw_status_row
;   Draw one status row.
;   called by: $D72D
; ----------------------------------------------------------------------
draw_status_row:
    stx copy_dst_hi
    lda data_D774,x
    beq loc_D74F
    jsr cursor_add_x_signed
loc_D74F:
    ldx copy_dst_hi
    lda data_D78D,x
    beq loc_D759
    jsr cursor_add_y_signed
loc_D759:
    jsr draw_map_area
    lda #$09
    jsr set_bank_b
    ldx class_index
    lda data_D7A6,x
    sta ppu_update_ptr_hi
    lda #$00
    sta ppu_update_ptr_lo
    lda ($F3),y
    tay
    lda #$0E
    jmp set_bank_b

data_D774:
    .incbin "build/assets/bank15_data.bin", $1774, $0019

data_D78D:
    .incbin "build/assets/bank15_data.bin", $178D, $0019

data_D7A6:
    .incbin "build/assets/bank15_data.bin", $17A6, $0003
; ----------------------------------------------------------------------
; cursor_add_x
;   Add A to cursor X with 15-column wrap.
;   called by: $D817, $E4D6, $F577, $F669, $F7B2, $F7CC, $F8E1
; ----------------------------------------------------------------------
cursor_add_x:
    ldx text_y
    stx cursor_y
    ldx text_x
    stx cursor_x
; ----------------------------------------------------------------------
; cursor_add_x_signed
;   Add signed A to cursor X with wrap.
;   called by: $C798, $CA1F, $CB48, $CCD5, $D168, $D396, $D45E, $D74C, $F5FE
; ----------------------------------------------------------------------
cursor_add_x_signed:
    clc
    adc cursor_x
    bmi loc_D7C1
    cmp #$0F
    bcc loc_D7BE
    inc cursor_y
    sbc #$0F
loc_D7BE:
    sta cursor_x
    rts
loc_D7C1:
    dec cursor_y
    clc
    adc #$0F
    sta cursor_x
    rts
; ----------------------------------------------------------------------
; cursor_add_y
;   Add A to cursor Y with 16-row wrap.
;   called by: $D824, $E4F2, $F57F, $F670, $F7BF, $F7D1, $F8EE
; ----------------------------------------------------------------------
cursor_add_y:
    ldx text_y2
    stx cursor_y2
    ldx text_x2
    stx cursor_x2
; ----------------------------------------------------------------------
; cursor_add_y_signed
;   Add signed A to cursor Y with wrap.
;   called by: $C79F, $CA38, $CCDC, $D16D, $D39B, $D463, $D756, $F605
; ----------------------------------------------------------------------
cursor_add_y_signed:
    clc
    adc cursor_x2
    bmi loc_D7E1
    cmp #$10
    bcc loc_D7DE
    inc cursor_y2
    sbc #$10
loc_D7DE:
    sta cursor_x2
    rts
loc_D7E1:
    dec cursor_y2
    clc
    adc #$10
    sta cursor_x2
    rts
; ----------------------------------------------------------------------
; cursor_to_ppu
;   Convert cursor X/Y to a nametable/PPU address in $68/$69.
;   called by: $CA59, $CCDF, $D170, $D39E, $D466, $F582
; ----------------------------------------------------------------------
cursor_to_ppu:
    lda cursor_x2
    asl a
    sta ppu_update_ptr_lo
    lda #$00
    sta ppu_update_ptr_hi
    lda cursor_x
    asl a
    asl a
    asl a
    asl a
    rol ppu_update_ptr_hi
    asl a
    rol ppu_update_ptr_hi
    asl a
    rol ppu_update_ptr_hi
    clc
    adc ppu_update_ptr_lo
    sta ppu_addr_lo_shadow
    lda cursor_y2
    lsr a
    ldx #$20
    bcc loc_D80E
    ldx #$24
loc_D80E:
    txa
    clc
    adc ppu_update_ptr_hi
    sta ppu_addr_hi_shadow
    rts
; ----------------------------------------------------------------------
; set_scroll_from_cursor
;   Set scroll registers from the cursor position.
;   called by: $CF34, $F0FA
; ----------------------------------------------------------------------
set_scroll_from_cursor:
    lda #$F9
    jsr cursor_add_x
    lda cursor_x
    asl a
    asl a
    asl a
    asl a
    sta scroll_y
    lda #$F8
    jsr cursor_add_y
    lda cursor_x2
    asl a
    asl a
    asl a
    asl a
    sta scroll_x
    lda cursor_y2
    and #$01
    sta ppu_update_ptr_lo
    lda ppu_ctrl_shadow
    and #$FE
    ora ppu_update_ptr_lo
    sta ppu_ctrl_shadow
    rts
; ----------------------------------------------------------------------
; draw_map_area
;   Draw a rectangular map area from the map data.
;   called by: $D759, $F589
; ----------------------------------------------------------------------
draw_map_area:
    lda #$00
    sta ptr0_hi
    lda cursor_y2
    asl a
    sta ppu_update_ptr_lo
    lda cursor_y
    asl a
    asl a
    asl a
    rol ptr0_hi
    asl a
    rol ptr0_hi
    asl a
    rol ptr0_hi
    asl a
    rol ptr0_hi
    clc
    adc ppu_update_ptr_lo
    sta ptr0_lo
    lda ptr0_hi
    clc
    adc #$A7
    sta ptr0_hi
    lda #$09
    jsr set_bank_b
    ldy #$00
    sty ppu_update_ptr_hi
    lda ($10),y
    tax
    iny
    lda ($10),y
    cmp #$0C
    bne loc_D87D
    ldy $6570,x
    beq loc_D87D
    lda #$0D
loc_D87D:
    jsr set_bank_b
    txa
    asl a
    rol ppu_update_ptr_hi
    asl a
    rol ppu_update_ptr_hi
    asl a
    rol ppu_update_ptr_hi
    sta ppu_update_ptr_lo
    ldx ppu_update_ptr_hi
    stx ptr1_hi
    asl a
    rol ptr1_hi
    asl a
    rol ptr1_hi
    asl a
    rol ptr1_hi
    clc
    adc ppu_update_ptr_lo
    sta ptr1_lo
    lda ptr1_hi
    adc ppu_update_ptr_hi
    adc #$80
    sta ptr1_hi
    lda #$00
    sta ppu_addr_hi
    lda cursor_x2
    lsr a
    sta ppu_update_ptr_lo
    lda cursor_x
    lsr a
    asl a
    asl a
    asl a
    adc ppu_update_ptr_lo
    tay
    lda ($12),y
    asl a
    rol ppu_addr_hi
    asl a
    rol ppu_addr_hi
    sta ppu_addr_lo
    lda cursor_x
    lsr a
    clc
    adc #$40
    tay
    ldx ppu_update_ptr_lo
    lda ($12),y
loc_D8CD:
    asl a
    dex
    bpl loc_D8CD
    bcc loc_D8D9
    lda ppu_addr_hi
    adc #$03
    sta ppu_addr_hi
loc_D8D9:
    ldx class_index
    lda ppu_addr_hi
    clc
    adc data_D950,x
    sta ppu_addr_hi
    lda #$09
    jsr set_bank_b
    ldy #$00
    lda cursor_x
    lsr a
    bcc loc_D8F1
    iny
    iny
loc_D8F1:
    lda cursor_x2
    lsr a
    bcc loc_D8F7
    iny
loc_D8F7:
    lda ($14),y
    pha
    cmp #$01
    bne loc_D949
    lda #$0C
    jsr set_bank_b
    ldy party_index
    lda $6600,y
    sta ppu_update_off
    lda b12_data_8800,y
    sta ppu_update_ptr_lo
    lda b12_data_8880,y
    sta ppu_update_ptr_hi
    ldy #$00
loc_D916:
    lda ($F3),y
    iny
    cmp cursor_x
    bne loc_D934
    lda ($F3),y
    iny
    cmp cursor_y
    bne loc_D935
    lda ($F3),y
    iny
    cmp cursor_x2
    bne loc_D936
    lda ($F3),y
    iny
    cmp cursor_y2
    bne loc_D937
    beq loc_D940
loc_D934:
    iny
loc_D935:
    iny
loc_D936:
    iny
loc_D937:
    iny
    asl ppu_update_off
    cpy #$28
    bne loc_D916
    beq loc_D949
loc_D940:
    asl ppu_update_off
    bcc loc_D949
    pla
    ldy #$02
    bne loc_D94B
loc_D949:
    pla
    tay
loc_D94B:
    lda #$09
    jmp set_bank_b

data_D950:
    .incbin "build/assets/bank15_data.bin", $1950, $0003
; ----------------------------------------------------------------------
; tile_address
;   Return the tile address for a map cell.
;   called by: $CA5C, $F5B8
; ----------------------------------------------------------------------
tile_address:
    lda #$00
    sta ppu_addr_lo
    ldx class_index
    lda data_D979,x
    sta ppu_addr_hi
    lda cursor_x
    lsr a
    asl a
    asl a
    asl a
    asl a
    tax
    lda cursor_y2
    lsr a
    bcc loc_D96F
    txa
    adc #$07
    tax
loc_D96F:
    stx ppu_update_ptr_lo
    lda cursor_x2
    lsr a
    clc
    adc ppu_update_ptr_lo
    tax
    rts

data_D979:
    .incbin "build/assets/bank15_data.bin", $1979, $0003
; ----------------------------------------------------------------------
; render_map_column
;   Render one map column and advance the scroll.
;   called by: $CF2E
; ----------------------------------------------------------------------
render_map_column:
    inc text_y
    lda #$00
    sta game_mode
    lda #$0F
loc_D984:
    pha
    jsr draw_party_header
    jsr draw_party_status
    jsr draw_party_window
    jsr draw_party_column_a
    jsr draw_party_footer
    jsr draw_party_column_b
    jsr flush_vram_queue
    pla
    sec
    sbc #$01
    bne loc_D984
    rts
; ----------------------------------------------------------------------
; flush_vram_queue
;   Flush the $0400 VRAM update queue to the PPU.
;   Queue format: $00 terminates; otherwise PPUADDR hi, PPUADDR lo,
;   length (bit 7 toggles PPUCTRL bit 2), then length data bytes.
;   called by: $C0B1, $D997, $EE9E
; ----------------------------------------------------------------------
flush_vram_queue:
    ldx vram_queue_read         ; Read the next VRAM queue command.
    lda $0400,x                 ; VRAM update command queue.
    beq loc_D9EA
    sta PPUADDR
    inx
    lda $0400,x                 ; VRAM update command queue.
    sta PPUADDR
    inx
    lda $0400,x                 ; VRAM update command queue.
    and #$7F
    tay
    lda $0400,x                 ; VRAM update command queue.
    bpl loc_D9DD
    lda ppu_ctrl_shadow
    ora #$04
    sta PPUCTRL
    bne loc_D9DD
loc_D9C7:
    lda $0400,x                 ; VRAM update command queue.
    beq loc_D9EA
    sta PPUADDR
    inx
    lda $0400,x                 ; VRAM update command queue.
    sta PPUADDR
    inx
    lda $0400,x                 ; VRAM update command queue.
    and #$7F
    tay
loc_D9DD:
    inx
loc_D9DE:
    lda $0400,x                 ; VRAM update command queue.
    sta PPUDATA
    inx
    dey
    bne loc_D9DE
    beq loc_D9C7
loc_D9EA:
    stx vram_queue_read
    rts
; ----------------------------------------------------------------------
; draw_tile_run
;   Draw a run of map/text tiles starting at the PPU cursor.
;   called by: $CE06, $CE1B
; ----------------------------------------------------------------------
draw_tile_run:
    stx ppu_update_len
    ldx vram_queue_write
    lda tile_attr
    asl a
    bcc loc_D9F9
    jmp loc_DA62
loc_D9F9:
    lda ppu_addr_hi_shadow
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_hi
    inx
    lda ppu_addr_lo_shadow
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_lo
    inx
    and #$1F
    sta ppu_update_off
    lda #$20
    sec
    sbc ppu_update_off
    cmp ppu_update_len
    bcc loc_DA18
    lda ppu_update_len
loc_DA18:
    sta $0400,x                 ; VRAM update command queue.
    inx
loc_DA1C:
    lda $0360,y                 ; Saved text tile rows for window redraw.
    sta $0400,x                 ; VRAM update command queue.
    iny
    inx
    dec ppu_update_len
    beq loc_DA5A
    inc ppu_update_ptr_lo
    lda ppu_update_ptr_lo
    and #$1F
    bne loc_DA1C
    lda ppu_update_ptr_hi
    eor #$04
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_hi
    inx
    lda ppu_addr_lo_shadow
    and #$E0
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_lo
    inx
    and #$1F
    sta ppu_update_off
    lda #$20
    sec
    sbc ppu_update_off
    cmp ppu_update_len
    bcc loc_DA53
    lda ppu_update_len
loc_DA53:
    sta $0400,x                 ; VRAM update command queue.
    inx
    jmp loc_DA1C
loc_DA5A:
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    rts
loc_DA62:
    lda ppu_addr_hi_shadow
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_hi
    inx
    and #$03
    asl a
    asl a
    asl a
    sta ppu_update_off
    lda ppu_addr_lo_shadow
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_lo
    inx
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc ppu_update_off
    sta ppu_update_off
    lda #$1E
    sec
    sbc ppu_update_off
    cmp ppu_update_len
    bcc loc_DA8E
    lda ppu_update_len
loc_DA8E:
    ora #$80
    sta $0400,x                 ; VRAM update command queue.
    inx
loc_DA94:
    lda $0360,y                 ; Saved text tile rows for window redraw.
    sta $0400,x                 ; VRAM update command queue.
    iny
    inx
    dec ppu_update_len
    beq loc_DA5A
    lda ppu_update_ptr_lo
    clc
    adc #$20
    sta ppu_update_ptr_lo
    lda ppu_update_ptr_hi
    adc #$00
    sta ppu_update_ptr_hi
    and #$03
    cmp #$03
    bne loc_DA94
    lda ppu_update_ptr_lo
    cmp #$C0
    bcc loc_DA94
    lda ppu_update_ptr_hi
    and #$FC
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_hi
    inx
    and #$03
    asl a
    asl a
    asl a
    sta ppu_update_off
    lda ppu_update_ptr_lo
    and #$1F
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_lo
    inx
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc ppu_update_off
    sta ppu_update_off
    lda #$1E
    sec
    sbc ppu_update_off
    cmp ppu_update_len
    bcc loc_DAE9
    lda ppu_update_len
loc_DAE9:
    ora #$80
    sta $0400,x                 ; VRAM update command queue.
    inx
    jmp loc_DA94
; ----------------------------------------------------------------------
; draw_map_object
;   Draw one map object/sprite from the object table.
;   called by: $F69A
; ----------------------------------------------------------------------
draw_map_object:
    lda tile_id_base
    sta ppu_update_ptr_hi
    ldx vram_queue_write
loc_DAF8:
    ldy #$23
    lda battle_cursor
    and #$08
    beq loc_DB02
    ldy #$27
loc_DB02:
    tya
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda battle_cursor
    and #$07
    sta ppu_update_ptr_lo
    lda battle_cursor
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda data_DB7F,y
    clc
    adc ppu_update_ptr_lo
    sta $0400,x                 ; VRAM update command queue.
    inx
    ldy tile_attr
    bmi loc_DB57
    and #$07
    sta ppu_update_ptr_lo
    lda #$08
    sec
    sbc ppu_update_ptr_lo
    cmp ppu_update_ptr_hi
    bcc loc_DB31
    lda ppu_update_ptr_hi
loc_DB31:
    sta $0400,x                 ; VRAM update command queue.
    inx
loc_DB35:
    ldy battle_cursor
    lda $0780,y
    sta $0400,x                 ; VRAM update command queue.
    inx
    dec ppu_update_ptr_hi
    beq loc_DB77
    inc battle_cursor
    lda battle_cursor
    and #$0F
    bne loc_DB51
    lda battle_cursor
    sec
    sbc #$10
    sta battle_cursor
loc_DB51:
    and #$07
    bne loc_DB35
    beq loc_DAF8
loc_DB57:
    lda #$01
    sta $0400,x                 ; VRAM update command queue.
    inx
    ldy battle_cursor
    lda $0780,y
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda battle_cursor
    clc
    adc #$10
    cmp #$80
    bcc loc_DB71
    sbc #$80
loc_DB71:
    sta battle_cursor
    dec ppu_update_ptr_hi
    bne loc_DAF8
loc_DB77:
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
loc_DB7E:
    rts

data_DB7F:
    .incbin "build/assets/bank15_data.bin", $1B7F, $0008
; ----------------------------------------------------------------------
; scroll_map
;   Scroll the map and redraw the exposed row/column.
;   called by: $CB1B, $CB80
; ----------------------------------------------------------------------
scroll_map:
    lda input_buttons
    and #$02
    beq loc_DB91
    dec text_speed_count
    dec text_speed_count
loc_DB91:
    lda text_line
    pha
    tax
    lda data_DBC6,x
    sta text_line
    jsr text_draw_line
    lda ppu_addr_lo_shadow
    ora #$20
    sta ppu_addr_lo_shadow
    pla
    pha
    tax
    lda data_DBC8,x
    sta text_line
    jsr text_draw_line
    pla
    sta text_line
    lda #$00
    sta tile_attr
    lda input_buttons
    and #$02
    beq loc_DBBF
    inc text_speed_count
    inc text_speed_count
loc_DBBF:
    lda input_buttons
    bne loc_DB7E
    jmp draw_map_object

data_DBC6:
    .incbin "build/assets/bank15_data.bin", $1BC6, $0002

data_DBC8:
    .incbin "build/assets/bank15_data.bin", $1BC8, $0002
; ----------------------------------------------------------------------
; text_render_cell
;   Render one 8x16 dialogue cell.
;   Builds two VRAM-queue entries from $0300/$0318 and $68/$69.
;   The 16-pixel line pitch is what makes a 2x2 kanji glyph fit.
;   called by: $D1A8
; ----------------------------------------------------------------------
text_render_cell:
    ldx text_line               ; Queue the top and bottom tile for this cell.
    lda data_DC8F,x
    sta ptr1_hi
loc_DBD1:
    ldx vram_queue_write
    lda ppu_addr_hi_shadow
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_addr_lo_shadow
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$01
    sta $0400,x                 ; VRAM update command queue.
    inx
    ldy ptr1_hi
    lda $0300,y                 ; Top 8x8 tiles for the four text lines.
    bpl loc_DBEF
    jmp loc_DC7C
loc_DBEF:
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_addr_hi_shadow
    sta ppu_update_ptr_hi
    lda ppu_addr_lo_shadow
    clc
    adc #$20
    sta ppu_update_ptr_lo
    bcc loc_DC02
    inc ppu_update_ptr_hi
loc_DC02:
    cmp #$C0
    bcc loc_DC1A
    lda ppu_update_ptr_hi
    and #$03
    cmp #$03
    bne loc_DC1A
    lda ppu_update_ptr_lo
    and #$1F
    sta ppu_update_ptr_lo
    lda ppu_update_ptr_hi
    and #$FC
    sta ppu_update_ptr_hi
loc_DC1A:
    lda ppu_update_ptr_hi
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_update_ptr_lo
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$01
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda $0318,y                 ; Bottom 8x8 tiles for the four text lines.
    sta $0400,x                 ; VRAM update command queue.
    inx
    inc ptr1_hi
    inc ppu_addr_lo_shadow
    lda ppu_addr_lo_shadow
    and #$1F
    bne loc_DC4C
    lda ppu_addr_hi_shadow
    eor #$04
    sta ppu_addr_hi_shadow
    lda ppu_addr_lo_shadow
    and #$E0
    sec
    sbc #$20
    sta ppu_addr_lo_shadow
loc_DC4C:
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    lda input_buttons
    and #$10
    bne loc_DC79
    lda frame_counter
    lsr a
    bcs loc_DC63
    lda #$07
    jsr sound_queue_add
loc_DC63:
    lda text_speed
    ldx $0318,y                 ; Bottom 8x8 tiles for the four text lines.
    cpx #$0A
    bne loc_DC6F
    clc
    adc #$02
loc_DC6F:
    pha
    jsr update_frame
    pla
    sec
    sbc #$01
    bpl loc_DC6F
loc_DC79:
    jmp loc_DBD1
loc_DC7C:
    pha
    ldx vram_queue_write
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    lda input_buttons
    and #$10
    beq loc_DC8D
    jsr wait_vblank
loc_DC8D:
    pla
    rts

data_DC8F:
    .incbin "build/assets/bank15_data.bin", $1C8F, $0004
; ----------------------------------------------------------------------
; text_draw_line
;   Draw a line of text tiles into the nametable.
;   called by: $D3AF, $DB9A, $DBAB
; ----------------------------------------------------------------------
text_draw_line:
    lda text_speed_count
    sta ppu_update_len
    lda ppu_addr_lo_shadow
    and #$1F
    sta ppu_update_ptr_lo
    lda #$20
    sec
    sbc ppu_update_ptr_lo
    cmp text_speed_count
    bcs loc_DCAF
    sta ppu_update_len
    lda text_speed_count
    sec
    sbc ppu_update_len
    sta ppu_update_off
loc_DCAF:
    ldx text_line
    ldy data_DD0B,x
    lda input_buttons
    and #$02
    beq loc_DCBC
    iny
    iny
loc_DCBC:
    lda text_speed_count
    sta ppu_update_ptr_lo
    ldx vram_queue_write
    lda ppu_addr_hi_shadow
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_addr_lo_shadow
    sta $0400,x                 ; VRAM update command queue.
    sta ppu_update_ptr_hi
    inx
    lda ppu_update_len
    sta $0400,x                 ; VRAM update command queue.
    inx
loc_DCD6:
    lda $0300,y                 ; Top 8x8 tiles for the four text lines.
    sta $0400,x                 ; VRAM update command queue.
    iny
    inx
    dec ppu_update_ptr_lo
    beq loc_DD03
    inc ppu_update_ptr_hi
    lda ppu_update_ptr_hi
    and #$1F
    bne loc_DCD6
    lda ppu_addr_hi_shadow
    eor #$04
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_addr_lo_shadow
    and #$E0
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda ppu_update_off
    sta $0400,x                 ; VRAM update command queue.
    inx
    jmp loc_DCD6
loc_DD03:
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    rts

data_DD0B:
    .incbin "build/assets/bank15_data.bin", $1D0B, $0009
; ----------------------------------------------------------------------
; draw_string
;   Draw a zero-terminated string.
;   called by: $CF91
; ----------------------------------------------------------------------
draw_string:
    jsr fetch_inline_word       ; inline pointer/data follows the JSR
data_DD17:
    lda #$40
    sta ppu_update_off
    ldx vram_queue_write
    ldy #$00
    lda ($00),y
loc_DD21:
    sta $0400,x                 ; VRAM update command queue.
    inx
    iny
    lda ($00),y
    sta $0400,x                 ; VRAM update command queue.
    inx
    iny
    lda ($00),y
    pha
    and #$3F
    sta ppu_update_len
    pla
    bit ppu_update_off
    beq loc_DD50
    and #$BF
    sta $0400,x                 ; VRAM update command queue.
    inx
    iny
    lda ($00),y
    iny
loc_DD43:
    sta $0400,x                 ; VRAM update command queue.
    inx
    dec ppu_update_len
    bne loc_DD43
    lda ($00),y
    jmp loc_DD5B
loc_DD50:
    sta $0400,x                 ; VRAM update command queue.
    inx
    iny
    lda ($00),y
    dec ppu_update_len
    bpl loc_DD50
loc_DD5B:
    cmp #$FF
    bne loc_DD21
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    rts
; ----------------------------------------------------------------------
; draw_text_window
;   Draw the dialogue window border and clear its interior.
;   called by: $C0DF, $CF37, $F529
; ----------------------------------------------------------------------
draw_text_window:
    ldx vram_queue_write
    lda #$1F
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$F0
    sta $0400,x                 ; VRAM update command queue.
    inx
    lda #$10
    sta $0400,x                 ; VRAM update command queue.
    inx
    ldy #$00
    sty ppu_update_ptr_lo
loc_DD7F:
    lda data_DDC2,y
    ldy palette_index
    sty ppu_update_ptr_hi
    beq loc_DDA6
    ldy ppu_update_ptr_lo
    sty ppu_update_off
    lsr ppu_update_off
    lsr ppu_update_off
    lsr ppu_update_off
    bcs loc_DD9E
loc_DD94:
    tay
    lsr a
    tya
    ror a
    dec ppu_update_ptr_hi
    bne loc_DD94
    beq loc_DDA6
loc_DD9E:
    tay
    asl a
    tya
    rol a
    dec ppu_update_ptr_hi
    bne loc_DD9E
loc_DDA6:
    sta $0400,x                 ; VRAM update command queue.
    inx
    inc ppu_update_ptr_lo
    ldy ppu_update_ptr_lo
    cpy #$10
    bne loc_DD7F
    lda #$00
    sta $0400,x                 ; VRAM update command queue.
    stx vram_queue_write
    inc palette_index
    lda palette_index
    and #$07
    sta palette_index
    rts

data_DDC2:
    .incbin "build/assets/bank15_data.bin", $1DC2, $0010
; ----------------------------------------------------------------------
; draw_window_box
;   Draw a general window box with variable position/size.
;   called by: $E856
; ----------------------------------------------------------------------
draw_window_box:
    lda #$0C
    jsr set_bank_b
    jmp loc_DDE3
; ----------------------------------------------------------------------
; update_party_portrait
;   Update a party member's portrait/class bits.
; ----------------------------------------------------------------------
update_party_portrait:
    lda #$0C
    jsr set_bank_b
    lda $60A8,y                 ; Party member class/officer id.
    tay
loc_DDE3:
    lda b12_data_A800,y
    sta ppu_update_ptr_lo
    lda b12_data_A900,y
    sta ppu_update_ptr_hi
    ldy #$04
    lda ($F3),y
    and #$C0
    clc
    rol a
    rol a
    rol a
    sta ppu_update_off
    lda $0520,x                 ; Per-actor state flags.
    and #$FC
    ora ppu_update_off
    sta $0520,x                 ; Per-actor state flags.
    dey
    lda ($F3),y
    tax
; ----------------------------------------------------------------------
; expand_name_tile
;   Expand one packed name-entry tile into the tile buffer.
; ----------------------------------------------------------------------
expand_name_tile:
    ldy #$00
    sty ppu_update_ptr_hi
    sty ppu_update_off
    cpx #$54
    bcc loc_DE14
    jmp loc_DE8A
loc_DE14:
    cpx #$2A
    bcc loc_DE1E
    txa
    sec
    sbc #$2A
    tax
    iny
loc_DE1E:
    stx ppu_update_ptr_lo
    stx ppu_update_len
    tya
    jsr set_bank_b
    lda ppu_update_len
    asl a
    rol ppu_update_off
    asl a
    rol ppu_update_off
    asl a
    rol ppu_update_off
    sta ppu_update_ptr_lo
    lda ppu_update_off
    sta ppu_update_ptr_hi
    lda ppu_update_ptr_lo
    asl a
    rol ppu_update_off
    clc
    adc ppu_update_ptr_lo
    sta ppu_update_ptr_lo
    lda ppu_update_off
    adc ppu_update_ptr_hi
    sta ppu_update_ptr_hi
    lda ppu_update_ptr_lo
    asl a
    rol ppu_update_ptr_hi
    asl a
    rol ppu_update_ptr_hi
    asl a
    rol ppu_update_ptr_hi
    asl a
    rol ppu_update_ptr_hi
    clc
    adc #$80
    sta $39
    lda ppu_update_ptr_hi
    adc #$80
    sta $3A
    lda #$06
    sta ppu_update_len
    lda #$00
    sta $3C
    lda screen_brightness
    asl a
    rol $3C
    asl a
    rol $3C
    asl a
    rol $3C
    asl a
    rol $3C
    sta $3B
loc_DE78:
    lda screen_brightness
    clc
    adc #$04
    sta screen_brightness
    lda #$01
    sta palette_dirty
    jsr wait_vblank
    dec ppu_update_len
    bne loc_DE78
loc_DE8A:
    jmp set_bank_current
; ----------------------------------------------------------------------
; load_battle_palette
;   Load the battle palette and tile set.
;   called by: $CF22
; ----------------------------------------------------------------------
load_battle_palette:
    lda #$09
    jsr set_bank_b
    ldy #$10
    lda #$04
    ldx #$80
    jsr copy_to_vram

data_DE9B:
    .incbin "build/assets/bank15_data.bin", $1E9B, $0002
    jmp set_bank_current
; ----------------------------------------------------------------------
; draw_battle_panel
;   Draw the battle status panel.
;   called by: $CF25
; ----------------------------------------------------------------------
draw_battle_panel:
    lda #$04
    jsr set_bank_b
    lda level
    asl a
    asl a
    asl a
    adc #$80
    sta $01
    lda #$00
    sta $00
    ldy #$18
    ldx #$7F
    jsr write_vram_block
    jmp set_bank_current

data_DEBC:
    .incbin "build/assets/bank15_data.bin", $1EBC, $0143

data_DFFF:
    .incbin "build/assets/bank15_data.bin", $1FFF, $0001

data_E000:
    .incbin "build/assets/bank15_data.bin", $2000, $0371

; ----------------------------------------------------------------------
; read_party_stat_byte
;   Read one byte from a party member's bank 12 stat record.
; ----------------------------------------------------------------------
read_party_stat_byte:
    pha
    lda #$0C
    jsr set_bank_b
    lda b12_data_A800,y
    sta ppu_update_ptr_lo
    lda b12_data_A900,y
    sta ppu_update_ptr_hi
    pla
    tay
    lda ($F3),y
    pha
    jsr set_bank_current
    pla
    rts

data_E38B:
    .incbin "build/assets/bank15_data.bin", $238B, $0075

data_E400:
    .incbin "build/assets/bank15_data.bin", $2400, $0064

; ----------------------------------------------------------------------
; copy_party_stats
;   Copy current party stats into the previous-stat snapshot.
;   called by: $F391
; ----------------------------------------------------------------------
copy_party_stats:
    lda $0561                   ; Per-actor map/world X.
    sta $0562                   ; Per-actor map/world X.
    lda $0571                   ; Per-actor map/world Y.
    sta $0572                   ; Per-actor map/world Y.
    lda $0581                   ; Per-actor screen X.
    sta $0582                   ; Per-actor screen X.
    lda $0591                   ; Per-actor screen Y.
    sta $0592                   ; Per-actor screen Y.
    lda $0560                   ; Per-actor map/world X.
    sta $0561                   ; Per-actor map/world X.
    lda $0570                   ; Per-actor map/world Y.
    sta $0571                   ; Per-actor map/world Y.
    lda $0580                   ; Per-actor screen X.
    sta $0581                   ; Per-actor screen X.
    lda $0590                   ; Per-actor screen Y.
    sta $0591                   ; Per-actor screen Y.
    rts
; ----------------------------------------------------------------------
; init_party_status
;   Initialise the party status screen.
;   called by: $F0F4
; ----------------------------------------------------------------------
init_party_status:
    lda game_mode
    sta $0530                   ; Per-actor palette/facing.
    sta $0531                   ; Per-actor palette/facing.
    sta $0532                   ; Per-actor palette/facing.
    sta party_active
    asl a
    tax
    lda data_E505,x
    sta ppu_update_len
    inx
    lda data_E505,x
    sta ppu_update_off
    lda game_mode
    eor #$01
    sta party_flags
    sta party_prev
    lda #$6E
    sta $0540                   ; Per-actor tile/sprite id.
    lda party_index
    bne loc_E4C3
    inc $0540                   ; Per-actor tile/sprite id.
loc_E4C3:
    ldy #$00
    sty $86
loc_E4C7:
    lda ppu_update_len
    asl a
    asl a
    asl a
    asl a
    clc
    adc $0540,y                 ; Per-actor tile/sprite id.
    sta $0541,y                 ; Per-actor tile/sprite id.
    lda ppu_update_len
    jsr cursor_add_x
    lda cursor_x
    sta $0561,y                 ; Per-actor map/world X.
    lda cursor_y
    sta $0571,y                 ; Per-actor map/world Y.
    lda ppu_update_off
    asl a
    asl a
    asl a
    asl a
    clc
    adc $0550,y                 ; Per-actor animation frame.
    sta $0551,y                 ; Per-actor animation frame.
    lda ppu_update_off
    jsr cursor_add_y
    lda cursor_x2
    sta $0581,y                 ; Per-actor screen X.
    lda cursor_y2
    sta $0591,y                 ; Per-actor screen Y.
    iny
    cpy #$02
    bne loc_E4C7
    rts

data_E505:
    .incbin "build/assets/bank15_data.bin", $2505, $0055

; ----------------------------------------------------------------------
; dialogue_sequence
;   Run a dialogue/event sequence and restore the previous screen.
;   called by: $F351
; ----------------------------------------------------------------------
dialogue_sequence:
    ldx #$25
    stx $03F0                   ; Small VRAM upload buffer.
    stx vram_dma_pending
    jsr wait_vblank
    ldx #$0F
    stx $03F0                   ; Small VRAM upload buffer.
    stx vram_dma_pending
    jsr wait_vblank
    ldx #$06
    stx text_actor
loc_E572:
    ldx text_actor
    lda $609C,x                 ; Party member state bits.
    bpl loc_E5DF
    txa
    asl a
    asl a
    tay
    lda $60D0,y                 ; Party member stats.
    sta ptr0_lo
    lda $60D1,y                 ; Party member stats.
    sta ptr0_hi
    lda #$64
    sta ptr1_hi
    jsr mul16x8_shift
    lda ptr0_lo
    ora ptr0_hi
    bne loc_E596
    inc ptr0_lo
loc_E596:
    lda #$00
    sta ptr1_lo
    jsr load_battle_tiles
    bne loc_E5FF
    bcs loc_E5DF
    lda #$00
    sta $609C,x                 ; Party member state bits.
    jsr b14_init_battle_party   ; banked call target (bank must be selected first)
    jsr reset_text_engine
    jsr text_reset_cursor
    jsr text_print_inline       ; inline pointer/data follows the JSR

data_E5B2:
    .dw b10_msg_index_036    ; text index $0024 -> b10_msg_036
    lda $0500                   ; Per-actor state flags.
    bmi loc_E5D9
    jsr text_draw_char
    jsr text_print_inline       ; inline pointer/data follows the JSR

data_E5BF:
    .dw b10_msg_index_037    ; text index $0025 -> b10_msg_037
    ldx #$30
    txs
    jsr wait_keypress
    ldy #$0A
    jsr draw_window
    lda #$0D
    jsr set_bank_b
    jsr b13_officer_status_init ; banked call target (bank must be selected first)
    pla
    pla
    jmp game_mode_switch
loc_E5D9:
    jsr wait_keypress
    jsr text_draw_screen
loc_E5DF:
    dec text_actor
    bpl loc_E572
    rts

data_E5E4:
    .incbin "build/assets/bank15_data.bin", $25E4, $0010

data_E5F4:
    .incbin "build/assets/bank15_data.bin", $25F4, $000B
loc_E5FF:
    inc $00

data_E601:
    .incbin "build/assets/bank15_data.bin", $2601, $005F

data_E660:
    .incbin "build/assets/bank15_data.bin", $2660, $0008

data_E668:
    .incbin "build/assets/bank15_data.bin", $2668, $00A9

; ----------------------------------------------------------------------
; load_party_hp
;   Load a party member's troops/HP from bank 12.
; ----------------------------------------------------------------------
load_party_hp:
    lda #$0C
    jsr set_bank_b
    ldy $60A8,x                 ; Party member class/officer id.
    lda b12_data_A800,y
    sta ppu_update_ptr_lo
    lda b12_data_A900,y
    sta ppu_update_ptr_hi
    ldy #$00
    lda ($F3),y
    sta $619C,x                 ; Party member derived stats.
    iny
    lda ($F3),y
    sta $61A8,x                 ; Party member derived stats.
    ldy #$09
    lda ($F3),y
    sta ptr0_lo
    lda #$00
    sta ptr0_hi
    lda $60A8,x                 ; Party member class/officer id.
    ldy #$08
loc_E73F:
    cmp data_E78C,y
    beq loc_E749
    dey
    bpl loc_E73F
    bmi loc_E759
loc_E749:
    ldy $6010
    lda data_E794,y
    sta ppu_addr_lo
    lda data_E79C,y
    sta ppu_addr_hi
    jsr rng_next
loc_E759:
    lda ptr0_lo
    sta $61B4,x                 ; Party member troops/HP.
    txa
    asl a
    asl a
    asl a
    tay
loc_E763:
    lda $6100,y                 ; Party member stats.
    cmp #$21
    beq loc_E772
    iny
    tya
    and #$07
    bne loc_E763
    beq loc_E781
loc_E772:
    lda $61B4,x                 ; Party member troops/HP.
    lsr a
    clc
    adc $61B4,x                 ; Party member troops/HP.
    bcc loc_E77E
    lda #$FF
loc_E77E:
    sta $61B4,x                 ; Party member troops/HP.
loc_E781:
    lda #$0E
    jsr set_bank_b
    jsr b14_officer_status_screen; banked call target (bank must be selected first)
    jmp set_bank_current

data_E78C:
    .incbin "build/assets/bank15_data.bin", $278C, $0008

data_E794:
    .incbin "build/assets/bank15_data.bin", $2794, $0008

data_E79C:
    .incbin "build/assets/bank15_data.bin", $279C, $0009
; ----------------------------------------------------------------------
; battle_screen
;   Battle screen setup and per-frame battle UI.
;   called by: $F8DC
; ----------------------------------------------------------------------
battle_screen:
    lda #$0C
    jsr set_bank_b
    lda #$58
    sta screen_brightness
    ldx #$03
    stx $A2
    dex
    stx ppu_addr_hi
    lda #$00
    tay
    ldx #$0C
loc_E7BA:
    sta $0503,x                 ; Per-actor state flags.
    dex
    bpl loc_E7BA
    ldx party_index
    lda $9000,x
    sta ptr1_lo
    lda $9080,x
    sta ptr1_hi
loc_E7CC:
    lda #$0C
    jsr set_bank_b
    ldx $A2
    lda ($12),y
    cmp #$FF
    bne loc_E7DC
    jmp loc_E8BC
loc_E7DC:
    and #$0F
    sta $0560,x                 ; Per-actor map/world X.
    lda ($12),y
    and #$30
    sta ppu_update_ptr_lo
    iny
    lda ($12),y
    and #$3F
    sta $0570,x                 ; Per-actor map/world Y.
    lda ($12),y
    and #$C0
    jsr nop_return
    bcs loc_E7F9
    lsr a
loc_E7F9:
    and #$40
    sta ppu_update_ptr_hi
    lda $05D0,x                 ; Per-actor status bits.
    and #$8F
    ora ppu_update_ptr_lo
    ora ppu_update_ptr_hi
    sta $05D0,x                 ; Per-actor status bits.
    iny
    lda ($12),y
    lsr a
    lsr a
    lsr a
    lsr a
    sta ppu_update_ptr_lo
    and #$0C
    ora #$81
    sta $0500,x                 ; Per-actor state flags.
    lda ppu_update_ptr_lo
    jsr set_actor_palette
    lda ($12),y
    and #$0F
    sta $0580,x                 ; Per-actor screen X.
    iny
    lda ($12),y
    sta ppu_addr_lo
    and #$1F
    sta $0590,x                 ; Per-actor screen Y.
    iny
    jsr nop_return
    lda ($12),y
    iny
    bcc loc_E83A
    lda ($12),y
loc_E83A:
    sta $05E0,x                 ; Per-actor level.
    iny
    lda ppu_addr_lo
    and #$40
    bne loc_E846
    inc ppu_addr_hi
loc_E846:
    lda ppu_addr_hi
    sta $0510,x                 ; Per-actor state flags.
    lda ppu_addr_lo
    and #$40
    bne loc_E870
    tya
    pha
    lda ($12),y
    tay
    jsr draw_window_box
    pla
    tay
    lda ppu_addr_lo
    bpl loc_E876
    tya
    pha
    ldx $A2
    lda #$01
    sta $0530,x                 ; Per-actor palette/facing.
    jsr draw_portrait
    pla
    tay
    jmp loc_E876
loc_E870:
    lda $051F,x                 ; Per-actor state flags.
    sta $0520,x                 ; Per-actor state flags.
loc_E876:
    lda #$0C
    jsr set_bank_b
    ldx $A2
    lda ($12),y
    sta $05F0,x
    tax
    lda $6300,x
    ldx $A2
    cmp #$80
    beq loc_E891
    lda #$00
    sta $0500,x                 ; Per-actor state flags.
loc_E891:
    lda ppu_addr_lo
    and #$20
    beq loc_E8B6
    iny
    lda ($12),y
    sta ppu_update_ptr_lo
    iny
    lda ($12),y
    sta ppu_update_ptr_hi
    tya
    pha
    lda #$E8
    pha
    lda #$B0
    pha
    lda #$0D
    jsr set_bank_b
    jmp ($00F3)
    pla
    tay
    jsr set_bank_current
loc_E8B6:
    iny
    inc $A2
    jmp loc_E7CC
loc_E8BC:
    jmp set_bank_current
; ----------------------------------------------------------------------
; nop_return
;   No-op returning immediately (used as a placeholder vector).
;   called by: $E7F3, $E830
; ----------------------------------------------------------------------
nop_return:
    pha
    ldx party_index
    lda $6700,x
    ldx $A2
    lsr a
    pla
    rts

data_E8CA:
    .incbin "build/assets/bank15_data.bin", $28CA, $0336

b15_text_data:
    .incbin "build/assets/bank15_data.bin", $2C00, $01A1

data_EDA1:
    .incbin "build/assets/bank15_data.bin", $2DA1, $0030

data_EDD1:
    .incbin "build/assets/bank15_data.bin", $2DD1, $00A8

; ----------------------------------------------------------------------
; nmi_handler
;   NMI/IRQ handler.
;   Updates PPU registers, DMA, sound, palette/VRAM queue, and scroll.
;   The same handler is used for the IRQ vector; IRQ sources are disabled.
; ----------------------------------------------------------------------
nmi_handler:
    php                         ; Save the interrupted registers.
    pha
    txa
    pha
    tya
    pha
    lda nmi_busy
    bne loc_EEE0
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda PPUSTATUS
    lda #$00
    sta PPUMASK
    sta OAMADDR
    lda #$02
    sta OAMDMA
    lda nmi_update_budget
    beq loc_EECE
    dec nmi_update_budget
    jsr flush_vram_queue
    lda vram_dma_pending
    beq loc_EECB
    ldx #$00
    stx vram_dma_pending
    lda #$3F
    sta PPUADDR
    stx PPUADDR
    ldy #$20
loc_EEB3:
    lda $03E0,x                 ; Small VRAM upload buffer.
    sta PPUDATA
    inx
    dey
    bne loc_EEB3
    lda #$3F
    sta PPUADDR
    sty PPUADDR
    sty PPUADDR
    sty PPUADDR
loc_EECB:
    jsr flush_palette
loc_EECE:
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
    lda ppu_mask_shadow
    sta PPUMASK
    jsr ppu_nmi_on
loc_EEE0:
    inc frame_counter
    ldx #$0C
    ldy input_mask
loc_EEE6:
    tya
    asl a
    tay
    bcs loc_EEF9
    lda task_state,x
    cmp #$01
    bne loc_EEF9
    dec task_timer,x
    bne loc_EEF9
    lda #$04
    sta task_state,x
loc_EEF9:
    dex
    dex
    dex
    dex
    bpl loc_EEE6
    lda nmi_mode
    bmi loc_EF38
    beq loc_EF08
    jmp loc_EF94
loc_EF08:
    lda current_prg_bank
    pha
    lda #$08
    jsr restore_bank_after_nmi
loc_EF10:
    ldx sound_queue_read
    lda $E0,x
    cmp #$88
    beq loc_EF2A
    pha
    lda #$88
    sta $E0,x
    inx
    txa
    and #$07
    sta sound_queue_read
    pla
    jsr sound_play              ; banked call target (bank must be selected first)
    jmp loc_EF10
loc_EF2A:
    jsr sound_update            ; banked call target (bank must be selected first)
    pla
    jsr restore_bank_after_nmi
loc_EF31:
    pla
    tay
    pla
    tax
    pla
    plp
    rti
loc_EF38:
    nop
    lda #$00
    sta $06
    ldx $00
loc_EF3F:
    ldy #$10
loc_EF41:
    dey
    bne loc_EF41
    dex
    bne loc_EF3F
loc_EF47:
    ldx $02
loc_EF49:
    ldy #$10
loc_EF4B:
    dey
    bne loc_EF4B
    dex
    bne loc_EF49
    lda #$91
    sta PPUCTRL
    ldx $04
    beq loc_EF62
loc_EF5A:
    ldy #$10
loc_EF5C:
    dey
    bne loc_EF5C
    dex
    bne loc_EF5A
loc_EF62:
    ldx $06
    ldy $6400,x
loc_EF67:
    dey
    bpl loc_EF67
    ldx $06
    lda data_EF8A,x
    sta PPUADDR
    ldx $06
    lda data_EF8F,x
    sta PPUADDR
    lda ppu_ctrl_shadow
    sta PPUCTRL
    inc $06
    lda $06
    cmp #$05
    bne loc_EF47
    jmp loc_EF31

data_EF8A:
    .incbin "build/assets/bank15_data.bin", $2F8A, $0005

data_EF8F:
    .incbin "build/assets/bank15_data.bin", $2F8F, $0005
loc_EF94:
    ldy #$00
    sty $06
loc_EF98:
    ldx data_EFC6,y
loc_EF9B:
    ldy #$20
loc_EF9D:
    dey
    bne loc_EF9D
    dex
    bne loc_EF9B
    lda $06
    and #$01
    tax
    lda $6400,x
    sta PPUSCROLL
    lda #$00
    sta PPUSCROLL
    lda ppu_ctrl_shadow
    ora $6402,x
    sta PPUCTRL
    inc $06
    ldy $06
    cpy #$03
    bne loc_EF98
    jmp loc_EF31

data_EFC6:
    .incbin "build/assets/bank15_data.bin", $2FC6, $0003
; ----------------------------------------------------------------------
; reset_init
;   Reset initialisation: wait for PPU, clear RAM, set MMC1, start main loop.
; ----------------------------------------------------------------------
reset_init:
    cld                         ; Warm up the PPU and clear RAM.
    lda #$10
    sta PPUCTRL
    ldx #$FF
    txs
loc_EFD2:
    lda PPUSTATUS
    bpl loc_EFD2
loc_EFD7:
    lda PPUSTATUS
    bmi loc_EFD7
loc_EFDC:
    lda PPUSTATUS
    bpl loc_EFDC
loc_EFE1:
    lda PPUSTATUS
    bmi loc_EFE1
loc_EFE6:
    lda PPUSTATUS
    bpl loc_EFE6
loc_EFEB:
    lda PPUSTATUS
    bmi loc_EFEB
    lda #$1E
    sta ppu_mask_shadow
    lda #$00
    sta PPUMASK
    sta $4010
    sta APUSTATUS
    lda #$40
    sta JOY2_APUFRAME
    lda #$0E
    jsr write_prg_bank
    jsr mmc1_init
    lda #$00
    sta b14_data_BFD9
    lsr a
    sta b14_data_BFD9
    lsr a
    sta b14_data_BFD9
    lsr a
    sta b14_data_BFD9
    lsr a
    sta b14_data_BFD9
    lda #$00
    sta data_DFFF
    lsr a
    sta data_DFFF
    lsr a
    sta data_DFFF
    lsr a
    sta data_DFFF
    lsr a
    sta data_DFFF
    lda #$00
    ldx #$F0
loc_F03A:
    sta $00,x
    dex
    bne loc_F03A
    sta $0400                   ; VRAM update command queue.
    lda #$0E
    sta current_bank_a
    sta current_bank_b
    lda #$88
    ldx #$08
loc_F04C:
    sta $DF,x
    dex
    bne loc_F04C
    stx sound_queue_write
    stx sound_queue_read
    lda #$00
    ldx #$07
    ldy #$07
    jsr fill_ram_block
    lda #$F0
    sta task_temp_hi
    lda #$72
    sta task_temp_lo
    lda #$00
    jsr task_set_continuation
    lda #$90
    sta ppu_ctrl_shadow
    jmp main_loop
    ldx #$30
    txs
    jsr ppu_nmi_on
    jsr nop_return2
    jsr ppu_init
    lda #$04
    sta party_flags
    sta party_prev
    lda #$FF
    sta $89
    jsr set_bank_13
    jsr b13_load_status_screen  ; banked call target (bank must be selected first)
    jsr set_bank_14
    jsr new_game_init
    jmp loc_F0E7
; ----------------------------------------------------------------------
; new_game_init
;   Initialise a new game/party state.
;   called by: $F091
; ----------------------------------------------------------------------
new_game_init:
    lda #$6E
    sta $0540                   ; Per-actor tile/sprite id.
    lda #$80
    sta $0550                   ; Per-actor animation frame.
    lda #$01
    sta $0520                   ; Per-actor state flags.
    sta $0511                   ; Per-actor state flags.
    lda #$00
    sta $0510                   ; Per-actor state flags.
    sta game_mode
    sta party_active
    lda #$02
    sta $0521                   ; Per-actor state flags.
    sta $0512                   ; Per-actor state flags.
    rts
; ----------------------------------------------------------------------
; battle_party_init
;   Initialise the battle party and switch to bank 13.
; ----------------------------------------------------------------------
battle_party_init:
    jsr set_bank_14
    jsr b14_init_party_loop     ; banked call target (bank must be selected first)
    jsr b14_delay_frames        ; banked call target (bank must be selected first)
    lda text_busy
    bne loc_F0CB
    jsr b14_init_battle_party   ; banked call target (bank must be selected first)
loc_F0CB:
    jmp set_bank_13

data_F0CE:
    .incbin "build/assets/bank15_data.bin", $30CE, $0009
; ----------------------------------------------------------------------
; enter_party_screen
;   Map bank 7 and enter the party/list screen.
; ----------------------------------------------------------------------
enter_party_screen:
    lda #$07
    jsr set_bank_a
    jmp b07_enter_party_screen  ; banked call target (bank must be selected first)
; ----------------------------------------------------------------------
; enter_status_screen
;   Map bank 13 and enter the officer status screen.
; ----------------------------------------------------------------------
enter_status_screen:
    lda #$0D
    jsr set_bank_a
    jmp b13_load_status_screen  ; banked call target (bank must be selected first)
loc_F0E7:
    jsr load_game
    ldx #$07
    lda #$FF
loc_F0EE:
    sta $6080,x
    dex
    bpl loc_F0EE
    jsr init_party_status
    jsr battle_main
    jsr set_scroll_from_cursor
    jsr ppu_nmi_off
    jsr ppu_bg_sprites_off
    jsr b14_init_battle_party   ; banked call target (bank must be selected first)
    jsr screen_refresh
    lda $7C
    beq loc_F11E
    jsr b14_copy_active_party   ; banked call target (bank must be selected first)
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

data_F116:
    .dw b10_msg_index_129    ; text index $0081 -> b10_msg_129
    jsr wait_keypress
    jsr text_draw_screen
loc_F11E:
    lda $6010
    cmp #$02
    bcs loc_F12A
    lda #$08
    sta $6705
loc_F12A:
    jmp game_mode_switch
    jsr text_print_inline       ; inline pointer/data follows the JSR

data_F130:
    .dw b10_msg_index_130    ; text index $0082 -> b10_msg_130
    rts
; ----------------------------------------------------------------------
; load_game
;   Load saved game data from battery-backed PRG RAM.
;   called by: $F0E7
; ----------------------------------------------------------------------
load_game:
    ldy $6011
    lda $6012,y
    sta party_index
    jsr b14_get_item_category   ; banked call target (bank must be selected first)
    ldy #$03
loc_F140:
    lda $6016,y
    sta text_x,y
    dey
    bpl loc_F140
    rts
; ----------------------------------------------------------------------
; game_mode_switch
;   Dispatch a new game mode/screen.
; ----------------------------------------------------------------------
game_mode_switch:
    ldx #$30
    txs
    lda battle_flags2
    lsr a
    bcc loc_F161
    lda battle_state
    bne loc_F161
    ldy $86
    beq loc_F161
    cpy #$05
    bcs loc_F161
    jsr battle_calc
loc_F161:
    lda controller_prev
    and #$A0
    beq loc_F172
    pha
    lda battle_flags2
    lsr a
    bcc loc_F175
    lda battle_state
    beq loc_F175
loc_F171:
    pla
loc_F172:
    jmp loc_F1DD
loc_F175:
    ldy $86
    cpy #$0E
    beq loc_F171
    cpy #$0F
    beq loc_F171
    lda battle_flags2
    and #$FE
    sta battle_flags2
    lda game_mode
    pha
    lda #$04
    sta game_mode
loc_F18C:
    lda nmi_frame_counter
    and #$0F
    beq loc_F19B
    jsr update_enemies
    jsr update_frame
    jmp loc_F18C
loc_F19B:
    pla
    sta game_mode
    pla
    and #$80
    bne loc_F1A6
    jmp b14_field_transition_a  ; banked call target (bank must be selected first)
loc_F1A6:
    lda #$0A
    jsr sound_queue_add
    ldx #$00
    jsr text_init
    jsr clear_text_state
    jsr text_wait
    jsr find_party_member
    lda #$0E
    jsr set_bank_a
    lda text_menu_index
    jsr dispatch_return_table

data_F1C3:
    .incbin "build/assets/bank15_data.bin", $31C3, $000A
; ----------------------------------------------------------------------
; game_main
;   Main gameplay/field update loop.
; ----------------------------------------------------------------------
game_main:
    jsr update_frame
    jsr text_draw_screen
    jsr set_bank_current
    lda #$00
    sta $71
    jsr update_frame
loc_F1DD:
    lda battle_flags2
    lsr a
    bcs loc_F1E5
    jmp loc_F2AD
loc_F1E5:
    lda battle_state
    and #$0F
    sta battle_state
    bne loc_F1F0
    jmp loc_F272
loc_F1F0:
    cmp #$0E
    beq loc_F1F7
    jmp loc_F3A0
loc_F1F7:
    lda level
    beq loc_F202
    cmp #$02
    beq loc_F202
    jmp loc_F225
loc_F202:
    inc $8D
    lda $8D
    cmp $607C
    bcs loc_F20E
    jmp loc_F225
loc_F20E:
    lda #$00
    sta $8D
    sta ptr0_hi
    sta ptr1_lo
    lda $607D
    sta ptr0_lo
    jsr load_battle_graphics
    adc $B060,y

data_F221:
    .incbin "build/assets/bank15_data.bin", $3221, $0004
loc_F225:
    lda battle_flags2
    and #$40
    beq loc_F24D
    lda battle_flags2
    ora #$02
    sta battle_flags2
    dec $8B
    ldy $8B
    bne loc_F24D
    and #$BD
    sta battle_flags2
    lda #$2A
    sta text_command
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

data_F245:
    .dw b10_msg_index_041    ; text index $0029 -> b10_msg_041
    jsr wait_keypress
    jsr text_draw_screen
loc_F24D:
    lda battle_flags2
    and #$04
    beq loc_F259
    lda $8A
    beq loc_F259
    dec $8A
loc_F259:
    lda $86
    cmp #$FF
    beq loc_F263
    cmp #$10
    bcs loc_F26F
loc_F263:
    lda $0500                   ; Per-actor state flags.
    and #$02
    bne loc_F26F
    lda $0530                   ; Per-actor palette/facing.
    sta party_active
loc_F26F:
    jmp loc_F3A0
loc_F272:
    lda battle_flags2
    and #$04
    beq loc_F294
    ldy $8A
    bne loc_F294
    lda battle_flags2
    and #$FB
    sta battle_flags2
    lda #$2B
    sta text_command
    jsr reset_text_engine
    jsr text_print_inline       ; inline pointer/data follows the JSR

data_F28C:
    .dw b10_msg_index_041    ; text index $0029 -> b10_msg_041
    jsr wait_keypress
    jsr text_draw_screen
loc_F294:
    lda battle_flags2
    and #$FE
    sta battle_flags2
    lda $86
    cmp #$0E
    bne loc_F2A6
    jsr b14_scan_bank7_table_a  ; banked call target (bank must be selected first)
    jmp loc_F2AD
loc_F2A6:
    cmp #$0F
    bne loc_F2AD
    jsr b14_scan_bank7_table_b  ; banked call target (bank must be selected first)
loc_F2AD:
    jsr set_bank_13
    lda #$15
    jsr b13_expand_name_tile    ; banked call target (bank must be selected first)
    bcs loc_F2F1
    lda text_x
    cmp #$06
    bne loc_F2F1
    lda text_y
    cmp #$2C
    bne loc_F2F1
    lda text_x2
    cmp #$04
    bne loc_F2F1
    lda text_y2
    cmp #$0C
    bne loc_F2F1
    lda controller_state
    and #$08
    beq loc_F2F1
    inc $8C
    lda $8C
    cmp #$06
    bne loc_F2F1
    lda #$00
    sta $8C
    sta game_mode
    sta $0530                   ; Per-actor palette/facing.
    lda #$15
    jsr b13_check_name_tile     ; banked call target (bank must be selected first)
    inc $6579
    jsr text_draw_screen
loc_F2F1:
    jsr set_bank_14
    lda controller_prev
    and #$0F
    beq loc_F302
    tay
    lda data_E5E4,y
    cmp #$FF
    bne loc_F305
loc_F302:
    jmp loc_F3EF
loc_F305:
    sta game_mode
    sta $0530                   ; Per-actor palette/facing.
    asl a
    tay
    lda battle_flags2
    ora #$02
    sta battle_flags2
    jsr update_party
    jsr draw_status_panel
    cpy #$0E
    beq loc_F320
    cpy #$0F
    bne loc_F326
loc_F320:
    lda $86
    cmp #$FF
    beq loc_F38F
loc_F326:
    cpy #$10
    bcc loc_F348
    lda $86
    cmp #$FF
    beq loc_F332
    sty $86
loc_F332:
    ldx #$00
    lda $0530,x                 ; Per-actor palette/facing.
    jsr set_actor_palette
    lda frame_counter
    and #$0F
    bne loc_F345
    lda #$0D
    jsr sound_queue_add
loc_F345:
    jmp loc_F3EF
loc_F348:
    cpy #$07
    bne loc_F354
    lda #$0E
    jsr sound_queue_add
    jsr dialogue_sequence
loc_F354:
    lda battle_flags2
    and #$04
    beq loc_F360
    cpy #$06
    bcs loc_F360
    ldy #$00
loc_F360:
    sty $86
    ldx #$00
    lda #$03
    sta ppu_update_ptr_lo
    jsr draw_battle_cursor
    lda $0500                   ; Per-actor state flags.
    and #$02
    beq loc_F38F
    lda $0530,x                 ; Per-actor palette/facing.
    jsr set_actor_palette
    ldx ppu_update_ptr_lo
    lda $05D0,x                 ; Per-actor status bits.
    bmi loc_F38C
    lda #$18
    sta $05B0,x                 ; Per-actor action delay.
    lda $05D0,x                 ; Per-actor status bits.
    ora #$80
    sta $05D0,x                 ; Per-actor status bits.
loc_F38C:
    jmp loc_F3EF
loc_F38F:
    inc battle_flags2
    jsr copy_party_stats
    jsr draw_party_header
    lda #$00
    sta battle_state
    sta menu_state
    jsr party_shift
loc_F3A0:
    jsr update_party_sprites
    lda game_mode
    asl a
    tax
    ldy #$FF
    lda battle_flags2
    and #$02
    beq loc_F3B2
    inx
    ldy #$FE
loc_F3B2:
    sty ppu_update_ptr_lo
    lda data_E660,x
    clc
    adc scroll_y
    cmp ppu_update_ptr_lo
    bne loc_F3C3
    lda ppu_update_ptr_lo
    sec
    sbc #$10
loc_F3C3:
    cmp #$F0
    bne loc_F3C9
    lda #$00
loc_F3C9:
    sta scroll_y
    lda data_E668,x
    bmi loc_F3D9
    clc
    adc scroll_x
    sta scroll_x
    bcs loc_F3E9
    bcc loc_F3EF
loc_F3D9:
    eor #$FF
    clc
    adc #$01
    sta ppu_update_ptr_lo
    lda scroll_x
    sec
    sbc ppu_update_ptr_lo
    sta scroll_x
    bcs loc_F3EF
loc_F3E9:
    lda ppu_ctrl_shadow
    eor #$01
    sta ppu_ctrl_shadow
loc_F3EF:
    jmp random_encounter
; ----------------------------------------------------------------------
; party_shift
;   Shift the party order and update cached actor ids.
;   called by: $F39D
; ----------------------------------------------------------------------
party_shift:
    lda party_prev
    sta party_prev3
    lda party_flags
    sta party_prev2
    sta party_prev
    lda game_mode
    eor #$01
    sta party_flags
    lda $0531                   ; Per-actor palette/facing.
    sta $0532                   ; Per-actor palette/facing.
    lda party_active
    sta $0531                   ; Per-actor palette/facing.
    ldx #$02
loc_F40F:
    lda $0530,x                 ; Per-actor palette/facing.
    jsr set_actor_palette
    lda $05A0,x                 ; Per-actor animation state.
    and #$80
    sta $05A0,x                 ; Per-actor animation state.
    dex
    bpl loc_F40F
    rts
; ----------------------------------------------------------------------
; update_party_sprites
;   Update party member sprite/animation state.
;   called by: $F3A0
; ----------------------------------------------------------------------
update_party_sprites:
    ldx #$02
loc_F423:
    lda $05A0,x                 ; Per-actor animation state.
    and #$9F
    sta $05A0,x                 ; Per-actor animation state.
    lda battle_flags2
    and #$02
    beq loc_F437
    inc $05A0,x                 ; Per-actor animation state.
    inc $05A0,x                 ; Per-actor animation state.
loc_F437:
    inc $05A0,x                 ; Per-actor animation state.
    dex
    bpl loc_F423
    ldx #$01
    lda party_prev2
    jsr get_party_member
    ldx #$02
    lda party_prev3
    jsr get_party_member
    rts
; ----------------------------------------------------------------------
; get_party_member
;   Look up a party member's actor id and stats.
;   called by: $F441, $F448
; ----------------------------------------------------------------------
get_party_member:
    asl a
    tay
    lda data_E5F4,y
    sta copy_src_lo
    iny
    lda data_E5F4,y
    sta copy_src_hi
    lda game_mode
    asl a
    asl a
    tay
    lda battle_flags2
    and #$02
    beq loc_F466
    iny
    iny
loc_F466:
    lda ($18),y
    clc
    adc $0550,x                 ; Per-actor animation frame.
    sta $0550,x                 ; Per-actor animation frame.
    iny
    lda ($18),y
    clc
    adc $0540,x                 ; Per-actor tile/sprite id.
    sta $0540,x                 ; Per-actor tile/sprite id.
    rts
; ----------------------------------------------------------------------
; update_party
;   Update the party roster and map sprites.
;   called by: $F312
; ----------------------------------------------------------------------
update_party:
    lda game_mode
    jsr set_cursor_from_table
    lda #$0C
    jsr set_bank_b
    ldx #$4F
loc_F486:
    lda b12_data_8C00,x
    cmp cursor_x
    bne loc_F4C3
    lda $8C58,x
    cmp cursor_y
    bne loc_F4C3
    lda $8CB0,x
    cmp cursor_x2
    bne loc_F4C3
    lda $8D08,x
    cmp cursor_y2
    bne loc_F4C3
    lda $6500,x
    bne loc_F4C3
    stx game_submode
    jsr set_bank_current
    ldx #$00
    lda $0530,x                 ; Per-actor palette/facing.
    jsr set_actor_palette
    lda #$10
    sta $86
    lda battle_flags2
    and #$FE
    sta battle_flags2
    pla
    pla
    jmp b14_field_transition_b  ; banked call target (bank must be selected first)
loc_F4C3:
    dex
    bpl loc_F486
    jmp set_bank_current
; ----------------------------------------------------------------------
; battle_calc
;   Battle damage/stat calculation helper.
;   called by: $F15E
; ----------------------------------------------------------------------
battle_calc:
    lda $6011
    cmp #$01
    bne loc_F4D4
    lda level
    beq loc_F4FE
loc_F4D4:
    cpy #$02
    bcc loc_F4FE
    lda rng1
    clc
    adc rng2
    sta rng1
    lda rng0
    clc
    adc rng1
    sta rng0
    and data_F517,y
    bne loc_F4FE
    lda rng2
    clc
    adc rng3
    sta rng2
    lda rng0
    clc
    adc rng2
    sta rng0
    and data_F51D,y
    beq loc_F4FF
loc_F4FE:
    rts
loc_F4FF:
    lda $0530                   ; Per-actor palette/facing.
    sta party_active
    lda #$10
    sta $86
    lda battle_flags2
    and #$FE
    sta battle_flags2
    lda #$80
    sta game_submode
    pla
    pla
    jmp b14_field_transition_b  ; banked call target (bank must be selected first)

data_F517:
    .incbin "build/assets/bank15_data.bin", $3517, $0006

data_F51D:
    .incbin "build/assets/bank15_data.bin", $351D, $0006
; ----------------------------------------------------------------------
; random_encounter
;   Random encounter check while walking.
; ----------------------------------------------------------------------
random_encounter:
    lda frame_counter
    and #$0F
    bne loc_F52F
    jsr draw_text_window
    jmp battle_tick_thunk
loc_F52F:
    lda battle_flags2
    lsr a
    bcs loc_F537
    jmp battle_tick_thunk
loc_F537:
    lda #$F6
    pha
    lda #$9D
    pha
    lda battle_state
    lsr a
    bcc loc_F543
    rts
loc_F543:
    lda menu_state
    inc menu_state
    jsr dispatch_return_table

data_F54A:
    .incbin "build/assets/bank15_data.bin", $354A, $0012
; ----------------------------------------------------------------------
; draw_party_window
;   Draw the party window headers.
;   called by: $CDF4, $D98B
; ----------------------------------------------------------------------
draw_party_window:
    lda map_x
    sta cursor_x
    lda map_y
    sta cursor_y
    lda map_x2
    sta cursor_x2
    lda map_y2
    sta cursor_y2
    lda #$09
    sta copy_src_lo
    bne loc_F589
; ----------------------------------------------------------------------
; draw_party_status
;   Draw the party status list.
;   called by: $CDF1, $D988
; ----------------------------------------------------------------------
draw_party_status:
    ldy game_mode
    lda data_F6A1,y
    jsr cursor_add_x
    ldy game_mode
    lda data_F6A5,y
    jsr cursor_add_y
    jsr cursor_to_ppu
    lda #$00
    sta copy_src_lo
loc_F589:
    jsr draw_map_area
    lda #$00
    sta ppu_addr_lo
    ldx class_index
    lda data_F6C9,x
    sta ppu_addr_hi
    lda #$03
    sta ppu_update_ptr_lo
    lda copy_src_lo
    asl a
    sta ppu_update_ptr_hi
loc_F5A0:
    lda game_mode
    asl a
    asl a
    adc ppu_update_ptr_lo
    tax
    lda data_F6CC,x
    adc ppu_update_ptr_hi
    tax
    lda ($14),y
    sta $0360,x                 ; Saved text tile rows for window redraw.
    inc ppu_addr_hi
    dec ppu_update_ptr_lo
    bpl loc_F5A0
    jsr tile_address
    lda ($14),y
    sta ppu_update_ptr_lo
    lda #$FC
    sta ppu_update_ptr_hi
    lda cursor_x
    lsr a
    bcc loc_F5D9
    asl ppu_update_ptr_lo
    asl ppu_update_ptr_lo
    asl ppu_update_ptr_lo
    asl ppu_update_ptr_lo
    sec
    rol ppu_update_ptr_hi
    rol ppu_update_ptr_hi
    rol ppu_update_ptr_hi
    rol ppu_update_ptr_hi
loc_F5D9:
    lda cursor_x2
    lsr a
    bcc loc_F5E7
    asl ppu_update_ptr_lo
    asl ppu_update_ptr_lo
    sec
    rol ppu_update_ptr_hi
    rol ppu_update_ptr_hi
loc_F5E7:
    lda $0780,x
    and ppu_update_ptr_hi
    ora ppu_update_ptr_lo
    sta $0780,x
    lda copy_src_lo
    bne loc_F5F7
    stx battle_cursor
loc_F5F7:
    lda game_mode
    asl a
    tay
    lda data_F6E0,y
    jsr cursor_add_x_signed
    iny
    lda data_F6E0,y
    jsr cursor_add_y_signed
    inc copy_src_lo
    lda copy_src_lo
    cmp #$09
    beq loc_F61A
    ldx game_mode
    cmp data_F6DC,x
    beq loc_F62A
    jmp loc_F589
loc_F61A:
    lda cursor_x
    sta map_x
    lda cursor_y
    sta map_y
    lda cursor_x2
    sta map_x2
    lda cursor_y2
    sta map_y2
loc_F62A:
    lda #$0E
    jsr set_bank_b
    rts
; ----------------------------------------------------------------------
; draw_party_column_a
;   Draw one party status column (left).
;   called by: $D98E
; ----------------------------------------------------------------------
draw_party_column_a:
    ldx game_mode
    lda ppu_addr_lo_shadow
    clc
    adc data_F6B1,x
    sta ppu_addr_lo_shadow
    lda data_F6B9,x
    sta tile_attr
    lda data_F6BD,x
    ldy data_F6C1,x
    tax
    jmp draw_tile_run
; ----------------------------------------------------------------------
; draw_party_column_b
;   Draw one party status column (right).
;   called by: $D994
; ----------------------------------------------------------------------
draw_party_column_b:
    ldx game_mode
    lda ppu_addr_lo_shadow
    clc
    adc data_F6B5,x
    sta ppu_addr_lo_shadow
    lda data_F6B9,x
    sta tile_attr
    lda data_F6BD,x
    ldy data_F6C5,x
    tax
    jmp draw_tile_run
; ----------------------------------------------------------------------
; draw_party_header
;   Draw the party header/name row.
;   called by: $CDEE, $D985, $F394
; ----------------------------------------------------------------------
draw_party_header:
    lda game_mode
    asl a
    tay
    lda data_F6A9,y
    jsr cursor_add_x
    iny
    lda data_F6A9,y
    jsr cursor_add_y
    lda cursor_x
    sta text_x
    sta $0560                   ; Per-actor map/world X.
    lda cursor_y
    sta text_y
    sta $0570                   ; Per-actor map/world Y.
    lda cursor_x2
    sta text_x2
    sta $0580                   ; Per-actor screen X.
    lda cursor_y2
    sta text_y2
    sta $0590                   ; Per-actor screen Y.
    rts
; ----------------------------------------------------------------------
; draw_party_footer
;   Draw the party window footer.
;   called by: $CE09, $D991
; ----------------------------------------------------------------------
draw_party_footer:
    ldx #$0A
    lda tile_attr
    bpl loc_F698
    ldx #$08
loc_F698:
    stx tile_id_base
    jsr draw_map_object
    rts
; ----------------------------------------------------------------------
; battle_tick_thunk
;   Battle tick thunk; falls through to battle_tick.
; ----------------------------------------------------------------------
battle_tick_thunk:
    jmp battle_tick

data_F6A1:
    .incbin "build/assets/bank15_data.bin", $36A1, $0004

data_F6A5:
    .incbin "build/assets/bank15_data.bin", $36A5, $0004

data_F6A9:
    .incbin "build/assets/bank15_data.bin", $36A9, $0008

data_F6B1:
    .incbin "build/assets/bank15_data.bin", $36B1, $0004

data_F6B5:
    .incbin "build/assets/bank15_data.bin", $36B5, $0004

data_F6B9:
    .incbin "build/assets/bank15_data.bin", $36B9, $0004

data_F6BD:
    .incbin "build/assets/bank15_data.bin", $36BD, $0004

data_F6C1:
    .incbin "build/assets/bank15_data.bin", $36C1, $0004

data_F6C5:
    .incbin "build/assets/bank15_data.bin", $36C5, $0004

data_F6C9:
    .incbin "build/assets/bank15_data.bin", $36C9, $0003

data_F6CC:
    .incbin "build/assets/bank15_data.bin", $36CC, $0010

data_F6DC:
    .incbin "build/assets/bank15_data.bin", $36DC, $0004

data_F6E0:
    .incbin "build/assets/bank15_data.bin", $36E0, $0008

; ----------------------------------------------------------------------
; battle_tick
;   Battle tick wrapper.
; ----------------------------------------------------------------------
battle_tick:
    jsr battle_update
    jmp game_mode_switch
; ----------------------------------------------------------------------
; battle_update
;   Per-frame battle update.
;   called by: $F6E8
; ----------------------------------------------------------------------
battle_update:
    lda battle_state
    cmp #$0C
    bne loc_F6FB
    lda #$00
    sta nmi_frame_counter
    jsr init_battle
loc_F6FB:
    jsr update_enemies
    jsr update_oam
    jsr hide_sprites
    lda battle_state
    lsr a
    bcs loc_F711
    lda battle_flags2
    and #$02
    beq loc_F711
    inc battle_state
loc_F711:
    inc battle_state
    lda battle_state
    and #$0F
    sta battle_state
    jsr wait_vblank
    rts
; ----------------------------------------------------------------------
; update_enemies
;   Update all active enemies.
;   called by: $F192, $F6FB, $F908
; ----------------------------------------------------------------------
update_enemies:
    ldx #$03
loc_F71F:
    lda $0500,x                 ; Per-actor state flags.
    asl a
    bcc loc_F72B
    jsr enemy_action
    jsr draw_enemy
loc_F72B:
    inx
    cpx #$10
    bne loc_F71F
    rts
; ----------------------------------------------------------------------
; enemy_action
;   Run one enemy's action.
;   called by: $F725
; ----------------------------------------------------------------------
enemy_action:
    lda $0500,x                 ; Per-actor state flags.
    and #$0C
    bne loc_F765
    lda $0500,x                 ; Per-actor state flags.
    and #$20
    bne loc_F74A
    lda $05B0,x                 ; Per-actor action delay.
    beq loc_F765
    dec $05B0,x                 ; Per-actor action delay.
    jmp loc_F765
loc_F74A:
    lda $05C0,x                 ; Per-actor current HP.
    inc $05C0,x                 ; Per-actor current HP.
    cmp #$10
    bne loc_F75E
    lda $0500,x                 ; Per-actor state flags.
    and #$DF
    sta $0500,x                 ; Per-actor state flags.
    bne loc_F765
loc_F75E:
    lda $0530,x                 ; Per-actor palette/facing.
    tay
    jsr enemy_move_a
loc_F765:
    rts
; ----------------------------------------------------------------------
; enemy_move_a
;   Move an enemy (variant A).
;   called by: $F762
; ----------------------------------------------------------------------
enemy_move_a:
    lda data_F90C,y
    clc
    adc $0540,x                 ; Per-actor tile/sprite id.
    jsr clamp_enemy_pos
    lda data_F911,y
    clc
    adc $0550,x                 ; Per-actor animation frame.
    sta $0550,x                 ; Per-actor animation frame.
    rts
; ----------------------------------------------------------------------
; enemy_move_b
;   Move an enemy (variant B).
;   called by: $F87E
; ----------------------------------------------------------------------
enemy_move_b:
    lda data_F916,y
    clc
    adc $0540,x                 ; Per-actor tile/sprite id.
    jsr clamp_enemy_pos
    lda data_F920,y
    clc
    adc $0550,x                 ; Per-actor animation frame.
    sta $0550,x                 ; Per-actor animation frame.
    rts
; ----------------------------------------------------------------------
; clamp_enemy_pos
;   Clamp/wrap an enemy position.
;   called by: $F76D, $F782
; ----------------------------------------------------------------------
clamp_enemy_pos:
    cmp #$FD
    beq loc_F798
    cmp #$FC
    bne loc_F79C
loc_F798:
    and #$EF
    bne loc_F7AA
loc_F79C:
    cmp #$EF
    bne loc_F7A4
    lda #$FF
    beq loc_F7AA
loc_F7A4:
    cmp #$EE
    bne loc_F7AA
    lda #$FE
loc_F7AA:
    sta $0540,x                 ; Per-actor tile/sprite id.
    rts
; ----------------------------------------------------------------------
; draw_enemy
;   Draw one enemy and its HP/status.
;   called by: $F728
; ----------------------------------------------------------------------
draw_enemy:
    txa
    pha
    lda #$F8
    jsr cursor_add_x
    lda cursor_x
    sta copy_src_lo
    lda cursor_y
    sta copy_src_hi
    lda #$F7
    jsr cursor_add_y
    lda cursor_x2
    sta copy_dst_lo
    lda cursor_y2
    sta copy_dst_hi
    lda #$08
    jsr cursor_add_x
    lda #$08
    jsr cursor_add_y
    pla
    tax
    lda copy_src_hi
    cmp $0570,x                 ; Per-actor map/world Y.
    bcc loc_F7E6
    bne loc_F816
    lda $0560,x                 ; Per-actor map/world X.
    cmp copy_src_lo
    bcc loc_F816
loc_F7E6:
    lda cursor_y
    cmp $0570,x                 ; Per-actor map/world Y.
    bcc loc_F816
    bne loc_F7F6
    lda cursor_x
    cmp $0560,x                 ; Per-actor map/world X.
    bcc loc_F816
loc_F7F6:
    lda copy_dst_hi
    cmp $0590,x                 ; Per-actor screen Y.
    bcc loc_F806
    bne loc_F816
    lda $0580,x                 ; Per-actor screen X.
    cmp copy_dst_lo
    bcc loc_F816
loc_F806:
    lda cursor_y2
    cmp $0590,x                 ; Per-actor screen Y.
    bcc loc_F816
    bne loc_F820
    lda cursor_x2
    cmp $0580,x                 ; Per-actor screen X.
    bcs loc_F820
loc_F816:
    lda $0500,x                 ; Per-actor state flags.
    ora #$01
    sta $0500,x                 ; Per-actor state flags.
    bne loc_F86E
loc_F820:
    lda $0500,x                 ; Per-actor state flags.
    and #$FE
    sta $0500,x                 ; Per-actor state flags.
    lda $0570,x                 ; Per-actor map/world Y.
    cmp text_y
    bcc loc_F841
    bne loc_F838
    lda $0560,x                 ; Per-actor map/world X.
    cmp text_x
    bcc loc_F841
loc_F838:
    lda $05D0,x                 ; Per-actor status bits.
    and #$F3
    ora #$04
    bne loc_F848
loc_F841:
    lda $05D0,x                 ; Per-actor status bits.
    and #$F3
    ora #$08
loc_F848:
    sta $05D0,x                 ; Per-actor status bits.
    lda $0590,x                 ; Per-actor screen Y.
    cmp text_y2
    bcc loc_F864
    bne loc_F85B
    lda $0580,x                 ; Per-actor screen X.
    cmp text_x2
    bcc loc_F864
loc_F85B:
    lda $05D0,x                 ; Per-actor status bits.
    and #$FC
    ora #$01
    bne loc_F86B
loc_F864:
    lda $05D0,x                 ; Per-actor status bits.
    and #$FC
    ora #$02
loc_F86B:
    sta $05D0,x                 ; Per-actor status bits.
loc_F86E:
    lda battle_flags2
    lsr a
    bcc loc_F881
    lda game_mode
    asl a
    tay
    lda battle_flags2
    and #$02
    beq loc_F87E
    iny
loc_F87E:
    jsr enemy_move_b
loc_F881:
    rts
; ----------------------------------------------------------------------
; update_enemy_pos
;   Update an enemy's screen position.
;   called by: $F900
; ----------------------------------------------------------------------
update_enemy_pos:
    lda copy_src_lo
    clc
    adc #$01
    cmp #$0F
    bne loc_F88D
    lda #$00
loc_F88D:
    sta ppu_update_ptr_lo
    lda $0560,x                 ; Per-actor map/world X.
    cmp ppu_update_ptr_lo
    bcc loc_F89F
    lda $0560,x                 ; Per-actor map/world X.
    sec
    sbc ppu_update_ptr_lo
    jmp loc_F8A8
loc_F89F:
    lda #$0F
    sec
    sbc ppu_update_ptr_lo
    clc
    adc $0560,x                 ; Per-actor map/world X.
loc_F8A8:
    asl a
    asl a
    asl a
    asl a
    sec
    sbc #$02
    sta $0540,x                 ; Per-actor tile/sprite id.
    lda copy_dst_lo
    clc
    adc #$01
    and #$0F
    sta ppu_update_ptr_lo
    lda $0580,x                 ; Per-actor screen X.
    cmp ppu_update_ptr_lo
    bcc loc_F8CB
    lda $0580,x                 ; Per-actor screen X.
    sec
    sbc ppu_update_ptr_lo
    jmp loc_F8D4
loc_F8CB:
    lda #$10
    sec
    sbc ppu_update_ptr_lo
    clc
    adc $0580,x                 ; Per-actor screen X.
loc_F8D4:
    asl a
    asl a
    asl a
    asl a
    sta $0550,x                 ; Per-actor animation frame.
    rts
; ----------------------------------------------------------------------
; battle_main
;   Battle main loop.
;   called by: $F0F7
; ----------------------------------------------------------------------
battle_main:
    jsr battle_screen
    lda #$F8
    jsr cursor_add_x
    lda cursor_x
    sta copy_src_lo
    lda cursor_y
    sta copy_src_hi
    lda #$F7
    jsr cursor_add_y
    lda cursor_x2
    sta copy_dst_lo
    lda cursor_y2
    sta copy_dst_hi
    ldx #$03
loc_F8FB:
    lda $0500,x                 ; Per-actor state flags.
    bpl loc_F903
    jsr update_enemy_pos
loc_F903:
    inx
    cpx #$10
    bne loc_F8FB
    jsr update_enemies
    rts

data_F90C:
    .incbin "build/assets/bank15_data.bin", $390C, $0005

data_F911:
    .incbin "build/assets/bank15_data.bin", $3911, $0005

data_F916:
    .incbin "build/assets/bank15_data.bin", $3916, $000A

data_F920:
    .incbin "build/assets/bank15_data.bin", $3920, $000A
; ----------------------------------------------------------------------
; init_battle
;   Initialise battle state and actors.
;   called by: $F6F8
; ----------------------------------------------------------------------
init_battle:
    ldx #$03
loc_F92C:
    lda $0500,x                 ; Per-actor state flags.
    bpl loc_F978
    and #$08
    bne loc_F978
    lda $05B0,x                 ; Per-actor action delay.
    bne loc_F978
    lda #$00
    sta $05C0,x                 ; Per-actor current HP.
    lda $05D0,x                 ; Per-actor status bits.
    and #$7F
    sta $05D0,x                 ; Per-actor status bits.
    lda rng1
    clc
    adc rng2
    sta rng1
    clc
    adc rng0
    sta rng0
    tay
    and #$0F
    ora #$70
    sta $05B0,x                 ; Per-actor action delay.
    tya
    jsr set_actor_palette
    jsr set_party_cursor
    cpy #$06
    bcs loc_F978
    jsr set_battle_cursor
    lda $0500,x                 ; Per-actor state flags.
    and #$02
    bne loc_F978
    lda $0500,x                 ; Per-actor state flags.
    ora #$20
    sta $0500,x                 ; Per-actor state flags.
loc_F978:
    inx
    cpx #$10
    bne loc_F92C
    rts
; ----------------------------------------------------------------------
; set_battle_cursor
;   Set the battle cursor to a party member.
;   called by: $F966
; ----------------------------------------------------------------------
set_battle_cursor:
    lda #$00
    sta ppu_update_ptr_lo
; ----------------------------------------------------------------------
; draw_battle_cursor
;   Draw the battle cursor.
;   called by: $F368
; ----------------------------------------------------------------------
draw_battle_cursor:
    lda $0560,x                 ; Per-actor map/world X.
    sta cursor_x
    lda $0570,x                 ; Per-actor map/world Y.
    sta cursor_y
    lda $0580,x                 ; Per-actor screen X.
    sta cursor_x2
    lda $0590,x                 ; Per-actor screen Y.
    sta cursor_y2
    lda $0530,x                 ; Per-actor palette/facing.
; ----------------------------------------------------------------------
; find_next_actor
;   Find the next active actor/party member.
; ----------------------------------------------------------------------
find_next_actor:
    jsr set_cursor_no_save
; ----------------------------------------------------------------------
; find_next_actor_from_x
;   Find the next active actor starting from X (no cursor-table setup).
; ----------------------------------------------------------------------
find_next_actor_from_x:
    stx ppu_update_off
    ldx ppu_update_ptr_lo
loc_F9A0:
    lda $0500,x                 ; Per-actor state flags.
    bpl loc_F9AE
    cpx ppu_update_off
    beq loc_F9AE
    jsr check_battle_cursor
    bcs loc_F9D6
loc_F9AE:
    inx
    cpx #$10
    bne loc_F9A0
    ldx ppu_update_off
    cpx #$00
    beq loc_F9CD
    lda cursor_x
    sta $0560,x                 ; Per-actor map/world X.
    lda cursor_y
    sta $0570,x                 ; Per-actor map/world Y.
    lda cursor_x2
    sta $0580,x                 ; Per-actor screen X.
    lda cursor_y2
    sta $0590,x                 ; Per-actor screen Y.
loc_F9CD:
    lda $0500,x                 ; Per-actor state flags.
    and #$FD
    sta $0500,x                 ; Per-actor state flags.
    rts
loc_F9D6:
    lda $0500,x                 ; Per-actor state flags.
    ora #$02
    sta $0500,x                 ; Per-actor state flags.
    stx ppu_update_ptr_lo
    ldx ppu_update_off
    lda $0500,x                 ; Per-actor state flags.
    ora #$02
    sta $0500,x                 ; Per-actor state flags.
    rts
; ----------------------------------------------------------------------
; check_battle_cursor
;   Check whether the battle cursor is on a valid target.
;   called by: $F9A9
; ----------------------------------------------------------------------
check_battle_cursor:
    lda $0500,x                 ; Per-actor state flags.
    bpl loc_FA0E
    lda $0560,x                 ; Per-actor map/world X.
    cmp cursor_x
    bne loc_FA0E
    lda $0570,x                 ; Per-actor map/world Y.
    cmp cursor_y
    bne loc_FA0E
    lda $0580,x                 ; Per-actor screen X.
    cmp cursor_x2
    bne loc_FA0E
    lda $0590,x                 ; Per-actor screen Y.
    cmp cursor_y2
    bne loc_FA0E
    sec
    rts
loc_FA0E:
    clc
    rts
; ----------------------------------------------------------------------
; read_inline_offset
;   Read an inline pointer and add a caller-supplied offset.
; ----------------------------------------------------------------------
read_inline_offset:
    stx ppu_update_ptr_lo
    sty ppu_update_ptr_hi
    jsr fetch_inline_word       ; inline pointer/data follows the JSR
data_FA17:
    ldy #$00
    beq loc_FA24
    stx ppu_update_ptr_lo
    sty ppu_update_ptr_hi
    jsr fetch_inline_word       ; inline pointer/data follows the JSR

data_FA22:
    .incbin "build/assets/bank15_data.bin", $3A22, $0002
loc_FA24:
    clc
    lda ($00),y
    adc ptr0_lo
    sta ($00),y
    iny
    lda ($00),y
    adc ptr0_hi
    sta ($00),y
    iny
    lda ($00),y
    adc ptr1_lo
    sta ($00),y
    ldx ppu_update_ptr_lo
    ldy ppu_update_ptr_hi
    rts
; ----------------------------------------------------------------------
; load_battle_graphics
;   Load battle graphics.
;   called by: $F21B
; ----------------------------------------------------------------------
load_battle_graphics:
    stx ppu_update_ptr_lo
    sty ppu_update_ptr_hi
    jsr fetch_inline_word       ; inline pointer/data follows the JSR

data_FA45:
    .incbin "build/assets/bank15_data.bin", $3A45, $0002
    beq loc_FA52
; ----------------------------------------------------------------------
; load_battle_tiles
;   Load battle tile sets.
;   called by: $E59A
; ----------------------------------------------------------------------
load_battle_tiles:
    stx ppu_update_ptr_lo
    sty ppu_update_ptr_hi
    jsr fetch_inline_word       ; inline pointer/data follows the JSR

data_FA50:
    .incbin "build/assets/bank15_data.bin", $3A50, $0002
loc_FA52:
    iny
    iny
    lda ($00),y
    cmp ptr1_lo
    bcc loc_FA6E
    bne loc_FA7F
    dey
    lda ($00),y
    cmp ptr0_hi
    bcc loc_FA6F
    bne loc_FA80
    dey
    lda ($00),y
    cmp ptr0_lo
    bcs loc_FA81
    bcc loc_FA70
loc_FA6E:
    dey
loc_FA6F:
    dey
loc_FA70:
    lda ($00),y
    sta ptr0_lo
    iny
    lda ($00),y
    sta ptr0_hi
    iny
    lda ($00),y
    sta ptr1_lo
    clc
loc_FA7F:
    dey
loc_FA80:
    dey
loc_FA81:
    php
    sec
    lda ($00),y
    sbc ptr0_lo
    sta ($00),y
    iny
    lda ($00),y
    sbc ptr0_hi
    sta ($00),y
    iny
    lda ($00),y
    sbc ptr1_lo
    sta ($00),y
    plp
    ldx ppu_update_ptr_lo
    ldy ppu_update_ptr_hi
    rts
; ----------------------------------------------------------------------
; read_input_state
;   Read controller state with repeat/edge handling.
;   called by: $C043
; ----------------------------------------------------------------------
read_input_state:
    ldx #$AC
    ldy #$04
    lda $00,x
    and #$02
    sta sound_ptr
    lda $01,x
    and #$02
    eor sound_ptr
    clc
    beq loc_FAB1
    sec
loc_FAB1:
    ror $00,x
    inx
    dey
    bne loc_FAB1
    lda rng0
    clc
    adc #$05
    sta rng0
    lda rng1
    clc
    adc #$07
    sta rng1
    lda rng2
    clc
    adc #$0B
    sta rng2
    lda rng3
    clc
    adc #$0D
    sta rng3
    rts

data_FAD4:
    .incbin "build/assets/bank15_data.bin", $3AD4, $00EE

; ----------------------------------------------------------------------
; nop_return2
;   No-op returning immediately.
;   called by: $F078
; ----------------------------------------------------------------------
nop_return2:
    rts

data_FBC3:
    .incbin "build/assets/bank15_data.bin", $3BC3, $02B6

data_FE79:
    .incbin "build/assets/bank15_data.bin", $3E79, $015F

; ----------------------------------------------------------------------
; reset_vector
;   Reset vector.  Resets MMC1 and jumps to reset_init.
; ----------------------------------------------------------------------
reset_vector:
    sei                         ; Reset vector: MMC1 reset then reset_init.
data_FFD9:
    inc data_FFD9
    jmp reset_init

data_FFDF:
    .incbin "build/assets/bank15_data.bin", $3FDF, $001A

data_FFF9:
    .incbin "build/assets/bank15_data.bin", $3FF9, $0001

b15_vectors:
    .incbin "build/assets/bank15_data.bin", $3FFA, $0006
