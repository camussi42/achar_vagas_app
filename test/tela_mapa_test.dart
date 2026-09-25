import 'package:achar_vagas_app/ambiente.dart';
import 'package:achar_vagas_app/config.dart';
import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:achar_vagas_app/services/localizacao.dart';
import 'package:achar_vagas_app/services/relatos_repository.dart';
import 'package:achar_vagas_app/services/trechos_repository.dart';
import 'package:achar_vagas_app/ui/faixa_aviso.dart';
import 'package:achar_vagas_app/ui/legenda_estado.dart';
import 'package:achar_vagas_app/ui/detalhe_trecho.dart';
import 'package:achar_vagas_app/ui/tela_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'apoio/tiles_falsos.dart';

/// tela do mapa (issues #3, #12, #13, #29 e #30) com repositorios em memoria,
/// tiles falsos e posicao controlada: nada de rede, GPS real ou Firebase.
///
/// os fakes registram as chamadas de `abrirConfiguracoes*` (aviso de
/// localizacao indisponivel) e falham de proposito para exercitar as faixas de
/// aviso do modo demonstracao (issue #29).
void main() {
  const uuid = 'c1d70afe-a7de-4b73-a41c-e92526ab72f9';
  const pontoFixo = LatLng(-24.0455000, -52.3790000);

  Trecho trechoDeTeste(LatLng centro) => Trecho(
        id: TrechoId.overture(uuid),
        via: 'Rua São Paulo',
        centroide: centro,
        geohash: geohashCodificar(
          centro.latitude,
          centro.longitude,
          precisao: precisaoGeohashConsulta,
        ),
        geometria: <LatLng>[
          LatLng(centro.latitude, centro.longitude - 0.001),
          LatLng(centro.latitude, centro.longitude + 0.001),
        ],
      );

  /// [usandoFirebase] e [motivo] controlam o aviso do topo do mapa (issue #29)
  /// e os repositorios podem ser trocados por fakes que falham.
  AmbienteApp ambienteCom({
    required LocalizacaoService localizacao,
    RelatosRepository? relatos,
    TrechosRepository? trechos,
    bool usandoFirebase = false,
    MotivoSemFirebase motivo = MotivoSemFirebase.naoConfigurado,
  }) =>
      AmbienteApp(
        usandoFirebase: usandoFirebase,
        uid: 'teste',
        motivoSemFirebase: usandoFirebase ? null : motivo,
        localizacao: localizacao,
        relatos: relatos ?? RelatosMemoria(),
        trechos: trechos ?? TrechosMemoria(),
      );

  Future<void> abrir(WidgetTester tester, AmbienteApp ambiente) async {
    await tester.pumpWidget(
      MaterialApp(home: TelaMapa(ambiente: ambiente, tileProvider: TilesFalsos())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  MapCamera cameraDoMapa(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(TileLayer)));

  /// relato valido (3 min atras) no ponto fixo.
  Relato relatoDeTeste(TrechoId trecho, TipoRelato tipo) => Relato.novo(
        uid: 'teste',
        trechoId: trecho,
        tipo: tipo,
        ponto: pontoFixo,
        criadoEm: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
      );

  /// posicao na tela de um ponto do mapa (para `tester.tapAt`).
  Offset naTela(WidgetTester tester, LatLng ponto) =>
      tester.getTopLeft(find.byType(FlutterMap)) +
      cameraDoMapa(tester).latLngToScreenOffset(ponto);

  testWidgets('mostra o mapa, os botoes de relato e a legenda', (tester) async {
    await abrir(
      tester,
      ambienteCom(localizacao: const LocalizacaoFixa(centroCampoMourao)),
    );

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Tem vaga'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Lotado'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Estou saindo'), findsOneWidget);
    expect(find.byType(LegendaEstado), findsOneWidget);
    expect(find.text('Relatos valem por 20 min'), findsOneWidget);
    expect(find.text('Com vaga'), findsOneWidget);
  });

  testWidgets('abre centralizado em Campo Mourao', (tester) async {
    await abrir(
      tester,
      ambienteCom(
        localizacao: _LocalizacaoSemAcesso(MotivoLocalizacao.servicoDesligado),
      ),
    );

    final camera = cameraDoMapa(tester);
    expect(camera.center.latitude, closeTo(centroCampoMourao.latitude, 1e-6));
    expect(camera.center.longitude, closeTo(centroCampoMourao.longitude, 1e-6));
    expect(camera.zoom, zoomInicialMapa);
  });

  testWidgets('mostra o marcador na posicao do usuario', (tester) async {
    await abrir(tester, ambienteCom(localizacao: const LocalizacaoFixa(pontoFixo)));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(chaveMarcadorUsuario), findsOneWidget);
    final camera = cameraDoMapa(tester);
    expect(camera.center.latitude, closeTo(pontoFixo.latitude, 1e-6));
    expect(camera.center.longitude, closeTo(pontoFixo.longitude, 1e-6));
    expect(camera.zoom, zoomUsuarioMapa);
  });

  testWidgets('permissao negada explica o caso e abre as configuracoes do app',
      (tester) async {
    final localizacao = _LocalizacaoSemAcesso(MotivoLocalizacao.permissaoNegada);
    final relatos = RelatosMemoria();
    await abrir(
      tester,
      ambienteCom(localizacao: localizacao, relatos: relatos),
    );

    expect(find.byKey(chaveMarcadorUsuario), findsNothing);

    await tester.tap(find.byKey(chaveBotaoLocalizacao));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // texto do motivo e caminho de correcao (a mensagem unica era da #3).
    expect(find.textContaining('permissão de localização está bloqueada'),
        findsOneWidget);
    expect(find.text('Abrir configurações'), findsOneWidget);
    expect(relatos.todos, isEmpty);
    expect(cameraDoMapa(tester).center.latitude,
        closeTo(centroCampoMourao.latitude, 1e-6));

    await tester.tap(find.byKey(chaveAbrirConfiguracoes));
    await tester.pump();

    expect(localizacao.configuracoesAppAbertas, 1);
    expect(localizacao.configuracoesLocalizacaoAbertas, 0);
  });

  testWidgets('permissao negada para sempre tambem leva as configuracoes do app',
      (tester) async {
    final localizacao =
        _LocalizacaoSemAcesso(MotivoLocalizacao.permissaoNegadaParaSempre);
    await abrir(tester, ambienteCom(localizacao: localizacao));

    await tester.tap(find.byKey(chaveBotaoLocalizacao));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('negada em definitivo'), findsOneWidget);

    await tester.tap(find.byKey(chaveAbrirConfiguracoes));
    await tester.pump();

    expect(localizacao.configuracoesAppAbertas, 1);
    expect(localizacao.configuracoesLocalizacaoAbertas, 0);
  });

  testWidgets('GPS desligado explica o caso e abre a localizacao do sistema',
      (tester) async {
    final localizacao = _LocalizacaoSemAcesso(MotivoLocalizacao.servicoDesligado);
    await abrir(tester, ambienteCom(localizacao: localizacao));

    await tester.tap(find.byKey(chaveBotaoLocalizacao));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('GPS do aparelho está desligado'), findsOneWidget);
    expect(find.text('Ativar localização'), findsOneWidget);

    await tester.tap(find.byKey(chaveAbrirConfiguracoes));
    await tester.pump();

    expect(localizacao.configuracoesLocalizacaoAbertas, 1);
    expect(localizacao.configuracoesAppAbertas, 0);
  });

  testWidgets('falha ao obter a posicao avisa sem oferecer acao',
      (tester) async {
    final localizacao = _LocalizacaoSemAcesso(MotivoLocalizacao.falha);
    await abrir(tester, ambienteCom(localizacao: localizacao));

    await tester.tap(find.byKey(chaveBotaoLocalizacao));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('Tente de novo em instantes'), findsOneWidget);
    expect(find.byKey(chaveAbrirConfiguracoes), findsNothing);
    expect(localizacao.configuracoesAppAbertas, 0);
    expect(localizacao.configuracoesLocalizacaoAbertas, 0);
  });

  testWidgets('na abertura o aviso de localizacao nao aparece', (tester) async {
    await abrir(
      tester,
      ambienteCom(
        localizacao: _LocalizacaoSemAcesso(MotivoLocalizacao.permissaoNegada),
      ),
    );

    // permissao negada na abertura: sem aviso, o caminho fica no botao.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('permissão'), findsNothing);
  });

  testWidgets('relatar sem localizacao avisa o motivo e nada e gravado',
      (tester) async {
    final localizacao = _LocalizacaoSemAcesso(MotivoLocalizacao.servicoDesligado);
    final relatos = RelatosMemoria();
    await abrir(
      tester,
      ambienteCom(localizacao: localizacao, relatos: relatos),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Tem vaga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(relatos.todos, isEmpty);
    expect(find.textContaining('GPS do aparelho está desligado'), findsOneWidget);
    expect(find.byKey(chaveAbrirConfiguracoes), findsOneWidget);
  });

  testWidgets('relatar resolve o trecho pela cascata e grava o relato',
      (tester) async {
    final relatos = RelatosMemoria();
    await abrir(
      tester,
      ambienteCom(
        localizacao: const LocalizacaoFixa(pontoFixo),
        relatos: relatos,
        trechos: TrechosMemoria(<Trecho>[trechoDeTeste(pontoFixo)]),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Tem vaga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(relatos.todos, hasLength(1));
    final relato = relatos.todos.single;
    expect(relato.tipo, TipoRelato.vaga);
    expect(relato.uid, 'teste');
    expect(relato.ponto, pontoFixo);
    expect(relato.trechoId, TrechoId.overture(uuid));
    expect(relato.trechoId.canonico, isTrue);
    expect(relato.geohash, hasLength(9));
    expect(find.textContaining('Rua São Paulo'), findsOneWidget);
  });

  testWidgets('relato em rua fora da malha cai no fallback geohash',
      (tester) async {
    final relatos = RelatosMemoria();
    await abrir(
      tester,
      ambienteCom(
        localizacao: const LocalizacaoFixa(pontoFixo),
        relatos: relatos,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Lotado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(relatos.todos, hasLength(1));
    final relato = relatos.todos.single;
    expect(relato.tipo, TipoRelato.lotado);
    expect(relato.trechoId.canonico, isFalse);
    expect(relato.trechoId.geohash, isNotNull);
    expect(find.textContaining('área aproximada'), findsOneWidget);
  });

  testWidgets('o botao de localizacao pede a posicao e centraliza no usuario',
      (tester) async {
    final localizacao = _LocalizacaoContada(pontoFixo);
    await abrir(tester, ambienteCom(localizacao: localizacao));

    // Na abertura a permissao foi negada: o mapa fica em Campo Mourao.
    expect(localizacao.chamadas, 1);
    expect(cameraDoMapa(tester).center.latitude,
        closeTo(centroCampoMourao.latitude, 1e-6));

    await tester.tap(find.byKey(chaveBotaoLocalizacao));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(localizacao.chamadas, 2);
    final camera = cameraDoMapa(tester);
    expect(camera.center.latitude, closeTo(pontoFixo.latitude, 1e-6));
    expect(camera.center.longitude, closeTo(pontoFixo.longitude, 1e-6));
    expect(camera.zoom, zoomUsuarioMapa);
    expect(find.byKey(chaveMarcadorUsuario), findsOneWidget);
  });

  testWidgets('modo demonstracao mostra a faixa com o motivo', (tester) async {
    await abrir(
      tester,
      ambienteCom(
        localizacao: const LocalizacaoFixa(centroCampoMourao),
        motivo: MotivoSemFirebase.semConexao,
      ),
    );

    expect(find.byKey(chaveFaixaDemonstracao), findsOneWidget);
    expect(find.textContaining('Modo demonstração'), findsOneWidget);
    expect(find.textContaining('não foi possível conectar'), findsOneWidget);
    expect(find.byKey(chaveFaixaSemDados), findsNothing);
  });

  testWidgets('ambiente firebase nao mostra a faixa de demonstracao',
      (tester) async {
    await abrir(
      tester,
      ambienteCom(
        localizacao: const LocalizacaoFixa(centroCampoMourao),
        usandoFirebase: true,
      ),
    );

    expect(find.byKey(chaveFaixaDemonstracao), findsNothing);
    expect(find.byKey(chaveFaixaSemDados), findsNothing);
  });

  testWidgets('falha dos relatos em tempo de execucao mostra a faixa',
      (tester) async {
    await abrir(
      tester,
      ambienteCom(
        localizacao: const LocalizacaoFixa(centroCampoMourao),
        usandoFirebase: true,
        relatos: _RelatosQueFalham(),
      ),
    );

    expect(find.byKey(chaveFaixaSemDados), findsOneWidget);
    expect(find.textContaining('o mapa pode estar desatualizado'),
        findsOneWidget);
    expect(find.byKey(chaveFaixaDemonstracao), findsNothing);
  });

  testWidgets('falha da consulta de trechos tambem mostra a faixa',
      (tester) async {
    await abrir(
      tester,
      ambienteCom(
        localizacao: const LocalizacaoFixa(centroCampoMourao),
        usandoFirebase: true,
        trechos: _TrechosQueFalham(),
      ),
    );

    expect(find.byKey(chaveFaixaSemDados), findsOneWidget);
    expect(find.byKey(chaveFaixaDemonstracao), findsNothing);
  });

  testWidgets('tocar na linha do trecho abre o detalhe com via, estado e idade',
      (tester) async {
    final relatos = RelatosMemoria();
    await relatos.criar(
      relatoDeTeste(TrechoId.overture(uuid), TipoRelato.vaga),
    );
    await abrir(
      tester,
      ambienteCom(
        localizacao: const _LocalizacaoNula(),
        relatos: relatos,
        trechos: TrechosMemoria(<Trecho>[trechoDeTeste(pontoFixo)]),
      ),
    );

    // o toque cai no meio da geometria.
    await tester.tapAt(naTela(tester, pontoFixo));
    await tester.pumpAndSettle();

    expect(find.byKey(chaveDetalheTrecho), findsOneWidget);
    expect(find.text('Rua São Paulo'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(chaveDetalheTrecho),
        matching: find.text('Com vaga'),
      ),
      findsOneWidget,
    );
    expect(find.text('1 relato válido nos últimos 20 min'), findsOneWidget);
    expect(find.text('Relato mais recente: há 3 min'), findsOneWidget);
  });

  testWidgets('tocar no circulo do fallback abre o detalhe da area aproximada',
      (tester) async {
    final relatos = RelatosMemoria();
    final idAproximado = Trecho.aproximado(pontoFixo).id;
    await relatos.criar(relatoDeTeste(idAproximado, TipoRelato.lotado));
    await abrir(
      tester,
      ambienteCom(
        localizacao: const _LocalizacaoNula(),
        relatos: relatos,
      ),
    );

    // sem trecho canonico o relato vira circulo na celula do geohash.
    final celula = geohashCaixa(idAproximado.chave);
    await tester.tapAt(naTela(tester, celula.centro));
    await tester.pumpAndSettle();

    expect(find.byKey(chaveDetalheTrecho), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(chaveDetalheTrecho),
        matching: find.textContaining('Área aproximada'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(chaveDetalheTrecho),
        matching: find.text('Lotado'),
      ),
      findsOneWidget,
    );
  });
}

/// sem permissao/servico de GPS: nunca ha posicao. Fake dos testes de detalhe
/// (#26), que nao precisam de localizacao para tocar no trecho.
class _LocalizacaoNula implements LocalizacaoService {
  const _LocalizacaoNula();

  @override
  Future<ResultadoLocalizacao> posicaoAtual() async =>
      const LocalizacaoIndisponivel(MotivoLocalizacao.falha);

  @override
  Stream<LatLng> acompanhar() => const Stream<LatLng>.empty();

  @override
  Future<void> abrirConfiguracoes() async {}

  @override
  Future<void> abrirConfiguracoesDeLocalizacao() async {}
}

/// localizacao sem acesso: devolve sempre o [motivo] e registra as configs.
class _LocalizacaoSemAcesso implements LocalizacaoService {
  _LocalizacaoSemAcesso(this.motivo);

  final MotivoLocalizacao motivo;
  int chamadas = 0;
  int configuracoesAppAbertas = 0;
  int configuracoesLocalizacaoAbertas = 0;

  @override
  Future<ResultadoLocalizacao> posicaoAtual() async {
    chamadas++;
    return LocalizacaoIndisponivel(motivo);
  }

  @override
  Stream<LatLng> acompanhar() => const Stream<LatLng>.empty();

  @override
  Future<void> abrirConfiguracoes() async {
    configuracoesAppAbertas++;
  }

  @override
  Future<void> abrirConfiguracoesDeLocalizacao() async {
    configuracoesLocalizacaoAbertas++;
  }
}

/// Nega a permissao na abertura e "autoriza" a partir da segunda chamada.
class _LocalizacaoContada implements LocalizacaoService {
  _LocalizacaoContada(this.ponto);

  final LatLng ponto;
  int chamadas = 0;

  @override
  Future<ResultadoLocalizacao> posicaoAtual() async {
    chamadas++;
    return chamadas == 1
        ? const LocalizacaoIndisponivel(MotivoLocalizacao.permissaoNegada)
        : LocalizacaoOk(ponto);
  }

  @override
  Stream<LatLng> acompanhar() => const Stream<LatLng>.empty();

  @override
  Future<void> abrirConfiguracoes() async {}

  @override
  Future<void> abrirConfiguracoesDeLocalizacao() async {}
}

/// Relatos que sempre falham: simula base/rede fora em tempo de execucao.
class _RelatosQueFalham implements RelatosRepository {
  @override
  Future<Relato> criar(Relato relato) => throw StateError('sem backend');

  @override
  Future<List<Relato>> buscarProximos(
    LatLng centro, {
    double raioM = raioConsultaPadraoM,
    int limite = limiteConsultaPadrao,
  }) =>
      throw StateError('sem backend');

  @override
  Stream<List<Relato>> observarProximos(
    LatLng centro, {
    double raioM = raioConsultaPadraoM,
    int limite = limiteConsultaPadrao,
  }) =>
      Stream<List<Relato>>.error(StateError('sem backend'));
}

/// Trechos que sempre falham: a malha canonica fica indisponivel.
class _TrechosQueFalham implements TrechosRepository {
  @override
  Future<List<Trecho>> candidatosProximos(
    LatLng centro, {
    double raioM = 150,
    int limite = 40,
  }) =>
      throw StateError('sem backend');
}
