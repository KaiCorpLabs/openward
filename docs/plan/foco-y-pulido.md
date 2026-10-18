# Foco y pulido: 0.3.0-beta.3, 0.3.0-beta.4 y v0.3.1

- **Estado:** primera y segunda fase hechas y publicadas (0.3.0-beta.3 y 0.3.0-beta.4); la tercera (v0.3.1), hecha y en revisión, sin publicar. Maquetas aprobadas el 2026-10-18 (filas «F1» a «F5» del lienzo); el reparto en fases, aceptado el mismo día y ajustado después de la beta.3.
- **Fecha:** 2026-10-18.
- **Base:** fase 1 de la hoja de ruta ([ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas)), sobre la [v0.3](v0.3.md) y antes de la v0.4 (el vault cifrado).
- **Duración estimada:** unas 5 semanas de trabajo: 1,5 la primera fase, 2 la segunda y 1,5 la tercera.

## Objetivo

Con la v0.3 la fase 1 tiene casi todas sus funciones. Una revisión de las pantallas con las capturas de las pruebas de ventana dejó claro que lo que más falta no son funciones, sino espacio, orientación y coherencia:
- **el terminal nunca tiene toda la ventana:** la barra lateral mide 272 px fijos y no se pliega; a 1280 px de ancho ocupa el 21 % de la ventana durante la sesión, y con dos paneles cada uno se queda en unos 500 px;
- **nada distingue un servidor de producción de uno de pruebas** una vez abierta la pestaña, y las filas de host son solo texto, sin favoritos ni recientes;
- **la pantalla de inicio repite acciones** que ya están en la barra y en la paleta, en un área casi vacía;
- **dos buscadores se pisan:** ⌘K busca hosts en la barra y ⌘P abre la paleta, que también busca hosts;
- **la barra de estado enseña primero lo que menos se mira** (los algoritmos completos) y corta la latencia, que ya se mide;
- **el editor de host es denso**, y hay iconos, verbos y estados que se contradicen.

Se reparte en tres fases; las dos primeras no tocan el vault:
- **Fase 1 (0.3.0-beta.3):** la barra plegable, ⌘K y la latencia, y el pulido. Entró en la prueba de la 0.3.
- **Fase 2 (0.3.0-beta.4):** el editor de host nuevo, el inicio sin los favoritos y lo que quedó de la primera fase. Solo interfaz, también dentro de la prueba de la 0.3.
- **Fase 3 (v0.3.1):** el entorno, el sistema y los favoritos, que añaden campos al vault. Va antes de que la v0.4 migre el vault al formato cifrado, para migrar una vez y con los campos ya definitivos; los secretos de la v0.4 entran en el editor nuevo de la segunda fase.

Sigue siendo solo escritorio y sin cuenta.

**Puerta de salida de la fase 1:**
- el equipo trabaja una semana con la barra en raíl u oculta durante las sesiones y la recupera con ⌘B o al acercar el ratón, sin buscarla;
- quien buscaba hosts con ⌘K sigue haciéndolo igual (escribir y Intro), y salta a pestañas y acciones desde ahí;
- la latencia se lee en la barra de estado y el ámbar no se confunde con un fallo;
- las pruebas de ventana, la de accesibilidad (texto de 12 px como mínimo) y la galería pasan sin regresiones.

**Puerta de salida de la fase 2:**
- en el editor, cambiar un valor heredado y volver a heredarlo se hace sin «Cambiar», y las pruebas de interfaz están reescritas para el editor nuevo;
- el día empieza desde el inicio (los recientes y la conexión rápida que completa) sin abrir la barra;
- la tarjeta de la latencia dice la de cada salto en una ruta con saltos.

**Puerta de salida de la fase 3:**
- cada persona marca sus grupos de producción y lo ve en la barra, en las pestañas y en los terminales;
- los hosts Debian y Ubuntu muestran su sistema por el banner sin ejecutar nada; los demás, al activar la lectura de `/etc/os-release` o al elegirlo a mano;
- los favoritos, arriba en la barra, en el raíl y en el inicio.

## Alcance

