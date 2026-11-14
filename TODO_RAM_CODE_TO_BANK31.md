# To do: the RAM code into bank 31 (written 2026-11-14, ready to execute)

The user asked (2026-11-14) why 751 bytes of code sit in battery RAM (the
"RAM image", `tools/asm/canvas_ram.asm`, at `$7900-$7BEE`: 37% of the 2 KiB
the dropped third save record left, `$7800-$7FFF`), and whether it can live
in the fixed bank (16 KiB bank 31).  A survey (below) found 1,282 dead
bytes in bank 31.  The user then asked for this file, to be executed after
a context compaction: **do the steps below, in order, then report.**

## The facts the plan rests on

**Why the code is in RAM today:** it must run with any bank mapped (IRQ,
NMI, the game's own routines calling hooks, code that switches banks).
Only bank 31 (`$C000-$FFFF`) and RAM are always visible; bank 31 had 30
free bytes.

**The RAM image now** (`decomp/build/kanji/canvas_ram.lst`, 751 bytes):

| Part | Bytes | RAM | Reached from |
|---|---:|---|---|
| `cv_irq` .. `cv_irq_end` (incl. `txr_lat`, `txr_r0v`) | 117 | `$7900-$7974` | `irq_handler` (`mmc3_b15.asm`: `jmp CV_IRQ`); raster-timed |
| `cv_stream` .. `cvs_rts` | 239 | `$7975-$7A63` | `nmi_gate` (`jmp CV_STREAM`), NMI, vblank-timed |
| `cv_nmi`, `cvn_live`, `txr_map6` | 23 | `$7A64-$7A7A` | `$EF0B` patch (`kanji_build.py`: `cvl["cv_nmi"]`), `cv_stream` |
| `cv_fill` | 18 | `$7A7B` | `$C2AB` block (`jmp CV_FILL`) |
| `cv_sm` | 33 | `$7A8D` | `mmc3_b15.asm` `$CB1B` / `$CB80` blocks (`jsr CV_SM`) |
| `cv_wincb` | 8 | `$7AAE` | battle window templates (`$F8 <cv_wincb> n`: `kanji_build.py` `battle_templates`, `PRISON_TPL`; bank 14 `b14_k_reward_tpl` via `fixed_hooks.inc` `CV_WINCB`) |
| `txr_call` | 40 | `$7AB6` | `kanji_msg.asm` (`jsr TXR_CALL`), bank 13 (4x), bank 14 (1x), the hooks below; `fixed_hooks.inc` `TXR_CALL` |
| `txr_rr` (self-modifying!) | 55 | `$7ADE` | `txr.asm` `read_kanji` (`jmp TXR_RR`) only |
| `txr_dlx` | 44 | `$7B15` | `$DD03` patch (`jmp`) |
| `txr_rcx` | 100 | `$7B41` | `$DBCA` patch (`jmp`) |
| `txr_cur` | 27 | `$7BA5` | `$CD07` patch (`pla / jsr`) |
| `txr_mi` | 5 | `$7BC0` | `$CF22` patch (`jsr`) |
| `txr_rd` | 23 | `$7BC5` | `mmc3_b15.asm` `redraw_start` (`jsr TXR_RD`) |
| `txr_tpm` | 11 | `$7BDC` | `mmc3_b15.asm` `txr_tp` (`jmp TXR_TPM`) |
| `txr_menu` | 8 | `$7BE7` | bank 13 boot screens (6x `jsr TXR_MENU`, `fixed_hooks.inc`) |

Build plumbing today:
- `kanji_build.py`: `CV_BANK = 27`, `CV_RAM = $7900`, `CV_RAM_PAGES = 7`,
  `CV_LABELS`, `build_canvas_ram()` (assembled **first**, before
  `mmc3_b15`), `write_canvas_bank()`, `canvas_ram.inc` (included by
  `mmc3_b15.asm` and `hack.asm`), the patches above.
- `hack.asm` `hack_init` copies 7 pages from bank 27 `$A000` to
  `$7900-$7FFF` at reset; the image's tail is zeros, so the copy also
  **clears `$7BEF-$7FFF`** (renderer tables `TXR_TABLES` `$7BF5`, buffers,
  `UI_RAM2`/`UI_RAM`, `PRG_R7X`...).  That clear must stay.
- `memory_map.py` (bank 27 rows, `canvas_ram.bin`), `lua_addrs.py`
  (`canvas_ram.lst`), `tools/mss_canvas.py` (installs the image into old
  states), the RAM gates' labels (`cv_scopy_end`, `cv_sforce`,
  `cv_sreload`, `cv_w1`...: test probes read them).

