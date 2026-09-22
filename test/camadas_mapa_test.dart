import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/estado_trecho.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:achar_vagas_app/ui/camadas_mapa.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Regras de pintura do mapa (issue #13): linha para trecho canonico com
/// geometria, circulo para o fallback geohash e nada para trecho sem relato.
void main() {
  const idCanonico = 'gers:c1d70afe-a7de-4b73-a41c-e92526ab72f9';
  const idFallback = 'gh:6gdz0ph';
  const ponto = LatLng(-24.0430793, -52.3772141);
  final agora = DateTime.utc(2026, 9, 21, 12);

  Trecho trechoCanonico({bool comGeometria = true}) => Trecho(
        id: TrechoId.parse(idCanonico),
        via: 'Rua São Paulo',
        centroide: ponto,
        geohash: geohashCodificar(ponto.latitude, ponto.longitude, precisao: 6),
        geometria: comGeometria
            ? const <LatLng>[
                LatLng(-24.0430000, -52.3780000),
                LatLng(-24.0430000, -52.3760000),
              ]
            : const <LatLng>[],
      );

  Relato relato(
    String trecho,
    TipoRelato tipo, {
    Duration atras = const Duration(minutes: 2),
    String uid = 'u1',
  }) =>
      Relato.novo(
        uid: uid,
        trechoId: TrechoId.parse(trecho),
        tipo: tipo,
        ponto: ponto,
        criadoEm: agora.subtract(atras),
      );

  Map<String, ResumoEstado> estadosDe(List<Relato> relatos) =>
      agregarPorTrecho(relatos, agora: agora, validade: validadeRelatoPadrao);

  group('combinar', () {
    test('trecho canonico com geometria vira linha', () {
      final camadas = combinar(
        trechos: <Trecho>[trechoCanonico()],
        estados: estadosDe(<Relato>[relato(idCanonico, TipoRelato.vaga)]),
        pontos: const <String, LatLng>{},
      );

      expect(camadas, hasLength(1));
      expect(camadas.single.temLinha, isTrue);
      expect(camadas.single.linha, hasLength(2));
      expect(camadas.single.raioM, 0);
      expect(camadas.single.rotulo, 'Rua São Paulo');
      expect(camadas.single.estado, EstadoTrecho.vaga);
      expect(camadas.single.id.canonico, isTrue);
    });

    test('trecho canonico sem geometria vira circulo no ponto relatado', () {
      final camadas = combinar(
        trechos: <Trecho>[trechoCanonico(comGeometria: false)],
        estados: estadosDe(<Relato>[relato(idCanonico, TipoRelato.lotado)]),
        pontos: const <String, LatLng>{idCanonico: ponto},
      );

      expect(camadas, hasLength(1));
      expect(camadas.single.temLinha, isFalse);
      expect(camadas.single.centro, ponto);
      expect(camadas.single.raioM, raioSemGeometriaM);
      expect(camadas.single.estado, EstadoTrecho.lotado);
    });

    test('trecho canonico sem geometria nem ponto conhecido nao e desenhado', () {
      final camadas = combinar(
        trechos: const <Trecho>[],
        estados: estadosDe(<Relato>[relato(idCanonico, TipoRelato.vaga)]),
        pontos: const <String, LatLng>{},
      );

      expect(camadas, isEmpty);
    });

    test('fallback geohash vira circulo no centro da celula', () {
      final caixa = geohashCaixa('6gdz0ph');
      final menor = caixa.alturaM < caixa.larguraM ? caixa.alturaM : caixa.larguraM;

      final camadas = combinar(
        trechos: const <Trecho>[],
        estados: estadosDe(<Relato>[relato(idFallback, TipoRelato.saindo)]),
        pontos: const <String, LatLng>{idFallback: ponto},
      );

      expect(camadas, hasLength(1));
      final camada = camadas.single;
      expect(camada.temLinha, isFalse);
      expect(camada.id.canonico, isFalse);
      expect(camada.estado, EstadoTrecho.saindo);
      expect(camada.centro.latitude, closeTo(caixa.centro.latitude, 1e-9));
      expect(camada.centro.longitude, closeTo(caixa.centro.longitude, 1e-9));
      expect(camada.raioM, closeTo(menor / 2, 1e-9));
      expect(camada.raioM, greaterThan(0));
    });

    test('trecho sem relato nao entra nas camadas', () {
      final camadas = combinar(
        trechos: <Trecho>[trechoCanonico()],
        estados: const <String, ResumoEstado>{},
        pontos: const <String, LatLng>{},
      );

      expect(camadas, isEmpty);
    });

    test('id fora do padrao e ignorado sem lancar', () {
      final camadas = combinar(
        trechos: const <Trecho>[],
        estados: <String, ResumoEstado>{
          'gers:xpto': const ResumoEstado(estado: EstadoTrecho.vaga, total: 1),
        },
        pontos: const <String, LatLng>{},
      );

      expect(camadas, isEmpty);
    });

    test('hash fora do alfabeto base32 e ignorado sem derrubar o mapa', () {
      // `TrechoId` aceita [0-9a-z]{6,9}, mas o geohash so usa base32 (sem a, i,
      // l e o): um id assim nao pode quebrar o desenho.
      final camadas = combinar(
        trechos: const <Trecho>[],
        estados: <String, ResumoEstado>{
          'gh:6gdz0pa': const ResumoEstado(estado: EstadoTrecho.vaga, total: 1),
        },
        pontos: const <String, LatLng>{},
      );

      expect(camadas, isEmpty);
    });

    test('ordem das camadas e estavel (por id)', () {
      final camadas = combinar(
        trechos: const <Trecho>[],
        estados: <String, ResumoEstado>{
          idFallback: const ResumoEstado(estado: EstadoTrecho.vaga, total: 1),
          idCanonico: const ResumoEstado(estado: EstadoTrecho.lotado, total: 1),
        },
        pontos: const <String, LatLng>{idCanonico: ponto},
      );

      expect(
        camadas.map((camada) => camada.id.valor).toList(),
        <String>[idCanonico, idFallback],
      );
    });
  });

  group('pontosMaisRecentes', () {
    test('guarda o ponto do relato mais recente de cada trecho', () {
      final pontos = pontosMaisRecentes(
        <Relato>[
          Relato.novo(
            uid: 'u1',
            trechoId: TrechoId.parse(idCanonico),
            tipo: TipoRelato.vaga,
            ponto: const LatLng(-24.0400000, -52.3700000),
            criadoEm: agora.subtract(const Duration(minutes: 10)),
          ),
          relato(idCanonico, TipoRelato.lotado, atras: const Duration(minutes: 1)),
        ],
        agora: agora,
        validade: validadeRelatoPadrao,
      );

      expect(pontos, hasLength(1));
      expect(pontos[idCanonico], ponto);
    });

    test('descarta relato vencido', () {
      final pontos = pontosMaisRecentes(
        <Relato>[
          relato(idFallback, TipoRelato.vaga,
              atras: const Duration(minutes: 21)),
        ],
        agora: agora,
        validade: validadeRelatoPadrao,
      );

      expect(pontos, isEmpty);
    });
  });
}