**Fase 1 · 0.3.0-beta.3:**
- **Modo foco** (F1):
  - la barra lateral con tres estados: abierta, raíl (56 px: buscar, los favoritos y los hosts con sesión abierta, «Todos los hosts», la Biblioteca en iconos y Ajustes) y oculta;
  - ⌘B la pliega y la abre; en Windows y Linux, sin atajo (Ctrl+B es del shell y Ctrl+Mayús+B es broadcast): su botón y la paleta. El estado se recuerda;
  - oculta, se asoma al acercar el ratón al borde izquierdo, por encima del terminal, y se esconde al apartarlo; «Fijar» la deja abierta;
  - con la barra en raíl u oculta, las pestañas suben junto a los botones de la ventana;
  - el ancho se cambia arrastrando el borde, entre 220 y 420 px;
  - Ajustes › General › Ventana: el estado de la barra, qué hacer al abrir una sesión (dejarla como esté, pasar a raíl u ocultarla; al volver al inicio o a una página se abre otra vez), el ancho y el margen del terminal;
  - el margen alrededor del texto del terminal pasa de 6 a 12 px, ajustable de 0 a 24 px.
- **Un solo ⌘K y la latencia a la vista** (F4):
  - ⌘K abre la paleta; ⌘P y ⌘⇧P siguen abriéndola. En Windows y Linux, Ctrl+Mayús+K y Ctrl+Mayús+P (Ctrl+K a secas llega al shell);
  - sin escribir, la paleta enseña las pestañas abiertas (con ⌘1…⌘9), los recientes y las acciones que más se usan;
  - al escribir van primero las pestañas y los hosts, luego los snippets, el historial y las acciones; `>` deja solo las acciones;
  - el buscador de la barra pasa a ser «Filtrar hosts», un filtro de la lista sin atajo propio;
  - la barra de estado: «Conectado», «poscuántico» si lo es, la latencia y una minigráfica de los últimos 5 minutos; Snippets y SFTP en iconos atenuados con su atajo;
  - al pasar el ratón por la latencia: la gráfica, la ruta con la latencia de cada salto, el intercambio, el cifrado y la clave del host; al hacer clic, el diálogo de la conexión de siempre;
  - al pasar el ratón por una pestaña: el host, su dirección y ruta y la latencia.
- **Pulido de consistencia** (F5a):
  - el candado abierto y en ámbar para las claves sin frase de paso;
  - «Detener» para un túnel abierto, y «Detenido» como estado;
  - los nombres de grupo tal como se escribieron: mayúsculas solo en las etiquetas fijas (BIBLIOTECA);
  - la acción principal de cada página, arriba a la derecha (Túneles, Claves, Identidades, Snippets, Espacios de trabajo);
  - el color de acento solo para lo vivo, lo elegido y la acción principal; los enlaces, en el color del texto;
  - texto de 12 px como mínimo (la barra de estado y las etiquetas de sección bajan hoy a 10–11 px);
  - un botón deshabilitado dice por qué («Abre alguna pestaña para poder guardarla»);
  - la Biblioteca sin contadores a cero;
  - «Ver la cola» al final de su fila;
  - la tarjeta «Conectando con…» solo si la conexión pasa de 400 ms, y sin repetir el camino en una lista; antes, solo el indicador de la pestaña;
  - cada botón de icono, con su nombre y su atajo al pasar el ratón.

**Fase 2 · 0.3.0-beta.4:**
- **La tarjeta de la latencia** dice la de ahora en grande y lleva la escala a un lado (arreglo de la beta.3).
- **Editor de host más ligero** (F5b):
  - los valores heredados se editan en su sitio: borde discontinuo y de dónde vienen («de Producción», «por defecto»); al escribir, el borde pasa a continuo con «aquí · heredaría …» y un botón ↺ que vuelve a heredar. Sin los enlaces «Cambiar»;
  - una leyenda de una línea en lugar del párrafo, con el orden de la herencia en un (i);
  - una sola rejilla, con la etiqueta a la izquierda;
  - «Avanzado» plegado: proxy, keepalive, sesión persistente, al salir del shell, túneles, variables, `TERM` y agente;
  - lo mismo en el editor de grupos y en el de identidades;
  - los enlaces, en el color del texto en toda la app (lo que quedó de F5a).
