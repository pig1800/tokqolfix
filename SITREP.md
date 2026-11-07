# SITREP — kanji target handoff (revision 3 + revision-4/5/6/7 addenda)

Date: 2026-11-07.  Baseline: revision-6 architecture plus this page-handling
pass.  The code baseline before the pivot was `b967d80`; the revision-5
evidence is in the section below.

This is the handoff document for the next planning iteration (Fable).
`PLAN.md` revision 3 contains the original work list; this file records what
is actually implemented, measured, and still open so the plan can be revised
from evidence instead of from the earlier assumptions.

## Revision 7 addendum (2026-11-07) — multi-page fix

The revision-6 runtime is unchanged.  Two regressions in the text compiler /
page dispatch were fixed:

- **`page_find` off-by-one.**  It left `Y` on the entry's `code_hi`; the
  handler then copied `t1,t2,t3,next_code_lo` instead of `t0..t3`.  That is
  why glyphs mixed and the border tile `$0D` appeared in page records.  `dey`
  at `@found` fixes it.
- **Cross-page visible lines.**  A page break leaves up to three lines from
  earlier pages on screen.  The compiler now reserves, for each page, the
  last three visible lines' kanji tiles (backward carry) and the kana tiles of
  this page and the next two pages (forward).  Both are required; either
  alone still mixes glyphs or restores kana over visible kanji.

`restore_exit` still skips visible tiles: the history/name-entry screen uses
a different kana font, so a bank-9 restore there garbles the prompt.  The
restore queue is four tiles per frame, which keeps `mask_restore` at 0.

Verified: oath pages 1-3 clean (`oath_zoom.png` redone), border `$0D`, a
four-line page with a line-4 kanji (`fourline_zoom.png`), history prompt and
name entry clean, 6,000-frame survey healthy.  Gates: `sram_watch` 0 hack
writes, `iram_watch` 0 foreign writes, `mask_restore` 0, min SP `$18`/`$28`.

`tools/qa_sweep.py` adds a message-warp sweep.  All 872 indices: 772 page-1
clean, 89 empty records, 11 context-dependent failures (shop/battle/name
font menus).  The history-prompt warp is not neutral, so a dedicated QA entry
point is still needed for the plan's zero-failure 2.5 gate.  The sweep
truncates each message at its first page break; per-page QA beyond page 1 is
also still open.

Final hashes: original
`40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
kanji `54fc79b849c69f984b257c62a55c3487ce5ec8596f2d253b01eea2d77f178d33`.

## Revision 6 addendum (2026-11-07) — ROM-resident pivot implemented

`PLAN.md` revision 6 is implemented. The runtime no longer uses battery RAM
or NMI code:

- **Overlay** 1,042 bytes at `$B800`, included byte-identically in text banks
  18-22. The fixed-bank `F8 3A C6` trampoline maps bank 10/11, reads the five
  inline bytes, maps the text bank and enters `$B800`. Fixed-bank block is
  94 bytes at `$C611-$C66E`; 7 patch ranges; bank 31 mirrors bank 15.
- **State** entirely in internal RAM: `$0131-$013F` (text bank/address, page
  pointer, code, page count, entry index, four tiles, uploaded flags),
  `$0140-$015F` (RAM font-copy stub), `$0160-$016F` (half-glyph/kana row),
  `$0170-$017F` (dirty-CHR bitmap), `$01E0-$01E7` (scratch).
- **Uploads** go through the game's `$0400` VRAM queue. The overlay waits for
  the queue to drain, writes the four 16-byte tile entries, and marks the
  tiles dirty. `restore_exit` restores kana for dirty tiles not referenced by
  `$0180`/`$0300`; `kana_prepare` restores a borrowed kana tile before page
  reuse.
- **Compiler** assigns the four CHR tiles per kanji from the page's free kana
  set and emits page records `count, count*(code_lo,code_hi,t0..t3)`. It
  consumes `decomp/text/kanji_plan/scene_borrow.tsv` (9 surveyed labels) and
  prompt list tags. Current max page entries 11, `min_free_static = 4`,
  `pages_over_capacity = 0`.
- **Name-entry charset**: the `savename` set is the exact 65 tiles drawn on
  the original name-entry screen, extracted from PPU `$2000/$2400`; the
  history prompts use it.
- **Gates**: `sram_watch` 0 hack writes (21,923 game SRAM writes);
  `iram_watch` 0 foreign writes to the reserved ranges; `mask_restore` 0
  visible-scanline frames; `stack_check` min SP `$18` at NMI and `$28` at
  overlay entry. Prompt/name-entry screenshots and field message
  `b10_msg_129` are clean; the 6,000-frame survey is healthy.

Final hashes: original
`40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
kanji `b1e33ab17ad4b41d4a1c6c34386aec0679b36eed3f7df149f2a71857b447bb4c`.
Remaining: Phase-2 all-message QA, per-prompt field list tags beyond the
`menu` heuristic, broader scene-borrow coverage, outer-bank/N8 checks, then
script/table/menu conversion.

