# Temas nuevos: Monitor, Berenjena y Búnker

- **Estado:** Monitor, Berenjena, Búnker, Marino, Catppuccin, Dracula y Tokyo Night, implementadas el 2026-10-19 (11 temas en 7 familias, para la 0.3.1-beta.5); el resto sigue de propuesta. Maquetas en el lienzo de diseño, filas «Temas» (y=34200: las tres familias; y=35680: la galería de Apariencia y más propuestas; y=37160: la segunda ronda).
- **Fecha:** 2026-10-19.
- **Base:** el sistema de temas de la B2 (`app/lib/ui/themes.dart`, `tokens.dart`, `terminal/schemes.dart`): familias con variante clara, oscura o las dos, y capas que se mezclan (colores, forma, fuentes y colores del terminal).
- **Alcance:** solo capas de tema. La ventana, los menús, los atajos y la disposición no cambian, y los siete temas de ahora (cinco familias) se quedan como están.

## Objetivo

Que la galería de Ajustes › Apariencia ofrezca, además de lo que ya hay, tres apariencias con carácter que se han pedido:
- **un terminal de letras verdes** de verdad, como una pantalla de fósforo;
- **el terminal de Ubuntu**, con su fondo morado;
- **los terminales de la saga Fallout**, monocromos y retrofuturistas.

Y dejar escritas otras apariencias posibles, para elegir cuáles entran después.

## Lo que ya hay

| Pieza | En qué se parece | Por qué no basta |
|---|---|---|
| Fósforo | Monoespaciado, fondo casi negro, acento verde menta, esquinas rectas | El texto del terminal es gris claro (`#C9D6CE`): el verde es solo el acento, no es una pantalla verde |
| Esquemas del terminal (Solarized, Dracula, Nord…) | Cambian la paleta del terminal | Solo el terminal: la ventana sigue siendo la del tema |
| Importar de iTerm2 o Ghostty | Cualquier paleta | Lo tiene que hacer cada persona, y tampoco toca la ventana |

## Propuesta

Tres familias nuevas en la misma galería, con los mismos tokens que las de ahora. Los nombres son propios, como Grafito o Papel, y no usan marcas de nadie: el aire de Ubuntu y de Fallout se toma del color, la letra y la forma, sin logotipos, textos ni pantallas de esos productos.

### Monitor (oscuro): letras verdes de verdad

- El texto del terminal es verde fósforo (`#33FF66` sobre `#040904`, 14,9:1); la negrita y el «blanco brillante» tiran a verde blanquecino, como el fósforo cuando brilla más.
- **Conserva los colores de los programas:** rojo, amarillo, azul, magenta y cian siguen siéndolo (ajustados para leerse sobre negro), así que `ls`, `git diff` o los avisos se distinguen igual que en otro tema. Los grises (0, 7, 8 y 15) son verdosos.
- La ventana es verde también: textos verdes en tres niveles, superficies negras teñidas de verde, acento verde.
- **IBM Plex Mono** en la interfaz y en el terminal: ya va con la app, y viene de la familia de los terminales de IBM.
- Esquinas casi rectas (2 px, 4 px en paneles) y pestañas de carpeta: se distingue de Fósforo, que usa bloques.

### Berenjena (claro y oscuro): el terminal de Ubuntu

- El terminal, morado berenjena (`#300A24`) con texto blanco, en las dos variantes: en Ubuntu el terminal es morado aunque el escritorio sea claro.
- Paleta Tango, la de siempre en Ubuntu, **aclarada donde no se leía sobre el morado**: el azul (`#3465A4` daba 3,1:1; ahora `#729FCF`, 6,9:1) y el gris brillante. El prompt verde y azul se ve como el de Ubuntu sin depender de «negrita en colores brillantes», que OpenWard no hace.
- La ventana, gris neutro al estilo de GNOME (oscura `#2B2B2B`, clara `#EBEBEB`), con el naranja de Ubuntu de acento (`#E95420`). El botón principal usa un naranja más hondo (`#C13F14`) para que el texto blanco pase AA (con `#E95420` daba 3,5:1).
- La letra del sistema en la interfaz y en el terminal (en Ubuntu, Ubuntu Sans). Ubuntu Sans y Ubuntu Sans Mono tienen la Ubuntu Font Licence 1.0, no la OFL (también en Google Fonts), así que no van con la app hasta decidirlo.
- Esquinas de 6 px, paneles de 12 px y pestañas de segmento, como las de GNOME.

