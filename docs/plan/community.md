# Camino a la Community y a la beta de pago

- **Revisión:** 2026-11-14, contra `main 553ab147e0d2c1fb7bc65f0e0ddb9890b40e3b39`. [Estado, evidencia y backlog](estado.md).
- **Base:** [ADR-010: decisiones vigentes](../adr/ADR-010-monorepo-go-supabase.md), [plan maestro #67](https://github.com/KaiCorpLabs/openward/issues/67), [lanzamiento](lanzamiento.md) y [plan móvil](movil.md).
- **Historia:** plan iniciado el 2026-11-06. Las versiones y estimaciones de las cinco etapas se conservan como mapa del trabajo, no como fechas ni como medida del trabajo restante.

## Objetivo

La **Community** es el cliente completo gratuito en local, sin cuenta, en Flutter con núcleo Rust. La sync E2EE alojada es el servicio de pago: **4,99 €/mes o 49 €/año, con 14 días sin tarjeta**. No se ofrecen backends de almacenamiento propio ni un servidor autoalojable.

La salida que coordina #67 es una **beta con pago activo**, condicionada a cuenta/sync reales, móvil, operación, distribución, revisión legal y auditoría. La secuencia anterior de lanzar escritorio, después móvil y finalmente cobro queda como antecedente; no acredita ninguna publicación ni permite omitir puertas. El desarrollo Android/iOS ya está integrado en main mediante [#69](https://github.com/KaiCorpLabs/openward/pull/69), con dispositivos físicos, firma y tiendas pendientes.

La dirección confirmada es **un monorepo** para Flutter, Rust y **Go mínimo**, con **Supabase gestionado para Auth y datos**. Edge Functions es una alternativa secundaria. Hay un único proyecto de producción por ahora; OVH está previsto para Go, sin despliegue. Sustituye el plan de identidad KaiCorp autoalojada, proxy OIDC propio, minipc/tailnet y backend en otro repositorio. El contrato de autenticación/callbacks, posesión, recuperación y revocación sigue abierto en [#62](https://github.com/KaiCorpLabs/openward/issues/62).

## Qué acredita el estado actual

| Nivel | Evidencia y límite |
|---|---|
| **Integrado en main** | Cliente local y vault v0.4, Android/iOS de #69 y fixes de [#70](https://github.com/KaiCorpLabs/openward/pull/70). La [CI de 553ab147](https://github.com/KaiCorpLabs/openward/actions/runs/43541166915) pasa; omite integración de app y matriz SSH en macOS/Windows. No contiene el servidor Go ni el motor de sync de las copias de trabajo. |
| **Probado localmente, sin publicar** | Motor, Go, lógica de suscripciones y pantallas de cuenta/sync en copias aisladas; recorrido entre dos vaults, ensayos móviles y conexión Go de lectura con TLS verificado. La CI completa de una revisión local anterior no acredita el último árbol ni su integración con main actual. |
| **Aplicado en Supabase** | Proyecto gestionado de producción, 11 tablas privadas con RLS habilitada y forzada, sin lectura para clientes `anon`/`authenticated`, login de backend limitado y helper privado de sesión. Esto no prueba aislamiento ante un backend comprometido ni un servicio desplegado. |
| **Pendiente** | Identidad Auth sintética con custodia segura; registro/login, logout y revocación alojados con JWT aún vigente; posesión/enrolamiento, recuperación y exclusión criptográfica. API cerrada (`design_pending`). Tampoco se han acreditado checkout real, operación, firma, auditoría o dispositivos físicos. |

En el último intento, las pruebas Auth se detuvieron por falta de identidad sintética y acceso utilizable al Dashboard, con el Mac bloqueado. Esta revisión documental no repite ni da por pasadas esas pruebas. No hay release pública; los 28 registros de release consultados son borradores.

## Puerta de salida

- Dos semanas como cliente SSH principal en macOS, Windows y Linux, más las puertas personales de [#37](https://github.com/KaiCorpLabs/openward/issues/37) y físicas/visuales de [#33](https://github.com/KaiCorpLabs/openward/issues/33).
- Usuario externo: cuenta nueva, vault protegido/importación, trial/compra, alta autorizada de segundo equipo y sync; recuperación en un tercero conforme al contrato, sin equiparar login a posesión de claves.
- Tres dispositivos × 10.000 ediciones convergen al 100 % contra backend de pruebas y relay real; offline, conflictos, reintentos y crash no pierden escrituras confirmadas.
- Logout y revocación alojados deniegan el mismo JWT todavía válido en las rutas aplicables; un dispositivo con claves previas exige resolver también rotación/exclusión criptográfica, no solo denegar el API.
- Matriz escritorio↔móvil, pagos, restauración de backups, instalación/actualización, revisión externa y legal documentadas sobre una candidata exacta; [#42](https://github.com/KaiCorpLabs/openward/issues/42) recoge el go/no-go explícito.

## Etapas

| Etapa | Versión | Contenido | Semanas |
|---|---|---|---|
| 1 | 0.3.4 y siguientes | [Lo básico completo](#etapa-1--lo-básico-completo) (P0–P7) | ~9 |
| 2 | 0.4 | [El vault cifrado](#etapa-2--v04-el-vault-cifrado) ([v0.4.md](v0.4.md), D0–D8) | ~9 |
| 3 | 0.5 | [El motor de sync](#etapa-3--v05-el-motor-de-sync) (S1 y S4–S6) | ~3,5 |
| 4 | 0.6 | [Servidor y cuentas](#etapa-4--v06-servidor-y-cuentas-de-kaicorp-labs) (C1–C6) | ~5 |
| 5 | 0.7 | [Abierto: el servidor en producción](#etapa-5--v07-abierto-el-servidor-en-producción) (M1–M3) | ~1,5 |

**La etapa 1 va antes que la v0.4.** Varias de sus funciones añaden datos a los hosts (protocolo, codificación, retroceso, Mosh, snippet al conectar), y conviene que entren antes de migrar el vault al formato cifrado (D3), como hicieron F2 y F3 en su día. D0–D2 de la v0.4 no tocan la app (el modelo de amenazas y los dos experimentos) y pueden ir en paralelo con P3–P7.

## Etapa 1 · Lo básico completo

**Lo que ya está:**
- hosts y grupos con herencia, etiquetas, entornos y el sistema de cada servidor;
- identidades, claves (generar, importar e instalar en el servidor) y known hosts;
- pestañas, paneles, broadcast y workspaces;
- SFTP de doble panel con permisos y archivos ocultos;
- túneles L/R/D, saltos, proxy HTTP/SOCKS5, ProxyCommand, agent forwarding, variables de entorno e intercambio de claves poscuántico;
- snippets con variables, terminal local, paleta, historial, conexión viva con tmux persistente y registros de sesión;
- temas, accesibilidad, español e inglés;
- importadores.

**Hitos de la etapa 1 (implementados; conservar las pruebas manuales pendientes):**

| # | Hito | Semanas |
|---|---|---|
| P0 | Windows y Linux al día | 1 |
| P1 | Telnet y puerto serie | 1,5 |
| P2 | Mosh en escritorio | 1 |
| P3 | Llaves FIDO2 y certificados | 1,5 |
| P4 | Terminal: copiar al seleccionar, resaltado, codificación, retroceso, tema por host y atajos | 1,5 |
| P5 | Autocompletado local | 1,5 |
| P6 | Snippets en varios hosts, snippet al conectar y archivos remotos abiertos en local | 1 |
| P7 | Pulido, Novedades, notas, guía de prueba y beta | 0,5 |

### P0 · Windows y Linux al día

- La 0.3.3 se prueba en un Windows limpio (Windows Sandbox) y en un Linux de escritorio, y se arregla lo que salga.
- **La CI corre en los tres sistemas en cada push y cada PR**, porque el repositorio es público desde el 2026-11-06 y los minutos no se cobran. Si vuelve a ser privado, la CI vuelve sola al reparto que ahorra minutos: Linux en cada push, Linux y Windows en cada etiqueta de versión, y los tres cada semana. «Run workflow» deja elegir los sistemas.
- La guía de prueba cubre los tres sistemas. Desde aquí, cada hito se prueba en los tres antes de darlo por hecho.

### P1 · Telnet y puerto serie

- **Un host puede ser SSH, Telnet o serie**, con la misma herencia de grupos.
- **Telnet:**
  - negocia el tamaño de la ventana (NAWS), el tipo de terminal (TTYPE) y el eco;
  - avisa a la vista de que no cifra: la contraseña viaja en claro.
- **Serie:**
  - crate `openward-serial` (`serialport`): lista de puertos, baudios, bits de datos, paridad, bits de parada y control de flujo;
  - un botón «Serie» junto a «Terminal local» y una entrada en la paleta;
  - en los tres sistemas.
- Los registros, la búsqueda y los temas funcionan igual que en SSH.
- **Importadores:** los hosts Telnet y serie que hoy se saltan pasan a importarse.

#### Qué deja P1 hecho

- **Los datos:**
  - dos campos nuevos en los ajustes, heredables como los demás: `protocol` (`ssh`, `telnet` o `serial`) y `serial`, la línea del puerto (baudios, bits de datos, paridad, bits de parada y control de flujo; por defecto 9600 8N1 sin control de flujo);
  - el host serie guarda su puerto en la dirección: `/dev/cu.usbserial-1410`, `/dev/ttyUSB0`, `COM3`;
  - un host Telnet cuyo puerto solo ponen los valores por defecto usa el 23, en el núcleo y en el editor;
  - la versión 0.3.3 lee esos hosts como SSH y no conecta (lo nuevo va en campos y no en variantes, para que la lectura no falle).
- **Telnet**, en el crate `openward-telnet`:
  - sin E/S, con 10 pruebas propias;
  - la negociación sigue el RFC 1143, para no responder en bucle;
  - acepta el eco, SGA y binario del servidor, y por su parte NAWS (el tamaño, otra vez en cada cambio), TTYPE (el `term` del host) y SGA; rechaza el resto;
  - Intro va como `CR LF`, el fin de línea de Telnet (RFC 1123, 3.3.1), salvo en binario.
- **Transporte de Telnet:**
  - es el de SSH: directo, con proxy, con ProxyCommand o por los saltos de la ruta, que siempre son SSH;
  - un host Telnet o serie no puede ser un salto;
  - sin keepalive propio;
  - si la conexión se pierde, vuelve como una de SSH; si el servidor cuelga (`exit`), la sesión termina sin error.
- **Serie**, en el crate `openward-serial`:
  - usa `serialport` 4.10.1, fijado y sin libudev: en Linux los puertos se buscan en `/sys`, y ni la compilación ni el paquete necesitan libudev;
  - el puerto se abre en exclusiva: una segunda pestaña lo encuentra en uso;
  - en macOS solo se listan los `cu.`;
  - si se suelta el cable, la sesión se cierra diciéndolo, sin reconectar sola;
  - el break se envía desde la paleta;
  - solo en escritorio: fuera de la comprobación de móvil de la CI.
- **Lo que solo da SSH** (archivos, túneles, saltos, copiar claves, leer el sistema):
  - el núcleo lo rechaza para los demás (`PlanError::NotSsh`);
  - la interfaz no lo ofrece.
- **Sin dirección guardada:**
  - `telnet://host[:puerto]` en la barra de conexión rápida;
  - «Puerto serie» junto a «Terminal local» en el inicio, y «Abrir un puerto serie…» en la paleta;
  - en los recientes, los registros y los espacios de trabajo se guardan como `telnet://…` y `serial://puerto[:baudios[,8N1[,rtscts|xonxoff]]]`, que una versión anterior no sabe abrir.
- **Importadores:**
  - Telnet y serie desde PuTTY, SecureCRT, Tabby y CSV;
  - Telnet desde Termius, con su puerto de `telnet_configs` cuando la tabla está (la de prueba no la tiene);
  - Telnet y serie desde MobaXterm, aunque del serie solo el puerto y la velocidad: el resto de la línea lo guarda en números propios cuyo significado no está claro, y queda en 8N1.
- **Pruebas:**
  - del núcleo: el códec, el puerto serie con un pseudoterminal (en macOS sin cambiar la velocidad, que no la admite), una sesión Telnet de principio a fin contra un servidor de la propia prueba, y en Linux una consola serie, con el cable soltado y el puerto liberado al cerrar;
  - de la app: la notación de las direcciones, el formulario, las pestañas y los mensajes;
  - una prueba de ventana: el editor, una sesión Telnet y un puerto que no está.
- **Pendiente:**
  - la prueba con hardware (punto 25 de [la guía](prueba-v0.3.md));
  - el eco local, para los pocos equipos que no hacen eco y tampoco lo negocian.

### P2 · Mosh en escritorio

- **Se revisa [ADR-009](../adr/ADR-009-mosh-clean-room.md):** en escritorio se usa el `mosh-client` instalado en el equipo (Homebrew, apt, dnf), como un programa aparte dentro del PTY de la terminal local. El flujo es:
  1. OpenWard arranca `mosh-server new` por su propia conexión SSH, con la autenticación, los saltos y los known hosts de siempre;
  2. lee `MOSH CONNECT <puerto> <clave>`;
  3. lanza `mosh-client` con `MOSH_KEY`.
  
  No se enlaza ni se distribuye código GPL.
- **Es una opción más, no un cambio de protocolo:** SSH sigue siendo lo normal, y Mosh se enciende por host o por grupo (apagado por defecto). Decidido el 2026-11-06.
- **Ajuste por host «Mosh»** (heredable):
  - si falta `mosh-client`, lo dice y explica cómo instalarlo;
  - si el UDP no llega, vuelve a SSH con la sesión persistente de tmux.
- **Límites:**
  - los saltos solo sirven para arrancar el servidor, porque el UDP va directo;
  - en Windows, hasta el cliente clean-room, que sigue en la fase 4 junto con el móvil.

#### Qué deja P2 hecho

- **Los datos:** dos ajustes heredables, `mosh` (apagado por defecto) y `mosh_server`, por si `mosh-server` no está en el `PATH` del servidor (`/opt/homebrew/bin/mosh-server`). Solo cuentan con SSH.
- **El núcleo** (`openward-app/src/mosh.rs`):
  - por la conexión SSH, arranca `mosh-server new -c 256`: primero con `LANG=C.UTF-8` y si no, con `en_US.UTF-8`, y con `-s` cuando no hay saltos;
  - lee `MOSH CONNECT` sin esperar a que el canal se cierre (`exec_until`, por si el servidor lo deja abierto);
  - busca `mosh-client` en el `PATH` de la shell de inicio y en los sitios de siempre (`find_program`);
  - lo lanza en el PTY con `MOSH_KEY`, y la conexión SSH sobra en cuanto llegan los primeros paquetes.
- **Si no se puede:** sin `mosh-client`, sin `mosh-server`, sin respuesta del servidor, o si `mosh-client` dice en 20 s que no le llega nada por UDP, la sesión sigue por esa misma conexión SSH, en tmux, sin volver a pedir la contraseña. La terminal dice por qué en una línea (`Event::MoshFallback`).
- **La app:** «Mosh» y «Servidor de Mosh» en «Avanzado» del editor, solo con SSH y con su nota; la píldora «Mosh» en la barra de estado, que con Mosh no enseña la latencia de SSH; y la línea de por qué no.
- **Pruebas:**
  - del formato de `MOSH CONNECT`, del comando y de qué ha fallado;
  - en S2 (el bastión tiene `mosh` y su UDP publicado; la CI instala `mosh-client`): una sesión por Mosh de punta a punta, Dropbear sin `mosh-server`, y un servidor sin UDP publicado que vuelve a SSH.
- **Pendiente:**
  - probarlo cambiando de red de verdad (punto 26 de [la guía](prueba-v0.3.md));
  - en Windows sigue por SSH hasta el cliente clean-room.

### P3 · Llaves FIDO2 y certificados

- **Llaves de seguridad** (`sk-ecdsa-sha2-nistp256@openssh.com` y `sk-ssh-ed25519@openssh.com`):
  - generarlas con PIN y toque;
  - importar las creadas con `ssh-keygen -t ed25519-sk`;
  - firmar con la llave conectada (CTAP2 por HID, detrás del trait `Signer` de [ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md)); la interfaz pide el toque.
- **Certificados de usuario** (`*-cert.pub`):
  - comprobar de punta a punta lo que las identidades ya leen;
  - mostrar principales y caducidad;
  - avisar antes de que caduquen.
- **Pruebas:**
  - en S2, un contenedor con `sshd` que acepta llaves `sk` y una CA de usuario;
  - en las pruebas automáticas, un autenticador por software, y una llave real a mano antes de cerrar el hito.
- Las claves en el Secure Enclave (Touch ID) van con D4 de la v0.4, porque comparten su riesgo de firma.

#### Qué deja P3 hecho

- **El núcleo** (`openward-fido`, [ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md#revisión-del-2026-11-06-llaves-fido2-en-escritorio)):
  - pide a la llave una aserción CTAP2 para `ssh:` y monta con ella la firma de OpenSSH (la de la llave, sus flags y su contador);
  - habla con la llave por USB HID con `ctap-hid-fido2`, sin `libfido2`, detrás de un trait `Authenticator`;
  - en las pruebas, un autenticador por software que firma como una llave.
- **Iniciar sesión** con una clave `sk` de `IdentityFile` o de una identidad:
  - la tarjeta de conexión dice «toca la llave de seguridad…» en el paso de ese salto;
  - si la clave se hizo con `verify-required`, pide el PIN, con hasta tres intentos;
  - si falla, dice por qué en palabras: no hay llave, hay más de una, el PIN, bloqueada, no se tocó a tiempo, no es la llave de esta clave, o Windows no deja (ahí, el agente de OpenSSH de Windows).
- **Generar:** «Nueva clave» › «En una llave de seguridad (FIDO2)», Ed25519 o ECDSA P-256, con el PIN si la llave lo tiene y «Pedir el PIN cada vez». Se guarda como `~/.ssh/id_ed25519_sk` y su `.pub`; el archivo no guarda ningún secreto. Las de `ssh-keygen -t ed25519-sk` se importan como cualquier clave.
- **La página de claves:** «Llave de seguridad» en vez de la frase de paso.
- **Certificados:**
  - uno caducado no se ofrece, y si el inicio de sesión falla, el error dice que fue eso;
  - las claves y las identidades avisan la última semana: «caduca en 3 días».
- **Pruebas:**
  - las dos clases de llave firman y OpenSSH lo verifica; el PIN; la llave de otra clave;
  - en S2: entrar con una clave `sk`, que con otra llave diga «no es la de esta clave», y un certificado que caducó ayer.
- **Pendiente:**
  - una llave de verdad a mano en los tres sistemas (punto 27 de [la guía](prueba-v0.3.md));
  - en Linux, el usuario necesita acceso a `/dev/hidraw*`: la regla de udev la traen `libfido2` o `u2f-udev` en casi todas las distribuciones;
  - las llaves residentes (`-O resident`) no se crean; las que ya existen se sacan con `ssh-keygen -K` y se importan.

### P4 · Terminal

- **Copiar al seleccionar y pegar con clic derecho**, como ajustes de la app.
- **Resaltado de palabras clave:**
  - reglas para error, warning, ok, direcciones IP y MAC, con colores del tema;
  - editables y apagables;
  - se aplican al pintar, sin tocar la salida ni los registros.
- **Por host** (heredables):
  - codificación: UTF-8 por defecto, más Latin-1, CP437, Big5, Shift-JIS… con `encoding_rs`, traduciendo en el núcleo antes del motor y al enviar;
  - retroceso como `^?` o `^H`;
  - tema del terminal.
- **Atajos:** perfiles Mac y PC, y la opción de que los atajos de la app no se coman teclas dentro del terminal.

#### Qué deja P4 hecho

- **Ajustes › Terminal**, de este equipo:
  - **Ratón:** «Copiar al seleccionar» y «Pegar con clic derecho» (con Ctrl y clic derecho, el menú del terminal). Los dos, apagados por defecto.
  - **Resaltado**, encendido por defecto: errores, avisos, «bien», direcciones IP (v4 con máscara y v6) y MAC (también las de Cisco, `0011.2233.4455`).
    - Cada regla tiene su interruptor y su color, uno de los 16 del terminal, que sigue al tema.
    - Se pueden añadir reglas propias con una expresión regular.
    - Solo se pinta el texto que el programa deja sin color, y nada en la pantalla alternativa (vim, less). La salida, lo que se copia y los registros no cambian.
  - **Atajos de:** este equipo, Mac (⌘) o PC (Ctrl+Mayús), en los tres sistemas. Con los de PC, «Las teclas, para el terminal» deja Ctrl+Tab, Ctrl+=, Ctrl+−, Ctrl+0, Ctrl+, y Ctrl+Alt+número al programa.
- **Por host**, heredables, en «Avanzado» del editor y para los tres protocolos:
  - **Codificación:** UTF-8, Latin-1, Latin-9, Windows-1252, CP437, Latin-2, Windows-1250/1251, KOI8-R, CP866, Shift-JIS, EUC-JP, Big5, GB18030 y EUC-KR.
    - El núcleo traduce a UTF-8 antes del motor y al enviar (`openward-app/src/charset.rs`, con `encoding_rs`; CP437 con su tabla).
    - El motor, la pantalla y el registro solo ven UTF-8. Por Mosh, siempre UTF-8.
  - **Retroceso:** DEL (`^?`) o Control-H (`^H`); Ctrl+Retroceso, el otro.
  - **Colores del terminal:** el terminal de un tema (Monitor, Berenjena, Búnker…), un esquema de la galería o uno importado, sea cual sea el tema de la app. «Los del tema de la app» en un host gana a lo que diga su grupo.
- **Importar:** de PuTTY llegan su `LineCodePage` y su `BksIsDel`.
- **Pruebas:**
  - del juego de caracteres (un carácter partido entre lecturas, CP437, lo que Latin-1 no tiene) y del retroceso;
  - del resaltado: qué colorea, que no pasa de un tramo a otro, los anchos, horas y versiones que no son direcciones;
  - de los ajustes y de los dos perfiles.
- **Pendiente:**
  - un equipo de red de verdad con Latin-1 o CP437 (punto 28 de [la guía](prueba-v0.3.md));
  - los atajos de Mac en Windows usan la tecla de Windows, que el sistema se queda en muchas combinaciones.

### P5 · Autocompletado local

- **Sugerencias en línea mientras se escribe**, en texto atenuado; una tecla las acepta.
- **De dónde salen:** el historial de ese host, los snippets y un repertorio de comandos comunes. Todo en el equipo y sin red.
- **Se apoya en el seguidor de línea del historial:**
  - no sugiere en la pantalla alternativa (editores, `less`…);
  - no sugiere cuando el prompt pide un secreto;
  - no sugiere con el historial desactivado.
- **La IA queda para la fase 3** ([ADR-008](../adr/ADR-008-ia-mcp-y-byok.md)), con tu propia clave o un modelo local. El diseño le deja el hueco para entrar como una fuente más.

#### Qué deja P5 hecho

- **«Sugerir mientras escribes»**, en Ajustes › Terminal, encendido con el historial de comandos:
  - lo que sigue, en gris tras el cursor; → o Fin lo acepta y se escribe como si se tecleara;
  - de dónde sale, en este orden: el historial de ese host (lo último primero), los snippets de una línea sin variables que preguntar, y unos 50 comandos comunes (desde dos letras);
  - todo en el equipo, sin red (`lib/history/suggest.dart`).
- **Cuándo no sugiere,** con el seguidor de línea del historial:
  - en la pantalla alternativa;
  - si el prompt pide un secreto, o la pantalla no muestra lo tecleado (no hay eco);
  - si la línea se editó con flechas o Tab;
  - si el shell ya sugiere tras el cursor (fish, zsh-autosuggestions);
  - con el historial apagado o mientras se hace broadcast;
  - para una línea que empieza con espacio.
- **La IA:** una `SuggestionSource` más cuando llegue (fase 3).
- **Pruebas:**
  - de las fuentes y su orden, y de cuándo la pantalla deja sugerir;
  - en la ventana: el historial sugiere, otra letra lo quita, Retroceso lo vuelve a traer y → lo escribe y se ejecuta.
- **Pendiente:** probarlo a mano con bash, zsh y fish (punto 29 de [la guía](prueba-v0.3.md)).

### P6 · Snippets en varios hosts y archivos remotos

- **Ejecutar un snippet en una selección de hosts:**
  - abre o reutiliza la conexión de cada uno;
  - lo ejecuta en todos;
  - muestra el resultado de cada host, en paneles o en una vista de resultados.
- **Snippet al conectar**, por host o grupo (heredable).
- **SFTP:**
  - abrir un archivo remoto con su app del sistema o con «Abrir con…»;
  - al guardarlo, se vuelve a subir, con aviso si cambió en el servidor mientras tanto.

#### Qué deja P6 hecho

- **«Ejecutar…» › «En varios hosts…»**, en la página de snippets:
  - se eligen los hosts (filtro por nombre, dirección, grupo o etiqueta; hasta 16) y lo que el snippet pregunta;
  - se abre una pestaña nueva con un panel por host en rejilla, y el snippet se escribe en cada uno en cuanto su shell está listo, con los valores de ese host;
  - el resultado de cada host queda en su panel.
- **Reutilizar la conexión:** los hosts que ya están conectados (en otra pestaña, por SFTP o por un túnel) abren un shell nuevo por esa conexión, sin volver a iniciar sesión (`App::connect_reusing`). Una reconexión abre la suya.
- **«Snippet al conectar»**, heredable, en «Avanzado» del editor y para los tres protocolos:
  - se escribe en cada shell nuevo en cuanto está listo, al conectar y al reconectar;
  - no se escribe al volver a una sesión persistente tal como estaba;
  - solo los snippets que no preguntan nada.
- **SFTP, «Abrir» y «Abrir con…»** en un archivo del servidor:
  - se trae a una carpeta temporal solo para este usuario (se borra al cerrar la pestaña) y se abre con su app o con la elegida: en Windows, su diálogo «Abrir con»; en macOS y Linux, el nombre de una app o un comando, que se recuerda;
  - mientras la pestaña SFTP siga abierta, cada vez que se guarda se sube;
  - si en el servidor cambió desde que se abrió, se pregunta antes, y Cancelar deja la copia aquí.
  - Una barra dice qué archivos se siguen y cuándo se subieron.
- **Pruebas:**
  - en S2, un segundo shell por la conexión del primero sin volver a iniciar sesión;
  - en la ventana, con S2: el snippet al conectar, uno en dos hosts a la vez, y un archivo abierto que se sube al guardarlo y que pregunta si cambió en el servidor;
  - de la rejilla de paneles.
- **Pendiente:**
  - probar «Abrir con…» con editores de verdad en los tres sistemas (punto 30 de [la guía](prueba-v0.3.md));
  - los resultados en una vista propia (salida y código de cada host) quedan para más adelante: hoy, cada uno en su panel.

### P7 · Pulido y beta

Novedades, notas, guía de prueba en los tres sistemas, accesibilidad y galería, y una beta 0.3.x.

#### Qué deja P7 hecho

- **«Novedades»** de la 0.3.4-beta.1 (`newsVersion`): seis entradas nuevas, una por hito de P1 a P6.
- **Notas** de la 0.3.4-beta.1 en [las de la 0.3](../notas/v0.3.md), y en [la guía](prueba-v0.3.md) los puntos 24 a 30, que se prueban en los tres sistemas.
- **Accesibilidad:** la prueba recorre también el diálogo de una regla de resaltado, «Nueva clave» en una llave de seguridad y un snippet en varios hosts. Encontró que los interruptores de las reglas no tenían nombre para un lector de pantalla, y ya lo tienen.
- **Galería:** el terminal de cada tema enseña el resaltado, y Ajustes › Terminal sale en cada tema.
- **La beta 0.3.4-beta.1** (2026-11-07): la etiqueta `v0.3.4-beta.1`, el borrador de la release que deja la CI con los paquetes de los tres sistemas, y el `.dmg` en el cask `openward` de `kaicorplabs/tap`. Su borrador no se publica: el paquete de Windows tenía AM-1, y la 0.3.4-beta.2 lo sustituye con los arreglos de D0.

## Etapa 2 · v0.4, el vault cifrado

El plan de la [v0.4](v0.4.md) tal cual (D0–D8), con tres ajustes que salen de este:
- **La clave de cuenta piensa en el servidor desde el principio.** La v0.4 guarda, además del vault, un paquete con la clave de cuenta, que es lo que la etapa 4 sube para dar de alta otros equipos. Va envuelto con la contraseña y con un secreto del kit, no solo con la KEK, para que con el paquete solo no se puedan probar contraseñas ([D0-1](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0)). El certificado del dispositivo admite más adelante claves de hardware (Secure Enclave, Keystore).
- **Desbloqueo en los tres sistemas:** Windows Hello y el llavero de Linux (libsecret) entran en la v0.4, no después. La Community sale en los tres.
- **Claves en el Secure Enclave (Touch ID)** junto al desbloqueo con Touch ID en D4. Si el llavero con biometría exige firmar con Developer ID, la cuenta de desarrollador de Apple hará falta antes del lanzamiento, aunque la notarización siga para entonces.

Las decisiones de la v0.4 (contraseña maestra obligatoria y «Más tarde» durante la beta, entre otras) y las tres de su modelo de amenazas están aceptadas desde el 2026-11-10. La sync de la etapa 3 confirma que la contraseña y el kit hacen falta.

D8 prepara `0.4.0-beta.1+31`, onboarding y Ajustes › Seguridad. La [guía](prueba-v0.4.md) mantiene pendientes la semana de uso, migraciones personales y autenticación física; #37/#33 siguen sus puertas. Preparar la candidata no publica una release.

## Etapa 3 · v0.5, el motor de sync

**Seguimiento:** [#38](https://github.com/KaiCorpLabs/openward/issues/38); contrato #62, UX #64 y seguridad #65. Hay implementación y pruebas locales sin publicar: no está integrado en main y no cierra este hito.

El motor de [ADR-005](../adr/ADR-005-sync-por-registros-de-dispositivo.md), sin backends de almacenamiento propio. Hasta el 2026-11-13 esta etapa era «sync con tu almacenamiento» y traía los backends gratuitos (carpeta, S3 y WebDAV). Se quitaron al decidir que toda la sync es de pago y alojada ([revisión de ADR-005](../adr/ADR-005-sync-por-registros-de-dispositivo.md#revisión-del-2026-11-13)): el único backend es el servidor de la etapa 4.

Sigue yendo antes del servidor por dos razones:
- el motor se puede probar entero sin servidor, con un backend de pruebas;
- el servidor será el backend de ese mismo motor, sin un segundo protocolo.

| # | Hito | Semanas |
|---|---|---|
| S1 | `openward-sync`: registros por dispositivo, segmentos firmados, merge por campo, lápidas y cursores, con un backend de pruebas (en memoria y en un directorio) que la app no ofrece. Puerta de ADR-005: 3 dispositivos × 10.000 ediciones con `proptest` convergen al 100 % | 2 |
| S4 | Equipos: añadir uno con un código o un QR desde otro que ya está dentro (o con el kit), ver la lista y revocar uno | 0,5 |
| S5 | Ajustes › Sincronización: estado («última sync hace 3 min»), conflictos con la versión que perdió e historial de un ítem | 0,5 |
| S6 | Compactación y poda, `openward-cli` para simular N dispositivos, formato en `spec/`, notas y beta | 0,5 |

- **S2 y S3 ya no existen:** eran el backend de carpeta y los de S3 y WebDAV. Los demás hitos conservan su número, porque otros documentos los citan.
- **La sync no se enciende en la app hasta la etapa 4,** porque no hay backend que elegir. S4 y S5 se construyen y se prueban contra el backend de pruebas, y C5 las conecta a la cuenta.
- **Qué se sincroniza por defecto:** todo el vault (hosts, grupos, identidades, claves y contraseñas guardadas, snippets, túneles y workspaces). El historial y los registros se quedan en cada equipo; sincronizarlos será opcional y más adelante.

## Etapa 4 · v0.6, servidor y cuentas de KaiCorp Labs

El título conserva su ancla histórica. La identidad vigente es **Supabase Auth gestionado para OpenWard**; no depende de una cuenta previa de KaiCorp ni de su antigua identidad autoalojada. [ADR-010](../adr/ADR-010-monorepo-go-supabase.md) sustituye ese diseño.

### Responsabilidades

- **Supabase:** identidad y persistencia gestionadas. Un solo proyecto de producción por ahora; los ensayos locales desechables no son otro proyecto de staging. Aislamiento de datos, migraciones y permisos se revisan en #39/#40/#65.
- **Go mínimo en el monorepo:** autorización de dispositivos y sync, sesiones vigentes, relay, entitlement y webhooks que necesiten autoridad de servidor; no duplicar Auth ni abrir directamente las tablas privadas para conseguir una prueba positiva.
- **Rust:** vault, cifrado, firmas y convergencia. La contraseña maestra y el kit no salen del dispositivo. Edge Functions queda como alternativa secundaria para piezas acotadas, sin un segundo backend paralelo.
- **Flutter:** cuenta, dispositivos, estado de sync y plan de #64, con el mismo núcleo en escritorio y móvil. Su implementación local aún requiere integración revisada con main.

### Cuenta, dispositivo y recuperación

El contrato #62 debe fijar identidad estable por emisor+sujeto, callbacks por plataforma y protecciones del flujo elegido (PKCE/state/nonce cuando corresponda). El loopback de escritorio no se copia al móvil; Android/iOS requieren sus callbacks propios. No se declara cerrado un flujo OIDC intermediado por Go.

**Cuenta, dispositivo, descifrado y pago son autoridades distintas.** Acceder por correo no recupera el vault ni autoriza por sí solo un equipo. El paquete remoto OWRP actual requiere contraseña maestra+kit; una copia local `.owvault` admite recuperación con kit. El kit no es una copia de los datos ni recupera una clave de hardware perdida. Pérdida de todos los equipos y olvido de contraseña requieren decisión y prueba antes de prometer recuperación remota solo con kit.

El helper de sesión aplicado en Supabase es una comprobación acotada; no acredita admisión/posesión, revocación completa ni exclusión de claves conservadas. El rol backend limitado y RLS no sustituyen las pruebas de autorización A/B en el servidor. La API permanece cerrada y `design_pending` hasta resolver estas puertas.

### Hitos conservados

| # | Hito actualizado | Seguimiento / cierre |
|---|---|---|
| C1 | Contrato API/fixtures, recuperación, posesión, sesiones y callbacks; ADR-010 registra solo decisiones ya confirmadas | #62; contrato aún pendiente |
| C2 | Go mínimo y migraciones Supabase en el monorepo, permisos mínimos y CI del árbol integrado | #39; trabajo local y esquema aplicado no equivalen a integración |
| C3 | Registro/login, dispositivo, logout/revocación, paquete de cuenta y borrado | #39/#62/#65; Auth alojado aún sin validar |
| C4 | Relay put/get/list/watch, cursores, cuotas, límites, aislamiento A/B y entitlement | #38/#39/#63; prueba contra relay real |
| C5 | Cuenta, alta de equipo, sync/conflictos y plan en Flutter; uso/exportación locales disponibles | #64; onboarding alojado y matriz escritorio↔móvil pendientes |
| C6 | Integración exacta de cliente/Go/Supabase, convergencia y pruebas antes de abrir servicios | #39/#42; OVH previsto sin despliegue |

## Etapa 5 · v0.7, abierto: el servidor en producción

**Seguimiento:** [#40](https://github.com/KaiCorpLabs/openward/issues/40). Supabase gestionado ya tiene el esquema indicado arriba; el runtime Go en OVH aún no está desplegado. No hay servicio de sync abierto ni cobros activos.

| # | Hito actualizado | Evidencia necesaria |
|---|---|---|
| M1 | Runtime Go en la infraestructura prevista, dominio y acceso público aprobados, TLS y WebSocket | Despliegue reproducible, permisos y secretos mínimos; no depender del minipc doméstico |
| M2 | Backups cifrados, restauración limpia, observabilidad, límites, migración/rollback y borrado | RPO/RTO medidos, alertas/runbooks y fallo del servicio sin impedir uso local |
| M3 | Términos, privacidad, soporte y operación del trial/pago | #63/#66 y revisión de #42/#65 antes de usuarios externos y cobro |

No se presupone un segundo proyecto Supabase para staging. El aislamiento de ensayos, la restauración y el paso a producción deben concretarse sin ensayar operaciones destructivas sobre producción. Los borradores de runbooks y pruebas locales no acreditan operación real.

## Después de este plan

El [plan de lanzamiento](lanzamiento.md) coordina también los frentes que ya pueden prepararse contra contratos/fixtures:

- **Distribución #41:** firma/notarización, actualizaciones autenticadas, paquetes, instalaciones y descargas trazables.
- **Móvil #68:** implementación integrada por #69; dispositivos físicos, S1.2/S2/S3/S5, firma, tiendas y cuenta/sync/pago pendientes.
- **Cobro #63:** 4,99 €/mes o 49 €/año, 14 días sin tarjeta; proveedor, checkout/webhooks y rutas de tienda por cerrar, sin activar cobros por documentarlo.
- **Seguridad #65:** modelo integrado, recuperación/revocación y auditoría externa antes de cobrar.
- **Presentación/legal #66:** web y docs honestas con la candidata, soporte, privacidad/términos, licencia/CLA y marca revisadas. La licencia actual sigue con todos los derechos reservados; el monorepo no decide por sí solo la licencia o publicación del servidor.
- **Más adelante:** agente SSH/CLI, equipos/IA y Enterprise; no son una fecha comprometida de esta beta.

## Decisiones del 2026-11-13

Decisiones confirmadas, reconciliadas el 2026-11-14 con #62/#67 y [ADR-010](../adr/ADR-010-monorepo-go-supabase.md):

1. Community completa en local sin cuenta; toda la sync de pago y alojada, sin almacenamiento propio ni servidor autoalojable.
2. Monorepo único con Flutter escritorio/móvil, núcleo Rust y servidor Go mínimo. Sustituye el repositorio backend separado.
3. Supabase gestionado para Auth/datos, un proyecto de producción por ahora; Edge Functions como alternativa secundaria.
4. Precio **4,99 €/mes o 49 €/año** y prueba **14 días sin tarjeta**. No quedan por decidir precio ni duración.
5. OVH previsto para Go, aún sin desplegar. No hay obligación vigente de minipc/tailnet ni identidad KaiCorp autoalojada.
6. Android/iOS forman parte del producto sincronizado y son puerta del pago. #67 fija la beta con pago desde la salida, condicionada a toda la evidencia; no promete una fecha ni acredita distribución móvil.

La revisión anterior que exigía servidor privado fuera de este repositorio queda como historia en ADR-006/007. La conciliación de licencias/publicación sigue pendiente; este cambio solo publica documentación.

## Decisiones por defecto (a confirmar)

Esta ancla conserva los enlaces existentes; las diez propuestas originales ya no son diez decisiones abiertas. No se reabren las decisiones confirmadas de arriba.

**Pendiente en #62/#63/#65/#66:**

- Inicio exacto del trial, fiscalidad, vendedor, mercados, retención/gracia y rutas de pago por tienda.
- Enrolamiento/posesión, recuperación remota, generaciones/rotación y exclusión criptográfica de dispositivos revocados.
- Contrato/callbacks por plataforma y qué datos sincronizar. Inventario inicial: hosts, grupos, identidades, claves exportables/contraseñas guardadas, snippets, túneles y workspaces; historial, grabaciones, ajustes por equipo y archivos externos requieren exclusión/inclusión explícita. Hardware: solo referencias/públicas, nunca privadas.
- Configuración operativa de OVH/Supabase, aislamiento de ensayos, restauración y soporte; licencia/CLA, marca y revisión legal antes de publicar.

Se conservan como historia las elecciones de etapa 1 y las puertas del vault. El registro/login de cuenta no sustituye el desbloqueo del vault; no se promete recuperación por correo ni exclusión criptográfica por denegar un token.

## Riesgos

| Riesgo | Puerta |
|---|---|
| Confundir main, laboratorio y Supabase aplicado | Evidencia por revisión exacta y nivel en [estado.md](estado.md); CI completa del árbol que se proponga integrar |
| Un merge, retry o crash pierde datos | #38: convergencia y durabilidad en backend de pruebas y relay real |
| JWT válido tras logout o revocación | #39/#65: denegación alojada verificable y control de cada ruta; helper aplicado no basta |
| Equipo revocado conserva claves | #62/#65: posesión, generaciones y rotación/exclusión criptográfica antes de abrir |
| Recuperar cuenta se interpreta como recuperar vault | #62/#64: autoridades separadas y límites OWRP/kit claros |
| CI/simuladores se toman por pruebas físicas | #33/#37/#42/#68: dispositivos reales, biometría, hardware y uso prolongado |
| Producción con un proyecto y sin restauración ensayada | #40: aislamiento de pruebas, backup/restauración y operación demostrada |
| Cobro o distribución sin candidata verificada | #41/#42/#63/#65/#66: firma, checkout, auditoría, legal y go/no-go explícitos |
