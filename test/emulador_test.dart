/// Testes do modo emulador: a flag do build e o contrato com o que ja existe
/// no repo (`firebase.json`, `docker-compose.yml`, `.firebaserc` e os dois
/// Dockerfiles). Nenhum teste aqui sobe emulador ou toca a rede.
library;

import 'dart:convert';
import 'dart:io';

import 'package:achar_vagas_app/bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('configuracao do emulador', () {
    test('sem dart-define o emulador fica desligado e o host e localhost', () {
      final config = configuracaoEmulador();

      expect(config.ligado, isFalse);
      expect(config.host, hostEmuladorPadrao);
    });

    test('a flag e o host vem do build', () {
      final config = configuracaoEmulador(ligado: true, host: 'firebase');

      expect(config.ligado, isTrue);
      expect(config.host, 'firebase');
    });

    test('host em branco volta para localhost e espaco em volta e ignorado', () {
      expect(configuracaoEmulador(ligado: true, host: '  ').host, hostEmuladorPadrao);
      expect(configuracaoEmulador(ligado: true, host: ' 10.0.2.2 ').host, '10.0.2.2');
    });

    test('as opcoes locais tem chave de fachada e o projeto demo', () {
      expect(opcoesEmuladorLocal.projectId, projetoEmulador);
      expect(opcoesEmuladorLocal.apiKey, isNotEmpty);
    });
  });

  group('contrato do modo emulador com o resto do repo', () {
    late Map<String, dynamic> firebaseJson;
    late String compose;
    late String dockerfileFlutter;
    late String dockerfileFirebase;

    setUpAll(() {
      firebaseJson =
          jsonDecode(File('firebase.json').readAsStringSync()) as Map<String, dynamic>;
      compose = File('docker-compose.yml').readAsStringSync();
      dockerfileFlutter = File('docker/flutter/Dockerfile').readAsStringSync();
      dockerfileFirebase = File('docker/firebase/Dockerfile').readAsStringSync();
    });

    test('as portas casam com o firebase.json', () {
      final emuladores = firebaseJson['emulators'] as Map<String, dynamic>;

      expect((emuladores['auth'] as Map<String, dynamic>)['port'], portaEmuladorAuth);
      expect(
        (emuladores['firestore'] as Map<String, dynamic>)['port'],
        portaEmuladorFirestore,
      );
    });

    test('as portas casam com o docker-compose.yml', () {
      expect(compose, contains('"$portaEmuladorAuth:$portaEmuladorAuth"'));
      expect(compose, contains('"$portaEmuladorFirestore:$portaEmuladorFirestore"'));
    });

    test('o projeto do emulador e o do .firebaserc', () {
      final rc = jsonDecode(File('.firebaserc').readAsStringSync()) as Map<String, dynamic>;
      final projetos = (rc['projects'] as Map<String, dynamic>).values;

      expect(projetos, contains(projetoEmulador));
    });

    test('o container do flutter sobe o app com a flag ligada', () {
      expect(dockerfileFlutter, contains('--dart-define=USAR_EMULADOR=true'));
    });

    test('o container do firebase importa e exporta emulator-data', () {
      expect(dockerfileFirebase, contains('--import=./emulator-data'));
      expect(dockerfileFirebase, contains('--export-on-exit=./emulator-data'));
    });

    test('emulator-data fica fora do git, mas a pasta e versionada', () {
      expect(
        File('.gitignore').readAsStringSync(),
        contains('!/emulator-data/.gitkeep'),
      );
      expect(File('emulator-data/.gitkeep').existsSync(), isTrue);
    });
  });
}
