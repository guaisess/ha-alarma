---
title: Política de privacidad de Alarma Casa
---

# Política de privacidad de Alarma Casa

_Versión 2026.11.15 · Última actualización: 23 de noviembre de 2026_

**Alarma Casa** (paquete `es.fernandezbadia.alarmacasa`) es una aplicación Android de uso personal y familiar para controlar la alarma doméstica de su desarrollador, Alfredo Fernández Badía (en adelante, «el desarrollador»), a través de su propio servidor de Home Assistant. Esta política explica qué datos usa la app y qué hace con ellos.

## 1. Resumen

- La app **no recopila datos para el desarrollador** ni los vende ni los comparte con anunciantes.
- **No contiene publicidad** ni herramientas de analítica o de informes de fallos de terceros.
- Los datos que introduces (dirección del servidor, token de acceso, código de la alarma) **se guardan solo en tu móvil** y se envían **únicamente al servidor de Home Assistant que tú configuras**.

## 2. Datos que utiliza la app

| Dato | Para qué | Dónde se guarda |
|---|---|---|
| Dirección (URL) de tu Home Assistant y entidad de la alarma | Conectar con tu alarma | En el móvil |
| Token de acceso de larga duración de Home Assistant | Autenticarse en tu servidor | En el móvil, en almacenamiento cifrado (Android Keystore) |
| Código de desarmado | Desarmar la alarma cuando lo pides | En el móvil, en almacenamiento cifrado |
| Nombre del móvil (que tú escribes) | Identificar tu dispositivo al registrar las notificaciones | En el móvil y en tu servidor de Home Assistant |
| Estado de la alarma, zonas y sensores | Mostrarlos en la app y en los widgets | En el móvil (caché temporal) |
| Historial de cambios de estado (máx. 100 entradas) | Mostrarlo en la pantalla Historial | En el móvil; se puede borrar desde la app |
| Token de notificaciones (Firebase Cloud Messaging) | Recibir avisos de la alarma | En el móvil, en Google Firebase y en tu servidor de Home Assistant |
| Preferencias (tema, modos de armado, tiempo de espera) | Personalizar la app | En el móvil |

La app **no accede** a tu ubicación, contactos, fotos, micrófono, cámara ni mensajes.

## 3. Con quién se comparten los datos

- **Tu servidor de Home Assistant**: la app envía a la dirección que configuras tus órdenes (armar, desarmar), el token de acceso y el token de notificaciones con el nombre de tu móvil. Esta conexión usa HTTPS/WSS (cifrada). Ese servidor lo gestionas tú; el desarrollador no tiene acceso a él.
- **Google (Firebase Cloud Messaging)**: para entregar las notificaciones push, Google recibe el identificador de tu instalación y el token de notificaciones, según su propia política de privacidad: <https://policies.google.com/privacy>.
- **Google Play**: la distribución e instalación se realizan a través de Google Play, que puede tratar datos según sus condiciones.

No se comparten datos con ninguna otra persona o empresa.

## 4. Copias de seguridad

La app permite exportar un fichero de copia de seguridad de su configuración (incluye el token y el código). Ese fichero se guarda en tu móvil, en una carpeta que tú controlas, y **es tu responsabilidad custodiarlo**. La app desactiva las copias de seguridad automáticas de Android en la nube para estos datos.

## 5. Seguridad

El token y el código se guardan cifrados con el almacén seguro de Android. Las conexiones con Home Assistant son siempre cifradas (la app no admite HTTP sin cifrar). Recomendamos usar un token exclusivo para la app y revocarlo desde Home Assistant si pierdes el móvil.

## 6. Conservación y eliminación

Los datos permanecen en tu móvil mientras tengas la app instalada. Puedes borrar el historial desde la propia app. **Al desinstalar la app o borrar sus datos desde los ajustes de Android, se eliminan todos los datos locales.** Para eliminar el token de notificaciones y el nombre de tu móvil de tu servidor, bórralos de tu instalación de Home Assistant. Para revocar el acceso, elimina el token de larga duración en tu perfil de Home Assistant.

## 7. Menores

La aplicación no está dirigida a menores de edad ni recopila datos de ellos de forma consciente.

## 8. Cambios en esta política

Si la política cambia, se publicará aquí una nueva versión con su fecha.

## 9. Contacto

Alfredo Fernández Badía · alfredo.fernandezbadia.es@gmail.com
