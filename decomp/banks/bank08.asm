; ======================================================================
; PRG bank 08  CPU $8000-$BFFF
; ======================================================================
; traced code: 1218 instructions / 2327 bytes; CDL code bytes: 2122
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$8A4F  b08_sound_driver: Music/sound driver code.
;   $8A50-$BFFF  b08_sound_data: Music/sound data and tables.
; ======================================================================

; Overlapping data aliases (tables referenced inside instructions)
b08_data_8400 = $8400

; Region aliases
b08_sound_driver = $8000

; ----------------------------------------------------------------------
; sound_update
;   Sound driver tick/update entry.
; ----------------------------------------------------------------------
sound_update:
    jmp sound_sequencer_update
; ----------------------------------------------------------------------
; sound_play
;   Sound driver command entry (A = command, X = parameter).
; ----------------------------------------------------------------------
sound_play:
    cmp #$FC
    bne b08_loc_800A
    jmp sound_stop
b08_loc_800A:
    cmp #$FD
    bne b08_loc_8011
    jmp sound_pause
b08_loc_8011:
    cmp #$FE
    bne b08_loc_8020
    lda #$01
    sta $C4
    lda #$00
    sta $CC
    jmp b08_loc_813A
b08_loc_8020:
    cmp #$FF
    bne b08_loc_802F
    lda #$01
    sta $C4
    lda #$00
    sta $CC
    jmp sound_channel_stop
b08_loc_802F:
    asl a
    tax
    lda b08_sound_data,x
    sta $C2
    lda b08_data_8A51,x
    sta $C3
    ldy #$00
    lda ($C2),y
    tax
    and #$0F
    beq b08_loc_80BB
    lda $C0
    and #$0F
    sta $C5
    cpx $C5
    bcs b08_loc_804F
    rts
b08_loc_804F:
    stx $C5
    lda $C0
    and #$F0
    ora $C5
    sta $C0
    lda #$01
    sta $C4
    lda #$00
    sta $CC
    lda #$00
    sta $C7
    sta $C8
    lda #$04
    sta $C5
    lda #$01
b08_loc_806D:
    clc
    adc $C2
    sta $C2
    lda #$00
    adc $C3
    sta $C3
    ldx $CC
    ldy #$00
b08_loc_807C:
    lda ($C2),y
    sta $0700,x
    inx
    iny
    cpy #$02
    bne b08_loc_807C
    ldy #$0E
    lda #$00
b08_loc_808B:
    sta $0700,x
    inx
    dey
    bne b08_loc_808B
    lda $C1
    lsr a
    bcs b08_loc_809A
    jsr sound_channel_clear
b08_loc_809A:
    jsr sound_channel_next
    dec $C5
    beq b08_loc_80A6
    lda #$02
    jmp b08_loc_806D
b08_loc_80A6:
    ldy #$02
    lda ($C2),y
    sta $077C
    iny
    lda ($C2),y
    sta $077D
    jsr sound_channel_shift
    lda #$00
    sta $C4
    rts
b08_loc_80BB:
    lda $C0
    and #$F0
    sta $C5
    cpx $C5
    bcs b08_loc_80C6
    rts
b08_loc_80C6:
    stx $C5
    lda $C0
    and #$0F
    ora $C5
    sta $C0
    lda #$01
    sta $C4
    lda #$00
    sta $CC
    ldx #$00
    lda #$02
    clc
    adc $C2
    sta $D0
    txa
    adc $C3
    sta $D1
    stx $D2
    stx $D3
    ldy #$01
    lda ($C2),y
    and #$0F
    tax
    ora $C1
    pha
    stx $C1
    lda #$04
    sta $C5
    lda #$02
    sta $C6
b08_loc_80FE:
    pla
    lsr a
    pha
    bcc b08_loc_810E
    jsr sound_channel_clear
    lda $C1
    lsr a
    bcs b08_loc_810E
    jsr sound_channel_start
b08_loc_810E:
    jsr sound_channel_next
    lda #$04
    clc
    adc $C6
    sta $C6
    dec $C5
    bne b08_loc_80FE
    jsr sound_channel_shift
    lda $C1
    sta $CF
    pla
    lda #$00
    sta $C4
    rts
; ----------------------------------------------------------------------
; sound_stop
;   Stop the current sound.
; ----------------------------------------------------------------------
sound_stop:
    iny
    sty $C7
    rts
