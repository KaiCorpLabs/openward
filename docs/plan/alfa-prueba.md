# Prueba de la alfa de escritorio

La puerta de salida de la [alfa](alfa-escritorio.md) es esta: el equipo trabaja una semana con OpenWard contra sus servidores reales, sin volver a su cliente anterior para lo básico, y anota los problemas que encuentre. Esta guía explica cómo instalarla, qué probar y cómo informar.

## Instalar

Los paquetes salen del CI:
1. En GitHub, ve a **Actions → CI** y abre la ejecución que quieras: la semanal, o una lanzada con «Run workflow».
2. Baja el artefacto `OpenWard-macOS`, `OpenWard-Linux` u `OpenWard-Windows`.

El de Linux sale en cada push.

### macOS 13 o posterior (Apple silicon e Intel)

```bash
app/tool/package-macos.sh
```

Ese es el atajo para crear el `.dmg` desde el repositorio.

1. Abre `OpenWard-<versión>-macos.dmg` y arrastra OpenWard a Aplicaciones.
2. La alfa no está firmada ni notarizada, así que macOS se niega a abrirla la primera vez. Para abrirla:
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
- `vault.db`: hosts, grupos y claves de host en las que se confía. **En la alfa no va cifrado**, pero no contiene secretos: las claves se guardan por ruta y las contraseñas no se guardan nunca.
- `settings.json`: los ajustes.

Para empezar de cero, borra la carpeta. OpenWard lee `~/.ssh/config` y `~/.ssh/known_hosts`, pero no los modifica.

## Qué probar

1. **Importar:** importa `~/.ssh/config` (icono de descarga en la barra lateral) y revisa el informe: qué entró y qué no.
2. **Conectar:** usa tus hosts de verdad.
   - Prueba con clave, con el agente (incluido el de 1Password u otro, si lo usas), con contraseña y con 2FA.
   - Prueba un salto a través de un bastión y, si los tienes, ProxyCommand con `cloudflared` o `aws ssm`.
3. **Trabajar con el terminal:**
   - vim, htop y tmux;
   - pegar varias líneas;
   - seleccionar y copiar (con Mayús dentro de vim o tmux si tienen el ratón activado);
   - redimensionar la ventana;
   - salidas largas.
4. **Pestañas y atajos:**
   - ⌘T terminal local, ⌘W cerrar, ⌘1–9 y ⌘K buscar;
   - renombrar y reordenar pestañas.
5. **Cortes de conexión:** suspende el portátil o cambia de red con una sesión abierta. Debería reconectarse sola.
6. **Ajustes:** tema claro u oscuro, tamaño de letra y Opción como Alt si usas emacs o readline.

## Limitaciones conocidas

Por alcance, la alfa no tiene:
- SFTP, túneles guardados, snippets, paneles divididos ni broadcast;
- importadores aparte de `~/.ssh/config`;
- historial de comandos;
- cifrado del vault.

Además:
- No hay pantalla para ver o borrar las claves de host guardadas.
- Al seleccionar arrastrando más allá del borde, el terminal no se desplaza solo.
- El intercambio de claves poscuántico solo se negocia con OpenSSH 10.0 o posterior (y Dropbear 2025.88): los 9.x solo ofrecen `sntrup761`, que russh no tiene.
- Linux y Windows se compilan y prueban en el CI, pero nadie los ha usado todavía a diario.

## Cómo informar

Abre una issue en el repositorio con:
- el sistema y la versión (`OpenWard 0.1.0-alfa`, el sistema operativo);
- qué hiciste, qué esperabas y qué pasó;
- para problemas de conexión, el texto de la barra de estado y los detalles de la conexión (pulsa la barra de estado);
- para problemas de pantalla, una captura y el programa que corría.

No pegues claves, contraseñas ni huellas de servidores internos en issues públicas.

Al final de la semana se repasan juntas y se decide qué falta para dar la alfa por buena.
