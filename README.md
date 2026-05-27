# 🏡 Alarma Casa HA

Aplicación Android para controlar la alarma de **Home Assistant** desde el móvil, con soporte completo para [Alarmo](https://github.com/nielsfaber/alarmo).

Desarrollada por **Alfredo Fernández Badía** · Bargas, Toledo · 2025

---

## Características

- ✅ Armar y desarmar con confirmación antes de ejecutar
- ✅ Estado en tiempo real (actualización automática cada 15s)
- ✅ Cuenta atrás visual durante el armado y la entrada
- ✅ Aviso de sensores abiertos que bloquean el armado
- ✅ Pantalla de configuración con prueba de conexión
- ✅ Actualizaciones automáticas desde una URL configurable
- ✅ Icono personalizado y tema oscuro

---

## Capturas

| Pantalla principal | Estado armando | Sensores abiertos | Configuración | Acerca de |
|---|---|---|---|---|
| Estado actual + botones Armar/Desarmar | Barra de cuenta atrás | Aviso en rojo con sensores | Conexión, token, código | Versión y datos del proyecto |

---

## Requisitos

### Home Assistant
- Home Assistant instalado y accesible (local o remoto)
- Integración [Alarmo](https://github.com/nielsfaber/alarmo) configurada
- Un **Long-Lived Access Token** (perfil de usuario → al final de la página)

### Para compilar
- Cuenta en [GitHub](https://github.com) (gratuita)
- Los 4 secretos de firma configurados en el repositorio (ver más abajo)

---

## Estructura del proyecto

```
ha-alarma/
├── .github/
│   └── workflows/
│       └── build.yml        # Pipeline de compilación y release
├── assets/
│   └── icon.png             # Icono de la app (1024×1024)
├── lib/
│   └── main.dart            # Código completo de la app
├── pubspec.yaml             # Dependencias y versión
├── version.json             # Control de versión para auto-update
└── README.md
```

---

## Compilación con GitHub Actions

El proyecto se compila completamente en la nube usando GitHub Actions. No es necesario instalar Flutter ni Android Studio.

### 1. Secretos necesarios

Ve a tu repositorio → **Settings → Secrets and variables → Actions** y añade:

| Nombre | Descripción |
|---|---|
| `KEYSTORE_BASE64` | Keystore en Base64 (generado una sola vez) |
| `KEYSTORE_PASSWORD` | Contraseña del keystore |
| `KEY_ALIAS` | Alias de la clave (`ha_alarm`) |
| `KEY_PASSWORD` | Contraseña de la clave |

> ⚠️ El keystore define la identidad de la app. Si se pierde o cambia, habrá que desinstalar la app en todos los dispositivos antes de instalar la nueva versión.

### 2. Proceso de compilación

Al hacer `push` a `main` el workflow:

1. Genera la estructura Android con `flutter create`
2. Aplica permisos y configuración de red en el `AndroidManifest.xml`
3. Firma el APK con el keystore permanente
4. Genera el icono en todos los tamaños de Android
5. Compila el APK en modo release
6. Crea automáticamente un **GitHub Release** con el APK adjunto

### 3. Descargar el APK

Una vez completado el build:
- Ve a la pestaña **Releases** del repositorio
- Descarga el `app-release.apk` de la última versión

---

## Configuración de la app

Al abrirla por primera vez aparece la pantalla de configuración. Pulsa el icono ⚙️ en cualquier momento para acceder.

| Campo | Descripción | Ejemplo |
|---|---|---|
| URL de Home Assistant | Dirección de tu servidor | `https://tu-servidor.es` |
| Token de acceso | Long-Lived Token de HA | `eyJhbGci...` |
| Entity ID de la alarma | ID de la entidad Alarmo | `alarm_control_panel.alarmo` |
| Código de desarmado | PIN de desarmado | `1234` |
| URL de version.json | Para actualizaciones automáticas | `https://tu-servidor.es/version.json` |

---

## Notificaciones push (Firebase)

La app puede recibir notificaciones push desde Home Assistant cuando cambia el estado de la alarma.

### 1. Crear proyecto en Firebase

1. Ve a [Firebase Console](https://console.firebase.google.com) y crea un proyecto
2. Añade una app Android con el package name `com.homeassistant.ha_alarm`
3. Descarga el `google-services.json`

### 2. Configurar el repositorio

**Secreto de GitHub** (Settings → Secrets and variables → Actions):

| Nombre | Valor |
|---|---|
| `GOOGLE_SERVICES_JSON_BASE64` | `cat google-services.json \| base64` (en tu terminal) |

**Archivo `lib/firebase_options.dart`** — rellena los valores del `google-services.json`:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey:            '...',   // api_key[0].current_key
  appId:             '...',   // client_info.mobilesdk_app_id
  messagingSenderId: '...',   // project_info.project_number
  projectId:         '...',   // project_info.project_id
  storageBucket:     '....firebasestorage.app',
);
```

### 3. Obtener el token FCM

Una vez instalada la app con Firebase configurado, ve a **Acerca de** — verás el token FCM con un botón para copiarlo. Este token identifica tu dispositivo.

### 4. Configurar Home Assistant

Añade en tu `configuration.yaml`:

```yaml
rest_command:
  notify_alarma:
    url: "https://fcm.googleapis.com/v1/projects/TU_PROJECT_ID/messages:send"
    method: POST
    headers:
      Authorization: "Bearer {{ token }}"
      Content-Type: "application/json"
    payload: >
      {
        "message": {
          "token": "TU_TOKEN_FCM",
          "notification": {
            "title": "{{ title }}",
            "body": "{{ body }}"
          }
        }
      }
```

Y una automatización que se dispare al cambiar el estado de la alarma:

```yaml
automation:
  - alias: "Notificación alarma"
    trigger:
      - platform: state
        entity_id: alarm_control_panel.alarmo
    action:
      - service: rest_command.notify_alarma
        data:
          title: "Alarma Casa"
          body: "Estado: {{ trigger.to_state.state }}"
```

> ⚠️ Para la autenticación OAuth2 de FCM v1 API necesitarás un script o integración adicional. La forma más sencilla para uso personal es usar el paquete `pyfcm` en un script de HA o la integración [FCM Notification](https://www.home-assistant.io/integrations/).

---

## Sistema de actualizaciones automáticas

La app comprueba en cada arranque si hay una versión nueva disponible.

### Formato del `version.json`

```json
{
  "version": "1.0.3",
  "url": "https://github.com/usuario/ha-alarma/releases/download/v1.0.3/app-release.apk"
}
```

### Flujo de actualización

1. La app descarga el `version.json` al arrancar
2. Compara la versión remota con la instalada
3. Si hay versión nueva → muestra diálogo con barra de progreso
4. Descarga el APK e inicia la instalación automáticamente
5. No vuelve a preguntar por la misma versión aunque se cierre la app

---

## Estados de la alarma

| Estado | Color | Descripción |
|---|---|---|
| `disarmed` | 🟢 Verde | Desarmada |
| `arming` | 🟠 Naranja | Armando — cuenta atrás de salida |
| `armed_away` | 🔴 Rojo | Armada |
| `pending` | 🟡 Amarillo | Entrada detectada — cuenta atrás antes de disparar |
| `triggered` | 🔴 Rojo | ¡Alarma disparada! |

---

## Dependencias principales

| Paquete | Versión | Uso |
|---|---|---|
| `http` | ^1.2.0 | Llamadas a la API REST de HA |
| `shared_preferences` | ^2.2.2 | Almacenamiento de configuración |
| `package_info_plus` | ^8.0.0 | Versión instalada de la app |
| `dio` | ^5.4.0 | Descarga del APK con progreso |
| `open_file` | ^3.3.2 | Instalación del APK descargado |
| `path_provider` | ^2.1.2 | Ruta de almacenamiento |
| `permission_handler` | ^11.3.0 | Permisos de Android |
| `flutter_launcher_icons` | ^0.13.1 | Generación del icono |

---

## Instalación inicial

1. Descarga el APK del último release
2. Copia el APK al móvil (cable, Drive, Telegram...)
3. Ajustes del móvil → **Instalar apps de fuentes desconocidas** → activar
4. Abre el APK e instala
5. Abre la app y configura la conexión

---

## Licencia

Uso personal. Todos los derechos reservados © Alfredo Fernández Badía, 2025.


---

## 📋 Historial de versiones

### v1.1.11
- 🔄 Refresco automático al volver de pantalla bloqueada (detección de ciclo de vida)
- 🔁 Reintentos automáticos (hasta 3) antes de mostrar "Sin conexión"
- 🛡️ El último estado conocido se mantiene visible mientras se reintenta la conexión

### v1.1.10
- 🐛 Corregida notificación push duplicada (FCM ya muestra automáticamente en background)

### v1.1.9
- 🏠 Nuevos modos de armado: **Armado en casa** (`armed_home`) y **Armado noche** (`armed_night`)
- 🎨 Iconos y colores diferenciados para cada modo de armado (naranja para Casa, morado para Noche)
- 🔄 Actualización de la tabla de estados con los nuevos modos

### v1.0.8
- 🐛 Corregida visualización de sensores abiertos cuando Alarmo bloquea el armado y vuelve a estado `disarmed`
- 🔔 Soporte para notificaciones push via Firebase Cloud Messaging (FCM)

### v1.0.7
- 🐛 Corregida pantalla de configuración que aparecía al arrancar aunque los datos estuvieran guardados
- 🐛 Sensores abiertos solo se muestran en estados relevantes (`arming`, `triggered`), no cuando la alarma está en reposo

### v1.0.6
- 🌐 Interfaz completamente en español (menús de copiar, pegar, seleccionar...)
- 🐛 Corregida persistencia incorrecta del aviso de sensores abiertos al actualizar estado

### v1.0.5
- ℹ️ Nueva pantalla "Acerca de" con versión, desarrollador y tecnologías
- ⏱️ Cuenta atrás visual durante el armado (`arming`) y la entrada (`pending`)
- 🚪 Aviso de sensores abiertos que bloquean el armado

### v1.0.3
- 🔄 Sistema de actualizaciones automáticas con barra de progreso
- 🎨 Icono personalizado (casa con escudo plateado)
- 🔧 Corrección de textos en botones de configuración

### v1.0.2
- 🔒 Firma permanente del APK (sin conflictos al actualizar)
- 📦 Release automático en GitHub Actions
- 🌐 Soporte HTTP y HTTPS en la conexión

### v1.0.1
- 🚀 Primera versión funcional
- Panel con estados Armar/Desarmar y confirmación
- Configuración de URL, token, entity ID y código
