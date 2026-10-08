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

El proyecto está en **fase 0** y **no tiene auditoría externa**. No lo uses con credenciales reales. La arquitectura prevé una auditoría externa del núcleo criptográfico antes de lanzar la sincronización.
