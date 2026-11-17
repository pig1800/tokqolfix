; ======================================================================
; Map-mode text renderer (TEXT_RENDERER.md, 2026-11-12).  PRG bank
; TXR_BANK, assembled for $8000.  txr_call (fixed_rt.asm) maps it
; with the game's lock protocol and calls $8000 with X = function; $10/$11
; are saved around the call.  Main thread only.
;
; Screen parts: rows 0-8, 9-14, 15-20, 21-29 show BG tiles $00-$7F from
; the pages R0 = 4, 8, 10, 12 (CHR $1000, $2000, $2800, $3000); the IRQ
; switches R0 in the hblank of lines 71, 119 and 167.  Every page holds the
; fixed set (old codes $6D $0B $6E $6F $0C $0D $7D $7E $0E $0F $70 $71) at
; tiles $00-$0B and a blank $7F; page 1 holds コマンド at $7B-$7E.  The
; rest is allocated per part: kanji in 4-tile groups from $0C up (t, t+1,
; t+2, t+3 = top-left, bottom-left, top-right, bottom-right), kana single
; tiles from the top down.  Text tiles are 1bpp: plane 0, plane 1 zero.
;
; The game's text cells hold old font codes ($00-$7F) and, from the
; message engine, kanji halves $80 + 2e (left) / $81 + 2e (right), e = the page
; entry (REG_LO/HI[e] = glyph code); $FA-$FF are line-end codes.  A row's
; screen row gives its part, its parity the kanji half's row (text lines
; start on odd rows in map mode).  Glyphs a row needs are uploaded (the NMI
; after the game's flush, TXR_UQ) before the row's entry is committed.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

PTR             = $10           ; (saved by txr_call)
UPDATE_FRAME    = $C0D5
SOUND_QUEUE_ADD = $C4D5
CELL_ROWS       = $DC8F         ; text_render_cell's row-buffer offsets by text_line
FONT_BANK       = 9
FONT_SRC        = $BA00
BLANK           = $7F

.base $8000
.org $8000
    jmp txr_dispatch            ; $8000: main thread (txr_call)
    jmp nmi_cvg                 ; $8003: NMI entries, this bank's first 8 KiB
    jmp nmi_live                ; $8006:   mapped at $8000 by the RAM's
    jmp nmi_map                 ; $8009:   stubs (unused: nmi_gate goes through cv_nmi)
txr_dispatch:                   ; (Y kept: TXF_PUT and TXF_LABEL keep it)
    lda txr_fnh,x
    pha
    lda txr_fnl,x
    pha
    rts
txr_fnl:
    .db <(txr_mapinit-1), <(txr_restore-1), <(txr_dl-1), <(txr_rc-1), <(txr_close-1)
    .db <(txr_dlc-1), <(txr_rcc-1), <(txr_fill-1), <(txr_put-1), <(txr_label-1)
    .db <(txr_menuinit-1), <(txr_name-1), <(txr_menuset-1)
    .db <(txr_oathset-1), <(txr_oathend-1)
txr_fnh:
    .db >(txr_mapinit-1), >(txr_restore-1), >(txr_dl-1), >(txr_rc-1), >(txr_close-1)
    .db >(txr_dlc-1), >(txr_rcc-1), >(txr_fill-1), >(txr_put-1), >(txr_label-1)
    .db >(txr_menuinit-1), >(txr_name-1), >(txr_menuset-1)
    .db >(txr_oathset-1), >(txr_oathend-1)

; ======================================================================
; NMI code (mapped at $8000-$9FFF by the RAM stubs; any bank may be in
; $A000-$BFFF).  Keep it in this bank's first 8 KiB.
; ======================================================================
; nmi_map's other paths (below it: the branches reach back).
nm_late:
    jsr nm_regs                 ; the original's writes, at once
    jsr r0_scene
    jsr cvn_arm
    jmp nm_rest
nm_off:
    jsr nm_regs
    jsr r0_scene
    lda #0
    sta MMC3_IRQ_OFF
    sta KANJI_IRQ_ST
    jmp nm_rest
nm_strm:
    lda #0
    sta CV_STRM                 ; (cv_stream ran cvn_map in this NMI)
    jsr nm_regs
    jmp nm_rest
nm_orig:
    lda scroll_x
    sta PPUSCROLL               ; $EED0
    lda #>($EED3-1)
    pha
    lda #<($EED3-1)
    pha
    lda current_prg_bank
    jmp NMI_PRG                 ; the main thread's bank back; returns to $EED3


; ----------------------------------------------------------------------
; NMI, map mode (TXR_ON bit 7), not busy: from the fixed bank's nmi_gate
; (in place of $EED0 "sta PPUSCROLL", through cv_nmi), after the game's
; flush, palette DMA and CHR-stream step; R6 = this bank.  The staged
; glyphs first (nmi_up), then the PPU-address force (v = $1000: A12 high
; when vblank ends, no MMC3 clock at the pre-render line's first BG
; fetch) with the original's PPUCTRL (ppu_nmi_on), scroll and PPUMASK,
; R0 = page 1 and the arm (stage 0 at the pre-render line's clock, the
; parts from line 71's clock: KANJI_IRQ_ST 2).  Then the rest of the
; original's $EED0-$EF0A, which touches no PPU register (TEXT_RENDERER.md
; "Upload speed", round 3): the frame counter and the task timers; $EF08's
; push and ef08_tail (the sound bank, $EF10).  No force when the game's
; flush ran long (its writes then come at once, as the original's) or
; cv_stream forced already.  nmi_mode not 0 (never seen in map mode): the
; original path.
; ----------------------------------------------------------------------
nmi_map:
    lda nmi_mode
    bne nm_orig
    lda vram_queue_read
    sec
    sbc KANJI_QPOS
    tax                         ; X = bytes the game flushed this frame
    lda CV_STRM
    bne nm_strm                 ; cv_stream forced and armed (no uploads)
    cpx #CV_MAP_FORCE_MAX+1
    bcs nm_late                 ; the game's NMI ran late: no force
    lda ppu_mask_shadow
    and #$18
    beq nm_off                  ; rendering off: no split, none pending
    lda TXR_RBQ
    beq @noread
    cpx #48
    bcs nm_force                ; a long flush: the read waits a frame
    jsr row_read                ; the GC's row (no uploads this frame)
    jmp nm_force
@noread:
    lda TXR_UQN
    beq nm_force
    jsr nmi_up                  ; staged glyphs (X = bytes flushed)
nm_force:
cv_force:                       ; (label for the gates)
    lda PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #$00
    sta PPUADDR                 ; v = $1000
    jsr nm_regs                 ; PPUCTRL, the scroll, PPUMASK
cv_force_end:
    lda #MMC3_R0                ; (the NMI's restore_bank_after_nmi gives
    sta MMC3_SELECT             ; $8000 back to MMC3_SEL)
    lda #CHR_SCENE_LO
    sta MMC3_DATA
    jsr cvn_arm
nm_rest:
    lda $39
    sta KANJI_LAST39
    lda vram_queue_read
    sta KANJI_QPOS
    inc frame_counter           ; $EEE0-$EEFE, as the original
    ldx #$0C
    ldy input_mask
@task:
    tya
    asl a
    tay
    bcs @next
    lda task_state,x
    cmp #$01
    bne @next
    dec task_timer,x
    bne @next
    lda #$04
    sta task_state,x
@next:
    dex
    dex
    dex
    dex
    bpl @task
    lda current_prg_bank        ; $EF08 (the epilogue pulls it)
    pha
    jmp EF08_TAIL

; The original's $EECE-$EEDF: PPUCTRL (ppu_nmi_on), the scroll, PPUMASK.
nm_regs:
    lda ppu_ctrl_shadow
    ora #$80
    sta ppu_ctrl_shadow
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
    lda ppu_mask_shadow
    sta PPUMASK
    rts

; R0 = page 1 (the top part's; the IRQ left the bottom part's).
r0_scene:
    lda #MMC3_R0
    sta MMC3_SELECT
    lda #CHR_SCENE_LO
    sta MMC3_DATA
    rts

; The arm: stage 0 at the pre-render line's clock, the parts from line
; 71's clock (KANJI_IRQ_ST 2); IRQs on (stage 0 may preempt the rest of
; the NMI).
cvn_arm:
    lda #0
    sta MMC3_IRQ_LATCH
cv_reload:                      ; (label for the gates)
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_OFF            ; acknowledge anything pending
    sta MMC3_IRQ_ON
    lda #2
    sta KANJI_IRQ_ST
    lda #TXR_N0
    sta KANJI_IRQ_N
    lda KANJI_NFLAGS
    ora #FLAG_ARMED
    sta KANJI_NFLAGS
    cli
cvn_rts:
    rts
; ----------------------------------------------------------------------
; NMI, through the RAM's cv_nmi: from the fixed bank's nmi_gate (map mode,
; not busy: nmi_map; such NMIs never reach $EF08) or from $EF0B (normal
; frames, $EF08's push done: busy NMIs and every mode but the map's).
; There: the oath's split arm (nmi_cv), then ef08_hook when the hack bank's
; NMI has work (a request, $39 moved or VRAM queue traffic: the pool's
; uploads and guard), else ef08_tail (the sound bank only).  The band page
; is gone (2026-11-14).
; ----------------------------------------------------------------------
nmi_cvg:
    lda nmi_busy
    bne @ef08
    bit TXR_ON
    bpl @ef08
    jmp nmi_map
@ef08:
    jsr nmi_cv
    bit TXR_ON
    bmi @no                     ; map mode (busy): nothing of the hack's NMI
    lda KANJI_REQ
    bne @yes
    lda $39
    cmp KANJI_LAST39
    bne @yes
    lda vram_queue_read
    cmp KANJI_QPOS
    bne @yes