### Búnker (oscuro): los terminales de los refugios

- **Un solo fósforo, hasta en los 16 colores del terminal:** cada color es un brillo de verde, en proporción a la luminosidad del color que representa (el azul, apagado; el amarillo y el cian, casi blancos). Todos leen a 3:1 como mínimo, salvo el negro.
- La interfaz, toda en verde; la pestaña activa, invertida (bloque verde con texto oscuro), como la opción elegida en aquellos terminales; esquinas rectas.
- **Share Tech Mono** en la interfaz y el terminal, y **VT323** en los títulos grandes (las dos OFL 1.1, incluidas en la app). VT323 se puede elegir también para el terminal: es más fiel, pero más pequeña al mismo tamaño (en el lienzo, Tweaks › termFont).
- **El rojo se queda para el peligro:** producción, los errores de conexión y lo que se borra siguen en rojo. Rompe un poco el monocromo, pero producción nunca debe parecer un laboratorio. El aviso es amarillo verdoso, para no salirse del fósforo.
- Opcional, aparte del tema: el **«Efecto CRT»** (abajo), que es lo que más recuerda al juego.

### Tokens

Todos pasan las comprobaciones de `app/test/theme_test.dart` (texto a 4,5:1 sobre cada fondo, marcas a 3:1 sobre la ventana) y las de las etiquetas de entorno de `environment_test.dart`.

**Colores de la interfaz**

| Token | Monitor | Berenjena (oscuro) | Berenjena (claro) | Búnker |
|---|---|---|---|---|
| **Superficies** | | | | |
| `window` | `#060B07` | `#2B2B2B` | `#EBEBEB` | `#051209` |
| `surface` | `#040904` | `#1F1F1F` | `#FAFAFA` | `#071A0D` |
| `raised` | `#0B160D` | `#2E2E2E` | `#FFFFFF` | `#0B2414` |
| `sunken` | `#030703` | `#191919` | `#F1F1F1` | `#040E07` |
| `hover` | `#0E1D11` | `#363636` | `#E0E0E0` | `#0E2C18` |
| `selected` | `#122817` | `#404040` | `#D9D9D9` | `#12381F` |
| `border` | `#163220` | `#3A3A3A` | `#D4D4D4` | `#174526` |
| `control` | `#2B5636` | `#5C5C5C` | `#B0B0B0` | `#2A6E41` |
| **Texto** | | | | |
| `text` | `#8CFFA6` | `#F6F5F4` | `#2B2B2B` | `#8CFFB4` |
| `textMuted` | `#68DB84` | `#CFCDCA` | `#4F4F4F` | `#66DD94` |
| `textSubtle` | `#55C270` | `#B3B1AD` | `#5C5C5C` | `#55C881` |
| **Acción y acento** | | | | |
| `primary` | `#33FF66` | `#C13F14` | `#C13F14` | `#4DFF91` |
| `onPrimary` | `#021006` | `#FFFFFF` | `#FFFFFF` | `#03140A` |
| `accent` | `#33FF66` | `#E95420` | `#D9461A` | `#4DFF91` |
| `accentText` | `#5CFF85` | `#FF8D5E` | `#A9380F` | `#7DFFAA` |
| `accentSoft` | `#0D2E16` | `#47231A` | `#FBE3D8` | `#0F361D` |
| **Estados** | | | | |
| `info` | `#4DF2E0` | `#78AEED` | `#1A65C2` | `#B2FFD6` |
| `infoSoft` | `#082220` | `#1E2A38` | `#E3EDFA` | `#0D2B1C` |
| `infoLine` | `#1A4D47` | `#33506F` | `#AFCBEF` | `#2C6B4A` |
| `warn` | `#E6F25C` | `#F5A93A` | `#A55800` | `#E1FF6B` |
| `warnSoft` | `#1C1F07` | `#382A14` | `#FCEFD9` | `#1B2309` |
| `warnLine` | `#4A5218` | `#6E5022` | `#EBC68A` | `#4C5E1C` |
| `danger` | `#FF6B5E` | `#FF7B63` | `#B81D27` | `#FF7259` |
| `dangerSoft` | `#2A0F0C` | `#3A1F1B` | `#FBE6E6` | `#2B110C` |
| `dangerLine` | `#6E2A23` | `#7A3B32` | `#ECB2B4` | `#77301F` |
| **Etiquetas y velo** | | | | |
| `tagWarm` | `#E6F25C` | `#EFC14A` | `#7F5300` | `#E1FF6B` |
| `tagWarmSoft` | `#1C1F07` | `#3A3114` | `#F5EACD` | `#1B2309` |
| `scrim` | `#CC000000` | `#99000000` | `#4D000000` | `#CC000000` |

