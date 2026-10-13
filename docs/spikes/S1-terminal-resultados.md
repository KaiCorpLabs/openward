# Spike S1 — Resultados: motor de terminal

- **Fecha:** 2026-10-13.
- **Estado:** cerrado en macOS. Las pruebas en dispositivos (S1.2) y en Windows y Linux quedan como condiciones de la decisión.
- **Decide:** [ADR-002](../adr/ADR-002-motor-de-terminal.md), aceptado con `libghostty-vt`.
- **Detalle, método y datos:** [S1-terminal.md §10](S1-terminal.md#10-resultados-preliminares-s10-smoke-test) y `spikes/s1-terminal/results/`.

## Respuesta

**`libghostty-vt` como motor**, detrás de nuestro adaptador `TermEngine`, con **render propio en Flutter** basado en un atlas de glifos. Es el único de los dos candidatos que pasa la puerta de memoria. Además trae casi todo lo que con `alacritty_terminal` tendríamos que escribir nosotros: codificadores de teclado y ratón, protocolo kitty, grafemas, pegado seguro, respuestas a consultas y compresión del historial. A cambio, su API aún cambia y la build necesita Zig. Ambas cosas son manejables con un commit fijado y nuestro adaptador.

## Puerta

Medido en un Apple M5 con pantalla a 60 Hz, en release. «Pendiente» significa que hace falta el dispositivo.

| Métrica | Umbral | alacritty | Ghostty | Estado |
|---|---|---|---|---|
| Parseo en el núcleo | ≥ 50 MiB/s en Android de gama media | 100–250 MiB/s (Mac) | 72–841 MiB/s (Mac) | Pendiente en Android (S1.2) |
| Salida masiva con la UI | Ningún frame > 100 ms; ≥ 55 fps; construcción + raster < 1 refresco | 60 fps; un frame congelado en 5 cargas | **60 fps procesando 154–495 MiB/s**; 0 congelados; construcción p95 1,5–3,3 ms, raster ≤ 0,4 ms | **Pasa** en Mac |
| Eco en el núcleo | p99 < 1 ms | 1,4 µs | 2,6 µs | **Pasa** |
| Eco de una tecla hasta el pintado | p95 < 1 refresco + 4 ms (20,7 ms) | 16,2 ms | **16,5 ms** (máx. 25,4) | **Pasa** en Mac |
| Corrección | vttest, vim, tmux, htop, less, man; diferencias documentadas | Coincide más con tmux, pero le faltan funciones VT220+ | Acierta en casi todo donde discrepan los dos | **Pasa**, con 3 fallos de Ghostty documentados |
| IME | Japonés, chino y coreano; Gboard y teclado de iOS | — | Probado con pruebas automáticas en Mac | Pendiente con IME reales y en móvil |
| **Memoria de scrollback** | < 300 MB (10 pestañas × 10.000 líneas × 120 columnas) | **322 MB: no pasa** | **98–104 MB**; 15 MB comprimido | **Pasa** |
| Accesibilidad | VoiceOver y TalkBack leen la pantalla fila a fila | — | No probado | **Pendiente** |

## Hipótesis

| # | Hipótesis | Resultado |
|---|---|---|
| H1 | Los dos motores parsean ≥ 50 MiB/s en móvil | Confirmada en Mac, con margen de 1,5 a 17 veces. Falta Android |
| H2 | alacritty no cabe en la memoria con 40.000 líneas; Ghostty sí | **Confirmada.** Ghostty ocupa 3 veces menos y comprime entre 6 y 7,5 veces más con logs reales |
| H3 | Un redibujado completo de 200×50 cabe en < 16 ms | Confirmada en Mac: la grabación de filas en p95 baja de 3,3–10,3 ms a 1,2–3,1 ms con el atlas. Falta Android |
| H4 | El IME funciona con un `TextInputClient` propio | Confirmada en Mac con pruebas automáticas de composición, confirmación y borrado. Falta probar con IME reales y en móvil |
| H5 | Con alacritty habría que escribir la codificación de teclado y ratón; Ghostty la trae | **Confirmada.** Con Ghostty, toda la entrada usa sus codificadores; solo es nuestra la tabla de teclas físicas |

## Puntuación final

| Criterio | Peso | alacritty | Ghostty | Qué cambió desde S1.3 |
|---|---|---|---|---|
| Memoria de scrollback | 25 % | 3 | 10 | Confirmado con logs reales (S1.1) |
| Trabajo propio pendiente | 25 % | 4 | 9 | S1.5 y S1.6 confirman los codificadores y las respuestas de Ghostty. A alacritty le faltan márgenes laterales, línea de estado, áreas protegidas y la mayoría de respuestas |
| Estabilidad de API y mantenimiento | 20 % | 7 | 4 | Sin cambios. Ghostty tiene 3 fallos que reportar upstream |
| Complejidad de build | 15 % | 10 | 4 | Se añade el pre-enlace en Apple; compila para Mac, iOS, Android, Linux y Windows (GNU) |
| Rendimiento | 15 % | 7 | 9 | Con la UI, Ghostty procesa entre 4 y 8 veces más datos a 60 fps |
| **Total ponderado** | | **5,7** | **7,5** | |

## Qué se lleva el producto

Probado en el spike y listo para pasar a `core/` y a la app:

- **Núcleo:**
  - el trait `TermEngine` y el formato de frames v1;
  - el adaptador de Ghostty, fijado al commit `05dcf887`, con Zig 0.16.0 y bindings generados;
  - pre-enlace en Apple, para que su `compiler_rt` no choque con el de Rust;
  - correcciones del adaptador: BCE, tamaño tras DECCOLM y filtro de DEL;
  - respuestas a consultas: XTVERSION, tamaño, esquema, colores y terminfo.
- **Tubería:**
  - codificar el frame dentro del tick de vsync, de forma síncrona. La vía asíncrona añadía un refresco entero;
  - solo hay trabajo si el motor tiene cambios.
- **Render:**
  - atlas de glifos con celdas en píxeles físicos;
  - cajas, bloques y Powerline dibujados como geometría;
  - párrafo de respaldo para emoji y clústeres raros.
- **Entrada:**
  - las teclas funcionales y las combinaciones van al codificador, el texto al método de entrada;
  - composición del IME en el cursor;
  - pegado con confirmación;
  - barra de teclas en móvil.
- **Pruebas:**
  - `termbench conform` contra referencias de tmux;
  - capturas comparables;
  - pruebas de integración de entrada en Flutter.
- **Terminal local:** `portable-pty` 0.9.0, probado en el banco.

## Condiciones de la aceptación

Se reabre el ADR-002 si alguna falla:

1. **Android de gama media (S1.2):** parseo ≥ 50 MiB/s, salida masiva a ≥ 55 fps, eco dentro de la puerta e IME con Gboard.
2. **iOS (S1.2):** lo mismo en un iPhone. Antes hay que arreglar la compilación del banco para iOS: `backtrace`, que llega por flutter_rust_bridge, no compila con `libc` 0.2.190.
3. **Windows y Linux:** compilar y enlazar en CI. Probado hasta ahora: la librería se compila de forma cruzada para Linux x86_64 y Windows (GNU). Falta enlazar con MSVC; ojo, la librería se llama `ghostty-vt-static.lib`. Después, pasar el banco una vez en cada sistema.
4. **Accesibilidad:** prototipo con `Semantics` por fila; VoiceOver y TalkBack deben leer la pantalla.

## Decisiones derivadas (propuestas, a confirmar)

| Tema | Propuesta | Por qué |
|---|---|---|
| Agrupación de grafemas (modo 2027) | Activa por defecto y configurable | Emoji y banderas en las celdas correctas, como Ghostty y tmux. Con vim, los emoji compuestos descuadran la línea |
| Cambio a 132 columnas (DECCOLM) | Respetarlo como xterm, solo si el programa activa el modo 40; la vista escala la rejilla | Casi solo lo usan vttest y programas antiguos; lo correcto es comportarse como xterm |
| Opción = Alt en macOS | Desactivado por defecto y configurable | Con teclado español, Opción escribe @, #, \\ y otros |
| Actualizar Ghostty | Cada trimestre o ante un arreglo necesario, regenerando bindings y pasando `make conformance` | La API cambia; las referencias de tmux detectan regresiones |
| Fallos de Ghostty | Reportar upstream: DEL impreso, parámetro 0 en SU/SD/IL/DL/DCH/CHT/CBT/HPR/VPR, `_` del juego gráfico DEC | Mientras tanto, el DEL se filtra en el adaptador |

## Lo que no se hizo

- **S1.7 (scrollback compacto propio):** descartada. Solo hacía falta si ganaba alacritty; Ghostty ya pasa la puerta y además comprime.
- **S1.2 (dispositivos):** pendiente. Queda como condición 1 y 2.
- **Dentro del alcance pero sin probar:** accesibilidad (condición 4). Selección, búsqueda, ligaduras e imágenes estaban fuera del alcance.
