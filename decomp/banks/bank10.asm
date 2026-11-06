; ======================================================================
; PRG bank 10  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$81E7  b10_msg_ptr_lo: Message pointer table, low bytes (488 entries).
;   $81E8-$81FF  b10_msg_ptr_gap: Pointer-table gap/auxiliary bytes.
;   $8200-$83E7  b10_msg_ptr_hi: Message pointer table, high bytes (488 entries).
;   $83E8-$BFFF  b10_messages: Editable compressed message bytecode.
; ======================================================================

.ifdef KANJI_TARGET
    .incbin "build/kanji/bank10.bin"
.else
.include "build/text/bank10_table.inc"
.include "build/text/bank10_data.inc"
.endif
