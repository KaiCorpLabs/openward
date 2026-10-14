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
| macOS | **Sin App Sandbox** | Un cliente SSH con terminal local lanza shells y ProxyCommand, lee `~/.ssh` y habla con el agente, como iTerm2 o Ghostty. La Mac App Store, que exige sandbox, queda fuera por ahora |

## Hitos

| ID | Hito | Días | Estado |
|---|---|---|---|
| A0 | Pasar al núcleo lo probado en los spikes: `openward-term` (sin alacritty), `openward-ghostty`, `openward-ssh` y `openward-pty`. Añadir Zig a la CI | 2 | **Hecho.** CI de Linux en verde, Zig incluido. `cargo-deny` ignora RUSTSEC-2023-0071 (`rsa`, sin corrección publicada), con la justificación en ADR-003 |
| A1 | Almacén y modelo: `openward-proto` (tipos y CBOR), `openward-vault` (fase 1, sin cifrar) con hosts, grupos, etiquetas, herencia y known hosts. Importador de `~/.ssh/config` (`openward-import`) | 3 | **Hecho** ([detalle](#a1-almacén-modelo-e-importador)) |
| A2 | `openward-app`, que orquesta las sesiones y resuelve la configuración efectiva, y `openward-ffi`, la superficie para Flutter con handles opacos y sin secretos | 3 | **Hecho** ([detalle](#a2-orquestación-y-ffi)) |
| A3 | App Flutter: ventana, barra lateral de hosts, búsqueda, pestañas y el widget de terminal del banco convertido en componente | 4 | **Hecho** ([detalle](#a3-la-app)) |
| A4 | Conexión: diálogos de autenticación, known hosts (TOFU, cambio), saltos, reconexión e indicador poscuántico | 3 | **Hecho** ([detalle](#a4-flujos-de-conexión)) |
| A5 | Selección y copia, ajustes, atajos y terminal local | 3 | Pendiente. Adelantados en A3: los atajos, el terminal local y renombrar y reordenar pestañas. Faltan la selección y copia, y los ajustes (fuente, tema, Opción = Alt, historial) |
| A6 | Empaquetado de macOS, builds de Linux y Windows en CI, y uso real por el equipo | 2 | Pendiente |

## A1: almacén, modelo e importador

**`openward-proto`.** Lo que va dentro de un ítem, en CBOR. En la fase 2 será el texto que se cifra.
- Tipos: `Group`, `Host` y `KnownHost`, más `Settings`, con todos los campos opcionales (`None` = heredar):
  - usuario, puerto, claves por ruta, certificados e `IdentitiesOnly`;
  - agente (ninguno, el del sistema o un socket propio, como el de un gestor de contraseñas);
  - ruta (directa, saltos o ProxyCommand), keepalive y reenvío del agente;
  - `TERM`, variables de entorno y política de claves de host (preguntar, aceptar nuevas o estricta).
- **Compatibilidad entre versiones:** los campos solo se añaden. Lo que escribe una versión más nueva se conserva al leer y al reescribir (`extra`). Un tipo de ítem desconocido se deja intacto en disco.
- Los IDs son UUIDv7, codificados como 16 bytes.

**`openward-vault`.** SQLite (`rusqlite` con SQLite incluido, que compila para iOS y Android).
- Tabla `items(vault_id, item_id, head_rev, envelope)` y sobre de versión 0 `{v, body}` sin cifrar. La fase 2 añade la versión 1, cifrada, en la misma columna.
- Un fichero nuevo se crea con permisos `0600`.
- Escrituras:
  - con revisión: una edición hecha sobre una revisión vieja se rechaza;
  - creación por lotes con IDs del llamante, todo o nada, para que una importación pueda referirse a sí misma;
  - validación de referencias: grupo existente, sin ciclos, y un salto debe apuntar a un host.
- Borrar un grupo sube su contenido al grupo padre. Un host que otros usan como salto no se puede borrar.
- `effective(host)` resuelve `defaults ← grupo raíz ← … ← grupo ← host` y dice de dónde viene cada ajuste.
- También: búsqueda por palabras (etiqueta, dirección, usuario, etiquetas y grupos) y recuento de etiquetas.
- Known hosts propios: `trust_host_key` sustituye la clave del mismo algoritmo para ese host, y `known_hosts_text` los entrega a `openward-ssh`.

**`openward-import`.** `~/.ssh/config` leído como lo lee `ssh`.
- Cada alias concreto de `Host` es un host, con los ajustes que usaría `ssh <alias>`: los de todos los bloques que encajan, comodines incluidos, y gana el primer valor.
- Soporta:
  - `Include` con globs, relativo a `~/.ssh` y limitado al bloque donde aparece;
  - `Match all`;
  - `%h` en `HostName`;
  - comillas y `clave=valor`;
  - `ProxyCommand` literal.
- Un `ProxyJump` a otro alias importado pasa a ser un salto a ese host.
- Avisos para la UI:
  - palabras clave no importadas, una vez cada una;
  - bloques `Match` saltados;
  - valores inválidos;
  - `StrictHostKeyChecking no`, que se importa como `accept-new`;
  - saltos que pierden claves al quedar como dirección suelta.
- No escribe nada. `cargo run -p openward-import --example ssh_config` resume qué se importaría (con `-v`, el detalle).

**Pruebas:** 5 en proto, 11 en vault y 13 en el importador, entre ellas una de extremo a extremo: importar, crear en el vault dentro de un grupo y resolver los saltos.

## A2: orquestación y FFI

**`openward-ssh`** se separa en dos pasos:
- `open`: transporte, kex y clave de host;
- autenticación paso a paso: `none`, clave, certificado, agente, contraseña y keyboard-interactive por rondas.

Así la app puede pedir lo que falta a mitad de conexión. Las claves de host que `known_hosts` no avala pasan por un *hook* asíncrono. La matriz de S2 sigue en verde (83 ok).

**`openward-app`** es lo que la UI pide al núcleo:
- **Plan de conexión** (`Plan::for_host`):
  - parte de la configuración efectiva;
  - resuelve los saltos: un salto a un host guardado trae su propia cadena y ajustes, y se detectan los bucles;
  - expande los tokens de OpenSSH (`~`, `%h`, `%p`, `%r`, `%n`, `%d`, `%u`, `${VAR}`);
  - si no hay `IdentityFile`, usa las claves por defecto;
  - el ProxyCommand solo vale en el primer salto.
- **Autenticación** en el orden de OpenSSH:
  - claves del agente que coinciden con un `IdentityFile`;
  - el resto del agente (salvo `IdentitiesOnly`);
  - ficheros de clave, cada uno con su certificado primero si lo tiene;
  - keyboard-interactive;
  - contraseña.

  Admite *partial success* (clave + 2FA). La frase de la clave se pide hasta tres veces y, si se cancela, esa clave se salta, como hace `ssh`.
- **Claves de host** por política:
  - **preguntar:** evento con la huella `SHA256:`;
  - **aceptar nuevas;**
  - **estricta.**

  Una clave cambiada se rechaza siempre: el fallo trae la clave nueva, y solo `trust_host_key`, un gesto explícito, la acepta. Lo aceptado se guarda en el vault; `~/.ssh/known_hosts` se lee, pero no se escribe.
- **Eventos por sesión:**
  - progreso por salto;
  - preguntas con id, que la UI responde con `answer`; los secretos de las respuestas se borran de memoria (`zeroize`);
  - `Connected` (kex, poscuántico, confianza);
  - `Started` (programa local en marcha);
  - `Closed` (código de salida o fallo tipado).
- **`Terminal`**: motor Ghostty, frames y entrada, como el banco de S1. Recibe la salida de un PTY local o de un canal SSH. Volver a conectar conserva la pantalla.
- **Importar `~/.ssh/config`** al grupo `~/.ssh/config`. Una segunda importación solo trae alias nuevos y respeta lo editado en OpenWard.
- El directorio de datos se crea con permisos `0700`.

**`openward-ffi` y `app/`.**
- API generada con flutter_rust_bridge 2.13:
  - un `OpenWard` opaco: CRUD de hosts y grupos con revisión, herencia con el origen de cada campo, búsqueda, etiquetas, importación, known hosts y respuestas;
  - un `TerminalSession` opaco: frames y entrada.
- `connect` y `openLocal` devuelven en Dart el `Stream` de eventos de la sesión. Los eventos son planos (tipo + parte).
- Las actualizaciones aplican la vista sobre el ítem guardado, así que no se pierden campos de versiones más nuevas.
- `app/`: proyecto de escritorio con cargokit (toolchain fijado y nombre de librería corregido) y una pantalla provisional.

**Pruebas:**
- **Rust:** 7 unitarias y 9 de integración contra los servidores de S2:
  - TOFU y shell con `stty size`;
  - pregunta de clave de host;
  - clave cambiada;
  - frase de la clave y contraseña con reintento;
  - contraseña en Dropbear;
  - 2FA con TOTP;
  - salto a un host guardado;
  - soltar el terminal cuelga la conexión;
  - shell local.

  El job `core` de la CI levanta los servidores en Linux para ejecutarlas.
- **Dart:** 4 pruebas de integración en macOS a través de los bindings, todas en verde.
- **Pendiente para A6:** compilar y probar `app/` en la CI.

## A3: la app

Escritorio con Flutter y Riverpod, en `app/lib`:
- **Ventana:**
  - barra lateral de hosts (280 px);
  - tira de pestañas;
  - el terminal de la pestaña al frente;
  - barra de estado.

  Tema oscuro cercano al fondo del terminal.
- **Barra lateral:**
  - grupos plegables con el recuento de hosts;
  - cada host con `usuario@dirección:puerto` efectivos y sus etiquetas;
  - búsqueda por palabras (Intro conecta al primero, Esc limpia);
  - menú contextual: conectar, editar y eliminar; en grupos, también crear dentro;
  - doble clic para conectar en una pestaña nueva.
- **Editores de host y grupo:**
  - nombre, dirección, grupo, etiquetas, usuario, puerto, claves por ruta, agente, ruta (directa, salto por un host guardado o ProxyCommand), política de claves de host y notas;
  - lo heredado aparece como pista atenuada, con su origen («Heredado: deploy (grupo prod)»);
  - una cadena importada que el editor no sabe editar se conserva tal cual;
  - los campos que el editor no muestra se mantienen.
- **Importar `~/.ssh/config`:** un informe en palabras de lo que entró y lo que no.
- **Pestañas:**
  - una por sesión, con un punto de estado y un aviso si hay una pregunta pendiente;
  - se cierran con clic central o ×, se reordenan arrastrando y se renombran con doble clic;
  - cada una tiene su controlador: sesión de Rust, render y eventos;
  - las ocultas se sondean a 4 Hz para mantener el título.
- **Terminal** (`terminal/`): el render del banco (atlas de glifos y cajas dibujadas) y su entrada (teclado, IME, pegado con confirmación, ratón y rueda), ahora como componente. `redraw()` pide la pantalla entera cuando cambia la densidad de píxeles.
- **Preguntas de la sesión** en una tarjeta sobre su pestaña, sin bloquear las demás:
  - huella de una clave de host nueva;
  - frase de la clave;
  - contraseña;
  - keyboard-interactive con una respuesta por pregunta.
- **Estado:** progreso, «Conectado · poscuántico (mlkem768x25519-sha256) · cifrado», o el fallo en palabras con un botón de reconectar o reiniciar.
- **Atajos:**
  - ⌘T terminal local, ⌘W cerrar, ⌘K buscar, ⌘1–9 y ⌘⇧[ ] para cambiar de pestaña;
  - Ctrl+Tab en todos los sistemas;
  - Ctrl+Mayús+T/W/K en Linux y Windows.

  El terminal deja pasar estas teclas.

**Pruebas:**
- 9 unitarias del render en Dart.
- 3 de integración de la ventana en macOS, con capturas renderizadas por la propia app:
  - barra lateral, búsqueda y terminal local;
  - crear un grupo y un host desde los editores y ver la herencia;
  - SSH con la pregunta de clave de host y la conexión poscuántica.
- Las 4 del FFI.

## A4: flujos de conexión

- **Clave de host cambiada:**
  - La conexión se rechaza siempre. El fallo trae la clave nueva y también las que se tenían por buenas para ese host y tipo de clave, con su origen: la lista de OpenWard o `~/.ssh/known_hosts`.
  - La pestaña muestra una tarjeta de fallo con «Revisar la clave…». Esta abre un diálogo con las huellas de antes y de ahora y una explicación del riesgo.
  - Confiar en la nueva exige marcar «He comprobado la huella nueva».
  - Si la clave vieja estaba en `~/.ssh/known_hosts`, el diálogo recuerda que OpenWard no toca ese fichero y da el `ssh-keygen -R` que hace falta.
- **Reconexión automática:**
  - Una sesión establecida que se cae por la red se reintenta a los 1, 2, 4, 8, 16 y 30 s, hasta 8 veces, sobre la misma pantalla.
  - El plan se recalcula en cada intento, por si el host se ha editado.
  - Si el fallo deja de ser de red (autenticación, clave), se para y lo dice.
  - Arriba del terminal aparece un aviso con el motivo, la cuenta atrás, «Reconectar ya» y «Cancelar».
  - La prueba mata el `sshd` de la sesión dentro del contenedor, directo o detrás de un salto, y comprueba que vuelve.
- **Progreso por saltos:**
  - Al empezar, la conexión anuncia su ruta.
  - Mientras se conecta por primera vez, una tarjeta muestra «Este equipo → bastion → db» con el estado de cada salto (hecho, conectando, autenticando o pendiente) y un botón de cancelar.
  - El editor de hosts admite cadenas de saltos: hosts guardados o direcciones `usuario@host:puerto`, en orden, que se pueden quitar.
- **Detalles de la conexión:** pulsando la barra de estado se ven:
  - destino y ruta;
  - intercambio de claves, con la explicación cuando no es poscuántico;
  - cifrado, algoritmo y huella de la clave del host (copiable);
  - confianza (conocida, nueva o certificada por una CA);
  - tiempo de conexión.
- La contraseña que PAM pide por keyboard-interactive se titula «Contraseña».

**Pruebas:**
- **Rust:** 10 de integración contra los servidores de S2, entre ellas la reconexión y las claves anteriores con su origen.
- **Dart:** 5 de integración de la ventana:
  - clave cambiada y confianza explícita;
  - ruta con salto en los detalles y reconexión tras matar la sesión.
- Una unitaria del analizador de direcciones de salto.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Zig y la librería precompilada complican la CI de Linux y Windows | Cachear la build de libghostty por commit y destino; probar Windows con MSVC en A0 |
| Selección y copia con el render propio | Se hace en el núcleo, sobre el estado de Ghostty, que tiene selección; la UI solo pinta el rango |
| Diálogos de autenticación a mitad de conexión (2FA, frase de la clave, TOFU) | La conexión pide a la UI lo que le falta mediante un stream de peticiones con respuesta, sin que el secreto viva en Dart más que el tiempo de enviarlo |
