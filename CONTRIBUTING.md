# Contribuir a OpenWard

Gracias por tu interés. OpenWard está en fase 1, con una beta de escritorio: el diseño todavía cambia, así que **abre un issue antes de un pull request grande**.

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

## DCO

Las contribuciones a `core/`, `app/`, `spec/`, `docs/` y `spikes/` usan el [Developer Certificate of Origin](https://developercertificate.org/). Firma cada commit:

```bash
git commit -s
```

Eso añade `Signed-off-by: Tu Nombre <tu@email>` y certifica que tienes derecho a aportar el código bajo la licencia del directorio.

## CLA (solo `server/`)

Las contribuciones al servidor, cuando exista, requerirán además un acuerdo de licencia de contribuidor (CLA). **No cedes el copyright:** concedes una licencia amplia que permite ofrecer el servidor también bajo licencia comercial. El motivo está en el [ADR-007](docs/adr/ADR-007-licencias-y-contribuciones.md).
