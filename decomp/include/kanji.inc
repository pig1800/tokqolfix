; ======================================================================
; Kanji-target RAM, font and text-runtime constants
; ======================================================================

; SRAM (battery-backed PRG RAM) scratch area.  The original game's highest
; static save reference is below $6800; this block is audited separately.
KANJI_GLYPH       = $6800   ; 32 bytes: one 1bpp glyph
KANJI_STAGE       = $6820   ; 64 bytes: four expanded 2bpp tiles
KANJI_CODE_LO     = $6860
KANJI_CODE_HI     = $6861
KANJI_ESCAPE      = $6862
KANJI_BASE        = $6863
KANJI_TEXT_BANK   = $6864
KANJI_CHR_FLAG    = $6865
KANJI_CHR_COUNT   = $6866
KANJI_CHR_TILES   = $6867   ; 4 tile numbers (0-127)
KANJI_META_PTR    = $686B   ; 2 bytes (points into $6E00)
KANJI_TMP0        = $686D
KANJI_TMP1        = $686E
KANJI_TMP2        = $686F
KANJI_TMP3        = $6870
KANJI_SRC         = $6871   ; 2 bytes
KANJI_DST         = $6873
KANJI_COUNT       = $6874
KANJI_BUFX        = $6875
KANJI_DIRTY       = $6880   ; 16-byte bitmap (1 = CHR tile was overwritten)
KANJI_KANA_READY  = $6890
KANA_FONT         = $6A00   ; 1 KiB copy of bank 9 $BA00-$BDFF
KANJI_META        = $6E00   ; copied per-message page records (2 KiB)

; Fixed-bank text engine entry points (bank 15/31).
TEXT_RETURN       = $D285
TEXT_LINE_LOOP    = $D250
TEXT_NORMAL_CHAR  = $D2B7
TEXT_CTRL_STORE   = $D2C7
TEXT_PUT_TILE     = $D340
TEXT_DRAW_CHAR    = $D456
SET_BANK_B        = $C482
WRITE_PRG_BANK    = $C4B7
FLUSH_PALETTE     = $C2FF
CALL_INLINE_BLOCK = $C4E4

; Overlay entry points are labels in tools/asm/kanji_fixed.asm.  Do not
; define them here: ASM6f would substitute the constant instead of the label.
