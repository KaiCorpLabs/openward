# Contribuir a OpenWard

Gracias por tu interés. OpenWard está en fase 1, con una beta de escritorio, y **hasta que se lance la Community no acepta contribuciones de código de fuera**: el repositorio tiene todos los derechos reservados ([LICENSING.md](LICENSING.md)). Los issues y los [avisos de seguridad](SECURITY.md) sí son bienvenidos.

Lo que sigue es cómo trabaja el equipo, y lo que se pedirá a quien contribuya cuando el código sea open source.

## Antes de empezar

- **Decisiones de arquitectura:** se proponen como ADR en [`docs/adr/`](docs/adr/) (estado, contexto, decisión, alternativas, consecuencias, validación). Un cambio que contradiga un ADR aceptado necesita un ADR nuevo.
- **Spikes:** el código de `spikes/` es desechable y no se importa desde `core/`.
- **Idioma:** issues, PRs y documentación en español o inglés.

## Comprobaciones

Desde un clon recién hecho, `make setup` deja las herramientas listas (ver el [README](README.md#desarrollo)).

```bash
make lint     # rustfmt + clippy con -D warnings
make test
make deny     # licencias y avisos de seguridad de las dependencias
```

Todo lo que hace la CI, aquí (núcleo, destinos móviles, spikes, dependencias, la app y sus pruebas de ventana, con los servidores SSH de prueba): `make ci`. Sin las pruebas de ventana, `make ci-quick`. Nada llega a `main` sin `make ci` en verde.

El núcleo prohíbe `unsafe` (`unsafe_code = "forbid"`). Las únicas excepciones son crates de FFI aislados y revisados (bindings de Flutter, firmantes de plataforma, motores en C) y un préstamo del descriptor del terminal local en `openward-pty`.

## Datos de prueba

No incluyas en el repositorio grabaciones de terminal, capturas ni logs con hosts, usuarios, rutas o claves reales. Graba en contenedores desechables con datos sintéticos.

## Firmar los commits

Firma cada commit con `Signed-off-by` ([Developer Certificate of Origin](https://developercertificate.org/)):

```bash
git commit -s
```

## CLA (desde el lanzamiento)

Cuando se abran las contribuciones, todas (cliente, especificación y documentación) requerirán un acuerdo de licencia de contribuidor (CLA). **No cedes el copyright:** concedes una licencia amplia que permite ofrecer OpenWard también con otras licencias, por ejemplo en la App Store. El motivo está en el [ADR-007](docs/adr/ADR-007-licencias-y-contribuciones.md).