@no:
    jmp EF08_TAIL
@yes:
    jmp EF08_HOOK

; Busy, or cv_stream ran it in this NMI: nothing.  Map mode: cv_stream's
; step only (CV_STRM bit 6: forced there, no uploads after it): R0 = page
; 1, the bookkeeping, the arm.  Elsewhere the opening oath's split (the
; band page and its arm are gone since 2026-11-14).  A, X.
nmi_cv:
    lda nmi_busy
    ora CV_STRM
    beq nmi_live
    lda #0
    sta CV_STRM                 ; (cv_stream ran it in this NMI, or busy)
    rts
nmi_live:
    bit TXR_ON
    bmi cvn_map
    jmp cvn_band_path
cvn_map:
    jsr r0_scene
    lda MMC3_SEL
    ora #MMC3_CHR_MODE
    sta MMC3_SELECT
    lda $39
    sta KANJI_LAST39
    lda vram_queue_read
    sta KANJI_QPOS
    lda ppu_mask_shadow
    and #$18
    beq cvn_off
    jmp cvn_arm
cvn_off:
    sta MMC3_IRQ_OFF
    sta KANJI_IRQ_ST            ; (A = 0)
cvn_brts:
    rts
cvn_band_path:                  ; (every mode but the map's)
    lda ppu_mask_shadow
    and #$18
    beq cvn_brts                ; rendering off
    lda TXR_ON
    cmp #TXR_SPLIT
    bne cvn_brts                ; no split (the band page is gone)
    jmp cvn_split               ; the opening oath's fixed split

; The opening oath (TXR_ON = TXR_SPLIT, the user's fixed split, 2026-11-14):
; R1 = the scene page for the frame's top (the portraits' tiles $80-$FF),
; then the IRQ for line SPLIT_LINE: stage 0 reloads the counter in line 0,
; the fixed bank's irq_split sets R1 = CHR $3800 (the oath's kanji).  The
; screen is black around that line, so neither the PPU-address force nor a
; wait is needed: a line or two of jitter is invisible.  FLAG_ARMED makes the
; hack NMI's irq_arm0 a no-op in this NMI.
cvn_split:
    lda #MMC3_R1
    sta MMC3_SELECT
    lda #CHR_SCENE_HI
    sta MMC3_DATA
    lda #0
    sta MMC3_IRQ_LATCH
    sta MMC3_IRQ_RELOAD         ; stage 0 at the pre-render line's clock
    sta MMC3_IRQ_OFF
    sta MMC3_IRQ_ON
    lda KANJI_NFLAGS
    ora #FLAG_ARMED
    sta KANJI_NFLAGS
    lda #1
    sta KANJI_IRQ_ST
    lda #SPLIT_LINE
    sta KANJI_IRQ_N
    cli
    rts

; The staged records after the game's flush (TEXT_RENDERER.md "Upload
; speed", B + D, round 3): kana from this bank's font copy (up_kana), kanji
; from the kanji store at R7 (up_kanji), as many as the budget allows:
; UP_UNITS less one unit per byte the game flushed (X).  Then the held
; cells.  R0 is left at any page (nmi_map sets page 1 after the force).
; A, X, Y lost.
nmi_up:
    txa
    cmp #UP_UNITS-UP_KANA+1
    bcc @go
    rts                         ; a long flush: the batch waits a frame
