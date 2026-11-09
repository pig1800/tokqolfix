; ======================================================================
; Tenchi o Kurau -- 512 KiB MMC3 kanji target (revision 21)
; ======================================================================
; 32 x 16 KiB PRG, 16 KiB CHR RAM, 8 KiB battery PRG RAM, mapper 4.
; Banks 0-15 keep the original game.  Banks 16-30 hold the extended font,
; text and tables.  Bank 31 (8 KiB banks 62/63, fixed at $C000-$FFFF in
; MMC3 PRG mode 0) is the patched fixed bank; bank 15 holds the same
; bytes.  Every 16 KiB game bank is mapped as two 8 KiB halves (R6/R7).
; CHR RAM is 16 KiB in CHR mode 1: page 0 is sprites (R2-R5), page 1 the
; scene, page 2 the private text band (only its tiles $00-$7F, R0).
; ======================================================================

KANJI_TARGET = 1

.db "NES",$1A
; NES 2.0: 32 x 16 KiB PRG, 16 KiB CHR RAM, mapper 4 (MMC3), 8 KiB
; battery PRG RAM.
.db $20,$00,$42,$08,$00,$00,$70,$08,$00,$00,$00,$01

.include "include/hardware.inc"
.include "include/ram.inc"
.include "build/text/index_symbols.inc"

; ---------------- banks 00-14 ----------------
.base $8000
.include "banks/bank00.asm"

.base $8000
.include "banks/bank01.asm"

.base $8000
.include "banks/bank02.asm"

.base $8000
.include "banks/bank03.asm"

.base $8000
.include "banks/bank04.asm"

.base $8000
.include "banks/bank05.asm"

.base $8000
.include "banks/bank06.asm"

.base $8000
.include "banks/bank07.asm"

.base $8000
.include "banks/bank08.asm"

.base $8000
.include "banks/bank09.asm"

.base $8000
.include "banks/bank10.asm"

.base $8000
.include "banks/bank11.asm"

.base $8000
.include "banks/bank12.asm"

.base $8000
.include "banks/bank13.asm"

.base $8000
.include "banks/bank14.asm"

; ---------------- bank 15 (fixed bank source; patched after assembly) ----------------
.base $C000
.include "banks/bank15.asm"

; ---------------- banks 16-30 (extension banks) ----------------
.include "banks/bank16_30.asm"

; ---------------- bank 31 (the MMC3 fixed bank: patched bank 15) ----------------
.base $C000
.incbin "build/kanji/bank31.bin"
