# Spike S1 — Motor de terminal

- **Estado:** en preparación. S1.0 está hecho: interfaz común, formato de frames, backend `alacritty_terminal` y `termbench`.
- **Fecha:** 2026-10-08.
- **Decide:** [ADR-002](../adr/ADR-002-motor-de-terminal.md).
- **Duración estimada:** 15–20 días de trabajo (dentro de las 4–6 semanas de la fase 0).

## 1. Pregunta

¿Qué motor VT (**`alacritty_terminal`** o **`libghostty-vt`**), con un **render propio en Flutter**, cumple la puerta del ADR-002 en Windows, macOS, Linux, Android e iOS, y con cuánto trabajo propio?

## 2. Hipótesis

| # | Hipótesis | Cómo se refuta |
|---|---|---|
| H1 | Los dos motores procesan la salida mucho más rápido de lo que llega por red (≥ 50 MiB/s en móvil de gama media) | `termbench run` en un dispositivo Android de gama media |
| H2 | El scrollback de `alacritty_terminal` (~26 B/celda) no cabe en el presupuesto de memoria con 40.000 líneas; `libghostty-vt`, con celdas compactas, sí | `termbench mem` con ambos motores |
| H3 | Un `CustomPainter` con caché de filas pinta un redibujado completo de 200×50 en < 16 ms p95 en un Android de gama media | Harness de render + `FrameTiming` |
| H4 | La composición IME (japonés, chino, coreano) y el teclado de Android funcionan con un `TextInputClient` propio | Pruebas manuales guiadas (§7) |
| H5 | Con `alacritty_terminal` tendremos que escribir la codificación de teclado y ratón (xterm y protocolo de teclado kitty); `libghostty-vt` la trae | Inventario de lo implementado al final del spike |

## 3. Alcance

**Dentro del alcance:** estado VT, formato de frames entre núcleo y UI, render, entrada (teclado, IME, ratón, pegado), scroll y scrollback, memoria, corrección con apps reales y una accesibilidad básica.

**Fuera del alcance:** SSH (S2), firmantes (S3), selección y búsqueda avanzadas, ligaduras, imágenes (sixel/kitty), temas y pulido visual.

## 4. Montaje

```mermaid
flowchart LR
  subgraph Núcleo Rust
    SRC[Corpus sintético<br/>grabaciones .cast<br/>PTY local] --> ENG{TermEngine}
    ENG --> A[alacritty_terminal]
    ENG --> G[libghostty-vt<br/>FFI C, Zig 0.16]
    ENG --> ENC[FrameEncoder<br/>frames de damage v1]
  end
  ENC --> TB[termbench<br/>rendimiento, eco, memoria]
  ENC -->|flutter_rust_bridge<br/>stream Uint8List| RH[Harness Flutter<br/>decodificador Dart + CustomPainter]
  RH --> M[FrameTiming, latencia,<br/>IME, accesibilidad]
```

- **`core/crates/openward-term`**: el trait `TermEngine`, el formato de frames v1 (documentado en `frame.rs`, con decodificador de referencia) y el backend `alacritty` con pruebas. **Hecho.**
- **`spikes/s1-terminal/termbench`**: CLI que mide la parte del núcleo. **Hecho:** `gen`, `run`, `replay` (asciicast v2/v3), `echo` y `mem`, con salida en texto o JSON.
- **`spikes/s1-terminal/render_harness`**: app Flutter que recibe frames por `flutter_rust_bridge`, los decodifica en Dart y los pinta. **Pendiente** (S1.4).

## 5. Corpus

| Tipo | Contenido | Estado |
|---|---|---|
| Sintético (`termbench gen`) | `ascii` (cat de un log), `sgr-log` (16, 256 y truecolor), `unicode` (CJK, emoji, combinantes, caracteres de caja), `fullscreen` (estilo htop, pantalla alternativa), `scroll-region` (estilo vim o less, DECSTBM) | Hecho, determinista |
| Grabaciones reales (asciinema v3, 200×50 y 80×24) | vim editando, htop 60 s, tmux con 4 paneles, `cat` de un log de 100 MB, `ls --color` en un directorio grande, `npm install` con barras de progreso, `less`/`man`, vim con texto CJK, **sesión de un agente de IA en modo TUI** (redibujado intenso) | S1.1 |

Las grabaciones se hacen **dentro de un contenedor desechable con datos sintéticos**, para que ningún `.cast` contenga rutas, hosts ni datos personales. Se guardan en `spikes/s1-terminal/corpus/casts/` solo si pesan menos de 5 MB; las grandes se regeneran con un script.

## 6. Métricas y puerta

