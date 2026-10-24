# Auditoría de la 0.3.1 y plan de remediación

- **Estado:** R0 y R1 publicados en la 0.3.2-beta.1 (2026-10-23); R2 hecho, sin publicar (irá en la 0.3.2-beta.2); R3 a R6, propuesta.
- **Fecha:** 2026-10-23.
- **Base:** 0.3.1-beta.9 (`fe9f887`), antes de la v0.4 (el vault cifrado). Los hitos se llaman R0–R6 para no confundirlos con los de otros planes (A, B, C, D, F).
- **Duración estimada:** unas 12 semanas de trabajo en total. Lo que va antes de la v0.4 (R0–R3) suma unas 5,5; R4 se hace al principio de la v0.4, y R5 y R6 se reparten.

## Objetivo

Con la fase 1 casi cerrada y la v0.4 a punto de cambiar el formato del vault, conviene saber qué hay debajo antes de construir encima. Esta auditoría lee el código entero (unas 60.000 líneas de Rust y 35.000 de Dart) buscando fallos, problemas de seguridad, de rendimiento y de diseño, y propone en qué orden arreglarlos.

**Cómo se hizo:**
- seis revisiones de solo lectura, una por área: conexión SSH (`openward-ssh`, `openward-app`, `openward-proto`), datos (FFI, vault, SFTP, importadores, PTY), terminal (motor y render), app Flutter (estado, ciclo de vida, rendimiento), diseño (sistema de diseño, UX, accesibilidad, idiomas) y build, CI y release;
- cada hallazgo apunta a un archivo y una línea y dice en qué escenario falla; los de gravedad crítica y alta se han vuelto a comprobar a mano. Los que dependen de algo que no se ve en el código llevan «(a comprobar)»;
- los contrastes, con la fórmula de `test/theme_test.dart` sobre los 18 temas;
- las herramientas, en local el 2026-10-23: `cargo fmt`, `cargo clippy -D warnings`, `flutter analyze` y `dart format` salen limpios; pasan 201 pruebas de Rust y 175 de Flutter; `cargo deny` **falla** (BR-1).

**Puerta de salida de la auditoría:**
- R0 y R1 publicados como 0.3.2-beta.1 antes de seguir con la v0.4;
- R2 y R3 publicados antes de la puerta de salida de la v0.4;
- R4 hecho antes de D3 (la migración al formato cifrado);
- ningún hallazgo crítico ni alto abierto cuando el repositorio pase a ser público.

## Resumen

**Lo que está bien hecho**, y conviene no romper:
- la confianza en el host se decide en el núcleo con veredictos claros: `@revoked`, `@cert-authority`, nombres con hash, `[host]:puerto` y cada salto por separado; una clave que cambia nunca se acepta sola; no hay inyección en tmux ni en os-release;
- el vault escribe en SQLite dentro de una transacción antes que en memoria, en WAL con `synchronous=FULL`, con el archivo en 0600; `extra` y `Unsupported` guardan lo que escribió una versión más nueva;
- el terminal tiene una buena arquitectura: frames de daño por filas probados con fixtures cruzados entre Rust y Dart, una Picture por fila con atlas, cajas y Powerline como geometría, y teclado, ratón y pegado delegados en los codificadores de Ghostty. Los valores por defecto son seguros: sin OSC 52, enlaces solo con ⌘ y con lista de esquemas, títulos limitados;
- Riverpod está bien usado, con `select` donde importa, y el ciclo de vida de los controladores está cuidado;
- la regla de los 12 px se cumple en todo el código, «Reducir movimiento» se respeta, y los dos ARB tienen las mismas 1183 claves con los plurales bien resueltos;
- la cadena de suministro: acciones fijadas por SHA, Zig verificado por SHA-256, Ghostty por commit, el mismo toolchain en todo, `unsafe` solo en dos crates y prohibido en el resto; las versiones coinciden en los 16 tags publicados.

**Lo que más pesa:**
- **Un servidor hostil puede escribir fuera de la carpeta de descarga** por SFTP (DT-1) o congelar la vista del terminal (TM-2); y la reanudación de transferencias confía en cualquier `.part` que encuentre (DT-2).
- **La CI se ha sustituido por disciplina, no por un script:** desde el 2026-10-16 han salido 15 betas sin la CI completa, las pruebas de conexión se dan por buenas sin servidores (BR-3) y hoy mismo hay un aviso de seguridad que para la puerta de `cargo deny` (BR-1).
- **La app trabaja en reposo:** el terminal pide un frame en cada vsync aunque no haya nada nuevo (TM-1), los túneles se consultan cada 500 ms (UI-10) y hay más sondeos (CX-17). Es batería en un portátil.
- **Trabajo síncrono en el hilo de la interfaz:** llamadas FFI que leen disco y calculan HMAC en cada cambio de pestaña (DT-4), el mutex del vault retenido mientras se genera una clave RSA (DT-3), y recálculos en `build` que no escalan a 1000 hosts ni a carpetas de 5000 archivos (UI-3, UI-11, UI-12).
- **Se pierde trabajo sin avisar:** un clic fuera de un editor tira los cambios (DS-2), ⌘W y ⌘Q cierran sesiones vivas sin preguntar (UI-4), se borra sin deshacer (DS-11) y reconectar a mano pierde la sesión tmux (CX-1).
- **Las conexiones tienen bordes:** no hay timeouts al conectar (CX-6) y el tipo de clave del host se negocia sin mirar las conocidas (CX-2).
- **Los errores del núcleo llegan en crudo y en inglés** («AnyhowException(the vault changed since…)»), y la interfaz decide comparando esas frases (DT-5).
- **El formato tiene huecos justo antes de la v0.4:** los structs anidados pierden los campos que no conocen (DT-10) y no hay fixtures de vaults de versiones publicadas (DT-12).

**Hallazgos por área y gravedad:**

| Área | Crítico | Alto | Medio | Bajo | Total |
|---|---|---|---|---|---|
| BR · Build, CI y release | | 4 | 6 | 6 | 16 |
| CX · Conexión SSH | | 2 | 10 | 11 | 23 |
| DT · Datos: vault, SFTP, importadores, FFI | 1 | 4 | 8 | 7 | 20 |
| TM · Terminal | | 3 | 9 | 13 | 25 |
| UI · App Flutter | | 4 | 14 | 4 | 22 |
| DS · Diseño, accesibilidad e idiomas | | 3 | 15 | 4 | 22 |
| **Total** | **1** | **20** | **62** | **45** | **128** |

## Hitos

### R0 · La puerta (2–3 días)

Antes de arreglar nada, que lo arreglado no se pueda romper sin que se note.
- **BR-1:** `cargo update -p ctutils` (0.4.3 → 0.4.5) y `make deny` en verde.
- **BR-2:** `make ci`, el equivalente local de `ci.yml`, en este orden: fmt y clippy (también con `--features alacritty`); los servidores S2, con `trap` para pararlos; `cargo test --workspace` y alacritty; `cargo check` de los destinos móviles; termbench, sshprobe y deny; `flutter analyze`, `dart format --set-exit-if-changed` y `flutter test`; las pruebas de ventana con `-d macos`. Deja una nota con el SHA (`git notes --ref=ci`) que se comprueba antes del fast-forward de main. Un `make ci-quick` sin las pruebas de ventana, para cada commit.
- **BR-3:** con `OPENWARD_REQUIRE_SERVERS=1` (que pone `make ci`), una prueba de conexión sin servidores falla en lugar de pasar; sin la variable, se cuenta cuántas se saltaron.
- **BR-4:** `package-macos.sh` se niega a empaquetar con el árbol sucio, si `HEAD` no es el tag `v$version`, si Cargo y pubspec no coinciden o si falta una de las dos arquitecturas; el SHA va junto al dmg y en las notas del tap.

**Puerta:** `make ci` pasa en main con los servidores arriba; un dmg solo sale de un tag limpio.

**Qué deja hecho:**
- `tool/ci.sh` (`make ci`, `make ci-quick`, `make ci-check`): arranca la máquina de podman si estaba parada (y la para al terminar), levanta y baja los servidores S2, y anota en `refs/notes/ci` el commit que pasó entero con el árbol limpio.
- Las pruebas de conexión de Rust fallan sin servidores con `OPENWARD_REQUIRE_SERVERS`, y las de ventana con `--dart-define=OPENWARD_REQUIRE_SERVERS=true`; `ci.yml` los pone donde hay servidores (Linux).
- `package-macos.sh --snapshot` para lo que no sale de un tag (el paquete se llama `OpenWard-<versión>+<commit>-macos.dmg` y `release-tap.sh` no lo publica); el semanal de `ci.yml` lo usa. El commit va en `<dmg>.commit` y en las notas del tap.

**Diferencias con el plan:**
- El mismo día salió otro aviso, RUSTSEC-2026-0386 (`AsyncFd` en tokio 1.53.2): tokio sube a 1.53.3, el PR de dependabot que estaba abierto.
- Sin la variable, `make test` avisa de que los servidores no están en lugar de contar las pruebas saltadas: cargo no enseña lo que escribe una prueba que pasa.

### R1 · Seguridad y datos (0.3.2-beta.1, ~1,5 semanas)

Lo que un servidor hostil, un archivo importado o un cierre a destiempo pueden aprovechar o romper.
- **SFTP:** los nombres remotos con `/`, `\0`, `.` o `..` se rechazan al listar, y `local_join` solo acepta componentes normales dentro de la raíz (DT-1); cada trabajo usa un `.part` propio, con el tamaño y la fecha del origen, y nunca borra uno ajeno (DT-2).
- **Clave del host:** los tipos ya conocidos para ese host:puerto van primero en la negociación; un veredicto nuevo, «hay claves de otro tipo», que avisa y que `AcceptNew` no acepta solo; los nombres, en minúsculas (CX-2). Sin `ssh-rsa` con SHA-1 de serie (CX-13).
- **known_hosts y ProxyCommand:** los ítems `KnownHost` con saltos de línea o espacios se rechazan al validar (CX-3); `%h`, `%r` y `%n` con metacaracteres de shell no se expanden, como en OpenSSH 9.6; un ProxyCommand importado de otro programa llega desactivado y con su texto a la vista (CX-4).
- **tmux:** el nombre de la sesión vive en el terminal y se reutiliza; `close()` (cerrar a propósito) se separa de `detach()` (reconectar) (CX-1).
- **Terminal:** un tramo se cierra antes de pasar de 65.535 bytes, y el decodificador de Dart se recupera de un frame malo (TM-2); con ⌘ pulsado sobre un enlace se ve su destino, marcado si no coincide con el texto (TM-7).
- **Arranque y archivos:** si el vault no abre (formato más nuevo, permisos, corrupción), una pantalla con el error y «Mostrar la carpeta de datos» en lugar de la ventana vacía (UI-1); ajustes, historial y recientes se escriben en un temporal y se renombran (UI-6); un candado en `vault.db` para que dos procesos no se pisen (DT-9).
- **Pequeños con efecto:** los temporizadores de la tarjeta de reconexión, que nunca arrancan (UI-2); `SECURITY.md` con un canal que pueda usar alguien de fuera (BR-7).

**Puerta:**
- pruebas nuevas: un servidor que devuelve `../x` en un listado; un `.part` ajeno junto al destino; un host conocido solo por ECDSA da `Known` y no «nuevo»; `connect` tras un corte da `Resumed`; un frame con un tramo de 70 KB; el arranque con un vault de formato más nuevo; la tarjeta de reconexión cuenta hacia atrás;
- `make ci` en verde y la 0.3.2-beta.1 en el tap.

