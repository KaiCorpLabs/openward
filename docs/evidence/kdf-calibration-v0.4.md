# Calibración KDF · corrección de v0.4

13 de noviembre de 2026. Seguimiento: [D8 #37](https://github.com/KaiCorpLabs/openward/issues/37).

## Regresión confirmada

La [CI de D8](https://github.com/KaiCorpLabs/openward/actions/runs/43323082739)
midió Windows en **1006,1 ms**, con 128 MiB y 16 pasadas. La calibración anterior
aceptaba cualquier medida >=500 ms, sin comprobar el extremo superior de 1 s.
Al agotar las pasadas de 64 MiB también duplicaba la memoria manteniendo las
pasadas, por lo que podía saltarse todo el intervalo buscado.

## Corrección

La calibración compartida por Windows, macOS y Linux busca una medida real
entre 500 y 1000 ms, con objetivo 750 ms. Los resultados rápidos y lentos acotan
las pasadas posibles de cada nivel de memoria. Se recalculan las pasadas
al aumentar memoria y se vuelve a medir; un exceso de tiempo reduce las
pasadas y se mide de nuevo. Nunca se devuelve una estimación como medida.

Se mantienen Argon2id v19, una lane, mínimo 64 MiB, máximo 256 MiB, 1–16 pasadas
y memoria×pasadas <= 2 GiB. La búsqueda no repite configuraciones y termina
tras un máximo de 12 medidas. Ante tiempos inestables o hardware que no pueda
cumplir con estos límites, devuelve su resultado medido más cercano al objetivo;
los errores de reserva/derivación se propagan. No reduce el suelo de seguridad
para hacer caber un equipo lento en el intervalo.

Esto afecta a nuevas altas y cambios de contraseña que llaman a `calibrate()`.
Los vaults existentes conservan los parámetros con los que se crearon; no hay
migración de formato ni modificación automática de sus credenciales.
Cambios de carga pueden alterar el tiempo de desbloqueo posterior.

## Pruebas y evidencia

Siete pruebas deterministas, sin esperas ni dependencias de la velocidad del
runner, cubren el salto de memoria de Windows, excesos de tiempo en ambos
niveles, extremos inclusivos, hardware lento/rápido, reloj de resolución nula,
ruido, agotamiento de las 12 medidas y propagación de errores.

La prueba release `calibrated_password_measurement` **falla** si el resultado
real queda fuera de 500–1000 ms. La CI la ejecuta en los tres sistemas, además
de las pruebas criptográficas, de vault, de app y de carga de 10.000 ítems.

Medición local preliminar, Apple M5 arm64/macOS 27.2, Rust 1.99.0:
**706,205375 ms, 128 MiB, 16 pasadas**. Es una medición de este equipo; no sustituye
la evidencia de Windows. Los resultados del commit final y el enlace de CI se
registran en #37 antes de cerrar su puerta KDF.

```sh
# Desde core/
cargo test --locked -p openward-crypto password::calibration::tests
cargo test --release --locked -p openward-crypto calibrated_password_measurement -- --ignored --nocapture
```

Las puertas de migración personal, recuperación independiente, semana de uso
y autenticación física siguen abiertas. Esta corrección no publica una release.