; ----------------------------------------------------------------------
; sound_pause
;   Pause/resume sound output.
; ----------------------------------------------------------------------
sound_pause:
    sty $C8
    lda #$01
    sta $C9
    lda $CA
    and #$01
    sta $CA
    rts
b08_loc_813A:
    lda $C0
    and #$0F
    sta $C0
    lda #$04
    sta $C5
    lda #$02
    sta $C6
b08_loc_8148:
    lda $C1
    lsr a
    bcc b08_loc_8153
    jsr sound_channel_clear
    jsr sound_channel_start
b08_loc_8153:
    jsr sound_channel_next
    lda #$04
    clc
    adc $C6
    sta $C6
    dec $C5
    bne b08_loc_8148
    lda #$00
    sta $C1
    sta $CF
    lda #$00
    sta $C4
    rts
; ----------------------------------------------------------------------
; sound_channel_start
;   Start/restart one sound channel from its current pattern.
;   called by: $810B, $8150
; ----------------------------------------------------------------------
sound_channel_start:
    lda $CC
    clc
    adc #$0A
    tax
    lda $0700,x
    ora $0701,x
    bne b08_loc_81C4
    ldy $C5
    ldx $C6
    jsr sound_channel_enable
    ldx $CC
    lda $0700,x
    ora $0701,x
    bne b08_loc_81C4
    rts
; ----------------------------------------------------------------------
; sound_channel_stop
;   Stop a channel and clear its state.
; ----------------------------------------------------------------------
sound_channel_stop:
    lda $C0
    and #$F0
    sta $C0
    lda #$00
    sta $C7
    sta $C8
    lda #$04
    sta $C5
b08_loc_819C:
    lda #$00
    ldx $CC
    sta $0700,x
    sta $0701,x
    jsr sound_channel_advance
    dec $C5
    bne b08_loc_819C
    lda #$00
    sta $C4
    rts
; ----------------------------------------------------------------------
; sound_channel_clear
;   Clear one channel's 16-byte working area.
;   called by: $8097, $8103, $814D
; ----------------------------------------------------------------------
sound_channel_clear:
    ldy #$0F
    lda #$10
    clc
    adc $CC
    tax
    lda #$00
b08_loc_81BC:
    sta $0700,x
    inx
    dey
    bne b08_loc_81BC
    rts
b08_loc_81C4:
    lda $C5
    pha
    lda $C6
    pha
    lda $077C
    sta $C5
    lda $077D
    sta $C6
    lda $CC
    clc
    adc #$06
    tax
    lda $0700,x
    and #$1F
    beq b08_loc_81EA
    tay
    lda #$00
b08_loc_81E4:
    clc
    adc #$04
    dey
    bne b08_loc_81E4
b08_loc_81EA:
    tay
    txa
    clc
    adc #$0E
    tax
    lda #$04
b08_loc_81F2:
    pha
    lda ($C5),y
    sta $0700,x
    iny
    inx
    pla
    sec
    sbc #$01
    bne b08_loc_81F2
    pla
    sta $C6
    pla
    sta $C5
    rts
; ----------------------------------------------------------------------
; sound_channel_next
;   Advance the channel's pattern pointer and update the loop count.
;   called by: $809A, $810E, $8153
; ----------------------------------------------------------------------
sound_channel_next:
    lsr $C1
    bcc sound_channel_advance
    lda $C1
    ora #$80
    sta $C1
; ----------------------------------------------------------------------
; sound_channel_advance
;   Advance the channel pointer by one record.
;   called by: $81A6
; ----------------------------------------------------------------------
sound_channel_advance:
    lda #$1F
    clc
    adc $CC
    sta $CC
    rts
; ----------------------------------------------------------------------
; sound_channel_shift
;   Shift/scale the channel's note value.
;   called by: $80B3, $811C
; ----------------------------------------------------------------------
sound_channel_shift:
    lsr $C1
    lsr $C1
    lsr $C1
    lsr $C1
    rts
; ----------------------------------------------------------------------
; sound_channel_enable
;   Enable/disable an APU channel and write its initial registers.
;   called by: $817E, $8289, $867A
; ----------------------------------------------------------------------
sound_channel_enable:
    cpy #$01
    beq b08_loc_822F
    lda #$00
    sta $4000,x
    sta $4001,x
    rts
b08_loc_822F:
    lda #$07
    sta APUSTATUS
    rts
