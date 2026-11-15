; ======================================================================
; The info screen's Left / Right (ui_info.asm): the code that maps other
; 8 KiB banks at R7, so it stays in $8000-$9FFF (ui.asm includes it
; before ui_data.inc).  is_gl maps the kanji store through MMC3_SEL and
; PRG_R7X (an NMI's restore keeps it): safe with the NMI on (the first
; page) and off (a flip's windows); is_rec and is_prd keep it off.
; ======================================================================

P1_N        = 27                ; plane-1 slots (the tactics' kanji)
P0_N        = 22                ; plane-0 slots (the equipment's kanji, 計)
IS_WMAX     = 5                 ; windows a flip may take (4 at most)

; Zero page ($00-$0F, the game's per-call scratch).  A window's:
ZP_GH       = $00               ; is_gl: the PPU address, high
ZP_GL       = $01               ;   its low byte (the first tile's plane)
ZP_GB       = $02               ;   the store's 8 KiB bank
ZP_GI       = $03               ; is_glyphs: the item
ZP_GE       = $04               ;   the window's end
ZP_PM       = $05               ; is_portrait: the parts left
ZP_DH       = $06               ; is_delay: 256-cycle blocks
ZP_DQ       = $07               ;   5-cycle passes
ZP_RV       = $08               ;   2: the remainder's routine
ZP_PT       = $0A               ; the window has the portrait
ZP_CM       = $0B               ;   the image
ZP_MK       = $0C               ;   PPUMASK from line 32
; the glyph passes':
BP_F        = $06               ; 2: the pool's slot flags
BP_C        = $08               ; 2: its glyphs (IS_P1G / IS_P0G)
BP_N        = $0A               ; its slots

; The flip's scratch: the OAM shadow (every sprite hidden on this screen;
; busy mode keeps the NMI's DMA off it; is_oam hides it again), and the
; image of the cells at $0600 (call_inline_block's page: free between game
; calls).
IMG         = $0600             ; 254 (ui_info.asm IM_*)
GI_H        = $0200             ; 28: glyph item i: its PPU address, high
GI_L        = GI_H+28           ;   low (the plane's first byte)
GI_B        = GI_L+28           ;   the store's 8 KiB bank
GI_P        = GI_B+28           ;   the glyph's pos
VL_G        = GI_H              ; 28: is_collect's list (before the items): the glyph
VL_P        = GI_L              ;   its pool (1: plane 1)
VL_S        = GI_B              ;   its slot
FL1         = GI_P+28           ; P1_N: plane-1 slot flags (F_*)
FL0         = FL1+P1_N          ; P0_N: plane-0 slot flags (FL1's next: one clear)
IS_REC      = FL0+P0_N          ; 16: the officer record's bytes $0A-$19
WIN_GS      = IS_REC+16         ; IS_WMAX each: a window's first item
WIN_GE      = WIN_GS+IS_WMAX    ;   its end
WIN_PT      = WIN_GE+IS_WMAX    ;   the portrait in it
WIN_CM      = WIN_PT+IS_WMAX    ;   the image in it
WIN_DH      = WIN_CM+IS_WMAX    ;   its delay: ZP_DH
WIN_DQ      = WIN_DH+IS_WMAX    ;   ZP_DQ
WIN_RV      = WIN_DQ+IS_WMAX    ;   ZP_RV's low byte
NMB_T       = WIN_RV+IS_WMAX    ; 3: the name's kanji k: the store's 8 KiB bank
NMP_T       = NMB_T+3           ; 3:   its pos
IS_INIT     = NMP_T+3           ; 1: the first page (the portrait is the game's)
IS_OFF      = IS_INIT+1         ; the officer (record)
NM_N        = IS_OFF+1          ; the name's kanji
VL_N        = NM_N+1            ; is_collect: glyphs in the list
IS_VI       = VL_N+1            ; im_glyphs: the list's next
IS_CTL      = IS_VI+1           ; is_unmap7: PPUCTRL (the NMI on, or off in the windows)
IS_EQN      = IS_CTL+1          ; eq_*: items so far
IS_EQS      = IS_EQN+1          ;   the next slot
IS_TOK      = IS_EQS+1          ;   the item name's next byte
IS_EQX      = IS_TOK+1          ; im_glyphs: the line's first cell
IS_EQC      = IS_EQX+1          ;   its column
NPART       = IS_EQC+1          ; the portrait parts to send (bit p)
NPN         = NPART+1           ;   how many
IS_PTF      = NPN+1             ; the portrait (colours, parts) to send
IS_CI       = IS_PTF+1          ; its colour index
GI_N        = IS_CI+1           ; glyph items
N_MAND      = GI_N+1            ;   the image's window's (the last ones)
WIN_N       = N_MAND+1          ; windows
IS_W        = WIN_N+1           ; the window
IS_PC       = IS_W+1            ; is_plan: the portrait in the last window
IS_CL       = IS_PC+1           ;   the last window's glyphs
IS_R        = IS_CL+1           ;   glyphs left for the others
IS_GS       = IS_R+1            ;   the next item
IS_WP       = IS_GS+1           ;   @win: the portrait
IS_WC       = IS_WP+1           ;   the image
IS_TR_END   = IS_WC+1
.if IS_TR_END > $0300
    .error "the info flip's scratch is over the OAM shadow"
.endif

; ----------------------------------------------------------------------
; is_gl: a glyph of the kanji store to one plane of a group's 4 tiles
; (8x16 order).  ZP_GH / ZP_GL: the PPU address of the first tile's plane
; (tile k's is 16 k further: a group never crosses a 16-tile row), ZP_GB:
; the store's 8 KiB bank, Y: the glyph's pos.  Rendering off, +1.
; IS_C_GL cycles from the jsr to the rts's end, always: no branch, and
; the store's byte rows are page-aligned (no indexed read crosses a
; page).  A, X lost; Y kept.
; ----------------------------------------------------------------------
IS_C_GL     = 371

is_gl:
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    lda ZP_GB
    sta PRG_R7X
    sta MMC3_DATA
    ldx ZP_GL
    lda ZP_GH
    sta PPUADDR
    stx PPUADDR
IS_GR = 0
.rept 8
    lda STORE_TAB+$100*IS_GR,y
    sta PPUDATA
IS_GR = IS_GR + 1
.endr
    txa
    clc
    adc #16
    tax
    lda ZP_GH
    sta PPUADDR
    stx PPUADDR
IS_GR = 8
.rept 8
    lda STORE_TAB+$100*IS_GR,y
    sta PPUDATA
IS_GR = IS_GR + 1
.endr
    txa
    clc
    adc #16
    tax
    lda ZP_GH
    sta PPUADDR
    stx PPUADDR
IS_GR = 16
.rept 8
    lda STORE_TAB+$100*IS_GR,y
    sta PPUDATA
IS_GR = IS_GR + 1
.endr
    txa
    clc
    adc #16
    tax
    lda ZP_GH
    sta PPUADDR
    stx PPUADDR
IS_GR = 24
.rept 8
    lda STORE_TAB+$100*IS_GR,y
    sta PPUDATA
IS_GR = IS_GR + 1
.endr
    lda #0
    sta PRG_R7X
    lda #UI_BANK*2+1
    sta MMC3_DATA
    rts

; A = an 8 KiB bank to R7, the NMI off: the NMI's restore keeps PRG_R7X
; only for a store bank or a text chunk, and these are other banks (the
; portraits', bank 12's).  A vblank that starts meanwhile keeps its flag
; set, so its NMI comes when is_unmap7 turns it on again (the reads take
; well under the vblank's 20 lines).
is_map7:
    tax
    lda ppu_ctrl_shadow
    and #$7B                    ; NMI off, +1
    sta PPUCTRL
    lda #MMC3_R7
    sta MMC3_SEL
    sta MMC3_SELECT
    stx MMC3_DATA
    rts

; R7 back to this bank's upper half, PPUCTRL = IS_CTL (the NMI on; off in
; a flip's windows, which run the NMI's work themselves).
is_unmap7:
    M_STUNMAP
    lda IS_CTL
    sta PPUCTRL
    rts

; ----------------------------------------------------------------------
; is_rec: officer record A (bank 12: its address at $A800 / $A900 + the
; officer; the table is in the bank's upper 8 KiB, 8 KiB bank 25, and so
; is every officer's record) to IS_REC: its bytes $0A-$19 (portrait parts
; 0-5, the colours, 3 bytes, the kana name).  ZP_PTR lost.
; ----------------------------------------------------------------------
is_rec:
    pha
    lda #25
    jsr is_map7
    pla
    tay
    lda $A800,y
    sta ZP_PTR
    lda $A900,y
    sta ZP_PTR+1
    cmp #$A0
    bcs @hi
    adc #$20                    ; (C clear) a record in the lower 8 KiB
    sta ZP_PTR+1
    lda #24
    jsr is_map7
@hi:
    ldy #$0A
@c:
    lda (ZP_PTR),y
    sta IS_REC-$0A,y
    iny
    cpy #$1A
    bne @c
    jmp is_unmap7

; ----------------------------------------------------------------------
; is_prd: portrait part A (the record's byte: bit 7 bank 3, else bank 2;
; low 7 bits n: 96 bytes at $8800 + 96 n, 6 tiles) to the buffer at ZP_A.
; No part crosses the banks' 8 KiB halves ($8800 + 96 * 64 = $A000).
; ZP_PTR, ZP_T lost.
; ----------------------------------------------------------------------
is_prd:
    pha
    and #$7F
    sta ZP_T
    lda #0
    sta ZP_PTR+1
    lda ZP_T
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1
    asl a
    rol ZP_PTR+1                ; 32 n
    sta ZP_PTR
    asl a
    sta ZP_T                    ; (64 n, low)
    lda ZP_PTR+1
    rol a                       ; (64 n, high)
    tax
    lda ZP_PTR
    clc
    adc ZP_T
    sta ZP_PTR
    txa
    adc ZP_PTR+1
    adc #$08                    ; offset $0800 + 96 n in the 16 KiB bank
    sta ZP_PTR+1
    pla
    asl a                       ; C = bit 7: bank 3
    lda #4                      ; (8 KiB banks 4 / 6: the lower halves)
    bcc @b2
    lda #6
@b2:
    sta ZP_T
    lda ZP_PTR+1
    cmp #$20
    bcc @lo
    sbc #$20                    ; (C set) the upper half
    inc ZP_T
@lo:
    ora #$A0                    ; at R7
    sta ZP_PTR+1
    lda ZP_T
    jsr is_map7
    ldy #0
@c:
    lda (ZP_PTR),y
    sta (ZP_A),y
    iny
    cpy #96
    bne @c
    jmp is_unmap7

.if $ > STORE_TAB
    .error "ui_info_lo: past $9FFF (it maps other banks at R7)"
.endif
