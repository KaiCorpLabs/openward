# Spike S6 — El envoltorio de claves: HPKE con X-Wing o con X25519

- **Estado:** cerrado (2026-11-09). Medido en macOS y en la CI de Linux y Windows. La decisión que propone está en el §7, aceptada con ADR-004 el 2026-11-10.
- **Fecha:** 2026-11-09.
- **Decide:** la parte del KEM de [ADR-004](../adr/ADR-004-vault-y-jerarquia-de-claves.md). Es D1 de la [v0.4](../plan/v0.4.md).
- **Código:** [`spikes/s6-hpke/`](../../spikes/s6-hpke/).

## 1. Pregunta

La v0.4 envuelve la clave de cada generación del vault con HPKE para la clave pública de la cuenta. Más adelante, la v0.6 envolverá con ella las claves para otros equipos y miembros. Esos sobres pasarán años en discos y servidores ajenos, y por eso ADR-004 quiere un KEM poscuántico: **X-Wing** (ML-KEM-768 y X25519).

¿Qué biblioteca de HPKE usamos: **`hpke-rs` con libcrux**, **`hpke` (rozbb)** o **`hpke-rs` con RustCrypto**? ¿Y X-Wing, que sigue siendo un borrador, ya sirve, o nos quedamos con **DHKEM(X25519)**?

## 2. Hipótesis

| # | Hipótesis | Cómo se refuta |
|---|---|---|
| H1 | Las bibliotecas implementan el mismo X-Wing en HPKE (código `0x647a` de `draft-ietf-hpke-pq`) y pasan sus vectores | Un vector que falle |
| H2 | El X-Wing del borrador 06, que es el que implementan, da lo mismo que el borrador 11, el último | Los vectores del borrador 11 contra su código |
| H3 | Lo que sella una, lo abre cualquier otra: la elección se puede deshacer sin volver a cifrar | Un par emisor y receptor que no se entienda |
| H4 | El tiempo no decide: envolver y desenvolver una clave cuesta menos de 1 ms en escritorio | Las medidas del banco |
| H5 | Todas compilan para iOS y Android | `cargo check` para los objetivos móviles |
| H6 | Sus licencias y avisos pasan el `deny.toml` del núcleo | `cargo deny` con esas reglas |

## 3. Alcance

**Dentro:** HPKE en modo base con HKDF-SHA256 y ChaCha20-Poly1305, que es la suite que usaría el vault, con los dos KEM. Los vectores publicados, la interoperabilidad, los tiempos, los tamaños, la compilación para móvil, las licencias, las auditorías y la verificación de cada candidata.

**Fuera:**
- los modos con PSK y autenticados: el vault no los usa;
- AES-GCM y los KDF de SHAKE;
- las curvas NIST;
- enlazar en un dispositivo, porque basta con compilar para el objetivo;
- `aws-lc-rs`: ya está en el núcleo y trae ML-KEM, pero no tiene HPKE ni X-Wing, y habría que escribir la combinación a mano.

## 4. Montaje

- **`spikes/s6-hpke/hpkebench`**, un CLI en Rust:
  - **`vectors`** pasa a cada candidata los vectores publicados:
    - el emisor, donde la biblioteca deja fijar la aleatoriedad: se le dan los bytes de `ikmE` y tiene que dar el mismo `enc` y los mismos mensajes;
    - el receptor, siempre: el par de claves a partir de `ikmR`, cada mensaje abierto en orden y los valores exportados.
  - **`interop`**: cada candidata sella para el par de claves de cada otra, y el receptor abre. Si se cambia un byte del texto cifrado, del `enc`, de `info` o del `aad`, no debe abrir.
  - **`bench`** mide crear un par de claves, derivarlo de una semilla, sellar una clave de 32 bytes y abrirla: mediana y p95 de 2000 a 5000 llamadas.
