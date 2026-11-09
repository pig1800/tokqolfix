; ======================================================================
; Kanji-target RAM, font and text-runtime constants (revision 11)
; ======================================================================
;
; Battery-backed PRG RAM ($6000-$7FFF) belongs entirely to the game and is
; never touched by this hack.
;
; Persistent hack state lives only in $0131-$017F.  That range sits between
; the text task's stack (top $0130) and the engine's saved tile rows
; ($0180-$01DF), so no stack can ever reach it.  $0102-$0103 are overlay /
; main-thread scratch that is never live across a yield or an NMI.
; $0100/$0101 belong to the game (bank-14 item code keeps a flag and a
; chest index there across a message; revision 16c moved the overlay's
; scratch off them).  Nothing is stored in $0104-$0130 (task stacks and
; number scratch) or in $01E0-$01FF (main stack and its overflow margin).
; There is no RAM code.
;
; CHR (16 KiB RAM, 4 KiB mode): page 0 sprites, page 1 scene, page 2 band.
; Page 2 is kept equal to page 1 except for the tiles in KANJI_STALE; the
; NMI selects page 2 from the dialogue window's top border to the bottom
; of the frame (sprite-0 sync) while KANJI_BAND is set.

KANJI_TEXT_BANK   = $0131
KANJI_TEXT_ADDR   = $0132   ; 2 bytes (consumed at overlay entry)
KANJI_PAGE_PTR    = $0134   ; 2 bytes: current page record in the text bank
KANJI_CODE_LO     = $0136   ; upload request: glyph index 0-717
KANJI_CODE_HI     = $0137
KANJI_PAGES_LEFT  = $0138   ; bit 7: page start pending, bit 6: PAGE_POOL
KANJI_BUFX        = $0139
KANJI_TILES       = $013A   ; 4 tile numbers (upload request / current kanji)
KANJI_UPLOADED    = $013E   ; 2-byte bitmap: page entry glyph is in CHR page 2

KANJI_A           = $0140   ; 16 bytes: active kanji tiles (lower 128)
KANJI_STALE       = $0150   ; 16 bytes: lower tiles where page 2 != page 1
KANJI_STALE_HI    = $0160   ; 4 bytes: upper tiles, one bit per 4 tiles
KANJI_BUF         = $0164   ; 16 bytes: CHR read-back buffer (NMI scratch outside
                            ; restore_tile: nt_check +0..+4, queue_scan +14, mark_stale +15)

KANJI_REQ         = $0174   ; request to the NMI (see REQ_* below)
KANJI_SPR0        = $0175   ; sprite 0 state: the vertical scroll it was placed
                            ; for (0-239); SPR0_STALE: place it again; SPR0_DIRTY:
                            ; page-0 tile $FF may have been overwritten
KANJI_BAND        = $0176   ; 1 = band page shown below the window border
KANJI_WIN_ROW     = $0177   ; window top-border nametable row (0-29)
KANJI_WIN_COL     = $0178   ; window left column 0-31, +$20 for nametable 1;
                            ; bits 6-7 pool state (WINCOL_*; readers mask)
KANJI_QPOS        = $0179   ; VRAM queue position already scanned
KANJI_LAST39      = $017A   ; last seen CHR-animation pointer ($39)
KANJI_NFLAGS      = $017B   ; FLAG_* bits, written by the NMI only
KANJI_FN          = $017C   ; call_hack function number
KANJI_PICK        = $017C   ; between NMIs: next tile to restore ($FF none);
                            ; shares KANJI_FN, every pick is re-validated
KANJI_T0          = $017D   ; NMI-context scratch
KANJI_T1          = $017E
KANJI_T2          = $017F

