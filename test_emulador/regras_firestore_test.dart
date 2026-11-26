/// Testes das `firestore.rules` no emulador (issue #39).
///
/// Aqui quem responde e o **rules engine de verdade**: cada caso e uma gravacao
/// ou leitura que passa pelo `:commit`/`GET` do emulador, com um token anonimo
/// do emulador do auth no lugar do `request.auth`.
///
/// Rodar (na maquina, com o emulador do docker-compose de pe):
///
///     docker-compose up -d firebase
///     flutter test test_emulador
///
/// ou tudo junto, sem depender de docker (e o comando do CI):
///
///     firebase emulators:exec --only firestore,auth "flutter test test_emulador"
///
/// Por que fora de `test/`: a suite de `test/` roda em qualquer maquina, sem
/// docker, e uma suite que passa **sem** emulador nao prova nada sobre as
/// regras. Sem emulador no ar os testes daqui falham com a instrucao de como
/// subir (e o `emulators:exec` derruba o job quando o emulador nao sobe).
library;

import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'apoio/emulador_firestore.dart';

/// Ponto no centro de Campo Mourao (o mesmo da tela do mapa).
final LatLng pontoDoMapa = LatLng(-24.0505, -52.3712);

/// O ponto acima no formato do `geo.geopoint` gravado no firestore.
PontoGeo noFormatoGeo(LatLng ponto) => PontoGeo(ponto.latitude, ponto.longitude);

/// Fallback do app quando a rua nao esta na malha importada.
const String geohashDoPonto = '6gdz0ph';

/// GERS de exemplo (uuid do schema v2 do Overture).
const String gersDoExemplo = 'c1d70afe-a7de-4b73-a41c-e92526ab72f9';