**Terminal.** Berenjena usa la misma paleta en claro y en oscuro (también como `terminalDark`).

| | Monitor | Berenjena | Búnker |
|---|---|---|---|
| `foreground` | `#33FF66` | `#FFFFFF` | `#66FF9F` |
| `background` | `#040904` | `#300A24` | `#071A0D` |
| `cursor` | `#33FF66` | `#FFFFFF` | `#66FF9F` |
| `selection` | `#1C5E30` | `#7A4D6E` | `#1E6B3D` |
| 0 negro | `#0F2A17` | `#2E3436` | `#123A20` |
| 1 rojo | `#FF5C57` | `#EF2929` | `#3BBF6A` |
| 2 verde | `#33FF66` | `#73D216` | `#66FF9F` |
| 3 amarillo | `#E6F25C` | `#EDD400` | `#B8FFD2` |
| 4 azul | `#5CB8FF` | `#729FCF` | `#2E9E58` |
| 5 magenta | `#E07CFF` | `#C49BC0` | `#4FD785` |
| 6 cian | `#4DF2E0` | `#2BC4C4` | `#94FFC0` |
| 7 blanco | `#A8E6B8` | `#D3D7CF` | `#7DF0AA` |
| 8 brillante negro | `#3E7A50` | `#888A85` | `#2C7247` |
| 9 brillante rojo | `#FF8A80` | `#FF6B6B` | `#5FE08E` |
| 10 brillante verde | `#8AFFA6` | `#8AE234` | `#8CFFB8` |
| 11 brillante amarillo | `#F5FF8A` | `#FCE94F` | `#DAFFE8` |
| 12 brillante azul | `#8FD0FF` | `#9DBFEA` | `#45BE74` |
| 13 brillante magenta | `#EEA8FF` | `#DDB8D9` | `#73EBA2` |
| 14 brillante cian | `#8AFFF0` | `#5FF0F0` | `#BBFFD7` |
| 15 brillante blanco | `#E6FFEC` | `#EEEEEC` | `#EDFFF4` |

| | Monitor | Berenjena | Búnker |
|---|---|---|---|
| Contraste del texto del terminal | 14,9:1 | 17,6:1 | 14,1:1 |

**Forma**

| | Monitor | Berenjena | Búnker |
|---|---|---|---|
| `radiusSmall` / `radius` / `radiusLarge` | 0 / 2 / 4 | 4 / 6 / 12 | 0 / 0 / 0 |
| Pestañas | `folder` | `segment` | `block` |
| `pills` / `insetTerminal` | no / no | no / no | no / no |

**Fuentes**

