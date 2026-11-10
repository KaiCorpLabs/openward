# Política de seguridad

OpenWard gestionará credenciales SSH, así que nos tomamos en serio cualquier vulnerabilidad, incluso en esta fase temprana.

## Cómo reportar

**No abras un issue público.** Usa el [reporte privado de vulnerabilidades de GitHub](https://docs.github.com/es/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) de este repositorio (pestaña *Security* → *Report a vulnerability*).

Incluye, si puedes:
- la versión o el commit afectado;
- los pasos para reproducirlo;
- el impacto que esperas (lectura de secretos, ejecución de código, suplantación de un host…).

## Qué puedes esperar

- Acuse de recibo en un plazo de **3 días laborables**.
- Una primera evaluación en **10 días laborables**.
- Coordinación de la divulgación: publicamos el aviso cuando hay una corrección disponible, o a los 90 días si no la hay, salvo acuerdo distinto.
- Te mencionamos en el aviso si quieres.

## Estado actual

OpenWard está en **beta** (0.3, solo escritorio) y **no tiene auditoría externa**. Hasta la v0.4 el vault va sin cifrar en el disco: no guarda secretos (las claves privadas se usan desde su archivo y las contraseñas se piden al conectar), pero sí los hosts, sus direcciones y las claves de host en las que confías. La arquitectura prevé una auditoría externa del núcleo criptográfico antes de lanzar la sincronización. El [modelo de amenazas](docs/THREAT_MODEL.md) dice qué protege OpenWard, de quién y qué queda fuera.
