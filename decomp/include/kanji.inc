; ======================================================================
; Kanji-target RAM, font and text-runtime constants (revision 10)
; ======================================================================
;
; Battery-backed PRG RAM ($6000-$7FFF) belongs entirely to the game and is
; never touched by this hack.
;
; All hack state lives in internal RAM:
;
;   $0131-$013F  text-engine state (fifteen bytes, as revision 9)
;   $0140-$014F  request / NMI / band state
;   $0150-$015F  sixteen-byte tile copy buffer
;   $0160-$016F  unused (kept free)
;   $0170-$017F  active-kanji bitmap A (128 tiles)
;   $01E0-$01EB  overlay/upload scratch
;
; There is no hack code in RAM and nothing in the stack pages
; ($0100-$0130, $01EC-$01FF).
;
; CHR page layout: page 0 sprites, page 1 scene, page 2 band shadow.
; The band page is a copy of page 1 except for the tiles in A.

KANJI_TEXT_BANK   = $0131
KANJI_TEXT_ADDR   = $0132   ; 2 bytes
KANJI_PAGE_PTR    = $0134   ; 2 bytes: current page record in the text bank
KANJI_CODE_LO     = $0136
KANJI_CODE_HI     = $0137
KANJI_PAGES_LEFT  = $0138
KANJI_ENTRY       = $0139   ; entry index within the current page (0-15)
KANJI_TILES       = $013A   ; 4 tile numbers
KANJI_UPLOADED    = $013E   ; 2-byte bitmap: page entry glyph is in CHR

KANJI_REQ_FLAG    = $0140   ; 1 = a glyph upload request is pending (tiles in KANJI_TILES)
KANJI_SHADOW_CUR  = $0148   ; resync cursor 0-127
KANJI_PAGE1_DIRTY = $0149   ; scene CHR changed since the last resync
KANJI_IN_NMI      = $014A   ; 1 while the NMI entry/band code runs
KANJI_FN          = $014B   ; call_hack function number
KANJI_BAND_ON     = $014D   ; band page visible / shadow required
KANJI_BAND_EXIT   = $014E   ; 1 = sprite hit, 2 = bounded poll
KANJI_MSG_OPEN    = $014F   ; 1 while a message stream is open
KANJI_REG1_TMP    = $0145   ; CHR register 1 value for the overlay helper
KANJI_SAVED_SP    = $0146   ; task stack pointer saved across the sync
KANJI_GLYPH_BUF   = $0150   ; 16-byte page-1 tile copy buffer

KANJI_A_BITS      = $0170   ; 16-byte active-kanji tile bitmap

; NMI-side scratch (below every task stack, never touched by the game).
KANJI_TMP0        = $010C
KANJI_TMP1        = $010D
KANJI_TMP2        = $010E
KANJI_TMP3        = $010F

; Overlay-side scratch (never used by the NMI hack code).
KANJI_OVL0        = $0100
KANJI_OVL1        = $0101
KANJI_OVL2        = $0102
KANJI_OVL3        = $0103
KANJI_BUFX        = $010B

KANA_FONT_BANK    = 9
KANJI_TEXT_BANKS  = 18      ; banks 18-22 are generated text/metadata banks
KANJI_HACK_BANKS  = 23      ; banks 23-24 hold identical code + glyph data
KANJI_GLYPH_BASE  = $8800   ; per-bank glyph bytes (after 2 KiB of code)
KANJI_GLYPHS_PER_BANK = 359

; Fixed-bank entry points (bank 15/31).
TEXT_RETURN       = $D285
TEXT_LINE_LOOP    = $D250
TEXT_NORMAL_CHAR  = $D2B7
TEXT_CTRL_STORE   = $D2C7
TEXT_DRAW_CHAR    = $D456
TEXT_REDRAW_LINES = $D405
TEXT_SAVE_TILES   = $CF5B
TEXT_HIDE         = $CC81
SET_BANK_B        = $C482
SET_BANK_CURRENT  = $C47E
SET_BANK_LOCK     = $C484
RESTORE_BANK_AFTER_NMI = $C4AA
SET_BANK_13       = $C4A2
SET_BANK_14       = $C4A6
WRITE_PRG_BANK    = $C4B7
FLUSH_PALETTE     = $C2FF
WAIT_VBLANK       = $C09F
PPU_NMI_OFF       = $C0F2
PPU_NMI_ON        = $C0FC
; CALL_HACK comes from build/kanji/fixed_hooks.inc (generated each build).
CALL_HACK_FN_ENTRY = 0
CALL_HACK_FN_BAND  = 1
CALL_HACK_FN_SCENE = 2
CALL_HACK_FN_SYNC  = 3
CALL_HACK_FN_RESET = 4
CALL_HACK_FN_GLYPH = 5
CALL_HACK_FN_PAGE2 = 6
CALL_HACK_FN_PAGE1 = 7
