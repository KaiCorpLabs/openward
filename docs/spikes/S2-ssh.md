# Spike S2 — SSH con `russh` (escritorio)

- **Estado:** cerrado en escritorio: medido en macOS. Linux (con la matriz) y Windows quedan en la CI, que aún no se ha ejecutado con este código. Resultados en §9.
- **Fecha:** 2026-10-13.
- **Decide:** la parte de escritorio del [ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md). Los firmantes de plataforma (S3) y la parte móvil se prueban en la fase 2.
- **Duración estimada:** 5–7 días de trabajo.

## 1. Pregunta

¿Sirve **`russh` 0.64** como cliente SSH de OpenWard en escritorio? Hay que comprobar que interopera con los servidores reales, que cubre la autenticación, los túneles y los saltos que necesita la v0.1, y que no frena al terminal.

## 2. Hipótesis

| # | Hipótesis | Cómo se refuta |
|---|---|---|
| H1 | `russh` se autentica con OpenSSH 8.x, 9.x y 10.x y con Dropbear, con todos los métodos de la v0.1 | Matriz de interoperabilidad (§5) con algún método en rojo sin arreglo razonable |
| H2 | Negocia kex poscuántico (`mlkem768x25519-sha256`) con OpenSSH ≥ 9.9 y cae a `curve25519` con los demás, sin errores | Kex negociado por servidor en la matriz |
| H3 | Los túneles L/R/D, los saltos anidados y ProxyCommand se componen sobre un transporte genérico sin código especial por combinación | Prueba de salto doble más túnel, y de ProxyCommand más salto |
| H4 | El SSH no es cuello de botella del terminal: ≥ 100 MiB/s por un canal en local y menos de 1 ms añadido al eco | `cat` grande y eco medidos por el canal SSH, frente a un PTY local |
| H5 | Se compila sin problemas para macOS, Linux y Windows con `aws-lc-rs` | Builds en CI; si `aws-lc-rs` complica Windows, se mide `ring` |

## 3. Alcance

- **Dentro del alcance:**
  - autenticación: contraseña, clave pública (Ed25519, ECDSA y RSA con `rsa-sha2-*`), keyboard-interactive con 2FA, certificados OpenSSH y agente del sistema;
  - known hosts: TOFU, modo estricto, lectura de `~/.ssh/known_hosts` y `@cert-authority`;
  - sesión con PTY, redimensionado, exec y código de salida;
  - keepalive y detección de corte con reconexión;
  - túneles local, remoto y dinámico (SOCKS5 propio);
  - saltos anidados, ProxyCommand y agent forwarding;
  - integración con el terminal del banco de S1.
- **Fuera del alcance:**
  - SFTP: va en la fase 1, pero `russh-sftp` es el mismo transporte y no añade riesgo de interoperabilidad;
  - firmantes de plataforma y FIDO2 (S3, fase 2 y 4);
  - móvil (fase 2): solo se comprueba barato que compila;
  - Windows OpenSSH y Tailscale SSH como servidores: necesitan una máquina Windows y una tailnet. Se prueban a mano antes de la v0.1.

## 4. Montaje

- **`spikes/s2-ssh/servers/`:** servidores SSH reales en contenedores sin acceso a internet, escuchando solo en `127.0.0.1`.
  - **Versiones de OpenSSH:**
    - 8.x: Ubuntu 22.04, con OpenSSH 8.9;
    - 9.x: Debian 12, con OpenSSH 9.2;
    - 10.x: Debian 13, con OpenSSH 10.0;
  - **Dropbear** en Alpine.
  - **Red interna:** un bastión y un destino, para probar los saltos.
  - **Material de prueba:** claves, CA de usuarios y de hosts y secreto TOTP. Se generan al arrancar, en un directorio temporal, y nunca se commitean.
- **`spikes/s2-ssh/sshprobe/`:** CLI en Rust sobre `russh` que ejecuta la matriz y da el resultado en texto o JSON. Su código ya tiene la forma del futuro `core/crates/openward-ssh`:
  - un transporte genérico;
  - el trait `Signer`;
  - known hosts en el núcleo.
- **Banco de render (S1):** gana un backend SSH junto al PTY local, para medir el eco y el `cat` a través de SSH y Ghostty.

## 5. Matriz de interoperabilidad

Resultado del 2026-10-13 (`sshprobe matrix`, datos en `spikes/s2-ssh/results/macos-matrix.json`). ✓ pasa, — no aplica.