- **Inicio** (F3, sin los favoritos):
  - la conexión rápida arriba, que completa con los hosts guardados y las direcciones ya usadas sin guardar, con «Conectar tal cual» (⌥Intro) y «Guardar como host…»;
  - **Recientes**: cuándo y cuánto duró cada conexión, y si fue con tmux; Intro conecta, ⌘Intro en un panel nuevo;
  - los túneles abiertos, con «Detener»;
  - los atajos principales en una línea;
  - el primer día, «Para empezar» (terminal local, host nuevo, importar, paleta) y el hueco de los recientes explicado.
- **Lo que quedó de la primera fase:**
  - la latencia de cada salto en la tarjeta (bastion 12 ms → destino 35 ms);
  - una hoja de atajos con ⌘/ (Ctrl+Mayús+/ en Windows y Linux), con búsqueda;
  - los atajos en los tooltips de los botones de icono que tienen uno (el SFTP, sobre todo);
  - Ctrl+Mayús+L pliega la barra en Windows y Linux.

**Fase 3 · v0.3.1:**
- **Identidad de host** (F2):
  - **entorno**, un ajuste heredado nuevo: nombre, nombre corto y color. Cuatro de serie (Producción · prod · rojo, Preproducción · pre · naranja, Pruebas · pruebas · azul, Personal · casa · violeta) y otros con su nombre y color. Se pone en el grupo y lo heredan sus hosts;
  - el entorno se ve en la barra (el monograma del sistema con su color y la etiqueta del grupo), en la pestaña (una línea arriba y el nombre corto) y en el terminal (una línea arriba y «prod · Producción» en la esquina);
  - **sistema**: un monograma (deb, ubu, fed, rhel, alp, arch, bsd, mac, win, ?), sin logotipos. Se deduce del banner del servidor al conectar, sin ejecutar nada; leer `/etc/os-release` es un ajuste heredado, apagado de serie; y se puede elegir a mano;
  - **favoritos**: una estrella en la fila al pasar el ratón y en el editor; arriba en la barra (sin sacarlos de su grupo), en el raíl, en la paleta y en el inicio, en el orden que se les dé.
- **Los favoritos en el inicio** (lo que queda de F3): en tarjetas con su sistema, su entorno y si hay sesión; con su hueco explicado el primer día; y la sección de favoritos de la barra puede plegarse en el inicio, porque ya están en el centro.

**Fuera:**
- confirmar el pegado de varias líneas y los comandos destructivos en los hosts de producción: se valora después, con el entorno ya en uso;
- autocompletar comandos desde el historial, arrastrar un archivo al terminal para subirlo y copiar la salida del último comando.

## Decisiones tomadas

- **Fases según si tocan el vault** (2026-10-18). Al principio eran dos: la interfaz en la beta.3 y el resto en la 0.3.1. Después de la beta.3 se adelantó a una beta.4 todo lo que no toca el vault (el editor nuevo, el inicio sin los favoritos y lo que quedó de la primera fase), y la 0.3.1 se queda con lo que añade campos al vault (el entorno, el sistema y los favoritos), antes de que la v0.4 lo migre al formato cifrado. De la v0.4, lo que no toca la interfaz (el modelo de amenazas y los experimentos de cifrado y formato) puede empezar en paralelo.
- **⌘K abre la paleta** (2026-10-18; antes buscaba hosts, ver la [v0.3](v0.3.md)). Escribir un nombre e Intro sigue conectando, así que la costumbre no cambia. Se cuenta en «Qué hay de nuevo».
- **El ámbar de la latencia es relativo:** a partir de 3 veces la latencia habitual del host (la mediana de los últimos 5 minutos) y por encima de 100 ms, o cuando falta una respuesta. Un servidor lejano pero estable no sale marcado siempre, y en la red local no salta por milisegundos. Solo cambia el color: los avisos siguen siendo los de C6.
- **La gráfica sale de las comprobaciones de C6:** una cada keepalive (10 s de serie), 30 puntos en 5 minutos. La latencia de cada salto necesita preguntar en cada conexión de la ruta. Si eso complica el núcleo, se deja la latencia total y la de cada salto queda para después.
- **El entorno es un ajuste heredado con nombre, nombre corto y color**, no un enum de valores fijos. Así se añaden entornos de serie sin variantes nuevas, que romperían la lectura en versiones anteriores (lo que se vio con el proxy en B5). El color va como nombre de un color del tema, para que cada tema lo pinte con su contraste, o como hex en los personalizados. Nunca va solo: siempre lleva el nombre corto al lado.
- **El sistema y el favorito son campos nuevos del host**, y viajarán con la sincronización. Las versiones anteriores los conservan sin usarlos, como dice la arquitectura para los campos desconocidos.
- **El sistema, sin ejecutar nada por defecto.** El banner ya lo dice a menudo (`SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u3`; russh lo da en `client::Session::remote_sshid()`). Leer `/etc/os-release` ejecuta un comando en el servidor, así que es opcional y se dice en el editor.
- **Los recientes son de cada equipo:** `recent.json` junto a `history.json`, 50 entradas como mucho, fuera del vault y sin sincronizar. Se apagan y se borran en Ajustes › General, como el historial, y se cifrarán con él en la fase 2. Guardan también las direcciones de la conexión rápida que no se guardaron como host.
- **La barra asomada va por encima del terminal**, sin moverlo, para que el terminal no cambie de tamaño a cada paso del ratón.
- **El margen del terminal, 12 px de serie.** Cambia las columnas que caben; el terminal avisa al servidor como en cualquier cambio de tamaño.

