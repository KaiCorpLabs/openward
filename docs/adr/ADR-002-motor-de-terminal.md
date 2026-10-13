# ADR-002 — Motor de terminal: estado en Rust, render en Flutter

- **Estado:** propuesto. **Recomendación provisional tras S1.3 (2026-10-13): `libghostty-vt`**, pendiente de S1.2, S1.5 y S1.6 ([evidencia](../spikes/S1-terminal.md#104-libghostty-vt-frente-a-alacritty_terminal-s13)).
- **Fecha:** 2026-10-08.
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

## Decisión

- **Estado y parser en Rust**, con dos candidatos que se deciden en el spike S1: **`alacritty_terminal`** (opción convencional en Rust) y **`libghostty-vt`** (más moderno: kitty graphics, búsqueda, encoders de teclado y ratón, pero con una API inestable y un toolchain Zig añadido).
- El núcleo procesa todo el flujo SSH y emite ***damage* por filas** (tramos de texto con estilo) a ≤ 60 Hz por `flutter_rust_bridge` sin copias.
- **Render propio en Flutter:** un `CustomPainter` con caché de glifos, alineado a la rejilla. Gestiona la selección, el IME y la barra de teclas móviles.
- **`xterm.dart` deja de ser plan B.** Solo sirve como referencia de código para la parte de render e input en Flutter (MIT).
- **Se fija una versión exacta** del motor elegido, detrás de un adaptador `TermEngine` propio, para absorber los cambios de API.

**Puerta del spike S1**, que se mide en las 5 plataformas entre los dos motores:

| Métrica | Umbral |
|---|---|
| `cat` de 100 MB | Sin cuadros congelados > 100 ms; la UI responde |
| Latencia del eco de una tecla, desde los datos recibidos hasta el pintado | p95 < 1 refresco + 4 ms (≈ 21 ms a 60 Hz). Con flujos continuos el byte más antiguo espera por construcción casi un refresco, así que se miden por fps y tiempo de frame ([S1 §10.2](../spikes/S1-terminal.md#102-banco-de-render-en-flutter-s14)) |
| `vttest` (pantallas básicas), vim, tmux, htop, mc | Sin errores visibles |
| IME (japonés y chino) y teclado en pantalla de Android | Composición correcta |
| Memoria de scrollback | < 300 MB con 10 pestañas × 10.000 líneas × 120 columnas; 40.000 líneas por defecto solo con scrollback compacto (el smoke test da ~26 B/celda con `alacritty_terminal`, ver [S1](../spikes/S1-terminal.md#10-resultados-preliminares-s10-smoke-test)) |

A igualdad de resultados gana `alacritty_terminal`, porque añade un toolchain menos (Zig) y su API cambia con menos frecuencia.

## Alternativas

| Alternativa | Ventaja | Por qué no como primera opción |
|---|---|---|
| `xterm.dart` puro | Ya integrado con Flutter; menos FFI | Sin versión desde febrero de 2024; problemas abiertos de rendimiento e IME; habría que mantener un fork |
| WebView con xterm.js | El terminal web más probado | Una WebView por pestaña; teclado e IME en móvil problemáticos; dos runtimes |
| Vistas nativas por plataforma (SwiftTerm, Termux view…) | Máxima integración | Cuatro implementaciones distintas |

## Consecuencias

El render propio es trabajo real: glifos anchos, emoji, combinaciones, ligaduras opcionales y accesibilidad para lectores de pantalla. A cambio, un único estado VT sirve para todas las funciones (grabación, búsqueda, MCP, CLI) y el rendimiento no depende del recolector de basura de Dart en el camino caliente.

## Validación y revisión

Aceptar con los números de S1 en `docs/spikes/S1-terminal.md`. Reabrir si la accesibilidad (VoiceOver o TalkBack) no es viable en el render propio. Si gana `alacritty_terminal`, revisar `libghostty-vt` cuando publique una API estable.