| | Monitor | Berenjena | Búnker |
|---|---|---|---|
| Interfaz | IBM Plex Mono | la del sistema | Share Tech Mono |
| Títulos (`display`) | la de la interfaz | la de la interfaz | VT323 |
| Etiquetas (`label`) | la de la interfaz | la de la interfaz | Share Tech Mono |
| Monoespaciada y terminal | IBM Plex Mono (ahora también en negrita) | la del sistema | Share Tech Mono |
| Incluida en la app | sí (se añade IBM Plex Mono Bold) | no hace falta | sí (OFL 1.1) |

### Cambios en el código

Hechos el 2026-10-19 para las siete familias (también las de la segunda ronda):
- `ui/themes.dart`: once `OwTheme` (`monitor`, `berenjena-oscuro`, `berenjena-claro`, `bunker`, `marino`, `catppuccin-latte`, `catppuccin-mocha`, `alucard`, `dracula`, `tokyo-night-day`, `tokyo-night`) en `OwThemes.all`, y siete `ThemeFamily` después de las cinco de antes.
- `terminal/schemes.dart`: sus paletas en `ThemePalettes`; Catppuccin, Dracula y Tokyo Night son las mismas que ya había en la lista de esquemas, que ahora las comparte, y la lista gana Alucard y Tokyo Night Day.
- `assets/fonts/`: Share Tech Mono, VT323 e IBM Plex Mono Bold, con su licencia al lado y en `NOTICE`; Share Tech Mono y VT323 entran también en las listas de fuentes de Apariencia, para mezclarlas con cualquier tema.
- Novedades: `newsVersion` pasa a 0.3.1-beta.5 con la entrada «Siete familias de temas más».
- Pruebas: `theme_test.dart` y `environment_test.dart` recorren `OwThemes.all`, así que comprueban los temas nuevos sin tocarlas; la galería (`gallery_test.dart`) saca capturas de las siete familias.
- Nada de l10n en los nombres: son nombres propios, iguales en todos los idiomas.
- Ajustes guardados: si alguien vuelve a una versión anterior con uno de estos temas elegido, `resolveTheme` ya cae en Papel o Grafito.

## Más propuestas, para elegir

En el lienzo, con una ventana pequeña cada una (fila de y=35680). Todas con los mismos tokens y las mismas comprobaciones de contraste cuando se diseñen enteras.

| Familia | Variantes | Idea | Para quién |
|---|---|---|---|
| Ámbar | oscuro | Monocromo ámbar (`#FFB000` sobre casi negro), el compañero de Monitor | Quien quiere el fósforo pero más cálido; cansa menos de noche |
| Cobalto | oscuro | El azul de los gestores de archivos de MS-DOS: fondo azul, cian, amarillo y blanco | Nostalgia de los noventa; muy legible |
| Vigilia | oscuro | Todo en rojo tenue sobre negro, sin luz azul; el peligro pasa a amarillo | Guardias de madrugada: no deslumbra ni rompe la adaptación a la oscuridad |
| Prisma | claro y oscuro | Paleta Okabe–Ito: producción en naranja y pruebas en azul, que se distinguen también en luminosidad | Daltonismo; va con Alto contraste en el apartado de accesibilidad |
| Neón | oscuro | Synthwave: magenta y cian sobre violeta | Quien quiere algo vistoso |
| Tinta | claro | Grises de papel electrónico, sin color salvo el peligro | Leer, presentar y hacer capturas para documentación |

Otras dos ideas que no son temas enteros:
- **Más esquemas del terminal** en la lista de siempre (Tango, Kanagawa, Everforest, Ayu, GitHub claro y oscuro), con licencia MIT como los de ahora; Campbell y Rosé Pine pasan a temas enteros en la segunda ronda. Es la capa «Colores del terminal», y cuesta poco.
- **«Efecto CRT»**, una opción del terminal para cualquier tema, apagada por defecto: líneas de barrido, un brillo suave alrededor del texto y las esquinas algo más oscuras. Sin parpadeo, para no molestar a nadie (y menos con «reducir movimiento»). Las líneas y el viñeteado son una capa encima del terminal; el brillo pide una segunda pasada del texto en el renderer, que hay que medir antes de prometerlo.

