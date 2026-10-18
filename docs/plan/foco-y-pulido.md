# Foco y pulido: 0.3.0-beta.3 y v0.3.1

- **Estado:** propuesta. Maquetas aprobadas el 2026-10-18 (filas «F1» a «F5» del lienzo); el reparto en dos fases, aceptado el mismo día.
- **Fecha:** 2026-10-18.
- **Base:** fase 1 de la hoja de ruta ([ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas)), sobre la [v0.3](v0.3.md) y antes de la v0.4 (el vault cifrado).
- **Duración estimada:** unas 5 semanas de trabajo: 1,5 la primera fase y 3,5 la segunda.

## Objetivo

Con la v0.3 la fase 1 tiene casi todas sus funciones. Una revisión de las pantallas con las capturas de las pruebas de ventana dejó claro que lo que más falta no son funciones, sino espacio, orientación y coherencia:
- **el terminal nunca tiene toda la ventana:** la barra lateral mide 272 px fijos y no se pliega; a 1280 px de ancho ocupa el 21 % de la ventana durante la sesión, y con dos paneles cada uno se queda en unos 500 px;
- **nada distingue un servidor de producción de uno de pruebas** una vez abierta la pestaña, y las filas de host son solo texto, sin favoritos ni recientes;
- **la pantalla de inicio repite acciones** que ya están en la barra y en la paleta, en un área casi vacía;
- **dos buscadores se pisan:** ⌘K busca hosts en la barra y ⌘P abre la paleta, que también busca hosts;
- **la barra de estado enseña primero lo que menos se mira** (los algoritmos completos) y corta la latencia, que ya se mide;
- **el editor de host es denso**, y hay iconos, verbos y estados que se contradicen.

Se reparte en dos fases según si tocan el vault o no:
- **Fase 1 (0.3.0-beta.3):** solo interfaz. Entra en la prueba de la 0.3 que ya está en marcha, antes de la 0.3.0.
- **Fase 2 (v0.3.1):** añade campos al vault y rehace el editor de host. Va antes de que la v0.4 migre el vault al formato cifrado, para migrar una vez y con los campos ya definitivos, y para que los secretos de la v0.4 entren en el editor nuevo.

Sigue siendo solo escritorio y sin cuenta.

**Puerta de salida de la fase 1:**
- el equipo trabaja una semana con la barra en raíl u oculta durante las sesiones y la recupera con ⌘B o al acercar el ratón, sin buscarla;
- quien buscaba hosts con ⌘K sigue haciéndolo igual (escribir y Intro), y salta a pestañas y acciones desde ahí;
- la latencia se lee en la barra de estado y el ámbar no se confunde con un fallo;
- las pruebas de ventana, la de accesibilidad (texto de 12 px como mínimo) y la galería pasan sin regresiones.

**Puerta de salida de la fase 2:**
- cada persona marca sus grupos de producción y lo ve en la barra, en las pestañas y en los terminales;
- los hosts Debian y Ubuntu muestran su sistema por el banner sin ejecutar nada; los demás, al activar la lectura de `/etc/os-release` o al elegirlo a mano;
- el día empieza desde el inicio (recientes y favoritos) sin abrir la barra;
- en el editor, cambiar un valor heredado y volver a heredarlo se hace sin «Cambiar», y las pruebas de interfaz están reescritas para el editor nuevo.

## Alcance

**Fase 1 · 0.3.0-beta.3:**
- **Modo foco** (F1):
  - la barra lateral con tres estados: abierta, raíl (56 px: buscar, los favoritos y los hosts con sesión abierta, «Todos los hosts», la Biblioteca en iconos y Ajustes) y oculta;
  - ⌘B la pliega y la abre (Ctrl+B no, en Windows y Linux es del shell: allí Ctrl+Mayús+B queda para broadcast y la barra va en el menú Ver y en la paleta); el estado se recuerda;
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

**Fase 2 · v0.3.1:**
- **Editor de host más ligero** (F5b):
  - los valores heredados se editan en su sitio: borde discontinuo y de dónde vienen («de Producción», «por defecto»); al escribir, el borde pasa a continuo con «aquí · heredaría …» y un botón ↺ que vuelve a heredar. Sin los enlaces «Cambiar»;
  - una leyenda de una línea en lugar del párrafo, con el orden de la herencia en un (i);
  - una sola rejilla, con la etiqueta a la izquierda;
  - «Avanzado» plegado: proxy, keepalive, sesión persistente, al salir del shell, túneles, variables, `TERM` y agente;
  - lo mismo en el editor de grupos y en el de identidades.