| Métrica | Herramienta | Umbral para aceptar |
|---|---|---|
| Throughput de parseo | `termbench run` | ≥ 50 MiB/s en un Android de gama media con todo el corpus |
| `cat` de 100 MB con la UI | Harness de render | Ningún frame congelado > 100 ms; la UI sigue respondiendo |
| Latencia del eco en el núcleo | `termbench echo` | p99 < 1 ms en todas las plataformas |
| Latencia del eco de una tecla, desde los datos recibidos hasta el pintado | Harness, carga de tecleo con bytes sueltos (`FrameTiming` + marca de tiempo del núcleo) | p95 < 1 refresco + 4 ms a 200×50 (≈ 21 ms a 60 Hz, ≈ 12 ms a 120 Hz) |
| Flujo continuo (salida masiva) | Harness, cargas del corpus al máximo ritmo | ≥ 55 fps y construcción + raster p95 < 1 refresco |
| Corrección | `vttest` (pantallas 1–3 y 8), vim, tmux, htop, mc, less, corpus `unicode` | Sin errores visibles; diferencias documentadas |
| IME | Japonés, chino pinyin, coreano; Gboard y teclado de iOS | Composición visible en el cursor y texto confirmado correcto |
| **Memoria de scrollback** | `termbench mem` | **< 300 MB con 10 pestañas × 10.000 líneas × 120 columnas.** Un valor por defecto de 40.000 líneas solo si hay scrollback compacto |
| Accesibilidad | VoiceOver y TalkBack | Se puede leer la pantalla visible fila a fila (viable, no perfecto) |

Gana el motor que pasa la puerta. Si pasan los dos, se puntúa:

| Criterio | Peso |
|---|---|
| Memoria de scrollback | 25 % |
| Trabajo propio pendiente (codificadores de entrada, búsqueda, scrollback compacto) | 25 % |
| Estabilidad de la API y riesgo de mantenimiento | 20 % |
| Complejidad de build (Zig, cross-compilación a 5 plataformas, tamaño del binario) | 15 % |
| Rendimiento medido | 15 % |

## 7. Plataformas y dispositivos

| Plataforma | Dispositivo mínimo | Notas |
|---|---|---|
| macOS | Mac con Apple Silicon (máquina de desarrollo) | También Intel si hay acceso |
| Windows | Windows 11 x64 (VM o equipo) | ConPTY para la terminal local; teclado ES e IME de Microsoft |
| Linux | Ubuntu 24.04, X11 y Wayland | IBus/Fcitx5 para el IME |
| Android | **Gama media** (por ejemplo, Pixel 6a o Galaxy A5x) y uno de gama baja | `termbench` cruzado a `aarch64-linux-android` y ejecutado por `adb` |
| iOS | iPhone 12 o posterior, y un iPad con teclado | `termbench` como prueba dentro del harness (iOS no permite ejecutables sueltos) |

## 8. Tareas

| ID | Tarea | Días | Estado |
|---|---|---|---|
| S1.0 | Trait `TermEngine`, formato de frames v1, backend `alacritty_terminal`, `termbench` | 1 | **Hecho** |
| S1.1 | Grabar el corpus real en un contenedor y añadir el script de regeneración | 1 | Pendiente |
| S1.2 | `termbench` con alacritty en las 5 plataformas; resultados en `spikes/s1-terminal/results/<plataforma>.jsonl` | 1–2 | Pendiente |
| S1.3 | Backend `libghostty-vt`: build con **Zig 0.16.0 exacto** (`brew install zig@0.16`, disponible como `zig`) para los 5 destinos; bindings de `vt.h` en un crate `-sys` aislado (la única excepción a `unsafe_code = "forbid"`); implementar `TermEngine` | 3–4 | Pendiente |
| S1.4 | Harness de render: app Flutter + `flutter_rust_bridge` 2.13.0, decodificador Dart del frame v1 con pruebas cruzadas contra frames de ejemplo generados en Rust, y `CustomPainter` con un `Picture` en caché por fila (solo se regraban las filas que cambian) | 3–4 | **En curso:** v1 (async) y v2 (sync) medidos en macOS (§10.2) |
| S1.4b | Carga de tecleo (bytes sueltos a intervalos aleatorios) para medir el eco | 0,5 | **Hecho** en macOS: pasa la puerta (§10.2) |
| S1.4c | Render con atlas de glifos (`drawRawAtlas`) para ASCII/latino, con párrafo de respaldo para CJK y emoji; comparar el coste de grabación con v2 | 1–2 | Pendiente |
| S1.5 | Entrada: codificación de teclas (xterm y protocolo kitty), ratón (SGR 1006), bracketed paste; IME con `TextInputClient` y región de composición en el cursor; barra de teclas en móvil | 2–3 | Pendiente |
| S1.6 | Corrección: vttest, apps reales y corpus unicode en ambos motores; capturas comparadas | 1–2 | Pendiente |
| S1.7 | Si se confirma H2: prototipo de scrollback compacto (texto UTF-8 con tramos de estilo para las líneas que salen de la pantalla) y medición | 2 | Condicional |
| S1.8 | Informe `S1-terminal-resultados.md` y ADR-002 aceptado | 1 | Pendiente |

