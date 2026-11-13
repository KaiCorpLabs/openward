# Estado y backlog verificable

Actualizado el **13 de noviembre de 2026**. Este índice relaciona el código,
las PR y las puertas del roadmap; las estimaciones antiguas no son fechas
comprometidas.

| Área | Estado y evidencia |
|---|---|
| Integración | D3: [#45](https://github.com/KaiCorpLabs/openward/pull/45) y [#52](https://github.com/KaiCorpLabs/openward/pull/52); D4: [#53](https://github.com/KaiCorpLabs/openward/pull/53); D5: [#54](https://github.com/KaiCorpLabs/openward/pull/54); D6: [#55](https://github.com/KaiCorpLabs/openward/pull/55); D7: [#56](https://github.com/KaiCorpLabs/openward/pull/56); D8: [#57](https://github.com/KaiCorpLabs/openward/pull/57); KDF: [#58](https://github.com/KaiCorpLabs/openward/pull/58), fusionadas. [CI de `main a9bc431`](https://github.com/KaiCorpLabs/openward/actions/runs/43397490475): 19 trabajos correctos y borrador de release omitido. Cada fusión posterior exige revisión exacta probada y actualización local por avance rápido. |
| Dependencias (13-11-2026) | Integración conjunta de [#46](https://github.com/KaiCorpLabs/openward/pull/46)–[#51](https://github.com/KaiCorpLabs/openward/pull/51) sobre `main a9bc431`, conservando sus commits: encoding_rs, flate2, uuid, libc/serde_json del benchmark y Riverpod 3.5.0. Lockfile de Flutter corregido al SDK fijado (`test_api 0.7.12`); CI, CI local y empaquetado Linux exigen `--enforce-lockfile`. Fusión sujeta a CI completa del árbol combinado. |
| CI de Mosh | [#26](https://github.com/KaiCorpLabs/openward/pull/26) fusionada con 19 trabajos correctos. La CI posterior encontró un aviso transitorio durante conexiones válidas; [#44](https://github.com/KaiCorpLabs/openward/pull/44) lo reproduce por PTY y cambia el fallback al diagnóstico final de fallo de handshake. Once casos focalizados y las conexiones UDP/SSH reales forman la puerta. |
| Beta | D8 prepara `0.4.0-beta.1+31` con [notas](../notas/v0.4.md), [pruebas](prueba-v0.4.md) y [medición local](../evidence/v0.4-beta1.md); sin publicación ni cask. Beta anterior: [#27](https://github.com/KaiCorpLabs/openward/pull/27) fusionada con 19 trabajos correctos: `0.3.4-beta.4+30` y notas preparadas. Etiqueta `v0.3.4-beta.4` fijada en `5736b7c`; borrador privado con cuatro paquetes, checksums y procedencia verificados. Publicación pendiente en #42. |
| Distribución | La etiqueta `v0.3.4-beta.4` incluye S2 y la corrección final de Mosh; D3 queda fuera de esa beta. No hay release pública; el [cask](https://github.com/KaiCorpLabs/homebrew-tap/blob/main/Casks/openward.rb) sigue en `0.3.4-beta.3`, por detrás de la etiqueta/borrador y del código candidato 0.4. |
| Seguridad | S0/S1 integrados. Cuatro correcciones de S2, con sus puertas de CI y fusión, en [#28](https://github.com/KaiCorpLabs/openward/pull/28), [#29](https://github.com/KaiCorpLabs/openward/pull/29), [#30](https://github.com/KaiCorpLabs/openward/pull/30) y [#31](https://github.com/KaiCorpLabs/openward/pull/31). [Seguimiento y límites](seguridad-0.3.3.md#seguimiento-de-s2). |
| v0.4 | D0–D2 completados y ADR-004/005 aceptados. D3 implementa sobres, jerarquía/Argon2id y migración del backend Rust, con pruebas de recuperación y formato documentado. [#43](https://github.com/KaiCorpLabs/openward/pull/43), [#45](https://github.com/KaiCorpLabs/openward/pull/45) y #32 conservan la evidencia. D4 añade alta optativa, desbloqueo y bloqueo ([#53](https://github.com/KaiCorpLabs/openward/pull/53)). D5 completa el kit con QR/PDF, la regeneración, el cambio de contraseña y el paquete de cuenta protegido por contraseña+kit ([#54](https://github.com/KaiCorpLabs/openward/pull/54)); D6 añade secretos optativos y datos locales cifrados ([contrato y pruebas](../../spec/protected-local-v1.md)); D7 implementa las copias portables y la restauración segura ([formato y guía](../../spec/vault-backup-v1.md)); D8 prepara onboarding obligatorio/«Más tarde», Ajustes y `0.4.0-beta.1+31` ([guía](prueba-v0.4.md)); #37 conserva las puertas humanas y #33 las físicas/visuales. |
| Móvil | Primera implementación de Android e iOS para [#68](https://github.com/KaiCorpLabs/openward/issues/68): la misma app, el núcleo para los cuatro destinos móviles, Keychain/Keystore, interfaz de teléfono y pruebas en simulador y emulador ([plan, paridad y límites](movil.md)). Puertas S1.2/S2/S3/S5 en dispositivos reales, firma y tiendas pendientes. |
| Uso real | Etapa 1 implementada; pruebas con hardware y dos semanas de uso pendientes. CI no las sustituye. |

## Hito v0.4

[Milestone v0.4](https://github.com/KaiCorpLabs/openward/milestone/1).
Cada issue contiene una lista comprobable y depende de los anteriores cuando
corresponde. Cerrar una PR parcial no cierra automáticamente su hito.

| Trabajo | Seguimiento | Puerta principal |
|---|---|---|
| D3: núcleo y migración | [#32](https://github.com/KaiCorpLabs/openward/issues/32) | Implementado: sobres v1, vectores/interoperabilidad, jerarquía/KDF y migración verificada; [formato y pruebas](../../spec/vault-sqlite-v2.md). |
| D4: desbloqueo/bloqueo | [#33](https://github.com/KaiCorpLabs/openward/issues/33) | Sesión/FFI/alta optativa implementadas y validadas en los tres sistemas en #53; [evidencia y límites](../../spec/vault-session-v1.md). Firma SSH P-256 no exportable implementada: alta con prueba de firma, referencia pública en el vault, bloqueo/cancelación y rechazo de exportación ([contrato y pruebas](../../spec/secure-enclave-ssh-v1.md)). Maquetas y autenticación física con el bundle real pendientes. |
| D5: recuperación | [#34](https://github.com/KaiCorpLabs/openward/issues/34) | Implementado en #54: kit obligatorio al cifrar, QR/PDF, regeneración y cambio de contraseña con autorización, paquete de cuenta D0-1 y recuperación de la misma copia cifrada en Linux/macOS/Windows; [contrato, pruebas y límites](../../spec/recovery-v1.md). |
| D6: secretos y sesiones | [#35](https://github.com/KaiCorpLabs/openward/issues/35) | Implementado: claves privadas y credenciales con consentimiento; historial, recientes y grabaciones cifrados, migración y bloqueo, clave por grabación y formato3 contra regresión a texto claro. [Pruebas y límites](../../spec/protected-local-v1.md); CI completa como puerta de fusión. |
| D7: copias | [#36](https://github.com/KaiCorpLabs/openward/issues/36) | Implementado: `.owvault` por contraseña/kit y JSON con autorización; restauración atómica en vault cifrado vacío con identidad propia, sin reemplazar datos. [Formato, pruebas y guía](../../spec/vault-backup-v1.md); CI completa como puerta de fusión. |
| D8: beta y validación | [#37](https://github.com/KaiCorpLabs/openward/issues/37) | Implementación y candidata `0.4.0-beta.1+31` preparadas; [notas](../notas/v0.4.md), [guía](prueba-v0.4.md). Calibración KDF corregida con regresión de Windows y prueba release estricta de 500–1000 ms ([evidencia](../evidence/kdf-calibration-v0.4.md)); CI completa en los tres sistemas como puerta de fusión. Semana de uso, migraciones personales y hardware pendientes. |

El [plan v0.4](v0.4.md) conserva el contrato aceptado. D8 exige proteger el
vault antes de Home, por contraseña+kit o «Más tarde» con una clave del llavero
y aviso permanente. El cifrado migra datos y rechaza el acceso al legado mientras
se prepara; una falta del llavero no permite entrar en claro. Los vaults cifrados
arrancan bloqueados. D5–D7 completan recuperación, secretos y copias. La beta
0.3.4 etiquetada y su borrador anterior se conservan por separado; la candidata
0.4 no se publica ni actualiza el cask en esta preparación.

## Puertas Community

[Milestone Community](https://github.com/KaiCorpLabs/openward/milestone/2).

| Trabajo | Seguimiento | Evidencia necesaria |
|---|---|---|
| v0.5: motor de sync | [#38](https://github.com/KaiCorpLabs/openward/issues/38) | Convergencia, equipos y recuperación/reintento contra un backend de pruebas; sin backends de almacenamiento propio. |
| v0.6: servidor y cuentas | [#39](https://github.com/KaiCorpLabs/openward/issues/39) | ADR/API/modelo revisados y despliegue inicial dentro del tailnet. |
| v0.7: operación pública | [#40](https://github.com/KaiCorpLabs/openward/issues/40) | Copias/restauración, monitorización, borrado y puerta pública aprobada. |
| Firma, actualización y descargas | [#41](https://github.com/KaiCorpLabs/openward/issues/41) | Instalación/actualización reales y artefactos trazables. |
| Pruebas manuales, decisiones y lanzamiento | [#42](https://github.com/KaiCorpLabs/openward/issues/42) | Hardware, uso prolongado, decisiones pendientes y revisión legal. |

El 2026-11-13 se decidió que toda la sync es de pago y alojada, con el servidor
privado y Android e iOS antes de cobrar ([decisiones](community.md#decisiones-del-2026-11-13)).
#38, #39 y #40 conservan su número con ese alcance.

Publicar una release, comprar dominio/certificados o activar servicios públicos
mantiene sus decisiones específicas. Los nuevos issues son trabajo de producto;
los reportes de vulnerabilidades usan el canal privado de [SECURITY.md](../../SECURITY.md).

Los 63 puntos del informe de seguridad y los 128 de la auditoría anterior son
inventarios históricos, no el número actual de vulnerabilidades o tareas
abiertas. Los casos pendientes de plataforma conservan su evidencia solicitada;
no se dan por cerrados por haber pasado la CI.
