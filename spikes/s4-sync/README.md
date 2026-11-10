# S4 · La sync, primera parte: el sobre v1 y el merge

Plan, resultados y decisión: [docs/spikes/S4-sync.md](../../docs/spikes/S4-sync.md).

| Ruta | Contenido |
|---|---|
| `syncsim/src/envelope.rs` | El sobre `v: 1`: CBOR canónico, revisión por contenido, AAD con la cabecera y firma del dispositivo |
| `syncsim/src/hlc.rs` | El reloj lógico híbrido |
| `syncsim/src/fields.rs` | El cuerpo de un ítem como rutas y valores, para un merge que no necesita conocer su tipo |
| `syncsim/src/dag.rs` | El DAG de revisiones y los dos merges: por relojes de campo (el propuesto) y a tres bandas (el de ADR-005) |
| `syncsim/src/sim.rs` | Dispositivos en memoria con registros que solo crecen, poda con instantánea y el oráculo que dice qué escrituras deben quedar |
| `syncsim/tests/convergence.rs` | Convergencia con `proptest` y los casos con nombre |
| `results/` | Las medidas en JSON, una por sistema |

```bash
cd syncsim && cargo test                       # sobre, reloj y convergencia
cd syncsim && cargo run --release              # tamaños, desbloqueo y 10.000 escrituras
cd syncsim && cargo run --release -- unlock
cd syncsim && PROPTEST_CASES=20000 cargo test --test convergence
```
