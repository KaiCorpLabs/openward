# Estado y backlog verificable

Actualizado el **12 de noviembre de 2026**. Este índice relaciona el código,
las PR y las puertas del roadmap; las estimaciones antiguas no son fechas
comprometidas.

| Área | Estado y evidencia |
|---|---|
| Integración | D3: [jerarquía #45](https://github.com/KaiCorpLabs/openward/pull/45) y [migración #52](https://github.com/KaiCorpLabs/openward/pull/52), con 19 trabajos correctos. D4: [sesión de vault #53](https://github.com/KaiCorpLabs/openward/pull/53), con 19 trabajos correctos. D5: [recuperación y contraseña #54](https://github.com/KaiCorpLabs/openward/pull/54), con CI completa como puerta de fusión. Cada fusión posterior exige revisión exacta probada y actualización local por avance rápido. |
| CI de Mosh | [#26](https://github.com/KaiCorpLabs/openward/pull/26) fusionada con 19 trabajos correctos. La CI posterior encontró un aviso transitorio durante conexiones válidas; [#44](https://github.com/KaiCorpLabs/openward/pull/44) lo reproduce por PTY y cambia el fallback al diagnóstico final de fallo de handshake. Once casos focalizados y las conexiones UDP/SSH reales forman la puerta. |
| Beta | [#27](https://github.com/KaiCorpLabs/openward/pull/27) fusionada con 19 trabajos correctos: `0.3.4-beta.4+30` y notas preparadas. Etiqueta `v0.3.4-beta.4` fijada en `5736b7c`; borrador privado con cuatro paquetes, checksums y procedencia verificados. Publicación pendiente en #42. |
| Distribución | La etiqueta `v0.3.4-beta.4` incluye S2 y la corrección final de Mosh; D3 queda fuera de esa beta. No hay release pública; no se ha actualizado el cask en este trabajo. |
| Seguridad | S0/S1 integrados. Cuatro correcciones de S2, con sus puertas de CI y fusión, en [#28](https://github.com/KaiCorpLabs/openward/pull/28), [#29](https://github.com/KaiCorpLabs/openward/pull/29), [#30](https://github.com/KaiCorpLabs/openward/pull/30) y [#31](https://github.com/KaiCorpLabs/openward/pull/31). [Seguimiento y límites](seguridad-0.3.3.md#seguimiento-de-s2). |
| v0.4 | D0–D2 completados y ADR-004/005 aceptados. D3 implementa sobres, jerarquía/Argon2id y migración del backend Rust, con pruebas de recuperación y formato documentado. [#43](https://github.com/KaiCorpLabs/openward/pull/43), [#45](https://github.com/KaiCorpLabs/openward/pull/45) y #32 conservan la evidencia. D4 añade alta optativa, desbloqueo y bloqueo ([#53](https://github.com/KaiCorpLabs/openward/pull/53)). D5 completa el kit con QR/PDF, la regeneración, el cambio de contraseña y el paquete de cuenta protegido por contraseña+kit ([#54](https://github.com/KaiCorpLabs/openward/pull/54)); D6–D8 y las puertas físicas/visuales de D4 siguen abiertos. |
| Uso real | Etapa 1 implementada; pruebas con hardware y dos semanas de uso pendientes. CI no las sustituye. |

## Hito v0.4

[Milestone v0.4](https://github.com/KaiCorpLabs/openward/milestone/1).
Cada issue contiene una lista comprobable y depende de los anteriores cuando
corresponde. Cerrar una PR parcial no cierra automáticamente su hito.

| Trabajo | Seguimiento | Puerta principal |
|---|---|---|
| D3: núcleo y migración | [#32](https://github.com/KaiCorpLabs/openward/issues/32) | Implementado: sobres v1, vectores/interoperabilidad, jerarquía/KDF y migración verificada; [formato y pruebas](../../spec/vault-sqlite-v2.md). |
| D4: desbloqueo/bloqueo | [#33](https://github.com/KaiCorpLabs/openward/issues/33) | Sesión/FFI/alta optativa implementadas y validadas en los tres sistemas en #53; [evidencia y límites](../../spec/vault-session-v1.md). Maquetas, autenticación física y SSH Secure Enclave pendientes. |
| D5: recuperación | [#34](https://github.com/KaiCorpLabs/openward/issues/34) | Implementado en #54: kit obligatorio al cifrar, QR/PDF, regeneración y cambio de contraseña con autorización, paquete de cuenta D0-1 y recuperación de la misma copia cifrada en Linux/macOS/Windows; [contrato, pruebas y límites](../../spec/recovery-v1.md). |
| D6: secretos y sesiones | [#35](https://github.com/KaiCorpLabs/openward/issues/35) | Guardado opcional y cifrado de historial, recientes y grabaciones. |
| D7: copias | [#36](https://github.com/KaiCorpLabs/openward/issues/36) | .owvault/JSON especificados y restauración verificada. |
| D8: beta y validación | [#37](https://github.com/KaiCorpLabs/openward/issues/37) | Uso, recuperación, mediciones, CI, notas y beta preparada. |

El [plan v0.4](v0.4.md) conserva el contrato de producto y las decisiones
aceptadas. D4 permite activar el cifrado desde Ajustes → Seguridad después de guardar y
confirmar un kit. El vault cifrado arranca bloqueado. Los vaults antiguos
siguen identificados como sin cifrar hasta completar esa alta; actualizar no
convierte datos reales. D5 añade QR/PDF y los cambios de credenciales. El onboarding obligatorio/«Más tarde»,
la copia/importación de datos `.owvault` y el cifrado de los datos derivados
siguen pendientes en D6–D8. Las copias antiguas conservan sus factores anteriores.

## Puertas Community

[Milestone Community](https://github.com/KaiCorpLabs/openward/milestone/2).

| Trabajo | Seguimiento | Evidencia necesaria |
|---|---|---|
| v0.5: sync con almacenamiento propio | [#38](https://github.com/KaiCorpLabs/openward/issues/38) | Convergencia, backends, equipos y recuperación/reintento. |
| v0.6: servidor y cuentas | [#39](https://github.com/KaiCorpLabs/openward/issues/39) | ADR/API/modelo revisados y despliegue inicial dentro del tailnet. |
| v0.7: operación pública | [#40](https://github.com/KaiCorpLabs/openward/issues/40) | Copias/restauración, monitorización, borrado y puerta pública aprobada. |
| Firma, actualización y descargas | [#41](https://github.com/KaiCorpLabs/openward/issues/41) | Instalación/actualización reales y artefactos trazables. |
| Pruebas manuales, decisiones y lanzamiento | [#42](https://github.com/KaiCorpLabs/openward/issues/42) | Hardware, uso prolongado, decisiones pendientes y revisión legal. |

Publicar una release, comprar dominio/certificados o activar servicios públicos
mantiene sus decisiones específicas. Los nuevos issues son trabajo de producto;
los reportes de vulnerabilidades usan el canal privado de [SECURITY.md](../../SECURITY.md).

Los 63 puntos del informe de seguridad y los 128 de la auditoría anterior son
inventarios históricos, no el número actual de vulnerabilidades o tareas
abiertas. Los casos pendientes de plataforma conservan su evidencia solicitada;
no se dan por cerrados por haber pasado la CI.
