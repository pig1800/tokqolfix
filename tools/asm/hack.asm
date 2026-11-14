; ======================================================================
; Hack bank code (revision 11), PRG bank 23.  Since 2026-11-14 the band
; page is gone (the user's order): no page-2 copy of the font, no stale
; tracking, restores or band IRQ.  The message engine stops the CPU where
; a message would have used it (kanji_msg.asm band_trap).  This bank
; serves the battle pool's glyph uploads and pool check (KANJI_REQ), guards
; the pool tiles against the game's CHR writes, copies the palettes, and
; holds the message engine (kanji_msg.asm, out of the text banks since
; 2026-11-14), which runs with a text chunk at R7.
;
; Assembled for $8000; everything (with the relocated palette tables at
; KANJI_PAL_DATA) in the bank's lower 8 KiB: R7 is a window, a bank of the
; kanji store (the glyph upload; kanji.inc STORE_*) or the message's text
; chunk (MSG_BANK).
;
; Entry points:
;   $8000  call_hack dispatcher (KANJI_FN), main thread or NMI flush
;   $8003  NMI after the game's PPU work, normal frames (loc_EF08)
;   $8006  NMI epilogue, every frame (loc_EF31)
;   $8009  load_text_graphics' table copy (HACK_PAL_COPY)
;   $800C  reset (HACK_INIT)
;   $800F  the message entry (MSG_ENTRY: the F8 trampoline's)
;   text_dispatch, ctrl_store: the fixed bank's text-engine hooks ($D28E,
;          $D2C7; kanji_build.py patches them from this listing)
;
; NMI rules: no zero-page use, at most
; three nested calls, no PPU access in busy frames, every PPU address
; write followed by a full scroll/PPUCTRL restore before the frame starts.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"
.include "../../decomp/build/kanji/fixed_hooks.inc"

LIGHT_QUEUE  = 8            ; max queued bytes for a light frame
; NMI scratch in the read-back buffer (the main thread uses the buffer only
; while the NMI is in busy mode or disabled).
MS_TMP       = KANJI_BUF+15
OFF_UNITS    = 16           ; work units per NMI with rendering off

.base $8000
.org $8000

    jmp fn_dispatch
    jmp nmi_ef08
    jmp nmi_ef31
    jmp pal_copy                ; $8009 HACK_PAL_COPY (load_text_graphics)
    jmp hack_init               ; $800C HACK_INIT (reset)
msg_entry_slot:
    jmp msg_entry               ; $800F MSG_ENTRY (the F8 trampoline)
.if msg_entry_slot != MSG_ENTRY
    .error "MSG_ENTRY is not the jump table's $800F"
.endif


; ======================================================================
; NMI, normal frames, after the game's PPU work (still in vblank).
; ======================================================================
nmi_ef08:
    lda nmi_busy
    beq @live
    ; Busy frame: rendering is off and the main thread owns the PPU (its
    ; CHR writes would clock the IRQ counter: no IRQ this frame).  Put the
    ; scene page back unless a main-thread routine holds R0 on purpose.
    sta MMC3_IRQ_OFF
    lda KANJI_MAINCHR
    bne @busy_q
    jsr r0_scene
@busy_q:
    lda vram_queue_read
    sta KANJI_QPOS
    rts
@live:
    ; Units first (the PPU work races the end of vblank), the CPU-only
    ; bookkeeping after the scroll restore.  With rendering on, a frame
    ; that stepped the CHR animation or flushed more than LIGHT_QUEUE bytes
    ; runs no unit.
    lda vram_queue_read
    sec
    sbc KANJI_QPOS
    sta KANJI_QBYTES            ; bytes the game flushed this frame
    tax
    jsr anim_check              ; C set: the CHR animation stepped
    lda KANJI_REQ
    beq @post
    lda ppu_mask_shadow
    and #$18
    bne @rendering
    lda #OFF_UNITS              ; rendering off for the whole coming frame
    bne @tier
@rendering:
    bcs @post                   ; the animation step ran long: no unit
    cpx #LIGHT_QUEUE+1
    bcs @post
    lda #1                      ; light frame, queued bytes: single units
    cpx #0
    bne @tier
    lda #2                      ; light frame, queue idle: double upload
@tier:
    sta KANJI_T1
    lda ppu_ctrl_shadow
    and #$FB                    ; +1 increment for our transfers
    sta PPUCTRL
    lda PPUSTATUS
    lda KANJI_T1
    cmp #OFF_UNITS
    beq @unit
    jsr work_unit               ; light frame: one unit (one or two tiles)
    jmp @restore
@unit:
    jsr work_unit               ; rendering off: up to OFF_UNITS units
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
@post:
    jsr pool_scan
    lda KANJI_REQ
    cmp #REQ_MARK
    bne @rts
    lda #0                      ; the glyph is complete
    sta KANJI_REQ
@rts:
    rts

; The game's NMI uploads a CHR-animation step in flush_palette: 4 tiles at
; ($3C:$3B) - $40, then $39 += $40.  With the pool armed, a step into the
; pool tiles disarms it.  Carry set when $39 moved since the last check.
; CPU only; X kept.
anim_check:
    lda $39
    cmp KANJI_LAST39
    beq @none
    sta KANJI_LAST39
    bit KANJI_WIN_COL           ; V = WINCOL_POOL_OK
    bvc @seen
    lda $3B
    sec
    sbc #$40
    and #$F0
    sta KANJI_T2
    lda $3C
    sbc #0
    cmp #$10
    bcc @seen
    cmp #$20
    bcs @seen
    sta KANJI_T1
    ldy #64
    jsr pool_guard
@seen:
    sec
    rts
@none:
    clc
    rts

; The VRAM queue entries the game flushed since the last scan: with the
; pool armed, a CHR entry that reaches the pool tiles disarms it.  Then
; KANJI_QPOS = the queue's read position.  CPU only.
pool_scan:
    bit KANJI_WIN_COL           ; V = WINCOL_POOL_OK
    bvc @done
    ldx KANJI_QPOS
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
    cmp #$10
    bcc @skip
    cmp #$20
    bcs @skip
    jsr pool_guard_q
@skip:
    sty KANJI_T0
    txa
    clc
    adc KANJI_T0
    tax
    jmp @entry
@done:
    lda vram_queue_read
    sta KANJI_QPOS
    rts

; ----------------------------------------------------------------------
; One unit of VRAM work: a glyph tile (two when KANJI_T1 is not 1) or four
; pool tiles checked.  The NMI (light or bulk) or the main-thread service,
; PPUCTRL +1 increment.  Carry set when there was nothing to do.  A request
; the band used to serve (REQ_RELEASE, REQ_RESTORE, REQ_SYNC: a save state
; from an earlier build) is dropped.
; ----------------------------------------------------------------------
work_unit:
    lda KANJI_REQ
    beq @none
    cmp #REQ_UPLOAD
    beq upload_unit
    cmp #REQ_UP1
    bcc @drop                   ; REQ_RELEASE, REQ_RESTORE
    cmp #REQ_MARK
    bcc upload_unit             ; REQ_UP1..REQ_UP3
    beq @none                   ; REQ_MARK: cleared after the scroll restore
@drop:
    lda #0                      ; (REQ_SYNC and the others)
    sta KANJI_REQ
@none:
    sec
    rts

; One tile (two when the frame has room) of the glyph KANJI_CODE to the pool
; tiles KANJI_TILES (upper tiles: R1, always the scene page): REQ_UPLOAD is
; tile 0, REQ_UP1..REQ_UP3 tiles 1-3; after tile 3 the request becomes
; REQ_MARK (cleared after the scroll restore).  KANJI_T1 = 1: one tile only.
upload_unit:
    lda KANJI_CODE_HI
    cmp #POOL_CHECK_CODE
    bne @glyph
    jmp pool_check_go
@glyph:
    jsr upload_slot
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

; ----------------------------------------------------------------------
; Glyph upload, one tile (Y = 0-3, the glyph's tile in KANJI_TILES order:
; TL, TR, BL, BR).  KANJI_CODE_HI/LO = the glyph's store bank and pos,
; KANJI_TILES = the four destination tiles, the CHR page selected.  The
; store bank at R7 (map_store): byte b of the glyph at STORE_TAB + 256 b +
; pos, the store's tiles in 8x16 order (TL, BL, TR, BR).
; ----------------------------------------------------------------------
glyph_upload:
    sty KANJI_T2                ; tile 0-3; KANJI_T1 is the NMI unit count
    lda KANJI_CODE_HI
    jsr map_store
    ldx KANJI_CODE_LO
    lda KANJI_T2                ; (the uploads end in unmap_store: no
    beq @t0                     ; deeper stack than before the store)
    cmp #2
    beq @t2
    bcs @t3
    jmp upload_tr               ; KANJI_TILES+1: TR
@t0:
    jmp upload_tl
@t2:
    jmp upload_bl               ; KANJI_TILES+2: BL
@t3:
    jmp upload_br

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

; Tile KANJI_TILES+k = the store's tile s of the glyph (X = pos).
.macro UPLOAD_TILE k, s
    ldy #k
    jsr tile_addr
    lda STORE_TAB+(s*8+0)*256,x
    sta PPUDATA
    lda STORE_TAB+(s*8+1)*256,x
    sta PPUDATA
    lda STORE_TAB+(s*8+2)*256,x
    sta PPUDATA
    lda STORE_TAB+(s*8+3)*256,x
    sta PPUDATA
    lda STORE_TAB+(s*8+4)*256,x
    sta PPUDATA
    lda STORE_TAB+(s*8+5)*256,x
    sta PPUDATA
    lda STORE_TAB+(s*8+6)*256,x
    sta PPUDATA
    lda STORE_TAB+(s*8+7)*256,x
    sta PPUDATA
    jmp plane1_blank            ; (Y = k still)
.endm

; Plane 1 of the tile just written (KANJI_TILES+Y) blank, except in the
; battle screen's groups 15-20 ($E0-$F7, the battle messages' last resort,
; ui_pchoose): their plane 1 holds the HP gauges and S P.  Then the store
; bank unmapped (unmap_store).
plane1_blank:
    lda KANJI_TILES,y
    cmp #$E0
    bcs unmap_store
    lda #0
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
; The main thread: R7 back to this bank's upper half, PRG_R7X cleared
; first (an NMI after it restores the same).  The NMI: nothing (its last
; restore maps the main thread's banks back).  X and Y kept.
unmap_store:
    lda KANJI_MAINCHR
    beq @rts
    lda #0
    sta PRG_R7X
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    lda #KANJI_HACK_BANK*2+1
    sta MMC3_DATA
@rts:
    rts

upload_tl:
    UPLOAD_TILE 0, 0
upload_tr:
    UPLOAD_TILE 1, 2
upload_bl:
    UPLOAD_TILE 2, 1
upload_br:
    UPLOAD_TILE 3, 3


; ======================================================================
; NMI epilogue, split frames only (ef31_gate): nothing since the band is
; gone (it put the scene page back and the band off).
; ======================================================================
nmi_ef31:
    rts


; ----------------------------------------------------------------------
; Reset (map-canvas step 3), called by the fixed bank's reset with this
; bank at R6/R7 and NMIs off: clear the hack state ($0103-$017F), the
; renderer state ($0780-$07FF) and battery RAM $7900-$7FFF (the renderer's
; tables and buffers, the UI bank's state; RAM code until 2026-11-14,
; fixed_rt.asm now).
; ----------------------------------------------------------------------
hack_init:
    lda #0
    sta PRG_R7X                 ; (battery RAM: any value at power-on)
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
    tax                         ; (A = 0; unrolled: the reset must not
@c3:                            ; cost the game a frame)
    sta $7900,x
    sta $7A00,x
    sta $7B00,x
    sta $7C00,x
    sta $7D00,x
    sta $7E00,x
    sta $7F00,x
    inx
    bne @c3
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

; R0 = the scene page (BG tiles $00-$7F).  NMI: $8000 written directly (the
; restore_bank_after_nmi that ends every NMI gives it back).  Main thread:
; under the bank-select shadow.  X and Y kept.
r0_scene:
    lda #MMC3_R0
    sta MMC3_SELECT
    lda #CHR_SCENE_LO
    sta MMC3_DATA
    rts
r0_scene_main:
    lda #MMC3_R0
    sta MMC3_SEL
    sta MMC3_SELECT
    lda #CHR_SCENE_LO
    sta MMC3_DATA
    rts

; A = a kanji store bank (0-3) at R7 (this code is all in $8000-$9FFF).
; The NMI writes R7 directly (its last restore_bank_after_nmi maps the
; main thread's banks back); the main thread (KANJI_MAINCHR) under the
; bank-select shadow, with PRG_R7X set so that an NMI's restore keeps it
; (unmap_store gives R7 back).  Y lost, X kept.
map_store:
    ora #STORE_8K
    ldy KANJI_MAINCHR
    bne @main
    ldy #MMC3_R7
    sty MMC3_SELECT
    sta MMC3_DATA
    rts
@main:
    sta PRG_R7X
    ldy #MMC3_R7
    sty MMC3_SEL
    sty MMC3_SELECT
    sta MMC3_DATA
    rts


; ----------------------------------------------------------------------
; Block writer, before the original body (main thread only: the fixed-bank
; hook handles the NMI's block write itself).  $02 = tile count, $03 =
; address high, $04 = address low | mode.  For page-1 writes select CHR
; page 1 and save the range (fn_block_post's pool check).
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
    jmp r0_scene_main
@page0:
@rts:
    rts


; ----------------------------------------------------------------------
; Block writer, after the original body (main thread, rendering off): a
; write into the pool tiles disarms the pool.  (Until 2026-11-14 it also
; copied every written font tile to the band page.)
; ----------------------------------------------------------------------
fn_block_post:
    lda KANJI_M0
    beq @rts
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
@rts:
    rts

; ----------------------------------------------------------------------
; Main thread with rendering off (busy mode or NMI disabled): serve the
; message engine's request directly.  KANJI_MAINCHR tells the store mapping that
; the main thread runs (map_store / unmap_store); two tiles a unit.
; ----------------------------------------------------------------------
fn_service:
    lda #1
    sta KANJI_MAINCHR
    lda #2
    sta KANJI_T1
    lda ppu_ctrl_shadow
    and #$FB
    sta PPUCTRL
    lda PPUSTATUS
@more:
    jsr work_unit
    lda KANJI_REQ
    beq @end
    cmp #REQ_MARK
    bne @more
    lda #0                      ; the glyph is complete
    sta KANJI_REQ
@end:
    lda PPUSTATUS
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda #0
    sta KANJI_MAINCHR
    rts


; (The second code segment, $B900 before the kanji store, follows.)

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
    bne ltg_mask                ; busy: the message engine checks at its next message
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

; pool_scan's CHR entries (pool armed): only entries starting in
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
pool_check_go:                  ; (pool tiles are upper tiles: R1, the scene page)
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


; ======================================================================
; The message engine (the text engine's kanji half).
; ======================================================================
.include "kanji_msg.asm"

.if $ > KANJI_PAL_DATA
    .error "the hack code runs into the relocated palette tables (KANJI_PAL_DATA)"
.endif
