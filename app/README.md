# OpenWard (app)

La app de Flutter de OpenWard, la misma para escritorio (macOS, Linux y Windows) y para teléfonos (Android e iOS: [plan, paridad y límites](../docs/plan/movil.md)). Habla con el núcleo de Rust (`core/crates/openward-ffi`) mediante flutter_rust_bridge, y lo compila y empaqueta cargokit (`rust_builder/`).

> **Estado:** beta de escritorio 0.3 ([plan](../docs/plan/v0.3.md), [notas](../docs/notas/v0.3.md), [guía de prueba](../docs/plan/prueba-v0.3.md)).

## Requisitos

- Lo que instala o pide `make setup`, en la raíz: Rust, Flutter con [FVM](https://fvm.app/) (la versión de `/.fvmrc`), Zig y `libghostty-vt`.

## Uso

```bash
fvm flutter run -d macos
```

**Android e iOS.** Además, el NDK de Android (`~/Library/Android/sdk/ndk`) o Xcode, y `libghostty-vt` para el destino: `aarch64-linux-android` y `x86_64-linux-android`, o `aarch64-ios` y `aarch64-ios-simulator`, con `core/crates/openward-ghostty/build-libghostty.sh <destino>`. cargokit compila el núcleo al construir la app.

```bash
fvm flutter run -d <emulador o simulador>
```

```bash
fvm flutter build apk --debug --target-platform android-arm64
```

```bash
fvm flutter build ios --simulator --debug
```

**Pruebas.** Hay cuatro conjuntos:
- `test/`: Dart sin Rust. Lo que habla con el núcleo (pestañas, conexiones, la cola de transferencias, los espacios de trabajo, la paleta) usa el `FakeOpenWard` de `test/fakes.dart`.
- `integration_test/ffi_test.dart`: el núcleo a través de los bindings.
- `integration_test/ui_test.dart`: la ventana entera. Guarda capturas en `$TMPDIR/openward-shots`.
- `integration_test/a11y_test.dart` y `gallery_test.dart`: accesibilidad (contraste, tamaños, foco) y la galería de temas.
- `integration_test/mobile_test.dart`: el teléfono (estructura, barra de teclas, SSH y el llavero del teléfono), en un simulador, un emulador o, solo la estructura, en macOS. Cómo pasarle los servidores S2: [plan móvil](../docs/plan/movil.md#cómo-se-prueba).

Las partes de SSH solo se ejecutan si los servidores de prueba están arriba (`spikes/s2-ssh/servers/up.sh`).

```bash
fvm flutter test test/
```

```bash
fvm flutter test integration_test/ffi_test.dart -d macos
```

```bash
fvm flutter test integration_test/ui_test.dart -d macos
```

**Empaquetar para macOS:** `.dmg` universal en `build/`, sin firmar.

```bash
tool/package-macos.sh
```

**Regenerar los iconos Umbral** (escritorio, el AppIcon de iOS y el icono adaptativo de Android) desde sus fuentes aprobadas. La [guía de marca](../assets/brand/umbral/README.md) documenta los SVG editables, los másteres oscuro y claro, la máscara de escritorio y las rutas de cada plataforma. Grafito oscuro es el predeterminado; la variante clara se exporta a `build/branding/`.

```bash
fvm flutter test --no-pub tool/make_icons.dart
```

**Regenerar los logos de los sistemas** desde la versión de Simple Icons fijada en el script (los códigos son los de `openward-app::system`):

```bash
dart run tool/system_logos.dart
```

**Regenerar los bindings** después de cambiar `core/crates/openward-ffi/src/api`. El resultado va a `lib/src/rust`, que se versiona.

```bash
PATH="$HOME/fvm/versions/$(jq -r .flutter ../.fvmrc)/bin:$PATH" flutter_rust_bridge_codegen generate
```

**Subir flutter_rust_bridge** es a mano y de una vez: la versión exacta en `core/crates/openward-ffi/Cargo.toml` y en `pubspec.yaml`, el generador (`cargo install flutter_rust_bridge_codegen --version …`) y los bindings regenerados, en el mismo commit. Dependabot lo ignora para que no suba solo una mitad.

## Notas

- **macOS sin App Sandbox.** Un cliente SSH con terminal local tiene que lanzar shells y ProxyCommand, leer `~/.ssh` y hablar con el agente, como hacen iTerm2 o Ghostty. Por eso la Mac App Store queda fuera por ahora.
- **cargokit lleva dos parches de OpenWard**, marcados en el código:
  - el toolchain de Rust se fija en `core/crates/openward-ffi/cargokit.yaml`;
  - el nombre de la librería convierte los `-` en `_`, como hace cargo.
