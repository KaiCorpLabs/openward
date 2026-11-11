# Lanzamiento: lo que queda para salir con la Community

- **Estado:** propuesta (2026-11-10). Ordena por prioridad lo que falta hasta lanzar la Community: lo que ya planifican [community.md](community.md) y [v0.4.md](v0.4.md), y lo que deja sin plan su apartado «[Después de este plan](community.md#después-de-este-plan)».
- **Fecha:** 2026-11-10.
- **Base:** el [camino a la Community](community.md) (etapas 2 a 5), la hoja de ruta ([ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas)) y el [modelo de amenazas](../THREAT_MODEL.md).
- **Duración estimada:** unas 18 semanas de los planes que ya existen: 6,5 de la v0.4, 5 de la v0.5, 5 de la v0.6 y 1,5 de la v0.7. Lo propio del lanzamiento (distribución, web y legal) todavía no tiene estimación, y las dos semanas de uso del punto 9 van aparte. La 0.2 y la 0.3 fueron bastante más rápidas que sus planes.

## Objetivo

Lanzar la **Community**, la edición gratuita, en macOS, Windows y Linux:
- con el vault cifrado, la sync con tu almacenamiento y el servidor abierto con las cuentas de KaiCorp Labs, como pide la puerta de salida del [camino a la Community](community.md);
- que se descargue de una web, firmada y con actualizaciones automáticas;
- con lo legal en orden: la licencia, la marca, los términos, la privacidad y la Ley de Ciberresiliencia.

La sync alojada de pago viene después ([prioridad 3](#prioridad-3-para-cobrar)).

## Dónde estamos (2026-11-10)

- **La etapa 1 está hecha** (P0–P7, de la 0.3.4-beta.1 a la beta.3).
- **De la v0.4 están hechos D0–D2**, con sus decisiones aceptadas, y ADR-004 y ADR-005 aceptados.
- **Desde el 2026-11-10, el repositorio tiene todos los derechos reservados** ([ADR-007](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-10)). Al lanzar, el cliente pasa a GPL-3.0 y el servidor sale con AGPL-3.0.
- **No hay ninguna release publicada.** Las 27 del repositorio son borradores. Hoy la app solo llega por el cask `openward` de `kaicorplabs/tap` y por los artefactos de la CI.
- **Lo que sale de la CI:**
  - en macOS, un `.dmg` con firma ad hoc;
  - en Windows, un `.zip` sin firmar;
  - en Linux, un `.tar.gz` para x86_64 y otro para aarch64.
  
  Ninguno se actualiza solo.

## Prioridad 1: sin esto no se lanza

| # | Qué | Semanas | Plan |
|---|---|---|---|
| 1 | Prueba de Touch ID y el Secure Enclave con la app firmada ad hoc | 1 día | [v0.4, riesgos](v0.4.md#riesgos) |
| 2 | Confirmar las 10 decisiones por defecto del camino a la Community | — | [community.md](community.md#decisiones-por-defecto-a-confirmar) |
| 3 | v0.4: el vault cifrado (D3–D8) | 6,5 | [v0.4.md](v0.4.md#hitos) |
| 4 | v0.5: sync con tu almacenamiento (S1–S6) | 5 | [etapa 3](community.md#etapa-3--v05-sync-con-tu-almacenamiento) |
| 5 | v0.6: servidor y cuentas de KaiCorp Labs (C1–C6) | 5 | [etapa 4](community.md#etapa-4--v06-servidor-y-cuentas-de-kaicorp-labs) |
| 6 | v0.7: el servidor en producción (M1–M3) | 1,5 | [etapa 5](community.md#etapa-5--v07-abierto-el-servidor-en-producción) |
| 7 | Distribución: firma, notarización, actualizaciones y paquetes | sin estimar | este documento |
| 8 | La web y la documentación pública | sin estimar | este documento |
| 9 | La prueba final: dos semanas de uso y la guía con hardware | 2 | [community.md](community.md) |
| 10 | Legal: la Ley de Ciberresiliencia | sin estimar | este documento |
| 11 | La licencia del lanzamiento, la marca, la lista «Siempre gratis» y `SECURITY.md` | — | [ADR-007](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-10) |
| 12 | Publicar la primera release | — | — |

### 1 · Touch ID y el Secure Enclave

Va primero porque puede adelantar un gasto. Si el llavero con biometría o las claves del Secure Enclave exigen una app firmada con Developer ID, la cuenta de Apple Developer (unos 99 € al año) hace falta antes de D4, no al final. Si no lo exigen, la firma espera al punto 7.

### 2 · Las decisiones del camino a la Community

Las de la v0.4 y las tres de su modelo de amenazas están aceptadas desde el 2026-11-10. Las diez del plan general siguen «a confirmar». Entre ellas:
- Mosh con el `mosh-client` instalado en el equipo;
- la sync gratuita antes que el servidor;
- las cuentas de KaiCorp Labs;
- la base de datos del servidor, aparte de la de la identidad.

### 3 · v0.4, el vault cifrado

- **D3:** `openward-crypto`, el vault cifrado y la migración desde la 0.3 (1,5 semanas). Antes de D4, se revisan las maquetas del lienzo.
- **D4:** el desbloqueo con contraseña, Touch ID, Windows Hello y el llavero de Linux, el bloqueo automático y las claves en el Secure Enclave (1,5 semanas).
- **D5:** el kit de recuperación, el cambio de contraseña y el paquete de la clave de cuenta (0,5 semanas).
- **D6:** los secretos en el vault, y el historial, los recientes y los registros cifrados (2 semanas). Cierra los tres hallazgos de D0 que siguen abiertos: [AM-4, AM-7 y AM-9](../THREAT_MODEL.md#9-hallazgos-de-d0).
- **D7:** la copia de seguridad y su especificación (0,5 semanas).
- **D8:** Ajustes › Seguridad y la 0.4.0-beta.1 (0,5 semanas).

### 4 · v0.5, sync con tu almacenamiento

El motor `openward-sync`, con la segunda parte de S4 como puerta de ADR-005 (3 dispositivos × 10.000 ediciones convergen al 100 %). Después, los backends de carpeta, S3 y WebDAV, añadir y revocar equipos, y la pantalla de sync.

### 5 · v0.6, servidor y cuentas de KaiCorp Labs

- **C1:** ADR-010, el modelo de amenazas del servidor y la API v1. Decide también si el servidor guarda una copia del paquete de la cuenta que se abra solo con el kit, para recuperar sin contraseña y sin ningún equipo ([THREAT_MODEL §11](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0)).
- **C2–C5:** el servidor en Go, la entrada con OIDC, el relay y la cuenta en la app.
- **C6:** el despliegue en el minipc, solo dentro del tailnet.

### 6 · v0.7, el servidor en producción

- La dirección pública por el túnel de Cloudflare.
- Las copias, la vigilancia y el borrado de los datos de una persona, como en los demás servicios de la casa.
- Los términos y la privacidad, porque entran datos de personas de fuera.

### 7 · Distribución

- **macOS:** firma con Developer ID y notarización. Sin ellas, Gatekeeper avisa o bloquea al abrir la app descargada.
- **Windows:** firma del ejecutable. Sin ella, SmartScreen avisa al abrirlo.
- **Actualizaciones automáticas:** Sparkle en macOS y WinSparkle en Windows. En Linux, las del sistema de paquetes.
- **Paquetes que faltan:**
  - en Linux, Flatpak, AppImage y `.deb`;
  - en Windows, un instalador, winget y Scoop.
  
  El cask de Homebrew ya existe.

### 8 · Web y documentación pública

- El dominio es propio de OpenWard (decidido el 2026-11-10), y es el mismo que usa M1 para el servidor. Hay que comprarlo antes de M1.
- La web, con las descargas de los tres sistemas.
- La documentación de uso, con la guía de prueba como punto de partida.

### 9 · La prueba final

- **Dos semanas** usando OpenWard como único cliente SSH en macOS, Windows y Linux.
- **Los puntos 24 a 30 de la [guía de prueba](prueba-v0.3.md)**, con hardware de verdad:
  - un cable serie;
  - Mosh cambiando de red;
  - una llave FIDO2 en los tres sistemas;
  - un equipo de red con Latin-1 o CP437;
  - el autocompletado con bash, zsh y fish;
  - «Abrir con…» con editores de verdad.

### 10 · La Ley de Ciberresiliencia

El análisis de la Ley de Ciberresiliencia (CRA, Reglamento (UE) 2024/2847). Como OpenWard tendrá plan de pago, lo más probable es que entre en ella.
- La obligación de notificar las vulnerabilidades explotadas aplica desde el 11 de septiembre de 2026.
- El resto aplica desde el 11 de diciembre de 2027.

El análisis dice qué aplica a la Community y qué al plan de pago. Va con los términos y la privacidad de M3.

### 11 · Licencia, marca, «Siempre gratis» y `SECURITY.md`

- **La marca:** registrar «OpenWard» (OEPM o EUIPO). Cuanto antes, porque la fecha de la solicitud es la que cuenta.
- **La licencia del lanzamiento:** hasta entonces, todos los derechos reservados. Al publicar, el cliente pasa a GPL-3.0 y el servidor sale con AGPL-3.0, con el bot de la CLA para todo el repositorio y la revisión legal de LICENSE y de la CLA.
- **La lista «Siempre gratis»** del README es un borrador, y lo que diga queda como promesa pública desde el lanzamiento.
- **`SECURITY.md` ya existe**, con el reporte privado de GitHub. Se repasa que los plazos sigan siendo realistas con usuarios de fuera.

### 12 · Publicar la primera release

Publicarla es una decisión aparte, como hasta ahora. Antes, se decide qué hacer con los borradores viejos.

## Orden

- Del 1 al 6 se va en orden, porque cada etapa usa lo que deja la anterior.
- **El 7, el 8, el 10 y el 11 no tocan el núcleo** y pueden ir en paralelo con la v0.5 y la v0.6:
  - la firma de macOS, en cuanto el punto 1 diga si hace falta antes;
  - las actualizaciones automáticas, antes de la primera beta con gente de fuera, para que las correcciones les lleguen solas;
  - comprar el dominio, antes de M1;
  - registrar la marca, lo antes posible;
  - lo legal, antes de M3.
- El 9 y el 12 cierran.

## Prioridad 2: conviene tenerlo el día del lanzamiento

- **Informes de fallos con consentimiento y un canal de opiniones.** Cuando la use gente de fuera, sin ellos no se sabrá qué falla.

## Prioridad 3: para cobrar

- **El plan de pago de la sync alojada** y el cobro, en el repositorio privado `openward-cloud`.
- **Una auditoría externa del cifrado y la sync** antes de cobrar por ella. Es la puerta de la fase 2 en [ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas).

## Después del lanzamiento

- **Android e iOS.** Antes, el spike S1.2: el motor de terminal en dispositivos reales, la condición pendiente de [ADR-002](../adr/ADR-002-motor-de-terminal.md).
- **Git como backend**, el agente SSH, la CLI `ow` y cuentas propias para el servidor autoalojado.
- **Mosh en Windows**, con el cliente clean-room de [ADR-009](../adr/ADR-009-mosh-clean-room.md).
- **La fase 3:** equipos, plan Team, IA con tu propia clave ([ADR-008](../adr/ADR-008-ia-mcp-y-byok.md)) y MCP.

## Lo que hay que decidir o hacer a mano

- **Gastos:** la cuenta de Apple Developer, el certificado de firma de Windows, el dominio y el registro de la marca.
- **Decisiones:**
  - las diez del camino a la Community (punto 2);
  - publicar cada release.
- **Trámites:** registrar la marca y comprar el dominio (puntos 8 y 11).
- **Pruebas:** las de hardware y las dos semanas de uso (punto 9).
- **Legal:** revisar LICENSE, la CLA, los términos, la privacidad y el análisis de la CRA.

## Fuera de la ruta

- [RustCrypto/SSH#620](https://github.com/RustCrypto/SSH/issues/620) está resuelto desde el 2026-11-10 por la [PR #623](https://github.com/RustCrypto/SSH/pull/623). Falta una versión publicada con el arreglo y compatible con `russh`: comprobado el 2026-11-11, `ssh-key` llega hasta `0.7.0-rc.12` (anterior al arreglo) y `russh` 0.64.1 y 0.65.1 fijan la `rc.11`. Hasta entonces se conserva `openward-ssh::keyfile`, con el mínimo de 24 bytes de magnitud aplicado también a claves con ceros iniciales y cifradas. Al actualizar, cambiar también las dependencias directas de `openward-app` y `openward-fido`, retirar el relleno local y mantener las pruebas de claves cortas y del mínimo ([ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md)).
