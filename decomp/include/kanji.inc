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
; CHR (16 KiB RAM, MMC3 CHR mode 1, revision 21): page 0 sprites (R2-R5),
; page 1 scene, page 2 band.  Only BG tiles $00-$7F switch (R0, 2 KiB):
; tiles $80-$FF always show the scene page (R1).  Page 2's lower half is
; kept equal to page 1's except for the tiles in KANJI_STALE; the MMC3
; scanline IRQ selects it from the dialogue window's top border row to the
; bottom of the frame while KANJI_BAND is set (revision 21b; sprite 0
; before).

; MMC3 registers and the bank-select shadow (see mmc3_b15.asm).
MMC3_SELECT       = $8000
MMC3_DATA         = $8001
MMC3_MIRROR       = $A000
MMC3_WRAM         = $A001
MMC3_IRQ_LATCH    = $C000
MMC3_IRQ_RELOAD   = $C001
MMC3_IRQ_OFF      = $E000
MMC3_IRQ_ON       = $E001
MMC3_CHR_MODE     = $80     ; every select: CHR mode 1, PRG mode 0
MMC3_R0           = $80     ; BG tiles $00-$7F (2 KiB)
MMC3_R1           = $81     ; BG tiles $80-$FF (2 KiB)
MMC3_R6           = $86     ; PRG $8000-$9FFF
MMC3_R7           = $87     ; PRG $A000-$BFFF
MMC3_SEL          = $00EB   ; main thread's last $8000 value (the game's
                            ; MMC1 bank_switch_lock, unused by the game
                            ; outside the rewritten switch routines)
CHR_SCENE_LO      = 4       ; 1 KiB CHR bank numbers: page 1 tiles $00-$7F
CHR_SCENE_HI      = 6       ;   page 1 tiles $80-$FF
CHR_BAND_LO       = 8       ;   page 2 tiles $00-$7F

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
KANJI_QBYTES      = $0175   ; NMI scratch: VRAM-queue bytes the game flushed
                            ; this frame ($FF: CHR animation); revision 21b
                            ; (was KANJI_SPR0, the sprite-0 state)
KANJI_BAND        = $0176   ; 1 = band page shown below the window border
KANJI_WIN_ROW     = $0177   ; window top-border nametable row (0-29), bit 6:
                            ; in the lower vertical half ($2800/$2C00)
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

FLAG_PAGE2        = $04     ; band page selected by this frame's IRQ
FLAG_PPU_DIRTY    = $08     ; NMI-internal: PPU address used, restore scroll
FLAG_HI_SUB       = $30     ; upper-tile restore cursor within a group
FLAG_HIT          = $40     ; this frame: the IRQ switched to the band page
FLAG_MISS         = $80     ; (unused since revision 21b)
FLAG_ARMED        = $80     ; this NMI: irq_arm0 ran (map-canvas step 1)

