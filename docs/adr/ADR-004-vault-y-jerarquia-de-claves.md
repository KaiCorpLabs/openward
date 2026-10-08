# ADR-004 — Vault local-first, cifrado por ítem y recuperación primero

- **Estado:** propuesto.
- **Fecha:** 2026-10-08.
- **Alcance:** almacenamiento local, jerarquía de claves, desbloqueo, recuperación y vaults de equipo.

## Contexto

Tres fallos habituales en gestores de credenciales con sync propietaria son perder el vault al reiniciar la contraseña de cifrado, no poder exportar y depender de una única nube. OpenWard tiene que evitarlos y usar el mismo formato cifrado en local, en el almacenamiento del usuario y en nuestro servidor. Además, los blobs sincronizados pasarán años en servidores ajenos.

## Decisión

- **Cifrado por ítem:** XChaCha20-Poly1305 con AAD ligada a `vault_id‖item_id‖rev‖key_gen`. Nombres, direcciones, tipo y marcas de tiempo van dentro del texto cifrado. SQLite guarda los sobres cifrados, así que **no se usa SQLCipher**: el formato local y el de sync son el mismo.
- **Jerarquía de claves:**
  - contraseña → Argon2id → KEK → clave de cuenta (Ed25519 para firmar y KEM para recibir claves);
  - clave de cuenta → certificados de dispositivo;
  - claves de vault por generación, envueltas con HPKE.
- **KEM híbrido poscuántico (X-Wing: X25519 + ML-KEM-768)** para envolver claves de vault. Estado a 2026-10-08:
  - **`hpke-rs`** 0.8.0: mantenido dentro de libcrux, con backend **verificado formalmente**, X-Wing draft-06 y licencia **MPL-2.0**.
  - **`hpke`** (rozbb) 0.14.1: MIT/Apache, X-Wing draft-10 por defecto, nunca auditado.
  - **`ml-kem`** 0.3.2 y **`x-wing`** 0.1.1 (RustCrypto): sin auditar.

  **Preferencia: `hpke-rs` con backend libcrux.** X-Wing es todavía un *draft* del IETF, así que `kem_id` registra la versión exacta del draft y hay un plan de migración a la RFC final. Si ninguna opción supera la revisión, se usa DHKEM(X25519) con `kem_id` versionado.
- **Desbloqueo:** contraseña, biometría (una clave aleatoria guardada en Keychain, Keystore o Windows Hello) o PIN con límite de intentos en móvil.
- **El kit de recuperación es obligatorio** al dar de alta. Cambiar la contraseña exige la actual, el kit u otro dispositivo aprobado. **Nunca se borra el vault sin avisar.**
- **Vaults de equipo con manifiesto firmado** (cadena de entradas `add_member`, `remove_member`, `rotate`, `set_role` firmadas por un administrador; el génesis lo firma el creador). La baja de un miembro rota la clave y los ítems antiguos se vuelven a cifrar de forma perezosa. La recuperación de cuenta por la organización es una política opcional y visible.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| SQLCipher de base completa (como Arveil) | Oculta también los metadatos locales | No sirve para sync; tendríamos dos formatos |
| MLS para los vaults de equipo | Ya lo conocemos (Arveil) | Optimiza el secreto hacia delante en mensajería; un vault necesita que los miembros nuevos lean el historial |
| El servidor guarda las claves (como una nube "normal") | Recuperación trivial; administración fácil | Rompe la propuesta zero-knowledge |
| Solo X25519 | Más simple y probado | Riesgo de "guarda ahora, descifra después" en datos de larga vida |

## Consecuencias

- Un usuario que pierda la contraseña, el kit y todos sus dispositivos pierde el vault. Es lo honesto en zero-knowledge, y la UI lo explica en el alta.
- La baja de un miembro no borra lo que ya vio: la app lo dice y recomienda rotar credenciales o usar certificados de corta duración.
- La confianza en la clave pública de un miembro nuevo depende de verificar huellas o de una atestación SSO del servidor. Queda documentado en `THREAT_MODEL.md`.

## Validación y revisión

Vectores de prueba propios, pruebas de rotación y recuperación, y revisión criptográfica externa antes de lanzar OpenWard Cloud. Reabrir si la experiencia de alta de miembros en equipos piloto exige atestación del servidor por defecto.
