/// grafo de dependencias do app, montado uma unica vez no `main`;
/// a tela recebe tudo pronto, o que permite trocar por memoria e dubles.
library;

import 'package:achar_vagas_app/data/trechos_demo_gerado.dart';
import 'package:achar_vagas_app/geo/resolver_geohash.dart';
import 'package:achar_vagas_app/geo/resolver_overture.dart';
import 'package:achar_vagas_app/geo/trecho_resolver.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:achar_vagas_app/services/localizacao.dart';
import 'package:achar_vagas_app/services/relatos_repository.dart';
import 'package:achar_vagas_app/services/rota.dart';
import 'package:achar_vagas_app/services/trechos_repository.dart';

/// Uid usado no modo demonstracao (sem Auth anonimo).
const String uidDemonstracao = 'dev-local';

class AmbienteApp {
  const AmbienteApp({
    required this.usandoFirebase,
    required this.uid,
    required this.localizacao,
    required this.relatos,
    required this.trechos,
    this.rota = const RotaUrlLauncher(),
  });

  /// `false` quando o Firebase nao esta configurado (modo demonstracao).
  final bool usandoFirebase;

  /// Uid do usuario (Auth anonimo) ou [uidDemonstracao] no modo demonstracao.
  final String uid;

  final LocalizacaoService localizacao;
  final RelatosRepository relatos;
  final TrechosRepository trechos;

  /// servico de rota ate o trecho.
  final RotaService rota;

  /// Cascata da issue #12: trecho canonico (Overture/GERS) e, quando nao ha
  /// malha importada para o ponto, a area aproximada por geohash.
  TrechoResolver get resolvedor => TrechoResolverCascata(<TrechoResolver>[
        ResolverOverture(trechos),
        const ResolverGeohash(),
      ]);

  /// Modo demonstracao: repositorios em memoria, semeados com os trechos reais
  /// do centro de Campo Mourao, e GPS real (quando houver permissao).
  factory AmbienteApp.demonstracao() => AmbienteApp(
        usandoFirebase: false,
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
