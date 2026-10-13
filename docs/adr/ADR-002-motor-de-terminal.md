# ADR-002 — Motor de terminal: estado en Rust, render en Flutter

- **Estado:** aceptado (2026-10-13): **`libghostty-vt`**, con las condiciones de la sección «Validación y revisión» ([informe del spike S1](../spikes/S1-terminal-resultados.md)).
- **Fecha:** 2026-10-08 (propuesto); 2026-10-13 (aceptado).
- **Alcance:** emulación VT, scrollback, render y entrada.

## Contexto

El terminal es lo que el usuario percibe en cada segundo de uso: latencia, fidelidad con vim, tmux y htop, IME, selección y scroll en móvil. Además, el estado del terminal también hace falta fuera de la UI: para grabar (asciicast), buscar, la CLI y el modo `tmux -CC`.

**Verificación del 2026-10-08:**

- **`xterm.dart` está prácticamente abandonado.** Su última versión en pub.dev es la 4.0.0 (27-feb-2024), el último commit es del 19-jun-2025 y tiene 110 issues abiertos. Entre ellos hay problemas de tirones con comandos interactivos (#73, abierto desde 2021), de IME coreano (#164) y de composición en Android (#143). ([pub.dev](https://pub.dev/packages/xterm), [GitHub](https://github.com/TerminalStudio/xterm.dart))
- **`alacritty_terminal`:**
  - versión 0.26.0 (6-abr-2026), Apache-2.0 y activo;
  - 69 crates lo embeben (egui_term, iced_term, gpui-terminal) y Zed usa un fork;
  - no promete una API estable, y su módulo `tty` (PTY) no va detrás de una feature.
- **`libghostty-vt`:**
  - MIT, muy activo, con builds para iOS (xcframework) y un job de CI para Android;
  - su cabecera C se declara "work-in-progress API… not yet stable" y la build necesita Zig 0.16. ([Ghostty](https://github.com/ghostty-org/ghostty))

El spike S1 comparó los dos candidatos con el mismo adaptador, el mismo formato de frames y el mismo render ([S1-terminal.md](../spikes/S1-terminal.md)).

## Decisión

- **Motor: `libghostty-vt`**, fijado a un commit exacto de Ghostty (hoy `05dcf887`) y compilado con Zig 0.16.0. Va detrás de nuestro adaptador `TermEngine`.
  - **Bindings:** se generan con `bindgen` y se commitean.
  - **Apple:** la librería se pre-enlaza en un solo objeto que solo exporta `ghostty_*`.
  - **Adaptador:** corrige lo que S1.6 encontró (BCE, tamaño tras DECCOLM, DEL) y responde a las consultas con las opciones de la librería.
- **`alacritty_terminal` queda descartado como motor.** No pasa la puerta de memoria y le faltan funciones que Ghostty trae. Se mantiene en `core/` solo como segunda referencia de corrección, hasta que el adaptador de Ghostty pase a `core/`.
- **Tubería:**
  - el núcleo procesa todo el flujo SSH y emite ***damage* por filas** (tramos de texto con estilo, frame v1) por `flutter_rust_bridge`;
  - el frame se codifica **dentro del tick de vsync**, de forma síncrona: la vía asíncrona añadía un refresco de latencia.
- **Render propio en Flutter:**
  - un `CustomPainter` con un `Picture` en caché por fila y un **atlas de glifos**;
  - celdas ajustadas a píxeles físicos;
  - cajas, bloques y Powerline dibujados como geometría;
  - párrafo de respaldo para emoji y clústeres raros.
- **Entrada:**
  - teclado, ratón, pegado y foco con los codificadores de Ghostty (xterm y protocolo kitty);
  - las teclas funcionales y las combinaciones van al codificador, el texto al método de entrada (`TextInputClient` propio);
  - composición del IME en el cursor;
  - pegado de varias líneas con confirmación;
  - barra de teclas en móvil.
- **Terminal local:** `portable-pty` 0.9.0 fijado (probado en el banco de S1.5).
- **`xterm.dart` sigue sin ser plan B.** Solo sirve como referencia de código para la parte de render e input en Flutter (MIT).

**Puerta del spike S1 y resultado** (macOS; los dispositivos son condición de esta aceptación):

| Métrica | Umbral | Resultado con `libghostty-vt` |
|---|---|---|
| Salida masiva (`cat` grande) | Sin cuadros congelados > 100 ms; la UI responde | 60 fps procesando 154–495 MiB/s, 0 congelados |
| Latencia del eco de una tecla, desde los datos recibidos hasta el pintado | p95 < 1 refresco + 4 ms (≈ 21 ms a 60 Hz). Con flujos continuos el byte más antiguo espera por construcción casi un refresco, así que se miden por fps y tiempo de frame ([S1 §10.2](../spikes/S1-terminal.md#102-banco-de-render-en-flutter-s14)) | p95 16,5 ms |
| `vttest` (pantallas básicas), vim, tmux, htop, mc | Sin errores visibles | Comparado con tmux en 551 pantallas de vttest y 23 de apps reales; 3 fallos de Ghostty documentados ([S1 §10.7](../spikes/S1-terminal.md#107-corrección-vttest-anchos-unicode-apps-reales-y-respuestas-s16)) |
| IME (japonés y chino) y teclado en pantalla de Android | Composición correcta | Pruebas automáticas en macOS; faltan IME reales y móvil |
| Memoria de scrollback | < 300 MB con 10 pestañas × 10.000 líneas × 120 columnas; 40.000 líneas por defecto solo con scrollback compacto | 98–104 MB (alacritty: 322 MB); 15 MB con compresión, así que 40.000 líneas son viables |

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| `alacritty_terminal` | API más estable, sin Zig, Apache-2.0 | No pasa la puerta de memoria (322 MB). Habría que escribir la codificación de teclado y ratón, el protocolo kitty, las respuestas y un scrollback compacto. Le faltan márgenes laterales, línea de estado y áreas protegidas |
| `xterm.dart` puro | Ya integrado con Flutter; menos FFI | Sin versión desde febrero de 2024; problemas abiertos de rendimiento e IME; habría que mantener un fork |
| WebView con xterm.js | El terminal web más probado | Una WebView por pestaña; teclado e IME en móvil problemáticos; dos runtimes |
| Vistas nativas por plataforma (SwiftTerm, Termux view…) | Máxima integración | Cuatro implementaciones distintas |

## Consecuencias

- **El render propio es trabajo real:** glifos anchos, emoji, combinaciones, ligaduras opcionales y accesibilidad para lectores de pantalla. A cambio, un único estado VT sirve para todas las funciones (grabación, búsqueda, MCP, CLI). El rendimiento no depende del recolector de basura de Dart en el camino caliente.
- **Zig 0.16.0 entra en el toolchain:** en CI y en las máquinas de desarrollo, con una librería precompilada por destino y cacheada. Añade +1 MB al binario.
- **Mantenimiento de la API de Ghostty:**
  - el commit se actualiza a propósito, no solo: cada trimestre o cuando haga falta un arreglo;
  - cada actualización regenera los bindings y pasa `make conformance`, que compara con las referencias de tmux y detecta regresiones.
- **Fallos que reportar upstream:** DEL impreso en una celda (mitigado en el adaptador), parámetro 0 en SU/SD/IL/DL/DCH/CHT/CBT/HPR/VPR, y `_` del juego gráfico DEC.
- **Agrupación de grafemas (modo 2027) activa por defecto:** emoji y banderas ocupan las celdas correctas. Los programas que calculan el ancho por punto de código (vim) se descuadran con emoji compuestos; por eso será configurable.

## Validación y revisión

**Condiciones de esta aceptación.** El ADR se reabre si alguna falla:
1. **Android de gama media (S1.2):** parseo ≥ 50 MiB/s, salida masiva a ≥ 55 fps, eco dentro de la puerta e IME con Gboard.
2. **iOS (S1.2):** lo mismo en un iPhone.
3. **Windows y Linux:** la librería compila y enlaza en CI (MSVC en Windows) y el banco funciona.
4. **Accesibilidad:** VoiceOver y TalkBack pueden leer la pantalla fila a fila con el render propio.

Si se reabre, la alternativa es `alacritty_terminal` con un scrollback compacto propio (la S1.7, descartada por ahora). Se revisa también si Ghostty deja de mantener la librería o si una actualización rompe más de lo que el adaptador puede absorber.
