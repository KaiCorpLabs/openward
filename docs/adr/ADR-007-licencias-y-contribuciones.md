# ADR-007 — Licencias por componente y régimen de contribuciones

- **Estado:** aceptado (2026-10-08). La licencia de `server/ee/` queda pendiente hasta la fase 4 ([ADR-006](ADR-006-servidor-open-core.md)).
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
