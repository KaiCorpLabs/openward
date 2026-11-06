# Prueba de la v0.3

La [v0.3](v0.3.md) cierra la fase 1. Su puerta de salida es esta:
- el equipo crea y sube sus claves desde OpenWard;
- trabaja una semana con la paleta y el historial;
- abre su día con un espacio de trabajo;
- importa un CSV propio.

Lo que trae está en las [notas de la versión](../notas/v0.3.md).

## Instalar

En macOS, como la 0.2 ([cómo](prueba-v0.2.md#instalar)): con Homebrew, o el `.dmg` de la release. La beta nueva llega con:

```bash
brew upgrade --cask openward
```

**Linux:** desde la 0.3.2-beta.7 la release trae un `.tar.gz` para x86_64 y otro para arm64; se descomprime y se abre `OpenWard/openward`. Necesita GTK 3. También se construye con `make package-linux` (en un contenedor, con podman o docker). **Windows:** desde la 0.3.4, cada etiqueta de versión deja en la CI un `.zip` (el artefacto `OpenWard-Windows` de esa ejecución), que acaba en la release. Mientras no haya, se compila en Windows con `fvm flutter build windows`. La compilación copia junto a la app el runtime de Visual C++; probarlo en un Windows recién instalado es el punto 24.

## Dónde guarda sus datos

En la misma carpeta que la 0.2 ([cuál](prueba-v0.2.md#dónde-guarda-sus-datos)), con algo más:
- `history.json`: el historial de comandos. Es de este equipo: no va al vault ni se sincroniza. Ajustes › Registros lo apaga o lo borra (antes de la 0.3.3, Ajustes › Terminal).
- `recent.json` (desde la 0.3.0-beta.3): las conexiones recientes y cuánto usas cada acción de la paleta. También es de este equipo; Ajustes › Registros lo apaga o lo borra (antes de la 0.3.3, Ajustes › General).
- `logs/` (desde la 0.3.3-beta.1): los registros de sesión. Por cada sesión, `<id>.json` con su entrada; si se grabó, también `<id>.cast.gz` (asciicast v2) y `<id>.txt.gz` (el texto para buscar). Y `config.json`, con los días y el espacio que se guardan. Es de este equipo y aún va **sin cifrar**: lo cifrará la v0.4. Ajustes › Registros abre la carpeta y lo borra todo.

Además, OpenWard escribe en `~/.ssh` cuando creas o importas una clave (siempre archivos nuevos), y en el `~/.ssh/authorized_keys` de un servidor cuando subes una.

## Qué probar

1. **Claves** (Biblioteca › Claves):
   - comprueba que están tus claves de `~/.ssh` con su huella (compárala con `ssh-keygen -lf`) y quién las usa;
   - crea una Ed25519 con frase de paso y otra sin ella;
   - importa una clave pegándola y otra eligiendo el archivo;
   - súbela a un servidor de prueba con «Subir a un servidor…», a un host guardado y a una dirección escrita a mano;
   - súbela otra vez y comprueba que dice que ya estaba y que `authorized_keys` no tiene la línea dos veces;
   - ponla en un host y conéctate solo con ella.
2. **Paleta** (⌘K, o ⌘P y ⌘⇧P):
   - haz con ella lo que sueles hacer con el ratón: dividir, abrir SFTP, ir a una página, abrir un host;
   - prueba a escribir solo unas letras («sftp», «dder», el nombre de un host).
3. **Historial:**
   - trabaja como siempre y, al rato, busca en la paleta un comando de antes y repítelo, con Intro y con ⌥Intro;
   - haz `sudo` y comprueba que la contraseña no aparece en la paleta;
   - empieza un comando con un espacio y comprueba que no se guarda;
   - dinos qué comandos echas en falta (con Tab, con las flechas, en prompts de varias filas) y cuáles sobran.
4. **Espacios de trabajo:**
   - abre tus pestañas de cada día, divide los paneles como los quieras y guárdalas («Guardar las pestañas abiertas…»);
   - cierra todo y ábrelo otra vez desde la biblioteca y desde la paleta;
   - cambia la distribución y usa «Cambiar por las pestañas abiertas»;
   - borra un host que esté en un espacio de trabajo y ábrelo: ese panel debe preguntar qué abrir.
5. **Conexión:**
   - con un terminal abierto, reinicia el servidor (o quítale la red) y comprueba que en unos segundos dice «no responde», luego que se perdió, y que vuelve solo cuando el servidor arranca;
   - pon «Sesión persistente» en un host que tenga tmux, deja algo corriendo (`top`, un `tail -f`), corta la red y comprueba que al volver sigue ahí; cierra la pestaña y comprueba con `tmux ls` en el servidor que ya no está;
   - en un servidor sin tmux, comprueba que la barra de estado dice «sin tmux».
6. **Foco** (0.3.0-beta.3):
   - pliega la barra con ⌘B a raíl y trabaja así un día; prueba también «Oculta» y que se asome al dejar el ratón en el borde izquierdo;
   - en Ajustes › General › Ventana, prueba «Con un terminal delante: En raíl» y comprueba que en el inicio y en las páginas vuelve a abrirse;
   - cambia el ancho arrastrando el borde y el margen del terminal, y dinos qué valores te quedan bien;
   - abre varias pestañas y salta entre ellas con ⌘K escribiendo su nombre; usa `>` para las acciones;
   - mira la latencia de la barra de estado en una red buena y en una mala (el móvil, una VPN): dinos si el ámbar salta cuando debe o asusta sin motivo.
7. **Editor e inicio** (0.3.0-beta.4):
   - edita un host de un grupo: cambia un valor heredado escribiendo encima, vuelve a heredarlo con ↺ y comprueba que el editor dice bien de dónde viene cada uno; dinos si echas en falta algo fuera de «Avanzado»;
   - cierra todas las pestañas y conéctate desde el inicio: escribe parte del nombre de un host, una dirección a la que ya fuiste y una nueva (⌥Intro la abre tal cual; «Guardar como host…» la guarda);
   - con el texto al 150 % (Ajustes › Apariencia) y en tu tema, mira que «Conectar» se lee en una sola línea (0.3.1-beta.9);
   - después de unos días, mira si los recientes del inicio (cuándo, cuánto duró, tmux) te sirven para volver;
   - con la ventana a tu tamaño de siempre, en grande y pequeña, mira que el inicio aprovecha el espacio: favoritos en fila, recientes en columnas y los atajos abajo (0.3.3-beta.2);
   - con un túnel abierto y sin pestañas, detenlo desde el inicio;
   - abre la hoja de atajos con ⌘/ (en un teclado español, ⌘⇧7) y busca alguno por su nombre y por su tecla;
   - con un host detrás de un bastion, pasa el ratón por la latencia y comprueba que dice la del bastion y la del destino.
8. **Entorno, sistema y favoritos** (0.3.1-beta.1):
   - marca tu grupo de producción como Producción y comprueba que sus pestañas y terminales lo dicen; dinos si la marca de la esquina del terminal molesta;
   - conéctate a tus servidores y mira qué sistema dice la barra; en los que no lo diga, acepta el aviso «Leer /etc/os-release» (0.3.1-beta.7) y dinos si acierta;
   - marca tus hosts de cada día como favoritos y ordénalos en el inicio arrastrando sus tarjetas.
9. **Paneles** (0.3.1-beta.2):
   - arrastra una pestaña sobre un terminal y suéltala en una mitad: la ventana ya no debe moverse;
   - con un solo terminal, arrastra su pestaña a una de sus mitades: queda ahí y la otra mitad pregunta qué abrir (0.3.1-beta.3);
   - con dos paneles, prueba el menú «…» de uno: moverlo a una pestaña nueva, intercambiarlo, abrir otra cosa e igualar tamaños; y arrastra su cabecera al hueco vacío de la barra;
   - divide un terminal y elige en el panel nuevo una pestaña ya abierta; prueba también «Dividir con …» en la paleta;
   - agarra el borde entre paneles y dinos si se encuentra a la primera.
10. **Barra lateral y Hosts** (0.3.1-beta.4):
   - trabaja un día con la barra abierta: ¿encuentras lo que usas sin abrir Hosts? Dinos si echas en falta algo de la barra de antes;
   - abre Hosts (⌘⇧H), busca, filtra por entorno y por etiqueta, prueba las tarjetas y conecta con doble clic, con Intro y con «Conectar»;
   - con varios terminales locales abiertos, mira «Local × N» en «Abiertas» y pasa por ellos con clics;
   - pliega la barra a raíl con 8 o más pestañas: los botones de arriba y de abajo deben seguir a la vista; abre la lista con el contador.
11. **Temas** (0.3.1-beta.5):
   - prueba unos días alguno de los temas nuevos (Monitor, Berenjena, Búnker, Marino, Catppuccin, Dracula o Tokyo Night) y dinos si se lee bien con tus programas de siempre (`htop`, `git diff`, `vim`…);
   - en Búnker, el terminal es de un solo color: ¿echas de menos el rojo de los errores?;
   - combina capas (por ejemplo, la ventana de Grafito con los colores del terminal de Marino) y prueba VT323 como letra del terminal.
12. **Logo** (0.3.1-beta.6):
   - mira el icono nuevo en el Dock, en el selector de apps (⌘Tab) y en Finder: ¿se reconoce en pequeño?;
   - en tu tema de siempre, mira el logo en el inicio, en Acerca de y en «Qué hay de nuevo», y dinos si se ve bien con su color.
13. **Sistema con logo** (0.3.1-beta.7):
   - mira los logos de tus hosts en la barra, el raíl, la página de Hosts y el inicio: ¿se reconocen en pequeño y con el color de cada entorno?;
   - conéctate por primera vez a un servidor que no diga su sistema (uno con Tailscale SSH, Fedora o macOS) y acepta el aviso: el logo debe cambiar sin reconectar;
   - en uno que no hayas conectado aún, prueba «Averiguar el sistema» en su menú; y activa «Leer /etc/os-release en todos los hosts» en Ajustes › General.
14. **Arrastrar en el SFTP** (0.3.1-beta.8):
   - haz clic y doble clic en archivos y carpetas, también con el trackpad: no debe aparecer la etiqueta del arrastre;
   - selecciona varios, haz clic en uno sin moverlo (queda solo ese) y arrastra varios al otro lado: dinos si el arrastre empieza cuando lo esperas.
15. **Seguridad y reconexión** (0.3.2-beta.1):
   - en un host con «Sesión persistente» y tmux, corta la red y pulsa «Reintentar ahora» cuando vuelva: debe seguir lo que tenías, y `tmux ls` en el servidor, enseñar una sola sesión `ow-`;
   - conéctate a hosts que ya estaban en tu `~/.ssh/known_hosts` desde hace tiempo: no deben preguntar como si fueran nuevos;
   - con ⌘ sobre un enlace del terminal, mira que abajo dice adónde lleva; con `printf '\e]8;;https://openward.dev\e\\banco.example.com\e]8;;\e\\\n'`, en ámbar;
   - descarga una carpeta grande por SFTP, páusala, cierra la pestaña y vuelve a bajarla: debe seguir donde iba;
   - abre la app instalada con otra ya abierta sobre los mismos datos (por ejemplo, con `open -n`): la segunda debe decir que no puede abrirlos.
16. **Rendimiento** (0.3.2-beta.2):
   - deja la app abierta con un terminal quieto y mira en el Monitor de Actividad que su CPU baja casi a 0 %; dinos si notas la batería;
   - con muchos hosts (importa un `~/.ssh/config` grande si tienes uno), busca en la barra, abre Hosts y la paleta: dinos si algo tarda;
   - haz `seq 1 200000` en un terminal y busca en él (⌘F) escribiendo deprisa: la ventana no debe pararse;
   - con un shell delante, arrastra el borde entre dos paneles: el prompt no debe repetirse.
17. **Conexiones y no perder trabajo** (0.3.2-beta.3):
   - conéctate a una dirección que no conteste (una IP de tu red sin nadie, o un puerto que acepte y calle): a los 15 s debe decir que no responde;
   - con un agente que pida aprobación (1Password, Secretive), recházala: debe pasar a la contraseña o a la siguiente clave;
   - si usas ProxyCommand con `cloudflared` o `aws ssm`, abre la app desde el Finder o el Dock y conéctate; rompe el comando a propósito y mira que el error dice por qué;
   - abre un túnel SOCKS, configura el navegador para usarlo y abre varias webs pesadas a la vez; luego cierra el túnel: debe cortar lo que estuviera cargando;
   - edita un host, cambia algo y pulsa Esc: debe preguntar; marca un host como producción, conéctate y pulsa ⌘W: debe preguntar; ⌘⇧T debe reabrir lo último cerrado;
   - con una transferencia en curso, ⌘Q o el botón rojo de la ventana: debe preguntar;
   - abre neovim o tmux y desplázate deprisa: no debe parpadear; mantén pulsada la j en vim: debe repetir.
18. **Errores y datos** (0.3.2-beta.4):
   - conéctate a un puerto cerrado, a un nombre que no existe y a una IP sin nadie: cada uno debe decir lo suyo en español, y «Detalles» la frase técnica;
   - conéctate a un host cuyo sistema OpenWard aún no conozca y abre su editor enseguida, antes de que salga el logo; cámbiale el nombre y guarda cuando el logo ya esté: no debe decir que cambió mientras tanto, el logo debe quedarse y la pestaña debe llevar el nombre nuevo;
   - borra un host por el que salten otros: el aviso debe decir por qué no se puede;
   - importa desde PuTTY, MobaXterm o SecureCRT algo con X11 o un proxy SOCKS4: el informe debe decirlo en español;
   - si conservas una beta anterior a esta, abre tus datos con ella después de usar esta: debe abrirlos igual.
19. **Accesibilidad y detalles** (0.3.2-beta.5):
   - recorre la app solo con Tab, Intro y Esc: el anillo debe decir siempre dónde estás, y no salir al hacer clic;
   - con VoiceOver (⌘F5), recorre la barra, el raíl y las pestañas y púlsalos; en un terminal, escribe y deja que lea la línea;
   - pon el texto al 150 % (Ajustes › Apariencia) y estrecha la ventana al mínimo: nada debe quedar cortado sin aviso;
   - en Claves, renombra una clave que use un host (el host debe seguir entrando), ponle una frase de paso y elimina una de prueba;
   - duplica un host y arrástralo a otro grupo en la página de Hosts;
   - abre vim con un tema de colores o tmux con su barra de color: deben verse; prueba «Limpiar el búfer» en el menú del terminal;
   - en un terminal, `printf 'ls \342\200\256txt.exe' | pbcopy` copia un texto con un carácter que le da la vuelta; al pegarlo, la vista previa debe marcarlo en ámbar antes de enviarlo.
20. **Por dentro** (0.3.2-beta.6):
   - busca «web prod» (o dos palabras tuyas) en la barra, en Hosts, en ⌘K y en el inicio: deben salir los mismos hosts;
   - importa tu `~/.ssh/config` y, si tienes, una exportación grande de otro programa: debe ir rápido y sin colgarse;
   - en un terminal local, abre `top` y cierra la pestaña: `top` no debe quedar corriendo (`ps`); deja algo con `nohup sleep 60 &`, escribe `exit`: la pestaña debe cerrarse;
   - descarga por SFTP un archivo con permisos 600: debe quedar 600 en tu disco;
   - en el editor de un host, cambia su entorno: la vista previa del sistema debe cambiar al momento;
   - con un tema de esquinas rectas (Búnker o Monitor), mira la página de Hosts y la barra de estado: nada redondo;
   - abre Ajustes › Acerca de › Licencias: deben estar Ghostty, las bibliotecas de Rust y las fuentes Share Tech Mono y VT323.
21. **SFTP con muchos archivos** (0.3.2-beta.7):
   - sube una carpeta con cientos de archivos pequeños (un `node_modules`, un repositorio) a un servidor lejano, y bájala otra vez: debe ir varias veces más rápido que en la 0.3.2-beta.6;
   - a mitad, pausa y sigue; en otra, cancela: no deben quedar archivos `.part` en el servidor ni en tu disco;
   - corta la red a mitad (o duerme el portátil) y vuelve: la copia debe seguir donde iba y acabar con todos los archivos, sin duplicados;
   - en Linux, descomprime el `.tar.gz` de la release y abre `OpenWard/openward`.
22. **CSV** («Importar…» › CSV):
   - exporta tus hosts de una hoja de cálculo o usa la plantilla de Termius;
   - comprueba los grupos, puertos, usuarios y etiquetas, y los avisos de lo que no entra;
   - impórtalo dos veces y comprueba que no se duplica.
23. **Registros de sesión** (0.3.3-beta.1):
   - sin activar nada, conéctate a un par de hosts y abre Registros (⌘⇧R): cada sesión debe tener su entrada, «sin registro»;
   - activa los registros en un grupo de pruebas (en su editor, «Avanzado» › «Registro de sesión») y conéctate a uno de sus hosts: el chip «Registro» debe salir en la barra de estado, y Ajustes › Registros debe nombrar ese grupo;
   - escribe una contraseña sin eco (`sudo -k; sudo true`, o `read -s x`): ni el visor ni el buscador deben tener lo que tecleaste;
   - pausa desde el chip, ejecuta `echo oculto-$((6*7))` y sigue: ni `oculto-42` ni el comando deben estar en el registro;
   - corta la red un momento y vuelve: debe quedar un solo registro, con el corte marcado en la línea de tiempo;
   - días después, busca en Registros algo que respondió un comando: debe salir sin abrir los registros uno a uno;
   - en el visor, salta entre comandos con las flechas, reproduce a 8× y guarda uno con una nota; exporta un `.cast` y comprueba que `asciinema play` lo reproduce;
   - cierra la app de golpe (`kill -9`) mientras graba: al abrirla, el registro debe estar, como mucho sin los últimos segundos;
   - vuelca algo grande (`cat` de un log de cientos de MB, o `seq 1 30000000`) con la grabación activada y sin ella, y dinos cuánto tarda cada vez;
   - cambia los días a 90 y reinicia la app: Ajustes › Registros debe seguir diciendo 90.
24. **En Windows y en Linux** (P0 del [camino a la Community](community.md#p0--windows-y-linux-al-día)). Desde aquí, cada beta se prueba en los tres sistemas:
   - **Windows recién instalado:** en Windows Sandbox (o un Windows sin herramientas de desarrollo), descomprime el `.zip` y abre `openward.exe`. Debe arrancar sin instalar nada más, porque el runtime de Visual C++ va con la app. Si falta una DLL, dinos cuál;
   - la primera vez, el asistente debe encontrar `%USERPROFILE%\.ssh\config` y las claves de esa carpeta;
   - la terminal local abre PowerShell, con colores, `Ctrl+C` y el tamaño al cambiar la ventana;
   - si usas el agente de OpenSSH de Windows (el servicio «OpenSSH Authentication Agent»), OpenWard debe conectar con sus claves sin pedirte nada;
   - **con el teclado español**, en Windows y en Linux: AltGr escribe en el terminal `@ # | \ [ ] { } €` y nunca dispara un atajo; Alt con una letra llega al programa como Alt (pruébalo con `cat -v` en un servidor: Alt+X debe salir `^[x`);
   - SFTP con rutas de Windows: `C:\Users\…`, carpetas con espacios y con tildes, y arrastrar desde el Explorador;
   - en Linux, en X11 y en Wayland: arranca, y el portapapeles copia y pega en los dos sentidos;
   - con el tamaño del texto al 150 % (Ajustes › Apariencia), recorre la barra lateral, Hosts y el inicio: nada debe salirse ni cortarse. Los atajos largos, como «Ctrl+Mayús+H», se quitan cuando no caben.
25. **Telnet y puerto serie** (P1 del [camino a la Community](community.md#p1--telnet-y-puerto-serie)):
   - **Telnet:** crea un host para un switch o un router; si no tienes ninguno, `docker run --rm -p 2323:23 busybox telnetd -F -l /bin/sh`. En el editor, pon «Protocolo» a Telnet:
     - debe avisar de que no cifra;
     - deben desaparecer el usuario, las claves y el agente;
     - el puerto debe quedar en 23.
   - conecta:
     - la barra de estado debe decir «Sin cifrar»;
     - cambia el tamaño de la ventana: `stty size` debe dar el nuevo;
     - `echo $TERM` debe dar `xterm-256color`;
     - `exit` debe cerrar la sesión sin decir que se perdió la conexión;
   - un host Telnet detrás de un bastión SSH («Ruta» › a través de él) debe conectar por el bastión;
   - en la barra de conexión rápida, `telnet://host:puerto` debe conectar por Telnet, y volver a hacerlo desde «Recientes»;
   - **puerto serie** (un cable USB a la consola de un router o un switch, o dos adaptadores cruzados; en Linux sirve `socat -d -d pty,raw,echo=0 pty,raw,echo=0`):
     - en el inicio, «Puerto serie»: la lista del botón USB debe tener el cable, con su nombre;
     - a 9600 8N1 debe salir la consola al pulsar Intro;
     - «Enviar un break por el puerto serie» (en la paleta) debe llevar un router a su monitor de arranque;
     - el mismo puerto en dos pestañas: la segunda debe decir que está en uso;
     - suelta el cable: la pestaña debe decir «Se ha desconectado…», y al volver a conectar, «Reconectar» debe abrirlo otra vez;
     - en Linux, con un usuario que no está en `dialout`, el error debe decir cómo añadirlo;
     - un host guardado con «Protocolo» › Puerto serie, el puerto elegido de la lista y otra velocidad, debe abrirse con esa velocidad;
   - **importar** desde PuTTY, SecureCRT, MobaXterm, Tabby, Termius o un CSV con sesiones Telnet y serie: deben llegar como Telnet y serie, no como avisos. De MobaXterm, el serie trae el puerto y la velocidad; comprueba el resto de la línea;
   - con los registros activados, una sesión Telnet y otra serie deben quedar en Registros y verse en el visor.
26. **Mosh** (P2 del [camino a la Community](community.md#p2--mosh-en-escritorio)), con `brew install mosh` (o `apt install mosh`) aquí y `mosh` en un servidor tuyo:
   - en el editor del host, «Avanzado» › Mosh › Encendido, y conecta: la barra debe decir «Mosh»;
   - cambia de red sin cerrar nada (de la wifi al móvil, o duerme el portátil diez minutos): la sesión debe seguir donde estaba, sin «Reconectando»;
   - con el servidor detrás de un cortafuegos que no deja pasar UDP (o un host sin `mosh`), la sesión debe seguir por SSH, en tmux, con una línea que diga por qué;
   - sin `mosh-client` en el equipo, igual, y la línea debe decir cómo instalarlo;
   - si `mosh-server` no está en el `PATH` del servidor (Homebrew en un Mac), pon su ruta en «Servidor de Mosh».
27. **Llaves de seguridad y certificados** (P3 del [camino a la Community](community.md#p3--llaves-fido2-y-certificados)), con una YubiKey u otra llave FIDO2, en los tres sistemas:
   - **crear:** «Claves» › «Nueva clave» › «En una llave de seguridad», Ed25519, y toca la llave cuando parpadee. Debe quedar `~/.ssh/id_ed25519_sk` con «Llave de seguridad» en la lista. Con una llave sin Ed25519 (las anteriores a 2020), elige ECDSA;
   - **entrar:** pon la clave en un servidor («Poner en un servidor») y conecta. La tarjeta debe pedir el toque, y sin tocarla debe decir que no se tocó a tiempo;
   - **el PIN:** crea otra con «Pedir el PIN cada vez». Al conectar, debe pedir el PIN, y con uno mal, decirlo y volver a pedirlo;
   - **otra llave:** con una segunda llave conectada en lugar de la primera, el error debe decir que no es la de esta clave; con las dos a la vez, que hay más de una;
   - **importar** una hecha con `ssh-keygen -t ed25519-sk`: debe entrar igual;
   - **en Linux**, sin la regla de udev de `/dev/hidraw*`, el error debe decir que falta y qué paquete la trae; **en Windows**, sin ser administrador, que se use el agente de OpenSSH de Windows;
   - **un certificado** que caduque en unos días (`ssh-keygen -s ca -V +3d`): «caduca en 3 días» en las claves y en la identidad. Ya caducado, el error al entrar debe decir que es el certificado.
28. **Terminal** (P4 del [camino a la Community](community.md#p4--terminal)):
   - **ratón:** en Ajustes › Terminal, «Copiar al seleccionar»: selecciona y pega en otra app sin copiar. «Pegar con clic derecho»: el clic derecho pega, y con Ctrl abre el menú;
   - **resaltado:** `ip addr`, `ping`, `journalctl -p warning` y un `make` que falle deben mostrar en color las direcciones, los avisos y los errores. `ls --color` debe seguir con sus colores, y en `vim` o `less` no debe pintarse nada. Apaga una regla, añade una tuya (`\bretry\b`) y cambia el tema: los colores lo siguen;
   - **codificación:** un switch o un sistema viejo en Latin-1 (o `printf '\xe1\xe9\xed\n'` en un servidor), con «Avanzado» › Codificación › Latin-1, debe verse «áéí» y escribir «ñ» debe llegar bien. Un BIOS o un menú de DOS en CP437 debe dibujar sus cajas;
   - **retroceso:** con Control-H, en un equipo que lo pida, Retroceso debe borrar en vez de escribir `^H`;
   - **colores por host:** pon Monitor a un host de producción. Su pestaña debe tener esos colores con cualquier tema, y los demás, los del tema;
   - **atajos:** en un Mac, «Atajos de» PC: Ctrl+Mayús+T abre un terminal y ⌘T no. En Windows o Linux con «Las teclas, para el terminal», Ctrl+Tab debe llegar al programa (en `emacs`, o con `showkey -a`).
29. **Sugerencias** (P5 del [camino a la Community](community.md#p5--autocompletado-local)):
   - en un host con historial, escribe el principio de un comando que ya usaste: el resto debe salir en gris y → (o Fin) escribirlo. Escribe otra cosa: debe desaparecer;
   - con `sudo` o `read -s`, mientras pide la contraseña, nada; en `vim` o `less`, nada;
   - con fish, o zsh con zsh-autosuggestions, solo la del shell, no las dos;
   - un snippet de una línea debe sugerirse también, y `do` en un host nuevo, `docker ps`;
   - con el historial de comandos apagado (Ajustes › Registros), «Sugerir mientras escribes» queda apagado y no sale nada.
 Ctrl+Mayús+K abre la paleta y Ctrl+Mayús+/ la hoja de atajos. La barra lateral se pliega con Ctrl+Mayús+L (Ctrl+B es del shell).

## Cómo informar

Como en la 0.2 ([cómo](prueba-v0.2.md#cómo-informar)). Para el historial, no pegues los comandos tal cual si llevan nombres de servidores internos: describe qué escribiste y qué esperabas. Lo mismo con los registros: no adjuntes un `.cast` ni un texto exportado sin leerlo antes, porque guarda todo lo que salió en pantalla.
