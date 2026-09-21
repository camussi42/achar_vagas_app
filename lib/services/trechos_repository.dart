/// Acesso aos trechos de rua canonicos (base global importada para o Firestore
/// pela pipeline em `tools/pipeline`).
///
/// O app **nunca** escreve em `trechos`: a colecao e populada pela pipeline
/// (Admin SDK) e as regras do Firestore bloqueiam escrita de cliente. Assim a
/// geometria e o nome de rua nao podem ser forjados por um usuario.
library;

import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:achar_vagas_app/models/trecho.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

abstract class TrechosRepository {
  /// Trechos cujo geohash de consulta esta na cobertura de [centro].
  Future<List<Trecho>> candidatosProximos(
    LatLng centro, {
    double raioM,
    int limite,
  });
}

/// Consulta por `whereIn` nos geohashes de [precisaoGeohashConsulta].
///
/// E o padrao GeoFire: uma igualdade por celula em vez de consulta espacial.
class TrechosFirestore implements TrechosRepository {
  TrechosFirestore({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String colecao = 'trechos';

  final FirebaseFirestore _firestore;

  @override
  Future<List<Trecho>> candidatosProximos(
    LatLng centro, {
    double raioM = 150,
    int limite = 40,
  }) async {
    final celulas = geohashCobertura(
      centro,
      raioM,
      precisao: precisaoGeohashConsulta,
    );
    final snapshot = await _firestore
        .collection(colecao)
        .where('geohash', whereIn: celulas)
        .limit(limite)
        .get();

    return snapshot.docs
        .map((doc) => _trechoDeFirestore(doc.id, doc.data()))
        .toList(growable: false);
  }
}

/// Versao em memoria: usada quando o Firebase nao esta configurado
/// (`flutter run` sem `flutterfire configure`) e nos testes.
class TrechosMemoria implements TrechosRepository {
  TrechosMemoria([Iterable<Trecho> semente = const <Trecho>[]]) {
    for (final trecho in semente) {
      salvar(trecho);
    }
  }

  final List<Trecho> _trechos = <Trecho>[];

  /// Todos os trechos cadastrados (introspecao para testes/dev).
  List<Trecho> get todos => List.unmodifiable(_trechos);

  void salvar(Trecho trecho) {
    _trechos.removeWhere((t) => t.id == trecho.id);
    _trechos.add(trecho);
  }

  @override
  Future<List<Trecho>> candidatosProximos(
    LatLng centro, {
    double raioM = 150,
    int limite = 40,
  }) async {
    final celulas = geohashCobertura(
      centro,
      raioM,
      precisao: precisaoGeohashConsulta,
    ).toSet();
    final encontrados = _trechos
        .where((trecho) => celulas.contains(trecho.geohash))
        .toList()
      ..sort((a, b) => a.distanciaDe(centro).compareTo(b.distanciaDe(centro)));
    return encontrados.take(limite).toList(growable: false);
  }
}

Trecho _trechoDeFirestore(String id, Map<String, dynamic> dados) {
  final centroide = dados['centroide'] as GeoPoint;
  final geometria = <LatLng>[
    for (final vertice in (dados['geometria'] as List<dynamic>? ?? const []))
      if (vertice is GeoPoint)
        LatLng(vertice.latitude, vertice.longitude)
      else
        LatLng(
          ((vertice as List<dynamic>)[0] as num).toDouble(),
          (vertice[1] as num).toDouble(),
        ),
  ];
  final atualizadoEm = dados['atualizadoEm'];

  return Trecho(
    id: TrechoId.parse(id),
    via: dados['via'] as String?,
    classe: dados['classe'] as String?,
    municipio: dados['municipio'] as String?,
    uf: dados['uf'] as String?,
    geometria: geometria,
    centroide: LatLng(centroide.latitude, centroide.longitude),
    geohash: dados['geohashConsulta'] as String,
    release: dados['release'] as String?,
    atualizadoEm: atualizadoEm is Timestamp ? atualizadoEm.toDate() : null,
  );
}
