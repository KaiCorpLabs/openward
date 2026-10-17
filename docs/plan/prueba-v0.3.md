# Prueba de la v0.3

La [v0.3](v0.3.md) cierra la fase 1. Su puerta de salida es esta:
- el equipo crea y sube sus claves desde OpenWard;
- trabaja una semana con la paleta y el historial;
- abre su día con un espacio de trabajo;
- importa un CSV propio.

Lo que trae está en las [notas de la versión](../notas/v0.3.md).

## Instalar

Como la 0.2 ([cómo](prueba-v0.2.md#instalar)). Con Homebrew, la beta nueva llega con:

```bash
brew upgrade --cask openward
```

## Dónde guarda sus datos

En la misma carpeta que la 0.2 ([cuál](prueba-v0.2.md#dónde-guarda-sus-datos)), con un archivo más:
- `history.json`: el historial de comandos. Es de este equipo: no va al vault ni se sincroniza. Ajustes › Terminal lo apaga o lo borra.

Además, OpenWard escribe en `~/.ssh` cuando creas o importas una clave (siempre archivos nuevos), y en el `~/.ssh/authorized_keys` de un servidor cuando subes una.

## Qué probar

1. **Claves** (Biblioteca › Claves):
   - comprueba que están tus claves de `~/.ssh` con su huella (compárala con `ssh-keygen -lf`) y quién las usa;
   - crea una Ed25519 con frase de paso y otra sin ella;
   - importa una clave pegándola y otra eligiendo el archivo;
   - súbela a un servidor de prueba con «Subir a un servidor…», a un host guardado y a una dirección escrita a mano;
   - súbela otra vez y comprueba que dice que ya estaba y que `authorized_keys` no tiene la línea dos veces;
   - ponla en un host y conéctate solo con ella.
2. **Paleta** (⌘⇧P o ⌘P):
   - haz con ella lo que sueles hacer con el ratón: dividir, abrir SFTP, ir a una página, abrir un host;
   - prueba a escribir solo unas letras («sftp», «dder», el nombre de un host).
3. **Historial:**
   - trabaja como siempre y, al rato, busca en la paleta un comando de antes y repítelo, con Intro y con ⌥Intro;
   - haz `sudo` y comprueba que la contraseña no aparece en la paleta;
   - empieza un comando con un espacio y comprueba que no se guarda;
   - dinos qué comandos echas en falta (con Tab, con las flechas, en prompts de varias filas) y cuáles sobran.
4. **Espacios de trabajo:**
   - abre tus pestañas de cada día, divide los paneles como los quieras y guárdalas («Guardar las pestañas abiertas…»);
   - cierra todo y ábrelo otra vez desde la biblioteca y desde la paleta;
   - cambia la distribución y usa «Cambiar por las pestañas abiertas»;
   - borra un host que esté en un espacio de trabajo y ábrelo: ese panel debe preguntar qué abrir.
5. **CSV** («Importar…» › CSV):
   - exporta tus hosts de una hoja de cálculo o usa la plantilla de Termius;
   - comprueba los grupos, puertos, usuarios y etiquetas, y los avisos de lo que no entra;
   - impórtalo dos veces y comprueba que no se duplica.

En Windows y Linux, ⌘ es Ctrl+Mayús: Ctrl+Mayús+P abre la paleta.

## Cómo informar

Como en la 0.2 ([cómo](prueba-v0.2.md#cómo-informar)). Para el historial, no pegues los comandos tal cual si llevan nombres de servidores internos: describe qué escribiste y qué esperabas.
