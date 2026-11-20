# ADR-010 — Monorepo, Go mínimo y Supabase gestionado

- **Estado:** decisiones del propietario confirmadas el 2026-11-13; reconciliadas el 2026-11-14. Este ADR documenta esas decisiones, no aprueba la API ni declara completa su implementación.
- **Alcance:** reparto de responsabilidades, repositorio, servicio alojado y modelo comercial de la beta.
- **Seguimiento:** [#62](https://github.com/KaiCorpLabs/openward/issues/62), [#39](https://github.com/KaiCorpLabs/openward/issues/39) y [plan maestro #67](https://github.com/KaiCorpLabs/openward/issues/67).

## Contexto

Los planes y ADR anteriores describían identidad KaiCorp autoalojada, un proxy OIDC, Go en otro repositorio y despliegue doméstico. Los issues ya recogen decisiones posteriores. Hace falta una referencia vigente sin confundir código integrado, pruebas locales y cambios aplicados al proveedor.

## Decisión

1. **Un monorepo OpenWard:** app Flutter de escritorio/Android/iOS, núcleo Rust y servidor Go mínimo. No crear otro repositorio backend para esta beta.
2. **Supabase gestionado para Auth y datos.** Un único proyecto de producción por ahora. No se vuelve al requisito de identidad autoalojada de KaiCorp ni a una base doméstica separada. Los entornos locales desechables no son proyectos de staging alojados.
3. **Go conserva la lógica de confianza necesaria:** autorización de dispositivos/sync, comprobación de sesiones vigentes, relay, entitlement y webhooks. Auth y persistencia gestionados no se duplican. La selección exacta de API/callbacks y su autorización siguen en #62/#39/#65.
4. **Edge Functions es alternativa secundaria** para piezas acotadas; Go es el camino principal. No se mantienen dos implementaciones paralelas por defecto.
5. **OVH previsto para Go, aún sin despliegue.** La topología, capacidad, secretos, backups y apertura pública requieren trabajo y evidencia de #40.
6. **Community completa en local y sin cuenta.** Toda la sync es de pago y alojada, sin almacenamiento propio ni servidor autoalojable. Precio **4,99 €/mes o 49 €/año**, prueba de **14 días sin tarjeta**. Inicio del trial, impuestos, vendedor, mercados, retención/gracia y rutas de tienda siguen pendientes.
7. **Objetivo de #67: beta con pago activo desde la salida**, cuando estén cerradas todas las puertas. Móvil forma parte del producto y de esa aceptación. La antigua secuencia escritorio → móvil → cobro es historia; no se deduce de ella una publicación ni una fecha.

## Límites de seguridad y publicación

- Cuenta, autorización/posesión del dispositivo, descifrado y pago son autoridades distintas. Login o recuperación por correo no descifran el vault ni admiten por sí solos otro equipo.
- El paquete remoto OWRP actual necesita contraseña maestra+kit; una copia local `.owvault` puede recuperarse con kit. El kit no contiene una copia de los datos ni recupera claves de hardware. No se promete recuperación remota solo con kit sin decisión y prueba.
- Logout/revocación deben comprobarse con JWT aún vigente en alojamiento. Denegar el API no retira claves previamente entregadas: posesión, generaciones y exclusión criptográfica siguen pendientes. La API permanece cerrada (`design_pending`).
- El esquema y el helper privados aplicados en Supabase no acreditan onboarding, aislamiento A/B completo, operación ni seguridad del sistema integrado. [Estado por nivel de evidencia](../plan/estado.md).
- El monorepo no decide automáticamente licencia, visibilidad ni publicación del servidor. [LICENSE](../../LICENSE) sigue vigente; revisar su conciliación con los componentes antes de publicar código. Este ADR no cambia licencias ni publica el trabajo local.

## Relación con el historial

Complementa el reparto Rust/Flutter/Go de [ADR-001](ADR-001-rust-core-flutter-go.md). Sustituye los requisitos de repositorio separado, identidad previa y despliegue doméstico del plan Community, y las partes incompatibles de [ADR-006](ADR-006-servidor-open-core.md) y [ADR-007](ADR-007-licencias-y-contribuciones.md). Sus revisiones anteriores se conservan como historia, sin reactivar un servidor autoalojable, AGPL ni una licencia nueva por esta reconciliación.

## Validación pendiente

- #62: contrato/fixtures versionados, callbacks por plataforma, posesión, enrolamiento y recuperación resueltos.
- #38/#39/#64: integrar el trabajo local sobre main actual, CI de la revisión exacta y recorrido real de cuenta/sync entre dispositivos.
- #65: logout/revocación alojados, aislamiento, exclusión criptográfica, revisión externa y auditoría con retest antes de cobrar.
- #63: checkout y ciclo de suscripción reales; #40: runtime, restauración y operación; #41/#68: firma, instalación y disponibilidad móvil.
- #33/#37/#42/#66: hardware, uso prolongado, recuperación personal, presentación/legal y go/no-go explícito. Documentar decisiones no cierra estos issues.