; ----------------------------------------------------------------------
; sound_sequencer_update
;   Main sequencer tick: walk active channels and decode the next event.
; ----------------------------------------------------------------------
sound_sequencer_update:
    inc $CA
    lda $C4
    beq b08_loc_823C
    rts
b08_loc_823C:
    ldx #$00
    ldy #$07
    stx $CC
    sty $CD
    lda #$00
    sta $CB
    lda #$04
    sta $CE
b08_loc_824C:
    lda #$01
    ldy #$18
    clc
    adc ($CC),y
    sta ($CC),y
    lda #$01
    ldy #$1D
    clc
    adc ($CC),y
    sta ($CC),y
    lda $CF
    lsr a
    bcc b08_loc_8266
    jsr sound_decode_pattern
b08_loc_8266:
    ldy #$00
    lda ($CC),y
    iny
    ora ($CC),y
    beq b08_loc_827E
    lda #$01
    ldy #$0E
    clc
    adc ($CC),y
    sta ($CC),y
    jsr sound_update_envelope
    jmp b08_loc_828C
b08_loc_827E:
    lda $CF
    lsr a
    bcs b08_loc_828C
    ldx $CB
    inx
    inx
    ldy $CE
    jsr sound_channel_enable
b08_loc_828C:
    lsr $CF
    bcc b08_loc_8296
    lda $CF
    ora #$80
    sta $CF
b08_loc_8296:
    dec $CE
    beq b08_loc_82B1
    lda #$04
    clc
    adc $CB
    sta $CB
    lda #$1F
    clc
    adc $CC
    sta $CC
    lda #$00
    adc $CD
    sta $CD
    jmp b08_loc_824C
b08_loc_82B1:
    lda $C8
    and #$7F
    beq b08_loc_82D5
    cmp $CA
    bne b08_loc_82D5
    lda $CA
    and #$01
    sta $CA
    inc $C9
    lda #$10
    cmp $C9
    bne b08_loc_82D5
    lda $C8
    bmi b08_loc_82D1
    lda #$00
    sta $C8
b08_loc_82D1:
    lda #$0F
    sta $C9
b08_loc_82D5:
    lda $D2
    beq b08_loc_82DB
    dec $D2
b08_loc_82DB:
    lsr $CF
    lsr $CF
    lsr $CF
    lsr $CF
    rts
; ----------------------------------------------------------------------
; sound_calc_volume
;   Calculate the current volume/envelope value.
; ----------------------------------------------------------------------
sound_calc_volume:
    ldy #$0C
    lda ($CC),y
    ldy #$02
    cpy $CE
    beq b08_loc_82F0
    and #$0F
b08_loc_82F0:
    sta $D4
    lda $C8
    and #$7F
    beq b08_loc_8323
    lda $C9
    ldy #$02
    cpy $CE
    bne b08_loc_8308
    ldx #$0C
b08_loc_8302:
    clc
    adc $C9
    dex
    bne b08_loc_8302
b08_loc_8308:
    tay
    lda $C8
    bmi b08_loc_831C
    ldx #$FF
b08_loc_830F:
    inx
    cpx $D4
    beq b08_loc_8323
    dey
    bne b08_loc_830F
    stx $D4
    jmp b08_loc_8323
b08_loc_831C:
    dec $D4
    beq b08_loc_8323
    dey
    bne b08_loc_831C
b08_loc_8323:
    lda #$02
    cmp $CE
    beq b08_loc_8374
    ldy #$0D
    lda ($CC),y
    tax
    and #$7F
    beq b08_loc_8374
    iny
    cmp ($CC),y
    beq b08_loc_833F
    iny
    lda ($CC),y
    and #$0F
    jmp b08_loc_8364
b08_loc_833F:
    lda #$00
    sta ($CC),y
    iny
    lda ($CC),y
    lsr a
    lsr a
    lsr a
    lsr a
    sta $D5
    txa
    bpl b08_loc_8356
    lda #$00
    sec
    sbc $D5
    sta $D5
b08_loc_8356:
    lda ($CC),y
    and #$0F
    clc
    adc $D5
    bpl b08_loc_8364
    lda #$00
    jmp b08_loc_836A
b08_loc_8364:
    cmp $D4
    bcc b08_loc_836A
    lda $D4
b08_loc_836A:
    sta $D4
    lda ($CC),y
    and #$F0
    ora $D4
    sta ($CC),y
b08_loc_8374:
    lda $CF
    lsr a
    bcs b08_loc_8380
    lda #$0C
    sta $D5
    jmp b08_loc_8387
