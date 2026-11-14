# Licencias

**Desde el 2026-11-10, todo el repositorio tiene todos los derechos reservados** ([LICENSE](LICENSE)). Solo se permite ver el código en GitHub y usar las versiones compiladas que publicamos. No se puede copiar, modificar, redistribuir ni usar en otros productos, ni usar para entrenar modelos de IA. Lo decide la [revisión del 2026-11-10 de ADR-007](docs/adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-10).

- **Lo publicado antes**, hasta el commit `945fbbe` (2026-11-10), salió con Apache-2.0, y esa licencia se sigue aplicando a esas copias.
- **Al lanzar la Community**, cada componente tendrá esta licencia:

  | Componente | Licencia al lanzar | Contribuciones |
  |---|---|---|
  | `core/`, `app/`, `spikes/` (el cliente) | GPL-3.0-only | CLA (acuerdo de licencia de contribuidor) |
  | `spec/`, `docs/` | CC-BY-4.0 | CLA |

- **El servidor de sincronización** se prevé en el mismo monorepo que Flutter/Rust, según [ADR-010](docs/adr/ADR-010-monorepo-go-supabase.md). Su código local aún no está integrado en main. Esta decisión sustituye el repositorio separado de las revisiones anteriores de ADR-006/007; no modifica [LICENSE](LICENSE) ni determina automáticamente licencia, visibilidad o publicación del servidor. Conciliar esos puntos con revisión legal antes de publicar código.
- **Contribuciones:** hasta el lanzamiento no se aceptan contribuciones de código de fuera; sí issues y avisos de seguridad ([CONTRIBUTING](CONTRIBUTING.md)).
- **Dependencias del cliente:** solo licencias permisivas (Apache-2.0, MIT, BSD, ISC, Zlib, Unicode, Unlicense) y MPL-2.0 con inventario. Las licencias GPL y AGPL no se admiten en el cliente, aunque salga con GPL: los derechos de todo su código tienen que ser nuestros para poder ofrecerlo también con otra licencia, como hace falta en la App Store. `cargo-deny` lo comprueba en la CI (`core/deny.toml`).
- **Fuentes incluidas:** SIL Open Font License 1.1, en `app/assets/fonts` con su licencia al lado. Se listan en [NOTICE](NOTICE).
- **Componentes de terceros:** conservan sus licencias, que están en [NOTICE](NOTICE) y en el archivo de licencia de cada uno (por ejemplo, `app/rust_builder/cargokit/LICENSE`).
- **Marca:** «OpenWard» y sus logotipos no se licencian con el código. Las versiones bifurcadas deben usar otro nombre.
