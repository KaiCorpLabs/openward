# Especificaciones

Aquí se documentarán los formatos públicos de OpenWard, para que cualquiera pueda leer, exportar o sincronizar sus datos sin depender de nuestro código:

| Documento | Contenido | Fase |
|---|---|---|
| `term-frame-v1.md` | Frames de damage entre el núcleo y la UI (hoy documentado en [`core/crates/openward-term/src/frame.rs`](../core/crates/openward-term/src/frame.rs)) | 0 |
| `vault-format.md` | Ítems, sobres cifrados y jerarquía de claves ([ADR-004](../docs/adr/ADR-004-vault-y-jerarquia-de-claves.md)) | 2 |
| `sync-protocol.md` | Registros por dispositivo, instantáneas y backends ([ADR-005](../docs/adr/ADR-005-sync-por-registros-de-dispositivo.md)) | 2 |
| `server-api.md` | API del servidor de sincronización | 2 |
| `export-format.md` | Exportación completa | 1 |

Licencia: CC-BY-4.0.
