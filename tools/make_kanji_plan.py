#!/usr/bin/env python3
"""Generate a kanji-hybrid planning text for the dialogue banks.

This is not part of the byte-exact build.  It uses a small local kana-kanji
model (yuuki14202028/kanakanji-edge-33m) to turn the kana dialogue into a
readable kanji/kana version, then keeps the original message labels and
control tokens.  The result is used to estimate how many 16x16 kanji glyphs
the dialogue would need.

Requires: transformers, torch, and a one-time model download.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import text
import textdata

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "decomp" / "text" / "kanji_plan"

MODEL = "subdiox/genmai-310M"
CONTEXT_TOKEN = "\uee02"
INPUT_START = "\uee00"
OUTPUT_START = "\uee01"


# Runs that can be sent to the model.  Everything else (punctuation, spaces,
# frame characters) is kept verbatim.
CONVERT_RUN = re.compile(
    r"([^\u3041-\u3096\u30a1-\u30f6\u30fc\u4e00-\u9fff0-9\uff10-\uff19]+)"
)

_tokenizer = None
_model = None


def _load():
    global _tokenizer, _model
    if _model is not None:
        return
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    _tokenizer = AutoTokenizer.from_pretrained(MODEL)
    _model = AutoModelForCausalLM.from_pretrained(MODEL).eval()
    if torch.cuda.is_available():
        _model = _model.to("cuda")


def _hira_to_kata(s: str) -> str:
    return "".join(
        chr(ord(c) + 0x60) if 0x3041 <= ord(c) <= 0x3096 else c for c in s
    )


def _convert_raw(kana: str, left_context: str = "") -> str:
    import torch

    prompt = f"{CONTEXT_TOKEN}{left_context}{INPUT_START}{kana}{OUTPUT_START}"
    ids = _tokenizer.encode(prompt, add_special_tokens=False, return_tensors="pt")
    if torch.cuda.is_available():
        ids = ids.to("cuda")
    with torch.inference_mode():
        out = _model.generate(
            ids,
            max_new_tokens=160,
            num_beams=5,
            num_return_sequences=1,
            length_penalty=0.0,
            do_sample=False,
            eos_token_id=_tokenizer.eos_token_id,
            pad_token_id=_tokenizer.pad_token_id,
        )
    return _tokenizer.decode(out[0][ids.shape[1]:], skip_special_tokens=True)


def _convert_segment(segment: str, context: str) -> str:
    reading = _hira_to_kata(segment)
    converted = _convert_raw(reading, context)
    return converted.replace(" ", "").replace("\u3000", "")


def convert_literal(s: str, context: str = "") -> tuple[str, str]:
    """Convert one run of literal text, preserving punctuation/space."""
    parts = CONVERT_RUN.split(s)
    out: list[str] = []
    for part in parts:
        if not part:
            continue
        if CONVERT_RUN.fullmatch(part):
            out.append(part)
            continue
        while len(part) > 60:
            cut = part.rfind("、", 20, 60)
            if cut < 0:
                cut = 55
            piece, part = part[:cut], part[cut:]
            converted = _convert_segment(piece, context)
            out.append(converted)
            context = (context + converted)[-160:]
        converted = _convert_segment(part, context)
        out.append(converted)
        context = (context + converted)[-160:]
    return "".join(out), context


def convert_string(s: str, context: str = "") -> tuple[str, str]:
    pieces = re.split(r"(<[^>]*>)", s)
    out: list[str] = []
    for piece in pieces:
        if not piece:
            continue
        if piece.startswith("<") and piece.endswith(">"):
            out.append(piece)
            continue
        converted, context = convert_literal(piece, context)
        out.append(converted)
    return "".join(out), context


def main() -> int:
    _load()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for bank in (10, 11):
        records = text.parse_dtx(text.dtx_name(bank))
        lines = [
            f"# Tenchi o Kurau dialogue bank {bank:02d} -- kanji planning version",
            "#",
            "# Generated from the kana dialogue with a local kana-kanji model.",
            "# This file is for glyph-budget assessment only; it is not assembled",
            "# into the ROM and does not replace the byte-exact .dtx source.",
            "#",
            "# Labels and control tokens match the original message table.",
            "# Proper names in katakana are deliberately left as katakana.",
            "",
        ]
        context = ""
        converted_records = []
        for rec in records:
            source = textdata.encode_record(rec.data)
            converted, context = convert_string(source, context)
            converted_records.append(
                {"labels": rec.labels, "source": source, "kanji": converted}
            )
            for label in rec.labels:
                lines.append(f"{label}:")
            lines.append(f'    "{converted}"')
            lines.append("")
        dtx_path = OUT_DIR / f"bank{bank:02d}_messages_kanji.dtx"
        dtx_path.write_text("\n".join(lines), encoding="utf-8")
        json_path = OUT_DIR / f"bank{bank:02d}_messages_kanji.json"
        json_path.write_text(
            json.dumps(converted_records, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"wrote {dtx_path} ({len(records)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