| Prueba | OpenSSH 8.9 | OpenSSH 9.2 | OpenSSH 10.0 | Dropbear 2025.88 |
|---|---|---|---|---|
| Kex negociado | `curve25519-sha256` | `curve25519-sha256` | **`mlkem768x25519-sha256`** | **`mlkem768x25519-sha256`** |
| Contraseña | ✓ | ✓ | ✓ | ✓ |
| Ed25519 / ECDSA P-256 / RSA (`rsa-sha2-512`) | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ |
| Clave Ed25519 cifrada con frase | ✓ | ✓ | ✓ | ✓ |
| Keyboard-interactive con TOTP (2FA) | ✓ | ✓ | ✓ | — |
| Certificado de usuario (CA de confianza) | ✓ | ✓ | ✓ | — |
| Certificado de host con `@cert-authority` | ✓ | ✓ | ✓ | — |
| Agente del sistema (`SSH_AUTH_SOCK`) | ✓ | ✓ | ✓ | ✓ |
| Agent forwarding | ✓ | ✓ | ✓ | ✓ |
| PTY, redimensionado, exec, código de salida | ✓ | ✓ | ✓ | ✓ |
| Variables de entorno (`AcceptEnv`) | ✓ | ✓ | ✓ | — |
| Túnel local, remoto y dinámico | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ |
| ProxyCommand | ✓ | ✓ | ✓ | ✓ |
| Keepalive y detección de corte | ✓ (3,9 s) | ✓ (4,0 s) | ✓ (3,9 s) | ✓ (3,9 s) |
| TOFU y clave de host cambiada (se bloquea) | ✓ ✓ | ✓ ✓ | ✓ ✓ | ✓ ✓ |
| Salto simple, doble y ProxyCommand + salto | | | ✓ ✓ ✓ (bastión) | |

**83 de 83 en verde**; 4 no aplican a Dropbear (no tiene certificados ni `AcceptEnv`, y la imagen no lleva PAM para 2FA).

## 6. Métricas y puerta

| Métrica | Umbral |
|---|---|
| Matriz §5 | En verde en OpenSSH 8.9, 9.2 y 10.0. Dropbear en verde en lo que soporta |
| Kex | Poscuántico con OpenSSH 10.0; Terrapin *strict kex* negociado en todos |
| Conexión hasta tener shell (local) | p50 < 150 ms con Ed25519 |
| Rendimiento de un canal (local) | ≥ 100 MiB/s |
| Eco por SSH en el banco | p95 dentro de la puerta de S1 (1 refresco + 4 ms) en local |
| Build | macOS, Linux y Windows compilan con el backend criptográfico elegido |

## 7. Tareas

| ID | Tarea | Días | Estado |
|---|---|---|---|
| S2.0 | Plan, servidores en contenedores y material de prueba | 1 | **Hecho** |
| S2.1 | `sshprobe`: conexión, kex, autenticación (todos los métodos) y known hosts | 1–2 | **Hecho** |
| S2.2 | Sesión: PTY, redimensionado, exec, keepalive, corte y reconexión | 1 | **Hecho** |
| S2.3 | Túneles L/R/D, saltos, ProxyCommand y agent forwarding | 1–2 | **Hecho** |
| S2.4 | Backend SSH en el banco de render: eco y `cat` por SSH | 1 | **Hecho** |
| S2.5 | Builds de escritorio y backend criptográfico; comprobación barata de compilación móvil | 0,5 | **Hecho** en macOS, iOS (check) y Android; Linux y Windows pendientes de la CI |
| S2.6 | Informe y parte de escritorio del ADR-003 | 0,5 | **Hecho** |

## 8. Riesgos del spike

| Riesgo | Mitigación |
|---|---|
| `ssh-key` 0.7 está en RC y `russh` la fija con `=` | Fijar versiones exactas; anotar lo que cambie al salir la 0.7.0 |
| Diferencias de Dropbear (algoritmos, sin certificados) | Documentar qué no soporta en vez de forzarlo |
| `aws-lc-rs` necesita CMake o NASM en algunas plataformas | Medirlo en S2.5; `ring` como alternativa |
| Las pruebas de red dependen de puertos locales | Puertos altos fijos en `127.0.0.1`, contenedores sin internet y limpieza al terminar |

## 9. Resultados (S2.6)

2026-10-13 · Apple M5 · release · servidores en contenedores (podman, VM de macOS). La red de la VM es la misma para nuestro cliente y para el `ssh` del sistema, que se mide como referencia.

