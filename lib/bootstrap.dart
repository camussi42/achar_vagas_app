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

class FirebaseBootstrap {
  const FirebaseBootstrap({required this.usingFirebase, required this.uid});

  final bool usingFirebase;
  final String uid;
}

Future<FirebaseBootstrap> bootstrapFirebase({
  ConfiguracaoEmulador? emulador,
}) async {
  final config = emulador ?? configuracaoEmulador();
  // com a flag ligada o `firebase_options.dart` e ignorado de proposito: o app
  // vai direto para o projeto local, que e o mesmo onde a semente de trechos
  // foi gravada. sem a flag nada muda (demonstracao ou firebase real).
  final options =
      config.ligado ? opcoesEmuladorLocal : DefaultFirebaseOptions.currentOrNull;
  if (options == null) {
    return const FirebaseBootstrap(usingFirebase: false, uid: '');
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
    final cred = await FirebaseAuth.instance.signInAnonymously();
    return FirebaseBootstrap(
      usingFirebase: true,
      uid: cred.user?.uid ?? '',
    );
  } catch (_) {
    return const FirebaseBootstrap(usingFirebase: false, uid: '');
  }
}
