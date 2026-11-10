# Spike S4 (primera parte) — El sobre v1 y el merge

- **Estado:** cerrado (2026-11-09). Medido en macOS y en la CI de Linux, Windows y macOS. La decisión que propone está en el §7, aceptada con ADR-005 el 2026-11-10.
- **Fecha:** 2026-11-09.
- **Decide:** el formato del sobre `v: 1` que escribe la v0.4 y el merge de [ADR-005](../adr/ADR-005-sync-por-registros-de-dispositivo.md). Es D2 de la [v0.4](../plan/v0.4.md). La segunda parte de S4 (los backends de verdad, carpeta y S3) es el hito S1 de la v0.5.
- **Código:** [`spikes/s4-sync/`](../../spikes/s4-sync/).

## 1. Pregunta

La v0.4 cifra el vault ítem a ítem con el mismo sobre que la v0.5 va a sincronizar, para no migrar dos veces. Antes de escribir `openward-crypto` (D3) hay que saber si ese sobre lleva lo que la sync necesita y si el merge de ADR-005 funciona:
- **¿Qué campos lleva el sobre `v: 1`,** cuánto pesa y cuánto cuesta abrir 10.000 al desbloquear?
- **¿Converge el merge a tres bandas** de ADR-005 (DAG de revisiones, merge por campo desde el ancestro común y, si los dos lados cambian el mismo campo, gana el reloj híbrido más reciente) sin perder escrituras?
- **¿Y cuando faltan revisiones antiguas?** ADR-005 poda los registros cuando todos los equipos han leído «o vence la retención»: un equipo que vuelve después de la poda no tiene el historial.

## 2. Hipótesis