## Hitos

**Fase 1 · 0.3.0-beta.3:**

| # | Hito | Semanas | Estado |
|---|---|---|---|
| F1 | Modo foco: barra plegable con ⌘B, raíl, asomada, ancho y margen del terminal | 0,5 | Hecho |
| F4 | Un solo ⌘K para la paleta, y la latencia con su gráfica en la barra de estado | 0,5 | Hecho |
| F5a | Pulido de consistencia: iconos, verbos, nombres, botones, tamaños, estados vacíos y la tarjeta de conexión | 0,5 | Hecho |
| — | 0.3.0-beta.3: «Qué hay de nuevo», galería, notas, guía de prueba y prueba en el equipo; después, 0.3.0 | — | — |

**Fase 2 · 0.3.0-beta.4:**

| # | Hito | Semanas | Estado |
|---|---|---|---|
| F5b | Editor de host, grupo e identidad: lo heredado se edita en su sitio; los enlaces en el color del texto | 1 | Hecho |
| F3a | Inicio sin los favoritos: recientes, túneles abiertos y conexión rápida que completa | 0,5 | Hecho |
| R | Lo que quedó de la primera fase: latencia por salto, hoja de atajos (⌘/), atajos en los tooltips y Ctrl+Mayús+L | 0,5 | Hecho |
| — | 0.3.0-beta.4: el arreglo de la tarjeta de latencia, «Qué hay de nuevo», galería, notas, guía de prueba y prueba en el equipo | — | — |

**Fase 3 · v0.3.1:**

| # | Hito | Semanas | Estado |
|---|---|---|---|
| F2 | Identidad de host: entorno heredado, sistema detectado y favoritos | 1,5 | Hecho |
| F3b | Los favoritos en el inicio | — | Hecho |
| — | 0.3.1-beta.1: «Qué hay de nuevo», galería, notas, guía de prueba y prueba en el equipo | — | — |

