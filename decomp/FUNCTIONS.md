# Routine index

This file is generated from the Mesen CDL trace and the routine names in
`tools/symbols.py`.  Names are working names: they describe the observed
behavior and call graph, not original source symbols.  Addresses are CPU
addresses inside each PRG bank.

`loc_XXXX` labels are intra-routine branch targets and are intentionally
not listed as separate routines.

Sizes are approximate: routines that use inline data after a JSR (text or
pointer tables) can appear shorter in this table than the bytes they occupy.

## Bank 07  ($8000-$BFFF)

| Address | Name | Approx. bytes | Callers | Summary |
|---:|---|---:|---:|---|
| `$9400` | `b07_entry` | 3 | 0 | Bank 7 entry point (thunk to the party screen setup). |
| `$9403` | `b07_enter_party_screen` | 3 | 0 | Front-end part of the party screen: draw the title, wait, and call the list-drawing routine. |
| `$942D` | `b07_run` | 41 | 0 | Bank 7 main runner/dispatch. |
| `$951F` | `b07_wait_and_draw` | 46 | 3 | Wait/draw loop used by the party screen. |
| `$9559` | `b07_delay_frames` | 16 | 15 | Delay for A frames while servicing the screen. |
| `$9C5F` | `b07_party_screen_setup` | 156 | 0 | Party/list screen setup: window, graphics, and bank switches. |
| `$9CBE` | `b07_party_list_draw` | 61 | 1 | Draw the party/list screen entries. |
| `$9CD7` | `b07_party_list_input` | 36 | 0 | Party/list screen input/menu handling. |
| `$9D68` | `b07_screen_fade_in` | 12 | 2 | Fade the screen in before the list is drawn. |
| `$9D74` | `b07_party_list_page` | 71 | 1 | Draw one page of the party/list screen. |
| `$9E00` | `b07_party_member_setup` | 97 | 1 | Load a party member's actor/stats and prepare the battle-party arrays. |

### Inline RAM routines

| Source address | Name | Bytes |
|---:|---|---:|
| `$9527` | `inline_9527` | 38 |
| `$9C88` | `inline_9C88` | 11 |
| `$9D1A` | `inline_9D1A` | 15 |
| `$9DC5` | `inline_9DC5` | 24 |
| `$9E52` | `inline_9E52` | 15 |

## Bank 08  ($8000-$BFFF)

| Address | Name | Approx. bytes | Callers | Summary |
|---:|---|---:|---:|---|
| `$8000` | `sound_update` | 3 | 2 | Sound driver tick/update entry. |
| `$8003` | `sound_play` | 344 | 1 | Sound driver command entry (A = command, X = parameter). |
| `$8129` | `sound_stop` | 4 | 0 | Stop the current sound. |
| `$812D` | `sound_pause` | 13 | 0 | Pause/resume sound output. |
| `$816C` | `sound_channel_start` | 99 | 2 | Start/restart one sound channel from its current pattern. |
| `$818C` | `sound_channel_stop` | 38 | 0 | Stop a channel and clear its state. |
| `$81B2` | `sound_channel_clear` | 18 | 3 | Clear one channel's 16-byte working area. |
| `$8207` | `sound_channel_next` | 18 | 3 | Advance the channel's pattern pointer and update the loop count. |
| `$8211` | `sound_channel_advance` | 8 | 1 | Advance the channel pointer by one record. |
| `$8219` | `sound_channel_shift` | 9 | 2 | Shift/scale the channel's note value. |
| `$8222` | `sound_channel_enable` | 19 | 3 | Enable/disable an APU channel and write its initial registers. |
| `$8235` | `sound_sequencer_update` | 175 | 0 | Main sequencer tick: walk active channels and decode the next event. |
| `$82E4` | `sound_calc_volume` | 529 | 0 | Calculate the current volume/envelope value. |
| `$850E` | `sound_note_reset` | 50 | 3 | Reset the per-note state after a new note/rest. |
| `$854E` | `sound_dispatch` | 23 | 2 | Dispatch through the note/command jump table. |
| `$8565` | `sound_decode_pattern` | 493 | 1 | Decode one pattern event (note, duration, instrument). |
| `$8698` | `sound_fetch_byte` | 20 | 7 | Fetch the next byte from the current music stream. |
| `$86AC` | `sound_update_envelope` | 15 | 1 | Advance the envelope and volume state. |
| `$86BB` | `sound_update_pitch` | 295 | 1 | Advance the pitch/slide state. |
| `$86CB` | `sound_update_noise` | 279 | 1 | Advance the noise/percussion state. |
| `$86FE` | `sound_command_parser` | 228 | 1 | Parse the next sound command/control byte. |
| `$88A1` | `sound_set_duty` | 30 | 2 | Set the current channel duty cycle. |
| `$88D9` | `sound_load_instrument` | 54 | 2 | Load an instrument definition into the channel state. |
| `$892D` | `sound_stream_read` | 31 | 13 | Read one byte from the active music stream and advance its pointer. |
| `$894C` | `sound_set_duration` | 33 | 2 | Calculate and store the current note duration. |

