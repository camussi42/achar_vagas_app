import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato do `trechoId` (issue #14).
///
/// O MESMO texto de regex vive em tres lugares:
///
///   - app      -> `TrechoId.padraoRegex` (lib/geo/trecho_id.dart)
///   - server   -> funcao `trechoIdValido` (firestore.rules)
///   - pipeline -> `PADRAO_TRECHO_ID` (tools/pipeline/trechos.py)
///
/// O teste que le os tres arquivos e compara o texto roda em
/// `tools/pipeline/test_pipeline.py` (`ContratoTrechoIdTest`). Aqui ficam as
/// regras de id do lado do app: o que o cliente pode montar e ler.
void main() {
  const uuid = 'c1d70afe-a7de-4b73-a41c-e92526ab72f9';
  const hexLegado = '08628d5437ffffff0473ffc36df547db';

  group('TrechoId.overture', () {
    test('normaliza o id GERS para minusculas', () {
      final id = TrechoId.overture(uuid.toUpperCase());

      expect(id.valor, 'gers:$uuid');
      expect(id.gersId, uuid);
      expect(id.geohash, isNull);
      expect(id.canonico, isTrue);
      expect(id.dividido, isFalse);
    });

    test('aceita o id hexadecimal legado (schema v1)', () {
      final id = TrechoId.overture(hexLegado);

      expect(id.valor, 'gers:$hexLegado');
      expect(id.gersId, hexLegado);
    });

    test('monta a faixa linear do lado de quadra', () {
      final id = TrechoId.overture(uuid, inicioLr: 0.5, fimLr: 1.0);

      expect(id.valor, 'gers:$uuid@0.5000:1.0000');
      expect(id.dividido, isTrue);
      expect(id.inicioLr, 0.5);
      expect(id.fimLr, 1.0);
    });

    test('arredonda a faixa linear para 4 casas', () {
      final id = TrechoId.overture(uuid, inicioLr: 0.123456, fimLr: 0.987654);

      expect(id.valor, 'gers:$uuid@0.1235:0.9877');
    });

    test('rejeita id inventado', () {
      for (final invalido in ['xpto', '', 'zzzz', 'gers:$uuid']) {
        expect(
          () => TrechoId.overture(invalido),
          throwsFormatException,
          reason: invalido,
        );
      }
    });

    test('rejeita faixa linear incompleta', () {
      expect(() => TrechoId.overture(uuid, inicioLr: 0.5), throwsArgumentError);
      expect(() => TrechoId.overture(uuid, fimLr: 0.5), throwsArgumentError);
    });

    test('rejeita posicao linear fora de 0..1', () {
      for (final ruim in [-0.1, 1.1, double.nan]) {
        expect(
          () => TrechoId.overture(uuid, inicioLr: ruim, fimLr: 1.0),
          throwsArgumentError,
          reason: '$ruim',
        );
      }
    });
  });

  group('TrechoId.geohash', () {
    test('aceita a celula do fallback', () {
      final id = TrechoId.geohash('6gdz0ph');

      expect(id.valor, 'gh:6gdz0ph');
      expect(id.geohash, '6gdz0ph');
      expect(id.gersId, isNull);
      expect(id.canonico, isFalse);
    });

    test('rejeita hash fora de 6..9 caracteres do base32', () {
      for (final invalido in ['ab', '6gdz0', '6gdz0ph4fx', '6gdz0p-']) {
        expect(
          () => TrechoId.geohash(invalido),
          throwsFormatException,
          reason: invalido,
        );
      }
    });

    test('normaliza hash em maiusculas para minusculas', () {
      // Mesma regra do id GERS: o valor gravado e sempre minusculo, porque as
      // regras do Firestore e a pipeline so aceitam minusculas.
      expect(TrechoId.geohash('6GDZ0PH').valor, 'gh:6gdz0ph');
    });

    test('aceita o limite inferior de 6 caracteres', () {
      // p6 e a precisao do indice de consulta (`precisaoGeohashConsulta`), entao
      // o limite inferior do contrato precisa mesmo ser aceito.
      expect(TrechoId.geohash('6gdz0p').valor, 'gh:6gdz0p');
    });
  });

  group('parse', () {
    test('le as duas origens e a faixa linear', () {
      expect(TrechoId.parse('gers:$uuid').gersId, uuid);
      expect(TrechoId.parse('gers:$hexLegado').gersId, hexLegado);

      final quadra = TrechoId.parse('gers:$uuid@0.2500:0.7500');
      expect(quadra.inicioLr, 0.25);
      expect(quadra.fimLr, 0.75);

      final fallback = TrechoId.parse('gh:6gdz0ph');
      expect(fallback.geohash, '6gdz0ph');
      expect(fallback.canonico, isFalse);
    });

    test('faz roundtrip pelo valor canonico', () {
      for (final texto in <String>[
        'gers:$uuid',
        'gers:$uuid@0.5000:1.0000',
        'gers:$hexLegado@0.0000:0.5000',
        'gh:6gdz0ph',
      ]) {
        expect(TrechoId.parse(texto).valor, texto, reason: texto);
      }
    });

    test('tentarParse devolve null em vez de lancar', () {
      for (final ruim in <String?>[
        null,
        '',
        'xpto',
        'gers:xpto',
        'gers:',
        'gers:$uuid@0.5000',
        'gh:ab',
        '6gdz0p',
        'gh:6gdz0ph!',
      ]) {
        expect(TrechoId.tentarParse(ruim), isNull, reason: '$ruim');
      }
    });

    test('parse estrito lanca em id invalido', () {
      expect(() => TrechoId.parse('gers:xpto'), throwsFormatException);
      expect(() => TrechoId.parse(''), throwsFormatException);
    });

    test('dois ids iguais compartilham igualdade e hashCode', () {
      final um = TrechoId.parse('gers:$uuid@0.2500:0.7500');
      final outro = TrechoId.parse('gers:$uuid@0.2500:0.7500');

      expect(um, outro);
      expect(um.hashCode, outro.hashCode);
      expect(um, isNot(TrechoId.parse('gers:$uuid@0.0000:0.2500')));
    });
  });

  group('padraoRegex (contrato com as regras do Firestore)', () {
    test('aceita todo id que o app gera', () {
      final regex = RegExp(TrechoId.padraoRegex);

      for (final texto in <String>[
        'gers:$uuid',
        'gers:$uuid@0.0000:0.5000',
        'gers:$hexLegado@0.5000:1.0000',
        'gh:6gdz0ph',
      ]) {
        expect(regex.hasMatch(texto), isTrue, reason: texto);
      }
    });

    test('rejeita id inventado (ancoras fechadas)', () {
      final regex = RegExp(TrechoId.padraoRegex);

      for (final texto in <String>[
        'gers:xpto',
        'gers:$uuid@0.5000',
        'gers:$uuid ',
        ' gers:$uuid',
        uuid,
        'gh:abc',
        'gh:6gdz0ph4fx',
      ]) {
        expect(regex.hasMatch(texto), isFalse, reason: texto);
      }
    });
  });
}
