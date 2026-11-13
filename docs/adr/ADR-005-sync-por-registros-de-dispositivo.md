# ADR-005 — Sync por registros de dispositivo con backends intercambiables

- **Estado:** **aceptado** (2026-11-10), con la primera parte de [S4](../spikes/S4-sync.md) (2026-11-09), que cambió el merge a relojes de campo y fijó el sobre. La segunda (v0.5, S1) puede reabrirlo ([Validación](#validación-y-revisión)). [Revisado el 2026-11-13](#revisión-del-2026-11-13): el motor se queda, pero su único backend es el servidor; no hay backends de almacenamiento propio.
- **Fecha:** 2026-10-08.
- **Alcance:** protocolo de sincronización, resolución de conflictos y backends.

## Contexto

La diferencia comercial de OpenWard es la **sync gratis con el almacenamiento del usuario** (carpeta, S3, WebDAV, Git) y la **sync alojada de pago** con tiempo real. Si cada backend tuviera su propio protocolo, el equipo no podría mantenerlos. El almacenamiento del usuario es "tonto": no hay transacciones, a veces no hay *compare-and-swap* y servicios como iCloud o Dropbox replican archivos con retraso.

## Decisión

- **Cada dispositivo solo añade a su registro:** segmentos inmutables firmados en `logs/<device_id>/<seq>.seg` e instantáneas en `snaps/`. **Nadie sobrescribe el archivo de otro.** Las operaciones mínimas de un backend son `put` de un objeto nuevo, `get` y `list(prefix, after)`. `watch` es opcional.
- **Merge en el cliente, por relojes de campo:** cada revisión lleva, para cada campo, el reloj lógico híbrido de la escritura que lo puso, y el merge se queda, campo a campo, con el más reciente. No necesita el historial, así que podar es seguro. Las revisiones siguen formando un DAG por ítem (`parents`), para el historial y para avisar de los conflictos: la versión perdedora queda en el historial con aviso. Un campo se escribe siempre con un reloj posterior al que sustituye, y el reloj no sigue a otro que vaya más de 60 s por delante.
  - **Revisado con [S4](../spikes/S4-sync.md#63-por-qué-falla-el-merge-a-tres-bandas) (2026-11-09).** Antes decía «merge a tres bandas por campo desde el ancestro común». S4 lo refutó: pierde escrituras cuando un campo vuelve a su valor anterior en un lado, y tras una poda un equipo que vuelve sin el historial deshace el trabajo de los demás.
- **Borrar es escribir el campo `deleted`** (la papelera), que gana o pierde como cualquier otro. Un borrado definitivo, con lápida, queda para cuando haga falta.
- **El sobre** (`v: 1`, [S4 §5](../spikes/S4-sync.md#5-el-sobre-v1)): `{v, vault, item, device, key_gen, parents, nonce, ct, sig}` en CBOR canónico; la revisión es el SHA-256 del sobre sin firma; la firma del dispositivo va en cada sobre y se comprueba al recibirlo, no al desbloquear.
- **Compactación** mediante instantáneas y poda cuando todos los dispositivos activos han confirmado lectura o vence la retención.
- **El relay es un backend más**, con `watch` (WebSocket), ACL y cuotas. OpenWard Cloud es el mismo relay operado por nosotros.
- **Formato especificado en `spec/`** (CBOR canónico, versionado) para que se puedan escribir clientes de terceros.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| Servidor con secuencia global (estilo Bitwarden) | Más simple en el servidor | No funciona con almacenamiento tonto; perdemos la sync gratis "con lo tuyo" |
| CRDT de documento completo (Automerge, Yjs) | Merge automático rico | Metadatos y tamaño grandes; cifrar por ítem es incómodo; un vault no es un documento colaborativo en tiempo real |
| Un único archivo de vault cifrado | Trivial (estilo KeePass) | Conflictos destructivos con Dropbox o iCloud; no escala a equipos |
| Git como protocolo universal | Historial gratis | No hay Git en iOS sin una librería pesada; S3 y WebDAV quedarían fuera |

## Consecuencias

Hay más complejidad en el cliente (merge, compactación, cursores). Se compensa con pruebas de propiedades (`proptest`: ediciones concurrentes aleatorias deben converger, y ninguna escritura que nadie vio puede perderse) y una CLI que simula N dispositivos. Cada revisión pesa unos 300 bytes más que el cuerpo, por la firma, los ids, el padre y los relojes de campo: 10.000 hosts ocupan unos 5 MB. Una lista (las etiquetas) se fusiona como un solo valor. El servidor queda muy simple y barato. La latencia de los backends tontos depende del servicio del usuario y la UI lo comunica ("última sync: hace 3 min, vía iCloud").

## Validación y revisión

S4, en dos partes:
- **Primera (2026-11-09), en memoria:** 3 dispositivos × 10.000 escrituras y 2.000 ejecuciones aleatorias de `proptest` con poda y relojes desfasados, en los tres sistemas. Con relojes de campo, convergencia del 100 % y ninguna escritura perdida; con tres bandas, no. Ver [S4-sync.md](../spikes/S4-sync.md).
- **Segunda (v0.5, S1), con backends:** 3 dispositivos × {carpeta, S3} con 10.000 ediciones concurrentes deben converger. Aceptar con convergencia del 100 % y compactación verificada. Reabrir si los backends con consistencia eventual (WebDAV o iCloud) producen pérdidas no detectables.

## Revisión del 2026-11-13

El contexto de arriba daba como diferencia comercial la sync gratis con el almacenamiento del usuario. Desde el 2026-11-13, toda la sincronización es de pago y alojada ([ADR-006](ADR-006-servidor-open-core.md#revisión-del-2026-11-13)).

**Decisión:**
- **El motor no cambia:** registros por dispositivo que solo crecen, merge por relojes de campo, el sobre `v: 1`, la compactación y el formato en `spec/`.
- **El único backend es el relay del servicio alojado.** Quedan descartados los backends de almacenamiento propio (carpeta, S3, WebDAV y Git) y el relay autoalojado.
- **El backend sigue siendo un trait** (`put`, `get`, `list` y `watch`). Además del relay, tiene uno de pruebas, en memoria y en un directorio, para las pruebas del núcleo y la CLI que simula N dispositivos. La app no lo ofrece.
- **La segunda parte de S4** pasa a ser: 3 dispositivos × 10.000 ediciones concurrentes con el motor de verdad contra el backend de pruebas (v0.5, S1) y contra el relay (v0.6, C6). Se acepta con convergencia del 100 % y compactación verificada. Ya no depende de los backends con consistencia eventual.

**Por qué no se reabre el diseño:**
- La alternativa del servidor con secuencia global se descartó porque no funcionaba con almacenamiento «tonto». Esa razón ya no cuenta, pero las demás sí: el sobre y el merge están medidos en S4 y la v0.4 ya escribe el sobre; el cliente funciona sin conexión y fusiona al volver; y el servidor queda simple, barato y sin ver el contenido.
- Que el motor pida tan poco al almacenamiento deja abierta la puerta a otros backends más adelante sin tocar el formato.

**Consecuencias:**
- Menos que construir y probar: sin los casos difíciles de iCloud, Dropbox o WebDAV (copias con retraso, archivos «en conflicto»).
- La latencia ya no depende del servicio del usuario: la da el relay, con `watch`.
- La etapa 3 del [camino a la Community](../plan/community.md#etapa-3--v05-el-motor-de-sync) pierde sus hitos de backends (S2 y S3).