## Segunda ronda: paletas famosas, ordenadores y cine

En el lienzo, fila de y=37160: Marino a tamaño completo y dos hojas de ventanas pequeñas. Pasa las mismas comprobaciones que los cuatro de arriba (Marino entero; las demás, en lo que enseñan las ventanas pequeñas).

### Marino (oscuro)

Letras verdes sobre un azul marino índigo, el aire de los clientes SSH modernos: el texto del terminal en verde (`#21B263` sobre `#131729`, 6,4:1), el prompt en un verde azulado más hondo, las carpetas en azul, los enlaces en azul celeste y las imágenes en magenta; la ventana en grises azulados, con el acento y el cursor verdes. Los azules y el magenta van más claros de lo habitual en esta clase de paletas para leerse a 3,5:1 como mínimo. Usa la letra del sistema en la interfaz y JetBrains Mono en el terminal, así que no hay que descargar nada. Esquinas de 6, 8 y 12 px y pestañas de segmento.

| Capa | Valores |
|---|---|
| Superficies | `window` `#1E2030`, `surface` `#1A1C2B`, `raised` `#262939`, `sunken` `#151724`, `hover` `#2A2D3F`, `selected` `#30344A`, `border` `#2A2D3E`, `control` `#40445B` |
| Texto | `text` `#F2F3F6`, `textMuted` `#BABECD`, `textSubtle` `#A3A7BA` |
| Acción y acento | `primary` `#22B565`, `onPrimary` `#08160F`, `accent` `#22B565`, `accentText` `#52D18D`, `accentSoft` `#173730` |
| Estados | `info` `#5AA2FF`, `infoSoft` `#192840`, `infoLine` `#2D4C78`, `warn` `#F0B44C`, `warnSoft` `#2C2416`, `warnLine` `#5E4A22`, `danger` `#FF6B73`, `dangerSoft` `#33191F`, `dangerLine` `#723039` |
| Etiquetas y velo | `tagWarm` `#F0B44C`, `tagWarmSoft` `#2C2416`, `scrim` `#990A0C16` |
| Terminal | texto `#21B263` sobre `#131729` (6,4:1), cursor `#21B263`, selección `#1F4A3E` |
| ANSI | 0 `#262B3F`, 1 `#E5484F`, 2 `#0E9A6E`, 3 `#DDB03E`, 4 `#2E73C9`, 5 `#C8378A`, 6 `#2B92F5`, 7 `#BAC0D0`, 8 `#666D87`, 9 `#FF6B73`, 10 `#3DDC86`, 11 `#F2CC5C`, 12 `#5A9BEA`, 13 `#E163A6`, 14 `#5CB2FF`, 15 `#EEF0F6` |
| Fuentes | interfaz: la del sistema; monoespaciada y terminal: JetBrains Mono |

### Paletas famosas, para toda la ventana

Hoy siete de ellas son solo un esquema del terminal; la propuesta es llevarlas a toda la ventana con sus propios colores. Sus proyectos las publican con licencia libre y animan a portarlas, así que conservan su nombre. En la ventana solo se aclara algún rojo para que lea a 4,5:1 (Solarized, Nord); los colores del terminal van tal cual los publican, y los que no llegan a 3:1 (el gris brillante de casi todas, el azul de Campbell) los arregla la opción «Contraste mínimo».

