# Android e iOS

- **Estado:** primera implementación completa en la rama de la PR de [#68](https://github.com/KaiCorpLabs/openward/issues/68) (2026-11-13). Compila y pasa sus pruebas en el simulador de iOS y en el emulador de Android. Falta todo lo que exige un teléfono real, una cuenta de desarrollador o una decisión (ver «Revisar después»).
- **Base:** [ADR-001](../adr/ADR-001-rust-core-flutter-go.md) (la misma app Flutter y el mismo núcleo Rust en las cinco plataformas), [ARCHITECTURE §3.7](../ARCHITECTURE.md#37-móvil) y las decisiones del 2026-11-13 ([community.md](community.md#decisiones-del-2026-11-13)): las apps salen después de la Community de escritorio y antes de cobrar por la sync.
- **Seguimiento:** [#68](https://github.com/KaiCorpLabs/openward/issues/68). Los contratos de cuenta, sync y cobro siguen en #62, #38, #64 y #63.

## Qué hay

**La app es la de `app/`, no una copia.** Se añaden `app/android/` y `app/ios/`, y lo que cambia en un teléfono se decide en un solo sitio, `lib/core/platform.dart` (`Device`): lo que no existe allí se oculta en vez de fallar.

**Núcleo (Rust).**
- Compila para `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-linux-android` y `x86_64-linux-android`. libghostty-vt se construye para los cuatro con `build-libghostty.sh`.
- `libc` 0.2.191: la 0.2.190 dejó `_dyld_*` solo en macOS y rompía `backtrace` (de `flutter_rust_bridge`) en iOS.
- Solo de escritorio, sin backend en el teléfono: las llaves FIDO2 por USB HID (`openward-fido` sin `hid`: el autenticador responde «el sistema no deja hablar con la llave») y los puertos serie (`openward-serial` sin `serialport`: en iOS enlazaba símbolos de IOKit de macOS).
- **iOS:** el Keychain y el Secure Enclave usan el mismo código que macOS (`security-framework`), con `use_protected_keychain` y sin `ignore_legacy_keychains`, que en iOS no existe.
- **Android:** el Keystore, a través de `VaultKeystore.kt`, al que el núcleo llama por JNI. `MainActivity` carga la librería con `System.loadLibrary` antes que Flutter, y `JNI_OnLoad` (`openward-ffi/src/android.rs`) le pasa la VM y la clase. La clave de 32 bytes vuelve a Rust y nunca pasa por Dart. Desbloqueo biométrico con BiometricPrompt y `CryptoObject` en cada uso (AES-256-GCM, StrongBox si lo hay, invalidada al cambiar las huellas); «Más tarde» con una clave del Keystore sin biometría.
- Nuevo `NativeProtection.biometric`: Face ID o Touch ID en iOS, huella o rostro en Android.
- **Carpetas de datos y del vault:** en el teléfono no se comprueba quién es el dueño de cada carpeta padre (AM-3), porque el contenedor de la app es del sistema (`/data/user/0` es de `system`, 0771). La carpeta sigue siendo 0700 y del usuario de la app.
- **Android:** `HOME` y `TMPDIR` apuntan a las carpetas de la app antes de cargar el núcleo; sin ellas, `~/.ssh`, `known_hosts` y los temporales no tenían dónde ir.

**Interfaz.**
- **Teléfono** (menos de 720 de ancho en Android o iOS):
  - una barra superior: menú, el título de la pestaña (un toque lista todas, con «Inicio»), buscar, número de pestañas y un menú de acciones;
  - la barra lateral entera en un cajón;
  - debajo de una sesión, la **barra de teclas** (`terminal/key_bar.dart`): Esc, Tab, Ctrl y Alt fijos (un toque, la siguiente tecla; dos, hasta soltarlos), flechas que se repiten, `| ~ / - _ $ * :`, Inicio, Fin, RePág, AvPág, pegar y el teclado.
- Las tabletas anchas conservan la ventana de escritorio con los mismos cambios táctiles.
- **Táctil, en todas partes:**
  - un toque conecta un host (en escritorio, doble clic) y abre una carpeta del SFTP;
  - mantener pulsado es el clic derecho (menús de hosts, archivos y terminal);
  - arrastrar desplaza la lista: se desactivan los arrastres de filas y pestañas, que competían con el desplazamiento.
- **Terminal:**
  - un toque abre el teclado, o un enlace;
  - mantener pulsado empieza una selección, que el dedo extiende, y al soltar sale el menú de copiar y pegar;
  - pellizcar cambia el tamaño de letra;
  - en Android el teclado del sistema va como «contraseña visible», para que no componga palabras enteras antes de entregarlas (ver limitaciones).
- **SFTP:**
  - un lado cada vez, con un selector;
  - el lado local es la carpeta de la app: «En mi iPhone › OpenWard» en Archivos (iOS) y la carpeta externa de la app en Android;
  - «Importar archivos del teléfono…» y «Guardar en…» pasan por los selectores del sistema;
  - no hay «Abrir» ni «Abrir con», porque no hay programas a los que pasar el archivo.
- **«Guardar como»:** el kit de recuperación, las copias del vault, exportar un registro y exportar una clave escriben en una carpeta temporal de la app y la entregan al selector del sistema (`core/save_file.dart` y el canal `openward/files`). La copia temporal se borra se guarde o no.
- **Claves:** elegir un archivo de clave en un teléfono la importa al vault, porque el sistema solo da una copia temporal. Ocultos en móvil:
  - generar llaves de seguridad;
  - el agente del sistema;
  - ProxyCommand y Mosh, salvo si ya vienen de un escritorio;
  - serie, terminal local, el pegado con clic derecho y la carpeta de registros.
- **Textos de teléfono:** «este teléfono» en vez de «esta cuenta del sistema», y la bienvenida no menciona `~/.ssh/config`.
- **Iconos:** `tool/make_icons.dart` genera también el AppIcon de iOS y el icono adaptativo de Android (con monocromo), a partir de los mismos másteres Umbral.

**Nativo.**
- `openward/security`: el vault se bloquea al apagarse la pantalla (Android) o al bloquearse el dispositivo (iOS, si tiene código), igual que con el bloqueo del sistema en escritorio. En iOS, la captura del selector de apps muestra una portada negra.
- `openward/sessions`: con sesiones abiertas, Android mantiene un servicio en primer plano con una notificación («N sesiones abiertas»), de tipo `specialUse`; en iOS se pide el tiempo que el sistema da en segundo plano. Después, la reconexión automática y tmux reanudan.
- `openward/files`: el selector de documentos de cada sistema.
- Android no hace copia de seguridad ni migración a otro teléfono de los datos de la app (`allowBackup=false` y `data_extraction_rules.xml`), porque el vault viajaría sin la clave del Keystore que lo abre con «Más tarde».

## Paridad con el escritorio

| Función | Android | iOS | Nota |
|---|---|---|---|
| Hosts, grupos, etiquetas, herencia, entornos, favoritos, recientes | Sí | Sí | |
| SSH: contraseña, 2FA, claves, certificados, saltos, proxy HTTP/SOCKS | Sí | Sí | Probado contra los servidores S2 desde el simulador y el emulador |
| Kex poscuántico | Sí | Sí | Se ve «post-quantum» en la barra de la sesión |
| Telnet | Sí | Sí | |
| Túneles L/R/D | Sí | Sí | Escuchan en el teléfono; mueren con la app en segundo plano en iOS |
| SFTP | Sí | Sí | Un lado cada vez; los archivos entran y salen por el selector del sistema |
| Snippets, historial, paleta, workspaces, known hosts, identidades | Sí | Sí | |
| Registros de sesión y visor | Sí | Sí | Exportar pasa por el selector del sistema |
| Paneles divididos y broadcast | Sí | Sí | Sin arrastrar paneles: se dividen desde los menús |
| Vault cifrado, kit, copias, «Más tarde» | Sí | Sí | «Más tarde» probado en ambos |
| Desbloqueo biométrico | BiometricPrompt | Face ID / Touch ID | Sin probar en dispositivo (el emulador no tiene huella enrolada) |
| Claves en hardware para SSH | No (Keystore pendiente) | Secure Enclave (sin probar en dispositivo) | ARCHITECTURE §3.5 |
| Llaves FIDO2 | No | No | Por NFC o USB, en una fase posterior |
| Terminal local | No | No | Sin shell del teléfono |
| Puertos serie | No | No | USB en Android, en una fase posterior; iOS no tiene |
| ProxyCommand, Mosh (`mosh-client`), agente del sistema | No | No | Sin programas del teléfono; Mosh volverá con el cliente clean-room ([ADR-009](../adr/ADR-009-mosh-clean-room.md)) |
| Importar de PuTTY, MobaXterm, SecureCRT y CSV desde un archivo | Sí | Sí | |
| Importar de programas instalados, Termius incluido, y `~/.ssh/config` | No | No | No hay otros programas en el teléfono |
| Abrir un archivo remoto con una app del equipo | No | No | |
| Atajos de teclado | Con teclado físico | Con teclado físico (iPad) | Las teclas de atajo no se dibujan en un teléfono |
| Cuenta, sync y cobro | — | — | Aún no existen en ninguna plataforma (#62, #38, #63) |

## Cómo se prueba

```sh
cd app
# Compila el núcleo para el destino y lo empaqueta
fvm flutter build apk --debug --target-platform android-arm64
fvm flutter build ios --simulator --debug

# Con los servidores S2 (spikes/s2-ssh/servers/up.sh)
S2=$HOME/Library/Caches/openward/s2-fixtures
fvm flutter test integration_test/mobile_test.dart -d <simulador iOS> \
  --dart-define=S2_FIXTURES=$S2
fvm flutter test integration_test/mobile_test.dart -d emulator-5554 \
  --dart-define=S2_HOST=10.0.2.2 --dart-define=S2_KEY_B64=$(base64 < $S2/id_ed25519 | tr -d '\n')
```

`mobile_test.dart` prueba tres cosas:
- la estructura de teléfono: cajón, un toque conecta, lista de pestañas, «Inicio», barra de teclas y menú al mantener pulsado;
- una sesión SSH real tecleada con la barra, con Ctrl fijo + C que interrumpe un `sleep`;
- el vault protegido con el llavero del teléfono: bloquearlo y volver a abrirlo, que solo se prueba en iOS y Android.

En macOS prueba la estructura de teléfono con `Device.debugMobile`; está en `tool/ci.sh` junto a las builds de Android e iOS.

Resultado del 2026-11-13: 3 de 3 en el iPhone 17 Pro (iOS 26.5, simulador), 3 de 3 en un emulador Android 15 arm64 y 2 de 2 en macOS (el caso del llavero se salta allí). A mano, en el emulador: onboarding con «Más tarde», reinicio y desbloqueo con el Keystore, conexión rápida con confirmación de la clave del host, contraseña, comandos y permiso de notificaciones.

La CI:
- en Actions, el núcleo completo para Android con el NDK del runner y el APK de depuración. iOS, sin Xcode, solo con lo que no compila C;
- en local, `tool/ci.sh` comprueba el núcleo completo para los cuatro destinos y construye las dos apps en el modo completo.

## Limitaciones conocidas

- **Teclado en Android:** sin composición. El japonés, el chino y el coreano escriben su alfabeto latino. Volver a permitir la composición sin retrasar el eco (Tab, `less`) es trabajo de S5.
- **Segundo plano en iOS:** sin conexión pasados unos 30 s; el reenganche a tmux recupera la sesión si el host lo tiene activado. Las transferencias largas del SFTP se cortan igual.
- **Biometría al activarla en Android:** se pide una vez para cifrar la clave y no se vuelve a leer en el momento, porque pediría el dedo dos veces. Su lectura se prueba en el primer desbloqueo. En macOS sí se lee de vuelta.
- **La ruta del archivo de datos se muestra** en el error de arranque. En el teléfono es una ruta del contenedor, sin botón para abrirla.
- **Tabletas anchas:** la ventana de escritorio sin hover. El menú de pestañas y algunos botones que salen al pasar el ratón solo se alcanzan manteniendo pulsado. No hay una estructura propia de iPad.
- **Diálogos de anchura fija:** se ajustan al ancho del teléfono porque Flutter limita su `SizedBox`. Puede quedar alguno con una fila que no quepa; ya se corrigieron los paneles de conexión.
- **Firma:** las builds de release se firman con la clave de depuración en Android y no hay equipo de firma en iOS.

## Revisar después

**Puertas pendientes de [#68](https://github.com/KaiCorpLabs/openward/issues/68):**
- [ ] S1.2: rendimiento y eco del terminal en un Android de gama media y en un iPhone reales, y VoiceOver y TalkBack fila a fila ([ADR-002](../adr/ADR-002-motor-de-terminal.md#validación-y-revisión)). Si falla, se reabre ADR-002.
- [ ] S2 móvil: la matriz de interoperabilidad desde un dispositivo y la elección `aws-lc-rs` / `ring` ([ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md)). Hoy se usa aws-lc-rs, igual que en escritorio.
- [ ] S3: el firmante SSH con Android Keystore / StrongBox, por JNI como el desbloqueo.
- [ ] S5: el IME en Android: composición, Gboard y CJK.
- [ ] Face ID o Touch ID y BiometricPrompt reales: activar, desbloquear, cancelar, cambiar las huellas (la clave debe invalidarse) y bloqueo por intentos.
- [ ] Secure Enclave en un iPhone: crear, firmar, borrar y comprobar que no se exporta (`spec/secure-enclave-ssh-v1.md`).

**Seguridad ([THREAT_MODEL §8](../THREAT_MODEL.md#8-lo-que-llega-después)):**
- [ ] Revisar que la excepción a AM-3 en el teléfono es correcta (`create_private_dir` y `openward-vault::migration::path`). El sandbox sustituye a la comprobación de los padres.
- [ ] Las copias temporales de «Guardar como», que incluyen una clave privada o un JSON en claro si el usuario los exporta: están en la caché de la app y se borran al terminar, pero un cierre a mitad las deja hasta que el sistema limpia la caché.
- [ ] iOS: el vault en «Application Support» entra en las copias de iCloud y la clave «Más tarde» (`ThisDeviceOnly`) no. Decidir si se excluye de la copia (`isExcludedFromBackup`) como en Android.
- [ ] Capturas de pantalla: en escritorio no se impiden. Valorar `FLAG_SECURE` en Android y la portada de iOS al grabar la pantalla.
- [ ] `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` y el permiso de notificaciones, para la revisión de Google Play.

**Producto e interfaz:**
- [ ] Una estructura propia de tableta (iPad y Android grandes), con barra lateral y paneles pensados para el dedo.
- [ ] Acciones de las filas visibles sin hover en las listas de hosts, o una pista de «mantén pulsado».
- [ ] Ajustes de teclado físico en móvil (Option como Alt y perfil de atajos), probados con un iPad y un teclado.
- [ ] Botones de la barra de teclas configurables, y gestos de dos dedos para el scroll local y de tmux.
- [ ] Los textos de permiso de iOS (Face ID y red local, en `Info.plist`) están solo en inglés: localizarlos con `InfoPlist.strings`. Los de Android (BiometricPrompt y la notificación) ya están en español e inglés.
- [ ] Modo agente, `tmux -CC` y avisos push (fase 3, [ARCHITECTURE §3.7](../ARCHITECTURE.md#37-móvil)).

**Distribución y cuentas (con aprobación aparte; sin gasto ni publicación en esta PR):**
- [ ] Identificadores finales antes de subir nada: `dev.openward.openward` (Android) y `dev.openward.OpenWard` (iOS, el mismo que macOS). No se pueden cambiar después.
- [ ] Cuentas de Apple Developer y de Google Play (gasto), firma de release, TestFlight y la prueba interna de Google Play. F-Droid y el APK en GitHub, en #41.
- [ ] Declaraciones de las tiendas: cifrado para la exportación (`ITSAppUsesNonExemptEncryption`), etiquetas de privacidad y seguridad de los datos.
- [ ] La CI de iOS en Actions con un runner de macOS, y las pruebas en un dispositivo real.

**Cuenta, sync y cobro:**
- [ ] Callbacks del inicio de sesión (App Links y Universal Links, PKCE) según el contrato de #62.
- [ ] Sync de #38 con el mismo vault.
- [ ] StoreKit y Play Billing o la ruta que decida #63.
- [ ] La matriz escritorio↔móvil de #42.
