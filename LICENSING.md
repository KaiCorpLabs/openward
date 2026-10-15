# Licencias

OpenWard usa una licencia distinta por componente ([ADR-007](docs/adr/ADR-007-licencias-y-contribuciones.md)).

| Componente | Licencia | Contribuciones |
|---|---|---|
| `core/`, `app/`, `spikes/` | [Apache-2.0](LICENSE) | [DCO](CONTRIBUTING.md#dco) |
| `server/` (cuando exista) | AGPL-3.0 | CLA (acuerdo de licencia de contribuidor) |
| `spec/`, `docs/` | CC-BY-4.0 | DCO |

- Si un directorio no tiene un archivo `LICENSE` propio, aplica la licencia de esta tabla.
- **Dependencias del cliente:** solo licencias permisivas (Apache-2.0, MIT, BSD, ISC, Zlib, Unicode, Unlicense) y MPL-2.0 con inventario. Las licencias GPL y AGPL no se admiten en el cliente. `cargo-deny` lo comprueba en CI ([`core/deny.toml`](core/deny.toml)).
- **Fuentes incluidas:** SIL Open Font License 1.1, en `app/assets/fonts` con su licencia al lado. Se listan en [NOTICE](NOTICE).
- **Marca:** "OpenWard" y sus logotipos no se licencian con el código. Las versiones bifurcadas deben usar otro nombre.
