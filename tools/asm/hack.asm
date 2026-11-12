; ======================================================================
; Hack bank code (revision 11), identical in PRG banks 23 and 24.
;
; Assembled for $8000.  The first $C00 bytes are code; glyph data starts
; at $8C00 as 32 byte tables of 359 glyphs each (table b holds byte b of
; every glyph in tile order TL, TR, BL, BR, 8 rows each).
;
; Entry points:
;   $8000  call_hack dispatcher (KANJI_FN), main thread or NMI flush
;   $8003  NMI after the game's PPU work, normal frames (loc_EF08)
;   $8006  NMI epilogue, every frame (loc_EF31)
;
; NMI rules: no zero-page use, at most
; three nested calls, no PPU access in busy frames, every PPU address
; write followed by a full scroll/PPUCTRL restore before the frame starts.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"
.include "../../decomp/build/kanji/canvas_ram.inc"

GLYPH_TAB    = $8C00
GSTRIDE      = 359
LIGHT_QUEUE  = 8            ; max queued bytes for a light frame
; irq_arm0 forces the PPU address only after flushes of at most this many
; bytes.  Measured on five paths (map-canvas step 1), the arm starts by
; line 260.6 after flushes up to 87 bytes, by pre-render dot 24 after
; 88-103 (the force then ends by dot ~150: harmless, the PPU reloads v
; from t at dots 257 and 280-304), and in line 0 after 104 or more.
; (ARM_CLI_MIN: kanji.inc, shared with the canvas RAM code.)
; NMI scratch in the read-back buffer (free outside restore_tile; the main
; thread uses the buffer only while the NMI is in busy mode or disabled).
MS_TMP       = KANJI_BUF+15
QS_NOREPLAY  = KANJI_BUF+14
OFF_UNITS    = 16           ; work units per NMI with rendering off

.base $8000
.org $8000

    jmp fn_dispatch
    jmp nmi_ef08
    jmp nmi_ef31
    jmp pal_copy                ; $8009 HACK_PAL_COPY (load_text_graphics)
    jmp hack_init               ; $800C HACK_INIT (reset)

; ======================================================================
; NMI, normal frames, after the game's PPU work (still in vblank).
; ======================================================================
nmi_ef08:
    lda nmi_busy
    beq @live
    ; Busy frame: rendering is off and the main thread owns the PPU (its
    ; CHR writes would clock the IRQ counter: no IRQ until a light frame
    ; arms it).  Put the scene page back for the game's own CHR writes
    ; unless a hack routine on the main thread has the band page selected
    ; on purpose.
    sta MMC3_IRQ_OFF
    lda KANJI_MAINCHR
    bne @busy_q
    lda #1
    jsr wr_reg1
@busy_q:
    lda KANJI_NFLAGS
    and #<~(FLAG_PAGE2|FLAG_PPU_DIRTY)
    sta KANJI_NFLAGS
    lda vram_queue_read
    sta KANJI_QPOS
    rts
@live:
    ; Everything up to the scroll restore races the end of vblank: keep it
    ; short.  CPU-only bookkeeping (queue scan, DMA flag, upload marks,
    ; page select) runs after the frame's last PPU access.  A frame that
    ; flushed more than REPLAY_MAX bytes or stepped the CHR animation runs
    ; no unit and no replay: arm the IRQ first (map-canvas step 1: the arm
    ; must come before the pre-render line's clock).
    lda vram_queue_read
    sec
    sbc KANJI_QPOS
    sta KANJI_QBYTES            ; bytes the game flushed this frame
    cmp #REPLAY_MAX+1
    bcs @arm_now
    lda $39
    cmp KANJI_LAST39
    beq @arm_later
@arm_now:
    jsr irq_arm0_nf
@arm_later:
    jsr anim_check
    bcc @no_anim
    ; The game's NMI uploaded a CHR-animation step and ran long: no VRAM
    ; work this frame (not even a replay).
    jsr irq_arm0_nf
    lda #$FF
    sta KANJI_QBYTES
    jsr scene_page_now
    sec
    jsr queue_scan
    jmp @post_nounit
@no_anim:
    ldx KANJI_QBYTES            ; bytes the game flushed this frame
    ; Dormant (no band shown, no request): only track stale tiles.  The
    ; band page is brought up to date when the next message starts
    ; (REQ_SYNC), so no restore runs while nobody can see page 2.
    lda KANJI_BAND
    ora KANJI_REQ
    beq @tier                   ; A = 0: no units
    lda ppu_mask_shadow
    and #$18
    bne @rendering
    ; Rendering is off for the whole coming frame: VRAM is free for a
    ; large batch.  The band stays requested; the probe in work_unit drops
    ; it if the window is gone.
    lda #OFF_UNITS
    bne @tier
@rendering:
    ; Light frame: no CHR animation and at most LIGHT_QUEUE queued bytes,
    ; so the game's NMI work ended early enough for one unit (every unit
    ; is measured to end before the pre-render line from the latest such
    ; entry seen, scanline 254.8).
    lda #0
    cpx #LIGHT_QUEUE+1
    bcs @tier
    lda #1                      ; light frame, queued bytes: single units
    cpx #0
    bne @tier
    lda #2                      ; light frame, queue idle: double upload
@tier:
    sta KANJI_T1
    tay
    bne @units
    ; No unit this frame.  Scan the queue now: a CHR entry the game wrote
    ; while the band page was still selected (after a band frame) is
    ; replayed on page 1 when the frame's traffic was small.  After a large
    ; flush (a window drawn) the scan ends well into the next frame, whose
    ; top lines would show the band page: put the scene page back first
    ; (revision 16).  Small flushes keep the replay's timing.
    cpx #REPLAY_MAX+1           ; C clear: replay allowed
    bcc @scan
    jsr irq_arm0_nf             ; no PPU access follows; preserves X
    jsr scene_page_now          ; preserves X
    sec
@scan:
    jsr queue_scan
    lda KANJI_NFLAGS
    and #FLAG_PPU_DIRTY
    beq @post_nounit
    lda PPUSTATUS
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
    jmp @post_nounit
@units:
    lda ppu_ctrl_shadow
    and #$FB                    ; +1 increment for our transfers
    sta PPUCTRL
    lda PPUSTATUS
    lda KANJI_T1
    cmp #OFF_UNITS
    beq @bulk
    jsr light_unit
    jmp @restore
@bulk:
    lda #1
    jsr wr_reg1                 ; restores read page 1
@unit:
    jsr work_unit
    bcs @restore
    dec KANJI_T1
    bne @unit
@restore:
    lda PPUSTATUS
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
    jsr irq_arm0                ; after the frame's last PPU access
    sec                         ; no replay after the scroll restore
    jsr queue_scan
@post_nounit:
    jsr irq_arm0                ; (no-op when armed above)
    jsr nt_rescan               ; window-gone check, now past the deadline
    ; No unit ran: CHR register 1 still holds the scene page unless the
    ; last epilogue switched to the band page.
    lda KANJI_NFLAGS
    and #FLAG_PAGE2
    beq @page_kept
@post:
    ; Scene page for the coming frame.
    lda KANJI_MAINCHR
    bne @page_kept
    lda #1
    jsr wr_reg1
@page_kept:
    lda KANJI_NFLAGS
    and #<~(FLAG_HIT|FLAG_MISS|FLAG_PAGE2|FLAG_PPU_DIRTY)
    sta KANJI_NFLAGS
    lda KANJI_REQ
    cmp #REQ_MARK
    bne @placed
    jsr mark_upload
    lda #0
    sta KANJI_REQ