## Bank 13  ($8000-$BFFF)

| Address | Name | Approx. bytes | Callers | Summary |
|---:|---|---:|---:|---|
| `$8800` | `b13_load_status_screen` | 41 | 1 | Load the officer status screen and its graphics. |
| `$88D0` | `b13_load_officer_palette` | 53 | 2 | Load the palette for the current officer. |
| `$8CF2` | `b13_copy_name_tiles` | 44 | 2 | Copy/decompress the 16x16 name tiles. |
| `$911A` | `b13_officer_status_menu` | 12 | 1 | Officer status menu main loop. |
| `$9173` | `b13_officer_status_exit` | 20 | 0 | Exit the officer status menu. |
| `$9187` | `b13_officer_status_input` | 137 | 1 | Officer status input/cursor update. |
| `$9210` | `b13_draw_officer_portrait` | 57 | 3 | Draw the officer portrait. |
| `$924C` | `b13_queue_portrait_tile` | 53 | 2 | Queue a portrait tile update. |
| `$9254` | `b13_queue_cursor_tile` | 45 | 2 | Queue a cursor tile update. |
| `$9260` | `b13_queue_tile` | 33 | 1 | Queue one tile update at the current PPU cursor. |
| `$9281` | `b13_queue_name_tile` | 27 | 2 | Queue a name tile update. |
| `$928B` | `b13_queue_name_tile2` | 17 | 1 | Queue a name tile update (variant). |
| `$929C` | `b13_officer_status_draw` | 112 | 1 | Draw/update the officer status screen. |
| `$98E7` | `b13_fade_out_wait` | 135 | 1 | Fade the screen out and wait for the transition. |
| `$9C00` | `b13_find_first_party` | 118 | 0 | Find the first active party member. |
| `$9C7A` | `b13_init_name_entry` | 27 | 7 | Initialise the name-entry screen. |
| `$9CA0` | `b13_expand_name_tile` | 22 | 4 | Expand one packed name tile. |
| `$9CB6` | `b13_pack_name_tile` | 8 | 1 | Pack/rotate one name-entry tile into the tile buffer. |
| `$9CC6` | `b13_check_name_tile` | 8 | 1 | Check/expand a packed name tile and set carry on failure. |
| `$9F63` | `b13_name_entry_screen` | 72 | 1 | Name-entry screen setup. |
| `$9FAB` | `b13_loc_9FAB` | 47 | 1 |  |
| `$A075` | `b13_name_entry_input` | 109 | 0 | Name-entry cursor/input handler. |
| `$A0F3` | `b13_officer_status_init` | 126 | 1 | Initialise the officer-status/gameplay handoff after name entry. |

### Inline RAM routines

| Source address | Name | Bytes |
|---:|---|---:|
| `$881A` | `inline_881A` | 15 |
| `$9213` | `inline_9213` | 54 |
| `$967A` | `inline_967A` | 15 |
| `$A157` | `inline_A157` | 26 |

## Bank 14  ($8000-$BFFF)