b08_loc_8380:
    lda #$09
    sta $D5
    jmp b08_loc_83F6
b08_loc_8387:
    ldy #$16
    lda ($CC),y
    and #$7F
    beq b08_loc_83CD
    ldy #$1D
    cmp ($CC),y
    beq b08_loc_8398
    jmp b08_loc_83C3
b08_loc_8398:
    lda #$00
    sta ($CC),y
    ldy #$17
    lda ($CC),y
    ldy #$1E
    clc
    adc ($CC),y
    beq b08_loc_83A9
    bpl b08_loc_83B0
b08_loc_83A9:
    lda #$01
    sta ($CC),y
    jmp b08_loc_83BA
b08_loc_83B0:
    sta ($CC),y
    cmp #$10
    bcc b08_loc_83C3
    lda #$0F
    sta ($CC),y
b08_loc_83BA:
    lda #$00
    ldy #$17
    sec
    sbc ($CC),y
    sta ($CC),y
b08_loc_83C3:
    ldy #$1E
    lda ($CC),y
    cmp $D4
    bcs b08_loc_83CD
    sta $D4
b08_loc_83CD:
    ldy #$02
    cpy $CE
    beq b08_loc_83E0
    lda $D5
    and #$7F
    tay
    lda ($CC),y
    and #$F0
    ora $D4
    sta $D4
b08_loc_83E0:
    ldx $CB
    lda $D4
    sta $4000,x
    lda $D5
    bpl b08_loc_83F2
    lda #$90
    sta $D5
    jmp b08_loc_83F6
b08_loc_83F2:
    lda #$09
    sta $D5
b08_loc_83F6:
    lda $D5
    and #$7F
    tay
    ldx #$00
    lda ($CC),y
    beq b08_loc_8410
    bpl b08_loc_8404
    dex
b08_loc_8404:
    iny
    clc
    adc ($CC),y
    sta ($CC),y
    txa
    iny
    adc ($CC),y
    sta ($CC),y
b08_loc_8410:
    lda $D5
    bmi b08_loc_841A
    lda $CF
    lsr a
    bcc b08_loc_841A
    rts
b08_loc_841A:
    ldy #$14
    lda ($CC),y
    and #$7F
    bne b08_loc_8425
    jmp b08_loc_84A1
b08_loc_8425:
    ldy #$18
    cmp ($CC),y
    beq b08_loc_842E
    jmp b08_loc_84A1
b08_loc_842E:
    lda #$00
    sta ($CC),y
    tax
    ldy #$15
    lda ($CC),y
    rol a
    rol a
    rol a
    rol a
    and #$07
    sta $D4
    ldy #$19
    lda ($CC),y
    asl a
    bcc b08_loc_844E
    lda #$00
    sec
    sbc $D4
    sta $D4
    dex
b08_loc_844E:
    lda $D4
    clc
    ldy #$1A
    adc ($CC),y
    sta ($CC),y
    iny
    txa
    adc ($CC),y
    sta ($CC),y
    ldy #$15
    lda ($CC),y
    and #$1F
    sta $D4
    ldy #$19
    lda ($CC),y
    clc
    adc #$01
    sta ($CC),y
    and #$7F
    cmp $D4
    bne b08_loc_84A1
    lda ($CC),y
    and #$80
    sta ($CC),y
    ldy #$14
    lda ($CC),y
    asl a
    bcs b08_loc_849B
    lda ($CC),y
    ora #$80
    sta ($CC),y
    ldy #$19
    lda ($CC),y
    bpl b08_loc_8494
    and #$7F
    sta ($CC),y
    jmp b08_loc_84A1
b08_loc_8494:
    ora #$80
    sta ($CC),y
    jmp b08_loc_84A1
b08_loc_849B:
    lda ($CC),y
    and #$7F
    sta ($CC),y
b08_loc_84A1:
    lda $D5
    and #$7F
    sta $D5
    inc $D5
    ldy #$1A
    lda ($CC),y
    ldy $D5
    clc
    adc ($CC),y
    tax
    ldy #$1B
    lda ($CC),y
    inc $D5
    ldy $D5
    adc ($CC),y
    tay
    lda #$01
    cmp $CE
    bne b08_loc_84DD
    lda #$0F
    sta APUSTATUS
    txa
    and #$0F
    tax
    inc $D5
    ldy $D5
    lda ($CC),y
    and #$80
    sta $D4
    txa
    ora $D4
    tax
    ldy #$00
