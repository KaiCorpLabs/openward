# OpenWard · Umbral

Identidad aprobada el 19 de octubre de 2026: una O abierta con un chevrón
separado que representa entrada y avance. **Grafito oscuro es el icono
predeterminado** en macOS, Windows y Linux. La variante clara está disponible
como fuente y exportación; no se añade selección automática de icono por tema.

## Fuentes

- `svg/`: símbolo vectorial editable en turquesa, positivo grafito y negativo
  blanco cálido. Son dos trazados reales; no contienen bitmaps ni requieren fuentes.
- `png/`: exportaciones transparentes originales del símbolo, de 16 a 1024 px.
- `masters/`: renders dimensionales aprobados, oscuro y claro, de 1024 × 1024 px.
  Son imágenes raster cuadradas y opacas, no modelos 3D ni vectores.
- `preview/`: lámina aprobada de revisión, no utilizable como icono de la app.
- `SOURCE.md`: guía original del paquete, conservada como referencia histórica.

Origen: `OpenWard-Umbral-review-v1.zip`, SHA-256
`465b610eeaa471fb5571752a259b13a9305ab04cfa60007b51026ee7924513be`.
Se conservan los archivos seleccionados sin alterar sus bytes. Los ICO/ICNS
opacos incluidos en el ZIP no se instalan: se vuelven a empaquetar después de
adaptar la silueta de escritorio.

## Uso de marca

- Grafito `#12161B`, turquesa `#3CC8B0`, blanco cálido `#F3F0EA`.
- Mantener la relación de aspecto y el `viewBox="0 0 1024 1024"` de los SVG.
- Espacio libre mínimo: 49 unidades del máster alrededor de la silueta.
- Positivo sobre fondos claros, negativo sobre fondos oscuros. Turquesa es un
  acento de marca; no implica contraste garantizado para texto.
- No añadir texto ni bordes en el hueco entre la O y el chevrón.
- La geometría plana y los reflejos de los renders dimensionales son fuentes
  distintas. Cambiar un SVG no modifica automáticamente el máster dimensional.

## Regenerar los iconos de escritorio

Con el Flutter fijado por el proyecto y las dependencias ya disponibles:

```sh
cd app
fvm flutter test --no-pub tool/make_icons.dart
```

No se requiere un servicio externo ni ejecutar CI. El generador usa Flutter,
ya presente en el proyecto; en macOS también usa el `iconutil` del sistema.

El generador lee los másteres y los PNG planos de 1024 px. No recrea el antiguo
escudo ni aproxima la geometría aprobada con trazados nuevos. Si se modifica un
SVG, actualizar también su exportación transparente de 1024 px antes de regenerar.

La adaptación mantiene la cuadrícula existente: placa de 824 × 824 unidades
en un lienzo de 1024 × 1024, margen de 100 y radio de 185. Se recorta el máster
a esa placa y se conserva transparencia exterior; macOS no aplica esta máscara
por nosotros. Desde 64 px se añade una sombra exterior corta. En 16, 24 y 32 px
se usa el símbolo plano a mayor escala óptica sobre la placa: turquesa en oscuro
y grafito en claro, para conservar la abertura y el chevrón.

### Archivos consumidos por la app

- macOS: `app/macos/Runner/Assets.xcassets/AppIcon.appiconset/`, PNG de 16, 32,
  64, 128, 256, 512 y 1024 px. Se conserva `Contents.json`. Xcode usa este
  catálogo para compilar `AppIcon.icns`; no hay que copiar un ICNS a mano.
- Windows: `app/windows/runner/resources/app_icon.ico`, con entradas PNG de
  16, 24, 32, 48, 64, 128 y 256 px; `Runner.rc` ya apunta a esta ruta.
- Linux: `app/linux/openward.png`, 512 px, usado por el empaquetado existente.

### Exportaciones locales

En `app/build/branding/` (ignorado por Git) se generan los PNG de ambas
variantes, los ICO multirresolución y, en macOS, los ICNS con `iconutil`.
Estos ICNS sirven para inspección local. Los tamaños de la variante clara
no reemplazan los iconos predeterminados ni cambian la apariencia de la app.

La integración cubre escritorio. iOS y Android conservan sus requisitos de
empaquetado para cuando se desarrollen esos clientes; no reutilizar los PNG con
margen de escritorio como si fueran sus másteres a sangre.

## Verificación local de la integración · 19 de octubre de 2026

- Generación local completada con `flutter test --no-pub tool/make_icons.dart`;
  análisis de `tool/make_icons.dart` sin incidencias.
- Comprobadas dimensiones, referencias de `Contents.json`, lectura de PNG,
  transparencia de las cuatro esquinas y margen exterior en ambas variantes.
- ICO oscuro y claro: siete entradas válidas, de 16 a 256 px. El ICO usado por
  Windows coincide con el oscuro generado; el PNG de Linux coincide con el de
  512 px. Los contenedores opacos originales del ZIP no se utilizan en la app.
- ICNS oscuro y claro generados y reabiertos con `iconutil`: diez posiciones
  de escala, de 16 a 1024 px.
- Catálogo macOS compilado localmente con `actool`: genera `AppIcon.icns`,
  `Assets.car` y metadatos `CFBundleIconFile = AppIcon`. `assetutil` confirma
  diez entradas del icono, de 16 a 1024 px, todas con transparencia. El ICNS
  compilado contiene las representaciones heredadas; el catálogo conserva las
  demás escalas en `Assets.car`.
- Revisada una lámina nativa con AppKit, incluyendo el ICNS compilado y los
  tamaños pequeños sobre fondos claros y oscuros. No se ha instalado ni
  arrancado una nueva build de OpenWard; tampoco se ha probado en una sesión
  real de Windows o Linux. No se ha ejecutado CI ni publicado una versión.
