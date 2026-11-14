# Documentación

| Documento | Contenido |
|---|---|
| [plan/estado.md](plan/estado.md) | Estado actual, PR, beta y backlog con hitos/issues y puertas comprobables |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Arquitectura, stack, fases y riesgos |
| [THREAT_MODEL.md](THREAT_MODEL.md) | Modelo de amenazas: qué se protege, de quién, lo que hay en el disco, las garantías de la v0.4 y lo que queda fuera (D0; sus decisiones, aceptadas) |
| [adr/](adr/) | Decisiones de arquitectura e historial (ADR-001 a ADR-010); [ADR-010 vigente](adr/ADR-010-monorepo-go-supabase.md): monorepo, Go mínimo, Supabase gestionado y precio/trial confirmados |
| [spikes/S1-terminal.md](spikes/S1-terminal.md) | Plan y resultados del spike del motor de terminal |
| [spikes/S2-ssh.md](spikes/S2-ssh.md) | Plan y resultados del spike de SSH con `russh` |
| [spikes/S4-sync.md](spikes/S4-sync.md) | Primera parte del spike de sync: el sobre `v: 1` y el merge por relojes de campo |
| [spikes/S6-hpke.md](spikes/S6-hpke.md) | Plan y resultados del spike del envoltorio de claves (HPKE con X-Wing) |
| [plan/alfa-escritorio.md](plan/alfa-escritorio.md) | Alfa de escritorio (v0.1): alcance, decisiones e hitos A0–A6 |
| [plan/alfa-prueba.md](plan/alfa-prueba.md) | Guía para la semana de uso de la alfa |
| [plan/v0.2.md](plan/v0.2.md) | v0.2: diseño, SFTP, túneles, paneles, identidades, snippets e importadores |
| [plan/prueba-v0.2.md](plan/prueba-v0.2.md) | Guía de las dos semanas de prueba de la v0.2 |
| [notas/v0.2.md](notas/v0.2.md) | Notas de la versión 0.2 |
| [plan/v0.3.md](plan/v0.3.md) | v0.3: keychain, paleta e historial, espacios de trabajo e importador de CSV |
| [plan/prueba-v0.3.md](plan/prueba-v0.3.md) | Guía de prueba de la v0.3 |
| [notas/v0.3.md](notas/v0.3.md) | Notas de la versión 0.3 |
| [plan/foco-y-pulido.md](plan/foco-y-pulido.md) | Foco y pulido: barra plegable, ⌘K, latencia y pulido (0.3.0-beta.3); editor e inicio (0.3.0-beta.4); entorno, sistema y favoritos (v0.3.1) |
| [plan/temas.md](plan/temas.md) | Las siete familias de temas (Monitor, Berenjena, Búnker, Marino, Catppuccin, Dracula y Tokyo Night), hechas en 0.3.1-beta.5 |
| [plan/auditoria-0.3.md](plan/auditoria-0.3.md) | Auditoría histórica de la 0.3.1: 128 entradas, seguimiento R0–R6 y mediciones; consultar el detalle de cada hito, no sus totales iniciales como deuda actual |
| [plan/registros.md](plan/registros.md) | Registros de sesión: lo que se vio en cada sesión, para buscarlo, volver a verlo y exportarlo (maquetas aprobadas, hitos L1–L4) |
| [plan/seguridad-0.3.3.md](plan/seguridad-0.3.3.md) | 63 fichas históricas y seguimientos S0/S1/S2 con pruebas, PR, CI y límites; los casos pendientes conservan su evidencia solicitada |
| [plan/community.md](plan/community.md) | Community local y beta de pago: decisiones, etapas e hitos; distingue main, trabajo local, Supabase aplicado y pendientes (2026-11-14) |
| [plan/v0.4.md](plan/v0.4.md) | v0.4: el vault cifrado (contraseña maestra, kit de recuperación, desbloqueo con biometría, secretos y copia de seguridad), etapa 2 del camino a la Community (en marcha) |
| [plan/movil.md](plan/movil.md) | Android e iOS (#68): la misma app y el mismo núcleo, qué hay, paridad con el escritorio, cómo se prueba, limitaciones y lo que hay que revisar antes de publicar |
| [plan/lanzamiento.md](plan/lanzamiento.md) | Beta con pago desde salida: dependencias #62/#67 y puertas de seguridad, móvil, cobro, operación, distribución, legal y go/no-go (2026-11-14) |

Pendiente: `PROTOCOL.md` (en [`spec/`](../spec/)).
