# Spikes de la fase 0

Prototipos para responder preguntas técnicas antes de construir el producto. **No es código de producto:** no se importa desde `core/` ni desde `app/`, y puede borrarse cuando su ADR quede aceptado.

| Spike | Pregunta | Plan | Decide |
|---|---|---|---|
| [S1 · terminal](s1-terminal/) | ¿Qué motor VT y qué render en Flutter? | [S1-terminal.md](../docs/spikes/S1-terminal.md) | [ADR-002](../docs/adr/ADR-002-motor-de-terminal.md) |
| S2 · SSH | ¿Cubre `russh` la interoperabilidad y el móvil? | Pendiente | [ADR-003](../docs/adr/ADR-003-ssh-russh-y-firmantes.md) |
| S3 · firmantes | ¿Firma con Secure Enclave y Keystore a través del bridge? | Pendiente | [ADR-003](../docs/adr/ADR-003-ssh-russh-y-firmantes.md) |
| S4 · sync | ¿Convergen los registros por dispositivo sobre carpeta y S3? | Pendiente | [ADR-005](../docs/adr/ADR-005-sync-por-registros-de-dispositivo.md) |
| S5 · entrada | Teclado e IME en Android y escritorio | Dentro de S1.5 | [ADR-002](../docs/adr/ADR-002-motor-de-terminal.md) |
| S6 · HPKE / X-Wing | ¿`hpke-rs` con libcrux o `hpke`? | Pendiente | [ADR-004](../docs/adr/ADR-004-vault-y-jerarquia-de-claves.md) |
