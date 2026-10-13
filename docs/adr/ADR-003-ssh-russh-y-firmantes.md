# ADR-003 — SSH con `russh` y firmantes intercambiables

- **Estado:** **aceptado para escritorio** (2026-10-13), con los números del [spike S2](../spikes/S2-ssh.md#9-resultados-s26). Los firmantes de plataforma (S3) y la ejecución en móvil siguen pendientes.
- **Fecha:** 2026-10-08 (propuesto); 2026-10-13 (escritorio aceptado).
- **Alcance:** transporte y autenticación SSH, SFTP y origen de las firmas.

## Contexto

Necesitamos un cliente SSH embebible en Rust que funcione en las 5 plataformas, con agent forwarding, túneles, saltos, certificados y, después, llaves hardware. Las claves pueden vivir en sitios muy distintos: el vault, un agente externo, Secure Enclave, Android Keystore, TPM, una llave FIDO2 o un certificado de corta duración emitido por Vault o step-ca. La UI no debe saber de dónde viene cada firma.

## Decisión

- **`russh`** como cliente SSH y **`russh-sftp`** para SFTP. **`ssh-key`** (RustCrypto) para parsear claves y certificados OpenSSH.
- Trait **`Signer`** (`public_key()`, `algorithms()`, `async sign(data)`) con estas implementaciones: software (vault), agente externo, Secure Enclave, Android Keystore, TPM, FIDO2 y un envoltorio de certificado. En Apple y Windows se llama a las APIs nativas desde Rust; en Android se hace una devolución de llamada a Kotlin a través del bridge.
- **El transporte es un stream genérico:** TCP directo, proxy HTTP o SOCKS5, ProxyCommand (escritorio) o un canal `direct-tcpip` de otra sesión (cadenas de saltos). Así todas las combinaciones se componen.
- **Known hosts** y su política viven en el núcleo, no en la UI.

**Lo que ya está verificado (2026-10-08, `russh` 0.64.1, Apache-2.0, muy activo):**

- **Kex poscuántico:** `mlkem768x25519-sha256` implementado y preferido por defecto; `sntrup761` no está.
- **Certificados de cliente:** con clave propia o con firmante externo.
- **Trait `auth::Signer`** (`auth_sign`), que podemos implementar para Secure Enclave, Keystore o una devolución de llamada.
- **Agent forwarding.**
- **Forwarding:** local (`direct-tcpip`), remoto (`tcpip_forward`) y de sockets Unix.
- **RSA:** `rsa-sha2-256/512`.
- **Otros:** Terrapin strict-kex, `hostkeys-prove`, formato PPK, keyboard-interactive y GSSAPI. Backend criptográfico `aws-lc-rs` (por defecto) o `ring`.

**Lo que tenemos que construir o validar nosotros:**

- **Forwarding dinámico (SOCKS):** no viene incluido; se implementa un servidor SOCKS5 local sobre `direct-tcpip`.
- **FIDO2/`sk-*`:** `russh` acepta la firma por un `Signer` externo o por un agente (PR #701, v0.61.1). Pero `ssh-key` solo verifica `sk`, no firma, así que la parte CTAP2 la ponemos nosotros (`libfido2` o `ctap-hid-fido2` en escritorio). [#219](https://github.com/Eugeny/russh/issues/219)
- **Móvil:** el CI de `russh` no prueba iOS ni Android (solo `wasm32-wasip1`). Nuestro CI compilará y ejecutará en ambos, y elegiremos entre `aws-lc-rs` y `ring` para móvil en el spike.
- **Aviso RUSTSEC-2023-0071 (Marvin) en `rsa`:** sin versión corregida. Afecta a las operaciones con clave privada RSA, que en un cliente son solo la firma al autenticarse con una clave RSA propia; la verificación de claves de host usa la pública y no se ve afectada. Recuperar la clave exige muchísimas firmas cronometradas, y aquí hay una por inicio de sesión. Queda ignorado en `cargo-deny` con esta justificación; la app recomienda Ed25519 al generar claves y se revisa cuando `rsa` publique una versión de tiempo constante.
- **`ssh-key` 0.7 sigue en RC** (`0.7.0-rc.11`) y `russh` la fija con `=`. Habrá cambios al publicarse la 0.7.0.

**Puerta del spike S2:** interoperabilidad con OpenSSH 8.x–10.x, Dropbear, Windows OpenSSH y Tailscale SSH (autenticación, certificados, L/R/D, saltos anidados, 2FA y kex poscuántico negociado), compilando y ejecutando en iOS y Android.

**Resultado de S2 en escritorio (2026-10-13):**
- **Matriz:** 83 de 83 pruebas en verde con OpenSSH 8.9, 9.2 y 10.0 y Dropbear 2025.88. Cubre autenticación (incluidos 2FA y certificados de usuario y de host), agente y su reenvío, L/R/D, saltos dobles, ProxyCommand y keepalive.
- **Kex poscuántico** negociado con OpenSSH 10.0 y con Dropbear.
- **Rendimiento:** 266–386 MiB/s por canal, a la par que OpenSSH.
- **Terminal completo por SSH:** eco p95 de 19,1 ms, dentro de la puerta de S1.
- **Builds:** compila para iOS y enlaza para Android.
- **Pendiente:**
  - Windows OpenSSH y Tailscale SSH, a mano antes de la v0.1;
  - ejecución en móvil (fase 2).
- **Hueco encontrado:** con OpenSSH 9.0–9.8 no hay kex poscuántico, porque esos servidores ofrecen `sntrup761`, que `russh` no tiene.

**Puerta del spike S3:** firma con Secure Enclave (macOS) y Keystore (Android) a través del trait, sin exportar la clave.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| `libssh2` / `libssh` vía FFI | Madurez, uso masivo | C sin seguridad de memoria; agent forwarding y extensibilidad de firmantes limitados; builds móviles más incómodas |
| `ssh2-rs` (bindings de libssh2) | API conocida | Hereda los límites de libssh2 |
| Ejecutar el binario `ssh` de OpenSSH | Máxima compatibilidad | No existe en iOS ni Android; poco control para la UI, los firmantes y el SFTP integrado |
| `golang.org/x/crypto/ssh` vía gomobile | Muy maduro | Mete Go en el cliente; dos runtimes en móvil |

## Consecuencias

Dependemos de un proyecto open source con un mantenedor principal (unas 1.900 estrellas). Hay que presupuestar contribuciones upstream (firma `sk-*` en `ssh-key`, CI móvil, casos raros de servidores) y tener una matriz de interoperabilidad en CI. Las alertas de seguridad corregidas en la 0.64.0 y la 0.64.1 obligan a vigilar los avisos de seguridad (`cargo-audit`) y a actualizar con rapidez. Los firmantes de plataforma necesitan código `unsafe` o FFI aislado en crates aparte y revisado.

## Validación y revisión

Aceptado para escritorio con la matriz de S2 en verde, que corre en la CI de Linux en cada push contra servidores reales. La parte de firmantes se acepta con S3 funcionando en dos plataformas. Reabrir si `russh` deja de mantenerse más de 6 meses o si hay un fallo de seguridad sin corregir en el transporte.