| Address | Name | Approx. bytes | Callers | Summary |
|---:|---|---:|---:|---|
| `$8000` | `b14_game_bank_entry` | 150 | 2 | Entry point for the gameplay/menu bank, called from the fixed bank. |
| `$8020` | `b14_menu_dispatch` | 118 | 0 | Menu/command dispatch for the current game mode. |
| `$8074` | `b14_menu_input` | 39 | 0 | Menu cursor/input update. |
| `$8385` | `b14_close_menu` | 16 | 2 | Close the current menu and restore the text engine. |
| `$8395` | `b14_status_screen` | 161 | 0 | Officer status screen setup. |
| `$83B2` | `b14_status_update` | 132 | 0 | Officer status screen per-frame update. |
| `$842F` | `b14_init_battle_party` | 61 | 6 | Initialise the battle party arrays. |
| `$846C` | `b14_battle_party_loop` | 51 | 0 | Battle party initialisation loop. |
| `$84FE` | `b14_party_status_update` | 33 | 1 | Update the party status panel. |
| `$867D` | `b14_delay_frames` | 9 | 1 | Delay for a fixed number of frames. |
| `$8948` | `b14_check_party_slot` | 16 | 1 | Check whether a party slot is empty. |
| `$959E` | `b14_field_transition_a` | 27 | 0 | Field/battle transition: restore the field screen and graphics. |
| `$9B73` | `b14_field_transition_b` | 6 | 0 | Field/battle transition: return to the field and refresh the party. |
| `$9B79` | `b14_field_transition_body` | 15 | 1 | Body of the field/battle transition routine. |
| `$B40E` | `b14_officer_list_screen` | 121 | 0 | Officer list/roster screen. |
| `$B487` | `b14_init_party_slots` | 6 | 0 | Initialise the seven party slots. |
| `$B48D` | `b14_init_party_loop` | 9 | 2 | Loop over the seven party slots. |
| `$B496` | `b14_copy_active_party` | 15 | 1 | Copy active party members into the battle arrays. |
| `$B4A5` | `b14_copy_party_stats` | 22 | 1 | Copy one member's stats to the battle array. |
| `$B4C5` | `b14_party_member_setup` | 124 | 1 | Set up one party member's battle record. |
| `$B791` | `b14_officer_status_screen` | 170 | 1 | Officer status screen and stat display. |
| `$B855` | `b14_find_injured_member` | 47 | 1 | Find a party member with the $C0/injured state bit. |
| `$B863` | `b14_calc_party_stat` | 33 | 1 | Calculate a party member's derived stat. |
| `$BC79` | `b14_scan_bank7_table_a` | 266 | 1 | Scan a bank 7 table for a matching map/position entry (variant A). |
| `$BD77` | `b14_scan_bank7_table_b` | 114 | 1 | Scan a bank 7 table for a matching map/position entry (variant B). |
| `$BEFF` | `b14_battle_setup_tail` | 10 | 1 | Tail of the battle setup: item category and display refresh. |
| `$BF09` | `b14_battle_setup` | 61 | 2 | Set up the battle/field display for the current game mode. |
| `$BF46` | `b14_get_item_category` | 32 | 3 | Look up an item's category/equipment slot. |
| `$BF66` | `b14_draw_battle_status` | 43 | 2 | Draw the battle status text/selection fields. |

### Inline RAM routines

| Source address | Name | Bytes |
|---:|---|---:|
| `$84AD` | `inline_84AD` | 72 |
| `$8640` | `inline_8640` | 58 |
| `$8694` | `inline_8694` | 108 |
| `$95AA` | `inline_95AA` | 15 |
| `$9B7E` | `inline_9B7E` | 9 |
| `$B4E0` | `inline_B4E0` | 36 |
| `$B726` | `inline_B726` | 104 |
| `$BC7C` | `inline_BC7C` | 84 |
| `$BD7A` | `inline_BD7A` | 45 |

## Bank 15  ($C000-$FFFF)

