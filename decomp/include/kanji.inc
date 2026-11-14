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
CHR_BAND_LO       = 14      ;   page 2 tiles $00-$7F: CHR $3800 since the map renderer (TEXT_RENDERER.md)

KANJI_TEXT_BANK   = $0131
KANJI_TEXT_ADDR   = $0132   ; 2 bytes (consumed at overlay entry)
KANJI_PAGE_PTR    = $0134   ; 2 bytes: current page record in the text bank
KANJI_CODE_LO     = $0136   ; upload request: glyph code (pos in its store bank)
KANJI_CODE_HI     = $0137   ;   (its store bank 0-3: STORE_8K below)
KANJI_PAGES_LEFT  = $0138   ; bit 7: page start pending, bit 6: PAGE_POOL
KANJI_BUFX        = $0139
KANJI_TILES       = $013A   ; 4 tile numbers (upload request / current kanji)
KANJI_UPLOADED    = $013E   ; 2-byte bitmap: page entry glyph is in CHR page 2
                            ; (band pages); pool pages: byte 0 counts the
                            ; names' kanji placed (kn_put, TXF_NAME)

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
; page: entry k of a page uses tiles $A4+4k..+3, in 8x16 order (TL, BL,
; TR, BR; since 2026-11-13, as the battle screen's groups).  No band, no
; sprite 0.
POOL_FIRST        = $A4
POOL_LAST         = $DF
POOL_SLOTS        = 15
                            ; (no page limit since 2026-11-13; it was 12)
POOL_SET          = 8       ; text_graphics_index of the battle graphics
WINCOL_POOL_OK    = $40     ; read back blank, no game write into them since
WINCOL_CHECKED    = $80     ; checked since the last graphics-set load
PAGE_POOL         = $40     ; KANJI_PAGES_LEFT: this message prints into the pool
POOL_CHECK_CODE   = $FF     ; KANJI_CODE_HI of the check request (REQ_UPLOAD
                            ; with pool tiles): read the tiles, no glyph

WINDOW_CORNER     = $6D     ; top-left frame tile of every text window

; The game's palette tables (data_C5EF / data_C6B2 / data_C6C2, read only by
; load_text_graphics) live in hack bank 23 at $9F00, relocated by
; kanji_build.py; their fixed-bank space holds the hook code.
KANJI_PAL_DATA    = $9F00   ; copy of $C5EF-$C6D1
KANJI_PAL_LO      = KANJI_PAL_DATA + $C3   ; data_C6B2 (pointer low bytes)
KANJI_PAL_HI      = KANJI_PAL_DATA + $D3   ; data_C6C2 (pointer high bytes)
HACK_PAL_COPY     = $8009   ; hack-bank table copy for load_text_graphics

KANA_FONT_BANK    = 9
KANJI_TEXT_BANKS  = 18      ; banks 18-22 are generated text/metadata banks
KANJI_HACK_BANK   = 23      ; the hack code, all in $8000-$9FFF (its upper
                            ; half is free)

