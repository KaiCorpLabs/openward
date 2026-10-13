# S1 · Motor de terminal

Plan completo, hipótesis, puerta y resultados preliminares: [docs/spikes/S1-terminal.md](../../docs/spikes/S1-terminal.md).

| Ruta | Contenido |
|---|---|
| `termbench/` | CLI que mide los motores detrás de `TermEngine`: `gen`, `run`, `replay`, `echo`, `mem` |
| `corpus/synthetic/` | Corpus generado con `termbench gen` (no se commitea) |
| `corpus/` | `record.sh` graba el corpus real en un contenedor sin red (`make corpus`); `check-casts.sh` busca fugas de datos del host |
| `corpus/casts/` | Grabaciones pequeñas (< 5 MB), commiteadas |
| `corpus/casts-big/` | Grabaciones grandes, regeneradas, nunca commiteadas |
| `ghostty-engine/` | Motor `libghostty-vt` (candidato B) |
| `results/` | Resultados por plataforma en JSON lines (`<plataforma>.jsonl`) |
| `s1-corpus/` | Cargas sintéticas deterministas, compartidas por `termbench` y el harness |
| `render_harness/` | App Flutter + `flutter_rust_bridge` que mide el render (S1.4). `fvm flutter build macos --release --dart-define=S1_AUTORUN=fullscreen:0:256` y ejecutar el binario: imprime una línea `S1RESULT {json}` por prueba |

```bash
cd termbench && cargo build --release
./target/release/termbench --help
```
