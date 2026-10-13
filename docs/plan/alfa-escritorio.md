# Alfa de escritorio (v0.1-alfa)

- **Estado:** en curso.
- **Fecha:** 2026-10-13.
- **Base:** fase 1 de la hoja de ruta ([ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas)), recortada a lo que hace falta para usarla a diario. Parte de los spikes cerrados: [S1](../spikes/S1-terminal-resultados.md) (terminal) y [S2](../spikes/S2-ssh.md) (SSH).
- **Duración estimada:** 3–4 semanas de trabajo.

## Objetivo

Una app de escritorio que el equipo pueda usar a diario en vez de su cliente SSH actual para lo básico:
- abrir hosts por SSH en pestañas;
- importar `~/.ssh/config`;
- abrir un terminal local;
- copiar y pegar;
- reconectar.

**Primero macOS**, con Linux y Windows compilando en CI.

**Puerta de salida:** el equipo trabaja una semana con la alfa contra sus servidores reales sin volver a su cliente anterior para estas tareas, y los problemas encontrados están anotados.

## Alcance

**Dentro:**
- **Hosts y grupos** guardados en local, con etiquetas, búsqueda y herencia de ajustes (grupo → host).
- **Importar `~/.ssh/config`:** `Host` y `HostName`, `User`, `Port`, `IdentityFile`, `ProxyJump`, `ProxyCommand`, `Include` y comodines.
- **SSH:**
  - autenticación con claves de disco, agente del sistema, contraseña y keyboard-interactive (2FA), pidiendo lo que haga falta en un diálogo;
  - known hosts propios con TOFU y bloqueo si la clave cambia, leyendo también `~/.ssh/known_hosts`;
  - saltos (`ProxyJump`) y ProxyCommand;
  - keepalive y reconexión;
  - indicador de kex poscuántico.
- **Terminal local** en una pestaña.
- **Pestañas:** abrir, cerrar, reordenar y renombrar. Atajos de teclado (⌘T, ⌘W, ⌘1–9, ⌘K para buscar hosts).
- **Selección de texto con el ratón y copia.** Si el programa sigue el ratón, se selecciona con Mayús.
- **Ajustes:** tamaño de letra, tema claro y oscuro, Opción = Alt e historial.
- **App de macOS** empaquetada en `.dmg`, sin firmar.

**Fuera** (siguientes versiones de la fase 1):
- SFTP y túneles guardados;
- snippets;
- división de paneles y broadcast;
- los demás importadores (PuTTY, MobaXterm, Termius);
- paleta de comandos completa;
- historial de comandos;
- cifrado del vault (fase 2);
- firma y notarización.

## Decisiones por defecto de la alfa

| Tema | Decisión | Por qué |
|---|---|---|
| Secretos | **No se guardan contraseñas ni claves privadas.** Las claves se referencian por ruta (como `IdentityFile`) o vienen del agente; las contraseñas y frases se piden en cada conexión y se olvidan al cerrarla | El vault cifrado es de la fase 2. Así la alfa no guarda nada sensible en claro |
| Almacén | SQLite (`rusqlite`) con una tabla de ítems en CBOR, el mismo modelo que tendrá el vault. En la fase 2 el contenido pasa a sobres cifrados | Evita una migración de formato entre fases |
| Known hosts | Tabla propia en el almacén. `~/.ssh/known_hosts` se lee, pero no se escribe | No tocar los ficheros de OpenSSH del usuario |
| Motor de terminal | `openward-ghostty`: el adaptador de S1, en un crate propio porque es FFI con `unsafe` | El workspace prohíbe `unsafe`; las excepciones van aisladas y auditadas (§3.2) |
| UI | Flutter de escritorio en `app/`; estado con Riverpod | Lo que fija la arquitectura (§3.1) |

## Hitos

| ID | Hito | Días | Estado |
|---|---|---|---|
| A0 | Pasar al núcleo lo probado en los spikes: `openward-term` (sin alacritty), `openward-ghostty`, `openward-ssh` y `openward-pty`. Añadir Zig a la CI | 2 | **Hecho** en local; la CI con Zig se valida con el push |
| A1 | Almacén y modelo: `openward-vault` (fase 1, sin cifrar) con hosts, grupos, etiquetas, herencia y known hosts. Importador de `~/.ssh/config` (`openward-import`) | 3 | Pendiente |
| A2 | `openward-app`, que orquesta las sesiones y resuelve la configuración efectiva, y `openward-ffi`, la superficie para Flutter con handles opacos y sin secretos | 3 | Pendiente |
| A3 | App Flutter: ventana, barra lateral de hosts, búsqueda, pestañas y el widget de terminal del banco convertido en componente | 4 | Pendiente |
| A4 | Conexión: diálogos de autenticación, known hosts (TOFU, cambio), saltos, reconexión e indicador poscuántico | 3 | Pendiente |
| A5 | Selección y copia, ajustes, atajos y terminal local | 3 | Pendiente |
| A6 | Empaquetado de macOS, builds de Linux y Windows en CI, y uso real por el equipo | 2 | Pendiente |

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Zig y la librería precompilada complican la CI de Linux y Windows | Cachear la build de libghostty por commit y destino; probar Windows con MSVC en A0 |
| Selección y copia con el render propio | Se hace en el núcleo, sobre el estado de Ghostty, que tiene selección; la UI solo pinta el rango |
| Diálogos de autenticación a mitad de conexión (2FA, frase de la clave, TOFU) | La conexión pide a la UI lo que le falta mediante un stream de peticiones con respuesta, sin que el secreto viva en Dart más que el tiempo de enviarlo |
