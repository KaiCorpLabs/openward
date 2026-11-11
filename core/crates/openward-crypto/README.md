# openward-crypto

Primer bloque de D3: el sobre v1 de [ADR-004](../../../docs/adr/ADR-004-vault-y-jerarquia-de-claves.md)
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

Quedan en [D3](https://github.com/KaiCorpLabs/openward/issues/32): jerarquía de
cuenta/dispositivo, HPKE/X-Wing y sus vectores S6, KEK/Argon2id calibrado y la
migración transaccional del vault con limpieza de páginas/WAL/copias claras.
Las ocho pruebas de este bloque no cierran ese hito ni sustituyen la revisión
criptográfica externa prevista antes de Cloud.