; ----------------------------------------------------------------------
; The kanji store (2026-11-13, the user's layout): every kanji glyph once,
; in four consecutive 8 KiB banks STORE_8K .. STORE_8K+3 (the 16 KiB banks
; STORE_16K and STORE_16K+1), 256 glyphs a bank; the last bank's unused
; columns are blank, room to grow.  A glyph's code is its number: bank =
; code >> 8, pos = code & $FF (message text: $EC + bank, pos).  Byte b of
; glyph pos is at STORE_TAB + 256 b + pos with its bank at R7 (one indexed
; load a byte, rows on pages); b = 8 k + row, tile k in 8x16 order (TL,
; BL, TR, BR, as the battle screen's groups and the original name font).
; Main-thread code maps a store bank at R7 with PRG_R7X set (the NMI's
; last restore keeps it; mmc3_b15.asm nmi_prg) and clears it before
; anything that may switch banks or yield.
; ----------------------------------------------------------------------
STORE_8K          = 32
STORE_16K         = 16
STORE_TAB         = $A000
STORE_GLYPHS      = 1024

; Fixed-bank entry points (bank 15/31).
TEXT_RETURN       = $D285
TEXT_LINE_LOOP    = $D250
TEXT_NORMAL_CHAR  = $D2B7
TEXT_PUT_TILE     = $D340   ; a cell from a byte (a dakuten byte: the mark above)
SET_BANK_B        = $C482
SET_BANK_CURRENT  = $C47E
SET_BANK_LOCK     = $C484
RESTORE_BANK_AFTER_NMI = $C4AA
SET_BANK_13       = $C4A2
SET_BANK_14       = $C4A6
WAIT_VBLANK       = $C09F
WAIT_VBLANK_QUEUED = $C0A7  ; always yields a frame (the NMI flushes)
TASK_RESUME       = $C040   ; task_scheduler, main task resumed: controller,
                            ; RNG step, nmi_frame_counter, sound hook, then
                            ; pla / tay / pla / tax / rts
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
CV_MAP_FORCE_MAX  = 104     ; nmi_map's force (round 3: ~2 lines earlier than the old path): the force must start
                            ; by line ~261.1 (its scroll writes before the pre-render line's copies, the arm before
                            ; its clock); a 104-byte flush in one entry starts it at ~261.07, the dialogue scroll's
                            ; 104 bytes (8 entries) at ~260.52.  Above it no force: an arm before the pre-render line
                            ; then sees a spurious A12 clock (splits early)
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
UIF_ARMY          = 3       ; army status screen: the whole screen, rendering off
UIF_INFO_ENTER    = 4       ; info screen, before battle_intro_screen
UIF_BSTART        = 5       ; battle start, rendering off: the fixed kanji
UIF_WINCB         = 6       ; battle window line (template CALL, X in UI_X)
UIF_SM            = 7       ; battle window metarow drawn (canvas cv_sm)
UIF_INFO_BUSY     = 8       ; info screen after battle_intro_screen: busy mode
                            ; until UIF_INFO_DRAW ends (the game's waits flush
                            ; at once)
UIF_BSETUP        = 9       ; battle_setup_slots is next: busy mode while the
                            ; screen is off (the slots' waits flush at once)
UIF_BSETUP_END    = 10      ; its slot loop ended (bank 15 $E10F, X = $0A
                            ; there): busy mode off again
UIF_DEC           = 11      ; copy_pointer_triplet's decimal digits (bank 15
                            ; $D671 is a stub; X in UI_DECX)
UIF_DIV           = 12      ; div24_shift (bank 15 $C1D2 is a stub; X, Y in
                            ; UI_DECX, UI_DECY)
UIF_WIPE          = 13      ; sub_CE2D (bank 14's room transfer wipe), before
                            ; its loop: text 18 columns right, one row down
UIF_WIPE_ROWS     = 14      ; after it: the two buffer rows, the text row back
UIF_ROWEV         = 15      ; sub_CE7A (bank 15 $CE7A is a stub): an event's
                            ; map change, the player's metarow redrawn
UIF_PCHOOSE       = 16      ; kanji_overlay pool_choose: a pool page's slots
                            ; (n in KANJI_M2; V set: fallback, clear the window)
UIF_PTILES        = 17      ; kanji_overlay pool_tiles: entry KANJI_M2's tiles
UIF_RWLOAD        = 18      ; the first victory message: queue reward kanji
                            ; KANJI_M2 into slot KANJI_M2 (the overlay waits)
UIF_NAMEG         = 19      ; put_officer_name's kanji path (mmc3_b15
                            ; pon_kanji): kanji NG_K of record NG_REC to
                            ; plane 1 of $A9-$A9+3 through the VRAM queue;
                            ; V set: none
; The fixed-bank trampolines of UIF_WIPE_ROWS and UIF_ROWEV (sub_CE2D's
; and sub_CE7A's space; mmc3_b15.asm checks these): bank 14 mapped while
; the game's routines run and while they yield, the UI bank again on return.
WIPE_STATUS       = $CE6E   ; draw_party_status + draw_party_window
WIPE_TICK         = $CE7F   ; wait_frame_tick
WIPE_WAIT         = $CE8A   ; wait_vblank
UI_DECY           = $7F9C   ; UIF_DIV: the caller's Y
UI_DECX           = $7F9D   ; UIF_DEC, UIF_DIV: the caller's X (the bytes before
                            ; UI_RAM2; the canvas RAM code ends below them)
; The reward window (victory) and the message pool (step B item 8).
UI_RAM2           = $7F9E   ; battery RAM after the canvas RAM code (below UI_RAM)
; Battle kanji slots (2026-11-13, the user's design; ui_battle.asm
; ui_pchoose / ui_ptiles): slot s = the 4 tiles $80 + 4s (s = 0-31), 8x16
; order; the battle screen's group k is slot k + 9.  Before the win: slots
; 9-23 (17-23, the command kanji 将武却退撃攻総, last; 0-8 are the portrait,
; 24-31 the other command kanji).  From the win: 0-5 the reward window's
; 金兵糧経験値 (loaded at the first victory message), 6-31 the messages.
; The slot table (SL_*) knows each slot's kanji: a kanji already in a slot
; is used from there; a new one takes the free slot unused longest.  Bit
; per slot in the masks: byte s >> 3, bit $80 >> (s & 7).
KANJI_PMASK       = UI_RAM2+0 ; 4: slots the page may not take: not this
                            ; phase's, shown (the lines, a window, placed
                            ; on this page) (UIF_PCHOOSE, UIF_PTILES)
UI_PML            = UI_RAM2+4 ; 4: the slots the message window may show: its
                            ; lines at the last UIF_PCHOOSE and every slot
                            ; UIF_PTILES placed since (the prisoner window
                            ; keeps off them: grp_shown)
UI_PMT            = UI_RAM2+8 ; 4: UIF_PCHOOSE scratch
UI_PS0            = UI_RAM2+12 ; UIF_PCHOOSE / UIF_PTILES scratch
UI_PS1            = UI_RAM2+13
UI_PS2            = UI_RAM2+14
UI_SLV            = UI_RAM2+15 ; SL_MAGIC: the slot table is this build's (a
                            ; state saved in a battle by an earlier build has
                            ; other bytes there; ui_battle sl_check)
