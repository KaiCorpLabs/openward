# ghostty-engine (spike S1.3)

`libghostty-vt` detrás de `openward_term::TermEngine`. Es el candidato B del [spike S1](../../../docs/spikes/S1-terminal.md). Es código de spike: solo pasará a `core/` si el ADR-002 acepta este motor.

## Compilar

Requisitos: Zig 0.16.0 exacto (`brew install zig@0.16`) y git. Para Android, además, el NDK (`ANDROID_NDK_HOME`).

```bash
./build-libghostty.sh                          # host (p. ej. aarch64-macos)
ANDROID_NDK_HOME=… ./build-libghostty.sh aarch64-linux-android
cargo test
```

El script clona Ghostty en la caché del usuario (`~/Library/Caches/openward/ghostty` en macOS), hace checkout del commit de [`GHOSTTY_COMMIT`](GHOSTTY_COMMIT) y deja la librería en `…/build/<commit>/<destino>/`, donde la busca `build.rs`. `GHOSTTY_VT_DIR` permite apuntar a otro directorio.

## Bindings

`src/sys.rs` se genera con `bindgen` (crate `bindgen-gen/`) y se commitea, para que la build normal no necesite libclang. Se regenera al cambiar `GHOSTTY_COMMIT`:

```bash
./build-libghostty.sh --bindings
```

## Licencias

`src/sys.rs` deriva de las cabeceras de `libghostty-vt` (Ghostty, © Mitchell Hashimoto y colaboradores de Ghostty, [licencia MIT](https://github.com/ghostty-org/ghostty/blob/main/LICENSE)). La librería se enlaza de forma estática y también es MIT. El resto del crate es Apache-2.0, como el repositorio.