void main() {
  final EmuladorFirestore emulador = EmuladorFirestore.doAmbiente();
  final List<String> criados = <String>[];
  int sequencia = 0;

  late UsuarioEmulador ana;
  late UsuarioEmulador bruno;

  /// Id novo por caso: o emulador do compose reaproveita `emulator-data` entre
  /// execucoes e as regras negam update, entao o mesmo id nao pode ser reescrito.
  String proximoId() =>
      'regras-${sequencia++}-${DateTime.now().microsecondsSinceEpoch}';

  /// Documento igual ao que `RelatosFirestore.criar` grava
  /// (`lib/services/relatos_repository.dart`): montado pelo proprio modelo do
  /// app, para o teste nao divergir do que o app manda.
  Map<String, Object?> relatoDoApp({
    required String uid,
    TrechoId? trecho,
    TipoRelato tipo = TipoRelato.vaga,
    DateTime? expiraEm,
  }) {
    final Relato relato = Relato.novo(
      uid: uid,
      trechoId: trecho ?? TrechoId.geohash(geohashDoPonto),
      tipo: tipo,
      ponto: pontoDoMapa,
      precisaoM: 8,
    );
    return <String, Object?>{
      'uid': relato.uid,
      'trechoId': relato.trechoId.valor,
      'tipo': relato.tipo.valor,
      'geo': <String, Object?>{
        'geopoint': noFormatoGeo(pontoDoMapa),
        'geohash': relato.geohash,
        'geohashConsulta': relato.geohashConsulta,
      },
      'precisaoM': relato.precisaoM,
      'expiraEm': expiraEm ?? relato.expiraEm,
    };
  }

  /// Copia do mapa sem um campo (os casos "sem uid", "sem tipo", "sem geo").
  Map<String, Object?> semCampo(Map<String, Object?> campos, String chave) =>
      <String, Object?>{...campos}..remove(chave);

  /// Grava um relato num id novo e registra para a limpeza final.
  Future<RespostaEmulador> criar(
    Map<String, Object?> campos, {
    String? token,
  }) {
    final String id = proximoId();
    criados.add(id);
    return emulador.gravarRelato(id, campos, token: token);
  }

  /// Recusa das regras: 403 `PERMISSION_DENIED`. Exigir o codigo (e nao so
  /// "nao passou") e o que impede um payload errado (400) de se passar por
  /// negativa das regras.
  void esperaNegado(RespostaEmulador resposta, {required String caso}) {
    expect(
      resposta.negadoPelasRegras,
      isTrue,
      reason: '$caso devia ser recusado pelas regras; veio ${resposta.detalhe}',
    );
  }

  void esperaAceito(RespostaEmulador resposta, {required String caso}) {
    expect(
      resposta.ok,
      isTrue,
      reason: '$caso devia passar pelas regras; veio ${resposta.detalhe}',
    );
  }

  setUpAll(() async {
    await emulador.exigirNoAr();
    ana = await emulador.entrarAnonimo();
    bruno = await emulador.entrarAnonimo();
    expect(ana.uid, isNotEmpty);
    expect(bruno.uid, isNot(ana.uid));
  });

  tearDownAll(() async {
    // Limpa o que a suite criou (o emulator-data do compose e reaproveitado).
    for (final String id in criados) {
      await emulador.apagar('relatos', id, token: EmuladorFirestore.tokenAdmin);
    }
    emulador.fechar();
  });

  group('criacao de relato', () {
    test('aceita o relato do app e grava criadoEm pelo servidor', () async {
      final DateTime antes = DateTime.now().toUtc();
      final RespostaEmulador resposta =
          await criar(relatoDoApp(uid: ana.uid), token: ana.token);

      esperaAceito(resposta, caso: 'relato do app (fallback geohash)');
      final DateTime? criadoEm = resposta.criadoEm;
      expect(criadoEm, isNotNull, reason: 'sem criadoEm na resposta');
      expect(
        criadoEm!.difference(antes).abs() < const Duration(minutes: 1),
        isTrue,
        reason: 'criadoEm devia ser o horario do servidor, e veio $criadoEm',
      );
    });

    test('aceita trecho canonico (gers) e lado de quadra (faixa linear)',
        () async {
      esperaAceito(
        await criar(
          relatoDoApp(uid: ana.uid, trecho: TrechoId.overture(gersDoExemplo)),
          token: ana.token,
        ),
        caso: 'trecho canonico gers',
      );
      esperaAceito(
        await criar(
          relatoDoApp(
            uid: ana.uid,
            trecho: TrechoId.overture(gersDoExemplo, inicioLr: 0.5, fimLr: 1),
          ),
          token: ana.token,
        ),
        caso: 'lado de quadra',
      );
    });

    test('aceita expiraEm dentro da tolerancia de um minuto', () async {
      final DateTime agora = DateTime.now().toUtc();
      for (final Duration folga in <Duration>[
        validadeRelatoPadrao - const Duration(seconds: 30),
        validadeRelatoPadrao + const Duration(seconds: 30),
      ]) {
        esperaAceito(
          await criar(
            relatoDoApp(uid: ana.uid, expiraEm: agora.add(folga)),
            token: ana.token,
          ),
          caso: 'expiraEm em $folga',
        );
      }
    });

    test('recusa uid diferente do usuario autenticado', () async {
      esperaNegado(
        await criar(relatoDoApp(uid: bruno.uid), token: ana.token),
        caso: 'relato em nome do bruno gravado pela ana',
      );
      esperaNegado(
        await criar(relatoDoApp(uid: 'uid-inventado'), token: ana.token),
        caso: 'relato com uid inventado',
      );
      esperaNegado(
        await criar(semCampo(relatoDoApp(uid: ana.uid), 'uid'), token: ana.token),
        caso: 'relato sem uid',
      );
    });

    test('sem auth nenhuma gravacao passa', () async {
      final RespostaEmulador resposta = await criar(relatoDoApp(uid: ana.uid));

      expect(
        resposta.ok,
        isFalse,
        reason: 'relato anonimo devia ser recusado; veio ${resposta.detalhe}',
      );
    });

    test('recusa tipo fora de vaga/lotado/saindo', () async {
      esperaNegado(
        await criar(
          <String, Object?>{...relatoDoApp(uid: ana.uid), 'tipo': 'besteira'},
          token: ana.token,
        ),
        caso: 'tipo besteira',
      );
      esperaNegado(
        await criar(semCampo(relatoDoApp(uid: ana.uid), 'tipo'), token: ana.token),
        caso: 'relato sem tipo',
      );
    });

    test('recusa trechoId fora do padrao', () async {
      for (final String invalido in <String>[
        'gers:xpto',
        'gers:$gersDoExemplo@0.5000',
        gersDoExemplo,
        'gh:6gdz0ph4fx',
        ' gh:6gdz0ph',
      ]) {
        esperaNegado(
          await criar(
            <String, Object?>{...relatoDoApp(uid: ana.uid), 'trechoId': invalido},
            token: ana.token,
          ),
          caso: 'trechoId "$invalido"',
        );
      }
      esperaNegado(
        await criar(
          semCampo(relatoDoApp(uid: ana.uid), 'trechoId'),
          token: ana.token,
        ),
        caso: 'relato sem trechoId',
      );
    });

    test('recusa geo que nao e geopoint + geohashes', () async {
      final Map<String, Object?> base = relatoDoApp(uid: ana.uid);
      final Map<String, Object?> geo = base['geo']! as Map<String, Object?>;
      Map<String, Object?> comGeo(Map<String, Object?> novo) =>
          <String, Object?>{...base, 'geo': novo};

      esperaNegado(
        await criar(
          comGeo(<String, Object?>{
            ...geo,
            'geopoint': '-24.0505,-52.3712',
          }),
          token: ana.token,
        ),
        caso: 'geopoint como texto',
      );
      esperaNegado(
        await criar(
          comGeo(<String, Object?>{
            ...geo,
            'geopoint': <double>[-24.0505, -52.3712],
          }),
          token: ana.token,
        ),
        caso: 'geopoint como lista',
      );
      esperaNegado(
        await criar(comGeo(semCampo(geo, 'geopoint')), token: ana.token),
        caso: 'geo sem geopoint',
      );
      esperaNegado(
        await criar(comGeo(semCampo(geo, 'geohash')), token: ana.token),
        caso: 'geo sem geohash',
      );
      esperaNegado(
        await criar(comGeo(semCampo(geo, 'geohashConsulta')), token: ana.token),
        caso: 'geo sem geohashConsulta',
      );
      esperaNegado(
        await criar(semCampo(base, 'geo'), token: ana.token),
        caso: 'relato sem geo',
      );
    });

    test('recusa expiraEm fora da tolerancia (prazo escolhido pelo cliente)',
        () async {
      final DateTime agora = DateTime.now().toUtc();
      for (final Duration fora in <Duration>[
        const Duration(hours: 1), // "nunca expira"
        const Duration(minutes: 2), // morre cedo demais
        const Duration(minutes: -5), // ja vencido
      ]) {
        esperaNegado(
          await criar(
            relatoDoApp(uid: ana.uid, expiraEm: agora.add(fora)),
            token: ana.token,
          ),
          caso: 'expiraEm em $fora',
        );
      }
    });

    test('recusa expiraEm que nao e timestamp', () async {
      final Map<String, Object?> campos = relatoDoApp(uid: ana.uid);
      campos['expiraEm'] = DateTime.now()
          .toUtc()
          .add(validadeRelatoPadrao)
          .toIso8601String();

      esperaNegado(
        await criar(campos, token: ana.token),
        caso: 'expiraEm como texto',
      );
      esperaNegado(
        await criar(semCampo(relatoDoApp(uid: ana.uid), 'expiraEm'),
            token: ana.token),
        caso: 'relato sem expiraEm',
      );
    });

    test('recusa criadoEm que nao vem do servidor', () async {
      // O relogio do aparelho nunca casa com `request.time`: e exatamente isso
      // que a regra usa para exigir o serverTimestamp.
      for (final DateTime relogio in <DateTime>[
        DateTime.now().toUtc(),
        DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ]) {
        esperaNegado(
          await emulador.gravarRelato(
            proximoId(),
            <String, Object?>{...relatoDoApp(uid: ana.uid), 'criadoEm': relogio},
            token: ana.token,
            criadoEmDoServidor: false,
          ),
          caso: 'criadoEm do aparelho ($relogio)',
        );
      }

      final Map<String, Object?> texto = relatoDoApp(uid: ana.uid);
      texto['criadoEm'] = DateTime.now().toUtc().toIso8601String();
      esperaNegado(
        await emulador.gravarRelato(
          proximoId(),
          texto,
          token: ana.token,
          criadoEmDoServidor: false,
        ),
        caso: 'criadoEm como texto',
      );
    });

  });

  group('leitura', () {
    test('ler relato exige login', () async {
      // semente pelo admin: o cliente nao consegue criar sem ser o dono, e o
      // que interessa aqui e so a leitura.
      final String id = proximoId();
      criados.add(id);
      await emulador.gravarComoAdmin('relatos', id, <String, Object?>{
        ...relatoDoApp(uid: ana.uid),
        'criadoEm': DateTime.now().toUtc(),
      });

      esperaNegado(
        await emulador.lerDocumento('relatos', id),
        caso: 'read de relato sem auth',
      );

      final RespostaEmulador comLogin =
          await emulador.lerDocumento('relatos', id, token: ana.token);
      esperaAceito(comLogin, caso: 'read de relato com login');
      expect(textoDeCampo(comLogin.corpo, 'uid'), ana.uid);
      expect(textoDeCampo(comLogin.corpo, 'tipo'), 'vaga');
    });

    test('com login, o relato de outro usuario tambem e legivel', () async {
      final String id = proximoId();
      criados.add(id);
      await emulador.gravarComoAdmin('relatos', id, <String, Object?>{
        ...relatoDoApp(uid: bruno.uid),
        'criadoEm': DateTime.now().toUtc(),
      });

      final RespostaEmulador comLogin =
          await emulador.lerDocumento('relatos', id, token: ana.token);

      // a regra e so `request.auth != null`: o mapa de relatos e colaborativo
      esperaAceito(comLogin, caso: 'read do relato do bruno pela ana');
      expect(textoDeCampo(comLogin.corpo, 'uid'), bruno.uid);
    });
  });

  group('trechos (base viaria)', () {
    test('o cliente le trechos sem login', () async {
      final String id = proximoId();
      await emulador.gravarComoAdmin('trechos', id, <String, Object?>{
        'id': id,
        'nome': 'Rua Teste',
      });

      final RespostaEmulador semLogin =
          await emulador.lerDocumento('trechos', id);
      esperaAceito(semLogin, caso: 'read de trecho sem login');
      expect(textoDeCampo(semLogin.corpo, 'nome'), 'Rua Teste');

      esperaAceito(
        await emulador.lerDocumento('trechos', id, token: ana.token),
        caso: 'read de trecho com login',
      );
    });

    test('o cliente nao grava em trechos (nem logado, nem anonimo)', () async {
      esperaNegado(
        await emulador.gravar(
          'trechos',
          proximoId(),
          <String, Object?>{'id': 'forjado', 'nome': 'Via Forjada'},
          token: ana.token,
        ),
        caso: 'escrita em trechos logado',
      );

      final RespostaEmulador anonima = await emulador.gravar(
        'trechos',
        proximoId(),
        <String, Object?>{'id': 'forjado', 'nome': 'Via Forjada'},
      );
      expect(
        anonima.ok,
        isFalse,
        reason: 'escrita anonima em trechos devia ser recusada; '
            'veio ${anonima.detalhe}',
      );
    });
  });

  group('update e delete', () {
    test('relato do proprio usuario nao aceita update nem delete', () async {
      esperaAceito(
        await criar(relatoDoApp(uid: ana.uid), token: ana.token),
        caso: 'criacao do relato',
      );
      final String id = criados.last;

      esperaNegado(
        await emulador.atualizar(
          'relatos',
          id,
          <String, Object?>{'tipo': 'lotado'},
          mascara: <String>['tipo'],
          token: ana.token,
        ),
        caso: 'update do proprio relato',
      );
      esperaNegado(
        await emulador.apagar('relatos', id, token: ana.token),
        caso: 'delete do proprio relato',
      );

      // e o relato continua intacto (o update nao passou "pela metade")
      final RespostaEmulador depois =
          await emulador.lerDocumento('relatos', id, token: ana.token);
      esperaAceito(depois, caso: 'read depois das tentativas');
      expect(textoDeCampo(depois.corpo, 'tipo'), 'vaga');
    });
  });
}

/// Valor de texto de um campo do documento devolvido pelo emulador.
String? textoDeCampo(Map<String, dynamic> documento, String campo) {
  final Object? campos = documento['fields'];
  if (campos is! Map) return null;
  final Object? valor = campos[campo];
  return valor is Map ? valor['stringValue'] as String? : null;
}