**Qué deja hecho:**
- **SFTP** (`openward-sftp`): `Remote::list` deja fuera los nombres que son una ruta, y `local_join` falla con `..` (y con `\` o `:` en Windows). El `.part` se llama `<nombre>.ow-<id>.part`, con el id del origen (FNV-1a de su ruta, tamaño y fecha, fijo entre versiones): una copia sigue desde un part del mismo archivo tal como es ahora, también en otra sesión, y nunca toca el `name.part` de un navegador ni uno de otra versión del archivo.
- **Clave del host** (`openward-ssh`): los tipos conocidos para el host van primero en la negociación (`host_key_order`); `Verdict::OtherType` cuando solo hay claves de otro tipo, que pregunta también con «Aceptar nuevas» y en estricto se rechaza; nombres en minúsculas, también los de las líneas con hash y los principales de los certificados. La tarjeta dice qué tipos se conocían, en ámbar.
- **`ssh-rsa` con SHA-1:** fuera de serie; un ajuste heredado nuevo, `legacy_host_keys` («Claves antiguas (ssh-rsa)», en «Avanzado»), y el importador de `~/.ssh/config` lo activa con `HostKeyAlgorithms +ssh-rsa`.
- **known_hosts** (`openward-proto`, `openward-vault`): `KnownHost::is_well_formed` (una línea: patrones y clave sin espacios ni controles, comentario sin controles); el vault rechaza lo demás, lo que ya hubiera no se lee, y el importador de Termius deja la clave en dos partes y el comentario en una línea.
- **ProxyCommand** (`openward-app::local`): `%h`, `%r` y `%n` con caracteres de shell hacen fallar el plan (`PlanError::UnsafeToken`); los de PuTTY, MobaXterm y Tabby no se importan y salen en el informe con su texto (`WarningKind::ProxyCommand`).
- **tmux** (`openward-app`): el nombre vive en el `Terminal` (`tmux_name`) y `connect` hace `detach()`, que no lo cierra; `close()` sigue cerrándolo.
- **Terminal:** `FrameEncoder::push_cell` parte el tramo antes de 64 KiB; Dart descarta un frame que no se lee y pide uno entero. Con ⌘ sobre un enlace, abajo a la izquierda, a dónde lleva; en ámbar si su texto nombra otro sitio (`linkMisleads`). Una URL partida en varias filas se abre entera (hasta 4 filas a cada lado).
- **Arranque y archivos:** `StartupErrorApp` cuando `RustLib.init` u `OpenWard.open` fallan; `core/json_file.dart` escribe ajustes, historial y recientes en un temporal que se renombra, y guarda en `<nombre>.bad` lo que no se pudo leer; el historial se escribe medio segundo después del último Intro (`flush()` al cerrar y al borrar). `vault.db.lock` con `File::try_lock`: un segundo OpenWard sobre los mismos datos ve la pantalla de error (`Error::OpenElsewhere`).
- **Reconexión:** los temporizadores de las tres tarjetas arrancan en `initState`.
- **Pruebas:** nombres de un servidor y `local_join`; el id del part y un part ajeno, de otra versión y propio, subiendo y bajando, contra S2; el orden de los tipos de clave; un host conocido por ECDSA contra el bastion sin preguntar; un tipo que nadie ofrece pregunta con «Aceptar nuevas»; tmux reconectado a mano da `Resumed` y deja una sola sesión; tramos largos; URLs partidas; `KnownHost` de varias líneas; tokens de ProxyCommand; ProxyCommand de Tabby; `HostKeyAlgorithms`; el candado; en Dart, la pantalla de error, los archivos atómicos, los segundos sin respuesta que avanzan y los enlaces que engañan.

**Diferencias con el plan:**
- Un nombre hostil en un listado no se puede probar contra OpenSSH, que nunca lo manda: lo cubren las pruebas unitarias de `is_name` y `local_join`. Esos nombres se dejan fuera sin contarlos, porque ningún servidor de verdad los tiene.
- El ProxyCommand importado no llega desactivado en el host: se queda en el informe de la importación, con su texto para ponerlo a mano. Así no hace falta un estado «desactivado» en el vault.
- Los parts viejos de OpenWard (de otra versión del archivo) se quedan donde estaban: borrarlos costaría listar cada carpeta remota.
- `SECURITY.md` dice ya el estado de verdad (beta, vault sin cifrar hasta la v0.4), pero el canal de reporte sigue siendo el del repositorio privado: falta decidir cuál (un correo o el reporte privado del tap).

### R2 · En reposo y a escala (0.3.2-beta.2, ~2 semanas)

Que la app no haga nada cuando no pasa nada, y que aguante 1000 hosts y carpetas grandes.
- **El terminal en reposo:** Rust avisa cuando hay daño y Dart pide el frame solo entonces (TM-1); la caché de contraste, acotada (TM-3); las pestañas ocultas solo leen el título y la campana (TM-22); el historial se comprime cuando la pestaña está quieta, con un tope de bytes (TM-10); el tamaño se aplica al soltar el divisor o tras 120 ms (TM-5); la búsqueda espera a que se deje de escribir y avanza por pasos acotados (TM-4).
- **Sondeos:** el tablero de túneles va por eventos, o solo vigila si el host tiene túneles (UI-10); el vigilante de la conexión, los túneles y el SFTP esperan al siguiente evento en lugar de mirar cada 250 ms–1 s (CX-17).
- **El hilo de la interfaz:** las llamadas FFI con disco o cálculo pasan a asíncronas y el contador de hosts conocidos se cachea (DT-4); el mutex del vault se suelta antes de generar claves o leer archivos (DT-3); cerrar un terminal local no espera al proceso (DT-6); `OwTheme` con `==`, para que ⌘B no reconstruya la app entera (UI-9).
- **Escala:** `visible` del SFTP, cacheada y con la clave de orden natural precalculada (UI-3); la paleta calcula sus entradas una vez por consulta (UI-11); índices en la biblioteca y listas perezosas en la barra y en Hosts (UI-12).
- **El runtime:** el trabajo bloqueante (recorrer carpetas locales, SQLite, archivos) va a `spawn_blocking`, y el parseo del terminal, a su hilo (CX-12).
- **Tamaño:** un `[profile.release]` con `strip`, `lto = "thin"` y `codegen-units = 1` (BR-14).

**Puerta (medida, no estimada):**
- con un terminal abierto y sin salida, la app no pide frames (Instruments o `debugPrintBeginFrameBanner`) y la CPU en reposo baja del 1 %; termbench mide el mismo eco que antes;
- con 1000 hosts y 300 líneas con hash en known_hosts, cambiar de pestaña no llama a la FFI y la barra se construye en menos de 16 ms;
- en una carpeta de 5000 archivos, ⌘A y una flecha caben en un frame;
- subir una carpeta de 20.000 archivos no hace saltar «Sin respuesta» en otra pestaña;
- el dmg mide lo mismo o menos que el de la beta.9.

**Qué deja hecho:**
- **Terminal a demanda** (`openward-app::terminal`): `Terminal::set_waker` avisa una vez cada vez que hay algo nuevo sin mirar, y `poll_meta` lee solo el título y la campana. El panel arranca su `Ticker` con el aviso y lo para tras dos frames sin nada; una pestaña oculta lee título y campana como mucho cuatro veces por segundo y solo si algo cambió, y al mostrarse pide la pantalla entera.
- **Búsqueda:** `ghostty_search_feed` y `ghostty_search_tick` con 2 ms por mirada (`SearchState.searching`); el panel sigue pidiendo frames mientras busca. La barra espera 120 ms tras la última tecla (Intro busca ya) y dice «Buscando…».
- **Redimensionado:** el tamaño va al núcleo 120 ms después del último cambio; lo que el panel dice que mide sigue al arrastre.
- **Historial:** un tope de 256 MiB por terminal además del de líneas; tras un minuto sin salida se comprime por pasos (`compress_step`), fuera del hilo de la interfaz.
- **Contraste:** la caché se vacía al llegar a 4096 parejas.
- **Túneles por eventos:** `App::watch_tunnels` avisa con cada cambio de estado y de conexiones de un túnel local; el tablero de Dart pregunta entonces. Solo la página de Túneles pregunta cada segundo, y solo con túneles remotos abiertos (sus conexiones se cuentan en la sesión, sin aviso).
- **Vigilante de la conexión** (`alive.rs`): duerme hasta el próximo plazo (la siguiente pregunta, una tecla sin respuesta, «no responde», «perdida»); la entrada lo despierta, y la salida solo mientras no responde.
- **Hilo de la interfaz:** `knownHostRows` e `installedPrograms` pasan a asíncronas; un `knownHostCount` barato para el contador de la Biblioteca (`knownHostCountProvider`); `keyComment` pregunta a `hostname` una vez.
- **Mutex del vault:** `known::Ours` toma del vault lo que hace falta y lee `known_hosts` sin él; `~/.ssh/config` se lee antes de tomarlo; las claves (`keychain::users`) lo toman solo al final, después de generar una RSA.
- **Terminal local:** cerrarlo manda la señal de cuelgue sin esperar; si el programa sigue un segundo después, se mata desde un hilo propio.
- **Runtime:** la salida de cada terminal SSH se analiza en su propio hilo, con una cola acotada (64 trozos) que sigue frenando al servidor si el análisis va lento; el recorrido de una carpeta local antes de subirla va a `spawn_blocking`.
- **Interfaz a escala:** `materialThemesProvider` hace los temas solo cuando cambia algo del tema; `FilePane.visible` y `selection` en caché, con la clave de orden natural (`NaturalName`) y un contador de cambios en la selección (`SelectedNames`); la paleta hace sus entradas una vez y las puntúa una vez por consulta; `Library` con índices por id y por grupo y `countUnder` memorizado; filas perezosas en la búsqueda de la barra y en Hosts, que escuchan qué sesiones hay y no cada cambio de pestañas.
- **Tamaño:** `[profile.release]` con `strip`, `lto = "thin"` y `codegen-units = 1`.
- **CI:** `tool/ci.sh` deja como estaban los `Cargo.lock` de los spikes que compila.
- **Pruebas:** el aviso una vez por mirada y `poll_meta`; la búsqueda por pasos en 50.000 líneas; el vigilante con tiempo simulado (la pregunta, exacta a los 2 s de la tecla; la salida tras «no responde», al instante); cerrar un programa que ignora el cuelgue; los hosts conocidos contados; los temas iguales al plegar la barra; 5000 archivos ordenados una vez; y, en las pruebas de ventana, un terminal quieto que deja de pedir frames y la ventana con 1000 hosts.

**La puerta, medida:**
- un terminal quieto deja de pedir frames en cuanto el prompt está dibujado, la salida los trae otra vez y vuelven a parar (prueba de ventana, por el estado del `Ticker`);
- con 1000 hosts, una pestaña nueva construye la ventana en 58 ms y una búsqueda que los encuentra todos, en 51 ms, en una build de depuración (en release no se ha medido a mano);
- 5000 archivos: `visible` y `selection` pedidos 5000 veces cada uno con todo seleccionado, en menos de 200 ms en total;
- el paquete de macOS pasa de 49,5 a 47,0 MB, la app de 115,8 a 103,8 MB y la librería del núcleo de 56 a 45 MB, con los mismos 4223 símbolos exportados que la beta.1;
- no se han medido a mano la CPU en reposo ni la subida de 20.000 archivos: lo cubren el `Ticker` parado y el recorrido fuera del runtime.

**Diferencias con el plan:**
- El atlas compartido (TM-6) y un notificador por división de paneles (UI-19) siguen en R6, como decía el plan en su apartado de lo que puede esperar.
- Los túneles y el SFTP siguen comprobando una vez por segundo si su conexión se cerró: esperar a un aviso de cierre necesita que russh lo dé. Lo que se quitó es el sondeo del vigilante (cuatro veces por segundo por conexión) y el del tablero de túneles (dos por segundo).
- `keys()` e `identities()` siguen siendo síncronas: leen pocos archivos y ya no retienen el vault. Importar desde otro programa sigue con el vault tomado mientras guarda las claves, que se arregla con DT-18 en R6.
- La caché de contraste se vacía entera en lugar de ser una LRU: con colores de 24 bits vuelve a llenarse de los que se usan.

### R3 · Conexiones que no se cuelgan y trabajo que no se pierde (0.3.2-beta.3, ~1,5 semanas)

- **Timeouts:** por etapa (TCP, banner e intercambio, cada respuesta de autenticación, el estado de tmux), en pausa mientras el usuario responde, e importando `ConnectTimeout` (CX-6); `Live::drop`, con el mismo límite que `mark_lost` (CX-19).
- **Autenticación:** un agente que se niega a firmar o un servidor que corta por `MaxAuthTries` no cuentan como red ni se reintentan ocho veces (CX-10); un certificado inválido vuelve a la clave simple, como en OpenSSH (CX-15).
- **Ecosistema OpenSSH:** también `/etc/ssh/ssh_known_hosts`, `UserKnownHostsFile` y `GlobalKnownHostsFile` (CX-5); ProxyCommand con el `PATH` del shell de login y sus últimas líneas de error en el fallo (CX-7); los modos del PTY (`IUTF8`, `VERASE`) (CX-21).
- **Túneles:** el bucle de aceptar sobrevive a los errores pasajeros (CX-8); cerrar un túnel corta sus conexiones y suelta la sesión (CX-9); escuchar en 127.0.0.1 y en ::1 (CX-14); un número de generación contra las carreras de abrir y cerrar (CX-20); abrir un túnel desde una página que se desmonta ya no se queda esperando (UI-20).
- **No perder trabajo:** cerrar un editor con cambios pregunta (DS-2); ⌘W sobre una sesión conectada de un entorno marcado o con transferencias, ⌘Q y cerrar la ventana preguntan, y la última pestaña se puede reabrir (UI-4); borrar un snippet o un túnel se deshace desde el aviso, y los dos «Borrar» de Ajustes confirman (DS-11).
- **macOS:** `NSLocalNetworkUsageDescription` y una pista cuando la red local está denegada (BR-9); mantener una letra pulsada repite en lugar de abrir el selector de acentos (TM-11).
- **Terminal:** la salida sincronizada (modo 2026) (TM-9); seleccionar arrastrando fuera del borde no manda flechas al programa (TM-12).
- **Cotas:** la salida de `exec` y lo que dice os-release, limitados (CX-16); el canal de la bomba del shell, acotado (CX-18).
- **SFTP:** una subida sobre un symlink o sobre un archivo de otro usuario no lo sustituye por otro inodo (DT-8); una carpeta que responde tarde no devuelve la vista a la anterior (UI-8).

**Puerta:** contra un servidor que acepta TCP y no habla, la tarjeta pasa a «No responde» en el tiempo configurado; un túnel SOCKS aguanta un navegador con 300 conexiones; ⌘Q con una transferencia en curso pregunta; Esc en un editor con cambios pregunta.

**Qué deja hecho:**
- **Timeouts** (`openward-ssh::client`): `Options::connect_timeout`, del ajuste heredable «Tiempo para conectar» (`connect_timeout_secs`, 15 s; `ConnectTimeout` al importar). Cubre abrir la conexión hasta la clave de host (TCP, ProxyCommand, proxy o salto, banner e intercambio) y cada respuesta de la autenticación; el tiempo que el usuario tarda en contestar sobre la clave de host no cuenta. Firmar con el agente tiene hasta dos minutos (una llave que tocar, una aprobación). El estado de tmux, 5 s; `Live::drop`, 2 s, como `mark_lost`. El fallo dice «no answer for N s», que la app muestra como «no responde (N s sin respuesta)».
- **Autenticación:** el agente firma a través de un firmante propio (`Signing`): si no firma, la petición no sale y la sesión sigue esperando la siguiente, en lugar de quedarse esperando la firma (russh no oye nada más mientras tanto); se pasa a la siguiente clave o método. Si no contesta a tiempo, no se le pregunta más en esa conexión (su respuesta aún podría llegar). Un servidor que cuelga después de rechazar algo (`MaxAuthTries`) es un fallo de autenticación con los métodos que aceptaba, no de red: no se reintenta ni se ofrecen las claves otra vez (`Session::gave_up`).
- **Certificados de host:** uno que no vale (otra CA, caducado) se mira por su clave simple en la misma conexión, como OpenSSH; si tampoco se conoce, se pregunta por ella según la política, y si no se acepta, el fallo es el del certificado (salvo una clave cambiada, que pesa más).
- **`known_hosts` de OpenSSH:** cada salto lee los del usuario (`~/.ssh/known_hosts`, `known_hosts2`) y los del sistema (`/etc/ssh/ssh_known_hosts`, `ssh_known_hosts2`), o los que digan `UserKnownHostsFile` y `GlobalKnownHostsFile` (ajustes nuevos, `known_hosts_files` y `global_known_hosts_files`; `none` es ninguno). Se importan de `~/.ssh/config`.
- **ProxyCommand:** corre con el `PATH` del shell de login (`$SHELL -l`, una vez, como mucho 3 s), con el de la app detrás; sus tres últimas líneas de stderr van en el error («ProxyCommand: cloudflared: command not found · …»).
- **PTY:** los modos de un terminal, como los manda OpenSSH: `IUTF8`, `VERASE` = DEL y las demás teclas de control, modo canónico, eco y `ONLCR`.
- **Túneles:** aceptar sobrevive a los errores pasajeros (espera de 10 ms a 1 s y vuelve; solo un listener que falla 30 s seguidos se da por perdido, y el túnel pasa a «Falló»). Cada listener lleva sus conexiones en un `JoinSet`: cerrar el túnel las corta y suelta la conexión SSH. A `localhost` escucha en 127.0.0.1 y, si se puede, en ::1. Un número por apertura (`Tunnels::begin`): un túnel cerrado mientras se abría (o abierto otra vez) suelta lo que abrió, y abrir uno que ya está abierto o abriéndose no hace nada. `openTunnel` espera con un `Completer` y pregunta en el navegador raíz.
- **Cotas:** `Session::exec_short` guarda como mucho 64 KiB y suelta el comando (os-release, tmux); el nombre del sistema, 64 caracteres, y lo que lo prueba, 128. La cola del shell hacia el servidor tiene 256 huecos: si el servidor no lee, lo que se teclea de más no se acumula, y las respuestas del terminal esperan.
- **SFTP:** una subida sobre un enlace simbólico escribe el archivo al que lleva; sobre un archivo de otro usuario o de otro grupo, escribe encima en su sitio (sin `.part`), como `sftp`, y queda suyo. Sin `posix-rename`, el anterior se aparta (`nombre.ow-….old`) hasta que el nuevo está en su sitio, y vuelve si no se puede. `FilePane.open` lleva un número de petición; las copias paradas (en pausa, fallidas) refrescan su carpeta una vez y se siguen.
- **Terminal:** la salida sincronizada (modo 2026) con `GHOSTTY_TERMINAL_OPT_RENDER_HOLD`: al empezar se guarda la pantalla, y los frames la enseñan hasta que el programa termina o pasa un segundo. Al seleccionar arrastrando fuera del borde se desplaza solo el historial (`scroll_history`), sin mandar flechas ni rueda al programa. `ApplePressAndHoldEnabled = false` entre los valores por defecto de la app.
- **No perder trabajo:** `EditorFrame(snapshot:)`: los editores de host, grupo, identidad, snippet y túnel preguntan «¿Descartar los cambios?» al salir sin guardar con algo cambiado (Esc, Cancelar, la ×, un clic fuera). ⌘W, la × y el clic central de una pestaña, «Cerrar las N» y «Cerrar las demás» preguntan si cortan una sesión conectada de un host con entorno marcado. ⌘Q y cerrar la ventana preguntan si hay sesiones abiertas, transferencias en curso (o en pausa) o túneles abiertos (`AppLifecycleListener.onExitRequested`; la ventana pasa por `NSApp.terminate`). ⌘⇧T (Ctrl+Mayús+Alt+T en Windows y Linux) y el menú de la pestaña reabren lo último cerrado, hasta 20: una pestaña con sus paneles como estaban, o un panel en una pestaña suya, con conexiones nuevas. Borrar un snippet o un túnel avisa con «Deshacer»; «Borrar» de las recientes y del historial piden confirmación (`confirmAction`). La ventana y el panel de los editores recuperan el foco cuando se les cae (`KeepFocus`): un campo, una vista o una página con el foco que desaparece (un ajuste que vuelve a heredarse, el SFTP al cambiar de pestaña) lo dejaba en la raíz, adonde no llegan ni Esc, ni ⌘W, ni ⌘↩.
- **macOS:** `NSLocalNetworkUsageDescription`; ante «No route to host» la app sugiere mirar el permiso de Red local.
- **Pruebas:** contra los servidores S2, un servidor mudo abandonado a su tiempo, un agente que no firma, `MaxAuthTries`, un certificado de otra CA, el `known_hosts` del sistema, los modos del PTY, cerrar un túnel con una conexión dentro (también por ::1), cerrarlo mientras pregunta, 300 conexiones SOCKS, la subida sobre un enlace y sobre el archivo de otro usuario (`/srv/shared/notes.txt` en la imagen de prueba) y `exec_short`; sin servidor, el tiempo de la pregunta que no cuenta, un ProxyCommand que falla, aceptar con errores pasajeros (tiempo simulado), las aperturas viejas de un túnel, la cola acotada, la salida sincronizada y la respuesta tardía de una carpeta; y en las pruebas de ventana, Esc con cambios, ⌘W sobre un host marcado, ⌘⇧T, salir con una transferencia en pausa, deshacer un snippet borrado y confirmar «Borrar».

**La puerta, medida:**
- un servidor que acepta TCP y no habla, con «Tiempo para conectar» a 2 s: la conexión se abandona entre 2 y 6 s con «no answer for 2 s» (`a_silent_server_is_given_up_on_in_time`), y la tarjeta lo dice como «no responde (2 s sin respuesta)»;
- un túnel SOCKS contesta a 300 conexiones a la vez, vuelve a 0 conexiones y sigue aceptando (`a_socks_tunnel_takes_a_browser_s_load`);
- salir con el terminal conectado y una transferencia en pausa pregunta «¿Salir de OpenWard?» con «1 sesión abierta, 1 transferencia en curso», y Cancelar sigue (prueba de ventana del SFTP);
- Esc en el editor de un host con un cambio pregunta «¿Descartar los cambios?»: Cancelar sigue editando y Descartar no guarda nada (prueba de ventana de los editores).

**Diferencias con el plan:**
- Un certificado inválido no reconecta sin certificados: se mira su clave simple en la misma conexión, que es lo que hace OpenSSH y ahorra una conexión.
- El agente que no firma y `MaxAuthTries` no tienen variantes nuevas en la FFI: el primero pasa a la siguiente clave y el segundo es «Autenticación fallida», que ya no se reintenta.
- `UserKnownHostsFile` y `GlobalKnownHostsFile` se importan y se guardan, pero aún no se editan en la app (editar el host los conserva); la página de Hosts conocidos sigue enseñando los de OpenWard y `~/.ssh/known_hosts`.
- El límite de descriptores de una app abierta desde el Finder (256) no se sube: hace falta código `unsafe`, que el núcleo no admite. Con muchas conexiones, el túnel espera a que se libere alguno en lugar de dejar de aceptar.
- `exec` sigue sin tope para los spikes y el benchmark; la app usa `exec_short`.
- Las copias en pausa o fallidas no se quitan de las que refrescan su carpeta: la refrescan una vez al pararse y otra al terminar.
- La salida sincronizada no tiene un temporizador propio: si el programa se calla a mitad, la pantalla se pone al día con la siguiente salida o tecla pasado el segundo. Leer el texto o seleccionar enseñan la pantalla de ese momento.
- Cerrar un navegador con transferencias no pregunta: siguen en la app y se ven en la cola. ⌘Q sí cuenta las sesiones locales.
- El texto de `NSLocalNetworkUsageDescription` va en inglés (la app aún no localiza su `Info.plist`). La nota del cask sobre la Red local se añade al publicar la beta, en el tap.
- De paso: el historial de comandos escribía lo pendiente al cerrarse leyendo `ref` dentro de `onDispose`, que Riverpod no permite; ahora guarda el archivo al empezar. Solo se notaba al cerrar la app medio segundo después de un comando.
- Al restaurar `authorized_keys`, la prueba que lo cambia lo escribe aparte y lo renombra: escrito en su sitio, otras pruebas en paralelo lo leían vacío y fallaban de vez en cuando.

### R4 · Formato y errores antes del vault cifrado (0.3.2-beta.4, ~1 semana)

Va antes de D3 (la migración), para migrar una vez y con el formato cerrado.
- **Formato:** `extra` también en los structs anidados (`Jump::Address`, `ProxyServer`, `EnvironmentMark`, `System`, `Source`, `Imported`), y la FFI los actualiza en su sitio (DT-10); fixtures de vaults escritos por la 0.3.0 y la 0.3.1, uno nuevo con cada versión que añada campos (DT-12); la migración entera en una transacción, con copia previa (`VACUUM INTO`) y las filas ilegibles a la vista (DT-11).
- **Errores tipados:** un `VaultError` (conflicto, no existe, en uso, inválido, ciclo, formato más nuevo, almacenamiento) en lugar de texto, traducido en la app con el detalle técnico en «Detalles»; Dart deja de buscar `'changed since'` y otras frases en inglés (DT-5). Un `runAction` que captura el error de cada mutación y lo dice, un manejador global y los lints de futuros sin esperar (UI-7).
- **Estado:** el editor fusiona con lo que cambió el núcleo (el sistema aprendido) en lugar de pedir que se cierre (UI-5); un evento «el vault cambió» del que dependen la biblioteca, los túneles y las claves (UI-14); el nombre de la pestaña sigue al del host (UI-15); el orden de los favoritos, en una transacción (DT-19).
- **Secretos:** `Zeroizing` en la contraseña del proxy, las respuestas interactivas y las claves importadas, `ProgramData` liberado al terminar, y un `Debug` que no imprime secretos (CX-11). Es la base de los secretos de D6.

**Puerta:** pasa la prueba de un campo desconocido anidado; un vault de la 0.3.0 abre, se migra y se lee con la 0.4; no queda ningún `contains(` sobre un error en Dart; ningún error del núcleo llega en inglés a una interfaz en español.

**Qué deja hecho:**
- **Campos desconocidos** (`openward-proto`): `extra` también en `System`, `Imported`, `Source::SshConfig`, `ProxyServer`, `EnvironmentMark` y `Jump::Address`. La FFI edita en su sitio: guardar un host conserva lo que una versión más nueva escribió dentro de su salto, su proxy, su entorno o su sistema, y `system::learned` también. `Imported` se compara por programa e id, no por lo que traiga de más.
- **Vaults publicados** (`openward-vault/tests/fixtures`): `vault-0.3.0.sqlite` y `vault-0.3.1.sqlite`, escritos con el código de `v0.3.0-beta.1` y `v0.3.1-beta.9` por `make.sh` (un worktree del tag y `gen-<versión>.rs` como ejemplo). `released_vaults.rs` los abre, comprueba cada tipo de elemento, guarda uno y lo vuelve a leer. Uno nuevo con cada versión que añada campos.
- **Migraciones** (`store.rs`): una lista de pasos (`STEPS`, de formato n a n + 1). Al abrir un archivo más viejo se copia como estaba (`VACUUM INTO`, `vault.sqlite.format-N.bak`, sin pisar una copia anterior) y se migra entero en una transacción: un paso que falla lo deja intacto. Las filas que esta versión no sabe leer (las escribió una más nueva) siguen en el archivo tal cual, y Ajustes › Acerca de dice cuántas.
- **Errores del vault, por tipo** (DT-5): `VaultError { kind, message }` con `Conflict`, `NotFound`, `InUse`, `Cycle`, `Invalid`, `NewerFormat`, `OpenElsewhere`, `FileChanged`, `Storage` y `Other`, en todas las funciones de la FFI que tocan el vault (de anyhow, `vault::Error`, `known::ForgetError`, `plan::PlanError` y `programs::Error`). La app los dice con sus palabras (`errorReason`, `saveErrorText`) y deja el texto del núcleo en «Detalles», que se lee y se copia. La pantalla de arranque dice por qué no abre (un formato más nuevo, otro OpenWard con los mismos datos).
- **Errores de conexión, por tipo:** `NetCause` (rechazada, no se encuentra, no se llega, no responde N s, perdida, o un ProxyCommand que falla, con lo que escribió) se decide en el núcleo por el tipo del error (`io::ErrorKind`, también el que russh lleva dentro y no enseña en la cadena, `russh::Error`, `NoAnswer`); solo un nombre que no resuelve se reconoce por lo que dice el sistema. Un certificado de host que no vale dice por qué (`CertProblem`: no es de host, ninguna `@cert-authority`, otra autoridad, caducado, otro nombre). Lo que el núcleo no sabe decir se dice «Algo ha fallado (más en «Detalles»)», con el botón al lado: en el panel de «No se ha podido conectar», en la barra de estado, en los túneles, al hacer, traer o instalar una clave, en el SFTP y al leer los datos de otro programa.
- **Avisos al importar, por tipo:** lo que no se trae de otro programa (`Missing`: X11, un proxy SOCKS4, telnet o de otro tipo, uno sin dirección, una llave física, una clave del vault de Tabby…) y un `Include` de `~/.ssh/config` que no se puede leer o sin permiso; de Termius, cuántos elementos no se han podido leer.
- **Acciones** (UI-7): `runAction` captura el error de un cambio (una estrella, un interruptor, un borrado, el orden de los favoritos) y lo dice con «Detalles»; `PlatformDispatcher.onError` dice los errores que nadie esperaba en lugar de perderlos; `unawaited_futures` en el análisis.
- **Estado** (UI-5, UI-14, UI-15, DT-19): guardar un host que cambió mientras se editaba (el sistema aprendido al conectar) fusiona a tres bandas con lo que se abrió (`update_host(…, base)`, por grupos de campos que van juntos), y solo un mismo campo cambiado en los dos sitios es un conflicto. `watch_vault` avisa de cada escritura, venga de donde venga: la biblioteca, los túneles, los snippets, las identidades, los espacios de trabajo y los hosts conocidos se refrescan, y el nombre de las pestañas y del historial de la paleta sigue al del host. El orden de los favoritos se guarda en una transacción (`update_all`).
- **Secretos** (CX-11): `Zeroizing` en la contraseña del proxy (con un `Debug` que no la imprime), en las claves importadas y su frase, y en lo que se lee de otros programas; `ProgramData` se libera al terminar, también si falla.
- **Pruebas:** un campo desconocido dentro de cada struct anidado, guardar sin perder lo que escribió una versión más nueva, los vaults de la 0.3.0 y la 0.3.1, una migración que corre una vez tras la copia y una que falla sin cambiar nada, cada escritura avisada, varios cambios todo o nada, los errores por tipo y la fusión a tres bandas; `NetCause` y cada `CertProblem` (con certificados hechos en la prueba); un puerto cerrado, rechazado por su tipo; contra los servidores S2, la conexión perdida, el servidor mudo y el certificado de otra CA, también por su tipo; en Dart, cada tipo de error en palabras, «Detalles», `runAction`, la pantalla de arranque y cada aviso al importar; y en las pruebas de ventana, renombrar un host con una pestaña abierta.

**La puerta, medida:**
- un campo desconocido dentro del salto, del proxy, del entorno y del sistema de un host sobrevive a leerlo y escribirlo (`unknown_fields_inside_are_kept`) y a guardarlo desde la app (`saving_keeps_what_a_newer_version_wrote_inside`);
- los vaults de la 0.3.0 y la 0.3.1 abren, se leen enteros, se guardan y se vuelven a leer (`a_vault_of_0_3_0`, `a_vault_of_0_3_1`); con un campo renombrado en el código, la prueba falla. La 0.4 aún no tiene pasos de migración: la maquinaria se prueba con pasos de prueba (copia y transacción), y el primero real (D3) correrá sobre estos mismos archivos;
- en `app/lib` no queda ningún `contains(`, `startsWith(` ni `RegExp` sobre el texto de un error: los de red y los de certificado se deciden por su tipo, y los avisos al importar también;
- lo que el núcleo dice en inglés solo se ve en «Detalles»: cada `VaultErrorKind`, `NetKind`, `CertKind` y `MissingKind` tiene sus palabras, y las pruebas comprueban que ninguna es la frase del núcleo.

**Diferencias con el plan:**
- `discarded_futures` no se activa: marca 45 llamadas que se lanzan a propósito sin esperar (abrir un diálogo desde un botón, refrescar al volver). `unawaited_futures` sí, y su único caso se ha marcado con `unawaited`.
- La fusión al guardar es solo para hosts, que es lo que el núcleo cambia por su cuenta; en grupos, identidades, snippets y túneles un cambio a la vez sigue siendo un conflicto con «Volver a cargar».
- Las respuestas a una pregunta interactiva van en `Zeroizing` hasta la llamada a russh, que las pide como `String` y no las borra.
- Las filas ilegibles de un grupo borrado no se mueven: siguen en el archivo con su grupo, y la versión que las escribió las verá sin él.
- Deshacer el borrado de un snippet o un túnel lo crea de nuevo, con otro id.
- De paso: un proxy de Termius sin dirección o sin puerto salía como «un proxy proxy without an address»; ahora es «un proxy sin dirección o sin puerto».

### R5 · Diseño, accesibilidad e idiomas (0.3.3 o dentro de la v0.4, ~2,5 semanas)

Los cuatro primeros cuestan menos de medio día cada uno y pueden entrar en cualquier beta.
- **Rápidos:** el botón de los avisos, legible en los 18 temas (DS-1); los controles del raíl, de la barra, de Hosts, del editor y las pestañas, activables con VoiceOver (DS-3); un anillo de foco de 2 px en los botones con el teclado (DS-4); tokens `onDanger` y `onWarn` y un `confirmDestructive()` común (DS-5).
- **Accesibilidad:** el entorno nunca solo por color en las filas y el raíl, y la latencia alta con algo más que el ámbar (DS-6); escalado del texto con tope y alturas que lo siguen (DS-14); objetivos de clic de 28 px en línea y 32 sueltos (DS-20); el terminal con `Semantics` por fila, regenerada solo en las filas sucias, y el cursor como valor de un campo de texto: la condición 4 de ADR-002 (TM-8); el cursor de bloque invierte el glifo y se vuelve hueco sin foco (TM-18); y pruebas con las combinaciones de colores que se usan de verdad, en Papel y Alto contraste, en inglés, al 150 % y a 760×480 (DS-15).
- **Sistema de diseño:** `OwPageHeader`, `OwEmptyState`, `OwFilterField`, `OwDataTable` y `OwButton.compact` para las páginas de la Biblioteca, que hoy los copian (DS-8); un filtro sin resultados lo dice (DS-21); diálogos de confirmación con Intro, Esc y foco inicial decididos (DS-12); los errores de validación en su campo, abriendo «Avanzado» si hace falta (DS-13).
- **Ventanas pequeñas:** mínimo de ventana en Windows y Linux, barra de estado en iconos por debajo de ~640 px y tablas que ocultan columnas (DS-7).
- **Idiomas:** un modelo único de atajos para la hoja, los tooltips y los menús, sin «Ctrl+Shift» en español (DS-10); los literales y formatos sueltos, y los entornos de serie traducidos al pintar (DS-22).
- **Lo que se echa en falta:** duplicar un host y soltarlo en un grupo; la selección múltiple, después (DS-16); un menú por clave (borrar, renombrar, cambiar la frase de paso, exportar, mostrar en Finder) (DS-17); la Biblioteca con nombres en la barra abierta e iconos propios (DS-18); la × al pasar el ratón, «Limpiar el búfer», Ctrl+Alt+1…9 y más entradas en el menú del terminal (DS-19).
- **Detalles del terminal:** pegado con los caracteres invisibles a la vista, y el historial solo con lo enviado (TM-14); los colores del programa (OSC 4/10/11/12) y la paleta del tema en el motor (TM-13); volver a la fuente del sistema la cambia de verdad (TM-21); el teclado numérico en modo aplicación y Opción izquierda o derecha como Alt (TM-23).

**Puerta:** la prueba de accesibilidad comprueba que todo nodo botón tiene su acción, el contraste de cada par usado y los objetivos de 28 px, en dos temas, dos idiomas y dos escalas; VoiceOver lee una línea del terminal.

### R6 · Deuda, pruebas, documentación y bajos (continuo, ~3 semanas repartidas)

- **Archivos grandes:** `hosts/editors.dart` en seis archivos, con el formulario puro y probado (UI-17, que además arregla una vista previa desfasada); `terminal_pane.dart` y `session_view.dart` (TM-25); una sola búsqueda de hosts (UI-16); tokens de espacio, texto, sombra y tiempo, con una prueba que prohíba literales fuera de `ui/` (DS-9).
- **Superficie:** las funciones de la FFI que solo usan las pruebas, bajo una feature (DT-20); la API de los spikes, fuera de `openward-ssh` (CX-22).
- **Pruebas:** Dart puro con un `Fake` de `OpenWard` para las pestañas, la conexión, la cola del SFTP, los espacios de trabajo, el formulario y la paleta (UI-18); el render, el atlas y `keys.dart` (TM-24); pruebas de datos hostiles y `cargo-fuzz` o proptest para cada importador (DT-13); márgenes de tiempo derivados de la configuración (BR-13).
- **Dependencias:** hmac y sha1 juntos, y tokio; grupos en dependabot, `pub` y sshprobe (BR-5).
- **Licencias y documentación:** las licencias de los crates (`cargo-about`) y de las dos fuentes que faltan, en la app, y Ghostty en NOTICE (BR-6); `make setup` y README, CONTRIBUTING y ARCHITECTURE al día (BR-8, BR-15).
- **Release:** `tool/bump-version.sh` y una prueba de que `coreVersion()` coincide con pubspec (BR-11); la caché de libghostty por versión de Zig y flags (BR-12); el toolchain de cargokit, comprobado (BR-16); paquetes de Linux en un contenedor y el runtime de VC++ en Windows (BR-10).
- **Rendimiento que puede esperar a que la medida lo pida:** el atlas compartido (TM-6); varios archivos en vuelo por trabajo en el SFTP (DT-7); un notificador por división en los paneles (UI-19); TM-15 a TM-17.
- **Resto de bajos:** CX-23, DT-14 a DT-18, TM-19, UI-13, UI-21, UI-22.

## Qué no entra

- **La firma y la notarización:** siguen al final, antes de publicar (ARCHITECTURE §15). BR-4 y BR-9 reducen lo que cuesta mientras tanto.
- **OSC 52** (TM-20): es una función, no un fallo, y hoy es seguro porque no está. Si se quiere, con permiso por host y nunca la lectura.
- **Avisos de versión nueva dentro de la app:** con Sparkle, junto a la firma.

## Decisiones que hacen falta

- **El orden:** R0–R3 antes de la v0.4, unas 5,5 semanas (lo propuesto); o solo R0 y R1 (unas 2) y R2–R3 intercalados con la v0.4.
- **`ssh-rsa` con SHA-1:** quitarlo de serie, con una opción heredada para servidores viejos (lo propuesto), o dejarlo y avisar.
- **ProxyCommand importado:** llega desactivado y con su texto a la vista (lo propuesto), o activo con un aviso.
- **⌘W sobre una sesión viva:** preguntar solo en los entornos marcados o con transferencias (lo propuesto), o siempre que haya sesión.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Ordenar los tipos de clave por lo conocido cambia hosts que hoy conectan sin preguntar | Solo cambia el orden de preferencia; las pruebas contra S2 cubren hosts con una, dos y tres claves; se cuenta en «Qué hay de nuevo» |
| Rechazar nombres remotos raros esconde archivos legítimos | Solo `/`, `\0`, `.` y `..` (más los de Windows en Windows); se cuentan y se dicen en el listado |
| El aviso de daño cambia la latencia de eco | El frame se pide en el mismo vsync; termbench mide el eco antes y después |
| Los timeouts cortan conexiones lentas de verdad | Por etapa, en pausa mientras el usuario responde, y `ConnectTimeout` por host |
| Las confirmaciones nuevas molestan | Solo con algo que perder (cambios, sesión de un entorno marcado, transferencias) y con «No volver a preguntar» |
| `make ci` tarda y se deja de usar | `make ci-quick` en cada commit; el completo antes de cada release y del fast-forward |
| Este documento describe fallos de seguridad abiertos | El repositorio es privado; R1 publicado antes de abrirlo |

## Hallazgos

Gravedad: **C** crítico, **A** alto, **M** medio, **B** bajo. Esfuerzo: **S** menos de medio día, **M** de 1 a 3 días, **L** más de 3. Rutas relativas a `core/crates/` (Rust) y a `app/lib/` (Dart), salvo que se diga otra cosa.

### BR · Build, CI y release

| ID | Grav. | Qué pasa | Dónde | Arreglo | Esf. | Hito |
|---|---|---|---|---|---|---|
| BR-1 | A | RUSTSEC-2026-0385: `ctutils` 0.4.3 hace comparaciones que no son de tiempo constante; llega por russh, ssh-key, rsa y p256/384/521. `make deny` falla | `core/Cargo.lock` | `cargo update -p ctutils` (a 0.4.5) | S | R0 |
| BR-2 | A | No hay CI local equivalente a `ci.yml`: alacritty, móvil, sshprobe, Flutter, pruebas de ventana, S2, Linux y Windows no se ejecutan desde el 2026-10-16 (15 betas). El código con `cfg(windows)` no lo compila nadie | `Makefile`, `.github/workflows/ci.yml` | `make ci` y la nota por SHA | M | R0 |
| BR-3 | A | Sin servidores S2, 29 pruebas de conexión (23 de `openward-app`, 6 de `openward-sftp`) hacen `return` y salen como superadas; `client.rs` (910 líneas) no tiene otra cobertura | `openward-app/tests/servers.rs:43`, `openward-sftp/tests/servers.rs:38` | `OPENWARD_REQUIRE_SERVERS=1` y recuento de saltadas | S | R0 |
| BR-4 | A | Nada comprueba de qué árbol sale el dmg (limpio, tag, versiones; `lipo` solo imprime) y el tap es público: un dmg con cambios sin commitear queda publicado como una versión | `app/tool/package-macos.sh:19-37`, `app/tool/release-tap.sh` | Comprobaciones y el SHA en las notas | S | R0 |
| BR-5 | M | Las PR de hmac 0.13 y sha1 0.11 no compilan por separado (`Hmac<Sha1>`); dependabot no mira `pub` ni sshprobe y puede subir flutter_rust_bridge solo en Rust | `.github/dependabot.yml` | Fusionar juntas, grupos, `pub`, ignorar frb | S | R6 |
| BR-6 | M | La lista de licencias de la app tiene 5 de las 7 fuentes (faltan Share Tech Mono y VT323) y ningún crate, aunque NOTICE dice lo contrario; libghostty-vt no aparece | `core/fonts.dart:6-12`, `NOTICE` | `cargo-about`, registrar las fuentes, prueba | M | R6 |
| BR-7 | M | El canal de seguridad es el reporte privado de un repositorio privado, mientras el binario es público; dice «fase 0» | `SECURITY.md:7,21-23` | Un correo o el reporte del tap; estado al día | S | R1 |
| BR-8 | M | Los pasos de README, `app/README` y CONTRIBUTING no funcionan desde cero (Zig «solo para el spike», la librería «se construye sola», «alfa 0.1.0») | `README.md:57`, `app/README.md`, `CONTRIBUTING.md` | `make setup` y documentos al día | S | R6 |
| BR-9 | M | Sin `NSLocalNetworkUsageDescription`; con firma ad hoc cada versión puede volver a pedir el permiso o quedarse denegada, y se ve «No route to host» (a comprobar) | `app/macos/Runner/Info.plist` | La clave, una pista ante `EHOSTUNREACH` y una nota en el cask | S | R3 |
| BR-10 | M | Sin paquetes de Linux ni Windows desde que paró la CI, aunque la guía y las notas los prometen; el zip de Windows no trae el runtime de VC++ (a comprobar) | `docs/plan/prueba-v0.2.md:9`, `app/windows/CMakeLists.txt` | `make package-linux`, `InstallRequiredSystemLibraries`, corregir la guía | M | R6 |
| BR-11 | B | La versión está en siete sitios y solo se prueba que `appVersion` coincide con pubspec | `app/pubspec.yaml`, `core/Cargo.toml`, `core/version.dart`, `welcome/whats_new.dart` | `tool/bump-version.sh` y prueba de `coreVersion()` | S | R6 |
| BR-12 | B | La caché de libghostty-vt se identifica solo por commit y destino: cambiar Zig o los flags reutiliza la vieja | `openward-ghostty/build-libghostty.sh:62-67` | Hash de Zig, flags y script en la ruta | S | R6 |
| BR-13 | B | `stalled <= 16 s` con un límite de 15 s y un `sleep(300 ms)`, en paralelo con otras 21 pruebas: candidatas a fallar a ratos (a comprobar) | `openward-app/tests/servers.rs:411,1378` | Márgenes de la configuración; sondeo en lugar de sleep | S | R6 |
| BR-14 | B | Sin `[profile.release]`: `openward_ffi.framework` ocupa 56 de los 108 MB de la app; el dmg pasó de 38 a 49 MB | `core/Cargo.toml` | `strip`, `lto = "thin"`, `codegen-units = 1` | S | R2 |
| BR-15 | B | ARCHITECTURE se presenta como «propuesta v0.1», lista 18 crates (hay 10) y da por hechos cargo-audit, SBOM y Sparkle; `docs/README.md` llama propuesta a los temas | `docs/ARCHITECTURE.md:3,115,138,409` | Una columna de estado | S | R6 |
| BR-16 | B | El toolchain de cargokit se copia a mano de `rust-toolchain.toml` | `openward-ffi/cargokit.yaml:5-8` | Comprobarlo en `make ci` | S | R6 |

### CX · Conexión SSH

| ID | Grav. | Qué pasa | Dónde | Arreglo | Esf. | Hito |
|---|---|---|---|---|---|---|
| CX-1 | A | «Reintentar ahora» y «Reconectar» generan otro nombre de tmux y cierran el terminal: la sesión con el trabajo del usuario queda huérfana en el servidor | `openward-app/src/lib.rs:153-157,667-679`, `terminal.rs:210` | El nombre en el terminal; `detach()` aparte de `close()` | S | R1 |
| CX-2 | A | El tipo de clave del host se negocia sin mirar las conocidas (siempre Ed25519): un host conocido solo por ECDSA o RSA sale como nuevo, y con `AcceptNew` se aprende otra clave sin avisar; los nombres distinguen mayúsculas | `openward-ssh/src/client.rs:309-322`, `known_hosts.rs:103-132,222-234` | Orden por lo conocido, veredicto «otro tipo», minúsculas | M | R1 |
| CX-3 | M | `KnownHost::to_line()` concatena sin validar: un comentario importado con `\n@cert-authority * …` convierte una clave en CA de todos los hosts | `openward-proto/src/lib.rs:395-410`, `openward-import/src/termius/model.rs:466` | Rechazar `\r`, `\n` y espacios al validar; construir sin pasar por texto | S | R1 |
| CX-4 | M | `%h`, `%r` y `%n` entran en `sh -c` sin comillas (la clase de CVE-2023-51385); los ProxyCommand de PuTTY, MobaXterm y Tabby se importan activos y sin aviso | `openward-app/src/local.rs:71-90`, `openward-import/src/putty.rs:287`, `mobaxterm.rs:169`, `tabby.rs:149` | Rechazar metacaracteres al expandir; importarlos desactivados y a la vista | S | R1 |
| CX-5 | M | Solo se lee `~/.ssh/known_hosts`: no se aplican los `@revoked` ni los `@cert-authority` del archivo global | `openward-app/src/local.rs:46-50` | Archivos globales y `UserKnownHostsFile` | S–M | R3 |
| CX-6 | M | No hay ningún timeout al conectar (TCP, banner, intercambio, autenticación, estado de tmux): un servidor mudo deja «Conectando» para siempre, y no cuenta como intento | `openward-ssh/src/client.rs:338-371`, `proxy.rs:54`, `openward-app/src/lib.rs:573` | Timeouts por etapa, `ConnectTimeout` | M | R3 |
| CX-7 | M | ProxyCommand con el `PATH` de launchd (sin `/opt/homebrew/bin`) y el stderr perdido: `cloudflared` o `aws ssm` fallan con «Disconnected» | `openward-ssh/src/client.rs:272-285,340-353` | El PATH del shell de login; stderr en el fallo | S | R3 |
| CX-8 | M | `while let Ok(..) = accept()` sale al primer error (EMFILE con un navegador por SOCKS): el túnel sigue «Abierto» y no acepta | `openward-app/src/tunnels.rs:332,356`, `openward-ssh/src/forward.rs:33` | Reintentar los pasajeros; `Failed` el resto | S | R3 |
| CX-9 | M | Cerrar o borrar un túnel no corta sus conexiones, y la sesión SSH sigue viva e invisible | `openward-app/src/tunnels.rs:92-103,333-361` | `JoinSet` o token de cancelación; `Weak<Live>` | S–M | R3 |
| CX-10 | M | Un agente que se niega a firmar o `MaxAuthTries` se clasifican como red: se reintenta 8 veces, reofreciendo todas las claves | `openward-app/src/connect.rs:349-354,430-462,568` | Variantes propias que no se reintentan | S–M | R3 |
| CX-11 | M | Secretos en `String` normales y con `Debug`: la contraseña del proxy, las respuestas interactivas, y las claves y frases importadas de Termius (`ProgramData` no se libera nunca) | `openward-app/src/connect.rs:308,567`, `openward-ssh/src/proxy.rs:19-27`, `openward-import/src/bundle.rs:141` | `Zeroizing`, sin `Clone`, `dispose()` | S | R4 |
| CX-12 | M | El runtime tiene 2 workers y hace trabajo bloqueante: recorrer carpetas locales del SFTP, SQLite y el parseo del terminal. Subir dos `node_modules` para todas las sesiones | `openward-app/src/lib.rs:76-81`, `openward-sftp/src/transfer.rs:646-660` | `spawn_blocking`; un hilo de parseo por terminal | M | R2 |
| CX-13 | B | Se aceptan firmas de host `ssh-rsa` (SHA-1), que OpenSSH quitó en la 8.8 | `openward-ssh/src/client.rs:309-322` | Fuera de serie, con opción heredada | S | R1 |
| CX-14 | B | Los túneles a `localhost` escuchan solo en 127.0.0.1, no en ::1 (a comprobar) | `openward-app/src/tunnels.rs:118-130` | Las dos familias | S | R3 |
| CX-15 | B | Con una línea `@cert-authority`, un certificado de otra CA o caducado es un fallo duro | `openward-app/src/connect.rs:219` | Reintentar sin certificados | S | R3 |
| CX-16 | B | La salida de `exec` no tiene límite y `PRETTY_NAME` se guarda sin acotar | `openward-ssh/src/client.rs:758-769`, `openward-app/src/system.rs:88-130` | 64 KiB y el nombre recortado | S | R3 |
| CX-17 | B | Sondeos cada 250 ms por conexión, y cada 500 ms–1 s en túneles y SFTP | `openward-app/src/alive.rs:98,118`, `tunnels.rs:212`, `sftp.rs:29` | `sleep_until` y `Notify` | S–M | R2 |
| CX-18 | B | Canal sin cota en la bomba del shell: las respuestas a DSR/DA se acumulan si el servidor no abre ventana (a comprobar) | `openward-app/src/terminal.rs:507,553` | Canal acotado | S | R3 |
| CX-19 | B | `Live::drop` desconecta sin timeout | `openward-app/src/live.rs:107-117` | El de `mark_lost` | S | R3 |
| CX-20 | B | Cerrar durante `listen` deja el túnel abierto; un doble «abrir» cierra el primero | `openward-app/src/tunnels.rs:160-199` | Número de generación | S | R3 |
| CX-21 | B | El PTY solo manda `ECHO`: sin `IUTF8`, el retroceso sobre «ñ» rompe bytes en Linux (a comprobar) | `openward-ssh/src/client.rs:806,831` | Los modos de OpenSSH | S | R3 |
| CX-22 | B | `openward-ssh` expone una segunda autenticación que solo usan los spikes y las pruebas, con una heurística que manda la contraseña a cualquier pregunta que diga «password» | `openward-ssh/src/client.rs:61-82,415-494`, `totp.rs` | Detrás de una feature | S | R6 |
| CX-23 | B | `${VÁR}` salta bytes como si fueran caracteres y pierde lo que sigue; faltan pruebas de `Local::expand` y de SOCKS5 mal formado | `openward-app/src/local.rs:96-104` | Índices por carácter y pruebas | S | R6 |

### DT · Datos: vault, SFTP, importadores, FFI

| ID | Grav. | Qué pasa | Dónde | Arreglo | Esf. | Hito |
|---|---|---|---|---|---|---|
| DT-1 | C | Path traversal al descargar carpetas: un servidor que lista `../../.zshrc` escribe fuera de la carpeta de destino, y sin conflicto arriba se sobrescribe (como CVE-2019-6111) | `openward-sftp/src/remote.rs:105-110,352`, `transfer.rs:589,630-634` | Rechazar los nombres al listar; `Component::Normal` y `starts_with(raíz)` | S | R1 |
| DT-2 | A | La reanudación toma el tamaño de cualquier `<nombre>.part` (otra descarga, otra versión, el de un navegador) y solo comprueba el tamaño final: corrupción silenciosa. Cancelar borra un `.part` ajeno. Una prueba fija este comportamiento | `openward-sftp/src/transfer.rs:744-756,811-815`, `tests/servers.rs:400-463` | Un `.part` propio con los metadatos del origen | M | R1 |
| DT-3 | A | El mutex del vault se retiene mientras se genera una clave RSA-4096 (segundos), se lee known_hosts o ssh_config o se descifran claves; lo comparten la UI y el runtime | `openward-ffi/src/api/keychain.rs:114-121`, `openward-app/src/lib.rs:450-512` | Copiar y soltar antes del trabajo caro | M | R2 |
| DT-4 | A | FFI síncrona con disco o cálculo en el hilo de la UI: el contador de la Biblioteca lee known_hosts y calcula un HMAC por cada par host×línea **en cada cambio de pestaña**, y la página lo repite en cada tecla; también `keys()`, `identities()`, `installed_programs()` y `key_comment()`, que lanza `hostname` | `hosts/sidebar.dart:1107`, `known_hosts/known_hosts_page.dart:134`, `openward-ffi/src/api/keychain.rs:93-158`, `known_hosts.rs:74`, `programs.rs:304` | Contador cacheado; asíncronas; sync solo para lo que está en memoria | S–M | R2 |
| DT-5 | A | 50 funciones devuelven `anyhow` como texto: el usuario lee «No se ha podido guardar: AnyhowException(the vault changed since…)» (23 sitios con `'$e'`), y Dart decide buscando frases en inglés (`'changed since'`, `'inside itself'`, `'jump host'`, `'file changed'`) | `hosts/editors.dart:2481,2623`, `snippets/snippet_editor.dart:105`, `hosts/host_actions.dart:85`, `tabs/messages.dart:41-65`, `openward-vault/src/lib.rs:43` | `VaultError` tipado y traducido, como `FileError` | M | R4 |
| DT-6 | M | Cerrar un terminal local bloquea la UI 50–200 ms (portable-pty duerme antes de SIGKILL); con seis paneles, hasta 1,2 s | `openward-ffi/src/api/session.rs:884`, `openward-pty/src/lib.rs:122` | `clone_killer()` y escalado en segundo plano | S | R2 |
| DT-7 | M | Cada archivo subido cuesta unas 8 idas y vueltas, en serie: 5000 archivos a 80 ms, unos 50 min | `openward-sftp/src/transfer.rs:571-617,715-774` | Varios en vuelo; sin stat redundantes | M–L | R6 |
| DT-8 | M | La subida sustituye con `rename`: pierde propietario, ACL y enlaces, y un symlink del servidor pasa a ser un archivo; sin `posix-rename`, el destino se borra antes | `openward-sftp/src/transfer.rs:772`, `remote.rs:198-230` | Resolver symlinks; escribir en sitio si es de otro; `.bak` | M | R3 |
| DT-9 | M | Dos procesos sobre el mismo `vault.db` (la build de desarrollo y la instalada) se pisan sin error | `openward-vault/src/store.rs:33-49,102-125` | Candado advisorio y `WHERE head_rev = ?` | S | R1 |
| DT-10 | M | Los structs anidados no tienen `extra`: un campo nuevo dentro de `Jump::Address`, `ProxyServer`, `EnvironmentMark`, `System`, `Source` o `Imported` se pierde al reescribir el ítem | `openward-proto/src/settings.rs:125,147,173`, `lib.rs:165,212,220`, `openward-ffi/src/api/vault.rs:323-378` | `#[serde(flatten)] extra` y una prueba | S | R4 |
| DT-11 | M | Las filas ilegibles no se ven en la app y borrar un grupo no las recoloca; si la v0.4 migra fila a fila, volver a la 0.3 enseña un vault vacío | `openward-vault/src/lib.rs:87-96,342-403` | La migración en una transacción, copia, recuento visible | M | R4 |
| DT-12 | M | No hay fixtures de vaults escritos por versiones publicadas: renombrar un campo pasa todas las pruebas y rompe los vaults tras `brew upgrade` | `openward-proto/src/lib.rs:500-700`, `openward-vault/src/tests.rs` | `tests/fixtures/vault-0.3.0.sqlite` y CBOR por tipo | S–M | R4 |
| DT-13 | M | Ninguna prueba de nombres remotos hostiles, de un `.part` ajeno, de campos anidados, de dos procesos ni del PTY; ningún fuzz de los parsers de entrada no confiable | — | Pruebas y `cargo-fuzz` o proptest | M | R6 |
| DT-14 | B | Importadores: lectura sin límite de tamaño, YAML con alias que se multiplican, `with_capacity` con un `u32` del archivo, recorridos que siguen symlinks sin límite | `openward-import/src/detect.rs:148,215`, `tabby.rs:39`, `termius/leveldb.rs:312` | Límites y `symlink_metadata` | S | R6 |
| DT-15 | B | `follow_links` lanza dos peticiones por symlink, sin límite, también al borrar o recorrer | `openward-sftp/src/remote.rs:127-154` | Concurrencia acotada | S | R6 |
| DT-16 | B | Bajar un archivo 0600 lo deja 0644 en local | `openward-sftp/src/transfer.rs:858-871` | Respetar los permisos restrictivos | S | R6 |
| DT-17 | B | Cerrar un terminal local solo señala la shell (un `nohup` mantiene el PTY); `LANG=en_US.UTF-8` fijo | `openward-pty/src/lib.rs:73-75,122` | `killpg`, `wait()`, el locale del sistema | S | R6 |
| DT-18 | B | Las claves de Termius se escriben en `~/.ssh` antes que el vault, sin `fsync` ni temporal | `openward-app/src/programs.rs:519-533,841-852` | Temporal, `sync_all`, `rename` | S | R6 |
| DT-19 | B | `order_favorites` hace N transacciones y no es atómico | `openward-ffi/src/api/app.rs:314-341` | `update_all` | S | R4 |
| DT-20 | B | Funciones solo para pruebas en la FFI de producción, y `known_hosts()` duplicada | `openward-ffi/src/api/app.rs:166-190,458-477` | Bajo una feature | S | R6 |

### TM · Terminal

| ID | Grav. | Qué pasa | Dónde | Arreglo | Esf. | Hito |
|---|---|---|---|---|---|---|
| TM-1 | A | El `Ticker` arranca en `initState` y no para: con un terminal a la vista, la app compone y rasteriza un frame en cada vsync (120 Hz en ProMotion) aunque no haya salida | `terminal/terminal_pane.dart:53,104,188` | Aviso de daño desde Rust y frame a demanda | M | R2 |
| TM-2 | A | La longitud de un tramo es `u16`: una fila ancha con grafemas largos (hasta 64 puntos de código por celda) la desborda, `decodeFrame` lanza en cada frame y la vista se congela | `openward-term/src/frame.rs:215-224`, `terminal/frame.dart:145`, `terminal/controller.dart:225` | Cerrar el tramo antes; try/catch y `redraw()` | S | R1 |
| TM-3 | A | La caché de contraste mínimo (activa de serie) guarda cada par fg/bg y no se vacía: con color de 24 bits (lolcat, chafa, previsualizaciones) crece sin límite | `terminal/renderer.dart:35,94-100` | LRU acotada, o solo la paleta | S | R2 |
| TM-4 | M | Cada tecla de la búsqueda recorre todo el historial de forma síncrona, dos veces, en el hilo de la UI | `openward-ghostty/src/engine/find.rs:62-137`, `tabs/find_bar.dart:36` | Esperar y avanzar por pasos acotados | M | R2 |
| TM-5 | M | Arrastrar un divisor redimensiona en cada frame: reflujo síncrono y un `window-change` por SSH que hace reimprimir el prompt | `terminal/terminal_pane.dart:197-210`, `tabs/session_view.dart:261` | Al soltar, o tras 120 ms | S | R2 |
| TM-6 | M | Un atlas de hasta 16 MiB por pestaña, que se copia entero con cada glifo nuevo; lleno, todo glifo nuevo va por Paragraph para siempre | `terminal/glyph_atlas.dart:17-116` | Un atlas compartido, por páginas | M | R6 |
| TM-7 | M | ⌘+clic abre un enlace OSC 8 sin enseñar su destino real; una URL partida en dos filas se abre recortada | `terminal/terminal_pane.dart:740-760`, `openward-ghostty/src/engine/find.rs:227-376` | Destino a la vista; unir las filas | S–M | R1 |
| TM-8 | M | El terminal no expone nada a los lectores de pantalla; la prueba de accesibilidad pasa porque no hay nodos | `terminal/renderer.dart:413-440`, ADR-002 | `Semantics` por fila | M–L | R5 |
| TM-9 | M | No se respeta la salida sincronizada (modo 2026): parpadeo en neovim, helix y tmux | `openward-ghostty/src/engine.rs:230-263` | `RENDER_HOLD` con tope de 1 s | S–M | R3 |
| TM-10 | M | El historial no se comprime nunca (la función existe y solo la usan las pruebas) ni tiene tope de bytes: 10 pestañas con 100.000 líneas rondan 1 GB | `openward-ghostty/src/engine.rs:286-293,449-474` | Comprimir en reposo, con tope | S | R2 |
| TM-11 | M | Mantener `j` o `k` en vim puede abrir el selector de acentos de macOS en lugar de repetir (a comprobar) | `terminal/terminal_pane.dart:317` | `ApplePressAndHoldEnabled = false` | S | R3 |
| TM-12 | M | Seleccionar arrastrando fuera del borde en less o man manda flechas al programa y borra la selección | `terminal/terminal_pane.dart:820-841`, `openward-ghostty/src/engine/input.rs:410` | Desplazar el historial sin teclas | S | R3 |
| TM-13 | B | Los colores que fija el programa (OSC 4/10/11/12) no se pintan, y las consultas devuelven la paleta de Ghostty, no la del tema | `openward-ghostty/src/engine.rs:42-51,399-426` | Pasar la paleta al motor | S | R5 |
| TM-14 | B | La vista previa del pegado no hace visibles los controles ni los caracteres bidireccionales; el historial guarda pegados cancelados | `terminal/terminal_pane.dart:397-451` | Hacerlos visibles; guardar después de enviar | S | R5 |
| TM-15 | B | Intro copia la pantalla entera hasta cuatro veces antes de enviarse | `openward-ghostty/src/engine.rs:764-887`, `history/line_tracker.dart:117` | Solo hasta el cursor, una vez | S | R6 |
| TM-16 | B | De 6 a 9 llamadas FFI por celda y listas temporales por glifo | `openward-ghostty/src/engine.rs:634-718`, `terminal/renderer.dart:116-209` | `RAW` una vez; buffers preasignados | S | R6 |
| TM-17 | B | `_hasColorGlyph` manda tramos enteros al camino lento por un icono de Nerd Font | `terminal/renderer.dart:236-289` | Solo emoji; partir el tramo | S | R6 |
| TM-18 | B | El cursor de bloque no invierte el glifo, no cubre un carácter ancho y no se vuelve hueco sin foco | `terminal/renderer.dart:348-373` | Invertir, ancho, hueco | S | R5 |
| TM-19 | B | `Effects` vive en un `Box` cuyo puntero crudo tiene C (UB formal), y métodos `&self` mutan estado C | `openward-ghostty/src/engine.rs:152-198,580-604` | `NonNull` y `&mut self` | S | R6 |
| TM-20 | B | OSC 52 no está: copiar desde vim o tmux remotos no llega al portapapeles | `openward-ghostty/src/engine.rs:230-263` | Ver «Qué no entra» | M | — |
| TM-21 | B | Volver a la fuente del sistema no la cambia en el terminal | `terminal/controller.dart:144-152` | Distinguir null de «sin cambio» | S | R5 |
| TM-22 | B | Las pestañas ocultas codifican y graban frames completos 4 veces por segundo | `terminal/controller.dart:267-280` | Solo el título y la campana; `redraw()` al volver | S | R2 |
| TM-23 | B | El teclado numérico va como texto (sin modo aplicación); Opción como Alt es global | `terminal/keys.dart:59-66`, `openward-ghostty/src/engine/input.rs:306` | `DECKPAM`; izquierda o derecha | S | R5 |
| TM-24 | B | Sin pruebas del render, del atlas, de `keys.dart` ni del límite de TM-2 | — | Pruebas | M | R6 |
| TM-25 | B | `terminal_pane.dart` (1032 líneas) mezcla teclado, IME, ratón, pegado y enlaces; `session_view.dart` (1246), paneles, cabeceras y barra de estado; el diálogo de pegado está duplicado | — | Partir en cinco archivos | M | R6 |

### UI · App Flutter

| ID | Grav. | Qué pasa | Dónde | Arreglo | Esf. | Hito |
|---|---|---|---|---|---|---|
| UI-1 | A | `RustLib.init()` y `OpenWard.open()` sin try/catch: con un vault de una versión más nueva (bajar de beta con Homebrew), sin permisos o corrupto, la ventana queda vacía y sin mensaje | `main.dart:17-23` | Pantalla de error con «Mostrar la carpeta» | S | R1 |
| UI-2 | A | `late final Timer _tick` solo se lee en `dispose()`: el temporizador se crea al cerrar y nunca hace tic. «Reintento en X s», su anillo y «sin respuesta desde N s» se quedan quietos | `tabs/connection_panels.dart:182`, `tabs/connection_motion.dart:344,466` | Crearlo en `initState`; prueba de 1 s | S | R1 |
| UI-3 | A | `visible` del SFTP filtra y ordena en cada acceso, con una `RegExp` por comparación, y se llama por cada fila seleccionada: ⌘A y una flecha en 5000 entradas tardan segundos | `sftp/files.dart:132-161,345-357` | Cachear e invalidar; clave precalculada | S | R2 |
| UI-4 | A | ⌘W, el clic central, «Cerrar las N», ⌘Q y cerrar la ventana cortan sesiones conectadas (también de producción), transferencias y túneles sin preguntar, y no se puede reabrir la pestaña | `tabs/tabs.dart:200,220,564`, `tabs/tab_strip.dart:723`, `hosts/sidebar.dart:727`; no hay `onExitRequested` | Confirmar cuando hay algo que perder; reabrir la última | M | R3 |
| UI-5 | M | El núcleo sube la revisión del host al aprender su sistema: editar un host recién conectado acaba en «cambió mientras tanto» y se pierden los cambios | `hosts/editors.dart:2415,2443-2485`, `openward-app/src/connect.rs:56-70` | Releer y fusionar a tres bandas | M | R4 |
| UI-6 | M | Ajustes, historial y recientes se guardan con `writeAsStringSync` en el hilo de la UI y sin temporal: un cierre a mitad deja un JSON roto que se descarta en silencio; el historial reescribe hasta 2000 entradas en cada Intro | `core/settings.dart:446-459`, `history/history.dart:97-142`, `home/recent.dart:196` | Temporal y `rename`; el historial, con espera | S | R1 |
| UI-7 | M | Mutaciones asíncronas sin capturar (favoritos, borrados, túneles con `rev`) y sin manejador global: en release el error se pierde y el interruptor vuelve atrás sin aviso | `hosts/host_actions.dart:36`, `tunnels/tunnels_page.dart:78-104,477`, `analysis_options.yaml` | `runAction`, manejador global, lints de futuros | S–M | R4 |
| UI-8 | M | `FilePane.open` no lleva número de petición: una respuesta tardía devuelve la vista a la carpeta anterior; los trabajos en pausa salen de la lista que refresca el destino | `sftp/files.dart:182-207`, `sftp/sftp_controller.dart:125` | Generación; solo `finished` | S | R3 |
| UI-9 | M | `OwTheme` no tiene `==`: cualquier cambio de ajustes, también ⌘B, reconstruye la app entera con sus terminales | `ui/tokens.dart:210-254`, `app.dart:15-23` | `==`, o `select` de los campos del tema | S | R2 |
| UI-10 | M | `TunnelBoard` consulta los túneles cada 500 ms mientras haya delante un terminal de un host guardado, tenga túneles o no | `tunnels/tunnels_page.dart:509-520,698-710`, `tunnels/tunnels.dart:47-65` | Eventos, o solo si tiene túneles | S–M | R2 |
| UI-11 | M | La paleta regenera y puntúa todas las entradas (cada host dos veces, 2000 del historial) en cada tecla y cada flecha | `palette/command_palette.dart:85-99,146-500` | Una vez por consulta; `RegExp` estática | S | R2 |
| UI-12 | M | La barra y la página de Hosts no escalan: `ListView(children:)`, búsqueda O(n²) por id, `countUnder` recursivo, y la barra vigila todo `tabsProvider` | `hosts/sidebar.dart:107,141`, `core/providers.dart:97`, `hosts/hosts_page.dart:112-170` | Índices, `ListView.builder`, providers memoizados | M | R2 |
| UI-13 | M | Al volver a montarse, el buscador de la barra y el filtro del SFTP salen vacíos con el filtro aún aplicado | `hosts/sidebar.dart:53`, `sftp/sftp_view.dart:102-131` | Inicializar desde el modelo | S | R6 |
| UI-14 | M | Cada notificador se refresca a mano tras cada mutación, con omisiones: borrar un host borra sus túneles, pero el contador no cambia | `hosts/host_actions.dart:61-93` | Evento «el vault cambió» | M | R4 |
| UI-15 | M | Renombrar un host con sesión abierta deja el nombre viejo en la pestaña, en «Abiertas» y en el historial | `core/connection.dart:40`, `tabs/tab_strip.dart:481` | Resolverlo al mostrar | S | R4 |
| UI-16 | M | Hay cuatro búsquedas de hosts distintas (la del núcleo, `matchScore` y dos `contains`): «web prod» da resultados distintos según dónde se busque | `home/start_page.dart:120-158`, `tabs/session_view.dart:668`, `keys/key_dialogs.dart:426` | Un `HostMatcher` | S–M | R6 |
| UI-17 | M | `hosts/editors.dart` tiene 2681 líneas, con el formulario mutable compartido entre padre e hijo: cambiar el entorno deja desfasada la vista previa del sistema | `hosts/editors.dart:106-372,745-757,2552` | Seis archivos; formulario `ChangeNotifier` | M | R6 |
| UI-18 | M | Sin pruebas unitarias de `TabsNotifier`, `ConnectionController.onEvent`, la cola del SFTP, los espacios de trabajo, el formulario ni la paleta: solo los cubre la prueba de ventana | — | Dart puro con un `Fake` de `OpenWard` | M | R6 |
| UI-19 | B | `Panes` es un solo `ChangeNotifier`: cada píxel al arrastrar un divisor reconstruye la vista, las pestañas y «Abiertas» | `tabs/panes.dart:245` | Un notificador por división | S–M | R6 |
| UI-20 | B | `openTunnel` espera en un bucle a 20 Hz y pregunta con el `context` de quien lo llamó: si la página se desmonta, la pregunta no sale y el túnel se queda «abriendo» | `tunnels/tunnels.dart:110-147` | `Completer` y el navegador raíz | S | R3 |
| UI-21 | B | Renombrar una pestaña usa el índice de antes del `await`, y el controlador se libera mientras el campo sigue montado | `tabs/tab_strip.dart:127-161`, `settings/appearance_page.dart:554` | Capturar la pestaña; el controlador en el `State` | S | R6 |
| UI-22 | B | La minigráfica recibe la lista mutable y `shouldRepaint` la compara consigo misma: con latencias iguales seguidas no avanza | `tabs/latency.dart:61,192` | Copia o contador | S | R6 |

### DS · Diseño, accesibilidad e idiomas

| ID | Grav. | Qué pasa | Dónde | Arreglo | Esf. | Hito |
|---|---|---|---|---|---|---|
| DS-1 | A | El botón de los avisos (acento sobre el color del texto) no llega a 4,5:1 en ningún tema: Fósforo 1,06, Búnker 1,07, Monitor 1,09, Grafito 1,69. Se ve el aviso de «Leer /etc/os-release», pero no su botón | `ui/themes.dart:1188-1191`, `home.dart:96-105` | `c.surface` en negrita o un token `inverseAccent`; el par en theme_test | S | R5 |
| DS-2 | A | Los paneles de edición se cierran con un clic fuera o con Esc (también con el cursor en un campo) y tiran los cambios sin avisar: host, grupo, identidad, túnel y snippet | `hosts/editors.dart:47-49,2074` | `EditorFrame(dirty:)` y «¿Descartar los cambios?» | M | R3 |
| DS-3 | A | Un `Semantics(button, excludeSemantics: true)` sin `onTap` se come la acción del hijo: con VoiceOver no se pueden pulsar los botones del raíl, «Abiertas», Hosts, la Biblioteca, los filtros de Hosts, la caja heredada del editor, el selector de sistema ni las pestañas | `hosts/rail.dart:417`, `hosts/sidebar.dart:751,873,1238`, `hosts/hosts_page.dart:649`, `hosts/editors.dart:1568,2353`, `tabs/tab_strip.dart:715` | `onTap` en el `Semantics`; prueba de que todo botón tiene `tap` | S | R5 |
| DS-4 | M | Los botones no definen el estado `focused`: con Tab apenas se ve dónde está el foco, peor donde primario y acento coinciden | `ui/themes.dart:1050-1106` | Anillo de 2 px en el acento, solo con teclado | S | R5 |
| DS-5 | M | Cinco combinaciones a mano en los botones de peligro y aviso, y dos suspenden (Nativo oscuro 2,82:1, Berenjena oscuro 2,54:1); «Eliminar host o grupo» usa el botón principal y no parece destructivo | `workspaces/workspaces_page.dart:239`, `known_hosts/known_hosts_page.dart:108`, `identities/identity_editor.dart:159`, `snippets/snippets.dart:287`, `hosts/host_actions.dart:73` | `onDanger`, `onWarn`, `dangerButtonStyle()`, `confirmDestructive()` | S | R5 |
| DS-6 | M | En Favoritos, Recientes, la búsqueda y el raíl, el entorno va solo por el color de un logo de 20 px; en Búnker «pre», «pruebas» y «sin entorno» son verdes; la latencia alta solo cambia de color | `hosts/sidebar.dart:505`, `hosts/rail.dart:180`, `tabs/latency.dart:28` | EnvChip corto o letra; «▲» y etiqueta semántica | S | R5 |
| DS-7 | M | Mínimo de ventana solo en macOS; las páginas de la Biblioteca no se adaptan; la barra de estado necesita unos 600 px en Windows y en español y se corta sin aviso; el panel lateral mide 560 px fijos | `windows/runner`, `linux/runner`, `tabs/session_view.dart:1046-1180`, `hosts/editors.dart:43` | Mínimos, iconos por debajo de ~640 px, tablas que ocultan columnas | M | R5 |
| DS-8 | M | Faltan primitivas: 7 cabeceras de página con tres anchos máximos, 8 estados vacíos, unos 10 campos de filtro, 5 tablas iguales y 8 «botones compactos» copiados | `snippets/snippets_page.dart:61`, `tunnels/tunnels_page.dart:160`, `keys/keys_page.dart:98`, `identities/identities_page.dart:74` | `OwPageHeader`, `OwEmptyState`, `OwFilterField`, `OwDataTable`, `OwButton.compact` | M | R5 |
| DS-9 | M | Hay tokens de color, forma y fuente, pero no de espacio, texto, sombra ni tiempo: 329 `EdgeInsets` literales, 182 `fontSize: 12` frente a 15 usos de `textTheme`, 23 radios que ignoran `OwShape` (esquinas redondas en los temas rectos), 8 sombras, 4 esperas de tooltip | `hosts/editors.dart`, `sftp/`, `ui/environment.dart:331` | `OwSpace`, roles de texto, `OwMotion`, `OwElevation`, prueba de literales | M–L | R6 |
| DS-10 | M | Las teclas de los atajos se escriben a mano en unos 40 sitios: «Ctrl+Shift+S» en español donde la hoja dice «Ctrl+Mayús+S»; «Supr» también en inglés; «⇧⌘N» frente a «⌘⇧N»; «⌫» en Windows | `snippets/snippets_page.dart:55`, `settings/settings_page.dart:488`, `sftp/sftp_view.dart:409,420`, `palette/command_palette.dart:776` | Un modelo único de atajos y una prueba | S–M | R5 |
| DS-11 | M | Un snippet y un túnel se borran al primer clic, sin deshacer (el túnel, sin try/catch); «Borrar (N)» de los recientes y del historial, también | `snippets/snippet_editor.dart:112`, `tunnels/tunnel_editor.dart:116`, `settings/settings_page.dart:235,496` | «Eliminado · Deshacer»; confirmar los dos «Borrar» | S | R3 |
| DS-12 | M | En los diálogos de confirmación Intro no hace nada y el foco inicial no está decidido | `hosts/host_actions.dart:63`, `identities/identity_editor.dart:144`, `sftp/dialogs.dart:640` | `showOwConfirm()` común | S | R5 |
| DS-13 | M | Los errores de validación salen solo al pie del editor, sin llevar el foco al campo, aunque esté plegado en «Avanzado», y sin que el lector lo diga | `hosts/editors.dart:2128-2132,2451` | `errorText` en el campo, abrir «Avanzado», `liveRegion` | S–M | R5 |
| DS-14 | M | La escala del sistema se multiplica por la de Ajustes sin tope (los ajustes aceptan 200 %), con alturas fijas que contienen texto: barra superior de 40 px, barra de estado de 30, filas del SFTP de 30 (a comprobar) | `app.dart:28-30`, `window/chrome.dart:16`, `tabs/session_view.dart:1116`, `sftp/sftp_view.dart:29` | Tope de 2,0 y alturas que siguen la escala | M | R5 |
| DS-15 | M | Las pruebas no miran las combinaciones que se usan: ni el acento sobre el texto, ni los botones de peligro, ni `accentText` sobre `selected` (Nativo claro 4,47); la de accesibilidad prueba un solo tema, idioma, tamaño y escala | `test/theme_test.dart:27-48`, `integration_test/a11y_test.dart:188-219` | Pares de los usos reales; dos temas, dos idiomas, dos escalas | S | R5 |
| DS-16 | M | Organizar hosts: no se puede duplicar, soltar en un grupo ni seleccionar varios; «Eliminar» abre un diálogo sin «…» | `hosts/host_actions.dart:136-149`, `hosts/sidebar.dart:54`, `hosts/hosts_page.dart:68` | Duplicar (S), soltar en un grupo (S–M); la selección múltiple, después | M–L | R5 |
| DS-17 | M | En Claves solo se puede copiar la pública e instalarla: ni borrar, renombrar, cambiar la frase de paso, exportar o mostrarla en Finder | `keys/keys_page.dart:300-318` | Un menú por fila; al borrar, quién la usa | M | R5 |
| DS-18 | M | La Biblioteca de la barra son seis iconos sin texto, y dos se repiten en otro sentido: el del terminal es también Snippets, y el de «poscuántico» es también Known hosts | `hosts/sidebar.dart:846,1217`, `tabs/session_view.dart:1053` | Icono y nombre en la barra abierta; iconos propios | S–M | R5 |
| DS-19 | B | La × solo sale en la pestaña activa; no hay «Limpiar el búfer»; el menú del terminal se queda en copiar y pegar; ir a la pestaña N solo existe en macOS | `tabs/tab_strip.dart:785`, `terminal/terminal_pane.dart:350-375`, `window/shortcuts.dart:69-72` | × al pasar el ratón, «Limpiar», Ctrl+Alt+1…9, más entradas | S–M | R5 |
| DS-20 | B | Objetivos de clic por debajo de 32 px: el chip de túneles (22), «Recibe» (24, y su texto no se puede pulsar), la estrella (26), los botones compactos (28); la prueba exige 24 | `tunnels/tunnels_page.dart:568`, `tabs/session_view.dart:500`, `hosts/sidebar.dart:541`, `ui/themes.dart:976` | 28 px en línea y 32 sueltos; la prueba, a 28 | S | R5 |
| DS-21 | B | Un filtro sin resultados enseña una tabla vacía en Snippets, Túneles e Identidades | `snippets/snippets_page.dart:151`, `tunnels/tunnels_page.dart:241`, `identities/identities_page.dart:132` | `OwEmptyState.noMatch` con «Quitar el filtro» | S | R5 |
| DS-22 | B | Literales y formatos sueltos: una pista en español también en inglés, la ruta del agente de macOS en Windows y Linux, «Local» a mano, «50 %» y la hora montados a mano, comillas mezcladas en el ARB inglés; los entornos de serie se guardan en el idioma del día en que se crearon | `snippets/snippet_editor.dart:176`, `hosts/editors.dart:1061`, `tabs/tabs.dart:170`, `sftp/queue_view.dart:426`, `tabs/connection_motion.dart:767`, `ui/environment.dart:68` | Al ARB o por plataforma; `DateFormat`; id para los de serie | S | R5 |
