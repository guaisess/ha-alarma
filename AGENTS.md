# App Alarma Casa — agent guide

## Stack
- Flutter 3.50.1 stable, Dart >=3.0.0 <4.0.0, Android-only (no iOS)
- No state mgmt library — `AlarmController extends ChangeNotifier` in `lib/controller.dart`
- No routing package — `Navigator.push(MaterialPageRoute(...))`
- Theme: static `AlarmApp.of(context)` pattern in `lib/main.dart`

## Version bump workflow (every change)
1. `pubspec.yaml`: formato `AAAA.MM.V+B` (ej. `2026.11.1+41`): `V` +1 en cada cambio y vuelve a 1 al empezar el mes; `B` (build number) +1 siempre
   - Versionar también los ficheros modificados (cabecera `// Versión AAAA.MM.V`)
2. Sin `version.json`: las actualizaciones las gestiona Google Play (el workflow sube el AAB)
3. `README.md`: add changelog entry at top of version history section

## Key architecture
- `lib/controller.dart` — `AlarmController` (ChangeNotifier): polling, WebSocket, timers, state
- `lib/services.dart` — `HaService` (REST), `HaWebSocketService` (WS), `StateCache`, `BackupService`, `WidgetService`
- `lib/models.dart` — `Config` (secure storage for token/code), `AlarmStateData`, `HistoryService`
- `lib/constants.dart` — colors, `stateInfo` map (state → label/color/icon)
- 4 screens in `lib/screens/`: `home_screen.dart`, `config_screen.dart`, `history_screen.dart`, `about_screen.dart`

## Dependencies worth knowing
- `flutter_secure_storage` — token & code (not plaintext SharedPreferences)
- `web_socket_channel` (via `dart:io` WebSocket) — real-time HA events
- `http` — REST fallback polling (15s normal, 30s when WS connected)
- `shared_preferences` — config, cache, history, widget data, FCM token

## Home Assistant integration
- REST: `GET /api/states/{entity_id}`, `POST /api/services/alarm_control_panel/{service}`
- WebSocket: `ws{s}://host/api/websocket` → auth → `subscribe_trigger` filtrado por entidad (alarma, zonas y marcas de robot)
- Retry: up to 3 attempts with exponential backoff (1s → 2s → 4s)
- WS reconnect: backoff 1s → 2s → 4s → 8s → 15s → 30s (capped)
- Arm services: `alarm_arm_away`, `alarm_arm_home`, `alarm_arm_night`, `alarm_arm_custom_bypass`

## Android specifics
- Native widgets: 2×2 (`AlarmWidget`) and 2×1 (`AlarmWidgetWide`) in `android_res/`
- Communication: `MethodChannel('es.fernandezbadia.alarmacasa/widget')` + `FlutterSharedPreferences`
- CI-only build: GitHub Actions workflow in `.github/workflows/build.yml` (Flutter 3.50.1, Java 17); compila un AAB para Google Play (paquete `es.fernandezbadia.alarmacasa`)

## UI conventions
- All UI in Spanish (`es_ES` locale)
- Custom `SectionCard`, `InputField`, `ActionButton`, `ThemeOption` in `lib/widgets.dart`
- Dark/light/system theme persisted in SharedPreferences under `app_theme`
- Emojis used in section titles (🎨 🌐 🔑 ⚙️ 🔄 💾)
- Todos los comentarios en español

## Testing
- No tests in repo. Build verification via CI only.
