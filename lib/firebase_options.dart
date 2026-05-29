// Este archivo se genera automáticamente en el build (GitHub Actions).
// Los valores reales se inyectan desde los secrets del repositorio.
// No edites este archivo manualmente — no tiene efecto en producción.
//
// Secrets necesarios en GitHub (Settings → Secrets → Actions):
//   FIREBASE_API_KEY
//   FIREBASE_APP_ID
//   FIREBASE_MESSAGING_SENDER
//   FIREBASE_PROJECT_ID
//   FIREBASE_STORAGE_BUCKET

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'PLACEHOLDER',
    appId:             'PLACEHOLDER',
    messagingSenderId: 'PLACEHOLDER',
    projectId:         'PLACEHOLDER',
    storageBucket:     'PLACEHOLDER',
  );
}