| Address | Name | Approx. bytes | Callers | Summary |
|---:|---|---:|---:|---|
| `$C000` | `main_loop` | 94 | 0 | Cooperative task scheduler and main loop entry. Each 4-byte task slot at $20..$3F has state, timer, and a continuation pointer.  State 0 is idle, 1 is timed, 2 is running, 4 is waiting, and 8 resumes at a pointer. |
| `$C003` | `task_scheduler` | 91 | 0 | Scan the four task slots and run the first ready task. Falls back to $C003 when every slot is idle. |
| `$C05E` | `task_set_continuation` | 16 | 1 | Store a continuation pointer in the current task and mark it ready. |
| `$C06E` | `task_clear` | 8 | 0 | Clear the current task's state (idle). |
| `$C08F` | `task_end` | 10 | 0 | Clear the current task and restart the scheduler. |
| `$C099` | `task_slot_from_current` | 6 | 2 | Load the current task index into A, then fall through to task_slot_from_a. |
| `$C09B` | `task_slot_from_a` | 4 | 2 | Convert A (task index) to a 4-byte task-slot offset in X. |
| `$C09F` | `wait_vblank` | 54 | 43 | Wait for the NMI window and flush queued PPU updates. If rendering is off, switch to the scheduler before waiting. |
| `$C0BC` | `wait_frames` | 7 | 9 | Wait for X frames by repeatedly yielding. |
| `$C0CE` | `wait_frame_tick` | 7 | 3 | Frame-paced wait helper.  Only acts when the low nibble of $33 is zero. |
| `$C0D5` | `update_frame` | 22 | 12 | Per-frame input/UI update. Polls the controller, updates sprites, and yields to the scheduler. |
| `$C0EB` | `update_frame_no_input` | 16 | 4 | Per-frame update variant that skips controller polling while a button is held. |
| `$C0F2` | `ppu_nmi_off` | 10 | 5 | Clear PPUCTRL bit 7 (disable NMI) and write the shadow. |
| `$C0FC` | `ppu_nmi_on` | 10 | 8 | Set PPUCTRL bit 7 (enable NMI) and write the shadow. |
| `$C106` | `one_minus_a` | 6 | 1 | Return 1 - A (ones-complement helper). |
| `$C10C` | `dispatch_return_table` | 22 | 4 | Dispatch through a table that follows the JSR return address. A selects the word entry; the return address is advanced past the table. |
| `$C122` | `ppu_bg_sprites_off` | 10 | 3 | Disable background and sprite rendering (PPUMASK bits 3-4). |
| `$C132` | `ppu_bg_sprites_off_shadow` | 10 | 3 | Disable background/sprite rendering in the shadow only. |
| `$C13F` | `screen_fade_in_step` | 21 | 3 | Advance one step of the screen fade-in state machine. |
| `$C145` | `screen_fade_in` | 12 | 9 | Enable NMI, restore the mask, yield, and step the fade state. |
| `$C151` | `screen_fade_out` | 10 | 6 | Begin a screen fade-out and wait. |
| `$C15B` | `rng_seed` | 83 | 4 | Seed the 24-bit LFSR from $10/$11/$16. |
| `$C15F` | `rng_next` | 79 | 1 | Advance the 24-bit LFSR (used for random encounters and battle rolls). |
| `$C1B3` | `mul16x8_shift` | 31 | 1 | Shift/multiply helper used by the RNG and battle math. |
| `$C1D2` | `div24_shift` | 69 | 1 | 24-bit shift/divide helper. |
| `$C25A` | `fetch_inline_word` | 38 | 9 | Fetch the word that follows the caller's JSR. Used by inline text and inline pointer data. |
| `$C280` | `read_controller` | 43 | 1 | Poll controller 1 and update $F5/$F7. The previous state is kept for edge detection. |
| `$C2AB` | `set_ppu_scroll` | 60 | 5 | Set PPU scroll/address registers from A/X/Y. |
| `$C2E7` | `fill_ram_block` | 24 | 4 | Fill a block of CPU RAM/PPU memory with a constant. |
| `$C2FF` | `flush_palette` | 50 | 2 | Upload a pending palette block through the VRAM helper. |
| `$C331` | `write_vram_block` | 107 | 3 | Write a block of bytes to PPUDATA from a RAM pointer. |
| `$C33A` | `copy_to_vram` | 107 | 7 | Copy a block from CPU memory to PPUDATA. |
| `$C3A5` | `vram_ptr_add8` | 20 | 3 | Add 8 to the 16-bit VRAM pointer in $00/$01. |
| `$C3A7` | `vram_ptr_add` | 18 | 1 | Add A to the 16-bit VRAM pointer in $00/$01. |
| `$C3B9` | `vram_put_tile_loop` | 53 | 5 | Write a run of bytes to PPUDATA from the current pointer. |
| `$C3CE` | `vram_put_run` | 32 | 2 | Write a run of bytes to PPUDATA with a fixed tile value. |
| `$C3E0` | `vram_put_tile_xor` | 14 | 1 | Write 8 bytes to PPUDATA XORed with a constant. |
| `$C3EE` | `read_inline_rect` | 75 | 1 | Read an inline rectangle/table descriptor and copy four bytes to $02-$06. |
| `$C439` | `ppu_init` | 39 | 13 | Initialise PPU registers, palette, scroll, and OAM shadow. |
| `$C43C` | `clear_screen` | 36 | 1 | Clear the screen and reset PPU state. |
| `$C44E` | `clear_oam_shadow` | 18 | 2 | Hide all 64 sprites in the OAM shadow. |
| `$C452` | `hide_sprites` | 14 | 2 | Write $F8 (offscreen Y) to every sprite in the OAM shadow. |
| `$C460` | `mmc1_reset` | 30 | 2 | Reset the MMC1 shift register and map bank 14. |
| `$C468` | `mmc1_init` | 22 | 1 | Initialise MMC1 control/PRG registers. |
| `$C47E` | `set_bank_current` | 32 | 11 | Map the bank stored in $43 at $8000. |
| `$C480` | `set_bank_a` | 30 | 7 | Map bank A at $8000 and update both current-bank variables. |
| `$C482` | `set_bank_b` | 28 | 42 | Map bank A at $8000; used for temporary data access. |
| `$C484` | `set_bank_lock` | 26 | 2 | Map bank A at $8000, waiting for a pending NMI bank restore. |
| `$C49E` | `set_bank_12` | 45 | 4 | Map bank 12 at $8000. |
| `$C4A2` | `set_bank_13` | 41 | 6 | Map bank 13 at $8000. |
| `$C4A6` | `set_bank_14` | 37 | 5 | Map bank 14 at $8000. |
| `$C4AA` | `restore_bank_after_nmi` | 33 | 2 | Restore the bank that was active before NMI. |
| `$C4B7` | `write_prg_bank` | 20 | 3 | Serialise A into the MMC1 PRG bank register. |
| `$C4CF` | `sound_queue_add_once` | 21 | 3 | Queue a sound command only when it differs from the last one. |
| `$C4D5` | `sound_queue_add` | 15 | 13 | Append a sound command to the 8-entry ring buffer at $E8. |
| `$C4E4` | `call_inline_block` | 23 | 18 | Copy the 255-byte inline block after the JSR to $0600 and jump to $0601. The block executes from RAM with a different PRG bank mapped; it must end with return_inline_block/JMP C4FB. |
| `$C4FB` | `return_inline_block` | 31 | 16 | Return from a call_inline_block block: restore the caller's bank and resume at the saved bank address. |
| `$C51A` | `draw_text_window_small` | 140 | 7 | Draw a compact text window (status/menu variant). |
| `$C522` | `draw_window` | 132 | 9 | Draw the standard dialogue/menu window frame. |
| `$C5A6` | `load_text_graphics` | 73 | 14 | Load the tile set for the current text/menu page. |
| `$C6D2` | `draw_portrait` | 173 | 1 | Draw a 16x16 portrait/actor tile block. |
| `$C783` | `set_cursor_from_table` | 32 | 2 | Set the text cursor from a two-byte table entry and save it. |
| `$C793` | `set_cursor_no_save` | 16 | 1 | Set the text cursor from a table without saving. |
| `$C7AB` | `set_actor_palette` | 22 | 7 | Set an actor's palette/facing bits. |
| `$C7C1` | `update_oam` | 181 | 4 | Rebuild the OAM shadow from the actor arrays. |
| `$C876` | `update_oam_sprite` | 254 | 2 | Update one actor's OAM entries. |
| `$C9B0` | `reset_text_engine` | 8 | 7 | Clear the text engine and reset its cursor. |
| `$C9B8` | `text_init` | 481 | 29 | Initialise text buffers, window tiles, and cursor state. |
| `$CB92` | `text_input` | 130 | 2 | Handle text-menu input and cursor movement. |
| `$CC19` | `read_stack_arg` | 49 | 1 | Read a byte from the caller's stack frame. |
| `$CC4A` | `text_find_line` | 55 | 2 | Find the text line/actor matching the current selection. |
| `$CC81` | `text_hide` | 20 | 1 | Hide the text cursor and restore the underlying tiles. |
| `$CC95` | `text_cursor_init` | 127 | 1 | Initialise the text cursor position. |
| `$CCA7` | `text_draw_cursor` | 109 | 2 | Draw/update the blinking text cursor. |
| `$CD14` | `clear_text_state` | 11 | 2 | Clear the text-menu selection variables. |
| `$CD1F` | `text_scroll` | 256 | 1 | Scroll the text window by one row. |
| `$CD9D` | `text_wait` | 11 | 6 | Wait for text input and update the cursor. |
| `$CDB3` | `text_wait_loop` | 44 | 6 | Main text input/wait loop. |
| `$CDDF` | `text_draw_screen` | 78 | 6 | Redraw the current text screen. |
| `$CED2` | `battle_intro_screen` | 38 | 2 | Battle introduction screen: window, fade, and clear. |
| `$CF1F` | `screen_refresh` | 60 | 2 | Refresh the whole screen: palette, window, text, sprites. |
| `$CF5B` | `text_save_tiles` | 27 | 2 | Save the current text tile rows for redraw. |
| `$CF91` | `status_message` | 3 | 1 | Draw a status message and load the matching text page. |
| `$CFA9` | `text_load_page` | 219 | 5 | Load a text page/graphics set from bank 12. |
| `$D084` | `text_draw_page` | 56 | 1 | Draw the loaded text page. |
| `$D10D` | `text_print_inline` | 14 | 18 | Print the inline message reference that follows the JSR. The first word is a 16-bit message-table index (< $200: bank 10, >= $200: bank 11 with $200 subtracted), not a direct address. |
| `$D11B` | `text_reset_cursor` | 9 | 1 | Reset text cursor/line/speed state. |
| `$D124` | `text_show_message` | 218 | 1 | Open a text window and run the message bytecode interpreter. Input: $14/$15 = 16-bit message-table index.  The split low/high tables in bank 10 or 11 turn it into the actual message address. |
| `$D1FD` | `text_set_cursor` | 44 | 3 | Set the PPU cursor address from the text cursor variables. |
| `$D229` | `text_clear_line` | 136 | 1 | Clear one 24-column text line in the tile buffers. |
| `$D340` | `text_put_tile` | 29 | 9 | Write the top/bottom tile pair for one character into the tile buffers. |
| `$D35D` | `text_put_char_shadow` | 73 | 1 | Queue the bottom/alternate tile for the current text character. |
| `$D365` | `text_put_char_cursor` | 65 | 1 | Queue the cursor/underline tile for the current text character. |
| `$D36F` | `text_put_char` | 55 | 1 | Queue the top tile for the current text character. |
| `$D376` | `text_scroll_up` | 105 | 2 | Scroll the four dialogue lines up by one line. |
| `$D405` | `text_redraw_lines` | 55 | 1 | Redraw all four text lines from the tile buffers. |
| `$D43C` | `wait_then_game_main` | 6 | 0 | Wait for a keypress, then resume the main gameplay loop. |
| `$D442` | `wait_keypress` | 10 | 6 | Wait until a button edge is detected. |
| `$D456` | `text_draw_char` | 64 | 2 | Render one 8x16 character and advance the text cursor. |
| `$D4A1` | `load_party_member_stats` | 168 | 1 | Load a party member's class/stat record from bank 12. |
| `$D567` | `draw_item_name` | 35 | 1 | Draw an item/equipment name from the bank 12 text tables. |
| `$D5A5` | `load_item_data` | 36 | 2 | Load item/equipment data from bank 12. |
| `$D5BA` | `draw_string_from_pointer` | 15 | 1 | Draw a FF-terminated string through the current pointer. |
| `$D5FE` | `load_party_member_record` | 56 | 2 | Load a party member record from the $6100 array. |
| `$D636` | `find_party_member` | 28 | 1 | Find the first active party member. |
| `$D652` | `read_inline_block_3` | 94 | 1 | Read an inline pointer and copy three bytes from it. |
| `$D661` | `read_pointer_triplet` | 79 | 1 | Read three bytes through the current pointer. |
| `$D671` | `copy_pointer_triplet` | 63 | 1 | Copy a three-byte pointer/triplet. |
| `$D713` | `set_party_cursor` | 32 | 1 | Position the status cursor on a party member. |
| `$D733` | `draw_status_panel` | 65 | 2 | Draw the officer/status panel for the current game mode. |
| `$D745` | `draw_status_row` | 47 | 1 | Draw one status row. |
| `$D7A9` | `cursor_add_x` | 32 | 7 | Add A to cursor X with 15-column wrap. |
| `$D7B1` | `cursor_add_x_signed` | 24 | 9 | Add signed A to cursor X with wrap. |
| `$D7C9` | `cursor_add_y` | 32 | 7 | Add A to cursor Y with 16-row wrap. |
| `$D7D1` | `cursor_add_y_signed` | 24 | 9 | Add signed A to cursor Y with wrap. |
| `$D7E9` | `cursor_to_ppu` | 44 | 6 | Convert cursor X/Y to a nametable/PPU address in $68/$69. |
| `$D815` | `set_scroll_from_cursor` | 41 | 3 | Set scroll registers from the cursor position. |
| `$D83E` | `draw_map_area` | 274 | 2 | Draw a rectangular map area from the map data. |
| `$D953` | `tile_address` | 38 | 2 | Return the tile address for a map cell. |
| `$D97C` | `render_map_column` | 37 | 2 | Render one map column and advance the scroll. |
| `$D9A1` | `flush_vram_queue` | 76 | 3 | Flush the $0400 VRAM update queue to the PPU. |
| `$D9ED` | `draw_tile_run` | 261 | 2 | Draw a run of map/text tiles starting at the PPU cursor. |
| `$DAF2` | `draw_map_object` | 141 | 1 | Draw one map object/sprite from the object table. |
| `$DB87` | `scroll_map` | 64 | 2 | Scroll the map and redraw the exposed row/column. |
| `$DBCA` | `text_render_cell` | 197 | 1 | Render one 8x16 dialogue cell. Builds two VRAM-queue entries from $0300/$0318 and $68/$69. |
| `$DC93` | `text_draw_line` | 120 | 3 | Draw a line of text tiles into the nametable. |
| `$DD14` | `draw_string` | 83 | 16 | Draw a zero-terminated string. |
| `$DD67` | `draw_text_window` | 91 | 4 | Draw the dialogue window border and clear its interior. |
| `$DDD2` | `draw_window_box` | 178 | 1 | Draw a general window box with variable position/size. |
| `$DDDA` | `update_party_portrait` | 179 | 1 | Update a party member's portrait/class bits. |
| `$DE07` | `expand_name_tile` | 134 | 1 | Expand one packed name-entry tile into the tile buffer. |
| `$DE8D` | `load_battle_palette` | 14 | 1 | Load the battle palette and tile set. |
| `$DEA0` | `draw_battle_panel` | 28 | 2 | Draw the battle status panel. |
| `$E371` | `read_party_stat_byte` | 26 | 3 | Read one byte from a party member's bank 12 stat record. |
| `$E464` | `copy_party_stats` | 49 | 1 | Copy current party stats into the previous-stat snapshot. |
| `$E495` | `init_party_status` | 112 | 4 | Initialise the party status screen. |
| `$E55A` | `dialogue_sequence` | 95 | 1 | Run a dialogue/event sequence and restore the previous screen. |
| `$E711` | `load_party_hp` | 123 | 1 | Load a party member's troops/HP from bank 12. |
| `$E7A5` | `battle_screen` | 277 | 1 | Battle screen setup and per-frame battle UI. |
| `$E8BF` | `nop_return` | 11 | 2 | No-op returning immediately (used as a placeholder vector). |
| `$EE79` | `nmi_handler` | 323 | 0 | NMI/IRQ handler. Updates PPU registers, DMA, sound, palette/VRAM queue, and scroll. |
| `$EFC9` | `reset_init` | 169 | 0 | Reset initialisation: wait for PPU, clear RAM, set MMC1, start main loop. |
| `$F097` | `new_game_init` | 36 | 1 | Initialise a new game/party state. |
| `$F0BB` | `battle_party_init` | 19 | 2 | Initialise the battle party and switch to bank 13. |
| `$F0D7` | `enter_party_screen` | 8 | 0 | Map bank 7 and enter the party/list screen. |
| `$F0DF` | `enter_status_screen` | 8 | 0 | Map bank 13 and enter the officer status screen. |
| `$F133` | `load_game` | 23 | 1 | Load saved game data from battery-backed PRG RAM. |
| `$F14A` | `game_mode_switch` | 634 | 0 | Dispatch a new game mode/screen. |
| `$F1CD` | `game_main` | 529 | 0 | Main gameplay/field update loop. |
| `$F3F2` | `party_shift` | 47 | 1 | Shift the party order and update cached actor ids. |
| `$F421` | `update_party_sprites` | 43 | 1 | Update party member sprite/animation state. |
| `$F44C` | `get_party_member` | 46 | 2 | Look up a party member's actor id and stats. |
| `$F47A` | `update_party` | 79 | 1 | Update the party roster and map sprites. |
| `$F4C9` | `battle_calc` | 78 | 1 | Battle damage/stat calculation helper. |
| `$F523` | `random_encounter` | 39 | 0 | Random encounter check while walking. |
| `$F55C` | `draw_party_window` | 212 | 2 | Draw the party window headers. |
| `$F572` | `draw_party_status` | 190 | 2 | Draw the party status list. |
| `$F630` | `draw_party_column_a` | 25 | 1 | Draw one party status column (left). |
| `$F649` | `draw_party_column_b` | 25 | 1 | Draw one party status column (right). |
| `$F662` | `draw_party_header` | 46 | 3 | Draw the party header/name row. |
| `$F690` | `draw_party_footer` | 14 | 2 | Draw the party window footer. |
| `$F69E` | `battle_tick_thunk` | 3 | 0 | Battle tick thunk; falls through to battle_tick. |
| `$F6E8` | `battle_tick` | 6 | 0 | Battle tick wrapper. |
| `$F6EE` | `battle_update` | 47 | 1 | Per-frame battle update. |
| `$F71D` | `update_enemies` | 20 | 3 | Update all active enemies. |
| `$F731` | `enemy_action` | 53 | 1 | Run one enemy's action. |
| `$F766` | `enemy_move_a` | 21 | 1 | Move an enemy (variant A). |
| `$F77B` | `enemy_move_b` | 21 | 1 | Move an enemy (variant B). |
| `$F790` | `clamp_enemy_pos` | 30 | 2 | Clamp/wrap an enemy position. |
| `$F7AE` | `draw_enemy` | 212 | 1 | Draw one enemy and its HP/status. |
| `$F882` | `update_enemy_pos` | 90 | 1 | Update an enemy's screen position. |
| `$F8DC` | `battle_main` | 48 | 3 | Battle main loop. |
| `$F92A` | `init_battle` | 84 | 1 | Initialise battle state and actors. |
| `$F97E` | `set_battle_cursor` | 109 | 1 | Set the battle cursor to a party member. |
| `$F982` | `draw_battle_cursor` | 105 | 1 | Draw the battle cursor. |
| `$F999` | `find_next_actor` | 82 | 1 | Find the next active actor/party member. |
| `$F99C` | `find_next_actor_from_x` | 79 | 1 | Find the next active actor starting from X (no cursor-table setup). |
| `$F9EB` | `check_battle_cursor` | 37 | 1 | Check whether the battle cursor is on a valid target. |
| `$FA10` | `read_inline_offset` | 44 | 2 | Read an inline pointer and add a caller-supplied offset. |
| `$FA3E` | `load_battle_graphics` | 7 | 1 | Load battle graphics. |
| `$FA49` | `load_battle_tiles` | 7 | 1 | Load battle tile sets. |
| `$FA9D` | `read_input_state` | 55 | 2 | Read controller state with repeat/edge handling. |
| `$FBC2` | `nop_return2` | 1 | 1 | No-op returning immediately. |
| `$FFD8` | `reset_vector` | 7 | 0 | Reset vector.  Resets MMC1 and jumps to reset_init. |