| Familia | Variantes | De dónde sale |
|---|---|---|
| Catppuccin | claro y oscuro (Latte y Mocha; Frappé y Macchiato si se quiere) | Catppuccin, MIT |
| Dracula | claro y oscuro (Alucard y Dracula) | Dracula, MIT |
| Tokyo Night | claro y oscuro (Day y Night) | Tokyo Night, MIT |
| Nord | claro y oscuro (Snow Storm y Polar Night) | Nord, MIT |
| Rosé Pine | claro y oscuro (Dawn y Main) | Rosé Pine, MIT |
| Gruvbox | claro y oscuro | Gruvbox, MIT |
| Solarized | claro y oscuro | Solarized, MIT |
| Darcula | oscuro (y su pareja clara) | el tema de los IDE de JetBrains, Apache-2.0; con JetBrains Mono, que ya va con la app |
| Campbell | oscuro | el esquema por defecto de Windows Terminal, MIT; con Cascadia Mono (OFL) |

Al implementarlas, los valores se copian de la fuente oficial de cada una, con su aviso en `NOTICE`, como los esquemas de ahora.

**Ya implementadas:** Catppuccin (Latte y Mocha), Dracula (Alucard y Dracula) y Tokyo Night (Day y Night), con IBM Plex Sans y JetBrains Mono. El terminal, tal cual lo publican, salvo el texto de Tokyo Night Day, un punto más oscuro (`#3459B5` en vez de `#3760BF`, que leía a 4,47:1). La ventana sale de sus propios colores (en Catppuccin, `crust`, `mantle`, `base` y `surface0` a `surface2`; en Dracula, sus fondos y su morado; en Tokyo Night, `bg_dark`, `bg` y `bg_highlight`), con los rojos y los textos tenues ajustados donde no llegaban a 4,5:1 y las páginas de Tokyo Night Day algo más claras que su terminal, para que las etiquetas de entorno se lean. Pestañas: píldora en Catppuccin, carpeta en Dracula y segmento en Tokyo Night. Los valores exactos, en `app/lib/ui/themes.dart`.

### Ordenadores y cine

Nombres y valores propios: de esas máquinas y películas solo se toma la idea de los colores.

| Familia | Variantes | Idea |
|---|---|---|
| Guisante | claro | Los cuatro verdes de la pantalla de las consolas de bolsillo; el rojo, solo para el peligro |
| Casete | oscuro | El azul con letras lila de los ordenadores de 8 bits, aclarado para que se lea |
| Disquete | oscuro | El escritorio azul, blanco y naranja de finales de los ochenta |
| Central | oscuro | Los terminales de color de los ordenadores centrales: verde para escribir, turquesa para las etiquetas, blanco para resaltar |
| Rejilla | oscuro | Las rejillas de neón cian del cine de ciencia ficción, con naranja para el peligro |
| Lluvia | oscuro | Neón ámbar y turquesa del cine negro futurista |

## Accesibilidad

- Los cuatro temas pasan las mismas comprobaciones que los de ahora; el texto del terminal está entre 14:1 y 17,6:1.
- Los colores ANSI leen a 3:1 como mínimo (salvo el negro), que es donde empieza la opción de contraste mínimo.
- En Búnker, `git diff` o `ls` se distinguen por el brillo, no por el color: es lo que se elige con ese tema. Quien quiera color con la ventana de Búnker combina las capas (por ejemplo, Búnker con los colores del terminal de Monitor).
- El rojo de peligro y de producción se mantiene en los tres temas.

## Preguntas abiertas

1. ~~¿Entran las tres familias?~~ Sí, y Marino, Catppuccin, Dracula y Tokyo Night (2026-10-19).
2. ¿Se incluyen Ubuntu Sans y Ubuntu Sans Mono con su licencia (Ubuntu Font Licence 1.0, libre pero distinta de la OFL)? Mientras no, Berenjena usa la letra del sistema.
3. Búnker: ¿monocromo estricto en el terminal (la propuesta) o con el rojo de los errores?
4. ¿Cuáles de las propuestas extra, después de estas? Recomendación: Ámbar (poco trabajo y hace pareja con Monitor) y Prisma (accesibilidad).
5. ¿El «Efecto CRT» con estos temas o más adelante, después de medir el brillo?
6. Versión: no tocan el vault, así que pueden ir en cualquier beta de la 0.3.
