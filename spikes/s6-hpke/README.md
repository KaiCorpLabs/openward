# S6 · El envoltorio de claves (HPKE con X-Wing o X25519)

Plan, resultados y decisión: [docs/spikes/S6-hpke.md](../../docs/spikes/S6-hpke.md).

| Ruta | Contenido |
|---|---|
| `hpkebench/` | CLI que compara `hpke-rs` 0.8.0 con libcrux, `hpke-rs` con RustCrypto y `hpke` 0.15.1 (rozbb), con DHKEM(X25519) y X-Wing: vectores (`vectors`), interoperabilidad (`interop`) y tiempos y tamaños (`bench`). Falla si falla una comprobación |
| `vectors/` | Los vectores publicados, solo de las suites que usaría el vault (modo base, HKDF-SHA256, ChaCha20-Poly1305) |
| `results/` | Las medidas en JSON, una por sistema |

```bash
cd hpkebench && cargo run --release                      # todo
cd hpkebench && cargo run --release -- vectors
cd hpkebench && cargo run --release -- bench --iters 5000 --json ../results/macos-aarch64.json
```

De dónde salen los vectores:

| Archivo | Origen |
|---|---|
| `hpke-x25519-rfc9180.json` | RFC 9180, apéndice A.2 (DHKEM(X25519), HKDF-SHA256, ChaCha20-Poly1305, modo base), del `origrfc-5f503c5.json` de `rust-hpke` v0.15.1 |
| `hpke-xwing-pq.json` | `draft-ietf-hpke-pq`: X-Wing (`0x647a`) con la misma suite, del `pq-6433c8f.json` de `rust-hpke` v0.15.1 |
| `xwing-draft11.json` | `draft-connolly-cfrg-xwing-kem-11`, `spec/test-vectors.json` del repositorio del borrador en el commit `984c2f7` (2026-09-23) |
