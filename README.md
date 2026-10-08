# OpenWard

**Cliente SSH open source, local-first y con sincronización cifrada de extremo a extremo, para Windows, macOS, Linux, iOS y Android.**

> [!WARNING]
> OpenWard está en **fase 0** (spikes técnicos). Todavía no hay nada usable. Este repositorio contiene la arquitectura, las decisiones (ADRs) y los primeros prototipos.

## Principios

- **Sin cuenta obligatoria.** La app funciona entera sin registrarse ni conectarse a ningún servidor.
- **Tus datos, en formato abierto.** Hosts, claves, snippets y túneles se exportan completos a un formato documentado en [`spec/`](spec/).
- **Cifrado de extremo a extremo.** Ningún servidor (ni el nuestro) ve hosts, usuarios, claves ni comandos.
- **Sincroniza con lo que ya tienes.** Carpeta (iCloud, Dropbox, Syncthing), S3, WebDAV o Git, o un servidor que tú mismo alojas.
- **Recuperación primero.** Cambiar o perder la contraseña nunca borra el vault en silencio.
- **Sin telemetría por defecto.**

## Estado y hoja de ruta

| Fase | Contenido | Estado |
|---|---|---|
| 0 · Spikes | Motor de terminal, SSH en las 5 plataformas, firma con hardware, formato de sync | **En curso** ([S1 terminal](docs/spikes/S1-terminal.md)) |
| 1 · MVP local | Cliente completo en escritorio y Android, sin cuenta | — |
| 2 · Vault y sync | Cifrado, recuperación, sync con almacenamiento propio, servidor autoalojable, iOS | — |
| 3 · Equipos e IA | Vaults compartidos, OIDC, servidor MCP, IA con tu propia clave o modelo local | — |
| 4 · Enterprise | SAML, SCIM, auditoría, grabación de sesiones, integraciones | — |

Detalle en [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Siempre gratis (borrador)

Lo siguiente es y seguirá siendo open source y gratuito. Esta lista solo puede crecer:

- la app completa en todas las plataformas, sin funciones capadas;
- la sincronización con tu propio almacenamiento;
- el servidor de sincronización autoalojable, con vaults de equipo, roles e inicio de sesión OIDC;
- la exportación completa de tus datos.

## Estructura

| Ruta | Contenido | Licencia |
|---|---|---|
| [`core/`](core/) | Núcleo Rust: terminal, SSH, vault, sync | Apache-2.0 |
| `app/` | App Flutter (a partir de la fase 1) | Apache-2.0 |
| `server/` | Servidor de sincronización en Go (a partir de la fase 2) | AGPL-3.0 |
| [`spec/`](spec/) | Formato del vault, protocolo de sync y API | CC-BY-4.0 |
| [`spikes/`](spikes/) | Prototipos de la fase 0; no es código de producto | Apache-2.0 |
| [`docs/`](docs/) | Arquitectura, ADRs, planes de spikes | CC-BY-4.0 |

Más detalles en [LICENSING.md](LICENSING.md).

## Desarrollo

Requisitos: Rust (la versión se fija en [`core/rust-toolchain.toml`](core/rust-toolchain.toml)).

```bash
make test     # pruebas del núcleo
make lint     # rustfmt + clippy en modo estricto
make bench    # smoke test del banco de pruebas del terminal
```

## Contribuir y seguridad

- [CONTRIBUTING.md](CONTRIBUTING.md): cómo proponer cambios (DCO).
- [SECURITY.md](SECURITY.md): cómo reportar vulnerabilidades en privado.