**Requisitos previos:** Rust 1.99.0 (fijado en `rust-toolchain.toml`), Flutter 3.47.6 (fijado en `.fvmrc`; se usa con `fvm flutter …`, sin tocar el Flutter global), Zig 0.16.0 (`zig@0.16` de Homebrew), `flutter_rust_bridge_codegen` 2.13.0, Android NDK y Xcode 27.

## 9. Riesgos del spike

| Riesgo | Mitigación |
|---|---|
| La API de `libghostty-vt` cambia durante el spike | Fijar el commit exacto de Ghostty; adaptador fino; medir el coste de seguirla |
| Cross-compilar Zig a Android o iOS da problemas | Usar el xcframework y el job de Android que ya tiene Ghostty; si falla en móvil, documentarlo como criterio |
| El render en Flutter no llega a 16 ms en gama media | Probar a pintar en un `Picture` por fila y, como último recurso, un atlas de glifos con `drawRawAtlas` |
| IME coreano o el teclado de Android se comportan mal (problemas conocidos en otros terminales Flutter) | Reservar S1.5 completo; probar en dispositivos reales, no en emulador |
| Las grabaciones filtran datos | Solo contenedor desechable; revisión antes de commitear |

## 10. Resultados preliminares (S1.0, smoke test)

2026-10-08 · Mac con Apple Silicon · build de release · `alacritty_terminal` 0.26.0 · 200×50 · corpus sintético de 4 MiB por archivo, troceado en bloques de 4 KiB y con un frame cada 64 KiB. **Son orientativos, no la medición del spike.**

| Entrada | Parseo | Con frames | Frame medio | `encode_damage` p95 |
|---|---|---|---|---|
| ascii | 98 MiB/s | 102 MiB/s | 7,3 KB | 63 µs |
| sgr-log | 134 MiB/s | 149 MiB/s | 11,9 KB | 70 µs |
| unicode | 108 MiB/s | 118 MiB/s | 26,8 KB | 82 µs |
| fullscreen | 217 MiB/s | 190 MiB/s | 7,5 KB | 52 µs |
| scroll-region | 190 MiB/s | 166 MiB/s | 8,8 KB | 57 µs |

- **Eco** (una tecla, un frame): p50 0,9 µs, p99 1,5 µs. Despreciable frente a la red y el pintado.
- **Memoria:** 2 pestañas × 5.000 líneas × 200 columnas ocupan ~52 MB, es decir, **~5,3 KB por línea (~26 B por celda)**. Extrapolado, 10 pestañas × 40.000 líneas × 200 columnas serían ~2 GB. **Esto refuerza H2.** El objetivo de memoria original del ADR-002 era inalcanzable con este motor sin scrollback compacto, y la puerta queda redefinida en §6.
- **Frames:** un frame completo de 200×50 pesa 7–27 KB; a 60 Hz son menos de 2 MB/s por el bridge, sin problema.
- **Móvil:** `openward-term` con `alacritty_terminal` compila (`cargo check`) para `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-linux-android` y `x86_64-linux-android`. Falta ejecutarlo en dispositivo (S1.2). El CI lo comprueba en cada cambio.

### 10.2 Banco de render en Flutter (S1.4)

2026-10-13 · Apple M5 · pantalla a 60 Hz · macOS release, Impeller (Metal) · Flutter 3.47.6 · `alacritty_terminal` · 200×50 · scrollback de 10.000 líneas · se descarta el primer medio segundo (calentamiento de shaders). Datos en `spikes/s1-terminal/results/macos-render-v*.jsonl`.

