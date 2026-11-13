# Jerarquía y registros de claves v1

D3, ADR-004. Implementación Rust en `openward-crypto`; no se exportan claves
ni texto descifrado a Dart. La activación en la app corresponde a D4, y el kit,
el cambio de contraseña y el paquete remoto de cuenta, a D5.

## Jerarquía

La cuenta contiene dos semillas independientes de 32 bytes: Ed25519 para
certificar y X-Wing para recibir claves. La segunda es el IKM de
`DeriveKeyPair`, no una representación intercambiable de otra biblioteca.
Cada dispositivo tiene su propia semilla Ed25519 y un certificado de cuenta
que vincula cuenta, UUID, clase de firmante y clave pública. Clase 1 significa
Ed25519 software; clases futuras de hardware se rechazan hasta implementarlas.
La revocación y los permisos de miembros requieren el manifiesto futuro.

Cada generación tiene una clave aleatoria independiente de 32 bytes. Se
envuelve con HPKE base / HKDF-SHA256 / ChaCha20-Poly1305, y la cuenta firma el
envoltorio. Info y AAD vinculan suite, cuenta, vault y generación. La
generación cero y las posiciones/firmas ajenas se rechazan.

Suites versionadas, sin negociación ni downgrade automático:

| Tag | KEM y construcción | PK / enc |
|---|---|---|
| 1 | `0x647a`, X-Wing draft-06, HPKE PQ draft-05; contrastado con vectores X-Wing draft-11 | 1216 / 1120 bytes |
| 2 | `0x0020`, DHKEM(X25519), RFC 9180 | 32 / 32 bytes |

## Registros binarios

Todos empiezan por cuatro bytes ASCII de magic y un byte de versión `1`.
Enteros multibyte en big endian; UUID de 16 bytes; firmas de 64. `blob` es una
longitud u16 seguida de exactamente esos bytes. No se admiten bytes finales,
versiones desconocidas ni longitudes mayores que las de la implementación.

| Magic | Campos después de versión |
|---|---|
| OWAP | suite:u8, signing_public:32, kem_public:según suite |
| OWDC | account_id:32, device:16, signer_kind:u8, signing_public:32, signature:64 |
| OWVK | suite:u8, vault:16, generation:u32, account_id:32, enc:según suite, ciphertext:48, signature:64 |
| OWKB | memory_kib:u32, passes:u32, salt:16, nonce:24, blob(ciphertext) |
| OWVH | vault:16, device:16, generation:u32, blob(OWAP), blob(OWDC), blob(OWVK), blob(OWKB) |

`account_id` es SHA-256 de OWAP completo. La firma OWDC usa el dominio
`openward device certificate v1\0` y el registro sin firma. Info/AAD de OWVK
usan `openward vault generation v1\0` seguido del prefijo hasta account_id;
la firma cubre esos bytes, enc y ciphertext. La apertura comprueba el contexto
esperado y la firma antes de desencapsular.

## Derivación y envoltorio local

Argon2id v19, salida 32 bytes, salt aleatorio de 16 bytes, una lane.
Memoria entre 64 y 256 MiB, pases entre 1 y 16, memoria×pases como máximo
2 GiB de trabajo. Se validan parámetros antes de reservar. La calibración
busca 0,5–1 s (objetivo 750 ms), comprobando ambos extremos. Acota las
pasadas con medidas reales y las reduce si hay un exceso de tiempo. Al subir
de 64 a 128 o 256 MiB las reescala respetando el presupuesto de trabajo; cada
configuración propuesta se mide antes de aceptarla. Máximo 12 medidas, sin
repetir configuraciones. Si el suelo/tope o tiempos inestables impiden cumplir,
devuelve el resultado medido más cercano al objetivo y propaga los errores.
La prueba release de CI exige 500–1000 ms en los tres runners. [Regresión,
algoritmo y pruebas](../docs/evidence/kdf-calibration-v0.4.md).

Las altas y cambios de contraseña usan esta calibración. La apertura de un
vault existente sigue usando sus parámetros guardados; no se alteran el formato
ni las credenciales anteriores. El tiempo puede variar con la carga posterior.

Contraseñas de 1–4096 bytes, sin normalización implícita. La UI de D4 aplica
la política de fuerza. OWKB usa XChaCha20-Poly1305 con nonce aleatorio y el
dominio `openward local key box v1\0`, su prefijo completo y el contexto del
llamador como AAD. Máximo 4096 bytes de secreto y 8192 de contexto.
OWVH cifra las semillas de cuenta (64 bytes) y dispositivo (32), y autentica
todos sus campos públicos/certificados/envoltorios. La apertura reconstruye
y contrasta las claves públicas antes de entregar la clave del vault.

**OWVH/OWKB son locales.** No son el paquete remoto de cuenta de D0-1:
ese paquete necesita contraseña **y** secreto de kit combinados con HKDF,
y se implementa en D5. No se debe sincronizar el envoltorio local con la KEK.

Las semillas, KEK, salida descifrada y memoria de trabajo completa de Argon2
usan `Zeroizing`; hpke-rs borra su tipo de clave privada al destruirlo. No
hay Debug/Clone en los tipos propios que contienen secretos. Los registros
codificados solo contienen claves públicas o ciphertext.

## Evidencia y dependencias

Los tres archivos de S6 se conservan en `tests/vectors/`, con sus fuentes
originales en `docs/spikes/S6-hpke.md` §4. Se comprueban emisor/receptor,
exportaciones RFC 9180/PQ, KEM draft-11 e interoperabilidad con `hpke` 0.15.1
en ambas direcciones. Argon2id pasa RFC 9106 §5.3; su vector pequeño no
rebaja el suelo del API de producción. Hay pruebas de contextos ajenos,
contraseña equivocada, truncado, alteración y rewrap sin cambiar los ítems.

Medición local release del 12-11-2026: 128 MiB, 16 pases, una lane, **695 ms**.
Es una medición de este equipo, no una promesa de latencia universal.

El lock añade 52 paquetes contando desarrollo/build, sin actualizar las
resoluciones anteriores de Windows. Los nuevos grupos de producción/build
son hpke-rs/crypto/libcrux 0.8.0, libcrux {aead,aes,chacha20poly1305,
curve25519,ecdh,hacl-rs,hkdf,hmac,hmac-drbg,intrinsics,kem,macros,ml-kem,
p256,p384,platform,poly1305,secrets,sha2,sha3,traits}, hax/core-models y sus
macros. Desarrollo incorpora hpke 0.15.1, x-wing 0.1.1, x25519-dalek 3.0.0,
shake/turboshake y herramientas de generación; las versiones transitivas
exactas y checksums están en `core/Cargo.lock`.

`RUSTSEC-2026-0173` es el aviso de mantenimiento aceptado por S6 para
proc-macro-error2 dentro de las macros de hax; la excepción de `deny.toml`
se revisa en cada actualización de libcrux. No se añaden otras excepciones.
La revisión criptográfica externa permanece como puerta previa a Cloud.