SL_MAGIC          = $5A
PRG_R7X           = UI_RAM2+16 ; main thread: the 8 KiB bank at R7 that the
                            ; NMI's last restore keeps (0: none, R7 =
                            ; 2 * current_prg_bank + 1); hack_init clears it
NG_REC            = UI_RAM2+17 ; put_officer_name's kanji (mmc3_b15 pon_kanji,
NG_K              = UI_RAM2+18 ;   UIF_NAMEG): the record, its kanji 0-2,
NG_X              = UI_RAM2+19 ;   the line-buffer index
                            ; (UI_RAM2+20 to +31: free)
UI_SHOWCHK        = UI_RAM2+32 ; 1: the window being drawn opens beside the
                            ; message window ($21 / $22: grp_shown applies)
                            ; (UI_RAM2+33: free)
RW_SLOT           = 0       ; the reward window's first slot (from the win)
UI_WON            = $80     ; UI_BATTLE bit 7: the battle is won (a message
                            ; with META_WIN started: b10_msg_059 / 061 / 062)
UI_RWLOAD         = $40     ; UI_BATTLE bit 6: the reward kanji are in 0-5
META_WIN          = $20     ; metadata byte 0 (page count) bit 5: a victory
                            ; message (kanji_text WIN_LABELS)
UI_RAM            = $7FC0   ; battery RAM after UI_RAM2
UI_PATH           = UI_RAM+0 ; 1 = the info screen was opened from a battle
UI_P2             = UI_RAM+1 ; 3 bytes: the battle's P2 colours 1-3
UI_BUSY           = UI_RAM+4 ; nmi_busy around the renderer's PPU access
UI_NOMIR          = UI_RAM+5 ; 1: the block writer does not mirror to the band
                            ; page (the battle start's and the info screen's
                            ; uploads; pal_copy clears it)
UI_TACT           = UI_RAM+6 ; info screen: bit n = tactic line n drawn
UI_BRIGHT         = UI_TACT  ; battle (the same byte; the info screen clears it): the
                            ; first column right of every window drawn since a
                            ; command window last blanked beside itself (UIF_SM)
SM_QMAX           = 56      ; cv_sm: queued bytes after a battle row pair that
                            ; make it wait for a flush (the blanking beside a
                            ; command window; a flush over ~110 bytes ends
                            ; past vblank: one frame scrolled wrong)
UI_SPST           = UI_RAM+7 ; battle: 1 = the tactic window's S P / 残 cells
                            ; are set (P1 at $27E4, P0 at $27E3, 残's top
                            ; half in row 17), written with a window's row
                            ; pair 18-19 (canvas cv_sm, UIF_SM)
; Battle screen (step B item 7).  Kanji area: plane 0 of the 23 groups
; $A4 + 4k (k = 0-22, tiles in 8x16 order t, t+1, t+2, t+3 = TL, BL, TR, BR);
; groups 8-22 hold the 15 fixed command kanji, filled from the back.
UI_BATTLE         = UI_RAM+8 ; not 0: the battle screen's kanji state is live
                            ; (1; bit 7 UI_WON once the battle is won)
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
UI_BSBUSY         = UI_RAM+63 ; UIF_BSETUP entered busy mode (UIF_BSETUP_END
                            ; leaves it only then)
UI_RAM_END        = UI_RAM+64

