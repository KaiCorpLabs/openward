# Camino a la Community: lo básico completo y la sincronización

- **Estado:** propuesta, pendiente de revisar. Como hasta ahora, cada hito con interfaz nueva pasa antes por maquetas en el lienzo.
- **Fecha:** 2026-11-06.
- **Base:** fases 1 y 2 de la hoja de ruta ([ARCHITECTURE §15](../ARCHITECTURE.md#15-hoja-de-ruta-con-puertas)) y los ADR [004](../adr/ADR-004-vault-y-jerarquia-de-claves.md) (vault), [005](../adr/ADR-005-sync-por-registros-de-dispositivo.md) (sync), [006](../adr/ADR-006-servidor-open-core.md) (servidor) y [009](../adr/ADR-009-mosh-clean-room.md) (Mosh). Incluye el plan de la [v0.4](v0.4.md) como etapa 2, con tres ajustes.
- **Duración estimada:** unas 29 semanas de plan en cinco etapas. Son estimaciones al estilo de los planes anteriores: la 0.2 y la 0.3 fueron bastante más rápidas que lo que decían sus planes.

## Objetivo

Llegar a una versión de escritorio que se pueda lanzar como **Community**, la edición gratuita:
- **todo lo que hoy se espera gratis de un cliente SSH moderno**, en macOS, Windows y Linux;
- **el vault cifrado** con contraseña maestra, kit de recuperación y desbloqueo con biometría;
- **sincronización E2EE entre equipos**, gratis con el almacenamiento de cada cual (una carpeta, S3, WebDAV) y con una cuenta en nuestro servidor;
- **el servidor funcionando con las cuentas de KaiCorp Labs** (`id.kaicorplabs.com`, Supabase Auth autoalojado), que ya existen y ya usan las demás apps de la casa: OpenWard no construye registro ni inicio de sesión propios.

**Orden acordado (2026-11-06):**
1. primero esto: lo básico, el vault y la sync;
2. después, el lanzamiento: la web, la firma y la notarización, y lo demás de «Después de este plan»;
3. y Android e iOS, cuando esto esté listo.

Ese mismo día se descartó montar Postgres y Supabase Auth aparte para OpenWard: la identidad de KaiCorp Labs ya es Supabase Auth y corre en el minipc de la casa.

**Puerta de salida del plan:**
- el equipo usa OpenWard dos semanas como único cliente SSH en macOS, Windows y Linux, sin echar en falta nada de la etapa 1;
- dos equipos de cada persona se sincronizan por una carpeta y por la cuenta. Con ediciones a la vez y sin conexión, convergen sin perder nada, y los conflictos se ven;
- se entra con una cuenta de KaiCorp Labs, se añade un segundo equipo y se recupera el vault en un tercero con el kit. El servidor no ve nunca la contraseña maestra ni nada en claro, y se comprueba en sus tablas y registros;
- una persona de fuera del equipo crea su cuenta, recibe la membresía de OpenWard y sincroniza contra el servidor público, que tiene copias, vigilancia y borrado de una persona como los demás servicios de la casa;
- `THREAT_MODEL.md` cubre el servidor y las cuentas.

## Etapas

| Etapa | Versión | Contenido | Semanas |
|---|---|---|---|
| 1 | 0.3.4 y siguientes | [Lo básico completo](#etapa-1--lo-básico-completo) (P0–P7) | ~9 |
| 2 | 0.4 | [El vault cifrado](#etapa-2--v04-el-vault-cifrado) ([v0.4.md](v0.4.md), D0–D8) | ~8,5 |
| 3 | 0.5 | [Sync con tu almacenamiento](#etapa-3--v05-sync-con-tu-almacenamiento) (S1–S6) | ~5 |
| 4 | 0.6 | [Servidor y cuentas de KaiCorp Labs](#etapa-4--v06-servidor-y-cuentas-de-kaicorp-labs) (C1–C6) | ~5 |
| 5 | 0.7 | [Abierto: el servidor en producción](#etapa-5--v07-abierto-el-servidor-en-producción) (M1–M3) | ~1,5 |

**La etapa 1 va antes que la v0.4.** Varias de sus funciones añaden datos a los hosts (protocolo, codificación, retroceso, Mosh, snippet al conectar), y conviene que entren antes de migrar el vault al formato cifrado (D3), como hicieron F2 y F3 en su día. D0–D2 de la v0.4 no tocan la app (el modelo de amenazas y los dos experimentos) y pueden ir en paralelo con P3–P7.

## Etapa 1 · Lo básico completo

**Lo que ya está:**
- hosts y grupos con herencia, etiquetas, entornos y el sistema de cada servidor;
- identidades, claves (generar, importar e instalar en el servidor) y known hosts;
- pestañas, paneles, broadcast y workspaces;
- SFTP de doble panel con permisos y archivos ocultos;
- túneles L/R/D, saltos, proxy HTTP/SOCKS5, ProxyCommand, agent forwarding, variables de entorno e intercambio de claves poscuántico;
- snippets con variables, terminal local, paleta, historial, conexión viva con tmux persistente y registros de sesión;
- temas, accesibilidad, español e inglés;
- importadores.

**Lo que falta:**

| # | Hito | Semanas |
|---|---|---|
| P0 | Windows y Linux al día | 1 |
| P1 | Telnet y puerto serie | 1,5 |
| P2 | Mosh en escritorio | 1 |
| P3 | Llaves FIDO2 y certificados | 1,5 |
| P4 | Terminal: copiar al seleccionar, resaltado, codificación, retroceso, tema por host y atajos | 1,5 |
| P5 | Autocompletado local | 1,5 |
| P6 | Snippets en varios hosts, snippet al conectar y archivos remotos abiertos en local | 1 |
| P7 | Pulido, Novedades, notas, guía de prueba y beta | 0,5 |

### P0 · Windows y Linux al día

- La 0.3.3 se prueba en un Windows limpio (Windows Sandbox) y en un Linux de escritorio, y se arregla lo que salga.
- **La CI corre en los tres sistemas en cada push y cada PR**, porque el repositorio es público desde el 2026-11-06 y los minutos no se cobran. Si vuelve a ser privado, la CI vuelve sola al reparto que ahorra minutos: Linux en cada push, Linux y Windows en cada etiqueta de versión, y los tres cada semana. «Run workflow» deja elegir los sistemas.
- La guía de prueba cubre los tres sistemas. Desde aquí, cada hito se prueba en los tres antes de darlo por hecho.

### P1 · Telnet y puerto serie

- **Un host puede ser SSH, Telnet o serie**, con la misma herencia de grupos.
- **Telnet:**
  - negocia el tamaño de la ventana (NAWS), el tipo de terminal (TTYPE) y el eco;
  - avisa a la vista de que no cifra: la contraseña viaja en claro.
- **Serie:**
  - crate `openward-serial` (`serialport`): lista de puertos, baudios, bits de datos, paridad, bits de parada y control de flujo;
  - un botón «Serie» junto a «Terminal local» y una entrada en la paleta;
  - en los tres sistemas.
- Los registros, la búsqueda y los temas funcionan igual que en SSH.
- **Importadores:** los hosts Telnet y serie que hoy se saltan pasan a importarse.

### P2 · Mosh en escritorio

- **Se revisa [ADR-009](../adr/ADR-009-mosh-clean-room.md):** en escritorio se usa el `mosh-client` instalado en el equipo (Homebrew, apt, dnf), como un programa aparte dentro del PTY de la terminal local. El flujo es:
  1. OpenWard arranca `mosh-server new` por su propia conexión SSH, con la autenticación, los saltos y los known hosts de siempre;
  2. lee `MOSH CONNECT <puerto> <clave>`;
  3. lanza `mosh-client` con `MOSH_KEY`.
  
  No se enlaza ni se distribuye código GPL.
- **Es una opción más, no un cambio de protocolo:** SSH sigue siendo lo normal, y Mosh se enciende por host o por grupo (apagado por defecto). Decidido el 2026-11-06.
- **Ajuste por host «Mosh»** (heredable):
  - si falta `mosh-client`, lo dice y explica cómo instalarlo;
  - si el UDP no llega, vuelve a SSH con la sesión persistente de tmux.
- **Límites:**
  - los saltos solo sirven para arrancar el servidor, porque el UDP va directo;
  - en Windows, hasta el cliente clean-room, que sigue en la fase 4 junto con el móvil.

### P3 · Llaves FIDO2 y certificados

- **Llaves de seguridad** (`sk-ecdsa-sha2-nistp256@openssh.com` y `sk-ssh-ed25519@openssh.com`):
  - generarlas con PIN y toque;
  - importar las creadas con `ssh-keygen -t ed25519-sk`;
  - firmar con la llave conectada (CTAP2 por HID, detrás del trait `Signer` de [ADR-003](../adr/ADR-003-ssh-russh-y-firmantes.md)); la interfaz pide el toque.
- **Certificados de usuario** (`*-cert.pub`):
  - comprobar de punta a punta lo que las identidades ya leen;
  - mostrar principales y caducidad;
  - avisar antes de que caduquen.
- **Pruebas:**
  - en S2, un contenedor con `sshd` que acepta llaves `sk` y una CA de usuario;
  - en las pruebas automáticas, un autenticador por software, y una llave real a mano antes de cerrar el hito.
- Las claves en el Secure Enclave (Touch ID) van con D4 de la v0.4, porque comparten su riesgo de firma.

### P4 · Terminal

- **Copiar al seleccionar y pegar con clic derecho**, como ajustes de la app.
- **Resaltado de palabras clave:**
  - reglas para error, warning, ok, direcciones IP y MAC, con colores del tema;
  - editables y apagables;
  - se aplican al pintar, sin tocar la salida ni los registros.
- **Por host** (heredables):
  - codificación: UTF-8 por defecto, más Latin-1, CP437, Big5, Shift-JIS… con `encoding_rs`, traduciendo en el núcleo antes del motor y al enviar;
  - retroceso como `^?` o `^H`;
  - tema del terminal.
- **Atajos:** perfiles Mac y PC, y la opción de que los atajos de la app no se coman teclas dentro del terminal.

### P5 · Autocompletado local

- **Sugerencias en línea mientras se escribe**, en texto atenuado; una tecla las acepta.
- **De dónde salen:** el historial de ese host, los snippets y un repertorio de comandos comunes. Todo en el equipo y sin red.
- **Se apoya en el seguidor de línea del historial:**
  - no sugiere en la pantalla alternativa (editores, `less`…);
  - no sugiere cuando el prompt pide un secreto;
  - no sugiere con el historial desactivado.
- **La IA queda para la fase 3** ([ADR-008](../adr/ADR-008-ia-mcp-y-byok.md)), con tu propia clave o un modelo local. El diseño le deja el hueco para entrar como una fuente más.

### P6 · Snippets en varios hosts y archivos remotos

- **Ejecutar un snippet en una selección de hosts:**
  - abre o reutiliza la conexión de cada uno;
  - lo ejecuta en todos;
  - muestra el resultado de cada host, en paneles o en una vista de resultados.
- **Snippet al conectar**, por host o grupo (heredable).
- **SFTP:**
  - abrir un archivo remoto con su app del sistema o con «Abrir con…»;
  - al guardarlo, se vuelve a subir, con aviso si cambió en el servidor mientras tanto.

### P7 · Pulido y beta

Novedades, notas, guía de prueba en los tres sistemas, accesibilidad y galería, y una beta 0.3.x.

## Etapa 2 · v0.4, el vault cifrado

El plan de la [v0.4](v0.4.md) tal cual (D0–D8), con tres ajustes que salen de este:
- **La clave de cuenta piensa en el servidor desde el principio.** D3 guarda, además del vault, un paquete con la clave de cuenta envuelta con la KEK, que es lo que la etapa 4 sube para dar de alta otros equipos. El certificado del dispositivo admite más adelante claves de hardware (Secure Enclave, Keystore).
- **Desbloqueo en los tres sistemas:** Windows Hello y el llavero de Linux (libsecret) entran en la v0.4, no después. La Community sale en los tres.
- **Claves en el Secure Enclave (Touch ID)** junto al desbloqueo con Touch ID en D4. Si el llavero con biometría exige firmar con Developer ID, la cuenta de desarrollador de Apple hará falta antes del lanzamiento, aunque la notarización siga para entonces.

Las decisiones abiertas de la v0.4 (contraseña maestra obligatoria y «Más tarde» durante la beta) siguen pendientes. La sync de la etapa 3 confirma que la contraseña y el kit hacen falta.

## Etapa 3 · v0.5, sync con tu almacenamiento

El motor de [ADR-005](../adr/ADR-005-sync-por-registros-de-dispositivo.md) con los backends gratuitos. Va antes del servidor por tres razones:
- es la promesa de la lista «Siempre gratis»;
- una carpeta es la forma más simple de probar el motor;
- el servidor será un backend más del mismo motor.

| # | Hito | Semanas |
|---|---|---|
| S1 | `openward-sync`: registros por dispositivo, segmentos firmados, merge por campo, lápidas y cursores. Puerta de ADR-005: 3 dispositivos × 10.000 ediciones con `proptest` convergen al 100 % | 2 |
| S2 | Backend de carpeta (iCloud Drive, Dropbox, Syncthing, una carpeta de red), con lo que esos servicios hacen mal: copias con retraso y archivos «en conflicto» | 0,5 |
| S3 | Backends S3 (AWS, R2, MinIO, B2) y WebDAV (Nextcloud); sus credenciales, en el vault | 1 |
| S4 | Equipos: añadir uno con un código o un QR desde otro que ya está dentro (o con el kit), ver la lista y revocar uno | 0,5 |
| S5 | Ajustes › Sincronización: estado («última sync hace 3 min, vía iCloud»), conflictos con la versión que perdió e historial de un ítem | 0,5 |
| S6 | Compactación y poda, `openward-cli` para simular N dispositivos, formato en `spec/`, notas y beta | 0,5 |

- **Qué se sincroniza por defecto:** todo el vault (hosts, grupos, identidades, claves y contraseñas guardadas, snippets, túneles y workspaces). El historial y los registros se quedan en cada equipo; sincronizarlos será opcional y más adelante.
- **Git como backend** queda para después. Está en ADR-005, pero aquí no aporta nada que S3 o una carpeta no den ya.

## Etapa 4 · v0.6, servidor y cuentas de KaiCorp Labs

### Las cuentas ya existen

La identidad de KaiCorp Labs es **Supabase Auth autoalojado**, que hace de proveedor OAuth 2.1 y OIDC (`https://id.kaicorplabs.com/auth/v1`). Su app de cuenta (`account.kaicorplabs.com`) ya hace todo lo que OpenWard necesitaría construir:
- el registro con confirmación por correo;
- la entrada, con segundo factor opcional (passkey o TOTP);
- la recuperación y el cambio de correo;
- las membresías por aplicación, que se comprueban en la pantalla de consentimiento;
- la administración.

Las demás apps de la casa entran con OIDC genérico por discovery. OpenWard es una más: **no tiene registro ni contraseñas propios**.

### El servidor

- `server/` en Go con AGPL-3.0 y **CLA desde el primer commit** ([ADR-006](../adr/ADR-006-servidor-open-core.md), [ADR-007](../adr/ADR-007-licencias-y-contribuciones.md)).
- Módulos mínimos: `identity`, `objects`, `realtime` y `admin`.
- Postgres con `sqlc` y migraciones. El `Store` también existe en SQLite, para autoalojar con un único binario.
- **El relay es un backend más** del motor de la etapa 3 (`put`, `get`, `list` y `watch` por WebSocket): el cliente no tiene un segundo protocolo de sync.
- **Un cliente OIDC genérico**, configurado por discovery y sin nada exclusivo de Supabase:
  - en la casa, contra la identidad de KaiCorp Labs;
  - autoalojado, contra el proveedor OIDC de cada cual, como promete la lista «Siempre gratis».
- **La base de datos es suya**, un Postgres aparte del de la identidad: lo que guarda la sync no se mezcla con las cuentas y se copia y se restaura por separado.

### Cómo entra la app de escritorio

1. La app abre el navegador del sistema en el servidor (`/v1/login`).
2. El servidor hace el flujo OIDC con la identidad, como cliente confidencial con PKCE, igual que las otras apps de la casa. El canje del código va por la red interna, sin salir a internet.
3. Al volver, el servidor entrega a la app un código de un solo uso por una redirección a `127.0.0.1` (el patrón de RFC 8252 para apps nativas).
4. La app lo cambia por una sesión ligada a su clave de dispositivo.

Hay tres ventajas:
- en la identidad solo se registra la dirección de vuelta del servidor;
- la app no habla nunca con el emisor, así que no le afecta la comprobación de navegador de Cloudflare en `id.kaicorplabs.com`;
- un servidor autoalojado funciona igual con otro proveedor.

### Qué guarda el servidor, y qué no

- **La cuenta se identifica por el `sub`** del token, nunca por el correo, que puede cambiar.
- **La cuenta identifica, no descifra.** El vault se sigue abriendo en el equipo con la contraseña maestra, que **no sale nunca del equipo**, tampoco derivada: la identidad no la conoce. Así:
  - recuperar el acceso a la cuenta por correo no toca el cifrado;
  - olvidar la contraseña maestra se resuelve con el kit, nunca borrando el vault.
- **Guarda:**
  - las claves públicas de la cuenta y los certificados de cada dispositivo;
  - los segmentos cifrados;
  - el paquete de la clave de cuenta envuelto con la KEK.
  
  Para añadir un equipo nuevo: se entra con la cuenta, se descarga el paquete y se abre con la contraseña maestra o con el kit (o se aprueba desde otro equipo, como en S4).
- **Cada sesión lleva la firma del dispositivo**, un desafío firmado ([ARCHITECTURE §7.1](../ARCHITECTURE.md#71-monolito-modular)). Un equipo revocado no entra aunque conserve el token.

### Dónde corre

- En el minipc de la casa, donde ya están la identidad y los demás servicios. Se despliega como ellos: imagen en GHCR que pasa Trivy, variables y secretos con las herramientas de la casa, y su red OIDC con la pasarela de la identidad.
- **Hasta la etapa 5, solo en el tailnet** (`tailscale serve`) y solo para el equipo: la membresía de OpenWard solo la tienen sus personas.

| # | Hito | Semanas |
|---|---|---|
| C1 | ADR-010 (cuentas y servidor), modelo de amenazas del servidor, API v1 en `spec/`, y el cliente OAuth y la membresía de OpenWard dados de alta en la identidad | 0,5 |
| C2 | `server/`: esqueleto, `Store` en Postgres y SQLite, migraciones, objetos, CI (`go test` en los dos dialectos) e imagen | 1 |
| C3 | Entrar: OIDC por discovery, el traspaso a la app por `127.0.0.1`, la cuenta por `sub`, certificados de dispositivo, el paquete de la clave, salir y borrar los datos de la cuenta | 1 |
| C4 | Relay: el backend del cliente, `watch` por WebSocket, cuotas y límite de peticiones | 1 |
| C5 | App: Ajustes › Cuenta (entrar con la cuenta de KaiCorp Labs, dispositivos y salir; el registro y el segundo factor se hacen en la app de cuenta), alta de un equipo nuevo por la cuenta y estado de la sync en tiempo real | 1 |
| C6 | Despliegue en el minipc (solo en el tailnet), prueba de punta a punta con 3 dispositivos × carpeta, S3 y relay, notas, guía y beta | 0,5 |

## Etapa 5 · v0.7, abierto: el servidor en producción

El servidor sale del tailnet para que entre gente de fuera del equipo, al estándar de los demás servicios de la casa.

| # | Hito | Semanas |
|---|---|---|
| M1 | Dirección pública por el túnel de Cloudflare, con el WebSocket a través de él (pings por debajo del límite de inactividad). Es la dirección estable que guardan los clientes, así que se decide aquí si va bajo `kaicorplabs.com` o bajo un dominio propio de OpenWard | 0,5 |
| M2 | Al estándar de la casa: copias nocturnas comprobadas, vigilancia, el borrado de una persona también en OpenWard e imágenes firmadas | 0,5 |
| M3 | Términos y privacidad (hay datos de personas de fuera), la membresía de OpenWard para quien la pida, notas y beta | 0,5 |

**Supabase en la nube no hace falta para esto.** Solo tendría sentido si un día el minipc se queda corto. Como el servidor no usa nada exclusivo de Supabase, mover la identidad o la base a otro sitio sería trabajo de operación, no de código.

## Después de este plan

Lo que queda para lanzar y que este plan no hace:
- **Web y distribución:**
  - la web (bajo `kaicorplabs.com` o en un dominio propio, la misma decisión que en M1) y la documentación pública;
  - firma y notarización en macOS y firma en Windows;
  - actualizaciones automáticas (Sparkle, WinSparkle);
  - Flatpak, AppImage y .deb; winget y Scoop.
- **Repositorio:**
  - el repo público, con la CI completa;
  - el canal de `SECURITY.md`;
  - la lista «Siempre gratis», cerrada.
- **Legal:** el análisis de la Ley de Ciberresiliencia (CRA).
- **Cobro:**
  - el plan de pago de la sync alojada, en el repositorio privado `openward-cloud`;
  - auditoría externa del cifrado y la sync antes de cobrar por ella.
- **Producto:**
  - informes de fallos con consentimiento y un canal de opiniones;
  - Git como backend, el agente SSH y la CLI `ow`;
  - cuentas internas del servidor autoalojado, para quien no tenga un proveedor OIDC.
- **Móvil:** Android e iOS. Antes, el spike S1.2 (el motor en dispositivos reales): es la condición pendiente de [ADR-002](../adr/ADR-002-motor-de-terminal.md).

## Decisiones por defecto (a confirmar)

1. La etapa 1 va antes que la v0.4, por los datos nuevos de los hosts; D0–D2 van en paralelo.
2. Mosh en escritorio con el `mosh-client` instalado en el equipo (revisión de ADR-009); el cliente clean-room sigue para el móvil y Windows.
3. Autocompletado local, sin IA; la IA llega en la fase 3.
4. La sync gratuita (carpeta, S3, WebDAV) va antes que el servidor; Git, después.
5. Las cuentas de OpenWard son las de KaiCorp Labs: una sola cuenta para todas las apps de la casa, con su registro, segundo factor y membresías.
6. La cuenta identifica, no descifra: la contraseña maestra no sale del equipo, ni siquiera derivada.
7. El servidor es un cliente OIDC genérico y la app no habla nunca con el emisor: entra a través del servidor.
8. La base de datos de OpenWard va aparte de la de la identidad.
9. En el minipc y solo en el tailnet hasta la etapa 5.
10. Se sincroniza todo el vault menos el historial y los registros.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| FIDO2 difícil de probar en la CI | Un autenticador por software en las pruebas automáticas y una llave real a mano antes de cerrar P3 |
| Touch ID y el Secure Enclave exigen una app firmada con Developer ID | Comprobarlo la primera semana de D4 (ya está en los riesgos de la v0.4); si hace falta, la cuenta de desarrollador de Apple antes de lo previsto |
| Mosh: falta `mosh-client` o el UDP está bloqueado | Se detecta y se vuelve a SSH con tmux, con un aviso claro |
| Las codificaciones heredadas confunden al motor | Traducir en el núcleo antes del motor; pruebas con vttest en Latin-1 y CP437 |
| El merge pierde datos con almacenamiento «tonto» | La puerta de ADR-005 (`proptest`) antes de la interfaz; iCloud y Dropbox probados con sus conflictos reales |
| Un fallo de la identidad deja a OpenWard sin cuentas, y a las demás apps también | La sync por carpeta o S3 no depende de ella, y lo ya sincronizado sigue en cada equipo; la identidad ya tiene copias y vigilancia |
| Cloudflare corta los WebSocket inactivos | Pings por debajo del límite y reconexión del `watch` sin perder el cursor |
| El minipc se queda corto (Intel N150, 32 GB, con los demás servicios) | Medir en C6 con el equipo; los segmentos pueden pasar a almacenamiento S3 sin tocar el cliente |
| Confundir el acceso a la cuenta con la contraseña del vault | Dos nombres distintos en la interfaz («tu cuenta de KaiCorp Labs» y «la contraseña del vault»); el correo de recuperación de la cuenta no promete nunca recuperar el vault |
