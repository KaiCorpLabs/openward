# Respuestas a consultas (S1.6)

Generado con `termbench reports --engine all`. «—» = sin respuesta.

| Query | Expected | alacritty | ghostty |
|---|---|---|---|
| DA1 primary attributes | `CSI ? 6x ; … c (VT220+ with features)` | `ESC [?6c` | `ESC [?62;22c` |
| DA2 secondary attributes | `CSI > Pp ; Pv ; Pc c` | `ESC [>0;2600;1c` | `ESC [>1;0;0c` |
| DSR status | `CSI 0 n` | `ESC [0n` | `ESC [0n` |
| CPR cursor position | `CSI 3 ; 5 R` | `ESC [3;5R` | `ESC [3;5R` |
| DECXCPR | `CSI ? 3 ; 5 R (; page optional)` | — | — |
| DECRQM bracketed paste (2004) | `CSI ? 2004 ; 2 $ y` | `ESC [?2004;2$y` | `ESC [?2004;2$y` |
| DECRQM sync output (2026) | `CSI ? 2026 ; 2 $ y` | `ESC [?2026;2$y` | `ESC [?2026;2$y` |
| DECRQM grapheme clusters (2027) | `CSI ? 2027 ; 1|2 $ y` | `ESC [?2027;0$y` | `ESC [?2027;1$y` |
| Kitty keyboard flags | `CSI ? 0 u` | — | `ESC [?0u` |
| XTVERSION | `DCS > | name version ST` | — | `ESC P>|OpenWard S1ESC \` |
| OSC 10 foreground | `OSC 10 ; rgb:… ST` | — | `ESC ]10;rgb:d4d4/d4d4/d4d4ESC \` |
| OSC 11 background | `OSC 11 ; rgb:… ST` | — | `ESC ]11;rgb:1616/1818/1d1dESC \` |
| OSC 4 palette entry 1 | `OSC 4 ; 1 ; rgb:… ST` | — | `ESC ]4;1;rgb:cccc/6666/6666ESC \` |
| Text area in cells (XTWINOPS 18) | `CSI 8 ; 24 ; 80 t` | `ESC [8;24;80t` | `ESC [8;24;80t` |
| Text area in pixels (XTWINOPS 14) | `CSI 4 ; h ; w t` | — | `ESC [4;384;640t` |
| DECRQSS SGR | `DCS 1 $ r 0;1;31 m ST` | — | `ESC P1$r0;1;31mESC \` |
| XTGETTCAP TN | `DCS 1 + r 544e=… ST` | — | `ESC P1+r544E=787465726D2D323536636F6C6F72ESC \` |
| Color scheme (DSR 996) | `CSI ? 997 ; 1|2 n` | — | `ESC [?997;1n` |
