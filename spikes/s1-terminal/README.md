# S1 · Motor de terminal

Plan completo, hipótesis, puerta y resultados preliminares: [docs/spikes/S1-terminal.md](../../docs/spikes/S1-terminal.md).

| Ruta | Contenido |
|---|---|
| `termbench/` | CLI que mide los motores detrás de `TermEngine`: `gen`, `run`, `replay`, `echo`, `mem` |
| `corpus/synthetic/` | Corpus generado con `termbench gen` (no se commitea) |
| `corpus/casts/` | Grabaciones asciinema pequeñas, hechas en contenedores con datos sintéticos |
| `results/` | Resultados por plataforma en JSON lines (`<plataforma>.jsonl`) |
| `render_harness/` | App Flutter de medición del render (tarea S1.4, pendiente) |

```bash
cd termbench && cargo build --release
./target/release/termbench --help
```
