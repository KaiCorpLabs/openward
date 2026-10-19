# OpenWard (app)

La app de Flutter de OpenWard. Por ahora solo hay escritorio (macOS, Linux y Windows); las demás plataformas llegan en fases posteriores. Habla con el núcleo de Rust (`core/crates/openward-ffi`) mediante flutter_rust_bridge, y lo compila y empaqueta cargokit (`rust_builder/`).

> **Estado:** alfa de escritorio 0.1.0 ([plan](../docs/plan/alfa-escritorio.md), [guía de prueba](../docs/plan/alfa-prueba.md)). La app permite:
> - guardar hosts y grupos e importar `~/.ssh/config`;
> - abrir pestañas con terminal SSH o local;
> - responder a las preguntas de conexión y reconectar;
> - seleccionar y copiar;
> - elegir los ajustes.

## Requisitos

- Flutter con [FVM](https://fvm.app/): la versión está en `/.fvmrc`.
- Rust y Zig, como en `core/`. La primera compilación construye `libghostty-vt` (`core/crates/openward-ghostty/build-libghostty.sh`).

## Uso

```bash
fvm flutter run -d macos
```

**Pruebas.** Hay tres conjuntos:
- `test/`: el decodificador de frames y el dibujo de cajas, sin Rust.
- `integration_test/ffi_test.dart`: el núcleo a través de los bindings.
- `integration_test/ui_test.dart`: la ventana entera. Guarda capturas en `$TMPDIR/openward-shots`.

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

**Regenerar los iconos Umbral** desde sus fuentes aprobadas. La [guía de marca](../assets/brand/umbral/README.md) documenta los SVG editables, los másteres oscuro y claro, la máscara de escritorio y las rutas de cada plataforma. Grafito oscuro es el predeterminado; la variante clara se exporta a `build/branding/`.

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

## Notas

- **macOS sin App Sandbox.** Un cliente SSH con terminal local tiene que lanzar shells y ProxyCommand, leer `~/.ssh` y hablar con el agente, como hacen iTerm2 o Ghostty. Por eso la Mac App Store queda fuera por ahora.
- **cargokit lleva dos parches de OpenWard**, marcados en el código:
  - el toolchain de Rust se fija en `core/crates/openward-ffi/cargokit.yaml`;
  - el nombre de la librería convierte los `-` en `_`, como hace cargo.
