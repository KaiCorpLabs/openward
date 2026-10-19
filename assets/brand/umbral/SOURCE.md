# OpenWard · Umbral
## Paquete de revisión · 19 octubre 2026

Identidad seleccionada: O abierta con un chevrón separado que sugiere entrada y avance. Conserva la dirección de la primera propuesta.

### Contenido
- `svg/`: símbolo vectorial real editable, construido con dos trazados. Teal, positivo grafito y negativo blanco cálido. Sin imágenes incrustadas ni fuentes necesarias.
- `png/`: exportaciones transparentes del símbolo en 16, 24, 32, 48, 64, 128, 256, 512 y 1024 px.
- `app-icons/dark/` y `app-icons/light/`: iconos dimensionales en esos mismos tamaños. Máster cuadrado opaco a sangre, para aplicar la máscara de cada plataforma durante la integración.
- `app-icons/*.ico`: contenedores multirresolución hasta 256 px.
- `app-icons/*.icns`: contenedores multirresolución hasta 1024 px.
- `preview/`: lámina de revisión; no es un archivo para instalar como icono.
- `validation.json`: comprobación de lectura de los archivos exportados.

### Color y espacio
- Grafito: #12161B
- Turquesa: #3CC8B0
- Blanco cálido: #F3F0EA
- En SVG, conservar la relación de aspecto y el viewBox 0 0 1024 1024. La marca ocupa aproximadamente el 64 % del ancho y el 59 % del alto.
- Espacio libre mínimo alrededor de la silueta: media anchura del trazo del anillo (49 unidades del máster). No acercar texto ni bordes al hueco entre O y chevrón.
- Usar el símbolo positivo sobre fondos claros, el negativo sobre fondos oscuros. El turquesa es el acento de marca, no un color de texto de accesibilidad garantizada.
- Para interfaces de 16–32 px, preferir los archivos planos. En 16 px el detalle es pequeño: revisar en la escala real del producto. No agrandar un PNG pequeño; exportar del SVG.

### Qué está finalizado y qué falta revisar
Los SVG son geometría editable; los iconos dimensionales son imágenes raster generadas, no modelos 3D ni vectores. La versión vectorial es una reconstrucción geométrica limpia de la propuesta seleccionada, no un calco exacto de sus reflejos y perspectiva. Los acabados claro y oscuro mantienen la misma dirección visual; pueden presentar diferencias leves de iluminación propias del render generado.

Los PNG de app son cuadrados opacos deliberadamente: evitan artefactos de recorte y permiten máscaras específicas de cada plataforma. Los ICO/ICNS se han generado y abierto correctamente con Pillow, pero no se han instalado ni probado en macOS, Windows, Linux o iOS. Este paquete no afirma certificación de Apple ni cumplimiento automático de requisitos de tiendas. Revisar máscara, márgenes ópticos y escala en el proyecto antes de publicar.

No se ha modificado el repositorio, ejecutado CI ni publicado ningún cambio. Requiere aprobación visual antes de integrar.
