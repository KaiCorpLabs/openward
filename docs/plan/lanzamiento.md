# Lanzamiento: lo que queda para salir con la Community

- **Estado:** propuesta (2026-11-10), revisada el 2026-11-13: toda la sync es de pago y alojada, el servidor es privado, y Android e iOS van antes de cobrar ([decisiones](community.md#decisiones-del-2026-11-13)). Ordena por prioridad lo que falta hasta lanzar la Community: lo que ya planifican [community.md](community.md) y [v0.4.md](v0.4.md), y lo que deja sin plan su apartado «[Después de este plan](community.md#después-de-este-plan)».
- **Fecha:** 2026-11-10.
- **Base:** el [camino a la Community](community.md) (etapas 2 a 5), la hoja de ruta ([ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas)) y el [modelo de amenazas](../THREAT_MODEL.md).
- **Estimación original (2026-11-10):** unas 18 semanas: 6,5 de la v0.4, 5 de la v0.5, 5 de la v0.6 y 1,5 de la v0.7. Es una referencia histórica, no trabajo restante ni una fecha comprometida; D3–D8 han avanzado como se detalla abajo. El 2026-11-13 la v0.5 bajó de 5 a 3,5 al quedarse sin los backends de almacenamiento propio. Distribución, web y legal siguen sin estimación, y las dos semanas de uso del punto 9 van aparte.

## Objetivo

Lanzar la **Community**, la edición gratuita, en macOS, Windows y Linux:
- con el cliente completo funcionando en local y sin cuenta, y el vault cifrado;
- con el servidor abierto a las cuentas de KaiCorp Labs, como pide la puerta de salida del [camino a la Community](community.md). La sync no es parte de la Community: es el servicio de pago, y hasta que se pueda cobrar funciona en periodo de prueba;
- que se descargue de una web, firmada y con actualizaciones automáticas;
- con lo legal en orden: la licencia, la marca, los términos, la privacidad y la Ley de Ciberresiliencia.

Cobrar por la sync viene después, con Android e iOS ([prioridad 3](#prioridad-3-para-cobrar)).

## Dónde estamos (2026-11-13)

- **Etapa 1 implementada** (P0–P7); hardware y uso real siguen abiertos en [#42](https://github.com/KaiCorpLabs/openward/issues/42).
- **v0.4:** D0–D3 y D5–D7 completados; sesión y backends D4, onboarding y Ajustes D8 integrados. Candidata `0.4.0-beta.1+31` en `main`, sin etiqueta ni release de 0.4. La KDF cumple 500–1000 ms en la CI release de los tres sistemas ([#58](https://github.com/KaiCorpLabs/openward/pull/58), [evidencia](../evidence/kdf-calibration-v0.4.md)).
- **Pendiente para cerrar v0.4:** maquetas originales y autenticación física, incluida la firma SSH con claves no exportables en Secure Enclave ([#33](https://github.com/KaiCorpLabs/openward/issues/33)); migraciones personales, una semana de uso cifrado y recuperación independiente ([#37](https://github.com/KaiCorpLabs/openward/issues/37)). No se ha modificado el vault personal durante esta preparación.
- **v0.5–v0.7:** motor de sync, servidor/cuentas y operación pública pendientes en [#38](https://github.com/KaiCorpLabs/openward/issues/38), [#39](https://github.com/KaiCorpLabs/openward/issues/39) y [#40](https://github.com/KaiCorpLabs/openward/issues/40).
- **Desde el 2026-11-10, el repositorio tiene todos los derechos reservados** ([ADR-007](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-10)). El plan de lanzamiento prevé el cliente con GPL-3.0; el servidor es privado desde la [revisión del 2026-11-13](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-13). La revisión legal sigue en #42.
- **Distribución:** ninguna release pública; 28 borradores a fecha de esta revisión. Última etiqueta/borrador `v0.3.4-beta.4` en `5736b7c`, con macOS universal, Windows x64 y Linux x86_64/aarch64, checksums y procedencia. El [cask](https://github.com/KaiCorpLabs/homebrew-tap/blob/main/Casks/openward.rb) sigue en `0.3.4-beta.3`; el código candidato 0.4 se obtiene de los artefactos de CI. Firma, actualizaciones y paquetes siguen en [#41](https://github.com/KaiCorpLabs/openward/issues/41).
- **CI habitual:** `.dmg` macOS universal con firma ad hoc, `.zip` Windows x64 sin firmar y `.tar.gz` Linux x86_64; Linux aarch64 tiene su flujo de contenedor aparte. Ninguno se actualiza solo. Las pruebas automatizadas no cierran las puertas humanas.

## Prioridad 1: sin esto no se lanza

| # | Qué | Semanas | Plan |
|---|---|---|---|
| 1 | Prueba de Touch ID y el Secure Enclave con la app firmada ad hoc | 1 día | [v0.4, riesgos](v0.4.md#riesgos) |
| 2 | Confirmar las 10 decisiones por defecto del camino a la Community | — | [community.md](community.md#decisiones-por-defecto-a-confirmar) |
| 3 | Cerrar v0.4: puertas restantes de #33 y #37 | pendiente de evidencia | [v0.4.md](v0.4.md#hitos) |
| 4 | v0.5: el motor de sync (S1 y S4–S6) | 3,5 | [etapa 3](community.md#etapa-3--v05-el-motor-de-sync) |
| 5 | v0.6: servidor y cuentas de KaiCorp Labs (C1–C6) | 5 | [etapa 4](community.md#etapa-4--v06-servidor-y-cuentas-de-kaicorp-labs) |
| 6 | v0.7: el servidor en producción (M1–M3) | 1,5 | [etapa 5](community.md#etapa-5--v07-abierto-el-servidor-en-producción) |
| 7 | Distribución: firma, notarización, actualizaciones y paquetes | sin estimar | este documento |
| 8 | La web y la documentación pública | sin estimar | este documento |
| 9 | La prueba final: dos semanas de uso y la guía con hardware | 2 | [community.md](community.md) |
| 10 | Legal: la Ley de Ciberresiliencia | sin estimar | este documento |
| 11 | La licencia del lanzamiento, la marca, la lista «Siempre gratis» y `SECURITY.md` | — | [ADR-007](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-10) |
| 12 | Publicar la primera release | — | — |

### 1 · Touch ID y el Secure Enclave

Sigue siendo una puerta de #33 porque puede adelantar la necesidad de Developer ID. La sonda ad hoc creó una clave efímera no exportable, pero Touch ID devolvió `SystemCancel` (-4): no valida autenticación física. La firma SSH P-256 está ahora implementada ([contrato y pruebas](../../spec/secure-enclave-ssh-v1.md)); falta comprobarla en el bundle real. Registrar el resultado con el bundle real antes de decidir certificados o compras.

### 2 · Las decisiones del camino a la Community

Las de la v0.4 y las tres de su modelo de amenazas están aceptadas desde el 2026-11-10. Las diez del plan general siguen «a confirmar». Entre ellas:
- Mosh con el `mosh-client` instalado en el equipo;
- el motor de sync antes que el servidor;
- las cuentas de KaiCorp Labs;
- la base de datos del servidor, aparte de la de la identidad.

Lo que cambia el modelo ya está decidido, el 2026-11-13: toda la sync de pago y alojada, el servidor privado, la cuenta gratuita con un periodo de prueba, y Android e iOS antes de cobrar ([community.md](community.md#decisiones-del-2026-11-13)).

### 3 · v0.4, el vault cifrado

- **D3:** `openward-crypto`, jerarquía y migración implementados y [#32](https://github.com/KaiCorpLabs/openward/issues/32) cerrado. [Formato y pruebas](../../spec/vault-sqlite-v2.md). Las maquetas originales siguen pendientes en #33.
- **D4:** sesión con contraseña, bloqueo y backends de Touch ID/Windows Hello/llavero Linux implementados en [#53](https://github.com/KaiCorpLabs/openward/pull/53). La firma SSH P-256 no exportable está implementada con Touch ID y referencias públicas en el vault ([contrato y límites](../../spec/secure-enclave-ssh-v1.md)); #33 conserva las maquetas y pruebas físicas.
- **D5:** el kit de recuperación, el cambio de contraseña y el paquete de la clave de cuenta (0,5 semanas). Implementado en [#54](https://github.com/KaiCorpLabs/openward/pull/54); [formato, pruebas de recuperación y límites](../../spec/recovery-v1.md).
- **D6:** los secretos en el vault, y el historial, los recientes y los registros cifrados (2 semanas). Implementado con guardado explícito, migración y barrera de formato3 ([contrato, pruebas y límites](../../spec/protected-local-v1.md)). Completa las mitigaciones de [AM-4, AM-7 y AM-9](../THREAT_MODEL.md#9-hallazgos-de-d0).
- **D7:** implementada la copia de seguridad `.owvault`/JSON y su restauración en un vault vacío con identidad propia (0,5 semanas). [Contrato, pruebas y guía de recuperación](../../spec/vault-backup-v1.md).
- **D8:** onboarding, Ajustes › Seguridad, notas y candidata `0.4.0-beta.1+31` integrados en [#57](https://github.com/KaiCorpLabs/openward/pull/57); KDF corregida y validada en #58. [#37](https://github.com/KaiCorpLabs/openward/issues/37) conserva las puertas personales de migración, uso y recuperación. No hay publicación de 0.4.

### 4 · v0.5, el motor de sync

El motor `openward-sync`, con la segunda parte de S4 como puerta de ADR-005 (3 dispositivos × 10.000 ediciones convergen al 100 %), contra un backend de pruebas. Después, añadir y revocar equipos, y la pantalla de sync. Desde el 2026-11-13 no trae backends de carpeta, S3 ni WebDAV: el único backend es el servidor de la v0.6 ([ADR-005](../adr/ADR-005-sync-por-registros-de-dispositivo.md#revisión-del-2026-11-13)).

### 5 · v0.6, servidor y cuentas de KaiCorp Labs

- **C1:** ADR-010, el modelo de amenazas del servidor y la API v1. Decide también si el servidor guarda una copia del paquete de la cuenta que se abra solo con el kit, para recuperar sin contraseña y sin ningún equipo ([THREAT_MODEL §11](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0)).
- **C2–C5:** el servidor en Go, la entrada con OIDC, el relay y la cuenta en la app. El servidor es privado y no se autoaloja ([ADR-006](../adr/ADR-006-servidor-open-core.md#revisión-del-2026-11-13)).
- **C6:** el despliegue en el minipc, solo dentro del tailnet.

### 6 · v0.7, el servidor en producción

- La dirección pública por el túnel de Cloudflare.
- Las copias, la vigilancia y el borrado de los datos de una persona, como en los demás servicios de la casa.
- Los términos y la privacidad, porque entran datos de personas de fuera.
- Quien entra sincroniza en su periodo de prueba: el plan de pago llega con la [prioridad 3](#prioridad-3-para-cobrar).

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
- **La licencia del lanzamiento:** hasta entonces, todos los derechos reservados. Al publicar, el cliente pasa a GPL-3.0, con el bot de la CLA para todo el repositorio y la revisión legal de LICENSE y de la CLA. El servidor no se publica: es privado ([ADR-007](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-13)).
- **La lista «Siempre gratis»** del README es un borrador, y lo que diga queda como promesa pública desde el lanzamiento. Desde el 2026-11-13 es el cliente completo en local, con el vault cifrado, y la exportación; la sync no está.
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

Toda la sync es de pago (2026-11-13). Hasta aquí ha funcionado en periodo de prueba.

- **Android e iOS.** El producto de pago es el mismo cliente, sincronizado, en el móvil y en el escritorio: las apps salen después del lanzamiento de escritorio y antes de cobrar. Antes, el spike S1.2: el motor de terminal en dispositivos reales, la condición pendiente de [ADR-002](../adr/ADR-002-motor-de-terminal.md).
- **El plan de pago de la sync**, con el final del periodo de prueba, y el cobro, en el repositorio privado `openward-cloud`.
- **Una auditoría externa del cifrado y la sync** antes de cobrar por ella. Es la puerta de la fase 2 en [ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas).

## Después del lanzamiento

- **El agente SSH y la CLI `ow`.**
- **Mosh en Windows**, con el cliente clean-room de [ADR-009](../adr/ADR-009-mosh-clean-room.md).
- **La fase 3:** equipos, plan Team, IA con tu propia clave ([ADR-008](../adr/ADR-008-ia-mcp-y-byok.md)) y MCP.

## Lo que hay que decidir o hacer a mano

- **Gastos:** la cuenta de Apple Developer, el certificado de firma de Windows, el dominio y el registro de la marca.
- **Decisiones:**
  - las diez del camino a la Community (punto 2);
  - lo que quedó abierto el 2026-11-13: la duración del periodo de prueba de la sync, el precio del plan y dónde se aloja el servicio en producción;
  - publicar cada release.
- **Trámites:** registrar la marca y comprar el dominio (puntos 8 y 11).
- **Pruebas:** las de hardware y las dos semanas de uso (punto 9).
- **Legal:** revisar LICENSE, la CLA, los términos, la privacidad y el análisis de la CRA.

## Fuera de la ruta

- [RustCrypto/SSH#620](https://github.com/RustCrypto/SSH/issues/620) está resuelto desde el 2026-11-10 por la [PR #623](https://github.com/RustCrypto/SSH/pull/623). Falta una versión publicada con el arreglo y compatible con `russh`: comprobado el 2026-11-11, `ssh-key` llega hasta `0.7.0-rc.12` (anterior al arreglo) y `russh` 0.64.1 y 0.65.1 fijan la `rc.11`. Hasta entonces se conserva `openward-ssh::keyfile`, con el mínimo de 24 bytes de magnitud aplicado también a claves con ceros iniciales y cifradas. Al actualizar, cambiar también las dependencias directas de `openward-app` y `openward-fido`, retirar el relleno local y mantener las pruebas de claves cortas y del mínimo ([ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md)).