@placed:
    ; Next frame's restore pick (CPU only; was in the epilogue, which now
    ; skips the hack bank while no band is shown).  A pending REQ_SYNC is
    ; done when nothing is left to pick.
    lda KANJI_REQ
    cmp #REQ_SYNC
    beq @pick
    lda KANJI_BAND
    beq @picked
@pick:
    jsr pick_restore
    lda KANJI_REQ
    cmp #REQ_SYNC
    bne @picked
    lda KANJI_PICK
    cmp #$FF
    bne @picked
    lda #0
    sta KANJI_REQ
@picked:
    rts

; The game's NMI uploads a CHR-animation step in flush_palette: 4 tiles at
; ($3C:$3B) - $40, then $39 += $40.  The fixed-bank block hook only selects
; the scene page there; mark the step's tiles stale here.  Carry set when
; $39 moved since the last check.  CPU only.
anim_check:
    lda $39
    cmp KANJI_LAST39
    beq @none
    sta KANJI_LAST39
    lda $3B
    sec
    sbc #$40
    and #$F0
    sta KANJI_T2
    lda $3C
    sbc #0
    cmp #$10
    bcc @page0
    cmp #$20
    bcs @seen
    sta KANJI_T1
    bit KANJI_WIN_COL           ; V = WINCOL_POOL_OK
    bvc @np
    ldy #64
    jsr pool_guard
@np:
    ldy #64
    jsr mark_range
    sec
    rts
@page0:
@seen:
    sec
    rts
@none:
    clc
    rts

