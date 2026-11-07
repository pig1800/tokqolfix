; ======================================================================
; Kanji-target RAM, font and text-runtime constants (revision 9)
; ======================================================================
;
; Battery-backed PRG RAM ($6000-$7FFF) belongs entirely to the game and is
; never touched by this hack: the three history books cover $6000-$7FFF.
;
; All hack state lives in internal RAM ranges that the original game clears
; at boot and never uses afterwards (audited with tools/lua/iram_audit.lua):
;
;   $0131-$013F  persistent text-engine state (fifteen bytes)
;   $0140-$0157  RAM-resident font-copy stub (installed per message)
;   $0158-$015F  RAM band trampoline (scene page, then delay loop)
;   $0160-$016F  one 16-byte half-glyph buffer (or 8-byte kana row)
;   $0170-$017E  RAM band delay loop
;   $01E0-$01E7  scratch for the overlay and the stub
;   $01E8-$01EB  band state (ready, on, NMI lock)
;
; The overlay code itself is ROM-resident: it is assembled once for $B800
; and included identically in every text bank (18-22).  The CHR page layout
; is: page 0 sprites, page 1 scene, page 2 text band (kana $00-$7F and a
; 32-glyph kanji cache in $80-$FF).
KANJI_TEXT_BANK   = $0131
KANJI_TEXT_ADDR   = $0132   ; 2 bytes
KANJI_PAGE_PTR    = $0134   ; 2 bytes: current page record in the text bank
KANJI_CODE_LO     = $0136
KANJI_CODE_HI     = $0137
KANJI_PAGES_LEFT  = $0138
KANJI_ENTRY       = $0139   ; entry index within the current page (0-15)
KANJI_TILES       = $013A   ; 4 tile numbers
KANJI_UPLOADED    = $013E   ; 2-byte bitmap: page entry glyph is in CHR

KANJI_STUB        = $0140   ; 24 bytes: RAM font-copy stub
KANJI_BAND_RAM    = $0158   ; 8 bytes: scene page write + jmp delay loop
KANJI_GLYPH       = $0160   ; 16 bytes: one half-glyph / one kana row
KANJI_BAND_WAIT   = $0170   ; 14 bytes: calibrated band switch delay
KANJI_CELL_CHECK  = $01EC   ; 6 bytes: high-tile control test for the renderer
KANJI_CELL_CHECK_X = $01F2  ; 6 bytes: high-tile test for text_redraw_lines

KANJI_SRC_BANK    = $01E0   ; stub: source PRG bank
KANJI_SRC_COUNT   = $01E1   ; stub: bytes to copy (1-32)
KANJI_TMP0        = $01E2
KANJI_TMP1        = $01E3
KANJI_TMP2        = $01E4
KANJI_TMP3        = $01E5
KANJI_BUFX        = $01E6
KANJI_Q           = $01E7   ; upload tile index 0-3

KANJI_BAND_READY  = $01E8   ; band page filled for this power-on
KANJI_BAND_ON     = $01E9   ; message open; NMI mid-frame switch enabled
KANJI_NMI_LOCK    = $01EA   ; partial MMC1 serial sequence in progress

KANA_FONT         = $BA00   ; bank 9, 128 rows of 8 bytes
KANA_FONT_BANK    = 9
KANJI_OVERLAY     = $B800   ; CPU address in every text bank
KANJI_TEXT_BANKS  = 18      ; banks 18-22 are generated text/metadata banks

; Fixed-bank text engine entry points (bank 15/31).
TEXT_RETURN       = $D285
TEXT_LINE_LOOP    = $D250
TEXT_NORMAL_CHAR  = $D2B7
TEXT_CTRL_STORE   = $D2C7
TEXT_PUT_TILE     = $D340
TEXT_DRAW_CHAR    = $D456
TEXT_REDRAW_LINES = $D405
TEXT_FAR_STUB     = $BF00
SET_BANK_B        = $C482
SET_BANK_CURRENT  = $C47E
SET_BANK_13       = $C4A2
SET_BANK_14       = $C4A6
WRITE_PRG_BANK    = $C4B7
FLUSH_PALETTE     = $C2FF
WAIT_VBLANK       = $C09F
PPU_NMI_ON        = $C0FC
CALL_INLINE_BLOCK = $C4E4
