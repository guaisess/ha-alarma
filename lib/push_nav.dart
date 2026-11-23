// Versión 2026.11.6
import 'package:flutter/foundation.dart';

/// Puente entre las notificaciones (FCM y locales) y la pantalla principal.
/// Al tocar un aviso con zona, se publica su nombre y la pantalla la enfoca.
class PushNav {
  static final ValueNotifier<String?> zona = ValueNotifier<String?>(null);

  /// Solicita abrir una zona; ignora avisos sin zona (los del maestro).
  static void abrir(String? nombreZona) {
    if (nombreZona == null || nombreZona.isEmpty) return;
    zona.value = null;        // fuerza notificar aunque sea la misma zona de antes
    zona.value = nombreZona;
  }
}
