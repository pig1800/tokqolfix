# Execution plan: kanji+kana text for Tenchi o Kurau (Rev 1)

Revision 8, 2026-11-07, after the revision-7 execution (commit `1b1001f`).
Section 1: what is confirmed. Section 2: two systemic defects found in the
field context. Section 3: work list. Section 4: decisions and what remains
for the user. Target remains emulator-only (Mesen); N8 compatibility by
construction, hardware pass later.

---

## 0. Revision-8 execution results (2026-11-08)

All Phase-2a tasks are implemented and green on the final build:

| Task | Result |
|---|---|
| 2.1 `<JUMP>` hook | `$D190`/`$D198` -> `jump_exit_13/14`; field replay dirty 76 -> 0; `qa_field` clean |
| 2.2 screen survey + reservations | `scene_borrow.tsv` has scene + screen columns; `pages_over_capacity=0`; 760 messages, 1,190 pages |
| 2.3 field harness | `qa_field.py`: 872 indices, 0 failures |
| 2.4 D3 font diff | original CHR 0 diffs vs bank 9; the 20 kanji-ROM diffs are the prompt's own tiles; shop failures were stale kanji |
| 2.5 per-page sweep | `qa_pages.py`: 872 indices, 1,356 pages, 0 failures |

Final gates: original byte-identical; kanji `a90614d8...`; `bank15_lint` 9
ranges; `sram_watch` 0; `iram_watch` 0; `mask_restore` 0; `stack_check` SP
`$18`/`$28`.  `qa_sweep.py` remains a fast page-1 smoke tool; its five
short-message timing cases all pass under `qa_pages.py`.

The reservations cost page capacity: the oath message is 9 short pages
instead of 3.  Text and borders are clean; this is a readability tradeoff,
recorded as remaining work.

---

## 1. Confirmed on a fresh build of `1b1001f`

| Gate | Result |
|---|---|
| Original target | byte-identical |
| `bank15_lint` | 7 ranges, bank 31 == bank 15 |
| `sram_watch` | 0 hack writes among 21,011 battery-RAM writes |
| `mask_restore` | 0 PPUMASK restores on a visible scanline |
| Multi-page | oath pages 1-3 clean, border `$0D` intact (`oath_zoom.png`) |
| Four lines | kanji on line 4 with the border intact (`fourline_zoom.png`) |

The `page_find` off-by-one and the cross-page reservations are real fixes.
The 872-index sweep exists and is the right shape of tool.

---

## 2. Two defects the sweep could not see

Both found with `tools/lua/field_kana_check.lua` (kanji ROM, survey inputs,
CHR and nametable dumps every 20 frames through the town) and confirmed by
decoding page records out of the built ROM.

### D1. `<JUMP>` exits leak kanji tiles into the next screen

`out/test/fk/fk_4400.png`: the field command menu (コマンド / はなす /
しらべる / たいれつ / ぶしょう / どうぐ) is garbled while NPC line 132 is
open. The six garbled tiles are マ は な し ら べ (`$24 $5D $1F $16 $31
$60`). Message 132 owns tiles `$0E $0F $10 $13`, so the garbage is not
its own. Messages 129-131, the preceding speech chain, own exactly those
six tiles. Each of those messages ends with `<JUMP:xxxx>`, which leaves
`text_show_message` through `jmp ($00F3)` into script code and never
reaches the exit hook at `$D1FA`, so `restore_exit` never runs and the
dirty bitmap is carried into the next screen. 95 messages in the script
end this way.

Fix: hook the `$F9` path before the bank switch, while the text bank is
still mapped. At `$D190` (`jsr set_bank_13`) and `$D198`
(`jsr set_bank_14`) call an overlay routine that runs the exit restore and
then tail-jumps to the original `set_bank_*`. Audit every other way out of
the interpreter: `<END>`, `<END_NOWAIT>` (both pass `$D1F3`), `<CALL>` with
no return, and `text_init` resets from menu code. Two new patch ranges,
registered in the lint.

