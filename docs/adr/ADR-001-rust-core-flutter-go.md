# ADR-001 — Núcleo Rust, UI Flutter y servidor Go

- **Estado:** propuesto.
- **Fecha:** 2026-10-08.
- **Alcance:** reparto de responsabilidades y lenguajes.

## Contexto

OpenWard necesita un mismo cliente en Windows, macOS, Linux, iOS y Android. La lógica sensible (SSH, criptografía, sync, vault) tiene que ser idéntica en todos. El equipo es pequeño y ya ha llevado a producción beta este patrón en Arveil: un núcleo Rust con `flutter_rust_bridge` y un relay Go sobre SQLite. En este tipo de aplicaciones lo habitual es Electron en escritorio con apps nativas en móvil, o bien Tauri.

## Decisión

- **Núcleo Rust** (`core/`), que contiene SSH, SFTP, terminal VT, vault, criptografía, sync, integraciones, IA/MCP, agente SSH y CLI. Es la única autoridad de seguridad.
- **UI Flutter** (`app/`) para las cinco plataformas, con un único código de interfaz que se comunica con el núcleo mediante `flutter_rust_bridge`, usando handles y streams.
- **Servidor Go** (`server/`) como monolito modular: no enlaza el núcleo y solo maneja datos cifrados y metadatos. La frontera entre cliente y servidor es el protocolo versionado de `spec/`.

## Alternativas

| Alternativa | Ventaja | Por qué no ahora |
|---|---|---|
| Tauri 2 + web (xterm.js) | xterm.js es el terminal web más maduro | Tauri se declara "production ready" desde la 2.0, pero no todos los plugins de escritorio están portados a móvil, y a 2026-10-08 tiene 51 issues abiertos de iOS y 91 de Android |
| Electron + nativo en móvil | Patrón habitual en clientes comerciales | Tres bases de UI; consumo de memoria y tiempo de arranque de Electron |
| Nativo por plataforma (SwiftUI, Kotlin, WinUI, GTK) | La mejor integración posible | Inviable para 1–3 personas |
| Kotlin Multiplatform + Compose | Bueno en Android | Escritorio y iOS menos probados; habría que reescribir el núcleo o enlazar Rust igualmente |
| Todo en Rust (UI con egui, Slint o GPUI) | Un solo lenguaje | Ecosistemas de UI móvil inmaduros; accesibilidad e IME en riesgo |
| Servidor en Rust | Compartir tipos | El servidor no necesita el núcleo; Go es más simple de operar (lección de Arveil) |

## Consecuencias

- Hay que mantener dos toolchains más Flutter, la frontera FFI y las builds móviles. Se compensa reutilizando la infraestructura de Arveil (`rust_builder`, CI, firma y actualizaciones).
- El terminal en Flutter es el mayor riesgo técnico. Queda acotado por el [ADR-002](ADR-002-motor-de-terminal.md) con un spike con puerta de salida.
- El servidor no puede validar el contenido; las reglas de autorización basadas en el contenido viven en los clientes, y el servidor solo aplica la ACL que conoce.

## Validación y revisión

Fase 0: la misma sesión SSH abierta desde macOS, Windows, Linux y Android con el núcleo compartido, con latencia y memoria medidas. Reabrir solo si Flutter no supera la puerta del terminal en dos plataformas o si el coste FFI impide publicar. No reabrir por benchmarks sintéticos.
