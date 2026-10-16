# Prueba de la v0.2

La puerta de salida de la [v0.2](v0.2.md) es esta: el equipo usa OpenWard dos semanas como único cliente, también para transferencias y túneles, y no quedan fallos que bloqueen el trabajo. Esta guía explica cómo instalar la beta, qué probar y cómo informar. Lo que trae está en las [notas de la versión](../notas/v0.2.md).

## Instalar

Los paquetes salen de la CI, y el de macOS también de Homebrew:
- **Con Homebrew (macOS):** el cask `openward` de `kaicorplabs/tap`, que también trae las betas siguientes. Lo explica la sección de macOS.
- **De una release:** en GitHub, **Releases**, el borrador o la beta `v0.2.0-beta.N`, con los tres paquetes.
- **De una ejecución:** **Actions → CI**, la semanal o una lanzada con «Run workflow». Baja el artefacto `OpenWard-macOS`, `OpenWard-Linux` u `OpenWard-Windows`. El de Linux sale en cada push.

### macOS 13 o posterior (Apple silicon e Intel)

Lo más cómodo es Homebrew. Una vez, añade el tap y confía en él:

```bash
brew tap kaicorplabs/tap && brew trust kaicorplabs/tap
```

Después, instala:

```bash
brew install --cask openward
```

Y con cada beta nueva, actualiza:

```bash
brew upgrade --cask openward
```

Si ya tenías OpenWard en Aplicaciones (la alfa, por ejemplo), llévala antes a la Papelera: Homebrew no instala encima de una app que no puso él, y tus datos no se pierden.

Sin Homebrew, abre `OpenWard-<versión>-macos.dmg` y arrastra OpenWard a Aplicaciones. Para crear el `.dmg` desde el repositorio:

```bash
app/tool/package-macos.sh
```

De las dos formas, la primera vez hay que dejarla abrir. No está firmada ni notarizada, así que macOS se niega a abrirla:
1. Intenta abrirla una vez.
2. Ve a **Ajustes del Sistema → Privacidad y seguridad**.
3. Pulsa **Abrir igualmente**.

También se puede quitar la cuarentena desde un terminal:

```bash
xattr -dr com.apple.quarantine /Applications/OpenWard.app
```

### Linux (x86_64, GTK 3)

```bash
tar xzf OpenWard-<versión>-linux-x64.tar.gz
```

```bash
./bundle/openward
```

### Windows 10/11 (x86_64)

Descomprime el `.zip` y abre `Release\openward.exe`. Como no está firmada, SmartScreen avisa: pulsa **Más información → Ejecutar de todas formas**.

## Dónde guarda sus datos

| Sistema | Carpeta |
|---|---|
| macOS | `~/Library/Application Support/dev.openward.OpenWard` |
| Linux | `~/.local/share/dev.openward.OpenWard` |
| Windows | `%APPDATA%\OpenWard contributors\OpenWard` |

Dentro están:
- `vault.db`: hosts, grupos, identidades, túneles, snippets y claves de host en las que se confía. **Aún no va cifrado**, pero no contiene secretos: las claves se guardan por ruta y las contraseñas no se guardan nunca.
- `settings.json`: los ajustes.

Si vienes de la alfa, tus datos siguen ahí y valen tal cual.

OpenWard lee `~/.ssh/config` y `~/.ssh/known_hosts`. Solo escribe en `known_hosts` cuando quitas una línea desde **Biblioteca › Hosts conocidos**, y antes guarda una copia en `known_hosts.old`.

## Qué probar

Úsala para todo, durante dos semanas. Lo nuevo de la 0.2, en concreto:

1. **Apariencia:** elige tema, combina capas y ajusta el tamaño del texto y el contraste mínimo (Ajustes › Apariencia). Pruébalo en claro y en oscuro.
2. **Terminal:**
   - busca con ⌘F;
   - abre enlaces con ⌘ y clic;
   - divide paneles con ⌘D y ⌘⇧D, y muévete entre ellos con ⌘⌥ y las flechas;
   - arrastra pestañas para ordenarlas, y suelta una pestaña o un host de la barra lateral sobre un terminal para dividirlo;
   - prueba el clic derecho en una pestaña y en el terminal;
   - sal de un shell con `exit` y comprueba que su pestaña se cierra sola;
   - activa el broadcast con ⌘⇧B y pega con él.
3. **SFTP (⌘⇧O):**
   - copia en las dos direcciones, también carpetas enteras;
   - arrastra desde el Finder o el Explorador;
   - corta la red a mitad de una copia y comprueba que retoma desde donde se quedó;
   - prueba con ficheros que ya existen y cambia permisos.
4. **Túneles:**
   - crea uno local, uno remoto y uno SOCKS5;
   - marca alguno para que se abra al conectar;
   - si tu `~/.ssh/config` tiene `LocalForward`, impórtalo.

   Si trabajas detrás de un proxy, ponlo en el grupo (fila «Proxy»).
5. **Identidades:** junta usuario y claves en una identidad, ponla en un grupo con «Usar en…» y comprueba que cada host dice de dónde le viene cada valor.
6. **Snippets:**
   - guarda los comandos que repites, con alguna `{{variable}}`;
   - ejecútalos con ⌘⇧S en un panel y con broadcast en varios.
7. **Hosts conocidos:** busca un servidor y olvida una clave. Si tu `known_hosts` tiene nombres cifrados, busca uno por su nombre.
8. **Teclado y lector de pantalla:** si usas VoiceOver, NVDA u Orca, recorre la app con Tab y dinos lo que no se entienda.
9. **Importar desde tu cliente anterior** (menú «…» › Importar…):
   - si usas Termius, léelo desde ahí. Comprueba que están tus hosts, grupos, identidades y túneles, y que las claves se encuentran en `~/.ssh` o se guardan allí;
   - si vienes de PuTTY, MobaXterm, Tabby o SecureCRT, importa su archivo exportado;
   - importa una segunda vez y comprueba que no se duplica nada;
   - conéctate a los hosts importados.

En Windows y Linux, ⌘ es Ctrl+Mayús: Ctrl+Mayús+D, Ctrl+Mayús+O, Ctrl+Mayús+S…

## Cómo informar

1. En **Ajustes › General**, pulsa **Informar de un problema…** y luego **Copiar**. Copia la versión, el sistema, el tema y cuántos hosts tienes, sin direcciones, usuarios ni claves.
2. Abre una issue en el repositorio y pega eso, con:
   - qué hiciste, qué esperabas y qué pasó;
   - para problemas de conexión, el texto de la barra de estado y los detalles de la conexión (pulsa la barra de estado);
   - para problemas de pantalla, una captura y el programa que corría.

No pegues claves, contraseñas ni huellas de servidores internos en issues públicas.

Al final de las dos semanas se repasan juntas y se decide qué falta para publicar la 0.2.
