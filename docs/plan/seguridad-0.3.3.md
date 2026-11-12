# Seguridad de la 0.3.3: contraste con main

Revisión del **11 de noviembre de 2026** de los 63 puntos de la [PR #8](https://github.com/KaiCorpLabs/openward/pull/8), frente a [main `35ab7a6`](https://github.com/KaiCorpLabs/openward/commit/35ab7a63187a58aae132a31bd000ab0858164dff). Se conserva cada ID y su orden. La [versión original del informe](https://github.com/KaiCorpLabs/openward/blob/377492780338bfd120c85b55a4d15efae20d9263/docs/plan/seguridad-0.3.3.md) examinaba `b6b0012` (0.3.3-beta.2); sus estados y cifras ya no describen por sí solos main.

Las fichas conservan el contraste inicial; los apartados de seguimiento de S0, S1 y S2 registran las correcciones posteriores, sus pruebas y sus PR. Para el estado actual prevalecen esos seguimientos. La fusión de este informe no acredita el cierre de los puntos que continúan abiertos.

## Resultado y alcance

| Dictamen en `35ab7a6` | Puntos | Significado |
|---|---:|---|
| Confirmado por evidencia estática | **25** | Hay un recorrido y una consecuencia dentro del alcance admitido, con las condiciones descritas en la ficha. No implica reproducción nueva. |
| Necesita revisión | **20** | Falta un hecho concreto de plataforma, permisos, comportamiento o contrato que podría cambiar el resultado. |
| No accionable en el alcance actual | **18** | Hay una defensa efectiva, una ruta todavía inactiva, un comportamiento deliberado o una exclusión explícita del modelo. **No significa que todos estén corregidos.** |
| Total de entradas originales | **63** | No se han añadido hallazgos de una búsqueda nueva ni fusionado entradas parecidas. |

Se aplica [SECURITY.md](../../SECURITY.md), única política encontrada al resolver las 66 rutas citadas, junto con el [modelo de amenazas](../THREAT_MODEL.md). Este contempla archivos importados hostiles, servidores SSH hostiles, otros usuarios del equipo y cadena de suministro. Excluye malware/programas del mismo UID, administradores y la denegación de servicio o llenado de disco por el servidor remoto. Una importación hostil que bloquea la aplicación sigue siendo un caso distinto de esa última exclusión.

El contraste inicial se limitó a leer código, configuración, dependencias fijadas y estado de GitHub. La remediación posterior sí incorpora reproducciones, regresiones, builds y CI, según el seguimiento de cada punto. Las nueve pruebas externas citadas por el informe original son **evidencia histórica**; no se presentan como pruebas repetidas por ese contraste. Tampoco se repite su búsqueda de secretos por todo el historial ni se certifica ausencia de secretos.

La gravedad mostrada en cada ficha es la **del informe de entrada**, para conservar trazabilidad; no se arrastran sus totales antiguos como una medición actual. C1…C25 y R1…R20 ordenan por explotabilidad relativa las colas de confirmados y de revisión, por separado; no son una puntuación CVSS.

## Cambios que alteran el diagnóstico

- **IM-2 está corregido en la ruta de importación del producto.** `hold_back` desactiva el forwarding de agente importado en hosts y grupos, y avisa.
- **IM-1 está mitigado parcialmente.** Ya se retiran binds fuera de loopback, pero `autostart` permanece y un túnel remoto puede exponer un servicio local.
- **DA-1 ya no describe el caso normal.** La carpeta se crea/endurece a 0700; queda por resolver la garantía si falla `chmod` o no es del usuario.
- **SF-8 y TE-1 tienen defensas nuevas.** Abrir un archivo remoto pasa por controles específicos, y U+2028/U+2029 ya se representan en el texto visible. Persisten las diferencias de la descarga ordinaria y la vista previa truncada.
- **CO-4 no queda resuelto por el arreglo reciente de ECDSA.** El cambio de escalares privados no normaliza la comparación de puntos públicos comprimidos en revocación.
- **CI-2 y CI-9 han cambiado.** Hay CI alojada en tres sistemas; core utiliza `crypto-bigint 0.7.10`. El repositorio ya es público.
- **CI-3 sigue vigente por una razón comprobada distinta:** el reporte privado de vulnerabilidades está desactivado (`enabled=false`, consulta autenticada de GitHub del 11-11-2026).

## Plan de remediación actualizado S0–S3

Las prioridades ordenan la remediación; su avance y sus límites se registran debajo. S2 está en validación; S3 conserva su planificación.

| Etapa | Trabajo | Condición para darlo por terminado |
|---|---|---|
| **S0 — confianza e importación** | CO-1, IM-1, IM-3, IM-4, DA-3, DA-4; habilitar un canal privado utilizable (CI-3) | Ningún archivo ajeno amplía autoridades, habilita túneles/comandos o añade claves sin consentimiento sobre el contenido y alcance efectivos. |
| **S0 — escritura y envío de archivos** | SF-1, SF-5 | Descarga anclada al destino, sin seguir enlaces locales preparados por otro usuario; subida confinada a la selección o enlaces autorizados explícitamente. |
| **S1 — política SSH y permisos** | CO-3…CO-6, SF-2, SF-3, SF-9; resolver CO-2 y DA-1 | Algoritmo recibido sujeto a la política; revocación canónica; rotación y fallos de persistencia seguros; permisos aplicados al objeto correcto. |
| **S1 — consentimiento e historial** | RG-1, RG-7, RG-8, TE-1 | Exclusión de historial consistente; texto/origen revisables antes de reenviar; borrado que incluya residuos administrados; pegado completo revisable. |
| **S2 — presupuestos de entrada y build** | IM-5, IM-6, DA-7, CI-1, CI-7 | Importación/lectura acotadas y herramientas/resolución de build ligadas a contenido revisado. |
| **S2 — hechos pendientes** | Las fichas que conservan hechos sin comprobar, según sus seguimientos | Obtener el dato mínimo indicado y convertir cada caso en confirmado o descartado con evidencia; no cerrar por ausencia de una PoC. Las 20 iniciales no son un recuento actual. |
| **S3 — D3/D6 y distribución** | DA-2, DA-5, RG-4, CI-4…CI-6, CI-8, CI-10…CI-12 y demás deuda documentada | Preparar migraciones y manejo de secretos, acordar la puerta de publicación, aislar builds y verificar procedencia antes de ampliar garantías. |

## Seguimiento de S0

El contraste anterior y las 63 fichas conservan la referencia histórica a
`35ab7a6`. Este seguimiento registra las correcciones posteriores, sin
convertir los casos pendientes de revisión en casos cerrados. Para el estado
actual de estos puntos prevalece este seguimiento sobre las fichas históricas.

| Punto | Cambio posterior |
|---|---|
| **CI-3** | Reporte privado de vulnerabilidades habilitado el 11-11-2026. Se comprobó con GET antes (`enabled=false`) y después (`enabled=true`) de cambiar el ajuste de GitHub. |
| **SF-1 y SF-5** | [PR #13](https://github.com/KaiCorpLabs/openward/pull/13). Las transferencias adquieren una autoridad local al comenzar a ejecutarse y la conservan al pausar o reanudar. Las lecturas, conflictos, directorios, partes, metadatos, instalación y cancelación se resuelven desde esa autoridad. Las partes se abren sin seguir enlaces y se rechazan si el descriptor no es un archivo regular con un único enlace duro, antes de truncar o escribir. La subida abre el origen antes de cualquier escritura remota, también en la preservación de propietario. Se conservan nombres deterministas de partes, reanudación, enlaces relativos contenidos y enlaces elegidos explícitamente como selección raíz. Los enlaces que escapan de la selección producen un error; «solo si es más reciente» conserva la comparación para enlaces contenidos y omite aquellos cuyo destino no se puede inspeccionar dentro de la selección. Los trabajos en espera no consumen descriptores; una adquisición fallida puede reintentarse. La validación completa se registra en los checks de la PR correspondiente. |
| **IM-1** | Corregido en la [PR #9](https://github.com/KaiCorpLabs/openward/pull/9), fusionada con 19 jobs correctos. La importación retira el arranque automático en los tres tipos de túnel, tanto al detectar como al guardar un bundle. Los túneles importados por versiones anteriores requieren aprobación desde el editor antes de arrancar automáticamente. Los túneles manuales y los del `~/.ssh/config` propio conservan su comportamiento. |
| **DA-3** | Corregido en la [PR #10](https://github.com/KaiCorpLabs/openward/pull/10), con 19 jobs correctos. Cada instalación valida una sola clave antes de E/S remota; los comentarios leídos o escritos por la app no producen líneas adicionales. La regresión SFTP comprueba rechazo sin cambios y autenticación válida posterior. |
| **CO-1** | Corregido en la [PR #11](https://github.com/KaiCorpLabs/openward/pull/11), fusionada con 19 jobs correctos. La importación exige seleccionar por separado cada entrada completa, con su alcance y huella. No se preselecciona ninguna al elegir hosts. Las autoridades y comodines importados antiguamente sin aprobación quedan fuera de las conexiones y de la lista activa hasta revisarlos de nuevo al importar. Se conservan los pins literales anteriores, revocaciones y claves propias. |
| **IM-3** | `no_change`: el recorrido atribuido al selector de archivos no existe en producción. Selector y drop pasan por `detect::read`, que no admite `ssh_config`; la acción OpenSSH usa `sshConfigFileProvider=null`, es decir, el `~/.ssh/config` propio y confiable del operador. Las rutas de archivo alternativas son overrides de pruebas. Se añade una regresión del límite de importación con `ProxyCommand`, extensión falsa y un CSV válido de control. Se corrige el dictamen anterior; no se presenta como un arreglo de runtime. |
| **IM-4 y DA-4** | Corregidos en la [PR #12](https://github.com/KaiCorpLabs/openward/pull/12), fusionada con 19 jobs correctos. La ejecución manual, el arranque y el envío multihost exigen revisar el comando completo renderizado cuando procede de snippets importados o incluye variables automáticas. El texto aprobado queda congelado; no se vuelve a renderizar tras consentir. Los controles se representan de forma visible y una reconexión invalida aprobaciones de la sesión anterior. Los snippets propios sin variables conservan la ejecución directa. Validación completa registrada en los checks de la PR correspondiente. |

La corrección de IM-1 incorpora regresiones de los tres tipos de túnel,
persistencia de aprobación y revocación, avisos traducidos y conexiones reales
por terminal/SFTP. El estado de la validación completa queda en los checks de
la [PR #9](https://github.com/KaiCorpLabs/openward/pull/9), fusionada con 19 jobs
correctos, incluida la regresión real de terminal y SFTP.

## Seguimiento de S1

El contraste de S1 partió de `main 0bc4c39`, una vez fusionado S0; cada PR
posterior se contrastó con la versión de main disponible antes de integrarla.
Las fichas originales conservan su referencia histórica; este seguimiento
registra los cambios de S1 y prevalece para su estado actual.

Los recorridos de CO-3…CO-6, SF-2, SF-3, SF-9, RG-1, RG-7, RG-8 y TE-1
siguen presentes en esa base. DA-1 confirma un fallo de garantía ante
ubicaciones inseguras/personalizadas o un endurecimiento fallido; no demuestra
exposición de la carpeta propia normal. CO-2 sigue pendiente de evidencia
de propietario y DACL de Windows con privilegios separados; no se declara
confirmado por la mera ausencia de un check.

| Punto | Cambio posterior |
|---|---|
| **RG-7** | El historial distingue texto propio, reconstruido de pantalla y origen antiguo/desconocido; cargar o reenviar no promueve su procedencia. Solo el texto propio sin controles, del mismo lugar y contexto de transporte, conserva el envío directo. Los demás casos y todo broadcast muestran procedencia, contenido completo con controles visibles y destinos antes de enviar; Enter cancela por defecto. Las sugerencias excluyen historial no propio, controles y snippets que requieran revisión o sustituciones. La entrega conserva texto, sesiones y generaciones capturados antes de las esperas, también en pegados; cambios de pestaña o shell no redirigen la decisión. Solo el envío válido actualiza el contador, se respeta la línea privada y escribir sin Enter no crea evidencia propia nueva. Regresión de sugerencia con ESC fallida en la base; 36 pruebas focalizadas y analyze correctos. La revisión encontró que faltaba el usuario de hosts guardados en el contexto: ahora el núcleo transporta el usuario efectivo del plan SSH, incluyendo herencia/OpenSSH, y su ausencia exige revisión. Se comprueba ops→root con el mismo host/clave, transporte FFI y renovación de terminal local. El seguimiento recibe la entrada de todos los paneles de broadcast, sin duplicar entradas persistidas. Integración real de historial antiguo añadida para CI; revisión independiente completada. [PR #24](https://github.com/KaiCorpLabs/openward/pull/24), [CI de la revisión](https://github.com/KaiCorpLabs/openward/actions/runs/43051744447). |
| **RG-1** | Un espacio propio al comienzo marca toda la línea como privada hasta Enter/Ctrl+C, también tras Tab, flechas, borrar el espacio o reconstruir la pantalla. Inicio/Ctrl+A/Ctrl+U y la posición incierta durante edición conservan la exclusión de forma prudente; el espacio del prompt no se interpreta como preferencia del usuario. Una línea privada tampoco ofrece sugerencias. Las tres regresiones iniciales fallan en la base; los controles conservan comandos normales, edición, prompts y reinicio tras cancelación. Ctrl+D/G/Z conservan la marca privada cuando Bash retiene la línea; la variante de Ctrl+D fue reproducida antes de corregirla. [PR #23](https://github.com/KaiCorpLabs/openward/pull/23), [CI de la revisión](https://github.com/KaiCorpLabs/openward/actions/runs/43051746716). |
| **SF-3** | Las carpetas nuevas de una transferencia se crean privadas, se pueblan con acceso temporal del propietario y reciben modo/fecha del origen de abajo arriba al completar el árbol. La umask efectiva se mide dentro de cada carpeta privada, sin cambiar la umask global; no se transfieren bits especiales. Solo se finalizan carpetas creadas por ese trabajo: las preexistentes conservan sus permisos. La propiedad y la finalización pendiente sobreviven a pausa/fallo/reintento, incluso con todos los archivos ya copiados; cancelar deja carpetas incompletas privadas. Regresión local 0755 frente a 0700 fallida en la base; 32 pruebas nativas correctas, incluidas cuatro umask en procesos aislados, sustitución del nombre del destino y 512 carpetas con límite de 128 descriptores. La revisión detectó un merge a enlace interno roto, alias de directorios y acumulación de descriptores; los tres se corrigieron. Los alias locales del mismo inode combinan permisos por intersección; una colisión remota ambigua por mayúsculas falla antes de copiar el segundo subárbol. Pruebas remotas añadidas para readonly, ambos sentidos, fallo final y pausa/cancelación durante mkdir; **Fusionado y verificado:** [PR #22](https://github.com/KaiCorpLabs/openward/pull/22), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43047626823) (19 trabajos correctos; release omitida por no ser etiqueta). |
| **SF-9** | El editor consulta los atributos actuales del destino y bloquea Aplicar si no conoce sus permisos. Muestra sticky/setuid/setgid y admite cuatro cifras: tres cifras o casillas conservan los bits especiales actuales; cuatro cifras los fijan explícitamente solo en la raíz. La recursión resuelve el enlace seleccionado, evita enlaces descendientes, conserva los bits especiales propios de cada hijo y aplica directorios de abajo arriba; los errores de lectura/aplicación se propagan. Regresiones de formato y enlace raíz fallidas antes del arreglo; 27 pruebas nativas SFTP y 19 del diálogo correctas. Se añade matriz remota para cuatro servidores; **Fusionado y verificado:** [PR #21](https://github.com/KaiCorpLabs/openward/pull/21), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43030907020) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **TE-1** | Ambas confirmaciones de pegado muestran el texto completo en una vista desplazable; se eliminan los cortes UTF-16 de 400/600 caracteres. La vista de broadcast puede desplazarse también en ventanas pequeñas, conservando Cancelar / Solo aquí / Todas y Enter seguro. Las regresiones fallan antes del arreglo por cola oculta y emoji partido con UTF-16 inválido; tres pruebas de widget comprueban texto exacto, controles/bidi al final, Unicode, recorrido hasta el final y decisiones. **Fusionado y verificado:** [PR #20](https://github.com/KaiCorpLabs/openward/pull/20), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43027014775) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **SF-2** | Los enlaces remotos conservan su identidad de enlace, pero sus metadatos de copia usan modo, fecha y tamaño del destino; un stat fallido elimina los valores efectivos antiguos. La descarga compara fechas actuales y crea/aplica permisos desde fstat del descriptor remoto abierto, antes de copiar; las partes reanudadas se limitan antes de escribir, y las heredadas con acceso excesivo reinician en un inode privado para no filtrar bytes nuevos a lectores antiguos, sin ampliar la umask. Fallos de chmod se propagan y el descriptor se cierra también al pausar/cancelar. La regresión del metadato del enlace falla antes del arreglo; 25 pruebas nativas y clippy correctos; la revisión detectó la parte reanudada pública, reproducida y corregida. Se añade matriz SSH real para enlaces anidados privados, ejecución y Newer con origen ilegible que debe omitirse; **Fusionado y verificado:** [PR #19](https://github.com/KaiCorpLabs/openward/pull/19), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43027016621) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **CO-5** | La rotación escribe la clave nueva y revocaciones específicas del host/puerto de las claves anteriores en una sola transacción. Incluye patrones/hash del vault y las claves de los archivos OpenSSH realmente usados por el intento, transportadas desde el fallo a la confirmación; no modifica archivos externos ni otros hosts. La igualdad canónica evita revocar la propia clave. Para estados antiguos, una clave residual que contradice un pin local explícito vuelve a `Changed`; si hay pins propios ambiguos se exige revisión. La política multiclave solo de archivos y los sujetos nuevos certificados por una CA siguen funcionando. Regresión en la base, pruebas de hash/case/puertos, certificados y fallo de la segunda escritura. **Fusionado y verificado:** [PR #18](https://github.com/KaiCorpLabs/openward/pull/18), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43027011653) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **CO-6** | Una clave desconocida se acepta solo tras persistirla o encontrarla ya autorizada al revalidar las fuentes. Un error de almacenamiento rechaza la conexión y llega al usuario; la revalidación y la escritura quedan bajo el mismo bloqueo del vault, por lo que una consulta Unknown antigua no sustituye una clave guardada mientras se preguntaba. Prueba SSH local real: error inyectado implica cero intentos de autenticación; permitir guardar conecta. Diez pruebas focalizadas de confianza; las suites acumuladas incluyen 115 pruebas de app y 32 SSH más cuatro de proxy. Flutter, analyze, clippy y formato correctos. **Fusionado y verificado:** [PR #18](https://github.com/KaiCorpLabs/openward/pull/18), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43027011653) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **CO-3** | La verificación KEX exige que el algoritmo de la firma real coincida con el negociado, antes de comprobarla criptográficamente y aceptar claves nuevas. El mismo límite cubre intercambio inicial, GEX, renegociación y claves certificadas. RSA/SHA-1 explícitamente negociado sigue disponible; la firma propia de la CA conserva su validación independiente. Parche mínimo sobre los fuentes exactos de russh 0.64.1, con procedencia y licencia; ambos consumidores de los spikes usan el mismo parche. La regresión criptográfica falla sin la comprobación (SHA-1 tras negociar SHA-256); tres pruebas focalizadas incluyen seis conexiones reales con los tres hashes, claves simples/certificados y rekey. Clippy, formato, licencias y revisión independiente correctos; **Fusionado y verificado:** [PR #16](https://github.com/KaiCorpLabs/openward/pull/16), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43031090093) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **RG-8** | El borrado total reconcilia el índice con los archivos de UUID canónico administrados (`.json`, `.json.tmp`, `.cast.gz`, `.txt.gz`), incluidos huérfanos. Conserva sesiones abiertas y archivos ajenos; los enlaces se desvinculan sin seguir su destino. Alta, cierre, cambios y borrado se serializan para evitar recreación tardía. Fallos de creación limpian residuos y fallos parciales de borrado mantienen reintento y error visible. La acción también está disponible con lista vacía. Regresión fallida en la base y 19 pruebas focalizadas correctas, más 100 nativas y 281 Flutter; integración de escritorio añadida para CI. **Fusionado y verificado:** [PR #15](https://github.com/KaiCorpLabs/openward/pull/15), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43025720157) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **Aviso de dependencia durante S1** | La CI detectó RUSTSEC-2026-0486 en rustix 1.1.5 después de la validación anterior. Se eleva el mínimo a 1.1.6 y se actualizan los tres lockfiles que lo contienen; la actualización de los consumidores refresca también sus versiones locales antiguas. La base RustSec actualizada valida `advisories ok`, sin exclusión nueva. Las pruebas nativas, clippy y el inventario de licencias pasan con la versión corregida; [PR #17 y CI completa](https://github.com/KaiCorpLabs/openward/pull/17) fusionadas. |
| **DA-1 (DAC Unix)** | La apertura falla antes del vault/logs si la carpeta no pertenece al usuario, era escribible por grupo/otros, un ancestro permite sustituirla o falla establecer/verificar `0700`. Una carpeta escribible se rechaza sin reparar: podría contener enlaces plantados y chmod no los neutraliza. Valida tanto el alias solicitado como el destino canónico y utiliza este último en el núcleo. Los padres sticky de confianza con entradas propias siguen permitidos, así como enlaces protegidos y carpetas propias `0755` o sin permisos iniciales. Las regresiones de carpeta ajena y vault enlazado fallan antes de sus correcciones; 100 pruebas nativas correctas y dos mediciones omitidas. Esta corrección no acredita privacidad mediante DACL de Windows ni una auditoría de ACL extendidas de macOS. **Fusionado y verificado:** [PR #17](https://github.com/KaiCorpLabs/openward/pull/17), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43020250955) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |
| **CO-4** | Pins, revocación de clave/sujeto/CA e identificación de autoridades comparan ECDSA por su punto SEC1 canónico en las tres curvas. Las claves SK conservan también su aplicación. No se reescriben los bytes firmados del certificado y se mantienen firma, validez y principal. Regresiones de codificación, certificados y conexiones SSH reales; la validación completa consta en los checks de la PR correspondiente. **Fusionado y verificado:** [PR #14](https://github.com/KaiCorpLabs/openward/pull/14), [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43012631035) (19 trabajos correctos; publicación de release omitida por no ser una etiqueta). |


### Estado de cierre

S1 comprende doce hallazgos confirmados: CO-3, CO-4, CO-5, CO-6,
DA-1 (DAC Unix), SF-2, SF-3, SF-9, RG-1, RG-7, RG-8 y TE-1. Cada uno tiene
una corrección, regresiones y revisión independiente documentadas arriba.
El cierre exige CI completa de la revisión exacta y fusión; las PR y
ejecuciones enlazadas permiten comprobar ambas condiciones.

| Hallazgo | PR de corrección | Evidencia de CI |
|---|---|---|
| SF-3 | [PR #22](https://github.com/KaiCorpLabs/openward/pull/22) | [9bc73f3](https://github.com/KaiCorpLabs/openward/actions/runs/43047626823) |
| RG-1 | [PR #23](https://github.com/KaiCorpLabs/openward/pull/23) | [a515b28](https://github.com/KaiCorpLabs/openward/actions/runs/43051746716) |
| RG-7 | [PR #24](https://github.com/KaiCorpLabs/openward/pull/24) | [b8edc65](https://github.com/KaiCorpLabs/openward/actions/runs/43051744447) |
| CO-2 | Sin corrección especulativa | No confirmado: falta prueba de propietario/DACL con privilegios separados en Windows. |

La garantía de DA-1 se limita al control de acceso discrecional Unix probado;
no acredita DACL de Windows ni ACL extendidas de macOS. SF-10 conserva su
propia incertidumbre: los cambios de permisos no acreditan ausencia general
de carreras remotas de nombres en SFTP.

La preparación de CI falló por DNS de los archivos de Ubuntu, antes de las
pruebas. El fallback a un espejo conserva keyrings y verificación de firmas;
la [ejecución de diagnóstico](https://github.com/KaiCorpLabs/openward/actions/runs/43044812131)
acredita instalación de dependencias y arranque de todos los servidores.
La matriz y los servidores obligatorios se conservan. Se corrigió también
una conversión de prueba dependiente de `mode_t` y dos esperas de escritorio:
el editor debe cerrarse tras guardar, y la shell debe mostrar un prompt
conocido antes de teclear. No se relajan sus aserciones ni sus plazos.

La integración funcional con servidores se ejecuta en Linux; macOS y Windows
conservan análisis, pruebas de widget, núcleo y empaquetado según la CI.
Las validaciones locales acumuladas incluyen 310 pruebas Flutter, 115 nativas
de app y 11 FFI. Dos pruebas nativas de medición se omiten deliberadamente;
no sustituyen regresiones de seguridad. El detalle reproducible de cambios,
pruebas y CI está en cada PR. El avance posterior de S2 se registra debajo;
S3 conserva su planificación.

## Seguimiento de S2

El contraste parte de `main 60f1be3`, después de S0/S1 y de la
preparación de la beta. Las fichas siguientes conservan su referencia histórica;
este seguimiento prevalece para el estado de estos cinco puntos. Se corrigen
cuatro casos confirmados y se reclasifica IM-6 sin cambiar código. El cierre en
main exige la CI completa de la revisión exacta y su fusión; el resultado de
cada puerta queda enlazado en la tabla, sin sustituirlo por pruebas locales.

| Punto | Resultado del contraste y corrección |
|---|---|
| **CI-1** | [PR #28](https://github.com/KaiCorpLabs/openward/pull/28). Índice multiarch de Ubuntu y commit Flutter fijados; rustup y Zig se verifican antes de ejecutar/descomprimir. La revisión detectó que faltaban los payloads posteriores: se fijan también el manifiesto/componentes mínimos de Rust y los archivos Dart/engine de Flutter para ambos Linux. Los scripts consumen un espejo local cerrado con esos archivos verificados; las descargas adicionales de engine fallan. Ocho pruebas incluyen instalador correcto con manifiesto/compilador cambiado y fuente Flutter correcta con Dart/engine cambiado. La construcción real detectó un error de ruta del espejo de Rust, corregido con regresión. [Bootstrap y paquetes x86_64/aarch64 correctos](https://github.com/KaiCorpLabs/openward/actions/runs/43106171668); [matriz general](https://github.com/KaiCorpLabs/openward/actions/runs/43106171551) con 19 trabajos correctos y PR fusionada con el mismo árbol probado. Docker real en ambas arquitecturas; no se acredita aquí una ejecución local de Podman rootless. Esto no cierra la descarga del SDK mediante la acción alojada ni el resto de CI-12. |
| **CI-7** | [PR #29](https://github.com/KaiCorpLabs/openward/pull/29). Lockfile específico del runner con las versiones transitivas existentes y sus hashes, exigido antes de compilar en ambas copias de Cargokit y en la recuperación 253. Se conserva la dependencia por ruta original que necesita Android. La caché incluye bytes de fuentes, manifiesto, lock y SDK; una caché antigua, un kernel ausente o una resolución/compilación fallida no se acepta. El bloqueo de preparación se libera antes de ejecutar, permitiendo el linker recursivo. Once casos por copia, dos runners reales en frío/caliente con Pub inaccesible y revisión independiente correctos; la revisión comprobó también recursión sin bloqueo. La [CI completa](https://github.com/KaiCorpLabs/openward/actions/runs/43107533986) pasa sus 19 trabajos, incluida ejecución real de cmd en Windows; PR fusionada con el mismo árbol probado. |
| **IM-5** | [PR #30](https://github.com/KaiCorpLabs/openward/pull/30). Presupuesto acumulado de bytes, trabajo y archivos desde LevelDB hasta blobs, Snappy, V8 y el bundle final. Se contabilizan copias y referencias expandidas antes de reservar, y se limita tanto la profundidad del formato como la del árbol expandido. Las matrices excesivas se rechazan, sin truncar. El agotamiento aborta la importación, sin convertirlo en una advertencia parcial. Dos regresiones fallan en la base: matriz dispersa truncada y referencias poco profundas que producen árboles altos. Se prueban también bloques repetidos, prefijos compartidos, archivos/registros acumulados y cabeceras comprimidas enormes. La revisión señaló amplificación posterior por configuraciones compartidas: el padre la confirmó con una fixture acotada y extendió el mismo presupuesto a cada uso de texto/JSON y a los joins. La revisión se interrumpió por una restricción de herramienta antes del informe final; no se atribuye una revisión independiente limpia. Las fixtures válidas y clippy pasan. [CI exacta `fa04055`](https://github.com/KaiCorpLabs/openward/actions/runs/43107664701); el cierre exige sus 19 trabajos correctos y la fusión de #30. |
| **DA-7** | [PR #31](https://github.com/KaiCorpLabs/openward/pull/31). Lector por descriptor de archivo regular, límite de 1 MiB para metadatos públicos/certificados y límite previo de 64 KiB para claves privadas del gestor. La lectura sigue acotada si el archivo crece; en Unix abre sin bloquear y rechaza FIFO/dispositivos, conservando enlaces a archivos regulares. Inspección y extracción pública pasan a FFI asíncrona; el vault se libera antes de E/S. La interfaz representa carga/error y usa consultas con listas de certificados inmutables para evitar lecturas por redibujado. La regresión de comentario público de 2 MiB falla en la base y pasa corregida; FIFO, tamaños, alias y certificados normales pasan. Análisis, pruebas nativas/FFI y 312 Flutter correctos; revisión independiente sin hallazgos concretos. La primera integración Linux detectó una aserción antes de terminar la lectura asíncrona. Se espera al estado y a la huella visibles dentro del límite existente, conservando las comprobaciones de certificados e identidades. [CI exacta `dea5326`](https://github.com/KaiCorpLabs/openward/actions/runs/43112955785); el cierre exige sus 19 trabajos correctos y la fusión de #31. |
| **IM-6** | `no_change`: no se confirma una entrada ajena dentro del alcance. El selector/drop usa `detect::read`, que rechaza `ssh_config`; la importación OpenSSH del producto usa `sshConfigFileProvider=null` y el archivo propio del operador. Los importadores ajenos no rellenan las rutas de `known_hosts`. Las lecturas acumulativas de Include y de confianza siguen siendo una oportunidad de endurecimiento sobre configuración propia, sin atribuirles la autoridad de un archivo ajeno. Se conserva la regresión de S0 que rechaza un ssh_config extranjero disfrazado y acepta un CSV válido. |

Las garantías quedan limitadas al recorrido probado. No se acredita privacidad
por DACL de Windows, ausencia de ACL extendidas, ausencia general de carreras
remotas SFTP ni integridad de toda la cadena de build. Las fichas con hechos de
plataforma, UX o publicación pendientes conservan sus pruebas/contexto
solicitados. S3 y D3–D8 se siguen en el [estado del proyecto](estado.md).

## Fichas contrastadas

### Conexión y confianza SSH

#### CO-1 · Autoridad global de hosts introducida por una importación

**Confirmado · Vigente** · **Prioridad C1**. Gravedad original: Media.

Un bundle puede conservar un marcador @cert-authority y el patrón *. El importador persiste todos los known hosts, incluso al seleccionar solo algunos hosts; la comprobación posterior usa esas autoridades.

- **Condiciones e impacto:** Importación de un bundle controlado por un tercero; Conexión posterior a un host cubierto por el patrón. Confianza SSH ampliada silenciosamente; posible MITM y entrega de credenciales.
- **Controles y límites:** La validación rechaza espacios y saltos en campos, pero no impide el marcador ni limita la autoridad al host elegido.
- **Pendiente de prueba/contexto:** El impacto requiere importar el bundle y después conectar con un servidor cuya clave certifique esa CA; no se ha repetido la PoC histórica.
- **Siguiente paso:** Separar claves de host y autoridades; exigir consentimiento explícito, mostrar alcance y limitar las entradas a la selección importada.
- **Evidencia en main:** [core/crates/openward-proto/src/lib.rs:437-467](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-proto/src/lib.rs#L437-L467); [core/crates/openward-app/src/programs.rs:784-814](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/programs.rs#L784-L814); [core/crates/openward-ssh/src/known_hosts.rs:286-320](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/known_hosts.rs#L286-L320).

#### CO-2 · ACL del known_hosts global en Windows

**Necesita revisión · Pendiente de plataforma** · **Prioridad R1**. Gravedad original: Media.

Se lee PROGRAMDATA/ssh/ssh_known_hosts sin verificar propietario ni DACL.

- **Condiciones e impacto:** Windows; Otro usuario puede modificar la ruta global. Posible modificación de la confianza SSH entre usuarios.
- **Controles y límites:** La ruta global puede estar protegida por el sistema o el instalador. Leerla no demuestra que un usuario distinto pueda escribirla.
- **Pendiente de prueba/contexto:** Falta comprobar creación, propietario y DACL en Windows con una cuenta estándar y con OpenSSH instalado/no instalado.
- **Siguiente paso:** Documentar y verificar la propiedad de esa ruta; rechazar confianza global si su escritura no está restringida.
- **Evidencia en main:** [core/crates/openward-app/src/local.rs:40-47](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/local.rs#L40-L47); [core/crates/openward-app/src/connect.rs:168-175](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/connect.rs#L168-L175).

#### CO-3 · La firma RSA recibida no queda ligada a la política legacy

**Confirmado · Vigente** · **Prioridad C13**. Gravedad original: Baja.

host_key_order excluye ssh-rsa/SHA-1 al desactivar legacy, pero el tratamiento de la clave no comprueba el hash recibido. russh 0.64.1 verifica la firma decodificada sin compararla con el algoritmo negociado; su ssh-key activa sha1.

- **Condiciones e impacto:** Servidor que usa una clave RSA aceptada; Firma ssh-rsa recibida con legacy desactivado. Aceptación de un algoritmo que la configuración pretende deshabilitar.
- **Controles y límites:** No permite falsificar por sí solo una firma RSA ni omite la comprobación de confianza de la clave.
- **Pendiente de prueba/contexto:** No se ha repetido el intercambio de red histórico; el alcance confirmado es la falta de aplicación de la política de algoritmo.
- **Siguiente paso:** Comprobar el algoritmo de la firma frente al negociado y a legacy_host_keys, incluidos certificados; cubrir el rechazo de SHA-1.
- **Evidencia en main:** [core/crates/openward-ssh/src/client.rs:230-291](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/client.rs#L230-L291); [core/crates/openward-ssh/src/client.rs:552-564](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/client.rs#L552-L564).

#### CO-4 · Una codificación ECDSA equivalente evade la comparación de revocación

**Confirmado · Vigente** · **Prioridad C10**. Gravedad original: Baja.

La revocación compara KeyData por igualdad. ssh-key 0.7.0-rc.11 conserva EncodedPoint comprimido o sin comprimir, aunque ambos representan el mismo punto al verificar firmas.

- **Condiciones e impacto:** Clave ECDSA revocada; El servidor presenta la misma clave con otra codificación y satisface otra ruta de confianza. La revocación puede no reconocer una clave equivalente.
- **Controles y límites:** El cambio reciente del decodificador de escalares de claves privadas no normaliza las claves públicas usadas por known_hosts.
- **Pendiente de prueba/contexto:** La PoC de conexión no se ha repetido; la igualdad por representación y la aceptación de ambos formatos se observan en el código fijado.
- **Siguiente paso:** Comparar una representación canónica del punto público en confianza y revocación, sin alterar los controles de firma.
- **Evidencia en main:** [core/crates/openward-ssh/src/known_hosts.rs:248-269](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/known_hosts.rs#L248-L269).

#### CO-5 · La rotación no elimina todas las entradas de confianza anteriores

**Confirmado · Vigente** · **Prioridad C11**. Gravedad original: Baja.

trust_host_key elimina solo el host literal y algoritmo coincidentes, sin retirar equivalentes por patrón, hash o diferencias de representación. El comprobador admite cualquiera de las claves coincidentes.

- **Condiciones e impacto:** Rotación de una clave; Otra entrada coincidente conserva la clave anterior. La clave antigua puede seguir autenticando al servidor tras la rotación.
- **Controles y límites:** Retirar una entrada literal sí funciona; algunas entradas también proceden de archivos externos que el vault no debe modificar sin consentimiento.
- **Pendiente de prueba/contexto:** El riesgo depende de que permanezca una entrada antigua que también cubra el destino.
- **Siguiente paso:** Definir la semántica de sustituir/revocar una clave y advertir de las fuentes de confianza residuales antes de confirmar la rotación.
- **Evidencia en main:** [core/crates/openward-vault/src/lib.rs:738-778](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-vault/src/lib.rs#L738-L778); [core/crates/openward-ssh/src/known_hosts.rs:248-280](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/known_hosts.rs#L248-L280).

#### CO-6 · El fallo al guardar una clave aceptada permite un nuevo TOFU al reconectar

**Confirmado · Vigente** · **Prioridad C12**. Gravedad original: Baja.

La rama AcceptNew continúa aunque vault.trust_host_key falle; la siguiente conexión reconstruye la confianza desde el almacenamiento y no recuerda esa aceptación.

- **Condiciones e impacto:** Política Aceptar nuevas; Fallo al persistir la clave; Otra conexión con una clave distinta. Repetición silenciosa de la confianza inicial en lugar de fijar la primera clave.
- **Controles y límites:** Exige fallo de persistencia y otra conexión; las claves ya guardadas mantienen sus controles de Changed/Revoked.
- **Pendiente de prueba/contexto:** No se ha provocado un fallo de disco en esta revisión.
- **Siguiente paso:** Propagar el fallo de guardado o mantener un pin de sesión explícito y advertir antes de volver a aceptar otra clave.
- **Evidencia en main:** [core/crates/openward-app/src/connect.rs:259-265](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/connect.rs#L259-L265); [core/crates/openward-app/src/connect.rs:319-334](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/connect.rs#L319-L334).

#### CO-7 · Canal del agente en conexiones sin solicitud de forwarding de sesión

**Necesita revisión · Alcance por precisar** · **Prioridad R3**. Gravedad original: Baja.

El handler admite canales de agente cuando existe el socket configurado, sin registrar que esa sesión solicitara forwarding; la configuración también llega a conexiones usadas para SFTP.

- **Condiciones e impacto:** Forwarding del agente habilitado para el host; Servidor solicita el canal fuera de una sesión que lo pidió. Posible acceso al agente más amplio que la autorización de la sesión.
- **Controles y límites:** forward_agent es opt-in del operador y solo se entrega al último salto. Reutilizar una conexión con forwarding autorizado puede ser intencionado.
- **Pendiente de prueba/contexto:** Falta definir si la autorización del host cubre toda conexión o únicamente la sesión terminal que lo solicitó.
- **Siguiente paso:** Precisar el contrato y ligar la aceptación del canal a una solicitud autorizada si el alcance es por sesión.
- **Evidencia en main:** [core/crates/openward-app/src/connect.rs:270-278](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/connect.rs#L270-L278); [core/crates/openward-ssh/src/client.rs:344-360](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/client.rs#L344-L360).

#### CO-8 · Preguntas keyboard-interactive con identidad remota poco diferenciada

**Necesita revisión · Pendiente de UX** · **Prioridad R10**. Gravedad original: Baja.

El servidor controla título, instrucciones y preguntas mostradas en la tarjeta.

- **Condiciones e impacto:** Servidor SSH hostil; El usuario interpreta la pregunta como local. Posible entrega de un secreto ajeno a esa autenticación.
- **Controles y límites:** La tarjeta también muestra usuario y host. No existe todavía el diálogo de desbloqueo del vault cifrado que presupone parte del escenario futuro.
- **Pendiente de prueba/contexto:** Falta validar que la presentación permite confundir una pregunta remota con una solicitud local en el flujo actual.
- **Siguiente paso:** Marcar siempre el origen remoto y separar visualmente autenticación SSH y cualquier futuro desbloqueo local.
- **Evidencia en main:** [app/lib/tabs/prompt_card.dart:60-74](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/tabs/prompt_card.dart#L60-L74); [app/lib/tabs/prompt_card.dart:157-171](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/tabs/prompt_card.dart#L157-L171).

#### CO-9 · Otros controles de conexión pendientes de contraste

**Necesita revisión · Observaciones mixtas** · **Prioridad R11**. Gravedad original: Informativa.

Se conservan las observaciones sobre canales descartados por los handlers por defecto, opciones críticas de certificados, strict KEX/Terrapin, loopback multiusuario, proxies Basic/SOCKS y oferta de identidades. El CONNECT interpola host sin validar CR/LF.

- **Condiciones e impacto:** Configuraciones de certificados, proxy o entorno local específicas. Riesgos condicionados de interpretación y alcance de confianza.
- **Controles y límites:** Los canales por defecto no conectan a un recurso local; strict KEX está habilitado; Basic/SOCKS y ofrecer claves del agente forman parte del transporte/configuración elegidos.
- **Pendiente de prueba/contexto:** Faltan un certificado con opción crítica relevante y un caso de proxy que demuestren el efecto de las entradas, además del modelo de exposición de loopback.
- **Siguiente paso:** Revisar por separado opciones críticas y framing de CONNECT; mantener los demás puntos como límites documentados, sin atribuirles una explotación conjunta.
- **Evidencia en main:** [core/crates/openward-ssh/src/known_hosts.rs:312-320](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/known_hosts.rs#L312-L320); [core/crates/openward-ssh/src/proxy.rs:85-102](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ssh/src/proxy.rs#L85-L102).

### Importadores

#### IM-1 · Los túneles importados conservan autostart

**Confirmado · Mitigación parcial** · **Prioridad C3**. Gravedad original: Media.

hold_back elimina binds no loopback, pero no modifica autostart. Un túnel remoto importado puede exponer automáticamente un servicio local al servidor al conectar.

- **Condiciones e impacto:** Importación de túneles controlados por un tercero; Conexión al host importado; Servicio local alcanzable desde el túnel. Exposición no consentida de servicios locales.
- **Controles y límites:** La exposición por bind 0.0.0.0 de la versión inicial está mitigada. Eso no neutraliza los túneles remotos ni el arranque automático.
- **Pendiente de prueba/contexto:** No se han abierto túneles de prueba; la configuración y su persistencia siguen trazables en código.
- **Siguiente paso:** Importar todos los túneles desactivados y mostrar dirección, destino y arranque antes de habilitarlos.
- **Evidencia en main:** [core/crates/openward-import/src/bundle.rs:298-328](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/bundle.rs#L298-L328); [core/crates/openward-import/src/detect.rs:135-138](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/detect.rs#L135-L138); [core/crates/openward-app/src/programs.rs:739-768](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/programs.rs#L739-L768).

#### IM-2 · El forwarding de agente importado se retiene desactivado

**No accionable en el alcance actual · Corregido en la ruta de producto**. Gravedad original: Baja.

El paso común de importación transforma forward_agent=true en None tanto en grupos como en hosts y añade aviso.

- **Condiciones e impacto:** Ruta de importación utilizada por la aplicación. La activación silenciosa descrita inicialmente ya está bloqueada.
- **Controles y límites:** No elimina una configuración de forwarding que el operador ya hubiera autorizado por otra vía; esa herencia no procede del archivo importado.
- **Pendiente de prueba/contexto:** No se han ejecutado pruebas nuevas de importación.
- **Siguiente paso:** Mantener este control común y su cobertura; no reabrir el caso solo porque existan lectores internos de formato.
- **Evidencia en main:** [core/crates/openward-import/src/bundle.rs:298-313](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/bundle.rs#L298-L313); [core/crates/openward-import/src/detect.rs:135-138](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/detect.rs#L135-L138).

#### IM-3 · ProxyCommand de un ssh_config ajeno llega activo sin vista previa suficiente

**Confirmado · Vigente** · **Prioridad C5**. Gravedad original: Baja.

El lector admite ProxyCommand y el flujo de importación de un archivo seleccionado conserva esa configuración sin una confirmación que muestre la orden completa.

- **Condiciones e impacto:** Importación de un ssh_config ajeno; Conexión posterior al host. Ejecución local de la orden configurada por el archivo.
- **Controles y límites:** El ssh_config propio del operador es configuración confiable según el modelo; el caso es un archivo ajeno elegido para importar. Los comandos de otros formatos se retienen como avisos.
- **Pendiente de prueba/contexto:** Exige conectar al host importado; no se ha ejecutado una orden de prueba.
- **Siguiente paso:** Retener ProxyCommand de archivos ajenos como dato inactivo hasta una autorización explícita que muestre la orden.
- **Evidencia en main:** [core/crates/openward-import/src/ssh_config.rs:430-449](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/ssh_config.rs#L430-L449); [core/crates/openward-app/src/programs.rs:739-768](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/programs.rs#L739-L768); [app/lib/import/programs.dart:39-51](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/import/programs.dart#L39-L51).

#### IM-4 · Snippets importados y ejecución con contenido fuera de la vista previa

**Confirmado · Vigente** · **Prioridad C9**. Gravedad original: Baja.

Se importan todos los snippets. La paleta muestra su primera línea; una ejecución simple no exige revisar el resto ni distingue su origen importado.

- **Condiciones e impacto:** Snippet de un archivo ajeno; Selección posterior en la paleta. Ejecución de órdenes adicionales que no aparecen en la vista previa.
- **Controles y límites:** No se ejecutan todos al importar: el usuario debe seleccionar un snippet. La elección pierde valor si el contenido ejecutado queda oculto.
- **Pendiente de prueba/contexto:** No se ha ejecutado ningún snippet.
- **Siguiente paso:** Seleccionar los snippets a importar y exigir una primera revisión completa antes de ejecutar contenido importado.
- **Evidencia en main:** [core/crates/openward-app/src/programs.rs:772-782](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/programs.rs#L772-L782); [core/crates/openward-import/src/termius/model.rs:458-467](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/termius/model.rs#L458-L467); [app/lib/palette/command_palette.dart:517-527](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/palette/command_palette.dart#L517-L527).

#### IM-5 · Amplificación de memoria al interpretar datos de Termius

**Confirmado · Vigente** · **Prioridad C20**. Gravedad original: Baja (la app se cae).

Referencias V8 clonadas en profundidad, arrays dispersos y acumulación de bloques LevelDB permiten que datos pequeños provoquen mucho más trabajo y memoria que su tamaño de entrada.

- **Condiciones e impacto:** Importación de un directorio Termius preparado. Agotamiento de memoria de la aplicación durante una importación.
- **Controles y límites:** Existen límites de 64 MiB y profundidad, pero son por archivo/bloque y no un presupuesto de objetos, clonaciones y resultado total.
- **Pendiente de prueba/contexto:** No se repiten las medidas de memoria o caída de la PoC original.
- **Siguiente paso:** Aplicar presupuestos globales de objetos, elementos, bytes expandidos y trabajo; evitar clonar grafos completos al resolver referencias.
- **Evidencia en main:** [core/crates/openward-import/src/termius/v8.rs:143-191](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/termius/v8.rs#L143-L191); [core/crates/openward-import/src/termius/leveldb.rs:197-265](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/termius/leveldb.rs#L197-L265).

#### IM-6 · Include y lecturas de confianza sin presupuesto total de trabajo

**Confirmado · Vigente** · **Prioridad C21**. Gravedad original: Baja (la app se cuelga).

Include limita profundidad pero no archivos visitados ni expansiones repetidas; los glob ** y el abanico de includes multiplican trabajo. Las lecturas de known_hosts de conexión no usan el lector de archivos acotado del importador.

- **Condiciones e impacto:** Configuración ajena con includes expansivos o rutas especiales. Bloqueo o consumo de recursos al importar o preparar una conexión.
- **Controles y límites:** Una profundidad máxima evita recursión infinita simple. El ssh_config propio pertenece al ámbito confiable; el archivo ajeno importado sigue siendo una entrada admitida.
- **Pendiente de prueba/contexto:** No se han medido tiempos ni bloqueado la interfaz en esta revisión.
- **Siguiente paso:** Limitar bytes y archivos totales, deduplicar includes y rechazar archivos especiales en todas las lecturas de configuración/confianza.
- **Evidencia en main:** [core/crates/openward-import/src/ssh_config.rs:440-449](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/ssh_config.rs#L440-L449); [core/crates/openward-import/src/ssh_config.rs:716-729](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/ssh_config.rs#L716-L729); [core/crates/openward-app/src/connect.rs:168-175](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/connect.rs#L168-L175).

#### IM-7 · Termius detectado automáticamente y acceso al llavero

**Necesita revisión · Pendiente de consentimiento** · **Prioridad R15**. Gravedad original: Informativa.

El aviso explícito de Termius depende del programa elegido; la autodetección puede reconocerlo y pasar a leer su llavero antes de ese aviso específico.

- **Condiciones e impacto:** Autodetección de datos Termius; Acceso al llavero disponible. Lectura de material de descifrado sin el aviso específico esperado.
- **Controles y límites:** El usuario ya ha pedido importar una ruta, y el sistema puede añadir un diálogo de acceso al llavero.
- **Pendiente de prueba/contexto:** Falta precisar si ese consentimiento general basta y comprobar la interacción nativa de cada plataforma.
- **Siguiente paso:** Aplicar el consentimiento tras detectar el formato y antes de acceder al llavero, si se exige autorización específica.
- **Evidencia en main:** [app/lib/import/programs.dart:38-51](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/import/programs.dart#L38-L51); [core/crates/openward-import/src/detect.rs:135-146](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/detect.rs#L135-L146).

### Datos y claves

#### DA-1 · La carpeta de datos es privada por defecto, con fallos de chmod ignorados

**Necesita revisión · Mitigación parcial** · **Prioridad R2**. Gravedad original: Media.

create_private_dir crea el directorio con 0700 y trata de endurecer uno existente, pero ignora el error de set_permissions. Algunos JSON se crean con permisos ordinarios dentro de esa carpeta.

- **Condiciones e impacto:** Directorio de datos existente o personalizado; Permisos amplios y endurecimiento fallido. Posible lectura entre usuarios de historial, ajustes y metadatos.
- **Controles y límites:** La afirmación de que el directorio normal siempre sale en 0755 ha quedado obsoleta. Un directorio 0700 propio protege también esos JSON 0644.
- **Pendiente de prueba/contexto:** Falta validar rutas compartidas/personalizadas, propietario ajeno y fallos de permisos; no está demostrado que un usuario estándar pueda leer el directorio normal.
- **Siguiente paso:** Fallar o advertir si no se puede garantizar la privacidad del directorio y comprobar su propiedad; verificar también instalaciones existentes.
- **Evidencia en main:** [core/crates/openward-app/src/lib.rs:1239-1256](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/lib.rs#L1239-L1256); [app/lib/core/json_file.dart:28-32](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/core/json_file.dart#L28-L32).

#### DA-2 · Backup de migración: ruta latente que debe endurecerse

**Ruta sustituida en D3 (2026-11-12); sin migración automática desde la app**. Gravedad original: Baja hoy (`STEPS` está vacío); Media con la primera migración real (D3).

La copia VACUUM INTO no aplica permisos ni política de eliminación específicos.

- **Condiciones e impacto:** Una futura migración activa la ruta de backup. Riesgo futuro de conservar una copia clara con protección insuficiente.
- **Controles y límites:** STEPS está vacío y el formato distribuido no alcanza hoy una migración que ejecute esa copia; el directorio de datos propio es 0700. No es una fuga activa demostrada en esta versión.
- **Pendiente de prueba/contexto:** Se debe volver a evaluar al añadir la primera migración real y el cifrado D3.
- **Resultado D3:** Se elimina la ruta de producción `VACUUM INTO`/backup claro. La nueva migración prepara solo ciphertext en un archivo 0600, verifica cada fila/metadato y reemplaza atómicamente tras cerrar/checkpointar la fuente y sus sidecars. Pruebas con WAL/PERSIST pendientes, freelist, aliases, fallos e interrupciones comprueban recuperación y ausencia del marcador claro en los archivos gestionados.
- **Límites vigentes:** Las copias externas previas, snapshots y bloques SSD no se borran con esta operación. ACL extendidas/DACL conservan su seguimiento de plataforma. La app activa esta API en D4/D5; el formato distribuido de la beta sigue siendo 1. [Contrato, comandos y evidencia](../../spec/vault-sqlite-v2.md).
- **Evidencia en main:** [core/crates/openward-vault/src/store.rs:18-18](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-vault/src/store.rs#L18); [core/crates/openward-vault/src/store.rs:73-83](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-vault/src/store.rs#L73-L83); [core/crates/openward-vault/src/store.rs:124-133](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-vault/src/store.rs#L124-L133).

#### DA-3 · Una clave pública con comentario multilínea instala líneas adicionales

**Confirmado · Vigente** · **Prioridad C6**. Gravedad original: Baja.

public_line conserva el comentario aceptado por ssh-key y with_authorized añade la cadena completa. El parser y serializador fijados de ssh-key permiten saltos internos en ese comentario.

- **Condiciones e impacto:** Clave pública o comentario suministrado por un tercero; El usuario instala esa clave. Instalación de una segunda clave de acceso no revisada.
- **Controles y límites:** El transporte SFTP evita una inyección de shell, pero no limita la operación a una única clave autorizada.
- **Pendiente de prueba/contexto:** No se ha repetido la instalación de la PoC histórica.
- **Siguiente paso:** Exigir exactamente una clave pública y una sola línea en el límite install_public_key; sanear controles en comentarios al importar y escribir claves.
- **Evidencia en main:** [core/crates/openward-app/src/keychain.rs:553-592](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/keychain.rs#L553-L592); [core/crates/openward-app/src/sftp.rs:149-164](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/sftp.rs#L149-L164).

#### DA-4 · Variables automáticas de snippets sustituidas como texto de shell

**Confirmado · Vigente** · **Prioridad C7**. Gravedad original: Baja.

Nombre, dirección y usuario del host se insertan literalmente en el comando; también pueden proceder de datos importados. El arranque de snippets reutiliza esa sustitución.

- **Condiciones e impacto:** Host o etiqueta importados; Snippet que interpola ese valor; Ejecución posterior. Órdenes adicionales por interpretación de datos como sintaxis de shell.
- **Controles y límites:** Los valores escritos por el operador son configuración confiable y existen confirmaciones para ciertas ejecuciones, pero una ejecución simple no revisa necesariamente el comando final.
- **Pendiente de prueba/contexto:** No se ha ejecutado un payload; el tratamiento correcto depende además del contexto sintáctico del shell.
- **Siguiente paso:** Mostrar el comando renderizado y diseñar sustitución tipada/escapado según contexto; no aplicar una comilla genérica que rompa otros contextos.
- **Evidencia en main:** [core/crates/openward-app/src/snippets.rs:84-99](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/snippets.rs#L84-L99); [app/lib/snippets/snippets.dart:55-104](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/snippets/snippets.dart#L55-L104).

#### DA-5 · Cobertura incompleta del borrado de secretos en memoria

**No accionable en el alcance actual · Endurecimiento D6 pendiente**. Gravedad original: Baja.

Persisten Strings y buffers de claves/descifrado sin Zeroizing en parte del recorrido FFI e importador.

- **Condiciones e impacto:** Acceso a memoria del proceso o futura ampliación del modelo. Permanencia de material sensible en memoria más tiempo del necesario.
- **Controles y límites:** El modelo excluye malware y programas del mismo UID que inspeccionan memoria. Otras rutas sí usan Zeroizing; no se identifica aquí una lectura de memoria por un actor admitido.
- **Pendiente de prueba/contexto:** No hay evidencia de un canal adicional de exposición. No se considera corregido.
- **Siguiente paso:** Conservar AM4/D6: inventariar copias y poner a cero buffers cuando se implemente el manejo completo de secretos.
- **Evidencia en main:** [core/crates/openward-ffi/src/api/keychain.rs:141-193](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ffi/src/api/keychain.rs#L141-L193); [core/crates/openward-import/src/termius/crypto.rs:1-79](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-import/src/termius/crypto.rs#L1-L79).

#### DA-6 · Exportación de claves sin garantía comprobada de permisos finales

**Necesita revisión · Pendiente de plataforma** · **Prioridad R5**. Gravedad original: Baja.

El flujo copia el archivo y después solicita chmod 600 sin comprobar su resultado; en Windows no aplica esa operación.

- **Condiciones e impacto:** Exportación a un destino cuya protección no está garantizada. Posible archivo de clave más accesible de lo esperado.
- **Controles y límites:** El resultado de File.copy depende de permisos del origen, destino, sistema de archivos y ACL. El usuario elige dónde exportar.
- **Pendiente de prueba/contexto:** Faltan pruebas de modo/ACL resultantes y tratamiento del fallo en macOS, Linux y Windows.
- **Siguiente paso:** Crear el destino de forma privada desde el inicio y comprobar permisos/ACL y errores antes de anunciar éxito.
- **Evidencia en main:** [app/lib/keys/key_actions.dart:40-50](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/keys/key_actions.dart#L40-L50).

#### DA-7 · Certificados leídos sin límite desde una llamada síncrona de la interfaz

**Confirmado · Vigente; impacto de disponibilidad** · **Prioridad C22**. Gravedad original: Informativa.

key_info usa Certificate::read_file sobre rutas configurables sin verificar archivo normal ni tamaño. identities y key_info están expuestas con frb(sync).

- **Condiciones e impacto:** Configuración ajena con CertificateFile hacia un archivo especial o enorme; Consulta de identidades. Bloqueo o agotamiento de recursos de la interfaz.
- **Controles y límites:** Las lecturas de clave de otras rutas sí están acotadas; ese control no cubre la lectura del certificado. No se afirma ejecución de código.
- **Pendiente de prueba/contexto:** No se ha abierto un FIFO ni medido un bloqueo; el recorrido síncrono y la lectura sin cota son estáticos.
- **Siguiente paso:** Usar el lector acotado de archivos normales también para certificados y sacar la E/S del recorrido síncrono de la interfaz.
- **Evidencia en main:** [core/crates/openward-app/src/keys.rs:82-90](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/keys.rs#L82-L90); [core/crates/openward-ffi/src/api/identities.rs:242-248](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ffi/src/api/identities.rs#L242-L248); [core/crates/openward-ffi/src/api/identities.rs:280-284](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ffi/src/api/identities.rs#L280-L284).

#### DA-8 · Alcance de la advertencia sobre datos claros

**No accionable en el alcance actual · Documentado**. Gravedad original: Informativa.

SECURITY.md enlaza al modelo, que enumera vault, historial, recientes, ajustes y registros todavía claros, con sus permisos.

- **Condiciones e impacto:** Uso actual de la beta sin cifrado completo. Límite de confidencialidad documentado; no una omisión vigente demostrada.
- **Controles y límites:** La frase breve sobre el vault no sustituye ese inventario. Los snippets/notas pueden contener texto sensible elegido por el usuario.
- **Pendiente de prueba/contexto:** No se ha vuelto a buscar secretos en el historial completo del repositorio.
- **Siguiente paso:** Mantener sincronizados ambos documentos conforme avance el cifrado y conservar advertencias sobre los datos claros de la beta.
- **Evidencia en main:** [SECURITY.md:1-23](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/SECURITY.md#L1-L23); [docs/THREAT_MODEL.md:1-140](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/docs/THREAT_MODEL.md#L1-L140).

#### DA-9 · Nombres literales de claves que contienen %

**No accionable en el alcance actual · Deuda de corrección**. Gravedad original: Informativa.

Los nombres enumerados y su posterior paso por expansión de tokens pueden discrepar cuando el nombre contiene %. Puede seleccionarse otro archivo del área de claves.

- **Condiciones e impacto:** Archivos con nombres especiales dentro de ~/.ssh. Acción sobre un archivo distinto del mostrado en un escenario local condicionado.
- **Controles y límites:** Las operaciones destructivas están limitadas a ~/.ssh y el escenario original exige que otro proceso del mismo UID prepare esos archivos, actor excluido.
- **Pendiente de prueba/contexto:** No se demuestra un cruce de privilegios con entradas admitidas.
- **Siguiente paso:** Separar rutas ya resueltas de expresiones con tokens para evitar operar sobre una clave distinta; no presentarlo como una vulnerabilidad corregida.
- **Evidencia en main:** [core/crates/openward-app/src/keychain.rs:206-236](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/keychain.rs#L206-L236); [core/crates/openward-app/src/local.rs:60-86](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/local.rs#L60-L86).

### SFTP y terminal local

#### SF-1 · Descargas que siguen enlaces locales en directorios y archivos .part

**Confirmado · Vigente** · **Prioridad C2**. Gravedad original: Media.

La comprobación de directorios sigue symlinks y la apertura del temporal no usa una defensa equivalente a NOFOLLOW/EXCL. Un .part existente se abre para escritura y ajuste de tamaño.

- **Condiciones e impacto:** Destino local o ancestro modificable por otro usuario; Enlace preparado antes o durante la descarga. Sobrescritura de archivos del usuario fuera del destino autorizado.
- **Controles y límites:** El nombre propio del temporal limita colisiones accidentales, pero no autentica su propietario. La seguridad de nombres remotos no impide seguir enlaces ya presentes localmente.
- **Pendiente de prueba/contexto:** Requiere un destino compartido modificable por otro usuario; las protecciones de symlinks varían entre sistemas. No se ha repetido la PoC.
- **Siguiente paso:** Anclar operaciones al directorio de destino y abrir sin seguir enlaces, verificar propietario/tipo y usar temporales creados exclusivamente.
- **Evidencia en main:** [core/crates/openward-sftp/src/local.rs:37-48](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/local.rs#L37-L48); [core/crates/openward-sftp/src/transfer.rs:1066-1075](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L1066-L1075); [core/crates/openward-sftp/src/transfer.rs:1134-1155](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L1134-L1155).

#### SF-2 · La descarga de un enlace usa permisos del enlace en lugar del destino

**Confirmado · Vigente** · **Prioridad C14**. Gravedad original: Baja.

follow_links actualiza tipo y tamaño, pero no modo/fecha. La transferencia conserva ese modo y lo aplica al archivo local del destino del enlace.

- **Condiciones e impacto:** Descarga de un enlace remoto a un archivo con permisos restrictivos. Archivo local con lectura o ejecución más amplia que el origen efectivo.
- **Controles y límites:** Las rutas de descarga directa de un archivo normal no pasan por esta discrepancia.
- **Pendiente de prueba/contexto:** No se han descargado archivos en esta revisión.
- **Siguiente paso:** Recoger los atributos efectivos del destino al seguir un enlace y aplicar una política de permisos locales que no amplíe acceso.
- **Evidencia en main:** [core/crates/openward-sftp/src/remote.rs:150-187](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/remote.rs#L150-L187); [core/crates/openward-sftp/src/transfer.rs:841-846](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L841-L846); [core/crates/openward-sftp/src/transfer.rs:1187-1197](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L1187-L1197).

#### SF-3 · Permisos de directorios no conservados en transferencias

**Confirmado · Vigente** · **Prioridad C15**. Gravedad original: Baja.

Los directorios nuevos se crean con los valores por defecto del destino, sin reproducir el modo restrictivo de la carpeta origen.

- **Condiciones e impacto:** Transferencia de un directorio restrictivo con archivos de modo más amplio. Pérdida de la restricción de acceso que imponía la carpeta.
- **Controles y límites:** Los permisos de cada archivo y la umask del destino pueden reducir el impacto, pero no preservan la barrera de un directorio 0700 con archivos legibles.
- **Pendiente de prueba/contexto:** No se ha comprobado una umask específica de plataforma.
- **Siguiente paso:** Crear directorios restrictivos y aplicar sus permisos finales al terminar, en ambas direcciones.
- **Evidencia en main:** [core/crates/openward-sftp/src/transfer.rs:949-949](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L949); [core/crates/openward-sftp/src/transfer.rs:1066-1075](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L1066-L1075).

#### SF-4 · Conservación de bits especiales durante la subida

**Necesita revisión · Pendiente del servidor** · **Prioridad R9**. Gravedad original: Baja.

Los atributos enviados conservan bits de modo hasta 07777, incluidos setuid, setgid y sticky.

- **Condiciones e impacto:** Origen con bits especiales; Servidor que permite conservarlos con efectos relevantes. Posible efecto de permisos no deseado en el destino.
- **Controles y límites:** La asignación de propietario y la preservación efectiva de esos bits dependen del servidor, del sistema de archivos y de los permisos de la cuenta.
- **Pendiente de prueba/contexto:** Enviar el bit no prueba por sí solo una elevación de privilegios. Falta un escenario con privilegios separados.
- **Siguiente paso:** Definir una política explícita de bits especiales y limpiarlos por defecto salvo preservación consentida.
- **Evidencia en main:** [core/crates/openward-sftp/src/remote.rs:365-380](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/remote.rs#L365-L380).

#### SF-5 · Subida recursiva de enlaces a archivos fuera del origen

**Confirmado · Vigente** · **Prioridad C4**. Gravedad original: Baja.

El recorrido local y la apertura de archivos siguen enlaces a archivos aunque el destino resuelto quede fuera de la carpeta seleccionada.

- **Condiciones e impacto:** Carpeta ajena extraída o recibida con symlinks; Subida recursiva al servidor. Envío de archivos privados situados fuera de la selección.
- **Controles y límites:** No se siguen del mismo modo todos los enlaces a carpetas. La selección de una carpeta no muestra cada destino de enlace a archivo.
- **Pendiente de prueba/contexto:** No se ha exfiltrado ningún archivo de prueba.
- **Siguiente paso:** No seguir enlaces por defecto en subidas recursivas o pedir autorización con destino resuelto; imponer confinamiento al origen seleccionado.
- **Evidencia en main:** [core/crates/openward-sftp/src/local.rs:116-136](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/local.rs#L116-L136); [core/crates/openward-sftp/src/transfer.rs:1000-1025](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L1000-L1025).

#### SF-6 · Nombres Unix ambiguos al subir a un servidor Windows

**Necesita revisión · Pendiente de plataforma** · **Prioridad R7**. Gravedad original: Baja.

Un cliente Unix puede aportar nombres con barra inversa o dos puntos que una implementación SFTP de Windows interprete de forma especial.

- **Condiciones e impacto:** Cliente Unix; Servidor Windows con interpretación especial de esos nombres. Posible destino distinto del nombre mostrado.
- **Controles y límites:** Las comprobaciones locales de Windows no describen necesariamente la semántica del servidor remoto; no todos los servidores normalizan igual.
- **Pendiente de prueba/contexto:** Falta validar servidores Windows concretos y si permiten separadores alternativos o ADS en esa ruta.
- **Siguiente paso:** Validar según la semántica del destino y rechazar nombres ambiguos antes de transferir.
- **Evidencia en main:** [core/crates/openward-sftp/src/transfer.rs:827-837](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L827-L837).

#### SF-7 · Nombres reservados de Windows en descargas

**Necesita revisión · Pendiente de plataforma** · **Prioridad R8**. Gravedad original: Baja.

local_join rechaza separadores y dos puntos, pero no expresa un control para CON/NUL y nombres terminados en punto o espacio.

- **Condiciones e impacto:** Descarga en Windows; Nombre remoto reservado o ambiguo. Colisión, fallo o acceso a un destino inesperado condicionado por plataforma.
- **Controles y límites:** El comportamiento real también depende de las rutas verbatim usadas por Rust y del sistema de archivos.
- **Pendiente de prueba/contexto:** No se ha validado la creación/apertura nativa en Windows; no se afirma escritura a dispositivos como resultado probado.
- **Siguiente paso:** Verificar las APIs reales y rechazar los nombres que no tengan una representación inequívoca en el destino.
- **Evidencia en main:** [core/crates/openward-sftp/src/transfer.rs:827-837](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L827-L837).

#### SF-8 · La descarga ordinaria no marca el origen del archivo

**Necesita revisión · Mitigación parcial** · **Prioridad R4**. Gravedad original: Baja.

La descarga ordinaria sigue aplicando el modo sin una marca explícita de origen o una retirada general del bit ejecutable.

- **Condiciones e impacto:** Archivo remoto descargado; Apertura posterior mediante aplicaciones del sistema. Posible menor advertencia de procedencia al abrir contenido remoto.
- **Controles y límites:** El flujo de Abrir/edición remota incorpora controles de cuarentena, ejecutables y nombres invisibles. Ese arreglo no equivale a marcar toda descarga.
- **Pendiente de prueba/contexto:** Falta comprobar el efecto real de Gatekeeper/SmartScreen y de cada sistema de archivos. No se declara un bypass general validado.
- **Siguiente paso:** Definir y comprobar la política de origen de las descargas ordinarias y armonizarla con el flujo Abrir.
- **Evidencia en main:** [core/crates/openward-sftp/src/transfer.rs:1187-1197](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/transfer.rs#L1187-L1197); [app/lib/sftp/open_safety.dart:1-120](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/sftp/open_safety.dart#L1-L120).

#### SF-9 · El diálogo de permisos pierde bits especiales y usa el modo de un enlace

**Confirmado · Vigente** · **Prioridad C16**. Gravedad original: Baja.

El diálogo recorta el modo a 0777; un enlace puede presentarse como 0777 mientras setstat actúa sobre su destino. La operación puede retirar sticky/setgid o ampliar permisos del destino.

- **Condiciones e impacto:** Cambio de permisos de una carpeta con bits especiales o de un symlink. Permisos del objeto efectivo diferentes de lo mostrado o esperado.
- **Controles y límites:** El usuario confirma un cambio de permisos, pero la pantalla no conserva ni representa todos los bits/objeto sobre los que opera.
- **Pendiente de prueba/contexto:** No se ha cambiado ningún permiso remoto durante la revisión.
- **Siguiente paso:** Preservar o mostrar los bits especiales y resolver explícitamente el objeto efectivo antes de editar permisos de un enlace.
- **Evidencia en main:** [app/lib/sftp/dialogs.dart:357-389](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/sftp/dialogs.dart#L357-L389); [core/crates/openward-sftp/src/remote.rs:328-380](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/remote.rs#L328-L380).

#### SF-10 · Operaciones recursivas y sustitución de enlaces entre comprobación y uso

**Necesita revisión · Carrera pendiente de validación** · **Prioridad R6**. Gravedad original: Baja.

El borrado/chmod recursivo comprueba el tipo antes de abrir o recorrer el nombre; entre ambas operaciones otro usuario del servidor puede sustituirlo.

- **Condiciones e impacto:** Árbol remoto compartido; Otro usuario sustituye una entrada durante la recursión. Posible operación fuera del subárbol aprobado.
- **Controles y límites:** La aplicación evita seguir enlaces observados durante la comprobación. El efecto final de la carrera depende de la implementación SFTP y sus permisos.
- **Pendiente de prueba/contexto:** Falta una reproducción con servidor y árbol compartido concretos; no se ha probado borrado fuera del origen.
- **Siguiente paso:** Preferir operaciones ancladas a handles/directorios y definir cómo abortar ante cambios; validar una carrera antes de asignar impacto definitivo.
- **Evidencia en main:** [core/crates/openward-sftp/src/remote.rs:309-360](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/remote.rs#L309-L360).

#### SF-11 · Límites frente a un servidor SFTP que agota recursos

**No accionable en el alcance actual · Disponibilidad fuera del modelo actual**. Gravedad original: Baja (la app se cae).

Persisten presupuestos incompletos de listados y recorrido. La descarga sí programa peticiones hasta end: se retira la afirmación absoluta de que ignora el tamaño anunciado.

- **Condiciones e impacto:** Servidor SFTP hostil. Agotamiento de recursos, excluido del alcance de seguridad acordado.
- **Controles y límites:** El modelo excluye expresamente que el servidor hostil deniegue servicio o llene disco. No se atribuye aquí una nueva lectura/escritura fuera de autorización.
- **Pendiente de prueba/contexto:** No se repiten cifras de consumo de la prueba original ni se afirma protección total.
- **Siguiente paso:** Mantener como robustez límites de entradas, profundidad, bytes y respuestas; volver a priorizar si se amplía el modelo de disponibilidad.
- **Evidencia en main:** [core/crates/openward-sftp/src/pipe.rs:110-166](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/pipe.rs#L110-L166); [core/crates/openward-sftp/src/remote.rs:110-149](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/remote.rs#L110-L149).

#### SF-12 · Otras observaciones de SFTP y terminal local

**No accionable en el alcance actual · Límites y robustez documentables**. Gravedad original: Informativa.

Se conservan tres observaciones: escritura intencional a través de enlaces remotos, sustitución del enlace authorized_keys al instalar una clave y asignaciones en pre_exec de portable-pty.

- **Condiciones e impacto:** Configuración local o enlaces remotos gestionados por el operador. Diferencias de semántica y posibles problemas de robustez.
- **Controles y límites:** La primera es una decisión de comportamiento; la segunda escribe el archivo administrado; la tercera es un riesgo de bloqueo sin un cruce de confianza demostrado en este caso.
- **Pendiente de prueba/contexto:** No se ha demostrado un acceso adicional de un actor del modelo ni un bloqueo reproducible.
- **Siguiente paso:** Documentar la semántica de enlaces y estudiar la robustez de pre_exec separadamente, sin presentarlos como fallos explotables confirmados.
- **Evidencia en main:** [core/crates/openward-app/src/sftp.rs:149-164](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/sftp.rs#L149-L164); [core/crates/openward-sftp/src/remote.rs:328-380](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-sftp/src/remote.rs#L328-L380).

### Registros e historial

#### RG-1 · El espacio inicial no excluye del historial una línea editada

**Confirmado · Vigente** · **Prioridad C17**. Gravedad original: Baja.

El camino sin edición comprueba el espacio inicial, pero el editado obtiene el texto reconstruido y lo recorta, perdiendo ese indicador de exclusión.

- **Condiciones e impacto:** Comando con espacio inicial; Edición de la línea antes de enviarla. Persistencia de un comando que el usuario pretendía excluir.
- **Controles y límites:** No se guardan teclas de contraseña por esta vía y el caso sin edición sí aplica la regla.
- **Pendiente de prueba/contexto:** No se han escrito comandos de prueba; AM7 continúa en D6.
- **Siguiente paso:** Conservar el indicador de no registrar antes de cualquier trim/reconstrucción y aplicarlo a historial y marcadores del registro.
- **Evidencia en main:** [app/lib/history/line_tracker.dart:125-165](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/history/line_tracker.dart#L125-L165).

#### RG-2 · Alcance temporal de la pausa de grabación

**Necesita revisión · Casos límite pendientes** · **Prioridad R12**. Gravedad original: Baja.

La salida comprueba paused y los marcadores comprueban el estado al emitirse; una línea empezada durante la pausa puede finalizar después. Redibujos y reconexiones necesitan un contrato explícito.

- **Condiciones e impacto:** Pausa durante la composición de una línea o reconexión/redibujo posterior. Posible persistencia posterior de texto asociado al intervalo pausado.
- **Controles y límites:** La pausa sí bloquea la salida mientras está activa. No equivale a borrar texto que el servidor vuelva a mostrar tras reanudar.
- **Pendiente de prueba/contexto:** Falta validar el seguimiento de líneas y estado al pausar/reanudar/reconectar; no se afirma que toda pausa falle.
- **Siguiente paso:** Definir la expectativa y descartar el seguimiento iniciado durante la pausa si el contrato requiere excluirlo por completo.
- **Evidencia en main:** [core/crates/openward-app/src/logs/recorder.rs:119-124](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/recorder.rs#L119-L124); [core/crates/openward-app/src/logs/recorder.rs:168-175](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/recorder.rs#L168-L175); [app/lib/history/line_tracker.dart:125-165](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/history/line_tracker.dart#L125-L165).

#### RG-3 · La cuota poda registros no guardados

**No accionable en el alcance actual · Retención intencionada; DOS excluido**. Gravedad original: Baja.

La retención por cuota elimina entradas antiguas no guardadas cuando se llena el espacio asignado.

- **Condiciones e impacto:** Servidor produce mucha salida; Cuota de retención alcanzada. Pérdida prevista de registros no guardados por la política de retención.
- **Controles y límites:** La poda excluye registros guardados y sesiones abiertas. No se sostiene que un servidor pueda borrar los guardados. El producto no promete un archivo forense inmutable y excluye DOS del servidor.
- **Pendiente de prueba/contexto:** No se han llenado cuotas durante esta revisión.
- **Siguiente paso:** Conservar y explicar la prioridad de los guardados; cuotas por host son una mejora de aislamiento y disponibilidad.
- **Evidencia en main:** [core/crates/openward-app/src/logs/recorder.rs:1-40](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/recorder.rs#L1-L40); [core/crates/openward-app/src/logs/mod.rs:489-525](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L489-L525).

#### RG-4 · Carga completa de grabaciones al reproducir o exportar

**No accionable en el alcance actual · Robustez pendiente**. Gravedad original: Baja (la app se cae).

Varias operaciones leen y descomprimen el registro entero; el escape JSON de controles puede amplificar su tamaño.

- **Condiciones e impacto:** Registro grande o muy compresible creado por salida del servidor. Consumo elevado de memoria en consulta, exportación o reproducción.
- **Controles y límites:** El efecto descrito es agotar recursos con salida del servidor, excluido por el modelo. No se identifica una lectura de archivos arbitrarios ni ejecución por el reproductor.
- **Pendiente de prueba/contexto:** No se repiten medidas de GiB/tiempo ni pruebas de caída.
- **Siguiente paso:** Pasar a lectura/exportación por bloques y limitar expansiones como mejora de robustez y requisito del trabajo D6.
- **Evidencia en main:** [core/crates/openward-app/src/logs/mod.rs:595-621](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L595-L621); [core/crates/openward-app/src/logs/mod.rs:703-740](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L703-L740); [core/crates/openward-app/src/logs/cast.rs:149-171](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/cast.rs#L149-L171).

#### RG-5 · Metadatos de sesión y ajuste Conexiones recientes

**Necesita revisión · Contrato de privacidad por aclarar** · **Prioridad R14**. Gravedad original: Baja.

Logs.begin crea una entrada aunque la grabación esté desactivada; el ajuste de recientes controla la presentación en inicio/paleta, no esa entrada del registro.

- **Condiciones e impacto:** Recientes desactivados; Inicio de sesión. Diferencia entre expectativa de privacidad y persistencia de metadatos.
- **Controles y límites:** La interfaz distingue entradas sin grabación y el borrado de recientes describe su alcance de lista. Persistir metadatos está documentado en el modelo.
- **Pendiente de prueba/contexto:** Falta decidir si el texto de ayuda de recientes comunica suficientemente esa separación, incluidos terminales locales.
- **Siguiente paso:** Aclarar el texto y ofrecer controles separados si se pretende permitir sesiones sin ningún metadato persistente.
- **Evidencia en main:** [core/crates/openward-app/src/logs/mod.rs:352-399](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L352-L399); [app/lib/l10n/app_es.arb:3272-3272](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/l10n/app_es.arb#L3272).

#### RG-6 · Fidelidad del texto derivado y caracteres de control

**Necesita revisión · Filtro confirmado; impacto visual pendiente** · **Prioridad R13**. Gravedad original: Baja.

TextFilter termina OSC/DCS/APC con BEL o ESC y deja pasar Unicode bidi y ancho cero; no trata CAN/SUB como fin. El texto derivado puede divergir del replay.

- **Condiciones e impacto:** Salida remota con secuencias canceladas o controles Unicode. Posible omisión o presentación engañosa en búsqueda y exportación de texto.
- **Controles y límites:** El filtro declara que es aproximado y el cast conserva la salida original. No se ha verificado aquí la presentación exacta de Ghostty/Flutter para cada secuencia.
- **Pendiente de prueba/contexto:** Falta comprobar cancelación CAN/SUB y el efecto visual del bidi en las vistas actuales antes de cerrar el alcance de engaño.
- **Siguiente paso:** Revisar cancelación de secuencias y hacer visibles los controles en resultados/comandos; contrastar con la salida realmente mostrada.
- **Evidencia en main:** [core/crates/openward-app/src/logs/text.rs:45-90](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/text.rs#L45-L90); [app/lib/logs/logs_page.dart:671-675](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/logs/logs_page.dart#L671-L675).

#### RG-7 · Texto reconstruido desde la pantalla que se reenvía desde el historial

**Confirmado · Vigente** · **Prioridad C8**. Gravedad original: Baja.

Las líneas editadas se reconstruyen de la pantalla controlada por el servidor. La paleta ofrece historial de otros hosts y _send reenvía con salto de línea sin la comprobación de controles aplicada al pegado normal.

- **Condiciones e impacto:** Servidor altera la pantalla de una línea editada; Selección posterior del historial, posiblemente en otro host. Ejecución de texto distinto del que el usuario cree recuperar.
- **Controles y límites:** El usuario debe seleccionar una entrada; hay indicación de origen y preferencia por el host actual, pero no un filtro estricto ni una revisión completa del texto reenviado.
- **Pendiente de prueba/contexto:** No se ha ejecutado un comando desde el historial en esta revisión.
- **Siguiente paso:** Tratar la reconstrucción de pantalla como no confiable, mostrar controles y origen, y aplicar la misma confirmación antes de enviar a otro destino.
- **Evidencia en main:** [core/crates/openward-ghostty/src/engine.rs:1059-1088](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ghostty/src/engine.rs#L1059-L1088); [app/lib/history/line_tracker.dart:125-165](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/history/line_tracker.dart#L125-L165); [app/lib/palette/command_palette.dart:241-266](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/palette/command_palette.dart#L241-L266); [app/lib/palette/command_palette.dart:930-944](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/palette/command_palette.dart#L930-L944).

#### RG-8 · Borrar todos no incluye archivos de registro huérfanos

**Confirmado · Vigente** · **Prioridad C18**. Gravedad original: Baja.

El mapa omite metadatos ilegibles y un fallo al escribir la entrada puede dejar el cast ya creado. delete_all borra los IDs del mapa, sin recorrer esos huérfanos ni temporales.

- **Condiciones e impacto:** Metadatos dañados o escritura fallida; El usuario solicita borrar todos. Datos de sesión conservados después de una solicitud de eliminación total.
- **Controles y límites:** La carpeta es privada y el borrado evita rutas arbitrarias. El problema es la garantía de eliminación de datos administrados, no acceso entre usuarios durante operación normal.
- **Pendiente de prueba/contexto:** No se han provocado fallos de disco; el orden de creación y la selección por mapa explican el residuo.
- **Siguiente paso:** Reconciliar archivos administrados con metadatos y barrer huérfanos seguros al borrar todo; no ampliar el borrado a archivos ajenos.
- **Evidencia en main:** [core/crates/openward-app/src/logs/mod.rs:235-260](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L235-L260); [core/crates/openward-app/src/logs/mod.rs:380-388](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L380-L388); [core/crates/openward-app/src/logs/mod.rs:450-481](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L450-L481).

#### RG-9 · Otras observaciones de registros e historial

**No accionable en el alcance actual · Límites y observaciones**. Gravedad original: Informativa.

Se mantienen los casos de cast manipulado, panic de FFI, cambio de ajustes con sesión abierta, exportación a un destino elegido y replay en aplicaciones externas. El registro contiene salida/tiempos y comandos inferidos, no un volcado de todas las pulsaciones.

- **Condiciones e impacto:** Acceso local al registro o decisiones explícitas de exportación/configuración. Riesgos locales condicionados y expectativas de comportamiento.
- **Controles y límites:** Modificar casts privados requiere acceso del mismo UID; la FFI contiene panics y los visores externos quedan fuera del producto. El destino de exportación es una elección explícita.
- **Pendiente de prueba/contexto:** No se demuestra un cruce adicional de confianza; no se afirma que cambiar el ajuste cierre una grabación ya abierta.
- **Siguiente paso:** Documentar la semántica de ajustes y exportación y conservar estas observaciones como robustez/UX.
- **Evidencia en main:** [core/crates/openward-app/src/logs/mod.rs:450-481](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/mod.rs#L450-L481); [core/crates/openward-app/src/logs/recorder.rs:119-175](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-app/src/logs/recorder.rs#L119-L175).

### Terminal

#### TE-1 · Confirmación de pegado con contenido fuera de la vista previa

**Confirmado · Mitigación parcial** · **Prioridad C19**. Gravedad original: Baja.

La vista previa se corta a 400 caracteres (600 en envío múltiple) sin una revisión completa del contenido que se autoriza.

- **Condiciones e impacto:** Pegado largo con contenido relevante fuera de la vista previa; Confirmación del usuario. Autorización de líneas o controles que no se han podido revisar.
- **Controles y límites:** El detector examina el texto completo y la visualización actual ya marca U+2028/U+2029; se retira la afirmación anterior de que esos separadores pasan sin marcar. Sigue sin haber vista completa de la cola.
- **Pendiente de prueba/contexto:** No se ha pegado un payload; el problema es el consentimiento con contenido oculto, no ejecución automática al abrir la tarjeta.
- **Siguiente paso:** Permitir revisar todo el texto y mostrar claramente cuánto contenido queda, con controles visibles en toda la previsualización.
- **Evidencia en main:** [app/lib/terminal/paste.dart:13-40](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/terminal/paste.dart#L13-L40); [app/lib/terminal/paste.dart:94-110](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/terminal/paste.dart#L94-L110); [app/lib/terminal/visible_text.dart:1-50](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/terminal/visible_text.dart#L1-L50).

#### TE-2 · Aviso multilínea y bracketed paste

**No accionable en el alcance actual · Comportamiento de protocolo**. Gravedad original: Informativa.

El motor trata el pegado según el modo 2004 indicado por el programa remoto, lo que cambia cuándo se necesita un aviso.

- **Condiciones e impacto:** Programa remoto que cambia el modo 2004. Diferencias de comportamiento de pegado acordes al protocolo.
- **Controles y límites:** Un servidor que controla su terminal ya controla lo que ejecuta allí; este mecanismo no demuestra ejecución local ni en otro host. El modo bracketed paste forma parte del protocolo.
- **Pendiente de prueba/contexto:** No se identifica un salto de confianza distinto del contenido incompleto de TE-1.
- **Siguiente paso:** Ofrecer siempre confirmar multilínea como preferencia de UX si se desea; no describir el modo 2004 como una vulnerabilidad por sí solo.
- **Evidencia en main:** [app/lib/terminal/terminal_pane.dart:589-606](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/terminal/terminal_pane.dart#L589-L606).

#### TE-3 · Enlaces ftp/mailto y presentación del destino

**Necesita revisión · Pendiente de aplicaciones nativas** · **Prioridad R18**. Gravedad original: Informativa.

La lista admite http, https, mailto y ftp y entrega la URL al manejador externo. La confirmación muestra el destino sin representar todos los caracteres de forma inequívoca.

- **Condiciones e impacto:** Enlace remoto; Apertura consentida; Manejador nativo con comportamiento relevante. Posible engaño o acción inesperada de una aplicación externa.
- **Controles y límites:** La apertura exige interacción/modificador y la lista de esquemas impide invocar esquemas arbitrarios.
- **Pendiente de prueba/contexto:** El tratamiento de mailto/adjuntos o ftp depende del cliente y sus asociaciones; no se ha demostrado adjuntar/exfiltrar un archivo.
- **Siguiente paso:** Normalizar la presentación y validar manejadores y parámetros peligrosos antes de atribuir un impacto específico.
- **Evidencia en main:** [app/lib/terminal/links.dart:16-29](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/terminal/links.dart#L16-L29); [app/lib/terminal/links.dart:65-69](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/terminal/links.dart#L65-L69).

#### TE-4 · Identificación del terminal y soporte de imágenes no utilizado

**No accionable en el alcance actual · Reducción de superficie**. Gravedad original: Informativa.

Se conservan la respuesta de versión y la capacidad de imágenes disponible en el motor.

- **Condiciones e impacto:** Servidor que consulta capacidades o envía imágenes. Superficie adicional y consumo de recursos.
- **Controles y límites:** Identificar la versión no demuestra explotación. El consumo de recursos por un servidor hostil está excluido; no se ha medido el supuesto pico de memoria.
- **Pendiente de prueba/contexto:** No hay un fallo adicional validado en esas funciones.
- **Siguiente paso:** Desactivar capacidades no utilizadas y revisar la identificación del terminal como endurecimiento, sin afirmar una corrección ya hecha.
- **Evidencia en main:** [core/crates/openward-ghostty/src/engine.rs:72-72](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ghostty/src/engine.rs#L72); [core/crates/openward-ghostty/src/engine.rs:265-311](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ghostty/src/engine.rs#L265-L311).

#### TE-5 · Análisis de temas iTerm2 mediante expresiones regulares

**Necesita revisión · Complejidad pendiente de medir** · **Prioridad R19**. Gravedad original: Informativa.

Se buscan valores XML con regex y el parseo se hace en el recorrido de interfaz.

- **Condiciones e impacto:** Tema iTerm2 ajeno menor que el límite admitido. Posible bloqueo de interfaz condicionado al coste real del parser.
- **Controles y límites:** La selección de temas sí rechaza archivos de 1 MiB o más; el informe inicial no reflejaba suficientemente ese límite.
- **Pendiente de prueba/contexto:** Sin análisis formal o prueba acotada no se concluye una complejidad cuadrática ni una congelación actual.
- **Siguiente paso:** Usar un parser plist/XML acotado o verificar el presupuesto temporal con entradas adversas dentro del límite.
- **Evidencia en main:** [app/lib/terminal/scheme_import.dart:34-40](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/terminal/scheme_import.dart#L34-L40); [app/lib/settings/appearance_page.dart:590-592](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/lib/settings/appearance_page.dart#L590-L592).

### Build, CI y publicación

#### CI-1 · Herramientas sin verificación de integridad en el contenedor Linux

**Confirmado · Mitigación parcial** · **Prioridad C23**. Gravedad original: Media.

El contenedor local sigue descargando Zig sin verificar el hash, ejecuta rustup desde la descarga y usa base/Flutter referenciados por tag. Ese camino sigue siendo parte del empaquetado.

- **Condiciones e impacto:** Uso del empaquetador basado en contenedor; Fuente/tag de herramienta sustituido o comprometido. Ejecución de una herramienta no ligada al contenido revisado en el build.
- **Controles y límites:** La CI Linux x64 alojada usa install-zig.sh con SHA-256; no se puede atribuir el fallo del contenedor a todos los artefactos actuales.
- **Pendiente de prueba/contexto:** No se ha ejecutado el contenedor ni se afirma compromiso de una herramienta descargada.
- **Siguiente paso:** Fijar base/commits y verificar hashes de herramientas en el contenedor igual que en el instalador de CI, antes de usarlo para distribuir.
- **Evidencia en main:** [app/tool/linux/Containerfile:4-22](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/tool/linux/Containerfile#L4-L22); [app/tool/package-linux.sh:37-64](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/tool/package-linux.sh#L37-L64); [.github/scripts/install-zig.sh:6-30](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.github/scripts/install-zig.sh#L6-L30).

#### CI-2 · La CI actual no ejecuta automáticamente forks en el equipo del mantenedor

**No accionable en el alcance actual · Premisa operativa obsoleta**. Gravedad original: Media.

Hay Actions alojadas para PRs/pushes y no se aceptan contribuciones externas de código antes de Community. Sobrevive documentación de la antigua puerta local.

- **Condiciones e impacto:** Decisión manual de ejecutar código ajeno localmente. El escenario original no refleja el flujo de CI actual.
- **Controles y límites:** No hay pull_request_target ni runner self-hosted que establezcan el salto descrito. Elegir ejecutar código ajeno como mantenedor no demuestra aquí una elevación adicional.
- **Pendiente de prueba/contexto:** No se ha reproducido el escenario histórico ni inspeccionado equipos privados.
- **Siguiente paso:** Actualizar comentarios de la puerta local y mantener aisladas las validaciones de contribuciones no confiables.
- **Evidencia en main:** [.github/workflows/ci.yml:1-61](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.github/workflows/ci.yml#L1-L61); [CONTRIBUTING.md:1-41](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/CONTRIBUTING.md#L1-L41); [tool/ci.sh:1-40](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/tool/ci.sh#L1-L40).

#### CI-3 · Reporte privado de vulnerabilidades desactivado

**Confirmado · Vigente; verificado en GitHub** · **Prioridad C25**. Gravedad original: Baja.

El repositorio es público, pero GET /repos/KaiCorpLabs/openward/private-vulnerability-reporting devuelve enabled=false el 11-11-2026. SECURITY.md remite al canal privado de GitHub.

- **Condiciones e impacto:** Investigador externo que sigue SECURITY.md. No puede utilizar el canal privado anunciado para reportar un problema.
- **Controles y límites:** La antigua explicación basada en que el repositorio era privado ya no es válida; la comprobación actual identifica el ajuste concreto que falta.
- **Pendiente de prueba/contexto:** No se cambia esa configuración administrativa en esta PR documental; no se ha enviado ninguna vulnerabilidad por un canal público.
- **Siguiente paso:** Habilitar private vulnerability reporting o publicar un contacto privado utilizable, y verificar el enlace como colaborador externo.
- **Evidencia en main:** [SECURITY.md:1-23](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/SECURITY.md#L1-L23).

#### CI-4 · Interpolación del tag en sed dentro de una release manual

**No accionable en el alcance actual · Endurecimiento; sin escalada demostrada**. Gravedad original: Baja (pide permiso de escritura).

El tag se inserta en el programa sed sin validar su alfabeto; el mecanismo de inyección descrito sigue siendo técnicamente relevante.

- **Condiciones e impacto:** Actor con permisos para crear tags y ejecutar workflows. Riesgo condicionado a una futura separación de privilegios; hoy el actor ya puede cambiar el build.
- **Controles y límites:** El workflow es manual y crear el tag/ejecutarlo exige permisos de escritura. No se han encontrado reglas o roles que separen a ese actor de quien puede modificar el workflow; no hay escalada de privilegios demostrada.
- **Pendiente de prueba/contexto:** Reevaluar si se introducen tags protegidos, actores con permisos distintos o secretos de publicación separados.
- **Siguiente paso:** Validar tags con una gramática estricta y evitar construir código sed con datos antes de ampliar privilegios del job.
- **Evidencia en main:** [.github/workflows/ci.yml:475-495](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.github/workflows/ci.yml#L475-L495).

#### CI-5 · El borrador de release solo depende del job app

**Necesita revisión · Contrato de publicación pendiente** · **Prioridad R16**. Gravedad original: Baja.

release necesita app, no todos los jobs, y no comprueba ascendencia del tag respecto a main. Es un borrador manual, no una publicación automática.

- **Condiciones e impacto:** Release manual desde tag; Otros checks fallan o el tag no procede de main. Posible borrador de distribución sin todas las garantías de validación previstas.
- **Controles y límites:** El job descarga artefactos de su propio run. No se ha confirmado el antiguo supuesto de fallo 403 por actions:read ni una promoción de artefactos de forks.
- **Pendiente de prueba/contexto:** Falta establecer la puerta obligatoria de publicación y verificar permisos efectivos del job antes de atribuir un bypass explotable.
- **Siguiente paso:** Exigir los checks acordados y procedencia del tag para publicar; validar permisos de descarga con evidencia de un run, sin asumir un fallo.
- **Evidencia en main:** [.github/workflows/ci.yml:470-502](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.github/workflows/ci.yml#L470-L502).

#### CI-6 · Cachés compartidas del empaquetador local

**No accionable en el alcance actual · Aislamiento local pendiente**. Gravedad original: Baja.

Los volúmenes del empaquetador y el caché de libghostty son compartidos. El hash usado para invalidar no autentica contra quien puede escribir el caché.

- **Condiciones e impacto:** Código ya ejecutado con acceso al caché local del mantenedor. Contaminación local condicionada a acceso previamente equivalente.
- **Controles y límites:** El escenario local necesita ejecutar código con acceso de escritura del propio mantenedor, actor excluido por el modelo. Las cachés de PRs de Actions tienen alcance de merge ref y no pueden sobrescribir las de main.
- **Pendiente de prueba/contexto:** No se demuestra un camino desde un fork alojado hasta un caché confiable de main.
- **Siguiente paso:** Aislar/limpiar cachés de releases y documentar su carácter no autenticado; reevaluar si se añade infraestructura compartida entre identidades.
- **Evidencia en main:** [app/tool/package-linux.sh:56-64](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/tool/package-linux.sh#L56-L64); [core/crates/openward-ghostty/build-libghostty.sh:65-87](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/crates/openward-ghostty/build-libghostty.sh#L65-L87).

#### CI-7 · Runner de cargokit sin resolución transitiva bloqueada

**Confirmado · Vigente; reproducibilidad de build** · **Prioridad C24**. Gravedad original: Baja.

El script genera otro runner y ejecuta pub get sin trasladar el lockfile del build_tool. Las dependencias directas están fijadas intencionadamente, pero no toda su resolución transitiva.

- **Condiciones e impacto:** Build del runner generado; Cambio admisible de una dependencia transitiva. Ejecución de código de build no ligado al lockfile revisado.
- **Controles y límites:** No se afirma que todas las dependencias floten ni que haya una dependencia comprometida; el problema es la resolución nueva fuera del conjunto revisado.
- **Pendiente de prueba/contexto:** No se ha resuelto de nuevo el runner ni comparado versiones descargadas.
- **Siguiente paso:** Usar una resolución bloqueada también para el runner generado y hacer revisables sus cambios transitivos.
- **Evidencia en main:** [app/rust_builder/cargokit/run_build_tool.sh:23-34](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/rust_builder/cargokit/run_build_tool.sh#L23-L34); [app/rust_builder/cargokit/run_build_tool.sh:73-77](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/rust_builder/cargokit/run_build_tool.sh#L73-L77); [app/rust_builder/cargokit/build_tool/pubspec.yaml:14-33](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/rust_builder/cargokit/build_tool/pubspec.yaml#L14-L33).

#### CI-8 · Volcado completo del entorno en build_pod.sh

**Necesita revisión · Exposición condicionada** · **Prioridad R17**. Gravedad original: Baja.

El script conserva una llamada incondicional a env que envía las variables al log.

- **Condiciones e impacto:** Build macOS con variables sensibles; Log accesible a otro actor. Posible exposición de secretos por diagnóstico.
- **Controles y límites:** No se han identificado secretos asignados al job app actual; GH_TOKEN está en el job release separado. El enmascarado de Actions tampoco garantiza proteger cualquier formato futuro.
- **Pendiente de prueba/contexto:** Falta demostrar una variable sensible presente y un lector del log con menos privilegios; no se afirma una filtración efectiva.
- **Siguiente paso:** Retirar el volcado general y limitar el diagnóstico a variables no sensibles antes de incorporar firma/credenciales al build.
- **Evidencia en main:** [app/rust_builder/cargokit/build_pod.sh:14-14](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/rust_builder/cargokit/build_pod.sh#L14).

#### CI-9 · crypto-bigint de core actualizado y cargo deny validado

**No accionable en el alcance actual · Corregido en core**. Gravedad original: Baja.

El lockfile principal contiene crypto-bigint 0.7.10. La CI de main 35ab7a6 completó cargo deny y el resto de checks.

- **Condiciones e impacto:** Lockfile de core en main 35ab7a6. El fallo concreto del lockfile principal ya no está presente.
- **Controles y límites:** La denuncia de core 0.7.6 y de su fallo de CI quedó obsoleta. El lockfile independiente del spike no se confunde con el distribuido.
- **Pendiente de prueba/contexto:** No se ha ejecutado una auditoría nueva durante este contraste estático ni se certifican todos los ecosistemas.
- **Siguiente paso:** Conservar la puerta cargo deny y seguir las actualizaciones del spike por separado.
- **Evidencia en main:** [core/Cargo.lock:620-630](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/core/Cargo.lock#L620-L630); [.github/workflows/ci.yml:1-61](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.github/workflows/ci.yml#L1-L61).

#### CI-10 · Artefactos de PR con nombres parecidos a los de distribución

**No accionable en el alcance actual · Procedencia visible; UX mejorable**. Gravedad original: Baja.

Algunos artefactos Linux/Windows de PR mantienen nombres de versión; el snapshot de macOS sí incluye commit.

- **Condiciones e impacto:** Descarga manual de un artefacto de PR. Posible confusión de procedencia, sin promoción automática a una release confiable.
- **Controles y límites:** El run identifica PR y origen, y release descarga exclusivamente su propio GITHUB_RUN_ID. No hay una ruta de promoción automática de artefactos de forks a release.
- **Pendiente de prueba/contexto:** El riesgo restante es confusión de un usuario que descargue artefactos de prueba, sin un bypass de publicación demostrado.
- **Siguiente paso:** Prefijar artefactos de PR, mostrar SHA/origen y reducir su retención como mejora de procedencia.
- **Evidencia en main:** [.github/workflows/ci.yml:470-502](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.github/workflows/ci.yml#L470-L502).

#### CI-11 · Empaquetado local y garantías de procedencia

**No accionable en el alcance actual · Requisito de distribución futura**. Gravedad original: Baja.

El empaquetador Linux admite árbol con cambios y no genera sumas/atestaciones comunes; ese nombre lleva explícitamente commit y sufijo dirty.

- **Condiciones e impacto:** Empaquetado local y futura distribución pública. Garantías de publicación aún incompletas, documentadas como requisito.
- **Controles y límites:** No se hace pasar silenciosamente un árbol sucio por un tag limpio. La publicación y firma definitiva siguen pendientes en el plan; no existe una promesa actual de procedencia autenticada equivalente para todos los paquetes.
- **Pendiente de prueba/contexto:** No se ha construido ni publicado un paquete en esta revisión.
- **Siguiente paso:** Antes de distribuir Community, exigir árbol/tag acordados y producir sumas y procedencia verificables, manteniendo las garantías macOS existentes.
- **Evidencia en main:** [app/tool/package-linux.sh:44-68](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/tool/package-linux.sh#L44-L68); [app/tool/package-macos.sh:33-46](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/tool/package-macos.sh#L33-L46).

#### CI-12 · Otros aspectos de build, datos personales y dependencias de spikes

**Necesita revisión · Observaciones mixtas actualizadas** · **Prioridad R20**. Gravedad original: Informativa.

Se conservan correo público y firma de tags, Hardened Runtime, ignores de datos/credenciales, fixtures, imágenes por tag y descarga interna de Flutter. El setup.sh de la acción fijada descarga el SDK sin una comprobación de hash; usar sha256 en la clave de caché no lo verifica. action.yaml además invoca actions/cache@v5 por tag.

- **Condiciones e impacto:** Dependencias de tooling, configuración de firma o archivos de trabajo particulares. Endurecimiento de cadena de suministro y privacidad con subcasos de distinto alcance.
- **Controles y límites:** El repositorio ya es público, el escenario de inyección macOS presupone mismo UID y las fixtures son intencionadas. El spike no se distribuye y su Tokio ya es 1.54.1: se retira la afirmación de que sigue en 1.53.2.
- **Pendiente de prueba/contexto:** No se ha repetido una búsqueda completa de secretos ni una auditoría del spike; no se conservan como vigentes todos los avisos antiguos de RustSec sin revalidación. Falta comprobar por separado los efectos de firma e imágenes.
- **Siguiente paso:** Verificar integridad del SDK, mantener ignores/fixtures deliberados y revisar el lockfile del spike separadamente; no reescribir el historial personal ni afirmar secretos encontrados.
- **Evidencia en main:** [.github/workflows/ci.yml:1-61](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.github/workflows/ci.yml#L1-L61); [app/macos/Runner.xcodeproj/project.pbxproj:1-120](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/app/macos/Runner.xcodeproj/project.pbxproj#L1-L120); [.gitignore:1-55](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/.gitignore#L1-L55); [spikes/s2-ssh/sshprobe/Cargo.lock:1-100](https://github.com/KaiCorpLabs/openward/blob/35ab7a63187a58aae132a31bd000ab0858164dff/spikes/s2-ssh/sshprobe/Cargo.lock#L1-L100).

## Fuentes externas y verificación

Las referencias de código anteriores están fijadas a `35ab7a63187a58aae132a31bd000ab0858164dff`; sus líneas no cambian al avanzar main.

- CO-3, CO-4 y DA-3 también contrastan las implementaciones locales fijadas en Cargo.lock: `russh 0.64.1` (`client/kex.rs`, comprobación de firma) y `ssh-key 0.7.0-rc.11` (`public/ecdsa.rs`, `public/ssh_format.rs`, `signature.rs`). En ssh-key la revisión de origen indicada por el paquete es `7a1c757d2e2fcde32680e373d5226481de6d434e`. La igualdad del punto codificado y la preservación del comentario se observan en esa dependencia concreta; no se extrapolan a versiones futuras.
- CI-4/CI-6: la documentación oficial indica el permiso de escritura requerido para [ejecutar manualmente un workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) y el [alcance de los cachés de PR al merge ref](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching). Son controles del flujo alojado; no protegen un caché local compartido por el mantenedor.
- CI-12: [setup.sh](https://github.com/subosito/flutter-action/blob/1a449444c387b1966244ae4d4f8c696479add0b2/setup.sh#L43-L48) descarga el archivo y el [action.yaml](https://github.com/subosito/flutter-action/blob/1a449444c387b1966244ae4d4f8c696479add0b2/action.yaml) de la acción fijada conserva referencias internas por tag. La variable sha256 del manifiesto se usa para componer una clave de caché, no como una comprobación del archivo descargado.
- CI-3: `GET /repos/KaiCorpLabs/openward/private-vulnerability-reporting` devolvió `{"enabled":false}`. Es una observación fechada, no una garantía sobre el estado futuro del ajuste.
- CI de referencia: [run de main 35ab7a6](https://github.com/KaiCorpLabs/openward/actions/runs/42900775281), con los 19 jobs terminados correctamente tras fusionar las actualizaciones de dependencias. Este resultado valida sus checks, no las PoCs de este informe. El estado de la CI del nuevo documento se conserva en los checks de la PR #8.

Se han preservado las 63 entradas y sus subobservaciones; las agrupaciones informativas contienen cuestiones de distinto alcance y no equivalen a una vulnerabilidad única. Las correcciones de producto deberán verificarse con pruebas dirigidas cuando se implementen. La ausencia de una PoC nueva no cierra un caso pendiente.
