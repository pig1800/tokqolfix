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
| `$951F` | `b07_wait_and_draw` | 29 | 3 | Wait/draw loop used by the party screen. |
| `$9559` | `b07_delay_frames` | 31 | 15 | Delay for A frames while servicing the screen. |
| `$9C5F` | `b07_party_screen_setup` | 52 | 0 | Party/list screen setup: window, graphics, and bank switches. |
| `$9CBE` | `b07_party_list_draw` | 61 | 1 | Draw the party/list screen entries. |
| `$9CD7` | `b07_party_list_input` | 36 | 0 | Party/list screen input/menu handling. |
| `$9D68` | `b07_screen_fade_in` | 12 | 2 | Fade the screen in before the list is drawn. |
| `$9D74` | `b07_party_list_page` | 71 | 1 | Draw one page of the party/list screen. |
| `$9E00` | `b07_party_member_setup` | 97 | 1 | Load a party member's actor/stats and prepare the battle-party arrays. |

### Inline RAM routines

| Source address | Name | Bytes |
|---:|---|---:|
| `$9527` | `inline_9527` | 36 |
| `$9C88` | `inline_9C88` | 11 |
| `$9D1A` | `inline_9D1A` | 17 |
| `$9D55` | `inline_9D55` | 11 |
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
| `$8698` | `sound_fetch_byte` | 20 | 10 | Fetch the next byte from the current music stream. |
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
| `$8800` | `b13_load_status_screen` | 40 | 1 | Load the officer status screen and its graphics. |
| `$88D0` | `b13_load_officer_palette` | 53 | 2 | Load the palette for the current officer. |
| `$8CF2` | `b13_copy_name_tiles` | 44 | 2 | Copy/decompress the 16x16 name tiles. |
| `$911A` | `b13_officer_status_menu` | 12 | 1 | Officer status menu main loop. |
| `$9173` | `b13_officer_status_exit` | 20 | 0 | Exit the officer status menu. |
| `$9187` | `b13_officer_status_input` | 137 | 1 | Officer status input/cursor update. |
| `$9210` | `b13_draw_officer_portrait` | 35 | 4 | Draw the officer portrait. |
| `$924C` | `b13_queue_portrait_tile` | 53 | 2 | Queue a portrait tile update. |
| `$9254` | `b13_queue_cursor_tile` | 45 | 2 | Queue a cursor tile update. |
| `$9260` | `b13_queue_tile` | 33 | 1 | Queue one tile update at the current PPU cursor. |
| `$9281` | `b13_queue_name_tile` | 27 | 2 | Queue a name tile update. |
| `$928B` | `b13_queue_name_tile2` | 17 | 1 | Queue a name tile update (variant). |
| `$929C` | `b13_officer_status_draw` | 149 | 1 | Draw/update the officer status screen. |
| `$98E7` | `b13_fade_out_wait` | 135 | 1 | Fade the screen out and wait for the transition. |
| `$9C00` | `b13_find_first_party` | 118 | 1 | Find the first active party member. |
| `$9C7A` | `b13_init_name_entry` | 27 | 7 | Initialise the name-entry screen. |
| `$9CA0` | `b13_expand_name_tile` | 22 | 5 | Expand one packed name tile. |
| `$9CB6` | `b13_pack_name_tile` | 8 | 1 | Pack/rotate one name-entry tile into the tile buffer. |
| `$9CC6` | `b13_check_name_tile` | 8 | 3 | Check/expand a packed name tile and set carry on failure. |
| `$9F63` | `b13_name_entry_screen` | 72 | 1 | Name-entry screen setup. |
| `$9FAB` | `b13_loc_9FAB` | 47 | 2 |  |
| `$A075` | `b13_name_entry_input` | 109 | 0 | Name-entry cursor/input handler. |
| `$A0F3` | `b13_officer_status_init` | 126 | 1 | Initialise the officer-status/gameplay handoff after name entry. |

### Inline RAM routines

| Source address | Name | Bytes |
|---:|---|---:|
| `$881A` | `inline_881A` | 29 |
| `$9213` | `inline_9213` | 50 |
| `$967A` | `inline_967A` | 35 |
| `$A157` | `inline_A157` | 26 |

## Bank 14  ($8000-$BFFF)

