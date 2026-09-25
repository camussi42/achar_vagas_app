/// Grafo de dependencias do app, montado uma unica vez no `main`.
///
/// A tela recebe tudo pronto (localizacao, repositorios e o resolvedor de
/// trecho). Isso permite trocar Firestore por memoria (modo demonstracao, sem
/// `firebase_options`) e GPS por posicao fixa (testes) sem tocar na UI.
library;

import 'package:achar_vagas_app/data/trechos_demo_gerado.dart';
import 'package:achar_vagas_app/geo/resolver_geohash.dart';
import 'package:achar_vagas_app/geo/resolver_overture.dart';
import 'package:achar_vagas_app/geo/trecho_resolver.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:achar_vagas_app/services/localizacao.dart';
import 'package:achar_vagas_app/services/relatos_repository.dart';
import 'package:achar_vagas_app/services/trechos_repository.dart';

/// Uid usado no modo demonstracao (sem Auth anonimo).
const String uidDemonstracao = 'dev-local';

/// Por que o app subiu sem backend (issue #29).
///
/// O `bootstrapFirebase` nunca derruba a abertura: o modo demonstracao entra no
/// lugar do Firebase e o motivo fica registrado aqui para a tela deixar claro
/// se as cores do mapa vem do banco ou de relatos locais.
enum MotivoSemFirebase {
  /// `firebase_options.dart` sem chaves (falta o `flutterfire configure`).
  naoConfigurado,

  /// `Firebase.initializeApp` falhou: rede fora ou configuracao invalida.
  semConexao,

  /// Auth anonimo recusado (provedor desativado, cota, regras).
  autenticacaoFalhou,
}

extension MotivoSemFirebaseTexto on MotivoSemFirebase {
  /// Detalhe curto mostrado na faixa da tela.
  String get rotulo => switch (this) {
        MotivoSemFirebase.naoConfigurado => 'Firebase não configurado',
        MotivoSemFirebase.semConexao => 'não foi possível conectar',
        MotivoSemFirebase.autenticacaoFalhou => 'falha no login anônimo',
      };
}

class AmbienteApp {
  const AmbienteApp({
    required this.usandoFirebase,
    required this.uid,
    required this.localizacao,
    required this.relatos,
    required this.trechos,
    this.motivoSemFirebase,
  });

  /// `false` quando o Firebase nao esta configurado (modo demonstracao).
  final bool usandoFirebase;

  /// Por que o app esta sem backend (issue #29); nulo quando usa o Firebase.
  final MotivoSemFirebase? motivoSemFirebase;

  /// Uid do usuario (Auth anonimo) ou [uidDemonstracao] no modo demonstracao.
  final String uid;

  final LocalizacaoService localizacao;
  final RelatosRepository relatos;
  final TrechosRepository trechos;

  /// Cascata da issue #12: trecho canonico (Overture/GERS) e, quando nao ha
  /// malha importada para o ponto, a area aproximada por geohash.
  TrechoResolver get resolvedor => TrechoResolverCascata(<TrechoResolver>[
        ResolverOverture(trechos),
        const ResolverGeohash(),
      ]);

  /// Modo demonstracao: repositorios em memoria, semeados com os trechos reais
  /// do centro de Campo Mourao, e GPS real (quando houver permissao).
  ///
  /// [motivo] e o que o `bootstrapFirebase` registrou (issue #29) e vai para a
  /// faixa que a tela mostra no topo do mapa.
  factory AmbienteApp.demonstracao({
    MotivoSemFirebase motivo = MotivoSemFirebase.naoConfigurado,
  }) =>
      AmbienteApp(
        usandoFirebase: false,
        motivoSemFirebase: motivo,
        uid: uidDemonstracao,
        localizacao: const LocalizacaoGeolocator(),
        relatos: RelatosMemoria(),
        trechos: TrechosMemoria(trechosDemoGerado.map(Trecho.fromMap)),
      );

  /// Modo Firebase: relatos e trechos ao vivo no Firestore.
  factory AmbienteApp.firebase({required String uid}) => AmbienteApp(
        usandoFirebase: true,
        uid: uid,
        localizacao: const LocalizacaoGeolocator(),
        relatos: RelatosFirestore(),
        trechos: TrechosFirestore(),
      );
}