**The survey** (2026-11-14; scratch tools `out/test/opt/survey.lua`,
`survey.sh`, `out/scratch/refscan.py`, `out/scratch/dis6502.py`,
`dis_b13.py`): every read/exec in the candidate blocks on 10 paths (power-on
standard path 6,200 frames, attract mode, two boot flows, menu cycle, shop,
record office, three battles), plus a search of every bank for `jsr`/`jmp`,
pointers, immediate pairs and inline pointers (`jsr $C33A` block writer,
`jsr $C4FB` return_inline_block) into them.

| Block | Bytes | What | Verdict |
|---|---:|---|---|
| `$E93D-$EE78` | 1,328 | menu scripts, `data_EDA1` / `data_EDD1` tables | **live** (every menu: ~10 fixed-bank read sites, bank 14 `$9617`/`$961C`, the UI bank): stays |
| `$FAD4` | 1 | `rts` of `read_input_state` | **live**: stays |
| `$FAD5-$FBC1` | 237 | developer debug overlay (RAM `$60-$63`, `$47` as hex sprites when `$A6` != 0) | **dead**: no caller, no pointer, never executed |
| `$FBC2` | 1 | `nop_return2` (`rts`), called by `$F078` | **live**: stays |
| `$FBC3-$FBE0` | 30 | `jmp $C09F` + a sprite-position table | **dead**: no reference |
| `$FBE1-$FC60` | 128 | 1bpp hex font 0-F | **dead**: only reader is bank 13's developer memory viewer at `$93BB` (`jsr $C33A` / `.dw $FBE1` at `$93DC`), which has no caller |
| `$FC61-$FFD7` | 887 | more 1bpp tiles (same developer screens) | **dead**: no reader found |

So **`$FAD5-$FBC1` (237) and `$FBC3-$FFD7` (1,045) are free: 1,282 bytes.**
(The reads logged "at" `$FAD4` / `$FBC3` were the CPU's dummy fetch after
the `rts` at `$FAD3` / `$FBC2`.  `$FFD8-$FFFF` is the reset vector code,
our `$FFDC-$FFDE` / `$FFE0-$FFEF` patches and the vectors: untouched.)

## Rules that apply (from earlier work; keep them)

- **Cycle neutrality:** the IRQ and NMI parts are dot/vblank-timed, and
  main-thread cycles in map mode can move a lag frame (RNG/NPC drift: a
  4-cycle `main_prg` change once did).  Keep every routine's cycles.
- **Keep the page layout:** the image starts page-aligned at `$7900`.  Put
  it at **`$FC00`** (page-aligned) in the same order, so every branch keeps
  its page relationship (a taken branch across a page costs +1 cycle).
  `$FC00 + 751 = $FEEF` fits below `$FFD7`.
- **Fixed-bank addresses of existing routines stay** (save states hold
  return addresses; `main_prg` etc. are documented as fixed).
- `txr_rr` modifies its own code: it cannot run from ROM.  Replace it (step
  3) and leave its 55 bytes as a gap at the same offset, so the routines
  after it keep their offsets too.
- `irq_handler` keeps its `jmp CV_IRQ` (3 cycles, as now).
- The original 256 KiB build stays byte-identical (`40f19e17...`).
- Commit and push at the end (master; attribution line as usual).

## Steps

1. **Baseline.**  `python decomp/build.py --target kanji`; copy
   `decomp/build/rom_kanji.nes` to `out/test/opt/preRB.nes` and
   `decomp/build/kanji/canvas_ram.bin` to `out/test/opt/preRB_ram.bin`;
   `cd out/test/opt && sh suite.sh preRB prb > suite_prb.log 2>&1` (about
   15 min, run in the background; it ends with "suite preRB prb done").

