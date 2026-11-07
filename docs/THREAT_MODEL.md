# Modelo de amenazas

- **Estado:** propuesta (D0 de la [v0.4](plan/v0.4.md)), sin auditoría externa. Describe la 0.3.4 tal como es y lo que la v0.4 cambia. Se revisa contra lo hecho en D8, y C1 (etapa 4 del [camino a la Community](plan/community.md)) le añade el servidor y las cuentas.
- **Fecha:** 2026-11-07.
- **Alcance:** el cliente de escritorio en macOS, Windows y Linux. La sync (v0.5), el servidor y las cuentas (v0.6), el móvil y la IA tienen su sitio en el [§8](#8-lo-que-llega-después), con lo que ya se sabe que traerán.
- **Base:** [ARCHITECTURE §11](ARCHITECTURE.md#11-seguridad-y-cadena-de-suministro), [ADR-003](adr/ADR-003-ssh-russh-y-firmantes.md) (SSH), [ADR-004](adr/ADR-004-vault-y-jerarquia-de-claves.md) (vault y claves) y [ADR-005](adr/ADR-005-sync-por-registros-de-dispositivo.md) (sync).

## 1. Qué se protege

| Activo | Por qué importa |
|---|---|
| Claves privadas SSH y las llaves de seguridad | Con ellas se entra en los servidores. Las de una llave FIDO2 no salen de la llave, pero su archivo dice qué llave usar |
| Contraseñas, frases de paso, PIN y códigos 2FA | Lo mismo, para lo que no va con clave |
| La lista de hosts | Direcciones, usuarios, puertos, saltos, túneles y notas: el mapa de la infraestructura de alguien, útil para atacarla aunque no traiga secretos |
| Las claves de host de confianza | Si alguien añade la suya, puede hacerse pasar por un servidor (integridad, no confidencialidad) |
| El historial de órdenes y los registros de sesión | Lo que se escribió y lo que se vio. A veces, un secreto escrito en una orden o que un programa enseñó |
| Snippets y variables | Órdenes que se ejecutan en los servidores, y a veces llevan un secreto |
| Las sesiones abiertas | Quien llegue a una escribe en un servidor con tus permisos |
| Desde la v0.4: la contraseña maestra, la KEK, la clave de cuenta, la clave del vault y el kit | Abren todo lo anterior |
| La propia app | Una app troyanizada tiene todo lo anterior |

## 2. Fronteras de confianza

**De confianza:**
- el núcleo y la app legítimos, construidos desde una etiqueta;
- el sistema operativo mientras maneja texto en claro, y su cifrado de disco;
- la sesión del usuario en el equipo;
- el hardware que guarda claves: la llave FIDO2 y, desde la v0.4, el Secure Enclave.

**Sin confianza:**
- **cada servidor**, aunque sea tuyo: puede estar comprometido, y todo lo que manda (la salida del terminal, los nombres del SFTP, las preguntas al entrar) es una entrada hostil;
- los saltos intermedios, la red y los proxies;
- los archivos que se importan, lo que se pega y los enlaces;
- los programas que la app busca en el `PATH` o ejecuta por ti (`mosh-client`, el ProxyCommand, tu shell de inicio, `xdg-open`, `secret-tool` al importar de Termius): son los tuyos, pero los encuentra el sistema;
- desde la v0.5, el almacenamiento de la sync; desde la v0.6, el servidor de OpenWard.

## 3. Atacantes y escenarios

| Amenaza | Defensa hoy (0.3.4) | Con la v0.4 | Lo que queda |
|---|---|---|---|
| **Robo del equipo apagado o con la sesión bloqueada** | Solo el cifrado de disco del sistema (FileVault, BitLocker, LUKS), si está activo. Sin él, se lee todo lo del [§4](#4-lo-que-hay-en-el-disco) | El vault, cifrado con la contraseña maestra | Si la sesión del sistema y la app están abiertas, nada. Con «Más tarde» (sin contraseña todavía), quien abra tu sesión del sistema abre el vault ([§5](#5-garantías-de-la-v04-con-sus-condiciones)) |
| **Una copia del disco o de su copia de seguridad** (Time Machine, una nube que copia la carpeta de la app) | Ninguna: el vault, el historial y los recientes van en claro | Los ítems, cifrados. Se ve cuántos hay, su tamaño y sus fechas | Las copias hechas con la 0.3 siguen en claro (la app no llega a ellas). Una contraseña débil se adivina sin conexión: Argon2id lo encarece, no lo impide |
| **Alguien en tu silla con la app abierta** | Ninguna | Bloqueo a los 15 min, al suspender el equipo y con ⌘L | Las sesiones siguen vivas aunque no se vean. Hasta que se bloquea, todo está a su alcance |
| **Otro usuario del mismo equipo** | `vault.db` y los registros, 0600. Pero la carpeta de datos queda en 0755, y el historial, los recientes y los ajustes en 0644 ([AM-3](#9-hallazgos-de-d0)) | Lo mismo, y además cifrado | Un túnel en 127.0.0.1 lo puede usar cualquier usuario del equipo, también el dinámico, que no pide contraseña (igual que `ssh -D`). Un administrador (root) lo lee todo |
| **Malware con tus permisos** | Fuera de alcance: lee archivos, memoria y teclado | Con la app bloqueada solo ve sobres cifrados, pero puede esperar a que desbloquees | Fuera de alcance ([§7](#7-fuera-de-alcance)) |
| **La red** (escucha o se interpone) | Comprobación de la clave del host: «Preguntar» por defecto. Una clave cambiada o revocada se rechaza, y una de otro tipo pregunta incluso con «Aceptar nuevas». Un certificado de host inválido no vale: se mira la clave sola, con la misma política, como hace OpenSSH. Kex poscuántico (`mlkem768x25519-sha256`) y `strict-kex` contra Terrapin. Telnet se marca «Sin cifrar» | — | La primera conexión sin huella verificada (o con «Aceptar nuevas») se puede suplantar. Telnet va en claro. OpenSSH 9.0–9.8 se queda sin kex poscuántico. La contraseña de un proxy HTTP o SOCKS5 viaja en claro hasta el proxy |
| **Un servidor hostil o comprometido** | El motor ignora el portapapeles (OSC 52), las notificaciones y OSC 7, y el título solo se usa en terminales locales. Los enlaces se abren con ⌘/Ctrl+clic, solo `http`, `https`, `mailto` y `ftp`, con aviso si el texto nombra otro host. Los nombres del SFTP se filtran (`/`, NUL, `.`, `..`; en Windows también `\` y `:`), y la lista enseña sus caracteres invisibles. «Abrir» deja la copia sin bit de ejecución y con la marca de origen del sistema, y pregunta antes con los tipos que el sistema ejecuta en vez de abrir. El reenvío del agente va apagado por defecto y solo al último salto. Los reenvíos remotos se aceptan solo en los puertos pedidos, y X11 no existe. Las preguntas al entrar, como mucho 3 intentos de 10 rondas. La respuesta de `mosh-server` se valida, y leer `os-release` es opcional y con límites | La contraseña maestra nunca se pide dentro de una sesión ([I-8](#6-invariantes-que-se-comprueban)) | Un documento puede atacar al programa que lo abre (un PDF a su lector): la marca de origen hace que Office lo abra en vista protegida, pero no protege a todos. Con el agente reenviado, el servidor firma con tus claves mientras dure la conexión. El servidor decide lo que ves, incluidas preguntas que imitan a la app. Todo lo que manda pasa por libghostty-vt ([§10](#10-riesgos-abiertos)) |
| **Un salto intermedio comprometido** | Cada salto comprueba su clave por separado. El tráfico al siguiente va cifrado de punta a punta (`direct-tcpip`), y el agente solo llega al último | — | Ve a quién te conectas y cuándo, y puede cortar |
| **Un archivo importado hostil** | 64 MiB por archivo, 16 niveles y 20.000 entradas como mucho. `proptest` en cada importador y decodificador. Las contraseñas nunca se importan, y las claves de otros programas solo si se eligen. Un ProxyCommand de otro programa no se importa: se descarta con un aviso que lo enseña | — | El reenvío del agente, las variables de entorno y los túneles abiertos a la red de otro programa sí llegan ([AM-8](#9-hallazgos-de-d0)). `~/.ssh/config` es tuyo: su ProxyCommand y sus reenvíos llegan tal cual, como los usaría `ssh` |
| **Pegar algo peligroso** | El motor no deja pasar un salto de línea fuera del pegado entre corchetes, ni su marca de fin. Avisa de los caracteres invisibles (controles, bidi, ancho cero). Pegar en varios paneles a la vez siempre pregunta | — | El pegado entre corchetes depende de la shell remota. Una orden que parece otra (homoglifos) no se detecta |
| **La cadena de suministro** | Versiones fijadas. `cargo-deny` (licencias y avisos de seguridad) y dependabot (Cargo, pub y Actions). Las acciones de la CI van fijadas por SHA. libghostty-vt se construye desde un commit fijado. El `.dmg` solo sale de una etiqueta con el árbol limpio, el cask fija su sha256 y un paquete publicado no se sustituye | — | [§10](#10-riesgos-abiertos): sin firma de desarrollador ni notarización, sin SBOM ni builds reproducibles |
| **Los programas que lanza la app** | En el ProxyCommand, `%h`, `%r` y `%n` no aceptan metacaracteres de la shell. `mosh-client` recibe la clave en `MOSH_KEY`, no en la línea de órdenes. «Abrir» pasa la ruta como archivo, sin shell: `open` en macOS, `ShellExecute` en Windows y `xdg-open` en Linux. El terminal local es tu shell | — | Un programa que aparece antes en el `PATH` puede hacerse pasar por `mosh-client`, como en tu shell. «Abrir con…» ejecuta el programa que escribas |

## 4. Lo que hay en el disco

En la carpeta de datos de la app (en macOS, `~/Library/Application Support/dev.openward.OpenWard`; en Linux, `$XDG_DATA_HOME/dev.openward.OpenWard`), salvo donde se dice otra cosa.

| Archivo | Qué guarda | Permisos | Hoy | Con la v0.4 |
|---|---|---|---|---|
| `vault.db` (con `-wal`, `-shm` y `.lock`) | Hosts y grupos (etiquetas, direcciones, usuarios, notas, el texto con el que se detectó el sistema), identidades sin secretos, claves de host de confianza, snippets, túneles y espacios de trabajo | 0600 | En claro (sobres `v: 0`) | Cifrado por ítem (D3) |
| `history.json` | Cada orden, dónde y cuándo se ejecutó (hasta 2000) | 0644 ([AM-3](#9-hallazgos-de-d0)) | En claro | Cifrado (D6) |
| `recent.json` | Las conexiones: a dónde, etiqueta y cuándo | 0644 ([AM-3](#9-hallazgos-de-d0)) | En claro | **No previsto** ([D0-2](#11-decisiones-que-salen-de-d0)) |
| `logs/` (`.json`, `.cast.gz`, `.txt.gz`) | Cada sesión (quién, a dónde, cuándo) y, si se graba, lo que se vio | 0700 y 0600 | En claro | **No previsto** ([D0-2](#11-decisiones-que-salen-de-d0)) |
| `settings.json` | Aspecto, reglas de resaltado y el programa de «Abrir con…»; no nombra hosts | 0644 | En claro | Igual |
| `~/.ssh/<clave>` | Las claves que genera o importa la app; las de una llave FIDO2 solo dicen qué llave usar | 0600 (`.pub` 0644) | Cifradas si tienen frase de paso | Dentro del vault, si se quiere (D6) |
| `~/.ssh/known_hosts` | Se lee al conectar. Solo se escribe al olvidar una línea, con una copia en `known_hosts.old` | Los que tenía | — | Igual |
| `<temporal>/openward-open-*` | Copias de archivos remotos abiertos aquí («Abrir», «Abrir con…») | 0700; la copia, sin bit de ejecución y con la marca de origen | En claro. Se borran al cerrar la pestaña, y las que queden, al arrancar otra vez ([AM-6](#9-hallazgos-de-d0)) | Igual |
| `<destino>.ow-*.part` | Transferencias a medias, que se quedan para reanudar | 0600 y los bits del servidor | En claro | Igual |
| Llavero del sistema | Nada de OpenWard. Solo se lee la clave de Termius al importar | — | — | La clave del desbloqueo (Touch ID, Windows Hello, llavero de Linux) |

Las contraseñas, las frases de paso y el PIN se piden en cada conexión y no se guardan en ningún sitio. Al núcleo llegan en `Zeroizing`, aunque después quedan copias sin borrar ([AM-4](#9-hallazgos-de-d0)). En Dart solo se vacía el campo, porque una cadena de Dart no se puede borrar de la memoria.

## 5. Garantías de la v0.4, con sus condiciones

- **Con la app cerrada o bloqueada, una copia del disco no dice qué hosts tienes, ni dónde están, ni qué guardaste.**
  - Condiciones: una contraseña que no se adivine (Argon2id, 64 MiB como mínimo y de 0,5 a 1 s por intento); y que nada fuera del vault nombre un host ([I-5](#6-invariantes-que-se-comprueban), [D0-2](#11-decisiones-que-salen-de-d0)).
  - Mientras se elige «Más tarde» al actualizar (durante la beta), el vault se cifra con una clave del llavero del sistema y sin contraseña: la copia del disco sola no basta, pero quien abra tu sesión del sistema abre el vault, y sin kit no hay recuperación. Un aviso fijo lo recuerda.
  - Se ve: cuántos ítems hay, su tamaño aproximado, sus identificadores, revisiones y generación de clave, y las fechas de los archivos.
- **Nadie cambia un ítem sin que se note:** el AAD (`vault_id‖item_id‖rev‖key_gen`) liga cada sobre a su sitio, así que modificarlo o moverlo a otro ítem o a otro vault hace fallar el descifrado.
  - No se detecta volver a una copia anterior y entera del vault: sus sobres siguen siendo válidos. Tampoco que falte un ítem. La sync de la v0.5 lo detecta entre equipos, con registros firmados y cursores.
- **Bloqueada, el núcleo no tiene nada del vault en claro.** Las sesiones abiertas siguen vivas, con sus claves de sesión en memoria, pero no se ven ni se escribe en ellas.
- **Sin la contraseña, con el kit:** el kit (256 bits) lo abre en cualquier equipo. Quien tenga el kit tiene el vault: se guarda como la contraseña, no junto al equipo.
- **El desbloqueo rápido es tan fuerte como su sistema:**
  - Touch ID y Windows Hello piden tu huella o tu cara. Si en macOS el llavero con biometría exige un Developer ID, el plan pasa a «recordar en este Mac» con el llavero normal, sin biometría, hasta firmar la app;
  - el llavero de Linux se abre con tu sesión, sin biometría. Cualquiera que llegue a tu sesión abierta abre también el vault ([D0-3](#11-decisiones-que-salen-de-d0)).
- **Un secreto copiado se borra del portapapeles a los 60 s.** Además, se marca para que no lo guarden el historial del portapapeles ni su sincronización: el tipo «oculto» en macOS, y en Windows, fuera del historial y de la nube.

## 6. Invariantes que se comprueban

Cada una es una prueba que se escribe en su hito.

| # | Invariante | Hito |
|---|---|---|
| I-1 | Ningún secreto guardado cruza a Dart: el núcleo lo usa y la app solo ve que existe | D3, D6 |
| I-2 | Bloqueado, el vault no tiene ítems en claro: el índice se vacía y las claves se borran (`zeroize`) | D3, D4 |
| I-3 | Cambiar `vault_id`, `item_id`, `rev` o `key_gen` en un sobre hace fallar el descifrado (vectores propios) | D1, D3 |
| I-4 | La migración no deja la 0.3 en claro: ni la copia que hace la migración (`VACUUM INTO`), ni páginas libres de SQLite, ni el WAL. Se comprueba buscando en los archivos el nombre de un host de prueba. La copia, mientras exista, va con 0600 | D3 |
| I-5 | Nada fuera del vault nombra un host. Se comprueba buscando en la carpeta de datos, después de una sesión, el nombre de un host de prueba | D3, D6 |
| I-6 | Una 0.3 no abre un vault de la 0.4 y lo dice, en vez de mostrarlo vacío | D3 |
| I-7 | El vault se recupera con el kit en una carpeta de datos nueva | D5 |
| I-8 | La contraseña maestra solo se pide en la pantalla de bloqueo y en Ajustes › Seguridad, nunca dentro de una sesión (una pregunta del servidor podría imitarla) | D4 |
| I-9 | Un secreto copiado desaparece del portapapeles a los 60 s y lleva la marca que lo deja fuera del historial | D4 |

## 7. Fuera de alcance

- Malware, u otro programa con tus permisos, mientras el vault está desbloqueado: puede leer la memoria, el teclado y la pantalla. Y un administrador del equipo, siempre.
- Lo que el servidor te enseña una vez dentro, más allá de las defensas del [§3](#3-atacantes-y-escenarios): controla la salida.
- Ataques físicos con el equipo encendido (memoria en frío, DMA) y canales laterales. Lo que el sistema lleve a la memoria de intercambio o a la hibernación lo protege el cifrado de disco.
- Que un servidor te deje sin servicio, o te llene el disco con una descarga enorme.
- Las copias antiguas que hizo la 0.3 en claro: la app no las alcanza, y al migrar lo dirá.

## 8. Lo que llega después

- **La sync (v0.5), con tu almacenamiento:**
  - el almacenamiento no lee ni falsifica nada, porque los segmentos van cifrados y firmados;
  - pero ve cuántos equipos hay, cuándo escribe cada uno y cuánto;
  - y puede borrar, quedarse atrás o devolver versiones viejas. Los cursores y las firmas lo detectan, y la app lo dice.
- **Un equipo comprometido con la clave de cuenta** escribe ítems válidos. Los que ejecutan algo (ProxyCommand, el snippet al conectar, la ruta de `mosh-server`, las variables de entorno) deben llegar desactivados o pedir confirmación la primera vez, con su texto a la vista.
- **Revocar un equipo** rota la generación de clave. Lo que ya vio queda visto ([ADR-004](adr/ADR-004-vault-y-jerarquia-de-claves.md)).
- **El servidor y las cuentas (v0.6):**
  - la identidad de KaiCorp Labs autentica, pero no descifra. Quien la comprometa consigue sobres cifrados y puede negar el servicio;
  - el paquete de la clave de cuenta que se sube es el punto delicado ([D0-1](#11-decisiones-que-salen-de-d0));
  - C1 amplía este documento con el servidor.
- **Vaults de equipo:** la clave pública de un miembro nuevo se puede sustituir. Se defiende con la huella o con una atestación del servidor ([ADR-004](adr/ADR-004-vault-y-jerarquia-de-claves.md)).
- **Móvil, y la IA con MCP** ([ADR-008](adr/ADR-008-ia-mcp-y-byok.md)): un agente con acceso a las sesiones es otro atacante posible, y tendrá su apartado cuando exista.

## 9. Hallazgos de D0

Salieron al repasar el código para escribir este documento.

| # | Gravedad | Qué pasa | Dónde | Arreglo | Cuándo |
|---|---|---|---|---|---|
| AM-1 | Alta | **En Windows, «Abrir» un archivo del SFTP pasa su ruta a `cmd /c start`.** El nombre lo elige el servidor, y Dart solo pone comillas si hay espacios. Un archivo llamado `informe&calc` ejecuta `calc` al abrirlo. Afecta al paquete de Windows de la 0.3.4-beta.1, en un borrador sin publicar, y a los de la CI desde P6, que se guardan 14 días como artefactos y puede bajar cualquiera con cuenta de GitHub | `app/lib/sftp/remote_edit.dart:209-214`, `core/crates/openward-sftp/src/lib.rs:96-98` | `ShellExecute` con la ruta como archivo, sin `cmd`: `url_launcher` con la ruta tal cual, sin una URL que codificar y decodificar por el camino. Si ningún programa abre ese tipo, el diálogo «Abrir con» de Windows | **Arreglado** (2026-11-07). La beta no se publica con el paquete de la 0.3.4-beta.1 |
| AM-2 | Media | **«Abrir» lanza lo que el sistema ejecuta en vez de abrir** (`.exe`, `.bat`, `.cmd`, `.ps1`, `.lnk`, `.command`, `.desktop`, `.jar`…). El nombre y el bit de ejecución los pone el servidor, y la copia no lleva la marca de cuarentena de macOS ni la de Windows. En la lista del SFTP, un nombre con caracteres bidi o de ancho cero puede disfrazar la extensión (`factura`, U+202E y `fdp.exe` se ve como `facturaexe.pdf`) | `app/lib/sftp/remote_edit.dart:205-218`, `core/crates/openward-sftp/src/transfer.rs:1187-1200` | Preguntar antes con esos tipos, cada sistema los suyos (en Windows, sin los puntos y espacios del final, que quita al guardar); quitar el bit de ejecución a la copia; `com.apple.quarantine` en macOS y la marca de origen (`Zone.Identifier`, zona 3) en Windows; y enseñar los caracteres invisibles de los nombres, como al pegar, también saltos de línea y tabuladores | **Arreglado** (2026-11-07) |
| AM-3 | Media | **La carpeta de datos queda en 0755**, porque la crea antes `path_provider` y el núcleo solo pone 0700 a una carpeta nueva. `history.json`, `recent.json` y `settings.json` se escriben con 0644. En Linux, otro usuario del equipo puede leer el historial si su carpeta personal lo deja | `core/crates/openward-app/src/lib.rs:1234-1249`, `app/lib/core/json_file.dart:28-33` | 0700 a la carpeta de datos en cada arranque (Unix) | La siguiente beta |
| AM-4 | Baja | **Secretos sin `Zeroizing`:** la frase de paso al generar una clave, el PIN al crearla en una llave, el texto de una clave importada y la clave de Termius al importar. Y copias de los que sí llegan en `Zeroizing`: las respuestas a las preguntas del servidor, y la contraseña, que `russh` recibe como cadena | `core/crates/openward-ffi/src/api/keychain.rs:141-195`, `core/crates/openward-import/src/termius/mod.rs:89-103`, `core/crates/openward-app/src/connect.rs:745,786-788` | `Zeroizing` en los tipos; lo de `russh`, donde su API lo permita | D6 |
| AM-5 | Baja | **Un túnel dinámico abierto a «Toda la red local» es un proxy SOCKS5 sin contraseña** hacia la red del servidor. El aviso de siempre («Cualquiera de tu red podrá usarlo») no dice que, en un dinámico, eso es entrar en toda la red del servidor | `core/crates/openward-app/src/tunnels.rs:156-179`, `core/crates/openward-ssh/src/forward.rs:110-200`, `app/lib/tunnels/tunnel_editor.dart:354-360` | Un aviso propio para el túnel dinámico | La siguiente beta |
| AM-6 | Baja | **Las copias de «Abrir» se quedan** si la app se cierra mal, o en Windows si otro programa las tiene abiertas | `app/lib/sftp/remote_edit.dart:190-200` | Cada carpeta lleva un cerrojo mientras está en uso. Al arrancar se borran las que lo tienen libre, porque su ejecución terminó, y las de antes del cerrojo, pasado un día. Las de otro OpenWard abierto se quedan | **Arreglado** (2026-11-07) |
| AM-7 | Baja | **El historial guarda los secretos escritos dentro de una orden** (`mysql -pclave`, `export TOKEN=…`), y la grabación de una sesión, lo que se vio. Ya se saltan lo que no se ve en pantalla, las respuestas a preguntas de contraseña, la pantalla alternativa, las órdenes de más de 4000 caracteres y las que empiezan por un espacio. Pero si la orden se edita con Tab o con las flechas, se lee de la pantalla sin el espacio y se guarda | `app/lib/history/line_tracker.dart:126-191` | Recordar el espacio del principio aunque la línea se edite, y cifrar el historial | D6 |
| AM-8 | Media | **Lo que se importa de otros programas puede encender el reenvío del agente**, además de traer variables de entorno y túneles abiertos a la red. Un archivo hostil (de Termius, PuTTY, SecureCRT, MobaXterm o Tabby) apunta un host a un servidor del atacante con el agente reenviado, y al conectarse este firma con tus claves | `core/crates/openward-import/src/termius/model.rs:303-319,441-443`, `putty.rs:303`, `securecrt.rs:360`, `mobaxterm.rs:236`, `tabby.rs:250` | Que el reenvío del agente y los túneles fuera de 127.0.0.1 lleguen apagados, con un aviso de lo que pedía el archivo, como el ProxyCommand | La siguiente beta |
| AM-9 | Baja | **La app promete lo que hoy no es verdad:** la nota de los registros dice que están en una carpeta que solo lee tu usuario (en Linux no, por AM-3) y que irán cifrados con el vault (el plan no lo prevé, [D0-2](#11-decisiones-que-salen-de-d0)) | `app/lib/l10n/app_es.arb:2304` (`logsUnencrypted`) | Se arregla con AM-3 y D0-2 | Con ellos |

## 10. Riesgos abiertos

Lo que impide hacer afirmaciones fuertes hasta que se resuelva:
- **Sin auditoría externa.** Está prevista una del núcleo criptográfico y de la sync antes de lanzar OpenWard Cloud.
- **Los paquetes no se pueden verificar:**
  - en macOS, el `.dmg` va firmado ad hoc y sin notarizar;
  - en Windows y Linux, sin firmar;
  - no hay SBOM, ni builds reproducibles, ni firmas de los artefactos;
  - quien controle la cuenta de KaiCorpLabs en GitHub puede publicar un cask o un paquete malicioso.

  La firma y la notarización van con el lanzamiento.
- **libghostty-vt** (Zig y C) lee todo lo que manda el servidor: es la superficie de análisis más grande. Se construye desde un commit fijado, y el fuzzing de VT está pendiente.
- **Dependencias SSH:** `russh` tiene un mantenedor principal; `ssh-key` 0.7 sigue en RC; y `rsa` tiene el aviso RUSTSEC-2023-0071 (Marvin), aceptado en [ADR-003](adr/ADR-003-ssh-russh-y-firmantes.md).
- **X-Wing sigue siendo un borrador del IETF;** D1 decide entre las implementaciones o DHKEM(X25519) con `kem_id` versionado.
- **Dart no puede borrar una cadena de la memoria:** lo que se escribe en un campo de la app vive ahí hasta que lo recoge el recolector.
- **Las dependencias de Dart** solo las vigila dependabot: no hay un análisis de avisos de seguridad como el de `cargo-deny` para Rust.

## 11. Decisiones que salen de D0

Para decidir antes de D3:
- **D0-1 · El paquete de la clave de cuenta que sube la v0.6.**
  - El plan lo envuelve con la KEK, que sale solo de la contraseña. Quien tenga el paquete (el servidor, o quien robe su base de datos) puede probar contraseñas sin límite.
  - Propuesta: envolverlo con una clave que salga de la contraseña **y** de un secreto de alta entropía del kit. Así, el paquete solo no basta.
  - Consecuencia: dar de alta un equipo nuevo pide el kit o la aprobación de otro equipo, que es justo lo que S4 de la etapa 3 ya plantea («con un código o un QR desde otro que ya está dentro, o con el kit»).
- **D0-2 · Lo que nombra hosts fuera del vault.**
  - `recent.json` (encendido por defecto) y los registros de sesión guardan a dónde te conectaste. La v0.4 solo cifra el historial, aunque la app ya dice en Ajustes › Registros que los registros irán cifrados con el vault ([AM-9](#9-hallazgos-de-d0)).
  - Propuesta: los tres en almacenes cifrados con una clave del vault, en D6. Sin eso, la primera garantía del [§5](#5-garantías-de-la-v04-con-sus-condiciones) no es verdad. Añade unos días.
- **D0-3 · El llavero de Linux.**
  - Desbloquear con libsecret no pide nada más que la sesión abierta.
  - Propuesta: apagado por defecto en Linux, con esa explicación al encenderlo.
