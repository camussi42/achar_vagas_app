/// Cliente minimo dos emuladores do firestore e do auth para os testes das
/// regras (issue #39).
///
/// Por que REST, e nao o SDK: `flutter test` roda na VM do Dart, onde os plugins
/// do firebase nao tem canal de plataforma, e o que precisamos exercitar e o
/// *rules engine* do emulador — quem decide se a gravacao passa sao as
/// `firestore.rules`. As duas chamadas usadas aqui sao as mesmas que o SDK faz
/// por baixo: `accounts:signUp` (login anonimo) e `:commit` (gravacao).
library;

import 'dart:convert';
import 'dart:io';

import 'package:achar_vagas_app/bootstrap.dart';

/// Ponto no formato do `geo.geopoint` (latlng do firestore).
class PontoGeo {
  const PontoGeo(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Traduz valores Dart para os campos do documento na API REST do Firestore.
///
/// E aqui que os testes falam a mesma lingua do app: `String`, `double`, `bool`,
/// `Map`, `List`, `DateTime` (timestamp) e [PontoGeo] (geopoint) viram os
/// `*Value` do proto. Campo ausente no mapa nao vai para a gravacao — e assim
/// que os testes cobrem o que a regra exigir e o cliente (nao) mandou.
Map<String, dynamic> valoresFirestore(Map<String, Object?> campos) =>
    <String, dynamic>{
      for (final MapEntry<String, Object?> campo in campos.entries)
        campo.key: _valorFirestore(campo.value),
    };

dynamic _valorFirestore(Object? valor) => switch (valor) {
      null => <String, dynamic>{'nullValue': 'NULL_VALUE'},
      String valor => <String, dynamic>{'stringValue': valor},
      bool valor => <String, dynamic>{'booleanValue': valor},
      int valor => <String, dynamic>{'integerValue': '$valor'},
      double valor => <String, dynamic>{'doubleValue': valor},
      DateTime valor => <String, dynamic>{
          'timestampValue': valor.toUtc().toIso8601String(),
        },
      PontoGeo valor => <String, dynamic>{
          'geoPointValue': <String, dynamic>{
            'latitude': valor.latitude,
            'longitude': valor.longitude,
          },
        },
      Map<Object?, Object?> valor => <String, dynamic>{
          'mapValue': <String, dynamic>{
            'fields': valoresFirestore(valor.cast<String, Object?>()),
          },
        },
      List<Object?> valor => <String, dynamic>{
          'arrayValue': <String, dynamic>{
            'values': <dynamic>[for (final Object? item in valor) _valorFirestore(item)],
          },
        },
      _ => throw ArgumentError('valor sem representacao no firestore: $valor'),
    };

/// Caminho completo de um documento no emulador (e no firestore real: e o mesmo
/// `projects/<projeto>/databases/(default)/documents/<colecao>/<id>`).
String nomeDocumento(String colecao, String id, {String projeto = projetoEmulador}) =>
    'projects/$projeto/databases/(default)/documents/$colecao/$id';

/// Escrita de um relato no formato que o SDK manda.
///
/// O `FieldValue.serverTimestamp()` vira uma *transformacao* no mesmo write
/// (`updateTransforms` com `setToServerValue: REQUEST_TIME`) — a API recusa
/// `transform` junto de `update`, e e essa transformacao que faz
/// `request.resource.data.criadoEm` chegar no rules engine como `request.time`.
/// Com [criadoEmDoServidor] `false` o `criadoEm` sai do relogio do cliente, que
/// e o caso que a regra precisa recusar.
Map<String, dynamic> escritaDeRelato(
  String id,
  Map<String, Object?> campos, {
  bool criadoEmDoServidor = true,
  String projeto = projetoEmulador,
}) {
  final Map<String, dynamic> escrita = <String, dynamic>{
    'update': <String, dynamic>{
      'name': nomeDocumento('relatos', id, projeto: projeto),
      'fields': valoresFirestore(campos),
    },
  };
  if (criadoEmDoServidor) {
    escrita['updateTransforms'] = <Map<String, String>>[
      <String, String>{'fieldPath': 'criadoEm', 'setToServerValue': 'REQUEST_TIME'},
    ];
  }
  return escrita;
}

/// Resposta crua do emulador, com o status do `google.rpc.Status` quando falha.
class RespostaEmulador {
  const RespostaEmulador(this.status, this.corpo);

  final int status;
  final Map<String, dynamic> corpo;

  /// O emulador responde 2xx quando as regras deixaram passar.
  bool get ok => status >= 200 && status < 300;

  /// `PERMISSION_DENIED` (403) e o que as regras devolvem ao negar.
  bool get negadoPelasRegras =>
      status == 403 && statusErro == 'PERMISSION_DENIED';

  /// Status do erro (`PERMISSION_DENIED`, `INVALID_ARGUMENT`, ...).
  String? get statusErro {
    final Object? erro = corpo['error'];
    return erro is Map ? erro['status'] as String? : null;
  }

  /// Mensagem do erro, para o `reason` das assercoes.
  String get detalhe {
    final Object? erro = corpo['error'];
    if (erro is! Map) return 'HTTP $status';
    return 'HTTP $status ${erro['status']}: ${erro['message']}';
  }

  /// Campo `criadoEm` gravado (microssegundos do servidor), quando veio.
  DateTime? get criadoEm {
    final Object? campos = (corpo['writeResults'] as List<dynamic>?)?.first;
    if (campos is! Map) return null;
    final List<dynamic>? transformadas =
        (campos['transformResults'] as List<dynamic>?);
    final Object? primeira = transformadas?.first;
    if (primeira is! Map) return null;
    final Object? valor = primeira['timestampValue'];
    return valor is String ? DateTime.parse(valor) : null;
  }
}

/// Usuario anonimo do emulador do auth: o `uid` e o token que o firestore le
/// como `request.auth`.
class UsuarioEmulador {
  const UsuarioEmulador({required this.uid, required this.token});

  final String uid;
  final String token;
}

/// Endereco de um emulador a partir do que o ambiente informa.
///
/// `firebase emulators:exec` exporta `FIRESTORE_EMULATOR_HOST` e
/// `FIREBASE_AUTH_EMULATOR_HOST` no formato `host:porta` (o mesmo que o
/// `tools/pipeline/semear_firestore.py` le). Sem a variavel vale o padrao do
/// repositorio (`localhost` + as portas do `firebase.json`), que e o caso de
/// quem sobe o emulador pelo docker-compose e roda a suite na maquina.
Uri enderecoEmulador(String? valor, int portaPadrao) {
  final String texto = (valor ?? '').trim();
  if (texto.isEmpty) return Uri.parse('http://$hostEmuladorPadrao:$portaPadrao');
  if (texto.startsWith('http://') || texto.startsWith('https://')) {
    return Uri.parse(texto);
  }
  return Uri.parse('http://$texto');
}

/// Cliente dos emuladores do firestore e do auth.
class EmuladorFirestore {
  EmuladorFirestore({
    Uri? firestore,
    Uri? auth,
    this.projeto = projetoEmulador,
    this.tempoLimite = const Duration(seconds: 20),
  })  : firestore =
            firestore ?? Uri.parse('http://$hostEmuladorPadrao:$portaEmuladorFirestore'),
        auth = auth ?? Uri.parse('http://$hostEmuladorPadrao:$portaEmuladorAuth');

  /// Le o ambiente: e o caminho do `firebase emulators:exec`.
  factory EmuladorFirestore.doAmbiente({Map<String, String>? ambiente}) {
    final Map<String, String> lido = ambiente ?? Platform.environment;
    return EmuladorFirestore(
      firestore: enderecoEmulador(
        lido['FIRESTORE_EMULATOR_HOST'],
        portaEmuladorFirestore,
      ),
      auth: enderecoEmulador(
        lido['FIREBASE_AUTH_EMULATOR_HOST'],
        portaEmuladorAuth,
      ),
    );
  }

  /// Token que o emulador trata como acesso total (o mesmo caminho do Admin SDK,
  /// que e quem grava a semente de `trechos`).
  static const String tokenAdmin = 'owner';

  /// Chave de fachada: o emulador do auth nao valida a chave da API.
  static const String _chaveFachada = 'emulador-local-sem-chave';

  final Uri firestore;
  final Uri auth;
  final String projeto;
  final Duration tempoLimite;
  final HttpClient _http = HttpClient();

  /// Fecha as conexoes (chamar no `tearDownAll`).
  void fechar() => _http.close(force: true);

  /// Falha com a instrucao de como subir o emulador quando ele nao esta de pe.
  Future<void> exigirNoAr() async {
    for (final MapEntry<String, Uri> entrada
        in <String, Uri>{'firestore': firestore, 'auth': auth}.entries) {
      try {
        await _enviar('GET', entrada.value);
      } on Object catch (erro) {
        throw StateError(
          'o emulador do ${entrada.key} nao respondeu em ${entrada.value} ($erro).\n'
          'suba com: docker-compose up -d firebase\n'
          'ou rode a suite junto do emulador: firebase emulators:exec '
          '--only firestore,auth "flutter test test_emulador"',
        );
      }
    }
  }

  /// Login anonimo (o mesmo caminho de `signInAnonymously`).
  Future<UsuarioEmulador> entrarAnonimo() async {
    final RespostaEmulador resposta = await _enviar(
      'POST',
      auth.replace(
        path: '/identitytoolkit.googleapis.com/v1/accounts:signUp',
        query: 'key=$_chaveFachada',
      ),
      corpo: <String, dynamic>{'returnSecureToken': true},
    );
    final Object? token = resposta.corpo['idToken'];
    final Object? uid = resposta.corpo['localId'];
    if (!resposta.ok || token is! String || uid is! String) {
      throw StateError('login anonimo falhou: ${resposta.detalhe}');
    }
    return UsuarioEmulador(uid: uid, token: token);
  }

  /// Grava um relato. Sem [token] a gravacao vai anonima.
  ///
  /// [criadoEmDoServidor] liga a transformacao `REQUEST_TIME` — o formato que o
  /// SDK manda para `FieldValue.serverTimestamp()` (a regra exige
  /// `criadoEm == request.time`). Com `false` o `criadoEm` sai do relogio do
  /// cliente, que e justamente o caso que a regra precisa recusar.
  Future<RespostaEmulador> gravarRelato(
    String id,
    Map<String, Object?> campos, {
    String? token,
    bool criadoEmDoServidor = true,
  }) =>
      commit(<Map<String, dynamic>>[
        escritaDeRelato(
          id,
          campos,
          criadoEmDoServidor: criadoEmDoServidor,
          projeto: projeto,
        ),
      ], token: token);

  /// Grava um documento qualquer da colecao (as regras decidem se pode).
  Future<RespostaEmulador> gravar(
    String colecao,
    String id,
    Map<String, Object?> campos, {
    String? token,
  }) =>
      commit(<Map<String, dynamic>>[
        <String, dynamic>{
          'update': <String, dynamic>{
            'name': _nome(colecao, id),
            'fields': valoresFirestore(campos),
          },
        },
      ], token: token);

  /// Grava ignorando as regras (preparar estado e limpar nos testes).
  Future<RespostaEmulador> gravarComoAdmin(
    String colecao,
    String id,
    Map<String, Object?> campos,
  ) =>
      gravar(colecao, id, campos, token: tokenAdmin);

  /// Le um documento.
  Future<RespostaEmulador> lerDocumento(
    String colecao,
    String id, {
    String? token,
  }) =>
      _enviar('GET', _documentosUri('/$colecao/$id'), token: token);

  /// Altera campos de um documento existente.
  Future<RespostaEmulador> atualizar(
    String colecao,
    String id,
    Map<String, Object?> campos, {
    required List<String> mascara,
    String? token,
  }) =>
      commit(<Map<String, dynamic>>[
        <String, dynamic>{
          'update': <String, dynamic>{
            'name': _nome(colecao, id),
            'fields': valoresFirestore(campos),
          },
          'updateMask': <String, dynamic>{'fieldPaths': mascara},
        },
      ], token: token);

  /// Apaga um documento.
  Future<RespostaEmulador> apagar(String colecao, String id, {String? token}) =>
      commit(<Map<String, dynamic>>[
        <String, dynamic>{'delete': _nome(colecao, id)},
      ], token: token);

  /// Executa escritas em um unico commit (o mesmo endpoint do SDK).
  Future<RespostaEmulador> commit(
    List<Map<String, dynamic>> escritas, {
    String? token,
  }) =>
      _enviar(
        'POST',
        _documentosUri(':commit'),
        corpo: <String, dynamic>{'writes': escritas},
        token: token,
      );

  String _nome(String colecao, String id) =>
      nomeDocumento(colecao, id, projeto: projeto);

  Uri _documentosUri([String sufixo = '']) => Uri.parse(
        '${firestore.origin}/v1/projects/$projeto/databases/(default)/documents$sufixo',
      );

  Future<RespostaEmulador> _enviar(
    String metodo,
    Uri destino, {
    Object? corpo,
    String? token,
  }) async {
    final HttpClientRequest requisicao =
        await _http.openUrl(metodo, destino).timeout(tempoLimite);
    requisicao.headers.contentType = ContentType.json;
    if (token != null) {
      requisicao.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (corpo != null) requisicao.write(jsonEncode(corpo));

    final HttpClientResponse resposta =
        await requisicao.close().timeout(tempoLimite);
    final String texto = await resposta.transform(utf8.decoder).join();
    return RespostaEmulador(resposta.statusCode, _corpo(texto));
  }

  /// Corpo JSON da resposta; o `GET /` do emulador responde texto puro ("Ok"),
  /// entao o que nao for JSON vira `bruto` em vez de derrubar o teste.
  static Map<String, dynamic> _corpo(String texto) {
    if (texto.isEmpty) return <String, dynamic>{};
    try {
      final Object? decodificado = jsonDecode(texto);
      return decodificado is Map<String, dynamic>
          ? decodificado
          : <String, dynamic>{'bruto': decodificado};
    } on FormatException {
      return <String, dynamic>{'bruto': texto};
    }
  }
}