**Medidas** (`sshprobe bench`, `results/macos-bench.jsonl`):

| Servidor | Conexión hasta autenticado, p50: `russh` / `ssh` | Un canal: `russh` / `ssh` | Eco por PTY remoto, p50 / p95 |
|---|---|---|---|
| OpenSSH 8.9 | 25 / 114 ms | 373 / 366 MiB/s | 1,2 / 2,4 ms |
| OpenSSH 9.2 | 23 / 111 ms | 370 / 358 MiB/s | 1,3 / 2,2 ms |
| OpenSSH 10.0 | 24 / 44 ms | 386 / 361 MiB/s | 1,2 / 2,3 ms |
| Dropbear | 5 / 17 ms | 266 / 272 MiB/s | 1,1 / 1,9 ms |

- La conexión del `ssh` del sistema incluye arrancar el proceso. Con 8.9 y 9.2, además, negocia `sntrup761x25519`, que es más lento.
- Una conexión con clave cifrada tarda unos 0,5 s más, por el bcrypt-pbkdf que descifra la clave (OpenSSH tarda lo mismo). El producto debe descifrar una vez y guardar la clave en el vault o el agente.

**Terminal completo por SSH** (banco de S1 con backend SSH y Ghostty, `results/macos-terminal.jsonl`):

| Medida | Resultado | Puerta |
|---|---|---|
| Eco de una tecla, de la pulsación al pintado, a ritmo humano | p50 11,9 ms · **p95 19,1 ms** · máx. 20,8 | p95 < 20,7 ms → **pasa** |
| 100 MiB de salida por SSH | 1,4 s (**70 MiB/s**, limitado por `tr` y `fold` en el servidor) a 56 fps; construcción p95 1,9 ms, raster 0,4 ms; **0 frames congelados** | Ninguno > 100 ms → **pasa** |

**Builds:**
- **macOS:** binario universal en la app del banco.
- **iOS:** `cargo check` sin problemas con `aws-lc-rs`.
- **Android arm64:** enlaza con el NDK r28 (ELF para `/system/bin/linker64`, 7,5 MB sin quitar símbolos).
- **Linux:** un job nuevo de la CI compila y pasa la matriz contra los servidores en cada push. Su primera ejecución será con este push.
- **Windows:** la CI semanal compila y pasa las pruebas unitarias. El agente usa una named pipe y ProxyCommand usa `cmd /C`; ese código no se ha compilado ni probado aún en Windows.
- **Backend criptográfico:** `aws-lc-rs`, el que trae `russh` por defecto. No ha dado problemas en macOS, iOS ni Android. `ring` queda como alternativa si Windows se complica.

**Hallazgos sobre `russh` 0.64.1:**
1. **Cubre todo lo de la v0.1 sin parches:** autenticación (incluido 2FA), certificados de usuario y de host, agente y su reenvío, túneles L/R/D, saltos encadenados y ProxyCommand sobre un transporte genérico, keepalive.
2. **`nodelay` viene desactivado.** Sin activarlo, Nagle retiene las pulsaciones. El cliente lo activa siempre.
3. **Los certificados de host también vienen desactivados** (`host_key_certificates`). Al activarlos, la validación es nuestra: firma de la CA, vigencia y principals. Está en `known_hosts.rs`, con pruebas.
4. **Un rechazo de la clave de host llega como un error genérico.** El cliente guarda el veredicto (`Changed`, `Unknown`…) para que la UI explique qué pasa.
5. **Kex poscuántico:** se negocia con OpenSSH ≥ 9.9 y con Dropbear 2025.88. Con OpenSSH 9.0–9.8 no: esos servidores ofrecen `sntrup761x25519`, que `russh` no implementa, y se cae a `curve25519`. Es un hueco a contribuir upstream si importa.
6. **`ssh-key` 0.7 sigue en RC** (`0.7.0-rc.11`), fijada por `russh`. Rechaza las claves P-256 con el escalar en 31 bytes, una de cada 512 de `ssh-keygen` («length invalid»): por eso la matriz fallaba de vez en cuando con el `id_ecdsa` recién generado. Desde el 2026-11-10 `openward-ssh` las lee (`keyfile.rs`).

**Pendiente:**
- probar a mano antes de la v0.1 Windows OpenSSH (servidor) y Tailscale SSH;
- SFTP con `russh-sftp` (fase 1);
- firmantes de plataforma y FIDO2 (S3, fases 2 y 4);
- ejecución en móvil (fase 2).
