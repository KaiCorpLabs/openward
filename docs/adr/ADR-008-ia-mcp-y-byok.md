# ADR-008 — IA: servidor MCP local y modelos BYOK o locales

- **Estado:** propuesto.
- **Fecha:** 2026-10-08.
- **Alcance:** funciones de IA en el cliente y su relación con agentes externos.

## Contexto

Partimos de tres observaciones:

- **Incluir inferencia alojada** en un plan supone un coste variable difícil de sostener para un proyecto pequeño.
- **Atar la IA a la telemetría** genera rechazo entre usuarios técnicos.
- En 2026 el uso que crece es **dirigir agentes (Claude Code, Codex) por SSH**, también desde el móvil.

Cada vez más clientes de conexión se exponen a agentes externos mediante MCP.

## Decisión

- **Servidor MCP local** en `openward-ai`, que se expone como `ow mcp` (stdio) o por HTTP en localhost con token.
  - Herramientas: `list_hosts`, `describe_host`, `run_command`, `open_session`, `sftp_get`, `sftp_put` y `start_forward`.
  - **Las claves nunca salen del núcleo:** el agente pide acciones y recibe resultados.
  - Cada acción requiere aprobación en la app, salvo las incluidas en listas permitidas por host o patrón de comando, y queda en un registro local.
- **Asistente en la app**, BYOK con OpenAI, Anthropic, Gemini o cualquier endpoint compatible, o local con Ollama o LM Studio. Antes de enviar se redactan los secretos y solo sale el contexto que el usuario selecciona.
- **Desactivado por defecto, sin telemetría**, y desactivable por política de organización.
- **No vendemos inferencia.** La IA no es una palanca de precio; el modo agente móvil se apoya en la suscripción que el usuario ya paga a su proveedor.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| Inferencia alojada incluida en los planes | Experiencia sin configurar nada | Coste variable que no controlamos; riesgo de margen; los datos de sesión salen a terceros |
| Sin IA | Simplicidad | Pierde el caso de uso que más crece (agentes por SSH) |
| IA solo mediante plugins de terceros | Cero mantenimiento | Experiencia irregular y riesgos de seguridad sin control |

## Consecuencias

Hay que diseñar bien el modelo de permisos del MCP: es un vector de ataque, porque un agente con inyección de prompt podría pedir comandos destructivos. Por defecto todo pide confirmación y las listas permitidas son explícitas. Sin IA alojada, la experiencia de "primer uso" exige configurar una clave o un modelo local; un asistente de configuración lo mitiga.

## Validación y revisión

Pruebas con Claude Code y Codex como clientes MCP y un *red team* interno de inyección de prompt sobre `run_command`. Reabrir la inferencia alojada solo si los equipos piloto la piden de forma explícita y como extra medido.