b08_loc_84DD:
    txa
    ldx $CB
    inx
    inx
    sta $4000,x
    tya
    ldy #$1C
    cmp ($CC),y
    bne b08_loc_84ED
    rts
b08_loc_84ED:
    sta ($CC),y
    ora #$08
    sta $4001,x
    rts
b08_loc_84F5:
    ldy #$01
    cpy $CE
    bne b08_loc_8501
    lda #$07
    sta APUSTATUS
    rts
b08_loc_8501:
    lda #$00
    ldx $CB
    inx
    inx
    sta $4000,x
    sta $4001,x
    rts
; ----------------------------------------------------------------------
; sound_note_reset
;   Reset the per-note state after a new note/rest.
;   called by: $8545, $85B4, $8794
; ----------------------------------------------------------------------
sound_note_reset:
    ldy #$14
    lda ($CC),y
    and #$7F
    sta ($CC),y
    ldy #$16
    lda ($CC),y
    asl a
    bcc b08_loc_852D
    ldy $D4
    lda ($CC),y
    ldx #$02
    cpx $CE
    beq b08_loc_8529
    and #$0F
b08_loc_8529:
    ldy #$1E
    sta ($CC),y
b08_loc_852D:
    ldx #$06
    lda #$00
    ldy #$18
b08_loc_8533:
    sta ($CC),y
    iny
    dex
    bne b08_loc_8533
    lda #$FF
    ldy #$1C
    sta ($CC),y
    rts
b08_loc_8540:
    ldy #$1C
    lda ($CC),y
    pha
    jsr sound_note_reset
    pla
    ldy #$1C
    sta ($CC),y
    rts
; ----------------------------------------------------------------------
; sound_dispatch
;   Dispatch through the note/command jump table.
;   called by: $85BA, $87B8
; ----------------------------------------------------------------------
sound_dispatch:
    txa
    asl a
    tay
    iny
    pla
    sta $D4
    pla
    sta $D5
    lda ($D4),y
    tax
    iny
    lda ($D4),y
    sta $D5
    stx $D4
    jmp ($00D4)
; ----------------------------------------------------------------------
; sound_decode_pattern
;   Decode one pattern event (note, duration, instrument).
;   called by: $8263
; ----------------------------------------------------------------------
sound_decode_pattern:
    lda $D2
    bne b08_loc_856C
    jmp b08_loc_858A
b08_loc_856C:
    ldy #$11
    lda ($CC),y
    iny
    ora ($CC),y
    bne b08_loc_8576
    rts
b08_loc_8576:
    iny
    lda ($CC),y
    ldy #$02
    cpy $CE
    beq b08_loc_8581
    and #$0F
b08_loc_8581:
    sta $D4
    lda #$93
    sta $D5
    jmp b08_loc_8387
b08_loc_858A:
    jsr sound_fetch_byte
    asl a
    bcs b08_loc_8593
    jmp b08_loc_85BA
b08_loc_8593:
    txa
    and #$0F
    cmp #$0F
    bne b08_loc_85A0
    jsr sound_fetch_byte
    jmp b08_loc_8540
b08_loc_85A0:
    and #$07
    sta $D4
    jsr sound_fetch_byte
    ldy #$11
    sta ($CC),y
    iny
    lda $D4
    sta ($CC),y
    lda #$13
    sta $D4
    jsr sound_note_reset
    jmp b08_loc_84F5
b08_loc_85BA:
    jsr sound_dispatch

b08_data_85BD:
    .incbin "build/assets/bank08_data.bin", $05BD, $000E
    jsr sound_fetch_byte
    sta $D2
    jmp b08_loc_858A
    jsr sound_fetch_byte
    ldy #$10
    sta ($CC),y
    jmp b08_loc_858A
    jsr sound_fetch_byte
    sta $D4
    ldy #$13
    lda ($CC),y
    and #$3F
    ora $D4
    jmp b08_loc_8600
    jsr sound_fetch_byte
    ldy #$02
    cpy $CE
    beq b08_loc_8600
    sta $D4
    ldy #$13
    lda ($CC),y
    and #$C0
    ora $D4
b08_loc_8600:
    ldy #$13
    sta ($CC),y
    jmp b08_loc_858A
    jsr sound_fetch_byte
    txa
    beq b08_loc_8613
    cpx $D3
    beq b08_loc_8624
    inc $D3
