import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Preencha com `flutterfire configure` (substitui este arquivo)
/// ou cole as chaves do console Firebase.
class DefaultFirebaseOptions {
  static FirebaseOptions? get currentOrNull {
    if (kIsWeb) {
      return _web.apiKey.isEmpty ? null : _web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _android.apiKey.isEmpty ? null : _android;
      default:
        return _web.apiKey.isEmpty ? null : _web;
    }
  }

  static const FirebaseOptions _android = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
  );

  static const FirebaseOptions _web = FirebaseOptions(
    apiKey: '',
    appId: '',
    messagingSenderId: '',
    projectId: '',
    storageBucket: '',
    authDomain: '',
  );
}
