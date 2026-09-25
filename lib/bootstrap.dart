import 'package:achar_vagas_app/ambiente.dart';
import 'package:achar_vagas_app/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Liga o app nos emuladores do docker-compose: `--dart-define=USAR_EMULADOR=true`.
const bool usarEmulador = bool.fromEnvironment('USAR_EMULADOR');

/// Host dos emuladores: de dentro do navegador e `localhost` (o nome do
/// servico, `firebase`, so existe dentro da rede do compose).
const String hostEmulador =
    String.fromEnvironment('HOST_EMULADOR', defaultValue: hostEmuladorPadrao);

const String hostEmuladorPadrao = 'localhost';

/// Portas iguais as do `firebase.json` e do `docker-compose.yml`.
const int portaEmuladorAuth = 9099;
const int portaEmuladorFirestore = 8080;

/// Projeto `demo-` do `.firebaserc`: 100% local e o mesmo que o
/// `tools/pipeline/semear_firestore.py` usa por padrao (e onde a semente de
/// `trechos` fica). `--dart-define=PROJETO_EMULADOR=outro` troca, se precisar.
const String projetoEmulador = String.fromEnvironment(
  'PROJETO_EMULADOR',
  defaultValue: 'demo-achar-vagas',
);

/// Opcoes de fachada do projeto local: com o emulador de pe nenhuma dessas
/// chaves e validada (o emulador so olha o `projectId`), mas elas precisam
/// existir para o app nao cair em modo demonstracao so porque o
/// `firebase_options.dart` ainda esta em branco.
const FirebaseOptions opcoesEmuladorLocal = FirebaseOptions(
  apiKey: 'emulador-local-sem-chave',
  appId: '1:1:web:emulador-local',
  messagingSenderId: '1',
  projectId: projetoEmulador,
  storageBucket: '$projetoEmulador.appspot.com',
  authDomain: '$projetoEmulador.firebaseapp.com',
);

/// Decisao lida das dart-defines do build.
class ConfiguracaoEmulador {
  const ConfiguracaoEmulador({required this.ligado, required this.host});

  final bool ligado;
  final String host;
}

/// Le as dart-defines; [ligado] e [host] existem para os testes.
ConfiguracaoEmulador configuracaoEmulador({bool? ligado, String? host}) {
  final escolhido = (host ?? hostEmulador).trim();
  return ConfiguracaoEmulador(
    ligado: ligado ?? usarEmulador,
    host: escolhido.isEmpty ? hostEmuladorPadrao : escolhido,
  );
}

/// Resultado do bootstrap: Firebase pronto ou o motivo de seguir sem backend
/// (issue #29).
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
///
/// Com a flag do emulador ligada o `firebase_options.dart` e ignorado de
/// proposito: o app vai direto para o projeto local, que e o mesmo onde a
/// semente de trechos foi gravada. Sem a flag nada muda (demonstracao ou
/// firebase real).
Future<FirebaseBootstrap> bootstrapFirebase({
  ConfiguracaoEmulador? emulador,
}) async {
  final config = emulador ?? configuracaoEmulador();
  final options =
      config.ligado ? opcoesEmuladorLocal : DefaultFirebaseOptions.currentOrNull;
  if (options == null) {
    return const FirebaseBootstrap.demonstracao(
      MotivoSemFirebase.naoConfigurado,
    );
  }

  try {
    await Firebase.initializeApp(options: options);
    if (config.ligado) {
      // antes do signInAnonymously: senao o login sairia para o firebase real.
      // o `automaticHostMapping` ja troca localhost por 10.0.2.2 no android.
      await FirebaseAuth.instance
          .useAuthEmulator(config.host, portaEmuladorAuth);
      FirebaseFirestore.instance.useFirestoreEmulator(
        config.host,
        portaEmuladorFirestore,
      );
    }
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
    // modo demonstracao do que gravar relato com identidade vazia. Com a flag do
    // emulador ligada a falha aqui e ele fora do ar, e nao o provedor real.
    return FirebaseBootstrap.demonstracao(
      config.ligado
          ? MotivoSemFirebase.semConexao
          : MotivoSemFirebase.autenticacaoFalhou,
    );
  }
}