- **Identidad de host** (F2):
  - **entorno**, un ajuste heredado nuevo: nombre, nombre corto y color. Cuatro de serie (Producción · prod · rojo, Preproducción · pre · naranja, Pruebas · pruebas · azul, Personal · casa · violeta) y otros con su nombre y color. Se pone en el grupo y lo heredan sus hosts;
  - el entorno se ve en la barra (el monograma del sistema con su color y la etiqueta del grupo), en la pestaña (una línea arriba y el nombre corto) y en el terminal (una línea arriba y «prod · Producción» en la esquina);
  - **sistema**: un monograma (deb, ubu, fed, rhel, alp, arch, bsd, mac, win, ?), sin logotipos. Se deduce del banner del servidor al conectar, sin ejecutar nada; leer `/etc/os-release` es un ajuste heredado, apagado de serie; y se puede elegir a mano;
  - **favoritos**: una estrella en la fila al pasar el ratón y en el editor; arriba en la barra (sin sacarlos de su grupo), en el raíl, en la paleta y en el inicio, en el orden que se les dé.
- **Inicio** (F3):
  - la conexión rápida arriba, que completa con los hosts guardados y las direcciones ya usadas sin guardar, con «Conectar tal cual» (⌥Intro) y «Guardar como host…»;
  - **Recientes**: cuándo y cuánto duró cada conexión, y si fue con tmux; Intro conecta, ⌘Intro en un panel nuevo;
  - **Favoritos** en tarjetas con su sistema, su entorno y si hay sesión;
  - los túneles abiertos, con «Detener»;
  - los atajos principales en una línea;
  - el primer día, «Para empezar» (terminal local, host nuevo, importar, paleta) y los huecos de recientes y favoritos explicados;
  - en el inicio, la sección de favoritos de la barra puede plegarse, porque ya están en el centro.

**Fuera:**
- confirmar el pegado de varias líneas y los comandos destructivos en los hosts de producción: se valora después, con el entorno ya en uso;
- autocompletar comandos desde el historial, arrastrar un archivo al terminal para subirlo y copiar la salida del último comando;
- una hoja de atajos con ⌘/.

## Decisiones tomadas

- **Dos fases, según si tocan el vault** (2026-10-18). La primera es solo interfaz y entra en la prueba de la 0.3. La segunda añade campos al vault y va antes de que la v0.4 lo migre al formato cifrado. De la v0.4, lo que no toca la interfaz (el modelo de amenazas y los experimentos de cifrado y formato) puede empezar en paralelo con la segunda fase.
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
| F1 | Modo foco: barra plegable con ⌘B, raíl, asomada, ancho y margen del terminal | 0,5 | — |
| F4 | Un solo ⌘K para la paleta, y la latencia con su gráfica en la barra de estado | 0,5 | — |
| F5a | Pulido de consistencia: iconos, verbos, nombres, botones, tamaños, estados vacíos y la tarjeta de conexión | 0,5 | — |
| — | 0.3.0-beta.3: «Qué hay de nuevo», galería, notas, guía de prueba y prueba en el equipo; después, 0.3.0 | — | — |

**Fase 2 · v0.3.1:**

| # | Hito | Semanas | Estado |
|---|---|---|---|
| F5b | Editor de host, grupo e identidad: lo heredado se edita en su sitio | 1 | — |
| F2 | Identidad de host: entorno heredado, sistema detectado y favoritos | 1,5 | — |
| F3 | Inicio: recientes, favoritos, túneles abiertos y conexión rápida que completa | 1 | — |
| — | 0.3.1-beta.1: «Qué hay de nuevo», galería, notas, guía de prueba y prueba en el equipo | — | — |

**El orden de la fase 2:** primero el editor, porque F2 le añade filas (entorno, sistema, favorito) y conviene hacerlas ya sobre el nuevo; F3 al final, porque usa los favoritos, el sistema y el entorno.

**Pruebas que hacen falta:**
- **F1:** plegar, raíl y ocultar con ⌘B y desde Ajustes; asomarse y fijar; el ancho y el margen se recuerdan; el terminal recibe el tamaño nuevo.
- **F4:** ⌘K, ⌘P y ⌘⇧P abren lo mismo; pestañas abiertas y recientes sin escribir; `>`; Ctrl+K llega al shell en Linux; la gráfica y el ámbar con latencias simuladas.
- **F5a:** la prueba de accesibilidad comprueba los 12 px; la tarjeta de conexión no aparece en una conexión local rápida y sí en el servidor congelado de S2.
- **F5b:** las pruebas de interfaz que pulsan «Cambiar» por posición pasan a buscar cada campo por su clave.
- **F2:** ida y vuelta de los campos nuevos en el vault y en versiones anteriores; la herencia del entorno; el banner de los servidores de S2 (los de OpenSSH sobre Ubuntu y Debian dicen su sistema; Dropbear sobre Alpine no, y sale «?» salvo con `/etc/os-release`); `/etc/os-release` solo se lee cuando está activado.
- **F3:** recientes y su archivo; completar en la conexión rápida; el inicio vacío.

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