| Carga (ritmo) | fps | Latencia p50 v1 → v2 | Latencia p95 v2 | Construcción p95 v2 | Raster p95 v2 | Grabación de filas p95 v2 |
|---|---|---|---|---|---|---|
| fullscreen (máx.) | 60 | 33,3 → 21,5 ms | 21,7 ms | 5,3 ms | 0,6 ms | 4,9 ms |
| sgr-log (máx.) | 60 | 33,3 → 22,9 ms | 23,6 ms | 7,1 ms | 0,8 ms | 6,8 ms |
| unicode (máx.) | 59 | 33,4 → 27,8 ms | 31,9 ms | 16,3 ms | 1,4 ms | 15,4 ms |
| scroll-region (máx.) | 60 | 33,3 → 20,7 ms | 21,0 ms | 4,5 ms | 0,6 ms | 4,3 ms |
| ascii (máx.) | 60 | 33,3 → 19,6 ms | 20,3 ms | 3,8 ms | 0,6 ms | 3,5 ms |
| fullscreen (2 MiB/s) | 60 | 32,4 → 20,3 ms | 21,1 ms | 4,9 ms | 0,7 ms | 4,6 ms |
| sgr-log (1 MiB/s) | 60 | 31,4 → 19,9 ms | 21,6 ms | 5,8 ms | 0,8 ms | 5,6 ms |

v1 pedía el frame a Rust de forma asíncrona en cada tick; v2 lo pide de forma síncrona dentro del tick. Codificar cuesta 50–100 µs en p95.

**Conclusiones:**

1. **La vía asíncrona añade un refresco entero** (~33 ms frente a ~20 ms): el frame llega cuando el refresco actual ya ha empezado. **Decisión para el producto:** codificar en el hilo de UI dentro del tick de vsync. Cuesta decenas de µs y elimina un refresco de latencia.
2. **Pintar es barato:** el raster p95 está entre 0,6 y 1,4 ms y la app va a 60 fps estables, sin frames congelados tras el calentamiento, incluso con salida masiva.
3. **El cuello de botella es grabar las filas en Dart** con un `Paragraph` por tramo de estilo: 3,5–15 ms en p95, y llega casi al presupuesto entero del refresco con CJK y emoji. En un Android de gama media puede ser varias veces más lento. **Siguiente iteración (S1.4c):** atlas de glifos con `drawRawAtlas`, que evita dar forma al texto en cada frame, y párrafo solo para lo que el atlas no cubra.
4. **La métrica de latencia original estaba mal planteada para flujos continuos.** El byte más antiguo de cada frame espera por construcción casi un refresco entero, así que "p95 < 16 ms" era imposible a 60 Hz. La latencia que percibe el usuario es la del eco de una tecla aislada: la puerta pasa a "p95 < 1 refresco + 4 ms" con una carga de tecleo (S1.4b). Los flujos continuos se evalúan por fps y por tiempo de frame (§6).
5. **El eco de tecla pasa la puerta en macOS (S1.4b).** La carga `typing` envía bytes sueltos cada 60–180 ms sobre una pantalla ya llena, como el eco del shell al escribir. Dos ejecuciones de 20 s (334 pulsaciones), vía síncrona, pantalla a 60 Hz:

   | Ejecución | Pulsaciones | p50 | p95 | p99 | Máx. | Puerta (1 refresco + 4 ms) |
   |---|---|---|---|---|---|---|
   | 1 | 166 | 8,8 ms | 17,4 ms | 18,9 ms | 40,3 ms | 20,7 ms → **pasa** |
   | 2 | 168 | 9,2 ms | 17,1 ms | 17,9 ms | 44,2 ms | 20,7 ms → **pasa** |

   El p50 (~9 ms) es medio refresco de espera más ~1 ms de proceso, el mínimo posible a 60 Hz. Grabar la única fila que cambia cuesta < 1 ms. Hay picos aislados de ~40 ms (menos del 1 % de las pulsaciones) que conviene investigar en Android. El raster p95 sube a 3,7–4,8 ms con este ritmo intermitente, probablemente porque la GPU baja de frecuencia entre pulsaciones. En una pantalla de 120 Hz o más la puerta se estrecha (~12 ms) y habrá que repetir la medición.
6. **Toolchain dentro de la build de Flutter:** cargokit solo aceptaba `stable`, `beta` o `nightly`, así que compilaba con el `stable` de la máquina y no con la versión fijada. Se ha parcheado la copia de cargokit del harness (`build_tool/lib/src/options.dart`) para aceptar una versión exacta, y `rust/cargokit.yaml` fija la 1.99.0. Habrá que proponer el cambio upstream o mantener el parche en la app real.

## 11. Cómo reproducir

```bash
cd spikes/s1-terminal/termbench
cargo build --release
./target/release/termbench gen ../corpus/synthetic --mb 16
./target/release/termbench run ../corpus/synthetic/*.txt --json > ../results/macos.jsonl
./target/release/termbench echo --json >> ../results/macos.jsonl
./target/release/termbench mem --tabs 10 --scrollback 10000 --cols 120 --json >> ../results/macos.jsonl
```
