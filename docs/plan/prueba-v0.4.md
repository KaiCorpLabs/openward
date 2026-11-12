# Guía de pruebas · 0.4.0-beta.1

Candidata build31. Seguimiento: [D8 #37](https://github.com/KaiCorpLabs/openward/issues/37).
Registrar sistema, arquitectura, versión, commit y enlace de CI del paquete.
Las pruebas automatizadas no acreditan uso humano ni autenticación física.
No adjuntar perfiles, contraseñas, kits, claves privadas o registros privados
al issue. Usar datos ficticios para capturas y errores reproducibles.

## Preparación

1. Instalar el artefacto de la CI del commit de la PR, comprobando su procedencia
   en el trabajo App de cada sistema. En macOS el snapshot incluye el commit
   en su nombre y `.commit`; Linux/Windows quedan ligados al artefacto y run.
2. Crear una copia externa privada del perfil 0.3 y un perfil de prueba separado.
   `OPENWARD_DATA` permite elegir este último al arrancar la app. Usar solo una
   instancia por perfil. No compartir un perfil entre versiones.
3. Preparar un host de pruebas. Anotar recuentos y contenido de hosts, grupos,
   identidades, snippets y claves antes de migrar, sin incluir secretos en el informe.

## Onboarding y migración

- Perfil nuevo: Home no aparece hasta confirmar contraseña y los dos grupos
  solicitados del kit. Cancelar, contraseña débil o confirmación errónea dejan
  el onboarding cerrado. Guardar el kit en un medio independiente, probar QR/PDF.
- Perfil 0.3: comparar todos los datos tras migrar; cerrar y reabrir, comprobar
  historial/recientes y reproducir una grabación antigua. El vault debe arrancar
  bloqueado. Los archivos auxiliares deben abrirse solo tras desbloquearlo.
- «Más tarde»: aceptar el aviso de Linux si corresponde; comprobar cifrado,
  recordatorio permanente, bloqueo y reapertura con la cuenta del sistema.
  Un llavero ausente/cancelado deja la pantalla cerrada. No eliminar el único
  llavero de un vault real para probar esta condición: usar un perfil desechable.
- Completar contraseña y kit desde el recordatorio o Ajustes: mismos datos,
  desbloqueo por contraseña y recuperación por kit tras reiniciar. Ya no debe
  ofrecerse la clave temporal del equipo ni quedar el aviso.

## Ajustes › Seguridad

- Contraseña incorrecta y cancelación del sistema mantienen el vault bloqueado.
  Cambiar contraseña exige la actual o el kit; la antigua deja de abrir la copia
  actual. Regenerar kit exige contraseña y confirmación; comprobar el kit nuevo.
- Bloquear con el botón, ⌘L / Ctrl+Alt+L, inactividad y suspensión. No deben
  pintarse ni exponerse por accesibilidad terminales, búsquedas, diálogos o
  metadatos privados. Las sesiones establecidas pueden continuar.
- Guardar y borrar una clave privada, una contraseña y una frase de paso con
  consentimiento. Reabrir y usar el host. Verificar las alternativas por ruta
  y «no guardar». Nunca mostrar un secreto guardado solo por abrir Ajustes.
- Comprobar Touch ID y Windows Hello físicamente, incluidos cancelación y
  fallback por contraseña. En Linux comprobar Secret Service y su advertencia.
  Anotar firma y capacidades del paquete: los mocks no cierran esta prueba.

## Recuperación y copias

1. Exportar `.owvault`. Crear otro perfil cifrado vacío con contraseña y kit
   distintos; restaurar con la contraseña de origen y repetir con su kit.
2. Probar en otro sistema/equipo. El destino conserva su propia contraseña y
   kit. Comparar los datos y una credencial utilizable; no solo los recuentos.
3. Exportar JSON aceptando que está en claro y autenticándose de nuevo.
   Restaurarlo en otro perfil vacío. Sin consentimiento o con contraseña
   incorrecta no debe escribirse ningún archivo.
4. Alterar una copia ficticia, truncarla, usar credencial errónea o un destino
   con datos: rechazar sin cambios. Cancelar la vista previa no importa nada.
5. Las claves por ruta y los datos locales D6 no viajan en estas copias. Las
   copias anteriores conservan su protección anterior. Eliminar con cuidado
   las exportaciones de prueba; no asumir borrado forense.

## Evidencia automatizada

La CI completa exige núcleo y App en Linux/macOS/Windows, dependencias, contratos
S1/S2/S4/S6, servidores SSH reales en Linux, integración FFI, UI y accesibilidad,
además de paquetes identificados por ejecución/commit. La galería es obligatoria en los tres sistemas. Su envoltorio rechaza fallos
internos aunque `flutter drive` termine con código0; la limpieza del perfil
temporal se comprueba dentro del cuerpo de la prueba.

`cargo test --release --locked -p openward-vault ten_thousand -- --ignored --nocapture`
mide la carga del índice de 10.000 ítems después del KDF (objetivo <300ms).
`cargo test --release --locked -p openward-crypto calibrated_password_measurement -- --ignored --nocapture`
informa la calibración Argon2id (objetivo 0,5–1s, mínimo64MiB). Registrar resultado
real y hardware; son medidas del runner, no una garantía para todo equipo.
La [medición local y su alcance](../evidence/v0.4-beta1.md) conserva los números de la candidata.
Las migraciones de fixtures publicados y la recuperación de archivos comunes
en los tres sistemas complementan, sin sustituir, las pruebas personales.

## Puertas humanas pendientes

| Puerta | Evidencia necesaria | Estado de la candidata |
|---|---|---|
| Migración personal sin pérdidas | Comparación antes/después y sistema, sin datos privados | Pendiente de participantes |
| Una semana de uso cifrado | Fechas, escenarios diarios e incidencias | Pendiente de participantes |
| Recuperación independiente personal | Otro perfil/equipo, contraseña olvidada en una copia | Pendiente; fixtures automatizados disponibles |
| Touch ID / Windows Hello físicos | Equipo, firma, éxito y cancelación | Pendiente en #33 |
| Revisión visual de maquetas | Referencia y conformidad | Pendiente en #33 |

Anotar cada resultado en #37 o #33 con commit y evidencia. Mantener #37 abierto
mientras falten estas puertas. La publicación pública, etiqueta de distribución
y cask se deciden aparte; esta preparación no los publica.
