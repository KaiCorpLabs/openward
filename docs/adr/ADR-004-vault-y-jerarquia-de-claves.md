# ADR-004 — Vault local-first, cifrado por ítem y recuperación primero

- **Estado:** **aceptado** (2026-11-10). [S6](../spikes/S6-hpke.md) (2026-11-09) cerró el KEM y la biblioteca, y [D0-1](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0), cómo se envuelve el paquete de la clave de cuenta.
- **Fecha:** 2026-10-08.
- **Alcance:** almacenamiento local, jerarquía de claves, desbloqueo, recuperación y vaults de equipo.

## Contexto

Tres fallos habituales en gestores de credenciales con sync propietaria son perder el vault al reiniciar la contraseña de cifrado, no poder exportar y depender de una única nube. OpenWard tiene que evitarlos y usar el mismo formato cifrado en local, en el almacenamiento del usuario y en nuestro servidor. Además, los blobs sincronizados pasarán años en servidores ajenos.

## Decisión

- **Cifrado por ítem:** XChaCha20-Poly1305 con la cabecera del sobre como AAD (`v`, `vault`, `item`, `device`, `key_gen`, `parents`, en CBOR canónico), como propone [S4](../spikes/S4-sync.md#5-el-sobre-v1) (2026-11-09). La revisión no va en el AAD porque sale del propio sobre: es su SHA-256 sin la firma. Nombres, direcciones, tipo y marcas de tiempo van dentro del texto cifrado. SQLite guarda los sobres cifrados, así que **no se usa SQLCipher**: el formato local y el de sync son el mismo.
- **Jerarquía de claves:**
  - contraseña → Argon2id → KEK → clave de cuenta (Ed25519 para firmar y KEM para recibir claves);
  - clave de cuenta → certificados de dispositivo;
  - claves de vault por generación, envueltas con HPKE.
- **El paquete de la clave de cuenta**, lo que la v0.6 sube al servidor para dar de alta otros equipos, va envuelto con una clave que sale de la contraseña (Argon2id) **y** de un secreto de alta entropía del kit, combinados con HKDF ([D0-1](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0)). Quien tenga solo el paquete, el servidor incluido, no puede probar contraseñas. Dar de alta un equipo nuevo pide el kit o la aprobación de un equipo que ya está dentro. La KEK, que sale solo de la contraseña, no sale del equipo.
- **KEM híbrido poscuántico, X-Wing (X25519 + ML-KEM-768),** para envolver claves de vault, en HPKE con modo base, HKDF-SHA256 y ChaCha20-Poly1305, y con **`hpke-rs` 0.8.0 sobre libcrux**. Lo midió [S6](../spikes/S6-hpke.md) (2026-11-09):
  - las tres candidatas pasan los vectores de RFC 9180, de `draft-ietf-hpke-pq` y del borrador 11 de X-Wing, y cada una abre lo que sellan las otras;
  - libcrux es la única con las primitivas **verificadas formalmente**: ML-KEM con hax y F\*, y X25519, ChaCha20-Poly1305 y SHA-2 de HACL\*. La capa HPKE no lo está;
  - trae 25 crates nuevos y un aviso de mantenimiento ([RUSTSEC-2026-0173](https://rustsec.org/advisories/RUSTSEC-2026-0173)) en una macro que solo corre al compilar;
  - **`hpke` (rozbb) 0.15.1 es la alternativa:** pone los mismos bytes en el disco y trae solo 7 crates nuevos, pero no está verificada ni auditada. Se cambia a ella sin volver a cifrar nada.

  X-Wing es todavía un *draft* del IETF: va por el 11, en el camino independiente, y su código para HPKE, `0x647a`, lo registra `draft-ietf-hpke-pq-05`. Por eso `kem_id` registra la versión exacta, y el plan de migración a la RFC final es volver a envolver la clave de cada generación. DHKEM(X25519), con `kem_id` versionado, queda como alternativa decidida.
- **Desbloqueo:** contraseña, biometría (una clave aleatoria guardada en Keychain, Keystore o Windows Hello) o PIN con límite de intentos en móvil. En Linux, el llavero (libsecret) no pide nada más que la sesión abierta, así que viene apagado ([D0-3](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0)).
- **El kit de recuperación es obligatorio** al dar de alta. Cambiar la contraseña exige la actual, el kit u otro dispositivo aprobado. **Nunca se borra el vault sin avisar.**
- **Vaults de equipo con manifiesto firmado** (cadena de entradas `add_member`, `remove_member`, `rotate`, `set_role` firmadas por un administrador; el génesis lo firma el creador). La baja de un miembro rota la clave y los ítems antiguos se vuelven a cifrar de forma perezosa. La recuperación de cuenta por la organización es una política opcional y visible.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| SQLCipher de base completa (como Arveil) | Oculta también los metadatos locales | No sirve para sync; tendríamos dos formatos |
| MLS para los vaults de equipo | Ya lo conocemos (Arveil) | Optimiza el secreto hacia delante en mensajería; un vault necesita que los miembros nuevos lean el historial |
| El servidor guarda las claves (como una nube "normal") | Recuperación trivial; administración fácil | Rompe la propuesta zero-knowledge |
| Solo X25519 | Más simple y probado | Riesgo de "guarda ahora, descifra después" en datos de larga vida |
| El paquete de la cuenta envuelto solo con la KEK | El kit no hace falta para dar de alta un equipo | Quien tenga el paquete prueba contraseñas sin conexión y sin límite ([D0-1](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0)) |

## Consecuencias

- Un usuario que pierda la contraseña, el kit y todos sus dispositivos pierde el vault. Es lo honesto en zero-knowledge, y la UI lo explica en el alta.
- La baja de un miembro no borra lo que ya vio: la app lo dice y recomienda rotar credenciales o usar certificados de corta duración.
- La confianza en la clave pública de un miembro nuevo depende de verificar huellas o de una atestación SSO del servidor. Queda documentado en `THREAT_MODEL.md`.

## Validación y revisión

Los vectores publicados que reúne S6 y una prueba de interoperabilidad con `hpke` (rozbb), en las pruebas de `openward-crypto`; vectores propios del sobre y de la jerarquía; pruebas de rotación y recuperación; y revisión criptográfica externa antes de lanzar OpenWard Cloud. Reabrir si la experiencia de alta de miembros en equipos piloto exige atestación del servidor por defecto.
