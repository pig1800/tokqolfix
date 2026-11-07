; ======================================================================
; Tenchi o Kurau -- 512 KiB SUROM kanji target
; ======================================================================
; 32 x 16 KiB PRG, 16 KiB CHR RAM, 8 KiB battery PRG RAM, mapper 1.
; Banks 0-15 keep the original game.  Banks 16-30 hold the extended font,
; text and tables.  Bank 31 is a patched copy of the fixed bank so that the
; outer SUROM bank can be 1 while code continues to run at $C000-$FFFF.
; CHR RAM is 16 KiB and MMC1 runs in 4 KiB CHR mode: page 0 is sprites,
; page 1 the scene, page 2 the private text band.
; ======================================================================

KANJI_TARGET = 1

.db "NES",$1A
; NES 2.0: 32 x 16 KiB PRG, 16 KiB CHR RAM, mapper 1 submapper 1 (SUROM),
; 8 KiB battery PRG RAM.
.db $20,$00,$12,$08,$10,$00,$70,$08,$00,$00,$00,$01

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

; ---------------- bank 31 (fixed-bank mirror + patches) ----------------
.base $C000
.incbin "build/kanji/bank31.bin"