; ----------------------------------------------------------------------
; Map-mode text renderer (TEXT_RENDERER.md, 2026-11-12).  PRG bank
; TXR_BANK (txr.asm); RAM stubs and the NMI uploader in canvas_ram.asm.
; Screen parts (rows 0-8 / 9-14 / 15-20 / 21-29) show BG tiles $00-$7F
; from R0 = 4 / 8 / 10 / 12 (CHR $1000 / $2000 / $2800 / $3000).
; ----------------------------------------------------------------------
TXR_BANK          = 26
TXF_MAPINIT       = 0       ; the map's font load: page 1 lower = the fixed set
TXF_RESTORE       = 1       ; clear_screen: the font back into page 1 lower
TXF_DL            = 2       ; text_draw_line's entries: translate before the commit
TXF_RC            = 3       ; text_render_cell, in map mode
TXF_RESET         = 4       ; redraw_start (windows closed): the glyphs stay (txr_close)
TXF_DLC           = 5       ; text_draw_line: continue after the uploads
TXF_RCC           = 6       ; text_render_cell: continue (after uploads or a pause)
TXF_FILL          = 7       ; set_ppu_scroll's fill (cv_fill)
TXF_PUT           = 8       ; map UI: text_put_tile (templates, item / tactic / place names)
TXF_LABEL         = 9       ; map UI: a label (bank 14: the gold window, その他)
TXF_MENU          = 10      ; the boot screens: TXR_ON = $40, the pool unusable (the set is in CHR: TXF_MENUSET)
TXF_NAME          = 11      ; an officer record's kanji name: its glyph codes into TXR_NM (battle messages)
TXF_LOOK          = 12      ; text_show_message after a 3rd line (map mode): V set = the next line would scroll
TXF_MENUSET       = 13      ; the boot entry (bank 13 b13_k_set): the fixed set into the upper page, once
TXR_N0            = 70      ; stage 0's count: the first switch in line 71's hblank
TXR_ON            = $0780   ; bit 7: page 1 lower holds the renderer's tiles (map mode); bit 6:
                            ; the UI words in kanji (map mode $C0; the boot screens' fixed set $40)
TXR_UQN           = $0781   ; staged tiles the NMI has still to upload
TXR_UQR           = $0782   ; the NMI's offset in TXR_UQ
TXR_BOOT          = $0783   ; bit 7: pages 2-4 hold the fixed set (since reset)
TXR_QX            = $0784   ; text_draw_line: the queue's end index
TXR_RET           = $0785   ; text_render_cell's return value (the line-end byte)
TXR_HB            = $0786   ; the queue byte held back (0: none): text_draw_line's wait (txr_dlc puts it
                            ; back); bit 7 set: text_render_cell's cells, put back by the NMI with its batch
