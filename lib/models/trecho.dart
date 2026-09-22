/// Trecho de rua (lado de quadra) resolvido para um ponto do mapa.
///
/// O trecho nunca e "inventado" pelo app: ou vem da base canonica (Overture,
/// id GERS) ou e um fallback aproximado por geohash quando ainda nao existe
/// malha conhecida para aquele ponto.
library;

import 'package:achar_vagas_app/geo/geo_utils.dart';
import 'package:achar_vagas_app/geo/geohash.dart';
import 'package:achar_vagas_app/geo/trecho_id.dart';
import 'package:latlong2/latlong.dart';

/// Precisao do geohash que identifica a area de um trecho aproximado (~150 m).
const int precisaoGeohashTrecho = 7;

/// Precisao do geohash usado como indice de consulta no Firestore (~1,2 km x
/// 610 m). Fica gravado em cada documento para permitir `whereIn`.
const int precisaoGeohashConsulta = 6;

class Trecho {
  const Trecho({
    required this.id,
    required this.centroide,
    required this.geohash,
    this.via,
    this.classe,
    this.municipio,
    this.uf,
    this.geometria = const <LatLng>[],
    this.release,
    this.atualizadoEm,
  });

  /// Fallback universal: area aproximada, sem nome de rua nem geometria.
  factory Trecho.aproximado(LatLng ponto) {
    final hash = geohashCodificar(
      ponto.latitude,
      ponto.longitude,
      precisao: precisaoGeohashTrecho,
    );
    return Trecho(
      id: TrechoId.geohash(hash),
      centroide: ponto,
      geohash: geohashCodificar(
        ponto.latitude,
        ponto.longitude,
        precisao: precisaoGeohashConsulta,
      ),
    );
  }

  final TrechoId id;

  /// Nome da via na base de origem (nulo no fallback por geohash).
  final String? via;

  /// Classe viaria da origem (`residential`, `primary`, ...).
  final String? classe;

  final String? municipio;
  final String? uf;

  /// Vertices do trecho. Vazio no fallback (area, nao linha).
  final List<LatLng> geometria;

  final LatLng centroide;

  /// Geohash de [precisaoGeohashConsulta] do centroide, usado como indice.
  final String geohash;

  /// Release da base de origem (ex.: `2026-08-19.0` do Overture).
  final String? release;

  final DateTime? atualizadoEm;

  /// `true` quando o trecho tem identidade global de via (id GERS).
  bool get canonico => id.canonico;

  bool get temGeometria => geometria.length >= 2;

  String get rotulo => (via == null || via!.isEmpty) ? 'Via sem nome' : via!;

  /// Distancia ate o trecho: ate a linha quando ha geometria, senao ate o ponto.
  double distanciaDe(LatLng ponto) => temGeometria
      ? distanciaPontoLinhaM(ponto, geometria)
      : distanciaM(ponto, centroide);

  /// Seriaisacao neutra (usada em testes, no seed/backup e na importacao).
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id.valor,
        'via': via,
        'classe': classe,
        'municipio': municipio,
        'uf': uf,
        'geometria': geometria
            .map((p) => <double>[p.latitude, p.longitude])
            .toList(growable: false),
        'centroide': <double>[centroide.latitude, centroide.longitude],
        'geohash': geohash,
        'release': release,
        'atualizadoEm': atualizadoEm?.toUtc().toIso8601String(),
      };

  static Trecho fromMap(Map<String, dynamic> map) {
    final id = TrechoId.parse(map['id'] as String);
    final centroide = _ponto(map['centroide']);
    final geometria = <LatLng>[
      for (final vertice in (map['geometria'] as List<dynamic>? ?? const []))
        _ponto(vertice),
    ];
    final atualizado = map['atualizadoEm'];
    return Trecho(
      id: id,
      via: map['via'] as String?,
      classe: map['classe'] as String?,
      municipio: map['municipio'] as String?,
      uf: map['uf'] as String?,
      geometria: geometria,
      centroide: centroide,
      geohash: _geohashDoMapa(map, centroide),
      release: map['release'] as String?,
      atualizadoEm: atualizado is String ? DateTime.tryParse(atualizado) : null,
    );
  }

  /// Geohash de consulta gravado pela pipeline (`geohashConsulta`).
  ///
  /// `geohash` continua aceito por compatibilidade com backups/importacoes
  /// antigas; quando nenhum dos dois existe, o valor e recalculado a partir do
  /// centroide — mesma precisao, portanto o mesmo resultado da pipeline.
  static String _geohashDoMapa(Map<String, dynamic> map, LatLng centroide) {
    final bruto = map['geohashConsulta'] ?? map['geohash'];
    if (bruto is String && bruto.isNotEmpty) return bruto;
    return geohashCodificar(
      centroide.latitude,
      centroide.longitude,
      precisao: precisaoGeohashConsulta,
    );
  }

  static LatLng _ponto(Object? bruto) {
    if (bruto is Map) {
      final lat = (bruto['lat'] ?? bruto['latitude']) as num;
      final lng = (bruto['lng'] ?? bruto['longitude']) as num;
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    final lista = bruto as List<dynamic>;
    return LatLng((lista[0] as num).toDouble(), (lista[1] as num).toDouble());
  }

  @override
  String toString() => 'Trecho(${id.valor}, via: $rotulo, canonico: $canonico)';
}
