# ADR-005 — Sync por registros de dispositivo con backends intercambiables

- **Estado:** propuesto, pendiente de spike (S4).
- **Fecha:** 2026-10-08.
- **Alcance:** protocolo de sincronización, resolución de conflictos y backends.

## Contexto

La diferencia comercial de OpenWard es la **sync gratis con el almacenamiento del usuario** (carpeta, S3, WebDAV, Git) y la **sync alojada de pago** con tiempo real. Si cada backend tuviera su propio protocolo, el equipo no podría mantenerlos. El almacenamiento del usuario es "tonto": no hay transacciones, a veces no hay *compare-and-swap* y servicios como iCloud o Dropbox replican archivos con retraso.

## Decisión

- **Cada dispositivo solo añade a su registro:** segmentos inmutables firmados en `logs/<device_id>/<seq>.seg` e instantáneas en `snaps/`. **Nadie sobrescribe el archivo de otro.** Las operaciones mínimas de un backend son `put` de un objeto nuevo, `get` y `list(prefix, after)`. `watch` es opcional.
- **Merge en el cliente:** un DAG de revisiones por ítem, merge a tres bandas por campo y, si el conflicto es en el mismo campo, gana la última escritura según un reloj lógico híbrido, guardando la versión perdedora en el historial con aviso. Los borrados son lápidas.
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

Hay más complejidad en el cliente (merge, compactación, cursores). Se compensa con pruebas de propiedades (`proptest`: ediciones concurrentes aleatorias deben converger) y una CLI que simula N dispositivos. El servidor queda muy simple y barato. La latencia de los backends tontos depende del servicio del usuario y la UI lo comunica ("última sync: hace 3 min, vía iCloud").

## Validación y revisión

S4: 3 dispositivos × {carpeta, S3} con 10.000 ediciones concurrentes deben converger. Aceptar con convergencia del 100 % y compactación verificada. Reabrir si los backends con consistencia eventual (WebDAV o iCloud) producen pérdidas no detectables.
