# Camino a la Community: lo básico completo y la sincronización

- **Estado (2026-11-13):** etapa 1 implementada; pruebas de hardware y uso real pendientes. La etapa 2 tiene D0–D3 y D5–D7 completados, la sesión de D4 y el onboarding/Ajustes de D8 integrados, con candidata `0.4.0-beta.1+31` y KDF validada en los tres sistemas. [#33](https://github.com/KaiCorpLabs/openward/issues/33) conserva maquetas y autenticación física; la firma SSH en Secure Enclave está implementada ([contrato y límites](../../spec/secure-enclave-ssh-v1.md)); [#37](https://github.com/KaiCorpLabs/openward/issues/37), migraciones personales, uso cifrado y recuperación independiente. Las etapas 3–5 siguen pendientes: el spike S4 no es el motor de sync de producción. Las decisiones de v0.4 están aceptadas; las diez del plan Community siguen por confirmar. El 2026-11-13 se decidió que toda la sync es de pago y alojada, sin backends de almacenamiento propio ni servidor autoalojable: las etapas 3 a 5 están revisadas con eso ([decisiones del 2026-11-13](#decisiones-del-2026-11-13)). Cada hito con interfaz nueva conserva la revisión de sus maquetas. [Estado y evidencia](estado.md).
- **Fecha:** 2026-11-06.
- **Base:** fases 1 y 2 de la hoja de ruta ([ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas)) y los ADR [004](../adr/ADR-004-vault-y-jerarquia-de-claves.md) (vault), [005](../adr/ADR-005-sync-por-registros-de-dispositivo.md) (sync), [006](../adr/ADR-006-servidor-open-core.md) (servidor) y [009](../adr/ADR-009-mosh-clean-room.md) (Mosh). Incluye el plan de la [v0.4](v0.4.md) como etapa 2, con tres ajustes.
- **Duración estimada:** unas 28 semanas de plan en cinco etapas (la etapa 3 perdió semana y media el 2026-11-13). Son estimaciones al estilo de los planes anteriores: la 0.2 y la 0.3 fueron bastante más rápidas que lo que decían sus planes.

## Objetivo

Llegar a una versión de escritorio que se pueda lanzar como **Community**, la edición gratuita, y dejar hecha la base del servicio de pago, que es la sincronización:
- **todo lo que hoy se espera gratis de un cliente SSH moderno**, en macOS, Windows y Linux;
- **el vault cifrado** con contraseña maestra, kit de recuperación y desbloqueo con biometría;
- **sincronización E2EE entre equipos**, con una cuenta en nuestro servidor. Es el servicio de pago y no forma parte de la Community: la cuenta es gratuita y trae un periodo de prueba de la sync, y la app funciona entera sin cuenta. No hay sync con el almacenamiento de cada cual ni servidor autoalojable (decidido el 2026-11-13);
- **el servidor funcionando con las cuentas de KaiCorp Labs** (`id.kaicorplabs.com`, Supabase Auth autoalojado), que ya existen y ya usan las demás apps de la casa: OpenWard no construye registro ni inicio de sesión propios.

**Orden acordado (2026-11-06):**
1. primero esto: lo básico, el vault y la sync;
2. después, el lanzamiento: la web, la firma y la notarización, y lo demás de «Después de este plan»;
3. y Android e iOS, cuando esto esté listo. Desde el 2026-11-13, además, antes de cobrar por la sync: el producto de pago es el mismo cliente sincronizado en el móvil y en el escritorio.

Ese mismo día se descartó montar Postgres y Supabase Auth aparte para OpenWard: la identidad de KaiCorp Labs ya es Supabase Auth y corre en el minipc de la casa.

**Puerta de salida del plan:**
- el equipo usa OpenWard dos semanas como único cliente SSH en macOS, Windows y Linux, sin echar en falta nada de la etapa 1;
- dos equipos de cada persona se sincronizan por la cuenta. Con ediciones a la vez y sin conexión, convergen sin perder nada, y los conflictos se ven;
- se entra con una cuenta de KaiCorp Labs, se añade un segundo equipo y se recupera el vault en un tercero con el kit. El servidor no ve nunca la contraseña maestra ni nada en claro, y se comprueba en sus tablas y registros;
- una persona de fuera del equipo crea su cuenta, recibe la membresía de OpenWard y sincroniza contra el servidor público en su periodo de prueba. El servidor tiene copias, vigilancia y borrado de una persona como los demás servicios de la casa;
- `THREAT_MODEL.md` cubre el servidor y las cuentas.

## Etapas

| Etapa | Versión | Contenido | Semanas |
|---|---|---|---|
| 1 | 0.3.4 y siguientes | [Lo básico completo](#etapa-1--lo-básico-completo) (P0–P7) | ~9 |
| 2 | 0.4 | [El vault cifrado](#etapa-2--v04-el-vault-cifrado) ([v0.4.md](v0.4.md), D0–D8) | ~9 |
| 3 | 0.5 | [El motor de sync](#etapa-3--v05-el-motor-de-sync) (S1 y S4–S6) | ~3,5 |
| 4 | 0.6 | [Servidor y cuentas de KaiCorp Labs](#etapa-4--v06-servidor-y-cuentas-de-kaicorp-labs) (C1–C6) | ~5 |
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

**Lo que falta:**

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

### Las cuentas ya existen

La identidad de KaiCorp Labs es **Supabase Auth autoalojado**, que hace de proveedor OAuth 2.1 y OIDC (`https://id.kaicorplabs.com/auth/v1`). Su app de cuenta (`account.kaicorplabs.com`) ya hace todo lo que OpenWard necesitaría construir:
- el registro con confirmación por correo;
- la entrada, con segundo factor opcional (passkey o TOTP);
- la recuperación y el cambio de correo;
- las membresías por aplicación, que se comprueban en la pantalla de consentimiento;
- la administración.

Las demás apps de la casa entran con OIDC genérico por discovery. OpenWard es una más: **no tiene registro ni contraseñas propios**.

### El servidor

- El servidor, en Go y **privado**: no se publica ni se autoaloja, y su código va en un repositorio privado, no en este ([ADR-006](../adr/ADR-006-servidor-open-core.md#revisión-del-2026-11-13), [ADR-007](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-13)).
- Módulos mínimos: `identity`, `objects`, `realtime` y `admin`.
- Postgres con `sqlc` y migraciones. El `Store` en SQLite, que estaba para autoalojar con un único binario, deja de ser un requisito: C1 decide si se conserva para las pruebas.
- **El relay es el backend** del motor de la etapa 3 (`put`, `get`, `list` y `watch` por WebSocket), y el único: el cliente no tiene un segundo protocolo de sync.
- **Un cliente OIDC genérico**, configurado por discovery y sin nada exclusivo de Supabase, contra la identidad de KaiCorp Labs. Así, mover la identidad a otro sitio es trabajo de operación, no de código.
- **La cuenta es gratuita y trae un periodo de prueba de la sync;** después, sincronizar pide el plan de pago (decidido el 2026-11-13). La duración de la prueba está por decidir, y el cobro va aparte ([«Después de este plan»](#después-de-este-plan)).
- **La base de datos es suya**, un Postgres aparte del de la identidad: lo que guarda la sync no se mezcla con las cuentas y se copia y se restaura por separado.

### Cómo entra la app de escritorio

1. La app abre el navegador del sistema en el servidor (`/v1/login`).
2. El servidor hace el flujo OIDC con la identidad, como cliente confidencial con PKCE, igual que las otras apps de la casa. El canje del código va por la red interna, sin salir a internet.
3. Al volver, el servidor entrega a la app un código de un solo uso por una redirección a `127.0.0.1` (el patrón de RFC 8252 para apps nativas).
4. La app lo cambia por una sesión ligada a su clave de dispositivo.

Hay tres ventajas:
- en la identidad solo se registra la dirección de vuelta del servidor;
- la app no habla nunca con el emisor, así que no le afecta la comprobación de navegador de Cloudflare en `id.kaicorplabs.com`;
- cambiar de proveedor de identidad no pide tocar la app.

### Qué guarda el servidor, y qué no

- **La cuenta se identifica por el `sub`** del token, nunca por el correo, que puede cambiar.
- **La cuenta identifica, no descifra.** El vault se sigue abriendo en el equipo con la contraseña maestra, que **no sale nunca del equipo**, tampoco derivada: la identidad no la conoce. Así:
  - recuperar el acceso a la cuenta por correo no toca el cifrado;
  - olvidar la contraseña maestra se resuelve con el kit, nunca borrando el vault.
- **Guarda:**
  - las claves públicas de la cuenta y los certificados de cada dispositivo;
  - los segmentos cifrados;
  - el paquete de la clave de cuenta, envuelto con la contraseña y con el secreto del kit ([D0-1](../THREAT_MODEL.md#11-decisiones-que-salen-de-d0)). Nada de lo que guarda se abre con la contraseña sola, así que quien lo robe no puede probar contraseñas.
  
  Para añadir un equipo nuevo: se entra con la cuenta, se descarga el paquete y se abre con la contraseña maestra y el kit (o se aprueba desde otro equipo, como en S4). Si hace falta también una copia que abra el kit solo, para recuperar sin contraseña y sin ningún equipo, lo decide C1.
- **Cada sesión lleva la firma del dispositivo**, un desafío firmado ([ARCHITECTURE §7.1](../ARCHITECTURE.md#71-monolito-modular)). Un equipo revocado no entra aunque conserve el token.

### Dónde corre

- En el minipc de la casa, donde ya están la identidad y los demás servicios. Se despliega como ellos: imagen en GHCR que pasa Trivy, variables y secretos con las herramientas de la casa, y su red OIDC con la pasarela de la identidad.
- **Hasta la etapa 5, solo en el tailnet** (`tailscale serve`) y solo para el equipo: la membresía de OpenWard solo la tienen sus personas.
- **En revisión (2026-11-13):** dónde se alojará el servicio en producción no está decidido. Hasta entonces, este apartado y la etapa 5 valen como están.

| # | Hito | Semanas |
|---|---|---|
| C1 | ADR-010 (cuentas y servidor), modelo de amenazas del servidor, API v1 en `spec/`, y el cliente OAuth y la membresía de OpenWard dados de alta en la identidad. Decide también si el `Store` en SQLite se conserva para las pruebas | 0,5 |
| C2 | El servidor, en su repositorio privado: esqueleto, `Store` en Postgres, migraciones, objetos, CI (`go test`) e imagen | 1 |
| C3 | Entrar: OIDC por discovery, el traspaso a la app por `127.0.0.1`, la cuenta por `sub`, certificados de dispositivo, el paquete de la clave, salir y borrar los datos de la cuenta | 1 |
| C4 | Relay: el backend del cliente, `watch` por WebSocket, cuotas y límite de peticiones | 1 |
| C5 | App: Ajustes › Cuenta (entrar con la cuenta de KaiCorp Labs, dispositivos y salir; el registro y el segundo factor se hacen en la app de cuenta), alta de un equipo nuevo por la cuenta y estado de la sync en tiempo real. Aquí se enciende la sync en la app, con S4 y S5 de la etapa 3 | 1 |
| C6 | Despliegue en el minipc (solo en el tailnet), prueba de punta a punta con 3 dispositivos contra el relay (la segunda parte de la puerta de ADR-005), notas, guía y beta | 0,5 |

## Etapa 5 · v0.7, abierto: el servidor en producción

El servidor sale del tailnet para que entre gente de fuera del equipo, al estándar de los demás servicios de la casa.

| # | Hito | Semanas |
|---|---|---|
| M1 | Dirección pública por el túnel de Cloudflare, con el WebSocket a través de él (pings por debajo del límite de inactividad). Es la dirección estable que guardan los clientes: un dominio propio de OpenWard (decidido el 2026-11-10) | 0,5 |
| M2 | Al estándar de la casa: copias nocturnas comprobadas, vigilancia, el borrado de una persona también en OpenWard e imágenes firmadas | 0,5 |
| M3 | Términos y privacidad (hay datos de personas de fuera), la membresía de OpenWard para quien la pida, notas y beta | 0,5 |

Quien entra en esta etapa sincroniza en su periodo de prueba: el plan de pago todavía no existe ([decisiones del 2026-11-13](#decisiones-del-2026-11-13)).

**Supabase en la nube no hace falta para esto.** Solo tendría sentido si un día el minipc se queda corto. Como el servidor no usa nada exclusivo de Supabase, mover la identidad o la base a otro sitio sería trabajo de operación, no de código.

## Después de este plan

Lo que queda para lanzar y que este plan no hace. El [plan de lanzamiento](lanzamiento.md) lo ordena por prioridad junto con las etapas de arriba:
- **Web y distribución:**
  - la web, en el dominio propio de OpenWard que usa M1, y la documentación pública;
  - firma y notarización en macOS y firma en Windows;
  - actualizaciones automáticas (Sparkle, WinSparkle);
  - Flatpak, AppImage y .deb; winget y Scoop.
- **Repositorio:**
  - el repo público, con la CI completa;
  - la licencia del lanzamiento (GPL-3.0 en el cliente; el servidor es privado), la CLA en todo el repositorio y el registro de la marca ([ADR-007](../adr/ADR-007-licencias-y-contribuciones.md#revisión-del-2026-11-13));
  - el canal de `SECURITY.md`;
  - la lista «Siempre gratis», cerrada: el cliente completo en local y la exportación, sin la sync.
- **Legal:** el análisis de la Ley de Ciberresiliencia (CRA).
- **Móvil:** Android e iOS, después del lanzamiento de escritorio y antes de cobrar por la sync (2026-11-13). Antes, el spike S1.2 (el motor en dispositivos reales): es la condición pendiente de [ADR-002](../adr/ADR-002-motor-de-terminal.md).
- **Cobro.** Toda la sync es de pago, y hasta aquí ha funcionado en periodo de prueba:
  - el plan de pago de la sync y el final del periodo de prueba, en el repositorio privado `openward-cloud`;
  - las apps de Android e iOS, publicadas;
  - auditoría externa del cifrado y la sync antes de cobrar por ella.
- **Producto:**
  - informes de fallos con consentimiento y un canal de opiniones;
  - el agente SSH y la CLI `ow`.

## Decisiones del 2026-11-13

Decididas, no por confirmar:
1. **Toda la sync es de pago y alojada.** La Community, la edición gratuita, es el cliente completo funcionando en local. No hay sync con almacenamiento propio (carpeta, S3, WebDAV, Git).
2. **No hay servidor autoalojable, y el servidor es privado:** no se publica al lanzar ([ADR-006](../adr/ADR-006-servidor-open-core.md#revisión-del-2026-11-13)).
3. **La v0.5 se queda como el motor de sync,** sin backends: la convergencia de ADR-005, añadir y revocar equipos, la pantalla de sync y el formato. El servidor de la v0.6 es el único backend ([ADR-005](../adr/ADR-005-sync-por-registros-de-dispositivo.md#revisión-del-2026-11-13)).
4. **Android e iOS van antes de cobrar.** La Community de escritorio se lanza primero, y las apps móviles son condición del plan de pago.
5. **La cuenta es gratuita y trae un periodo de prueba de la sync.** La app sigue funcionando entera sin cuenta.

Quedan abiertas:
- la duración del periodo de prueba, y el precio del plan;
- dónde se aloja el servicio en producción. Los planes de las etapas 4 y 5 siguen como estaban hasta que se decida;
- cómo funciona la sync entre la etapa 5 y el plan de pago. Por defecto, y a confirmar: en periodo de prueba para todas las cuentas, sin prometer sync gratuita.

## Decisiones por defecto (a confirmar)

1. La etapa 1 va antes que la v0.4, por los datos nuevos de los hosts; D0–D2 van en paralelo.
2. Mosh en escritorio con el `mosh-client` instalado en el equipo (revisión de ADR-009); el cliente clean-room sigue para el móvil y Windows.
3. Autocompletado local, sin IA; la IA llega en la fase 3.
4. El motor de sync va antes que el servidor, que es su único backend. Hasta el 2026-11-13 decía «la sync gratuita (carpeta, S3, WebDAV) va antes que el servidor; Git, después».
5. Las cuentas de OpenWard son las de KaiCorp Labs: una sola cuenta para todas las apps de la casa, con su registro, segundo factor y membresías.
6. La cuenta identifica, no descifra: la contraseña maestra no sale del equipo, ni siquiera derivada.
7. El servidor es un cliente OIDC genérico y la app no habla nunca con el emisor: entra a través del servidor.
8. La base de datos de OpenWard va aparte de la de la identidad.
9. En el minipc y solo en el tailnet hasta la etapa 5.
10. Se sincroniza todo el vault menos el historial y los registros.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| FIDO2 difícil de probar en la CI | Un autenticador por software en las pruebas automáticas y una llave real a mano antes de cerrar P3 |
| Touch ID y el Secure Enclave exigen una app firmada con Developer ID | Comprobarlo la primera semana de D4 (ya está en los riesgos de la v0.4); si hace falta, la cuenta de desarrollador de Apple antes de lo previsto |
| Mosh: falta `mosh-client` o el UDP está bloqueado | Se detecta y se vuelve a SSH con tmux, con un aviso claro |
| Las codificaciones heredadas confunden al motor | Traducir en el núcleo antes del motor; pruebas con vttest en Latin-1 y CP437 |
| El merge pierde datos | La puerta de ADR-005 (`proptest`) antes de la interfaz, y la prueba de punta a punta contra el relay en C6 |
| Un fallo de la identidad deja a OpenWard sin cuentas, y a las demás apps también | La app funciona entera en local sin cuenta, y lo ya sincronizado sigue en cada equipo; la identidad ya tiene copias y vigilancia |
| Cloudflare corta los WebSocket inactivos | Pings por debajo del límite y reconexión del `watch` sin perder el cursor |
| El minipc se queda corto (Intel N150, 32 GB, con los demás servicios) | Medir en C6 con el equipo; los segmentos pueden pasar a almacenamiento S3 sin tocar el cliente |
| Confundir el acceso a la cuenta con la contraseña del vault | Dos nombres distintos en la interfaz («tu cuenta de KaiCorp Labs» y «la contraseña del vault»); el correo de recuperación de la cuenta no promete nunca recuperar el vault |