| Address | Name | Approx. bytes | Callers | Summary |
|---:|---|---:|---:|---|
| `$8000` | `b14_field_cmd_talk` | 150 | 2 | Field menu はなす (talk), entry 0 of the fixed-bank table at $F1C3; msg 001 when nobody is there. |
| `$8020` | `b14_menu_dispatch` | 118 | 0 | Menu/command dispatch for the current game mode. |
| `$8074` | `b14_menu_input` | 39 | 0 | Menu cursor/input update. |
| `$809B` | `b14_field_cmd_search` | 17 | 0 | Field menu しらべる (search), entry 1 of the $F1C3 table. |
| `$80B7` | `b14_sub_80B7` | 22 | 1 |  |
| `$8147` | `b14_sub_8147` | 178 | 1 |  |
| `$8268` | `b14_sub_8268` | 107 | 1 |  |
| `$8306` | `b14_field_cmd_formation` | 107 | 0 | Field menu たいれつ (formation), entry 2: window 4 (ならび / ぐんし); ぐんし sets or clears the strategist bit $40 (msgs 021/022/023/471). |
| `$8385` | `b14_close_menu` | 16 | 2 | Close the current menu and restore the text engine. |
| `$8395` | `b14_formation_reorder` | 161 | 0 | The ならび reorder screen: members are picked one by one; B undoes a pick ($846C). |
| `$83B2` | `b14_status_update` | 132 | 0 | Officer status screen per-frame update. |
| `$842F` | `b14_init_battle_party` | 61 | 8 | Initialise the battle party arrays. |
| `$846C` | `b14_battle_party_loop` | 51 | 0 | Battle party initialisation loop. |
| `$849F` | `b14_field_cmd_officers` | 11 | 0 | Field menu ぶしょう (officers), entry 3: officer list (window 3), then the info screen ($84F8). |
| `$84AA` | `b14_wincb_party_list_line` | 75 | 0 | Window CALL (F8) in templates 3, 5 and $0C; runs the inline block at $84AD. |
| `$84AD` | `b14_inline_party_list_line` | 72 | 0 | Inline block (bank 12): one officer-list line: ＊ ($0E, not present) or ★ ($0F, strategist), then the name (put_officer_name). |
| `$84F8` | `b14_field_officer_info` | 6 | 0 | Map path into the info screen (b14_party_status_update, then b14_officer_info_screen), back to the field through field_return_refresh. |
| `$84FE` | `b14_party_status_update` | 38 | 1 | Update the party status panel. |
| `$8518` | `b14_officer_info_screen` | 12 | 1 | The officer info screen (both paths; the battle calls it from b14_battle_officer_info): portrait, name (window $1B kana, window $08 kanji with $A9 = $10), stats, equipment and tactics windows. |
| `$857B` | `b14_wincb_stat_value_bar` | 92 | 0 | Window 9 CALL: one stat (ぶりょく $619C, ちりょく $61A8, こうげき, ぶそうど $60B4, S.P $61FB) as 3 digits, then a bar of $F4 per 26 points plus $F3 for a remainder of 13 or more. |
| `$8616` | `b14_wincb_sp_label` | 18 | 0 | Window 9 CALL: the S . P tiles $F6 $F8 $F7. |
| `$8628` | `b14_wincb_troop_max` | 21 | 0 | Window $2D (へいしすう) CALL: text_actor's 24-bit troop maximum $6160 as 6 digits. |
| `$863D` | `b14_wincb_equipped_line` | 61 | 0 | Window $0B (そうび) CALL; runs the inline block at $8640. |
| `$8640` | `b14_inline_equipped_line` | 58 | 0 | Inline block (bank 12): the next equipped item (bit 7) of text_actor from slot $70, drawn with load_item_data. |
| `$867D` | `b14_delay_frames` | 9 | 2 | Delay for a fixed number of frames. |
| `$8686` | `b14_field_cmd_items` | 11 | 0 | Field menu どうぐ (items), entry 4: officer list (window 3), then b14_field_item_menu. |
| `$8691` | `b14_wincb_item_list_line` | 111 | 0 | Window CALL for window 6 (field item list) and window $16 (battle item subwindow, 8 calls); runs the inline block at $8694. |
| `$8694` | `b14_inline_item_list_line` | 108 | 0 | Inline block (bank 12): one item slot of text_actor (load_item_data); field index $54 with ＊ for equipped items, battle index battle_anim; then rewinds text_col. |
| `$8703` | `b14_field_item_menu` | 64 | 0 | Item menu of the chosen officer: msg 009 without items, else the list (window 6) and つかう/わたす/そうび/すてる (window 7, table $8748). |
| `$8750` | `b14_item_menu_use` | 77 | 0 | Item menu つかう (use). |
| `$87AB` | `b14_item_menu_give` | 131 | 0 | Item menu わたす (give). |
| `$8851` | `b14_item_menu_equip` | 170 | 0 | Item menu そうび (equip). |
| `$890A` | `b14_item_menu_discard` | 47 | 0 | Item menu すてる (discard). |
| `$8948` | `b14_check_party_slot` | 16 | 1 | Check whether a party slot is empty. |
| `$8980` | `b14_item_effect_dispatch` | 8 | 2 | Jump on text_command - $18 through the 40-entry table at $8988 (items $18-$3F); from the field ($879B) and battle item use ($A341); C set = something happened. |
| `$8B29` | `b14_sub_8B29` | 93 | 1 |  |
| `$8CD4` | `b14_heal_target_troops` | 15 | 1 | Add $10-$12 to text_target's troops $60D0, capped at the maximum $6160, then msg 039; also used by tactic type 2 ($BA44). |
| `$8D48` | `b14_consume_used_item` | 18 | 5 | Clear item slot $70 of text_actor and recompact the list, then C = 1: the shared tail of the item effects. |
| `$8D5A` | `b14_effect_msg_pause` | 15 | 1 | Pause before an effect message: field waits for A/B, battle waits 10 frames, all-out mode none. |
| `$8D69` | `b14_abort_if_target_down` | 11 | 2 | If text_target is down (state bit 7 clear), drop the caller's return address and return C = 0 to the caller's caller. |
| `$8D74` | `b14_sub_8D74` | 68 | 4 |  |
| `$9222` | `b14_wincb_gold_line` | 8 | 0 | Window $18/$22 CALL: the 金 tile ($6C), then gold ($6076). |
| `$922A` | `b14_wincb_food_line` | 18 | 0 | Window $18/$22 CALL: 兵ろう ($7F $35 $3F), then food ($6079). |
| `$923C` | `b14_wincb_exp_line` | 28 | 0 | Window $22 CALL: けいけんち, then experience ($6070). |
| `$9579` | `b14_sub_9579` | 37 | 1 |  |
| `$959E` | `b14_army_status_screen` | 26 | 0 | Select on the map: the leader's portrait and kanji name, gold/food/exp, level, the troop list and the strategist's S.P. |
| `$95AA` | `b14_inline_upload_status_kanji` | 14 | 0 | Inline block: bank 1 mapped, copy_to_vram mode 2 writes plane 1 of BG tiles $C0-$D7 from bank 1 $8000. |
| `$9649` | `b14_print_gold` | 6 | 0 | Flush the VRAM queue, then print gold $6076. |
| `$9656` | `b14_print_food` | 6 | 0 | Flush the VRAM queue, then print food $6079. |
| `$9663` | `b14_print_exp` | 6 | 0 | Flush the VRAM queue, then print experience $6070. |
| `$9670` | `b14_wincb_print_sp` | 6 | 0 | Window $0F CALL: S.P $61FB as 3 digits. |
| `$967D` | `b14_wincb_print_sp_factor` | 6 | 0 | Window $0F CALL: $61F8 (the S.P multiplier of b14_calc_tactic_points) as 3 digits. |
| `$968A` | `b14_wincb_tactic_sp_left` | 6 | 0 | Window $17 (battle tactic subwindow title) CALL: the remaining S.P $6210 as 3 digits. |
| `$969C` | `b14_wincb_army_member_line` | 119 | 0 | Window $0E CALL (inline block, bank 12): per party-order entry a ＊/★ marker, the name, then troops $60D0 / maximum $6160. |
| `$977B` | `b14_battle_calc_damage` | 442 | 1 | Damage of the acting slot (tactic power, or ぶりょく x troop factor with class, terrain, defence and defend modifiers and a random spread); subtracted from the target's $60D0; msgs 052/053 on a critical roll. |
| `$99DC` | `b14_msgcb_victory_exp` | 44 | 0 | Message CALL (msgs 061/062): experience = enemy totals x area factor, added to $6070 and printed. |
| `$9A3C` | `b14_msgcb_victory_gold` | 31 | 0 | Message CALL (msgs 061/062): gold reward, added to $6076 and printed. |
| `$9A65` | `b14_msgcb_victory_food` | 21 | 0 | Message CALL (msg 061): food reward, added to $6079 and printed. |
| `$9A84` | `b14_sum_enemy_officer_stats` | 88 | 2 | Sum over the enemy officers the larger (cursor_x = 0) or smaller (1, then x5) of $61A3/$61AF, scaled by the area table $9AE1. |
| `$9AF3` | `b14_calc_food_use_rate` | 44 | 1 | At battle end: total troops of the 7 members -> $607D = total / 1000 or $607C = 1000 / total (the field food rate). |
| `$9B73` | `b14_battle_entry` | 6 | 0 | Battle entry from the fixed bank: b14_battle_run, then field_return_refresh. |
| `$9B79` | `b14_battle_run` | 14 | 1 | text_busy + 1, the encounter transition (inline block), then the battle from b14_battle_start. |
| `$9B7E` | `b14_inline_battle_transition` | 9 | 0 | Inline block: bank 13 b13_fade_out_wait (encounter sound and flashes, then CHR $1800-$1FFF masked in 16 steps). |
| `$9B89` | `b14_battle_start` | 88 | 0 | Battle (re)start, also for chained battles: battle_intro_screen_body (battle CHR and palette set 8), scroll, battle flags, attribute layout $A59E. |
| `$9BF5` | `b14_inline_battle_area_from_map` | 43 | 0 | Inline block (bank 13): the area rank $6026 from the map position. |
| `$9C22` | `b14_battle_setup_enemy_list` | 82 | 0 | Random battle: b14_battle_roll_encounter_lineup; scripted: $6E/$6F = bank-12 enemy list $8D60 + submode x 5. |
| `$9C5C` | `b14_inline_pick_enemy_leader` | 24 | 0 | Inline block (bank 12): the first present officer of the ($6E) list becomes the enemy leader $60AF. |
| `$9C87` | `b14_battle_build_lineup` | 249 | 0 | Battle slots $6097-$609B: present non-strategist members, then the strategist, $A3 for empty; then battle_setup_slots (names, gauges), $AA = 0, and the surprise roll (msgs 102/103). |
| `$9CA0` | `b14_sub_9CA0` | 237 | 5 |  |
| `$9D40` | `b14_battle_round_start` | 91 | 0 | Start of a round: tactic points, clear the commands; all-out mode goes straight to execution or ends. |
| `$9D58` | `b14_battle_command_phase` | 67 | 0 | Command input: slot 0, command count $7C = 0, clear the S.P reserves $6213-$6217. |
| `$9D66` | `b14_battle_command_slot` | 53 | 0 | Command input for one slot: skips slots that are down or held by a tactic, loads the portrait ($CF96) and places it. |
| `$9D92` | `b14_battle_command_panel` | 100 | 0 | Step forward; window $11 (the round's first command: two columns) or window $12 (four commands). |
| `$9D9C` | `b14_battle_command_panel_full` | 73 | 0 | Window $11 input: the right column is そうこうげき, たいきゃく or ぶしょう (target select, b14_battle_officer_info, then back here). |
| `$9DF6` | `b14_battle_cmd_chosen` | 50 | 0 | Store the left-column command in $61D0,x (0 fight, 1 tactic, 2 defend, 3 item), then target or subwindow. |
| `$9DFF` | `b14_sub_9DFF` | 41 | 1 |  |
| `$9E2D` | `b14_battle_item_subwindow` | 111 | 0 | The item subwindow (window $16): chosen slot in $61DA,x, target type from table $8958. |
| `$9E61` | `b14_battle_cmd_tactic` | 45 | 0 | さくりゃく: checks strategist, learned tactics and S.P (msgs 469/468/470), then the tactic subwindow. |
| `$9E9D` | `b14_battle_tactic_needs_river` | 6 | 0 | Msg 123 (no river nearby), then b14_battle_cmd_error_wait. |
| `$9EA5` | `b14_battle_cmd_error_wait` | 6 | 0 | Wait for A/B after a command error message, then b14_battle_cmd_retry. |
| `$9EAB` | `b14_battle_tactic_subwindow` | 143 | 0 | The tactic subwindow (window $17): tactic in $6200,x, river check, cost $BBDB against $6210 reserved in $6213,x, target type $BB40. |
| `$9EF4` | `b14_battle_cmd_retry` | 9 | 0 | Command cancelled: step back, clear the slot's S.P reserve, reopen the panel. |
| `$9EFD` | `b14_battle_cmd_prev_slot` | 47 | 0 | B on the panel: window $14, step back, previous slot that takes input. |
| `$9F2C` | `b14_battle_cmd_accept` | 27 | 0 | Command accepted: sound $0A, window $14, step back, next slot or execution after slot 4. |
| `$9F47` | `b14_battle_all_out_advance` | 41 | 1 | そうこうげき: slots 0-4 fight; all units move from column $40 to $70. |
| `$9F70` | `b14_battle_all_out_withdraw` | 44 | 1 | All units move back from $70 to $40. |
| `$9F9C` | `b14_battle_cmd_retreat` | 15 | 0 | たいきゃく: msg 046; success if the enemy was unaware or a roll against $A69A passes, else msg 047. |
| `$9FE8` | `b14_battle_party_loses_round` | 22 | 0 | Party slots do nothing ($40), enemies act: after an ambush or a failed retreat. |
| `$9FFE` | `b14_battle_retreat_escape` | 71 | 0 | Successful retreat: the party units turn around, then b14_battle_flee_to_field. |
| `$A045` | `b14_battle_execute_round` | 36 | 0 | Execution phase: enemy commands (b14_battle_ai_pick_commands), turn order, clear the portrait, then the turn loop. |
| `$A072` | `b14_battle_next_turn` | 220 | 0 | Next slot of the turn order $61EE; sets text_actor/text_target; tactic effects ending (msg 319). |
| `$A148` | `b14_battle_turn_dispatch` | 36 | 0 | Run the slot's command: defend (msg 054), item, tactic, otherwise attack. |
| `$A176` | `b14_battle_attack` | 8 | 0 | たたかう: msg 050, then the attack roll. |
| `$A180` | `b14_battle_attack_roll` | 305 | 0 | Step forward; miss (8/256, msg 051) or attack animation and damage (b14_battle_attack_target). |
| `$A1AA` | `b14_battle_after_action` | 273 | 0 | After an action: defeat or victory checks, extra attacks, multi-target tactics, ambush troops. |
| `$A2B4` | `b14_battle_round_end` | 157 | 0 | End of round: active tactic effects may end (b11 msgs 320-323), then the next round. |
| `$A311` | `b14_battle_use_item` | 29 | 0 | どうぐ in battle: msg 010, then the item effect (b14_item_effect_dispatch) or msg 011. |
| `$A353` | `b14_battle_over` | 42 | 0 | Battle result: attributes, music, msgs 059/060, scripted-battle bookkeeping, chained battles. |
| `$A3E2` | `b14_battle_end_anim` | 60 | 0 | Both outcomes: reset the actors, 120-frame animation, then defeat (sub_E5C1) or the victory path. |
| `$A41E` | `b14_battle_victory_rewards` | 10 | 0 | Victory: msg 061/062 (exp, gold, food), level-up check, prisoners in random battles. |
| `$A44E` | `b14_battle_offer_prisoners` | 111 | 0 | Captured enemy officers (msg 104): recruit or release. |
| `$A52F` | `b14_battle_release_prisoner` | 3 | 0 | Msg 105 (released), then the officer's $6300 status = $90. |
| `$A54C` | `b14_battle_return_to_field` | 68 | 1 | Common battle exit: food rate, actor tables, PPU off, field party sprites, area music. |
| `$A590` | `b14_battle_open_list_window` | 14 | 2 | Open the item ($16) or tactic ($17) subwindow given in X and wait (C = 1 on cancel). |
| `$A6F1` | `b14_battle_ai_pick_commands` | 289 | 1 | Enemy (all-out: every) command and target choice for the round. |
| `$A8B2` | `b14_battle_ai_pick_tactic` | 173 | 2 | Enemy tactic choice by troop ratio and chance; stores it in $6200,x, command $61D0,x = 1. |
| `$A95F` | `b14_battle_calc_turn_order` | 135 | 1 | Randomised speed per slot from $61B4, sorted fastest first into $61EE. |
| `$AA1A` | `b14_battle_officer_info` | 71 | 1 | ぶしょう in battle: the info screen (b14_officer_info_screen) for the chosen slot, then $A9 = $10, the names of battle slots 0 and 1 re-streamed, the gauge colour $03EA restored, the portrait and window reloaded. |
| `$AA61` | `b14_battle_target_has_troops` | 25 | 1 | Z = 1 when target slot $79's troops $60D0-$60D2 are zero; X preserved. |
| `$AA7A` | `b14_battle_clear_actor_tables` | 29 | 3 | Zero entries 4-15 of every 16-byte actor array $0500-$05FF. |
| `$AA97` | `b14_battle_actor_step_forward` | 107 | 4 | Walk the current slot's sprite forward to X = $50 (party) or $A0 (enemy). |
| `$AA9D` | `b14_battle_actor_walk_to_x` | 100 | 1 | Walk the current slot's sprite 2 px per frame to the X in Y (mirrored for enemies). |
| `$AAB0` | `b14_battle_actor_step_back` | 81 | 8 | Walk the current slot's sprite back to X = $40 (party) or $B0 (enemy). |
| `$AAB2` | `b14_sub_AAB2` | 79 | 1 |  |
| `$AB01` | `b14_battle_place_target_cursor` | 15 | 1 | Show the target cursor sprite at the row from table $AB10. |
| `$AB15` | `b14_battle_select_ally_target` | 167 | 1 | Up/down target cursor over the party slots 0-4 (item targets). |
| `$AB20` | `b14_battle_select_enemy_target` | 156 | 2 | Up/down target cursor over the live enemy slots 5-9; chosen slot in $61E4,x; Z = 1 on A. |
| `$ABBC` | `b14_battle_cursor_slot_state` | 12 | 3 | State bits of slot $79 + ptr1_lo, X = slot. |
| `$ABC8` | `b14_battle_open_notice_window` | 12 | 5 | Message window $15 for a notice (no items, no strategist, not enough S.P) and event text. |
| `$ABD4` | `b14_battle_show_actor_portrait` | 13 | 1 | Load the acting officer's face (tiles $80-$A3) and place it right (enemy) or left (party), then b14_battle_open_msg_window. |
| `$ABEB` | `b14_battle_open_msg_window` | 20 | 5 | Reset the text cursor; message window $01 (enemy) or $15 (party). |
| `$ABF6` | `b14_battle_open_party_msg_window` | 9 | 1 | Message window $15. |
| `$ABFF` | `b14_battle_close_msg_window` | 10 | 7 | Erase the acting side's face and draw the blank window $14 or $13. |
| `$AC03` | `b14_battle_close_enemy_msg_window` | 3 | 5 | Erase the right face and draw the blank window $13. |
| `$AC11` | `b14_battle_blank_party_msg_window` | 10 | 6 | Draw the blank window $14 (no face erase). |
| `$AC1B` | `b14_battle_attack_target` | 238 | 1 | Normal attack: retarget past dead slots, flash or shake, damage, kill and wipe-out messages (055-058), troop panel update. |
| `$AD9B` | `b14_battle_next_target_slot` | 26 | 1 | $61E4,x = next slot on the same side (5 -> 0, 10 -> 5). |
| `$ADB5` | `b14_battle_gauge_scale` | 81 | 1 | Troop gauge scale: the party's largest maximum troops against 500/2001/5001/10001/15001 picks units per segment ($76/$77) and the gauge colour (table $AE46), stored to $03EA (BG palette 2 colour 2) and vram_dma_pending. |
| `$AE62` | `b14_battle_calc_free_tactic_pts` | 23 | 1 | $6210 = tactic points $61FB minus the costs reserved this turn ($6213-$6217). |
| `$AE79` | `b14_battle_clear_tactic_reserve` | 8 | 2 | Clear the current slot's reserved tactic cost $6213,x. |
| `$AE87` | `b14_battle_actor_max_ability` | 15 | 2 | The larger of the acting member's $619C and $61A8. |
| `$AE96` | `b14_battle_clear_commands` | 14 | 2 | Clear the command ($61D0) and tactic ($6200) bytes of all 10 slots. |
| `$AEA4` | `b14_battle_delay_anim_frames` | 16 | 3 | Wait X frames running the actor animation (skipped in all-out mode). |
| `$AEBC` | `b14_battle_intro_event` | 110 | 1 | Scripted battle intro: the leader's face and message, special cases, then the window closes. |
| `$B02A` | `b14_battle_victory_event` | 203 | 1 | Scripted battle: post-victory face and message, story flags, captured officers' $6300 = $90. |
| `$B1C1` | `b14_battle_event_3d_betrayal` | 25 | 0 | Scripted battle $3D ending: dialogue (b11 191-200), then the lightning sequence. |
| `$B26A` | `b14_battle_lightning_strike_loss` | 42 | 0 | Palette flash, b11 201, then the battle ends as a loss. |
| `$B2A1` | `b14_event_speaker_right_71` | 21 | 5 | Event dialogue: face $71 on the right, message window 1. |
| `$B2BB` | `b14_event_speaker_left_88` | 21 | 5 | Event dialogue: face $88 on the left, message window $15. |
| `$B2DA` | `b14_sub_B2DA` | 8 | 4 |  |
| `$B2E7` | `b14_battle_lightning_dodge_input` | 45 | 0 | Scripted battle $4E: an 8-press input within about 255 frames; timeout -> the strike. |
| `$B324` | `b14_battle_roll_encounter_lineup` | 218 | 1 | Random encounter: enemy type from the terrain, 2-5 enemies into $0300-$0304, maybe one regional officer. |
| `$B40E` | `b14_collect_region_officers` | 121 | 1 | Officers of region $6026 (bit 4 of $6300) into $0310, or switch game_submode to $4B/$4F. |
| `$B487` | `b14_init_party_slots` | 6 | 0 | Initialise the seven party slots. |
| `$B48D` | `b14_init_party_loop` | 9 | 3 | Loop over the seven party slots. |
| `$B496` | `b14_refill_present_troops` | 15 | 1 | Current troops = maximum for each present party member. |
| `$B4A5` | `b14_refill_member_troops` | 22 | 2 | Member A's current troops $60D0 = maximum $6160. |
| `$B4C5` | `b14_calc_member_max_troops` | 162 | 1 | Member Y's maximum troops: fixed table value, or 100 grown per party level by class factors. |
| `$B4E0` | `b14_inline_fixed_max_troops` | 36 | 0 | Inline block (bank 12): the member's fixed 16-bit maximum troops from the table at $BED0. |
| `$B586` | `b14_check_level_up` | 49 | 1 | Experience against the level table $B687: level-up messages, troops, new tactics, tactic points. |
| `$B723` | `b14_text_call_tactic_name` | 107 | 0 | Window CALL (tactic window $17, 6x; also $EA20): one tactic name of the $65A0 list. |
| `$B726` | `b14_inline_print_tactic_name` | 104 | 0 | Inline block (bank 12): tactic name from $65A0 (two columns in battle), draw_item_name. |
| `$B791` | `b14_build_member_tactic_list` | 196 | 2 | Rebuild member X's 6-entry tactic list $65A0 + 6X from the per-level tables. |
| `$B855` | `b14_calc_strategist_tactic_pts` | 47 | 2 | Find the strategist (state $C0) among members 0-6 and compute tactic points, else $61FB = 0. |
| `$B863` | `b14_calc_tactic_points` | 33 | 1 | $61FB = member X's $61A8 x $61F8 / 256 - spent $61FE, clamped at 0. |
| `$B913` | `b14_battle_exec_tactic` | 79 | 0 | Tactic turn: effect animation, msg 124, S.P cost, success roll (466/467), then damage, heal, status, dispel, kill or retreat. |
| `$BAD8` | `b14_inline_tactic_retreat_home` | 22 | 0 | Inline block for tactic $1E: bank 13 resets the location stack, then the location reloads. |
| `$BAF0` | `b14_battle_flee_to_field` | 12 | 0 | Leave the battle (b14_battle_return_to_field), refresh, reset the stack, game_mode_switch. |
| `$BC66` | `b14_battle_print_tactic_effect` | 19 | 2 | Tactic effect message $0320 + 2 x (text_command - $10) + side (b11 288-317). |
| `$BC79` | `b14_field_enter_location` | 228 | 1 | Entrance check (called from $F2A0). |
| `$BC7C` | `b14_inline_find_entrance` | 225 | 0 | Inline block (bank 7): scan the entrance records for the current map and position. |
| `$BD62` | `b14_field_enter_location_done` | 21 | 0 | After an entrance match: door sound, window 5, init_party_status, then the area change. |
| `$BD77` | `b14_field_transfer_or_exit` | 100 | 1 | Transfer / exit check (called from $F2AA). |
| `$BD7A` | `b14_inline_find_transfer` | 97 | 0 | Inline block (bank 7): scan the transfer records for an exact position match. |
| `$BDDF` | `b14_field_transfer_done` | 80 | 0 | After a transfer match: redraw, reload the area screen and music, back to the field loop. |
| `$BE2F` | `b14_field_exit_to_prev_location` | 199 | 0 | No match: pop the location stack, per-location exit tweaks, then the area change. |
| `$BE70` | `b14_inline_exit_69_flag_check` | 12 | 0 | Inline block (bank 13): location $69 exit adjustment. |
| `$BEF3` | `b14_field_area_change_tail` | 12 | 0 | $91 = 1, b14_field_change_area, drop the caller's frame, resume the field loop. |
| `$BEFF` | `b14_field_change_area` | 10 | 2 | Area tileset lookup, screen load and music. |
| `$BF02` | `b14_field_load_area_and_music` | 7 | 1 | Load the area screen and start its music. |
| `$BF09` | `b14_field_load_area_screen` | 61 | 2 | Party facing and scroll, map render, area CHR and palette, fade. |
| `$BF46` | `b14_field_get_area_tileset` | 32 | 4 | level = tileset nibble from $BF98; class_index 0/1/2 by tileset. |
| `$BF66` | `b14_field_play_area_music` | 43 | 2 | Pick and queue the area music. |

### Inline RAM routines

| Source address | Name | Bytes |
|---:|---|---:|
| `$814D` | `inline_814D` | 172 |
| `$823D` | `inline_823D` | 11 |
| `$84AD` | `b14_inline_party_list_line` | 72 |
| `$8640` | `b14_inline_equipped_line` | 58 |
| `$8694` | `b14_inline_item_list_line` | 108 |
| `$95AA` | `b14_inline_upload_status_kanji` | 17 |
| `$969F` | `inline_969F` | 116 |
| `$9B7E` | `b14_inline_battle_transition` | 9 |
| `$9BF5` | `b14_inline_battle_area_from_map` | 43 |
| `$9C5C` | `b14_inline_pick_enemy_leader` | 24 |
| `$AF4A` | `inline_AF4A` | 9 |
| `$B09C` | `inline_B09C` | 9 |
| `$B4E0` | `b14_inline_fixed_max_troops` | 36 |
| `$B726` | `b14_inline_print_tactic_name` | 104 |
| `$BAD8` | `b14_inline_tactic_retreat_home` | 22 |
| `$BC7C` | `b14_inline_find_entrance` | 225 |
| `$BD7A` | `b14_inline_find_transfer` | 97 |
| `$BE70` | `b14_inline_exit_69_flag_check` | 12 |

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
| `$C09F` | `wait_vblank` | 54 | 65 | Wait for the NMI window and flush queued PPU updates. If rendering is off, switch to the scheduler before waiting. |
| `$C0A7` | `wait_vblank_queued` | 46 | 17 | Yield one frame with nmi_update_budget = 1 (the NMI flushes the VRAM queue); unlike wait_vblank there is no direct-flush path. |
| `$C0BC` | `wait_frames` | 7 | 16 | Wait for X frames by repeatedly yielding. |
| `$C0C3` | `update_frames` | 11 | 1 | Run update_frame X times. |
| `$C0CE` | `wait_frame_tick` | 7 | 5 | Frame-paced wait helper.  Only acts when the low nibble of $33 is zero. |
| `$C0D5` | `update_frame` | 22 | 15 | Per-frame input/UI update. Polls the controller, updates sprites, and yields to the scheduler. |
| `$C0E2` | `loc_C0E2` | 9 | 15 |  |
| `$C0EB` | `update_frame_no_input` | 7 | 4 | Per-frame update variant that skips controller polling while a button is held. |
| `$C0F2` | `ppu_nmi_off` | 10 | 6 | Clear PPUCTRL bit 7 (disable NMI) and write the shadow. |
| `$C0FC` | `ppu_nmi_on` | 10 | 8 | Set PPUCTRL bit 7 (enable NMI) and write the shadow. |
| `$C106` | `one_minus_a` | 6 | 3 | Return 1 - A (ones-complement helper). |
| `$C10C` | `dispatch_return_table` | 22 | 6 | Dispatch through a table that follows the JSR return address. A selects the word entry; the return address is advanced past the table. |
| `$C122` | `ppu_bg_sprites_off` | 10 | 4 | Disable background and sprite rendering (PPUMASK bits 3-4). |
| `$C132` | `ppu_bg_sprites_off_shadow` | 10 | 4 | Disable background/sprite rendering in the shadow only. |
| `$C13F` | `screen_fade_in_step` | 21 | 4 | Advance one step of the screen fade-in state machine. |
| `$C145` | `screen_fade_in` | 12 | 11 | Enable NMI, restore the mask, yield, and step the fade state. |
| `$C151` | `screen_fade_out` | 10 | 10 | Begin a screen fade-out and wait. |
| `$C15B` | `mul16_by_u8` | 83 | 15 | $10-$12 = $10-$11 x $15 (clears $14 and $12, then mul16x16_shr8). |
| `$C15F` | `mul16x16_shr8` | 79 | 12 | $10-$12 = ($10-$11 x $14-$15) >> 8 (clears $12, then mul24x16_shr8). |
| `$C163` | `mul24x16_shr8` | 75 | 4 | $10-$12 = ($10-$12 x $14-$15) >> 8 (24-bit result). |
| `$C1B3` | `div16_by_u8` | 31 | 1 | $10-$11 = $10-$11 / $13, remainder in $12.  Y preserved. |
| `$C1D2` | `div24_shift` | 69 | 5 | 24-bit shift/divide helper. |
| `$C25A` | `fetch_inline_word` | 38 | 9 | Fetch the word that follows the caller's JSR. Used by inline text and inline pointer data. |
| `$C280` | `read_controller` | 43 | 1 | Poll controller 1 and update $F5/$F7. The previous state is kept for edge detection. |
| `$C2AB` | `set_ppu_scroll` | 60 | 7 | Set PPU scroll/address registers from A/X/Y. |
| `$C2E7` | `fill_ram_block` | 24 | 4 | Fill a block of CPU RAM/PPU memory with a constant. |
| `$C2FF` | `flush_palette` | 50 | 2 | Upload a pending palette block through the VRAM helper. |
| `$C331` | `write_vram_block` | 107 | 3 | Write a block of bytes to PPUDATA from a RAM pointer. |
| `$C33A` | `copy_to_vram` | 107 | 11 | Copy a block from CPU memory to PPUDATA. |
| `$C3A5` | `vram_ptr_add8` | 20 | 3 | Add 8 to the 16-bit VRAM pointer in $00/$01. |
| `$C3A7` | `vram_ptr_add` | 18 | 1 | Add A to the 16-bit VRAM pointer in $00/$01. |
| `$C3B9` | `vram_put_tile_loop` | 53 | 5 | Write a run of bytes to PPUDATA from the current pointer. |
| `$C3CE` | `vram_put_run` | 32 | 2 | Write a run of bytes to PPUDATA with a fixed tile value. |
| `$C3E0` | `vram_put_tile_xor` | 14 | 1 | Write 8 bytes to PPUDATA XORed with a constant. |
| `$C3EE` | `read_inline_rect` | 75 | 1 | Read an inline rectangle/table descriptor and copy four bytes to $02-$06. |
| `$C439` | `ppu_init` | 39 | 14 | Initialise PPU registers, palette, scroll, and OAM shadow. |
| `$C43C` | `clear_screen` | 36 | 1 | Clear the screen and reset PPU state. |
| `$C44E` | `clear_oam_shadow` | 18 | 4 | Hide all 64 sprites in the OAM shadow. |
| `$C452` | `hide_sprites` | 14 | 2 | Write $F8 (offscreen Y) to every sprite in the OAM shadow. |
| `$C460` | `mmc1_reset` | 30 | 2 | Reset the MMC1 shift register and map bank 14. |
| `$C468` | `mmc1_init` | 22 | 1 | Initialise MMC1 control/PRG registers. |
| `$C47E` | `set_bank_current` | 32 | 11 | Map the bank stored in $43 at $8000. |
| `$C480` | `set_bank_a` | 30 | 7 | Map bank A at $8000 and update both current-bank variables. |
| `$C482` | `set_bank_b` | 28 | 47 | Map bank A at $8000; used for temporary data access. |
| `$C484` | `set_bank_lock` | 26 | 2 | Map bank A at $8000, waiting for a pending NMI bank restore. |
| `$C49E` | `set_bank_12` | 45 | 7 | Map bank 12 at $8000. |
| `$C4A2` | `set_bank_13` | 41 | 15 | Map bank 13 at $8000. |
| `$C4A6` | `set_bank_14` | 37 | 7 | Map bank 14 at $8000. |
| `$C4AA` | `restore_bank_after_nmi` | 33 | 2 | Restore the bank that was active before NMI. |
| `$C4B7` | `write_prg_bank` | 20 | 3 | Serialise A into the MMC1 PRG bank register. |
| `$C4CF` | `sound_queue_add_once` | 21 | 8 | Queue a sound command only when it differs from the last one. |
| `$C4D5` | `sound_queue_add` | 15 | 29 | Append a sound command to the 8-entry ring buffer at $E8. |
| `$C4E4` | `call_inline_block` | 23 | 28 | Copy the 255-byte inline block after the JSR to $0600 and jump to $0601. The block executes from RAM with a different PRG bank mapped; it must end with return_inline_block/JMP C4FB. |
| `$C4FB` | `return_inline_block` | 31 | 32 | Return from a call_inline_block block: restore the caller's bank and resume at the saved bank address. |
| `$C51A` | `draw_text_window_small` | 140 | 9 | Draw a compact text window (status/menu variant). |
| `$C522` | `draw_window` | 132 | 16 | Draw the standard dialogue/menu window frame. |
| `$C5A6` | `load_text_graphics` | 73 | 15 | Load the tile set for the current text/menu page. |
| `$C6D2` | `draw_portrait` | 173 | 1 | Draw a 16x16 portrait/actor tile block. |
| `$C783` | `set_cursor_from_table` | 32 | 2 | Set the text cursor from a two-byte table entry and save it. |
| `$C793` | `set_cursor_no_save` | 16 | 1 | Set the text cursor from a table without saving. |
| `$C7AB` | `set_actor_palette` | 22 | 7 | Set an actor's palette/facing bits. |
| `$C7C1` | `update_oam` | 181 | 4 | Rebuild the OAM shadow from the actor arrays. |
| `$C876` | `update_oam_sprite` | 254 | 2 | Update one actor's OAM entries. |
| `$C990` | `text_window_restore_wait` | 9 | 3 | text_init window X, text_restore_tiles, then text_wait_loop. |
| `$C999` | `text_window_restore` | 6 | 1 | text_init window X, then text_restore_tiles. |
| `$C99F` | `text_window_restore_ask` | 17 | 5 | Open window 2 (or $25 when battle_flags is set), restore the saved text tiles and wait; C set = cancelled. |
| `$C9B0` | `reset_text_engine` | 8 | 25 | Clear the text engine and reset its cursor. |
| `$C9B8` | `text_init` | 472 | 52 | Initialise text buffers, window tiles, and cursor state. |
| `$CB92` | `text_input` | 130 | 2 | Handle text-menu input and cursor movement. |
| `$CC19` | `read_stack_arg` | 49 | 5 | Read a byte from the caller's stack frame. |
| `$CC4A` | `text_find_line` | 55 | 2 | Find the text line/actor matching the current selection. |
| `$CC81` | `text_hide` | 20 | 3 | Hide the text cursor and restore the underlying tiles. |
| `$CC95` | `text_cursor_init` | 127 | 1 | Initialise the text cursor position. |
| `$CCA7` | `text_draw_cursor` | 109 | 2 | Draw/update the blinking text cursor. |
| `$CD14` | `clear_text_state` | 11 | 3 | Clear the text-menu selection variables. |
| `$CD1F` | `text_scroll` | 256 | 1 | Scroll the text window by one row. |
| `$CD9D` | `text_wait` | 11 | 10 | Wait for text input and update the cursor. |
| `$CDA8` | `text_wait_ask` | 11 | 1 | text_wait_loop; C set when cancelled or when $5B is non-zero. |
| `$CDB3` | `text_wait_loop` | 44 | 8 | Main text input/wait loop. |
| `$CDDF` | `text_draw_screen` | 78 | 10 | Redraw the current text screen. |
| `$CE2D` | `sub_CE2D` | 77 | 1 |  |
| `$CE7A` | `sub_CE7A` | 88 | 1 |  |
| `$CED2` | `battle_intro_screen` | 38 | 2 | Battle introduction screen: window, fade, and clear. |
| `$CEDA` | `battle_intro_screen_body` | 30 | 1 | battle_intro_screen after its window and frame wait. |
| `$CF19` | `field_return_refresh` | 516 | 0 | screen_refresh, then continue the field loop at $F1DD. |
| `$CF1F` | `screen_refresh` | 60 | 4 | Refresh the whole screen: palette, window, text, sprites. |
| `$CF5B` | `text_save_tiles` | 27 | 2 | Save the current text tile rows for redraw. |
| `$CF76` | `text_restore_tiles` | 27 | 3 | Restore the text tile rows ($0180 -> $0300, $60 bytes) and the text cursor ($39-$3C -> $1C-$1F, $57 -> $56) saved by text_save_tiles. |
| `$CF91` | `status_message` | 3 | 1 | Draw a status message and load the matching text page. |
| `$CF96` | `load_actor_portrait` | 38 | 6 | Load the portrait page of text_actor's officer (text_load_page). |
| `$CFA1` | `sub_CFA1` | 5 | 1 |  |
| `$CFA9` | `text_load_page` | 219 | 10 | Load a text page/graphics set from bank 12. |
| `$D084` | `text_draw_page` | 56 | 1 | Draw the loaded text page. |
| `$D10D` | `text_print_inline` | 14 | 123 | Print the inline message reference that follows the JSR. The first word is a 16-bit message-table index (< $200: bank 10, >= $200: bank 11 with $200 subtracted), not a direct address. |
| `$D11B` | `text_reset_cursor` | 9 | 9 | Reset text cursor/line/speed state. |
| `$D124` | `text_show_message` | 218 | 5 | Open a text window and run the message bytecode interpreter. Input: $14/$15 = 16-bit message-table index.  The split low/high tables in bank 10 or 11 turn it into the actual message address. |
| `$D1FD` | `text_set_cursor` | 44 | 3 | Set the PPU cursor address from the text cursor variables. |
| `$D229` | `text_clear_line` | 136 | 1 | Clear one 24-column text line in the tile buffers. |
| `$D340` | `text_put_tile` | 29 | 10 | Write the top/bottom tile pair for one character into the tile buffers. |
| `$D35D` | `text_put_char_shadow` | 73 | 1 | Queue the bottom/alternate tile for the current text character. |
| `$D365` | `text_put_char_cursor` | 65 | 1 | Queue the cursor/underline tile for the current text character. |
| `$D36F` | `text_put_char` | 55 | 1 | Queue the top tile for the current text character. |
| `$D376` | `text_scroll_up` | 105 | 3 | Scroll the four dialogue lines up by one line. |
| `$D405` | `text_redraw_lines` | 55 | 1 | Redraw all four text lines from the tile buffers. |
| `$D43C` | `wait_then_game_main` | 6 | 0 | Wait for a keypress, then resume the main gameplay loop. |
| `$D442` | `wait_keypress` | 10 | 12 | Wait until a button edge is detected. |
| `$D456` | `text_draw_char` | 64 | 19 | Render one 8x16 character and advance the text cursor. |
| `$D49A` | `put_officer_name_target` | 5 | 1 | put_officer_name for actor text_target ($4B); nothing if negative. |
| `$D49F` | `put_officer_name_actor` | 170 | 3 | put_officer_name for actor text_actor ($4A). |
| `$D4A1` | `put_officer_name` | 168 | 3 | Write the name of officer Y ($60A8,y -> record in bank 12) into the text line buffer at X: kana tiles, or (when $AA is non-zero) the kanji name, whose glyphs (record bytes $10-$13) are streamed to plane 1 of the tiles at $A9 (+4 per kanji). |
| `$D567` | `draw_item_name` | 35 | 1 | Draw an item/equipment name from the bank 12 text tables. |
| `$D59F` | `load_item_data_6e` | 42 | 1 | load_item_data for item $6E, or for $4D when $6E is negative. |
| `$D5A5` | `load_item_data` | 36 | 2 | Load item/equipment data from bank 12. |
| `$D5BA` | `draw_string_from_pointer` | 15 | 1 | Draw a FF-terminated string through the current pointer. |
| `$D5F2` | `compact_items_all` | 12 | 1 | Compact the item slots of actors 6..0 (compact_items_f2). |
| `$D5FE` | `compact_items_actor` | 56 | 7 | Compact the 8 item slots of actor text_actor ($6100 + 8 * actor): empty slots move to the end. |
| `$D602` | `compact_items_f2` | 52 | 1 | Compact the item slots of actor $F2. |
| `$D636` | `find_party_member` | 28 | 4 | Find the first active party member. |
| `$D652` | `read_inline_block_3` | 94 | 15 | Read an inline pointer and copy three bytes from it. |
| `$D661` | `read_pointer_triplet` | 79 | 4 | Read three bytes through the current pointer. |
| `$D671` | `copy_pointer_triplet` | 63 | 2 | Copy a three-byte pointer/triplet. |
| `$D6C2` | `sub_D6C2` | 49 | 1 |  |
| `$D6F3` | `put_number_bottom` | 32 | 0 | Append the 7 decimal digits at $0104-$010A to the bottom text row ($0318,x), skipping leading zeros (the last digit is always kept). |
| `$D713` | `set_party_cursor` | 32 | 1 | Position the status cursor on a party member. |
| `$D733` | `draw_status_panel` | 65 | 4 | Draw the officer/status panel for the current game mode. |
| `$D745` | `draw_status_row` | 47 | 1 | Draw one status row. |
| `$D7A9` | `cursor_add_x` | 32 | 9 | Add A to cursor X with 15-column wrap. |
| `$D7B1` | `cursor_add_x_signed` | 24 | 9 | Add signed A to cursor X with wrap. |
| `$D7C9` | `cursor_add_y` | 32 | 8 | Add A to cursor Y with 16-row wrap. |
| `$D7D1` | `cursor_add_y_signed` | 24 | 9 | Add signed A to cursor Y with wrap. |
| `$D7E9` | `cursor_to_ppu` | 44 | 6 | Convert cursor X/Y to a nametable/PPU address in $68/$69. |
| `$D815` | `set_scroll_from_cursor` | 41 | 3 | Set scroll registers from the cursor position. |
| `$D83E` | `draw_map_area` | 274 | 2 | Draw a rectangular map area from the map data. |
| `$D953` | `tile_address` | 38 | 2 | Return the tile address for a map cell. |
| `$D97C` | `render_map_column` | 37 | 2 | Render one map column and advance the scroll. |
| `$D9A1` | `flush_vram_queue` | 76 | 5 | Flush the $0400 VRAM update queue to the PPU. |
| `$D9ED` | `draw_tile_run` | 261 | 6 | Draw a run of map/text tiles starting at the PPU cursor. |
| `$DAF2` | `draw_map_object` | 141 | 1 | Draw one map object/sprite from the object table. |
| `$DB87` | `scroll_map` | 64 | 2 | Scroll the map and redraw the exposed row/column. |
| `$DBCA` | `text_render_cell` | 197 | 1 | Render one 8x16 dialogue cell. Builds two VRAM-queue entries from $0300/$0318 and $68/$69. |
| `$DC93` | `text_draw_line` | 120 | 3 | Draw a line of text tiles into the nametable. |
| `$DD14` | `draw_string` | 83 | 43 | Draw a zero-terminated string. |
| `$DD67` | `draw_text_window` | 91 | 4 | Draw the dialogue window border and clear its interior. |
| `$DDD2` | `draw_window_box` | 178 | 1 | Draw a general window box with variable position/size. |
| `$DDDA` | `update_party_portrait` | 179 | 2 | Update a party member's portrait/class bits. |
| `$DE07` | `expand_name_tile` | 134 | 1 | Expand one packed name-entry tile into the tile buffer. |
| `$DE8D` | `load_battle_palette` | 14 | 2 | Load the battle palette and tile set. |
| `$DEA0` | `draw_battle_panel` | 28 | 2 | Draw the battle status panel. |
| `$DEBC` | `battle_sp_owner_x6` | 33 | 5 | Y = 6 x the SP owner of the current side: for a party slot the highest actor 0-6 whose state bits are $C0 (the strategist), for an enemy slot the slot + 2.  A = Y = $FF when the party has none. |
| `$DEDD` | `battle_actor_items_x8` | 9 | 3 | Y = 8 x the actor of the current battle slot (its item list offset). |
| `$DEE6` | `battle_arg_slot_actor` | 5 | 12 | Y = actor of battle slot $79. |
| `$DEEB` | `battle_current_actor` | 25 | 13 | Y = actor of the current battle slot (party_count); battle_flags = 0 for a party slot (0-4), 1 for an enemy slot (5-9). |
| `$DEF6` | `battle_slot_actor` | 14 | 8 | Y = actor of battle slot A: party order $6097 for slots 0-4, A + 2 for the enemy slots. |
| `$DF04` | `battle_setup_slots` | 13 | 1 | Battle setup: upload the battle CHR from bank 9, fill the enemy slots from the encounter table, then battle_setup_names draws every slot (sprite, name, troops) and battle_setup_intro prints the appearance messages. |
| `$E09B` | `battle_setup_names` | 103 | 0 | Battle setup, all 10 slots: $A9 = $10 (name kanji go to plane 1 from tile $10, 4 tiles per kanji, no reuse, no bound), then per present slot the sprite, the name (put_officer_name_actor) and the troop gauge. |
| `$E116` | `battle_setup_intro` | 89 | 0 | Battle setup: music, then one appearance message per new enemy. |
| `$E198` | `battle_slot_init_sprite` | 64 | 1 | Initialise the sprite of battle slot party_count and refresh OAM. |
| `$E200` | `battle_draw_slot_troops` | 54 | 5 | Draw the troop count and gauge of battle slot $79 (gauge tiles $E0-$EE, scale $76/$77; enemy gauges fill right to left). |
| `$E300` | `battle_sprite_frame` | 35 | 7 | One battle animation frame: step the actor sprites, then yield. |
| `$E323` | `battle_effect_setup` | 61 | 3 | Start battle effect X (bank 1 pointers), drawn over two frames. |
| `$E369` | `read_actor_record_byte` | 34 | 2 | Read byte A of text_actor's officer record (read_party_stat_byte). |
| `$E371` | `read_party_stat_byte` | 26 | 8 | Read one byte from a party member's bank 12 stat record. |
| `$E38B` | `call_b13_9c00` | 12 | 2 | Call bank 13 $9C00, then map bank 14 again (flags kept). |
| `$E464` | `copy_party_stats` | 49 | 1 | Copy current party stats into the previous-stat snapshot. |
| `$E495` | `init_party_status` | 112 | 5 | Initialise the party status screen. |
| `$E50D` | `field_party_sprites_reset` | 77 | 5 | Put the three field party sprites on the party position with facing $87 (actor arrays $0530/$0540/$0560). |
| `$E55A` | `dialogue_sequence` | 72 | 2 | Run a dialogue/event sequence and restore the previous screen. |
| `$E5C1` | `battle_defeat` | 24 | 0 | Defeat: reset the stack, wait for a key, window $0A, bank 13 $A0F3, then game_mode_switch. |
| `$E711` | `load_party_hp` | 123 | 2 | Load a party member's troops/HP from bank 12. |
| `$E7A5` | `battle_screen` | 277 | 1 | Battle screen setup and per-frame battle UI. |
| `$E8BF` | `nop_return` | 11 | 2 | No-op returning immediately (used as a placeholder vector). |
| `$E937` | `jmp_b13_b3cb` | 6 | 1 | Map bank 13 and jump to $B3CB. |
| `$EE79` | `nmi_handler` | 323 | 0 | NMI/IRQ handler. Updates PPU registers, DMA, sound, palette/VRAM queue, and scroll. |
| `$EFC9` | `reset_init` | 169 | 0 | Reset initialisation: wait for PPU, clear RAM, set MMC1, start main loop. |
| `$F097` | `new_game_init` | 36 | 1 | Initialise a new game/party state. |
| `$F0BB` | `battle_party_init` | 19 | 2 | Initialise the battle party and switch to bank 13. |
| `$F0D7` | `enter_party_screen` | 8 | 0 | Map bank 7 and enter the party/list screen. |
| `$F0DF` | `enter_status_screen` | 8 | 0 | Map bank 13 and enter the officer status screen. |
| `$F133` | `load_game` | 23 | 2 | Load saved game data from battery-backed PRG RAM. |
| `$F14A` | `game_mode_switch` | 631 | 0 | Dispatch a new game mode/screen. |
| `$F1CD` | `game_main` | 526 | 0 | Main gameplay/field update loop. |
| `$F3F2` | `party_shift` | 47 | 1 | Shift the party order and update cached actor ids. |
| `$F421` | `update_party_sprites` | 43 | 1 | Update party member sprite/animation state. |
| `$F44C` | `get_party_member` | 46 | 2 | Look up a party member's actor id and stats. |
| `$F47A` | `update_party` | 79 | 1 | Update the party roster and map sprites. |
| `$F4C9` | `battle_calc` | 78 | 1 | Battle damage/stat calculation helper. |
| `$F523` | `random_encounter` | 39 | 0 | Random encounter check while walking. |
| `$F55C` | `draw_party_window` | 212 | 4 | Draw the party window headers. |
| `$F572` | `draw_party_status` | 190 | 4 | Draw the party status list. |
| `$F630` | `draw_party_column_a` | 25 | 1 | Draw one party status column (left). |
| `$F649` | `draw_party_column_b` | 25 | 1 | Draw one party status column (right). |
| `$F662` | `draw_party_header` | 46 | 5 | Draw the party header/name row. |
| `$F690` | `draw_party_footer` | 14 | 3 | Draw the party window footer. |
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
| `$F8DC` | `battle_main` | 48 | 4 | Battle main loop. |
| `$F92A` | `init_battle` | 84 | 1 | Initialise battle state and actors. |
| `$F97E` | `set_battle_cursor` | 109 | 1 | Set the battle cursor to a party member. |
| `$F982` | `draw_battle_cursor` | 105 | 1 | Draw the battle cursor. |
| `$F999` | `find_next_actor` | 82 | 1 | Find the next active actor/party member. |
| `$F99C` | `find_next_actor_from_x` | 79 | 1 | Find the next active actor starting from X (no cursor-table setup). |
| `$F9EB` | `check_battle_cursor` | 37 | 1 | Check whether the battle cursor is on a valid target. |
| `$FA10` | `add24_inline` | 46 | 15 | Add the 24-bit amount $10-$12 to the 24-bit variable at the inline pointer (Y = 0).  X/Y preserved. |
| `$FA1B` | `add24_inline_y` | 35 | 2 | add24_inline with the caller's Y as the byte offset. |
| `$FA3E` | `sub24_inline_clamped` | 95 | 5 | Subtract the 24-bit amount $10-$12 from the 24-bit variable at the inline pointer (Y = 0), clamped at zero: a larger amount is first cut to the variable.  X/Y preserved. |
| `$FA49` | `sub24_inline_clamped_y` | 84 | 3 | sub24_inline_clamped with the caller's Y as the byte offset. |
| `$FA9D` | `read_input_state` | 55 | 12 | Read controller state with repeat/edge handling. |
| `$FBC2` | `nop_return2` | 1 | 1 | No-op returning immediately. |
| `$FFD8` | `reset_vector` | 7 | 0 | Reset vector.  Resets MMC1 and jumps to reset_init. |