; Scanline IRQ (revision 21b; two stages since map-canvas step 1).  The
; counter clocks once per rendered line at dot ~325 (BG at $1000, sprites
; at $0000), on A12 rises of vblank VRAM traffic, at the pre-render line's
; first BG fetch when vblank ends with the PPU address below $1000, and in
; Mesen once more at line 0 dot 5 on every other frame.  irq_arm0 (hack
; bank) runs right after the frame's last PPU access: it sets the PPU
; address to $1000, so the only clock left before rendering is the
; pre-render line's at dot ~325, and reloads with 0 there: IRQ stage 0.
; Its handler (irq_stage0) runs in line 0, after the irregular clock, and
; reloads the counter for line T (the window border row's first line):
; stage 1 comes at line T's clock and switches in line T + 1, on every
; frame whose game NMI flushed at most ARM_FORCE_MAX bytes (hack.asm).
; Heavier flushes (full-screen redraws) end the game's NMI at line 259.6
; and arm in line 0: the switch comes one line later there.
IRQ_OFS           = 2
IRQ_CHAIN         = 240
IRQ_ARM_MAX       = 40
; Map-canvas step 1: the two-stage arm (irq_arm0, irq_stage0).  NMI
; scratch in the read-back buffer, written after the frame's last unit.
KANJI_IRQ_ST      = KANJI_BUF+12 ; 1 = the next IRQ is stage 0
KANJI_IRQ_N       = KANJI_BUF+13 ; stage 1 comes at the clock of this line
MAP_ATTR          = $7800         ; 256 bytes: the map's attribute shadow for all
                                ; four nametables (the third save record's RAM,
                                ; map-canvas step 2; $7900-$7FFF free)
WINROW_LOWER      = $40         ; KANJI_WIN_ROW: four-screen lower half (row
                                ; * 8 and row >> 3 | $20 keep working)

; Battle pool (revision 18).  The battle tile set leaves tiles $A4-$DF of
; the scene page blank and never shows them.  A message printed while the
; battle graphics set is loaded, once the hack has read those tiles back
; blank, puts its kanji there (page 1, plane 0) instead of on the band
; page: entry k of a page uses tiles $A4+4k..+3.  No band, no sprite 0.
POOL_FIRST        = $A4
POOL_LAST         = $DF
POOL_SLOTS        = 15
POOL_PAGE_MAX     = 12      ; kanji per pool page: KANJI_UPLOADED bits 0-3
                            ; of byte 1 hold the page's first slot
POOL_SET          = 8       ; text_graphics_index of the battle graphics
WINCOL_POOL_OK    = $40     ; read back blank, no game write into them since
WINCOL_CHECKED    = $80     ; checked since the last graphics-set load
PAGE_POOL         = $40     ; KANJI_PAGES_LEFT: this message prints into the pool
POOL_CHECK_CODE   = $FF     ; KANJI_CODE_HI of the check request (REQ_UPLOAD
                            ; with pool tiles): read the tiles, no glyph

WINDOW_CORNER     = $6D     ; top-left frame tile of every text window

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

; call_hack function numbers (hack bank $8000 dispatcher).
FN_BLOCK_PRE      = 0       ; before a block write: page 1, save params
FN_BLOCK_POST     = 1       ; after a block write: mirror to page 2
FN_SERVICE        = 2       ; main thread, rendering off: serve KANJI_REQ

; Map-canvas step 3: the dialogue canvas.  A text window whose rows reach
; the band (screen rows 18-27, metarows 9-13 below the camera's top) in
; map mode is drawn into the other vertical half (address EOR $0800, the
; same in-half rows), with the map's tiles and palettes beside it, and a
; split IRQ shows it from line 144.  The visible half keeps the map.
; State in internal RAM $0780-$07FF (the old attribute shadow), cleared by
; hack_init at reset; the code runs from battery RAM at CV_RAM (copied from
; PRG bank CV_BANK at reset: it calls the game's map lookups, which map
; other banks over $8000-$BFFF).
CV_REDIR          = $0780   ; bit 7: band-row writes go to the canvas
CV_MROWS          = $0781   ; band metarows set up in the canvas (flanks written)
CV_PEND           = $0782   ; canvas tile rows to show (main thread)
CV_ROWS           = $0783   ; canvas tile rows shown: CV_PEND once the queue is flushed (NMI)
CV_CUR            = $0784   ; text_init: this metarow's band index, $FF = not in the canvas
CV_BC             = $0785   ; text_init: the metarow's canvas attribute-shadow index
CV_V1H            = $0786   ; $2006 pair, stage 1: the canvas's top row (fine Y 0)
CV_V1L            = $0787
CV_V2H            = $0788   ; $2006 pair, stage 2: the map row below the canvas
CV_V2L            = $0789
CV_LATCH          = $078A   ; stage 2's IRQ latch: 8 * CV_ROWS - 1
CV_S              = $078B   ; main-thread scratch
CV_T0             = $078C
CV_M0             = $078D   ; the camera's left metacol on the 32-metacol ring
CV_WL             = $078E   ; the window's first screen metacol
CV_WR             = $078F   ; the first screen metacol right of the window's whole metatiles
CV_C0             = $0790   ; screen column 0's nametable column (0-63)
CV_HB             = $0791   ; the canvas row's address high byte (left table)
CV_LB             = $0792   ; the canvas row's address low byte, column 0, tile row 0
CV_R              = $0793   ; emit: tile row 0/1
CV_C              = $0794   ; emit: screen column
CV_N              = $0795   ; emit: cells left
CV_K              = $0796   ; emit: cells in this entry
CV_SAVE           = $0798   ; 7 bytes: state around the map lookups
CV_NOFORCE        = $079F   ; NMI: bit 7 = irq_arm0 skips its address force
CV_FLANK          = $07A0   ; 64 bytes: the metarow's map tiles by screen column (row 0, row 1)
CV_I0             = $07E0   ; IRQ stage 0 scratch (cv_split)
CV_I1             = $07E1
CV_I2             = $07E2
CV_Q              = $07E3   ; the queue's write index when the canvas last shrank
CV_SROWS          = $07E4   ; CV_ROWS that CV_V1H-CV_LATCH were computed for
CV_ARMED          = $07E5   ; cv_nmi: bit 7 = armed in this NMI (cli pending)
CV_STRM           = $07E6   ; cv_stream: bit 6 = cv_nmi called from the stream step, bit 7 = done in this NMI
; IRQs are enabled inside the NMI (so stage 0 preempts a long NMI tail) only
; when the band's switch line is this low: the longest NMI tail measured
; ends in line 25, and the band stage writes $8000.
ARM_CLI_MIN       = 40

; NMI frame classes (hack.asm's nmi_ef08 and the canvas's cv_nmi agree on
; them).  A frame whose game flush exceeded REPLAY_MAX bytes, or that
; stepped the CHR animation, runs no hack unit or replay: it arms the IRQ
; first thing.  The PPU-address force is skipped after flushes over
; ARM_FORCE_MAX bytes (the game's NMI then ends in the pre-render line).
REPLAY_MAX        = 27      ; max queued bytes for a page-1 CHR replay
ARM_FORCE_MAX     = 103
CV_FORCE_MAX      = 103     ; cv_nmi's force: 104-byte flushes end it at pre-render dot ~262
CV_QWAIT          = 32      ; cv_sm: queued bytes that make a new canvas metarow wait for a flush
CV_TOP            = 18      ; the canvas's first tile row on screen
CV_BANK           = 27      ; PRG bank with the RAM image at $A000
CV_RAM            = $7900   ; the RAM code (MAP_ATTR is $7800-$78FF)
CV_RAM_PAGES      = 7       ; 1792 bytes copied at reset ($7900-$7FFF)
HACK_INIT         = $800C   ; hack bank entry, reset: clear the hack state, install CV_RAM

; ----------------------------------------------------------------------
; Bank-switch-free kanji on the info screen (step B, INFO_SCREEN.md).
; The UI bank holds the screen renderer, its own copy of the UI kanji
; glyphs and the item / tactic kanji tables (tools/asm/ui.asm); bank 14
; calls it through the fixed bank's call_ui (X = function).
; ----------------------------------------------------------------------
UI_BANK           = 28
UIF_INFO_DRAW     = 0       ; info screen, still black: CHR and the layout
UIF_BINFO_ENTER   = 1       ; battle wrapper, before the info screen
UIF_BINFO_EXIT    = 2       ; battle wrapper, after it (rendering off)
UIF_ARMY          = 3       ; army status screen: flush, SP / MSP cells P1
UIF_INFO_ENTER    = 4       ; info screen, before battle_intro_screen
UIF_BSTART        = 5       ; battle start, rendering off: the fixed kanji
UIF_WINCB         = 6       ; battle window line (template CALL, X in UI_X)
UIF_SM            = 7       ; battle window metarow drawn (canvas cv_sm)
UI_RAM            = $7FC0   ; battery RAM after the canvas RAM code
UI_PATH           = UI_RAM+0 ; 1 = the info screen was opened from a battle
UI_P2             = UI_RAM+1 ; 3 bytes: the battle's P2 colours 1-3
UI_BUSY           = UI_RAM+4 ; nmi_busy around the renderer's PPU access
UI_NOMIR          = UI_RAM+5 ; 1: the block writer does not mirror to the band
                            ; page (the battle start's and the info screen's
                            ; uploads; pal_copy clears it)
UI_TACT           = UI_RAM+6 ; info screen: bit n = tactic line n drawn
UI_SPST           = UI_RAM+7 ; battle: 1 = the tactic window's S P / 残 cells
                            ; are set (P1 at $27E4, P0 at $27E3, 残's top
                            ; half in row 17), written with a window's row
                            ; pair 18-19 (canvas cv_sm, UIF_SM)
; Battle screen (step B item 7).  Kanji area: plane 0 of the 23 groups
; $A4 + 4k (k = 0-22, tiles in 8x16 order t, t+1, t+2, t+3 = TL, BL, TR, BR);
; groups 8-22 hold the 15 fixed command kanji, filled from the back.
UI_BATTLE         = UI_RAM+8 ; 1 = the battle screen's kanji state is live
UI_X              = UI_RAM+9 ; template CALL: the row-buffer index X
UI_SMRET          = UI_RAM+10 ; cv_sm's return address low byte ($82: the
                            ; window's last row pair)
UI_PEND           = UI_RAM+11 ; bit n: line n has a kanji still drawn blank
UI_WIN            = UI_RAM+12 ; the window being drawn (text_mode), 0: none
UI_BMODE          = UI_RAM+13 ; 0: window start, 1: window end
UI_BLINE          = UI_RAM+14 ; the line being drawn
UI_BQ             = UI_RAM+15 ; glyph uploads queued since the last flush
UI_BE             = UI_RAM+16 ; scratch
UI_SLOT           = UI_RAM+17 ; 23: glyph in plane 0 of group k; $FF unknown,
                            ; $FE a message kanji (maybe on screen)
UI_GF             = UI_RAM+40 ; 23: bit 0 a window on screen shows group k,
                            ; bit 1 the window being drawn uses it
UI_RAM_END        = UI_RAM+63