### D2. The command menu is on screen during field messages

On the field the command menu stays visible while a talk or search message
is open, so its kana tiles are "referenced outside the window" for every
such message. The compiler only reserves menu kana for prompt messages.
Message 132 happened not to collide; 129-131 did. This is the general
case the revision-6 design assigned to "reservation tags plus QA", and
neither existed for it: the prompt tags do not cover talk messages, and
the sweep ran on the history screen, where no menu is drawn.

Fix, in two parts:

1. **Survey records screen-referenced tiles.** Extend the scene-borrow
   capture: at every message open, record every tile `< $80` referenced
   by either nametable outside the window, and emit it per message label
   alongside the scene-borrow set. The compiler reserves both. Unsurveyed
   messages fall back to the command-menu kana set plus the 26-tile
   allowance.
2. **Field QA harness.** Add an entry point that opens any message in the
   field with the command menu visible: a Mesen save state taken in town
   with the menu open, plus patching the talk-message inline index. Run
   every message there as well as on the history screen; keep the
   assertion that no page tile is referenced outside the window.

### D3. The sweep's eleven "context-dependent" failures are not explained

They were dismissed because the history screen "uses a different kana
font". That must be shown, not assumed: dump `$1000-$17FF` on the history
screen and diff against bank 9; list the differing tiles. If the fonts
match, those eleven are real failures of the same kind as D1/D2.

---

## 3. Work list (ordered)

### Phase 2a — Close D1-D3 (blocking)

| # | Task | Exit criterion |
|---|---|---|
| 2.1 | **Done.** Hooked `$D190`/`$D198`; open-time stale restore covers END/END_NOWAIT/CALL/text_init; 9 lint ranges. | Dirty 76 -> 0 in the field replay; `qa_field` clean. |
| 2.2 | **Done.** History, field and page-1 surveys merged into `scene_borrow.tsv`; scene tiles minus message kana plus the 48-tile field floor. | `pages_over_capacity=0`; reservation avg 81.6, max 124. |
| 2.3 | **Done.** `town_menu.mss` + `qa_field.py`; all 872 indices. | 0 failures. |
| 2.4 | **Done.** Original history/name-entry CHR matches bank 9 in all 128 tiles; kanji-ROM diffs are the prompt's own slots. | Different-font claim retired; shop failures closed. |
| 2.5 | **Done.** `qa_pages.py` samples every 2 frames and groups by page pointer. | 872 indices, 1,356 pages, 0 failures. |

### Phase 2b — Remaining gates (unchanged)

Prompt list tags for party/item prompts; scene-borrow coverage as the
playthrough grows; slot 2/3 registration byte-compare; random-RAM power-on
on three seeds; no PRG-register bit-4 writes; second emulator run.

### Phase 3 — Script, tables, menus; Phase 4 — UI; Phase 5 — release (unchanged)

---

## 4. Decisions and what remains for the user

Decided: emulator-only target; kana inside field lists; survey plus
reservation remains the mechanism (no return to runtime scans, which the
RAM budget forbids).

For the user later: proofreading when phase 3 starts; hardware pass when
an N8 exists. The field-context corruption is fixed; the build is safe for
save-state testing but still not a release (Phase 3 content and Phase 4 UI
remain). The extra page breaks are a known readability tradeoff.

---

## 5. Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji
python tools\qa_sweep.py --workers 4
python tools\qa_field.py --workers 4
python tools\qa_pages.py --workers 4
python tools\make_screen_survey.py
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\field_kana_check.lua --name fk
python tools\field_check.py
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua       --name sram
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\mask_restore.lua     --name mask
```

`field_kana_check.lua` writes `out/test/fk/fk_NNNN_{ppu,chr,ram}.bin` and PNGs;
`field_check.py` checks the command-menu box.  The authoritative field gate is
`qa_field.py` (menu-open save state), not the title-screen replay.
