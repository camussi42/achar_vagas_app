import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/ui/camadas_mapa.dart';
import 'package:achar_vagas_app/ui/detalhe_trecho.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// folha de detalhe: via, estado, idade e contagem dos relatos validos.
void main() {
  const idCanonico = 'gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9';
  const ponto = LatLng(-24.0430793, -52.3772141);
  final agora = DateTime.utc(2026, 9, 21, 12);

  DetalheTrecho detalhe({
    String? via = 'Rua São Paulo',
    String valor = idCanonico,
    EstadoTrecho estado = EstadoTrecho.vaga,
    int total = 1,
    int vagas = 1,
    double raioM = 0,
    Duration atras = const Duration(minutes: 3),
    VoidCallback? onIrAteAqui,
  }) =>
      DetalheTrecho(
        camada: TrechoEstado(
          id: TrechoId.parse(valor),
          resumo: ResumoEstado(
            estado: estado,
            total: total,
            vagas: vagas,
            atualizadoEm: agora.subtract(atras),
          ),
          via: via,
          centro: ponto,
          raioM: raioM,
        ),
        agora: agora,
        onIrAteAqui: onIrAteAqui,
      );

  Future<void> mostrar(WidgetTester tester, Widget folha) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: folha)),
      );

  group('idadeLegivel', () {
    test('menos de um minuto e "agora"', () {
      expect(
        idadeLegivel(agora.subtract(const Duration(seconds: 30)), agora: agora),
        'agora',
      );
    });

    test('minutos em texto curto', () {
      expect(
        idadeLegivel(agora.subtract(const Duration(minutes: 3)), agora: agora),
        'há 3 min',
      );
    });

    test('horas (relato que passou da validade) nao viram numero absurdo', () {
      expect(
        idadeLegivel(agora.subtract(const Duration(hours: 2)), agora: agora),
        'há 2 h',
      );
      expect(
        idadeLegivel(
          agora.subtract(const Duration(hours: 2, minutes: 5)),
          agora: agora,
        ),
        'há 2 h 05',
      );
    });

    test('sem relato e horario no futuro (relogio atrasado)', () {
      expect(idadeLegivel(null, agora: agora), 'sem relato');
      expect(
        idadeLegivel(agora.add(const Duration(minutes: 2)), agora: agora),
        'agora',
      );
    });
  });

  group('DetalheTrecho', () {
    testWidgets('mostra via, estado, contagem e idade do relato', (tester) async {
      await mostrar(tester, detalhe());

      expect(find.byKey(chaveDetalheTrecho), findsOneWidget);
      expect(find.text('Rua São Paulo'), findsOneWidget);
      expect(find.text('Com vaga'), findsOneWidget);
      expect(find.text('1 relato válido nos últimos 20 min'), findsOneWidget);
      expect(find.text('1 com vaga · 0 lotado · 0 liberando'), findsOneWidget);
      expect(find.text('Relato mais recente: há 3 min'), findsOneWidget);
    });

    testWidgets('mostra a contagem no plural', (tester) async {
      await mostrar(tester, detalhe(total: 3, vagas: 2));

      expect(find.text('3 relatos válidos nos últimos 20 min'), findsOneWidget);
    });

    testWidgets('fallback geohash usa o rotulo de area aproximada',
        (tester) async {
      await mostrar(
        tester,
        detalhe(via: null, valor: 'gh:6gdz0ph', raioM: 75),
      );

      expect(find.text('Área aproximada (~75 m)'), findsOneWidget);
    });

    testWidgets('sem relato valido avisa em vez de mostrar idade',
        (tester) async {
      await mostrar(
        tester,
        DetalheTrecho(
          camada: TrechoEstado(
            id: TrechoId.geohash('6gdz0ph'),
            resumo: const ResumoEstado.desconhecido(),
            centro: ponto,
            raioM: 75,
          ),
          agora: agora,
        ),
      );

      expect(find.text('Nenhum relato válido agora'), findsOneWidget);
      expect(find.textContaining('Relato mais recente'), findsNothing);
    });

    testWidgets('sem callback de rota o botao nao aparece', (tester) async {
      await mostrar(tester, detalhe());

      expect(find.byKey(chaveBotaoIrAteTrecho), findsNothing);
      expect(find.text('Ir até aqui'), findsNothing);
    });

    testWidgets('com callback o botao de rota aparece e dispara',
        (tester) async {
      var toques = 0;
      await mostrar(tester, detalhe(onIrAteAqui: () => toques++));

      expect(find.byKey(chaveBotaoIrAteTrecho), findsOneWidget);
      await tester.tap(find.byKey(chaveBotaoIrAteTrecho));

      expect(toques, 1);
    });
  });
}
