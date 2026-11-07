; ======================================================================
; Kanji-target RAM, font and text-runtime constants
; ======================================================================

; SRAM (battery-backed PRG RAM) map.  The original game's highest static
; reference is $6780; $6800-$7FFF is unused by the base game.  Everything
; here must stay inside that audited range.
;
;   $6800-$68FF  scratch/staging (glyph, expanded tiles, counters, dirty map)
;   $6900-$69FF  runtime page allocation and CHR scan scratch
;   $6A00-$6DFF  1 KiB copy of the bank-9 kana font (128 x 8 bytes)
;   $6E00-$6FFF  per-message page-record buffer (max 512 bytes)
;   $7000-$7001  overlay signature word ("KO")
;   $7002-$7FFF  RAM-resident text-engine overlay (up to 3070 bytes)
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
KANJI_RESIDENT    = $68A0   ; 16-byte bitmap (1 = CHR tile currently holds kana)
KANJI_SCAN_POS    = $68C0
KANJI_SCAN_ACTIVE = $68C1
KANJI_SCAN_DONE   = $68C2
KANJI_SCAN_TILE   = $68C3
KANJI_SCAN_BUF    = $68D0   ; 16-byte NMI scratch: one CHR tile
KANJI_NMI0        = $68E0   ; NMI-only scratch (main-thread TMPs stay live)
KANJI_NMI1        = $68E1
KANJI_NMI2        = $68E2
KANJI_NMI3        = $68E3
KANJI_NMI4        = $68E4
KANJI_VRAM_POS    = $68E5   ; 2 bytes: nametable scan offset ($0000-$03FF)
KANJI_VRAM_ACTIVE = $68E7
KANJI_VRAM_DONE   = $68E8

KANJI_PAGE        = $6920   ; runtime page: count + count*6 (code,t0..t3)
KANJI_PAGE_USED   = $69F0   ; 16-byte bitmap of text/menu tiles reserved
KANJI_PAGE_I      = $68C4
KANJI_PAGE_OFF    = $68C5
KANJI_PAGE_EPTR   = $68C6
KANJI_PAGE_ALLOC  = $68C7
KANJI_PAGE_SCAN   = $68C8
KANJI_PAGES_LEFT  = $68C9
KANJI_RESTORE_POS = $68CA
KANJI_DIRTY_ANY   = $68CB
KANJI_NMI_DONE    = $68CC
; $68F0-$68FF is reused: KANJI_SCREEN while a message is open,
; KANJI_VISIBLE at message exit (the two lifetimes do not overlap).
KANJI_SCREEN      = $68F0   ; 16-byte bitmap of tiles visible in the nametable
KANJI_VISIBLE     = $68F0   ; 16-byte bitmap built from the text buffers

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
KANJI_OVERLAY_SIZE = $0C00  ; bytes copied from bank 24 $8000-$8BFF
KANA_SIG0         = $4B     ; 'K'
KANA_SIG1         = $41     ; 'A'

; Fixed-bank text engine entry points (bank 15/31).
TEXT_RETURN       = $D285
TEXT_LINE_LOOP    = $D250
TEXT_NORMAL_CHAR  = $D2B7
TEXT_CTRL_STORE   = $D2C7
TEXT_PUT_TILE     = $D340
TEXT_DRAW_CHAR    = $D456
TEXT_REDRAW_LINES = $D405
TEXT_FAR_STUB     = $C63A
SET_BANK_B        = $C482
WRITE_PRG_BANK    = $C4B7
FLUSH_PALETTE     = $C2FF
WAIT_VBLANK       = $C09F
CALL_INLINE_BLOCK = $C4E4

; Overlay entry points are labels in tools/asm/kanji_fixed.asm.  Do not
; define them here: ASM6f would substitute the constant instead of the label.
