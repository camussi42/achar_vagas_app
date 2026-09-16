import 'package:achar_vagas_app/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseBootstrap {
  const FirebaseBootstrap({required this.usingFirebase, required this.uid});

  final bool usingFirebase;
  final String uid;
}

Future<FirebaseBootstrap> bootstrapFirebase() async {
  final options = DefaultFirebaseOptions.currentOrNull;
  if (options == null) {
    return const FirebaseBootstrap(usingFirebase: false, uid: '');
  }
  try {
    await Firebase.initializeApp(options: options);
    final cred = await FirebaseAuth.instance.signInAnonymously();
    return FirebaseBootstrap(
      usingFirebase: true,
      uid: cred.user?.uid ?? '',
    );
  } catch (_) {
    return const FirebaseBootstrap(usingFirebase: false, uid: '');
  }
}