; Scene page for the coming frame when the last epilogue selected the band
; page (FLAG_PAGE2 stays set for queue_scan's replay test and @post).
; Preserves X and Y.
scene_page_now:
    lda KANJI_NFLAGS
    and #FLAG_PAGE2
    beq @kept
    lda KANJI_MAINCHR
    bne @kept
    lda #1
    jmp wr_reg1
@kept:
    rts

; ----------------------------------------------------------------------
; Scan the VRAM queue entries flushed since the last scan and mark the
; CHR tiles they wrote as stale on the band page.  C clear on entry: a
; page-1 CHR entry of at most 16 bytes for tiles $00-$7F that the game
; flushed while the band page was still selected (FLAG_PAGE2) is written
; again on page 1 from the queue ring (sets FLAG_PPU_DIRTY; the caller
; restores scroll).  Tiles $80-$FF (R1) always show the scene page.
; ----------------------------------------------------------------------
queue_scan:
    lda #0
    rol a
    sta QS_NOREPLAY             ; 1 = no replay
    ldx KANJI_QPOS
    stx NT_Q0                   ; this frame's first entry (nt_rescan)
    lda vram_queue_read
    sec
    sbc KANJI_QPOS
    beq @done
    cmp #193
    bcs @done                   ; too much traffic to trust the ring
@entry:
    cpx vram_queue_read
    beq @done
    lda $0400,x
    beq @done
    sta KANJI_T1                ; address high
    inx
    lda $0400,x
    sta KANJI_T2                ; address low
    inx
    lda $0400,x
    and #$7F
    tay                         ; length
    inx
    lda KANJI_T1
    cmp #$20
    bcs @nt
    cmp #$10
    bcc @page0
    lda QS_NOREPLAY
    bne @mark
    lda KANJI_NFLAGS
    and #FLAG_PAGE2
    beq @mark
    lda KANJI_T1
    cmp #$18
    bcs @mark                   ; tiles $80-$FF: R1, always the scene page
    dex
    lda $0400,x                 ; length byte: +32 mode or > 16 bytes?
    inx
    cmp #17
    bcs @mark
    cpy #0
    beq @mark
    jsr replay_entry
@mark:
    bit KANJI_WIN_COL           ; V = WINCOL_POOL_OK
    bvc @nopool
    jsr pool_guard_q
@nopool:
    jsr mark_range
    jmp @skip
@page0:
@skip:
    sty KANJI_T0
    txa
    clc
    adc KANJI_T0
    tax
    jmp @entry
@nt:
    lda QS_NOREPLAY
    beq @skip                   ; before the scroll restore: nt_rescan
    lda KANJI_T1
    cmp #$30
    bcs @skip
    jsr nt_check
    jmp @skip
@done:
    lda vram_queue_read
    sta KANJI_QPOS
    rts

; Write queue entry data $0400,X (Y bytes, 1-16) to page-1 address
; KANJI_T1:KANJI_T2.  Preserves X, Y, KANJI_T1, KANJI_T2.
replay_entry:
    lda #1
    jsr wr_reg1
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL
    lda PPUSTATUS
    lda KANJI_T1
    sta PPUADDR
    lda KANJI_T2
    sta PPUADDR
    txa
    pha
    tya
    pha
@b:
    lda $0400,x
    sta PPUDATA
    inx
    dey
    bne @b
    pla
    tay
    pla
    tax
    lda KANJI_NFLAGS
    ora #FLAG_PPU_DIRTY
    sta KANJI_NFLAGS
    rts

; Mark the tiles touched by a page-1 write: KANJI_T1 = address high
; ($10-$1F), KANJI_T2 = address low, Y = length (0 = 128).  Preserves X/Y.
mark_range:
    txa
    pha
    tya
    bne @len
    lda #128
@len:
    clc
    adc #15
    sta KANJI_T0
    lda KANJI_T2
    and #$0F
    clc
    adc KANJI_T0
    lsr a
    lsr a
    lsr a
    lsr a
    sta KANJI_T0                ; tile count
    lda KANJI_T1
    asl a
    asl a
    asl a
    asl a
    sta KANJI_T1
    lda KANJI_T2
    lsr a
    lsr a
    lsr a
    lsr a
    ora KANJI_T1                ; first tile
@tile:
    sta KANJI_T1                ; (no stack: the NMI chain runs on the
    jsr mark_stale              ;  text task's small stack)
    lda KANJI_T1
    clc
    adc #1
    dec KANJI_T0
    bne @tile
    pla
    tax
    rts

; A = tile 0-255: mark it stale on the band page.  Clobbers A, X and
; KANJI_BUF+15 (scratch outside restore_tile), preserves Y and KANJI_T0/T1.
; Upper tiles are never stale (revision 21): the band page switches only
; BG tiles $00-$7F, $80-$FF always show the scene page.  The upper-group
; restore paths stay but never find a group.
mark_stale:
    sta MS_TMP
    cmp #$80
    bcs @upper
    and #7
    tax
    lda bitmask,x
    sta KANJI_T2
    lda MS_TMP
    lsr a
    lsr a
    lsr a
    tax
    lda KANJI_T2
    ora KANJI_STALE,x
    sta KANJI_STALE,x
    rts
@hi:
    and #$7F
    sta MS_TMP
    lsr a
    lsr a
    and #7                      ; group bit within the byte
    tax
    lda bitmask,x
    sta KANJI_T2
    lda MS_TMP
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    tax                         ; byte 0-3
    lda KANJI_T2
    ora KANJI_STALE_HI,x
    sta KANJI_STALE_HI,x
    lda KANJI_NFLAGS            ; restart the group cursor
    and #<~FLAG_HI_SUB
    sta KANJI_NFLAGS
@upper:
    rts

; ----------------------------------------------------------------------
; Window probe: while the band is on, the window's top-left corner tile
; must still be in the nametable.  If it is gone, drop the band.  The
; active set stays until the overlay releases it (the overlay owns it).  Runs inside the VRAM budget; leaves the PPU address
; dirty (the caller restores scroll).
; ----------------------------------------------------------------------
probe_window:
    lda KANJI_BAND
    beq @rts
    lda KANJI_WIN_ROW
    lsr a
    lsr a
    lsr a
    ora #$20
    tay
    lda KANJI_WIN_COL
    and #$20
    beq @nt0
    tya
    ora #$04
    tay
@nt0:
    lda KANJI_WIN_ROW
    asl a
    asl a
    asl a
    asl a
    asl a
    sta KANJI_T0
    lda KANJI_WIN_COL
    and #$1F
    ora KANJI_T0
    sty PPUADDR
    sta PPUADDR
    lda PPUDATA
    lda PPUDATA
    cmp #WINDOW_CORNER
    beq @rts
    lda #0
    sta KANJI_BAND
@rts:
    rts

release_a:
    lda #0
    ldx #15
@l:
    sta KANJI_A,x
    dex
    bpl @l
    rts

; ----------------------------------------------------------------------
; One unit of VRAM work, bulk (rendering off) or main-thread service
; (CHR page 1 selected, PPUCTRL +1 increment).  Carry set when there was
; nothing to do.
; ----------------------------------------------------------------------
work_unit:
    lda KANJI_REQ
    beq @no_req
    cmp #REQ_RELEASE
    bne @not_release
    jsr release_a
    jmp @req_free
@not_release:
    cmp #REQ_MARK
    bne @not_mark
    jsr mark_upload
@req_free:
    lda #0
    sta KANJI_REQ
    jmp @no_req                 ; CPU only, keep the unit
@not_mark:
    cmp #REQ_SYNC
    bne @not_sync
    jsr restore_next            ; C set: nothing left to restore
    bcc @synced
    lda #0
    sta KANJI_REQ
@synced:
    rts
@not_sync:
    cmp #REQ_RESTORE
    bne @upload
    lda KANJI_TILES             ; REQ_RESTORE: tile in KANJI_TILES
    jsr restore_if_stale
    lda #0
    sta KANJI_REQ
    clc
    rts
@upload:
    jmp upload_unit
@no_req:
    jsr probe_window
    jmp restore_next

; One unit of vblank work in a light frame, with no searching.  Order:
; a pending request, the window probe (every 8th frame), the restore
; picked in advance by the epilogue (KANJI_PICK).
light_unit:
    lda KANJI_REQ
    beq @probe
    cmp #REQ_SYNC
    beq @pick
    cmp #REQ_RELEASE
    beq @release
    cmp #REQ_MARK
    beq @probe                  ; marked after the scroll restore
    cmp #REQ_RESTORE
    bne @upload
    lda #1
    jsr wr_reg1                 ; read page 1
    lda KANJI_TILES
    jsr restore_if_stale
    lda #0
    sta KANJI_REQ
    rts
@upload:
    jmp upload_unit_nmi
@release:
    jsr release_a
    lda #0
    sta KANJI_REQ
@probe:
    lda KANJI_BAND
    beq @rts                    ; dormant: page 2 is synced at message start
    lda frame_counter
    and #7
    bne @pick
    jmp probe_window
@pick:
    lda KANJI_PICK
    ldx #$FF
    stx KANJI_PICK
    cmp #$FF
    beq @rts
    pha
    lda #1
    jsr wr_reg1                 ; read page 1
    pla
    cmp #$80
    bcs @pick_hi
    jmp restore_if_stale
@pick_hi:
    ; upper tile: its group must still be stale
    sta KANJI_T0
    and #$7F
    lsr a
    lsr a
    pha
    and #7
    tay
    lda bitmask,y
    sta KANJI_T2
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda KANJI_T2
    and KANJI_STALE_HI,x
    beq @rts
    lda KANJI_T0
    jsr restore_tile
    jmp advance_hi
@rts:
    rts

; After restoring an upper tile of the lowest stale group: advance the
; group cursor; when the group is complete, clear its bit.
advance_hi:                     ; KANJI_T0 = the upper tile just restored
    lda KANJI_T0
    and #$7F
    lsr a
    lsr a
    sta KANJI_T2                ; group 0-31
    lda KANJI_NFLAGS
    clc
    adc #$10
    and #FLAG_HI_SUB
    beq @done
    sta KANJI_T0
    lda KANJI_NFLAGS
    and #<~FLAG_HI_SUB
    ora KANJI_T0
    sta KANJI_NFLAGS
    rts
@done:
    lda KANJI_NFLAGS
    and #<~FLAG_HI_SUB
    sta KANJI_NFLAGS
    lda KANJI_T2
    and #7
    tay
    lda bitmask,y
    eor #$FF
    sta KANJI_T0
    lda KANJI_T2
    lsr a
    lsr a
    lsr a
    tax
    lda KANJI_T0
    and KANJI_STALE_HI,x
    sta KANJI_STALE_HI,x
    rts

; One tile (two when the frame has room) of the glyph KANJI_CODE to the
; band page: REQ_UPLOAD is tile 0, REQ_UP1..REQ_UP3 tiles 1-3; after tile
; 3 the request becomes REQ_MARK (bookkeeping, done after the scroll
; restore).  KANJI_T1 = 1: one tile only.
upload_unit:
    lda KANJI_TILES
    bpl @band_u
    lda KANJI_CODE_HI
    cmp #POOL_CHECK_CODE
    bne @pool_u
    jmp pool_check_main
@pool_u:
    jsr upload_slot
    lda #1                      ; pool tiles live on the scene page
    bne @page
@band_u:
    jsr upload_slot
    lda #2
@page:
    jsr set_page
    ldy KANJI_T0
    jmp upload_go
; The live NMI's light unit (KANJI_MAINCHR is clear outside busy mode):
; the band page goes straight to CHR register 1, ~20 cycles sooner than
; set_page, which pays for the sprite-0 check in light_unit.
upload_unit_nmi:
    lda #2
    ldx KANJI_TILES
    bpl @band                   ; band tiles are below $80
    lda KANJI_CODE_HI
    cmp #POOL_CHECK_CODE
    bne @pool
    jmp pool_check_nmi
@pool:
    lda #1                      ; pool tiles: the scene page
@band:
    jsr wr_reg1                 ; A only
    ldy #0
    lda KANJI_REQ
    cmp #REQ_UPLOAD
    beq @k
    sec
    sbc #REQ_UP1-1
    tay
@k:
    sty KANJI_T0
upload_go:
    jsr glyph_upload
    ; Queue-idle light frames (T1 = 2), bulk frames and the main-thread
    ; service have room for the second tile of the pair as well; frames
    ; with queued bytes (T1 = 1) take one tile.
    lda KANJI_T1
    cmp #1
    beq @one
    lda KANJI_T0
    and #1
    bne @one
    inc KANJI_T0
    ldy KANJI_T0
    jsr glyph_upload
@one:
    lda #1
    jsr set_page
    ldy KANJI_T0
    iny
    cpy #4
    bcs @last
    tya
    clc
    adc #REQ_UP1-1
    sta KANJI_REQ
    clc
    rts
@last:
    lda #REQ_MARK
    sta KANJI_REQ
    clc
    rts

; Y = KANJI_T0 = glyph slot 0-3 of the pending upload request.
upload_slot:
    ldy #0
    lda KANJI_REQ
    cmp #REQ_UPLOAD
    beq @k
    sec
    sbc #REQ_UP1-1
    tay
@k:
    sty KANJI_T0
    rts

; Mark the four uploaded tiles active and stale (page 2 differs there).
mark_upload:
    ldy #3
@mark:
    lda KANJI_TILES,y
    bmi @next                   ; pool tile: scene page, not a band slot
    and #$7F
    pha
    lsr a
    lsr a
    lsr a
    tax
    pla
    and #7
    sty KANJI_T2
    tay
    lda bitmask,y
    ldy KANJI_T2
    pha
    ora KANJI_A,x
    sta KANJI_A,x
    pla
    ora KANJI_STALE,x
    sta KANJI_STALE,x
@next:
    dey
    bpl @mark
    rts

; ----------------------------------------------------------------------
; Restore one stale tile that is not active (lower first, then upper
; groups one tile at a time).  Carry set when nothing is stale.
; ----------------------------------------------------------------------
restore_next:
    lda text_graphics_index     ; step B: the battle and the info screen
    cmp #POOL_SET               ; keep no band page (a sync is done at once)
    beq @none
    ldx #0
@lower:
    lda KANJI_A,x
    eor #$FF
    and KANJI_STALE,x
    bne @found
    inx
    cpx #16
    bne @lower
    ldx #0
@upper:
    lda KANJI_STALE_HI,x
    bne @found_hi
    inx
    cpx #4
    bne @upper
@none:
    sec
    rts
@found:
    ldy #0
@bit:
    asl a
    bcs @got
    iny
    bne @bit
@got:
    sty KANJI_T0
    txa
    asl a
    asl a
    asl a
    ora KANJI_T0
    jsr restore_tile
    clc
    rts
@found_hi:
    ldy #0
@bit_hi:
    asl a
    bcs @got_hi
    iny
    bne @bit_hi
@got_hi:
    txa
    asl a
    asl a
    asl a
    sta KANJI_T0
    tya
    ora KANJI_T0                ; group 0-31
    pha
    asl a
    asl a
    ora #$80
    sta KANJI_T0                ; group's first tile
    lda KANJI_NFLAGS
    and #FLAG_HI_SUB
    lsr a
    lsr a
    lsr a
    lsr a
    ora KANJI_T0
    jsr restore_tile
    lda KANJI_NFLAGS
    clc
    adc #$10
    and #FLAG_HI_SUB
    beq @group_done
    sta KANJI_T0
    lda KANJI_NFLAGS
    and #<~FLAG_HI_SUB
    ora KANJI_T0
    sta KANJI_NFLAGS
    pla
    clc
    rts
@group_done:
    lda KANJI_NFLAGS
    and #<~FLAG_HI_SUB
    sta KANJI_NFLAGS
    pla
    pha
    and #7
    tay
    lda bitmask,y
    eor #$FF
    sta KANJI_T0
    pla
    lsr a
    lsr a
    lsr a
    tax
    lda KANJI_T0
    and KANJI_STALE_HI,x
    sta KANJI_STALE_HI,x
    clc
    rts

; A = lower tile: restore it if it is stale and not active.
restore_if_stale:
    and #$7F
    pha
    lsr a
    lsr a
    lsr a
    tax
    pla
    pha
    and #7
    tay
    lda bitmask,y
    and KANJI_STALE,x
    beq @no
    and KANJI_A,x
    bne @no
    pla
    jmp restore_tile
@no:
    pla
    rts

; ----------------------------------------------------------------------
; Copy CHR page-1 tile A to page 2 and clear its stale bit (lower tiles).
; Page 1 selected on entry and exit; PPUCTRL +1 increment.
; ----------------------------------------------------------------------
restore_tile:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    tay                         ; address high
    pla
    pha
    asl a
    asl a
    asl a
    asl a
    tax                         ; address low
    sty PPUADDR
    stx PPUADDR
    lda PPUDATA
    lda PPUDATA
    sta KANJI_BUF+0
    lda PPUDATA
    sta KANJI_BUF+1
    lda PPUDATA
    sta KANJI_BUF+2
    lda PPUDATA
    sta KANJI_BUF+3
    lda PPUDATA
    sta KANJI_BUF+4
    lda PPUDATA
    sta KANJI_BUF+5
    lda PPUDATA
    sta KANJI_BUF+6
    lda PPUDATA
    sta KANJI_BUF+7
    lda PPUDATA
    sta KANJI_BUF+8
    lda PPUDATA
    sta KANJI_BUF+9
    lda PPUDATA
    sta KANJI_BUF+10
    lda PPUDATA
    sta KANJI_BUF+11
    lda PPUDATA
    sta KANJI_BUF+12
    lda PPUDATA
    sta KANJI_BUF+13
    lda PPUDATA
    sta KANJI_BUF+14
    lda PPUDATA
    sta KANJI_BUF+15
    lda #2
    jsr set_page
    sty PPUADDR
    stx PPUADDR
    lda KANJI_BUF+0
    sta PPUDATA
    lda KANJI_BUF+1
    sta PPUDATA
    lda KANJI_BUF+2
    sta PPUDATA
    lda KANJI_BUF+3
    sta PPUDATA
    lda KANJI_BUF+4
    sta PPUDATA
    lda KANJI_BUF+5
    sta PPUDATA
    lda KANJI_BUF+6
    sta PPUDATA
    lda KANJI_BUF+7
    sta PPUDATA
    lda KANJI_BUF+8
    sta PPUDATA
    lda KANJI_BUF+9
    sta PPUDATA
    lda KANJI_BUF+10
    sta PPUDATA
    lda KANJI_BUF+11
    sta PPUDATA
    lda KANJI_BUF+12
    sta PPUDATA
    lda KANJI_BUF+13
    sta PPUDATA
    lda KANJI_BUF+14
    sta PPUDATA
    lda KANJI_BUF+15
    sta PPUDATA
    lda #1
    jsr set_page
    pla
    cmp #$80
    bcs @rts
    pha
    lsr a
    lsr a
    lsr a
    tax
    pla
    and #7
    tay
    lda bitmask,y
    eor #$FF
    and KANJI_STALE,x
    sta KANJI_STALE,x
@rts:
    rts

; ----------------------------------------------------------------------
; Glyph upload, one tile (Y = 0-3).  KANJI_CODE_LO/HI = glyph 0-717,
; KANJI_TILES = the four destination tiles, CHR page 2 selected.  Maps bank 24 for glyphs
; 359-717 (the code is identical there).
; ----------------------------------------------------------------------
glyph_upload:
    sty KANJI_T2                ; tile 0-3; KANJI_T1 is the NMI unit count
    ; Code = bank * 512 + local (local 0-358): high byte bit 0 selects the
    ; low/high table half, the rest the glyph bank (23 + n).
    lda KANJI_CODE_HI
    lsr a
    bcs @hi_half
    beq @lo_mapped              ; bank 23 is already mapped
    adc #KANJI_HACK_BANK        ; carry clear
    jsr map_bank
@lo_mapped:
    ldx KANJI_CODE_LO
    jmp @lowx
@hi_half:
    beq @hi_mapped
    clc
    adc #KANJI_HACK_BANK
    jsr map_bank
@hi_mapped:
    ldx KANJI_CODE_LO
    jmp @high
@lowx:
    lda KANJI_T2
    beq upload_low_0
    cmp #2
    beq @low_2
    bcs @low_3
    jmp upload_low_1
@low_2:
    jmp upload_low_2
@low_3:
    jmp upload_low_3
@high:
    lda KANJI_T2
    beq @high_0
    cmp #2
    beq @high_2
    bcs @high_3
    jmp upload_high_1
@high_0:
    jmp upload_high_0
@high_2:
    jmp upload_high_2
@high_3:
    jmp upload_high_3

; Set the PPU address for tile KANJI_TILES+Y (lower tile).
tile_addr:
    lda KANJI_TILES,y
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta PPUADDR
    lda KANJI_TILES,y
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
    rts

.macro UPLOAD_TILE tab, k
    ldy #k
    jsr tile_addr
    lda tab+(k*8+0)*GSTRIDE,x
    sta PPUDATA
    lda tab+(k*8+1)*GSTRIDE,x
    sta PPUDATA
    lda tab+(k*8+2)*GSTRIDE,x
    sta PPUDATA
    lda tab+(k*8+3)*GSTRIDE,x
    sta PPUDATA
    lda tab+(k*8+4)*GSTRIDE,x
    sta PPUDATA
    lda tab+(k*8+5)*GSTRIDE,x
    sta PPUDATA
    lda tab+(k*8+6)*GSTRIDE,x
    sta PPUDATA
    lda tab+(k*8+7)*GSTRIDE,x
    sta PPUDATA
    lda #0
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
.endm

upload_low_0:
    UPLOAD_TILE GLYPH_TAB, 0
    rts
upload_low_1:
    UPLOAD_TILE GLYPH_TAB, 1
    rts
upload_low_2:
    UPLOAD_TILE GLYPH_TAB, 2
    rts
upload_low_3:
    UPLOAD_TILE GLYPH_TAB, 3
    rts
upload_high_0:
    UPLOAD_TILE GLYPH_TAB+256, 0
    rts
upload_high_1:
    UPLOAD_TILE GLYPH_TAB+256, 1
    rts
upload_high_2:
    UPLOAD_TILE GLYPH_TAB+256, 2
    rts
upload_high_3:
    UPLOAD_TILE GLYPH_TAB+256, 3
    rts

; ======================================================================
; NMI epilogue, split frames only (ef31_gate): the scene page, no band, no
; IRQ (the band switch is the scanline IRQ's since revision 21b).
; ======================================================================
nmi_ef31:
    lda nmi_busy
    bne @rts
    lda nmi_mode
    beq @rts
    sta MMC3_IRQ_OFF
    lda KANJI_MAINCHR
    bne @rts
    lda #1
    jsr wr_reg1
    lda #0
    sta KANJI_BAND
    lda KANJI_NFLAGS
    and #<~FLAG_PAGE2
    sta KANJI_NFLAGS
    jmp anim_check
@rts:
    rts

; ----------------------------------------------------------------------
; Scanline IRQ arming (map-canvas step 1), right after the frame's last
; PPU access; once per NMI (FLAG_ARMED).  T = the window's top border row's
; first scanline in the frame about to be drawn (WIN_ROW * 8 - scroll_y,
; modulo 240; 16-208).  The PPU address is set to $1000 first, so A12 is
; high when vblank ends and the pre-render line's first BG fetch is no
; clock; then the counter reloads with 0 at the pre-render line's clock
; (dot ~325) and IRQ stage 0 comes there.  Its handler runs in line 0,
; after the frame's last irregular clock, and reloads the counter for
; line T: stage 1 comes at the clock of line T and switches in line T + 1.
; IRQs are enabled here, so stage 0 also preempts a long NMI tail.
; Preserves X and Y.
; ----------------------------------------------------------------------
irq_arm0_nf:
    ; Before any PPU access of ours: the game's NMI already left v = $1000
    ; (nmi_force, map-canvas step 3), in vblank however long its flush ran.
    lda #$80
    bne arm0_go
irq_arm0:
    lda #$00
arm0_go:
    sta CV_NOFORCE
    lda KANJI_NFLAGS
    bpl arm0_once
    rts                         ; armed once already in this NMI
arm0_once:
    ora #FLAG_ARMED
    sta KANJI_NFLAGS
    lda ppu_mask_shadow
    and #$18
    beq arm0_off                    ; rendering off: nothing to switch
    ; (Map mode never gets here: ef08_gate skips the hack's NMI and cv_nmi
    ; arms the text renderer's parts.)
    lda KANJI_BAND
    beq arm0_off
    bit CV_NOFORCE
    bmi arm0_noforce
arm0_force:
    lda KANJI_QBYTES
    cmp #ARM_FORCE_MAX+1
    bcs arm0_noforce                ; the game's NMI ran late: no PPU access
arm_force:                      ; (label for vblank_deadline.lua)
    lda PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #$00
    sta PPUADDR                 ; v = $1000: A12 high until the BG fetches
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
arm_force_end:
arm0_noforce:
    lda #0
    sta MMC3_IRQ_LATCH
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_OFF            ; acknowledge anything pending
    sta MMC3_IRQ_ON
    lda #1
    sta KANJI_IRQ_ST
    ; T for stage 0 (it runs only after the cli below).
    lda KANJI_WIN_ROW
    asl a
    asl a
    asl a
    sec
    sbc scroll_y
    bcs arm0_row
    sbc #15                     ; borrow: wrap modulo 240 (carry clear: -16)
arm0_row:
    cmp #16
    bcc arm0_cancel
    cmp #209
    bcs arm0_cancel
    sta KANJI_IRQ_N
    cmp #ARM_CLI_MIN
    bcc arm0_rts                ; switch near the top: stage 0 waits for the
    cli                         ; NMI's end (its tail could still be running
arm0_rts:                       ; when stage 1 writes $8000)
    rts
arm0_cancel:
    lda #0
    sta KANJI_IRQ_ST
arm0_off:
    sta MMC3_IRQ_OFF
    rts

; ----------------------------------------------------------------------
; Reset (map-canvas step 3), called by the fixed bank's reset with this
; bank at R6/R7 and NMIs off: clear the hack state ($0103-$017F) and the
; canvas state ($0780-$07FF), copy the canvas RAM code from bank CV_BANK
; ($A000, mapped at R7 for the copy) to CV_RAM.
; ----------------------------------------------------------------------
hack_init:
    lda #0
    ldx #$7C
@c1:
    sta KANJI_MAINCHR,x
    dex
    bpl @c1
    ldx #$7F
@c2:
    sta CV_REDIR,x
    dex
    bpl @c2
    lda #MMC3_R7
    sta MMC3_SELECT
    lda #CV_BANK*2+1
    sta MMC3_DATA
    ldx #0                      ; (unrolled: the reset must not cost the
@cp:                            ; game a frame)
    lda $A000,x
    sta CV_RAM,x
    lda $A100,x
    sta CV_RAM+$100,x
    lda $A200,x
    sta CV_RAM+$200,x
    lda $A300,x
    sta CV_RAM+$300,x
    lda $A400,x
    sta CV_RAM+$400,x
    lda $A500,x
    sta CV_RAM+$500,x
    lda $A600,x
    sta CV_RAM+$600,x
    inx
    bne @cp
    lda #KANJI_HACK_BANK*2+1
    sta MMC3_DATA
    rts

; ======================================================================
; call_hack dispatcher.
; ======================================================================
fn_dispatch:
    lda KANJI_FN
    beq fn_block_pre
    cmp #FN_BLOCK_POST
    bne @svc
    jmp fn_block_post
@svc:
    jmp fn_service

; A = CHR page (1 scene, 2 band) for BG tiles $00-$7F.  Main-thread hack
; code runs with KANJI_MAINCHR set and uses the bank-select shadow; the
; NMI writes directly.
set_page:
    pha
    lda KANJI_MAINCHR
    bne @main
    pla
    jmp wr_reg1
@main:
    pla
    jmp wr_reg1_main


; NMI: R0 = page A's lower half (4 * A).  $8000 is left on R0; the
; restore_bank_after_nmi that ends every NMI gives it back.  Preserves X
; and Y.
wr_reg1:
    cmp #2                      ; page 1: R0 = CHR_SCENE_LO; page 2 (the
    lda #CHR_SCENE_LO           ; band): CHR_BAND_LO ($3800 since the map
    bcc @r                      ; renderer)
    lda #CHR_BAND_LO
@r:
    pha
    lda #MMC3_R0
    sta MMC3_SELECT
    pla
    sta MMC3_DATA
    rts

; Main thread: the same, under the bank-select shadow (an NMI between the
; select and the data write restores $8000 = MMC3_SEL = R0).  Preserves X
; and Y.
wr_reg1_main:
    cmp #2
    lda #CHR_SCENE_LO
    bcc @r
    lda #CHR_BAND_LO
@r:
    pha
    lda #MMC3_R0
    sta MMC3_SEL
    sta MMC3_SELECT
    pla
    sta MMC3_DATA
    rts

; A = glyph bank 24-30, using the context's protocol.  The NMI writes R6
; and R7 directly (the hack code is the same in every hack bank; the
; NMI's last restore_bank_after_nmi gives $8000 back).  Clobbers X and Y
; in the NMI (glyph_upload reloads them).
map_bank:
    pha
    lda KANJI_MAINCHR
    bne @main_pla
    pla
    asl a
    tax
    lda #MMC3_R6
    sta MMC3_SELECT
    stx MMC3_DATA
    inx
    lda #MMC3_R7
    sta MMC3_SELECT
    stx MMC3_DATA
    rts
@main_pla:
    pla
    jmp SET_BANK_LOCK

; ----------------------------------------------------------------------
; Block writer, before the original body (main thread only: the fixed-bank
; hook handles the NMI's block write itself).  $02 = tile count, $03 =
; address high, $04 = address low | mode.  For page-1 writes select CHR
; page 1 and save the range; for page-0 writes over tile $FF invalidate the
; sprite.
; ----------------------------------------------------------------------
fn_block_pre:
    lda #0
    sta KANJI_M0
    lda $03
    cmp #$20
    bcs @rts                    ; nametable / palette
    cmp #$10
    bcc @page0
    lda $04
    and #$02                    ; read mode: nothing changes
    bne @rts
    lda $03
    sta KANJI_M0
    lda $04
    and #$F0
    sta KANJI_M1
    lda $02
    sta KANJI_M2
    lda #1
    jmp wr_reg1_main
@page0:
@rts:
    rts

; ----------------------------------------------------------------------
; Block writer, after the original body (main thread, rendering off): copy
; every written tile to the band page now.
; ----------------------------------------------------------------------
fn_block_post:
    lda KANJI_M0
    beq @rts
    lda #1
    sta KANJI_MAINCHR
    lda PPUSTATUS
    ; first tile
    lda KANJI_M0
    asl a
    asl a
    asl a
    asl a
    sta KANJI_M0
    lda KANJI_M1
    lsr a
    lsr a
    lsr a
    lsr a
    ora KANJI_M0
    sta KANJI_M1                ; KANJI_M1 = current tile
@tile:
    lda KANJI_M1
    cmp #$80
    bcs @upper                  ; upper tiles: scene page only (R1)
    ldx UI_NOMIR                ; step B: the battle start's and the info
    bne @stale                  ; screen's uploads: no band page to keep
    lsr a
    lsr a
    lsr a
    tax
    lda KANJI_M1
    and #7
    tay
    lda bitmask,y
    and KANJI_A,x
    beq @copy
    ; active kanji tile: keep the glyph, leave it stale for later
@stale:
    lda KANJI_M1
    jsr mark_stale
    jmp @next
@copy:
    jsr restore_tile_main       ; page 1 -> page 2, clears a lower stale bit
@upper:
    lda KANJI_M1
    cmp #POOL_FIRST
    bcc @next
    cmp #POOL_LAST+1
    bcs @next
    jsr pool_off                ; the game wrote a pool tile
@next:
    inc KANJI_M1
    dec KANJI_M2
    bne @tile
    lda #0
    sta KANJI_M0
    sta KANJI_MAINCHR
@rts:
    rts

; ----------------------------------------------------------------------
; Main thread with rendering off (busy mode or NMI disabled): serve the
; overlay's request directly.  The PPU is free; the busy-mode NMI leaves
; CHR register 1 alone while KANJI_MAINCHR is set.
; ----------------------------------------------------------------------
fn_service:
    lda #1
    sta KANJI_MAINCHR
    jsr wr_reg1_main            ; restores read page 1 (a band frame may
                                ; have left page 2 selected)
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL
    lda PPUSTATUS
@more:
    jsr work_unit
    lda KANJI_REQ
    bne @more
    lda PPUSTATUS
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda #0
    sta KANJI_MAINCHR
    rts

bitmask:
    .db $80, $40, $20, $10, $08, $04, $02, $01

; The glyph tables start here; kanji_build.py pads the code to 3 KiB.
.org $8C00
; ======================================================================
; Second code segment, after the glyph tables ($B8E0) and before the
; relocated palette tables ($BF00); kanji_build.py copies it into every
; hack bank like the first.
; ======================================================================
.org $B900

; ----------------------------------------------------------------------
; Map text renderer, NMI (txr.asm nmi_up; TEXT_RENDERER.md "Upload
; speed", B + D and round 2): the kanji records of TXR_UQ from X on (R0 |
; $80, PPU address hi, lo of tile t, the glyph's column, its bank's R6
; value | $80 for the +256 half), each one's four tiles t..t+3 (top-left,
; bottom-left, top-right, bottom-right = glyph tiles 0, 2, 1, 3) in plane
; 0 of page R0, straight from the glyph table, unrolled.  Stops at a kana
; record or the batch's end (TXR_UQN 0): C clear; or when TXR_UB has no
; UP_KANJI left: C set.  Entered with R7 = the upper half of a hack bank
; (this code is the same in each: it maps R7 to another one under its own
; feet) and R6 = the renderer bank's lower half; maps R6/R7 to each
; glyph's bank (KANJI_T0: the R6 value mapped; $FF from the caller), R0
; when it changes (KANJI_T1: the caller's), R6 back before returning.
; X = the next record; Y lost; PPUCTRL +1 increments set by the caller.
; ----------------------------------------------------------------------
.macro MKT tab, j, k
    lda TXR_UQ+1,x
    sta PPUADDR
    lda TXR_UQ+2,x
    ora #j*16
    sta PPUADDR
    MK8 tab, k
.endm
.macro MKT0 tab
    lda TXR_UQ+1,x
    sta PPUADDR
    lda TXR_UQ+2,x
    sta PPUADDR
    MK8 tab, 0
.endm
.macro MK8 tab, k
    lda tab+(k*8+0)*GSTRIDE,y
    sta PPUDATA
    lda tab+(k*8+1)*GSTRIDE,y
    sta PPUDATA
    lda tab+(k*8+2)*GSTRIDE,y
    sta PPUDATA
    lda tab+(k*8+3)*GSTRIDE,y
    sta PPUDATA
    lda tab+(k*8+4)*GSTRIDE,y
    sta PPUDATA
    lda tab+(k*8+5)*GSTRIDE,y
    sta PPUDATA
    lda tab+(k*8+6)*GSTRIDE,y
    sta PPUDATA
    lda tab+(k*8+7)*GSTRIDE,y
    sta PPUDATA
.endm

mk_run:                         ; (the caller sets KANJI_T0 = $FF: no glyph bank mapped yet)
mk_rec:
    lda TXR_UB
    sec
    sbc #UP_KANJI
    bcs @fits
    sec                         ; no time left this NMI: C set
    jmp mk_exit
@fits:
    sta TXR_UB
    lda TXR_UQ+4,x              ; the glyph bank's R6 value
    and #$7F
    cmp KANJI_T0
    beq @mapped
    sta KANJI_T0
    ldy #MMC3_R6
    sty MMC3_SELECT
    sta MMC3_DATA
    ora #1
    ldy #MMC3_R7
    sty MMC3_SELECT
    sta MMC3_DATA               ; (the same code there)
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
    ldy TXR_UQ+3,x              ; the glyph's column
    lda TXR_UQ+4,x
    bpl @lo
    jmp mk_hi
@lo:
    MKT0 GLYPH_TAB
    MKT GLYPH_TAB, 1, 2
    MKT GLYPH_TAB, 2, 1
    MKT GLYPH_TAB, 3, 3
    jmp mk_next
mk_hi:
    MKT0 GLYPH_TAB+256
    MKT GLYPH_TAB+256, 1, 2
    MKT GLYPH_TAB+256, 2, 1
    MKT GLYPH_TAB+256, 3, 3
mk_next:
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
    jmp mk_rec
@out:
    clc
mk_exit:                        ; (C kept)
    lda #MMC3_R6
    sta MMC3_SELECT
    lda #TXR_BANK*2
    sta MMC3_DATA
    rts
.if mk_run <> HACK_MKUP
.error "mk_run must stay at HACK_MKUP (kanji.inc)"
.endif

; load_text_graphics' table copy (revision 16c; was inline in the fixed
; bank, whose space went to chr1_scene when $E6B3-$E6C3 turned out to be a
; battle table).  Main thread, this bank mapped by the caller under the
; lock protocol; jumped to and back (LTG_COPIED), so the text task's stack
; is no deeper than with the inline copy.  Same effects as the original:
; $F3/$F4 point at the palette record, $03E0+ receives it, Y ends at the
; record's terminator.
pal_copy:
    lda #0                      ; step B: the uploads before this load were
    sta UI_NOMIR                ; the one-shot no-mirror ones; the battle
    sta UI_BATTLE               ; screen's kanji state ends (UIF_BSTART)
    ldx text_graphics_index
    lda KANJI_PAL_LO,x
    sta ppu_update_ptr_lo
    lda KANJI_PAL_HI,x
    sta ppu_update_ptr_hi
    ldy #$00
    lda (ppu_update_ptr_lo),y
    tax
@copy:
    iny
    lda (ppu_update_ptr_lo),y
    bmi @end
    sta $03E0,x
    inx
    bne @copy
@end:
    ; A new graphics set: the pool is unchecked.  The battle set posts a
    ; check of the pool tiles now (served in the following NMIs, at once
    ; while rendering is off), so the first message need not wait.  A, X
    ; only; Y stays as the copy left it.
    lda KANJI_WIN_COL
    and #<~(WINCOL_POOL_OK|WINCOL_CHECKED)
    sta KANJI_WIN_COL
    lda text_graphics_index
    cmp #POOL_SET
    bne ltg_mask
    lda KANJI_REQ
    bne ltg_mask                ; busy: the overlay checks at its next message
    lda #POOL_FIRST
    sta KANJI_TILES
    lda #0
    sta KANJI_TILES+1
    lda #POOL_CHECK_CODE
    sta KANJI_CODE_HI
    lda #REQ_UPLOAD
    sta KANJI_REQ
ltg_mask:                       ; (the gates count ltg_mask..ltg_mask_end as game code)
    ; load_text_graphics' palette mask (moved from the fixed bank in
    ; map-canvas step 1): every set bit of $A5 blacks one palette, the
    ; DMA flag gets Y, as the original.
    lda $A5
    beq @done
    ldy #$00
@mask:
    lsr a
    bcs @black
    iny
    iny
    iny
    iny
    cpy #$20
    bne @mask
    beq @done
@black:
    ldx #$04
@black4:
    pha
    lda #$0F
    sta $03E0,y
    pla
    iny
    dex
    bne @black4
    beq @mask
@done:
    sty vram_dma_pending
    lda #$00
    sta $A5
    jmp LTG_COPIED
ltg_mask_end:

; Epilogue: choose the next tile to restore (no PPU access, no deadline).
; KANJI_PICK = tile, or $FF when nothing is stale.
pick_restore:
    lda #$FF
    sta KANJI_PICK
    lda text_graphics_index     ; step B: no band-page restores in the battle
    cmp #POOL_SET               ; and the info screen (a pending sync ends)
    beq @rts_pick
    ldx #0
@lower:
    lda KANJI_STALE,x
    beq @next
    lda KANJI_A,x
    eor #$FF
    and KANJI_STALE,x
    bne @found
@next:
    inx
    cpx #16
    bne @lower
    ldx #0
@upper:
    lda KANJI_STALE_HI,x
    bne @found_hi
    inx
    cpx #4
    bne @upper
@rts_pick:
    rts
@found:
    ldy #0
@bit:
    asl a
    bcs @got
    iny
    bne @bit
@got:
    sty KANJI_T0
    txa
    asl a
    asl a
    asl a
    ora KANJI_T0
    sta KANJI_PICK
    rts
@found_hi:
    ldy #0
@bit_hi:
    asl a
    bcs @got_hi
    iny
    bne @bit_hi
@got_hi:
    sty KANJI_T0
    txa
    asl a
    asl a
    asl a
    ora KANJI_T0                ; group 0-31
    asl a
    asl a
    ora #$80
    sta KANJI_T0
    lda KANJI_NFLAGS
    and #FLAG_HI_SUB
    lsr a
    lsr a
    lsr a
    lsr a
    ora KANJI_T0
    sta KANJI_PICK
    rts

; ----------------------------------------------------------------------
; Window-gone check on the VRAM queue (revision 15).  Queue entry: address
; KANJI_T1:KANJI_T2 ($2000-$2FFF), Y = length, data at $0400,X, length
; byte (bit 7 = +32 steps) at $0400,X-1.  While the band is up, an entry
; that writes the window's top-left corner cell with another tile means
; the window is being erased: drop the band now instead of waiting for
; the window probe, whose frames are rare while the map scrolls (the
; epilogue's sprite-0 wait would keep costing most of each frame).  CPU
; only; preserves X, Y, KANJI_T1/T2.  Scratch: KANJI_BUF+0..+4 (the
; read-back buffer is free outside restore_tile).
; ----------------------------------------------------------------------
NT_HI  = KANJI_BUF+0
NT_LO  = KANJI_BUF+1
NT_K   = KANJI_BUF+2
NT_LEN = KANJI_BUF+3
NT_X   = KANJI_BUF+4
NT_Q0  = KANJI_BUF+5            ; queue position at the frame's first scan
nt_check:
    lda KANJI_BAND
    beq nt_ret
    lda QS_NOREPLAY
    beq nt_ret                  ; scan before the scroll restore: nt_rescan
    cpy #0
    bne nt_go
nt_ret:
    rts
nt_go:
    stx NT_X
    sty NT_LEN
    lda KANJI_WIN_ROW           ; corner cell address, as probe_window
    lsr a
    lsr a
    lsr a
    ora #$20
    sta NT_HI
    lda KANJI_WIN_COL
    and #$20
    beq nt_nt0
    lda NT_HI
    ora #$04
    sta NT_HI
nt_nt0:
    lda KANJI_WIN_ROW
    asl a
    asl a
    asl a
    asl a
    asl a
    sta NT_LO
    lda KANJI_WIN_COL
    and #$1F
    ora NT_LO
    sec                         ; offset = corner - entry address
    sbc KANJI_T2
    sta NT_LO
    lda NT_HI
    sbc KANJI_T1
    bcc nt_done                   ; corner before the entry
    sta NT_HI
    lda $03FF,x                 ; length byte
    bmi nt_vertical
    lda NT_HI
    bne nt_done
    lda NT_LO
    bcs nt_index                  ; always (C set from the subtraction)
nt_vertical:
    lda NT_LO
    and #$1F
    bne nt_done                   ; not in the entry's column
    lda NT_LO
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    sta NT_K
    lda NT_HI
    asl a
    asl a
    asl a
    ora NT_K
nt_index:
    cmp NT_LEN
    bcs nt_done                   ; past the entry's end
    clc
    adc NT_X
    tax
    lda $0400,x
    cmp #WINDOW_CORNER
    beq nt_done
    lda #0
    sta KANJI_BAND
nt_done:
    ldx NT_X
nt_rts:
    rts

; Second pass for the no-unit path, whose queue scan runs before the scroll
; restore (it may replay a CHR entry) and so skips nt_check: walk the same
; entries again after the restore.  CPU only.
nt_rescan:
    lda QS_NOREPLAY
    bne nr_rts                  ; queue_scan ran nt_check itself (revision 16)
    lda KANJI_BAND
    beq nr_rts
    lda vram_queue_read
    sec
    sbc NT_Q0
    beq nr_rts
    cmp #193
    bcs nr_rts
    lda #1
    sta QS_NOREPLAY             ; lets nt_check run
    ldx NT_Q0
nr_entry:
    cpx vram_queue_read
    beq nr_rts
    lda $0400,x
    beq nr_rts
    sta KANJI_T1
    inx
    lda $0400,x
    sta KANJI_T2
    inx
    lda $0400,x
    and #$7F
    tay
    inx
    lda KANJI_T1
    cmp #$20
    bcc nr_skip
    cmp #$30
    bcs nr_skip
    jsr nt_check
nr_skip:
    sty KANJI_T0
    txa
    clc
    adc KANJI_T0
    tax
    jmp nr_entry
nr_rts:
    rts

; ----------------------------------------------------------------------
; Block writer copy (main thread, busy mode, KANJI_MAINCHR set): tile
; KANJI_M1 from page 1 (selected) to page 2, back to page 1, and clear its
; lower stale bit, as restore_tile.  The R0 writes are inline under the
; bank-select shadow, so the stack holds only this routine's return
; address there (revision 18; was 6 bytes).
; ----------------------------------------------------------------------
restore_tile_main:
    jsr tile_ppuaddr
    lda PPUDATA                 ; buffered read
    ldx #0
@rd:
    lda PPUDATA
    sta KANJI_BUF,x
    inx
    cpx #16
    bne @rd
    lda #MMC3_R0                ; band page, under the bank-select shadow
    sta MMC3_SEL
    sta MMC3_SELECT
    lda #CHR_BAND_LO
    sta MMC3_DATA
    jsr tile_ppuaddr
    ldx #0
@wr:
    lda KANJI_BUF,x
    sta PPUDATA
    inx
    cpx #16
    bne @wr
    lda #CHR_SCENE_LO           ; scene page ($8000 = MMC3_SEL = R0 still:
    sta MMC3_DATA               ; an NMI in between restored it)
    lda KANJI_M1
    bmi @done                   ; upper tiles: no lower stale bit
    lsr a
    lsr a
    lsr a
    tax
    lda KANJI_M1
    and #7
    tay
    lda bitmask,y
    eor #$FF
    and KANJI_STALE,x
    sta KANJI_STALE,x
@done:
    rts

; PPUADDR = page tile KANJI_M1 ($1000 + tile * 16).
tile_ppuaddr:
    lda KANJI_M1
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta PPUADDR
    lda KANJI_M1
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
    rts

; ----------------------------------------------------------------------
; Battle pool (revision 18).
; pool_off: the game wrote into the pool tiles (block writer, main thread;
; queue or CHR animation, NMI): no pool until the next check.
; ----------------------------------------------------------------------
pool_off:
    lda UI_BATTLE               ; step B: the battle screen manages the
    bne pool_rts                ; tiles itself (UI bank, UI_SLOT)
    lda KANJI_WIN_COL
    and #<~WINCOL_POOL_OK
    sta KANJI_WIN_COL
pool_rts:
    rts

; queue_scan's CHR entries (pool armed): only entries starting in
; $1900-$1DFF can reach the pool.
pool_guard_q:
    lda KANJI_T1
    cmp #>(POOL_FIRST*16+$1000)-1
    bcc pool_rts                ; starts below $1900
    cmp #>(POOL_LAST*16+$1000)+1
    bcs pool_rts                ; starts at $1E00 or later
; pool_guard (NMI bookkeeping): the game wrote Y bytes (0 = 128) of CHR at
; KANJI_T1:KANJI_T2; any overlap with the pool tiles disarms the pool.
; Preserves X, Y and the T registers.
pool_guard:
    tya
    pha
    bne @len
    lda #128
@len:
    clc
    adc KANJI_T2
    sta MS_TMP                  ; end, low
    lda KANJI_T1
    adc #0                      ; end, high (exclusive)
    cmp #>(POOL_FIRST*16+$1000)
    bcc @done                   ; ends before $1A00
    bne @end_ok
    lda MS_TMP
    cmp #<(POOL_FIRST*16+$1000)+1
    bcc @done                   ; ends at or before $1A40
@end_ok:
    lda KANJI_T1                ; starts below $1E00?
    cmp #>((POOL_LAST+1)*16+$1000)
    bcs @done
    jsr pool_off
@done:
    pla
    tay
    rts

; Pool check (REQ_UPLOAD, KANJI_CODE_HI = POOL_CHECK_CODE): read four pool
; tiles of the scene page per unit, OR them into KANJI_TILES+1; KANJI_TILES
; is the next tile.  After $DF the pool is checked, and armed when every
; byte was 0.  NMI (light or bulk) or main thread with rendering off.
pool_check_nmi:
    lda #1
    jsr wr_reg1                 ; read the scene page
    jmp pool_check_go
pool_check_main:
    lda #1
    jsr set_page
pool_check_go:
    lda KANJI_TILES
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta PPUADDR
    lda KANJI_TILES
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
    lda PPUDATA                 ; buffered read
    lda KANJI_TILES+1
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    ora PPUDATA
    sta KANJI_TILES+1
    lda KANJI_TILES
    clc
    adc #4
    sta KANJI_TILES
    cmp #POOL_LAST+1
    bcc @more
    lda KANJI_WIN_COL
    ora #WINCOL_CHECKED
    ldx KANJI_TILES+1
    bne @dirty
    ora #WINCOL_POOL_OK
@dirty:
    sta KANJI_WIN_COL
    lda #0
    sta KANJI_REQ
@more:
    clc
    rts

