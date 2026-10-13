# S1 · Motor de terminal

Plan, hipótesis, puerta y datos: [docs/spikes/S1-terminal.md](../../docs/spikes/S1-terminal.md). Resultados y decisión (gana `libghostty-vt`): [S1-terminal-resultados.md](../../docs/spikes/S1-terminal-resultados.md). El motor ya vive en el núcleo: `core/crates/openward-ghostty`.

| Ruta | Contenido |
|---|---|
| `termbench/` | CLI que mide y compara los motores detrás de `TermEngine`: `gen`, `run`, `replay`, `echo`, `mem`, `conform`, `reports` |
| `corpus/synthetic/` | Corpus generado con `termbench gen` (no se commitea) |
| `corpus/` | `record.sh` graba el corpus real en un contenedor sin red (`make corpus`); `check-casts.sh` busca fugas de datos del host |
| `corpus/casts/` | Grabaciones pequeñas (< 5 MB), commiteadas |
| `corpus/casts-big/` | Grabaciones grandes, regeneradas, nunca commiteadas |
| `corpus/conformance/` | Referencias de tmux para vttest, anchos Unicode y apps reales (`make conformance-record`; se comparan con `make conformance`) |
| `results/` | Resultados en JSON lines por plataforma y paso; `results/conformance/` tiene los informes de corrección |
| `s1-corpus/` | Cargas sintéticas deterministas, compartidas por `termbench` y el harness |
| `render_harness/` | App Flutter + `flutter_rust_bridge`: banco de render (S1.4, `S1_AUTORUN`, `S1_ENGINE`), shell y registro de teclas (S1.5) y capturas comparables (S1.6). Ver su README |

```bash
cd termbench && cargo build --release
./target/release/termbench --help
```
