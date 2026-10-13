# render_harness

Banco de render y de entrada del [spike S1](../../../docs/spikes/S1-terminal.md): app Flutter con el núcleo en Rust vía `flutter_rust_bridge`.

- **Banco de render (S1.4):** cargas sintéticas y de tecleo; mide fps, tiempos de frame y latencia. `--dart-define=S1_AUTORUN=…` ejecuta sin intervención y `S1_ENGINE=alacritty|ghostty` elige el motor.
- **Entrada (S1.5):** shell real en un pty local, o registro de teclas que muestra los bytes de cada entrada. Se abren con los botones de la barra superior o con `--dart-define=S1_PAGE=shell|keylog`.

```bash
fvm flutter run -d macos --release
fvm flutter test                                          # decodificador de frames
fvm flutter test integration_test/input_test.dart -d macos  # entrada de punta a punta
```

Los bindings de Dart se regeneran con `flutter_rust_bridge_codegen generate` (2.13.0).
