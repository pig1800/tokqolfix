; ======================================================================
; Kanji-target RAM, font and text-runtime constants
; ======================================================================

; SRAM (battery-backed PRG RAM) map.  The original game's highest static
; reference is $6780; $6800-$7FFF is unused by the base game.  Everything
; here must stay inside that audited range.
;
;   $6800-$68FF  scratch/staging (glyph, expanded tiles, counters, dirty map)
;   $6900-$69FF  unused guard gap
;   $6A00-$6DFF  1 KiB copy of the bank-9 kana font (128 x 8 bytes)
;   $6E00-$6FFF  per-message page-record buffer (max 512 bytes)
;   $7000-$7001  overlay signature word ("KO")
;   $7002-$73FF  RAM-resident text-engine overlay (executes from PRG RAM)
;   $7400-$7FFF  free
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
KANJI_KANA_READY  = $6890   ; 2-byte signature: kana font copy is valid

KANA_FONT         = $6A00   ; 1 KiB copy of bank 9 $BA00-$BDFF
KANJI_META        = $6E00   ; per-message page records (max 512 bytes)

; Overlay signature and source.  The overlay is copied out of bank 24 by the
; far loader on the first message after power-on (or whenever the signature
; is wrong, e.g. after random-RAM power-on).
KANJI_SIGNATURE   = $7000
KANJI_SIG0        = $4B     ; 'K'
KANJI_SIG1        = $4F     ; 'O'
KANJI_OVERLAY     = $7002
KANJI_OVERLAY_BANK = 24
KANJI_OVERLAY_SRC = $8000
KANJI_OVERLAY_SIZE = $0400  ; bytes copied from bank 24 $8000-$83FF
KANA_SIG0         = $4B     ; 'K'
KANA_SIG1         = $41     ; 'A'

; Fixed-bank text engine entry points (bank 15/31).
TEXT_RETURN       = $D285
TEXT_LINE_LOOP    = $D250
TEXT_NORMAL_CHAR  = $D2B7
TEXT_CTRL_STORE   = $D2C7
TEXT_PUT_TILE     = $D340
TEXT_DRAW_CHAR    = $D456
TEXT_FAR_STUB     = $C63A
SET_BANK_B        = $C482
WRITE_PRG_BANK    = $C4B7
FLUSH_PALETTE     = $C2FF
CALL_INLINE_BLOCK = $C4E4

; Overlay entry points are labels in tools/asm/kanji_fixed.asm.  Do not
; define them here: ASM6f would substitute the constant instead of the label.
