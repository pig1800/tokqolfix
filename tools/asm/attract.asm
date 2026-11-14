; ======================================================================
; Bank ATT_BANK (24): the title screen's tile set and the attract mode in
; kanji (titlekanji.txt, the user's spec, 2026-11-14; data from
; tools/attract_build.py).
;
; $8000 att_attract: the attract mode, in place of bank 7's
;       b07_enter_party_screen (the fixed bank's enter_party_screen maps
;       this bank).  The same steps and frame counts as the original; it
;       ends in enter_status_screen (the title) as the original.
; $8003 att_title_set: called from the title's inline block (bank 13,
;       rendering and NMI off): the title's tile set and nametable.  (Until
;       2026-11-14 also the game's font on the band page, which is gone.)
; $8006 att_restore: Start on the title (bank 13's b13_k_restore, NMI off):
;       the font and the letters back on the scene page, as the original's
;       title load left them for the boot screens.
; $8009 title_fx: the title's logo intro, every NMI while nmi_mode = $80
;       (the fixed bank's $EF38 maps this bank's first half at R6 alone):
;       the strips' positions and the IRQ events that draw them.
;
; Every screen has its own BG tile set, uploaded while it is black: kanji
; from tile $00 (8x16 order TL, BL, TR, BR, from the kanji store), then
; the 8x8 glyphs (the game's font in bank 9, the title's letters in bank
; 2), tile $FF blank; the nametables are filled with $FF.  The title keeps
; its logo at $80-$DF, and the intro over it uses the title's set.
;
; The portraits are 8x16 sprites (the user's choice, 2026-11-14): 18 a
; portrait, at most 54, 6 on a line, so the NMI's own OAM DMA shows all of
; them; no scanline IRQ and no mid-frame write.  Their tiles go to the
; sprite page in top/bottom pairs; band 2's portrait is the H-flip.  The
; slide is the original's: 8 pixels a frame for 31 frames, a column hidden
; while it is past the screen's edge.
;
; The phrases are drawn through the game's VRAM queue (draw_string) with
; the original phrases' attribute records: each line fades in through BG
; palette 2 on its own attribute row, as the original's (a kanji line's
; two rows are the original line's row and the dakuten row above it).
;
; Banks 2, 3 and 9 are read by small RAM routines (RR_*, copied to the
; $0600 page) that map them with set_bank_b, the game's NMI-safe switch;
; the kanji store is read at R7 with PRG_R7X set (kanji.inc), from code
; below $A000.
; ======================================================================
.include "../../decomp/include/hardware.inc"
.include "../../decomp/include/ram.inc"
.include "../../decomp/include/kanji.inc"

; Fixed-bank routines (the original's addresses).
DRAW_STRING_PTR     = $DD17     ; draw_string after its fetch_inline_word: ($00) = the block
SCREEN_OFF          = $C145     ; screen_fade_in: rendering off (shadow), nmi_busy set
SCREEN_ON           = $C151     ; screen_fade_out: nmi_busy cleared, rendering on
FADE_OUT            = $C522     ; draw_window: palettes to black, Y frames a step
FADE_IN             = $C51A     ; draw_text_window_small: palettes from black
LOAD_TEXT_GRAPHICS  = $C5A6
ENTER_STATUS_SCREEN = $F0DF     ; bank 13's title

FADE_MASK   = $A5               ; the fades: a set bit leaves that palette alone
KEEP_OAM    = $A4               ; the fades: nonzero, no clear_oam_shadow / update_oam
SLIDE       = $7C               ; the slide's offset (bank 7's own variable)
NPOR        = map_y2            ; portraits on this screen (bank 7's portrait index; the
                                ; fades use the temporaries $0B-$0F)
BLANK       = $FF
FONT_SRC    = $BA00             ; bank 9: the game's font, 128 tiles 1bpp (load_battle_palette)
LETTER_SRC  = $BE00             ; bank 2: the title's letters $E0-$FF, 1bpp

; Zero page: the game's call temporaries (nothing here yields while using
; them; the NMI of a busy frame does not touch them).
ZP_S        = $02               ; 2: RAM routines' source
ZP_D        = $04               ; 2: RAM routines' PPU destination
ZP_G        = $06               ; 2: glyph pointer (the kanji store)
ZP_N        = $08               ; count
ZP_I        = $09
ZP_P        = $0A               ; portrait
ZP_T        = $0C               ; 2: table pointer

RAM_RR      = $0660             ; the RAM routines (the title's inline block runs below $0640)

.base $8000
.org $8000
    jmp att_attract             ; $8000
    jmp att_title_set           ; $8003
    jmp att_restore             ; $8006
    jmp title_fx                ; $8009 ATT_TITLE_FX (kanji.inc)
.if title_fx_slot != ATT_TITLE_FX + 3
    .error "ATT_TITLE_FX is not the jump table's $8009"
.endif
title_fx_slot:

; ======================================================================
; The title (bank 13's inline block, NMI and rendering off, this bank at
; $8000 through set_bank_b): both nametables blank, the title's tile set,
; the logo map, TM, PUSH START, the copyright lines.  The block's
; draw_string then queues only the attribute records (ATT_TITLE_ATTR).
; ======================================================================
att_title_set:
    lda #$FF
    sta TFX_S                   ; (the intro starts at its first step)
    jsr att_rr_install
    lda PPUSTATUS
    lda #$20
    jsr att_nt_blank
    lda #$24
    jsr att_nt_blank
    ldx #0
    jsr att_set
    lda #<att_title_nt
    sta ZP_T
    lda #>att_title_nt
    sta ZP_T+1
    ; (falls through)

; Records at (ZP_T) written to the PPU now (no fills, no vertical runs).
att_direct:
    lda PPUSTATUS
@rec:
    ldy #0
    lda (ZP_T),y
    cmp #$FF
    beq @done
    sta PPUADDR
    iny
    lda (ZP_T),y
    sta PPUADDR
    iny
    lda (ZP_T),y
    iny
    tax
@byte:
    lda (ZP_T),y
    sta PPUDATA
    iny
    dex
    bne @byte
    tya
    clc
    adc ZP_T
    sta ZP_T
    bcc @rec
    inc ZP_T+1
    bcs @rec
@done:
    rts

; A = nametable high byte: its 960 tiles blank.
att_nt_blank:
    sta PPUADDR
    lda #0
    sta PPUADDR
    lda #BLANK
    ldx #3
    ldy #0
@page:
    sta PPUDATA
    iny
    bne @page
    dex
    bne @page
    ldy #$C0
@rest:
    sta PPUDATA
    dey
    bne @rest
    rts

; Start on the title: the font (tiles $00-$7F) and the letters ($E0-$FF) on
; the scene page, as the original's title load wrote them.
att_restore:
    jsr att_rr_install
    jsr att_font
    lda #$1E
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #<LETTER_SRC
    sta ZP_S
    lda #>LETTER_SRC
    sta ZP_S+1
    ldx #32
    lda #2
    jmp RR_COPY

; The game's font (bank 9, 128 tiles 1bpp) to tiles $00-$7F of the page at R0.
att_font:
    lda PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda #<FONT_SRC
    sta ZP_S
    lda #>FONT_SRC
    sta ZP_S+1
    ldx #128
    lda #9
    jmp RR_COPY

; ======================================================================
; Tile set X (attract_lo.inc): kanji count, (store bank, pos) each from
; tile $00 on; 8x8 count, (tile, source) each: source bit 7 = letter
; (bank 2, $BE00 + 8 n), else font tile (bank 9, $BA00 + 8 n); then tile
; $FF blank.  Rendering off.
; ======================================================================
att_set:
    lda att_set_lo,x
    sta ZP_T
    lda att_set_hi,x
    sta ZP_T+1
    lda PPUSTATUS
    lda #$10
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldy #0
    lda (ZP_T),y
    sta ZP_N
    beq @small
@kanji:
    iny
    lda (ZP_T),y
    pha
    iny
    lda (ZP_T),y
    tax
    pla
    sty ZP_I
    jsr att_glyph
    ldy ZP_I
    dec ZP_N
    bne @kanji
@small:
    iny
    lda (ZP_T),y
    sta ZP_N
    beq @blank
@glyph:
    iny
    lda (ZP_T),y                ; the tile: PPU $1000 + 16 t
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$10
    sta PPUADDR
    pla
    asl a
    asl a
    asl a
    asl a
    sta PPUADDR
    iny
    lda (ZP_T),y
    sty ZP_I
    bmi @letter
    pha                         ; font tile n: bank 9 $BA00 + 8 n
    asl a
    asl a
    asl a
    sta ZP_S
    pla
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc #$BA
    sta ZP_S+1
    lda #9
    bne @copy
@letter:
    asl a                       ; letter n: bank 2 $BE00 + 8 n (bit 7 shifted out)
    asl a
    asl a
    sta ZP_S
    lda #$BE
    sta ZP_S+1
    lda #2
@copy:
    ldx #1
    jsr RR_COPY
    ldy ZP_I
    dec ZP_N
    bne @glyph
@blank:
    lda #$1F
    sta PPUADDR
    lda #$F0
    sta PPUADDR
    lda #0
    ldx #16
@zero:
    sta PPUDATA
    dex
    bne @zero
    rts

; A = store bank (0-3), X = pos: the glyph's 4 tiles at the PPU address
; (plane 0 the glyph, plane 1 blank).  The store at R7 with PRG_R7X set
; (an NMI's restore keeps it), R7 back to this bank's upper half after.
att_glyph:
    ora #STORE_8K
    sta PRG_R7X
    tay
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    sty MMC3_DATA
    stx ZP_G
    lda #>STORE_TAB
    sta ZP_G+1
    ldy #0
@tile:
    ldx #8
@row:
    lda (ZP_G),y
    sta PPUDATA
    inc ZP_G+1
    dex
    bne @row
    lda #0
    ldx #8
@plane1:
    sta PPUDATA
    dex
    bne @plane1
    lda ZP_G+1
    cmp #>STORE_TAB+32
    bne @tile
    lda #0
    sta PRG_R7X
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    lda #ATT_BANK*2+1
    sta MMC3_DATA
    rts
att_store_end:

; ======================================================================
; The RAM routines (copied to RAM_RR before each screen's uploads).
; ======================================================================
att_rr_install:
    ldx #0
@copy:
    lda att_rr_src,x
    sta RAM_RR,x
    inx
    cpx #RR_END-RR_COPY
    bne @copy
    rts

att_rr_src:
.base RAM_RR
; A = 16 KiB bank, (ZP_S) = X tiles of 8 bytes, the PPU address set:
; plane 0 from them, plane 1 blank (copy_to_vram's mode 4).
RR_COPY:
    jsr SET_BANK_B
    ldy #0
@tile:
    lda (ZP_S),y
    sta PPUDATA
    iny
    lda (ZP_S),y
    sta PPUDATA
    iny
    lda (ZP_S),y
    sta PPUDATA
    iny
    lda (ZP_S),y
    sta PPUDATA
    iny
    lda (ZP_S),y
    sta PPUDATA
    iny
    lda (ZP_S),y
    sta PPUDATA
    iny
    lda (ZP_S),y
    sta PPUDATA
    iny
    lda (ZP_S),y
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
    tya
    bne @next
    inc ZP_S+1
@next:
    dex
    bne @tile
    beq rr_back
; A = 16 KiB bank, (ZP_S) = 6 tiles of a portrait part (96 bytes), tile k
; to the PPU address ZP_D + 32 k.
RR_PART:
    jsr SET_BANK_B
    ldy #0
@tile:
    lda ZP_D+1
    sta PPUADDR
    lda ZP_D
    sta PPUADDR
@byte:
    lda (ZP_S),y
    sta PPUDATA
    iny
    tya
    and #$0F
    bne @byte
    lda ZP_D
    clc
    adc #32
    sta ZP_D
    bcc @next
    inc ZP_D+1
@next:
    cpy #96
    bne @tile
rr_back:
    lda #ATT_BANK
    jmp SET_BANK_B
RR_END:
.base att_rr_src + (RR_END - RR_COPY)
.if RR_END > $0700
    .error "the RAM routines leave the $0600 page"
.endif

; ======================================================================
; The attract mode (bank 7's b07_enter_party_screen .. b07_loc_9516).
; ======================================================================
att_attract:
    lda #<att_intro_clr         ; the title's text lines off (logo and TM stay)
    sta $00
    lda #>att_intro_clr
    sta $01
    jsr DRAW_STRING_PTR
    lda #60
    jsr att_delay
    lda #0
    sta map_y
    lda #ATT_NINTRO
    sta map_x
    jsr att_phrases
    lda #120
    jsr att_delay
    jsr att_fade_out
    lda #180
    jsr att_delay
    lda #0
    sta map_x2
att_screen:                     ; the portrait screens (b07_run)
    jsr SCREEN_OFF
    jsr att_rr_install
    lda #$AA
    jsr att_blank
    ldx map_x2
    inx
    jsr att_set
    jsr att_portraits
    lda #$F8
    sta SLIDE
    jsr att_place
    lda ppu_ctrl_shadow         ; 8x16 sprites on this screen
    ora #$20
    sta ppu_ctrl_shadow
    jsr att_palettes
    jsr SCREEN_ON
@slide:
    jsr att_place
    lda #1
    jsr att_delay
    lda SLIDE
    sec
    sbc #8
    sta SLIDE
    bne @slide
    jsr att_place
    lda #40
    jsr att_delay
    ldx map_x2
    lda att_nphr,x
    sta map_x
    jsr att_phrases
    lda #150
    jsr att_delay
    lda #150
    jsr att_delay
    jsr att_fade_out
    inc map_x2
    lda map_x2
    cmp #5
    bne att_screen
    ; the text screen (b07_loc_94DD)
    jsr SCREEN_OFF
    jsr att_sprites_off
    jsr att_rr_install
    lda #$AA
    jsr att_blank
    ldx #ATT_NSETS-1
    jsr att_set
    jsr SCREEN_ON
    lda #150
    jsr att_delay
    lda #150
    jsr att_delay
    lda #ATT_NFINAL
    sta map_x
    jsr att_phrases
    lda #150
    jsr att_delay
    lda #150
    jsr att_delay
    jsr att_fade_out
    lda #150
    jsr att_delay
    lda #150
    jsr att_delay
att_end:                        ; (b07_loc_9516; Start comes here too)
    jsr att_sprites_off
    lda #0
    sta loop_counter
    sta battle_flags
    jmp ENTER_STATUS_SCREEN

; A frames (b07_delay_frames): Start ends the attract mode.
att_delay:
    sta party_scan
@frame:
    jsr WAIT_VBLANK
    lda controller_prev
    and #$10
    bne @start
    dec party_scan
    bne @frame
    rts
@start:
    ldx #$2E
    txs
    jmp att_end

; map_x phrases from phrase map_y / 2 (b07_wait_and_draw): each queued,
; the palettes loaded, palette 2 faded in.
att_phrases:
    lda #40
    jsr att_delay
    ldy map_y
    lda att_phr,y
    sta $00
    lda att_phr+1,y
    sta $01
    iny
    iny
    sty map_y
    jsr DRAW_STRING_PTR
    jsr att_palettes
    lda #1
    sta KEEP_OAM
    lda #$FB
    sta FADE_MASK
    ldy #5
    jsr FADE_IN
    lda #40
    jsr att_delay
    dec map_x
    bne att_phrases
    rts

; The text set's palettes (load_text_graphics), sprite palette 0 = BG
; palette 3 (the portraits' colours).
att_palettes:
    lda #0
    sta FADE_MASK
    jsr LOAD_TEXT_GRAPHICS
    ldx #2
@copy:
    lda $03ED,x
    sta $03F1,x
    dex
    bpl @copy
    rts

att_fade_out:
    lda #1
    sta KEEP_OAM
    ldy #10
    jmp FADE_OUT

; Nametable $2000 blank, its attributes A (rendering off).
att_blank:
    pha
    lda PPUSTATUS
    lda #$20
    jsr att_nt_blank
    pla
    ldx #64
@attr:
    sta PPUDATA
    dex
    bne @attr
    rts

att_sprites_off:
    ldx #0
    lda #$F8
@hide:
    sta $0200,x
    inx
    inx
    inx
    inx
    bne @hide
    lda ppu_ctrl_shadow
    and #$DF
    sta ppu_ctrl_shadow
    rts

; ======================================================================
; Portraits of screen map_x2: the 6 parts of each to the sprite page, part
; R's tile c at tile 36 p + 12 (R >> 1) + 2 c + (R & 1) (8x16 pairs).
; ======================================================================
att_portraits:
    ldx map_x2
    lda att_por_n,x
    sta NPOR
    lda att_por_lo,x
    sta ZP_T
    lda att_por_hi,x
    sta ZP_T+1
    lda PPUSTATUS
    ldy #0
    sty ZP_P
@por:
    lda #0
    sta ZP_I
@part:
    ldx ZP_P
    lda att_pbase_lo,x
    ldx ZP_I
    clc
    adc att_roff_lo,x
    sta ZP_D
    ldx ZP_P
    lda att_pbase_hi,x
    ldx ZP_I
    adc att_roff_hi,x
    sta ZP_D+1
    lda (ZP_T),y
    pha
    iny
    lda (ZP_T),y
    sta ZP_S
    iny
    lda (ZP_T),y
    sta ZP_S+1
    iny
    sty ZP_N
    pla
    jsr RR_PART
    ldy ZP_N
    inc ZP_I
    lda ZP_I
    cmp #6
    bne @part
    inc ZP_P
    lda ZP_P
    cmp NPOR
    bne @por
    rts

att_pbase_lo:   .db <0, <576, <1152           ; 36 tiles a portrait
att_pbase_hi:   .db >0, >576, >1152
att_roff_lo:    .db <0, <16, <192, <208, <384, <400
att_roff_hi:    .db >0, >16, >192, >208, >384, >400

; The OAM shadow from SLIDE: band 1 and 3 at x = 16 + SLIDE (from the
; right), band 2 mirrored at x = 192 - SLIDE (from the left); a column past
; the screen's edge hidden; the sprites after the last portrait hidden.
att_place:
    ldx #0
    lda #0
    sta ZP_P
@por:
    lda ZP_P
    cmp NPOR
    bcs @rest
    lda #0
    sta ZP_I
@spr:
    ldy ZP_I
    lda ZP_P
    cmp #1
    beq @flip
    lda att_sdx,y
    clc
    adc #16
    adc SLIDE
    bcs @hide
    bcc @show
@flip:
    lda #232
    sec
    sbc att_sdx,y
    sec
    sbc SLIDE
    bcc @hide
@show:
    sta $0203,x
    ldy ZP_P
    lda att_top,y
    ldy ZP_I
    clc
    adc att_sdy,y
    sta $0200,x
    ldy ZP_P
    lda att_tbase,y
    ldy ZP_I
    clc
    adc att_sdt,y
    sta $0201,x
    ldy ZP_P
    lda att_attr,y
    sta $0202,x
    jmp @next
@hide:
    lda #$F8
    sta $0200,x
@next:
    inx
    inx
    inx
    inx
    inc ZP_I
    lda ZP_I
    cmp #18
    bne @spr
    inc ZP_P
    bne @por
@rest:
    lda #$F8
@off:
    sta $0200,x
    inx
    inx
    inx
    inx
    bne @off
    rts

; ======================================================================
; The title's logo intro (2026-11-14; TEXT_RENDERER.md "The title's logo
; intro by IRQ").  The logo's five tile rows (nametable rows 5-9) are
; shown as strips of 8 lines, each from its image line 42 + 8k, with blank
; lines between that close up as the intro runs; the screen above line 42
; and below strip 4 is the title as it stands.  Bank 13 steps $04 from 31
; to 0 every 4 frames; the original NMI drew the step's strips with
; cycle-counted waits (one picture per step, 15 a second).
;
; Here, every NMI: the progress u (frames to the end): u = 4 * step + 1 -
; f, f = the step's frame 1-4, but 0 at the intro's first NMI (bank 13's
; frame wait shows that frame with rendering off: u = 125); then 124 down
; to 0, one a frame, and 0 through the last step.  The spread G = 3u / 16
; lines (23.25 at u = 124: the original's 31 delay steps of 0.76 lines)
; and strip k's top line P = 42 + 8k + (k+1) G, rounded (tfx_p0-4, made
; by the assembler).  The blank lines above strip k start at E (42, or 8
; below strip k-1's top).  The events (title_irq, fixed bank):
;   - E = P: none (the strips touch: the nametable goes on);
;   - P - E >= 3: at line E - 3, $91 (the empty right-hand table from line
;     E on); at line P - 3, the $2006 pair in the hblank of line P - 1
;     (the strip from line P on), then PPUCTRL back;
;   - P - E = 1-2: both from one IRQ at line E - 3.
; Each IRQ reloads the counter for the next event first.  The arm, after
; the game's PPU work (v = $1000 first: no stray A12 rise before the
; pre-render line): latch 0, so event 0 ("stage 0", no writes) comes at
; the pre-render line's clock and reloads the counter in line 0 for the
; first real event, as the map renderer's stage 0 does.  That needs the
; NMI over well before the pre-render line: an NMI running into line 0
; holds stage 0 back, its reload misses line 0's clock and every event
; comes a line late (measured with a slower title_fx; hence the tables).
; The delays (title_irq's loops, 5 cycles a pass) are measured in Mesen:
; the $2006 write lands in dots 257-320, the $91 write near dot 85 of line
; E - 1 (its window: line E - 2's dot 257 to line E - 1's dot 256).
; ======================================================================
TFX_WE      = 11                ; IRQ line X: the $91 write in line X + 2, near dot 85
TFX_WS      = 20                ; IRQ line X: the $2006 write in line X + 2's hblank
TFX_WC1     = 31                ; after the $91 write: line X + 3's hblank (1 blank line)
TFX_WC2     = 54                ; line X + 4's hblank (2 blank lines)
TFX_TOP     = 42                ; strip 0's top line in the finished logo (image line 42)

title_fx:
    lda #0
    sta KANJI_IRQ_ST            ; (the title's IRQs pass irq_split to title_irq)
    sta TFX_I
    sta MMC3_IRQ_OFF            ; (nothing left from the frame before)
    sta TFX_W1                  ; event 0: stage 0, no writes
    sta TFX_W2
    lda $04                     ; the step, and its frame f (1-4; 0 at the
    cmp TFX_S                   ; first NMI: TFX_S = $FF from att_title_set)
    beq @same
    ldx TFX_S
    sta TFX_S
    lda #1
    inx
    bne @f
    lda #0
@f:
    sta TFX_P
    bpl @step                   ; (always)
@same:
    lda TFX_P
    cmp #4
    bcs @step
    inc TFX_P
@step:
    lda TFX_S
    cmp #32
    bcc @u
    lda #0                      ; (not a step: the finished logo)
@u:
    asl a
    asl a
    sec                         ; u = 4 * step + 1 - f
    sbc TFX_P
    bcc @end
    adc #0                      ; (C set: + 1)
    bcc @g                      ; (always: u <= 125)
@end:
    lda #0
@g:
    sta TFX_U
    tay
    lda #TFX_TOP
    sta TFX_E
    ldx #1                      ; the events: 0 is stage 0
    lda tfx_p0,y
    sta TFX_Q
    lda #0
    jsr tfx_strip
    lda tfx_p1,y
    sta TFX_Q
    lda #1
    jsr tfx_strip
    lda tfx_p2,y
    sta TFX_Q
    lda #2
    jsr tfx_strip
    lda tfx_p3,y
    sta TFX_Q
    lda #3
    jsr tfx_strip
    lda tfx_p4,y
    sta TFX_Q
    lda #4
    jsr tfx_strip
    stx TFX_N
    cpx #2
    bcc @none                   ; (no event: no IRQ)
    lda TFX_X+1                 ; stage 0's reload, consumed at line 0's
    sta TFX_L                   ; clock: the first event's line
    ldx #1
@rl:
    inx
    cpx TFX_N
    bcs @arm
    lda TFX_X,x                 ; the lines to the next event, less one
    clc
    sbc TFX_X-1,x
    sta TFX_L-1,x
    bcs @rl                     ; (always: the events ascend)
@arm:
    lda #0
    sta TFX_L-1,x               ; (the last event: none after it)
    bit PPUSTATUS               ; v = $1000 (A12 high into the pre-render
    lda #$10                    ; line), then t back for its copies
    sta PPUADDR
    lda #$00
    sta PPUADDR
    lda ppu_ctrl_shadow
    sta PPUCTRL
    lda scroll_x
    sta PPUSCROLL
    lda scroll_y
    sta PPUSCROLL
    lda #0                      ; stage 0 at the pre-render line's clock
    sta MMC3_IRQ_LATCH
    sta MMC3_IRQ_RELOAD
    sta MMC3_IRQ_ON
@none:
    rts

; Strip A (top line TFX_Q) into the events from X; E then 8 below it.
; Y = TFX_U again on return.
tfx_strip:
    sta TFX_K
    lda TFX_Q
    sec
    sbc TFX_E                   ; the blank lines above it
    beq @next
    ldy TFX_K
    cmp #3
    bcs @two
    cmp #2                      ; 1-2: one event at line E - 3
    lda #TFX_WC1
    bcc @w2
    lda #TFX_WC2
@w2:
    sta TFX_W2,x
    lda TFX_E
    sec
    sbc #3
    sta TFX_X,x
    lda #TFX_WE
    sta TFX_W1,x
    bne @addr                   ; (always)
@two:
    lda TFX_E                   ; the blank start: line E - 3
    sbc #3                      ; (C set)
    sta TFX_X,x
    lda #TFX_WE
    sta TFX_W1,x
    lda #0
    sta TFX_W2,x
    inx
    lda TFX_Q                   ; the strip: line P - 3
    sec
    sbc #3
    sta TFX_X,x
    lda #0
    sta TFX_W1,x
    lda #TFX_WS
    sta TFX_W2,x
@addr:
    lda tfx_hi,y                ; the $2006 pair: nametable row 5 + k, fine Y
    sta TFX_A,x                 ; 2 (the original's data_EF8A / data_EF8F)
    lda tfx_lo,y
    sta TFX_B,x
    inx
@next:
    lda TFX_Q
    clc
    adc #8
    sta TFX_E
    ldy TFX_U
    rts

tfx_hi:     .db $20, $20, $20, $21, $21
tfx_lo:     .db $A0, $C0, $E0, $00, $20
; P_k(u) = 42 + 8k + round((k+1) * 3u / 16), u = 0-125
TFX_UV = 0
tfx_p0:
.rept 126
    .db TFX_TOP + ((1 * 3 * TFX_UV + 8) >> 4)
TFX_UV = TFX_UV + 1
.endr
TFX_UV = 0
tfx_p1:
.rept 126
    .db TFX_TOP + 8 + ((2 * 3 * TFX_UV + 8) >> 4)
TFX_UV = TFX_UV + 1
.endr
TFX_UV = 0
tfx_p2:
.rept 126
    .db TFX_TOP + 16 + ((3 * 3 * TFX_UV + 8) >> 4)
TFX_UV = TFX_UV + 1
.endr
TFX_UV = 0
tfx_p3:
.rept 126
    .db TFX_TOP + 24 + ((4 * 3 * TFX_UV + 8) >> 4)
TFX_UV = TFX_UV + 1
.endr
TFX_UV = 0
tfx_p4:
.rept 126
    .db TFX_TOP + 32 + ((5 * 3 * TFX_UV + 8) >> 4)
TFX_UV = TFX_UV + 1
.endr
.if $ > $A000
    .error "title_fx must stay in the bank's first half (the NMI maps it alone)"
.endif

att_top:    .db 31, 95, 159                     ; band tops - 1 (OAM Y)
att_tbase:  .db 0, 36, 72
att_attr:   .db $00, $40, $00                   ; band 2: H-flip
att_sdx:    .db 0, 8, 16, 24, 32, 40,  0, 8, 16, 24, 32, 40,  0, 8, 16, 24, 32, 40
att_sdy:    .db 0, 0, 0, 0, 0, 0,  16, 16, 16, 16, 16, 16,  32, 32, 32, 32, 32, 32
att_sdt:    .db 0, 2, 4, 6, 8, 10,  12, 14, 16, 18, 20, 22,  24, 26, 28, 30, 32, 34

.include "../../decomp/build/kanji/attract_lo.inc"
att_lo_end:
.if att_store_end > $A000
    .error "the kanji store reader is past $9FFF"
.endif
.if att_lo_end > $A000
    .error "the lower half is full"
.endif

.org $A000
.include "../../decomp/build/kanji/attract_hi.inc"
att_hi_end:
.if att_hi_end > $C000
    .error "bank 24 is full"
.endif
