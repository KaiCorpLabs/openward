# ADR-006 — Servidor Go open-core por fases

- **Estado:** aceptado (2026-10-08), [revisado el 2026-11-13](#revisión-del-2026-11-13): el servidor pasa a ser privado, sin autoalojamiento, y toda la sincronización es de pago y alojada. Esa revisión deja sin efecto lo que el texto de abajo dice del servidor AGPL y autoalojable, confirmado por última vez el 2026-11-10. El servicio alojado va en un dominio propio de OpenWard. Hasta el lanzamiento, el repositorio tiene todos los derechos reservados ([ADR-007](ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-10)).
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

## Revisión del 2026-11-13

El texto de arriba era el plan del 2026-10-08, confirmado el 2026-11-10. Esta revisión cambia la frontera entre lo gratuito y lo de pago.

**Decisión:**
- **Toda la sincronización es de pago y alojada.** Sincronizar pide una cuenta y el servicio alojado de OpenWard. No hay sincronización con el almacenamiento del usuario (carpeta, S3, WebDAV, Git) ni servidor autoalojable.
- **La edición gratuita, la Community, es el cliente completo funcionando en local.** La app sigue sin pedir cuenta: todo lo que no es sincronizar funciona sin registrarse y sin servidor.
- **La cuenta es gratuita** y trae un periodo de prueba de la sync. Después, sincronizar pide el plan de pago. La duración de la prueba está por decidir.
- **El servidor es privado.** No se publica al lanzar ni sale con AGPL-3.0, y su código no vive en este repositorio.
- **Quedan sin efecto** los puntos 1 (todo el servidor con AGPL-3.0), 2 (la CLA de `server/`, que ya no recibe contribuciones de fuera) y la parte del 5 que mantenía SQLite para autoalojar con un único binario. C1 del [camino a la Community](../plan/community.md#etapa-4--v06-servidor-y-cuentas-de-kaicorp-labs) decide si el `Store` en SQLite se conserva para las pruebas.
- **La fase 4** (`ee/` y las licencias para que una empresa autoaloje) se decide al llegar a ella, con los mismos datos que pide «Validación y revisión». No se promete.

**Por qué:**
- **La sync es lo único que se cobra a una persona.** Si existiera la misma función gratis, con el almacenamiento propio o con un servidor autoalojado, no habría nada que cobrar. A cambio, la Community da todo lo demás.
- **El servidor está por escribir.** No se recorta nada publicado, y la lista «Siempre gratis» era un borrador que entra en vigor con el lanzamiento ([ADR-007](ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-13)). Abrir después siempre se puede; cerrar después, no.
- **La confianza en el servicio no depende de leer el código del servidor.** El cliente es open source y el cifrado es de extremo a extremo: el servidor solo recibe sobres cifrados y firmados, y eso se comprueba en el cliente.
- **Va contra «reabrir solo hacia más apertura»**, como la revisión del 2026-11-10 de ADR-007, y por la misma razón: es antes del lanzamiento y sin nada publicado. Desde el lanzamiento, la regla vale: lo que salga abierto no se cierra.

**Consecuencias:**
- Es la alternativa «servidor de coordinación cerrado con clientes abiertos» de la tabla de arriba, con sus inconvenientes. Las observaciones del contexto siguen siendo ciertas: poder autoalojar es lo que más piden los usuarios técnicos, y con el cliente abierto y el formato en `spec/` alguien puede escribir un servidor compatible. Ninguna licencia lo impide; la defensa sigue siendo el servicio.
- **Un solo backend que construir, probar y atender.** Desaparecen los backends de almacenamiento propio y sus casos difíciles (copias con retraso, archivos «en conflicto»), y el empaquetado del servidor para terceros ([ADR-005](ADR-005-sync-por-registros-de-dispositivo.md#revisión-del-2026-11-13)).
- **Sin plan de pago no hay sync.** Para llevar los datos de un equipo a otro quedan la copia de seguridad y la exportación completa, que son del cliente.
- Los equipos (vaults compartidos, roles, invitaciones y OIDC) dejan de tener una vía gratuita por el servidor autoalojado: son del plan Team alojado de la fase 3.
- No cambia el resto: el monolito modular en Go y sus módulos, el servidor que no ve nunca el contenido, y la facturación y la infraestructura en `openward-cloud`.
- Cambian con esta revisión [ADR-007](ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-13), [LICENSING](../../LICENSING.md), el README (la lista «Siempre gratis» y la estructura), [ARCHITECTURE](../ARCHITECTURE.md) (§6.2, §7 y §12), el [camino a la Community](../plan/community.md) y el [plan de lanzamiento](../plan/lanzamiento.md).