b08_loc_8613:
    jsr sound_fetch_byte
    sta $D4
    jsr sound_fetch_byte
    sta $D1
    lda $D4
    sta $D0
    jmp b08_loc_858A
b08_loc_8624:
    lda #$00
    sta $D3
    lda #$02
    clc
    adc $D0
    sta $D0
    lda #$00
    adc $D1
    sta $D1
    jmp b08_loc_858A

b08_data_8638:
    .incbin "build/assets/bank08_data.bin", $0638, $0016
    lda $D0
    sec
    sbc #$01
    sta $D0
    lda $D1
    sbc #$00
    sta $D1
    lda $C0
    and #$0F
    sta $C0
    lda #$00
    sta $C1
    lda $CF
    and #$FE
    sta $CF
    ldy #$0A
    lda ($CC),y
    iny
    ora ($CC),y
    bne b08_loc_8687
    ldx $CB
    inx
    inx
    ldy $CE
    jsr sound_channel_enable
    ldy #$00
    lda ($CC),y
    iny
    ora ($CC),y
    bne b08_loc_8687
    rts
b08_loc_8687:
    ldy #$06
    lda ($CC),y
    and #$1F
    tax
    jsr sound_load_instrument
    lda #$0C
    sta $D4
    jmp sound_note_reset
; ----------------------------------------------------------------------
; sound_fetch_byte
;   Fetch the next byte from the current music stream.
;   called by: $858A, $859A, $85A4, $85CB, $85D3, $85DD, $85ED, $8607, $8613, $8618
; ----------------------------------------------------------------------
sound_fetch_byte:
    ldy #$00
    lda ($D0),y
    tax
    lda #$01
    clc
    adc $D0
    sta $D0
    lda #$00
    adc $D1
    sta $D1
    txa
    rts
; ----------------------------------------------------------------------
; sound_update_envelope
;   Advance the envelope and volume state.
;   called by: $8278
; ----------------------------------------------------------------------
sound_update_envelope:
    lda $C7
    beq sound_update_pitch
b08_loc_86B0:
    pha
    jsr sound_update_pitch
    pla
    sec
    sbc #$01
    bne b08_loc_86B0
    rts
; ----------------------------------------------------------------------
; sound_update_pitch
;   Advance the pitch/slide state.
;   called by: $86B1
; ----------------------------------------------------------------------
sound_update_pitch:
    ldy #$05
    lda ($CC),y
    asl a
    bcc sound_update_noise
    lda $CA
    and #$01
    beq sound_update_noise
    jsr sound_update_noise
; ----------------------------------------------------------------------
; sound_update_noise
;   Advance the noise/percussion state.
;   called by: $86C8
; ----------------------------------------------------------------------
sound_update_noise:
    ldy #$02
    lda ($CC),y
    iny
    ora ($CC),y
    beq b08_loc_86F6
    ldx #$FF
    dey
    lda ($CC),y
    sec
    sbc #$04
    sta ($CC),y
    txa
    iny
    adc ($CC),y
    sta ($CC),y
    dey
    ora ($CC),y
    beq b08_loc_86F6
    ldy #$0A
    lda ($CC),y
    iny
    ora ($CC),y
    bne b08_loc_86F3
    rts
b08_loc_86F3:
    jmp sound_calc_volume
b08_loc_86F6:
    ldy #$05
    lda ($CC),y
    and #$7F
    sta ($CC),y
; ----------------------------------------------------------------------
; sound_command_parser
;   Parse the next sound command/control byte.
;   called by: $8710
; ----------------------------------------------------------------------
sound_command_parser:
    jsr sound_stream_read
    and #$F0
    bne b08_loc_8708
    jmp b08_loc_87B8
b08_loc_8708:
    cmp #$20
    bne b08_loc_8717
    txa
    and #$07
    pha
    jsr sound_command_parser
    pla
    jmp b08_loc_879A
b08_loc_8717:
    cmp #$30
    bne b08_loc_871E
    jmp b08_loc_87AD
b08_loc_871E:
    txa
    rol a
    rol a
    rol a
    rol a
    and #$07
    tay
    lda b08_data_896D,y
    jsr sound_set_duration
b08_loc_872C:
    ldy #$06
    lda ($CC),y
    and #$E0
    beq b08_loc_874A
    sec
    sbc #$20
    sta $D4
    lda ($CC),y
    and #$1F
    ora $D4
    sta ($CC),y
    lda $CF
    lsr a
    bcc b08_loc_8747
    rts
