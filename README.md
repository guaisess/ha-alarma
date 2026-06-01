# 🏡 Alarma Casa HA

Aplicación Android para controlar la alarma de **Home Assistant** desde el móvil, con soporte completo para [Alarmo](https://github.com/nielsfaber/alarmo).

Desarrollada por **Alfredo Fernández Badía** · Bargas, Toledo · 2025

---

## Características

- ✅ Armar y desarmar con confirmación antes de ejecutar
- ✅ Estado en tiempo real (actualización automática cada 15s)
- ✅ Cuenta atrás visual durante el armado y la entrada
- ✅ Aviso de sensores abiertos que bloquean el armado
- ✅ Pantalla de configuración con prueba de conexión y timeout configurable
- ✅ Actualizaciones automáticas desde una URL configurable
- ✅ Tema claro, oscuro o seguir al sistema
- ✅ Vibración y beep al ejecutar acciones
- ✅ Historial local de cambios de estado (últimos 50)
- ✅ Widget en la pantalla de inicio (2×2 y 2×1)
- ✅ Notificaciones push via Firebase Cloud Messaging
- ✅ Icono personalizado rojo carmesí con escudo y señal de alarma

---

## Estructura del proyecto

```
ha-alarma/
├── .github/
│   └── workflows/
│       └── build.yml              # Pipeline de compilación y release
├── android_res/
│   ├── layout/
│   │   ├── alarm_widget.xml       # Layout widget 2×2
│   │   └── alarm_widget_wide.xml  # Layout widget 2×1
│   ├── xml/
│   │   ├── alarm_widget_info.xml       # Metadatos widget 2×2
│   │   └── alarm_widget_wide_info.xml  # Metadatos widget 2×1
│   └── AlarmWidget.kt             # Receiver de ambos widgets
├── assets/
│   └── icon.png                   # Icono de la app (1024×1024)
├── lib/
│   ├── main.dart                  # Punto de entrada y AlarmApp
│   ├── constants.dart             # Colores y constantes
│   ├── models.dart                # Modelos de datos e historial
│   ├── services.dart              # HaService, FeedbackService, UpdateService, WidgetService
│   ├── widgets.dart               # Widgets reutilizables
│   ├── firebase_options.dart      # Configuración Firebase (generado en CI)
│   └── screens/
│       ├── home_screen.dart       # Pantalla principal
│       ├── config_screen.dart     # Configuración
│       ├── history_screen.dart    # Historial de estados
│       └── about_screen.dart      # Acerca de
├── pubspec.yaml                   # Dependencias y versión
├── version.json                   # Control de versión para auto-update
└── README.md
```

---

## Compilación con GitHub Actions

El proyecto se compila completamente en la nube. No es necesario instalar Flutter ni Android Studio.

### Secretos necesarios

Ve a tu repositorio → **Settings → Secrets and variables → Actions** y añade:

| Nombre | Descripción |
|---|---|
| `KEYSTORE_BASE64` | Keystore en Base64 |
| `KEYSTORE_PASSWORD` | Contraseña del keystore |
| `KEY_ALIAS` | Alias de la clave (`ha_alarm`) |
| `KEY_PASSWORD` | Contraseña de la clave |
| `GOOGLE_SERVICES_JSON_BASE64` | `google-services.json` en Base64 |
| `FIREBASE_API_KEY` | API Key de Firebase |
| `FIREBASE_APP_ID` | App ID de Firebase |
| `FIREBASE_MESSAGING_SENDER` | Sender ID de Firebase |
| `FIREBASE_PROJECT_ID` | Project ID de Firebase |
| `FIREBASE_STORAGE_BUCKET` | Storage bucket de Firebase |

> ⚠️ El keystore define la identidad de la app. Si se pierde, habrá que desinstalar en todos los dispositivos.

### Proceso de compilación

Al hacer `push` a `main` el workflow:

1. Genera la estructura Android con `flutter create`
2. Parchea `AndroidManifest.xml` (permisos, label, widgets)
3. Inyecta las opciones de Firebase desde secrets
4. Firma el APK con el keystore permanente
5. Genera el icono en todos los tamaños
6. Compila el APK en modo release
7. Crea automáticamente un **GitHub Release** con el APK

---

## Configuración de la app

Pulsa ⚙️ en cualquier momento para acceder a la configuración.

| Campo | Descripción | Ejemplo |
|---|---|---|
| URL de Home Assistant | Dirección del servidor | `https://tu-servidor.es` |
| Token de acceso | Long-Lived Token de HA | `eyJhbGci...` |
| Entity ID de la alarma | ID de la entidad Alarmo | `alarm_control_panel.alarmo` |
| Código de desarmado | PIN de desarmado | `1234` |
| Timeout de conexión | Segundos antes de error | `5` |
| URL de version.json | Para actualizaciones automáticas | `https://tu-servidor.es/version.json` |
| Tema | Claro / Oscuro / Sistema | Sistema |

---

## Widget en pantalla de inicio

La app incluye dos widgets para añadir al escritorio de Android:

| Widget | Tamaño | Contenido |
|---|---|---|
| Alarma Casa | 2×2 | Icono de estado, texto del estado, hora de actualización |
| Alarma Casa Wide | 2×1 | Icono a la izquierda, estado y hora a la derecha |

Para añadirlos: mantén pulsado en el escritorio → Widgets → busca "Alarma Casa".
El widget se actualiza automáticamente cada vez que la app refresca el estado.

---

## Notificaciones push (Firebase)

### 1. Crear proyecto en Firebase

1. Ve a [Firebase Console](https://console.firebase.google.com) y crea un proyecto
2. Añade una app Android con el package name `com.homeassistant.ha_alarm`
3. Descarga el `google-services.json`

### 2. Configurar secrets de GitHub

| Nombre | Valor |
|---|---|
| `GOOGLE_SERVICES_JSON_BASE64` | `cat google-services.json \| base64` |
| `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |
| `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_MESSAGING_SENDER` | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` |
| `FIREBASE_STORAGE_BUCKET` | `project_info.storage_bucket` |

### 3. Obtener el token FCM

En **Acerca de** verás el token FCM con un botón para copiarlo.

### 4. Automatización en Home Assistant

```yaml
automation:
  - alias: "Notificación alarma"
    trigger:
      - platform: state
        entity_id: alarm_control_panel.alarmo
    action:
      - service: rest_command.notify_alarma
        data:
          title: "🏡 Alarma Casa"
          body: >
            {% set hora = now().strftime('%H:%M') %}
            {% set estados = {
              'disarmed':    'Desarmada',
              'armed_away':  'Armada',
              'armed_home':  'Armada en casa',
              'armed_night': 'Armada noche',
              'arming':      'Armando...',
              'pending':     'Entrada detectada',
              'triggered':   '¡ALARMA DISPARADA!'
            } %}
            {% set estado = estados.get(trigger.to_state.state, trigger.to_state.state) %}
            {% set usuario = trigger.to_state.attributes.get('changed_by', '') %}
            {{ hora }} — {{ estado }}{% if usuario and trigger.to_state.state in ['disarmed','armed_away','armed_home','armed_night'] %} ({{ usuario }}){% endif %}
```

---

## Sistema de actualizaciones automáticas

```json
{
  "version": "1.2.7",
  "url": "https://github.com/guaisess/ha-alarma/releases/download/v1.2.7/app-release.apk"
}
```

---

## Estados de la alarma

| Estado | Color | Descripción |
|---|---|---|
| `disarmed` | 🟢 Verde | Desarmada |
| `arming` | 🟠 Naranja | Armando — cuenta atrás de salida |
| `armed_away` | 🔴 Rojo | Armada |
| `armed_home` | 🟠 Naranja | Armada en casa |
| `armed_night` | 🟣 Morado | Armada noche |
| `pending` | 🟡 Amarillo | Entrada detectada |
| `triggered` | 🔴 Rojo | ¡Alarma disparada! |

---

## Dependencias principales

| Paquete | Versión | Uso |
|---|---|---|
| `http` | ^1.2.0 | API REST de HA |
| `shared_preferences` | ^2.2.2 | Configuración local |
| `package_info_plus` | ^8.0.0 | Versión instalada |
| `dio` | ^5.4.0 | Descarga APK con progreso |
| `open_file` | ^3.3.2 | Instalación del APK |
| `path_provider` | ^2.1.2 | Ruta de almacenamiento |
| `permission_handler` | ^11.3.0 | Permisos Android |
| `firebase_core` | ^3.6.0 | Firebase base |
| `firebase_messaging` | ^15.1.3 | Notificaciones push |
| `flutter_local_notifications` | ^17.2.2 | Notificaciones locales |
| `vibration` | ^3.1.0 | Feedback háptico |
| `intl` | ^0.19.0 | Formato de fechas |
| `home_widget` | ^0.6.0 | Widget en pantalla de inicio |
| `flutter_launcher_icons` | ^0.13.1 | Generación del icono |

---

## Instalación inicial

1. Descarga el APK del último release
2. Copia el APK al móvil
3. Ajustes → **Instalar apps de fuentes desconocidas** → activar
4. Abre el APK e instala
5. Configura la conexión

---

## Licencia

Uso personal. Todos los derechos reservados © Alfredo Fernández Badía, 2025.

---

## 📋 Historial de versiones

### v1.3.3
- 🐛 Widget: arreglado AndroidManifest patching para widgets (receivers)
- ✅ Mejora robustez del parsing XML — Python en lugar de sed
- 📌 Agregados try-catch en AlarmWidget y AlarmWidgetWide para manejar errores
- 🔧 Logging de errores a logcat para debugging de widgets
- ✓ Receivers correctamente formateados en AndroidManifest.xml

### v1.3.2
- 🐛 Widget: corregida inicialización de datos — ahora se cargan valores por defecto ANTES de que se cree el widget
- 📌 Widget 2×2: ahora muestra el estado de la alarma correctamente
- 📌 Widget 2×1: corregido error de carga ("Error al cargar el widget")
- 🎯 WidgetService.init() se ejecuta en main() para garantizar datos disponibles

### v1.3.1
- 📁 Copia de seguridad: ahora permite seleccionar archivos para restaurar
- 🔧 File picker para elegir archivo JSON desde Descargas/Alarma Casa Backups
- ✅ Interfaz mejorada con confirmación de restauración exitosa

### v1.2.9
- 💾 Copia de seguridad: nueva función para exportar e importar configuración completa
- ⚙️ Nuevo servicio BackupService con soporte para exportar/importar JSON
- 🎯 Permite recuperar la configuración si se desinstala la app

### v1.2.8
- 🐛 Widget: corregido fallo de carga de plugins (2×2 y 2×1) — inicialización de valores por defecto y sincronización de SharedPreferences

### v1.2.7
- 🐛 Widget: corregido "Error al cargar" — eliminada dependencia de HomeWidgetProvider, actualización directa vía broadcast

### v1.2.6
- 🐛 Widget: reemplazado HomeWidgetProvider por AppWidgetProvider nativo

### v1.2.5
- 🐛 Widget: corregido tamaño en selector (minWidth/minHeight eliminados)
- 🐛 Widget: valor por defecto "Alarma Casa" para evitar pantalla en blanco

### v1.2.4
- 🐛 Corregido error de carga del widget (valores por defecto cuando no hay datos)
- 📏 Corregido tamaño del widget 2×1 en el selector

### v1.2.3
- 🎨 Nuevo icono: rojo carmesí con escudo, casa y señal de alarma
- 📱 Widget 2×2 en la pantalla de inicio
- 📏 Widget 2×1 en la pantalla de inicio

### v1.2.2
- 🐛 Corregido error de compilación del widget Android (Kotlin stdlib + recursos)

### v1.2.1
- 📱 Widget en la pantalla de inicio de Android

### v1.2.0
- 🎨 Tema claro, oscuro y seguir al sistema (configurable en ajustes)
- 📳 Vibración + beep de confirmación al ejecutar acciones
- 🕐 Indicador de última actualización ("Hace Xs") bajo el estado
- 🔁 Reconexión con backoff exponencial (1s → 2s → 4s)
- ⏱️ Timeout de conexión configurable en ajustes
- 📋 Historial local de cambios de estado (últimos 50)

### v1.1.11
- 🔄 Refresco automático al volver de pantalla bloqueada
- 🔁 Reintentos automáticos (hasta 3) antes de mostrar "Sin conexión"
- 🛡️ El último estado conocido se mantiene visible mientras se reintenta

### v1.1.10
- 🐛 Corregida notificación push duplicada

### v1.1.9
- 🏠 Nuevos modos: Armado en casa (`armed_home`) y Armado noche (`armed_night`)
- 🎨 Iconos y colores diferenciados por modo

### v1.0.8
- 🐛 Corregida visualización de sensores abiertos
- 🔔 Soporte para notificaciones push via FCM

### v1.0.7
- 🐛 Corregida pantalla de configuración al arrancar
- 🐛 Sensores abiertos solo en estados relevantes

### v1.0.6
- 🌐 Interfaz completamente en español
- 🐛 Corregida persistencia del aviso de sensores

### v1.0.5
- ℹ️ Nueva pantalla "Acerca de"
- ⏱️ Cuenta atrás visual en armado y entrada
- 🚪 Aviso de sensores abiertos

### v1.0.3
- 🔄 Actualizaciones automáticas con barra de progreso
- 🎨 Icono personalizado

### v1.0.2
- 🔒 Firma permanente del APK
- 📦 Release automático en GitHub Actions

### v1.0.1
- 🚀 Primera versión funcional