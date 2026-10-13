# OpenWard (app)

La app de Flutter de OpenWard. Por ahora solo hay escritorio (macOS, Linux y Windows); las demás plataformas llegan en fases posteriores. Habla con el núcleo de Rust (`core/crates/openward-ffi`) mediante flutter_rust_bridge, y lo compila y empaqueta cargokit (`rust_builder/`).

> **Estado:** hito A2 de la [alfa de escritorio](../docs/plan/alfa-escritorio.md). `lib/main.dart` es provisional: solo lista los hosts guardados e importa `~/.ssh/config`. La interfaz de verdad llega con A3.

## Requisitos

- Flutter con [FVM](https://fvm.app/): la versión está en `/.fvmrc`.
- Rust y Zig, como en `core/`. La primera compilación construye `libghostty-vt` (`core/crates/openward-ghostty/build-libghostty.sh`).

## Uso

```bash
fvm flutter run -d macos
```

**Pruebas de integración.** Llaman al núcleo de verdad a través de los bindings: hosts y herencia, importación, shell local y una conexión SSH con la pregunta de clave de host. La parte de SSH solo se ejecuta si los servidores de prueba están arriba (`spikes/s2-ssh/servers/up.sh`).

```bash
fvm flutter test integration_test/ffi_test.dart -d macos
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