**Qué deja hecha la primera fase:**
- **Ajustes** (`settings.json`): `sidebar` (abierta, raíl u oculta), `sidebar_on_session` (como esté, en raíl u oculta), `sidebar_width` (220–420, 272 de serie), `terminal_padding` (0–24, 12 de serie) y `recent_connections`. Un archivo de una versión anterior toma los valores de serie.
- **Barra lateral** (`window/sidebar_state.dart`): la regla de qué se ve (`shownSidebar`: el ajuste, plegado más con un terminal o un SFTP delante si así se pide, salvo que ⌘B la abriera ahí), ⌘B, el ancho al arrastrar su borde (doble clic lo restablece) y la barra asomada. El raíl (`hosts/rail.dart`) enseña las pestañas de terminal y SFTP con sus iniciales y su estado; los favoritos llegan con F2.
- **Recientes** (`home/recent.dart`, `recent.json`): cada conexión SSH que se abre (cuándo y hasta cuándo) y cuántas veces corre cada acción de la paleta, para ordenarlas. Se adelantan de F3 porque la paleta los necesita; el inicio los usará en F3.
- **Paleta:** pestañas abiertas, recientes, `>` y «Conectar a …» para una dirección; las acciones con un id, para contarlas.
- **Latencia** (`tabs/latency.dart`): las últimas 30 medidas en la conexión, la habitual (la mediana) y el ámbar; la minigráfica y la tarjeta al pasar el ratón; la pista de la pestaña.
- **Pulido:** los textos de 10–11 px pasan a 12; `SectionLabel(keepCase:)` para los nombres de grupo; cabeceras de Túneles, Identidades y Snippets con la acción a la derecha, como Claves y Espacios de trabajo; la tarjeta «Conectando con…» pasados 400 ms y sin la fila «Este equipo», que ya está en el dibujo.
- **Pruebas:** la regla de la barra, ⌘B, el ancho y los recientes en `test/focus_test.dart`; una prueba de ventana nueva (raíl, asomada, oculta, plegarse sola, el ancho y la paleta con pestañas y `>`); la latencia y su tarjeta contra S2; el raíl en la galería de temas; y la prueba de accesibilidad comprueba que ningún texto en pantalla baja de 12 px, también en el raíl y en la barra asomada.

**Diferencias con el plan:**
- En Windows y Linux la barra no tiene atajo: no hay menú de la app donde ponerla, así que va en su botón y en la paleta. (Ctrl+Mayús+L llega en la segunda fase.)
- La latencia de cada salto queda para después: la tarjeta enseña la ruta y la latencia hasta el destino. (Llega en la segunda fase.)
- Los enlaces siguen en el color de acento salvo en la barra de estado: cambiarlos en toda la app va con el editor nuevo (F5b), que quita los «Cambiar».
- Los recientes (y su ajuste) entran en esta fase, no en F3.

**Qué deja hecha la segunda fase:**
- **Editor** (`hosts/editors.dart`): cada ajuste es una fila (`_SettingRow`) con dos estados. Heredado: borde discontinuo, de dónde viene a la derecha y un clic para cambiarlo aquí, con el foco ya en el campo. Cambiado aquí: el campo, «heredaría …» debajo y ↺ para volver a heredar. Una leyenda de una línea (`_InheritLegend`) con el orden de la herencia en su ⓘ. «Avanzado» (proxy, política de claves del host, sesión persistente, keepalive y agente) va plegado y se abre solo si el host ya cambia algo de ahí. `EditorFieldRow` pone la etiqueta a la izquierda, también en el editor de identidades.
- **Enlaces:** el `TextButton` del tema va en el color del texto y se subraya al pasar el ratón.
- **Inicio** (`home/start_page.dart`): la conexión rápida con sugerencias (hosts por coincidencia y por uso reciente, direcciones usadas sin guardar, «Conectar a …» tal cual con ⌥Intro y «Guardar como host…», que abre el editor con la dirección, el usuario y el puerto); los recientes con cuándo, cuánto duró (`durationText`) y tmux; los túneles abiertos con «Detener»; los atajos, y el primer día «Para empezar». Los recientes guardan si la sesión fue en tmux.
- **Latencia de cada salto:** el núcleo pregunta a cada salto con cada comprobación (`Live::jump_rtts`) y lo manda en un evento nuevo (`Event::Hops`, `SessionEventKind.hops` en Dart); la tarjeta lo pone junto a cada salto de la ruta.
- **Atajos** (`window/shortcuts.dart`): la hoja con todos, por grupos y en dos columnas si hay sitio, con búsqueda sin acentos por lo que hacen o por sus teclas; se abre con ⌘/ (también por el carácter `/`, para los teclados donde la barra va con Mayús), Ctrl+Mayús+/ en Windows y Linux, desde la paleta y desde el inicio. `withKeys` y `sidebarKeys` ponen el atajo en los tooltips: SFTP, el + de las pestañas y la barra lateral. Ctrl+Mayús+L pliega la barra en Windows y Linux.
- **Pruebas:** los recientes con su duración y tmux, `durationText` y la hoja de atajos (las teclas de cada sistema y la búsqueda) en `test/focus_test.dart`; en la prueba de ventana, el inicio (sugerencias, guardar como host, ⌥Intro, la hoja con ⌘/), detener un túnel desde el inicio y la latencia del bastion; el editor se recorre por la clave de cada campo; la latencia de cada salto contra el bastion de S2 en el núcleo; y la prueba de accesibilidad recorre el editor con «Avanzado» abierto, el inicio con recientes y sugerencias, y la hoja de atajos.

