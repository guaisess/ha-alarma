# 🏡 Alarma Casa HA

Aplicación Android para controlar la alarma de **Home Assistant** desde el móvil, con soporte completo para [Alarmo](https://github.com/nielsfaber/alarmo).

Desarrollada por **Alfredo Fernández Badía** · Bargas, Toledo · 2025

---

## Características

- ✅ Armar y desarmar con confirmación antes de ejecutar
- ✅ Estado en tiempo real vía **WebSocket** (eventos push instantáneos)
- ✅ Cuenta atrás visual durante el armado y la entrada
- ✅ Aviso de sensores abiertos que bloquean el armado
- ✅ Pantalla de configuración con prueba de conexión y timeout configurable
- ✅ Distribución por Google Play (prueba interna); las actualizaciones las hace Play
- ✅ Tema claro, oscuro o seguir al sistema
- ✅ Vibración y beep al ejecutar acciones
- ✅ Historial local de cambios de estado (últimos 50)
- ✅ Widget en la pantalla de inicio (2×2 y 2×1)
- ✅ Notificaciones push via Firebase Cloud Messaging
- ✅ Token y código almacenados cifrados (flutter_secure_storage)
- ✅ Cache del último estado para visualización sin conexión
- ✅ Pull-to-refresh en pantalla principal
- ✅ Reconexión automática WebSocket con backoff exponencial
- ✅ Modos de armado adicionales: Casa, Noche, Vacaciones (configurable)

---

## Estructura del proyecto

```
ha-alarma/
├── .github/
│   └── workflows/
│       └── build.yml              # Compila el AAB firmado y lo sube a Play
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
│   ├── services.dart              # HaService, HaWebSocketService, StateCache, etc.
│   ├── controller.dart            # AlarmController (ChangeNotifier)
│   ├── widgets.dart               # Widgets reutilizables
│   ├── firebase_options.dart      # Configuración Firebase (generado en CI)
│   └── screens/
│       ├── home_screen.dart       # Pantalla principal
│       ├── config_screen.dart     # Configuración
│       ├── history_screen.dart    # Historial de estados
│       └── about_screen.dart      # Acerca de
├── pubspec.yaml                   # Dependencias y versión
└── README.md
```

---

## Compilación con GitHub Actions

El proyecto se compila completamente en la nube. No es necesario instalar Flutter ni Android Studio.

### Secretos necesarios

Ve a tu repositorio → **Settings → Secrets and variables → Actions** y añade:

| Nombre | Descripción |
|---|---|
| `PLAY_SERVICE_ACCOUNT_JSON` | (Opcional) JSON de la cuenta de servicio de Google Play para subir solo cada versión |
| `KEYSTORE_BASE64` | Keystore (clave de subida a Play) en Base64 |
| `KEYSTORE_PASSWORD` | Contraseña del keystore |
| `KEY_ALIAS` | Alias de la clave (`ha_alarm`) |
| `KEY_PASSWORD` | Contraseña de la clave |
| `GOOGLE_SERVICES_JSON_BASE64` | `google-services.json` en Base64 |
| `FIREBASE_API_KEY` | API Key de Firebase |
| `FIREBASE_APP_ID` | App ID de Firebase |
| `FIREBASE_MESSAGING_SENDER` | Sender ID de Firebase |
| `FIREBASE_PROJECT_ID` | Project ID de Firebase |
| `FIREBASE_STORAGE_BUCKET` | Storage bucket de Firebase |

> ⚠️ El keystore es la clave de subida a Google Play. Si se pierde, se puede restablecer desde Play Console, pero guarda una copia.

### Proceso de compilación

Al hacer `push` a `main` el workflow:

1. Genera la estructura Android con `flutter create`
2. Parchea `AndroidManifest.xml` (permisos, label, widgets)
3. Inyecta las opciones de Firebase desde secrets
4. Firma el paquete con la clave de subida (keystore)
5. Genera el icono en todos los tamaños
6. Ejecuta las pruebas y compila el **AAB** en modo release
7. Crea un **GitHub Release** con el AAB y, si existe `PLAY_SERVICE_ACCOUNT_JSON`, lo sube a la **prueba interna** de Google Play

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
| Nombre de este móvil | Nombre con el que se registra su token push en HA | `alfredo` |
| Tema | Claro / Oscuro / Sistema | Sistema |

---

## Widget en pantalla de inicio

La app incluye dos widgets para añadir al escritorio de Android:

| Widget | Tamaño | Contenido |
|---|---|---|
| Alarma Casa | 2×2 | Icono, estado, hora de actualización y botones Armar/Desarmar (con confirmación) |
| Alarma Casa Wide | 2×1 | Tres líneas centradas: título, estado y hora |

Para añadirlos: mantén pulsado en el escritorio → Widgets → busca "Alarma Casa".
El widget se actualiza automáticamente cada vez que la app refresca el estado.

---

## Notificaciones push (Firebase)

### 1. Crear proyecto en Firebase

1. Ve a [Firebase Console](https://console.firebase.google.com) y crea un proyecto
2. Añade una app Android con el package name `es.fernandezbadia.alarmacasa`
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
| `flutter_secure_storage` | ^9.2.2 | Token y código cifrados |
| `package_info_plus` | ^8.0.0 | Versión instalada |
| `path_provider` | ^2.1.2 | Ruta de almacenamiento |
| `permission_handler` | ^11.3.0 | Permisos Android |
| `firebase_core` | ^3.6.0 | Firebase base |
| `firebase_messaging` | ^15.1.3 | Notificaciones push |
| `flutter_local_notifications` | ^17.2.2 | Notificaciones locales |
| `vibration` | ^3.1.0 | Feedback háptico |
| `intl` | ^0.19.0 | Formato de fechas |
| `flutter_launcher_icons` | ^0.13.1 | Generación del icono |

---

## Instalación

1. Pide que te añadan como tester en la prueba interna de Google Play (con tu correo de Google)
2. Abre el enlace de invitación e instala **Alarma Casa** desde Play Store
3. Configura la conexión (URL `https://...`, token y entidad) y el nombre del móvil
4. Las actualizaciones llegan solas desde Play

---

## Licencia

Uso personal. Todos los derechos reservados © Alfredo Fernández Badía, 2025.

---

## 📋 Historial de versiones

### v2026.11.18
- 🧹 Los sensores abiertos de un armado fallido ya no se quedan en pantalla: tras un armado fallido se ocultan a los 5 minutos (o al volver a armar) y no se muestran en las zonas desarmadas

### v2026.11.17
- 💾 Copia de seguridad: se guarda con el selector del sistema (las rutas directas a Descargas no funcionan desde Android 11); al importar una copia con otra URL se borran el token y el código actuales si la copia no trae los suyos
- 🧩 Widget: se marca "⚠ Sin actualizar" en gris si el estado tiene más de 10 minutos; se refresca cada 30 min y ya no se pone en "Sin conexión" en cada arranque
- 🗺️ Las zonas no desaparecen si falla una petición; aviso cuando el robot desarma una zona al armar
- 🔌 WebSocket: latido cada 30 s y sin conexiones duplicadas; los nombres de sensores que fallan se reintentan
- 🔒 CI: el secreto de Play solo llega al paso de subida; `pubspec.lock` versionado
- 🧪 Pruebas del controlador y de la copia de seguridad (28 en total); migración a `material_ui`; Dart >=3.9
- 🧹 Código sin uso eliminado

### v2026.11.16
- 🔒 Ajustes: la URL de Home Assistant debe empezar por `https://`; si no, avisa al probar y al guardar. Una URL `http://` guardada antes muestra el motivo en lugar de "Sin conexión"
- 🔔 Push (en HA): el filtro de zonas usa la marca de robot en lugar de `changed_by`, que Alarmo no refresca

### v2026.11.15
- 📄 Política de privacidad en `docs/privacidad.md`, publicada con GitHub Pages (requisito de Google Play)
- 🛠️ CI: los cambios solo de documentación (`docs/`, `*.md`) no recompilan la app

### v2026.11.14
- 🛠️ CI: Java 21 (el lint de AGP 9 fallaba con Java 17 en `firebase_core`)

### v2026.11.13
- 🛠️ CI: compileSdk 37 y desugaring de bibliotecas Java (exigidos por flutter_local_notifications y androidx.core 1.19)

### v2026.11.12
- 📦 Distribución por Google Play: nuevo identificador `es.fernandezbadia.alarmacasa` (hay que reinstalar y registrar la app en Firebase con ese paquete)
- 🧹 Se elimina la auto-actualización por APK (permiso `REQUEST_INSTALL_PACKAGES`, `version.json`, `dio`, `open_file`, `permission_handler`); Play no la permite
- 🛠️ CI: compila AAB con Flutter 3.50.1 (target Android 16 / API 36), firma con Gradle KTS y sube a prueba interna si hay credencial
- ⬆️ Dependencias actualizadas a sus últimas versiones mayores (firebase, file_picker, flutter_local_notifications, flutter_secure_storage...)
- 🔒 Sin copias de seguridad en la nube de Android (`allowBackup=false`)

### v2026.11.11
- 🧩 Widget 2×2: botones Armar y Desarmar. Abren la app con el diálogo de confirmación (nunca actúan solos; con el móvil bloqueado, Android pide desbloquear antes)

### v2026.11.10
- 🔒 Seguridad: se quita `usesCleartextTraffic`; la app solo admite conexiones cifradas (HTTPS/WSS). La URL de HA debe empezar por `https://`

### v2026.11.9
- 🛠️ CI: ejecuta `flutter test` antes de compilar; acciones actualizadas a versiones con Node 24 (checkout v7, setup-java v6, upload-artifact v7, action-gh-release v3)

### v2026.11.8
- 🧪 Pruebas unitarias (`flutter test`): estados, zonas, configuración, historial, parseo de HA y comparación de versiones

### v2026.11.7
- 📲 La app registra sola su token FCM en HA: nuevo campo "Nombre de este móvil" en Ajustes; HA lo guarda en `fcm_tokens.json` (evento `ha_alarma_registrar_token`)

### v2026.11.6
- 🔔 Al tocar una notificación con zona, la app se abre, se desplaza hasta las zonas y resalta la zona 5 s (app abierta, en segundo plano o cerrada)

### v2026.11.5
- 🔄 Actualización: también se comprueba al volver a la app (máx. cada 30 min); nunca se abren dos avisos a la vez

### v2026.11.4
- 🕘 Historial: registra también los cambios de cada zona; marca con 🤖 los desarmes hechos por los robots (hasta 100 entradas)
- 🧩 Widget: muestra las zonas cuyo estado difiere del maestro (p. ej. "🤖 PB desarmada")

### v2026.11.3
- 🔄 Actualización: un error de descarga ya no marca la versión como vista; se vuelve a ofrecer. Tampoco se bloquea si falló la lectura de `version.json`
- 🛠️ CI: `version.json` solo se actualiza cuando el release está publicado (evita el 404 al descargar el APK)
- 🚪 Sensores abiertos y anulados por zona, con nombre legible obtenido de HA (también en el aviso del estado maestro)

### v2026.11.2
- 🗺️ Zonas de Alarmo (Perímetro, Planta baja, Planta alta) en solo lectura bajo los botones de la pantalla principal
- 🤖 Indicador "Desarmada por robot" (según `input_boolean.robots_alarma_desarmada_auto_*`) y botón "Armar" solo en zonas que el robot no rearmó
- ⚠️ Aviso al armar de forma completa si hay un robot con zona desarmada (puede quedarse en "Armando")
- 🔌 WebSocket: una sola suscripción filtrada a la alarma, las zonas y las marcas de robot

### v2026.11.1 (antes 1.5.1)
- 🔌 WebSocket: la reconexión ya respeta el backoff (antes se reseteaba y reintentaba cada segundo)
- 🔌 WebSocket: suscripción filtrada en servidor (`subscribe_trigger` solo de la entidad de alarma) en lugar de todos los `state_changed`
- 🔌 `auth_invalid` detiene los reintentos y muestra "Token no válido"
- ⚡ Sin redibujados cada segundo; el sondeo REST ya no se reinicia con cada evento WS
- 🧩 Widget: color azul para el estado Vacaciones
- 💾 Backup: incluye `show_arm_modes`, importación tolerante a tipos y guardado con alternativa en Android 11+
- 🔐 Migración automática de token/código antiguos al almacén seguro
- 🛠️ Constantes centralizadas en `constants.dart`; parseo de estado unificado (REST/WS)
- 📝 README: estructura y ejemplos actualizados

### v1.5.0
- 🏠 Nuevos modos de armado: Casa, Noche, Vacaciones
  - Submenú configurable en Ajustes → Avanzado → Mostrar modos de armado
  - Desactivado por defecto, actívalo si usas múltiples modos en Alarmo
  - Cada modo con su color e icono distintivo
- ✈️ Añadido estado `armed_custom_bypass` (Vacaciones) al sistema

### v1.4.0
- ⚡ Eventos en tiempo real vía **WebSocket** (HA WebSocket API)
  - Conexión persistente con reconexión automática (backoff exponencial)
  - Actualización instantánea del estado sin polling
  - Polling cada 30s como fallback cuando WebSocket está activo
- 🔒 Token y código almacenados cifrados con `flutter_secure_storage`
  - Migración automática desde SharedPreferences
  - Backup/Restore compatible con el nuevo almacenamiento
- 📦 Nueva arquitectura con **AlarmController** (ChangeNotifier)
  - Lógica separada de la UI, más mantenible
  - Estado preservado al navegar a configuración
- 💾 Cache del último estado conocido en SharedPreferences
  - Muestra el último estado mientras se reconecta
- 📱 Pull-to-refresh en pantalla principal
- 📜 Auto-scroll al último evento en el historial
- 🐛 Todos los catch blocks ahora registran errores con debugPrint
- 🎯 Feedback de carga mejorado en guardado de configuración

### v1.3.7
- 🎨 Widget 2×1: rediseño — sin icono, tres líneas centradas
  - Línea 1: "Alarma Casa" en blanco
  - Línea 2: estado en su color (verde, rojo, naranja...)
  - Línea 3: última actualización en gris pequeño

### v1.3.6
- 🐛 Widget 2×1: eliminado `<View>` del separador (no soportado en RemoteViews)
  - RemoteViews solo admite: LinearLayout, TextView, ImageView, Button...
  - El `<View>` base causa "Error al cargar el widget" en todos los launchers
  - Reemplazado por `layout_marginLeft` en el LinearLayout hijo

### v1.3.5
- 🐛 Widget: corregido fichero SharedPreferences incorrecto (causa raíz real)
  - Flutter guarda en `FlutterSharedPreferences`, no en `{packageName}_preferences`
  - El widget ahora lee el estado correcto de la alarma
- 🐛 Widget 2×1: corregido crash por `layout_marginHorizontal` no soportado en RemoteViews
  - Reemplazado por `layout_marginLeft` + `layout_marginRight`

### v1.3.4
- 🐛 Widget: añadidos `minWidth`/`minHeight` a los XML del provider (causa raíz del "Error al cargar el widget")
- 🔧 Permisos de red (INTERNET) restaurados en AndroidManifest
- ✅ Widget 2×1: ahora compatible con todos los launchers Android

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