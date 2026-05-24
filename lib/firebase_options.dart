// ─── Configuración de Firebase ────────────────────────────────
// Rellena estos valores desde Firebase Console:
//   1. Ve a https://console.firebase.google.com
//   2. Tu proyecto → Configuración del proyecto → General
//   3. Baja hasta "Tus apps" → selecciona la app Android
//   4. Descarga el google-services.json y extrae los valores de abajo
//
// Los valores también están disponibles en google-services.json:
//   apiKey           → client[0].api_key[0].current_key
//   appId            → client[0].client_info.mobilesdk_app_id
//   messagingSenderId → project_info.project_number
//   projectId        → project_info.project_id
//   storageBucket    → project_info.storage_bucket

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyCn2UIQgvPJ2FNf2cHksPzPu1RL4d72okY',
    appId:             '1:40150776349:android:47612da8cdc75829a264f4',
    messagingSenderId: '40150776349',
    projectId:         'ha-alarma',
    storageBucket:     'ha-alarma.firebasestorage.app',
  );
}