TXR_HI            = $0787   ;   and its index
TXR_RS            = $0788   ; txr_rr: 2, source address
TXR_RST           = $078A   ; txr_rr: 2, source stride
TXR_RN            = $078C   ; txr_rr: byte count
TXR_RO            = $078D   ; txr_rr: offset in TXR_GBUF
TXR_SN            = $078E   ; main thread: records staged in this batch
TXR_FULL          = $078F   ; cells drawn blank because a page was full (count)
TXR_P             = $0790   ; main thread: the entry's part 0-3
TXR_PAR           = $0791   ; main thread: 0 = the entry's row is a line's top row
TXR_E             = $0792   ; main thread: queue index of the entry
TXR_EN            = $0793   ; main thread: cells left in the entry
TXR_HE            = $0794   ; text_render_cell: the queue index after the held cells (the NMI flushes them)
TXR_B             = $0795   ; main thread: the byte being translated
TXR_T             = $0796   ; main thread: tile
TXR_G             = $0797   ; main thread: group / loop index
TXR_K             = $0798   ; main thread: kanji glyph code (2)
TXR_Y             = $079A   ; text_render_cell: row-buffer index
TXR_N             = $079B   ; text_render_cell: cells in this step (1 or 2)
TXR_I             = $079C   ; scratch
TXR_J             = $079D
TXR_Q0            = $079E   ; NMI: the queue read index before the flush
REG_LO            = $07A0   ; 32: glyph code of kanji entry e (low): 0-15 a message page's, 16-31 the map UI's
REG_HI            = $07C0   ;     (high)
TXR_CT            = $07E7   ; text_render_cell: 2 top tiles
TXR_CB            = $07E9   ; text_render_cell: 2 bottom tiles
TXR_EL            = $07EB   ; text_draw_line: bytes in TXR_EB
TXR_UB            = $07EC   ; NMI: the uploader's budget left (UP_* units)
TXR_ST            = $07ED   ; a renderer call's status for its stub (0 done, 1 uploads, 2 pause)
TXR_WC            = $07EE   ; text_render_cell: cells to pause for
TXR_S10           = $07EF   ; txr_call: $10, $11 and the bank, kept (not on the stack)
TXR_S11           = $07F0
TXR_SB            = $07F1
TXR_RX            = $07F2   ; txr_rd: X, Y kept
TXR_RY            = $07F3
TXR_GCS           = $07E0   ; GC: bit 7 = running, bits 0-1 = the part (the canvas's old CV_I0-CV_SROWS)
TXR_GCF           = $07E1   ; GC: ran for this line / cell already (a second miss draws blank)
TXR_GCR           = $07E2   ; GC: rows requested so far
TXR_RBQ           = $07E3   ; GC: a row read is pending for the NMI
TXR_A1H           = $07F4   ; GC row read: segment 1 address, count; segment 2
TXR_A1L           = $07F5
TXR_N1            = $07F6
TXR_A2H           = $07F7
TXR_A2L           = $07F8
TXR_N2            = $07F9
TXR_GN            = $07FA   ; GC: the part's row count
TXR_TA            = $07E4   ; map UI (TXF_PUT / TXF_LABEL): the byte or label; then put_str's index
TXR_TX            = $07E5   ; map UI: the row-buffer index passed in
TXR_TY            = $07FB   ; map UI: the caller's Y
TXR_SKIP          = $07FC   ; map UI: kana bytes still to skip (a word shown in kanji)
TXR_UR            = $07FD   ; map UI: REG entry 16-31 taken last (round robin)
TXR_PX            = $07FE   ; map UI: put_str's row-buffer index
TXR_LA            = $07FF   ; map UI: the label's row-buffer index after it
TXR_MARK          = TXR_UQ  ; GC: 16-byte bitmap of the tiles shown (the staging area is idle)
; Battery RAM (the canvas code's old space, after the RAM image), from the
; top down to TXR_TABLES:
TXR_NG            = 28      ; kanji groups per part: tiles $0C-$7B
TXR_UQSZ          = 55      ; staging bytes: 5-byte records, kana R0, PPU hi, lo, font offset, font page; kanji R0 | $80, PPU hi, lo, the glyph's pos and its store bank's R7 value
TXR_UQ            = $7F65   ; 55: the staged records (TXR_SN bytes; the NMI: TXR_UQN left from TXR_UQR)
; The NMI uploader's budget (TEXT_RENDERER.md "Upload speed", B + D and
; round 3), in units of 16 cycles from nmi_up's entry (about line 247.3):
; the records end in time for the force (v = $1000 before line 261) and
; the arm, one unit fewer per byte the game flushed in that NMI.  The
; charges are each record's worst case.
UP_UNITS          = 85
UP_KANA           = 11      ; a kana record (txr.asm up_kana; ~157 cycles, ~171 with an R0 switch)
UP_KANJI          = 27      ; a kanji record, 4 tiles (txr.asm up_kanji; 426 cycles with a store-bank and an R0 switch)
UP_CELLS          = 14      ; text_render_cell's released cells, flushed by the NMI (rel_flush)
; (The NMI uploader reads the kanji store above: R7 = STORE_8K + bank.)
TXR_EB            = $7F35   ; 48: text_draw_line's entries, out of the queue
TXR_GBUF          = $7F15   ; 32: glyph bytes read by txr_rr
; The battle's kanji slot table (2026-11-13): the map renderer's staging
; buffers (TXR_EB, TXR_UQ: map mode only) hold it in battle.
SL_LO             = TXR_EB     ; 32: text code (low) of the kanji in slot s
SL_HI             = TXR_EB+32  ; 32: its high byte; $FF: none known
SL_AGE            = TXR_EB+64  ; 32: SL_CLK when slot s was last used
SL_CLK            = TXR_EB+96  ; pages begun (UIF_PCHOOSE)
TXR_NM            = TXR_GBUF ; TXF_NAME: kanji count (0: none or no room), 3 codes lo, 3 hi
TXR_NJ            = TXR_NM+7 ;   the overlay's loop: the name's kanji 0-2
TXR_NE            = TXR_NM+8 ;   the first free reserved pool entry (TXF_NAME), then the loop's
TXR_TBM           = $7ED5   ; 4 x 16: tiles in use in part p (bit set)
TXR_GHI           = $7E65   ; 4 x 28: glyph code of group g in part p (high; $FF = free)
TXR_GLO           = $7DF5   ; 4 x 28: (low)
TXR_KM            = $7BF5   ; 4 x 128: kana code -> tile in part p (0 = none)
TXR_TABLES        = $7BF5   ; the RAM image must end at or below this
