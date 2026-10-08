# ADR-009 — Mosh mediante implementación clean-room en Rust

- **Estado:** propuesto (fase 4); en las fases 1–3 se usa SSH + tmux con reenganche automático.
- **Fecha:** 2026-10-08.
- **Alcance:** continuidad de sesión en redes móviles y en segundo plano.

## Contexto

En móvil, las sesiones SSH mueren al cambiar de red o al suspenderse la app (iOS). Mosh resuelve esto y es la base de los clientes móviles que se usan para dirigir agentes de IA desde el teléfono.

**Verificación del 2026-10-08:**

- **mosh 1.4.0** (octubre de 2022) es **GPL-3.0-or-later con excepción de enlace de OpenSSL**. Enlazarlo obligaría a usar GPL en el cliente, lo que contradice el [ADR-007](ADR-007-licencias-y-contribuciones.md) (Apache-2.0).
- **`mosh-rs` 0.1.0** (agosto de 2026) es el primer cliente Rust que dice ser compatible con `mosh-server`. También es GPL-3.0 y está muy verde (una versión, 0 estrellas), así que **no se puede usar ni leer** para una implementación clean-room.
- **Eternal Terminal** es **Apache-2.0** y está activo (v7.0.0, julio de 2026), pero exige `etserver` en el servidor. Existe una reimplementación en Rust sobre QUIC (`etr` 0.10.6) cuya compatibilidad con ET no está verificada.

([mosh COPYING](https://github.com/mobile-shell/mosh/blob/master/COPYING), [mosh-rs](https://crates.io/crates/mosh-rs), [EternalTerminal](https://github.com/MisterTea/EternalTerminal))

## Decisión

1. **Fases 1–3:**
   - reconexión automática con backoff;
   - **sesión persistente** con `tmux new -A -s ow-<id>`, que convierte la reconexión en un reenganche;
   - **tmux control mode** (`-CC`) para scroll y paneles nativos;
   - en Android, un servicio en primer plano mientras haya sesiones.
2. **Fase 4:** **cliente Mosh clean-room en Rust** (`openward-mosh`).
   - Alcance: SSP sobre UDP, AES-128-OCB, mensajes protobuf, y diff y predicción de eco local aplicados sobre el estado VT del [ADR-002](ADR-002-motor-de-terminal.md).
   - Se implementa a partir de la descripción del protocolo y de capturas de tráfico, **sin leer el código GPL**, con un registro de procedencia y pruebas contra `mosh-server` real.

## Alternativas

| Alternativa | Ventaja | Por qué no |
|---|---|---|
| Enlazar mosh (C++, GPLv3) | Rápido y probado | Obliga a usar GPL en todo el cliente |
| Cliente GPL aparte ("OpenWard Mosh helper") | Aísla la licencia | No hay procesos auxiliares en iOS; complejidad de distribución |
| Usar `mosh-rs` | Ya existe en Rust | GPL-3.0 e inmaduro; además contaminaría el clean-room |
| Eternal Terminal (Apache-2.0) | Licencia compatible y proyecto activo | Requiere `etserver`, menos habitual que `mosh-server`; puede añadirse como transporte opcional |
| No soportar Mosh | Cero trabajo | Deja fuera el uso móvil que más crece |

## Consecuencias

Son semanas de trabajo de protocolo y pruebas, y existe el riesgo de diferencias sutiles con `mosh-server`. El orden por fases da valor antes: tmux con reenganche cubre buena parte de los casos sin instalar nada nuevo en el servidor.

## Validación y revisión

Pruebas de interoperabilidad contra `mosh-server` 1.4+ con pérdida de paquetes y cambios de IP simulados, y revisión de la procedencia del código. Reabrir si aparece una implementación Rust con licencia compatible y madura, para adoptarla o contribuir a ella.