- **Vectores** (en `spikes/s6-hpke/vectors/`, solo las suites que usaría el vault):
  - RFC 9180, A.2: DHKEM(X25519), HKDF-SHA256, ChaCha20-Poly1305, con 257 mensajes y 3 exportaciones;
  - `draft-ietf-hpke-pq`: X-Wing con la misma suite, con 10 mensajes y 5 exportaciones. Es el archivo `pq-6433c8f.json` que publica `rust-hpke` v0.15.1;
  - el borrador 11 de X-Wing: 3 vectores del KEM solo, del repositorio del borrador (commit `984c2f7`, el del 23 de septiembre).
- **La CI** lo corre en los tres sistemas (job «Spike S6 HPKE»). Si un vector o una prueba de interoperabilidad falla, el job falla.

## 5. Las candidatas hoy

| | `hpke-rs` 0.8.0 + libcrux | `hpke` 0.15.1 (rozbb) | `hpke-rs` 0.8.0 + RustCrypto |
|---|---|---|---|
| X-Wing | `XWingDraft06`, código `0x647a` | `XWing`, código `0x647a`, sobre `x-wing` 0.1.1 (borrador 06) | El de `x-wing` 0.1.1, solo con la función `experimental` |
| ML-KEM y X25519 | libcrux: ML-KEM **verificado formalmente** con hax y F\*; X25519, ChaCha20-Poly1305 y SHA-2, de HACL\*, también verificados | RustCrypto (`ml-kem`, `x25519-dalek`), **sin auditar** | RustCrypto, sin auditar |
| La capa HPKE | Sin verificar. `libcrux-kem`, que une X-Wing, está «en preverificación» | Sin auditoría pagada. Cloudflare revisó la 0.8 por su cuenta | Sin verificar |
| Licencia | MPL-2.0 (`hpke-rs`) y Apache-2.0 (libcrux). El `deny.toml` ya admite MPL-2.0 con inventario | MIT o Apache-2.0 | MPL-2.0 |
| Crates nuevos para el núcleo | **25**: una segunda pila criptográfica | **7**: el núcleo ya tiene `ml-kem`, `sha3` y `hkdf` por `russh` | 33 |
| Avisos | `hax-lib-macros` usa `proc-macro-error2`, **sin mantener** ([RUSTSEC-2026-0173](https://rustsec.org/advisories/RUSTSEC-2026-0173)). Solo se usa al compilar | Ninguno | El mismo de libcrux |
| Claves privadas | Se borran de la memoria al soltarlas (`Zeroize`) | Igual | Igual |
| Última versión | 2026-10-07; el repositorio pasó a `celabshq/libcrux` | 2026-10-28 | 2026-10-07 |

**X-Wing sigue siendo un borrador.** Está en `draft-connolly-cfrg-xwing-kem-11` (2026-09-23), que ahora sigue el camino independiente del IETF y no el de CFRG. Su código para HPKE, `0x647a` (`MLKEM768-X25519`), lo registra `draft-ietf-hpke-pq-05`, un documento del grupo de trabajo de HPKE (2026-07-06). Ninguno es RFC todavía.

## 6. Resultados

**Vectores (H1, H2): pasan todos.**

| | X25519 · RFC 9180 | X-Wing · `draft-ietf-hpke-pq` | X-Wing solo · borrador 11 |
|---|---|---|---|
| `hpke-rs` + libcrux | Emisor y receptor | Emisor y receptor | `libcrux-kem`: claves, encapsular y desencapsular |
| `hpke` (rozbb) | Emisor y receptor (ver nota) | Emisor y receptor | `x-wing`: claves, encapsular y desencapsular |
| `hpke-rs` + RustCrypto | Solo receptor | Solo receptor | — |

- **El borrador 06 da lo mismo que el 11:** el código de las dos bibliotecas, escrito para el borrador 06, da los resultados del 11 byte a byte.
- **La nota de rozbb:** `hpke` guarda la clave privada X25519 con los bits que fija X25519 (*clamping*), como dice RFC 9180 §7.1.2. Los vectores la traen sin fijar. Es la misma clave, y el banco lo da por bueno.
- **El emisor de `hpke-rs` con RustCrypto** no se puede comprobar, porque su aleatoriedad no se deja fijar desde fuera.

**Interoperabilidad (H3): 18 de 18.** Con los dos KEM, cada una de las tres abre lo que sellan las otras dos, y ninguna abre un sobre con un byte cambiado.

**Tamaños:**

| bytes | Clave pública | Clave privada | `enc` | Clave de 32 B sellada |
|---|---|---|---|---|
| DHKEM(X25519) | 32 | 32 | 32 | 48 |
| X-Wing | 1216 | 32 (la semilla) | 1120 | 48 |

Con X-Wing, cada clave envuelta ocupa unos 1,2 KB en vez de 80 bytes. Es una vez por generación del vault y por equipo o miembro, así que no pesa.

**Tiempos (H4)**, en µs, mediana y p95 entre paréntesis. Mac: Apple M5, release, 5000 llamadas.

| | Sellar X25519 | Abrir X25519 | Sellar X-Wing | Abrir X-Wing | Par X-Wing |
|---|---|---|---|---|---|
| `hpke-rs` + libcrux | 89 (159) | 84 (156) | 93 (134) | **100** (136) | 65 (106) |
| `hpke` (rozbb) | 92 (153) | 61 (110) | 106 (150) | 219 (278) | 64 (91) |
| `hpke-rs` + RustCrypto | 63 (112) | 62 (103) | 102 (135) | 220 (271) | 56 (79) |

Linux, Windows y el macOS de la CI: en el §6.1.

- **Todo queda por debajo de 0,3 ms en el Mac** y de 0,4 ms en la CI. El desbloqueo tiene 300 ms para 10.000 ítems y abre una clave por generación, así que el tiempo no decide.
- **Entre ejecuciones, las medianas cambian hasta un 30 %.** Las diferencias pequeñas de la tabla no significan nada.
- **libcrux abre X-Wing en la mitad de tiempo** que las dos de RustCrypto, y su X25519 es algo más lento.

**Móvil (H5):** las tres pasan `cargo check` en release para `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-linux-android`, `x86_64-linux-android` y `armv7-linux-androideabi`. No se ha enlazado en un dispositivo.

**Licencias y avisos (H6):** pasan las licencias. Con libcrux sale un aviso: `proc-macro-error2` está sin mantener. No es una vulnerabilidad, y solo corre al compilar, como dependencia de las macros de hax.

### 6.1 En la CI

[Ejecución 42606374587](https://github.com/KaiCorpLabs/openward/actions/runs/42606374587), con 2000 llamadas. En los tres sistemas pasan las 32 comprobaciones (vectores e interoperabilidad). Tiempos en µs, mediana y p95 entre paréntesis:

| | Sellar X25519 | Abrir X25519 | Sellar X-Wing | Abrir X-Wing | Par X-Wing |
|---|---|---|---|---|---|
| **Linux x86_64** (`ubuntu-latest`) | | | | | |
| `hpke-rs` + libcrux | 95 (103) | 91 (98) | 114 (122) | **133** (141) | 68 (74) |
| `hpke` (rozbb) | 89 (97) | 71 (78) | 154 (163) | 331 (340) | 90 (97) |
| `hpke-rs` + RustCrypto | 73 (80) | 72 (79) | 155 (164) | 332 (345) | 89 (96) |
| **Windows x86_64** (`windows-latest`) | | | | | |
| `hpke-rs` + libcrux | 80 (98) | 76 (100) | 101 (177) | **121** (229) | 61 (72) |
| `hpke` (rozbb) | 78 (136) | 61 (102) | 153 (178) | 342 (380) | 98 (137) |
| `hpke-rs` + RustCrypto | 63 (76) | 62 (76) | 155 (236) | 344 (377) | 98 (115) |
| **macOS arm64** (`macos-latest`) | | | | | |
| `hpke-rs` + libcrux | 68 (81) | 62 (78) | 80 (101) | **89** (101) | 47 (61) |
| `hpke` (rozbb) | 55 (73) | 45 (58) | 80 (89) | 161 (197) | 46 (55) |
| `hpke-rs` + RustCrypto | 44 (56) | 44 (57) | 84 (95) | 168 (191) | 47 (56) |

Lo mismo que en el Mac: todo por debajo de 0,4 ms, y libcrux abre X-Wing entre 2 y 2,8 veces más rápido. Los JSON están en `spikes/s6-hpke/results/`.

## 7. Decisión que propone

- **X-Wing, ya.**
  - Pasa los vectores en las dos bibliotecas serias, y el borrador 06 da lo mismo que el 11.
  - El sobre guarda el KEM y su versión: `0x647a`, con la construcción del borrador 06 y HPKE según `draft-ietf-hpke-pq-05`. Si la RFC final cambia algo, se vuelve a envolver la clave de cada generación, que son unos pocos sobres. Los ítems no se tocan.
  - DHKEM(X25519) queda como alternativa decidida, sin cambiar nada más.
- **La suite:** modo base, HKDF-SHA256 y ChaCha20-Poly1305. Sin PSK ni modo autenticado, que X-Wing además no tiene: quién envolvió una clave lo dicen las firmas Ed25519 de los sobres (S4, ADR-005) y del manifiesto del equipo (ADR-004).
- **La biblioteca: `hpke-rs` 0.8.0 con libcrux**, como prefería ADR-004.
  - Sus primitivas son las únicas verificadas formalmente.
  - Abre X-Wing en la mitad de tiempo.
  - Deja fijar la aleatoriedad, así que el núcleo puede pasar los vectores del emisor en sus pruebas.
- **Con estas condiciones:**
  - versiones exactas (`=0.8.0`) y un inventario de los 25 crates en `deny.toml`;
  - RUSTSEC-2026-0173 ignorado en `deny.toml`, con su motivo (solo al compilar, dentro de hax), y revisado en cada actualización de libcrux;
  - `openward-crypto` trae como pruebas los tres archivos de vectores, y una de interoperabilidad con `hpke` (rozbb) como dependencia de desarrollo. Si cualquiera de las dos cambia lo que produce, salta;
  - las claves privadas y los secretos compartidos van en `Zeroizing` en nuestra frontera, porque `hpke-rs` los recibe como `Vec<u8>`.
- **La alternativa es `hpke` (rozbb).** Pone los mismos bytes en el disco (lo prueba H3), trae 7 crates nuevos en vez de 25 y tiene licencia permisiva. A cambio, no tiene verificación ni auditoría pagada. Se cambia a ella si libcrux da problemas de mantenimiento o de plataforma, sin volver a cifrar nada.
- **Descartadas:**
  - **`hpke-rs` con RustCrypto:** su X-Wing va detrás de `experimental`, no deja comprobar el emisor y no aporta nada sobre las otras dos;
  - **`aws-lc-rs`:** no tiene ni HPKE ni X-Wing, y no queremos escribir la combinación nosotros;
  - **solo X25519:** se queda como plan B.

## 8. Qué queda

- **Enlazar en un iPhone y un Android de verdad,** con la app de la fase 2. Hoy solo se ha compilado.
- **La revisión criptográfica externa** que ADR-004 pide antes de OpenWard Cloud (v0.6). Debe incluir nuestro uso de `hpke-rs`.
- **Seguir los dos borradores:** `draft-connolly-cfrg-xwing-kem` y `draft-ietf-hpke-pq`. Cuando haya RFC, comparar con los vectores finales y, si cambian, migrar con un `kem_id` nuevo.