b08_loc_8747:
    jmp b08_loc_8540
b08_loc_874A:
    txa
    and #$1F
    bne b08_loc_8753
    tax
    jmp b08_loc_8775
b08_loc_8753:
    ldy #$01
    cpy $CE
    bne b08_loc_875E
    ldx #$00
    jmp b08_loc_8775
b08_loc_875E:
    asl a
    ldy #$07
    clc
    adc ($CC),y
    sta $D4
    lda #$00
    iny
    adc ($CC),y
    sta $D5
    ldy #$01
    lda ($D4),y
    tax
    dey
    lda ($D4),y
b08_loc_8775:
    ldy #$0A
    sta ($CC),y
    iny
    txa
    sta ($CC),y
    ldy #$0D
    lda ($CC),y
    sta $D4
    and #$7F
    beq b08_loc_878A
    jsr sound_set_duty
b08_loc_878A:
    lda $CF
    lsr a
    bcc b08_loc_8790
    rts
b08_loc_8790:
    lda #$0C
    sta $D4
    jsr sound_note_reset
    jmp b08_loc_84F5
b08_loc_879A:
    ror a
    ror a
    ror a
    ror a
    and #$E0
    sta $D4
    ldy #$06
    lda ($CC),y
    and #$1F
    ora $D4
    sta ($CC),y
    rts
b08_loc_87AD:
    lda #$80
    ldy #$05
    ora ($CC),y
    sta ($CC),y
    jmp sound_command_parser
b08_loc_87B8:
    jsr sound_dispatch

b08_data_87BB:
    .incbin "build/assets/bank08_data.bin", $07BB, $0014
    jsr sound_stream_read
    ldy #$04
    sta ($CC),y
    jmp sound_command_parser
    jsr sound_stream_read
    ldy #$09
    sta ($CC),y
    jmp sound_command_parser
    jsr sound_stream_read
    sta $D4
    ldy #$0C
    lda ($CC),y
    and #$3F
    ora $D4
    jmp b08_loc_8806
    jsr sound_stream_read
    ldy #$02
    cpy $CE
    beq b08_loc_8806
    sta $D4
    ldy #$0C
    lda ($CC),y
    and #$C0
    ora $D4
b08_loc_8806:
    ldy #$0C
    sta ($CC),y
    jmp sound_command_parser
    jsr sound_stream_read
    txa
    beq b08_loc_8829
    ldy #$05
    lda ($CC),y
    and #$7F
    sta $D4
    cpx $D4
    beq b08_loc_883C
    inc $D4
    lda ($CC),y
    and #$80
    ora $D4
    sta ($CC),y
b08_loc_8829:
    jsr sound_stream_read
    pha
    jsr sound_stream_read
    pla
    ldy #$00
    sta ($CC),y
    iny
    txa
    sta ($CC),y
    jmp sound_command_parser
b08_loc_883C:
    lda ($CC),y
    and #$80
    sta ($CC),y
    ldy #$00
    lda #$02
    clc
    adc ($CC),y
    sta ($CC),y
    iny
    lda #$00
    adc ($CC),y
    sta ($CC),y
    jmp sound_command_parser
    jsr sound_stream_read
    ldx #$7D
    ldy #$89
    stx $D4
    sty $D5
    asl a
    ldy #$07
    clc
    adc $D4
    sta ($CC),y
    lda #$00
    adc $D5
    iny
    sta ($CC),y
    jmp sound_command_parser
    jsr sound_stream_read
    rol a
    rol a
    rol a
    rol a
    and #$07
    tay
    lda b08_data_8975,y
    jsr sound_set_duration
    jmp b08_loc_872C
    jsr sound_stream_read
    ldy #$0D
    sta ($CC),y
    pha
    jsr sound_stream_read
    ldy #$0F
    sta ($CC),y
    pla
    sta $D4
    and #$7F
    beq b08_loc_889E
    jsr sound_set_duty
b08_loc_889E:
    jmp sound_command_parser
; ----------------------------------------------------------------------
; sound_set_duty
;   Set the current channel duty cycle.
;   called by: $8787, $889B
; ----------------------------------------------------------------------
sound_set_duty:
    lda #$00
    ldy #$0E
    sta ($CC),y
    lda $D4
    bpl b08_loc_88B0
    lda #$0F
    jmp b08_loc_88B2
