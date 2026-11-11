# Estado y backlog verificable

Actualizado el **11 de noviembre de 2026**. Este índice relaciona el código,
las PR y las puertas del roadmap; las estimaciones antiguas no son fechas
comprometidas.

| Área | Estado y evidencia |
|---|---|
| Integración | Base del balance: `main 2118736`, tras las PR #26–#29. Cada fusión posterior exige revisión exacta probada y actualización local por avance rápido. |
| CI de Mosh | [#26](https://github.com/KaiCorpLabs/openward/pull/26) fusionada: 19 trabajos correctos y árbol integrado igual al probado. Corrige la selección entre salida del cliente y aviso UDP pendiente. |
| Beta | [#27](https://github.com/KaiCorpLabs/openward/pull/27) fusionada con 19 trabajos correctos: `0.3.4-beta.4+30` y notas preparadas. Etiqueta/borrador/artefactos finales pendientes de cerrar S2. |
| Distribución | La última etiqueta anterior es `v0.3.4-beta.3`; sus binarios no incluyen por sí solos las correcciones posteriores. No hay release pública; no se ha actualizado el cask en este trabajo. |
| Seguridad | S0/S1 integrados. Cuatro correcciones de S2, con sus puertas de CI y fusión, en [#28](https://github.com/KaiCorpLabs/openward/pull/28), [#29](https://github.com/KaiCorpLabs/openward/pull/29), [#30](https://github.com/KaiCorpLabs/openward/pull/30) y [#31](https://github.com/KaiCorpLabs/openward/pull/31). [Seguimiento y límites](seguridad-0.3.3.md#seguimiento-de-s2). |
| v0.4 | D0–D2 completados y ADR-004/005 aceptados. D3 iniciado en [#43](https://github.com/KaiCorpLabs/openward/pull/43): sobre canónico autenticado y ocho pruebas; queda fuera de esta beta. D3–D8 conservan sus criterios de cierre abajo. |
| Uso real | Etapa 1 implementada; pruebas con hardware y dos semanas de uso pendientes. CI no las sustituye. |

## Hito v0.4

[Milestone v0.4](https://github.com/KaiCorpLabs/openward/milestone/1).
Cada issue contiene una lista comprobable y depende de los anteriores cuando
corresponde. Cerrar una PR parcial no cierra automáticamente su hito.

| Trabajo | Seguimiento | Puerta principal |
|---|---|---|
| D3: núcleo y migración | [#32](https://github.com/KaiCorpLabs/openward/issues/32) | Sobres v1, vectores/interoperabilidad y migración transaccional sin pérdidas. |
| D4: desbloqueo/bloqueo | [#33](https://github.com/KaiCorpLabs/openward/issues/33) | Maquetas revisadas, ciclo de bloqueo y pruebas nativas en tres sistemas. |
| D5: recuperación | [#34](https://github.com/KaiCorpLabs/openward/issues/34) | Kit y cambio de contraseña; recuperación independiente. |
| D6: secretos y sesiones | [#35](https://github.com/KaiCorpLabs/openward/issues/35) | Guardado opcional y cifrado de historial, recientes y grabaciones. |
| D7: copias | [#36](https://github.com/KaiCorpLabs/openward/issues/36) | .owvault/JSON especificados y restauración verificada. |
| D8: beta y validación | [#37](https://github.com/KaiCorpLabs/openward/issues/37) | Uso, recuperación, mediciones, CI, notas y beta preparada. |

El [plan v0.4](v0.4.md) conserva el contrato de producto y las decisiones
aceptadas. El vault actual continúa sin cifrar hasta implementar y activar esa
migración.

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
