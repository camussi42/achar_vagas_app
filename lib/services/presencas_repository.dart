/// Acesso às presenças de usuários no mapa em tempo real (issue #50).
///
/// Consulta por proximidade reaproveitando a mesma estratégia de geohash
/// usada pelos relatos (`geohashCobertura`).
library;

import 'dart:async';

import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/geo_utils.dart';
import 'package:achar_vagas_app/models/presenca.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Raio (m) da consulta de presenças próximas.
const double raioPresencaPadraoM = 1500;

/// TTL de uma presença no servidor: após esse período sem atualização,
/// o usuário some do mapa.
const Duration ttlPresencaPadrao = Duration(minutes: 10);

/// Intervalo mínimo entre atualizações de posição (throttle).
const Duration throttttePresencaMinimo = Duration(seconds: 30);

/// Distância mínima (m) que o usuário precisa andar para valer uma nova gravação.
const double passoAtualizacaoPresencaM = 200;

abstract class PresencasRepository {
  /// Grava/atualiza a presença do próprio usuário.
  Future<void> atualizar(Presenca presenca);

  /// Remove a presença do próprio usuário (ao fechar/descartar a tela).
  Future<void> remover(String uid);

  /// Lê presenças próximas de [centro].
  Future<List<Presenca>> buscarProximas(
    LatLng centro, {
    double raioM,
    int limite,
  });

  /// Observa presenças próximas de [centro] em tempo real.
  Stream<List<Presenca>> observarProximas(
    LatLng centro, {
    double raioM,
    int limite,
  });
}

/// Implementação no Firestore.
class PresencasFirestore implements PresencasRepository {
  PresencasFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String colecao = 'presenca';

  final FirebaseFirestore _firestore;

  /// Última posição gravada (para throttle).
  LatLng? _ultimaPosicao;
  /// Último horário de gravação (para throttle).
  DateTime? _ultimaGravacao;

  @override
  Future<void> atualizar(Presenca presenca) async {
    // Throttle: só grava se andar passoAtualizacaoPresencaM ou passou
    // throttttePresencaMinimo desde a última gravação.
    final agora = DateTime.now().toUtc();
    if (_ultimaPosicao != null && _ultimaGravacao != null) {
      final moveu =
          distanciaM(presenca.ponto, _ultimaPosicao!) >=
          passoAtualizacaoPresencaM;
      final passouTempo =
          agora.difference(_ultimaGravacao!) >= throttttePresencaMinimo;
      if (!moveu && !passouTempo) return;
    }
    _ultimaPosicao = presenca.ponto;
    _ultimaGravacao = agora;

    await _firestore.collection(colecao).doc(presenca.uid).set(
      presenca.toMap(),
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> remover(String uid) async {
    await _firestore.collection(colecao).doc(uid).delete();
    _ultimaPosicao = null;
    _ultimaGravacao = null;
  }

  @override
  Future<List<Presenca>> buscarProximas(
    LatLng centro, {
    double raioM = raioPresencaPadraoM,
    int limite = 100,
  }) async {
    final snapshot = await _consulta(centro, raioM, limite).get();
    return _filtrar(
      snapshot.docs.map((doc) => Presenca.fromMap(doc.id, doc.data())),
      centro,
      raioM,
    );
  }

  @override
  Stream<List<Presenca>> observarProximas(
    LatLng centro, {
    double raioM = raioPresencaPadraoM,
    int limite = 100,
  }) =>
      _consulta(centro, raioM, limite).snapshots().map(
            (snapshot) => _filtrar(
              snapshot.docs.map((doc) => Presenca.fromMap(doc.id, doc.data())),
              centro,
              raioM,
            ),
          );

  Query<Map<String, dynamic>> _consulta(
    LatLng centro,
    double raioM,
    int limite,
  ) {
    final celulas = geohashCobertura(
      centro,
      raioM,
      precisao: precisaoGeohashPresenca,
    );
    return _firestore
        .collection(colecao)
        .where('geo.geohashConsulta', whereIn: celulas)
        .limit(limite);
  }
}

/// Versão em memória: usada no modo demonstração e nos testes.
class PresencasMemoria implements PresencasRepository {
  final Map<String, Presenca> _presencas = <String, Presenca>{};
  final StreamController<void> _mudancas = StreamController<void>.broadcast();

  @override
  Future<void> atualizar(Presenca presenca) async {
    _presencas[presenca.uid] = presenca;
    _mudancas.add(null);
  }

  @override
  Future<void> remover(String uid) async {
    _presencas.remove(uid);
    _mudancas.add(null);
  }

  @override
  Future<List<Presenca>> buscarProximas(
    LatLng centro, {
    double raioM = raioPresencaPadraoM,
    int limite = 100,
  }) async =>
      _proximas(centro, raioM, limite);

  @override
  Stream<List<Presenca>> observarProximas(
    LatLng centro, {
    double raioM = raioPresencaPadraoM,
    int limite = 100,
  }) async* {
    yield _proximas(centro, raioM, limite);
    yield* _mudancas.stream.map((_) => _proximas(centro, raioM, limite));
  }

  List<Presenca> _proximas(LatLng centro, double raioM, int limite) {
    final encontrados = _presencas.values
        .where((p) => distanciaM(p.ponto, centro) <= raioM)
        .toList()
      ..sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
    return encontrados.take(limite).toList(growable: false);
  }

  /// Todas as presenças cadastradas (introspecão para testes/dev).
  List<Presenca> get todas => List.unmodifiable(_presencas.values);

  /// Libera o controlador de eventos (uso em testes).
  Future<void> descartar() => _mudancas.close();
}

List<Presenca> _filtrar(
  Iterable<Presenca> presencas,
  LatLng centro,
  double raioM,
) {
  final encontrados = presencas
      .where((p) => distanciaM(p.ponto, centro) <= raioM)
      .toList()
    ..sort((a, b) => b.atualizadoEm.compareTo(a.atualizadoEm));
  return encontrados;
}