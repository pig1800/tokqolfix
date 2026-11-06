#!/usr/bin/env python3
"""Assemble the decompilation and verify it byte-for-byte against the ROM.

Usage:
    python build.py                # rebuild assets/text + assemble + verify
    python build.py --target kanji # build the 512 KiB SUROM kanji target
    python build.py --allow-diff   # assemble even if the ROM was modified
    python build.py --listing      # also write build/rom.lst
    python build.py --skip-assets  # reuse existing build/assets binaries
    python build.py --skip-text    # reuse existing build/text includes
"""
from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ASM6F = ROOT / "tools" / "toolchain" / "asm6f" / "asm6f_64.exe"
ORIGINAL = ROOT / "Tenchi o Kurau (Japan) (Rev 1).nes"
BUILD_DIR = HERE / "build"
OUTPUT = BUILD_DIR / "rom.nes"
OUTPUT_KANJI = BUILD_DIR / "rom_kanji.nes"
MAIN = HERE / "main.asm"
MAIN_KANJI = HERE / "main_kanji.asm"
KANJI_BUILDER = ROOT / "tools" / "kanji_build.py"
EXPECTED_SHA256 = "40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367"
EXPECTED_KANJI_SIZE = 16 + 32 * 0x4000


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=["original", "kanji"], default="original",
                    help="build the byte-exact original or the expanded kanji hack")
    ap.add_argument("--allow-diff", action="store_true",
                    help="return success even if the output differs from the original ROM")
    ap.add_argument("--listing", action="store_true", help="write an ASM6f listing")
    ap.add_argument("--skip-assets", action="store_true", help="do not regenerate build/assets from PNGs")
    ap.add_argument("--skip-text", action="store_true", help="do not regenerate build/text from .dtx files")
    args = ap.parse_args()
    kanji = args.target == "kanji"
    output = OUTPUT_KANJI if kanji else OUTPUT
    main_asm = MAIN_KANJI if kanji else MAIN

    if not ASM6F.exists():
        print(f"error: assembler not found: {ASM6F}", file=sys.stderr)
        return 2
    if not ORIGINAL.exists():
        print(f"error: original ROM not found: {ORIGINAL}", file=sys.stderr)
        return 2

    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # Rebuild the binary graphics resources from the editable PNGs.  This keeps
    # assets/*.png as the source of truth while ASM6f still sees plain bytes.
    assets_py = ROOT / "tools" / "assets.py"
    if assets_py.exists() and not args.skip_assets:
        result = subprocess.run([sys.executable, str(assets_py), "build"],
                                cwd=ROOT, text=True, capture_output=True)
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        if result.returncode != 0:
            print(f"asset build failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

    # Rebuild the message-table/message-data includes from the editable .dtx
    # files.  The DTX files are the source of truth for banks 10/11.
    text_py = ROOT / "tools" / "text.py"
    if text_py.exists() and not args.skip_text:
        result = subprocess.run([sys.executable, str(text_py), "build"],
                                cwd=ROOT, text=True, capture_output=True)
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        if result.returncode != 0:
            print(f"text build failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

    if kanji:
        if not KANJI_BUILDER.exists():
            print(f"error: kanji builder not found: {KANJI_BUILDER}", file=sys.stderr)
            return 2
        result = subprocess.run([sys.executable, str(KANJI_BUILDER), "build"],
                                cwd=ROOT, text=True, capture_output=True)
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        if result.returncode != 0:
            print(f"kanji build failed with exit code {result.returncode}", file=sys.stderr)
            return result.returncode

    cmd = [str(ASM6F)]
    if args.listing:
        cmd.append("-l")
    cmd += [str(main_asm), str(output)]

    result = subprocess.run(cmd, cwd=HERE, text=True, capture_output=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        print(f"assembly failed with exit code {result.returncode}", file=sys.stderr)
        return result.returncode

    if not output.exists():
        print("error: assembler produced no output", file=sys.stderr)
        return 2

    got = bytearray(output.read_bytes())
    if kanji:
        # Bank 15 needs the SUROM write_prg_bank patch.  Keep the assembler
        # source include (it defines labels used by bank 14) and apply the
        # byte-level patch after assembly.
        bank15 = (BUILD_DIR / "kanji" / "bank15.bin").read_bytes()
        assert len(bank15) == 0x4000
        got[16 + 15 * 0x4000:16 + 16 * 0x4000] = bank15
        output.write_bytes(got)
    got = bytes(got)
    if kanji:
        print(f"built:  {output}")
        print(f"size:   {len(got)} bytes (expected {EXPECTED_KANJI_SIZE})")
        print(f"sha256: {sha256(output)}")
        if len(got) != EXPECTED_KANJI_SIZE:
            print("FAIL: unexpected kanji-target size", file=sys.stderr)
            return 1
        # The first 256 KiB must stay identical to the original except for the
        # banks intentionally replaced by the kanji target (10, 11, 13).
        original = ORIGINAL.read_bytes()
        allowed = {10, 11, 13, 15}
        for bank in range(16):
            a = got[16 + bank * 0x4000:16 + (bank + 1) * 0x4000]
            b = original[16 + bank * 0x4000:16 + (bank + 1) * 0x4000]
            if bank not in allowed and a != b:
                print(f"FAIL: bank {bank:02d} differs but should be original", file=sys.stderr)
                return 1
        lint = ROOT / "tools" / "bank15_lint.py"
        if lint.exists():
            result = subprocess.run([sys.executable, str(lint), "--rom", str(output)],
                                    cwd=ROOT, text=True, capture_output=True)
            if result.stdout:
                print(result.stdout, end="")
            if result.stderr:
                print(result.stderr, end="", file=sys.stderr)
            if result.returncode != 0:
                return result.returncode
        print("OK: 512 KiB kanji target assembled")
        print(f"     bank 31 mirrors bank 15 with text-engine patches")
        return 0

    want = ORIGINAL.read_bytes()
    print(f"built:  {output}")
    print(f"size:   {len(got)} bytes (expected {len(want)})")
    print(f"sha256: {sha256(output)}")
    print(f"target: {EXPECTED_SHA256}")

    if got == want:
        print("OK: byte-identical to the original ROM")
        return 0

    limit = min(len(got), len(want))
    first = next((i for i in range(limit) if got[i] != want[i]), limit)
    if first >= limit and len(got) != len(want):
        print(f"mismatch: size differs; first extra byte at 0x{first:06X}")
    else:
        prg = first - 16 if first >= 16 else None
        bank = prg // 0x4000 if prg is not None and prg >= 0 else None
        off = prg % 0x4000 if bank is not None else None
        if bank is not None:
            base = 0xC000 if bank == 15 else 0x8000
            print(f"mismatch: file 0x{first:06X}  PRG 0x{prg:06X}  bank {bank} CPU ${base + off:04X}")
            print(f"  want ${want[first]:02X}  got ${got[first]:02X}")
        else:
            print(f"mismatch: file 0x{first:06X}  header byte")
            print(f"  want ${want[first]:02X}  got ${got[first]:02X}")

    if args.allow_diff:
        print("NOTE: output differs from the original ROM (allowed by --allow-diff)")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
