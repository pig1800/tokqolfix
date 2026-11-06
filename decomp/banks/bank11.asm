; ======================================================================
; PRG bank 11  CPU $8000-$BFFF
; ======================================================================
; traced code: 0 instructions / 0 bytes; CDL code bytes: 0
;
; Data resources (editable PNGs under assets/, rebuilt by build.py):
;   $8000-$817F  b11_msg_ptr_lo: Message pointer table, low bytes (384 entries).
;   $8180-$81FF  b11_msg_ptr_gap: Pointer-table gap/auxiliary bytes.
;   $8200-$837F  b11_msg_ptr_hi: Message pointer table, high bytes (384 entries).
;   $8380-$BFFF  b11_messages: Editable compressed message bytecode.
; ======================================================================

.ifdef KANJI_TARGET
    .incbin "build/kanji/bank11.bin"
.else
.include "build/text/bank11_table.inc"
.include "build/text/bank11_data.inc"
.endif
