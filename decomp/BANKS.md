# Bank / resource map

| Bank | CPU window | Role | Code bytes | Data resource |
|---:|---|---|---:|---|
| 00 | `$8000` | Character/sprite/background tiles | 0 | `bank00_chr` |
| 01 | `$8000` | 16x16 kanji + character graphics | 0 | `split PNG resources` |
| 02 | `$8000` | 16x16 kanji + portrait/title graphics | 0 | `split PNG resources` |
| 03 | `$8000` | Title/portrait graphics | 0 | `bank03_chr` |
| 04 | `$8000` | Portrait graphics | 0 | `bank04_chr` |
| 05 | `$8000` | Map chip graphics | 0 | `bank05_chr` |
| 06 | `$8000` | Map layout/event data | 0 | `bank06_map` |
| 07 | `$8000` | Party/list screen and event code | 796 | `bank07_data` |
| 08 | `$8000` | Sound driver + music data | 2278 | `bank08_data` |
| 09 | `$8000` | UI graphics + 1bpp kana font | 0 | `split PNG resources` |
| 10 | `$8000` | Split message pointer table + editable .dtx text | 0 | `bank10_messages` |
| 11 | `$8000` | Split message pointer table + editable .dtx text | 0 | `bank11_messages` |
| 12 | `$8000` | Enemy/town/item/weapon tables | 0 | `bank12_tables` |
| 13 | `$8000` | Officer status/name-entry code + dictionary | 2557 | `bank13_data` |
| 14 | `$8000` | Gameplay/menu code + embedded tables | 2311 | `bank14_data` |
| 15 | `$C000` | Fixed bank: main loop, text engine, NMI, bank switching | 10446 | `bank15_data` |
