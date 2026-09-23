import 'package:achar_vagas_app/ambiente.dart';
import 'package:achar_vagas_app/config.dart';
import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:achar_vagas_app/services/localizacao.dart';
import 'package:achar_vagas_app/services/relatos_repository.dart';
import 'package:achar_vagas_app/services/trechos_repository.dart';
import 'package:achar_vagas_app/ui/legenda_estado.dart';
import 'package:achar_vagas_app/ui/tela_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'apoio/tiles_falsos.dart';

/// Tela do mapa (issues #3, #12, #13 e #30) com repositorios em memoria, tiles
/// falsos e posicao controlada: nada de rede, GPS real ou Firebase.
///
/// A #30 cobre os quatro motivos de localizacao indisponivel e a acao de abrir
/// as configuracoes (do app ou do sistema), por isso os fakes registram as
/// chamadas de `abrirConfiguracoes*`.
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

  AmbienteApp ambienteCom({
    required LocalizacaoService localizacao,
    RelatosMemoria? relatos,
    List<Trecho> trechos = const <Trecho>[],
  }) =>
      AmbienteApp(
        usandoFirebase: false,
        uid: 'teste',
        localizacao: localizacao,
        relatos: relatos ?? RelatosMemoria(),
        trechos: TrechosMemoria(trechos),
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

    // Texto do caso (nao mais a mensagem unica da #3) e o caminho de correcao.
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

    // A permissao foi pedida (e negada) na abertura, mas sem aviso: o mapa ja
    // esta em Campo Mourao e o caminho de correcao fica no botao (issue #30).
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
        trechos: <Trecho>[trechoDeTeste(pontoFixo)],
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
}

/// Sem acesso a localizacao: devolve sempre o [motivo] informado e registra se
/// as configuracoes foram abertas (issue #30).
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
