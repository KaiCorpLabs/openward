# Registros de sesión

- **Estado:** maquetas aprobadas el 2026-10-28 (fila «Registros» del lienzo). Va en la 0.3.3, con los valores por defecto propuestos. L1 (el núcleo) publicado en main el 2026-10-28; L2 (la página y el visor) hecho el mismo día, sin publicar; L3 y L4, pendientes.
- **Fecha:** 2026-10-28.
- **Base:** [ARCHITECTURE §10](../ARCHITECTURE.md#10-registros-auditoría-y-grabación), que ya prevé un historial de sesiones local con reproducción en asciicast, gratis y en el cliente. Fase 1, antes de la v0.4 (el vault cifrado).
- **Duración estimada:** unas 2,5 semanas de trabajo.

## Objetivo

Hoy, lo que se vio en un terminal se pierde con la pestaña:
- no hay forma de contestar «¿qué ejecuté ayer en web-1 y qué respondió?», ni de recuperar un arreglo para repetirlo, contárselo a otra persona o escribir un informe después de una incidencia;
- si la conexión se corta, la pestaña guarda lo último que se vio, pero se pierde en cuanto se cierra;
- el historial de comandos (C2) guarda los comandos, pero no dónde ni cuándo se ejecutaron, ni qué respondieron.

Los registros de sesión resuelven eso en el propio equipo, sin cuenta:
- **cada sesión deja una entrada**: dónde, cuándo, cuánto duró y cómo acabó;
- **donde se active, también lo que salió en pantalla**, con sus tiempos y un marcador por comando, para volver a verlo, buscar en él y exportarlo en un formato abierto.

No es un control de cumplimiento: la grabación hecha en el cliente se puede evitar con un cliente modificado ([ARCHITECTURE §10](../ARCHITECTURE.md#10-registros-auditoría-y-grabación)). La grabación obligatoria, con retención en el servidor, es otra pieza, de la fase 4.

**Puerta de salida:**
- el equipo lo activa en su grupo de producción durante una semana y encuentra, con el buscador, lo que respondió un comando de días antes sin abrir los registros uno a uno;
- una contraseña leída sin eco (`stty -echo`, `sudo`) no aparece nunca en un registro, y lo que se teclea tampoco;
- con la grabación activada, el terminal no pierde más de un 5 % al volcar un archivo grande. La medida de L1 da un 7–9 % con una avalancha sintética a unos 600 MB/s (ver «Qué deja L1 hecho»), así que esta puerta está por decidir;
- un `.cast` exportado se reproduce con `asciinema play`;
- un cierre brusco de la app pierde como mucho los últimos segundos del registro, nunca el archivo;
- las pruebas de ventana, la de accesibilidad y la galería pasan sin regresiones.

## Alcance

**Núcleo (`openward-app::logs`, nuevo):**
- **Qué se graba:**
  - la salida del programa tal como llega al motor (`Terminal::output`, igual para SSH y para la terminal local), con su tiempo;
  - los cambios de tamaño (`Terminal::resize`);
  - marcadores: cada comando (los manda el seguidor de la línea de C2), las pausas, los cortes y las reconexiones;
  - nunca lo que se teclea, se pega o llega por broadcast.
- **Formato:** asciicast v2, la versión que entienden todas las herramientas de asciinema:
  - una cabecera JSON con el ancho, el alto, la hora de inicio, `TERM` y el título;
  - un evento por línea: `o` para la salida, `r` para el tamaño y `m` para los marcadores.
- **Archivos:** en `logs/` junto a los ajustes (carpeta `0700`, archivos `0600`), por sesión y con un UUIDv7 como id:
  - `<id>.json`, la entrada con sus metadatos;
  - `<id>.cast.gz`, la grabación;
  - `<id>.txt.gz`, el texto para buscar.
- **Escritura:** en un hilo propio, con un canal acotado, fuera del lock del terminal:
  - la salida se agrupa y se comprime (`flate2`, que ya está en el árbol);
  - el gzip se cierra por bloques cada pocos segundos, así que un cierre brusco pierde como mucho el último bloque;
  - si el disco falla, el registro se detiene y el panel lo dice. Nunca frena el terminal.
- **Metadatos de cada sesión, aunque no se grabe:**
  - dónde fue (`host:<id>`, `address:` o `local`) y su nombre;
  - el entorno y el sistema de ese momento;
  - inicio y fin, y cómo acabó: cerrada, cortada o la app se cerró;
  - si usó tmux, el tamaño, el número de comandos, y si está guardado y con qué nota.
- **Texto para buscar:** lo saca el mismo hilo que escribe, mientras graba, con un filtro de texto: quita las secuencias de escape y aplica a la línea los retornos de carro, los retrocesos y las ediciones de línea. Cada línea va con el momento en que empezó. Lo que se ve en pantalla completa (vim, htop) queda en la reproducción, no en la búsqueda.
- **Reproducción:** un `Terminal` sin E/S alimentado desde el archivo, con avance, pausa, velocidad y salto a un momento. Los silencios de más de 2 s duran 2 s. Para volver atrás, reproduce sin pintar desde el principio; los puntos de control, solo si hacen falta.
- **Retención:**
  - al arrancar, al acabar cada sesión y al cambiar los límites, se borra por edad (30 días por defecto) y por espacio (2 GB por defecto), primero los más antiguos sin guardar;
  - los guardados no caducan;
  - un registro en curso no se toca.
- **FFI (`api/logs.rs`):**
  - listar con filtros y buscar, con los resultados según llegan;
  - abrir un reproductor, guardar con nota, borrar y exportar (`.cast`, `.txt` o solo un comando);
  - pausar y seguir una sesión, y marcar un comando.

**Ajustes:**
- **`session_log`, heredado** (por defecto ← grupos ← host):
  - sí o no, y por defecto no;
  - es un campo opcional nuevo de `Settings`, como `persistent_session`;
  - en el editor, una fila «Registro de sesión» dentro de «Avanzado».
- **De este equipo** (`settings.json`): los terminales locales (no por defecto), los días, el espacio máximo y la carpeta.

**Interfaz:**
- **Biblioteca › Registros** (⌘⇧R; Ctrl+Mayús+R en Windows y Linux), una página como la de Hosts:
  - las sesiones agrupadas por día, y filtros: con registro, guardadas, por entorno y locales;
  - el buscador «Busca en lo que se vio», con las líneas que coinciden;
  - una vista previa con lo último que se vio y los últimos comandos;
  - «Abrir el registro» y «Conectar otra vez».
- **El visor**, una pestaña de solo lectura:
  - la lista de comandos, que salta a cada uno;
  - ⌘F con el buscador del terminal;
  - una línea de tiempo con las marcas de los comandos y de las pausas, y la reproducción a 1×, 2× y 8×, saltando los silencios largos;
  - «Guardar» con una nota, «Exportar…» (`.cast`, `.txt`, copiar, o solo el comando elegido), «Conectar otra vez» y «Borrar».
- **Mientras graba:**
  - «Registro» en la cabecera del panel, con su menú: pausar, abrir el registro de la sesión, no guardar en este host y ajustes;
  - en pausa, «En pausa · m:ss», y en el registro, un hueco con su duración;
  - lo mismo en la paleta.
- **Desde otras pantallas:** la tarjeta de conexión perdida (C6) ofrece «Ver el registro», y los recientes del inicio también.
- **Ajustes › Registros**, una pestaña nueva:
  - el interruptor general y dónde está activado, con enlaces a esos hosts y grupos;
  - los terminales locales, los días, el espacio con lo que se usa, la carpeta y «Borrar todos…»;
  - una nota mientras vayan sin cifrar;
  - debajo, «Historial de comandos» y «Conexiones recientes», que se mudan desde General y Terminal.

**Fuera de alcance:**
- sincronizar los registros entre equipos: con la sincronización de la v0.5 y la v0.6, opcional, porque pesan;
- compartirlos con notas en un vault de equipo: fase 3;
- la grabación obligatoria con retención en el servidor y su visor: fase 4, `ee/recordings`;
- grabar lo que se teclea;
- el registro de transferencias del SFTP;
- el móvil.

## Decisiones tomadas

1. **Solo la salida, nunca la entrada.** Lo que se teclea incluye contraseñas en prompts sin eco; lo que sale es lo que se ve. Es la misma regla que el historial de comandos.
2. **Desactivado por defecto mientras vaya sin cifrar.** Un registro guarda todo lo que se ve, también un `cat .env` o un token impreso. Se activa por host o grupo, o en todos. Con el vault cifrado (v0.4) se revisa el valor por defecto.
3. **Cifrado en el D6 de la v0.4**, junto con el historial de comandos: la misma clave y la misma migración.
4. **asciicast v2 y archivos propios por sesión**, sin índice compartido ni SQLite. Nadie escribe a la vez en un mismo archivo, cada sesión se borra, se exporta y se cifra por separado, y un cierre brusco deja las demás enteras. (El plan proponía un `index.json`; al implementarlo se cambió por un `<id>.json` por sesión.)
5. **La entrada de cada sesión existe aunque no se grabe**: la página sirve desde el primer día como historial, y dice qué sesiones no tienen registro.
6. **Gratis y local.** Lo que tendrá un coste de servidor (sincronizar, compartir en equipo, retener por obligación) sigue el reparto de [ADR-006](../adr/ADR-006-servidor-open-core.md).
7. **Nombre:** «Registros» en español y «Session logs» en inglés.

8. **Valores por defecto** (aceptados el 2026-10-28):
   - desactivado;
   - sin los terminales locales;
   - 30 días y 2 GB;
   - «Historial de comandos» y «Conexiones recientes» se mudan a Ajustes › Registros;
   - va en una 0.3.3, antes de la v0.4.
9. **Un registro es una conexión**, con sus reconexiones automáticas. Reconectar a mano, o abrir otro programa en la pestaña, empieza otro. Una conexión que no llega a abrir la shell no deja entrada. Las direcciones escritas a mano siguen el valor del equipo («en todos los hosts»).

## Preguntas abiertas

- ¿Se activa por defecto cuando el vault vaya cifrado, o sigue siendo opcional?
- ¿Se unen más adelante `recent.json` y las entradas de los registros? Hoy guardan casi lo mismo. En este plan se dejan aparte para no tocar el inicio ni la paleta.
- ¿Basta un coste del 7–9 % con avalanchas de salida, o se rebaja? Rebajarlo pasaría, por ejemplo, por sacar el texto al cerrar en lugar de mientras se graba.

## Hitos

| # | Hito | Semanas | Estado |
|---|---|---|---|
| L1 | Núcleo: grabador asciicast, entradas, retención, texto para buscar, reproductor y FFI | 1 | Hecho, sin publicar |
| L2 | Página Registros y visor: comandos, buscar, línea de tiempo, guardar y exportar | 1 | Hecho, sin publicar |
| L3 | En la sesión y en Ajustes: cabecera del panel, pausa, tarjeta de corte, ajuste heredado, editor y Ajustes › Registros | 0,5 | Propuesto |
| L4 | Pruebas de ventana, notas, guía de prueba y beta | — | Propuesto |

**Qué deja L1 hecho:**
- **Núcleo (`openward-app::logs`):**
  - el almacén (`Logs`): entradas, retención, guardar con nota, borrar, buscar, exportar y el texto de un solo comando;
  - el grabador, en un hilo propio por sesión: gzip rápido, vaciado cada 2 s, como mucho 32 MiB en cola y 1 GiB de salida por sesión, con un marcador cuando deja algo fuera;
  - el filtro de texto;
  - el reproductor (`Player`);
  - `LogSink`, que sigue los eventos de la conexión: empieza al abrirse la shell, marca los cortes y las vueltas, y acaba con la sesión;
  - el `Terminal` le pasa lo que sale y los cambios de tamaño, y acepta marcar comandos y pausar.
- **Ajustes:**
  - `session_log` en `Settings`, heredado, falso por defecto;
  - `App::set_session_log_everywhere`, que cambia el valor del equipo sin tocar `read_os_release`.
- **FFI (`api/logs.rs`):**
  - las entradas;
  - `watch_logs`;
  - la búsqueda por un stream que acaba con ella;
  - guardar, borrar, exportar y el texto de un comando;
  - el reproductor (`LogPlayer`);
  - en `TerminalSession`: `log_command`, `pause_log` y `log_state`.
- **Dart:** el seguidor de la línea marca cada comando al pulsar Intro. La interfaz es de L2 y L3.
- **Medidas** (release, Mac del equipo):
  - con una avalancha sintética de 256 MB de líneas de log con color, el terminal va a unos 620 MB/s sin grabar y a unos 575 MB/s grabando (7–9 % menos);
  - el escritor guarda hasta unos 220 MB/s, y lo que pasa de ahí queda fuera con su marcador;
  - en disco ocupa en torno a un 20 % de lo que salió;
  - por etapas: gzip rápido 1,8 GB/s (el normal, 270 MB/s), JSON 870 MB/s y filtro de texto 430 MB/s.
- **Pruebas:**
  - 20 de unidad del módulo;
  - 3 de integración nuevas: con S2, la contraseña sin eco no queda, y la grabación sigue al host y al valor del equipo; sin S2, la terminal local;
  - las 37 de servidores, con S2.

**Qué deja L2 hecho:**
- **Núcleo y FFI:**
  - `Logs::preview` con las últimas líneas y los marcadores, sin reproducir la sesión;
  - `lines_around`, con el texto alrededor de una coincidencia;
  - `plain_text`, para copiarlo todo.
- **Página Registros** (`PageKind.logs`):
  - se abre con ⌘⇧R (Ctrl+Mayús+R fuera de macOS), desde la Biblioteca o desde la paleta;
  - las sesiones por día, con su tramo horario, duración, tamaño y estado (grabando, se cortó, sin registro, N comandos);
  - el espacio usado y los límites;
  - la búsqueda en lo grabado, con las tres primeras líneas de cada sesión y cuántas más hay;
  - filtros: todas, con registro, guardadas, por entorno y locales;
  - la vista previa con las últimas líneas y los últimos comandos, o las líneas alrededor de la coincidencia elegida, con «Abrir el registro» o «Abrir aquí» y «Conectar otra vez».
- **Visor** (`PageKind.log`):
  - el panel de terminal en modo de solo lectura (`TerminalPane.readOnly`): ni teclas, ni pegar, ni método de entrada; el ratón solo selecciona, la rueda solo mueve el historial y el tamaño es el de la grabación;
  - `TerminalController.playback` sobre el terminal del reproductor;
  - la columna de comandos, que salta al final de cada uno, con las pausas y los cortes;
  - ⌘F para buscar, espacio para reproducir y las flechas para pasar de un comando a otro;
  - la línea de tiempo con las marcas de los comandos y de las pausas, y velocidades 1×, 2× y 8×;
  - Guardar con nota, Exportar (`.cast`, `.txt`, copiar todo o el comando elegido con su salida), Conectar otra vez, Dejar de guardar y Borrar.
- **Cambios respecto a las maquetas:**
  - el visor es una página con un registro cada vez, no un tipo de pestaña nuevo: así no hace falta tocar el resto de sitios que conocen las pestañas, y la pestaña lleva igualmente el nombre y la hora del registro;
  - «Solo el comando elegido» es una entrada del menú Exportar («Copiar el comando elegido y su salida»), no una casilla.
- **Pruebas:**
  - una de ventana nueva en `ui_test`: una terminal local grabada se busca, se abre en la coincidencia, salta a un comando, se guarda con nota, se reproduce hasta el final y se borra;
  - la prueba del núcleo para la vista previa;
  - `flutter test`, con 241 pruebas, y la de los tokens de diseño.

**Pruebas que pide cada hito:**
- **L1:**
  - el `.cast` se ajusta a la especificación y se relee igual;
  - un cierre a mitad de bloque se recupera;
  - la retención borra en orden y nunca los guardados;
  - el texto extraído de una salida con colores, tabuladores y caracteres anchos sale bien;
  - con el servidor de S2: `stty -echo` no deja la contraseña;
  - el coste de grabar, con y sin grabación.
- **L2:**
  - abrir, saltar a un comando, buscar, guardar con nota y exportar desde la interfaz;
  - la reproducción llega al mismo estado de pantalla que el terminal en vivo.
- **L3:**
  - un grupo con el registro activado graba y uno sin él no;
  - pausar deja un hueco;
  - cortar la conexión con el contenedor congelable de S2 deja el registro completo hasta el corte.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un secreto queda en un registro | Desactivado por defecto y por host o grupo; nunca la entrada; pausa a mano; borrar uno o todos; archivos `0600`; cifrado en la v0.4; la nota de Ajustes lo explica |
| Grabar frena el terminal con mucha salida | Hilo propio con cola acotada y compresión fuera del lock; si el disco no llega, se deja fuera y se marca, sin esperar. Medido: 7–9 % con 600 MB/s de salida (puerta: menos de un 5 %; por decidir) |
| `top`, tmux o un `tail -f` llenan el disco | Compresión, tope de espacio, y un tope por sesión que detiene el registro con un aviso |
| Buscar en muchos registros tarda | Texto plano comprimido por sesión, búsqueda en segundo plano con resultados según llegan; un índice solo si al medir con 2 GB hace falta |
| Saltar a un momento de un registro largo tarda | Reproducir sin pintar; puntos de control del estado del motor si un salto pasa de medio segundo |
| La app se cierra de golpe | Bloques gzip cerrados cada pocos segundos; al arrancar, los registros sin cerrar se marcan «la app se cerró» |
| Se toma por un control de auditoría | La documentación y los Ajustes dicen que es un registro personal; el cumplimiento necesita la pieza del servidor o un bastión |