@go:
    eor #$FF
    sec
    adc #UP_UNITS
    sta TXR_UB                  ; UP_UNITS - X
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL                 ; +1 increments
    lda #$FF
    sta KANJI_T1                ; R0 unknown (the IRQ's last part): set for the first record
    sta KANJI_T0                ; R7 unknown: mapped for the first kanji (the
                                ; NMI's last restore maps the main thread's back)
    bit PPUSTATUS
    ldx TXR_UQR
@rec:
    lda TXR_UQ,x
    bmi @kanji
    jsr up_kana
    jmp @next
@kanji:
    jsr up_kanji
@next:
    bcs @done                   ; no time left: the rest next NMI
    lda TXR_UQN
    bne @rec
@done:
    stx TXR_UQR
    ; text_render_cell's cells held for this batch (TXR_HB bit 7): put
    ; back now that the glyphs are in CHR, and flushed here when the time
    ; allows (UP_CELLS left: up to 4 one-byte entries) and nothing queued
    ; before them is still waiting; else the game's next flush.
    lda TXR_UQN
    bne nu_rts                  ; the batch goes on next frame
    lda TXR_HB
    bpl nu_rts
    and #$7F
    ldy TXR_HI
    sta $0400,y
    lda #0
    sta TXR_HB
    lda TXR_UB
    cmp #UP_CELLS
    bcc nu_rts
    lda vram_queue_read
    cmp TXR_HI
    bne nu_rts
    jmp rel_flush
nu_rts:
    rts

; The kana records of TXR_UQ from X on (R0, PPU address hi, lo, the
; glyph's offset in its font page, the page 0-3): 8 bytes from this bank's
; font copy (in the NMI's half).  R0 written only when it changes
; (KANJI_T1).  Stops at a kanji record or the batch's end (C clear), or
; when TXR_UB has no UP_KANA left (C set).  X = the next record; Y lost.
.macro KANA8 src
    lda src+0,y
    sta PPUDATA
    lda src+1,y
    sta PPUDATA
    lda src+2,y
    sta PPUDATA
    lda src+3,y
    sta PPUDATA
    lda src+4,y
    sta PPUDATA
    lda src+5,y
    sta PPUDATA
    lda src+6,y
    sta PPUDATA
    lda src+7,y
    sta PPUDATA
.endm
up_kana:
uk_rec:
    lda TXR_UB
    sec
    sbc #UP_KANA
    bcs @fits
    sec                         ; no time left this NMI: C set
    rts
@fits:
    sta TXR_UB
    lda TXR_UQ,x
    cmp KANJI_T1
    beq @r0
    sta KANJI_T1
    ldy #MMC3_R0
    sty MMC3_SELECT
    sta MMC3_DATA
@r0:
    lda TXR_UQ+1,x
    sta PPUADDR
    lda TXR_UQ+2,x
    sta PPUADDR
    ldy TXR_UQ+3,x
    lda TXR_UQ+4,x
    bne @n0
    KANA8 font_copy
    jmp uk_next
@n0:
    cmp #2
    beq @p2
    bcs @p3
    KANA8 font_copy+$100
    jmp uk_next
@p2:
    KANA8 font_copy+$200
    jmp uk_next
@p3:
    KANA8 font_copy+$300
uk_next:
    txa
    clc
    adc #5
    tax
    lda TXR_UQN
    sec
    sbc #5
    sta TXR_UQN
    beq @out
    lda TXR_UQ,x
    bmi @out
    jmp uk_rec
@out:
    clc
    rts
; The kanji records of TXR_UQ from X on (R0 | $80, PPU address hi, lo of
; tile t, the glyph's pos and its store bank's R7 value): each one's
; four tiles t..t+3 (top-left, bottom-left, top-right, bottom-right: the
; store's tiles 0-3, 8x16 order) in plane 0 of page R0, from the kanji
; store at R7 (rows on pages: 4 cycles a byte), unrolled.  R7 and R0 written only
; when they change (KANJI_T0, KANJI_T1).  Stops at a kana record or the
; batch's end (C clear), or when TXR_UB has no UP_KANJI left (C set).
; X = the next record; Y lost; PPUCTRL +1 increments set by the caller.
.macro UJT j, k
    lda TXR_UQ+1,x
    sta PPUADDR
    lda TXR_UQ+2,x
    ora #j*16
    sta PPUADDR
    UJ8 k
.endm
.macro UJT0
    lda TXR_UQ+1,x
    sta PPUADDR
    lda TXR_UQ+2,x
    sta PPUADDR
    UJ8 0
.endm
.macro UJ8 k
    lda STORE_TAB+(k*8+0)*256,y
    sta PPUDATA
    lda STORE_TAB+(k*8+1)*256,y
    sta PPUDATA
    lda STORE_TAB+(k*8+2)*256,y
    sta PPUDATA
    lda STORE_TAB+(k*8+3)*256,y
    sta PPUDATA
    lda STORE_TAB+(k*8+4)*256,y
    sta PPUDATA
    lda STORE_TAB+(k*8+5)*256,y
    sta PPUDATA
    lda STORE_TAB+(k*8+6)*256,y
    sta PPUDATA
    lda STORE_TAB+(k*8+7)*256,y
    sta PPUDATA
.endm
up_kanji:
uj_rec:
    lda TXR_UB
    sec
    sbc #UP_KANJI
    bcs @fits
    sec                         ; no time left this NMI: C set
    rts
@fits:
    sta TXR_UB
    lda TXR_UQ+4,x              ; the store bank's R7 value
    cmp KANJI_T0
    beq @mapped
    sta KANJI_T0
    ldy #MMC3_R7
    sty MMC3_SELECT
    sta MMC3_DATA
@mapped:
    lda TXR_UQ,x
    and #$7F
    cmp KANJI_T1
    beq @r0
    sta KANJI_T1
    ldy #MMC3_R0
    sty MMC3_SELECT
    sta MMC3_DATA
@r0:
    ldy TXR_UQ+3,x              ; the pos
    UJT0
    UJT 1, 1
    UJT 2, 2
    UJT 3, 3
    txa
    clc
    adc #5
    tax
    lda TXR_UQN
    sec
    sbc #5
    sta TXR_UQN
    beq @out
    lda TXR_UQ,x
    bpl @out
    jmp uj_rec
@out:
    clc
    rts

; The released cells' entries (queue TXR_HI .. TXR_HE: PPU address, count,
; bytes; +1 increments) to the PPU; the queue read index past them.
rel_flush:
    ldx TXR_HI
@e:
    cpx TXR_HE
    beq @end
    lda $0400,x
    sta PPUADDR
    inx
    lda $0400,x
    sta PPUADDR
    inx
    lda $0400,x
    and #$7F
    tay
    inx
@d:
    lda $0400,x
    sta PPUDATA
    inx
    dey
    bne @d
    beq @e
@end:
    stx vram_queue_read
    stx KANJI_QPOS              ; (not counted as the game's next flush)
    rts
; The GC's row read (NMI after the game's flush, or the main thread with
; the NMI held off): TXR_N1 cells from TXR_A1H/L and TXR_N2 from
; TXR_A2H/L into TXR_GBUF.
row_read:
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL                 ; +1 increments
    ldy #0
    bit PPUSTATUS
    lda TXR_A1H
    sta PPUADDR
    lda TXR_A1L
    sta PPUADDR
    lda PPUDATA                 ; (the read buffer's old byte)
    ldx TXR_N1
@a:
    lda PPUDATA
    sta TXR_GBUF,y
    iny
    dex
    bne @a
    ldx TXR_N2
    beq @done
    bit PPUSTATUS
    lda TXR_A2H
    sta PPUADDR
    lda TXR_A2L
    sta PPUADDR
    lda PPUDATA
@b:
    lda PPUDATA
    sta TXR_GBUF,y
    iny
    dex
    bne @b
@done:
    lda #0
    sta TXR_RBQ
    rts
; The bank-9 font (1bpp, 128 glyphs), the build's asset (identical to
; bank 9 $BA00): kana glyphs (the main thread's and the NMI uploader's)
; and the font restore without a bank switch.  In the first 8 KiB with
; the NMI code: the NMI maps only that half of this bank at $8000.
    .align 256
font_copy:
    .incbin "../../decomp/build/assets/bank09_kana.bin"
nmi_code_end:
.if nmi_code_end > $A000
.error "the renderer's NMI code and the font copy must stay in the bank's first 8 KiB"
.endif

; Part p's R0 value, group-table base, bitmap base, kana-map base (lo/hi).
part_r0:    .db CHR_SCENE_LO, 8, 10, 12
part_g:     .db 0, TXR_NG, TXR_NG*2, TXR_NG*3
part_b:     .db 0, 16, 32, 48
part_kml:   .db <TXR_KM, <(TXR_KM+$80), <(TXR_KM+$100), <(TXR_KM+$180)
part_kmh:   .db >TXR_KM, >(TXR_KM+$80), >(TXR_KM+$100), >(TXR_KM+$180)
bitmask:    .db $80, $40, $20, $10, $08, $04, $02, $01

; New tiles $00-$0B: the old font codes they show.
fix_src:    .db $6D, $0B, $6E, $6F, $0C, $0D, $7D, $7E, $0E, $0F, $70, $71
; コマンド in page 1, tiles $7B-$7E.
cmd_src:    .db $4B, $24, $68, $6B

; ======================================================================
; Page and allocator setup
; ======================================================================

; The map setup (screen_refresh, in place of its font load), rendering
; off: page 1 lower = the fixed set, コマンド, everything else blank; pages
; 2-4 the first time after reset (nothing else uses them).  Every part's
; glyphs free.  Map mode from here.
txr_mapinit:
    jsr busy_on
    bit TXR_BOOT
    bmi @p1
    lda #8
    jsr page_init
    lda #10
    jsr page_init
    lda #12
    jsr page_init
    lda #$80
    sta TXR_BOOT
@p1:
    lda #CHR_SCENE_LO
    jsr page_init
    ldx #0                      ; コマンド
@cmd:
    stx TXR_G
    lda cmd_src,x
    jsr read_kana
    lda TXR_G
    clc
    adc #$7B
    jsr write_gbuf
    ldx TXR_G
    inx
    cpx #4
    bne @cmd
    jsr busy_off
    jsr txr_reset
    lda #$C0                    ; the renderer (bit 7) and the UI words (bit 6)
    sta TXR_ON
    rts

; R0 = A, every tile of the page: the fixed set at $00-$0B, the rest blank.
page_init:
    jsr set_r0
    bit PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #0
    sta PPUADDR
    tax                         ; the 2 KiB blank first
@z:
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    dex
    bne @z
    ldx #0
@f:
    stx TXR_G
    lda fix_src,x
    jsr read_kana
    lda TXR_G
    jsr write_gbuf
    ldx TXR_G
    inx
    cpx #12
    bne @f
    rts

; clear_screen (cv_fill, before the fill), rendering off: the font back
; into page 1 lower, as the game loads it.  Not map mode any more.
txr_restore:
    jsr busy_on
    lda #CHR_SCENE_LO
    jsr set_r0
    lda #0
    jsr tile_addr
    lda #<font_copy
    sta PTR
    lda #>font_copy
    sta PTR+1
    ldx #128                    ; tiles
@tile:
    ldy #0
@d:
    lda (PTR),y
    sta PPUDATA
    iny
    cpy #8
    bne @d
    lda #0
    ldy #8
@z:
    sta PPUDATA
    dey
    bne @z
    lda PTR
    clc
    adc #8
    sta PTR
    bcc @n
    inc PTR+1
@n:
    dex
    bne @tile
    jsr busy_off
    lda #0
    sta TXR_ON
    sta MMC3_IRQ_OFF            ; no map split pending any more
    sta KANJI_IRQ_ST
    rts

; redraw_start (TXF_RESET: the full redraw that closes the map's windows):
; no part shows text now.  A part keeps its glyphs, so a window opened
; again finds them and uploads nothing (TEXT_RENDERER.md "Upload speed",
; E), unless it has fewer than KEEP_MIN free tiles: then it is freed here,
; for nothing, instead of by a read-back GC (a frame per row) in the next
; window.
KEEP_MIN        = 48            ; free tiles (12 kanji) a part keeps its glyphs with
txr_close:
    lda #0
    sta TXR_SKIP
    ldx #3
@p:
    stx TXR_P
    jsr part_free
    cmp #KEEP_MIN
    bcs @keep
    jsr part_reset
@keep:
    ldx TXR_P
    dex
    bpl @p
    rts

; A = the free tiles of part TXR_P (zero bits in its bitmap).
part_free:
    ldx TXR_P
    lda part_b,x
    tax
    lda #16
    sta TXR_J
    lda #0
    sta TXR_I
@b:
    lda TXR_TBM,x
    and #$0F
    tay
    lda nib_free,y
    clc
    adc TXR_I
    sta TXR_I
    lda TXR_TBM,x
    lsr a
    lsr a
    lsr a
    lsr a
    tay
    lda nib_free,y
    clc
    adc TXR_I
    sta TXR_I
    inx
    dec TXR_J
    bne @b
    lda TXR_I
    rts
nib_free:   .db 4, 3, 3, 2, 3, 2, 2, 1, 3, 2, 2, 1, 2, 1, 1, 0

; Every part's glyphs free.  The map setup only (page 1 held the font, or
; another screen's tiles, before).
txr_reset:
    ldx #3
@p:
    stx TXR_P
    jsr part_reset
    ldx TXR_P
    dex
    bpl @p
    lda TXR_HB                  ; (never left held: the queue would stop)
    beq @nh
    and #$7F
    ldy TXR_HI
    sta $0400,y
@nh:
    lda #0
    sta TXR_HB
    sta TXR_UQN
    sta TXR_FULL
    sta TXR_SKIP
    rts

; Part TXR_P's glyphs free: its kana map empty, its groups free, its bitmap
; holding only the pinned tiles (the fixed set, the blank; page 1's
; コマンド, whose kana stay mapped).
part_reset:
    ldx TXR_P
    lda part_kml,x
    sta PTR
    lda part_kmh,x
    sta PTR+1
    lda #0
    ldy #127
@km:
    sta (PTR),y
    dey
    bpl @km
    lda part_g,x
    tay
    ldx #TXR_NG
    lda #$FF
@g:
    sta TXR_GHI,y
    iny
    dex
    bne @g
    ldx TXR_P
    lda part_b,x
    tax
    lda #$FF                    ; tiles $00-$07, $08-$0B: fixed
    sta TXR_TBM,x
    lda #$F0
    sta TXR_TBM+1,x
    lda #0
    ldy #13
@z:
    sta TXR_TBM+2,x
    inx
    dey
    bne @z
    lda #$01                    ; $7F blank (byte 15: X is base + 13)
    sta TXR_TBM+2,x
    lda TXR_P
    bne @r
    lda #$1F                    ; page 1: $7B-$7F
    sta TXR_TBM+15
    ldx #3
@cmd:
    lda cmd_src,x
    tay
    txa
    clc
    adc #$7B
    sta TXR_KM,y
    dex
    bpl @cmd
@r:
    rts

; ----------------------------------------------------------------------
; The nametable fill set_ppu_scroll ($C2AB; RAM cv_fill stores A/X/Y in
; $00-$02 and calls this): A = table ($20 / $24), X = tile, Y = attribute
; byte; rendering off.  Both twins (four-screen), unrolled.  Leaving map
; mode (clear_screen starts every other screen): the font back first.
; ----------------------------------------------------------------------
txr_fill:
    bit TXR_ON                  ; leaving map mode: the font back first
    bpl @fx                     ; (TEXT_RENDERER.md)
    jsr txr_restore
@fx:
    lda #0                      ; (the boot screens' fixed set ends too)
    sta TXR_ON
    ; PPUCTRL bit 1 is the map camera's vertical half (walk_scroll, nt_bits:
    ; the four-screen ring); the original never sets it, its screens draw
    ; into the upper twins and showed either.  A screen built here shows
    ; the upper one (2026-11-17: the ending's last two screens, drawn at
    ; $2000 after a map scene that left bit 1 set, showed the blank $2800).
    ; The map sets it again from its camera (set_scroll_from_cursor).
    lda ppu_ctrl_shadow
    and #$FD
    sta ppu_ctrl_shadow
cvf_go:
    lda $00
    ldy #1                      ; two tables (no subroutine: the original
    ora #$08                    ; is flat, the stack stays as deep): the
cvf_table:                      ; lower twin first
    bit PPUSTATUS
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda $01
    ldx #64                     ; 64 x 16 bytes
cvf_loop:
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    dex
    beq cvf_tdone
    cpx #4
    bne cvf_loop
    lda $02                     ; the last 64: the attribute bytes
    jmp cvf_loop
cvf_tdone:
    lda $00                     ; then the table
    dey
    bpl cvf_table
    rts

; The boot screens (txr_menu in RAM, after ppu_init: rendering and the NMI
; off): the menus, starting / registering / deleting / copying a history
; book, the name entry.  No arbitrary text there, so no renderer: the
; font stays in page 1 and the fixed set (txr_ui.inc: the kanji of the
; boot menu, the speed window, the name entry, the record prompts: the
; user's set, 2026-11-14) goes to upper-page tiles FIX_FIRST.. (the battle
; set's tiles there are never shown on these screens).  The UI words and
; the messages' kanji (the message engine's fix_put) are put with those tiles
; (TXR_ON = $40): no band.  The battle pool's tiles hold the set: no pool.
; The set goes into CHR once, at the boot entry (txr_menuset; 2026-11-14:
; nothing writes those tiles while the boot screens last, measured on every
; flow), so a screen sets only the flags here.
txr_menuinit:
    lda KANJI_WIN_COL
    and #$3F
    ora #WINCOL_CHECKED         ; checked, not usable
    sta KANJI_WIN_COL
    lda #$40
    sta TXR_ON
    rts

; TXF_MENUSET: the fixed set into upper-page tiles FIX_FIRST.. (bank 13
; b13_k_set, at the boot entry after b13_loc_8A23's graphics set 8, which
; writes those tiles; rendering off).
txr_menuset:
    jsr busy_on
    ldx #0
@g:
    stx TXR_G
    lda fix_clo,x
    sta TXR_K
    lda fix_chi,x
    sta TXR_K+1
    jsr read_kanji              ; TXR_GBUF[0-31]
    lda TXR_G
    asl a
    asl a
    adc #FIX_FIRST              ; (C clear)
    sta TXR_T
    ldy #0                      ; t: top-left (TXR_GBUF in 8x16 order,
    jsr fix_tile                ; as the store)
    ldy #8                      ; t+1: bottom-left
    jsr fix_tile
    ldy #16                     ; t+2: top-right
    jsr fix_tile
    ldy #24                     ; t+3: bottom-right
    jsr fix_tile
    ldx TXR_G
    inx
    cpx #FIX_N
    bne @g
    jmp busy_off

; TXF_OATH: the opening oath's kanji (txr_ui.inc oath_clo/chi, the user's
; set) into CHR $3800 (the band page until 2026-11-14), tiles 4k..4k+3 there
; (TL, BL, TR, BR), written with R0 = CHR_BAND_LO; R1 shows them as tiles
; $80 + 4k below the fixed split.
; Then TXR_ON = TXR_SPLIT.  Bank 13 b13_k_oath, after the scene's portraits
; and before its fade-in (rendering off).
txr_oathset:
    jsr busy_on
    lda #CHR_BAND_LO
    jsr set_r0
    ldx #0
@g:
    stx TXR_G
    lda oath_clo,x
    sta TXR_K
    lda oath_chi,x
    sta TXR_K+1
    jsr read_kanji              ; TXR_GBUF[0-31]
    lda TXR_G
    asl a
    asl a
    sta TXR_T
    ldy #0
    jsr fix_tile
    ldy #8
    jsr fix_tile
    ldy #16
    jsr fix_tile
    ldy #24
    jsr fix_tile
    ldx TXR_G
    inx
    cpx #OATH_N
    bne @g
    jsr busy_off                ; (R0 = the scene page again)
    lda #TXR_SPLIT
    sta TXR_ON
    rts

; TXF_OATHEND (bank 13 b13_k_oathend, rendering and the NMI off): the split
; off (TXR_ON first, so a pending IRQ switches nothing), R1 = the scene page.
; CHR $3800 keeps the oath's kanji: nothing else uses it outside map mode.
txr_oathend:
    lda #0
    sta TXR_ON
    sta MMC3_IRQ_OFF
    sta KANJI_IRQ_ST
    lda #MMC3_R1
    sta MMC3_SEL
    sta MMC3_SELECT
    lda #CHR_SCENE_HI
    sta MMC3_DATA
    rts

; Tile TXR_T = TXR_GBUF[Y..Y+7] in plane 0, plane 1 zero; then TXR_T + 1.
fix_tile:
    lda TXR_T
    jsr tile_addr
    ldx #8
@b:
    lda TXR_GBUF,y
    sta PPUDATA
    iny
    dex
    bne @b
    txa
    ldx #8
@z:
    sta PPUDATA
    dex
    bne @z
    inc TXR_T
    rts

; ======================================================================
; PPU helpers (rendering off, busy: the main thread owns the PPU)
; ======================================================================

; The NMI leaves the PPU alone (busy) and the hack NMI leaves R0 alone.
busy_on:
    inc nmi_busy
    lda #1
    sta KANJI_MAINCHR
    lda ppu_ctrl_shadow         ; +1 increments (a vertical queue entry may
    and #$FB                    ; have left +32)
    sta PPUCTRL
    rts
busy_off:
    lda #CHR_SCENE_LO
    jsr set_r0
    lda #0
    sta KANJI_MAINCHR
    dec nmi_busy
    rts

; R0 = A under the bank-select shadow (main thread).
set_r0:
    pha
    lda #MMC3_R0
    sta MMC3_SEL
    sta MMC3_SELECT
    pla
    sta MMC3_DATA
    rts

; PPU address = plane 0 of tile A (pattern table $1000).
tile_addr:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    bit PPUSTATUS
    sta PPUADDR
    pla
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
    rts

; Tile A of the R0 page = TXR_GBUF[0-7] in plane 0, plane 1 zero.
write_gbuf:
    jsr tile_addr
    ldx #0
@d:
    lda TXR_GBUF,x
    sta PPUDATA
    inx
    cpx #8
    bne @d
    lda #0
@z:
    sta PPUDATA
    dex
    bne @z
    rts

; TXR_GBUF[0-7] = the old font's glyph A (1bpp; this bank's copy of the
; bank-9 font, so no bank switch: the stack stays shallow).
read_kana:
    ldx #0
    stx PTR+1
    asl a
    rol PTR+1
    asl a
    rol PTR+1
    asl a
    rol PTR+1
    sta PTR
    lda PTR+1
    clc
    adc #>font_copy
    sta PTR+1
    ldy #7
@c:
    lda (PTR),y
    sta TXR_GBUF,y
    dey
    bpl @c
    rts

; TXR_GBUF[0-31] = kanji glyph TXR_K (store bank TXR_K+1, pos TXR_K), in
; the store's order (8x16: TL, BL, TR, BR, 8 rows each): byte b at
; STORE_TAB + 256 b + pos with the store's 8 KiB bank STORE_8K + TXR_K+1
; at R7, PRG_R7X set (an NMI's restore keeps it; ui.asm M_STMAP), then R7
; back to this bank's upper half, PRG_R7X cleared first (M_STUNMAP).  The
; loop runs in this bank's lower half and touches no upper-half data.
; (Until 2026-11-14 a RAM routine mapped the store as the current bank.)
; Called only where the main thread writes CHR itself (rendering off or
; the NMI busy: txr_menuset, txr_oathset, is_direct's glyphs).  Padded to
; the old reader's cycles.  PTR lost, X = 0, Y = pos.
RK_PAD          = 168           ; 5 * 168 + 1 = 841 cycles
read_kanji:
    lda TXR_K+1
    ora #STORE_8K
    sta PRG_R7X
    tax
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    stx MMC3_DATA
    lda #<STORE_TAB
    sta PTR
    lda #>STORE_TAB
    sta PTR+1
    ldy TXR_K
    ldx #0
@b:
    lda (PTR),y
    sta TXR_GBUF,x
    inc PTR+1
    inx
    cpx #32
    bne @b
    lda #0
    sta PRG_R7X
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    lda #TXR_BANK*2+1
    sta MMC3_DATA
    ldx #RK_PAD                 ; (the RAM reader's 1,618 cycles, jsr to
@pad:                           ; return: the boot entry and the oath read
    dex                         ; 25 and 20 glyphs with rendering off, and
    bne @pad                    ; 841 cycles less moved the boot menu a
    rts                         ; frame earlier, and the standard path's RNG)
.if $ > $A000
    .error "read_kanji must run in the bank's lower half (R7 holds the store)"
.endif
.if >@pad != >$
    .error "read_kanji's pad loop crosses a page (+1 cycle per pass)"
.endif

; ======================================================================
; Staging: TXR_SN records built in TXR_UQ, then published (TXR_UQN) for
; the NMI uploader.  With rendering off (or busy) they are written
; directly, the NMI held off.  The renderer never waits itself: a
; function that needs the NMI returns TXR_ST = 1 and the RAM stub waits
; at the original routine's stack depth, then calls the continuation.
; ======================================================================

; C clear: room for a record of A bytes.  C set: no room, the batch is
; published (TXR_ST = 1).
stage_room:
    clc
    adc TXR_SN
    cmp #TXR_UQSZ+1
    bcc @ok
    jsr stage_out
    sec
    rts
@ok:
    clc
    rts

; The batch out: published for the NMI (TXR_ST = 1, TXR_SN kept until the
; stub's continuation clears it).  Records exist only with rendering on
; and not busy (otherwise stage_kana / stage_kanji write the glyph at once).
stage_out:
    lda TXR_SN
    beq @rts
    jsr stage_pub
    lda #1
    sta TXR_ST
@rts:
    rts

; The batch published for the NMI uploader.
stage_pub:
    lda #0
    sta TXR_UQR
    lda TXR_SN
    sta TXR_UQN
    rts

; Z set: the main thread writes CHR itself (rendering off, or busy).
is_direct:
    lda nmi_busy
    bne @busy
    lda ppu_mask_shadow
    and #$18
    rts
@busy:
    lda #0
    rts

; The record at TXR_SN: R0 = part TXR_P's (| A), the PPU address of tile
; TXR_T at +1/+2.  X = TXR_SN.
rec_head:
    ldx TXR_SN
    ldy TXR_P
    ora part_r0,y
    sta TXR_UQ,x
    lda TXR_T
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta TXR_UQ+1,x
    lda TXR_T
    asl a
    asl a
    asl a
    asl a
    sta TXR_UQ+2,x
    rts

; Kana TXR_B as tile TXR_T of part TXR_P: a record (R0, PPU address hi,
; lo, the glyph's offset in its 256-byte font page, the page), or with
; rendering off / busy the glyph written now.
stage_kana:
    jsr is_direct
    beq @now
    lda #0
    jsr rec_head
    lda TXR_B
    asl a
    asl a
    asl a
    sta TXR_UQ+3,x
    lda TXR_B
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    sta TXR_UQ+4,x
    txa
    clc
    adc #5
    sta TXR_SN
    rts
@now:
    lda TXR_B
    jsr read_kana
    jsr busy_on
    ldy TXR_P
    lda part_r0,y
    jsr set_r0
    lda TXR_T
    jsr write_gbuf
    jmp busy_off

; Kanji TXR_K as group tiles TXR_T .. TXR_T + 3 of part TXR_P: a record
; (R0 | $80, PPU address hi, lo of tile TXR_T, the glyph's pos and its
; store bank's R7 value: the code as it is), or with rendering off / busy
; the glyph written now (TXR_T + 4 after).
stage_kanji:
    jsr is_direct
    beq @now
    lda #$80
    jsr rec_head
    lda TXR_K
    sta TXR_UQ+3,x              ; its pos
    lda TXR_K+1
    ora #STORE_8K
    sta TXR_UQ+4,x              ; its store bank's R7 value
    txa
    clc
    adc #5
    sta TXR_SN
    rts
@now:
    jsr read_kanji              ; TXR_GBUF[0-31]
    jsr busy_on
    ldy TXR_P
    lda part_r0,y
    jsr set_r0
    ldy #0                      ; top-left (8x16 order, as the store)
    jsr fix_tile
    ldy #8                      ; bottom-left
    jsr fix_tile
    ldy #16                     ; top-right
    jsr fix_tile
    ldy #24                     ; bottom-right
    jsr fix_tile
    jmp busy_off

; ======================================================================
; Translation
; ======================================================================

; Part and parity of the nametable address A (high) / X (low) on the
; 60-row ring: TXR_P = 0-3 by screen row, TXR_PAR = 0 for an odd row (a
; text line's top row).
addr_part:
    sta TXR_I
    and #$08                    ; lower vertical half: +30 rows
    beq @u
    lda #30
@u:
    sta TXR_J
    lda TXR_I
    and #$03
    asl a
    asl a
    asl a
    sta TXR_I                   ; (hi & 3) * 8
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    ora TXR_I                   ; row 0-29 in its half
    tax
    and #1
    eor #1
    sta TXR_PAR
    txa
    clc
    adc TXR_J                   ; ring row 0-59
    sta TXR_I
    lda ppu_ctrl_shadow         ; the camera's top ring row
    and #$02
    beq @t
    lda #30
@t:
    sta TXR_J
    lda scroll_y
    lsr a
    lsr a
    lsr a
    clc
    adc TXR_J
    sta TXR_J
    lda TXR_I
    sec
    sbc TXR_J
    bcs @pos
    adc #60
@pos:
    ldx #0
    cmp #9
    bcc @p
    inx
    cmp #15
    bcc @p
    inx
    cmp #21
    bcc @p
    inx
@p:
    stx TXR_P
    rts

; C clear: A = the tile for cell byte A in part TXR_P (row parity
; TXR_PAR); a glyph new in this part is allocated and staged.  Bytes
; $C0-$FF unchanged: the line-end codes, and tiles of the upper page that
; menus write as they are (the boot menu's L, $EB, from the UI block); the
; kanji codes are $80-$BF (REG entries 0-31).  C set: no staging room
; (nothing allocated; retry after the batch is in, TXR_ST = 1).
xlate:
    cmp #$C0
    bcs @keep
    sta TXR_B
    cmp #$80
    bcs @kanji
    tay
    lda fix_map,y
    bpl @ok                     ; the fixed set and the blank
    ; Kana: this part's tile, or a new one from the top down.
    ldx TXR_P
    lda part_kml,x
    sta PTR
    lda part_kmh,x
    sta PTR+1
    ldy TXR_B
    lda (PTR),y
    bne @ok
    lda #5
    jsr stage_room
    bcs @rts
    jsr alloc_kana
    bcs @full
    sta TXR_T
    ldy TXR_B
    sta (PTR),y
    jsr stage_kana
    lda TXR_T
@ok:
    clc
@rts:
    rts
@keep:
    clc
    rts
@full:
    lda TXR_GCF
    bne @blank                  ; the GC ran for this line already
    jsr stage_out               ; what is staged goes up first
    lda TXR_P
    ora #$80
    sta TXR_GCS                 ; the continuation runs the GC first
    lda #0
    sta TXR_GCR
    lda #1
    sta TXR_ST
    sec
    rts
@blank:
    inc TXR_FULL
    lda #BLANK
    clc
    rts
@kanji:
    and #$7F
    lsr a
    tax
    lda REG_LO,x
    sta TXR_K
    lda REG_HI,x
    sta TXR_K+1
    jsr find_group
    bcc @have
    lda #5
    jsr stage_room
    bcs @rts
    jsr alloc_group
    bcs @full
    lda TXR_G
    asl a
    asl a
    adc #$0C
    sta TXR_T
    jsr stage_kanji
@have:
    lda TXR_G                   ; t + 2 * right half + bottom row
    asl a
    asl a
    adc #$0C
    sta TXR_T
    lda TXR_B
    and #1
    asl a
    ora TXR_PAR
    ora TXR_T
    clc
    rts

; C clear: TXR_G = the group of part TXR_P holding glyph TXR_K.
find_group:
    ldx TXR_P
    lda part_g,x
    tax
    ldy #0
@l:
    lda TXR_GHI,x
    cmp TXR_K+1
    bne @n
    lda TXR_GLO,x
    cmp TXR_K
    beq @f
@n:
    inx
    iny
    cpy #TXR_NG
    bne @l
    sec
    rts
@f:
    sty TXR_G
    clc
    rts

; C clear: TXR_G = a free group of part TXR_P (4 tiles free), now TXR_K's.
alloc_group:
    ldx TXR_P
    lda part_g,x
    sta TXR_I
    lda #0
    sta TXR_G
@l:
    ldx TXR_I
    lda TXR_GHI,x
    cmp #$FF
    bne @n
    jsr group_bits              ; X = bitmap byte, A = the group's 4 bits
    and TXR_TBM,x
    beq @take
@n:
    inc TXR_I
    inc TXR_G
    lda TXR_G
    cmp #TXR_NG
    bne @l
    sec
    rts
@take:
    jsr group_bits
    ora TXR_TBM,x
    sta TXR_TBM,x
    ldx TXR_I
    lda TXR_K
    sta TXR_GLO,x
    lda TXR_K+1
    sta TXR_GHI,x
    clc
    rts

; Group TXR_G of part TXR_P: X = its bitmap byte, A = its 4 bits.  Tiles
; $0C + 4g: byte (3 + g) >> 1, the low nibble for even g.
group_bits:
    lda TXR_G
    clc
    adc #3
    lsr a
    php
    ldx TXR_P
    clc
    adc part_b,x
    tax
    plp
    lda #$0F
    bcs @r
    lda #$F0
@r:
    rts

; C clear: A = a free tile of part TXR_P for a kana, from $7E down to $0C;
; marked used.
alloc_kana:
    ldx TXR_P
    lda part_b,x
    clc
    adc #15
    tax                         ; bitmap byte of tiles $78-$7F
    lda #$7F
    sta TXR_T
@byte:
    lda TXR_TBM,x
    cmp #$FF
    beq @next8
    ldy #7                      ; bit 7 - (tile & 7)
@bit:
    lda bitmask,y
    and TXR_TBM,x
    beq @take
    dec TXR_T
    dey
    bpl @bit
    bmi @nexttile
@next8:
    lda TXR_T
    sec
    sbc #8
    sta TXR_T
@nexttile:
    dex
    txa
    ldy TXR_P
    sec
    sbc part_b,y
    cmp #1                      ; down to byte 1 (tiles $08-$0F: $0C-$0F)
    bcs @byte
    sec
    rts
@take:
    lda TXR_T
    cmp #$0C
    bcc @no
    lda bitmask,y
    ora TXR_TBM,x
    sta TXR_TBM,x
    lda TXR_T
    clc
    rts
@no:
    sec
    rts

; ======================================================================
; GC (a part is full): read the part's visible rows back from VRAM, one
; row a frame (the NMI) or all at once (rendering off), keep the tiles
; shown and the ones this line already uses, free every other kana tile
; and kanji group, then the line goes on (the failed cell retried).
; C set: wait (TXR_ST = 1), then call again; C clear: done.
; ======================================================================
part_row:   .db 0, 9, 15, 21
part_rows:  .db 9, 6, 6, 9

gc_step:
    lda TXR_RBQ
    beq @go
    jmp gc_wait
@go:
    lda TXR_GCS
    and #3
    sta TXR_P
    lda TXR_GCR
    bne gc_got
    ; Start: the bitmap holds the tiles this line already uses (EB's bytes
    ; before TXR_E, the cell's tiles; conservative) and page 1's pins.
    ldx #15
    lda #0
@clr:
    sta TXR_MARK,x
    dex
    bpl @clr
    ldx TXR_E
    beq @cell
@eb:
    dex
    lda TXR_EB,x
    jsr mark_tile
    cpx #0
    bne @eb
@cell:
    lda TXR_CT
    jsr mark_tile
    lda TXR_CT+1
    jsr mark_tile
    lda TXR_CB
    jsr mark_tile
    lda TXR_CB+1
    jsr mark_tile
    lda TXR_MARK+15
    ora #$1E                    ; $7B-$7E (pinned in page 1)
    sta TXR_MARK+15
    ldx TXR_P
    lda part_rows,x
    sta TXR_GN
    jmp gc_req
gc_got:
    ldx #31                     ; the row read: mark its tiles
@m:
    lda TXR_GBUF,x
    jsr mark_tile
    dex
    bpl @m
    lda TXR_GCR
    cmp TXR_GN
    bcs gc_free
gc_req:
    jsr row_addr
    inc TXR_GCR
    lda #1
    sta TXR_RBQ
    lda nmi_busy
    bne @direct
    lda ppu_mask_shadow
    and #$18
    bne gc_wait
@direct:
    jsr busy_on
    jsr row_read
    jsr busy_off
    jmp gc_got
gc_wait:
    lda #1
    sta TXR_ST
    sec
    rts
gc_free:
    ; Kana: a tile no row shows is free again.
    ldx TXR_P
    lda part_kml,x
    sta PTR
    lda part_kmh,x
    sta PTR+1
    ldy #127
@k:
    lda (PTR),y
    beq @kn
    jsr is_marked
    bne @kn
    lda (PTR),y
    jsr tbm_clear
    lda #0
    sta (PTR),y
@kn:
    dey
    bpl @k
    ; Kanji groups: one whose four tiles no row shows is free again.
    lda #0
    sta TXR_G
@g:
    ldx TXR_P
    lda part_g,x
    clc
    adc TXR_G
    tay
    lda TXR_GHI,y
    cmp #$FF
    beq @gn
    lda TXR_G                   ; (3 + g) >> 1, the nibble
    clc
    adc #3
    lsr a
    tax
    lda #$0F
    bcs @nib
    lda #$F0
@nib:
    and TXR_MARK,x
    bne @gn
    lda #$FF
    sta TXR_GHI,y
    jsr group_bits              ; X = the part's bitmap byte, A = nibble
    eor #$FF
    and TXR_TBM,x
    sta TXR_TBM,x
@gn:
    inc TXR_G
    lda TXR_G
    cmp #TXR_NG
    bne @g
    lda #0
    sta TXR_GCS
    sta TXR_GCR
    lda #1
    sta TXR_GCF
    clc
    rts

; A = a tile: set in TXR_MARK when below $7F (X, Y kept).
mark_tile:
    cmp #$7F
    bcs @r
    stx TXR_J
    pha
    and #7
    tax
    lda bitmask,x
    sta TXR_I
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda TXR_I
    ora TXR_MARK,x
    sta TXR_MARK,x
    ldx TXR_J
@r:
    rts

; A = a tile: Z clear when it is in TXR_MARK (Y kept).
is_marked:
    pha
    and #7
    tax
    lda bitmask,x
    sta TXR_I
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda TXR_MARK,x
    and TXR_I
    rts

; A = a tile of part TXR_P: its bit in TXR_TBM cleared (Y kept).
tbm_clear:
    pha
    and #7
    tax
    lda bitmask,x
    eor #$FF
    sta TXR_I
    pla
    lsr a
    lsr a
    lsr a
    ldx TXR_P
    clc
    adc part_b,x
    tax
    lda TXR_I
    and TXR_TBM,x
    sta TXR_TBM,x
    rts

; The nametable addresses of screen row part_row[P] + TXR_GCR: 32 cells
; from the camera's left column, up to two segments (the ring's two
; horizontal tables).
row_addr:
    ldx TXR_P
    lda part_row,x
    clc
    adc TXR_GCR
    sta TXR_I                   ; screen row
    lda ppu_ctrl_shadow
    and #$02
    beq @t
    lda #30
@t:
    sta TXR_J
    lda scroll_y
    lsr a
    lsr a
    lsr a
    clc
    adc TXR_J
    clc
    adc TXR_I                   ; ring row
    cmp #60
    bcc @r60
    sbc #60
@r60:
    ldx #$20                    ; upper half
    cmp #30
    bcc @h
    sbc #30
    ldx #$28                    ; lower half
@h:
    stx TXR_A1H
    sta TXR_I                   ; row in the half
    lsr a
    lsr a
    lsr a
    ora TXR_A1H
    sta TXR_A1H                 ; + row >> 3
    sta TXR_A2H
    lda TXR_I
    asl a
    asl a
    asl a
    asl a
    asl a
    sta TXR_A1L                 ; (row & 7) << 5
    sta TXR_A2L
    lda scroll_x                ; first column on the 64-column ring
    lsr a
    lsr a
    lsr a
    sta TXR_I                   ; column 0-31
    lda ppu_ctrl_shadow
    and #$01
    beq @x
    lda TXR_A1H
    ora #$04
    sta TXR_A1H                 ; the right table first
    bne @x2
@x:
    lda TXR_A2H
    ora #$04
    sta TXR_A2H                 ; the right table second
@x2:
    lda TXR_A1L
    ora TXR_I
    sta TXR_A1L
    lda #32
    sec
    sbc TXR_I
    sta TXR_N1
    lda TXR_I
    sta TXR_N2
    rts

; ======================================================================
; text_draw_line's entries (queue $40 .. TXR_QX).  They leave the queue
; (other tasks may queue while glyphs upload: the stub's waits yield),
; are translated in TXR_EB, then queued again at the queue's end; TXR_QX
; = the new end (the stub writes the terminator and commits).
; TXF_DL starts, TXF_DLC continues after a wait (TXR_ST = 1 returned).
; ======================================================================
txr_dl:
    ldx vram_queue_write
    ldy #0
@out:
    cpx TXR_QX
    beq @outd
    lda $0400,x
    sta TXR_EB,y
    inx
    iny
    cpy #48
    bne @out
@outd:
    sty TXR_EL
    ldx vram_queue_write
    lda #0
    sta $0400,x                 ; the queue ends before them again
    sta TXR_SN
    sta TXR_E
    sta TXR_EN
    sta TXR_GCF
    beq dl_go
txr_dlc:
    lda TXR_HB
    beq @nohold
    ldy TXR_HI                  ; the rows held back during the wait
    sta $0400,y
    lda #0
    sta TXR_HB
@nohold:
    lda #0
    sta TXR_SN                  ; (the NMI has the batch in CHR)
    bit TXR_GCS
    bpl dl_go
    jsr gc_step
    bcc dl_go
    rts                         ; (TXR_ST = 1: a row read or uploads)
dl_go:
    lda #0
    sta TXR_ST
@loop:
    ldx TXR_E
    cpx TXR_EL
    bcs @done
    lda TXR_EN
    bne @cell
    lda TXR_EB,x                ; an entry's header
    pha
    lda TXR_EB+1,x
    tax
    pla
    jsr addr_part
    ldx TXR_E
    lda TXR_EB+2,x
    and #$7F
    sta TXR_EN
    inx
    inx
    inx
    stx TXR_E
    jmp @loop
@cell:
    lda TXR_EB,x
    jsr xlate
    bcs @wait
    ldx TXR_E
    sta TXR_EB,x
    inx
    stx TXR_E
    dec TXR_EN
    jmp @loop
@wait:
    jmp dl_hold
@done:
    jsr stage_out
    lda TXR_ST
    bne @wait                   ; the last batch first (TXF_DLC: queued)
    ldx vram_queue_write
    ldy #0
@in:
    cpy TXR_EL
    beq @ind
    lda TXR_EB,y
    sta $0400,x
    inx
    iny
    bne @in
@ind:
    stx TXR_QX
    rts

; The entry waits for its glyphs (TXR_ST = 1): what is queued before it
; (the row pair's first row) is held back until it is committed, so the
; pair and the attributes draw_map_object queues after it reach the
; screen in one frame (a row shown with the old attributes for a frame
; or more otherwise).  Not while a GC reads the rows back: they must be
; on screen then.  txr_dlc releases it.
dl_hold:
    bit TXR_GCS
    bmi @r
    ldy vram_queue_read
    lda $0400,y
    beq @r                      ; nothing queued
    sta TXR_HB
    sty TXR_HI
    lda #0
    sta $0400,y                 ; the NMI's flush stops there
@r:
    rts

; ======================================================================
; text_render_cell in map mode (the original at $DBCA), one step a call:
; a cell, or a kanji's two columns (no half kanji), translated and
; queued.  TXR_ST: 0 = the line ended (TXR_RET = its end byte), 1 = wait
; for the uploads then TXF_RCC, 2 = queued: the stub pauses TXR_WC cells
; from row-buffer index TXR_Y (as the original), then TXF_RCC.
; ======================================================================
txr_rc:
    ldx text_line
    lda CELL_ROWS,x
    sta ptr1_hi
    lda #0
    sta TXR_SN
    sta TXR_GCF
    beq rc_step
txr_rcc:
    lda TXR_UQN                 ; the last batch in CHR and its cells
    ora TXR_RBQ                 ; released (or the GC's row read done)?
    ora TXR_HB
    beq @go
    lda #1                      ; not yet: the stub waits a frame
    sta TXR_ST
    rts
@go:
    lda #0
    sta TXR_SN
    bit TXR_GCS
    bpl rc_step
    jsr gc_step
    bcc rc_step
    rts
rc_step:
    lda #0
    sta TXR_ST
    ldy ptr1_hi
    sty TXR_Y
    lda $0300,y
    cmp #$FA
    bcc @cell
    sta TXR_RET                 ; the line's end
    ldx vram_queue_write
    lda #0
    sta $0400,x
    rts
@cell:
    ldx #1
    cmp #$80
    bcc @n1
    lsr a                       ; a kanji's left half (even): both columns
    bcs @n1
    inx
@n1:
    stx TXR_N
    lda ppu_addr_hi_shadow      ; the cell's part (its top row)
    ldx ppu_addr_lo_shadow
    jsr addr_part
    ldy TXR_Y
    lda $0300,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CT
    inc TXR_PAR                 ; (0: the top row) the bottom row
    ldy TXR_Y
    lda $0318,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CB
    lda TXR_N
    cmp #2
    bne @tr
    dec TXR_PAR
    ldy TXR_Y
    lda $0301,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CT+1
    inc TXR_PAR
    ldy TXR_Y
    lda $0319,y
    jsr xlate
    bcc $+5
    jmp @wait
    sta TXR_CB+1
@tr:
    ldx vram_queue_write
    stx TXR_HE                  ; (the cells' first byte, for now)
    lda #0
    sta TXR_G
@q:
    ldx TXR_G
    lda TXR_CT,x
    sta TXR_T
    lda TXR_CB,x
    sta TXR_B
    jsr queue_cell
    inc TXR_G
    lda TXR_G
    cmp TXR_N
    bne @q
    ldx vram_queue_write
    lda #0
    sta $0400,x
    lda TXR_SN
    beq @nb
    ; New glyphs: the cells go up in the NMI that uploads them
    ; (TEXT_RENDERER.md "Upload speed", C).  Held back until then (the
    ; game's flush stops at the 0); the NMI puts the byte back after the
    ; batch and flushes them itself when the time allows.  The hold
    ; first, then the batch: an NMI between them has nothing to release.
    ldy TXR_HE
    sty TXR_HI                  ; the held cells: TXR_HI .. TXR_HE
    stx TXR_HE
    lda $0400,y
    ora #$80
    sta TXR_HB
    lda #0
    sta $0400,y
    jsr stage_pub
@nb:
    lda #0
    sta TXR_GCF                 ; (the next cell may run the GC again)
    lda TXR_N
    sta TXR_WC
    clc
    adc ptr1_hi
    sta ptr1_hi
    lda #2
    sta TXR_ST
@rts:
    rts
@wait:
    rts                         ; (stage_room published: TXR_ST = 1)

; Two queue entries: TXR_T at ($69, $68), TXR_B one row below (the
; four-screen wrap of $DC0E), then the cursor one cell right (the next
; table at column 32).  Committed (vram_queue_write).
queue_cell:
    ldx vram_queue_write
    lda ppu_addr_hi_shadow
    sta $0400,x
    inx
    lda ppu_addr_lo_shadow
    sta $0400,x
    inx
    lda #1
    sta $0400,x
    inx
    lda TXR_T
    sta $0400,x
    inx
    lda ppu_addr_hi_shadow
    sta TXR_I
    lda ppu_addr_lo_shadow
    clc
    adc #$20
    sta TXR_J
    bcc @c
    inc TXR_I
@c:
    cmp #$C0
    bcc @ok
    lda TXR_I
    and #$03
    cmp #$03
    bne @ok
    lda TXR_I                   ; below row 29: row 0 of the other half
    eor #$0B
    sta TXR_I
    lda TXR_J
    and #$1F
    sta TXR_J
@ok:
    lda TXR_I
    sta $0400,x
    inx
    lda TXR_J
    sta $0400,x
    inx
    lda #1
    sta $0400,x
    inx
    lda TXR_B
    sta $0400,x
    inx
    lda #0
    sta $0400,x                 ; the terminator before the commit
    stx vram_queue_write
    inc ppu_addr_lo_shadow
    lda ppu_addr_lo_shadow
    and #$1F
    bne @rts
    lda ppu_addr_hi_shadow
    eor #$04
    sta ppu_addr_hi_shadow
    lda ppu_addr_lo_shadow
    and #$E0
    sec
    sbc #$20
    sta ppu_addr_lo_shadow
@rts:
    rts

; Old font code -> new tile for the fixed set and the blank; bit 7 set:
; a kana (this part's own tile).
fix_map:
    .db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, BLANK, $01, $04, $05, $08, $09
    .dsb $60-$10, $FF
    .db $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $02, $03
    .db $0A, $0B, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $06, $07, $FF

; ======================================================================
; Kanji UI (TEXT_RENDERER.md "Kanji UI"): the map's menus in kanji.
; text_put_tile's calls in the window templates (text_input $CC02, bank
; 14 mapped), in draw_string_from_pointer ($D5C0, bank 12: item names
; from Y = 2, tactic and place names from Y = 0), in put_officer_name
; ($D4C0, bank 12: officer names from Y = $14) and in the boot menu's
; lines (bank 13 $9023, the string at $10 from Y = 1) come here in map mode
; (txr_tp in the fixed bank, txr_tpm in RAM).  A known kana word is put in
; its kanji form (txr_ui.inc, generated by kanji_build.py) and the rest of
; its bytes are skipped; any other byte is put as the game puts it.  The
; ROM's kana stay as they are: battle, the title and the scenes (no map
; mode) show them as before.
; Kanji take the line codes $A0-$BF: REG entries 16-31, a message page's
; are 0-15.  An entry is taken again only when no row buffer ($0300-$035F)
; and no saved row ($0180-$01DF) holds its codes.
; ======================================================================
UI_E0           = 16            ; the first REG entry of the map UI

; TXF_PUT: TXR_TA = the byte, TXR_TX = the row-buffer index, Y = the
; source index (kept).  X = the row-buffer index after the cell(s).
txr_put:
    sty TXR_TY
    lda TXR_SB
    cmp #12
    beq @b12
    cmp #13
    beq @b13
    cmp #14
    bne @plain
    lda TXR_SKIP                ; a template (window text_mode, text_col Y)
    bne @skip
    jsr ui_tpl
    bcc @str
    bcs @plain
@b12:
    cpy #0
    bne @b12n
    sty TXR_SKIP                ; Y = 0: a tactic or a place name starts
    ldx #UI_N0-1
    jsr ui_r0
    bcc @str
    bcs @plain
@b13:
    cpy #1                      ; the boot menu's line ($10) starts (Y = 1)
    bne @b12n
    lda #0
    sta TXR_SKIP
    ldx #UI_N1-1
    jsr ui_r1
    bcc @str
    bcs @plain
@b12n:
    lda TXR_SKIP
    bne @skip
    cpy #2
    beq @item
    cpy #$14                    ; Y = $14: an officer name starts
    bne @plain                  ; (put_officer_name, $D4C0; map mode only:
    bit TXR_ON                  ; the boot screens' fixed set has no names)
    bpl @plain
    jsr ui_rn
    bcc @str
    bcs @plain
@item:
    ldx #UI_N2-1                ; Y = 2: an item name starts
    jsr ui_r2
    bcs @plain
@str:
    ldx TXR_TX
    jmp put_str                 ; (Y back from TXR_TY there)
@skip:
    dec TXR_SKIP                ; a byte of a word put in kanji
    ldx TXR_TX
    ldy TXR_TY
    rts
@plain:
    lda TXR_TA
    ldx TXR_TX
    jsr TEXT_PUT_TILE
    ldy TXR_TY
    rts

; Template text_mode's word at text_col TXR_TY: C clear, PTR = its string,
; TXR_SKIP = the bytes to skip.  C set: none.
ui_tpl:
    ldx text_mode
    cpx #UI_NWIN
    bcs @no
    lda ui_win_lo,x
    sta PTR
    lda ui_win_hi,x
    sta PTR+1
    ora PTR
    beq @no
    ldy #0
@w:
    lda (PTR),y
    cmp #$FF
    beq @no
    cmp TXR_TY
    beq @f
    iny
    iny
    iny
    iny
    bne @w
@f:
    iny
    lda (PTR),y
    sta TXR_SKIP
    iny
    lda (PTR),y
    tax
    iny
    lda (PTR),y
    sta PTR+1
    stx PTR
    clc
    rts
@no:
    sec
    rts

; The record at ($F3) among the tactic and place names (ui_r0, X = count
; - 1) or the item names (ui_r2): C clear, PTR = its string, TXR_SKIP set.
ui_r0:
    lda ui_r0_lo,x
    cmp ppu_update_ptr_lo
    bne @n
    lda ui_r0_hi,x
    cmp ppu_update_ptr_hi
    beq @f
@n:
    dex
    bpl ui_r0
    sec
    rts
@f:
    lda ui_r0_sk,x
    sta TXR_SKIP
    lda ui_r0_sl,x
    sta PTR
    lda ui_r0_sh,x
    sta PTR+1
    clc
    rts
ui_r1:
    lda ui_r1_lo,x
    cmp PTR
    bne @n
    lda ui_r1_hi,x
    cmp PTR+1
    beq @f
@n:
    dex
    bpl ui_r1
    sec
    rts
@f:
    lda ui_r1_sk,x
    sta TXR_SKIP
    lda ui_r1_sl,x
    sta PTR
    lda ui_r1_sh,x
    sta PTR+1
    clc
    rts
ui_r2:
    lda ui_r2_lo,x
    cmp ppu_update_ptr_lo
    bne @n
    lda ui_r2_hi,x
    cmp ppu_update_ptr_hi
    beq @f
@n:
    dex
    bpl ui_r2
    sec
    rts
@f:
    lda ui_r2_sk,x
    sta TXR_SKIP
    lda ui_r2_sl,x
    sta PTR
    lda ui_r2_sh,x
    sta PTR+1
    clc
    rts

; The officer record at ($F3) among the names (ui_rn): C clear, PTR = its
; string, TXR_SKIP set.  C set: none.
ui_rn:
    ldx #UI_NN-1
@l:
    lda ui_rn_lo,x
    cmp ppu_update_ptr_lo
    bne @n
    lda ui_rn_hi,x
    cmp ppu_update_ptr_hi
    beq @f
@n:
    dex
    cpx #$FF
    bne @l
    sec
    rts
@f:
    lda ui_rn_sk,x
    sta TXR_SKIP
    lda ui_rn_sl,x
    sta PTR
    lda ui_rn_sh,x
    sta PTR+1
    clc
    rts

; TXF_NAME (the message engine, battle messages): TXR_TA = the name's code, as
; the message engine's dispatch index: 16-22 for $F4-$F7 (an officer: $F4
; text_target's, $F5 text_actor's, $F6 party_slot's else text_target's,
; $F7 the record of $05F0,[$72]; TXR_TA = the record after), 24 for $D565's
; tactic (text_command).  TXR_TX = the pool page's entry count byte (bits
; 0-4 the page's kanji, bits 5-6 its names: 3 reserved entries each).
; TXR_NM = the name's kanji, TXR_NM+1.. their codes' low bytes, TXR_NM+4..
; the high bytes; TXR_NE = the first reserved entry not taken
; (KANJI_UPLOADED: the names' kanji the page placed).  TXR_NM = 0: kana (no kanji name, or the reserved
; entries left cannot hold it); $FF: no officer (nothing is put).
txr_name:
    ldy #0
    sty TXR_NM
    lda TXR_TA
    cmp #24
    bne @off
    ldx text_command            ; a tactic (0-31)
    lda tn_n,x
    sta TXR_NM
    lda tn_lo0,x
    sta TXR_NM+1
    lda tn_hi0,x
    sta TXR_NM+4
    lda tn_lo1,x
    sta TXR_NM+2
    lda tn_hi1,x
    sta TXR_NM+5
    lda tn_lo2,x
    sta TXR_NM+3
    lda tn_hi2,x
    sta TXR_NM+6
    jmp @r
@off:
    cmp #22
    beq @f7
    cmp #18
    bne @f6
    ldx text_actor              ; $F5
    jmp @x
@f6:
    cmp #20
    bne @t
    ldx party_slot              ; $F6: party_slot's, else text_target's
    bpl @x
@t:
    ldx text_target             ; $F4 (none if negative)
    bpl @x
    lda #$FF
    sta TXR_NM
    rts
@f7:
    ldx $72                     ; $F7: the record of $05F0,[$72]
    lda $05F0,x
    jmp @rec
@x:
    lda $60A8,x                 ; the officer's record
@rec:
    sta TXR_TA
    tax
    cpx #UI_NRI
    bcs @r
    lda ui_ri,x                 ; the record's ui_rn index + 1
    beq @r
    tax
    lda ui_rn_sl-1,x
    sta PTR
    lda ui_rn_sh-1,x
    sta PTR+1
@l:
    lda (PTR),y                 ; $ED n ... $FF
    cmp #$ED
    bne @r
    iny
    lda (PTR),y
    iny
    tax
    lda nm_gc_hi,x
    pha
    lda nm_gc_lo,x
    ldx TXR_NM
    sta TXR_NM+1,x
    pla
    sta TXR_NM+4,x
    inc TXR_NM
    bne @l
@r:
    lda TXR_TX                  ; the reserved entries: n .. n + 3 * names
    and #$1F
    sta TXR_NE
    lda TXR_TX
    and #$60
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    sta TXR_I
    asl a
    adc TXR_I                   ; (C clear)
    adc TXR_NE
    sta TXR_J
    lda TXR_NE                  ; the first one not taken: after the names'
    clc                         ; kanji the page placed (KANJI_UPLOADED
    adc KANJI_UPLOADED          ; counts them, kn_put)
    sta TXR_NE
    cmp TXR_J
    bcs @none
    lda TXR_NE
    clc
    adc TXR_NM
    cmp TXR_J
    beq @ok
    bcc @ok
@none:
    lda #0
    sta TXR_NM
@ok:
    rts

; TXF_LABEL (bank 14: the gold window's 金 and 兵糧, the list's その他):
; TXR_TA = the label, TXR_TX = the row-buffer index.  The label from index
; + ui_lb_off; X = index + ui_lb_adv.  Y kept.
txr_label:
    sty TXR_TY
    ldy TXR_TA
    lda TXR_TX
    clc
    adc ui_lb_adv,y
    sta TXR_LA
    lda TXR_TX
    clc
    adc ui_lb_off,y
    tax
    lda ui_lb_lo,y
    sta PTR
    lda ui_lb_hi,y
    sta PTR+1
    jsr put_str
    ldx TXR_LA
    ldy TXR_TY
    rts

; The string at PTR into the row buffers from index X: a kana byte as
; text_put_tile puts it, $EC n UI kanji n (both rows, two cells), $ED n
; name kanji n (map mode only), $FF ends.  X = the index after it, Y =
; TXR_TY.  (Shallow: it runs inside the text task's small stack, from a
; message's item or officer name too.)
put_str:
    ldy #0
@l:
    lda (PTR),y
    cmp #$FF
    bne @c
    ldy TXR_TY
    rts
@c:
    iny
    cmp #$EC
    beq @k
    cmp #$ED
    beq @nk
    jsr TEXT_PUT_TILE           ; (Y kept)
    jmp @l
@nk:
    lda (PTR),y
    iny
    sty TXR_TA
    stx TXR_PX
    tay
    lda nm_gc_lo,y
    sta TXR_K
    lda nm_gc_hi,y
    sta TXR_K+1
    jmp @reg
@k:
    lda (PTR),y
    iny
    sty TXR_TA
    stx TXR_PX
    bit TXR_ON
    bpl @fix                    ; the boot screens: the fixed set's tiles
    tay
    lda ui_gc_lo,y
    sta TXR_K
    lda ui_gc_hi,y
    sta TXR_K+1
@reg:
    jsr ui_reg
    ldx TXR_PX
    sta $0300,x                 ; left half, both rows (the row's parity
    sta $0318,x                 ; picks the top or the bottom tile)
    ora #1
    sta $0301,x
    sta $0319,x
    inx
    inx
    ldy TXR_TA
    jmp @l
@fix:
    tay
    lda ui_fx,y                 ; t (t, t+1, t+2, t+3 = TL, BL, TR, BR)
    ldx TXR_PX
    sta $0300,x
    clc
    adc #1
    sta $0318,x
    adc #1
    sta $0301,x
    adc #1
    sta $0319,x
    inx
    inx
    ldy TXR_TA
    jmp @l

; A = the line code ($A0 + 2k) of glyph TXR_K in REG entry 16 + k: the
; entry that has it, else the next one (round robin) no row holds.
ui_reg:
    ldx #15
@f:
    lda REG_LO+UI_E0,x
    cmp TXR_K
    bne @n
    lda REG_HI+UI_E0,x
    cmp TXR_K+1
    beq @got
@n:
    dex
    bpl @f
    lda #0                      ; the entries the rows hold: TXR_I (0-7),
    sta TXR_I                   ; TXR_J (8-15)
    sta TXR_J
    ldy #$5F
@s:
    lda $0300,y
    sec
    sbc #$80+UI_E0*2
    cmp #$20
    bcs @s2
    lsr a
    tax
    jsr ui_mark
@s2:
    lda $0180,y
    sec
    sbc #$80+UI_E0*2
    cmp #$20
    bcs @s3
    lsr a
    tax
    jsr ui_mark
@s3:
    dey
    bpl @s
    ldy #16
@p:
    lda TXR_UR
    clc
    adc #1
    and #15
    sta TXR_UR
    tax
    cpx #8
    bcs @hi
    lda bitmask,x
    and TXR_I
    beq @take
    bne @pn
@hi:
    lda bitmask-8,x
    and TXR_J
    beq @take
@pn:
    dey
    bne @p
    ldx TXR_UR                  ; (all 16 held: the next one anyway)
@take:
    lda TXR_K
    sta REG_LO+UI_E0,x
    lda TXR_K+1
    sta REG_HI+UI_E0,x
@got:
    txa
    asl a
    ora #$80+UI_E0*2
    rts

; X = a UI entry 0-15 a row holds: its bit in TXR_I / TXR_J.  Y kept.
ui_mark:
    cpx #8
    bcs @hi
    lda bitmask,x
    ora TXR_I
    sta TXR_I
@r:
    rts
@hi:
    lda bitmask-8,x
    ora TXR_J
    sta TXR_J
    rts

    .include "../../decomp/build/kanji/txr_ui.inc"

