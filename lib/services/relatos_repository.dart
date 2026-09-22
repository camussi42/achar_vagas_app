/// Acesso aos relatos (a parte "tempo real" do app).
///
/// Consulta por proximidade sem PostGIS: os documentos carregam o geohash de
/// precisao 6 e a query usa `whereIn` com as celulas que cobrem o raio
/// (`geohashCobertura`). O filtro exato de distancia e a ordenacao por horario
/// acontecem no cliente — ver `docs/adr/0001-identidade-de-trecho.md`.
library;

import 'dart:async';

import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/geo_utils.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/relato.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Valores usados por padrao nas consultas de proximidade.
const double raioConsultaPadraoM = 1200;
const int limiteConsultaPadrao = 300;

abstract class RelatosRepository {
  /// Grava um novo relato e devolve o registro com `id`.
  Future<Relato> criar(Relato relato);

  Future<List<Relato>> buscarProximos(
    LatLng centro, {
    double raioM,
    int limite,
  });

  Stream<List<Relato>> observarProximos(
    LatLng centro, {
    double raioM,
    int limite,
  });
}

/// Implementacao no Firestore.
class RelatosFirestore implements RelatosRepository {
  RelatosFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String colecao = 'relatos';

  final FirebaseFirestore _firestore;

  @override
  Future<Relato> criar(Relato relato) async {
    final referencia =
        await _firestore.collection(colecao).add(<String, dynamic>{
      'uid': relato.uid,
      'trechoId': relato.trechoId.valor,
      'tipo': relato.tipo.valor,
      'geo': <String, dynamic>{
        'geopoint': GeoPoint(relato.ponto.latitude, relato.ponto.longitude),
        'geohash': relato.geohash,
        'geohashConsulta': relato.geohashConsulta,
      },
      'precisaoM': relato.precisaoM,
      // Resolvido no servidor: as regras exigem criadoEm == request.time.
      'criadoEm': FieldValue.serverTimestamp(),
    });
    return Relato(
      id: referencia.id,
      uid: relato.uid,
      trechoId: relato.trechoId,
      tipo: relato.tipo,
      ponto: relato.ponto,
      geohash: relato.geohash,
      geohashConsulta: relato.geohashConsulta,
      precisaoM: relato.precisaoM,
      criadoEm: relato.criadoEm,
    );
  }

  @override
  Future<List<Relato>> buscarProximos(
    LatLng centro, {
    double raioM = raioConsultaPadraoM,
    int limite = limiteConsultaPadrao,
  }) async {
    final snapshot = await _consulta(centro, raioM, limite).get();
    return _filtrar(
      snapshot.docs.map((doc) => _relatoDeFirestore(doc.id, doc.data())),
      centro,
      raioM,
    );
  }

  @override
  Stream<List<Relato>> observarProximos(
    LatLng centro, {
    double raioM = raioConsultaPadraoM,
    int limite = limiteConsultaPadrao,
  }) =>
      _consulta(centro, raioM, limite).snapshots().map(
            (snapshot) => _filtrar(
              snapshot.docs
                  .map((doc) => _relatoDeFirestore(doc.id, doc.data())),
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
      precisao: precisaoGeohashConsulta,
    );
    return _firestore
        .collection(colecao)
        .where('geo.geohashConsulta', whereIn: celulas)
        .limit(limite);
  }
}

/// Versao em memoria: usada quando o Firebase nao esta configurado e nos testes.
class RelatosMemoria implements RelatosRepository {
  final List<Relato> _relatos = <Relato>[];
  final StreamController<void> _mudancas = StreamController<void>.broadcast();
  int _proximoId = 1;

  /// Relatos cadastrados (introspecao para testes/dev).
  List<Relato> get todos => List.unmodifiable(_relatos);

  void limpar() {
    _relatos.clear();
    _mudancas.add(null);
  }

  @override
  Future<Relato> criar(Relato relato) async {
    final salvo = Relato(
      id: relato.id ?? 'mem_${_proximoId++}',
      uid: relato.uid,
      trechoId: relato.trechoId,
      tipo: relato.tipo,
      ponto: relato.ponto,
      geohash: relato.geohash,
      geohashConsulta: relato.geohashConsulta,
      precisaoM: relato.precisaoM,
      criadoEm: relato.criadoEm,
    );
    _relatos.add(salvo);
    _mudancas.add(null);
    return salvo;
  }

  @override
  Future<List<Relato>> buscarProximos(
    LatLng centro, {
    double raioM = raioConsultaPadraoM,
    int limite = limiteConsultaPadrao,
  }) async =>
      _proximos(centro, raioM, limite);

  @override
  Stream<List<Relato>> observarProximos(
    LatLng centro, {
    double raioM = raioConsultaPadraoM,
    int limite = limiteConsultaPadrao,
  }) async* {
    yield _proximos(centro, raioM, limite);
    yield* _mudancas.stream.map((_) => _proximos(centro, raioM, limite));
  }

  List<Relato> _proximos(LatLng centro, double raioM, int limite) {
    final encontrados = _relatos
        .where((relato) => distanciaM(relato.ponto, centro) <= raioM)
        .toList()
      ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return encontrados.take(limite).toList(growable: false);
  }

  /// Libera o controlador de eventos (uso em testes).
  Future<void> descartar() => _mudancas.close();
}

List<Relato> _filtrar(Iterable<Relato> relatos, LatLng centro, double raioM) {
  final encontrados = relatos
      .where((relato) => distanciaM(relato.ponto, centro) <= raioM)
      .toList()
    ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
  return encontrados;
}

Relato _relatoDeFirestore(String id, Map<String, dynamic> dados) {
  final geo = dados['geo'] as Map<String, dynamic>;
  final ponto = geo['geopoint'] as GeoPoint;
  final criadoEm = dados['criadoEm'];

  return Relato(
    id: id,
    uid: dados['uid'] as String,
    trechoId: TrechoId.parse(dados['trechoId'] as String),
    tipo: TipoRelatoTexto.tentarParse(dados['tipo'] as String?) ??
        TipoRelato.vaga,
    ponto: LatLng(ponto.latitude, ponto.longitude),
    geohash: geo['geohash'] as String,
    geohashConsulta: geo['geohashConsulta'] as String,
    precisaoM: (dados['precisaoM'] as num?)?.toDouble(),
    criadoEm: criadoEm is Timestamp ? criadoEm.toDate() : DateTime.now().toUtc(),
  );
}
