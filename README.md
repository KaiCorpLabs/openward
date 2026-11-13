# OpenWard

**Cliente SSH local-first y con sincronización cifrada de extremo a extremo, para Windows, macOS, Linux, iOS y Android.**

> [!IMPORTANT]
> **Todos los derechos reservados.** El código se puede leer aquí, pero no copiar, modificar, redistribuir ni usar en otros productos: ver [LICENSE](LICENSE). El cliente será open source cuando se lance la Community ([LICENSING.md](LICENSING.md)).

> [!WARNING]
> OpenWard está en **fase 1**: hay una beta de escritorio (0.3) que el equipo prueba a diario ([notas](docs/notas/v0.3.md), [guía de prueba](docs/plan/prueba-v0.3.md)). Aún no está firmada y el vault no va cifrado.

## Principios

- **Sin cuenta obligatoria.** La app funciona entera en tu equipo sin registrarse ni conectarse a ningún servidor. La cuenta solo hace falta para sincronizar.
- **Tus datos, en formato abierto.** Hosts, claves, snippets y túneles se exportan completos a un formato documentado en [`spec/`](spec/).
- **Cifrado de extremo a extremo.** Nuestro servidor no ve hosts, usuarios, claves ni comandos.
- **Solo se paga por sincronizar.** La sincronización entre equipos es opcional y es el servicio de pago: va con una cuenta gratuita, que trae un periodo de prueba. Todo lo demás es gratis.
- **Recuperación primero.** Cambiar o perder la contraseña nunca borra el vault en silencio.
- **Sin telemetría por defecto.**

## Estado y hoja de ruta

| Fase | Contenido | Estado |
|---|---|---|
| 0 · Spikes | Motor de terminal, SSH en las 5 plataformas, firma con hardware, formato de sync | Escritorio hecho ([S1 terminal](docs/spikes/S1-terminal.md), S2 SSH); móvil y sync, con la fase 2 |
| 1 · MVP local | Cliente completo en escritorio, sin cuenta | Funcionalidad de la [etapa 1](docs/plan/community.md#etapa-1--lo-básico-completo) implementada; quedan las pruebas manuales de hardware y uso prolongado |
| 2 · Vault y sync | Cifrado, recuperación, sync alojada con cuenta (de pago); Android e iOS, después del lanzamiento de escritorio y antes de cobrar por la sync | D0–D2 de la [v0.4](docs/plan/v0.4.md) completados; D3–D8 y las etapas de sync/servidor pendientes |
| 3 · Equipos e IA | Vaults compartidos, OIDC, servidor MCP, IA con tu propia clave o modelo local | — |
| 4 · Enterprise | SAML, SCIM, auditoría, grabación de sesiones, integraciones | — |

Detalle en [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

Estado actual, PR y criterios de cierre en el [backlog del proyecto](docs/plan/estado.md).

## Siempre gratis (borrador)

Desde el lanzamiento de la Community, lo siguiente será open source y gratuito, y la lista solo podrá crecer:

- la app completa en todas las plataformas, funcionando en tu equipo y sin cuenta: todo lo que no es sincronizar;
- el vault cifrado, con su recuperación y sus copias de seguridad;
- la exportación completa de tus datos.

La sincronización entre equipos no está en la lista: es de pago, con una cuenta en el servicio alojado de OpenWard y un periodo de prueba. No hay sincronización con almacenamiento propio ni servidor autoalojable ([ADR-006](docs/adr/ADR-006-servidor-open-core.md#revisión-del-2026-11-13)).

## Estructura

Hoy, todo el repositorio tiene todos los derechos reservados ([LICENSE](LICENSE)). La última columna es la licencia que tendrá cada parte al lanzar la Community.

| Ruta | Contenido | Licencia al lanzar |
|---|---|---|
| [`core/`](core/) | Núcleo Rust: terminal, SSH, vault, sync | GPL-3.0 |
| [`app/`](app/) | App Flutter de escritorio | GPL-3.0 |
| [`spec/`](spec/) | Formato del vault, protocolo de sync y API | CC-BY-4.0 |
| [`spikes/`](spikes/) | Prototipos de la fase 0; no es código de producto | GPL-3.0 |
| [`docs/`](docs/) | Arquitectura, ADRs, planes de spikes | CC-BY-4.0 |

El servidor de sincronización (a partir de la fase 2) no está en este repositorio: es privado y no se publica. Más detalles en [LICENSING.md](LICENSING.md).

## Desarrollo

Desde un clon recién hecho, `make setup` instala lo que el proyecto fija y dice qué más falta en la máquina:

- **Rust:** la versión de [`core/rust-toolchain.toml`](core/rust-toolchain.toml), con `rustup`.
- **Flutter:** la versión de [`.fvmrc`](.fvmrc), con [FVM](https://fvm.app) (`brew install fvm`); se usa como `fvm flutter …`.
- **Zig 0.16.0**, para el motor del terminal (`libghostty-vt`), que `make setup` compila la primera vez: `brew install zig@0.16`.
- **jq**, **podman** (o docker, para los servidores SSH de prueba) y, en macOS, **Xcode**.
- `cargo-deny`, `cargo-about` y `flutter_rust_bridge_codegen`, que instala `make setup` en sus versiones.

```bash
make setup    # las herramientas y libghostty-vt
make test     # pruebas del núcleo
make lint     # rustfmt + clippy en modo estricto
make ci       # todo lo que mira la CI, aquí, como antes de subir a main
```

La app y sus pruebas, en [`app/README.md`](app/README.md).

## Contribuir y seguridad

- [CONTRIBUTING.md](CONTRIBUTING.md): cómo proponer cambios (DCO).
- [SECURITY.md](SECURITY.md): cómo reportar vulnerabilidades en privado.
