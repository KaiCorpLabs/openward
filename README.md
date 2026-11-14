# OpenWard

**Cliente SSH local-first y con sincronización cifrada de extremo a extremo, para Windows, macOS, Linux, iOS y Android.**

> [!IMPORTANT]
> **Todos los derechos reservados.** El código se puede leer aquí, pero no copiar, modificar, redistribuir ni usar en otros productos: ver [LICENSE](LICENSE). El cliente será open source cuando se lance la Community ([LICENSING.md](LICENSING.md)).

> [!WARNING]
> Estado revisado el **2026-11-14**: `main 553ab147` integra el vault cifrado v0.4 y la base Android/iOS. No hay release pública; cuenta/sync/pago alojados siguen pendientes de integración y validación. Hardware, firma y auditoría conservan sus puertas en el [estado verificable](docs/plan/estado.md).

## Principios

- **Sin cuenta obligatoria.** La app funciona entera en tu equipo sin registrarse ni conectarse a ningún servidor. La cuenta solo hace falta para sincronizar.
- **Tus datos, en formato abierto.** Hosts, claves, snippets y túneles se exportan completos a un formato documentado en [`spec/`](spec/).
- **Cifrado de extremo a extremo.** Nuestro servidor no ve hosts, usuarios, claves ni comandos.
- **Solo se paga por sincronizar.** La sincronización entre equipos es opcional y es el servicio de pago: va con una cuenta gratuita. Precio confirmado: **4,99 €/mes o 49 €/año, 14 días sin tarjeta**; todavía sin cobros activos. Todo lo demás es gratis.
- **Recuperación primero.** Cambiar o perder la contraseña nunca borra el vault en silencio.
- **Sin telemetría por defecto.**

## Estado y hoja de ruta

| Fase | Contenido | Estado |
|---|---|---|
| 0 · Spikes | Motor de terminal, SSH en las 5 plataformas, firma con hardware, formato de sync | Escritorio hecho ([S1 terminal](docs/spikes/S1-terminal.md), S2 SSH); móvil y sync, con la fase 2 |
| 1 · MVP local | Cliente completo en escritorio, sin cuenta | Funcionalidad de la [etapa 1](docs/plan/community.md#etapa-1--lo-básico-completo) implementada; quedan las pruebas manuales de hardware y uso prolongado |
| 2 · Vault y sync | Cifrado, recuperación, sync alojada de pago y Android/iOS | Vault y base móvil integrados; puertas físicas/personales abiertas. Motor/Go/cuenta/pago en copias locales sin publicar; [plan de beta](docs/plan/lanzamiento.md) |
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
| [`app/`](app/) | App Flutter de escritorio, Android e iOS | GPL-3.0 |
| [`spec/`](spec/) | Formato del vault, protocolo de sync y API | CC-BY-4.0 |
| [`spikes/`](spikes/) | Prototipos de la fase 0; no es código de producto | GPL-3.0 |
| [`docs/`](docs/) | Arquitectura, ADRs, planes de spikes | CC-BY-4.0 |

La dirección vigente es un **monorepo Flutter/Rust/Go mínimo con Supabase gestionado** ([ADR-010](docs/adr/ADR-010-monorepo-go-supabase.md)). El Go de las copias de trabajo aún no está integrado en main; su licencia/publicación requieren conciliación antes de publicar código. La licencia actual no cambia ([LICENSING.md](LICENSING.md)).

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
