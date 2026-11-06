# Toolchain

## ASM6f

- File: `asm6f/asm6f_64.exe`
- Version: ASM6f v1.6, modifications v03 (2025-01-27)
- Source: https://github.com/freem/asm6f
- Release archive: `asm6f_v03_20250127.zip`
- Purpose: assembles `decomp/main.asm` into a byte-identical iNES ROM.

The Windows binary is checked into this workspace so the decompilation can be
built without installing a system-wide 6502 toolchain. `decomp/build.py`
expects it at this path.

## Python

`tools/decompile.py`, `tools/cdl_summary.py`, `tools/merge_cdl.py`, and
`decomp/build.py` are Python 3 scripts with no third-party dependencies.
