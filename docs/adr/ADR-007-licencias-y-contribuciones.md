# ADR-007 — Licencias por componente y régimen de contribuciones

- **Estado:** aceptado (2026-10-08), [revisado el 2026-11-10](#revisión-del-2026-11-10): todos los derechos reservados hasta el lanzamiento de la Community; desde entonces, el cliente con GPL-3.0 y la CLA en todo el repositorio. [Revisado el 2026-11-13](#revisión-del-2026-11-13): el servidor es privado y no sale con AGPL-3.0, y la sync deja la lista «Siempre gratis» ([ADR-006](ADR-006-servidor-open-core.md#revisión-del-2026-11-13)).
- **Fecha:** 2026-10-08.
- **Alcance:** licencia de cada directorio, CLA/DCO y promesa pública.

## Contexto

Queremos la máxima adopción del cliente, evitar que alguien aloje nuestro servidor como competencia sin aportar, y poder vender EE. Hay limitaciones prácticas:

- SignPath firma gratis en Windows solo builds sin componentes propietarios.
- Muchas empresas prohíben AGPL en software que instalan en los puestos de trabajo.
- Si el servidor AGPL recibe contribuciones sin CLA, no podemos combinarlo con `ee/` bajo licencia comercial.

## Decisión

| Componente | Licencia | Contribuciones |
|---|---|---|
| `core/`, `app/` (cliente completo), `spikes/` | **Apache-2.0** | DCO |
| `server/` (todo el servidor en las fases 2 y 3) | **AGPL-3.0** | **CLA desde el primer commit** (licencia de derechos amplia, sin cesión de copyright) |
| `server/ee/` (aparece en la fase 4, solo funciones nuevas) | Por decidir con datos: comercial, FSL o AGPL | Solo el equipo |
| `openward-cloud` (repositorio privado) | Privado | Cobros, alta de clientes, infraestructura y antiabuso; no es producto distribuible |
| `spec/`, `docs/` | CC-BY-4.0 | DCO |
| Marca "OpenWard" y logotipos | Política de marca (los forks deben renombrarse) | — |

**Promesa pública "siempre gratis"**, publicada en la v0.1: cliente completo, sync con almacenamiento propio, relay autoalojado, vaults de equipo básicos, OIDC, exportación completa. **No se recortará nunca**; solo puede crecer.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| AGPL en todo el stack | Protege contra que alguien reempaquete el cliente | Freno a la adopción en empresas; la AGPL por sí sola no evita la competencia en servicios alojados |
| MIT en todo | Máxima simplicidad | Permite alojar el relay como competencia sin aportar nada |
| BSL o FSL en todo | Protección comercial | No es open source según la OSI; daño de reputación en una comunidad sensible a las licencias |
| CLA en todo el repositorio | Flexibilidad total | Frena a contribuidores casuales del cliente, que es donde más contribuciones llegarán |

**Dependencias:** `cargo-deny` y `go-licenses` en CI, con una lista permitida (Apache-2.0, MIT, BSD, ISC, Zlib, Unicode y MPL-2.0).

- **MPL-2.0** (copyleft a nivel de archivo, compatible con distribuir bajo Apache) se acepta con inventario. Afecta a `hpke-rs` y `serialport`.
- **GPL y AGPL están prohibidas en el cliente:** no se puede enlazar mosh ni `mosh-rs` ([ADR-009](ADR-009-mosh-clean-room.md)).

## Consecuencias

Hay que mantener un bot de CLA solo para `server/` y explicar en CONTRIBUTING por qué. Un tercero puede bifurcar el cliente Apache y venderlo con otro nombre; lo aceptamos, porque el valor de pago está en el servicio y la marca.

## Validación y revisión

Revisión legal de la CLA antes del primer commit de `server/` (fase 2), y de la licencia de `ee/` al entrar en la fase 4. Reabrir solo para abrir más (por ejemplo, EE en FSL), nunca para cerrar.

## Revisión del 2026-11-10

La tabla de arriba era el plan del 2026-10-08. Esta revisión la cambia.

**Decisión:**
- **Hasta el lanzamiento de la Community, todo el repositorio tiene todos los derechos reservados** ([LICENSE](../../LICENSE)).
  - Solo se permite ver el código y bifurcarlo dentro de GitHub, como permiten sus Términos de servicio, y usar las versiones compiladas que publicamos.
  - Se reserva también la minería de textos y datos (artículo 4.3 de la Directiva (UE) 2019/790): nada del repositorio se puede usar para entrenar modelos de IA.
  - No se aceptan contribuciones de código de fuera.
- **Al lanzar:**

  | Componente | Licencia | Contribuciones |
  |---|---|---|
  | `core/`, `app/`, `spikes/` (el cliente) | **GPL-3.0-only**, en vez de Apache-2.0 | CLA |
  | `server/` | **AGPL-3.0-only**, autoalojable como dice [ADR-006](ADR-006-servidor-open-core.md) | CLA |
  | `spec/`, `docs/` | CC-BY-4.0, para que se puedan escribir clientes compatibles ([ADR-005](ADR-005-sync-por-registros-de-dispositivo.md)) | CLA |

- **CLA en todo el repositorio**, no solo en `server/`. Con ella se puede ofrecer el cliente también con otra licencia (la App Store no admite la GPL de terceros) y el servidor con licencia comercial.
- **GPL y AGPL siguen prohibidas en las dependencias del cliente** por esa misma razón: los derechos de todo su código tienen que ser nuestros.
- **La marca «OpenWard» se registra** (OEPM o EUIPO) antes del lanzamiento. La licencia no protege el nombre; la marca registrada permite retirar de las tiendas una copia que lo use.

**Por qué:**
- **Apache-2.0 deja cerrar una copia del cliente,** ponerle otro nombre y venderla, también con una sync de pago propia. La GPL-3.0 no impide copiar, pero sí cerrar: quien distribuya una copia tiene que publicar todo su código con la misma licencia. El cliente sigue siendo open source y auditable, que en una app de credenciales es un argumento de venta.
- **GPL y no AGPL en el cliente**, porque muchas empresas no permiten software AGPL en sus equipos y son las que van a pagar.
- **Todos los derechos reservados hasta el lanzamiento**, porque lo más valioso (el vault cifrado, la sync y el servidor) está por escribir. Abrir después siempre se puede; cerrar después, no.
- **Rompe a propósito la regla de abajo** («reabrir solo para abrir más»), y solo esta vez. El repositorio llevaba cuatro días público, con dos visitas, y nadie más había contribuido. Desde el lanzamiento, la regla vuelve a valer.

**Consecuencias:**
- Lo publicado hasta el commit `945fbbe` (2026-11-10) salió con Apache-2.0, y esa licencia sigue valiendo para quien tenga esas copias.
- La promesa «Siempre gratis» vale desde el lanzamiento, no desde ya. El README lo dice.
- Antes de abrir las contribuciones: el bot de la CLA para todo el repositorio, y la revisión legal de la CLA (ya prevista) y de LICENSE.
- SignPath firma gratis solo builds con licencia OSI y sin componentes propietarios: sirve desde el lanzamiento, con la GPL. Las betas de antes siguen sin firmar o con una firma de pago.
- `cargo-deny` y `cargo-about` no comprueban los crates propios, que no se publican (`[licenses.private]` en `core/deny.toml` y `private` en `core/about.toml`).

## Revisión del 2026-11-13

La revisión del 2026-11-10 mantenía el servidor con AGPL-3.0 y autoalojable. La [revisión del 2026-11-13 de ADR-006](ADR-006-servidor-open-core.md#revisión-del-2026-11-13) lo cambia: toda la sincronización es de pago y alojada, y el servidor es privado.

**Decisión:**
- **Al lanzar:**

  | Componente | Licencia | Contribuciones |
  |---|---|---|
  | `core/`, `app/`, `spikes/` (el cliente) | **GPL-3.0-only**, como en la revisión del 2026-11-10 | CLA |
  | `spec/`, `docs/` | CC-BY-4.0 | CLA |
  | El servidor | **Privado**, en vez de AGPL-3.0-only: no se publica ni se distribuye, y no está en este repositorio | Solo el equipo |

- **La promesa «Siempre gratis»** queda así: la app completa en todas las plataformas, funcionando en local y sin cuenta, con el vault cifrado, su recuperación y sus copias de seguridad; y la exportación completa de los datos. Salen de la lista la sync con almacenamiento propio, el relay autoalojado, y los vaults de equipo básicos y el OIDC que llegaban con él.
- **No cambia** lo demás de la revisión del 2026-11-10: todos los derechos reservados hasta el lanzamiento, la CLA en todo el repositorio, GPL y AGPL prohibidas en las dependencias del cliente, y el registro de la marca.

**Por qué:**
- La sync es lo que se cobra, así que no puede estar también en la lista de lo gratuito, ni con un servidor que cualquiera pueda alojar ([ADR-006](ADR-006-servidor-open-core.md#revisión-del-2026-11-13)).
- **Es la segunda vez que se va contra «reabrir solo para abrir más»**, y la revisión del 2026-11-10 decía «solo esta vez». Sigue siendo antes del lanzamiento: el servidor no existe, y la promesa «Siempre gratis» no ha entrado en vigor. Desde el lanzamiento, la regla vale.

**Consecuencias:**
- La CLA ya no hace falta para vender el servidor con licencia comercial. Sigue en todo el repositorio para poder ofrecer el cliente también con otra licencia, como pide la App Store.
- SignPath sigue valiendo para el cliente: lleva una licencia OSI y no incluye componentes propietarios.
- Cambian con esta revisión [LICENSING](../../LICENSING.md), y la lista «Siempre gratis» y la tabla de estructura del README.

