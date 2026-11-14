# Lanzamiento: Community local y beta de pago

- **Revisión:** 2026-11-14, contra `main 553ab147e0d2c1fb7bc65f0e0ddb9890b40e3b39`.
- **Referencias vigentes:** [estado y evidencia](estado.md), [plan Community](community.md), [ADR-010](../adr/ADR-010-monorepo-go-supabase.md), [móvil](movil.md) y [plan maestro #67](https://github.com/KaiCorpLabs/openward/issues/67).
- **Historia:** propuesta del 2026-11-10. Las estimaciones antiguas (~18 semanas, después 3,5 para el motor sin backends propios) no son una fecha ni el trabajo restante. Se conservan las dos semanas de uso y las puertas físicas, de recuperación y auditoría.

## Objetivo

La Community es el cliente completo gratuito en local, con vault cifrado y sin cuenta obligatoria. La sync E2EE alojada cuesta **4,99 €/mes o 49 €/año**, con **14 días sin tarjeta**. El objetivo vigente de #67 es salir como **beta con pago activo**, con cuenta/sync fiables y móvil validado. La publicación y activación de cobros requieren un go/no-go explícito después de reunir la evidencia.

La secuencia anterior de Community de escritorio, móvil y después cobro queda como historia. El código Android/iOS ya está fusionado; eso no acredita su disponibilidad en tiendas ni permite cobrar antes de las puertas. No se presenta un trial como servicio ya abierto.

La arquitectura acordada es monorepo Flutter/Rust/Go mínimo, Supabase gestionado para Auth/datos y un único proyecto de producción por ahora. Edge Functions es alternativa secundaria. OVH está previsto, aún sin desplegar. No se requiere backend en otro repositorio, identidad KaiCorp autoalojada ni producción en el minipc/tailnet.

## Dónde estamos (2026-11-14)

| Nivel | Estado verificado |
|---|---|
| **Integrado en main** | Etapa 1 y vault v0.4: D0–D3 y D5–D7 implementados, sesión/backends D4 y onboarding/Ajustes **locales** D8; candidata `0.4.0-beta.1+31`. Android/iOS por [#69](https://github.com/KaiCorpLabs/openward/pull/69); Escape y fixtures SSH/Telnet por [#70](https://github.com/KaiCorpLabs/openward/pull/70). |
| **CI de main** | [553ab147](https://github.com/KaiCorpLabs/openward/actions/runs/43541166915): 19 trabajos correctos, borrador de release omitido. Integración de app y matriz SSH se ejecutan en Linux; sus pasos se omiten en macOS/Windows. No acredita hardware, operación ni trabajo local sin publicar. |
| **Probado localmente** | Motor de sync, Go, lógica de suscripciones y UX de cuenta/sync en copias aisladas; recorrido entre dos vaults y ensayos de simulador/emulador. Conexión Go real de lectura a Supabase con TLS verificado. No está integrado en main; falta CI completa del último árbol y conciliación con main actual. |
| **Aplicado en Supabase** | Proyecto de producción, 11 tablas privadas con RLS habilitada/forzada y sin lectura para clientes `anon`/`authenticated`, login backend limitado y helper privado de sesión. No equivale a servicio desplegado ni aislamiento ante backend comprometido. |
| **Bloqueado en el último ensayo** | Auth real, logout/revocación alojados con JWT vigente: falta identidad sintética con custodia segura y acceso al Dashboard; el Mac estaba bloqueado. API cerrada `design_pending`; no se han repetido esas pruebas durante esta revisión. |
| **Pendiente de producto/seguridad** | Onboarding alojado, posesión/enrolamiento, recuperación remota, exclusión criptográfica, checkout real, operación, firma/distribución, dispositivos físicos y auditoría. #33/#37 conservan sus puertas personales y físicas. |
| **Distribución** | Ninguna release pública. Los 28 registros consultados son borradores; el último sigue en `v0.3.4-beta.4`, anterior al vault v0.4 y al móvil de main. Una etiqueta, paquete de CI o borrador no es una candidata pública validada. |

## Prioridad 1: sin esto no se lanza

Los números conservan los enlaces históricos del plan. La preparación puede ir en paralelo contra el contrato #62; integrar y abrir servicios depende de sus puertas.

| # | Trabajo | Seguimiento y cierre |
|---|---|---|
| 1 | Touch ID, llavero protegido y firma SSH Secure Enclave en bundle real; hardware de escritorio/móvil | [#33](https://github.com/KaiCorpLabs/openward/issues/33), #68 |
| 2 | Contrato común, callbacks, posesión, recuperación y decisiones restantes | [#62](https://github.com/KaiCorpLabs/openward/issues/62); [ADR-010](../adr/ADR-010-monorepo-go-supabase.md) ya registra las confirmadas |
| 3 | Cerrar las puertas restantes del vault v0.4 | [#37](https://github.com/KaiCorpLabs/openward/issues/37), #33; [guía](prueba-v0.4.md) |
| 4 | Motor de sync durable y convergencia | [#38](https://github.com/KaiCorpLabs/openward/issues/38) |
| 5 | Go mínimo, Supabase Auth/datos y UX integrada | [#39](https://github.com/KaiCorpLabs/openward/issues/39), [#64](https://github.com/KaiCorpLabs/openward/issues/64), #62/#65 |
| 6 | Runtime, restauración, monitorización, borrado y operación | [#40](https://github.com/KaiCorpLabs/openward/issues/40) |
| 7 | Firma, actualizaciones, paquetes y descargas | [#41](https://github.com/KaiCorpLabs/openward/issues/41), #68 |
| 8 | Web, documentación y soporte fieles a la candidata | [#66](https://github.com/KaiCorpLabs/openward/issues/66) |
| 9 | E2E y dos semanas de uso; hardware y escritorio↔móvil | [#42](https://github.com/KaiCorpLabs/openward/issues/42), #33/#37/#68 |
| 10 | Análisis legal pertinente, incluida CRA | #66/#42; revisión pendiente |
| 11 | Licencia/CLA, marca, «Siempre gratis» y canal de seguridad | #66/#42; ninguna licencia cambia en esta revisión |
| 12 | Go/no-go de publicación y pago sobre candidata exacta | #67/#42, con #63/#65 cerrados |

### 1 · Touch ID y el Secure Enclave

La sonda ad hoc histórica creó una clave efímera no exportable, pero Touch ID devolvió `SystemCancel`: no valida autenticación física. La firma SSH P-256 está implementada ([contrato y límites](../../spec/secure-enclave-ssh-v1.md)); falta probar alta, conexión, cancelación, bloqueo, reapertura y borrado en el bundle real. Los mocks y simuladores no acreditan Face ID/Touch ID, Windows Hello ni BiometricPrompt físicos. Registrar resultados antes de decidir certificados/compras.

### 2 · Decisiones y contrato

Monorepo, Go mínimo, Supabase gestionado, precio y duración del trial están confirmados. #62 sigue abierto porque registrar estas decisiones no completa la API, fixtures, callbacks, posesión o recuperación. Faltan también inicio del contador, fiscalidad, vendedor, mercados, retención/gracia y rutas de pago.

Cuenta, dispositivo, descifrado y entitlement son autoridades distintas. El paquete remoto actual exige contraseña maestra+kit; el kit no es copia de datos ni recupera hardware. No se promete recuperación remota solo con kit ni admisión de otro equipo por login de cuenta.

### 3 · v0.4, el vault cifrado

D3–D8 tienen implementación integrada ([plan](v0.4.md), [notas](../notas/v0.4.md)). [#58](https://github.com/KaiCorpLabs/openward/pull/58) conserva la [calibración KDF en los tres sistemas](../evidence/kdf-calibration-v0.4.md). #33 conserva maquetas originales y autenticación/firma físicas. #37 conserva migración personal, una semana real de uso cifrado y recuperación independiente; no se acreditan con fixtures. El onboarding **local** integrado no prueba el de cuenta/sync alojadas.

### 4 · v0.5, el motor de sync

Integrar el trabajo local de #38 con el main actual. Exigir colas/cursores/confirmaciones durables, reintentos idempotentes, duplicados/desorden, crash, conflictos recuperables y compactación. Puerta: tres dispositivos × 10.000 ediciones convergen al 100 % contra backend de pruebas **y relay real**. No hay backends de carpeta/S3/WebDAV ofrecidos al usuario.

### 5 · v0.6, servidor y cuentas

Supabase gestionado aporta Auth/datos; Go mínimo en el monorepo conserva la lógica de confianza. Resolver #62 e integrar #39/#64 con #38/#63. Probar autorización A/B, enrolamiento/posesión, recuperación, callbacks por plataforma, sesión viva, logout y revocación alojados. El helper privado no sustituye esas pruebas. Mantener la API cerrada `design_pending` hasta resolverlas; denegar un token no excluye criptográficamente a quien conserva claves (#65).

### 6 · v0.7, operación

OVH previsto, sin runtime desplegado. #40 exige permisos y secretos mínimos, TLS/WebSocket, backups cifrados fuera del host, restauración limpia con RPO/RTO medidos, alertas/runbooks, migraciones/rollback y borrado/retención. Un solo proyecto Supabase por ahora: definir aislamiento de ensayos y restauración sin inventar staging ya disponible. Los tests locales de operación no acreditan estos procedimientos en producción.

### 7 · Distribución

#41 exige firma/notarización macOS, firma Windows, paquetes Linux/Windows y actualizaciones autenticadas con pruebas de manipulación, interrupción, rollback y migración. Android/iOS requieren firma de release y disponibilidad validada de #68. Verificar los mismos archivos que recibirá el usuario con commit, checksums y procedencia. El APK de depuración y los artefactos ad hoc actuales no cierran esta puerta.

### 8 · Web y documentación pública

#66 debe mostrar función/plataforma/estado, precio, prueba, límites, recuperación, cancelación y soporte verificables. Descargas ligadas a #41, sin anunciar móvil disponible por haber compilado. Dominio/marca, compras, certificados y publicación conservan su decisión específica.

### 9 · La prueba final

- Dos semanas usando OpenWard como cliente SSH principal en macOS/Windows/Linux y una semana cifrada/migración/recuperación independiente de #37.
- Hardware de los puntos 24–30 de la [guía](prueba-v0.3.md): serie, cambio de red Mosh, FIDO2, codificaciones, shells y editores externos; puertas #33 y móviles S1.2/S2/S3/S5 de #68.
- Usuario externo: cuenta → vault/importación → trial/compra → segundo dispositivo autorizado → sync; offline/concurrencia/conflictos, logout/revocación con JWT vigente y recuperación en tercero limpio.
- Escritorio↔escritorio y escritorio↔Android/iOS; caída y restauración del servicio, actualización sin pérdida y ciclo completo de cobro. Registrar candidata exacta y evidencia en #42.

### 10 · Revisión legal

#66/#42 requieren análisis de aplicabilidad y obligaciones de la CRA, privacidad, términos, retención/borrado, cancelación y devoluciones con apoyo jurídico adecuado. No se considera terminado por disponer de borradores ni se deduce una validación legal de este roadmap.

### 11 · Licencia, marca, «Siempre gratis» y `SECURITY.md`

[LICENSE](../../LICENSE) mantiene todos los derechos reservados. El plan previo de cliente GPL-3.0 y CLA debe revisarse junto a licencia/publicación del Go en el monorepo ([ADR-010](../adr/ADR-010-monorepo-go-supabase.md)); no se crea una excepción ni se publica código local aquí. Revisar marca y promesa de cliente local completo/exportación gratuitos. [SECURITY.md](../../SECURITY.md) ya existe; comprobar canal y plazos antes de usuarios externos.

### 12 · Publicación

#42 reúne evidencia, candidata/commit, riesgos residuales y responsables. Pérdida/corrupción, aislamiento, recuperación, revocación/exclusión, cobro incorrecto o backup no restaurable son **no-go**. Resolver el destino de borradores antiguos. Release, apertura pública y cobro requieren decisión explícita final; no se activan al cerrar una PR de documentación.

## Orden

1. Cerrar decisiones/contrato #62 y conciliar fuentes locales con main actual, conservando su evidencia por revisión.
2. Motor #38, backend #39, UX #64 y billing #63 preparan contra fixtures e integran sobre el contrato. #40/#41/#66 pueden preparar operación, distribución y textos en paralelo.
3. #65 acompaña desde el modelo; su cierre exige sistema real, revisión externa, auditoría y retest antes de cobrar.
4. #42 valida todo, incluida la entrega móvil del propietario #68 y #33/#37. Después, go/no-go de #67.

## Prioridad 2: conviene tenerlo el día del lanzamiento

Informes de fallos solo con consentimiento y secretos redactados, canal de feedback y soporte con responsables/plazos realistas (#66/#40).

## Prioridad 3: para cobrar

Este título conserva su ancla histórica; son puertas de la misma beta de pago, no una fase que permita abrir cobros después sin validación:

- **#63:** proveedor y checkout reales, webhooks autenticados/idempotentes, renovación, impago, cancelación, reembolso, restauración de derechos y rutas de tienda; 4,99 €/mes o 49 €/año y 14 días sin tarjeta. Vencimiento/cancelación conservan acceso y exportación locales.
- **#68:** Android/iOS integrados, pero dispositivos físicos, cuenta/sync, firma y tiendas siguen pendientes.
- **#65:** revisión y auditoría externa del cifrado/sync con correcciones verificadas sobre la candidata, incluyendo recuperación y revocación/exclusión.

## Después del lanzamiento

Agente SSH/CLI `ow`, Mosh clean-room para Windows/móvil y fases de equipos, IA BYOK/MCP y Enterprise. No se cuentan como entregadas ni se fijan fechas.

## Lo que hay que decidir o hacer a mano

Gastos/cuentas de desarrollador, certificados, dominio/marca, pruebas físicas y uso real; contrato y decisiones comerciales aún abiertas, revisión legal/licencias y go/no-go. El precio, duración del trial, monorepo y Supabase gestionado ya no están pendientes de decidir.

## Fuera de la ruta

La corrección local de claves SSH cortas conserva su contexto en [ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md). La comprobación de versiones upstream del 2026-11-11 es historia: antes de retirar el workaround hay que verificar una versión compatible publicada y conservar las regresiones del mínimo de magnitud. Esta revisión documental no actualiza dependencias.