| # | Hipótesis | Cómo se refuta | Resultado |
|---|---|---|---|
| H1 | El sobre de ARCHITECTURE §4.2 lleva lo que la sync necesita y nada del ítem en claro | Que el simulador necesite algo más fuera del cifrado | **Se mantiene,** con dos cambios: la revisión no es un campo y el AAD es la cabecera entera ([§5](#5-el-sobre-v1)) |
| H2 | Abrir 10.000 ítems cabe en los 300 ms de la puerta de la v0.4 | Medirlo | **Sí sin firmas** (92–146 ms en la CI). Comprobando cada firma, **no** (603–636 ms): las firmas se comprueban al llegar, no al desbloquear |
| H3 | El merge a tres bandas converge y no pierde escrituras con el historial entero | Una ejecución de `proptest` que diverja o pierda una escritura | **Refutada:** pierde escrituras cuando un campo vuelve a su valor anterior en un lado ([§6.3](#63-por-qué-falla-el-merge-a-tres-bandas)) |
| H4 | Tras podar los registros, el merge sigue siendo correcto | Un equipo que vuelve después de la poda | **Refutada para tres bandas** (deshace el trabajo de los demás). **Se mantiene con relojes de campo** |
| H5 | El reloj híbrido mantiene el orden causal con relojes de pared desfasados (±2 min) y uno muy adelantado | Que gane una escritura que otro ya había visto y sobrescrito | **Se mantiene,** si cada campo se escribe con un reloj posterior al que sustituye |
| H6 | 3 equipos × 10.000 escrituras convergen, en tiempos razonables | La ejecución larga | **Se mantiene con relojes de campo** (0,17–0,19 ms por escritura en la CI). Tres bandas pierde escrituras y, con un solo ítem, es de 15 a 17 veces más lento |

## 3. Alcance

**Dentro:**
- el sobre `v: 1` con criptografía de verdad: XChaCha20-Poly1305, Ed25519 y SHA-256;
- el cuerpo real de un host (`openward-proto`) para los tamaños y el desbloqueo;
- el reloj lógico híbrido, el DAG de revisiones y dos merges;
- tres equipos en memoria con registros que solo crecen, lecturas a trozos y en cualquier orden, relojes desfasados y poda con instantánea;
- un oráculo que dice, para cada campo, qué escrituras deben poder quedar.

**Fuera:**
- los backends (carpeta, S3, WebDAV): son la v0.5;
- los segmentos `.seg` firmados y los cursores de lectura: un registro aquí es una lista de sobres;
- la jerarquía de claves y los certificados de dispositivo: una sola clave de vault (`key_gen` 1) y un registro de claves públicas de los equipos;
- la UI de conflictos: aquí solo se cuentan.

## 4. Montaje

- **`spikes/s4-sync/syncsim`**, una biblioteca y un CLI en Rust:
  - `envelope.rs`, el sobre; `hlc.rs`, el reloj; `fields.rs`, el cuerpo como rutas y valores; `dag.rs`, el DAG y los dos merges; `sim.rs`, los equipos y el oráculo;
  - `syncsim sizes`, `unlock` y `runs` dan los números; sin argumentos, los tres.
- **Los dos merges:**
  - **a tres bandas,** el de ADR-005: desde el ancestro común más bajo de las cabezas (si hay varios, su propio merge, como la estrategia recursiva de Git; si no hay ninguno, todo lo distinto es conflicto), un campo cambiado en un solo lado se queda con ese lado; cambiado en los dos, gana la cabeza con el reloj más reciente;
  - **por relojes de campo,** el propuesto: cada revisión lleva, para cada campo, el reloj de la escritura que lo puso. El merge se queda, campo a campo, con el más reciente; si empatan, con el valor mayor. Es un mapa «gana la última escritura», un CRDT: no necesita el historial.
- **Los equipos:** tres, que escriben solo en su registro y leen los de los demás a trozos (de 1 a 3 sobres cada vez en las pruebas). Un sobre puede llegar antes que su padre. La poda («compactar») la hace un equipo: lee todo, deja una instantánea con sus cabezas y el almacenamiento borra los registros hasta ahí. Quien se quedó atrás carga la instantánea.
- **El oráculo:** el simulador apunta, aparte del formato, qué había visto cada equipo de cada ítem al escribir (un vector de versiones por ítem). Al final, todos leen todo y, para cada campo de cada ítem:
  - todos los equipos tienen que ver lo mismo;
  - el valor tiene que ser el de una de las «últimas escrituras»: las que ninguna otra escritura de ese campo había visto. Si solo hay una, tiene que ser esa.
- **`proptest`** genera escrituras (también vaciar un campo), envíos, lecturas a trozos, esperas y podas, con relojes de pared desfasados hasta ±2 minutos. Un equipo no sigue un reloj que va más de 60 s por delante del suyo.
- **La CI** lo corre en los tres sistemas (job «Spike S4 sync»): las pruebas (2.000 ejecuciones aleatorias) y las medidas. Si una ejecución con relojes de campo diverge o pierde una escritura, el job falla.

## 5. El sobre v1

```text
{ v: 1, ct, sig, item, nonce, vault, device, key_gen, parents }
```

| Campo | Qué es |
|---|---|
| `v` | 1 |
| `vault`, `item`, `device` | 16 bytes cada uno (UUID) |
| `key_gen` | La generación de la clave del vault |
| `parents` | Las revisiones de las que sale, en orden y sin repetir: una al editar, varias al editar un ítem con varias cabezas, ninguna al crearlo |
| `nonce` | 24 bytes aleatorios (XChaCha20) |
| `ct` | XChaCha20-Poly1305 del texto en claro, con la cabecera como AAD |
| `sig` | Ed25519 del dispositivo sobre un contexto y el sobre sin `sig` |

- **CBOR determinista** (RFC 8949 §4.2.1): longitudes definidas, enteros en su forma más corta y claves ordenadas. Lo que no está en esa forma se rechaza, para que la firma y la revisión cubran un único valor.
- **La revisión es el contenido:** su id es SHA-256 de un contexto y el sobre sin `sig`. No es un campo, así que nadie puede nombrar una revisión con un contenido que no es el suyo, y dos equipos no pueden chocar con el mismo número.
- **El AAD es la cabecera entera** (`v`, `vault`, `item`, `device`, `key_gen`, `parents`) en CBOR canónico, no solo `vault_id‖item_id‖rev‖key_gen`. El texto cifrado solo se abre en su sitio del DAG, aunque nadie compruebe la firma. La revisión no puede ir en el AAD, porque sale del texto cifrado.
- **En claro solo va lo que la sync necesita para colocarlo.** El tipo, los nombres, las direcciones y las horas van dentro.

**El texto en claro** (dentro de `ct`):

```text
{ hlc, body, base, clocks, unset }
```

- `hlc`: el reloj de la escritura. Va dentro para que el servidor no vea cuándo cambian los ítems.
- `body`: el mismo CBOR del cuerpo que hoy va en `v: 0`. `openward-proto` no cambia.
- `base`, `clocks` y `unset`: el reloj de cada campo. `base` es el más antiguo, `clocks` solo tiene los campos escritos después y `unset` los que una escritura vació, con su reloj. Un ítem recién creado lleva `clocks` vacío.

**Los campos de un cuerpo** son rutas: un mapa anidado da rutas (`settings` › `port`), y las listas y los valores simples son hojas. El merge no necesita saber el tipo del ítem, así que también funciona con los campos que añada una versión más nueva.

## 6. Resultados

### 6.1 Tamaños

Un host típico (usuario, puerto, un salto, sistema), con un padre:

| | Bytes |
|---|---|
| Cuerpo (CBOR de `openward-proto`) | 254 |
| Sobre `v: 0` de hoy | 265 |
| Sobre `v: 1`, tres bandas | 520 |
| Sobre `v: 1`, relojes de campo | 549 |
| … tras editar tres campos en otros momentos | 604 |
| … con dos padres (un merge) | 638 |

- El sobre añade unos 230 bytes: la firma (70), los tres ids (unos 70), un padre (43), el nonce (31) y el resto de claves. El cifrado añade 16 y los relojes de campo, unos 30 más 18 por campo editado.
- **10.000 hosts pasan de 2,2 MB a 5,0 MB.** No es un problema en escritorio ni en móvil.

### 6.2 Desbloqueo: abrir 10.000 hosts

El mejor de cinco intentos. Abrir es decodificar el sobre (comprobando su forma canónica), descifrarlo y decodificar el cuerpo.

| | Este Mac (con carga) | CI macOS | CI Linux | CI Windows |
|---|---|---|---|---|
| `v: 0` de hoy | 19–35 ms | 38 ms | 46 ms | 55 ms |
| `v: 1` | 51–115 ms | 92 ms | 127 ms | 146 ms |
| `v: 1` sin volver a comprobar la forma | 46–110 ms | 86 ms | 115 ms | 130 ms |
| `v: 1` y cada firma | 286–860 ms | 636 ms | 603 ms | 619 ms |
| `v: 1` y las firmas en lote | 122–334 ms | 231 ms | 286 ms | 323 ms |

- **Sin firmas cabe de sobra** en los 300 ms de la puerta de la v0.4, que se cuentan después de derivar la contraseña.
- **Comprobar cada firma al desbloquear no cabe,** y en lote se come casi todo el margen (en el runner de Windows, lo pasa). No hace falta: el AEAD ya autentica cada sobre con la clave del vault, y la firma dice qué equipo lo escribió, que importa al recibirlo (la sync de la v0.5 y los permisos de los equipos de la v0.6). **Las firmas se comprueban al llegar,** y el vault local solo guarda sobres ya comprobados.
- El Mac de las medidas tenía otros procesos en marcha (carga media de 5 a 6), y por eso sus tiempos van en rangos. Los de la CI son la referencia, y son los de [`results/`](../../spikes/s4-sync/results/). Los runners son más lentos que un equipo de escritorio.

### 6.3 Por qué falla el merge a tres bandas

**Con el historial entero** (`proptest` lo encuentra enseguida; reducido a mano son once pasos, la prueba `three_way_brings_back_an_unset_that_both_devices_had_undone`):
1. El equipo C vacía la etiqueta. El B también la vacía sin haber visto lo de C, y después la vuelve a poner. El A ve lo de C y vuelve a poner la etiqueta.
2. Las dos vaciadas las deshizo alguien que las había visto. La etiqueta tiene que quedarse.
3. Pero A, al juntar su lado con la vaciada de B, compara con el ancestro común (el ítem recién creado): en el lado de A la etiqueta «no cambió», porque pasó de un valor a vacío y volvió. Gana la vaciada de B. A B le pasa lo mismo con la de C.
4. Las dos guardan el resultado en su siguiente revisión, y la etiqueta acaba vacía en todos los equipos.

El merge a tres bandas solo ve el ancestro común y las cabezas, no lo que pasó entre medias. En las ejecuciones largas con 50 ítems pierde 3 escrituras de 10.000, las mismas en los tres sistemas. **Converge igual:** todos los equipos acaban con el mismo valor equivocado, así que una prueba que solo mire la convergencia no lo ve.

**Con los registros podados** (la prueba `back_after_the_logs_were_pruned_three_way_reverts_the_label`):
1. C se va. A y B cambian la etiqueta. A poda los registros.
2. C, sin conexión, cambia el puerto, y vuelve: carga la instantánea con la cabeza de B, pero sin los padres de esa cabeza.
3. C no encuentra un ancestro común, así que todo lo distinto es conflicto, y su cabeza es la más reciente: **vuelve a poner la etiqueta antigua**. Además diverge: A y B, que sí tienen el historial, ven otra cosa.

**Con relojes de campo** las dos situaciones salen bien: la etiqueta que A volvió a poner lleva un reloj posterior a la vaciada que vio, y la etiqueta antigua de C lleva el reloj de cuando se escribió, no el de su última revisión.

### 6.4 Relojes

- Un campo se escribe con el reloj del equipo **o con el siguiente al del campo que sustituye**, el que sea mayor. Así gana siempre la escritura que vio a la otra, aunque el reloj de pared de su equipo vaya atrasado (prueba con 10 minutos) o no haya seguido un reloj adelantado.
- Un equipo **no sigue un reloj que va más de 60 s por delante** del suyo. Sin ese límite, un equipo con la fecha mal puesta arrastraría a todos a su futuro para siempre. Sus escrituras se aplican igual, y pierden ante la siguiente que las vea (prueba con un reloj un día adelantado).
- Si dos equipos escriben el mismo campo sin verse, gana el reloj más reciente, como decía ADR-005. Si empatan (mismo milisegundo y mismo contador), gana el valor mayor, y todos los equipos eligen el mismo.

### 6.5 Convergencia

- **`proptest`, relojes de campo:** 2.000 ejecuciones en cada pasada de la CI, y 60.000 en local (tres pasadas de 20.000), de hasta 150 operaciones con poda y relojes desfasados. Todas convergen y ninguna pierde una escritura.
- **Las ejecuciones largas:** 3 equipos, 10.000 escrituras, lecturas a trozos de hasta 40 sobres y uno de los equipos 40 s adelantado y otro 25 s atrasado.

| Merge | Ítems | Podas | Resultado | µs por escritura (CI Linux) | Avisos de conflicto |
|---|---|---|---|---|---|
| Relojes de campo | 50 | 0 | Bien | 170 | 7 |
| Tres bandas | 50 | 0 | **3 escrituras perdidas** | 191 | — |
| Relojes de campo | 50 | 3 | Bien | 170 | 7 |
| Tres bandas | 50 | 3 | **3 escrituras perdidas** | 193 | — |
| Relojes de campo | 1 | 0 | Bien | 168 | 3 |
| Tres bandas | 1 | 0 | Bien en esta semilla | 2.546 | — |
| Relojes de campo | 1 | 3 | Bien | 166 | 3 |
| Tres bandas | 1 | 3 | Bien en esta semilla | 2.596 | — |

- El tiempo por escritura incluye sellarla y firmarla, y que los otros dos equipos la comprueben, la descifren y la junten. Lo que más pesa es Ed25519.
- **Con relojes de campo, el coste no depende del historial.** Con tres bandas, buscar el ancestro común recorre el historial del ítem: con todas las escrituras en un solo ítem es de 15 a 17 veces más lento (de 11 en el Mac).
- **Los avisos de conflicto** son escrituras al mismo campo sin verse, donde una perdió. Se calculan con el DAG: lo que perdió no está en la historia de lo que ganó. Es lo que la UI de la v0.5 enseñaría con «la versión que perdió».

### 6.6 Lo que encontró el oráculo

La primera versión del oráculo llevaba un solo vector de versiones por equipo, para todo el vault, y `proptest` encontró un «fallo» de los relojes de campo que no lo era: leer una revisión de un ítem no te da el estado de otro. Ahora va por ítem. **Para la v0.5:** las pruebas de `openward-sync` tienen que razonar la causalidad por ítem, igual que el merge.

## 7. Decisión propuesta

1. **El sobre `v: 1` del §5:** `{v, vault, item, device, key_gen, parents, nonce, ct, sig}` en CBOR canónico, que se rechaza en cualquier otra forma.
   - **La revisión es el SHA-256 del sobre sin firma** y no un campo. `parents` nombra revisiones así.
   - **El AAD es la cabecera entera,** no `vault_id‖item_id‖rev‖key_gen`.
   - **La firma Ed25519 del dispositivo,** con contexto, en cada sobre: dice quién lo escribió también cuando el sobre viaja en una instantánea de otro equipo.
2. **Dentro de `ct`:** `{hlc, body, base, clocks, unset}`, con el cuerpo de hoy sin cambios.
3. **El merge por relojes de campo** en lugar del merge a tres bandas. Se queda el DAG, para el historial de un ítem y para los avisos de conflicto, pero el merge no lo necesita, así que podar los registros es seguro.
4. **Cada campo se escribe con un reloj posterior al que sustituye,** y el reloj híbrido no sigue a otro que vaya más de 60 s por delante.
5. **Las firmas se comprueban al recibir un sobre,** no al desbloquear. El vault local guarda solo sobres comprobados y, al desbloquear, no vuelve a comprobar la forma canónica.
6. **Borrar es escribir un campo `deleted`** que gana o pierde como cualquier otro: lleva el ítem a la papelera, de donde se recupera con otra escritura. Un borrado definitivo, con lápida, queda para cuando haga falta.

**Límites que se aceptan:**
- **Una lista es un solo valor:** si dos equipos añaden etiquetas a la vez, gana una de las dos listas, con aviso de conflicto. Si molesta, las etiquetas pasan a ser un mapa (`{nombre: true}`), y cada una se fusiona por separado.
- **`modified`** cambia en cada escritura, así que dos ediciones simultáneas de campos distintos siempre «chocan» en él. No es un conflicto que enseñar: lo puede dar el reloj más reciente.

**Qué cambia si se acepta:**
- [ADR-005](../adr/ADR-005-sync-por-registros-de-dispositivo.md): el merge (ya actualizado en este cambio, con estado «propuesto»).
- [ADR-004](../adr/ADR-004-vault-y-jerarquia-de-claves.md): el AAD (ya actualizado).
- [ARCHITECTURE](../ARCHITECTURE.md) §4.2 (el sobre y la tabla, que guarda cabezas y no una revisión por ítem), §5 (el AAD) y §6.1 (el merge).
- [THREAT_MODEL](../THREAT_MODEL.md): la garantía de que nadie cambia un ítem sin que se note y la invariante I-3, con la cabecera en vez de `rev`.

## 8. Lo que queda

- **D3 (`openward-crypto` y el vault cifrado):** el sobre y el texto en claro de este spike, con vectores propios (los de `syncsim` sirven de punto de partida). La tabla guarda las revisiones y marca las cabezas; cuántas revisiones antiguas guardar en el equipo lo decide D3.
- **v0.5, S1 (`openward-sync`):** los segmentos firmados, los cursores, la instantánea y la poda de verdad, con estas mismas pruebas de convergencia sobre carpeta y S3. Es la puerta de ADR-005 que falta.
- **v0.6:** los permisos de escritura de los equipos se comprueban con la firma de cada sobre, contra el manifiesto.
