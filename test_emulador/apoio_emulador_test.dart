/// Testes do apoio dos testes do emulador: o que da para conferir sem emulador.
///
/// Roda em qualquer maquina (`flutter test test_emulador/apoio_emulador_test.dart`).
/// E aqui que o formato das escritas fica preso: o `criadoEm` do servidor vira
/// uma transformacao no mesmo write, e nao um campo com horario do aparelho.
library;

import 'package:achar_vagas_app/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/emulador_firestore.dart';

void main() {
  group('enderecoEmulador', () {
    test('sem a variavel usa o host e a porta padrao do repo', () {
      expect(
        enderecoEmulador(null, portaEmuladorFirestore),
        Uri.parse('http://$hostEmuladorPadrao:$portaEmuladorFirestore'),
      );
      expect(
        enderecoEmulador('   ', portaEmuladorAuth),
        Uri.parse('http://$hostEmuladorPadrao:$portaEmuladorAuth'),
      );
    });

    test('le o host:porta que o emulators:exec exporta', () {
      expect(
        enderecoEmulador('127.0.0.1:8080', portaEmuladorFirestore),
        Uri.parse('http://127.0.0.1:8080'),
      );
      expect(
        enderecoEmulador('127.0.0.1:9099', portaEmuladorAuth),
        Uri.parse('http://127.0.0.1:9099'),
      );
    });

    test('aceita host do docker (firebase) e endereco com esquema', () {
      expect(
        enderecoEmulador('firebase:8080', portaEmuladorFirestore),
        Uri.parse('http://firebase:8080'),
      );
      expect(
        enderecoEmulador('http://localhost:8080', portaEmuladorFirestore),
        Uri.parse('http://localhost:8080'),
      );
    });
  });

  group('EmuladorFirestore.doAmbiente', () {
    test('usa as variaveis do firebase quando existem', () {
      final EmuladorFirestore emulador = EmuladorFirestore.doAmbiente(
        ambiente: <String, String>{
          'FIRESTORE_EMULATOR_HOST': '127.0.0.1:8080',
          'FIREBASE_AUTH_EMULATOR_HOST': '127.0.0.1:9099',
        },
      );

      expect(emulador.firestore, Uri.parse('http://127.0.0.1:8080'));
      expect(emulador.auth, Uri.parse('http://127.0.0.1:9099'));
      expect(emulador.projeto, projetoEmulador);
    });

    test('sem as variaveis cai nas portas do docker-compose', () {
      final EmuladorFirestore emulador =
          EmuladorFirestore.doAmbiente(ambiente: <String, String>{});

      expect(
        emulador.firestore,
        Uri.parse('http://$hostEmuladorPadrao:$portaEmuladorFirestore'),
      );
      expect(
        emulador.auth,
        Uri.parse('http://$hostEmuladorPadrao:$portaEmuladorAuth'),
      );
    });
  });

  group('valoresFirestore', () {
    test('traduz cada tipo para o campo do proto', () {
      final Map<String, dynamic> campos = valoresFirestore(<String, Object?>{
        'uid': 'ana',
        'tipo': 'vaga',
        'precisaoM': 8,
        'confiavel': true,
        'expiraEm': DateTime.utc(2026, 9, 28, 12, 30, 15, 123),
        'geopoint': const PontoGeo(-24.05, -52.37),
        'geo': <String, Object?>{'geohash': '6gdz0ph'},
        'lista': <Object?>[1, 'a'],
      });

      expect(campos['uid'], <String, dynamic>{'stringValue': 'ana'});
      expect(campos['tipo'], <String, dynamic>{'stringValue': 'vaga'});
      expect(campos['precisaoM'], <String, dynamic>{'integerValue': '8'});
      expect(campos['confiavel'], <String, dynamic>{'booleanValue': true});
      expect(
        campos['expiraEm'],
        <String, dynamic>{'timestampValue': '2026-09-28T12:30:15.123Z'},
      );
      expect(
        campos['geopoint'],
        <String, dynamic>{
          'geoPointValue': <String, dynamic>{
            'latitude': -24.05,
            'longitude': -52.37,
          },
        },
      );
      expect(
        campos['geo'],
        <String, dynamic>{
          'mapValue': <String, dynamic>{
            'fields': <String, dynamic>{
              'geohash': <String, dynamic>{'stringValue': '6gdz0ph'},
            },
          },
        },
      );
      expect(
        campos['lista'],
        <String, dynamic>{
          'arrayValue': <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{'integerValue': '1'},
              <String, dynamic>{'stringValue': 'a'},
            ],
          },
        },
      );
    });

    test('campo ausente no mapa nao vai para a gravacao', () {
      final Map<String, dynamic> campos =
          valoresFirestore(<String, Object?>{'uid': 'ana'});

      expect(campos.keys, <String>['uid']);
    });
  });

  group('escritaDeRelato', () {
    test('manda o criadoEm como transformacao do servidor', () {
      final Map<String, dynamic> escrita = escritaDeRelato(
        'regras-1',
        <String, Object?>{'uid': 'ana'},
      );

      expect(
        (escrita['update'] as Map<String, dynamic>)['name'],
        nomeDocumento('relatos', 'regras-1', projeto: projetoEmulador),
      );
      expect(
        escrita['updateTransforms'],
        <Map<String, String>>[
          <String, String>{
            'fieldPath': 'criadoEm',
            'setToServerValue': 'REQUEST_TIME',
          },
        ],
      );
    });

    test('sem a transformacao o criadoEm sai do proprio write', () {
      final Map<String, dynamic> escrita = escritaDeRelato(
        'regras-2',
        <String, Object?>{
          'uid': 'ana',
          'criadoEm': DateTime.utc(2026, 9, 28, 12),
        },
        criadoEmDoServidor: false,
        projeto: 'demo-achar-vagas',
      );

      expect(escrita.containsKey('updateTransforms'), isFalse);
      final Map<String, dynamic> campos =
          (escrita['update'] as Map<String, dynamic>)['fields']
              as Map<String, dynamic>;
      expect(
        campos['criadoEm'],
        <String, dynamic>{'timestampValue': '2026-09-28T12:00:00.000Z'},
      );
    });
  });
}