**Diferencias con el plan (segunda fase):**
- «Avanzado» tiene lo que el editor ya tenía (proxy, política de claves del host, sesión persistente, keepalive y agente); al salir del shell, las variables y `TERM` aún no se editan desde aquí, y los túneles tienen su página.
- El editor de identidades no hereda nada: toma la rejilla con las etiquetas a la izquierda, sin los estados de herencia.
- ⌘Intro en los recientes, para abrirlos en un panel nuevo, queda fuera: el inicio solo se ve sin pestañas abiertas, así que no hay panel que dividir.

**Qué deja hecha la tercera fase:**
- **Vault** (`openward-proto`): dos ajustes heredados nuevos, `environment` (ninguno, o una marca con nombre, nombre corto y color) y `read_os_release` (apagado de serie); y dos campos del host, `system` (código del monograma, nombre, de dónde salió y el texto que lo dijo) y `favorite` (su puesto). Una versión anterior los guarda sin tocarlos, como cualquier campo que no conoce.
- **Colores:** el vault guarda el color por su nombre (rojo, naranja, amarillo, verde, azul, violeta, rosa o gris) y cada tema lo dibuja con su paleta; los cuatro entornos de serie usan los tonos de peligro, aviso e información del tema. Una prueba comprueba que cada marca se lee sobre su fondo en todos los temas.
- **Sistema** (`openward-app::system`): el banner del servidor (que guarda `openward-ssh` al negociar) dice Debian (con su versión), Raspberry Pi OS, Ubuntu (las LTS por su OpenSSH), FreeBSD, NetBSD y Windows; si el host lo pide, `/etc/os-release` (o `uname -s` donde no lo hay, como en macOS) dice el resto, por su `ID` o su `ID_LIKE`. Se aprende de cada host guardado de la conexión, también de los saltos, y solo se escribe en el vault si cambia: nunca sobre uno elegido a mano, ni sobre lo que dijo os-release si el banner no dice nada nuevo. La app vuelve a leer los hosts con el evento `HostsChanged`.
- **Interfaz** (`ui/environment.dart`): `EnvChip` («prod», o «prod · Producción») y `SystemBadge` (el monograma teñido por el entorno; antes de la primera conexión, el contorno de un servidor). El entorno marca la pestaña (una raya arriba y su nombre corto) y el terminal (una raya arriba y su nombre en la esquina), y va en la cabecera de su grupo; el monograma, en cada host de la barra, en el raíl, en los recientes y en las sugerencias del inicio.
- **Editores:** el de grupo elige el entorno entre ninguno, los cuatro de serie y uno propio («Otro, con su nombre y color…»), con una vista previa y cuántos hosts lo heredan; el de host lo hereda como cualquier ajuste, y añade «Favorito» y la sección «Sistema» (el monograma, qué lo dijo, los iconos para elegirlo a mano, «Volver a deducirlo al conectar» y «Leer /etc/os-release»).
- **Favoritos:** la estrella al pasar el ratón por un host (y en su menú y en su editor); arriba en la barra, sin sacarlos de su grupo; en el raíl, los que no tienen pestaña; en la paleta, antes de escribir nada; y en el inicio, en tarjetas con su sistema, su entorno y si hay sesión, que se ordenan arrastrando (o con «Mover antes» y «Mover después» de un lector de pantalla). En el inicio, la sección de la barra empieza plegada.
- **Pruebas:** el sistema por el banner y por os-release, y cuándo se guarda, en el núcleo; contra S2, Ubuntu 22.04 por el banner, Dropbear sobre Alpine solo con os-release y los dos Debian de un salto; la herencia del entorno y los campos nuevos en el vault; los colores en todos los temas y el orden de los favoritos en `test/environment_test.dart`; en la prueba de ventana, el entorno del grupo, uno propio, el sistema a mano, la estrella, las tarjetas y su orden, la paleta y la marca en la pestaña; la galería, con un grupo de producción, un favorito y dos sistemas en cada tema; y la de accesibilidad, el selector de entorno, el diálogo de uno propio y el inicio con favoritos.

