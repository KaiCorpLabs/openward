# Prueba de la v0.3

La [v0.3](v0.3.md) cierra la fase 1. Su puerta de salida es esta:
- el equipo crea y sube sus claves desde OpenWard;
- trabaja una semana con la paleta y el historial;
- abre su día con un espacio de trabajo;
- importa un CSV propio.

Lo que trae está en las [notas de la versión](../notas/v0.3.md).

## Instalar

Como la 0.2 ([cómo](prueba-v0.2.md#instalar)). Con Homebrew, la beta nueva llega con:

```bash
brew upgrade --cask openward
```

## Dónde guarda sus datos

En la misma carpeta que la 0.2 ([cuál](prueba-v0.2.md#dónde-guarda-sus-datos)), con un archivo más:
- `history.json`: el historial de comandos. Es de este equipo: no va al vault ni se sincroniza. Ajustes › Terminal lo apaga o lo borra.
- `recent.json` (desde la 0.3.0-beta.3): las conexiones recientes y cuánto usas cada acción de la paleta. También es de este equipo; Ajustes › General lo apaga o lo borra.

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
   - después de unos días, mira si los recientes del inicio (cuándo, cuánto duró, tmux) te sirven para volver;
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
14. **CSV** («Importar…» › CSV):
   - exporta tus hosts de una hoja de cálculo o usa la plantilla de Termius;
   - comprueba los grupos, puertos, usuarios y etiquetas, y los avisos de lo que no entra;
   - impórtalo dos veces y comprueba que no se duplica.

En Windows y Linux, ⌘ es Ctrl+Mayús: Ctrl+Mayús+K abre la paleta y Ctrl+Mayús+/ la hoja de atajos. La barra lateral se pliega con Ctrl+Mayús+L (Ctrl+B es del shell).

## Cómo informar

Como en la 0.2 ([cómo](prueba-v0.2.md#cómo-informar)). Para el historial, no pegues los comandos tal cual si llevan nombres de servidores internos: describe qué escribiste y qué esperabas.
