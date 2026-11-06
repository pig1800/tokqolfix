; ======================================================================
; Tenchi o Kurau (Japan) (Rev 1) -- readable disassembly/reconstruction
; ======================================================================
; Target SHA-256: 40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367
; Build: python decomp/build.py
;
; The ROM is split into 16 PRG banks.  Code is emitted for paths proven
; by Mesen CDL or direct control flow.  Graphics, text, and large data
; blocks live under assets/ and are included with INCBIN; editing the
; PNG resources changes the corresponding bytes without touching code.
;
; Bank coverage:
;   bank 00:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 01:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 02:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 03:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 04:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 05:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 06:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 07:   344 insns,   796 bytes code,   312 CDL code bytes
;   bank 08:  1195 insns,  2278 bytes code,  1946 CDL code bytes
;   bank 09:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 10:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 11:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 12:     0 insns,     0 bytes code,     0 CDL code bytes
;   bank 13:  1182 insns,  2557 bytes code,  1650 CDL code bytes
;   bank 14:  1106 insns,  2311 bytes code,  1004 CDL code bytes
;   bank 15:  5206 insns, 10446 bytes code,  8690 CDL code bytes
; ======================================================================
; iNES/NES 2.0 header: PRG 16x16K, CHR 0, mapper 1 (MMC1),
; horizontal mirroring, battery PRG RAM, 8K CHR RAM, NTSC.
; ======================================================================

.db "NES",$1A
.db $10,$00,$12,$08,$00,$00,$70,$07,$00,$00,$00,$01

.include "include/hardware.inc"
.include "include/ram.inc"
.include "build/text/index_symbols.inc"

; ---------------- bank 00 ----------------
.base $8000
.include "banks/bank00.asm"

; ---------------- bank 01 ----------------
.base $8000
.include "banks/bank01.asm"

; ---------------- bank 02 ----------------
.base $8000
.include "banks/bank02.asm"

; ---------------- bank 03 ----------------
.base $8000
.include "banks/bank03.asm"

; ---------------- bank 04 ----------------
.base $8000
.include "banks/bank04.asm"

; ---------------- bank 05 ----------------
.base $8000
.include "banks/bank05.asm"

; ---------------- bank 06 ----------------
.base $8000
.include "banks/bank06.asm"

; ---------------- bank 07 ----------------
.base $8000
.include "banks/bank07.asm"

; ---------------- bank 08 ----------------
.base $8000
.include "banks/bank08.asm"

; ---------------- bank 09 ----------------
.base $8000
.include "banks/bank09.asm"

; ---------------- bank 10 ----------------
.base $8000
.include "banks/bank10.asm"

; ---------------- bank 11 ----------------
.base $8000
.include "banks/bank11.asm"

; ---------------- bank 12 ----------------
.base $8000
.include "banks/bank12.asm"

; ---------------- bank 13 ----------------
.base $8000
.include "banks/bank13.asm"

; ---------------- bank 14 ----------------
.base $8000
.include "banks/bank14.asm"

; ---------------- bank 15 ----------------
.base $C000
.include "banks/bank15.asm"