**Diferencias con el plan (tercera fase):**
- «Leer /etc/os-release» es un ajuste heredado como los demás: en el editor de host va bajo «Sistema» (con borde discontinuo mientras se hereda) y en el de grupo, en «Avanzado».
- El monograma es un poco más ancho que alto, para que quepan cuatro letras sin bajar de 12 px.
- En el tema Papel, de pestañas redondeadas, la pestaña lleva solo el nombre corto del entorno, sin raya.
- Las direcciones sin guardar de los recientes llevan «?»: no hay host donde guardar su sistema.

**El orden:** primero el editor (beta.4), porque F2 le añade filas (entorno, sistema, favorito) y conviene hacerlas ya sobre el nuevo; los favoritos del inicio, con F2 (0.3.1).

**Pruebas que hacen falta:**
- **F1:** plegar, raíl y ocultar con ⌘B y desde Ajustes; asomarse y fijar; el ancho y el margen se recuerdan; el terminal recibe el tamaño nuevo.
- **F4:** ⌘K, ⌘P y ⌘⇧P abren lo mismo; pestañas abiertas y recientes sin escribir; `>`; Ctrl+K llega al shell en Linux; la gráfica y el ámbar con latencias simuladas.
- **F5a:** la prueba de accesibilidad comprueba los 12 px; la tarjeta de conexión no aparece en una conexión local rápida y sí en el servidor congelado de S2.
- **F5b:** las pruebas de interfaz que pulsan «Cambiar» por posición pasan a buscar cada campo por su clave.
- **F2:** ida y vuelta de los campos nuevos en el vault y en versiones anteriores; la herencia del entorno; el banner de los servidores de S2 (los de OpenSSH sobre Ubuntu y Debian dicen su sistema; Dropbear sobre Alpine no, y sale «?» salvo con `/etc/os-release`); `/etc/os-release` solo se lee cuando está activado.
- **F3a:** recientes con su duración; completar en la conexión rápida (hosts, direcciones usadas, tal cual, guardar); el inicio vacío.
- **R:** la latencia de cada salto contra el bastion de S2; la hoja de atajos con búsqueda; Ctrl+Mayús+L en Linux.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| ⌘K deja de buscar solo hosts y molesta a quien ya lo usa | Al escribir van primero los hosts e Intro conecta, como antes; se cuenta en «Qué hay de nuevo» |
| Con la barra en raíl u oculta se pierde la lista de hosts | Se asoma al acercar el ratón, ⌘B la trae y ⌘K busca; el raíl enseña los favoritos y los hosts con sesión |
| El ámbar de la latencia asusta sin motivo | Es relativo a lo habitual de cada host, con un mínimo de 100 ms, y solo cambia el color |
| El color del entorno no se distingue (daltonismo, temas claros) | Siempre lleva el nombre corto; los colores de serie difieren también en luminosidad y cada tema los pinta con su contraste |
| El sistema detectado se equivoca | Solo se usa lo que el banner dice claramente; si no, «?»; siempre se puede elegir a mano |
| Leer `/etc/os-release` ejecuta algo en el servidor | Apagado de serie, por host o grupo, y dicho en el editor |
| Los campos nuevos del vault rompen versiones anteriores | Solo se añaden campos; el entorno no es un enum; las pruebas leen un vault de la 0.3.1 con la 0.3.0 |
| Los recientes dicen qué hosts se usan y cuándo | Son de este equipo, no se sincronizan, se apagan y se borran en Ajustes, y se cifrarán con el historial |
| Rehacer el editor rompe muchas pruebas de interfaz | Se reescriben con claves por campo en lugar de posiciones de texto, como parte de F5b |
