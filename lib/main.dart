import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
import 'models.dart';
import 'firebase_options.dart';
import 'services.dart';
import 'screens/home_screen.dart';

// ─── Notificaciones locales (global) ─────────────────────────
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

// ─── Handler Firebase background ─────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  // ─── Inicializar widget ANTES de que la app se lance ────
  await WidgetService.init();

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _localNotifications.initialize(
    const InitializationSettings(android: androidSettings),
  );

  const channel = AndroidNotificationChannel(
    'ha_alarm_channel', 'Alarma Casa HA',
    description: 'Notificaciones de estado de la alarma',
    importance: Importance.max,
  );
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  runApp(const AlarmApp());
}

// ─── App raíz ─────────────────────────────────────────────────
class AlarmApp extends StatefulWidget {
  const AlarmApp({super.key});

  static _AlarmAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_AlarmAppState>();

  @override
  State<AlarmApp> createState() => _AlarmAppState();
}

class _AlarmAppState extends State<AlarmApp> {
  AppThemeMode _themeMode = AppThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _themeMode = themeFromString(prefs.getString('app_theme')));
  }

  Future<void> setTheme(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', themeToString(mode));
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alarma',
      debugShowCheckedModeBanner: false,
      themeMode: toFlutterThemeMode(_themeMode),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES')],
      locale: const Locale('es', 'ES'),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(surface: kSurface, primary: kBlue),
      ),
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFf1f5f9),
        colorScheme: const ColorScheme.light(surface: Colors.white, primary: kBlue),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFf1f5f9),
          foregroundColor: Color(0xFF0f172a),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
