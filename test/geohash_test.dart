import 'dart:math' as math;

import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Valores de referencia obtidos com a biblioteca Python `pygeohash`
/// (implementacao independente), documentados em
/// `docs/adr/0001-identidade-de-trecho.md`.
///
/// Se algum destes testes falhar, a codificacao/vizinhanca esta errada e as
/// consultas por proximidade no Firestore passariam a perder relatos.
void main() {
  const centroCampoMourao = LatLng(-24.0430793, -52.3772141);

  group('geohashCodificar', () {
    test('bate com o oraculo para o centro de Campo Mourao/PR', () {
      expect(geohashCodificar(-24.0430793, -52.3772141, precisao: 4), '6gdz');
      expect(geohashCodificar(-24.0430793, -52.3772141, precisao: 5), '6gdz0');
      expect(geohashCodificar(-24.0430793, -52.3772141, precisao: 6), '6gdz0p');
      expect(geohashCodificar(-24.0430793, -52.3772141, precisao: 7), '6gdz0ph');
      expect(geohashCodificar(-24.0430793, -52.3772141, precisao: 8), '6gdz0ph4');
      expect(geohashCodificar(-24.0430793, -52.3772141, precisao: 9), '6gdz0ph4f');
    });

    test('bate com o caso canonico da literatura', () {
      expect(geohashCodificar(42.6, -5.6, precisao: 5), 'ezs42');
      expect(geohashCodificar(42.6, -5.6, precisao: 9), 'ezs42e44y');
    });

    test('rejeita precisao fora de 1..12', () {
      expect(() => geohashCodificar(0, 0, precisao: 0), throwsArgumentError);
      expect(() => geohashCodificar(0, 0, precisao: 13), throwsArgumentError);
    });
  });

  group('geohashCaixa', () {
    test('limites e centro iguais aos do oraculo', () {
      final caixa = geohashCaixa('6gdz0p');
      expect(caixa.latMin, closeTo(-24.0435791015625, 1e-9));
      expect(caixa.latMax, closeTo(-24.0380859375, 1e-9));
      expect(caixa.lngMin, closeTo(-52.3828125, 1e-9));
      expect(caixa.lngMax, closeTo(-52.371826171875, 1e-9));
      expect(caixa.centro.latitude, closeTo(-24.04083251953125, 1e-9));
      expect(caixa.centro.longitude, closeTo(-52.3773193359375, 1e-9));
    });

    test('o centro da celula recodifica para ela mesma', () {
      for (final hash in ['6gdz', '6gdz0p', '6gdz0ph', 'ezs42']) {
        final centro = geohashCentro(hash);
        expect(
          geohashCodificar(centro.latitude, centro.longitude,
              precisao: hash.length),
          hash,
        );
      }
    });

    test('celula encolhe conforme a precisao aumenta', () {
      final p4 = geohashCaixa('6gdz');
      final p5 = geohashCaixa('6gdz0');
      final p6 = geohashCaixa('6gdz0p');
      final p7 = geohashCaixa('6gdz0ph');

      // p4 no Parana: ~19,5 km de altura (celula larga e baixa)
      expect(p4.alturaM, closeTo(19540, 200));
      expect(p5.alturaM, lessThan(p4.alturaM));
      expect(p6.alturaM, lessThan(p5.alturaM));
      expect(p7.alturaM, lessThan(p6.alturaM));
      expect(p7.larguraM, lessThan(p6.larguraM));

      // p6 no Parana: ~611 m de altura e ~1116 m de largura
      expect(p6.alturaM, closeTo(611, 5));
      expect(p6.larguraM, closeTo(1116, 10));
    });

    test('dimensoes seguem o numero de bits de latitude/longitude', () {
      // Comprimento par reparte os bits igualmente; comprimento impar da um bit
      // extra para a longitude (por isso a largura encolhe mais rapido).
      final latCentro = geohashCentro('6gdz0p').latitude;
      const metrosPorGrau = raioTerraM * math.pi / 180;

      for (final hash in ['6gdz', '6gdz0p', '6gdz0ph', '6gdz0ph4f']) {
        final bits = 5 * hash.length;
        final bitsLat = bits ~/ 2;
        final bitsLng = bits - bitsLat;
        final caixa = geohashCaixa(hash);
        final esperadoAltura =
            180 / math.pow(2, bitsLat) * metrosPorGrau;
        final esperadoLargura = 360 /
            math.pow(2, bitsLng) *
            metrosPorGrau *
            math.cos(latCentro * math.pi / 180);

        expect(
          caixa.alturaM,
          closeTo(esperadoAltura, esperadoAltura * 0.01),
          reason: 'altura de $hash',
        );
        expect(
          caixa.larguraM,
          closeTo(esperadoLargura, esperadoLargura * 0.01),
          reason: 'largura de $hash',
        );
      }
    });

    test('rejeita geohash vazio ou com caractere invalido', () {
      expect(() => geohashCaixa(''), throwsArgumentError);
      expect(() => geohashCaixa('6gdz0pa'), throwsArgumentError);
    });
  });

  group('geohashVizinho', () {
    test('bate com o oraculo (varios comprimentos/paridades)', () {
      const esperado = <String, Map<DirecaoVizinho, String>>{
        'ezs42': {
          DirecaoVizinho.norte: 'ezs48',
          DirecaoVizinho.sul: 'ezs40',
          DirecaoVizinho.leste: 'ezs43',
          DirecaoVizinho.oeste: 'ezefr',
        },
        '6gdz': {
          DirecaoVizinho.norte: '6gfb',
          DirecaoVizinho.sul: '6gdy',
          DirecaoVizinho.leste: '6gep',
          DirecaoVizinho.oeste: '6gdx',
        },
        '6gdz0p': {
          DirecaoVizinho.norte: '6gdz20',
          DirecaoVizinho.sul: '6gdz0n',
          DirecaoVizinho.leste: '6gdz0r',
          DirecaoVizinho.oeste: '6gdxpz',
        },
        '6gdz0ph': {
          DirecaoVizinho.norte: '6gdz0pk',
          DirecaoVizinho.sul: '6gdz0nu',
          DirecaoVizinho.leste: '6gdz0pj',
          DirecaoVizinho.oeste: '6gdz0p5',
        },
      };

      esperado.forEach((hash, direcoes) {
        direcoes.forEach((direcao, valorEsperado) {
          expect(
            geohashVizinho(hash, direcao),
            valorEsperado,
            reason: 'vizinho $direcao de $hash',
          );
        });
      });
    });

    test('voltar pela direcao oposta devolve a celula original', () {
      for (final hash in ['6gdz0p', '6gdz0ph', 'ezs42', '6gdz']) {
        expect(
          geohashVizinho(
            geohashVizinho(hash, DirecaoVizinho.norte),
            DirecaoVizinho.sul,
          ),
          hash,
        );
        expect(
          geohashVizinho(
            geohashVizinho(hash, DirecaoVizinho.leste),
            DirecaoVizinho.oeste,
          ),
          hash,
        );
      }
    });

    test('vizinho fica a uma celula de distancia do centro', () {
      final centro = geohashCentro('6gdz0p');
      final norte =
          geohashCentro(geohashVizinho('6gdz0p', DirecaoVizinho.norte));
      final leste =
          geohashCentro(geohashVizinho('6gdz0p', DirecaoVizinho.leste));
      expect(
        geohashCaixa('6gdz0p').alturaM,
        closeTo(distanciaM(centro, norte), 1),
      );
      expect(
        geohashCaixa('6gdz0p').larguraM,
        closeTo(distanciaM(centro, leste), 1),
      );
    });

    test('lanca na borda do mundo', () {
      expect(
        () => geohashVizinho('u', DirecaoVizinho.norte),
        throwsArgumentError,
      );
      expect(
        () => geohashVizinho('b', DirecaoVizinho.norte),
        throwsArgumentError,
      );
      expect(
        () => geohashVizinho('', DirecaoVizinho.norte),
        throwsArgumentError,
      );
    });
  });

  group('geohashVizinhanca', () {
    test('devolve 9 celulas distintas incluindo a central', () {
      final vizinhanca = geohashVizinhanca('6gdz0p');
      expect(vizinhanca.todas, hasLength(9));
      expect(vizinhanca.todas.toSet(), hasLength(9));
      expect(vizinhanca.todas, contains('6gdz0p'));
      expect(vizinhanca.norte, '6gdz20');
      expect(
        vizinhanca.sudoeste,
        geohashVizinho('6gdz0n', DirecaoVizinho.oeste),
      );
    });
  });

  group('geohashCobertura', () {
    test('cobre todos os pontos dentro do raio de 800 m', () {
      const raio = 800.0;
      final celulas = geohashCobertura(centroCampoMourao, raio, precisao: 6);
      expect(celulas, isNotEmpty);

      for (var rumo = 0; rumo < 360; rumo += 10) {
        for (var dist = 0.0; dist <= raio; dist += 50) {
          final ponto = deslocarM(centroCampoMourao, dist, rumo.toDouble());
          final hash =
              geohashCodificar(ponto.latitude, ponto.longitude, precisao: 6);
          expect(
            celulas,
            contains(hash),
            reason: 'ponto a ${dist.toInt()}m no rumo $rumo caiu em $hash',
          );
        }
      }
    });

    test('raio pequeno nao sai da celula do ponto', () {
      // 50 m cabe com folga dentro de uma celula p6 (~611 m x 1116 m):
      // a cobertura deve ser minima, nao a vizinhanca 3x3 inteira.
      final celulas = geohashCobertura(centroCampoMourao, 50, precisao: 6);
      expect(celulas, contains('6gdz0p'));
      expect(celulas, hasLength(1));
    });

    test('raio que cruza a borda inclui a celula vizinha', () {
      // ponto perto da borda sul da celula (~55 m) + raio de 300 m
      final celulas = geohashCobertura(centroCampoMourao, 300, precisao: 6);
      expect(celulas, contains('6gdz0p'));
      expect(celulas, contains('6gdz0n'));
      expect(celulas.length, greaterThan(1));
      expect(celulas.length, lessThanOrEqualTo(25));
    });

    test('aborta quando a consulta ficaria grande demais', () {
      expect(
        () => geohashCobertura(centroCampoMourao, 20000, precisao: 6),
        throwsArgumentError,
      );
    });

    test('rejeita raio negativo', () {
      expect(
        () => geohashCobertura(centroCampoMourao, -1),
        throwsArgumentError,
      );
    });
  });
}
