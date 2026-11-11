# openward-ghostty

`libghostty-vt` detrás de `openward_term::TermEngine`: el motor de terminal de OpenWard, elegido en el [ADR-002](../../../docs/adr/ADR-002-motor-de-terminal.md) tras el [spike S1](../../../docs/spikes/S1-terminal-resultados.md). Es el único crate del núcleo con `unsafe` (FFI), como excepción auditada (ARCHITECTURE §3.2).

## Compilar

Requisitos: Zig 0.16.0 exacto (`brew install zig@0.16`) y git. Para Android, además, el NDK (`ANDROID_NDK_HOME`).

```bash
./build-libghostty.sh                          # host (p. ej. aarch64-macos)
ANDROID_NDK_HOME=… ./build-libghostty.sh aarch64-linux-android
cargo test
```

El script clona Ghostty en la caché del usuario (`~/Library/Caches/openward/ghostty` en macOS), hace checkout del commit de [`GHOSTTY_COMMIT`](GHOSTTY_COMMIT) y deja la librería en `…/build/<commit>/<destino>/`, donde la busca `build.rs`. `GHOSTTY_VT_DIR` permite apuntar a otro directorio.

## Entrada (S1.5)

`src/engine/input.rs` añade al motor la codificación de teclas, ratón, pegado y foco con los codificadores de `libghostty-vt`, sincronizados con los modos del terminal antes de cada evento (`encode_key`, `encode_text`, `encode_mouse`, `wheel`, `encode_paste`, `encode_focus`, `input_modes`). Las teclas llegan como uso HID USB, el mismo que da Flutter en `PhysicalKeyboardKey.usbHidUsage`.

## Respuestas y ajustes del adaptador (S1.6)

- **Respuestas a consultas:** el motor responde como un terminal completo, mediante opciones de libghostty-vt: XTVERSION, tamaño (XTWINOPS), esquema de color (DSR 996), colores por defecto (OSC 10/11) y nombre de terminfo (XTGETTCAP).
- **Ajustes del adaptador**, con una prueba cada uno:
  - las celdas borradas con color de fondo (BCE) conservan ese color;
  - el tamaño se relee tras cada `feed`, por si el programa cambia a 132 columnas;
  - DEL (0x7F) se filtra antes de llegar a la librería, que lo imprimiría.

## Enlace en Apple

Zig mete su `compiler_rt` en la librería estática y, enlazada con `-force_load` (como hace Xcode con los plugins de Flutter), choca con los `compiler_builtins` de Rust. En destinos Apple, `build.rs` pre-enlaza el archivo con `ld -r` en un único objeto que solo exporta `_ghostty_*`; el resto queda interno.

## Bindings

`src/sys.rs` se genera con `bindgen` (crate `bindgen-gen/`) y se commitea, para que la build normal no necesite libclang. Se regenera al cambiar `GHOSTTY_COMMIT`:

```bash
./build-libghostty.sh --bindings
```

## Licencias

`src/sys.rs` deriva de las cabeceras de `libghostty-vt` (Ghostty, © Mitchell Hashimoto y colaboradores de Ghostty, [licencia MIT](https://github.com/ghostty-org/ghostty/blob/main/LICENSE)). La librería se enlaza de forma estática y también es MIT. El resto del crate tiene todos los derechos reservados, como el repositorio ([LICENSE](../../../LICENSE)).
