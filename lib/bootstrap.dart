import 'package:achar_vagas_app/ambiente.dart';
import 'package:achar_vagas_app/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Resultado do bootstrap: Firebase pronto ou o motivo de seguir sem backend.
class FirebaseBootstrap {
  const FirebaseBootstrap({
    required this.usingFirebase,
    required this.uid,
    this.motivoSemFirebase,
  });

  /// Firebase pronto e usuario anonimo autenticado.
  const FirebaseBootstrap.firebase(String uid)
      : this(usingFirebase: true, uid: uid);

  /// Sem backend: [motivo] explica o que falhou (issue #29).
  const FirebaseBootstrap.demonstracao(MotivoSemFirebase motivo)
      : this(usingFirebase: false, uid: '', motivoSemFirebase: motivo);

  final bool usingFirebase;
  final String uid;

  /// Por que o app caiu no modo demonstracao; nulo quando [usingFirebase].
  final MotivoSemFirebase? motivoSemFirebase;
}

/// Sobe o Firebase sem derrubar o app quando algo falta.
///
/// Antes a falha era silenciosa (`catch (_)`) e quem usava o app nao sabia se
/// as cores do mapa vinham do banco ou de relatos locais. Agora cada caso vira
/// um [MotivoSemFirebase] que a tela mostra na faixa do modo demonstracao (#29).
Future<FirebaseBootstrap> bootstrapFirebase() async {
  final options = DefaultFirebaseOptions.currentOrNull;
  if (options == null) {
    return const FirebaseBootstrap.demonstracao(
      MotivoSemFirebase.naoConfigurado,
    );
  }

  try {
    await Firebase.initializeApp(options: options);
  } catch (_) {
    // Rede fora ou configuracao invalida: o app segue com os trechos em
    // memoria e avisa na tela.
    return const FirebaseBootstrap.demonstracao(MotivoSemFirebase.semConexao);
  }

  try {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final uid = cred.user?.uid;
    if (uid == null || uid.isEmpty) {
      return const FirebaseBootstrap.demonstracao(
        MotivoSemFirebase.autenticacaoFalhou,
      );
    }
    return FirebaseBootstrap.firebase(uid);
  } catch (_) {
    // Sem uid o Firestore recusaria os relatos pelas regras: melhor admitir o
    // modo demonstracao do que gravar relato com identidade vazia.
    return const FirebaseBootstrap.demonstracao(
      MotivoSemFirebase.autenticacaoFalhou,
    );
  }
}