2. **Move the code into bank 31.**
   - Add a `.base $FC00` block to `mmc3_b15.asm` holding `canvas_ram.asm`'s
     code in the same order (or `.include` a renamed file with its
     `.base`/`.org` changed; drop the `CV_RAM` org).  Keep the labels'
     names (they become `mmc3_b15.lst` labels).
   - Add `$FAD5-$FBC1` and `$FBC3-$FFD7` to `kanji_build.py` `HOOK_RANGES`
     and to `bank15_lint.py` `PATCHES` (comment: the developer debug
     overlay, its hex font and tiles, unreachable; survey in this file).
     Keep `$FAD4` and `$FBC2` original.
   - `kanji_build.py`: drop `build_canvas_ram`, `write_canvas_bank`,
     `canvas_ram.inc` generation and `CV_BANK`/`CV_RAM`/`CV_RAM_PAGES`;
     take `cv_*`/`txr_*` addresses from `mmc3_b15.lst` (`labels`) for the
     patches (`$EF0B`, `$DD03`, `$DBCA`, `$CD07`, `$CF22`, templates) and
     for `fixed_hooks.inc` (`CV_WINCB`, `TXR_CALL`, `TXR_MENU`).
     `mmc3_b15.asm` no longer includes `canvas_ram.inc` (its own labels);
     `hack.asm` must get `CV_*`/`TXR_*` it uses from `fixed_hooks.inc`.
   - **Check `cv_wincb` in the templates:** the template interpreter's
     `$F8` handling takes the address as is today (`$7AAE`, high byte below
     `$80`); confirm it also works for `$Fxxx` (in the message engine's
     `$F8`, bit 7 of the high byte selects `set_bank_current`; read the
     template interpreter in bank 15's `text_init` before relying on it).
   - `hack_init`: replace the 7-page copy from bank 27 with a clear of
     `$7900-$7FFF` (A = 0, unrolled like the copy).  Bank 27 becomes free.
   - Add assembler checks (`.if`) that the IRQ code and `cv_stream`'s copy
     loop start at the same page offsets as in RAM (`cv_irq` = `$FC00`).

3. **Replace `txr_rr`.**  `txr.asm` `read_kanji` (bank 26's lower half,
   main thread, called through `txr_call` so the current bank is 26) reads
   the glyph's 32 bytes through the R7 window instead: map the store's
   8 KiB bank (`STORE_8K + TXR_K+1`) at R7 with `PRG_R7X` set (as `ui.asm`
   `M_STMAP`), read byte b of pos `TXR_K` at `STORE_TAB + 256 b + pos`, then
   R7 back to `TXR_BANK*2+1` with `PRG_R7X` cleared first (as
   `M_STUNMAP`).  No upper-half data of bank 26 may be touched in between.
   Leave the 55-byte gap in bank 31 where `txr_rr` was.  Cycles change
   here (faster): watch the map-mode tests; pad if a lag frame moves.

4. **Build and lint.**  Lint OK; `MEMORY_MAP.md` regenerated (teach
   `memory_map.py`: bank 27 free; bank 31's new ranges; drop
   `canvas_ram.bin`).  `lua_addrs.py`: `canvas_ram.lst` -> `mmc3_b15.lst`.
   `kanji.inc`: the RAM-code notes (`CV_RAM`, `TXR_TABLES` "the RAM image
   must end"), and its stale header line "There is no RAM code" (true at
   last: there is none).

5. **Test.**  Copy the new ROM to `out/test/opt/postRB.nes`; for the
   state-based tests copy **`preRB_ram.bin` to `postRB_ram.bin`** (the
   states may hold return addresses into the old RAM code; installing the
   old image keeps them valid, the new ROM never calls it).
   `sh suite.sh postRB qrb`, then `python -I suite_cmp.py prb qrb`:
   expect 0 differences (the copy flow's frame 800 border line is a known
   build-to-build jitter).  Also confirm in the listing that no timed
   branch changed page, and run `python -I tools/scroll_scan.py` (0).

6. **Docs and memory.**  TEXT_RENDERER.md (a section: the RAM code in bank
   31, the dead developer blocks, the survey), STATUS.md (ROM space: bank
   27 free, WRAM `$7900-$7BEE` free), DEBLOAT_TODO.md, MEMORY_MAP.md; the
   memory note `message-engine-layout` / a new one for this layout.
   Delete this file in the same commit (its content then lives in
   TEXT_RENDERER.md).

7. **Commit and push.**

## Expected result

- WRAM: 751 bytes freed at `$7900-$7BEE` (no RAM code at all; the reset
  clear stays); bank 27 free (16 KiB).
- Bank 31: the code at `$FC00-$FEEE` (with the 55-byte gap at `txr_rr`'s
  offset); 531 more bytes free: `$FAD5-$FBC1` (237), `$FBC3-$FBFF` (61),
  `$FEEF-$FFD7` (233).
- Old save states saved inside a renderer call return once into their own
  stale RAM copy (harmless); states saved on the map are unaffected.