## Revision 5 addendum (2026-11-07)

`PLAN.md` revision 5 was executed and its central premise failed. The upper
CHR range is referenced on the history/name-entry screens (window border,
menu and name fonts); opening the pool from `game_mode`/`text_mode` alone
garbles the screen. The revision-4 nametable gate is required and restored.

A second discovery invalidates the old SRAM audit: bank 13 copies a 2 KiB
save slot over `$6800-$6FFF` through an indirect pointer (`PC $9F6B-$9F7E`,
"5S" written at `$6008/$6009`). Long-lived state in that range is wiped by
the save menu. The upper save area at `$7C00` survives. An internal-RAM
relocation of the runtime state was implemented but corrupted page records
and was reverted; see `STATUS.md` for the exact symptom and next steps.

The NMI budget was re-measured with `mask_restore.lua` (the PPUMASK restore
at `$EEDA`, not `rti`). Revision-4 batches still show visible-scanline
restores; 4-tile/64-byte batches still showed them and broke the survey
(green screen), so they were reverted. The black band remains open.

Final state of this pass: original
`40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
kanji `cf2db99fee82206ce5425f60a6093f5c6f177ae10f9ca6c973f92d2ffd6a445f`;
overlay 2,981 bytes; 17 lint ranges; prompts and the 6,000-frame survey are
clean. Compiler checks were added for page slots (≤13) and metadata (≤256).

## Revision 4 addendum (2026-11-07)

`PLAN.md` revision 4 switched the font to JF-Dot-Shinonome16 and proposed
blank upper-tile allocation. Evidence showed the history screen's upper CHR
is not blank: 124 of 128 tiles `$80-$FF` hold the menu/name font. The
implemented rule is therefore "unreferenced by both nametables and OAM",
with the whole upper pool closed on map/portrait screens.

Implemented in this pass:

- `cell_check` at `$C64F` plus patches at `$DBE7/$DBEA`; tiles `$00-$F9`
  now render and `$FA-$FF` stay controls. 17 lint ranges.
- Upper free/dirty bitmaps, 32-byte screen/visible bitmaps, OAM sprite tile
  marking, upper restore-to-zero, and upper-pool reuse at message open.
- 2 KiB nametable scan at 128 bytes/frame, alternating with the 8-tile CHR
  scan. Message-open scan is about 32 frames.
- `tools/lua/nmi_budget.lua`: original max 10,132 / avg 2,786 cycles; kanji
  max 15,833 / avg 3,430. Splitting the scans cut the peak from 21,636.

Current build: original
`40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367`;
kanji `862d7f377d11050e3eb0f4b4118b6267140cf4d3705bbb913f596bd47d78d6bb`;
overlay 2,981 bytes. The history prompt and runtime slot line are both clean
in `out/test/ktown_1100.png` and `out/test/ktown_1240.png`.

Still open: field prompts that fall back to lower tiles (the full
menu/party/item union did not fit), redraw scrolling, conditional CHR
rescan, and phase 3 content conversion.

The sections below describe the revision-3 state and are retained for
history. Where they conflict with this addendum or `STATUS.md`, the addendum
and `STATUS.md` win.

---

## 1. Build state

| Target | Result |
|---|---|
| `python decomp\build.py` | original 262,160-byte ROM, SHA-256 `40f19e179b84a4a2576d678dd97d9d1dc0925ea848841e6b030ffecfa73a8367` |
| `python decomp\build.py --target kanji` | 524,304-byte SUROM ROM, SHA-256 `ce583c7f72066119b794f3001b817e7923c71addc810ecd9e07da1cd1059c82f` |
| `python tools\bank15_lint.py --rom decomp\build\rom_kanji.nes` | 15 registered patch ranges, `bank31 == bank15` |
| Overlay | 2,247 bytes at `$7002-$78C8`; far loader copies 3,072 bytes |
| Fixed-bank hooks | 91 bytes at `$C611` |
| Far loader block | 181 bytes |
| Compiler report | 760 unique messages, 1,180 pages, `max_page_slots=11`, `min_free_with_kanji=8`, `max_meta_bytes=221`, `pages_over_capacity=0` |

The original-bank checks still pass: only banks 10, 11, 13 and 15 differ from
the base game.

---

## 2. Current architecture

### 2.1 Cartridge and banks

- NES 2.0, mapper 1 submapper 1 (SUROM), 32 × 16 KiB PRG, 8 KiB CHR RAM,
  8 KiB battery PRG RAM.
- Bank 15 is patched; bank 31 is a byte-identical mirror of patched bank 15.
- Banks 10/11 contain pointer tables and 8-byte far stubs
  (`F8 3A C6 <text bank> <addr lo/hi> <meta lo/hi>`).
- Text data lives in banks 18/19; page metadata in banks 22/23; kanji font
  in banks 16/17; overlay source in bank 24.
- The overlay executes from PRG RAM; the far loader at bank 13 `$8317`
  (copied to `$0601`) installs it when the `$7000` signature is wrong.

### 2.2 SRAM map (`$6800-$7FFF`)

| Range | Use |
|---|---|
| `$6800-$681F` | one 1bpp glyph (32 bytes) |
| `$6820-$685F` | four expanded 2bpp tiles (64 bytes) |
| `$6860-$687F` | code/escape/bank/CHR job/TMP/BUFX variables |
| `$6880-$688F` | `KANJI_DIRTY` (lower 128 tiles) |
| `$6890-$6891` | kana-font copy signature (`KA`) |
| `$68A0-$68AF` | `KANJI_RESIDENT` (lower 128 tiles hold kana) |
| `$68B0-$68BF` | currently unused |
| `$68C0-$68CF` | scan/page counters and flags |
| `$68D0-$68DF` | NMI CHR/nametable scratch buffer |
| `$68E0-$68E8` | NMI-only scratch |
| `$68F0-$68FF` | `KANJI_SCREEN` while a message is open; `KANJI_VISIBLE` at message exit (shared lifetime) |
| `$6920-$69E0` | runtime page: count + up to 32 × 6 bytes |
| `$69F0-$69FF` | runtime page used-tile bitmap |
| `$6A00-$6DFF` | 1 KiB copy of the bank-9 kana font |
| `$6E00-$6FFF` | per-message page metadata (512 bytes) |
| `$7000-$7001` | `KO` overlay signature |
| `$7002-$7FFF` | overlay (2,247 bytes used, max 3,070) |

### 2.3 Page metadata

Message header at the metadata address in bank 22/23:

```
byte 0: page count
byte 1: payload length low  (currently informational)
byte 2: payload length high (currently informational)
```

The overlay copies a fixed 512 bytes from `meta_addr + 3` into `KANJI_META`.
Payload cap in the compiler is 509 bytes.  Current maximum is 221.

Per page:

```
count
16-byte used bitmap        (bit 0 = tile 0 -> bitmask $80)
count * (code_lo, code_hi)
```

At page start the overlay expands this into the runtime page at `$6920`:

```
count
count * (code_lo, code_hi, tile0, tile1, tile2, tile3)
```

`KANJI_META_PTR` advances by `17 + 2*count` per page.  The first page is
loaded by `meta_load`; `ctrl_store` loads the next page when `$FC` is stored.

### 2.4 Runtime scan and allocation

At message open (`kanji_far.asm` @meta):

1. `scan_start` clears `KANJI_RESIDENT` and `KANJI_SCREEN`, sets both scan
   jobs active.
2. `scan_wait` busy-waits on `frame_counter` for up to 40 frames.
   - CHR scan: 8 tiles/frame, 128 tiles total (16 frames).
   - Nametable scan: 64 bytes/frame, `$2000-$23FF` (16 frames).
   - The two scans run in parallel in the NMI job runner.
3. `meta_load` copies the page payload and calls `page_alloc` for page 1.

Allocation at page start (`page_alloc`):

- Scan tile numbers 0-127 in order.
- Accept only `resident ∧ ¬page_used ∧ ¬screen`.
- Allocate four distinct tiles per kanji; store them in the runtime page.
- Clear the allocated tile's bit in the runtime `PAGE_USED` copy so the same
  tile is not allocated twice; because the scan position also advances, the
  next entry never revisits it.
- If fewer than four tiles are available, fill the remaining slots with
  `$0A` (blank); the handler draws four blank cells instead of corrupting
  CHR.
- `KANJI_PAGES_LEFT` counts remaining pages; `ctrl_store` blanks the page if
  metadata runs out.

`KANJI_EC` searches the runtime page by code and writes the four tile
numbers to `$0300/$0301/$0318/$0319` (TL/TR/BL/BR).

### 2.5 CHR upload and restore

- `upload_glyph` reads the 32-byte 1bpp glyph from bank 16/17, expands each
  quadrant to 16 bytes (plane 0 = font, plane 1 = 0), sets
  `KANJI_CHR_TILES[0..3]`, `KANJI_CHR_COUNT=4`, `KANJI_CHR_FLAG=1`, and
  waits for the NMI `chr_upload` to clear the flag.
- Upload marks the four tiles dirty and clears their resident bits.
- `KANJI_DIRTY_ANY` gates the NMI rendering-off restore.
- `restore_tile` reads the 8-byte kana glyph from `KANA_FONT` (16-bit offset),
  writes 16 bytes to CHR through the same upload job, sets the resident bit
  and clears the dirty bit.
- `kana_prepare` is installed at every `jsr text_put_tile` site in bank 15
  (six sites) and two bank-13 name-list sites.  It computes the bottom tile
  for the character and restores it if the resident bit is clear.
- `restore_exit` at `$D1FA` builds `KANJI_VISIBLE` from the `$0180-$01DF`
  and `$0300-$03BF` buffers and restores every dirty tile that is **not**
  referenced there.  Visible prompt kanji survive; menus drawn outside the
  text engine get kana back.
- `restore_job` in NMI restores up to four dirty tiles per frame when
  `ppu_mask_shadow & $18 == 0` (rendering off).
- `redraw_hook` at `$D388` calls `text_redraw_lines`, then re-uploads any
  runtime-page entry that has at least one resident tile again.  It has not
  been exercised by a scripted scrolling test.

### 2.6 NMI entry

Fixed bank `$EE7F` is patched to `jmp nmi_entry_guard`:

```
nmi_entry_guard:
    jsr check_sig
    bne @orig
    jmp RAM_NMI_ENTRY
