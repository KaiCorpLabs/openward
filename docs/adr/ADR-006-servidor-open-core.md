# ADR-006 — Servidor Go open-core por fases

- **Estado:** aceptado (2026-10-08). La licencia concreta de `ee/` se decide en la fase 4.
- **Fecha:** 2026-10-08.
- **Alcance:** servidor (relay, equipos y enterprise), persistencia y frontera entre la edición libre y la de pago.

## Contexto

El servidor solo hace falta para lo que se cobra: sync alojada, tiempo real y push, equipos con control de escritura y revocación, SSO y SCIM, auditoría central y grabaciones. Todo lo individual funciona sin servidor ([ARCHITECTURE §6](../ARCHITECTURE.md#6-sincronización)).

Partimos de cuatro observaciones:

- **Poder autoalojar es lo que más piden** los usuarios técnicos de clientes SSH.
- **Esconder el código del servidor protege poco:** el protocolo es público y la comunidad escribe servidores compatibles (Vaultwarden, Headscale).
- **Lo que las empresas pagan** es el proveedor (soporte, auditorías, responsabilidad) y el derecho legal a usar las funciones enterprise, no el acceso al código.
- **Lo que provoca forks y rechazo es recortar lo que ya era gratis** (Teleport, HashiCorp, Redis, Mattermost), no cobrar por funciones nuevas.

## Decisión

**Open core en el que la separación es legal, no secreta, y se introduce por fases:**

1. **Fases 2 y 3: todo el servidor es AGPL-3.0.**
   - Módulos `identity`, `vaults`, `objects`, `realtime`, `push` y `admin`;
   - sync, vaults de equipo con roles, invitaciones, **OIDC** y auditoría de eventos del servidor.
   - Los ingresos vienen del **servicio alojado** (OpenWard Cloud: Sync y Team).
2. **CLA en `server/` desde el primer commit.** Mantiene abierta la opción de vender licencias comerciales sin chocar con contribuciones de terceros ([ADR-007](ADR-007-licencias-y-contribuciones.md)).
3. **Fase 4: aparece `server/ee/`**, solo con **funciones nuevas** que nunca fueron gratis: SAML, SCIM, políticas gestionadas, exportación a SIEM, grabaciones con retención y consola de organización.
   - Se compila solo con `-tags ee`. En autoalojado se activa con una licencia firmada (Ed25519) que se verifica sin conexión.
   - **La licencia de `ee/` se decide entonces con datos:**
     - **comercial**, si hay empresas pidiéndolas para autoalojar;
     - **FSL** (código visible que pasa a Apache a los 2 años), si pesa más la auditabilidad;
     - **AGPL** (todo abierto), si nadie las pide para autoalojar.
4. **Facturación, alta de clientes, infraestructura y antiabuso** del servicio alojado viven en un repositorio privado (`openward-cloud`) que importa el servidor como librería. No es producto distribuible.
5. **Persistencia:** interfaz `Store` con SQLite (`modernc.org/sqlite`, binario único para autoalojar) y Postgres (servicio alojado). Objetos en disco o en S3/R2. `sqlc` y migraciones por dialecto, ambas en CI.
6. **Consola de organización** (fase 4) con Go + templ + htmx dentro del binario. Las operaciones que necesitan claves (alta de miembros, rotación) se hacen desde la app de escritorio, porque el servidor no tiene claves.

**Regla permanente:** nada que haya estado en el servidor AGPL pasa nunca a `ee/`. La frontera solo se mueve hacia más apertura.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| Servidor de coordinación cerrado con clientes abiertos | Parece proteger el negocio | Pierde "autoalojable", que es el motor de crecimiento; no protege, porque el protocolo es público y saldría un servidor compatible |
| Todo AGPL para siempre (modelo Plausible) | Máxima confianza y simplicidad | Válido. Se mantiene como resultado posible de la fase 4 si ninguna empresa pide funciones enterprise para autoalojar |
| `ee/` desde el principio | Frontera clara desde el día 1 | Decisión prematura, sin datos de demanda; complica las fases 2 y 3 sin ingresos que lo justifiquen |
| Equipos solo de pago (también al autoalojar) | Más ingresos por asiento | Se percibe como límite artificial; Vaultwarden demostró que la comunidad lo reimplementa |
| Consola en Next.js aparte | Stack conocido | Segundo despliegue; rompe el binario único |

## Consecuencias

- En las fases 2 y 3 una empresa puede autoalojar sync y equipos sin pagar. Lo aceptamos: es el motor de adopción, y la mayoría de equipos pequeños preferirá el servicio alojado.
- Alguien puede reimplementar las funciones enterprise en un servidor compatible. Ninguna licencia lo impide. La defensa es ser el proveedor de confianza: auditorías, certificaciones, soporte y velocidad.
- La CLA añade un poco de fricción a quien contribuye al servidor; se explica en CONTRIBUTING.
- Desde la fase 4 hay que mantener dos dialectos SQL y vigilar que nada de `ee/` se filtre a la build OSS: en CI, comprobación de imports y pruebas con y sin el tag.

## Validación y revisión

Al entrar en la fase 4, decidir la licencia de `ee/` con: número de solicitudes de empresas que quieren autoalojar, ingresos del servicio alojado y conversaciones con los primeros clientes Team. Reabrir solo hacia más apertura, nunca recortando lo que ya era AGPL.