b08_loc_88B0:
    lda #$00
b08_loc_88B2:
    sta $D4
    ldy #$0F
    lda ($CC),y
    and #$F0
    ora $D4
    sta ($CC),y
    rts
    jsr sound_stream_read
    sta $D4
    ldy #$06
    lda ($CC),y
    and #$E0
    ora $D4
    sta ($CC),y
    lda $CF
    lsr a
    bcs b08_loc_88D6
    jsr sound_load_instrument
b08_loc_88D6:
    jmp sound_command_parser
; ----------------------------------------------------------------------
; sound_load_instrument
;   Load an instrument definition into the channel state.
;   called by: $868E, $88D3
; ----------------------------------------------------------------------
sound_load_instrument:
    txa
    beq b08_loc_88E4
    lda #$00
b08_loc_88DE:
    clc
    adc #$04
    dex
    bne b08_loc_88DE
b08_loc_88E4:
    clc
    adc $077C
    sta $D4
    lda #$00
    adc $077D
    sta $D5
    ldx #$00
    ldy #$14
b08_loc_88F5:
    lda ($D4,x)
    sta ($CC),y
    iny
    cpy #$18
    bne b08_loc_88FF
    rts
b08_loc_88FF:
    lda #$01
    clc
    adc $D4
    sta $D4
    lda #$00
    adc $D5
    sta $D5
    jmp b08_loc_88F5

b08_data_890F:
    .incbin "build/assets/bank08_data.bin", $090F, $001E
; ----------------------------------------------------------------------
; sound_stream_read
;   Read one byte from the active music stream and advance its pointer.
;   called by: $86FE, $87CF, $87D9, $87E3, $87F3, $880D, $8829, $882D, $8855, $8872, $8885, $888D (+1 more)
; ----------------------------------------------------------------------
sound_stream_read:
    ldy #$00
    lda ($CC),y
    sta $D4
    iny
    lda ($CC),y
    sta $D5
    dey
    lda ($D4),y
    tax
    lda #$01
    clc
    adc $D4
    sta ($CC),y
    lda #$00
    adc $D5
    iny
    sta ($CC),y
    txa
    rts
; ----------------------------------------------------------------------
; sound_set_duration
;   Calculate and store the current note duration.
;   called by: $8729, $887F
; ----------------------------------------------------------------------
sound_set_duration:
    sta $D4
    lda #$00
    sta $D5
    ldy #$04
    lda ($CC),y
    tay
    lda #$00
b08_loc_8959:
    clc
    adc $D4
    bcc b08_loc_8960
    inc $D5
b08_loc_8960:
    dey
    bne b08_loc_8959
    ldy #$02
    sta ($CC),y
    iny
    lda $D5
    sta ($CC),y
    rts

b08_data_896D:
    .incbin "build/assets/bank08_data.bin", $096D, $0008

b08_data_8975:
    .incbin "build/assets/bank08_data.bin", $0975, $00DB

b08_sound_data:
    .incbin "build/assets/bank08_data.bin", $0A50, $0001

b08_data_8A51:
    .incbin "build/assets/bank08_data.bin", $0A51, $03FF

b08_data_8E50:
    .incbin "build/assets/bank08_data.bin", $0E50, $0400

b08_data_9250:
    .incbin "build/assets/bank08_data.bin", $1250, $0400

b08_data_9650:
    .incbin "build/assets/bank08_data.bin", $1650, $0400

b08_data_9A50:
    .incbin "build/assets/bank08_data.bin", $1A50, $0400

b08_data_9E50:
    .incbin "build/assets/bank08_data.bin", $1E50, $0400

b08_data_A250:
    .incbin "build/assets/bank08_data.bin", $2250, $0400

b08_data_A650:
    .incbin "build/assets/bank08_data.bin", $2650, $0400

b08_data_AA50:
    .incbin "build/assets/bank08_data.bin", $2A50, $0400

b08_data_AE50:
    .incbin "build/assets/bank08_data.bin", $2E50, $0400

b08_data_B250:
    .incbin "build/assets/bank08_data.bin", $3250, $0400

b08_data_B650:
    .incbin "build/assets/bank08_data.bin", $3650, $0400

b08_data_BA50:
    .incbin "build/assets/bank08_data.bin", $3A50, $0400

b08_data_BE50:
    .incbin "build/assets/bank08_data.bin", $3E50, $01B0