@orig:
    lda nmi_busy
    bne @busy
    jmp $EE83
@busy:
    jmp $EEE0
```

Overlay `nmi_entry_ram`:

```
    lda nmi_busy
    bne @busy
    lda PPUSTATUS      ; clear vblank before any CHR work
    lda #1
    sta KANJI_NMI_DONE
    lda #0
    sta PPUMASK
    jsr nmi_jobs
    jmp $EE83
@busy:
    jmp $EEE0
```

`nmi_jobs` = `chr_upload`, `scan_job`, `restore_job`.
The palette guard at `$EECB` calls `nmi_hook`, which runs the jobs only if
`KANJI_NMI_DONE` is zero (fallback path), then jumps to `flush_palette`.

This placement is important: the old pre-handler upload did CHR work before
`PPUSTATUS` was read and caused vblank-flag NMI re-entry and stack growth.

### 2.7 Fixed-bank patch ranges

All registered in `tools/bank15_lint.py`:

| Range | Purpose |
|---|---|
| `$C4B7-$C4B9` | `jmp` SUROM switcher |
| `$C611-$C675` | switcher, far stub, signature check, NMI entry/palette guards |
| `$CC02-$CC04` | `jsr kana_prepare` (menu text) |
| `$D1FA-$D1FC` | `jmp restore_exit` |
| `$D28E-$D290` | `jmp text_dispatch` |
| `$D2BB-$D2BD` | `jsr kana_prepare` (main message path) |
| `$D2C7-$D2C9` | `jsr ctrl_store` |
| `$D32B-$D32D` | `jsr kana_prepare` (word handler) |
| `$D388-$D38A` | `jsr redraw_hook` |
| `$D4C0-$D4C2` | `jsr kana_prepare` (name handler) |
| `$D57D-$D57F` | `jsr kana_prepare` (item name) |
| `$D582-$D584` | `jsr kana_prepare` (item name) |
| `$D5C0-$D5C2` | `jsr kana_prepare` (item name) |
| `$EE7F-$EE81` | `jmp nmi_entry_guard` |
| `$EECB-$EECD` | `jsr nmi_palette_guard` |

Bank 13 is patched **post-assembly** in `decomp/build.py` at `$9023` and
`$905B` (`jsr text_put_tile` -> `jsr kana_prepare`).  These two sites are not
covered by the bank-15 lint; re-audit them if bank 13 changes.

---

## 3. Verified behaviour and evidence

- History prompt renders as one page:
  `どの歴史書を登録しますか?`, with the 1-3 menu above it.
  Evidence: `out/test/kanji_prompt_one_page.png` (from
  `tools/lua/prompt_pages.lua`).
- Name-entry grid after selection is clean:
  `out/test/kanji_name_entry_clean.png`.
- Field command menu is clean after the message-exit restore:
  はなす / しらべる / たいねつ / ふじょう / どうぐ.
  Evidence: `out/test/kanji_field_menu_clean.png`.
- Field map tiles are intact through frame 6,000:
  `out/test/kanji_field_map_clean.png`.
- A 6,000-frame scene run reaches the field and does not hang; the earlier
  `$73D0` hang was specific to the reverted NMI CHR prototype.
- SRAM write watch over `$6800-$7FFF` for 6,000 frames: every write comes
  from the RAM far loader (`$0600-$06FF`) or the overlay (`$7002-$7FFF`).
  No base-game writes.
- Original ROM still byte-identical.

---

## 4. Measurements

### 4.1 Scene CHR survey (original ROM)

`tools/lua/scene_survey.lua` dumps CHR every 60 frames to frame 6,000 and a
screenshot every 240 frames.

| Frame | Observation |
|---|---|
| 0060-1560 | all 128 kana tiles match the bank-9 font |
| 1620 | 26 tiles missing: `$42-$5B` (oath scene portraits) |
| 2340 | all 128 kana restored |
| 4260 | 23 tiles missing: `$00-$17` (town/field transition) |
| 4320 | all 128 kana restored |

Worst measured borrowing is 26 tiles.  This is
`SCENE_BORROW_ALLOWANCE = 26` in `tools/kanji_text.py` and is applied to
ordinary pages.  Prompt pages use an allowance of 8 because they already
reserve the menu kana stream.

### 4.2 Compiler

From `decomp/build/kanji/kanji_text_report.json`:

```json
{
  "inventory": 718,
  "messages": 760,
  "pages": 1180,
  "max_page_slots": 11,
  "min_free_with_kanji": 8,
  "pages_over_capacity": 0,
  "scene_borrow_allowance": 26,
  "reserved_count": 24,
  "menu_stream_tiles": 76,
  "party_name_tiles": 57,
  "item_name_tiles": 62,
  "max_meta_bytes": 221,
  "data_banks": [18, 19]
}
```

`RESERVED_TILES` is frame/cursor/digit tiles plus `$6C` (金) and `$7F` (兵),
which the field map uses as icons.

### 4.3 Scan cost

The CHR and nametable scans run in parallel: roughly 16 frames if both complete
at budget, with a hard timeout at 40 frames.  The screenshots show no visible
top-of-screen glitch, but this has not been measured on hardware and the NMI
budget shares vblank with the existing VRAM queue.

---

## 5. Known issues

### 5.1 Runtime save-slot names collide with prompt kanji (open)

The history slot menu prints a save-slot name and `L64` **after** the prompt
has opened.  The name is drawn from save data and may use any kana tile.
The prompt's kanji allocation cannot see it, so the menu overwrites one or
more kanji tiles.

Evidence (`tools/lua/town_kanji.lua`, current build):

- `out/test/ktown_1100.png`: prompt reads
  `どの歴史書 始 をメロめますか?`; slot line reads `1 くわO L64`.
- `out/test/ktown_1240.png`: same, with the choice menu
  `はやい / ふむう / おそい` open and clean.

The nametable scan cannot help because the slot menu is drawn later.  Options
for the next iteration:

1. **Convert the slot menu to the kanji-aware drawer** and give it dedicated
   slots (preferred; fits phase 3/4).
2. **Decode the displayed save-slot name at message open** and reserve its
   exact tiles.  Fragile, but small if the save format is decoded.
3. **Use upper CHR tiles ($80-$FF) for prompt kanji.**  This needs a change
   to the text engine: `text_render_cell` at `$DBEF` uses `bpl` on
   `$0300,y`, so any tile >= 128 is treated as a control.  That check must
   change to a `>= $FA` test (no room at the current site; needs a larger
   patch/trampoline), then the upper-half scan/blank bitmap and
   restore-to-zero path can be added.
4. **Kana relocation** (tried and reverted): when a menu draw hits a
   kanji-owned tile, copy the kana glyph to a free resident tile and redirect
   that draw.  This produced new corruption in the field name list
   (`*1ンプ1`, `*111`) because free tiles' original kana glyphs were
   overwritten and/or some menu draws bypass the hook.  Not in commit
   `a3f8b8d`.

### 5.2 Redraw re-upload is unverified

`redraw_hook` is installed and the logic is in place, but no current test
message scrolls four lines, so the path has not been exercised by a
screenshot test.

### 5.3 Inline scripts and tables remain kana

The intro/oath lines, several town/event lines, WORD/PLACE/ITEM tables, and
runtime name records still use the original kana.  These are PLAN.md phase 3
tasks.  The current indexed-message compiler covers banks 10/11 only.

### 5.4 Scan delay and NMI budget

The message-open scan costs roughly 16 frames.  If the VRAM queue is busy at
the same time, the NMI handler may exceed vblank.  The current screenshots do
not show a glitch, but this needs a hardware or cycle-accurate check.
Possible mitigations: cache the resident/screen bitmaps per scene, reduce the
CHR scan to 4 tiles/frame, or move the nametable scan to a slower background
job.

### 5.5 Overlay headroom is limited

The far loader copies 3,072 bytes; code uses 2,247, leaving 823 bytes.  A
previous attempt to copy 4,096 bytes produced NMI/BRK storms during the first
message.  The exact cause was not fully isolated (zeroing `$7C02-$7FFF`
and/or copy duration were candidates).  Do not raise the copy length without
a fresh bisect and a 6,000-frame run.

### 5.6 Runtime capacity margin

`min_free_with_kanji` is 8.  The runtime nametable scan can reserve additional
tiles beyond the compiler's `PAGE_USED` bitmap; if it consumes the 8-tile
margin, `page_alloc` blanks the remaining kanji ($0A) instead of corrupting
CHR.  This is deliberate but should be monitored in new scenes.

---

## 6. Failed or reverted experiments

- **NMI CHR save/restore prototype** (pre-revision 3): read/wrote CHR from a
  wait loop inside NMI; caused NMI re-entry and stack growth on the outdoor
  map.  Reverted.
- **Pre-handler `chr_upload` at `$EE7F`**: unsafe CHR access before
  `PPUSTATUS`; replaced by the PPUSTATUS-first overlay entry.
- **4,096-byte overlay copy**: caused BRK/NMI storms on the first message;
  reverted to 3,072 bytes.
- **Menu kana relocation**: redirected conflicting menu kana to free resident
  tiles; corrupted the field name list.  Reverted; not in the current commit.

---

## 7. Recommended next iteration (ordered)

1. **Fix the runtime save-slot name collision.**
   Preferred: convert the history slot menu to the kanji-aware drawer and
   reserve dedicated slots.  Alternative: decode the save-slot name and mark
   its tiles in `KANJI_SCREEN` at message open.  Do not retry the naive kana
   relocation without a plan for preserving the destination tiles' original
   glyphs and covering every menu draw path.
2. **Exercise redraw.**
   Find or construct a message with four visible lines, let it scroll, and
   verify that restored tiles are re-uploaded from `redraw_hook`.
3. **Phase 3: inline scripts, tables, names.**
   Move bank-15/bank-13 inline menu/oath strings into indexed messages;
   convert WORD/PLACE/ITEM tables and name records.  The compiler already
   reserves table/name tiles; the missing piece is the content conversion and
   any new inline-message plumbing.
4. **Phase 4: UI screens.**
   Status, inventory, name-entry labels, and the history slot menu.
5. **Measure the NMI budget on hardware / cycle-accurate.**
   Confirm no top-of-screen glitches at the fastest text speed with a busy
   VRAM queue.  If needed, reduce scan batch sizes or cache per scene.
6. **QA and release.**
   Scripted render of all 872 messages; Mesen and EverDrive N8 playthrough;
   BPS patch.

---

## 8. Open decisions for Fable

1. Should prompt kanji use upper CHR tiles?  This requires changing the
   text-engine control test at `$DBEF` and adding upper-half scan/restore
   state.  It would preserve all lower kana for runtime names, at the cost of
   a more invasive text-engine patch.
2. Can the save-slot name be decoded from SRAM reliably enough to reserve its
   tiles?  If yes, that is a much smaller fix than upper CHR.
3. Is the menu kana stream in `MENU_TILES` (bank 15 `$2948-$2DA1`) complete?
   The history slot line uses additional runtime name tiles, so the answer is
   currently no for that one screen.
4. Is the 8-tile prompt margin enough across all scenes?  Instrument
   `page_alloc` failures (blank slots) and log them per message.
5. Should the scan be cached per scene?  It currently runs at every message
   open; caching would require a reliable CHR-change signal.

---

## 9. File map

| Path | Role |
|---|---|
| `PLAN.md` | revision-3 work list and progress appendix |
| `STATUS.md` | verified state, blockers, commands |
| `CHANGELOG.md` | implementation history including this pass |
| `SITREP.md` | this handoff |
| `decomp/build.py` | original/kanji build, bank-13 post-assembly patches |
| `tools/kanji_build.py` | overlay/hooks/far/bank15/bank31 orchestration |
| `tools/kanji_text.py` | text compiler, reservations, page metadata |
| `tools/asm/kanji_fixed.asm` | `$7002` overlay, dispatcher, renderer, NMI jobs |
| `tools/asm/kanji_far.asm` | bank-13 RAM far loader and overlay install |
| `tools/asm/surom_b15.asm` | `$C611` SUROM switcher, far stub, NMI guards |
| `decomp/include/kanji.inc` | SRAM map, signatures, fixed-bank symbols |
| `tools/bank15_lint.py` | bank15 patch-range and bank31 mirror check |
| `tools/lua/scene_survey.lua` | 6,000-frame scene/CHR survey |
| `tools/lua/prompt_pages.lua` | one-page prompt and name-entry capture |
| `tools/lua/town_kanji.lua` | history prompt -> field sequence |
| `tools/lua/sram_watch.lua` | `$6800-$7FFF` write audit |

## 10. Commands

```powershell
python decomp\build.py
python decomp\build.py --target kanji
python tools\bank15_lint.py --rom decomp\build\rom_kanji.nes

python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\prompt_pages.lua --name prompt_pages
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\town_kanji.lua --name ktown
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\scene_survey.lua --name survey_kanji
python tools\mesen_run.py "Tenchi o Kurau (Japan) (Rev 1).nes" tools\lua\scene_survey.lua --name survey_orig
python tools\mesen_run.py decomp\build\rom_kanji.nes tools\lua\sram_watch.lua --name kanji_sram_watch
```

Outputs land in `out/test/`.  `out/` is gitignored except for the milestone
screenshots that were force-added.
