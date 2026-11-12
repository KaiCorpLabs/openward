# openward-crypto

Núcleo de D3: el sobre v1 de [ADR-004](../../../docs/adr/ADR-004-vault-y-jerarquia-de-claves.md)
y [ADR-005](../../../docs/adr/ADR-005-sync-por-registros-de-dispositivo.md).
Todavía no activa el cifrado del vault ni cambia la apertura de la app.

- XChaCha20-Poly1305 por cuerpo, nonce aleatorio de 24 bytes y cabecera completa como AAD.
- Firma Ed25519 con el contexto de S4 y revisión SHA-256 del sobre sin firma,
  con su contexto separado.
- CBOR canónico de esquema fijo: longitudes definidas y mínimas, orden exacto,
  padres estrictamente ascendentes y rechazo de campos/trailing bytes.
- Límite de 64 MiB por cuerpo y 64 padres por revisión. Las declaraciones de
  longitud se validan antes de copiar; el parser no recurre ni construye valores
  CBOR genéricos.
- La apertura exige el vault, ítem y generación esperados por el almacenamiento,
  evitando aceptar un sobre válido en otra posición.
- Clave del vault y texto descifrado en `Zeroizing`; el cifrador activa su
  soporte de borrado de claves. No hay API Dart en este bloque.

La entrada desde otro dispositivo usa `Envelope::open_received`, con la clave
pública de escritor que la capa de cuenta/dispositivo haya autorizado. La lectura
local de un sobre admitido usa `open`: autentica el AEAD sin repetir la firma,
como decidió S4. La asociación dispositivo→clave pública corresponde a la capa
de cuenta y a su certificado; este módulo no la inventa.

La fixture contiene **claves públicas de prueba** y semillas deliberadamente
conocidas. La produjo el experimento S4 con nonce, clave y semilla fijos:
el módulo abre y reescribe esos bytes, reproduce firma/cifrado/revisión y
contrasta cambios, posiciones, declaraciones enormes y formas no canónicas.
Las semillas no son credenciales de usuarios.

La [jerarquía de claves](../../../spec/keys-v1.md) añade cuenta, certificado de
dispositivo, generaciones envueltas con HPKE/X-Wing y KEK/Argon2id calibrado.
Las semillas y la memoria de trabajo de Argon2 se borran al liberar sus tipos.
Los vectores publicados de S6 y RFC 9106 pasan junto a la interoperabilidad
con la alternativa de biblioteca.

La [migración del vault](../../../spec/vault-sqlite-v2.md) integra estos módulos
con SQLite cifrado, bloqueo Rust y limpieza de páginas/WAL/copias claras. La
activación desde la app depende de D4/D5. Las pruebas no sustituyen la revisión
criptográfica externa prevista antes de Cloud.