; Main-thread scratch (overlay and main-context hack calls only; never live
; across a yield).  KANJI_MAINCHR is set while main-thread hack code has
; the band page selected, so a busy-mode NMI leaves CHR register 1 alone.
KANJI_M0          = $0132   ; = KANJI_TEXT_ADDR, consumed at overlay entry
KANJI_M1          = $0133   ;   (M0/M1 is also the dispatcher's jump vector)
KANJI_M2          = $0102
KANJI_MAINCHR     = $0103

REQ_NONE          = 0
REQ_UPLOAD        = 1       ; upload glyph KANJI_CODE to KANJI_TILES
REQ_RELEASE       = 2       ; clear the active set
REQ_RESTORE       = 3       ; restore lower tile KANJI_TILES+0 from page 1
REQ_UP1           = 4       ; NMI internal: glyph tile 1 next
REQ_UP2           = 5       ; NMI internal: glyph tile 2 next
REQ_UP3           = 6       ; NMI internal: glyph tile 3 next
REQ_MARK          = 7       ; NMI internal: glyph done, mark its tiles
REQ_SYNC          = 8       ; restore every stale, inactive tile (message start)

FLAG_SPRITE_OK    = $01     ; page-0 tile $FF holds the sprite-0 pattern
FLAG_DMA_SPRITE   = $02     ; sprite 0 was in the OAM copied this frame
FLAG_PAGE2        = $04     ; band page selected since the last epilogue hit
FLAG_PPU_DIRTY    = $08     ; NMI-internal: PPU address used, restore scroll
FLAG_HI_SUB       = $30     ; upper-tile restore cursor within a group
FLAG_HIT          = $40     ; last band frame: sprite-0 hit seen
FLAG_MISS         = $80     ; last band frame: poll timed out

SPR0_STALE        = $FE     ; KANJI_SPR0: window moved, place sprite 0 again

; Battle pool (revision 18).  The battle tile set leaves tiles $A4-$DF of
; the scene page blank and never shows them.  A message printed while the
; battle graphics set is loaded, once the hack has read those tiles back
; blank, puts its kanji there (page 1, plane 0) instead of on the band
; page: entry k of a page uses tiles $A4+4k..+3.  No band, no sprite 0.
POOL_FIRST        = $A4
POOL_LAST         = $DF
POOL_SLOTS        = 15
POOL_SET          = 8       ; text_graphics_index of the battle graphics
WINCOL_POOL_OK    = $40     ; read back blank, no game write into them since
WINCOL_CHECKED    = $80     ; checked since the last graphics-set load
PAGE_POOL         = $40     ; KANJI_PAGES_LEFT: this message prints into the pool
POOL_CHECK_CODE   = $FF     ; KANJI_CODE_HI of the check request (REQ_UPLOAD
                            ; with pool tiles): read the tiles, no glyph
SPR0_DIRTY        = $FF     ; KANJI_SPR0: re-upload the sprite-0 tile first

WINDOW_CORNER     = $6D     ; top-left frame tile of every text window
SPRITE0_TILE      = $FF     ; page-0 tile used for the sprite-0 hit

; The game's palette tables (data_C5EF / data_C6B2 / data_C6C2, read only by
; load_text_graphics) live in hack banks 23/24 at $BF00, relocated by
; kanji_build.py; their fixed-bank space holds the hook code.
KANJI_PAL_DATA    = $BF00   ; copy of $C5EF-$C6D1
KANJI_PAL_LO      = KANJI_PAL_DATA + $C3   ; data_C6B2 (pointer low bytes)
KANJI_PAL_HI      = KANJI_PAL_DATA + $D3   ; data_C6C2 (pointer high bytes)
HACK_PAL_COPY     = $8009   ; hack-bank table copy for load_text_graphics

KANA_FONT_BANK    = 9
KANJI_TEXT_BANKS  = 18      ; banks 18-22 are generated text/metadata banks
KANJI_HACK_BANK   = 23      ; banks 23-24 hold identical code + glyph data
KANJI_GLYPH_BASE  = $8C00   ; per-bank glyph tables (after 3 KiB of code)
KANJI_GLYPHS_PER_BANK = 359

; Fixed-bank entry points (bank 15/31).
TEXT_RETURN       = $D285
TEXT_LINE_LOOP    = $D250
TEXT_NORMAL_CHAR  = $D2B7
SET_BANK_B        = $C482
SET_BANK_CURRENT  = $C47E
SET_BANK_LOCK     = $C484
RESTORE_BANK_AFTER_NMI = $C4AA
SET_BANK_13       = $C4A2
SET_BANK_14       = $C4A6
WAIT_VBLANK       = $C09F
TEXT_DRAW_CHAR    = $D456   ; prompt + wait for the button
TEXT_REDRAW_LINES = $D405   ; shift the window's tile rows up one row
OUTER_MARK        = $BFFF   ; bit 7 set in game banks 0-15, clear in banks 16-30
MMC1_RESET_ADDR   = $FFD9   ; inc here resets the MMC1 shift register

; call_hack function numbers (hack bank $8000 dispatcher).
FN_BLOCK_PRE      = 0       ; before a block write: page 1, save params
FN_BLOCK_POST     = 1       ; after a block write: mirror to page 2
FN_SERVICE        = 2       ; main thread, rendering off: serve KANJI_REQ
